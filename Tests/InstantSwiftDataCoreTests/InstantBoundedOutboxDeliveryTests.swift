import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// Upstream delivery authority:
/// `/Users/laptop/Sync/instant-data-swift/upstream/instant/client/packages/core/src/Reactor.js`
/// at upstream commit `e71017612aed4031710a35e2fcace30d38d557ac`.
///
/// Reactor keeps pending mutations in a resident map and `_flushPendingMessages`
/// visits that map in mutation order. Swift adapts the same ordering and
/// acknowledgement rules to a durable SQLite queue, so automatic delivery must
/// first admit a fixed row window instead of rebuilding the complete map.
@Suite(.serialized)
struct InstantBoundedOutboxDeliveryTests {
  @Test
  func automaticClaimExcludesForeignRuntimeSuccessorUntilHeadIsAccepted()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let firstMutation = boundedMutation(
      index: 0,
      prefix: "atomic-claim",
      entityID: "shared-claim-entity"
    )
    try await seedBoundedOutbox(
      [firstMutation],
      cacheURL: cacheURL
    )
    let firstStore = try SQLitePersistenceStore(fileURL: cacheURL)
    let secondStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await firstStore.bootstrap()
    try await secondStore.bootstrap()

    let first = try await firstStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "runtime-a",
        claimToken: "claim-a",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 1
      )
    )
    let successor = boundedMutation(
      index: 1,
      prefix: "atomic-claim",
      entityID: "shared-claim-entity"
    )
    try await secondStore.saveOutbox([firstMutation, successor])
    let second = try await secondStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "runtime-b",
        claimToken: "claim-b",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 50
      )
    )

    expectNoDifference(first.mutations.map(\.id), ["tx-atomic-claim-00000"])
    expectNoDifference(
      second.mutations.map(\.id),
      [],
      "A foreign claimant owns the whole ordered lane, even when global count/step/byte capacity remains."
    )
    #expect(Set(first.mutations.map(\.id)).isDisjoint(with: second.mutations.map(\.id)))
    let firstClaim = try await firstStore.outboxDeliveryClaimForTesting(
      id: "tx-atomic-claim-00000"
    )
    expectNoDifference(firstClaim?.state, .claimed)
    expectNoDifference(firstClaim?.claimToken, "claim-a")
    expectNoDifference(firstClaim?.claimantID, "runtime-a")
    expectNoDifference(firstClaim?.deadlineMilliseconds, 15_000)
    expectNoDifference(firstClaim?.deliveryStarted, true)

    let revision = try await firstStore.currentOutboxRevision()
    let acceptedHead = try await firstStore.acceptOutboxMutation(
      id: "tx-atomic-claim-00000",
      serverTransactionID: "server-atomic-head",
      expectedOutboxRevision: revision
    )
    _ = try #require(acceptedHead)
    let successorClaim = try await secondStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "runtime-b",
        claimToken: "claim-b-after-head",
        now: InstantTimestamp(milliseconds: 10_001)
      )
    )
    expectNoDifference(successorClaim.mutations.map(\.id), ["tx-atomic-claim-00001"])
    try await secondStore.releaseAutomaticOutboxClaim(token: "claim-b-after-head")
    let releasedSuccessor = try await secondStore.outboxDeliveryClaimForTesting(
      id: "tx-atomic-claim-00001"
    )
    expectNoDifference(releasedSuccessor?.state, .ready)
    expectNoDifference(releasedSuccessor?.claimToken, nil)
    expectNoDifference(
      releasedSuccessor?.deliveryStarted,
      true,
      "Release makes a row retryable but never erases proof that it was offered to delivery."
    )
    await firstStore.simulateUnexpectedConnectionCloseForTesting()
    await secondStore.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func explicitFlushCannotLeapfrogAnAutomaticallyClaimedHead() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutations = (0..<2).map {
      boundedMutation(
        index: $0,
        prefix: "explicit-head-barrier",
        entityID: "one-explicit-head-entity"
      )
    }
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    let automaticStore = try SQLitePersistenceStore(fileURL: cacheURL)
    let explicitStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await automaticStore.bootstrap()
    try await explicitStore.bootstrap()
    let automatic = try await automaticStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "automatic-runtime",
        claimToken: "automatic-head-token",
        now: InstantTimestamp(milliseconds: 20_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(automatic.mutations.map(\.id), ["tx-explicit-head-barrier-00000"])

    do {
      _ = try await explicitStore.claimPendingOutboxMutationsForExplicitFlush(
        limit: 1,
        claimantID: "explicit-runtime",
        claimToken: "explicit-token",
        now: InstantTimestamp(milliseconds: 20_000)
      )
      Issue.record("Expected the explicit lane to stop at the claimed queue head.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "claim explicit outbox flush")
    }

    let revision = try await automaticStore.currentOutboxRevision()
    _ = try await automaticStore.acceptOutboxMutation(
      id: "tx-explicit-head-barrier-00000",
      serverTransactionID: "server-explicit-head",
      expectedOutboxRevision: revision
    )
    let explicit = try await explicitStore.claimPendingOutboxMutationsForExplicitFlush(
      limit: 1,
      claimantID: "explicit-runtime",
      claimToken: "explicit-token-after-head",
      now: InstantTimestamp(milliseconds: 20_001)
    )
    expectNoDifference(explicit.map(\.id), ["tx-explicit-head-barrier-00001"])
    _ = try await explicitStore.releaseAutomaticOutboxClaim(
      token: "explicit-token-after-head"
    )
  }

  @Test
  func explicitFlushStopsBeforeLocalOnlyConfirmedBarrier() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let explicitProbe = BoundedOutboxExplicitRequestProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-explicit-confirmed-barrier",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: InstantMutationTransportClient { request in
        await explicitProbe.record(request)
        return InstantMutationTransportResponse(results: [])
      },
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await runtime.persistence.saveOutbox([
      unprovenConfirmedBoundedMutation(
        index: 0,
        prefix: "explicit-confirmed-barrier"
      ),
      boundedMutation(index: 1, prefix: "explicit-confirmed-barrier"),
    ])

    let flush = try await runtime.flushPendingMutations(limit: 1)
    #expect(flush.request.mutations.isEmpty)
    let explicitRequestCount = await explicitProbe.requestCount()
    expectNoDifference(explicitRequestCount, 0)

    _ = try await runtime.connect()
    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [
      "tx-explicit-confirmed-barrier-00000",
      "tx-explicit-confirmed-barrier-00001",
    ])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func explicitFlushMarksOnlySelectedRowsBeforeTransportAndKeepsProofSticky()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let probe = BoundedOutboxExplicitFlushProbe(cacheURL: cacheURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-offer",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          try await probe.observe(request)
          return InstantMutationTransportResponse(
            results: request.mutations.map {
              InstantMutationTransportResult(
                mutationID: $0.mutationID,
                outcome: .confirmed
              )
            }
          )
        }
      )
    )
    for index in 0..<2 {
      let mutation = boundedMutation(index: index, prefix: "explicit-offer")
      _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    }

    _ = await runtime.outboxMutations()
    let firstBeforeFlush = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: "tx-explicit-offer-00000"
    )
    let secondBeforeFlush = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: "tx-explicit-offer-00001"
    )
    expectNoDifference(firstBeforeFlush, false, "Public inspection is read-only.")
    expectNoDifference(secondBeforeFlush, false, "Public inspection is read-only.")

    let result = try await runtime.flushPendingMutations(limit: 1)
    let observed = await probe.observedDeliveryStarted()
    expectNoDifference(result.request.mutations.map(\.mutationID), ["tx-explicit-offer-00000"])
    expectNoDifference(observed, [
      "tx-explicit-offer-00000": true,
      "tx-explicit-offer-00001": false,
    ])

    let firstAfterStatusRewrite = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-explicit-offer-00000")
    let secondAfterStatusRewrite = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-explicit-offer-00001")
    expectNoDifference(
      firstAfterStatusRewrite,
      true,
      "A transport-result body/status rewrite must preserve ever-offered proof."
    )
    expectNoDifference(secondAfterStatusRewrite, false, "The flush limit marks no tail rows.")
  }

  @Test
  func cancellationIgnoringExplicitTransportStaysExclusivelyFencedAfterTimeout()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let transport = BoundedOutboxSuspendedExplicitTransport()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-timeout-fence",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          await transport.send(request)
        }
      )
    )
    for index in 0..<2 {
      let mutation = boundedMutation(
        index: index,
        prefix: "explicit-timeout-fence",
        entityID: "one-explicit-timeout-entity"
      )
      _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    }

    let flush = Task { try await runtime.flushPendingMutations(limit: 1) }
    await transport.waitUntilEntered()
    do {
      _ = try await flush.value
      Issue.record("Expected the explicit mutation transport to time out at five seconds.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "flush Instant mutation transport")
      #expect(error.message.contains("5000ms"))
    }

    let competingStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await competingStore.bootstrap()
    let competingClaim = try await competingStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "competing-runtime",
        claimToken: "competing-token",
        now: InstantTimestamp(milliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
      )
    )
    expectNoDifference(
      competingClaim.mutations,
      [],
      "The retained explicit send renews its exclusive durable lane after the caller times out."
    )
    do {
      _ = try await runtime.flushPendingMutations(limit: 1)
      Issue.record("Expected a second explicit flush to reject the retained send.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "claim explicit outbox flush")
    }

    await transport.resumeServerAccepted()
    try await instantLiveWithTimeout(
      operation: "wait for fenced late explicit response disposition",
      timeoutMilliseconds: 5_000
    ) {
      while true {
        let pendingCount = try await runtime.persistence.countOutboxMutations(status: .pending)
        let headClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
          id: "tx-explicit-timeout-fence-00000"
        )
        if pendingCount == 1, headClaim?.state == .ready { break }
        await Task.yield()
      }
    }
    let successorClaim = try await competingStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "competing-runtime",
        claimToken: "competing-token-after-response",
        now: InstantTimestamp(milliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
      )
    )
    expectNoDifference(
      successorClaim.mutations.map(\.id),
      ["tx-explicit-timeout-fence-00001"]
    )
    _ = try await competingStore.releaseAutomaticOutboxClaim(
      token: "competing-token-after-response"
    )
  }

  @Test
  func staleExplicitFailureCannotFailAReclaimedMutation() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let transport = BoundedOutboxSuspendedExplicitTransport()
    let now = InstantTimestamp(milliseconds: 100_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-stale-failure",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { now },
        mutationTransport: InstantMutationTransportClient { request in
          await transport.send(request)
        }
      )
    )
    let mutation = boundedMutation(
      index: 0,
      prefix: "explicit-stale-failure",
      entityID: "explicit-stale-failure-entity"
    )
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)

    let flush = Task { try await runtime.flushPendingMutations(limit: 1) }
    await transport.waitUntilEntered()
    let competingStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await competingStore.bootstrap()
    let reclaimed = try await competingStore.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "reclaiming-runtime",
        claimToken: "reclaimed-token",
        now: InstantTimestamp(
          milliseconds: now.milliseconds
            + InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds + 1
        )
      )
    )
    expectNoDifference(reclaimed.mutations.map(\.id), [mutation.id])

    await transport.resumeFailed(message: "late permission rejection")
    let result = try await flush.value
    #expect(
      result.failed.isEmpty,
      "A transport response may dispose only the exact durable claim token it was issued."
    )
    let outboxRevision = try await competingStore.currentOutboxRevision()
    let persistedRows = try await competingStore.loadOutboxMutations(
      statuses: [.pending, .confirmed, .failed],
      ids: [mutation.id],
      limit: 1,
      expectedOutboxRevision: outboxRevision
    )
    let persisted = try #require(
      persistedRows?.first
    )
    expectNoDifference(persisted.status, .pending)
    expectNoDifference(persisted.failureMessage, nil)
    let claim = try await competingStore.outboxDeliveryClaimForTesting(id: mutation.id)
    expectNoDifference(claim?.claimToken, "reclaimed-token")
    let visible = await runtime.store.snapshot().triples
    #expect(visible.contains { $0.entityID == "explicit-stale-failure-entity" })
    _ = try await competingStore.releaseAutomaticOutboxClaim(token: "reclaimed-token")
  }

  @Test
  func validExplicitFailureAtomicallyRemovesItsOptimisticValue() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-valid-failure",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        mutationTransport: InstantMutationTransportClient { request in
          InstantMutationTransportResponse(
            results: request.mutations.map {
              InstantMutationTransportResult(
                mutationID: $0.mutationID,
                outcome: .failed,
                message: "permission rejected"
              )
            }
          )
        }
      )
    )
    let mutation = boundedMutation(
      index: 0,
      prefix: "explicit-valid-failure",
      entityID: "explicit-valid-failure-entity"
    )
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    let optimistic = await runtime.store.snapshot().triples
    #expect(optimistic.contains { $0.entityID == "explicit-valid-failure-entity" })

    let result = try await runtime.flushPendingMutations(limit: 1)
    expectNoDifference(result.failed.map(\.id), [mutation.id])
    let afterRejection = await runtime.store.snapshot().triples
    #expect(
      !afterRejection.contains { $0.entityID == "explicit-valid-failure-entity" },
      "A valid server rejection removes the rejected optimistic layer, matching Reactor."
    )
  }

  @Test
  func explicitConfirmationPreservesCurrentRebasedDurableBody() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    var original = boundedMutation(index: 0, prefix: "explicit-confirm-rebase")
    original.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-before-rebase",
      operations: [.deleteEntity("before-rebase")]
    )
    try await persistence.saveOutbox([original])
    let selected = try await persistence.claimPendingOutboxMutationsForExplicitFlush(
      limit: 1,
      claimantID: "explicit-confirm-runtime",
      claimToken: "explicit-confirm-token",
      now: InstantTimestamp(milliseconds: 50_000)
    )

    var rebased = original
    rebased.transaction = boundedMutation(
      index: 1,
      prefix: "explicit-confirm-rebased-body",
      entityID: "rebased-current-entity"
    ).transaction
    rebased.transaction.id = original.id
    rebased.rollbackTransaction = InstantStoreTransaction(
      id: "rollback-after-rebase",
      operations: [.deleteEntity("rebased-current-entity")]
    )
    try await persistence.saveOutbox([rebased])

    let confirmed = try await persistence.confirmExplicitlyFlushedOutboxMutations(
      [
        InstantMutationTransportResult(
          mutationID: original.id,
          outcome: .confirmed,
          acceptance: .serverAccepted
        )
      ],
      selectedMutations: selected,
      claimToken: "explicit-confirm-token"
    )
    expectNoDifference(confirmed.map(\.status), [.confirmed])
    let returned = try #require(confirmed.first)
    expectNoDifference(
      returned.transaction,
      rebased.transaction,
      "Explicit flush must return the full current durable transaction, not its compact lifecycle shell."
    )
    expectNoDifference(
      returned.rollbackTransaction,
      rebased.rollbackTransaction,
      "The public confirmed result must preserve the current rebased rollback body."
    )
    let revision = try await persistence.currentOutboxRevision()
    let currentRows = try await persistence.loadOutboxMutations(
      statuses: [.pending, .confirmed, .failed],
      ids: [original.id],
      limit: 1,
      expectedOutboxRevision: revision
    )
    let current = try #require(currentRows?.first)
    expectNoDifference(current.transaction, rebased.transaction)
    expectNoDifference(current.rollbackTransaction, rebased.rollbackTransaction)
    expectNoDifference(current.status, .confirmed)
  }

  @Test
  func migrationTreatsLegacyRowsAsOfferedAndNewRowsAsNeverOffered() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let legacyMutation = boundedMutation(index: 0, prefix: "migration-legacy")
    let legacyStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await legacyStore.bootstrap()
    try await legacyStore.saveOutbox([legacyMutation])
    await legacyStore.simulateUnexpectedConnectionCloseForTesting()
    try restorePreBoundedDeliveryOutboxSchema(cacheURL: cacheURL)

    let migratedStore = try SQLitePersistenceStore(fileURL: cacheURL)
    try await migratedStore.bootstrap()
    let legacyDeliveryStarted = try await migratedStore.outboxDeliveryStartedForTesting(
      id: legacyMutation.id
    )
    expectNoDifference(
      legacyDeliveryStarted,
      true,
      "Rows that predate durable offer tracking must migrate fail-closed."
    )

    let newMutation = boundedMutation(index: 1, prefix: "migration-new")
    try await migratedStore.saveOutbox([legacyMutation, newMutation])
    let preservedLegacyDeliveryStarted =
      try await migratedStore
      .outboxDeliveryStartedForTesting(id: legacyMutation.id)
    let newDeliveryStarted = try await migratedStore.outboxDeliveryStartedForTesting(
      id: newMutation.id
    )
    expectNoDifference(preservedLegacyDeliveryStarted, true, boundedOutboxSource)
    expectNoDifference(
      newDeliveryStarted,
      false,
      "Only rows inserted with durable offer tracking may begin as never offered."
    )
  }

  @Test
  func coldRelaunchTenThousandRowDeliveryDecodesOnlyFiftyAndIgnoresCorruptTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "ten-thousand") },
      cacheURL: cacheURL
    )
    try corruptBoundedOutboxBody(
      id: "tx-ten-thousand-09999",
      cacheURL: cacheURL
    )
    let residentBeforeRelaunch = InstantProcessMemory.sample()?.residentBytes
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-ten-thousand",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let residentAfterRelaunch = InstantProcessMemory.sample()?.residentBytes
    let bootstrapBodyDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let bootstrapLifecycleDecodeCount =
      await runtime.persistence.currentDecodedOutboxLifecycleCount()
    expectNoDifference(bootstrapBodyDecodeCount, 0)
    expectNoDifference(bootstrapLifecycleDecodeCount, 0)
    if let residentBeforeRelaunch, let residentAfterRelaunch {
      #expect(
        residentAfterRelaunch <= residentBeforeRelaunch + 64 * 1_024 * 1_024,
        "Cold bootstrap retained \(residentAfterRelaunch - min(residentAfterRelaunch, residentBeforeRelaunch)) extra resident bytes."
      )
    }
    let firstDeliveryStartedBeforeSelection = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-ten-thousand-00000")
    expectNoDifference(firstDeliveryStartedBeforeSelection, false, boundedOutboxSource)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for bounded ten-thousand-row delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      sentMutationIDs,
      (0..<50).map { String(format: "tx-ten-thousand-%05d", $0) },
      boundedOutboxSource
    )
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      50,
      boundedOutboxSource
    )
    let decodedBodyByteCount = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    #expect(decodedBodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    let firstDeliveryStartedAfterSelection = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-ten-thousand-00000")
    let tailDeliveryStartedAfterSelection = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-ten-thousand-09999")
    expectNoDifference(firstDeliveryStartedAfterSelection, true, boundedOutboxSource)
    expectNoDifference(tailDeliveryStartedAfterSelection, false, boundedOutboxSource)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacyAcceptedHeadsAndCorruptSentinelDoNotStarvePendingTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-legacy-heads",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    var accepted = (0..<100).map {
      acceptedBoundedMutation(index: $0, prefix: "legacy-head")
    }
    accepted.append(boundedMutation(index: 100, prefix: "legacy-tail"))
    try await runtime.persistence.saveOutbox(accepted)
    try clearBoundedDeliveryMetadata(cacheURL: cacheURL)
    try corruptBoundedOutboxBody(
      id: "tx-legacy-head-00050",
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for pending tail behind legacy accepted heads",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentMutationIDs, ["tx-legacy-tail-00100"], boundedOutboxSource)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 101)
    let maximumWindowBodyCount =
      await runtime.persistence.maximumAutomaticOutboxWindowBodyCountForTesting()
    #expect(maximumWindowBodyCount <= InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount)
    let quarantinedBody = try await runtime.persistence.quarantinedOutboxBodyForTesting(
      id: "tx-legacy-head-00050"
    )
    let hasVisibleFailure = await runtime.failedMutations().contains {
      $0.id == "tx-legacy-head-00050" && $0.status == .failed
    }
    expectNoDifference(quarantinedBody, "{malformed-json")
    #expect(hasVisibleFailure)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func inFlightRowsDoNotConsumeTheNextDurableSelectionWindow() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-in-flight",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox(
      (0..<51).map { boundedMutation(index: $0, prefix: "in-flight") }
    )

    runtime.requestLiveMutationDelivery()
    try await instantLiveWithTimeout(
      operation: "wait for initial fifty-mutation window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }
    await runtime.persistence.resetDecodedOutboxBodyCount()
    let sentWithoutFreedCapacity = await runtime.sendOutstandingMutationsToLiveSession()
    #expect(sentWithoutFreedCapacity)
    let fullWindowDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      fullWindowDecodeCount,
      0,
      "A full in-flight window must not decode any additional durable bodies."
    )
    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: "tx-in-flight-00000",
        fields: ["tx-id": .string("server-in-flight-00000")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for one freed slot to admit the unsent tail",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(52)
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentMutationIDs.last, "tx-in-flight-00050", boundedOutboxSource)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      2,
      "The acknowledgement decodes one row and the refill decodes only the one unsent row."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func sameKeySuccessorBeyondFiftyRowBoundaryPreservesOlderVisibleWrite() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-write-key-boundary",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    for index in 0..<51 {
      let mutation = boundedMutation(
        index: index,
        prefix: "write-key-boundary",
        entityID: "todo-shared-write-key"
      )
      try await runtime.transact(
        mutation.transaction,
        createdAt: mutation.createdAt
      )
    }
    await runtime.persistence.resetDecodedOutboxBodyCount()

    _ = try await runtime.connect()
    let sent = await liveSession.sentMessages().filter { $0.op == "transact" }
    expectNoDifference(sent.count, 50, boundedOutboxSource)
    let boundary = try #require(sent.last)
    expectNoDifference(boundary.clientEventID, "tx-write-key-boundary-00049")
    #expect(
      boundary.fields["tx-steps"]?.arrayValue?.isEmpty == false,
      "The older write at the admitted-window boundary must remain because a same-key successor is durably queued just beyond it."
    )
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      50,
      boundedOutboxSource
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func failedActiveOverlaySuccessorPreservesOlderAutomaticWrite() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-failed-active-successor",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let older = boundedMutation(
      index: 0,
      prefix: "failed-active-successor",
      entityID: "failed-active-shared-entity"
    )
    let newer = boundedMutation(
      index: 1,
      prefix: "failed-active-successor",
      entityID: "failed-active-shared-entity"
    )
    _ = try await runtime.transact(older.transaction, createdAt: older.createdAt)
    _ = try await runtime.transact(newer.transaction, createdAt: newer.createdAt)

    let revision = try await runtime.persistence.currentOutboxRevision()
    var durable = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        expectedOutboxRevision: revision
      )
    )
    let newerIndex = try #require(durable.firstIndex { $0.id == newer.id })
    durable[newerIndex].status = .failed
    durable[newerIndex].failureMessage = "permission denied"
    durable[newerIndex].failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    durable[newerIndex].optimisticOverlayState = .applied
    try await runtime.persistence.saveOutbox(durable)

    _ = try await runtime.connect()
    let sent = try #require(
      await liveSession.sentMessages().first {
        $0.op == "transact" && $0.clientEventID == older.id
      }
    )
    #expect(
      sent.fields["tx-steps"]?.arrayValue?.isEmpty == false,
      "A newer failed mutation whose optimistic overlay is still visible must preserve the older same-key wire write."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func corruptActiveOverlaySuccessorInsideWindowPreservesOlderAutomaticWrite()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-corrupt-active-successor",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let older = boundedMutation(
      index: 0,
      prefix: "corrupt-active-successor",
      entityID: "corrupt-active-shared-entity"
    )
    let corruptSuccessor = boundedMutation(
      index: 1,
      prefix: "corrupt-active-successor",
      entityID: "corrupt-active-shared-entity"
    )
    let validTail = boundedMutation(index: 2, prefix: "corrupt-active-successor")
    for mutation in [older, corruptSuccessor, validTail] {
      _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    }
    try corruptBoundedOutboxBody(id: corruptSuccessor.id, cacheURL: cacheURL)

    try await withKnownIssue {
      _ = try await runtime.connect()
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }

    let sentMessages = await liveSession.sentMessages().filter { $0.op == "transact" }
    expectNoDifference(sentMessages.compactMap(\.clientEventID), [older.id, validTail.id])
    let sentOlder = try #require(sentMessages.first { $0.clientEventID == older.id })
    #expect(
      sentOlder.fields["tx-steps"]?.arrayValue?.isEmpty == false,
      "Quarantining a newer active same-key overlay must not erase the older selected wire write."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func publicTransportProjectionPreservesWriteAcrossCorruptActiveSuccessor()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-public-corrupt-successor",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let older = boundedMutation(
      index: 0,
      prefix: "public-corrupt-successor",
      entityID: "public-corrupt-shared-entity"
    )
    let corruptSuccessor = boundedMutation(
      index: 1,
      prefix: "public-corrupt-successor",
      entityID: "public-corrupt-shared-entity"
    )
    _ = try await runtime.transact(older.transaction, createdAt: older.createdAt)
    _ = try await runtime.transact(
      corruptSuccessor.transaction,
      createdAt: corruptSuccessor.createdAt
    )
    try corruptBoundedOutboxBody(id: corruptSuccessor.id, cacheURL: cacheURL)

    try await withKnownIssue {
      let transport = await runtime.outboxTransportMutations()
      let projectedOlder = try #require(transport.first { $0.mutationID == older.id })
      #expect(
        !projectedOlder.txSteps.isEmpty,
        "Public inspection must return the older raw wire write when a newer visible overlay cannot be decoded."
      )
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }
  }

  @Test
  func automaticDeliveryKeepsMutationAndStepBudgets() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-step-budget",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox(
      (0..<30).map { boundedMutation(index: $0, prefix: "step-budget", stepCount: 10) }
    )

    runtime.requestLiveMutationDelivery()
    try await instantLiveWithTimeout(
      operation: "wait for weighted automatic delivery window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(26)
    }

    let sent = await liveSession.sentMessages().filter { $0.op == "transact" }
    #expect(sent.count <= 50)
    let sentStepCount = sent.reduce(into: 0) { count, message in
      count += message.fields["tx-steps"]?.arrayValue?.count ?? 0
    }
    #expect(sentStepCount <= 256, "Automatic delivery admitted \(sentStepCount) steps.")
    expectNoDifference(sent.count, 25, boundedOutboxSource)
    let lastAdmittedDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-step-budget-00024")
    let firstUnsentDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-step-budget-00025")
    let tailDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-step-budget-00029")
    expectNoDifference(lastAdmittedDeliveryStarted, true, boundedOutboxSource)
    expectNoDifference(
      firstUnsentDeliveryStarted,
      false,
      "A row stopped by the step budget has never been offered."
    )
    expectNoDifference(
      tailDeliveryStarted,
      false,
      "Rows beyond the step-budget boundary remain eligible for never-offered supersession."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func automaticDeliveryQuarantinesOverLimitStepHeadAndContinuesToTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-hard-step-limit",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox([
      boundedMutation(
        index: 0,
        prefix: "hard-step-limit",
        stepCount: InstantAutomaticOutboxClaimLimits.maximumStepCount + 1
      ),
      boundedMutation(index: 1, prefix: "hard-step-limit"),
    ])
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for tail behind an over-limit step mutation",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
    } matching: { issue in
      issue.description.contains("257 transport steps exceeds the 256-step automatic-delivery limit")
    }

    let sent = await liveSession.sentMessages().filter { $0.op == "transact" }
    expectNoDifference(sent.compactMap(\.clientEventID), ["tx-hard-step-limit-00001"])
    let maximumSentStepCount = sent.map {
      $0.fields["tx-steps"]?.arrayValue?.count ?? 0
    }.max() ?? 0
    #expect(maximumSentStepCount <= InstantAutomaticOutboxClaimLimits.maximumStepCount)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      1,
      "Normalized step metadata quarantines the 257-step head before its body is decoded."
    )
    let failed = await runtime.failedMutations()
    #expect(failed.contains { $0.id == "tx-hard-step-limit-00000" && $0.status == .failed })
    _ = try? await runtime.closeConnection()
  }

  @Test
  func newOverLimitStepMutationFailsBeforeLocalCommitAndNextWriteDelivers() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-reject-new-step-oversize",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let oversized = boundedMutation(
      index: 0,
      prefix: "reject-new-step-oversize",
      stepCount: InstantAutomaticOutboxClaimLimits.maximumStepCount + 1
    )
    do {
      _ = try await runtime.transact(oversized.transaction, createdAt: oversized.createdAt)
      Issue.record("Expected a new 257-step mutation to fail before local commit.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      #expect(error.message.contains("257 transport steps"))
    }
    let triplesAfterRejectedWrite = await runtime.store.snapshot().triples
    let outboxCountAfterRejectedWrite = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(triplesAfterRejectedWrite, [])
    expectNoDifference(outboxCountAfterRejectedWrite, 0)

    let valid = boundedMutation(index: 1, prefix: "reject-new-step-oversize")
    _ = try await runtime.transact(valid.transaction, createdAt: valid.createdAt)
    try await instantLiveWithTimeout(
      operation: "wait for valid write after rejected step-oversize write",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [valid.id])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func newOversizedBodyMutationFailsBeforeLocalCommitAndNextWriteDelivers() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-reject-new-body-oversize",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let oversized = boundedLargeMutation(
      index: 0,
      prefix: "reject-new-body-oversize",
      valueByteCount: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
    )
    do {
      _ = try await runtime.transact(oversized.transaction, createdAt: oversized.createdAt)
      Issue.record("Expected a new oversized durable mutation body to fail before local commit.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      #expect(error.message.contains("8388608-byte durable delivery limit"))
    }
    let triplesAfterRejectedWrite = await runtime.store.snapshot().triples
    let outboxCountAfterRejectedWrite = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(triplesAfterRejectedWrite, [])
    expectNoDifference(outboxCountAfterRejectedWrite, 0)

    let valid = boundedMutation(index: 1, prefix: "reject-new-body-oversize")
    _ = try await runtime.transact(valid.transaction, createdAt: valid.createdAt)
    try await instantLiveWithTimeout(
      operation: "wait for valid write after rejected body-oversize write",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [valid.id])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacySameKeyStepBlockerRemainsSuccessorProofAndNeverOffered() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-legacy-step-blocker",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox([
      boundedMutation(
        index: 0,
        prefix: "legacy-step-blocker",
        entityID: "shared-step-blocker",
        stepCount: 250
      ),
      boundedMutation(
        index: 1,
        prefix: "legacy-step-blocker",
        entityID: "shared-step-blocker",
        stepCount: 10
      ),
    ])
    try clearBoundedDeliveryMetadata(
      id: "tx-legacy-step-blocker-00001",
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()

    runtime.requestLiveMutationDelivery()
    try await instantLiveWithTimeout(
      operation: "wait for first mutation before legacy step blocker",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    let blockerDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-legacy-step-blocker-00001")
    expectNoDifference(sent.clientEventID, "tx-legacy-step-blocker-00000")
    #expect(sent.fields["tx-steps"]?.arrayValue?.isEmpty == false)
    expectNoDifference(
      blockerDeliveryStarted,
      false,
      "A decoded row stopped by the remaining step budget is normalized but not offered."
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func automaticDeliveryUsesRevisionQualifiedDurableVisibleWrites() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-shared-sqlite-visible-write",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let staleRuntime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = boundedMutation(
      index: 0,
      prefix: "shared-sqlite-visible-write",
      entityID: "shared-todo"
    )
    try await staleRuntime.persistence.saveOutbox([mutation])

    let otherRuntimePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await otherRuntimePersistence.bootstrap()
    try await otherRuntimePersistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: TodoExample.attributes,
        triples: [
          InstantTriple(
            entityID: "shared-todo",
            attributeID: "todos/text",
            value: .string("newer durable value"),
            txID: "other-runtime-server-write",
            txTime: InstantTimestamp(milliseconds: 10_000)
          )
        ]
      )
    )

    _ = try await staleRuntime.connect()
    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    expectNoDifference(sent.clientEventID, mutation.id)
    expectNoDifference(
      sent.fields["tx-steps"]?.arrayValue,
      [],
      "The selector must use the durable store revision, not the stale runtime actor."
    )
    _ = try? await staleRuntime.closeConnection()
    await otherRuntimePersistence.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func automaticDeliveryBoundsEncodedBodyBytesBeforeDecode() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-body-bytes",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox(
      (0..<3).map {
        boundedLargeMutation(index: $0, prefix: "body-bytes", valueByteCount: 5 * 1_024 * 1_024)
      }
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    runtime.requestLiveMutationDelivery()
    try await instantLiveWithTimeout(
      operation: "wait for byte-bounded automatic delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, ["tx-body-bytes-00000"])
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 1)
    let decodedBodyByteCount = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    #expect(decodedBodyByteCount <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    let secondMutationDeliveryStarted = try await runtime.persistence
      .outboxDeliveryStartedForTesting(id: "tx-body-bytes-00001")
    expectNoDifference(secondMutationDeliveryStarted, false)

    await runtime.persistence.resetDecodedOutboxBodyCount()
    let repeatedPumpCompleted = await runtime.sendOutstandingMutationsToLiveSession()
    let repeatedPumpDecodeCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let repeatedSentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    #expect(repeatedPumpCompleted)
    expectNoDifference(
      repeatedPumpDecodeCount,
      0,
      "The first 5 MiB durable claim consumes the global byte window; another pump may not decode a second 5 MiB body before ACK or release."
    )
    expectNoDifference(repeatedSentIDs, ["tx-body-bytes-00000"])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func oversizedHeadIsQuarantinedWithoutDecodeAndSmallTailStillDelivers() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-oversized-head",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox([
      boundedLargeMutation(
        index: 0,
        prefix: "oversized-head",
        valueByteCount: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
      ),
      boundedMutation(index: 1, prefix: "oversized-head"),
    ])
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for small tail behind oversized head",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
    } matching: { issue in
      issue.description.contains("exceeds the 8388608-byte automatic-delivery limit")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let decodedBodyBytes = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    let quarantinedBodyBytes = try await runtime.persistence
      .quarantinedOutboxBodyByteCountForTesting(id: "tx-oversized-head-00000")
    let failedIDs = Set(await runtime.failedMutations().map(\.id))
    expectNoDifference(sentIDs, ["tx-oversized-head-00001"])
    expectNoDifference(decodedBodyCount, 1, "Only the small tail body is decoded.")
    #expect(decodedBodyBytes <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    #expect(quarantinedBodyBytes > InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    #expect(failedIDs.contains("tx-oversized-head-00000"))
    _ = try? await runtime.closeConnection()
  }

  @Test
  func fiftyCorruptHeadsBecomeVisibleFailuresAndDoNotStarveTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-corrupt-head-window",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox(
      (0..<51).map { boundedMutation(index: $0, prefix: "corrupt-head-window") }
    )
    try corruptBoundedOutboxBodies(
      ids: (0..<50).map { String(format: "tx-corrupt-head-window-%05d", $0) },
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for tail behind corrupt delivery window",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, ["tx-corrupt-head-window-00050"])
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let failedMutationCount = await runtime.failedMutations().count
    expectNoDifference(failedMutationCount, 50)
    let quarantinedBody = try await runtime.persistence.quarantinedOutboxBodyForTesting(
      id: "tx-corrupt-head-window-00000"
    )
    expectNoDifference(quarantinedBody, "{malformed-json")
    expectNoDifference(decodedBodyCount, 51)
    let maximumWindowBodyCount =
      await runtime.persistence.maximumAutomaticOutboxWindowBodyCountForTesting()
    #expect(maximumWindowBodyCount <= InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func malformedLifecycleWithOversizedFailedBodyCannotPoisonConnectOrTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var oversizedFailure = boundedLargeMutation(
      index: 0,
      prefix: "oversized-failed-lifecycle",
      valueByteCount: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
    )
    oversizedFailure.status = .failed
    oversizedFailure.failureMessage = "could not resolve missing deployed attribute"
    oversizedFailure.failure = InstantMutationFailure(
      code: .validationFailed,
      message: oversizedFailure.failureMessage!
    )
    try await seedBoundedOutbox([
      oversizedFailure,
      boundedMutation(index: 1, prefix: "oversized-failed-lifecycle"),
    ], cacheURL: cacheURL)
    try corruptBoundedOutboxLifecycle(
      id: oversizedFailure.id,
      cacheURL: cacheURL
    )

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-oversized-failed-lifecycle",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      _ = try await runtime.connect()
      try await instantLiveWithTimeout(
        operation: "wait for pending tail after oversized failed lifecycle",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
    } matching: { issue in
      issue.description.contains("invalid lifecycle metadata")
        || issue.description.contains("exceeds the 8388608-byte automatic-delivery limit")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let decodedBodyBytes = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    let failedIDs = Set(await runtime.failedMutations().map(\.id))
    expectNoDifference(sentIDs, ["tx-oversized-failed-lifecycle-00001"])
    expectNoDifference(decodedBodyCount, 1, "Only the small pending tail body is decoded.")
    #expect(decodedBodyBytes <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    #expect(failedIDs.contains(oversizedFailure.id))
    let connectionStatus = try await runtime.connectionStatus()
    #expect(connectionStatus.state == .opened)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func mixedCorruptWindowRefillsBeforeTheValidRowsAreAcknowledged() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-mixed-corrupt-window",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    try await runtime.persistence.saveOutbox(
      (0..<51).map { boundedMutation(index: $0, prefix: "mixed-corrupt-window") }
    )
    try corruptBoundedOutboxBodies(
      ids: (0..<49).map { String(format: "tx-mixed-corrupt-window-%05d", $0) },
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()

    try await withKnownIssue {
      runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for mixed corrupt-window refill",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(3)
      }
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [
      "tx-mixed-corrupt-window-00049",
      "tx-mixed-corrupt-window-00050",
    ])
    expectNoDifference(Set(sentIDs).count, sentIDs.count)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func retryableFailedLifecycleIsNotHiddenBehindFiftyTerminalFailures() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var mutations = (0..<50).map { index -> PendingMutation in
      var mutation = boundedMutation(index: index, prefix: "retry-candidate-order")
      mutation.status = .failed
      mutation.failureMessage = "permission denied while delivering"
      mutation.failure = InstantMutationFailure(
        code: .permissionRejected,
        message: mutation.failureMessage!
      )
      return mutation
    }
    var retryable = boundedMutation(index: 50, prefix: "retry-candidate-order")
    retryable.status = .failed
    retryable.failureMessage = "could not resolve attribute after schema deployment"
    retryable.failure = InstantMutationFailure(
      code: .validationFailed,
      message: retryable.failureMessage!
    )
    mutations.append(retryable)
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()

    let candidates = try await persistence.loadFailedMutationLifecycles(limit: 50)
    expectNoDifference(candidates.map(\.id), ["tx-retry-candidate-order-00050"])
  }

  @Test
  func fiftyEncodingFailuresUseBoundedRowAddressedQuarantineAndDoNotStarveTail()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-encoding-head-window",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let invalid = (0..<50).map {
      boundedEncodingFailureMutation(index: $0, prefix: "encoding-head-window")
    }
    try await runtime.persistence.saveOutbox(
      invalid + [boundedMutation(index: 50, prefix: "encoding-head-window")]
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    try await withKnownIssue {
      runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for tail behind encoding-failure window",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
    } matching: { issue in
      issue.description.contains("quarantined")
        || issue.description.contains("missing-bounded-attribute")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, ["tx-encoding-head-window-00050"])
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let failedMutationCount = await runtime.failedMutations().count
    expectNoDifference(failedMutationCount, 50)
    let maximumWindowBodyCount =
      await runtime.persistence.maximumAutomaticOutboxWindowBodyCountForTesting()
    #expect(decodedBodyCount <= 101)
    #expect(maximumWindowBodyCount <= InstantAutomaticOutboxClaimLimits.maximumBodyDecodeCount)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func mixedEncodingFailureWindowRefillsWithoutAnAcknowledgement() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    let runtime = try await connectedRuntime(
      appID: "bounded-outbox-mixed-encoding-window",
      cacheURL: cacheURL,
      liveSession: liveSession
    )
    let mutations = (0..<49).map {
      boundedEncodingFailureMutation(index: $0, prefix: "mixed-encoding-window")
    } + [
      boundedMutation(index: 49, prefix: "mixed-encoding-window"),
      boundedMutation(index: 50, prefix: "mixed-encoding-window"),
    ]
    try await runtime.persistence.saveOutbox(mutations)

    try await withKnownIssue {
      runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for mixed encoding-window refill",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(3)
      }
    } matching: { issue in
      issue.description.contains("quarantined")
        || issue.description.contains("missing-bounded-attribute")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [
      "tx-mixed-encoding-window-00049",
      "tx-mixed-encoding-window-00050",
    ])
    expectNoDifference(Set(sentIDs).count, sentIDs.count)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacyConfirmedUnprovenRowsRemainOrderedAheadOfPendingTail() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutations = (0..<100).map {
      unprovenConfirmedBoundedMutation(index: $0, prefix: "legacy-order")
    } + [boundedMutation(index: 100, prefix: "legacy-order")]
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    try restorePreBoundedDeliveryOutboxSchema(cacheURL: cacheURL)

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-legacy-order",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for first strict legacy claim window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(
      sentIDs,
      (0..<50).map { String(format: "tx-legacy-order-%05d", $0) },
      "Legacy confirmed rows with no server proof are ordered delivery barriers; the pending tail may not leapfrog them."
    )
    #expect(!sentIDs.contains("tx-legacy-order-00100"))
    _ = try? await runtime.closeConnection()
  }

  @Test
  func durableFiveSecondDeadlineSelfWakesAndRetriesWithoutExternalEvent() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      [boundedMutation(index: 0, prefix: "deadline-retry")],
      cacheURL: cacheURL
    )
    let clock = BoundedOutboxLockedClock(milliseconds: 100_000)
    let deadlineSleep = BoundedOutboxControlledSleep()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-deadline-retry",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { clock.now() },
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveReconnectSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await withKnownIssue {
      _ = try await runtime.connect()
      await liveSession.waitForSentMessageCount(2)
      await deadlineSleep.waitForFirstDelay()
      let firstDelay = await deadlineSleep.firstDelay()
      expectNoDifference(firstDelay, 5_000)
      clock.advance(by: 5_000)
      await deadlineSleep.resumeFirstDelay()
      try await instantLiveWithTimeout(
        operation: "wait for deadline-driven mutation retry",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(3)
      }
    } matching: { issue in
      issue.description.contains("did not acknowledge")
    }

    let sentIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(sentIDs, [
      "tx-deadline-retry-00000",
      "tx-deadline-retry-00000",
    ])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func sameProcessOfflineTenThousandEnqueuesKeepResidentBarrierCacheBounded()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-same-process-ten-thousand",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    for index in 0..<10_000 {
      let mutation = boundedMutation(
        index: index,
        prefix: "same-process-ten-thousand",
        entityID: "one-hot-offline-entity"
      )
      _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)
    }

    let durableMutationCount = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(durableMutationCount, 10_000)
    let residentBarrierCount = await runtime.mutationDeliveryBarrierMutations().count
    #expect(
      residentBarrierCount <= InstantAutomaticOutboxClaimLimits.maximumMutationCount,
      "SQLite owns the queue; the runtime keeps only its bounded active claim/barrier set."
    )
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(
      queueWideReadCount,
      0,
      "Appending one local mutation must not scan or rebuild the durable queue."
    )
  }

  @Test
  func publicTenThousandRowTransportInspectionDoesNotPopulateDeliveryBarrier()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "inspection-ten-thousand") },
      cacheURL: cacheURL
    )
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-inspection-ten-thousand",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let mutations = await runtime.outboxTransportMutations()
    expectNoDifference(mutations.count, 10_000)
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
    let firstDeliveryStarted = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: "tx-inspection-ten-thousand-00000"
    )
    expectNoDifference(
      firstDeliveryStarted,
      false,
      "Explicit inspection neither claims nor marks a mutation as offered."
    )
  }

  @Test
  func coldTenThousandRowInspectionQuarantinesCorruptTailWithoutReturningPartialQueue()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "inspection-corrupt-tail") },
      cacheURL: cacheURL
    )
    try corruptBoundedOutboxBody(
      id: "tx-inspection-corrupt-tail-09999",
      cacheURL: cacheURL
    )
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-inspection-corrupt-tail",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await runtime.persistence.resetDecodedOutboxBodyCount()

    var mutations: [PendingMutation] = []
    await withKnownIssue {
      mutations = await runtime.outboxMutations()
    } matching: { issue in
      issue.description.contains("quarantined corrupt durable mutation")
    }
    expectNoDifference(
      mutations.count,
      10_000,
      "A corrupt tail becomes one visible failed shell; it must not collapse a complete durable inspection to an empty resident fallback."
    )
    let tail = try #require(mutations.last)
    expectNoDifference(tail.id, "tx-inspection-corrupt-tail-09999")
    expectNoDifference(tail.status, .failed)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 10_000)
    let quarantinedByteCount = try await runtime.persistence
      .quarantinedOutboxBodyByteCountForTesting(id: tail.id)
    #expect(quarantinedByteCount > 0)
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
  }

  @Test
  func limitedExplicitFlushOfTenThousandRowsDecodesAndDisposesOnlySelectedBody()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map { boundedMutation(index: $0, prefix: "flush-ten-thousand") },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-flush-ten-thousand",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations(limit: 1)
    expectNoDifference(result.request.mutations.map(\.mutationID), [
      "tx-flush-ten-thousand-00000"
    ])
    expectNoDifference(result.pendingMutationCount, 9_999)
    expectNoDifference(result.mutationCount, 10_000)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      2,
      "Explicit flush decodes only the selected row for transport and its current post-I/O body for the public result; it never hydrates the queue."
    )
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
  }
}

