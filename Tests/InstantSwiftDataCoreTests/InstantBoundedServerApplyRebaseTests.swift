import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantBoundedServerApplyRebaseTests {
  @Test
  func tenThousandDisjointRowsDecodeNoBodiesAndNeverReadTheQueue() async throws {
    let mutations = (0..<10_000).map { index in
      boundedServerApplyMutation(
        id: String(format: "disjoint-%05d", index),
        position: Int64(index),
        entityID: String(format: "disjoint-entity-%05d", index),
        before: nil,
        after: "local-\(index)"
      )
    }
    let snapshot = InstantPersistenceSnapshot(
      store: InstantStoreSnapshot(
        attributes: boundedServerApplyAttributes,
        triples: mutations.compactMap { mutation in
          mutation.transaction.operations.compactMap(\.insertedTriple).first
        }
      ),
      outbox: mutations
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "ten-thousand-disjoint",
      snapshot: snapshot
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetServerApplyMetricsForTesting()
    let outboxRevisionBeforeApply = try await runtime.persistence.currentOutboxRevision()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-disjoint",
        operations: [
          .insert(boundedServerApplyTriple(
            entityID: "server-only",
            value: "server",
            transactionID: "server-disjoint",
            milliseconds: 20_000
          ))
        ]
      )
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    let outboxMutationCount = try await runtime.persistence.countOutboxMutations()
    let outboxRevisionAfterApply = try await runtime.persistence.currentOutboxRevision()
    expectNoDifference(metrics.plannedBodyCount, 0)
    expectNoDifference(metrics.decodedBodyCount, 0)
    expectNoDifference(metrics.decodedBodyByteCount, 0)
    expectNoDifference(metrics.reverseBodyPageCount, 0)
    expectNoDifference(metrics.forwardBodyPageCount, 0)
    expectNoDifference(metrics.maximumBodyPageCount, 0)
    expectNoDifference(metrics.maximumBodyPageByteCount, 0)
    expectNoDifference(queueWideReadCount, 0)
    expectNoDifference(outboxMutationCount, 10_000)
    expectNoDifference(outboxRevisionAfterApply, outboxRevisionBeforeApply)
  }

  @Test
  func oneHundredOneConnectedRowsStreamAsFiftyFiftyOneInBothDirections() async throws {
    let entityID = "connected-entity"
    let mutations = boundedServerApplyMutationChain(
      count: 101,
      entityID: entityID,
      prefix: "connected"
    )
    let finalTriple = try #require(
      mutations.last?.transaction.operations.compactMap(\.insertedTriple).first
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "one-hundred-one-connected",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [finalTriple]
        ),
        outbox: mutations
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-connected",
        operations: [
          .insert(boundedServerApplyTriple(
            entityID: entityID,
            value: "server-new",
            transactionID: "server-connected",
            milliseconds: 10_000
          ))
        ]
      )
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedBodyCount, 101)
    expectNoDifference(metrics.decodedBodyCount, 202)
    expectNoDifference(metrics.reverseBodyPageCount, 3)
    expectNoDifference(metrics.forwardBodyPageCount, 3)
    expectNoDifference(metrics.reverseBodyRowCount, 101)
    expectNoDifference(metrics.forwardBodyRowCount, 101)
    expectNoDifference(metrics.reverseMaximumBodyPageCount, 50)
    expectNoDifference(metrics.forwardMaximumBodyPageCount, 50)
    expectNoDifference(metrics.reverseLastBodyPageCount, 1)
    expectNoDifference(metrics.forwardLastBodyPageCount, 1)
    expectNoDifference(metrics.maximumBodyPageCount, 50)
    #expect(
      metrics.maximumBodyPageByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(queueWideReadCount, 0)
    let stored = try await runtime.persistence.loadState()
    expectNoDifference(stored.snapshot.outbox.map(\.id), mutations.map(\.id))
    expectNoDifference(
      stored.snapshot.store.triples.first(where: { $0.entityID == entityID })?.value,
      .string("local-100")
    )
  }

  @Test
  func componentLargerThanEightMiBStreamsWithoutAnOversizedBodyPage() async throws {
    let entityID = "large-component"
    let payload = String(repeating: "x", count: 2_100_000)
    let mutations = (0..<3).map { index in
      boundedServerApplyMutation(
        id: "large-\(index)",
        position: Int64(index),
        entityID: entityID,
        before: index == 0 ? "base" : "\(payload)-\(index - 1)",
        after: "\(payload)-\(index)"
      )
    }
    let finalTriple = try #require(
      mutations.last?.transaction.operations.compactMap(\.insertedTriple).first
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "larger-than-eight-mib",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [finalTriple]
        ),
        outbox: mutations
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-large",
        operations: [
          .insert(boundedServerApplyTriple(
            entityID: entityID,
            value: "server-large",
            transactionID: "server-large",
            milliseconds: 10_000
          ))
        ]
      )
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedBodyCount, 3)
    #expect(
      metrics.plannedBodyByteCount
        > InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    #expect(metrics.reverseBodyPageCount > 1)
    #expect(metrics.forwardBodyPageCount > 1)
    #expect(
      metrics.maximumBodyPageByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(queueWideReadCount, 0)
  }

  @Test
  func tenThousandMetricPagesRetainOnlyConstantSizeCounters() {
    var metrics = InstantServerApplyMetrics()

    for index in 0..<10_000 {
      metrics.recordBodyPage(
        direction: index.isMultiple(of: 2) ? .reverse : .forward,
        bodyCount: 50,
        bodyByteCount: 1_024
      )
    }

    expectNoDifference(metrics.reverseBodyPageCount, 5_000)
    expectNoDifference(metrics.forwardBodyPageCount, 5_000)
    expectNoDifference(metrics.reverseBodyRowCount, 250_000)
    expectNoDifference(metrics.forwardBodyRowCount, 250_000)
    expectNoDifference(metrics.reverseMaximumBodyPageCount, 50)
    expectNoDifference(metrics.forwardMaximumBodyPageCount, 50)
    expectNoDifference(metrics.reverseLastBodyPageCount, 50)
    expectNoDifference(metrics.forwardLastBodyPageCount, 50)
    expectNoDifference(metrics.maximumBodyPageCount, 50)
    expectNoDifference(metrics.maximumBodyPageByteCount, 1_024)
    let retainedIntegerArrays = Mirror(reflecting: metrics).children.compactMap { child in
      child.value is [Int] ? child.label ?? "<unlabeled>" : nil
    }
    expectNoDifference(retainedIntegerArrays, [])
  }

  @Test
  func compactLifecyclePatchPagesRespectEightMiBForLargeFailureMessages() async throws {
    let entityID = "large-failure-lifecycle"
    let failureMessages = [
      String(repeating: "f", count: 8_000_000),
      String(repeating: "s", count: 600_000),
    ]
    let mutations = boundedServerApplyMutationChain(
      count: failureMessages.count,
      entityID: entityID,
      prefix: "large-failure"
    ).enumerated().map { index, mutation in
      var mutation = mutation
      mutation.status = .failed
      mutation.failureMessage = failureMessages[index]
      return mutation
    }
    let finalTriple = try #require(
      mutations.last?.transaction.operations.compactMap(\.insertedTriple).first
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "large-failure-lifecycle",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [finalTriple]
        ),
        outbox: mutations
      )
    )
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      boundedServerApplyServerWrite(
        entityID: "large-failure-server-only",
        id: "large-failure-server"
      )
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.residentPatchPageCount, 2)
    expectNoDifference(metrics.residentPatchRowCount, 2)
    expectNoDifference(metrics.maximumResidentPatchPageCount, 1)
    #expect(
      metrics.maximumResidentPatchPageByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    #expect(
      metrics.maximumResidentPatchPageByteCount
        > InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes - 500_000
    )
    let outboxRevision = try await runtime.persistence.currentOutboxRevision()
    for expected in mutations {
      let loaded = try await runtime.persistence.loadOutboxMutations(
        statuses: [.failed],
        ids: [expected.id],
        expectedOutboxRevision: outboxRevision
      )
      let durable = try #require(loaded?.first)
      expectNoDifference(durable.status, .failed)
      expectNoDifference(durable.optimisticOverlayState, .removed)
      expectNoDifference(durable.failureMessage, expected.failureMessage)
    }
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(queueWideReadCount, 0)
  }

  @Test
  func failedActiveOverlayIsARootEvenWhenTheServerWriteIsDisjoint() async throws {
    var failed = boundedServerApplyMutation(
      id: "failed-active",
      position: 1,
      entityID: "failed-entity",
      before: "server-base",
      after: "failed-local",
      status: .failed
    )
    failed.failureMessage = "permission denied"
    failed.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "failed-active-root",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [
            boundedServerApplyTriple(
              entityID: "failed-entity",
              value: "failed-local",
              transactionID: failed.id,
              milliseconds: 2
            )
          ]
        ),
        outbox: [failed]
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-disjoint-from-failure",
        operations: [
          .insert(boundedServerApplyTriple(
            entityID: "server-entity",
            value: "server",
            transactionID: "server-disjoint-from-failure",
            milliseconds: 10
          ))
        ]
      )
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedBodyCount, 1)
    expectNoDifference(metrics.decodedBodyCount, 2)
    let state = try await runtime.persistence.loadState()
    let retainedFailure = try #require(state.snapshot.outbox.first)
    expectNoDifference(retainedFailure.id, failed.id)
    expectNoDifference(retainedFailure.optimisticOverlayState, .removed)
    expectNoDifference(retainedFailure.rollbackTransaction, nil)
    expectNoDifference(
      state.snapshot.store.triples.first(where: { $0.entityID == "failed-entity" })?.value,
      .string("server-base")
    )
  }

  @Test
  func emptyServerOperationPrunesWatermarkWithoutDecodingABody() async throws {
    var accepted = boundedServerApplyMutation(
      id: "accepted",
      position: 1,
      entityID: "accepted-entity",
      before: nil,
      after: "accepted"
    )
    let acceptedTriple = try #require(
      accepted.transaction.operations.compactMap(\.insertedTriple).first
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "empty-watermark",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [acceptedTriple]
        ),
        outbox: [accepted]
      )
    )
    let claimToken = "empty-watermark-acceptance-claim"
    let claim = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: runtime.automaticDeliveryClaimantIDForTesting(),
        claimToken: claimToken,
        now: InstantTimestamp(milliseconds: 10),
        maximumMutationCount: 1
      )
    )
    expectNoDifference(claim.mutations.map(\.id), [accepted.id])
    _ = try #require(
      try await runtime.acceptMutationIfPresent(
        id: accepted.id,
        serverTransactionID: "41",
        claimToken: claimToken
      )
    )
    let before = try await runtime.persistence.loadCompactState()
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(id: "42", operations: []),
      processedTransactionID: "42"
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedBodyCount, 0)
    expectNoDifference(metrics.decodedBodyCount, 0)
    let outboxMutationCount = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(outboxMutationCount, 0)
    let after = try await runtime.persistence.loadCompactState()
    expectNoDifference(after.storeRevision, before.storeRevision)
    expectNoDifference(after.outboxRevision, before.outboxRevision + 1)
    let processedTransactionID = try await runtime.persistence.loadMetadataValue(
      key: "sync.processed_transaction_id:bounded-server-apply-empty-watermark"
    )
    expectNoDifference(
      processedTransactionID,
      "42"
    )
  }

  @Test
  func connectedServerProvenOverlayIsRebasedWithoutLosingAcceptanceProof() async throws {
    var accepted = boundedServerApplyMutation(
      id: "accepted-connected",
      position: 1,
      entityID: "accepted-connected-entity",
      before: "server-base",
      after: "accepted-local",
      status: .confirmed
    )
    accepted.serverTransactionID = "900"
    accepted.confirmationSource = .webSocketTransactOK
    let localTriple = try #require(
      accepted.transaction.operations.compactMap(\.insertedTriple).first
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "accepted-connected",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [localTriple]
        ),
        outbox: [accepted]
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "100",
        operations: [
          .insert(boundedServerApplyTriple(
            entityID: "accepted-connected-entity",
            value: "new-server-base",
            transactionID: "100",
            milliseconds: 100
          ))
        ]
      ),
      processedTransactionID: "100"
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedBodyCount, 1)
    expectNoDifference(metrics.decodedBodyCount, 2)
    let state = try await runtime.persistence.loadState()
    let retained = try #require(state.snapshot.outbox.first)
    expectNoDifference(retained.id, accepted.id)
    expectNoDifference(retained.status, .confirmed)
    #expect(retained.provesServerAcceptance)
    expectNoDifference(retained.serverTransactionID, "900")
    expectNoDifference(
      state.snapshot.store.triples.first(where: {
        $0.entityID == "accepted-connected-entity"
      })?.value,
      .string("accepted-local")
    )
  }

  @Test
  func globalActiveEffectMakesEveryOverlayPartOfTheBoundedPlan() async throws {
    var global = boundedServerApplyMutation(
      id: "global-overlay",
      position: 1,
      entityID: "global-entity",
      before: "global-base",
      after: "global-local"
    )
    global.transaction.operations.append(
      .ruleParams(
        entityID: "global-rule-entity",
        namespace: "items",
        params: .object([:])
      )
    )
    let disjoint = boundedServerApplyMutation(
      id: "disjoint-overlay",
      position: 2,
      entityID: "disjoint-entity",
      before: "disjoint-base",
      after: "disjoint-local"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "global-overlay",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [global, disjoint].compactMap {
            $0.transaction.operations.compactMap(\.insertedTriple).first
          }
        ),
        outbox: [global, disjoint]
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-disjoint-from-global",
        operations: [
          .insert(boundedServerApplyTriple(
            entityID: "server-only-global-case",
            value: "server",
            transactionID: "server-disjoint-from-global",
            milliseconds: 100
          ))
        ]
      )
    )

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedBodyCount, 2)
    expectNoDifference(metrics.decodedBodyCount, 4)
    expectNoDifference(metrics.reverseBodyPageCount, 1)
    expectNoDifference(metrics.forwardBodyPageCount, 1)
    expectNoDifference(metrics.reverseBodyRowCount, 2)
    expectNoDifference(metrics.forwardBodyRowCount, 2)
    expectNoDifference(metrics.reverseMaximumBodyPageCount, 2)
    expectNoDifference(metrics.forwardMaximumBodyPageCount, 2)
    expectNoDifference(metrics.reverseLastBodyPageCount, 2)
    expectNoDifference(metrics.forwardLastBodyPageCount, 2)
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(queueWideReadCount, 0)
  }

  @Test
  func queryRetractionProtectionUsesIndexedOptimisticFootprintsWithoutBodyReads() async throws {
    let pending = boundedServerApplyMutation(
      id: "query-retraction-owner",
      position: 1,
      entityID: "query-retraction-entity",
      before: "server",
      after: "local"
    )
    let localTriple = try #require(
      pending.transaction.operations.compactMap(\.insertedTriple).first
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "query-retraction-protection",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [localTriple]
        ),
        outbox: [pending]
      )
    )
    await runtime.persistence.resetDecodedOutboxBodyCount()

    let protected = try await runtime.persistence.protectingServerRetractions([
      .retract(localTriple)
    ])

    expectNoDifference(protected, [])
    let decodedBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let queueWideReadCount =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(decodedBodyCount, 0)
    expectNoDifference(queueWideReadCount, 0)
  }

  @Test
  func deferredPayloadIsHydratedOnlyForTheAddressedComponentDuringRebase() async throws {
    let mutation = boundedServerApplyMutation(
      id: "deferred-overlay",
      position: 1,
      entityID: "deferred-entity",
      before: "server-base",
      after: "large-local-payload"
    )
    let localTriple = try #require(
      mutation.transaction.operations.compactMap(\.insertedTriple).first
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "deferred-component",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: boundedServerApplyAttributes,
          triples: [localTriple]
        ),
        outbox: [mutation]
      ),
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: ["items/value"]
      )
    )
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-deferred",
        operations: [
          .insert(boundedServerApplyTriple(
            entityID: "deferred-entity",
            value: "server-new",
            transactionID: "server-deferred",
            milliseconds: 100
          ))
        ]
      )
    )

    let deferredMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    #expect(deferredMetrics.valueCount > 0)
    let serverApplyMetrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(serverApplyMetrics.plannedBodyCount, 1)
    expectNoDifference(serverApplyMetrics.decodedBodyCount, 2)
    let stored = try await runtime.persistence.loadState()
    #expect(
      stored.snapshot.store.triples.allSatisfy {
        $0.attributeID != "items/value"
      }
    )
    let durableDeferredValues = try await runtime.persistence.loadDeferredValues(
      attributeIDs: ["items/value"],
      entityIDs: ["deferred-entity"]
    )
    expectNoDifference(durableDeferredValues.map(\.value), [.string("large-local-payload")])
    let hotStoreSnapshot = await runtime.store.snapshot()
    #expect(hotStoreSnapshot.triples.allSatisfy { $0.attributeID != "items/value" })
  }

  @Test
  func offeredRowRejectsChangedWireStagingWithoutChangingDurableAuthority() async throws {
    let cacheURL = boundedServerApplyCacheURL("offered-stage-row")
    let mutation = boundedServerApplyMutation(
      id: "offered-stage-row",
      position: 1,
      entityID: "offered-stage-entity",
      before: "server-base",
      after: "local"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "offered-stage-row",
      cacheURL: cacheURL,
      snapshot: boundedServerApplySnapshot(mutations: [mutation])
    )
    let persistence = runtime.persistence
    let didClaim = try await persistence.claimOutboxMutationWithoutHydrationForTesting(
      id: mutation.id,
      claimantID: "offered-stage-claimant",
      claimToken: "offered-stage-token",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaim)
    let didRelease = try await persistence.releaseAutomaticOutboxClaim(
      id: mutation.id,
      claimantID: "offered-stage-claimant"
    )
    #expect(didRelease)

    let plan = try await boundedReadyServerApplyPlan(
      persistence: persistence,
      id: "offered-stage-plan",
      entityID: "offered-stage-entity"
    )

    let plannedBefore = try await persistence.loadServerApplyBodyPage(
      planID: plan.id,
      direction: .reverse,
      after: nil
    )
    #expect(!plannedBefore.isStale)
    let original = try #require(plannedBefore.entries.first?.mutation)
    let changedWire = boundedChangedWireMutation(
      original,
      entityID: "offered-stage-entity",
      value: "different-wire-value"
    )
    #expect(
      try changedWire.mutationWireIntentFingerprint()
        != original.mutationWireIntentFingerprint()
    )
    let authorityBefore = try await boundedDurableAuthority(
      persistence: persistence,
      mutationID: mutation.id
    )
    let claimBefore = try #require(authorityBefore.claim)
    #expect(claimBefore.deliveryStarted)
    expectNoDifference(claimBefore.state, .ready)

    do {
      try await persistence.stageServerApplyBodyPage(
        planID: plan.id,
        dispositions: [.update(changedWire)]
      )
      Issue.record("Expected an offered server-apply row to reject changed wire intent.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "persist offered outbox mutation")
      #expect(error.message.contains(mutation.id))
    }

    let plannedAfter = try await persistence.loadServerApplyBodyPage(
      planID: plan.id,
      direction: .forward,
      after: nil
    )
    let reader = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reader.bootstrap()
    let authorityAfter = try await boundedDurableAuthority(
      persistence: reader,
      mutationID: mutation.id
    )
    #expect(!plannedAfter.isStale)
    expectNoDifference(plannedAfter.entries.map(\.mutation), [original])
    expectNoDifference(authorityAfter, authorityBefore)
    try await persistence.finishServerApplyPlan(id: plan.id)
  }

  @Test
  func claimAndReleaseMakesAnUnofferedServerApplyPlanStale() async throws {
    let cacheURL = boundedServerApplyCacheURL("claim-release-stale-plan")
    let mutation = boundedServerApplyMutation(
      id: "claim-release-stale-row",
      position: 1,
      entityID: "claim-release-stale-entity",
      before: "server-base",
      after: "local"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "claim-release-stale-plan",
      cacheURL: cacheURL,
      snapshot: boundedServerApplySnapshot(mutations: [mutation])
    )
    let persistence = runtime.persistence
    let authorityBefore = try await boundedDurableAuthority(
      persistence: persistence,
      mutationID: mutation.id
    )
    #expect(!(try await persistence.outboxDeliveryStartedForTesting(id: mutation.id)))

    let plan = try await boundedReadyServerApplyPlan(
      persistence: persistence,
      id: "claim-release-stale-plan",
      entityID: "claim-release-stale-entity"
    )
    let plannedBefore = try await persistence.loadServerApplyBodyPage(
      planID: plan.id,
      direction: .reverse,
      after: nil
    )
    #expect(!plannedBefore.isStale)
    let original = try #require(plannedBefore.entries.first?.mutation)
    let changedWire = boundedChangedWireMutation(
      original,
      entityID: "claim-release-stale-entity",
      value: "stale-plan-wire-value"
    )

    let writer = try SQLitePersistenceStore(fileURL: cacheURL)
    try await writer.bootstrap()
    let didClaim = try await writer.claimOutboxMutationWithoutHydrationForTesting(
      id: mutation.id,
      claimantID: "claim-release-race-writer",
      claimToken: "claim-release-race-token",
      deadlineMilliseconds: 5_000
    )
    #expect(didClaim)
    let didRelease = try await writer.releaseAutomaticOutboxClaim(
      id: mutation.id,
      claimantID: "claim-release-race-writer"
    )
    #expect(didRelease)

    let stalePage = try await persistence.loadServerApplyBodyPage(
      planID: plan.id,
      direction: .forward,
      after: nil
    )
    #expect(stalePage.isStale)
    expectNoDifference(stalePage.entries.map(\.mutation), [])
    do {
      try await persistence.stageServerApplyBodyPage(
        planID: plan.id,
        dispositions: [.update(changedWire)]
      )
      Issue.record("Expected stale changed-wire staging to reject the newly offered row.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "persist offered outbox mutation")
    }
    let commit = try await persistence.commitServerApplyPlan(
      planID: plan.id,
      changedEntityTriples: [:],
      mergingAttributes: [],
      queryResults: [],
      storeChanged: false,
      metadataKey: "claim-release-stale-metadata",
      metadataValue: "must-not-commit",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 100)
    )
    if case .some = commit {
      Issue.record("Expected the claim-and-release race to invalidate the server-apply commit.")
    }

    let reader = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reader.bootstrap()
    let authorityAfter = try await boundedDurableAuthority(
      persistence: reader,
      mutationID: mutation.id
    )
    let claimAfter = try #require(authorityAfter.claim)
    expectNoDifference(authorityAfter.state, authorityBefore.state)
    expectNoDifference(authorityAfter.rowRevision, authorityBefore.rowRevision)
    expectNoDifference(claimAfter.state, .ready)
    expectNoDifference(claimAfter.claimToken, nil)
    expectNoDifference(claimAfter.claimantID, nil)
    #expect(claimAfter.deliveryStarted)
    let staleMetadata = try await reader.loadMetadataValue(
      key: "claim-release-stale-metadata"
    )
    expectNoDifference(
      staleMetadata,
      nil
    )
    try await persistence.finishServerApplyPlan(id: plan.id)
  }

  @Test
  func localTransactionCommitsWhileServerApplyIsPreparedThenServerApplyCatchesItUp() async throws {
    let entityID = "local-during-server-apply-entity"
    let localMutationID = "local-during-server-apply"
    let serverTransactionID = "server-with-concurrent-local"
    let barrier = BoundedServerApplyPreparationBarrier()
    let runtime = try await boundedServerApplyRuntime(
      suffix: "local-during-server-apply",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: boundedServerApplyAttributes)
      ),
      onPrepared: { _ in
        await barrier.pauseFirstPreparation()
      }
    )
    await runtime.persistence.resetServerApplyMetricsForTesting()

    let serverApply = Task {
      try await runtime.applyServerTransaction(
        boundedServerApplyServerWrite(
          entityID: entityID,
          id: serverTransactionID
        )
      )
    }
    await barrier.waitUntilFirstPreparationPauses()

    let localWrite = Task {
      try await runtime.transact(
        InstantStoreTransaction(
          id: localMutationID,
          operations: [
            .insert(boundedServerApplyTriple(
              entityID: entityID,
              value: "local",
              transactionID: localMutationID,
              milliseconds: 200
            ))
          ]
        ),
        createdAt: InstantTimestamp(milliseconds: 200)
      )
    }
    let localResult: InstantStoreMutationResult?
    let localFailure: (any Error)?
    do {
      localResult = try await instantLiveWithTimeout(
        operation: "commit a local transaction while server apply is prepared",
        timeoutMilliseconds: 5_000,
        onAbandon: {
          localWrite.cancel()
          Task { await barrier.release() }
        }
      ) {
        try await localWrite.value
      }
      localFailure = nil
    } catch {
      localResult = nil
      localFailure = error
    }

    let pausedState = try await runtime.persistence.loadState()
    await barrier.release()
    _ = try? await localWrite.value
    let serverResult = try await serverApply.value
    if let localFailure { throw localFailure }

    expectNoDifference(localResult?.transactionID, localMutationID)
    expectNoDifference(pausedState.snapshot.outbox.map(\.id), [localMutationID])
    expectNoDifference(
      pausedState.snapshot.store.triples.first(where: { $0.entityID == entityID })?.value,
      .string("local")
    )
    expectNoDifference(
      serverResult.syncState.processedTransactionID,
      serverTransactionID
    )

    let finalState = try await runtime.persistence.loadState()
    let finalMutation = try #require(finalState.snapshot.outbox.first)
    expectNoDifference(finalState.snapshot.outbox.map(\.id), [localMutationID])
    expectNoDifference(
      finalState.snapshot.store.triples.first(where: { $0.entityID == entityID })?.value,
      .string("local")
    )
    expectNoDifference(
      finalMutation.rollbackTransaction?.operations.compactMap(\.insertedTriple).first?.value,
      .string("server")
    )
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
    expectNoDifference(metrics.planCount, 1)
  }

  @Test
  func sustainedLocalTransactionsCannotStarveOneServerRefresh() async throws {
    let rootEntityID = "continuous-local-root"
    let writer = BoundedServerApplyConcurrentLocalWriter(
      rootEntityID: rootEntityID,
      writesPerPreparation: 8
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "continuous-local-writes",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: boundedServerApplyAttributes)
      ),
      onPrepared: { _ in
        await writer.writeBatchForPreparation()
      }
    )
    await writer.install(runtime)
    await runtime.persistence.resetServerApplyMetricsForTesting()

    let result = try await instantLiveWithTimeout(
      operation: "apply one server refresh while local recording writes continue",
      timeoutMilliseconds: 5_000
    ) {
      try await runtime.applyServerTransaction(
        boundedServerApplyServerWrite(
          entityID: rootEntityID,
          id: "server-during-continuous-local"
        )
      )
    }

    expectNoDifference(
      result.syncState.processedTransactionID,
      "server-during-continuous-local"
    )
    let writeFailures = await writer.failures()
    expectNoDifference(writeFailures, [])
    let localMutationIDs = await writer.mutationIDs()
    expectNoDifference(localMutationIDs.count, 8)

    let finalState = try await runtime.persistence.loadState()
    expectNoDifference(
      finalState.snapshot.outbox.map(\.id),
      (0..<8).map { "continuous-local-\($0)" }
    )
    expectNoDifference(
      finalState.snapshot.store.triples.first(where: {
        $0.entityID == rootEntityID && $0.attributeID == "items/value"
      })?.value,
      .string("local-7")
    )
    for index in 0..<8 {
      expectNoDifference(
        finalState.snapshot.store.triples.first(where: {
          $0.entityID == "continuous-local-segment-\(index)"
            && $0.attributeID == "items/value"
        })?.value,
        .string("segment-\(index)")
      )
      let mutation = try #require(finalState.snapshot.outbox.first(where: {
        $0.id == "continuous-local-\(index)"
      }))
      let rollback = try #require(mutation.rollbackTransaction)
      expectNoDifference(
        rollback.operations.compactMap(\.insertedTriple).first(where: {
          $0.entityID == rootEntityID && $0.attributeID == "items/value"
        })?.value,
        .string(index == 0 ? "server" : "local-\(index - 1)")
      )
      #expect(rollback.operations.contains(where: {
        $0.deletedEntityID == "continuous-local-segment-\(index)"
      }))
    }
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.planCount, 1)
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
  }

  @Test
  func sameEntitySupersessionWaitsForServerRefreshCatchUp() async throws {
    let rootEntityID = "catch-up-same-entity-root"
    let writer = BoundedServerApplyConcurrentLocalWriter(
      rootEntityID: rootEntityID,
      writesPerPreparation: 2,
      includesUniqueSegment: false
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "catch-up-same-entity",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: boundedServerApplyAttributes)
      ),
      onPrepared: { _ in
        await writer.writeBatchForPreparation()
      }
    )
    await writer.install(runtime)
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      boundedServerApplyServerWrite(
        entityID: rootEntityID,
        id: "catch-up-same-entity-server"
      )
    )

    let state = try await runtime.persistence.loadState()
    expectNoDifference(
      state.snapshot.outbox.map(\.id),
      ["continuous-local-0", "continuous-local-1"]
    )
    expectNoDifference(
      state.snapshot.store.triples.first(where: {
        $0.entityID == rootEntityID && $0.attributeID == "items/value"
      })?.value,
      .string("local-1")
    )
    let first = try #require(state.snapshot.outbox.first(where: {
      $0.id == "continuous-local-0"
    }))
    let second = try #require(state.snapshot.outbox.first(where: {
      $0.id == "continuous-local-1"
    }))
    expectNoDifference(
      first.rollbackTransaction?.operations.compactMap(\.insertedTriple).first?.value,
      .string("server")
    )
    expectNoDifference(
      second.rollbackTransaction?.operations.compactMap(\.insertedTriple).first?.value,
      .string("local-0")
    )
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.planCount, 1)
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
  }

  @Test
  func oneOutsideGateReplayThenForcedDrainCatchesTheNextLocalBatch() async throws {
    let rootEntityID = "two-round-catch-up-root"
    let writer = BoundedServerApplyConcurrentLocalWriter(
      rootEntityID: rootEntityID,
      writesPerPreparation: 51
    )
    let outsideReplay = BoundedServerApplyOutsideReplayProbe()
    let runtime = try await boundedServerApplyRuntime(
      suffix: "two-round-catch-up",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: boundedServerApplyAttributes)
      ),
      onPrepared: { _ in
        await writer.writeBatchForPreparation()
      },
      onCatchUpReplayedOutsideOperationGate: { appendedBodyCount in
        await outsideReplay.record(appendedBodyCount: appendedBodyCount)
        await writer.writeNextBatch(count: 2)
      }
    )
    await writer.install(runtime)
    await runtime.persistence.resetServerApplyMetricsForTesting()

    let result = try await instantLiveWithTimeout(
      operation: "finish a forced second catch-up drain",
      timeoutMilliseconds: 15_000
    ) {
      try await runtime.applyServerTransaction(
        boundedServerApplyServerWrite(
          entityID: rootEntityID,
          id: "two-round-catch-up-server"
        )
      )
    }

    expectNoDifference(
      result.syncState.processedTransactionID,
      "two-round-catch-up-server"
    )
    let outsideReplayBodyCounts = await outsideReplay.counts()
    let writeFailures = await writer.failures()
    let localMutationIDs = await writer.mutationIDs()
    expectNoDifference(outsideReplayBodyCounts, [51])
    expectNoDifference(writeFailures, [])
    expectNoDifference(localMutationIDs.count, 53)

    let state = try await runtime.persistence.loadState()
    expectNoDifference(
      state.snapshot.outbox.map(\.id),
      (0..<53).map { "continuous-local-\($0)" }
    )
    expectNoDifference(
      state.snapshot.store.triples.first(where: {
        $0.entityID == rootEntityID && $0.attributeID == "items/value"
      })?.value,
      .string("local-52")
    )
    for index in [0, 50, 51, 52] {
      let mutation = try #require(state.snapshot.outbox.first(where: {
        $0.id == "continuous-local-\(index)"
      }))
      expectNoDifference(
        mutation.rollbackTransaction?.operations.compactMap(\.insertedTriple).first(where: {
          $0.entityID == rootEntityID && $0.attributeID == "items/value"
        })?.value,
        .string(index == 0 ? "server" : "local-\(index - 1)")
      )
      expectNoDifference(
        state.snapshot.store.triples.first(where: {
          $0.entityID == "continuous-local-segment-\(index)"
            && $0.attributeID == "items/value"
        })?.value,
        .string("segment-\(index)")
      )
    }

    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.planCount, 1)
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
    expectNoDifference(metrics.forwardBodyPageCount, 3)
    expectNoDifference(metrics.forwardBodyRowCount, 53)
    expectNoDifference(metrics.forwardMaximumBodyPageCount, 50)
  }

  @Test
  func continuouslyAppendingPeerTakesBoundedFallbackAndDoesNotBlockClose() async throws {
    let cacheURL = boundedServerApplyCacheURL("continuous-peer-catch-up")
    let peer = try await boundedServerApplyRuntime(
      suffix: "continuous-peer-catch-up",
      cacheURL: cacheURL,
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: boundedServerApplyAttributes)
      )
    )
    let writer = BoundedServerApplyConcurrentLocalWriter(
      rootEntityID: "continuous-peer-root",
      writesPerPreparation: 1
    )
    let barrier = BoundedServerApplyPreparationBarrier()
    let replayProbe = BoundedServerApplyCatchUpReplayProbe()
    let runtime = try await boundedServerApplyPeerRuntime(
      suffix: "continuous-peer-catch-up",
      cacheURL: cacheURL,
      onPrepared: { _ in
        await writer.writeBatchForPreparation()
        await barrier.pauseFirstPreparation()
      },
      onCatchUpReplayed: { replayCount, appendedBodyCount in
        await replayProbe.record(
          replayCount: replayCount,
          appendedBodyCount: appendedBodyCount
        )
        await writer.writeNextBatch(count: 1)
      }
    )
    await writer.install(peer)
    await runtime.persistence.resetServerApplyMetricsForTesting()

    let serverApply = Task { () -> InstantError? in
      do {
        _ = try await runtime.applyServerTransaction(
          boundedServerApplyServerWrite(
            entityID: "continuous-peer-root",
            id: "continuous-peer-server"
          )
        )
        return nil
      } catch let error as InstantError {
        return error
      } catch {
        Issue.record("Expected a structured bounded-fallback error, got: \(error)")
        return nil
      }
    }
    await barrier.waitUntilFirstPreparationPauses()

    let close = Task {
      try await runtime.closeConnection()
    }
    try await instantLiveWithTimeout(
      operation: "queue close behind the active server refresh",
      timeoutMilliseconds: 5_000,
      onAbandon: {
        serverApply.cancel()
        close.cancel()
        Task { await barrier.release() }
      }
    ) {
      while await runtime.serverApplyGateWaiterCountForTesting() == 0 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    await barrier.release()

    let closedStatus = try await instantLiveWithTimeout(
      operation: "close after bounded peer catch-up fallback",
      timeoutMilliseconds: 15_000,
      onAbandon: {
        serverApply.cancel()
        close.cancel()
      }
    ) {
      try await close.value
    }
    let applyError = try #require(await serverApply.value)

    expectNoDifference(closedStatus.state, .closed)
    expectNoDifference(applyError.code, .persistenceFailed)
    expectNoDifference(applyError.operation, "apply server transaction")
    expectNoDifference(applyError.localID, "continuous-peer-server")
    expectNoDifference(
      applyError.message,
      "The local store changed repeatedly while applying server transaction 'continuous-peer-server'."
    )
    let replayCounts = await replayProbe.replayCounts()
    let replayBodyCounts = await replayProbe.appendedBodyCounts()
    expectNoDifference(replayCounts, Array(repeating: [1, 2], count: 5).flatMap { $0 })
    expectNoDifference(replayBodyCounts, Array(repeating: 1, count: 10))
    let writeFailures = await writer.failures()
    let localMutationIDs = await writer.mutationIDs()
    expectNoDifference(writeFailures, [])
    expectNoDifference(localMutationIDs, (0..<15).map { "continuous-local-\($0)" })

    let durableState = try await runtime.persistence.loadState()
    expectNoDifference(durableState.snapshot.outbox.map(\.id), localMutationIDs)
    expectNoDifference(
      durableState.snapshot.store.triples.first(where: {
        $0.entityID == "continuous-peer-root"
      })?.value,
      .string("local-14")
    )
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.planCount, 5)
    expectNoDifference(metrics.commitAttemptCount, 0)
    expectNoDifference(metrics.staleCommitCount, 0)
    let serverApplyGateWaiterCount = await runtime.serverApplyGateWaiterCountForTesting()
    let operationGateWaiterCount = await runtime.operationGateWaiterCountForTesting()
    expectNoDifference(serverApplyGateWaiterCount, 0)
    expectNoDifference(operationGateWaiterCount, 0)
  }

  @Test
  func caughtUpRuleParamsKeepNoMaterializedEffectReceiptsAndAdvanceSequence() async throws {
    let writer = BoundedServerApplyRuleParamsWriter()
    let runtime = try await boundedServerApplyRuntime(
      suffix: "no-materialized-catch-up",
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: boundedServerApplyAttributes)
      ),
      onPrepared: { _ in
        await writer.writeOnce()
      }
    )
    await writer.install(runtime)
    await runtime.persistence.resetServerApplyMetricsForTesting()
    let sequenceBeforeApply = await runtime.store.currentSequence()

    _ = try await runtime.applyServerTransaction(
      boundedServerApplyServerWrite(
        entityID: "no-materialized-server-entity",
        id: "no-materialized-server"
      )
    )

    let writeFailureDescription = await writer.failureDescription()
    expectNoDifference(writeFailureDescription, nil)
    let recordedSequenceAfterWrites = await writer.recordedSequenceAfterWrites()
    let sequenceAfterLocalWrites = try #require(recordedSequenceAfterWrites)
    expectNoDifference(sequenceAfterLocalWrites, sequenceBeforeApply + 2)
    let sequenceAfterServerApply = await runtime.store.currentSequence()
    expectNoDifference(sequenceAfterServerApply, sequenceAfterLocalWrites + 1)

    let state = try await runtime.persistence.loadState()
    expectNoDifference(
      state.snapshot.outbox.map(\.id),
      ["catch-up-rule-params-0", "catch-up-rule-params-1"]
    )
    for mutation in state.snapshot.outbox {
      expectNoDifference(mutation.rollbackTransaction, nil)
      expectNoDifference(mutation.optimisticOverlayState, .applied)
      expectNoDifference(
        mutation.optimisticEffectReceiptVersion,
        PendingMutation.currentOptimisticEffectReceiptVersion
      )
      switch mutation.optimisticEffectReceipt {
      case .noCurrentMaterializedEffect:
        break
      case .unknown, .materialized:
        Issue.record("Expected rule params to retain a no-current-effect receipt.")
      }
    }
    expectNoDifference(
      state.snapshot.store.triples.first(where: {
        $0.entityID == "no-materialized-server-entity"
      })?.value,
      .string("server")
    )
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.planCount, 1)
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
  }

  @Test
  func emptyServerApplyAdoptsAnotherRuntimeLocalWriteIntoTheHotStore() async throws {
    let cacheURL = boundedServerApplyCacheURL("cross-runtime-empty-server")
    let peer = try await boundedServerApplyRuntime(
      suffix: "cross-runtime-empty-server",
      cacheURL: cacheURL,
      snapshot: InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: boundedServerApplyAttributes)
      )
    )
    let race = BoundedServerApplyRaceProbe()
    let runtime = try await boundedServerApplyPeerRuntime(
      suffix: "cross-runtime-empty-server",
      cacheURL: cacheURL,
      onPrepared: { _ in
        guard await race.claim() else { return }
        do {
          _ = try await peer.transact(
            InstantStoreTransaction(
              id: "cross-runtime-local",
              operations: [
                .insert(boundedServerApplyTriple(
                  entityID: "cross-runtime-local-entity",
                  value: "peer-local",
                  transactionID: "cross-runtime-local",
                  milliseconds: 1_000
                ))
              ]
            ),
            createdAt: InstantTimestamp(milliseconds: 1_000)
          )
        } catch {
          await race.record(error)
        }
      }
    )
    await runtime.persistence.resetServerApplyMetricsForTesting()
    let durableStateBeforeApply = try await runtime.persistence.loadState()
    let sequenceBeforeApply = await runtime.store.currentSequence()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(id: "cross-runtime-empty-server", operations: [])
    )

    let didRunRace = await race.didRun()
    let raceFailureDescription = await race.failureDescription()
    #expect(didRunRace)
    expectNoDifference(raceFailureDescription, nil)
    let expectedRebasedTriple = boundedServerApplyTriple(
      entityID: "cross-runtime-local-entity",
      value: "peer-local",
      transactionID: "cross-runtime-local",
      milliseconds: 1
    )
    let hotSnapshot = await runtime.store.snapshot()
    let hotTriple = try #require(hotSnapshot.triples.first(where: {
      $0.entityID == "cross-runtime-local-entity"
    }))
    expectNoDifference(hotTriple, expectedRebasedTriple)
    let sequenceAfterApply = await runtime.store.currentSequence()
    expectNoDifference(sequenceAfterApply, sequenceBeforeApply + 1)
    let durableState = try await runtime.persistence.loadState()
    expectNoDifference(durableState.snapshot.outbox.map(\.id), ["cross-runtime-local"])
    let durableTriple = try #require(durableState.snapshot.store.triples.first(where: {
      $0.entityID == "cross-runtime-local-entity"
    }))
    let durableMutation = try #require(durableState.snapshot.outbox.first)
    let durableMutationTriple = try #require(
      durableMutation.transaction.operations.compactMap(\.insertedTriple).first
    )
    expectNoDifference(durableTriple, expectedRebasedTriple)
    expectNoDifference(durableMutationTriple, expectedRebasedTriple)
    expectNoDifference(durableState.storeRevision, durableStateBeforeApply.storeRevision + 2)
    expectNoDifference(durableState.outboxRevision, durableStateBeforeApply.outboxRevision + 2)
    expectNoDifference(
      durableState.attributeRevision,
      durableStateBeforeApply.attributeRevision
    )
    let installedRevisions = runtime.installedStoreRevisionsForTesting()
    expectNoDifference(installedRevisions.store, durableState.storeRevision)
    expectNoDifference(installedRevisions.attributes, durableState.attributeRevision)

    let relaunched = try await boundedServerApplyPeerRuntime(
      suffix: "cross-runtime-empty-server-relaunch",
      cacheURL: cacheURL
    )
    let relaunchedHotSnapshot = await relaunched.store.snapshot()
    let relaunchedHotTriple = try #require(relaunchedHotSnapshot.triples.first(where: {
      $0.entityID == "cross-runtime-local-entity"
    }))
    let relaunchedDurableState = try await relaunched.persistence.loadState()
    expectNoDifference(relaunchedHotTriple, expectedRebasedTriple)
    expectNoDifference(relaunchedDurableState, durableState)
    let relaunchedInstalledRevisions = relaunched.installedStoreRevisionsForTesting()
    expectNoDifference(relaunchedInstalledRevisions.store, durableState.storeRevision)
    expectNoDifference(
      relaunchedInstalledRevisions.attributes,
      durableState.attributeRevision
    )
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.planCount, 1)
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
  }

  @Test
  func storeRevisionRaceRetriesThePlanBeforePublishing() async throws {
    let cacheURL = boundedServerApplyCacheURL("store-revision-race")
    let race = BoundedServerApplyRaceProbe()
    let mutation = boundedServerApplyMutation(
      id: "store-race-overlay",
      position: 1,
      entityID: "store-race-entity",
      before: "server-base",
      after: "local"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "store-revision-race",
      cacheURL: cacheURL,
      snapshot: boundedServerApplySnapshot(mutations: [mutation]),
      onPrepared: { _ in
        guard await race.claim() else { return }
        do {
          let writer = try SQLitePersistenceStore(fileURL: cacheURL)
          try await writer.bootstrap()
          let revision = Int64(
            try await writer.loadMetadataValue(key: "store_revision") ?? "0"
          ) ?? 0
          try await writer.saveMetadataValue(
            String(revision + 1),
            key: "store_revision",
            updatedAt: InstantTimestamp(milliseconds: 100)
          )
        } catch {
          await race.record(error)
        }
      }
    )
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      boundedServerApplyServerWrite(entityID: "store-race-entity", id: "store-race-server")
    )

    let didRunRace = await race.didRun()
    let raceFailureDescription = await race.failureDescription()
    #expect(didRunRace)
    expectNoDifference(raceFailureDescription, nil)
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
    expectNoDifference(metrics.planCount, 2)
  }

  @Test
  func rowRevisionAndStatusRaceRetriesAgainstTheAcceptedRow() async throws {
    let cacheURL = boundedServerApplyCacheURL("row-revision-race")
    let race = BoundedServerApplyRaceProbe()
    let mutation = boundedServerApplyMutation(
      id: "row-race-overlay",
      position: 1,
      entityID: "row-race-entity",
      before: "server-base",
      after: "local"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "row-revision-race",
      cacheURL: cacheURL,
      snapshot: boundedServerApplySnapshot(mutations: [mutation]),
      onPrepared: { _ in
        guard await race.claim() else { return }
        do {
          let writer = try SQLitePersistenceStore(fileURL: cacheURL)
          try await writer.bootstrap()
          let didClaim = try await writer.claimOutboxMutationWithoutHydrationForTesting(
            id: mutation.id,
            claimantID: "row-revision-race-runtime",
            claimToken: "row-revision-race-token",
            deadlineMilliseconds: 6_000
          )
          guard didClaim else {
            throw CancellationError()
          }
          let revision = try await writer.currentOutboxRevision()
          _ = try await writer.acceptOutboxMutation(
            id: mutation.id,
            serverTransactionID: "900",
            claimantID: "row-revision-race-runtime",
            claimToken: "row-revision-race-token",
            expectedOutboxRevision: revision
          )
        } catch {
          await race.record(error)
        }
      }
    )
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      boundedServerApplyServerWrite(entityID: "row-race-entity", id: "100"),
      processedTransactionID: "100"
    )

    let didRunRace = await race.didRun()
    let raceFailureDescription = await race.failureDescription()
    #expect(didRunRace)
    expectNoDifference(raceFailureDescription, nil)
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.commitAttemptCount, 1)
    expectNoDifference(metrics.staleCommitCount, 0)
    let state = try await runtime.persistence.loadState()
    let retained = try #require(state.snapshot.outbox.first)
    expectNoDifference(retained.status, .confirmed)
    expectNoDifference(retained.serverTransactionID, "900")
    #expect(retained.provesServerAcceptance)
  }

  @Test
  func componentClosureRaceRetriesAndIncludesTheNewlyConnectedRow() async throws {
    let cacheURL = boundedServerApplyCacheURL("component-closure-race")
    let race = BoundedServerApplyRaceProbe()
    let target = boundedServerApplyMutation(
      id: "closure-target",
      position: 1,
      entityID: "closure-entity",
      before: "target-base",
      after: "target-local"
    )
    let disjoint = boundedServerApplyMutation(
      id: "closure-disjoint",
      position: 2,
      entityID: "closure-disjoint-entity",
      before: "disjoint-base",
      after: "disjoint-local"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "component-closure-race",
      cacheURL: cacheURL,
      snapshot: boundedServerApplySnapshot(mutations: [target, disjoint]),
      onPrepared: { _ in
        guard await race.claim() else { return }
        do {
          try boundedServerApplyExecute(
            """
            INSERT OR REPLACE INTO instant_outbox_effect_entities (
              mutation_id, entity_id, created_at_ms
            ) VALUES ('closure-disjoint', 'closure-entity', 2);
            """,
            cacheURL: cacheURL
          )
        } catch {
          await race.record(error)
        }
      }
    )
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      boundedServerApplyServerWrite(entityID: "closure-entity", id: "closure-server")
    )

    let didRunRace = await race.didRun()
    let raceFailureDescription = await race.failureDescription()
    #expect(didRunRace)
    expectNoDifference(raceFailureDescription, nil)
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.commitAttemptCount, 2)
    expectNoDifference(metrics.staleCommitCount, 1)
    expectNoDifference(metrics.planCount, 2)
    expectNoDifference(metrics.plannedBodyCount, 3)
    let outboxMutationCount = try await runtime.persistence.countOutboxMutations()
    expectNoDifference(outboxMutationCount, 2)
  }

  @Test
  func validCatchUpAppendDoesNotHideAComponentClosureRace() async throws {
    let cacheURL = boundedServerApplyCacheURL("catch-up-plus-component-closure-race")
    let race = BoundedServerApplyRaceProbe()
    let writer = BoundedServerApplyConcurrentLocalWriter(
      rootEntityID: "catch-up-closure-entity",
      writesPerPreparation: 1,
      includesUniqueSegment: false
    )
    let target = boundedServerApplyMutation(
      id: "catch-up-closure-target",
      position: 1,
      entityID: "catch-up-closure-entity",
      before: "target-base",
      after: "target-local"
    )
    let disjoint = boundedServerApplyMutation(
      id: "catch-up-closure-disjoint",
      position: 2,
      entityID: "catch-up-closure-disjoint-entity",
      before: "disjoint-base",
      after: "disjoint-local"
    )
    let runtime = try await boundedServerApplyRuntime(
      suffix: "catch-up-plus-component-closure-race",
      cacheURL: cacheURL,
      snapshot: boundedServerApplySnapshot(mutations: [target, disjoint]),
      onPrepared: { _ in
        guard await race.claim() else { return }
        await writer.writeBatchForPreparation()
        do {
          try boundedServerApplyExecute(
            """
            INSERT OR REPLACE INTO instant_outbox_effect_entities (
              mutation_id, entity_id, created_at_ms
            ) VALUES ('catch-up-closure-disjoint', 'catch-up-closure-entity', 2);
            """,
            cacheURL: cacheURL
          )
        } catch {
          await race.record(error)
        }
      }
    )
    await writer.install(runtime)
    await runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await runtime.applyServerTransaction(
      boundedServerApplyServerWrite(
        entityID: "catch-up-closure-entity",
        id: "catch-up-closure-server"
      )
    )

    let didRunRace = await race.didRun()
    let raceFailureDescription = await race.failureDescription()
    let writeFailures = await writer.failures()
    let localMutationIDs = await writer.mutationIDs()
    #expect(didRunRace)
    expectNoDifference(raceFailureDescription, nil)
    expectNoDifference(writeFailures, [])
    expectNoDifference(localMutationIDs, ["continuous-local-0"])
    let state = try await runtime.persistence.loadState()
    expectNoDifference(
      state.snapshot.outbox.map(\.id),
      [
        "catch-up-closure-target",
        "catch-up-closure-disjoint",
        "continuous-local-0",
      ]
    )
    let appended = try #require(state.snapshot.outbox.first(where: {
      $0.id == "continuous-local-0"
    }))
    expectNoDifference(
      appended.rollbackTransaction?.operations.compactMap(\.insertedTriple).first(where: {
        $0.entityID == "catch-up-closure-entity"
      })?.value,
      .string("target-local")
    )
    expectNoDifference(
      state.snapshot.store.triples.first(where: {
        $0.entityID == "catch-up-closure-entity"
      })?.value,
      .string("local-0")
    )
    let metrics = await runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.commitAttemptCount, 2)
    expectNoDifference(metrics.staleCommitCount, 1)
    expectNoDifference(metrics.planCount, 2)
    expectNoDifference(metrics.plannedBodyCount, 4)
  }
}

