import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// Nested include limits must bound authoritative and persisted live-query triples (#044 / #155).
///
/// SQLite Data: `LIMIT 2` on a child join keeps two rows per parent.
/// TypeScript instaql applies nested limits client-side after Reactor constructs
/// the raw query store. This Swift-specific containment acts earlier because
/// Swift shares one authoritative hot store across every live query.
///
/// Swift `runtime.query` already returns two children (L1), but the observe path
/// used to apply every decoded child to the hot store before persistence trimmed
/// `instant_live_query_triples`. A Mac recordings list query with
/// `segments.$limit: 2` therefore materialized hundreds of historical segments.
///
/// Bound query inserts once in the live-refresh translator and use that exact
/// set for both authoritative operations and query-result replacement. Retain
/// the persistence save/load defense. Live `transact` is unchanged. Non-JSON
/// query keys stay unfiltered so existing prune tests keep their synthetic keys.
@Suite(.serialized)
struct InstantLiveQueryNestedLimitMemoryTests {
  private let childCount = 10
  private let nestedLimit = 2

  @Test
  func nestedLimitKeepsTwoNewestChildrenPerParent() {
    let fixture = NestedLimitFixture(childCount: childCount)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: fixture.queryKey,
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(
      retained,
      [fixture.recordingID, fixture.segmentID(8), fixture.segmentID(9)]
    )
    print("nested_limit_retained_entity_count: \(retained.count)")
  }

  @Test
  func nestedLimitFollowsRecordingIDStringWhenRefTriplesAreAbsent() {
    let fixture = NestedLimitFixture(childCount: childCount, childLink: .recordingID)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: fixture.queryKey,
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(
      retained,
      [fixture.recordingID, fixture.segmentID(8), fixture.segmentID(9)]
    )
  }

  @Test
  func nestedLimitIsPerParentNotGlobal() {
    let fixture = NestedLimitFixture(childCount: 10, recordingCount: 2)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: fixture.queryKey,
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(
      retained,
      [
        "recording-0",
        "recording-1",
        "recording-0-segment-8",
        "recording-0-segment-9",
        "recording-1-segment-8",
        "recording-1-segment-9",
      ]
    )
  }

  @Test
  func nonJSONQueryKeyKeepsEveryEntity() {
    let fixture = NestedLimitFixture(childCount: childCount)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: "query-active-page",
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(retained.count, childCount + 1)
  }