private func connectedRuntime(
  appID: String,
  cacheURL: URL,
  liveSession: LiveReactorParitySession
) async throws -> InstantRuntime {
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: cacheURL,
    initialAttributes: TodoExample.attributes,
    liveTransport: liveSession.transport
  )
  configuration.autoConnectLiveTransport = false
  let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
  _ = try await runtime.connect()
  let sentOps = await liveSession.sentMessages().map(\.op)
  expectNoDifference(
    sentOps,
    ["init"],
    boundedOutboxSource
  )
  return runtime
}

private func boundedMutation(
  index: Int,
  prefix: String,
  entityID: String? = nil,
  stepCount: Int = 1
) -> PendingMutation {
  let id = String(format: "tx-%@-%05d", prefix, index)
  let createdAt = InstantTimestamp(milliseconds: Int64(index + 1))
  let operations = (0..<stepCount).map { step in
    InstantTripleOperation.insert(
      InstantTriple(
        entityID: entityID ?? "todo-\(prefix)-\(index)-\(step)",
        attributeID: "todos/text",
        value: .string("value-\(index)-\(step)"),
        txID: id,
        txTime: createdAt
      )
    )
  }
  return PendingMutation(
    id: id,
    createdAt: createdAt,
    transaction: InstantStoreTransaction(id: id, operations: operations)
  )
}