private let boundedServerApplyAttributes = [
  InstantAttribute(
    id: "items/value",
    namespace: "items",
    name: "value",
    valueType: .string,
    isRequired: false
  )
]

private func boundedServerApplyRuntime(
  suffix: String,
  cacheURL providedCacheURL: URL? = nil,
  snapshot: InstantPersistenceSnapshot,
  deferredValueResidency: InstantDeferredValueResidencyPolicy = .none,
  onPrepared: (@Sendable (_ planID: String) async -> Void)? = nil,
  onCatchUpReplayedOutsideOperationGate:
    (@Sendable (_ appendedBodyCount: Int) async -> Void)? = nil,
  onCatchUpReplayed:
    (@Sendable (_ replayCount: Int, _ appendedBodyCount: Int) async -> Void)? = nil
) async throws -> InstantRuntime {
  let cacheURL = providedCacheURL ?? boundedServerApplyCacheURL(suffix)
  let persistence = try SQLitePersistenceStore(
    fileURL: cacheURL,
    deferredValueResidency: deferredValueResidency,
    declaredAttributes: boundedServerApplyAttributes
  )
  try await persistence.bootstrap()
  try await persistence.saveStoreSnapshot(snapshot.store)
  let seededStore = try await persistence.loadCompactState()
  let didSeedRuntimePreparedOutbox = try await persistence.saveOutbox(
    snapshot.outbox,
    replacing: [],
    metadataEntries: [],
    expectedStoreRevision: seededStore.storeRevision,
    expectedOutboxRevision: seededStore.outboxRevision
  )
  expectNoDifference(didSeedRuntimePreparedOutbox, true)
  var configuration = InstantRuntimeConfiguration(
    appID: "bounded-server-apply-\(suffix)",
    persistenceURL: cacheURL,
    initialAttributes: boundedServerApplyAttributes,
    deferredValueResidency: deferredValueResidency
  )
  configuration.onServerApplyPreparedBeforeCommitForTesting = onPrepared
  configuration.onServerApplyCatchUpReplayedOutsideOperationGateForTesting =
    onCatchUpReplayedOutsideOperationGate
  configuration.onServerApplyCatchUpReplayedForTesting = onCatchUpReplayed
  return try await InstantRuntime.bootstrap(
    configuration: configuration
  )
}

