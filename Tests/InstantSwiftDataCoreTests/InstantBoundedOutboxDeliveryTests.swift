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
    let acceptedHeadClaim = try #require(
      try await firstStore.outboxDeliveryClaimForTesting(id: "tx-atomic-claim-00000")
    )
    expectNoDifference(acceptedHeadClaim.state, .ready)
    expectNoDifference(acceptedHeadClaim.projectedBodyByteCount, nil)
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
    expectNoDifference(releasedSuccessor?.projectedBodyByteCount, nil)
    expectNoDifference(
      releasedSuccessor?.deliveryStarted,
      true,
      "Release makes a row retryable but never erases proof that it was offered to delivery."
    )
    await firstStore.simulateUnexpectedConnectionCloseForTesting()
    await secondStore.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func legacyClaimWithoutProjectedBytesBlocksRefillUntilReleased() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutations = (0..<2).map {
      boundedMutation(index: $0, prefix: "legacy-projected-byte-claim")
    }
    try await seedBoundedOutbox(mutations, cacheURL: cacheURL)
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()

    let firstWindow = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "legacy-projected-byte-runtime",
        claimToken: "legacy-projected-byte-token",
        now: InstantTimestamp(milliseconds: 10_000),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(firstWindow.mutations.map(\.id), [mutations[0].id])
    try executeBoundedOutboxSQL(
      """
      UPDATE instant_outbox
      SET delivery_claim_projected_body_bytes = NULL
      WHERE mutation_id = '\(mutations[0].id)';
      """,
      cacheURL: cacheURL
    )

    let blockedWindow = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "legacy-projected-byte-runtime",
        claimToken: "blocked-refill-token",
        now: InstantTimestamp(milliseconds: 10_001)
      )
    )
    expectNoDifference(blockedWindow.mutations.map(\.id), [])
    let blockedTail = try #require(
      try await store.outboxDeliveryClaimForTesting(id: mutations[1].id)
    )
    expectNoDifference(blockedTail.state, .ready)
    expectNoDifference(blockedTail.claimToken, nil)
    expectNoDifference(blockedTail.projectedBodyByteCount, nil)
    expectNoDifference(blockedTail.deliveryStarted, false)

    _ = try await store.releaseAutomaticOutboxClaim(token: "legacy-projected-byte-token")
    let releasedHead = try #require(
      try await store.outboxDeliveryClaimForTesting(id: mutations[0].id)
    )
    expectNoDifference(releasedHead.state, .ready)
    expectNoDifference(releasedHead.projectedBodyByteCount, nil)
    let revision = try await store.currentOutboxRevision()
    _ = try #require(
      try await store.acceptOutboxMutation(
        id: mutations[0].id,
        serverTransactionID: "server-legacy-projected-byte-head",
        expectedOutboxRevision: revision
      )
    )
    let tailWindow = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "legacy-projected-byte-runtime",
        claimToken: "tail-after-legacy-release-token",
        now: InstantTimestamp(milliseconds: 10_002)
      )
    )
    expectNoDifference(tailWindow.mutations.map(\.id), [mutations[1].id])
    _ = try await store.releaseAutomaticOutboxClaim(token: "tail-after-legacy-release-token")
    await store.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func expiredClaimClearsProjectedByteReservationBeforeRefill() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let mutation = boundedMutation(index: 0, prefix: "expired-projected-byte-claim")
    try await seedBoundedOutbox([mutation], cacheURL: cacheURL)
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()

    let claim = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "expired-projected-byte-runtime",
        claimToken: "expired-projected-byte-token",
        now: InstantTimestamp(milliseconds: 10_000)
      )
    )
    expectNoDifference(claim.mutations.map(\.id), [mutation.id])
    #expect(
      try await store.outboxDeliveryClaimForTesting(id: mutation.id)?
        .projectedBodyByteCount != nil
    )

    let reclaimed = try await store.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: "expired-projected-byte-runtime",
        claimToken: "no-refill-token",
        now: InstantTimestamp(
          milliseconds: 10_000
            + InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds
        ),
        maximumMutationCount: 0
      )
    )
    expectNoDifference(reclaimed.reclaimedMutationIDs, [mutation.id])
    expectNoDifference(reclaimed.mutations.map(\.id), [])
    let expiredClaim = try #require(
      try await store.outboxDeliveryClaimForTesting(id: mutation.id)
    )
    expectNoDifference(expiredClaim.state, .ready)
    expectNoDifference(expiredClaim.claimToken, nil)
    expectNoDifference(expiredClaim.projectedBodyByteCount, nil)
    await store.simulateUnexpectedConnectionCloseForTesting()
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
    try await instantLiveWithTimeout(
      operation: "wait for automatic delivery behind the explicit confirmed barrier",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }
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
  func explicitFlushTimeoutAbortsAndExactlyJoinsCancellationIgnoringOperationAndRenewal()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let transport = BoundedOutboxCancellationIgnoringPreparedTransport()
    let deadlineSleep = BoundedOutboxCancellationIgnoringSleep()
    let renewalSleep = BoundedOutboxCancellationIgnoringSleep()
    let completion = BoundedOutboxCompletionProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-explicit-timeout-exact-cleanup",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: .preparedOperations { request in
        transport.operation(for: request)
      }
    )
    configuration.explicitMutationTransportDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    configuration.explicitMutationClaimRenewalSleep = { milliseconds in
      try await renewalSleep.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = boundedMutation(
      index: 0,
      prefix: "explicit-timeout-exact-cleanup",
      entityID: "one-explicit-timeout-entity"
    )
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)

    let flush = Task {
      defer { completion.record() }
      return try await runtime.flushPendingMutations(limit: 1)
    }
    defer {
      flush.cancel()
      transport.releaseWithServerAcceptance()
      deadlineSleep.release()
      renewalSleep.release()
    }
    try await instantLiveWithTimeout(
      operation: "wait for the prepared explicit mutation operation and its owned timers",
      timeoutMilliseconds: 5_000
    ) {
      while !transport.didEnter || !deadlineSleep.didEnter || !renewalSleep.didEnter {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(transport.mutationIDs, [mutation.id])
    expectNoDifference(
      deadlineSleep.requestedMilliseconds,
      UInt64(InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds)
    )

    deadlineSleep.release()
    try await instantLiveWithTimeout(
      operation: "wait for explicit mutation timeout to abort transport work",
      timeoutMilliseconds: 5_000
    ) {
      while transport.abortCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(
      renewalSleep.cancellationCount,
      0,
      "The durable claim keeps renewing until the exact late response is dispositioned."
    )
    expectNoDifference(
      deadlineSleep.cancellationCount,
      0,
      "The five-second deadline wins naturally; it is not modeled as caller cancellation."
    )
    expectNoDifference(completion.didComplete, false)
    #expect(!(await runtime.exactCloseBackgroundTasksAreIdleForTesting()))

    transport.releaseWithServerAcceptance()
    try await instantLiveWithTimeout(
      operation: "wait for cancellation-ignoring explicit transport to return",
      timeoutMilliseconds: 5_000
    ) {
      while transport.runCompletionCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    try await instantLiveWithTimeout(
      operation: "wait for late authoritative acceptance disposition before timeout returns",
      timeoutMilliseconds: 5_000
    ) {
      while try await runtime.persistence.countOutboxMutations(status: .confirmed) != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(
      completion.didComplete,
      false,
      "A timeout cannot return while the exact renewal tail still owns the flush graph."
    )
    let outboxRevisionAfterDisposition = try await runtime.persistence.currentOutboxRevision()
    let persistedAfterDisposition = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [mutation.id],
        limit: 1,
        expectedOutboxRevision: outboxRevisionAfterDisposition
      )?.first
    )
    expectNoDifference(persistedAfterDisposition.status, .confirmed)
    expectNoDifference(persistedAfterDisposition.confirmationSource, .serverTransport)
    #expect(persistedAfterDisposition.provesServerAcceptance)
    try await instantLiveWithTimeout(
      operation: "wait for renewal cancellation after authoritative timeout disposition",
      timeoutMilliseconds: 5_000
    ) {
      while renewalSleep.cancellationCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(completion.didComplete, false)

    renewalSleep.release()
    do {
      _ = try await instantLiveWithTimeout(
        operation: "wait for explicit timeout to join all exact owned work",
        timeoutMilliseconds: 5_000
      ) {
        try await flush.value
      }
      Issue.record("Expected the explicit mutation transport to time out at five seconds.")
    } catch let error as InstantError {
      expectNoDifference(error.operation, "flush Instant mutation transport")
      #expect(error.message.contains("5000ms"))
    }

    expectNoDifference(completion.didComplete, true)
    expectNoDifference(transport.abortCount, 1, "Prepared-operation abort is idempotent.")
    #expect(await runtime.exactCloseBackgroundTasksAreIdleForTesting())
    let pendingCount = try await runtime.persistence.countOutboxMutations(status: .pending)
    expectNoDifference(pendingCount, 0)
    let confirmedCount = try await runtime.persistence.countOutboxMutations(status: .confirmed)
    expectNoDifference(confirmedCount, 1)
    let outboxRevisionAfterTimeoutReturn = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      outboxRevisionAfterTimeoutReturn,
      outboxRevisionAfterDisposition,
      "The timeout error returns only after authoritative acceptance is durably complete."
    )
  }

  @Test
  func closeConnectionAbortsAndExactlyJoinsActiveExplicitFlushBeforeReturning()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let transport = BoundedOutboxCancellationIgnoringPreparedTransport()
    let deadlineSleep = BoundedOutboxCancellationIgnoringSleep()
    let renewalSleep = BoundedOutboxCancellationIgnoringSleep()
    let flushCompletion = BoundedOutboxCompletionProbe()
    let closeCompletion = BoundedOutboxCompletionProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-explicit-close-exact-cleanup",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      mutationTransport: .preparedOperations { request in
        transport.operation(for: request)
      }
    )
    configuration.explicitMutationTransportDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    configuration.explicitMutationClaimRenewalSleep = { milliseconds in
      try await renewalSleep.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = boundedMutation(index: 0, prefix: "explicit-close-exact-cleanup")
    _ = try await runtime.transact(mutation.transaction, createdAt: mutation.createdAt)

    let flush = Task {
      defer { flushCompletion.record() }
      return try await runtime.flushPendingMutations(limit: 1)
    }
    defer {
      flush.cancel()
      transport.releaseWithServerAcceptance()
      deadlineSleep.release()
      renewalSleep.release()
    }
    try await instantLiveWithTimeout(
      operation: "wait for active explicit flush before close",
      timeoutMilliseconds: 5_000
    ) {
      while !transport.didEnter || !deadlineSleep.didEnter || !renewalSleep.didEnter {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(transport.mutationIDs, [mutation.id])
    let close = Task {
      let status = try await runtime.closeConnection()
      closeCompletion.record()
      return status
    }
    defer { close.cancel() }
    try await instantLiveWithTimeout(
      operation: "wait for close to abort explicit transport and deadline work",
      timeoutMilliseconds: 5_000
    ) {
      while transport.abortCount != 1
        || deadlineSleep.cancellationCount != 1
      {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(
      renewalSleep.cancellationCount,
      0,
      "Close keeps the durable claim renewed until the exact late response is dispositioned."
    )
    let stateWhileAuthoritativeResponseIsPending = try await runtime.connectionStatus().state
    #expect(stateWhileAuthoritativeResponseIsPending != .closed)
    expectNoDifference(closeCompletion.didComplete, false)
    expectNoDifference(flushCompletion.didComplete, false)
    #expect(!(await runtime.exactCloseBackgroundTasksAreIdleForTesting()))

    transport.releaseWithServerAcceptance()
    try await instantLiveWithTimeout(
      operation: "wait for aborted explicit transport tail",
      timeoutMilliseconds: 5_000
    ) {
      while transport.runCompletionCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    try await instantLiveWithTimeout(
      operation: "wait for authoritative acceptance disposition before close publishes closed",
      timeoutMilliseconds: 5_000
    ) {
      while try await runtime.persistence.countOutboxMutations(status: .confirmed) != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(closeCompletion.didComplete, false)
    expectNoDifference(flushCompletion.didComplete, false)
    let stateAfterDispositionBeforeCleanupJoin = try await runtime.connectionStatus().state
    #expect(stateAfterDispositionBeforeCleanupJoin != .closed)
    let outboxRevisionAfterDisposition = try await runtime.persistence.currentOutboxRevision()
    let persistedAfterDisposition = try #require(
      try await runtime.persistence.loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        ids: [mutation.id],
        limit: 1,
        expectedOutboxRevision: outboxRevisionAfterDisposition
      )?.first
    )
    expectNoDifference(persistedAfterDisposition.status, .confirmed)
    expectNoDifference(persistedAfterDisposition.confirmationSource, .serverTransport)
    #expect(persistedAfterDisposition.provesServerAcceptance)
    try await instantLiveWithTimeout(
      operation: "wait for renewal cancellation after authoritative close disposition",
      timeoutMilliseconds: 5_000
    ) {
      while renewalSleep.cancellationCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(closeCompletion.didComplete, false)
    expectNoDifference(flushCompletion.didComplete, false)

    deadlineSleep.release()
    renewalSleep.release()
    let closedStatus = try await instantLiveWithTimeout(
      operation: "wait for close to join active explicit flush",
      timeoutMilliseconds: 5_000
    ) {
      try await close.value
    }
    expectNoDifference(closedStatus.state, .closed)
    expectNoDifference(closeCompletion.didComplete, true)
    #expect(await runtime.exactCloseBackgroundTasksAreIdleForTesting())
    let pendingCountAtCloseReturn = try await runtime.persistence.countOutboxMutations(
      status: .pending
    )
    expectNoDifference(pendingCountAtCloseReturn, 0)
    let confirmedCountAtCloseReturn = try await runtime.persistence.countOutboxMutations(
      status: .confirmed
    )
    expectNoDifference(confirmedCountAtCloseReturn, 1)
    let outboxRevisionAtCloseReturn = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      outboxRevisionAtCloseReturn,
      outboxRevisionAfterDisposition,
      "Close publishes closed only after the exact accepted response is durable."
    )

    do {
      _ = try await instantLiveWithTimeout(
        operation: "wait for close-cancelled explicit flush caller",
        timeoutMilliseconds: 5_000
      ) {
        try await flush.value
      }
    } catch {}

    expectNoDifference(flushCompletion.didComplete, true)
    expectNoDifference(transport.abortCount, 1, "Close abort is idempotent.")
    #expect(await runtime.exactCloseBackgroundTasksAreIdleForTesting())
    let outboxRevisionAfterFlushCaller = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(
      outboxRevisionAfterFlushCaller,
      outboxRevisionAtCloseReturn,
      "No explicit-flush disposition may write after close returns."
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
    let runtime = try await disconnectedRuntime(
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
      _ = try await runtime.connect()
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

    await runtime.requestLiveMutationDelivery()
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
    try await instantLiveWithTimeout(
      operation: "wait for the fifty-mutation same-key boundary window",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(51)
    }
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
    try await instantLiveWithTimeout(
      operation: "wait for the older write protected by a failed active overlay",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
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
      try await instantLiveWithTimeout(
        operation: "wait for delivery after quarantining the corrupt active overlay",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(3)
      }
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

    await runtime.requestLiveMutationDelivery()
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
    let runtime = try await disconnectedRuntime(
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
      _ = try await runtime.connect()
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
    let runtime = try await disconnectedRuntime(
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

    _ = try await runtime.connect()
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
  func automaticDeliveryHydratesRequiredFoundationAndFiltersOptionalStaleWrite()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let mutation = requiredFoundationMutation(
      id: "tx-required-foundation-older",
      entityID: "segment-required-foundation",
      text: "older text must not overwrite the visible value",
      optionalPreview: "older preview must be filtered",
      recordingID: "recording-required-foundation",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    try await runtime.persistence.saveOutbox([mutation])

    let visibleAt = InstantTimestamp(milliseconds: 200)
    let otherRuntimePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await otherRuntimePersistence.bootstrap()
    try await otherRuntimePersistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/id",
            value: .string("segment-required-foundation"),
            transactionID: mutation.id,
            timestamp: mutation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/recording",
            value: .ref("recording-required-foundation"),
            transactionID: mutation.id,
            timestamp: mutation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/text",
            value: .string("newest materialized text"),
            transactionID: "newer-visible-write",
            timestamp: visibleAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation",
            attributeID: "transcriptionSegments/searchPreview",
            value: .string("newest optional preview"),
            transactionID: "newer-visible-write",
            timestamp: visibleAt
          ),
        ]
      )
    )

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for schema-complete required-foundation delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    let valuesByAttributeID = boundedOutboxAddTripleValues(in: sent)

    expectNoDifference(sent.clientEventID, mutation.id)
    expectNoDifference(
      valuesByAttributeID,
      [
        "transcriptionSegments/id": .string("segment-required-foundation"),
        "transcriptionSegments/recording": .string("recording-required-foundation"),
        "transcriptionSegments/text": .string("newest materialized text"),
      ],
      "The relation-bearing wire mutation must carry the newest required scalar without reviving an optional stale field."
    )
    _ = try? await runtime.closeConnection()
    await otherRuntimePersistence.simulateUnexpectedConnectionCloseForTesting()
  }

  @Test
  func automaticDeliveryFailsOversizedRequiredHydrationAndSendsSmallTail()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-projected-oversize",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let oversizedHead = requiredFoundationMutation(
      id: "tx-required-foundation-projected-oversize",
      entityID: "segment-required-foundation-projected-oversize",
      text: "tiny persisted text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-oversize",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    let smallTail = requiredFoundationMutation(
      id: "tx-required-foundation-projected-small-tail",
      entityID: "segment-required-foundation-projected-small-tail",
      text: "small tail text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-small-tail",
      createdAt: InstantTimestamp(milliseconds: 300)
    )
    try await runtime.persistence.saveOutbox([oversizedHead, smallTail])

    let oversizedAuthoritativeText = String(
      repeating: "x",
      count: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024
    )
    try await runtime.persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation-projected-oversize",
            attributeID: "transcriptionSegments/text",
            value: .string(oversizedAuthoritativeText),
            transactionID: "authoritative-required-foundation-projected-oversize",
            timestamp: InstantTimestamp(milliseconds: 200)
          )
        ]
      )
    )

    await runtime.persistence.resetVisibleRequiredScalarDecodeMetricsForTesting()
    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for small tail behind projected-oversize required hydration",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let sentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let failedHead = try #require(
      await runtime.failedMutations().first { $0.id == oversizedHead.id }
    )
    let headClaim = try #require(
      try await runtime.persistence.outboxDeliveryClaimForTesting(id: oversizedHead.id)
    )
    let decodedRequiredScalarCount =
      await runtime.persistence.decodedVisibleRequiredScalarCountForTesting()
    let decodedRequiredScalarValueByteCount =
      await runtime.persistence.decodedVisibleRequiredScalarValueByteCountForTesting()
    let materializedText = try #require(
      try await runtime.persistence.loadSnapshot().store.triples.first {
        $0.entityID == "segment-required-foundation-projected-oversize"
          && $0.attributeID == "transcriptionSegments/text"
      }
    )

    expectNoDifference(sentMutationIDs, [smallTail.id])
    expectNoDifference(failedHead.failure?.code, .validationFailed)
    #expect(failedHead.failureMessage?.contains("projected pending body") == true)
    #expect(
      failedHead.failureMessage?.contains(
        "\(InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)-byte"
      ) == true
    )
    expectNoDifference(headClaim.state, .ready)
    expectNoDifference(headClaim.claimToken, nil)
    expectNoDifference(headClaim.projectedBodyByteCount, nil)
    expectNoDifference(
      decodedRequiredScalarCount,
      0,
      "An individually oversized projected row must fail from SQLite value-length metadata before decoding the authoritative value."
    )
    expectNoDifference(decodedRequiredScalarValueByteCount, 0)
    expectNoDifference(materializedText.value, .string(oversizedAuthoritativeText))

    let repeatedPumpCompleted = await runtime.sendOutstandingMutationsToLiveSession()
    #expect(repeatedPumpCompleted)
    let repeatedSentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    expectNoDifference(repeatedSentMutationIDs, [smallTail.id])
    _ = try? await runtime.closeConnection()
  }

  @Test
  func automaticDeliveryDefersSecondFiveMiBRequiredHydrationUntilCapacityReleases()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-projected-window",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let first = requiredFoundationMutation(
      id: "tx-required-foundation-projected-window-first",
      entityID: "segment-required-foundation-projected-window-first",
      text: "tiny first persisted text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-window-first",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    let second = requiredFoundationMutation(
      id: "tx-required-foundation-projected-window-second",
      entityID: "segment-required-foundation-projected-window-second",
      text: "tiny second persisted text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-projected-window-second",
      createdAt: InstantTimestamp(milliseconds: 200)
    )
    try await runtime.persistence.saveOutbox([first, second])

    let fiveMiBText = String(repeating: "y", count: 5 * 1_024 * 1_024)
    try await runtime.persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation-projected-window-first",
            attributeID: "transcriptionSegments/text",
            value: .string(fiveMiBText),
            transactionID: "authoritative-required-foundation-projected-window-first",
            timestamp: InstantTimestamp(milliseconds: 300)
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation-projected-window-second",
            attributeID: "transcriptionSegments/text",
            value: .string(fiveMiBText),
            transactionID: "authoritative-required-foundation-projected-window-second",
            timestamp: InstantTimestamp(milliseconds: 300)
          ),
        ]
      )
    )

    await runtime.persistence.resetVisibleRequiredScalarDecodeMetricsForTesting()
    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for first five-MiB projected mutation",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }

    let initiallySentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let firstClaim = try #require(
      try await runtime.persistence.outboxDeliveryClaimForTesting(id: first.id)
    )
    let deferredClaim = try #require(
      try await runtime.persistence.outboxDeliveryClaimForTesting(id: second.id)
    )
    let initialRequiredScalarDecodeCount =
      await runtime.persistence.decodedVisibleRequiredScalarCountForTesting()
    let initialRequiredScalarValueByteCount =
      await runtime.persistence.decodedVisibleRequiredScalarValueByteCountForTesting()
    expectNoDifference(initiallySentMutationIDs, [first.id])
    expectNoDifference(firstClaim.state, .claimed)
    #expect((firstClaim.projectedBodyByteCount ?? 0) > 5 * 1_024 * 1_024)
    #expect(
      (firstClaim.projectedBodyByteCount ?? .max)
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    expectNoDifference(deferredClaim.state, .ready)
    expectNoDifference(deferredClaim.claimToken, nil)
    expectNoDifference(deferredClaim.projectedBodyByteCount, nil)
    expectNoDifference(deferredClaim.deliveryStarted, false)
    expectNoDifference(
      initialRequiredScalarDecodeCount,
      1,
      "The aggregate-overflow suffix must remain metadata-only until the admitted prefix releases capacity."
    )
    #expect(initialRequiredScalarValueByteCount > 5 * 1_024 * 1_024)
    #expect(
      initialRequiredScalarValueByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )

    await liveSession.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: first.id,
        fields: ["tx-id": .string("server-required-foundation-projected-window-first")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for deferred five-MiB projection after capacity release",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }
    let finallySentMutationIDs = await liveSession.sentMessages()
      .filter { $0.op == "transact" }
      .compactMap(\.clientEventID)
    let finalRequiredScalarDecodeCount =
      await runtime.persistence.decodedVisibleRequiredScalarCountForTesting()
    expectNoDifference(finallySentMutationIDs, [first.id, second.id])
    expectNoDifference(finalRequiredScalarDecodeCount, 2)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func activeSuccessorKeepsOriginalThenNewRequiredFoundationValues() async throws {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-successor",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let older = requiredFoundationMutation(
      id: "tx-required-foundation-successor-older",
      entityID: "segment-required-foundation-successor",
      text: "older ordered text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-successor",
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    let newer = requiredFoundationMutation(
      id: "tx-required-foundation-successor-newer",
      entityID: "segment-required-foundation-successor",
      text: "newer ordered text",
      optionalPreview: nil,
      recordingID: nil,
      createdAt: InstantTimestamp(milliseconds: 200)
    )
    _ = try await runtime.transact(older.transaction, createdAt: older.createdAt)
    _ = try await runtime.transact(newer.transaction, createdAt: newer.createdAt)

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for ordered required-foundation successor delivery",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(3)
    }
    let sent = await liveSession.sentMessages().filter { $0.op == "transact" }
    let olderSent = try #require(sent.first { $0.clientEventID == older.id })
    let newerSent = try #require(sent.first { $0.clientEventID == newer.id })

    expectNoDifference(sent.compactMap(\.clientEventID), [older.id, newer.id])
    expectNoDifference(
      boundedOutboxAddTripleValues(in: olderSent)["transcriptionSegments/text"],
      .string("older ordered text"),
      "A pending successor is not authoritative: the predecessor must keep its original required value."
    )
    expectNoDifference(
      boundedOutboxAddTripleValues(in: newerSent)["transcriptionSegments/text"],
      .string("newer ordered text")
    )
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacyActiveUnconfirmedOverlayCannotHydrateLaterFoundationMutation()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorServerAttrs(from: requiredFoundationAttributes))
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "bounded-outbox-required-foundation-legacy-overlay",
      persistenceURL: cacheURL,
      initialAttributes: requiredFoundationAttributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    var activeFailedOverlay = requiredFoundationMutation(
      id: "tx-required-foundation-active-failed-overlay",
      entityID: "segment-required-foundation-active-failed-overlay",
      text: "newer unconfirmed optimistic text",
      optionalPreview: nil,
      recordingID: nil,
      createdAt: InstantTimestamp(milliseconds: 300)
    )
    activeFailedOverlay.createdAt = InstantTimestamp(milliseconds: 100)
    activeFailedOverlay.status = .failed
    activeFailedOverlay.failureMessage = "permission denied"
    activeFailedOverlay.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    activeFailedOverlay.optimisticOverlayState = .applied
    let foundation = requiredFoundationMutation(
      id: "tx-required-foundation-after-active-failed-overlay",
      entityID: "segment-required-foundation-active-failed-overlay",
      text: "foundation text",
      optionalPreview: nil,
      recordingID: "recording-required-foundation-active-failed-overlay",
      createdAt: InstantTimestamp(milliseconds: 200)
    )
    try await runtime.persistence.saveOutbox([activeFailedOverlay, foundation])
    try await runtime.persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: requiredFoundationAttributes,
        triples: [
          requiredFoundationTriple(
            entityID: "segment-required-foundation-active-failed-overlay",
            attributeID: "transcriptionSegments/id",
            value: .string("segment-required-foundation-active-failed-overlay"),
            transactionID: foundation.id,
            timestamp: foundation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation-active-failed-overlay",
            attributeID: "transcriptionSegments/recording",
            value: .ref("recording-required-foundation-active-failed-overlay"),
            transactionID: foundation.id,
            timestamp: foundation.createdAt
          ),
          requiredFoundationTriple(
            entityID: "segment-required-foundation-active-failed-overlay",
            attributeID: "transcriptionSegments/text",
            value: .string("newer unconfirmed optimistic text"),
            transactionID: activeFailedOverlay.id,
            timestamp: InstantTimestamp(milliseconds: 300)
          ),
        ]
      )
    )
    try executeBoundedOutboxSQL(
      """
      UPDATE instant_outbox
      SET confirmation_proven = NULL
      WHERE mutation_id = 'tx-required-foundation-active-failed-overlay';
      """,
      cacheURL: cacheURL
    )
    await runtime.persistence.invalidateMemoryCache()

    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for foundation delivery past an active legacy overlay",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    let materializedText = try #require(
      try await runtime.persistence.loadSnapshot().store.triples.first {
        $0.entityID == "segment-required-foundation-active-failed-overlay"
          && $0.attributeID == "transcriptionSegments/text"
      }
    )

    expectNoDifference(sent.clientEventID, foundation.id)
    expectNoDifference(
      boundedOutboxAddTripleValues(in: sent)["transcriptionSegments/text"],
      .string("foundation text"),
      "An active unconfirmed overlay is locally visible but cannot become authoritative input to an older-id wire body."
    )
    expectNoDifference(
      materializedText.value,
      .string("newer unconfirmed optimistic text"),
      "Filtering wire delivery must not disturb the newer local optimistic value."
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
    try await instantLiveWithTimeout(
      operation: "wait for the revision-qualified durable visible write",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let sent = try #require(
      await liveSession.sentMessages().first { $0.op == "transact" }
    )
    expectNoDifference(sent.clientEventID, mutation.id)
    expectNoDifference(
      boundedOutboxAddTripleValues(in: sent),
      ["server-todos-text": .string("newer durable value")],
      "A required scalar must use the revision-qualified durable value instead of disappearing or reviving its stale body value."
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

    await runtime.requestLiveMutationDelivery()
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
      await runtime.requestLiveMutationDelivery()
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
    let runtime = try await disconnectedRuntime(
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
      _ = try await runtime.connect()
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
    let runtime = try await disconnectedRuntime(
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
      _ = try await runtime.connect()
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
    await runtime.persistence.resetFailedMutationRetryMetricsForTesting()
    let encodingQuarantineDiagnostics = BoundedOutboxDiagnosticCounter()
    let diagnosticsToken = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "outbox.mutation.encoding-quarantined",
        entry.metadata["mutationID"]?.hasPrefix("tx-encoding-head-window-") == true
      else { return }
      encodingQuarantineDiagnostics.increment()
    }
    defer { InstantDiagnostics.shared.removeHandler(diagnosticsToken) }

    try await withKnownIssue {
      await runtime.requestLiveMutationDelivery()
      try await instantLiveWithTimeout(
        operation: "wait for tail behind encoding-failure window",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
      try await instantLiveWithTimeout(
        operation: "wait for the encoding-failure delivery pump to become idle",
        timeoutMilliseconds: 5_000
      ) {
        while !(await runtime.automaticMutationPumpIsIdleForTesting()) {
          await Task.yield()
        }
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
    let quarantineDiagnosticCount = encodingQuarantineDiagnostics.value
    expectNoDifference(quarantineDiagnosticCount, 50)
    let retryMetrics = await runtime.persistence.failedMutationRetryMetricsForTesting()
    expectNoDifference(retryMetrics.completedWindowCount, 0)
    expectNoDifference(retryMetrics.totalCandidateRowCount, 0)
    expectNoDifference(retryMetrics.totalDecodedBodyCount, 0)
    let maximumWindowBodyCount =
      await runtime.persistence.maximumAutomaticOutboxWindowBodyCountForTesting()
    expectNoDifference(decodedBodyCount, 101)
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
      await runtime.requestLiveMutationDelivery()
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
    configuration.liveMutationDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await withKnownIssue {
      _ = try await runtime.connect()
      try await instantLiveWithTimeout(
        operation: "wait for the initial deadline-bound mutation delivery",
        timeoutMilliseconds: 5_000
      ) {
        await liveSession.waitForSentMessageCount(2)
      }
      try await instantLiveWithTimeout(
        operation: "wait for the durable mutation deadline schedule",
        timeoutMilliseconds: 5_000
      ) {
        await deadlineSleep.waitForFirstDelay()
      }
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
  func unlimitedExplicitFlushOfTenThousandRowsAdmitsOneFiftyMutationWindow()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<10_000).map {
        boundedMutation(index: $0, prefix: "unlimited-flush-ten-thousand")
      },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-unlimited-flush-ten-thousand",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations()

    expectNoDifference(
      result.request.mutations.map(\.mutationID),
      (0..<InstantAutomaticOutboxClaimLimits.maximumMutationCount).map {
        String(format: "tx-unlimited-flush-ten-thousand-%05d", $0)
      }
    )
    expectNoDifference(result.pendingMutationCount, 9_950)
    expectNoDifference(result.mutationCount, 10_000)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      InstantAutomaticOutboxClaimLimits.maximumMutationCount,
      "The exact owned window carries each selected body through disposition instead of decoding it twice or hydrating the tail."
    )
    let firstTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-unlimited-flush-ten-thousand-00050"
    )
    let finalTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-unlimited-flush-ten-thousand-09999"
    )
    expectNoDifference(firstTailClaim?.state, .ready)
    expectNoDifference(firstTailClaim?.deliveryStarted, false)
    expectNoDifference(finalTailClaim?.state, .ready)
    expectNoDifference(finalTailClaim?.deliveryStarted, false)
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
  }

  @Test
  func unlimitedExplicitFlushHonorsTheTwoHundredFiftySixStepWindow()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<30).map {
        boundedMutation(index: $0, prefix: "explicit-step-window", stepCount: 10)
      },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-step-window",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations()

    expectNoDifference(result.request.mutations.count, 25)
    let transportStepCount = result.request.mutations.reduce(into: 0) { count, mutation in
      count += mutation.txSteps.count
    }
    expectNoDifference(transportStepCount, 250)
    #expect(transportStepCount <= InstantAutomaticOutboxClaimLimits.maximumStepCount)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 25)
    let firstTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-explicit-step-window-00025"
    )
    expectNoDifference(firstTailClaim?.state, .ready)
    expectNoDifference(firstTailClaim?.deliveryStarted, false)
  }

  @Test
  func unlimitedExplicitFlushHonorsTheEightMiBDurableBodyWindowBeforeDecode()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    try await seedBoundedOutbox(
      (0..<3).map {
        boundedLargeMutation(
          index: $0,
          prefix: "explicit-byte-window",
          valueByteCount: 5 * 1_024 * 1_024
        )
      },
      cacheURL: cacheURL
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-explicit-byte-window",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations()

    expectNoDifference(
      result.request.mutations.map(\.mutationID),
      ["tx-explicit-byte-window-00000"]
    )
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 1)
    let decodedBodyBytes = await runtime.persistence.currentDecodedOutboxBodyByteCount()
    #expect(decodedBodyBytes <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes)
    let firstTailClaim = try await runtime.persistence.outboxDeliveryClaimForTesting(
      id: "tx-explicit-byte-window-00001"
    )
    expectNoDifference(firstTailClaim?.state, .ready)
    expectNoDifference(firstTailClaim?.deliveryStarted, false)
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
      1,
      "A smaller caller limit still owns and decodes exactly one body through transport and disposition."
    )
    let residentBarrier = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(residentBarrier, [])
  }

  @Test
  func repeatedExplicitFailureOfTenThousandRowsKeepsResidentActorEmpty()
    async throws
  {
    let cacheURL = try temporaryBoundedOutboxCacheURL()
    var mutations = (0..<10_000).map {
      boundedMutation(index: $0, prefix: "failed-flush-ten-thousand")
    }
    let targetTriples = try (0..<2).map { index in
      let triple = try #require(
        mutations[index].transaction.operations.compactMap { operation -> InstantTriple? in
          guard case let .insert(triple) = operation else { return nil }
          return triple
        }.first
      )
      mutations[index].rollbackTransaction = InstantStoreTransaction(
        id: "rollback-\(mutations[index].id)",
        operations: [.deleteEntity(triple.entityID)]
      )
      return triple
    }
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: TodoExample.attributes,
        triples: targetTriples
      )
    )
    try await persistence.saveOutbox(mutations)
    await persistence.simulateUnexpectedConnectionCloseForTesting()
    let corruptTailID = "tx-failed-flush-ten-thousand-09999"
    try corruptBoundedOutboxBody(id: corruptTailID, cacheURL: cacheURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "bounded-outbox-failed-flush-ten-thousand",
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
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let result = try await runtime.flushPendingMutations(limit: 1)

    expectNoDifference(result.failed.map(\.id), ["tx-failed-flush-ten-thousand-00000"])
    expectNoDifference(result.pendingMutationCount, 9_999)
    expectNoDifference(result.mutationCount, 10_000)
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(
      decodedBodyCount,
      2,
      "Explicit rejection decodes the selected transport body and only its affected terminal component."
    )
    let quarantinedTailByteCount = try await runtime.persistence
      .quarantinedOutboxBodyByteCountForTesting(id: corruptTailID)
    expectNoDifference(quarantinedTailByteCount, 0)
    let tailDeliveryStarted = try await runtime.persistence.outboxDeliveryStartedForTesting(
      id: corruptTailID
    )
    expectNoDifference(tailDeliveryStarted, false)
    let residentBarrierAfterFirstFailure = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(
      residentBarrierAfterFirstFailure,
      [],
      "A terminal failure removes its target shell and must not append it back to an empty resident actor."
    )

    await runtime.persistence.resetDecodedOutboxBodyCount()
    let repeated = try await runtime.flushPendingMutations(limit: 1)

    expectNoDifference(repeated.failed.map(\.id), ["tx-failed-flush-ten-thousand-00001"])
    expectNoDifference(repeated.pendingMutationCount, 9_998)
    expectNoDifference(repeated.mutationCount, 10_000)
    let repeatedDecodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    expectNoDifference(repeatedDecodedBodyCount, 2)
    let residentBarrierAfterSecondFailure = await runtime.mutationDeliveryBarrierMutations()
    expectNoDifference(
      residentBarrierAfterSecondFailure,
      [],
      "Repeated terminal failures must keep the body-free resident actor empty."
    )
  }
}

