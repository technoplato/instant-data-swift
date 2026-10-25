// History:
// - 2026-10-25: added (#1121): each fact is stored once, in a table keyed by the fact itself, with its JSON computed
//   when it is read; a store in the old layout is rebuilt once and keeps every fact.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// Each fact is stored once (#1121). `instant_triples` kept a fact's five columns, a `json` column repeating the whole
/// row, and, as a rowid table with a text key, the key a third time in its own index: on one phone's store 174,817
/// facts took 127 MB that way. Keyed by the fact itself (WITHOUT ROWID) with `json` computed when it is read, the same
/// facts take 41 MB (#1076's phone copy, migrated with the store's own SQL), and an entity's facts share their pages.
@Suite
struct InstantFactLayoutTests {
  /// 400 todos, 1,600 facts: one b-tree holds them, keyed by the fact, and `json` takes no space.
  @Test
  func eachFactIsStoredOnce() async throws {
    let directory = try InstantTestScratch.directory("fact-layout")
    let store = directory.appendingPathComponent("store.sqlite")
    let runtime = try await CheckpointCadence.runtime(store)
    for index in 0..<400 { _ = try await CheckpointCadence.write(index, on: runtime) }

    let layout = try FactLayout.read(store)

    expectNoDifference(layout.btrees, ["instant_triples"])
    #expect(layout.withoutRowid, "the fact table is keyed by the fact itself")
    #expect(layout.jsonIsComputed, "a fact's json is computed when it is read, not stored")
    #expect(layout.pages <= 70, "1,600 facts take \(layout.pages) pages")
  }

  /// A store written in the old layout (a rowid table with a stored `json`) is rebuilt once at its next open, and every
  /// fact reads back as it was, column for column and through the runtime.
  @Test
  func aStoreInTheOldLayoutIsRebuiltWithEveryFact() async throws {
    let directory = try InstantTestScratch.directory("fact-layout-migration")
    let store = directory.appendingPathComponent("store.sqlite")
    var runtime = try await CheckpointCadence.runtime(store)
    var written: [String] = []
    for index in 0..<120 { written.append(try await CheckpointCadence.write(index, on: runtime)) }
    await runtime.persistence.simulateUnexpectedConnectionCloseForTesting()
    try FactLayout.rewriteInTheOldLayout(store)
    let factsBefore = try FactLayout.facts(store)
    #expect(try !FactLayout.read(store).withoutRowid, "the fixture starts in the old layout")

    runtime = try await CheckpointCadence.runtime(store)
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query)).map(\.text).sorted()

    expectNoDifference(try FactLayout.facts(store), factsBefore)
    expectNoDifference(todos, written)
    let layout = try FactLayout.read(store)
    #expect(layout.withoutRowid && layout.jsonIsComputed, "the next open rebuilt the table: \(layout)")
    expectNoDifference(try CheckpointCadence.integrity(store), "ok")
  }
}

/// How the fact table is laid out, read from SQLite's own catalog.
struct FactLayout: CustomStringConvertible {
  /// The b-trees (table and indexes) the fact table's pages belong to.
  var btrees: [String]
  var pages: Int
  var withoutRowid: Bool
  /// `json` is a virtual generated column: SQLite computes it when a row is read and stores nothing.
  var jsonIsComputed: Bool

  var description: String {
    "btrees=\(btrees) pages=\(pages) withoutRowid=\(withoutRowid) jsonIsComputed=\(jsonIsComputed)"
  }

  static func read(_ store: URL) throws -> FactLayout {
    try withConnection(store) { connection in
      let btrees = try strings(
        connection,
        "SELECT DISTINCT name FROM dbstat WHERE name IN (SELECT name FROM sqlite_master WHERE tbl_name = 'instant_triples') AND name != 'instant_triples_lookup' ORDER BY name"
      )
      let pages = try strings(
        connection,
        "SELECT count(*) FROM dbstat WHERE name IN (SELECT name FROM sqlite_master WHERE tbl_name = 'instant_triples') AND name != 'instant_triples_lookup'"
      ).first.flatMap(Int.init) ?? 0
      let withoutRowid = try strings(connection, "SELECT wr FROM pragma_table_list('instant_triples')").first == "1"
      // `hidden` is 2 for a virtual generated column, 3 for a stored one, 0 for an ordinary column.
      let hidden = try strings(connection, "SELECT hidden FROM pragma_table_xinfo('instant_triples') WHERE name = 'json'")
      return FactLayout(btrees: btrees, pages: pages, withoutRowid: withoutRowid, jsonIsComputed: hidden.first == "2")
    }
  }

  /// Every fact's columns, sorted.
  static func facts(_ store: URL) throws -> [String] {
    try withConnection(store) { connection in
      try strings(
        connection,
        """
        SELECT entity_id || '|' || attribute_id || '|' || value_json || '|' || tx_id || '|' || tx_time_ms
        FROM instant_triples ORDER BY entity_id, attribute_id, value_json
        """
      )
    }
  }

  /// Rebuilds the fact table as migration 0001 made it, each row's `json` the text the store reads for it, and forgets
  /// migration 0032, as a store written before #1121 is.
  static func rewriteInTheOldLayout(_ store: URL) throws {
    try withConnection(store) { connection in
      for sql in [
        "BEGIN IMMEDIATE",
        """
        CREATE TABLE instant_triples_old (
          entity_id TEXT NOT NULL,
          attribute_id TEXT NOT NULL,
          value_json TEXT NOT NULL,
          tx_id TEXT NOT NULL,
          tx_time_ms INTEGER NOT NULL,
          json TEXT NOT NULL,
          PRIMARY KEY (entity_id, attribute_id, value_json)
        )
        """,
        """
        INSERT INTO instant_triples_old SELECT entity_id, attribute_id, value_json, tx_id, tx_time_ms, json
        FROM instant_triples ORDER BY entity_id, attribute_id, value_json
        """,
        "DROP TABLE instant_triples",
        "ALTER TABLE instant_triples_old RENAME TO instant_triples",
        "DELETE FROM instant_schema_migrations WHERE name = '0032_instant_triples_stored_once'",
        "COMMIT",
      ] {
        try execute(connection, sql)
      }
    }
  }

  private static func withConnection<Value>(_ store: URL, _ body: (OpaquePointer?) throws -> Value) throws -> Value {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      defer { sqlite3_close_v2(connection) }
      throw StorageIOError("open \(store.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    sqlite3_busy_timeout(connection, 5_000)
    return try body(connection)
  }

  private static func execute(_ connection: OpaquePointer?, _ sql: String) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
      throw StorageIOError("\(sql.prefix(60)): \(String(cString: sqlite3_errmsg(connection)))")
    }
  }

  private static func strings(_ connection: OpaquePointer?, _ sql: String) throws -> [String] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError("\(sql.prefix(60)): \(String(cString: sqlite3_errmsg(connection)))")
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      values.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
    }
    return values
  }
}