private func boundedServerApplyPeerRuntime(
  suffix: String,
  cacheURL: URL,
  onPrepared: (@Sendable (_ planID: String) async -> Void)? = nil,
  onCatchUpReplayed:
    (@Sendable (_ replayCount: Int, _ appendedBodyCount: Int) async -> Void)? = nil
) async throws -> InstantRuntime {
  var configuration = InstantRuntimeConfiguration(
    appID: "bounded-server-apply-\(suffix)",
    persistenceURL: cacheURL,
    initialAttributes: boundedServerApplyAttributes
  )
  configuration.onServerApplyPreparedBeforeCommitForTesting = onPrepared
  configuration.onServerApplyCatchUpReplayedForTesting = onCatchUpReplayed
  return try await InstantRuntime.bootstrap(configuration: configuration)
}

private func boundedServerApplyCacheURL(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "instant-bounded-server-apply-\(suffix)-\(UUID().uuidString).sqlite"
  )
}

private func boundedServerApplySnapshot(
  mutations: [PendingMutation]
) -> InstantPersistenceSnapshot {
  InstantPersistenceSnapshot(
    store: InstantStoreSnapshot(
      attributes: boundedServerApplyAttributes,
      triples: mutations.compactMap {
        $0.transaction.operations.compactMap(\.insertedTriple).first
      }
    ),
    outbox: mutations
  )
}