private func connectedRuntime(
  appID: String,
  cacheURL: URL,
  liveSession: LiveReactorParitySession
) async throws -> InstantRuntime {
  let runtime = try await disconnectedRuntime(
    appID: appID,
    cacheURL: cacheURL,
    liveSession: liveSession
  )
  _ = try await runtime.connect()
  let sentOps = await liveSession.sentMessages().map(\.op)
  expectNoDifference(
    sentOps,
    ["init"],
    boundedOutboxSource
  )
  return runtime
}

private func disconnectedRuntime(
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
  return try await InstantRuntime.bootstrap(configuration: configuration)
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

private let requiredFoundationAttributes: [InstantAttribute] = [
  .primaryKey(namespace: "transcriptionSegments"),
  InstantAttribute(
    id: "transcriptionSegments/text",
    namespace: "transcriptionSegments",
    name: "text",
    valueType: .string,
    isRequired: true
  ),
  InstantAttribute(
    id: "transcriptionSegments/searchPreview",
    namespace: "transcriptionSegments",
    name: "searchPreview",
    valueType: .string,
    isRequired: false
  ),
  InstantAttribute(
    id: "transcriptionSegments/recording",
    namespace: "transcriptionSegments",
    name: "recording",
    valueType: .ref,
    isRequired: false,
    forwardIdentity: "transcriptionSegments/recording",
    reverseIdentity: "recordings/transcriptionSegments",
    linkNamespace: "recordings"
  ),
]

private func requiredFoundationMutation(
  id: String,
  entityID: String,
  text: String,
  optionalPreview: String?,
  recordingID: String?,
  createdAt: InstantTimestamp
) -> PendingMutation {
  var operations: [InstantTripleOperation] = [
    .insert(
      requiredFoundationTriple(
        entityID: entityID,
        attributeID: "transcriptionSegments/id",
        value: .string(entityID),
        transactionID: id,
        timestamp: createdAt
      )
    )
  ]
  if let recordingID {
    operations.append(
      .insert(
        requiredFoundationTriple(
          entityID: entityID,
          attributeID: "transcriptionSegments/recording",
          value: .ref(recordingID),
          transactionID: id,
          timestamp: createdAt
        )
      )
    )
  }
  operations.append(
    .insert(
      requiredFoundationTriple(
        entityID: entityID,
        attributeID: "transcriptionSegments/text",
        value: .string(text),
        transactionID: id,
        timestamp: createdAt
      )
    )
  )
  if let optionalPreview {
    operations.append(
      .insert(
        requiredFoundationTriple(
          entityID: entityID,
          attributeID: "transcriptionSegments/searchPreview",
          value: .string(optionalPreview),
          transactionID: id,
          timestamp: createdAt
        )
      )
    )
  }
  return PendingMutation(
    id: id,
    createdAt: createdAt,
    transaction: InstantStoreTransaction(id: id, operations: operations)
  )
}

private func requiredFoundationTriple(
  entityID: String,
  attributeID: String,
  value: InstantValue,
  transactionID: String,
  timestamp: InstantTimestamp
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: attributeID,
    value: value,
    txID: transactionID,
    txTime: timestamp
  )
}

