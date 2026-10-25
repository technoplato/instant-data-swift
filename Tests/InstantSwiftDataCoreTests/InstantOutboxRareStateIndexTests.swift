// History:
// - 2026-10-25: added (#1115 slice 2): the outbox's rare-state indexes are partial on the states they find, each open
//   puts them in place as defined, and the queries they serve still search them.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// The outbox's three rare-state indexes (#1115): the synchronization blocker (an active overlay with no receipt),
/// effect normalization (an active overlay whose effect metadata is not the current version, or has no receipt) and
/// delivery metadata (older than the current version). Each is partial on its state, so a live write is in none of
/// them, and SQLite uses one only for a query whose WHERE clause holds the index's own predicate.
@Suite
struct InstantOutboxRareStateIndexTests {
  /// A new store holds each index as defined, partial on its state at the current version.
  @Test
  func eachRareStateIndexIsPartialOnItsState() async throws {
    let store = try await RareStateIndexes.store("rare-state-defined")

    expectNoDifference(try RareStateIndexes.storedDefinitions(store), RareStateIndexes.definitions)
    expectNoDifference(
      SQLitePersistenceStore.staleDeliveryMetadataPredicate,
      "delivery_metadata_version < \(InstantOutboxDeliveryMetadata.currentVersion)"
    )
    #expect(
      SQLitePersistenceStore.unknownActiveEffectPredicate.contains(
        "optimistic_effect_metadata_version != \(InstantOptimisticEffectFootprint.currentVersion)"
      )
    )
    for (name, definition) in RareStateIndexes.definitions {
      #expect(definition.contains("\nWHERE "), "\(name) is partial: \(definition)")
    }
  }

  /// A store whose indexes an older version built (a full index, a partial one naming another version, or none) gets
  /// each as defined at its next open, and a query that forces one still prepares: SQLite refuses `INDEXED BY` on a
  /// partial index the query's WHERE clause does not imply.
  @Test
  func anOpenRebuildsTheRareStateIndexesAnOlderVersionBuilt() async throws {
    let store = try await RareStateIndexes.store("rare-state-rebuilt")
    try RareStateIndexes.execute(
      store,
      """
      DROP INDEX instant_outbox_synchronization_blocker_idx;
      CREATE INDEX instant_outbox_synchronization_blocker_idx
      ON instant_outbox (optimistic_overlay_active, optimistic_effect_receipt_fingerprint, created_at_ms, mutation_id);
      DROP INDEX instant_outbox_effect_normalization_idx;
      CREATE INDEX instant_outbox_effect_normalization_idx
      ON instant_outbox (optimistic_overlay_active, optimistic_effect_metadata_version, created_at_ms, mutation_id)
      WHERE optimistic_overlay_active = 1
        AND (optimistic_effect_metadata_version != 1 OR optimistic_effect_receipt_fingerprint IS NULL);
      DROP INDEX instant_outbox_delivery_metadata_idx;
      """
    )

    let persistence = try SQLitePersistenceStore(fileURL: store)
    try await persistence.bootstrap()
    let blocker = try await persistence.synchronizationBlocker()
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    expectNoDifference(try RareStateIndexes.storedDefinitions(store), RareStateIndexes.definitions)
    expectNoDifference(blocker, nil)
    for query in RareStateIndexes.forcedQueries {
      _ = try RareStateIndexes.plan(store, query)
    }
  }

  /// The queries a rare-state index serves search it, and none scans the outbox: the claim's candidate read and its
  /// continuation check as the library runs them, and the blocker, normalization and old-metadata checks in the shape
  /// the library writes them. A scan would read every refused write's late columns through its body (#1108).
  @Test
  func theQueriesARareStateIndexServesStillSearchIt() async throws {
    let store = try await RareStateIndexes.store("rare-state-plans")
    let expected: [(sql: String, index: String)] = [
      (SQLitePersistenceStore.automaticDeliveryCandidatesSQL, "instant_outbox_delivery_metadata_idx"),
      (SQLitePersistenceStore.automaticDeliveryCandidateExistsSQL, "instant_outbox_delivery_metadata_idx"),
      (
        """
        SELECT EXISTS(
          SELECT 1 FROM instant_outbox
          WHERE status IN (?, ?) AND \(SQLitePersistenceStore.staleDeliveryMetadataPredicate)
            AND optimistic_overlay_active = 1
          LIMIT 1
        )
        """,
        "instant_outbox_delivery_metadata_idx"
      ),
    ] + RareStateIndexes.forcedQueries.map { ($0, RareStateIndexes.forcedIndex(in: $0)) }

    for (sql, index) in expected {
      let plan = try RareStateIndexes.plan(store, sql)
      #expect(plan.contains { $0.contains("INDEX \(index)") }, "\(index) in \(plan) for \(sql)")
      #expect(!plan.contains { $0.hasPrefix("SCAN instant_outbox") }, "a scan of the outbox in \(plan) for \(sql)")
    }
  }
}