private struct BoundedServerApplyDurableAuthority: Equatable {
  var state: InstantPersistenceState
  var rowRevision: Int64
  var claim: InstantOutboxDeliveryClaim?
}

private func boundedDurableAuthority(
  persistence: SQLitePersistenceStore,
  mutationID: String
) async throws -> BoundedServerApplyDurableAuthority {
  let state = try await persistence.loadState()
  let rowRevision = try await persistence.outboxMutationRevisionForTesting(id: mutationID)
  let claim = try await persistence.outboxDeliveryClaimForTesting(id: mutationID)
  return BoundedServerApplyDurableAuthority(
    state: state,
    rowRevision: rowRevision,
    claim: claim
  )
}

private func boundedReadyServerApplyPlan(
  persistence: SQLitePersistenceStore,
  id: String,
  entityID: String
) async throws -> InstantServerApplyPlan {
  let load = try await persistence.beginServerApplyPlan(
    id: id,
    footprint: InstantServerApplyFootprint(entityIDs: [entityID], isGlobal: false),
    hasServerOperations: true,
    processedTransactionID: "\(id)-server",
    confirmingMutationID: nil,
    confirmingClaimantID: nil
  )
  switch load {
  case let .ready(plan):
    return plan
  case let .normalizationRequired(firstMutationID):
    Issue.record("Unexpected normalization blocker: \(firstMutationID)")
    throw CancellationError()
  }
}

