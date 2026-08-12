import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Query-scoped InstantStore bootstrap (#044 / #155).
///
/// SQLite Data: GRDB keeps the corpus on disk. A screen SQL LIMIT loads the
/// visible page. Closing the screen drops that page. History not on screen
/// stays on disk.
///
/// Instant TypeScript
/// (`upstream/instant/client/packages/core/src/Reactor.js`,
/// `store.ts`, `IndexedDBStorage.ts`): there is no second full graph. Each
/// `querySub` has its own `result.store` from `createStore(attrs, result.triples)`.
/// `dataForQuery` runs instaql on that per-query store plus pending mutations.
/// IndexedDB persists `querySubs` / `kv` / `syncSubs`, not a triples table of
/// the whole app.
///
/// Instant Swift Data: `instant_triples` is a second full copy. Bootstrap
/// `loadStoreSnapshotWithoutTransaction` used to SELECT every non-deferred
/// triple into one global `TripleIndexes`. That is the remaining RAM floor
/// after deferred transcript payloads (trial 2) and observer splice (trial 1).
///
/// This suite measures unique hot-store entity IDs after bootstrap. A 32-row
/// persisted live query must not materialize a 1,000-row identity corpus.
/// Unobserved rows stay in SQLite. Live `transact` is unchanged.
@Suite(.serialized)
struct InstantQueryScopedHotStoreMemoryTests {
  private let corpusCount = 1_000
  private let pageSize = 32

  @Test
  func bootstrapWithoutLiveQueryTriplesKeepsTheIdentityCorpus() async throws {
    let cacheURL = temporaryQueryScopedCacheURL("full-load")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let fixture = QueryScopedFixture(siblingCount: corpusCount)
    try await seedQueryScopedCache(cacheURL, fixture: fixture, pageSize: nil)

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    let loaded = try await persistence.loadCompactState()
    let hotEntityIDs = uniqueEntityIDs(in: loaded.snapshot.store.triples)
    let storedCount = try await persistence.storedTripleEntityCountForTesting()
    expectNoDifference(hotEntityIDs.count, corpusCount)
    expectNoDifference(storedCount, corpusCount)
    print("control_hot_store_entity_count: \(hotEntityIDs.count)")
  }

  @Test
  func bootstrapWithAPageSizedLiveQueryLoadsOnlyThoseEntities() async throws {
    let cacheURL = temporaryQueryScopedCacheURL("scoped-load")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let fixture = QueryScopedFixture(siblingCount: corpusCount)
    try await seedQueryScopedCache(cacheURL, fixture: fixture, pageSize: pageSize)

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    let loaded = try await persistence.loadCompactState()
    let hotEntityIDs = uniqueEntityIDs(in: loaded.snapshot.store.triples)
    let storedCount = try await persistence.storedTripleEntityCountForTesting()
    expectNoDifference(hotEntityIDs.count, pageSize)
    expectNoDifference(
      hotEntityIDs,
      Set((0..<pageSize).map(fixture.entityID))
    )
    expectNoDifference(storedCount, corpusCount)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "query-scoped-hot-store",
        persistenceURL: cacheURL,
        initialAttributes: fixture.attributes
      )
    )
    let runtimeEntityIDs = uniqueEntityIDs(in: await runtime.store.snapshot().triples)
    let runtimeStoredCount = try await runtime.persistence.storedTripleEntityCountForTesting()
    expectNoDifference(runtimeEntityIDs.count, pageSize)
    expectNoDifference(runtimeStoredCount, corpusCount)
    print("scoped_hot_store_entity_count: \(runtimeEntityIDs.count)")
    print("sqlite_entity_count: \(corpusCount)")
  }
}

private struct QueryScopedFixture {
  let namespace = "transcriptionSegments"
  let siblingCount: Int

  let idAttribute = InstantAttribute.primaryKey(namespace: "transcriptionSegments")
  let recordingIDAttribute = InstantAttribute(
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
    [idAttribute, recordingIDAttribute, segmentIndexAttribute]
  }

  func entityID(_ index: Int) -> String {
    "segment-\(index)"
  }

  func triples(for index: Int) -> [InstantTriple] {
    let entityID = entityID(index)
    let timestamp = InstantTimestamp(milliseconds: Int64(index + 1))
    let txID = "seed-\(entityID)"
    return [
      InstantTriple(
        entityID: entityID,
        attributeID: idAttribute.id,
        value: .string(entityID),
        txID: txID,
        txTime: timestamp
      ),
      InstantTriple(
        entityID: entityID,
        attributeID: recordingIDAttribute.id,
        value: .string("recording-a"),
        txID: txID,
        txTime: timestamp
      ),
      InstantTriple(
        entityID: entityID,
        attributeID: segmentIndexAttribute.id,
        value: .number(Double(index)),
        txID: txID,
        txTime: timestamp
      ),
    ]
  }
}

private func seedQueryScopedCache(
  _ cacheURL: URL,
  fixture: QueryScopedFixture,
  pageSize: Int?
) async throws {
  let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
  try await persistence.bootstrap()
  var triples: [InstantTriple] = []
  triples.reserveCapacity(fixture.siblingCount * 3)
  for index in 0..<fixture.siblingCount {
    triples.append(contentsOf: fixture.triples(for: index))
  }
  try await persistence.saveStoreSnapshot(
    InstantStoreSnapshot(attributes: fixture.attributes, triples: triples)
  )
  guard let pageSize else { return }
  let pageTriples = (0..<pageSize).flatMap { fixture.triples(for: $0) }
  let state = try await persistence.loadCompactState()
  let now = InstantTimestamp(
    milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded())
  )
  let didSave = try await persistence.saveLiveRefresh(
    state.snapshot,
    queryResults: [
      InstantPersistedLiveQueryResult(
        replacement: InstantLiveQueryResultReplacement(
          key: "scribe-timeline-page",
          triples: pageTriples,
          pageInfo: nil
        ),
        updatedAt: now
      )
    ],
    storeChanged: false,
    outboxChanged: false,
    metadataKey: "query-scoped.watermark",
    metadataValue: "page",
    metadataUpdatedAt: now,
    expectedStoreRevision: state.storeRevision,
    expectedOutboxRevision: state.outboxRevision,
    expectedAttributeRevision: state.attributeRevision
  )
  expectNoDifference(didSave, true)
}

private func uniqueEntityIDs(in triples: [InstantTriple]) -> Set<String> {
  Set(triples.map(\.entityID))
}

private func temporaryQueryScopedCacheURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "InstantQueryScopedHotStoreMemoryTests-\(name)-\(UUID().uuidString)"
    )
    .appendingPathComponent("state.sqlite")
}