private func acceptedBoundedMutation(index: Int, prefix: String) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  mutation.status = .confirmed
  mutation.serverTransactionID = "server-\(mutation.id)"
  mutation.confirmationSource = nil
  return mutation
}

private func unprovenConfirmedBoundedMutation(index: Int, prefix: String) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  mutation.status = .confirmed
  mutation.serverTransactionID = nil
  mutation.confirmationSource = .localTransport
  return mutation
}

private func boundedEncodingFailureMutation(index: Int, prefix: String) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  guard case let .insert(originalTriple)? = mutation.transaction.operations.first else {
    return mutation
  }
  var triple = originalTriple
  triple.attributeID = "missing-bounded-attribute"
  mutation.transaction.operations = [.insert(triple)]
  return mutation
}

private func boundedLargeMutation(
  index: Int,
  prefix: String,
  valueByteCount: Int
) -> PendingMutation {
  var mutation = boundedMutation(index: index, prefix: prefix)
  let id = mutation.id
  mutation.transaction.operations = [
    .insert(
      InstantTriple(
        entityID: "todo-\(prefix)-\(index)",
        attributeID: "todos/text",
        value: .string(String(repeating: "x", count: valueByteCount)),
        txID: id,
        txTime: mutation.createdAt
      )
    )
  ]
  return mutation
}

private func temporaryBoundedOutboxCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantBoundedOutboxDeliveryTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func seedBoundedOutbox(
  _ mutations: [PendingMutation],
  cacheURL: URL
) async throws {
  let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
  try await persistence.bootstrap()
  try await persistence.saveOutbox(mutations)
  await persistence.simulateUnexpectedConnectionCloseForTesting()
}

private func clearBoundedDeliveryMetadata(cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    UPDATE instant_outbox
    SET delivery_state = NULL, delivery_metadata_version = 0;
    DELETE FROM instant_outbox_write_keys;
    """,
    cacheURL: cacheURL
  )
}

private func clearBoundedDeliveryMetadata(id: String, cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    UPDATE instant_outbox
    SET delivery_state = NULL, delivery_metadata_version = 0,
        transport_step_count = NULL, encoded_body_bytes = NULL
    WHERE mutation_id = '\(id)';
    DELETE FROM instant_outbox_write_keys WHERE mutation_id = '\(id)';
    """,
    cacheURL: cacheURL
  )
}

private func restorePreBoundedDeliveryOutboxSchema(cacheURL: URL) throws {
  try executeBoundedOutboxSQL(
    """
    PRAGMA foreign_keys = OFF;
    DROP TABLE instant_outbox_write_keys;
    CREATE TABLE instant_outbox_pre_0012 (
      mutation_id TEXT PRIMARY KEY NOT NULL,
      status TEXT NOT NULL,
      created_at_ms INTEGER NOT NULL,
      json TEXT NOT NULL
    );
    INSERT INTO instant_outbox_pre_0012 (mutation_id, status, created_at_ms, json)
    SELECT mutation_id, status, created_at_ms, json
    FROM instant_outbox;
    DROP TABLE instant_outbox;
    ALTER TABLE instant_outbox_pre_0012 RENAME TO instant_outbox;
    DELETE FROM instant_schema_migrations
    WHERE name = '0012_bounded_outbox_delivery';
    PRAGMA foreign_keys = ON;
    """,
    cacheURL: cacheURL
  )
}