private func boundedChangedWireMutation(
  _ mutation: PendingMutation,
  entityID: String,
  value: String
) -> PendingMutation {
  var mutation = mutation
  mutation.transaction = InstantStoreTransaction(
    id: mutation.transaction.id,
    operations: [
      .insert(boundedServerApplyTriple(
        entityID: entityID,
        value: value,
        transactionID: mutation.transaction.id,
        milliseconds: 100
      ))
    ]
  )
  return mutation
}

private func boundedServerApplyServerWrite(
  entityID: String,
  id: String
) -> InstantStoreTransaction {
  InstantStoreTransaction(
    id: id,
    operations: [
      .insert(boundedServerApplyTriple(
        entityID: entityID,
        value: "server",
        transactionID: id,
        milliseconds: 100
      ))
    ]
  )
}

private actor BoundedServerApplyRaceProbe {
  private var claimed = false
  private var recordedFailureDescription: String?

  func claim() -> Bool {
    guard !claimed else { return false }
    claimed = true
    return true
  }

  func record(_ error: Error) {
    recordedFailureDescription = String(describing: error)
  }

  func didRun() -> Bool {
    claimed
  }

  func failureDescription() -> String? {
    recordedFailureDescription
  }
}

private actor BoundedServerApplyPreparationBarrier {
  private var didPauseFirstPreparation = false
  private var isReleased = false
  private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func pauseFirstPreparation() async {
    guard !didPauseFirstPreparation else { return }
    didPauseFirstPreparation = true
    let pauseWaiters = self.pauseWaiters
    self.pauseWaiters.removeAll()
    for waiter in pauseWaiters { waiter.resume() }
    guard !isReleased else { return }
    await withCheckedContinuation { continuation in
      releaseWaiters.append(continuation)
    }
  }

  func waitUntilFirstPreparationPauses() async {
    guard !didPauseFirstPreparation else { return }
    await withCheckedContinuation { continuation in
      pauseWaiters.append(continuation)
    }
  }

  func release() {
    guard !isReleased else { return }
    isReleased = true
    let releaseWaiters = self.releaseWaiters
    self.releaseWaiters.removeAll()
    for waiter in releaseWaiters { waiter.resume() }
  }
}

