import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #1007: a device writes tens of megabytes a minute to its local store while it records, and nothing said which store
/// call wrote them. The storage write meter counts, for each store call, its write transactions and the pages SQLite
/// wrote for them.
@Suite
struct InstantStorageWriteMeterTests {
  @Test
  func eachStoreCallsWritesAreCountedUnderItsName() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantStorageWriteMeterTests-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try SQLitePersistenceStore(fileURL: url, declaredAttributes: TodoExample.attributes)
    try await store.bootstrap()

    let before = InstantStorageWriteMeter.snapshot()
    let triples = (0..<200).map { index in
      InstantTriple(
        entityID: "todo-\(index)",
        attributeID: TodoExample.attributes[1].id,
        value: .string(String(repeating: "words of todo \(index) ", count: 8)),
        txID: "tx-\(index)",
        txTime: InstantTimestamp(milliseconds: Int64(index) + 1)
      )
    }
    try await store.saveStoreSnapshot(InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples))
    let counted = InstantStorageWriteMeter.snapshot().subtracting(before)

    let save = try #require(counted.operations["saveStoreSnapshot(_:)"], "operations: \(counted.operations)")
    #expect(save.transactions >= 1)
    // 200 facts of about 160 bytes each fill more than a few 4 KB pages.
    #expect(save.pagesWritten >= 8, "pages: \(save.pagesWritten)")
  }

  // #1245: SQLite's own counters, per store call: what the call's statements did (virtual-machine steps, steps of a
  // full scan, sorts, rows put into automatic indexes, re-prepares) and what its page cache did (hits, misses, spills),
  // so a call that writes many pages also says whether it scanned, sorted or missed the cache to do it.
  @Test
  func eachStoreCallCarriesSQLitesOwnCounters() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantStorageWriteMeterTests-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try SQLitePersistenceStore(fileURL: url, declaredAttributes: TodoExample.attributes)
    try await store.bootstrap()

    let before = InstantStorageWriteMeter.snapshot()
    let triples = (0..<200).map { index in
      InstantTriple(
        entityID: "todo-\(index)",
        attributeID: TodoExample.attributes[1].id,
        value: .string(String(repeating: "words of todo \(index) ", count: 8)),
        txID: "tx-\(index)",
        txTime: InstantTimestamp(milliseconds: Int64(index) + 1)
      )
    }
    try await store.saveStoreSnapshot(InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples))
    let save = try #require(
      InstantStorageWriteMeter.snapshot().subtracting(before).operations["saveStoreSnapshot(_:)"]
    )

    // Saving 200 facts steps SQLite's virtual machine at least once per fact, and reads pages through the cache.
    #expect(save.sqlite.virtualMachineSteps >= 200, "sqlite: \(save.sqlite)")
    #expect(save.sqlite.cacheHits + save.sqlite.cacheMisses > 0, "sqlite: \(save.sqlite)")
  }

  @Test
  func aCachedStatementIsCountedOncePerUse() throws {
    let connection = try Self.inMemoryConnection()
    defer { sqlite3_close_v2(connection) }
    var cache = SQLiteStatementCache()
    let sql = "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 100) SELECT count(*) FROM n"
    func use() {
      let statement = cache.checkOut(sql, on: connection).statement
      while sqlite3_step(statement) == SQLITE_ROW {}
      cache.checkIn(statement)
    }

    use()
    let once = cache.statementCounters.virtualMachineSteps
    use()

    // The second use reuses the first's prepared statement; its steps count once, not on top of the first's.
    #expect(once > 100)
    expectNoDifference(cache.statementCounters.virtualMachineSteps, 2 * once)
  }

  @Test
  func aSortAFullScanAndAnAutomaticIndexAreCounted() throws {
    let connection = try Self.inMemoryConnection()
    defer { sqlite3_close_v2(connection) }
    for sql in [
      "CREATE TABLE line (id INTEGER PRIMARY KEY, speaker TEXT, text TEXT)",
      "CREATE TABLE speaker (name TEXT, color TEXT)",
      """
      WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 200)
      INSERT INTO line (speaker, text) SELECT 'speaker ' || (x % 20), 'line ' || x FROM n
      """,
      """
      WITH RECURSIVE n(x) AS (SELECT 0 UNION ALL SELECT x + 1 FROM n WHERE x < 19)
      INSERT INTO speaker (name, color) SELECT 'speaker ' || x, 'color ' || x FROM n
      """,
    ] {
      #expect(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
    }
    var cache = SQLiteStatementCache()
    func use(_ sql: String) {
      let statement = cache.checkOut(sql, on: connection).statement
      while sqlite3_step(statement) == SQLITE_ROW {}
      cache.checkIn(statement)
    }

    // No index on text: a full scan of the table and a sort of its 200 rows.
    use("SELECT text FROM line ORDER BY text DESC")
    expectNoDifference(cache.statementCounters.sorts, 1)
    #expect(cache.statementCounters.fullScanSteps >= 199)
    // No index on either side of the join: SQLite builds an automatic index on one side for the statement.
    use("SELECT line.text, speaker.color FROM line JOIN speaker ON speaker.name = line.speaker")
    #expect(cache.statementCounters.automaticIndexRows > 0, "counters: \(cache.statementCounters)")
  }

  private static func inMemoryConnection() throws -> OpaquePointer {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(":memory:", &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
      let connection
    else {
      sqlite3_close_v2(connection)
      throw CocoaError(.fileReadUnknown)
    }
    return connection
  }
}