private func boundedOutboxAddTripleValues(
  in message: InstantLiveMessage
) -> [String: InstantLiveJSONValue] {
  Dictionary(
    uniqueKeysWithValues: message.fields["tx-steps"]?.arrayValue?.compactMap { step in
      guard let values = step.arrayValue,
        values.count >= 4,
        values[0].stringValue == "add-triple",
        let attributeID = values[2].stringValue
      else { return nil }
      return (attributeID, values[3])
    } ?? []
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
    -- The effect-entity table stays at its 0015 shape, including created_at_ms.
    -- Replay only migrations whose outbox columns or indexes were removed.
    DELETE FROM instant_schema_migrations
    WHERE name IN (
      '0012_bounded_outbox_delivery',
      '0013_outbox_supersession_lifecycle',
      '0014_outbox_optimistic_effects',
      '0016_failed_mutation_retry_window',
      '0017_bounded_server_apply',
      '0018_schema_failure_attribute_revision',
      '0019_projected_outbox_claim_bytes'
    );
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

private final class BoundedOutboxDiagnosticCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  func increment() {
    lock.withLock { count += 1 }
  }

  var value: Int {
    lock.withLock { count }
  }
}

private actor BoundedOutboxControlledSleep {
  private var recordedFirstDelay: UInt64?
  private var firstDelayContinuation: CheckedContinuation<Void, Error>?
  private var delayWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

  func sleep(milliseconds: UInt64) async throws {
    guard recordedFirstDelay == nil else { throw CancellationError() }
    recordedFirstDelay = milliseconds
    for waiter in delayWaiters.values { waiter.resume() }
    delayWaiters.removeAll()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          firstDelayContinuation = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelFirstDelay() }
    }
  }

  func waitForFirstDelay() async {
    guard recordedFirstDelay == nil else { return }
    let waiterID = UUID()
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume()
        } else {
          delayWaiters[waiterID] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancelDelayWaiter(id: waiterID) }
    }
  }

  func firstDelay() -> UInt64? {
    recordedFirstDelay
  }

  func resumeFirstDelay() {
    firstDelayContinuation?.resume()
    firstDelayContinuation = nil
  }

  private func cancelFirstDelay() {
    firstDelayContinuation?.resume(throwing: CancellationError())
    firstDelayContinuation = nil
  }

  private func cancelDelayWaiter(id: UUID) {
    delayWaiters.removeValue(forKey: id)?.resume()
  }
}

