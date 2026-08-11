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
    accepted.status = .confirmed
    accepted.serverTransactionID = "41"
    accepted.confirmationSource = .webSocketTransactOK
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
    expectNoDifference(metrics.commitAttemptCount, 2)
    expectNoDifference(metrics.staleCommitCount, 1)
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
          let revision = try await writer.currentOutboxRevision()
          _ = try await writer.acceptOutboxMutation(
            id: mutation.id,
            serverTransactionID: "900",
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
    expectNoDifference(metrics.commitAttemptCount, 2)
    expectNoDifference(metrics.staleCommitCount, 1)
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
  onPrepared: (@Sendable (_ planID: String) async -> Void)? = nil
) async throws -> InstantRuntime {
  let cacheURL = providedCacheURL ?? boundedServerApplyCacheURL(suffix)
  let persistence = try SQLitePersistenceStore(
    fileURL: cacheURL,
    deferredValueResidency: deferredValueResidency,
    declaredAttributes: boundedServerApplyAttributes
  )
  try await persistence.bootstrap()
  try await persistence.saveSnapshot(snapshot)
  var configuration = InstantRuntimeConfiguration(
    appID: "bounded-server-apply-\(suffix)",
    persistenceURL: cacheURL,
    initialAttributes: boundedServerApplyAttributes,
    deferredValueResidency: deferredValueResidency
  )
  configuration.onServerApplyPreparedBeforeCommitForTesting = onPrepared
  return try await InstantRuntime.bootstrap(
    configuration: configuration
  )
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
}