private func corruptBoundedOutboxBody(id: String, cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open fault-injection database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "UPDATE instant_outbox SET json = '{malformed-json' WHERE mutation_id = ?",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare body corruption")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
    throw boundedOutboxSQLiteError(database, operation: "corrupt outbox body")
  }
}

private func corruptBoundedOutboxBodies(ids: [String], cacheURL: URL) throws {
  for id in ids {
    try corruptBoundedOutboxBody(id: id, cacheURL: cacheURL)
  }
}

private func corruptBoundedOutboxLifecycle(id: String, cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open lifecycle fault database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "UPDATE instant_outbox SET lifecycle_json = '{malformed-lifecycle' WHERE mutation_id = ?",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare lifecycle corruption")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else {
    throw boundedOutboxSQLiteError(database, operation: "corrupt outbox lifecycle")
  }
}

private final class BoundedOutboxLockedClock: @unchecked Sendable {
  private let lock = NSLock()
  private var milliseconds: Int64

  init(milliseconds: Int64) {
    self.milliseconds = milliseconds
  }

  func now() -> InstantTimestamp {
    lock.withLock { InstantTimestamp(milliseconds: milliseconds) }
  }

  func advance(by delta: Int64) {
    lock.withLock { milliseconds += delta }
  }
}

private actor BoundedOutboxControlledSleep {
  private var recordedFirstDelay: UInt64?
  private var firstDelayContinuation: CheckedContinuation<Void, Error>?
  private var delayWaiters: [CheckedContinuation<Void, Never>] = []

  func sleep(milliseconds: UInt64) async throws {
    guard recordedFirstDelay == nil else { throw CancellationError() }
    recordedFirstDelay = milliseconds
    for waiter in delayWaiters { waiter.resume() }
    delayWaiters.removeAll()
    try await withCheckedThrowingContinuation { continuation in
      firstDelayContinuation = continuation
    }
  }

  func waitForFirstDelay() async {
    guard recordedFirstDelay == nil else { return }
    await withCheckedContinuation { continuation in
      delayWaiters.append(continuation)
    }
  }

  func firstDelay() -> UInt64? {
    recordedFirstDelay
  }

  func resumeFirstDelay() {
    firstDelayContinuation?.resume()
    firstDelayContinuation = nil
  }
}

