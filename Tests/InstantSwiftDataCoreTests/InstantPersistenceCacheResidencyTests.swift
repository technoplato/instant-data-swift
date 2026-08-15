import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantPersistenceCacheResidencyTests {
  @Test
  func twoThousandOutboxAndQueryResultRevisionsDoNotReloadTheLargeStore() async throws {
    let cacheURL = try temporaryCacheResidencyURL("scalar-revisions")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: cacheResidencyAttributes,
        triples: cacheResidencyTriples(count: 10_000)
      )
    )
    var state = try await persistence.loadCompactState()
    await persistence.resetCacheResidencyMetricsForTesting()

    for index in 0..<2_000 {
      if index.isMultiple(of: 2) {
        let didSave = try await persistence.saveOutbox(
          [],
          replacing: [],
          expectedOutboxRevision: state.outboxRevision
        )
        expectNoDifference(didSave, true)
      } else {
        let result = InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(
            key: "query-\(index)",
            triples: [],
            pageInfo: nil
          ),
          updatedAt: InstantTimestamp(milliseconds: Int64(index))
        )
        let didSave = try await persistence.saveLiveRefresh(
          state.snapshot,
          queryResults: [result],
          storeChanged: false,
          outboxChanged: false,
          metadataKey: "cache-residency.watermark",
          metadataValue: String(index),
          metadataUpdatedAt: InstantTimestamp(milliseconds: Int64(index)),
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision,
          expectedAttributeRevision: state.attributeRevision
        )
        expectNoDifference(didSave, true)
      }
      state = try await persistence.loadCompactState()
    }

    let metrics = await persistence.cacheResidencyMetricsForTesting()
    expectNoDifference(
      metrics,
      InstantPersistenceCacheResidencyMetrics()
    )
    expectNoDifference(state.storeRevision, 1)
    expectNoDifference(state.attributeRevision, 1)
    expectNoDifference(state.outboxRevision, 1_000)
    expectNoDifference(state.queryResultRevision, 1_000)
  }

  @Test
  func automaticRetryWindowsDoNotInvalidateTheLargeStore() async throws {
    let cacheURL = try temporaryCacheResidencyURL("automatic-retry")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let mutations = (0..<101).map(cacheResidencyRetryableMutation(index:))
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: cacheResidencyAttributes,
        triples: cacheResidencyTriples(count: 10_000)
          + cacheResidencyInsertedTriples(in: mutations)
      )
    )
    try await saveRuntimePreparedCacheResidencyOutbox(mutations, to: persistence)
    _ = try await persistence.loadCompactState()
    await persistence.resetCacheResidencyMetricsForTesting()

    for expectedRetriedCount in [50, 50, 1] {
      let loadedApplication = try await persistence.retryAutomaticFailedMutationWindow(
        after: nil,
        excludingMutationIDs: []
      )
      let application = try #require(loadedApplication)
      expectNoDifference(application.retriedMutations.count, expectedRetriedCount)
      _ = try await persistence.loadCompactState()
    }

    let metrics = await persistence.cacheResidencyMetricsForTesting()
    expectNoDifference(metrics, InstantPersistenceCacheResidencyMetrics())
    let failedMutationCount = try await persistence.countOutboxMutations(status: .failed)
    let pendingMutationCount = try await persistence.countOutboxMutations(status: .pending)
    expectNoDifference(failedMutationCount, 0)
    expectNoDifference(pendingMutationCount, 101)
  }

  @Test
  func publicConfirmationAddressesOneOfTenThousandOutboxRows() async throws {
    let cacheURL = try temporaryCacheResidencyURL("public-confirmation")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: cacheResidencyAttributes,
        triples: cacheResidencyTriples(count: 10_000)
      )
    )
    try await persistence.saveOutbox(
      (0..<10_000).map(cacheResidencyPendingMutation(index:))
    )
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "cache-residency-public-confirmation",
        persistenceURL: cacheURL,
        initialAttributes: cacheResidencyAttributes
      )
    )
    let revisionsBeforeConfirmation = try await runtime.persistence.loadCompactState()
    let queueWideReadCountBeforeConfirmation =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    let targetRevisionBeforeConfirmation =
      try await runtime.persistence.outboxMutationRevisionForTesting(id: "confirm-05000")
    let neighborRevisionBeforeConfirmation =
      try await runtime.persistence.outboxMutationRevisionForTesting(id: "confirm-05001")
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.resetPersistenceCacheResidencyMetricsForTesting()

    let confirmed = try await runtime.confirmMutation(id: "confirm-05000")

    expectNoDifference(confirmed.id, "confirm-05000")
    expectNoDifference(confirmed.status, .confirmed)
    expectNoDifference(confirmed.confirmationSource, .manual)
    let decodedOutboxBodyCount = await runtime.persistence.currentDecodedOutboxBodyCount()
    let materializedOutboxBodyCount =
      await runtime.persistence.currentMaterializedOutboxBodyCount()
    let revisionsAfterConfirmation = try await runtime.persistence.loadCompactState()
    let queueWideReadCountAfterConfirmation =
      await runtime.persistence.localMutationQueueWideReadCountForTesting()
    let targetRevisionAfterConfirmation =
      try await runtime.persistence.outboxMutationRevisionForTesting(id: "confirm-05000")
    let neighborRevisionAfterConfirmation =
      try await runtime.persistence.outboxMutationRevisionForTesting(id: "confirm-05001")
    expectNoDifference(decodedOutboxBodyCount, 1)
    expectNoDifference(materializedOutboxBodyCount, 1)
    expectNoDifference(
      revisionsAfterConfirmation.storeRevision,
      revisionsBeforeConfirmation.storeRevision
    )
    expectNoDifference(
      revisionsAfterConfirmation.outboxRevision,
      revisionsBeforeConfirmation.outboxRevision + 1
    )
    expectNoDifference(
      queueWideReadCountAfterConfirmation,
      queueWideReadCountBeforeConfirmation
    )
    expectNoDifference(
      targetRevisionAfterConfirmation,
      targetRevisionBeforeConfirmation + 1
    )
    expectNoDifference(
      neighborRevisionAfterConfirmation,
      neighborRevisionBeforeConfirmation
    )
    let pendingMutationCount = try await runtime.persistence.countOutboxMutations(
      status: .pending
    )
    let confirmedMutationCount = try await runtime.persistence.countOutboxMutations(
      status: .confirmed
    )
    expectNoDifference(pendingMutationCount, 9_999)
    expectNoDifference(confirmedMutationCount, 1)
    let cacheMetrics = await runtime.persistenceCacheResidencyMetricsForTesting()
    expectNoDifference(cacheMetrics, InstantPersistenceCacheResidencyMetrics())
  }

  @Test
  func serverAndAttributeRefreshesStayResidentAndExternalStoreMutationReloadsOnce() async throws {
    let cacheURL = try temporaryCacheResidencyURL("runtime-adoption")
    let seed = try SQLitePersistenceStore(fileURL: cacheURL)
    try await seed.bootstrap()
    try await seed.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: cacheResidencyAttributes,
        triples: cacheResidencyTriples(count: 10_000)
      )
    )
    await seed.simulateUnexpectedConnectionCloseForTesting()

    let first = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "cache-residency-first",
        persistenceURL: cacheURL,
        initialAttributes: cacheResidencyAttributes
      )
    )
    await first.resetPersistenceCacheResidencyMetricsForTesting()

    for index in 0..<1_000 {
      _ = try await first.applyServerTransaction(
        InstantStoreTransaction(id: "metadata-only-\(index)", operations: []),
        processedTransactionID: "metadata-only-\(index)",
        receivedAt: InstantTimestamp(milliseconds: Int64(index))
      )
    }
    let metadataOnlyMetrics = await first.persistenceCacheResidencyMetricsForTesting()
    expectNoDifference(metadataOnlyMetrics, InstantPersistenceCacheResidencyMetrics())

    let internalRefreshTriple = InstantTriple(
      entityID: "internal-server-refresh",
      attributeID: "cache-residency/value",
      value: .string("internal"),
      txID: "internal-server-refresh",
      txTime: InstantTimestamp(milliseconds: 10_000)
    )
    _ = try await first.applyServerTransaction(
      InstantStoreTransaction(
        id: "internal-server-refresh",
        operations: [.insert(internalRefreshTriple)]
      ),
      processedTransactionID: "internal-server-refresh",
      receivedAt: InstantTimestamp(milliseconds: 10_000)
    )
    _ = try await first.persistedStoreAttributes()
    let internalRefreshMetrics = await first.persistenceCacheResidencyMetricsForTesting()
    expectNoDifference(internalRefreshMetrics, InstantPersistenceCacheResidencyMetrics())

    let attributeWriter = try SQLitePersistenceStore(fileURL: cacheURL)
    try await attributeWriter.bootstrap()
    let attributeWriterState = try await attributeWriter.loadState()
    var attributeOnlySnapshot = attributeWriterState.snapshot.store
    attributeOnlySnapshot.attributes.append(cacheResidencySecondaryAttribute)
    let didSaveAttributeOnlySnapshot = try await attributeWriter.saveStoreSnapshot(
      attributeOnlySnapshot,
      replacing: attributeWriterState.snapshot.store,
      expectedStoreRevision: attributeWriterState.storeRevision,
      expectedOutboxRevision: attributeWriterState.outboxRevision,
      expectedAttributeRevision: attributeWriterState.attributeRevision
    )
    expectNoDifference(didSaveAttributeOnlySnapshot, true)
    await attributeWriter.simulateUnexpectedConnectionCloseForTesting()

    let refreshedAttributes = try await first.persistedStoreAttributes()
    expectNoDifference(refreshedAttributes.contains(cacheResidencySecondaryAttribute), true)
    let attributeRefreshMetrics = await first.persistenceCacheResidencyMetricsForTesting()
    expectNoDifference(attributeRefreshMetrics, InstantPersistenceCacheResidencyMetrics())

    let second = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "cache-residency-second",
        persistenceURL: cacheURL,
        initialAttributes: cacheResidencyAttributes
      )
    )
    _ = try await second.transact(
      InstantStoreTransaction(
        id: "external-store-write",
        operations: [
          .insert(
            InstantTriple(
              entityID: "external-entity",
              attributeID: "cache-residency/value",
              value: .string("external"),
              txID: "external-store-write",
              txTime: InstantTimestamp(milliseconds: 20_000)
            )
          )
        ]
      )
    )

    _ = try await first.persistedStoreAttributes()
    _ = try await first.persistedStoreAttributes()
    let externalStoreRefreshMetrics = await first.persistenceCacheResidencyMetricsForTesting()
    expectNoDifference(
      externalStoreRefreshMetrics,
      InstantPersistenceCacheResidencyMetrics(
        fullStoreSnapshotLoadCount: 1,
        fullStateReconstructionCount: 1,
        storeSnapshotReplacementCount: 1
      )
    )
    let refreshedStoreSnapshot = await first.store.snapshot()
    let externalValue = refreshedStoreSnapshot.triples.first(where: {
      $0.entityID == "external-entity"
    })?.value
    expectNoDifference(
      externalValue,
      .string("external")
    )
  }

  @Test
  func directPersistenceInspectionCannotAdvancePastTheRuntimeStore() async throws {
    let cacheURL = try temporaryCacheResidencyURL("direct-inspection-runtime-lag")
    let seed = try SQLitePersistenceStore(fileURL: cacheURL)
    try await seed.bootstrap()
    try await seed.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: cacheResidencyAttributes,
        triples: cacheResidencyTriples(count: 10_000)
      )
    )
    await seed.simulateUnexpectedConnectionCloseForTesting()

    let reader = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "cache-residency-direct-reader",
        persistenceURL: cacheURL,
        initialAttributes: cacheResidencyAttributes
      )
    )
    let writer = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "cache-residency-direct-writer",
        persistenceURL: cacheURL,
        initialAttributes: cacheResidencyAttributes
      )
    )
    _ = try await writer.transact(
      InstantStoreTransaction(
        id: "direct-inspection-external-write",
        operations: [
          .insert(
            InstantTriple(
              entityID: "direct-inspection-external-entity",
              attributeID: "cache-residency/value",
              value: .string("external"),
              txID: "direct-inspection-external-write",
              txTime: InstantTimestamp(milliseconds: 40_000)
            )
          )
        ]
      )
    )

    let directlyInspected = try await reader.persistence.loadState()
    _ = try await writer.confirmMutation(id: "direct-inspection-external-write")
    let afterOutboxOnlyChange = try await writer.persistence.loadCompactState()
    expectNoDifference(
      afterOutboxOnlyChange.storeRevision,
      directlyInspected.storeRevision
    )
    expectNoDifference(
      afterOutboxOnlyChange.outboxRevision,
      directlyInspected.outboxRevision + 1
    )
    await reader.resetPersistenceCacheResidencyMetricsForTesting()

    let rows = try await reader.query(
      InstantQueryPlan(
        id: "cache-residency.direct-inspection-runtime-lag",
        namespace: "cache-residency",
        filters: [.equals(field: "value", value: .string("external"))],
        limit: 1
      )
    )
    #expect(rows.contains { $0.id == "direct-inspection-external-entity" })
    let metrics = await reader.persistenceCacheResidencyMetricsForTesting()
    expectNoDifference(
      metrics,
      InstantPersistenceCacheResidencyMetrics(
        fullStoreSnapshotLoadCount: 1,
        fullStateReconstructionCount: 1,
        storeSnapshotReplacementCount: 1
      )
    )
  }

  @Test
  func localMutationRejectsAnAttributeOnlyRevisionRace() async throws {
    let cacheURL = try temporaryCacheResidencyURL("local-mutation-attribute-race")
    let stalePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await stalePersistence.bootstrap()
    let staleState = try await stalePersistence.loadState()
    expectNoDifference(staleState.storeRevision, 0)
    expectNoDifference(staleState.attributeRevision, 0)
    expectNoDifference(staleState.outboxRevision, 0)

    let attributeWriter = try SQLitePersistenceStore(fileURL: cacheURL)
    try await attributeWriter.bootstrap()
    let attributeWriterState = try await attributeWriter.loadState()
    let didSaveAttribute = try await attributeWriter.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: cacheResidencyAttributes, triples: []),
      replacing: attributeWriterState.snapshot.store,
      expectedStoreRevision: attributeWriterState.storeRevision,
      expectedOutboxRevision: attributeWriterState.outboxRevision,
      expectedAttributeRevision: attributeWriterState.attributeRevision
    )
    expectNoDifference(didSaveAttribute, true)
    let afterAttributeWrite = try await attributeWriter.loadCompactState()
    expectNoDifference(afterAttributeWrite.storeRevision, 0)
    expectNoDifference(afterAttributeWrite.attributeRevision, 1)
    expectNoDifference(afterAttributeWrite.outboxRevision, 0)

    let mutation = cacheResidencyLocalMutation()
    let triples = mutation.transaction.operations.compactMap { operation -> InstantTriple? in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
    let entityID = try #require(triples.first?.entityID)
    let didSaveMutation = try await stalePersistence.saveLocalMutation(
      changedEntityTriples: [entityID: triples],
      pendingMutation: mutation,
      expectedStoreRevision: staleState.storeRevision,
      expectedAttributeRevision: staleState.attributeRevision,
      expectedOutboxRevision: staleState.outboxRevision
    )
    expectNoDifference(didSaveMutation, false)

    let reopened = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reopened.bootstrap()
    let finalState = try await reopened.loadState()
    expectNoDifference(finalState.storeRevision, 0)
    expectNoDifference(finalState.attributeRevision, 1)
    expectNoDifference(finalState.outboxRevision, 0)
    expectNoDifference(finalState.snapshot.store.attributes, cacheResidencyAttributes)
    expectNoDifference(finalState.snapshot.store.triples, [])
    expectNoDifference(finalState.snapshot.outbox, [])
  }

  @Test
  func fullSnapshotRejectsAnAttributeOnlyRevisionRace() async throws {
    let cacheURL = try temporaryCacheResidencyURL("full-snapshot-attribute-race")
    let stalePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await stalePersistence.bootstrap()
    let staleState = try await stalePersistence.loadState()
    expectNoDifference(staleState.storeRevision, 0)
    expectNoDifference(staleState.attributeRevision, 0)
    expectNoDifference(staleState.outboxRevision, 0)

    let attributeWriter = try SQLitePersistenceStore(fileURL: cacheURL)
    try await attributeWriter.bootstrap()
    let attributeWriterState = try await attributeWriter.loadState()
    let didSaveAttribute = try await attributeWriter.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: cacheResidencyAttributes, triples: []),
      replacing: attributeWriterState.snapshot.store,
      expectedStoreRevision: attributeWriterState.storeRevision,
      expectedOutboxRevision: attributeWriterState.outboxRevision,
      expectedAttributeRevision: attributeWriterState.attributeRevision
    )
    expectNoDifference(didSaveAttribute, true)
    let afterAttributeWrite = try await attributeWriter.loadCompactState()
    expectNoDifference(afterAttributeWrite.storeRevision, 0)
    expectNoDifference(afterAttributeWrite.attributeRevision, 1)
    expectNoDifference(afterAttributeWrite.outboxRevision, 0)

    let didSaveSnapshot = try await stalePersistence.saveSnapshot(
      staleState.snapshot,
      expectedStoreRevision: staleState.storeRevision,
      expectedAttributeRevision: staleState.attributeRevision,
      expectedOutboxRevision: staleState.outboxRevision
    )
    expectNoDifference(didSaveSnapshot, false)

    let reopened = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reopened.bootstrap()
    let finalState = try await reopened.loadState()
    expectNoDifference(finalState.storeRevision, 0)
    expectNoDifference(finalState.attributeRevision, 1)
    expectNoDifference(finalState.outboxRevision, 0)
    expectNoDifference(finalState.snapshot.store.attributes, cacheResidencyAttributes)
    expectNoDifference(finalState.snapshot.store.triples, [])
    expectNoDifference(finalState.snapshot.outbox, [])
  }

  @Test
  func terminalPreparationAndCommitRejectAnAttributeOnlyRevisionRace() async throws {
    let cacheURL = try temporaryCacheResidencyURL("terminal-attribute-race")
    let stalePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await stalePersistence.bootstrap()
    let mutation = cacheResidencyTerminalMutation()
    let initialState = try await stalePersistence.loadState()
    let materializedTriples = cacheResidencyInsertedTriples(in: [mutation])
    let didMaterialize = try await stalePersistence.saveStoreSnapshot(
      InstantStoreSnapshot(triples: materializedTriples),
      replacing: initialState.snapshot.store,
      expectedStoreRevision: initialState.storeRevision,
      expectedOutboxRevision: initialState.outboxRevision,
      expectedAttributeRevision: initialState.attributeRevision
    )
    expectNoDifference(didMaterialize, true)
    try await saveRuntimePreparedCacheResidencyOutbox([mutation], to: stalePersistence)
    let staleState = try await stalePersistence.loadCompactState()
    expectNoDifference(staleState.storeRevision, 1)
    expectNoDifference(staleState.attributeRevision, 0)
    expectNoDifference(staleState.outboxRevision, 1)
    let claimToken = "terminal-attribute-race-claim"
    let didClaim = try await stalePersistence.claimOutboxMutationWithoutHydrationForTesting(
      id: mutation.id,
      claimantID: "cache-residency-test",
      claimToken: claimToken,
      deadlineMilliseconds: 5_000
    )
    expectNoDifference(didClaim, true)
    let initialLoad = try await stalePersistence.loadClaimedTerminalFailureComponent(
      id: mutation.id,
      claimToken: claimToken,
      expectedStoreRevision: staleState.storeRevision,
      expectedAttributeRevision: staleState.attributeRevision
    )
    guard case let .ready(component) = initialLoad else {
      Issue.record("Expected the claimed terminal component to be ready before the race.")
      return
    }

    let attributeWriter = try SQLitePersistenceStore(fileURL: cacheURL)
    try await attributeWriter.bootstrap()
    let attributeWriterState = try await attributeWriter.loadState()
    let didSaveAttribute = try await attributeWriter.saveRuntimePreparedStoreSnapshot(
      InstantStoreSnapshot(
        attributes: cacheResidencyAttributes,
        triples: attributeWriterState.snapshot.store.triples
      ),
      replacing: attributeWriterState.snapshot.store,
      expectedStoreRevision: attributeWriterState.storeRevision,
      expectedOutboxRevision: attributeWriterState.outboxRevision,
      expectedAttributeRevision: attributeWriterState.attributeRevision
    )
    expectNoDifference(didSaveAttribute, true)
    let afterAttributeWrite = try await attributeWriter.loadCompactState()
    expectNoDifference(afterAttributeWrite.storeRevision, 1)
    expectNoDifference(afterAttributeWrite.attributeRevision, 1)
    expectNoDifference(afterAttributeWrite.outboxRevision, 1)

    await stalePersistence.resetDecodedOutboxBodyCount()
    let racedLoad = try await stalePersistence.loadClaimedTerminalFailureComponent(
      id: mutation.id,
      claimToken: claimToken,
      expectedStoreRevision: staleState.storeRevision,
      expectedAttributeRevision: staleState.attributeRevision
    )
    guard case .staleClaim = racedLoad else {
      Issue.record("Expected an attribute-only race to invalidate terminal preparation.")
      return
    }
    let decodedBodyCount = await stalePersistence.currentDecodedOutboxBodyCount()
    expectNoDifference(decodedBodyCount, 0)

    var failedMutation = component.target
    failedMutation.status = .failed
    failedMutation.failureMessage = "permission denied"
    failedMutation.failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "permission denied"
    )
    failedMutation.optimisticOverlayState = .removed
    failedMutation.rollbackTransaction = nil
    let commit = try await stalePersistence.commitClaimedTerminalFailure(
      targetID: mutation.id,
      claimToken: claimToken,
      expectedStoreRevision: component.expectedStoreRevision,
      expectedAttributeRevision: staleState.attributeRevision,
      expectedComponentRowRevisions: component.rowRevisions,
      expectedComponentIDs: component.ids,
      failedMutation: failedMutation,
      rebasedSuccessors: [],
      changedEntityTriples: [:],
      metadataEntries: []
    )
    #expect(commit == nil)

    let reopened = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reopened.bootstrap()
    let finalState = try await reopened.loadState()
    expectNoDifference(finalState.storeRevision, 1)
    expectNoDifference(finalState.attributeRevision, 1)
    expectNoDifference(finalState.outboxRevision, 1)
    expectNoDifference(finalState.snapshot.store.attributes, cacheResidencyAttributes)
    expectNoDifference(finalState.snapshot.store.triples, materializedTriples)
    expectNoDifference(finalState.snapshot.outbox.map(\.status), [.pending])
  }

  @Test
  func metadataStoreSnapshotRejectsAnAttributeOnlyRevisionRace() async throws {
    let cacheURL = try temporaryCacheResidencyURL("metadata-store-attribute-race")
    let stalePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await stalePersistence.bootstrap()
    let staleState = try await stalePersistence.loadState()

    let attributeWriter = try SQLitePersistenceStore(fileURL: cacheURL)
    try await attributeWriter.bootstrap()
    let attributeWriterState = try await attributeWriter.loadState()
    let didSaveAttribute = try await attributeWriter.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: cacheResidencyAttributes, triples: []),
      replacing: attributeWriterState.snapshot.store,
      expectedStoreRevision: attributeWriterState.storeRevision,
      expectedOutboxRevision: attributeWriterState.outboxRevision,
      expectedAttributeRevision: attributeWriterState.attributeRevision
    )
    expectNoDifference(didSaveAttribute, true)

    let metadataKey = "cache-residency.metadata-store-attribute-race"
    let didSaveStaleStore = try await stalePersistence.saveStoreSnapshot(
      staleState.snapshot.store,
      replacing: staleState.snapshot.store,
      metadataKey: metadataKey,
      metadataValue: "stale",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 70_001),
      expectedStoreRevision: staleState.storeRevision,
      expectedOutboxRevision: staleState.outboxRevision,
      expectedAttributeRevision: staleState.attributeRevision
    )
    expectNoDifference(didSaveStaleStore, false)

    let reopened = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reopened.bootstrap()
    let finalState = try await reopened.loadState()
    expectNoDifference(finalState.storeRevision, 0)
    expectNoDifference(finalState.attributeRevision, 1)
    expectNoDifference(finalState.outboxRevision, 0)
    expectNoDifference(finalState.snapshot.store.attributes, cacheResidencyAttributes)
    let metadataValue = try await reopened.loadMetadataValue(key: metadataKey)
    expectNoDifference(metadataValue, nil)
  }

  @Test
  func metadataStoreSnapshotTracksAnAttributeOnlyChangeInItsOwnRevisionDomain() async throws {
    let cacheURL = try temporaryCacheResidencyURL("metadata-store-attribute-only")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let state = try await persistence.loadState()

    let didSave = try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: cacheResidencyAttributes, triples: []),
      replacing: state.snapshot.store,
      metadataKey: "cache-residency.metadata-store-attribute-only",
      metadataValue: "saved",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 75_001),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)

    let loaded = try await persistence.loadStateWithSource()
    expectNoDifference(loaded.source, .memory)
    expectNoDifference(loaded.state.storeRevision, 0)
    expectNoDifference(loaded.state.attributeRevision, 1)
    expectNoDifference(loaded.state.outboxRevision, 0)
    expectNoDifference(loaded.state.snapshot.store.attributes, cacheResidencyAttributes)
  }

  @Test
  func queryOnlyLiveRefreshRejectsAnAttributeOnlyRevisionRace() async throws {
    let cacheURL = try temporaryCacheResidencyURL("live-refresh-attribute-race")
    let stalePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await stalePersistence.bootstrap()
    let staleState = try await stalePersistence.loadState()

    let attributeWriter = try SQLitePersistenceStore(fileURL: cacheURL)
    try await attributeWriter.bootstrap()
    let attributeWriterState = try await attributeWriter.loadState()
    let didSaveAttribute = try await attributeWriter.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: cacheResidencyAttributes, triples: []),
      replacing: attributeWriterState.snapshot.store,
      expectedStoreRevision: attributeWriterState.storeRevision,
      expectedOutboxRevision: attributeWriterState.outboxRevision,
      expectedAttributeRevision: attributeWriterState.attributeRevision
    )
    expectNoDifference(didSaveAttribute, true)

    let queryResult = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: "cache-residency.live-refresh-attribute-race",
        triples: [],
        pageInfo: nil
      ),
      updatedAt: InstantTimestamp(milliseconds: 80_001)
    )
    let metadataKey = "cache-residency.live-refresh-attribute-race"
    let didSaveRefresh = try await stalePersistence.saveLiveRefresh(
      staleState.snapshot,
      queryResults: [queryResult],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: metadataKey,
      metadataValue: "stale",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 80_001),
      expectedStoreRevision: staleState.storeRevision,
      expectedOutboxRevision: staleState.outboxRevision,
      expectedAttributeRevision: staleState.attributeRevision
    )
    expectNoDifference(didSaveRefresh, false)

    let reopened = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reopened.bootstrap()
    let finalState = try await reopened.loadState()
    expectNoDifference(finalState.storeRevision, 0)
    expectNoDifference(finalState.attributeRevision, 1)
    expectNoDifference(finalState.outboxRevision, 0)
    expectNoDifference(finalState.queryResultRevision, 0)
    let savedResult = try await reopened.liveQueryResult(key: queryResult.key)
    expectNoDifference(savedResult, nil)
    let metadataValue = try await reopened.loadMetadataValue(key: metadataKey)
    expectNoDifference(metadataValue, nil)
  }

  @Test
  func liveRefreshTracksAnAttributeOnlyChangeInItsOwnRevisionDomain() async throws {
    let cacheURL = try temporaryCacheResidencyURL("live-refresh-attribute-only")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let state = try await persistence.loadState()

    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: cacheResidencyAttributes, triples: [])
      ),
      queryResults: [],
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "cache-residency.live-refresh-attribute-only",
      metadataValue: "saved",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 90_001),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)

    let loaded = try await persistence.loadStateWithSource()
    expectNoDifference(loaded.source, .memory)
    expectNoDifference(loaded.state.storeRevision, 0)
    expectNoDifference(loaded.state.attributeRevision, 1)
    expectNoDifference(loaded.state.outboxRevision, 0)
    expectNoDifference(loaded.state.snapshot.store.attributes, cacheResidencyAttributes)
  }

  @Test
  func metadataSnapshotAdoptsExactDivergentRevisionCounters() async throws {
    let cacheURL = try temporaryCacheResidencyURL("metadata-snapshot-divergent-revisions")
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let seedTriples = cacheResidencyTriples(count: 2)
    let initialSnapshot = InstantPersistenceSnapshot(
      store: InstantStoreSnapshot(
        attributes: cacheResidencyAttributes,
        triples: [seedTriples[0]]
      )
    )
    try await persistence.saveSnapshot(initialSnapshot)
    var state = try await persistence.loadState()

    var storeWithExtraTriple = state.snapshot.store
    storeWithExtraTriple.triples.append(seedTriples[1])
    var didSave = try await persistence.saveStoreSnapshot(
      storeWithExtraTriple,
      replacing: state.snapshot.store,
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)
    state = try await persistence.loadState()
    didSave = try await persistence.saveStoreSnapshot(
      initialSnapshot.store,
      replacing: state.snapshot.store,
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)
    state = try await persistence.loadState()

    for index in 0..<4 {
      var nextStore = state.snapshot.store
      if index.isMultiple(of: 2) {
        nextStore.attributes.append(cacheResidencySecondaryAttribute)
      } else {
        nextStore.attributes.removeAll { $0.id == cacheResidencySecondaryAttribute.id }
      }
      didSave = try await persistence.saveStoreSnapshot(
        nextStore,
        replacing: state.snapshot.store,
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision,
        expectedAttributeRevision: state.attributeRevision
      )
      expectNoDifference(didSave, true)
      state = try await persistence.loadState()
    }

    for _ in 0..<6 {
      didSave = try await persistence.saveOutbox(
        state.snapshot.outbox,
        replacing: state.snapshot.outbox,
        expectedOutboxRevision: state.outboxRevision
      )
      expectNoDifference(didSave, true)
      state = try await persistence.loadState()
    }
    expectNoDifference(state.storeRevision, 3)
    expectNoDifference(state.attributeRevision, 5)
    expectNoDifference(state.outboxRevision, 7)
    expectNoDifference(state.snapshot, initialSnapshot)
    await persistence.resetCacheResidencyMetricsForTesting()

    didSave = try await persistence.saveSnapshot(
      state.snapshot,
      replacing: state.snapshot,
      metadataKey: "cache-residency.metadata-snapshot-divergent-revisions",
      metadataValue: "saved",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 100_001),
      expectedStoreRevision: state.storeRevision,
      expectedAttributeRevision: state.attributeRevision,
      expectedOutboxRevision: state.outboxRevision
    )
    expectNoDifference(didSave, true)

    let loaded = try await persistence.loadStateWithSource()
    expectNoDifference(loaded.source, .memory)
    expectNoDifference(loaded.state.storeRevision, 4)
    expectNoDifference(loaded.state.attributeRevision, 6)
    expectNoDifference(loaded.state.outboxRevision, 8)
    let metrics = await persistence.cacheResidencyMetricsForTesting()
    expectNoDifference(metrics, InstantPersistenceCacheResidencyMetrics())
  }
}