private actor BoundedServerApplyConcurrentLocalWriter {
  private weak var runtime: InstantRuntime?
  private let rootEntityID: String
  private let writesPerPreparation: Int
  private let includesUniqueSegment: Bool
  private var nextIndex = 0
  private var writtenMutationIDs: [String] = []
  private var writeFailures: [String] = []

  init(
    rootEntityID: String,
    writesPerPreparation: Int,
    includesUniqueSegment: Bool = true
  ) {
    self.rootEntityID = rootEntityID
    self.writesPerPreparation = writesPerPreparation
    self.includesUniqueSegment = includesUniqueSegment
  }

  func install(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }

  func writeBatchForPreparation() async {
    await writeNextBatch(count: writesPerPreparation)
  }

  func writeNextBatch(count: Int) async {
    guard let runtime else {
      writeFailures.append("The Runtime was not installed before server preparation.")
      return
    }
    for _ in 0..<count {
      let index = nextIndex
      nextIndex += 1
      let mutationID = "continuous-local-\(index)"
      do {
        var operations: [InstantTripleOperation] = [
          .insert(boundedServerApplyTriple(
            entityID: rootEntityID,
            value: "local-\(index)",
            transactionID: mutationID,
            milliseconds: Int64(1_000 + index)
          ))
        ]
        if includesUniqueSegment {
          operations.append(
            .insert(boundedServerApplyTriple(
              entityID: "continuous-local-segment-\(index)",
              value: "segment-\(index)",
              transactionID: mutationID,
              milliseconds: Int64(1_000 + index)
            ))
          )
        }
        _ = try await runtime.transact(
          InstantStoreTransaction(
            id: mutationID,
            operations: operations
          ),
          createdAt: InstantTimestamp(milliseconds: Int64(1_000 + index))
        )
        writtenMutationIDs.append(mutationID)
      } catch {
        writeFailures.append("\(mutationID): \(error)")
      }
    }
  }

  func mutationIDs() -> [String] {
    writtenMutationIDs
  }

  func failures() -> [String] {
    writeFailures
  }
}

