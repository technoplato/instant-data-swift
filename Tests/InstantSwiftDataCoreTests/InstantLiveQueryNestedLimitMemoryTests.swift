import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Nested include limits must bound persisted live-query triples (#044 / #155).
///
/// SQLite Data: `LIMIT 2` on a child join keeps two rows per parent.
/// TypeScript instaql applies per-parent nested `limit` before
/// `createStore(attrs, result.triples)`.
///
/// Swift `runtime.query` already returns two children (L1). The observe path
/// still persists every matching child into `instant_live_query_triples`. A
/// Mac recordings list query with `segments.$limit: 2` stored 481 segments
/// (328 on one parent). Trial 3 then loaded that union into InstantStore.
///
/// Filter at save and load in `SQLitePersistenceStore`. InstantRuntime is
/// unedited. Live `transact` is unchanged. Non-JSON query keys stay unfiltered
/// so existing prune tests keep their synthetic keys.
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

private struct NestedLimitFixture {
  let childCount: Int
  let recordingCount: Int
  let recordingID = "recording-a"

  init(childCount: Int, recordingCount: Int = 1) {
    self.childCount = childCount
    self.recordingCount = recordingCount
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
              attributeID: segmentRecordingAttribute.id,
              value: .ref(id),
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

private func temporaryNestedLimitCacheURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "InstantLiveQueryNestedLimitMemoryTests-\(name)-\(UUID().uuidString)"
    )
    .appendingPathComponent("state.sqlite")
}
