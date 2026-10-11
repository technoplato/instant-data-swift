import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #653: the write path did work whose result nobody sees. Each test here pins one saving and the behavior that must
/// not change with it.
@Suite(.serialized)
struct InstantWritePathEnergyTests {
  // MARK: - SQLite's page cache

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

  /// A memory warning releases the cache, which no save does any more (#653).
  @Test
  func aMemoryWarningReleasesThePageCache() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("page-cache-release")
    try await InstantOfflineRuntimeFixture.createTodo("first", in: runtime)
    try await InstantOfflineRuntimeFixture.createTodo("second", in: runtime)
    let warm = try await runtime.persistence.pageCacheStatusForTesting()

    await runtime.persistence.releaseMemory()

    let released = try await runtime.persistence.pageCacheStatusForTesting()
    print("#653 page cache: \(warm.usedBytes) B warm, \(released.usedBytes) B after a memory warning")
    #expect(released.usedBytes < warm.usedBytes, "warm: \(warm.usedBytes) B, released: \(released.usedBytes) B")
    try await InstantOfflineRuntimeFixture.createTodo("third", in: runtime)
    let pendingCount = await runtime.pendingMutationCount()
    expectNoDifference(pendingCount, 3, "the store keeps working after the release")
  }

  // MARK: - Prepared statements

  /// Every statement was prepared and finalized on each call, so SQLite parsed and planned the same SQL again for
  /// every save. On a device database's copy SQLite ran 17% fewer instructions per write with a 2 MiB page cache, and
  /// 23% fewer with reused statements as well (#653).
  @Test
  func repeatedSavesReuseTheirPreparedStatements() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("statement-reuse")
    try await InstantOfflineRuntimeFixture.createTodo("warm-1", in: runtime)
    try await InstantOfflineRuntimeFixture.createTodo("warm-2", in: runtime)
    let preparedBefore = await runtime.persistence.preparedStatementCountForTesting()

    for index in 0..<10 {
      try await InstantOfflineRuntimeFixture.createTodo("reuse-\(index)", in: runtime)
    }

    let preparedAfter = await runtime.persistence.preparedStatementCountForTesting()
    let pendingCount = await runtime.pendingMutationCount()
    expectNoDifference(preparedAfter - preparedBefore, 0)
    expectNoDifference(pendingCount, 12, "every write is still durable in the outbox")
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