private let cacheResidencyAttributes = [
  InstantAttribute(
    id: "cache-residency/value",
    namespace: "cache-residency",
    name: "value",
    valueType: .string,
    cardinality: .one,
    isIndexed: true,
    isUnique: false
  )
]

private let cacheResidencySecondaryAttribute = InstantAttribute(
  id: "cache-residency/secondary",
  namespace: "cache-residency",
  name: "secondary",
  valueType: .string,
  cardinality: .one,
  isIndexed: false,
  isUnique: false
)

private func cacheResidencyTriples(count: Int) -> [InstantTriple] {
  (0..<count).map { index in
    InstantTriple(
      entityID: "large-entity-\(index)",
      attributeID: "cache-residency/value",
      value: .string("value-\(index)"),
      txID: "seed-\(index)",
      txTime: InstantTimestamp(milliseconds: Int64(index + 1))
    )
  }
}

private func cacheResidencyRetryableMutation(index: Int) -> PendingMutation {
  let id = String(format: "retry-%05d", index)
  let timestamp = InstantTimestamp(milliseconds: Int64(index + 20_001))
  let triple = InstantTriple(
    entityID: "retry-entity-\(index)",
    attributeID: "cache-residency/value",
    value: .string("retry-\(index)"),
    txID: id,
    txTime: timestamp
  )
  var mutation = PendingMutation(
    id: id,
    createdAt: timestamp,
    transaction: InstantStoreTransaction(id: id, operations: [.insert(triple)]),
    status: .failed,
    failureMessage: "service unavailable"
  )
  mutation.failure = InstantMutationFailure(
    code: PendingMutation.failureCode(message: "service unavailable"),
    message: "service unavailable"
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-\(id)",
    operations: [.retract(triple)]
  )
  return mutation
}