// SAFETY: `lock` protects the completion bit shared by the test task and its
// observer. The probe deliberately has no asynchronous cleanup of its own.
private final class BoundedOutboxCompletionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false

  var didComplete: Bool {
    lock.withLock { completed }
  }

  func record() {
    lock.withLock { completed = true }
  }
}

// SAFETY: `lock` protects the one-shot continuation and every observation.
// Cancellation is recorded but intentionally does not resume the continuation,
// allowing tests to prove exact joins rather than cooperative cancellation.
private final class BoundedOutboxCancellationIgnoringSleep: @unchecked Sendable {
  private let lock = NSLock()
  private var entered = false
  private var milliseconds: UInt64?
  private var cancellations = 0
  private var isReleased = false
  private var continuation: CheckedContinuation<Void, Never>?

  var didEnter: Bool {
    lock.withLock { entered }
  }

  var requestedMilliseconds: UInt64? {
    lock.withLock { milliseconds }
  }

  var cancellationCount: Int {
    lock.withLock { cancellations }
  }

  func sleep(milliseconds: UInt64) async throws {
    lock.withLock {
      entered = true
      self.milliseconds = milliseconds
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        let resumeImmediately = lock.withLock { () -> Bool in
          guard !isReleased else { return true }
          self.continuation = continuation
          return false
        }
        if resumeImmediately {
          continuation.resume()
        }
      }
    } onCancel: {
      self.lock.withLock { self.cancellations += 1 }
    }
    try Task.checkCancellation()
  }

  func release() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !isReleased else { return nil }
      isReleased = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