  @Test
  func translatorBoundsAuthoritativeOperationsAndReplacementToNewestTwoChildren() throws {
    let fixture = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))

    let translation = try fixture.translation(transactionID: "nested-limit-translation")
    let transactionTriples = translation.transaction.operations.compactMap(\.insertedTriple)
    let replacement = try #require(translation.queryResultReplacements.first)
    let expectedEntityIDs: Set<String> = [
      fixture.recordingID,
      fixture.segmentID(8),
      fixture.segmentID(9),
    ]

    expectNoDifference(Set(transactionTriples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(Set(replacement.triples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(transactionTriples, replacement.triples)
    expectNoDifference(transactionTriples.count, 8)
  }

  @Test
  func translatorAppliesNestedLimitPerParent() throws {
    let fixture = NestedLimitLiveRefreshFixture(
      recordingCount: 2,
      childIndices: Array(0..<childCount)
    )

    let translation = try fixture.translation(transactionID: "nested-limit-two-parents")
    let transactionTriples = translation.transaction.operations.compactMap(\.insertedTriple)
    let replacement = try #require(translation.queryResultReplacements.first)
    let expectedEntityIDs: Set<String> = [
      "recording-0",
      "recording-1",
      "recording-0-segment-8",
      "recording-0-segment-9",
      "recording-1-segment-8",
      "recording-1-segment-9",
    ]

    expectNoDifference(Set(transactionTriples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(Set(replacement.triples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(transactionTriples, replacement.triples)
    expectNoDifference(transactionTriples.count, 16)
  }

  @Test
  func translatorBoundsServerAttributeTriplesUsingOpaqueLocalAttributeMetadata() throws {
    let fixture = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))

    let translation = try InstantLiveRefreshTranslator.translate(
      fixture.serverIDRefresh(
        transactionID: "nested-limit-server-attribute-ids",
        childLink: .recordingID
      ),
      existingAttributes: NestedLimitLiveRefreshFixture.opaqueLocalAttributes,
      receivedAt: InstantTimestamp(milliseconds: 1)
    )
    let transactionTriples = translation.transaction.operations.compactMap(\.insertedTriple)
    let replacement = try #require(translation.queryResultReplacements.first)
    let expectedEntityIDs: Set<String> = [
      fixture.recordingID,
      fixture.segmentID(8),
      fixture.segmentID(9),
    ]
    let expectedLocalAttributeIDs: Set<String> = [
      "local-recording-id",
      "local-recording-updated-at",
      "local-segment-id",
      "local-segment-recording-id",
      "local-segment-index",
    ]

    expectNoDifference(Set(transactionTriples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(Set(replacement.triples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(transactionTriples, replacement.triples)
    expectNoDifference(Set(transactionTriples.map(\.attributeID)), expectedLocalAttributeIDs)
  }

  @Test
  func translatorLeavesUnboundedAndNonQueryComputationsUnchanged() throws {
    let fixture = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))

    let unbounded = try fixture.translation(
      transactionID: "nested-limit-unbounded",
      query: fixture.query(nestedLimit: nil)
    )
    let unboundedTriples = unbounded.transaction.operations.compactMap(\.insertedTriple)
    expectNoDifference(Set(unboundedTriples.map(\.entityID)).count, childCount + 1)
    let unboundedReplacement = try #require(unbounded.queryResultReplacements.first)
    expectNoDifference(unboundedReplacement.triples, unboundedTriples)

    let nonQuery = try fixture.translation(
      transactionID: "nested-limit-non-query",
      includesQuery: false
    )
    let nonQueryTriples = nonQuery.transaction.operations.compactMap(\.insertedTriple)
    expectNoDifference(Set(nonQueryTriples.map(\.entityID)).count, childCount + 1)
    expectNoDifference(nonQuery.queryResultReplacements.count, 0)
  }

  @Test
  func sequentialRefreshRetractsDepartingChildAndPlateausAtRootPlusTwo() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("sequential-window")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-limit-sequential-window",
        persistenceURL: cacheURL,
        initialAttributes: NestedLimitLiveRefreshFixture.attributes
      )
    )
    var maximumTripleCount = 0

    for offset in 0..<12 {
      let fixture = NestedLimitLiveRefreshFixture(
        childIndices: Array(offset..<(offset + childCount))
      )
      _ = try await runtime.applyLiveRefresh(
        fixture.refresh(transactionID: "nested-limit-window-\(offset)")
      )
      let snapshot = await runtime.store.snapshot()
      maximumTripleCount = max(maximumTripleCount, snapshot.triples.count)
      expectNoDifference(
        Set(snapshot.triples.map(\.entityID)),
        [fixture.recordingID, fixture.segmentID(offset + 8), fixture.segmentID(offset + 9)]
      )
    }

    expectNoDifference(maximumTripleCount, 8)
  }

  @Test
  func repeatedLargeReplacementMutatesOnlyChangedOwnershipIdentities() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("ownership-diff")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let attribute = InstantAttribute.primaryKey(namespace: "recordings")
    let queryKey =
      """
      {"recordings":{"$":{"limit":1000,"order":{"updatedAtMs":"desc"}}}}
      """
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: [attribute])
    )

    func triples(
      range: Range<Int>,
      transactionID: String,
      milliseconds: Int64
    ) -> [InstantTriple] {
      range.map { index in
        InstantTriple(
          entityID: String(format: "recording-%04d", index),
          attributeID: attribute.id,
          value: .string(String(format: "recording-%04d", index)),
          txID: transactionID,
          txTime: InstantTimestamp(milliseconds: milliseconds)
        )
      }
    }

    func result(
      _ triples: [InstantTriple],
      milliseconds: Int64
    ) -> InstantPersistedLiveQueryResult {
      InstantPersistedLiveQueryResult(
        replacement: InstantLiveQueryResultReplacement(
          key: queryKey,
          triples: triples,
          pageInfo: nil
        ),
        updatedAt: InstantTimestamp(milliseconds: milliseconds)
      )
    }

    var state = try await persistence.loadCompactState()
    let initialTriples = triples(
      range: 0..<772,
      transactionID: "ownership-initial",
      milliseconds: 1
    )
    let initialSaved = try await persistence.saveLiveRefresh(
      state.snapshot,
      queryResults: [result(initialTriples, milliseconds: 1)],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "ownership-diff-watermark",
      metadataValue: "initial",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 1),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(initialSaved, true)
    try installLiveQueryOwnershipMutationCounter(at: cacheURL)

    state = try await persistence.loadCompactState()
    let replayTriples = triples(
      range: 0..<772,
      transactionID: "ownership-replay",
      milliseconds: 2
    )
    let replaySaved = try await persistence.saveLiveRefresh(
      state.snapshot,
      queryResults: [result(replayTriples, milliseconds: 2)],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "ownership-diff-watermark",
      metadataValue: "replay",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 2),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(replaySaved, true)
    expectNoDifference(
      try liveQueryOwnershipMutationCounts(at: cacheURL),
      LiveQueryOwnershipMutationCounts(inserted: 0, deleted: 0, updated: 0)
    )
    let replayPersistedValue = try await persistence.liveQueryResult(key: queryKey)
    let replayPersisted = try #require(replayPersistedValue)
    expectNoDifference(replayPersisted, result(replayTriples, milliseconds: 2))

    try resetLiveQueryOwnershipMutationCounter(at: cacheURL)
    state = try await persistence.loadCompactState()
    let changedTriples = Array(replayTriples.dropFirst())
      + triples(
        range: 772..<773,
        transactionID: "ownership-changed",
        milliseconds: 3
      )
    let changedSaved = try await persistence.saveLiveRefresh(
      state.snapshot,
      queryResults: [result(changedTriples, milliseconds: 3)],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "ownership-diff-watermark",
      metadataValue: "changed",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 3),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(changedSaved, true)
    expectNoDifference(
      try liveQueryOwnershipMutationCounts(at: cacheURL),
      LiveQueryOwnershipMutationCounts(inserted: 1, deleted: 1, updated: 0)
    )
    let persistedValue = try await persistence.liveQueryResult(key: queryKey)
    let persisted = try #require(persistedValue)
    expectNoDifference(persisted, result(changedTriples, milliseconds: 3))
    let ownershipEncoder = JSONEncoder()
    let expectedOwnership = try Set(
      changedTriples.map { triple in
        TestLiveQueryOwnershipIdentity(
          queryKey: queryKey,
          entityID: triple.entityID,
          attributeID: triple.attributeID,
          valueJSON: try #require(
            String(data: ownershipEncoder.encode(triple.value), encoding: .utf8)
          )
        )
      }
    )
    expectNoDifference(try liveQueryOwnership(at: cacheURL), expectedOwnership)

    let relaunched = try SQLitePersistenceStore(fileURL: cacheURL)
    try await relaunched.bootstrap()
    let relaunchedValue = try await relaunched.liveQueryResult(key: queryKey)
    let relaunchedResult = try #require(relaunchedValue)
    expectNoDifference(relaunchedResult, persisted)
  }

  @Test
  func repeatedScribeShapedRefreshInvalidatesOnlyTheChangedSegment() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("semantic-noop-refresh")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-limit-semantic-noop-refresh",
        persistenceURL: cacheURL,
        initialAttributes: NestedLimitLiveRefreshFixture.attributes
      )
    )
    let fixture = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))
    let queryKey = try InstantLiveQueryEncoder.registrationKey(for: fixture.query())
    let observation = await runtime.store.observeLiveQueryLease(
      fixture.plan(),
      registrationKey: queryKey,
      remotePageInfo: .waiting
    )
    let recorder = NestedLimitEmissionRecorder()
    let observationTask = Task {
      for await emission in observation.stream {
        await recorder.append(emission)
      }
    }
    defer { observationTask.cancel() }
    let emptyInitial = try await nestedLimitEmission(
      from: recorder,
      at: 0,
      operation: "await Scribe-shaped initial emission"
    )
    expectNoDifference(emptyInitial.values, [])

    let initial = try await runtime.applyLiveRefresh(
      fixture.refresh(transactionID: "semantic-noop-refresh-initial"),
      receivedAt: InstantTimestamp(milliseconds: 1)
    )
    expectNoDifference(
      initial.application.mutation.changedEntityIDs,
      [fixture.recordingID, fixture.segmentID(8), fixture.segmentID(9)]
    )
    let initialEmission = try await nestedLimitEmission(
      from: recorder,
      at: 1,
      operation: "await initial Scribe-shaped refresh emission"
    )
    expectNoDifference(initial.application.mutation.emissions, [initialEmission])

    let replay = try await runtime.applyLiveRefresh(
      fixture.refresh(transactionID: "semantic-noop-refresh-replay"),
      receivedAt: InstantTimestamp(milliseconds: 2)
    )
    expectNoDifference(replay.insertedTripleCount, 8)
    expectNoDifference(replay.application.mutation.changedEntityIDs, [])
    expectNoDifference(
      replay.application.syncState.processedTransactionID,
      "semantic-noop-refresh-replay"
    )
    expectNoDifference(replay.application.mutation.emissions, [])
    let replayMetrics = await runtime.store.lastPublishMetrics
    expectNoDifference(replayMetrics.rematerializedObserverCount, 0)
    expectNoDifference(replayMetrics.materializedSnapshotCount, 0)

    // If the identical replay leaked an emission, the recorder's fixed indexes and final count
    // make the changed-segment assertions below fail deterministically.
    let changed = try await runtime.applyLiveRefresh(
      fixture.refresh(
        transactionID: "semantic-noop-refresh-changed",
        segmentIndexOverrides: [9: 9.5]
      ),
      receivedAt: InstantTimestamp(milliseconds: 3)
    )
    expectNoDifference(changed.application.mutation.changedEntityIDs, [fixture.segmentID(9)])
    expectNoDifference(
      changed.application.syncState.processedTransactionID,
      "semantic-noop-refresh-changed"
    )
    let changedEmission = try await nestedLimitEmission(
      from: recorder,
      at: 2,
      operation: "await changed Scribe segment emission"
    )
    expectNoDifference(changed.application.mutation.emissions, [changedEmission])
    let changedSegment = try #require(
      changedEmission.values.first?.links?["segments"]?.first {
        $0.id == fixture.segmentID(9)
      }
    )
    expectNoDifference(
      changedSegment.values[NestedLimitLiveRefreshFixture.segmentIndexAttribute.name]?.first,
      .number(9.5)
    )

    let firstPageInfo = try await runtime.applyLiveRefresh(
      fixture.refresh(
        transactionID: "semantic-noop-page-info-first",
        segmentIndexOverrides: [9: 9.5],
        pageInfoHasNextPage: true
      ),
      receivedAt: InstantTimestamp(milliseconds: 4)
    )
    expectNoDifference(firstPageInfo.application.mutation.changedEntityIDs, [])
    let firstPageInfoEmission = try await nestedLimitEmission(
      from: recorder,
      at: 3,
      operation: "await page-info-only Scribe emission"
    )
    expectNoDifference(firstPageInfoEmission.pageInfo?.hasNextPage, true)
    expectNoDifference(firstPageInfo.application.mutation.emissions, [firstPageInfoEmission])

    let unchangedPageInfo = try await runtime.applyLiveRefresh(
      fixture.refresh(
        transactionID: "semantic-noop-page-info-replay",
        segmentIndexOverrides: [9: 9.5],
        pageInfoHasNextPage: true
      ),
      receivedAt: InstantTimestamp(milliseconds: 5)
    )
    expectNoDifference(unchangedPageInfo.application.mutation.changedEntityIDs, [])
    expectNoDifference(unchangedPageInfo.application.mutation.emissions, [])
    let unchangedPageInfoMetrics = await runtime.store.lastPublishMetrics
    expectNoDifference(unchangedPageInfoMetrics.rematerializedObserverCount, 0)
    expectNoDifference(unchangedPageInfoMetrics.materializedSnapshotCount, 0)

    // A second real page-info change proves the unchanged replay did not enqueue a stream value.
    let secondPageInfo = try await runtime.applyLiveRefresh(
      fixture.refresh(
        transactionID: "semantic-noop-page-info-second",
        segmentIndexOverrides: [9: 9.5],
        pageInfoHasNextPage: false
      ),
      receivedAt: InstantTimestamp(milliseconds: 6)
    )
    let secondPageInfoEmission = try await nestedLimitEmission(
      from: recorder,
      at: 4,
      operation: "await second page-info-only Scribe emission"
    )
    expectNoDifference(secondPageInfoEmission.pageInfo?.hasNextPage, false)
    expectNoDifference(secondPageInfo.application.mutation.emissions, [secondPageInfoEmission])

    let replacement = try #require(
      try await runtime.persistence.liveQueryResult(key: queryKey)
    )
    let changedIndex = try #require(
      replacement.triples.first {
        $0.entityID == fixture.segmentID(9)
          && $0.attributeID == NestedLimitLiveRefreshFixture.segmentIndexAttribute.id
      }
    )
    expectNoDifference(changedIndex.value, .number(9.5))
    expectNoDifference(replacement.pageInfo, secondPageInfoEmission.pageInfo)
    let emissionCount = await recorder.count()
    expectNoDifference(emissionCount, 5)
    await observation.cancel()
  }

  @Test
  func departingChildStaysWhileAnotherLiveQueryOwnsIt() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("overlapping-owner")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-limit-overlapping-owner",
        persistenceURL: cacheURL,
        initialAttributes: NestedLimitLiveRefreshFixture.attributes
      )
    )
    let first = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))
    let segmentOwnerQuery = first.segmentQuery()
    _ = try await runtime.applyLiveRefresh(
      first.refresh(
        transactionID: "nested-limit-overlap-first",
        additionalComputations: [
          first.segmentsOnlyComputation(query: segmentOwnerQuery, indices: [8])
        ]
      )
    )

    let shifted = NestedLimitLiveRefreshFixture(childIndices: Array(1...childCount))
    _ = try await runtime.applyLiveRefresh(
      shifted.refresh(transactionID: "nested-limit-overlap-shift")
    )
    let snapshot = await runtime.store.snapshot()

    expectNoDifference(
      Set(snapshot.triples.map(\.entityID)),
      [
        shifted.recordingID,
        shifted.segmentID(8),
        shifted.segmentID(9),
        shifted.segmentID(10),
      ]
    )
  }

  @Test
  func departingChildStaysWhilePendingOptimisticMutationOwnsIt() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("pending-owner")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-limit-pending-owner",
        persistenceURL: cacheURL,
        initialAttributes: NestedLimitLiveRefreshFixture.attributes
      )
    )
    let first = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))
    _ = try await runtime.applyLiveRefresh(
      first.refresh(transactionID: "nested-limit-pending-first")
    )
    let pendingAt = InstantTimestamp(milliseconds: 2)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "nested-limit-pending-child",
        operations: [
          .insert(
            InstantTriple(
              entityID: first.segmentID(8),
              attributeID: NestedLimitLiveRefreshFixture.segmentIndexAttribute.id,
              value: .number(8),
              txID: "nested-limit-pending-child",
              txTime: pendingAt
            )
          )
        ]
      ),
      createdAt: pendingAt
    )

    let shifted = NestedLimitLiveRefreshFixture(childIndices: Array(1...childCount))
    _ = try await runtime.applyLiveRefresh(
      shifted.refresh(transactionID: "nested-limit-pending-shift")
    )
    let snapshot = await runtime.store.snapshot()
    let protectedChildTriples = snapshot.triples.filter { $0.entityID == first.segmentID(8) }

    expectNoDifference(
      Set(protectedChildTriples.map(\.attributeID)),
      [
        NestedLimitLiveRefreshFixture.segmentIDAttribute.id,
        NestedLimitLiveRefreshFixture.segmentRecordingAttribute.id,
        NestedLimitLiveRefreshFixture.segmentIndexAttribute.id,
      ]
    )
    let pendingMutationIDs = await runtime.pendingMutations().map(\.id)
    expectNoDifference(pendingMutationIDs, ["nested-limit-pending-child"])
  }

  @Test
  func bootstrapLoadsOnlyTheLimitedLiveQueryPage() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("scoped-nested")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let fixture = NestedLimitFixture(childCount: childCount)

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: fixture.attributes, triples: fixture.allTriples)
    )
    let state = try await persistence.loadCompactState()
    let now = InstantTimestamp(milliseconds: 1)
    let didSave = try await persistence.saveLiveRefresh(
      state.snapshot,
      queryResults: [
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(
            key: fixture.queryKey,
            triples: fixture.allTriples,
            pageInfo: nil
          ),
          updatedAt: now
        )
      ],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "nested-limit.watermark",
      metadataValue: "bloated-observe",
      metadataUpdatedAt: now,
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)

    let reloaded = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reloaded.bootstrap()
    let loaded = try await reloaded.loadCompactState()
    let hotEntityIDs = Set(loaded.snapshot.store.triples.map(\.entityID))
    expectNoDifference(hotEntityIDs.count, 1 + nestedLimit)
    expectNoDifference(
      hotEntityIDs,
      [fixture.recordingID, fixture.segmentID(8), fixture.segmentID(9)]
    )
    let storedCount = try await reloaded.storedTripleEntityCountForTesting()
    expectNoDifference(storedCount, childCount + 1)
    print("nested_limit_hot_store_entity_count: \(hotEntityIDs.count)")
    print("sqlite_entity_count: \(storedCount)")
  }
}