private func cacheResidencyInsertedTriples(
  in mutations: [PendingMutation]
) -> [InstantTriple] {
  mutations.flatMap { mutation in
    mutation.transaction.operations.compactMap { operation -> InstantTriple? in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
  }
}

private func saveRuntimePreparedCacheResidencyOutbox(
  _ mutations: [PendingMutation],
  to persistence: SQLitePersistenceStore
) async throws {
  let state = try await persistence.loadCompactState()
  let didSave = try await persistence.saveOutbox(
    mutations,
    replacing: [],
    metadataEntries: [],
    expectedStoreRevision: state.storeRevision,
    expectedOutboxRevision: state.outboxRevision
  )
  expectNoDifference(didSave, true)
}

private func cacheResidencyPendingMutation(index: Int) -> PendingMutation {
  let id = String(format: "confirm-%05d", index)
  let timestamp = InstantTimestamp(milliseconds: Int64(index + 30_001))
  var mutation = PendingMutation(
    id: id,
    createdAt: timestamp,
    transaction: InstantStoreTransaction(
      id: id,
      operations: [
        .insert(
          InstantTriple(
            entityID: "confirm-entity-\(index)",
            attributeID: "cache-residency/value",
            value: .string("confirm-\(index)"),
            txID: id,
            txTime: timestamp
          )
        )
      ]
    )
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private func cacheResidencyLocalMutation() -> PendingMutation {
  let timestamp = InstantTimestamp(milliseconds: 50_001)
  let triple = InstantTriple(
    entityID: "local-attribute-race-entity",
    attributeID: "cache-residency/value",
    value: .string("local"),
    txID: "local-attribute-race",
    txTime: timestamp
  )
  var mutation = PendingMutation(
    id: "local-attribute-race",
    createdAt: timestamp,
    transaction: InstantStoreTransaction(
      id: "local-attribute-race",
      operations: [.insert(triple)]
    )
  )
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-local-attribute-race",
    operations: [.retract(triple)]
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private func cacheResidencyTerminalMutation() -> PendingMutation {
  let timestamp = InstantTimestamp(milliseconds: 60_001)
  let triple = InstantTriple(
    entityID: "terminal-attribute-race-entity",
    attributeID: "cache-residency/value",
    value: .string("terminal"),
    txID: "terminal-attribute-race",
    txTime: timestamp
  )
  var mutation = PendingMutation(
    id: "terminal-attribute-race",
    createdAt: timestamp,
    transaction: InstantStoreTransaction(
      id: "terminal-attribute-race",
      operations: [.insert(triple)]
    )
  )
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-terminal-attribute-race",
    operations: [.retract(triple)]
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion =
    PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private func temporaryCacheResidencyURL(_ suffix: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "InstantPersistenceCacheResidencyTests-\(suffix)-\(UUID().uuidString)",
    isDirectory: true
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
