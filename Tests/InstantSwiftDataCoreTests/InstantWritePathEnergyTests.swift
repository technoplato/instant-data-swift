import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #653: the write path did work whose result nobody sees. Each test here pins one saving and the behavior that must
/// not change with it.
@Suite(.serialized)
struct InstantWritePathEnergyTests {
  // MARK: - SQLite's page cache

  /// With no page cache (`PRAGMA cache_size = 0`), SQLite made room for each page a save touched by writing a dirty
  /// page to the WAL in the middle of the transaction, and wrote it again at commit: on a device database's copy a
  /// write cost 992 KB of logical writes, 609 KB with a 2 MiB cache (#653).
  @Test
  func aLocalSaveWritesEachChangedPageOnlyAtCommit() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("page-cache-spill")
    try await InstantOfflineRuntimeFixture.createTodo("warm", in: runtime)
    _ = try await runtime.persistence.pageCacheStatusForTesting(resettingSpillCount: true)

    for index in 0..<5 {
      try await InstantOfflineRuntimeFixture.createTodo("spill-\(index)", in: runtime)
    }

    let status = try await runtime.persistence.pageCacheStatusForTesting()
    let pendingCount = await runtime.pendingMutationCount()
    expectNoDifference(status.spilledPageCount, 0)
    expectNoDifference(pendingCount, 6, "every write is still durable in the outbox")
  }

  /// The cache is bounded at 2 MiB per connection, and a save no longer empties it: the pages the next save reads
  /// are still in memory (#653).
  @Test
  func thePageCacheIsBoundedAtTwoMebibytesAndStaysWarmBetweenSaves() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("page-cache-warm")
    try await InstantOfflineRuntimeFixture.createTodo("first", in: runtime)
    try await InstantOfflineRuntimeFixture.createTodo("second", in: runtime)

    let status = try await runtime.persistence.pageCacheStatusForTesting()
    expectNoDifference(status.cacheSize, -2_048)
    #expect(status.usedBytes > 0, "a save left SQLite's page cache empty")
  }

  /// Reading a store far larger than the cache keeps the cache within its bound (#653).
  @Test
  func readingALargeStoreKeepsThePageCacheWithinItsBound() async throws {
    let persistence = try SQLitePersistenceStore(fileURL: try Self.temporaryCacheURL("page-cache-bound"))
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: Self.largeStoreAttributes, triples: Self.largeStoreTriples(count: 20_000))
    )
    await persistence.invalidateMemoryCache()

    let state = try await persistence.loadState()

    expectNoDifference(state.snapshot.store.triples.count, 20_000)
    let status = try await persistence.pageCacheStatusForTesting()
    #expect(status.usedBytes > 1_048_576, "the read did not fill the cache")
    #expect(status.usedBytes <= 2_621_440, "the cache grew past 2 MiB and its page headers")
  }

  // MARK: - Helpers

  static func temporaryCacheURL(_ name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-write-path-energy-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static let largeStoreAttributes = [
    InstantAttribute(
      id: "energy-large/value",
      namespace: "energy-large",
      name: "value",
      valueType: .string,
      cardinality: .one,
      isIndexed: true,
      isUnique: false
    )
  ]

  static func largeStoreTriples(count: Int) -> [InstantTriple] {
    (0..<count).map { index in
      InstantTriple(
        entityID: "large-entity-\(index)",
        attributeID: "energy-large/value",
        value: .string("value-\(index)-" + String(repeating: "x", count: 64)),
        txID: "seed-\(index)",
        txTime: InstantTimestamp(milliseconds: Int64(index + 1))
      )
    }
  }
}
