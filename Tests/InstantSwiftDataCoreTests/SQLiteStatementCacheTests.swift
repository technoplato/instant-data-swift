import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// The persistence store prepares each SQL text once and reuses the statement (#403). These pin what that must keep:
/// statements are reused, a warm transact compiles nothing, the cache stays bounded in entries and memory, and nothing
/// outlives a close or a schema change.
@Suite(.serialized)
struct SQLiteStatementCacheTests {
  @Test
  func repeatedReadsReuseOneStatement() async throws {
    let (store, cacheURL) = try await Self.bootstrappedStore()
    defer { Self.remove(cacheURL) }
    _ = try await store.countOutboxMutations()
    let before = await store.statementCacheMetricsForTesting()

    for _ in 0..<10 {
      _ = try await store.countOutboxMutations()
    }

    let after = await store.statementCacheMetricsForTesting()
    expectNoDifference(after.prepareCount - before.prepareCount, 0)
    expectNoDifference(after.uncachedPrepareCount - before.uncachedPrepareCount, 0)
    expectNoDifference(after.reuseCount - before.reuseCount, 10)
  }

  /// Once a first transact has prepared what transact runs, the next ones compile no SQL at all: every statement on
  /// the write path, the status reads, and the transaction control statements come from the cache.
  @Test
  func aWarmTransactPreparesNoStatement() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SQLiteStatementCacheTests-\(UUID().uuidString).sqlite")
    defer { Self.remove(cacheURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "statement-cache-transact",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    func create(_ index: Int) async throws {
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "statement-cache-\(index)",
          operations: TodoExample.createOperations(
            id: "statement-cache-todo-\(index)",
            text: "todo \(index)",
            createdAt: createdAt,
            transactionID: "statement-cache-\(index)"
          )
        ),
        createdAt: createdAt
      )
    }
    try await create(0)
    let warm = await runtime.persistence.statementCacheMetricsForTesting()

    for index in 1...5 {
      try await create(index)
    }

    let after = await runtime.persistence.statementCacheMetricsForTesting()
    let pendingCount = await runtime.pendingMutations().count
    let statementBytes = await runtime.persistence.statementMemoryBytesForTesting()
    expectNoDifference(after.prepareCount - warm.prepareCount, 0)
    expectNoDifference(after.uncachedPrepareCount - warm.uncachedPrepareCount, 0)
    #expect(after.reuseCount - warm.reuseCount > 5 * 10)
    expectNoDifference(pendingCount, 6)
    // What the kept statements cost: well under a mebibyte for everything transact and its status runs.
    #expect(statementBytes < 1_048_576)
  }

  @Test
  func theCacheStaysWithinItsBound() async throws {
    let (store, cacheURL) = try await Self.bootstrappedStore()
    defer { Self.remove(cacheURL) }

    for value in 0..<200 {
      let selected = try await store.selectInt64ForTesting("SELECT \(value)")
      expectNoDifference(selected, Int64(value))
    }

    let metrics = await store.statementCacheMetricsForTesting()
    let statementBytes = await store.statementMemoryBytesForTesting()
    let liveCount = await store.liveStatementCountForTesting()
    #expect(metrics.cachedStatementCount <= 64)
    #expect(statementBytes < 1_048_576)
    #expect(metrics.evictionCount >= 200 - 64)
    expectNoDifference(liveCount, metrics.cachedStatementCount)
  }

  /// `sqlite3_close` refuses to close, and leaks the connection, while a statement is live. Closing finalizes the
  /// cache first, and the store reopens with an empty cache on its next call.
  @Test
  func closingFinalizesEveryCachedStatement() async throws {
    let (store, cacheURL) = try await Self.bootstrappedStore()
    defer { Self.remove(cacheURL) }
    _ = try await store.countOutboxMutations()
    _ = try await store.loadMetadataValue(key: "statement-cache")
    let liveBeforeClose = await store.liveStatementCountForTesting()
    #expect(liveBeforeClose > 0)

    let closeResult = await store.simulateUnexpectedConnectionCloseForTesting()
    let cachedAfterClose = await store.statementCacheMetricsForTesting().cachedStatementCount
    expectNoDifference(closeResult, SQLITE_OK)
    expectNoDifference(cachedAfterClose, 0)

    let countAfterReopen = try await store.countOutboxMutations()
    let cachedAfterReopen = await store.statementCacheMetricsForTesting().cachedStatementCount
    let liveAfterReopen = await store.liveStatementCountForTesting()
    expectNoDifference(countAfterReopen, 0)
    expectNoDifference(cachedAfterReopen, 1)
    expectNoDifference(liveAfterReopen, 1)
  }

  /// Bootstrap's `CREATE ... IF NOT EXISTS` statements change nothing on an existing store, so they keep the cache.
  @Test
  func aDDLStatementThatChangesNothingKeepsTheCache() async throws {
    let (store, cacheURL) = try await Self.bootstrappedStore()
    defer { Self.remove(cacheURL) }
    _ = try await store.countOutboxMutations()
    let cached = await store.statementCacheMetricsForTesting().cachedStatementCount
    #expect(cached > 0)

    try await store.executeForTesting("CREATE TABLE IF NOT EXISTS instant_outbox (mutation_id TEXT PRIMARY KEY)")

    let cachedAfter = await store.statementCacheMetricsForTesting().cachedStatementCount
    #expect(cachedAfter >= cached)
  }

  @Test
  func aSchemaChangeFinalizesTheCache() async throws {
    let (store, cacheURL) = try await Self.bootstrappedStore()
    defer { Self.remove(cacheURL) }
    _ = try await store.countOutboxMutations()
    _ = try await store.loadMetadataValue(key: "statement-cache")
    let cachedBefore = await store.statementCacheMetricsForTesting().cachedStatementCount
    #expect(cachedBefore > 0)

    try await store.executeForTesting("CREATE TABLE IF NOT EXISTS statement_cache_probe (id INTEGER)")

    let cachedAfterChange = await store.statementCacheMetricsForTesting().cachedStatementCount
    let liveAfterChange = await store.liveStatementCountForTesting()
    expectNoDifference(cachedAfterChange, 0)
    expectNoDifference(liveAfterChange, 0)
    let countAfterChange = try await store.countOutboxMutations()
    let cachedAfterRead = await store.statementCacheMetricsForTesting().cachedStatementCount
    expectNoDifference(countAfterChange, 0)
    expectNoDifference(cachedAfterRead, 1)
  }

  private static func bootstrappedStore() async throws -> (SQLitePersistenceStore, URL) {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("SQLiteStatementCacheTests-\(UUID().uuidString).sqlite")
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    return (store, cacheURL)
  }

  private static func remove(_ cacheURL: URL) {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(at: URL(fileURLWithPath: cacheURL.path + suffix))
    }
  }
}
