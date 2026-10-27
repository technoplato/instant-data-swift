// History:
// - 2026-10-27: added (#1244): guards for two entries of docs/FOOTGUNS.md that had none: a lookup's partial index, and
//   the stored value's synthesized Codable wrapper (#1251, a known issue until the encoding changes).

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// Guards for entries of `docs/FOOTGUNS.md` that no test held (#1244). Each fails when its footgun comes back; one that
/// documents a cost not fixed yet records a known issue, so the fix flips it.
@Suite
struct FootgunGuardTests {
  /// "Repeat a partial index's condition word for word, and force it with `INDEXED BY`": the lookup local reads use
  /// finds its entities in the partial index, and the same lookup without the index's condition reads the whole fact
  /// table, so the plan this guard checks can tell the two apart.
  @Test
  func aLookupReadsThePartialIndexAndTheSameLookupWithoutItsConditionScans() async throws {
    let lookup: Set<String> = ["lines/recordingID", "recordings/id"]
    let directory = try InstantTestScratch.directory("footgun-lookup-plan")
    let store = InstantTestScratch.store(directory.appendingPathComponent("store.sqlite"))
    let persistence = try SQLitePersistenceStore(
      fileURL: store,
      localLookup: InstantLocalLookupPolicy(attributeIDs: lookup.sorted())
    )
    try await persistence.bootstrap()

    expectNoDifference(
      try Self.queryPlan(SQLiteReadConnection.entityIDsSQL(lookupAttributeIDs: lookup), in: store),
      ["SEARCH instant_triples USING COVERING INDEX instant_triples_lookup (attribute_id=? AND value_json=?)"]
    )
    expectNoDifference(
      try Self.queryPlan(
        "SELECT entity_id FROM instant_triples WHERE attribute_id = ? AND value_json = ?",
        in: store
      ),
      ["SCAN instant_triples"]
    )
  }

  /// "Do not let a synthesized `Codable` shape become the storage format": a stored string is its JSON plus a short
  /// tag at most. Today the store keeps `{"string":{"_0":"abc"}}` for the 5 bytes of `"abc"`, again at each level of a
  /// JSON value, inside the fact table's primary key and each index that holds the value: +46% of one device store's
  /// value bytes (#1251).
  @Test
  func aStoredStringCostsItsJSONPlusAShortTag() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let stored = try InstantStoredJSON.stored(.string("abc"), using: encoder)

    withKnownIssue("#1251: the stored value keeps the synthesized Codable wrapper") {
      #expect(stored.utf8.count <= #""abc""#.utf8.count + 4, "stored as \(stored)")
    }
  }

  /// `EXPLAIN QUERY PLAN` of `sql` on its own read-only connection, one detail line per step.
  private static func queryPlan(_ sql: String, in url: URL) throws -> [String] {
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    try #require(sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    try #require(sqlite3_prepare_v2(database, "EXPLAIN QUERY PLAN \(sql)", -1, &statement, nil) == SQLITE_OK)
    var details: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let detail = sqlite3_column_text(statement, 3) { details.append(String(cString: detail)) }
    }
    return details
  }
}