private actor BoundedOutboxExplicitFlushProbe {
  private let cacheURL: URL
  private var observed: [String: Bool] = [:]

  init(cacheURL: URL) {
    self.cacheURL = cacheURL
  }

  func observe(_ request: InstantMutationTransportRequest) throws {
    for id in ["tx-explicit-offer-00000", "tx-explicit-offer-00001"] {
      observed[id] = try boundedOutboxDeliveryStarted(id: id, cacheURL: cacheURL)
    }
    #expect(request.mutations.map(\.mutationID) == ["tx-explicit-offer-00000"])
  }

  func observedDeliveryStarted() -> [String: Bool] {
    observed
  }
}

private actor BoundedOutboxExplicitRequestProbe {
  private var requests: [InstantMutationTransportRequest] = []

  func record(_ request: InstantMutationTransportRequest) {
    requests.append(request)
  }

  func requestCount() -> Int {
    requests.count
  }
}

private actor BoundedOutboxSuspendedExplicitTransport {
  private var request: InstantMutationTransportRequest?
  private var responseContinuation:
    CheckedContinuation<InstantMutationTransportResponse, Never>?
  private var entryWaiters: [CheckedContinuation<Void, Never>] = []

  func send(_ request: InstantMutationTransportRequest) async
    -> InstantMutationTransportResponse
  {
    self.request = request
    for waiter in entryWaiters { waiter.resume() }
    entryWaiters.removeAll()
    // A checked continuation intentionally ignores Task cancellation. This
    // pins the runtime's hard-timeout + durable-renewal fence rather than the
    // cooperative behavior of Task.sleep.
    return await withCheckedContinuation { continuation in
      responseContinuation = continuation
    }
  }

  func waitUntilEntered() async {
    guard request == nil else { return }
    await withCheckedContinuation { continuation in
      entryWaiters.append(continuation)
    }
  }

  func resumeServerAccepted() {
    guard let request, let responseContinuation else { return }
    responseContinuation.resume(returning: InstantMutationTransportResponse(
      results: request.mutations.map {
        InstantMutationTransportResult(
          mutationID: $0.mutationID,
          outcome: .confirmed,
          acceptance: .serverAccepted
        )
      }
    ))
    self.responseContinuation = nil
  }

  func resumeFailed(message: String) {
    guard let request, let responseContinuation else { return }
    responseContinuation.resume(returning: InstantMutationTransportResponse(
      results: request.mutations.map {
        InstantMutationTransportResult(
          mutationID: $0.mutationID,
          outcome: .failed,
          message: message
        )
      }
    ))
    self.responseContinuation = nil
  }
}