private struct NestedLimitLiveRefreshFixture {
  private struct WireAttributeIDs {
    var recordingID: String
    var recordingUpdatedAt: String
    var segmentID: String
    var segmentRecording: String
    var segmentRecordingID: String
    var segmentIndex: String

    static let local = Self(
      recordingID: NestedLimitLiveRefreshFixture.recordingIDAttribute.id,
      recordingUpdatedAt: NestedLimitLiveRefreshFixture.recordingUpdatedAtAttribute.id,
      segmentID: NestedLimitLiveRefreshFixture.segmentIDAttribute.id,
      segmentRecording: NestedLimitLiveRefreshFixture.segmentRecordingAttribute.id,
      segmentRecordingID: NestedLimitLiveRefreshFixture.segmentRecordingIDAttribute.id,
      segmentIndex: NestedLimitLiveRefreshFixture.segmentIndexAttribute.id
    )
    static let server = Self(
      recordingID: "server-recordings-id",
      recordingUpdatedAt: "server-recordings-updated-at",
      segmentID: "server-segments-id",
      segmentRecording: "server-segments-recording",
      segmentRecordingID: "server-segments-recording-id",
      segmentIndex: "server-segments-index"
    )
  }

  enum ChildLink {
    case recording
    case recordingID
  }

  let recordingCount: Int
  let childIndices: [Int]
  let recordingID = "recording-a"