private actor BoundedServerApplyOutsideReplayProbe {
  private var appendedBodyCounts: [Int] = []

  func record(appendedBodyCount: Int) {
    appendedBodyCounts.append(appendedBodyCount)
  }

  func counts() -> [Int] {
    appendedBodyCounts
  }
}

private actor BoundedServerApplyCatchUpReplayProbe {
  private var recordedReplayCounts: [Int] = []
  private var recordedAppendedBodyCounts: [Int] = []

  func record(replayCount: Int, appendedBodyCount: Int) {
    recordedReplayCounts.append(replayCount)
    recordedAppendedBodyCounts.append(appendedBodyCount)
  }

  func replayCounts() -> [Int] {
    recordedReplayCounts
  }

  func appendedBodyCounts() -> [Int] {
    recordedAppendedBodyCounts
  }
}

private actor BoundedServerApplyRuleParamsWriter {
  private weak var runtime: InstantRuntime?
  private var didWrite = false
  private var recordedFailureDescription: String?
  private var sequenceAfterWrites: Int64?

  func install(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }

  func writeOnce() async {
    guard !didWrite else { return }
    didWrite = true
    guard let runtime else {
      recordedFailureDescription = "The Runtime was not installed before server preparation."
      return
    }
    do {
      for index in 0..<2 {
        let mutationID = "catch-up-rule-params-\(index)"
        _ = try await runtime.transact(
          InstantStoreTransaction(
            id: mutationID,
            operations: [
              .ruleParams(
                entityID: "catch-up-rule-entity-\(index)",
                namespace: "items",
                params: .object([:])
              )
            ]
          ),
          createdAt: InstantTimestamp(milliseconds: Int64(2_000 + index))
        )
      }
      sequenceAfterWrites = await runtime.store.currentSequence()
    } catch {
      recordedFailureDescription = String(describing: error)
    }
  }

  func failureDescription() -> String? {
    recordedFailureDescription
  }

  func recordedSequenceAfterWrites() -> Int64? {
    sequenceAfterWrites
  }
}