private func boundedOutboxDeliveryStarted(id: String, cacheURL: URL) throws -> Bool {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open explicit-flush probe database")
  }
  defer { sqlite3_close(database) }
  var statement: OpaquePointer?
  guard
    sqlite3_prepare_v2(
      database,
      "SELECT delivery_started FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      -1,
      &statement,
      nil
    ) == SQLITE_OK
  else {
    throw boundedOutboxSQLiteError(database, operation: "prepare explicit-flush probe")
  }
  defer { sqlite3_finalize(statement) }
  let bindResult = id.withCString {
    sqlite3_bind_text(statement, 1, $0, -1, boundedOutboxSQLiteTransient)
  }
  guard bindResult == SQLITE_OK, sqlite3_step(statement) == SQLITE_ROW else {
    throw boundedOutboxSQLiteError(database, operation: "read explicit-flush offer marker")
  }
  return sqlite3_column_int64(statement, 0) != 0
}

private func executeBoundedOutboxSQL(_ sql: String, cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw boundedOutboxSQLiteError(database, operation: "open metadata database")
  }
  defer { sqlite3_close(database) }
  guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
    throw boundedOutboxSQLiteError(database, operation: "clear delivery metadata")
  }
}

private func boundedOutboxSQLiteError(
  _ database: OpaquePointer?,
  operation: String
) -> NSError {
  NSError(
    domain: "InstantBoundedOutboxDeliveryTests",
    code: 1,
    userInfo: [
      NSLocalizedDescriptionKey: database.map { String(cString: sqlite3_errmsg($0)) }
        ?? "Could not \(operation)."
    ]
  )
}

private let boundedOutboxSQLiteTransient = unsafeBitCast(
  -1,
  to: sqlite3_destructor_type.self
)

private let boundedOutboxSource =
  "upstream Reactor.js pending-mutation order adapted to a fixed durable SQLite delivery window"