// SAFETY: `lock` protects the one-shot run continuation, request, and counters.
// `releaseWithServerAcceptance` deliberately returns a successful response even
// after synchronous abort, proving that the exact owner durably dispositions an
// authoritative response before a timeout or close boundary can return.
private final class BoundedOutboxCancellationIgnoringPreparedTransport:
  @unchecked Sendable
{
  private let lock = NSLock()
  private var request: InstantMutationTransportRequest?
  private var entered = false
  private var isReleased = false
  private var continuation: CheckedContinuation<Void, Never>?
  private var aborts = 0
  private var runCompletions = 0

  var didEnter: Bool {
    lock.withLock { entered }
  }

  var abortCount: Int {
    lock.withLock { aborts }
  }

  var mutationIDs: [String] {
    lock.withLock { request?.mutations.map(\.mutationID) ?? [] }
  }

  var runCompletionCount: Int {
    lock.withLock { runCompletions }
  }

  func operation(
    for request: InstantMutationTransportRequest
  ) -> InstantMutationTransportOperation {
    InstantMutationTransportOperation(
      run: { try await self.run(request) },
      abort: { self.abort() }
    )
  }

  private func run(
    _ request: InstantMutationTransportRequest
  ) async throws -> InstantMutationTransportResponse {
    lock.withLock {
      self.request = request
      entered = true
    }
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        guard !isReleased else { return true }
        self.continuation = continuation
        return false
      }
      if resumeImmediately {
        continuation.resume()
      }
    }
    lock.withLock { runCompletions += 1 }
    return InstantMutationTransportResponse(
      results: request.mutations.map {
        InstantMutationTransportResult(
          mutationID: $0.mutationID,
          outcome: .confirmed,
          acceptance: .serverAccepted
        )
      }
    )
  }

  private func abort() {
    lock.withLock { aborts += 1 }
  }

  func releaseWithServerAcceptance() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !isReleased else { return nil }
      isReleased = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
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