private func boundedServerApplyExecute(_ sql: String, cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(
    cacheURL.path,
    &database,
    SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
    nil
  ) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw NSError(
      domain: "InstantBoundedServerApplyRebaseTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Could not open the server-apply fixture."]
    )
  }
  defer { sqlite3_close(database) }
  var errorMessage: UnsafeMutablePointer<CChar>?
  guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
    defer { sqlite3_free(errorMessage) }
    throw NSError(
      domain: "InstantBoundedServerApplyRebaseTests",
      code: 2,
      userInfo: [
        NSLocalizedDescriptionKey: errorMessage.map { String(cString: $0) }
          ?? "Unknown SQLite fixture error."
      ]
    )
  }
}

private func boundedServerApplyMutationChain(
  count: Int,
  entityID: String,
  prefix: String
) -> [PendingMutation] {
  (0..<count).map { index in
    boundedServerApplyMutation(
      id: "\(prefix)-\(String(format: "%03d", index))",
      position: Int64(index),
      entityID: entityID,
      before: index == 0 ? "base" : "local-\(index - 1)",
      after: "local-\(index)"
    )
  }
}

private func boundedServerApplyMutation(
  id: String,
  position: Int64,
  entityID: String,
  before: String?,
  after: String,
  status: InstantMutationStatus = .pending
) -> PendingMutation {
  let write = boundedServerApplyTriple(
    entityID: entityID,
    value: after,
    transactionID: id,
    milliseconds: position + 1
  )
  var mutation = PendingMutation(
    id: id,
    createdAt: InstantTimestamp(milliseconds: position),
    transaction: InstantStoreTransaction(id: id, operations: [.insert(write)]),
    status: status,
    failureMessage: status == .failed ? "retained failure" : nil
  )
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-\(id)",
    operations: before.map { value in
      [
        .insert(boundedServerApplyTriple(
          entityID: entityID,
          value: value,
          transactionID: "rollback-\(id)",
          milliseconds: position + 1
        ))
      ]
    } ?? [.deleteEntity(entityID)]
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private func boundedServerApplyTriple(
  entityID: String,
  value: String,
  transactionID: String,
  milliseconds: Int64
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: "items/value",
    value: .string(value),
    txID: transactionID,
    txTime: InstantTimestamp(milliseconds: milliseconds)
  )
}

private extension InstantTripleOperation {
  var insertedTriple: InstantTriple? {
    guard case let .insert(triple) = self else { return nil }
    return triple
  }

  var deletedEntityID: String? {
    guard case let .deleteEntity(entityID) = self else { return nil }
    return entityID
  }
}