  init(recordingCount: Int = 1, childIndices: [Int]) {
    self.recordingCount = recordingCount
    self.childIndices = childIndices
  }

  static let recordingIDAttribute = InstantAttribute.primaryKey(namespace: "recordings")
  static let recordingUpdatedAtAttribute = InstantAttribute(
    id: "recordings/updatedAtMs",
    namespace: "recordings",
    name: "updatedAtMs",
    valueType: .number,
    isIndexed: true
  )
  static let segmentIDAttribute = InstantAttribute.primaryKey(
    namespace: "transcriptionSegments"
  )
  static let segmentRecordingAttribute = InstantAttribute(
    id: "transcriptionSegments/recording",
    namespace: "transcriptionSegments",
    name: "recording",
    valueType: .ref,
    cardinality: .one,
    isIndexed: true,
    forwardIdentity: "transcriptionSegments/recording",
    reverseIdentity: "recordings/segments",
    linkNamespace: "recordings"
  )
  static let segmentIndexAttribute = InstantAttribute(
    id: "transcriptionSegments/segmentIndex",
    namespace: "transcriptionSegments",
    name: "segmentIndex",
    valueType: .number,
    isIndexed: true
  )
  static let segmentRecordingIDAttribute = InstantAttribute(
    id: "transcriptionSegments/recordingID",
    namespace: "transcriptionSegments",
    name: "recordingID",
    valueType: .string,
    isIndexed: true
  )