/// A store's rare-state indexes, read and planned through SQLite directly.
enum RareStateIndexes {
  /// Each index's definition as SQLite keeps it: its SQL without `IF NOT EXISTS`.
  static var definitions: [String: String] {
    Dictionary(
      uniqueKeysWithValues: SQLitePersistenceStore.rareStateIndexes.map {
        ($0.name, $0.sql.replacingOccurrences(of: "CREATE INDEX IF NOT EXISTS", with: "CREATE INDEX"))
      }
    )
  }

  /// The queries that force a rare-state index with `INDEXED BY`, in the shape the library writes them.
  static let forcedQueries = [
    """
    SELECT mutation_id
    FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
    WHERE optimistic_overlay_active = 1 AND optimistic_effect_receipt_fingerprint IS NULL
    ORDER BY created_at_ms, mutation_id
    LIMIT 1
    """,
    """
    SELECT COUNT(*)
    FROM instant_outbox INDEXED BY instant_outbox_synchronization_blocker_idx
    WHERE optimistic_overlay_active = 1 AND optimistic_effect_receipt_fingerprint IS NULL
    """,
    """
    SELECT EXISTS(
      SELECT 1 FROM instant_outbox INDEXED BY instant_outbox_effect_normalization_idx
      WHERE optimistic_overlay_active = 1
        AND optimistic_effect_metadata_version != \(InstantOptimisticEffectFootprint.currentVersion)
      LIMIT 1
    )
    """,
    """
    SELECT mutation_id
    FROM instant_outbox INDEXED BY instant_outbox_effect_normalization_idx
    WHERE \(SQLitePersistenceStore.unknownActiveEffectPredicate)
    ORDER BY created_at_ms, mutation_id
    LIMIT 1
    """,
    """
    SELECT mutation_id, created_at_ms
    FROM instant_outbox INDEXED BY instant_outbox_effect_normalization_idx
    WHERE \(SQLitePersistenceStore.unknownActiveEffectPredicate)
      AND confirmation_proven = 0
      AND (created_at_ms > ? OR (created_at_ms = ? AND mutation_id > ?))
    ORDER BY created_at_ms, mutation_id
    LIMIT 1
    """,
  ]

  static func forcedIndex(in sql: String) -> String {
    sql.contains("instant_outbox_synchronization_blocker_idx")
      ? "instant_outbox_synchronization_blocker_idx" : "instant_outbox_effect_normalization_idx"
  }

  /// A bootstrapped store with no rows, its connection closed.
  static func store(_ label: String) async throws -> URL {
    let store = try InstantTestScratch.directory(label).appendingPathComponent("store.sqlite")
    let persistence = try SQLitePersistenceStore(fileURL: store)
    try await persistence.bootstrap()
    await persistence.simulateUnexpectedConnectionCloseForTesting()
    return store
  }

  static func storedDefinitions(_ store: URL) throws -> [String: String] {
    let names = SQLitePersistenceStore.rareStateIndexes.map { "'\($0.name)'" }.joined(separator: ", ")
    return try withConnection(store) { connection in
      var definitions: [String: String] = [:]
      try rows(connection, "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND name IN (\(names))") {
        definitions[String(cString: sqlite3_column_text($0, 0))] = String(cString: sqlite3_column_text($0, 1))
      }
      return definitions
    }
  }

  /// `EXPLAIN QUERY PLAN`'s details for `sql`; throws when SQLite cannot plan it.
  static func plan(_ store: URL, _ sql: String) throws -> [String] {
    try withConnection(store) { connection in
      var details: [String] = []
      try rows(connection, "EXPLAIN QUERY PLAN \(sql)") { details.append(String(cString: sqlite3_column_text($0, 3))) }
      return details
    }
  }

  static func execute(_ store: URL, _ sql: String) throws {
    try withConnection(store) { connection in
      guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
        throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
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
    return try body(connection)
  }

  private static func rows(_ connection: OpaquePointer?, _ sql: String, _ row: (OpaquePointer?) -> Void) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError("\(String(cString: sqlite3_errmsg(connection))): \(sql)")
    }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
  }
}