  static var attributes: [InstantAttribute] {
    [
      recordingIDAttribute,
      recordingUpdatedAtAttribute,
      segmentIDAttribute,
      segmentRecordingAttribute,
      segmentRecordingIDAttribute,
      segmentIndexAttribute,
    ]
  }

  static var opaqueLocalAttributes: [InstantAttribute] {
    [
      InstantAttribute(
        id: "local-recording-id",
        namespace: "recordings",
        name: "id",
        valueType: .string,
        primaryKey: true
      ),
      InstantAttribute(
        id: "local-recording-updated-at",
        namespace: "recordings",
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "local-segment-id",
        namespace: "transcriptionSegments",
        name: "id",
        valueType: .string,
        primaryKey: true
      ),
      InstantAttribute(
        id: "local-segment-recording",
        namespace: "transcriptionSegments",
        name: "recording",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "transcriptionSegments/recording",
        reverseIdentity: "recordings/segments",
        linkNamespace: "recordings"
      ),
      InstantAttribute(
        id: "local-segment-recording-id",
        namespace: "transcriptionSegments",
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "local-segment-index",
        namespace: "transcriptionSegments",
        name: "segmentIndex",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }

  var recordingIDs: [String] {
    recordingCount == 1
      ? [recordingID]
      : (0..<recordingCount).map { "recording-\($0)" }
  }

  func segmentID(_ index: Int, recordingID: String? = nil) -> String {
    let recordingID = recordingID ?? self.recordingID
    return recordingCount == 1 ? "segment-\(index)" : "\(recordingID)-segment-\(index)"
  }

  func query(nestedLimit: Int? = 2) -> InstantLiveJSONValue {
    var segmentOptions: [String: InstantLiveJSONValue] = [
      "order": .object(["segmentIndex": .string("desc")])
    ]
    if let nestedLimit {
      segmentOptions["limit"] = .number(Double(nestedLimit))
    }
    return .object([
      "recordings": .object([
        "$": .object([
          "limit": .number(50),
          "order": .object(["updatedAtMs": .string("desc")]),
        ]),
        "segments": .object(["$": .object(segmentOptions)]),
      ])
    ])
  }

  func plan() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "recordings.scribe-shaped",
      namespace: "recordings",
      order: InstantQueryOrder("updatedAtMs", .descending),
      limit: 50,
      includes: [
        InstantQueryInclude(
          "segments",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "recordings.scribe-shaped.segments",
            namespace: "transcriptionSegments",
            order: InstantQueryOrder("segmentIndex", .descending),
            limit: 2
          )
        )
      ]
    )
  }

  func segmentQuery() -> InstantLiveJSONValue {
    .object(["transcriptionSegments": .object([:])])
  }

  func translation(
    transactionID: String,
    query: InstantLiveJSONValue? = nil,
    includesQuery: Bool = true
  ) throws -> InstantLiveRefreshTranslation {
    try InstantLiveRefreshTranslator.translate(
      refresh(
        transactionID: transactionID,
        query: query,
        includesQuery: includesQuery
      ),
      existingAttributes: Self.attributes,
      receivedAt: InstantTimestamp(milliseconds: 1)
    )
  }

  func refresh(
    transactionID: String,
    query: InstantLiveJSONValue? = nil,
    includesQuery: Bool = true,
    additionalComputations: [InstantLiveJSONValue] = [],
    segmentIndexOverrides: [Int: Double] = [:],
    pageInfoHasNextPage: Bool? = nil
  ) -> InstantLiveRefreshOK {
    InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: transactionID,
      attrs: [],
      computations: [
        computation(
          query: query,
          includesQuery: includesQuery,
          segmentIndexOverrides: segmentIndexOverrides,
          pageInfoHasNextPage: pageInfoHasNextPage
        )
      ]
        + additionalComputations
    )
  }

  func serverIDRefresh(
    transactionID: String,
    childLink: ChildLink = .recording
  ) -> InstantLiveRefreshOK {
    InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: transactionID,
      attrs: Self.serverAttributes,
      computations: [
        computation(attributeIDs: .server, childLink: childLink)
      ]
    )
  }

  private func computation(
    query: InstantLiveJSONValue? = nil,
    includesQuery: Bool = true,
    attributeIDs: WireAttributeIDs = .local,
    childLink: ChildLink = .recording,
    segmentIndexOverrides: [Int: Double] = [:],
    pageInfoHasNextPage: Bool? = nil
  ) -> InstantLiveJSONValue {
    var rootData: [String: InstantLiveJSONValue] = [
      "datalog-result": .object([
        "join-rows": .array(recordingRows(attributeIDs: attributeIDs))
      ])
    ]
    if let pageInfoHasNextPage, let cursorEntityID = recordingIDs.first {
      let cursor: InstantLiveJSONValue = .array([
        .string(cursorEntityID),
        .string(attributeIDs.recordingUpdatedAt),
        .number(1),
        .number(1),
      ])
      rootData["page-info"] = .object([
        "recordings": .object([
          "start-cursor": cursor,
          "end-cursor": cursor,
          "has-previous-page?": .bool(false),
          "has-next-page?": .bool(pageInfoHasNextPage),
        ])
      ])
    }
    var object: [String: InstantLiveJSONValue] = [
      "instaql-result": .array([
        .object([
          "data": .object(rootData),
          "child-nodes": .array([
            .object([
              "data": .object([
                "datalog-result": .object([
                  "join-rows": .array(
                    segmentRows(
                      indices: childIndices,
                      attributeIDs: attributeIDs,
                      childLink: childLink,
                      segmentIndexOverrides: segmentIndexOverrides
                    )
                  )
                ])
              ]),
              "child-nodes": .array([]),
            ])
          ]),
        ])
      ])
    ]
    if includesQuery {
      object["instaql-query"] = query ?? self.query()
    }
    return .object(object)
  }

  func segmentsOnlyComputation(
    query: InstantLiveJSONValue,
    indices: [Int]
  ) -> InstantLiveJSONValue {
    .object([
      "instaql-query": query,
      "instaql-result": .array([
        .object([
          "data": .object([
            "datalog-result": .object([
              "join-rows": .array(segmentRows(indices: indices))
            ])
          ]),
          "child-nodes": .array([]),
        ])
      ]),
    ])
  }

  private func recordingRows(
    attributeIDs: WireAttributeIDs = .local
  ) -> [InstantLiveJSONValue] {
    recordingIDs.enumerated().map { index, id in
      .array([
        wireTriple(id, attributeIDs.recordingID, .string(id)),
        wireTriple(
          id,
          attributeIDs.recordingUpdatedAt,
          .number(Double(index + 1))
        ),
      ])
    }
  }

  private func segmentRows(
    indices: [Int],
    attributeIDs: WireAttributeIDs = .local,
    childLink: ChildLink = .recording,
    segmentIndexOverrides: [Int: Double] = [:]
  ) -> [InstantLiveJSONValue] {
    recordingIDs.flatMap { recordingID in
      indices.map { index in
        let id = segmentID(index, recordingID: recordingID)
        return .array([
          wireTriple(id, attributeIDs.segmentID, .string(id)),
          wireTriple(
            id,
            childLink == .recording
              ? attributeIDs.segmentRecording
              : attributeIDs.segmentRecordingID,
            .string(recordingID)
          ),
          wireTriple(
            id,
            attributeIDs.segmentIndex,
            .number(segmentIndexOverrides[index] ?? Double(index))
          ),
        ])
      }
    }
  }

  private func wireTriple(
    _ entityID: String,
    _ attributeID: String,
    _ value: InstantLiveJSONValue
  ) -> InstantLiveJSONValue {
    .array([
      .string(entityID),
      .string(attributeID),
      value,
      .number(1),
    ])
  }

  private static var serverAttributes: [InstantLiveJSONValue] {
    [
      serverAttribute(
        id: WireAttributeIDs.server.recordingID,
        namespace: "recordings",
        name: "id"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.recordingUpdatedAt,
        namespace: "recordings",
        name: "updatedAtMs",
        checkedDataType: "number"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentID,
        namespace: "transcriptionSegments",
        name: "id"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentRecording,
        namespace: "transcriptionSegments",
        name: "recording",
        reverseNamespace: "recordings",
        reverseName: "segments"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentRecordingID,
        namespace: "transcriptionSegments",
        name: "recordingID"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentIndex,
        namespace: "transcriptionSegments",
        name: "segmentIndex",
        checkedDataType: "number"
      ),
    ]
  }

  private static func serverAttribute(
    id: String,
    namespace: String,
    name: String,
    checkedDataType: String = "string",
    reverseNamespace: String? = nil,
    reverseName: String? = nil
  ) -> InstantLiveJSONValue {
    var object: [String: InstantLiveJSONValue] = [
      "id": .string(id),
      "forward-identity": .array([
        .string("forward-\(id)"),
        .string(namespace),
        .string(name),
      ]),
      "value-type": .string(reverseNamespace == nil ? "blob" : "ref"),
      "checked-data-type": .string(checkedDataType),
      "cardinality": .string("one"),
    ]
    if let reverseNamespace, let reverseName {
      object["reverse-identity"] = .array([
        .string("reverse-\(id)"),
        .string(reverseNamespace),
        .string(reverseName),
      ])
    }
    return .object(object)
  }
}

private extension InstantTripleOperation {
  var insertedTriple: InstantTriple? {
    guard case let .insert(triple) = self else { return nil }
    return triple
  }
}

private struct NestedLimitFixture {
  let childCount: Int
  let recordingCount: Int
  let childLink: ChildLink
  let recordingID = "recording-a"

  enum ChildLink {
    case recordingRef
    case recordingID
  }

  init(
    childCount: Int,
    recordingCount: Int = 1,
    childLink: ChildLink = .recordingRef
  ) {
    self.childCount = childCount
    self.recordingCount = recordingCount
    self.childLink = childLink
  }
  let queryKey =
    """
    {"recordings":{"$":{"fields":["title"],"limit":50,"order":{"updatedAtMs":"desc"}},"segments":{"$":{"limit":2,"order":{"segmentIndex":"desc"}}}}}
    """

  let recordingIDAttribute = InstantAttribute.primaryKey(namespace: "recordings")
  let recordingUpdatedAtAttribute = InstantAttribute(
    id: "recordings/updatedAtMs",
    namespace: "recordings",
    name: "updatedAtMs",
    valueType: .number,
    isIndexed: true
  )
  let segmentIDAttribute = InstantAttribute.primaryKey(namespace: "transcriptionSegments")
  let segmentRecordingAttribute = InstantAttribute(
    id: "transcriptionSegments/recording",
    namespace: "transcriptionSegments",
    name: "recording",
    valueType: .ref,
    cardinality: .one,
    isIndexed: true,
    forwardIdentity: "transcriptionSegments/recording",
    reverseIdentity: "recordings/segments",
    linkNamespace: "recordings"
  )
  let segmentRecordingIDAttribute = InstantAttribute(
    id: "transcriptionSegments/recordingID",
    namespace: "transcriptionSegments",
    name: "recordingID",
    valueType: .string,
    isIndexed: true
  )
  let segmentIndexAttribute = InstantAttribute(
    id: "transcriptionSegments/segmentIndex",
    namespace: "transcriptionSegments",
    name: "segmentIndex",
    valueType: .number,
    isIndexed: true
  )

  var attributes: [InstantAttribute] {
    [
      recordingIDAttribute,
      recordingUpdatedAtAttribute,
      segmentIDAttribute,
      segmentRecordingAttribute,
      segmentRecordingIDAttribute,
      segmentIndexAttribute,
    ]
  }

  func segmentID(_ index: Int) -> String {
    recordingCount == 1 ? "segment-\(index)" : "recording-0-segment-\(index)"
  }

  var allTriples: [InstantTriple] {
    let time = InstantTimestamp(milliseconds: 1)
    var triples: [InstantTriple] = []
    let recordingIDs: [String]
    if recordingCount == 1 {
      recordingIDs = [recordingID]
    } else {
      recordingIDs = (0..<recordingCount).map { "recording-\($0)" }
    }
    for (recordingIndex, id) in recordingIDs.enumerated() {
      triples.append(
        contentsOf: [
          InstantTriple(
            entityID: id,
            attributeID: recordingIDAttribute.id,
            value: .string(id),
            txID: "seed-\(id)",
            txTime: time
          ),
          InstantTriple(
            entityID: id,
            attributeID: recordingUpdatedAtAttribute.id,
            value: .number(Double(recordingIndex + 1)),
            txID: "seed-\(id)",
            txTime: time
          ),
        ]
      )
      for index in 0..<childCount {
        let entityID =
          recordingCount == 1
          ? "segment-\(index)"
          : "\(id)-segment-\(index)"
        let txID = "seed-\(entityID)"
        triples.append(
          contentsOf: [
            InstantTriple(
              entityID: entityID,
              attributeID: segmentIDAttribute.id,
              value: .string(entityID),
              txID: txID,
              txTime: time
            ),
            InstantTriple(
              entityID: entityID,
              attributeID: childLink == .recordingRef
                ? segmentRecordingAttribute.id
                : segmentRecordingIDAttribute.id,
              value: childLink == .recordingRef ? .ref(id) : .string(id),
              txID: txID,
              txTime: time
            ),
            InstantTriple(
              entityID: entityID,
              attributeID: segmentIndexAttribute.id,
              value: .number(Double(index)),
              txID: txID,
              txTime: time
            ),
          ]
        )
      }
    }
    return triples
  }
}

private actor NestedLimitEmissionRecorder {
  private var emissions: [InstantQueryEmission] = []

  func append(_ emission: InstantQueryEmission) {
    emissions.append(emission)
  }

  func emission(at index: Int) -> InstantQueryEmission? {
    guard emissions.indices.contains(index) else { return nil }
    return emissions[index]
  }

  func count() -> Int {
    emissions.count
  }
}

private func nestedLimitEmission(
  from recorder: NestedLimitEmissionRecorder,
  at index: Int,
  operation: String
) async throws -> InstantQueryEmission {
  try await instantLiveWithTimeout(
    operation: operation,
    timeoutMilliseconds: 5_000
  ) {
    while true {
      if let emission = await recorder.emission(at: index) {
        return emission
      }
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }
}

private func temporaryNestedLimitCacheURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "InstantLiveQueryNestedLimitMemoryTests-\(name)-\(UUID().uuidString)"
    )
    .appendingPathComponent("state.sqlite")
}

private struct LiveQueryOwnershipMutationCounts: Equatable {
  var inserted: Int64
  var deleted: Int64
  var updated: Int64
}

private struct TestLiveQueryOwnershipIdentity: Hashable {
  var queryKey: String
  var entityID: String
  var attributeID: String
  var valueJSON: String
}

private func installLiveQueryOwnershipMutationCounter(at url: URL) throws {
  try withNestedLimitSQLite(at: url) { connection in
    try executeNestedLimitSQL(
      """
      CREATE TABLE test_live_query_ownership_mutations (
        kind TEXT NOT NULL
      );
      CREATE TRIGGER test_live_query_ownership_inserted
      AFTER INSERT ON instant_live_query_triples
      BEGIN
        INSERT INTO test_live_query_ownership_mutations (kind) VALUES ('insert');
      END;
      CREATE TRIGGER test_live_query_ownership_deleted
      AFTER DELETE ON instant_live_query_triples
      BEGIN
        INSERT INTO test_live_query_ownership_mutations (kind) VALUES ('delete');
      END;
      CREATE TRIGGER test_live_query_ownership_updated
      AFTER UPDATE ON instant_live_query_triples
      BEGIN
        INSERT INTO test_live_query_ownership_mutations (kind) VALUES ('update');
      END;
      """,
      on: connection
    )
  }
}

private func resetLiveQueryOwnershipMutationCounter(at url: URL) throws {
  try withNestedLimitSQLite(at: url) { connection in
    try executeNestedLimitSQL(
      "DELETE FROM test_live_query_ownership_mutations",
      on: connection
    )
  }
}

private func liveQueryOwnershipMutationCounts(
  at url: URL
) throws -> LiveQueryOwnershipMutationCounts {
  try withNestedLimitSQLite(at: url) { connection in
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
      connection,
      """
      SELECT
        COALESCE(SUM(kind = 'insert'), 0),
        COALESCE(SUM(kind = 'delete'), 0),
        COALESCE(SUM(kind = 'update'), 0)
      FROM test_live_query_ownership_mutations
      """,
      -1,
      &statement,
      nil
    ) == SQLITE_OK,
      sqlite3_step(statement) == SQLITE_ROW
    else {
      defer { sqlite3_finalize(statement) }
      throw nestedLimitSQLiteError(
        operation: "read live-query ownership mutation counts",
        connection: connection
      )
    }
    defer { sqlite3_finalize(statement) }
    return LiveQueryOwnershipMutationCounts(
      inserted: sqlite3_column_int64(statement, 0),
      deleted: sqlite3_column_int64(statement, 1),
      updated: sqlite3_column_int64(statement, 2)
    )
  }
}

private func liveQueryOwnership(
  at url: URL
) throws -> Set<TestLiveQueryOwnershipIdentity> {
  try withNestedLimitSQLite(at: url) { connection in
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
      connection,
      """
      SELECT query_key, entity_id, attribute_id, value_json
      FROM instant_live_query_triples
      """,
      -1,
      &statement,
      nil
    ) == SQLITE_OK
    else {
      defer { sqlite3_finalize(statement) }
      throw nestedLimitSQLiteError(
        operation: "prepare live-query ownership read",
        connection: connection
      )
    }
    defer { sqlite3_finalize(statement) }

    var ownership: Set<TestLiveQueryOwnershipIdentity> = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return ownership }
      guard
        code == SQLITE_ROW,
        let queryKey = sqlite3_column_text(statement, 0),
        let entityID = sqlite3_column_text(statement, 1),
        let attributeID = sqlite3_column_text(statement, 2),
        let valueJSON = sqlite3_column_text(statement, 3)
      else {
        throw nestedLimitSQLiteError(
          operation: "read live-query ownership",
          connection: connection
        )
      }
      ownership.insert(
        TestLiveQueryOwnershipIdentity(
          queryKey: String(cString: queryKey),
          entityID: String(cString: entityID),
          attributeID: String(cString: attributeID),
          valueJSON: String(cString: valueJSON)
        )
      )
    }
  }
}

private func withNestedLimitSQLite<Value>(
  at url: URL,
  _ operation: (OpaquePointer) throws -> Value
) throws -> Value {
  var connection: OpaquePointer?
  guard sqlite3_open_v2(
    url.path,
    &connection,
    SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
    nil
  ) == SQLITE_OK,
    let connection
  else {
    defer { sqlite3_close(connection) }
    throw nestedLimitSQLiteError(
      operation: "open live-query ownership test database",
      connection: connection
    )
  }
  defer { sqlite3_close(connection) }
  sqlite3_busy_timeout(connection, 10_000)
  return try operation(connection)
}

private func executeNestedLimitSQL(
  _ sql: String,
  on connection: OpaquePointer
) throws {
  guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
    throw nestedLimitSQLiteError(
      operation: "execute live-query ownership test SQL",
      connection: connection
    )
  }
}

private func nestedLimitSQLiteError(
  operation: String,
  connection: OpaquePointer?
) -> InstantError {
  InstantError(
    code: .persistenceFailed,
    operation: operation,
    message: connection.map { String(cString: sqlite3_errmsg($0)) }
      ?? "SQLite connection unavailable.",
    recovery: "Inspect the temporary live-query ownership test database."
  )
}
