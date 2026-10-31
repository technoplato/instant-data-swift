// History:
// - 2026-10-31: added (#1426, #1440): a stored live-query result is its ownership rows, its facts and a narrow
//   header. A reader gets the same result in a running process and after a kill, in every field; the header row holds
//   no JSON; a store 1.9.54 left converts once at bootstrap.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// A stored live-query result held the whole result as one JSON blob, rewritten whole every five minutes while it
/// changed (#1123) and then only at the app's flush (1.9.54), with the newest result kept in memory meanwhile and a
/// kill repaired from the ownership rows at the next launch (#566). Both are a copy that waits, which the maintainer
/// ruled out for #1426: a write is not batched or delayed, and its cost is fixed at the source. So a stored result is
/// what every refresh already writes exactly: its ownership rows (which facts it holds), its facts (as the store holds
/// them) and a narrow header (its page info, count and time). Every reader builds it from those rows, so a reader in a
/// running process and a reader after a kill get the same result, and a refresh writes only its diff (#1426), with no
/// blob for the header's update to read (#1440).
@Suite(.serialized)
struct InstantStoredLiveQueryResultTests {
  typealias Writes = InstantLiveQueryResultWriteTests

  /// A row changes, a row joins, the page info changes and a row leaves; the stored result is then the facts the store
  /// holds for the rows the server's last answer named, with their stamps, the last page info and the last refresh's
  /// time: in the running process, and in a new process after a kill (no flush, no close).
  @Test
  func aStoredResultIsWhatTheStoreHoldsInARunningProcessAndAfterAKill() async throws {
    let url = try Writes.temporaryCacheURL()
    let clock = Writes.TestClock(1_791_150_000_000)
    var rows = (0..<3).map { Row(index: $0, text: Writes.longText($0, revision: 0)) }
    let fixture = try await Writes.answeredTodos(rows.map(\.text), appID: "stored-result-every-field", url: url, clock: clock)
    let key = try InstantLiveQueryEncoder.registrationKey(for: fixture.query)

    rows[1].text = Writes.longText(1, revision: 1)
    try await Self.refresh(rows, hasNextPage: nil, in: fixture)
    rows.append(Row(index: 3, text: Writes.longText(3, revision: 0)))
    try await Self.refresh(rows, hasNextPage: true, in: fixture)
    rows.removeFirst()
    try await Self.refresh(rows, hasNextPage: true, in: fixture)

    let expected = try Self.expectedResult(
      key: key,
      url: url,
      rows: rows,
      hasNextPage: true,
      updatedAt: clock.now()
    )
    let running = try await fixture.runtime.persistence.storedLiveQueryResultForTesting(key: key)
    expectNoDifference(running, expected)
    #expect(running == expected, "the running process's stored result is what the store holds")

    // The app is killed: no flush, no close. A new process opens the same store an hour later.
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    clock.advance(by: 3_600_000)
    let reopened = try await Writes.makeRuntime(url: url, session: session, clock: clock, appID: "stored-result-every-field")
    let afterKill = try await reopened.persistence.storedLiveQueryResultForTesting(key: key)
    expectNoDifference(afterKill, expected)
    #expect(afterKill == expected, "after a kill the stored result is the same")
    _ = try await reopened.closeConnection()
    _ = fixture
  }

  /// The header row a refresh updates holds no JSON: its page info has its own column, and its facts are its ownership
  /// rows and the store's facts (#1440: the update of a 600 KB row's count and time read the whole JSON).
  @Test
  func aStoredResultsHeaderHoldsNoJSON() async throws {
    let url = try Writes.temporaryCacheURL()
    var rows = (0..<20).map { Row(index: $0, text: Writes.longText($0, revision: 0)) }
    let fixture = try await Writes.answeredTodos(rows.map(\.text), appID: "stored-result-header", url: url)
    let key = try InstantLiveQueryEncoder.registrationKey(for: fixture.query)
    rows[3].text = Writes.longText(3, revision: 1)
    try await Self.refresh(rows, hasNextPage: true, in: fixture)

    let header = try Self.header(url, key: key)
    #expect(header.jsonBytes == 0, "the header row holds \(header.jsonBytes) bytes of JSON")
    let pageInfo = try header.pageInfoJSON.map {
      try JSONDecoder().decode(InstantQueryPageInfo.self, from: Data($0.utf8))
    }
    expectNoDifference(pageInfo, Self.pageInfo(hasNextPage: true))
    _ = try await fixture.runtime.closeConnection()
  }

  /// A store 1.9.54 left holds each result's whole JSON, and a result whose JSON waited has a marker holding its newest
  /// page info. Bootstrap converts it once: the header takes the marker's page info (or the JSON's, without a marker),
  /// the JSON goes, and the marker goes; the result is then what the store holds.
  @Test(arguments: [true, false])
  func aStoreThatOneDotNineDotFiftyFourLeftConvertsOnce(withMarker: Bool) async throws {
    let url = try Writes.temporaryCacheURL()
    let clock = Writes.TestClock(1_791_150_000_000)
    var rows = (0..<3).map { Row(index: $0, text: Writes.longText($0, revision: 0)) }
    let appID = "stored-result-convert-\(withMarker)"
    let fixture = try await Writes.answeredTodos(rows.map(\.text), appID: appID, url: url, clock: clock)
    let key = try InstantLiveQueryEncoder.registrationKey(for: fixture.query)
    rows[2].text = Writes.longText(2, revision: 1)
    try await Self.refresh(rows, hasNextPage: true, in: fixture)
    _ = try await fixture.runtime.closeConnection()
    let updatedAt = clock.now()

    // 1.9.54's layout: the whole result as JSON with an older page info, and, when its write waited, the newest page
    // info in its marker.
    let newest = try Self.expectedResult(key: key, url: url, rows: rows, hasNextPage: true, updatedAt: updatedAt)
    var stale = newest
    stale.pageInfo = withMarker ? Self.pageInfo(hasNextPage: false) : newest.pageInfo
    try Self.writeOneDotNineDotFiftyFourLayout(
      url,
      result: stale,
      markerPageInfo: withMarker ? .some(newest.pageInfo) : .none
    )

    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    clock.advance(by: 60_000)
    let reopened = try await Writes.makeRuntime(url: url, session: session, clock: clock, appID: appID)
    let converted = try await reopened.persistence.storedLiveQueryResultForTesting(key: key)
    expectNoDifference(converted, newest)
    #expect(converted == newest, "the converted result is what the store holds, with its newest page info")
    let header = try Self.header(url, key: key)
    #expect(header.jsonBytes == 0, "the converted header holds \(header.jsonBytes) bytes of JSON")
    #expect(try Self.waitingMarkerCount(url) == 0, "no waiting marker is left")
    _ = try await reopened.closeConnection()
    _ = fixture
  }

  // MARK: - Helpers

  struct Row {
    var index: Int
    var text: String
  }

  static func pageInfo(hasNextPage: Bool) -> InstantQueryPageInfo {
    InstantQueryPageInfo(startCursor: nil, endCursor: nil, hasPreviousPage: false, hasNextPage: hasNextPage)
  }

  /// One `refresh-ok` restating the todo query with `rows` (each todo keeps its own id) and the page info when
  /// `hasNextPage` is given; waits until the runtime saved the result.
  static func refresh(_ rows: [Row], hasNextPage: Bool?, in fixture: Writes.Fixture) async throws {
    let savesBefore = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting().saves
    fixture.clock.advance(by: 1_000)
    let number = fixture.clock.now().milliseconds
    var data: [String: InstantLiveJSONValue] = [
      "datalog-result": .object([
        "join-rows": .array(
          rows.map {
            Writes.todoJoinRow(id: Writes.todoID($0.index), text: $0.text, createdAt: 1_700_000_000_000 + Int64($0.index))
          }
        )
      ])
    ]
    if let hasNextPage {
      data["page-info"] = .object([
        TodoExample.namespace: .object([
          "start-cursor": .null,
          "end-cursor": .null,
          "has-next-page?": .bool(hasNextPage),
          "has-previous-page?": .bool(false),
        ])
      ])
    }
    await fixture.session.enqueue(
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: "refresh-\(number)",
        fields: [
          "attrs": .array([]),
          "computations": .array([
            .object([
              "instaql-query": fixture.query,
              "instaql-result": .array([.object(["data": .object(data), "child-nodes": .array([])])]),
              "processed-tx-id": .string("server-tx-\(number)"),
            ])
          ]),
          "processed-tx-id": .string("server-tx-\(number)"),
        ]
      )
    )
    try await Writes.waitFor("the refresh's result to be saved") {
      await fixture.runtime.liveQueryResultJSONWriteStatsForTesting().saves > savesBefore
    }
  }

  /// The result the store holds for `rows`: their facts with the store's stamps, the page info and the time.
  static func expectedResult(
    key: String,
    url: URL,
    rows: [Row],
    hasNextPage: Bool?,
    updatedAt: InstantTimestamp
  ) throws -> InstantPersistedLiveQueryResult {
    let facts = try rows.flatMap { try storedFacts(url, entityID: Writes.todoID($0.index)) }
    #expect(facts.count == rows.count * 4, "each todo holds its four facts")
    return InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: key,
        triples: facts,
        pageInfo: hasNextPage.map(Self.pageInfo(hasNextPage:))
      ),
      updatedAt: updatedAt
    )
  }

  static func open(_ url: URL) throws -> OpaquePointer {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let database else {
      sqlite3_close(database)
      throw Writes.StoredFactCountFailure(message: "could not open \(url.path)")
    }
    sqlite3_busy_timeout(database, 10_000)
    return database
  }

  static func rows(_ url: URL, _ sql: String, _ bindings: [String] = []) throws -> [[String?]] {
    let database = try open(url)
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw Writes.StoredFactCountFailure(message: String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, binding) in bindings.enumerated() {
      sqlite3_bind_text(statement, Int32(index + 1), binding, -1, transient)
    }
    var rows: [[String?]] = []
    var code = sqlite3_step(statement)
    while code == SQLITE_ROW {
      rows.append((0..<sqlite3_column_count(statement)).map { column in
        sqlite3_column_text(statement, column).map { String(cString: $0) }
      })
      code = sqlite3_step(statement)
    }
    guard code == SQLITE_DONE else {
      throw Writes.StoredFactCountFailure(message: String(cString: sqlite3_errmsg(database)))
    }
    return rows
  }

  /// The result the SQLite store at `url` holds under `key`, read from its rows as a reader outside the store would: its
  /// header's time and page info, and each ownership row's fact with the stamp the store holds for it.
  static func storedResult(_ url: URL, key: String) throws -> InstantPersistedLiveQueryResult? {
    let headers = try rows(
      url,
      "SELECT query_id, updated_at_ms, page_info_json FROM instant_live_query_results WHERE query_key = ?",
      [key]
    )
    guard let header = headers.first, let queryID = header[0], let updatedAt = header[1].flatMap(Int64.init) else {
      return nil
    }
    let decoder = JSONDecoder()
    let facts = try rows(
      url,
      """
      SELECT owned.entity_id, owned.attribute_id, owned.value_json, fact.tx_id, fact.tx_time_ms
      FROM instant_live_query_triples AS owned
      LEFT JOIN instant_triples AS fact
        ON fact.entity_id = owned.entity_id AND fact.attribute_id = owned.attribute_id
        AND fact.value_json = owned.value_json
      WHERE owned.query_id = ?
      """,
      [queryID]
    )
    let triples = try facts.map { row in
      InstantTriple(
        entityID: row[0] ?? "",
        attributeID: row[1] ?? "",
        value: try decoder.decode(InstantValue.self, from: Data((row[2] ?? "null").utf8)),
        txID: row[3] ?? "",
        txTime: InstantTimestamp(milliseconds: row[4].flatMap(Int64.init) ?? 0)
      )
    }
    return InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: key,
        triples: triples,
        pageInfo: try header[2].map { try decoder.decode(InstantQueryPageInfo.self, from: Data($0.utf8)) }
      ),
      updatedAt: InstantTimestamp(milliseconds: updatedAt)
    )
  }

  /// The facts the store holds for `entityID`, decoded from their stored form.
  static func storedFacts(_ url: URL, entityID: String) throws -> [InstantTriple] {
    try rows(url, "SELECT json FROM instant_triples WHERE entity_id = ?", [entityID]).compactMap { row in
      try row.first.flatMap { $0 }.map { try JSONDecoder().decode(InstantTriple.self, from: Data($0.utf8)) }
    }
  }

  /// The bytes of JSON a stored result's header row holds, and its page info column.
  static func header(_ url: URL, key: String) throws -> (jsonBytes: Int, pageInfoJSON: String?) {
    let found = try rows(
      url,
      "SELECT length(CAST(json AS BLOB)), page_info_json FROM instant_live_query_results WHERE query_key = ?",
      [key]
    )
    let row = try #require(found.first, "no stored result for the key")
    return (Int(row[0] ?? "0") ?? 0, row[1])
  }

  static func waitingMarkerCount(_ url: URL) throws -> Int {
    let found = try rows(
      url,
      "SELECT COUNT(*) FROM instant_sync_metadata WHERE key LIKE ?",
      [Self.waitingMarkerPrefix + "%"]
    )
    return Int(found.first?.first.flatMap { $0 } ?? "0") ?? 0
  }

  /// Writes `result` back in the layout 1.9.54 left: the results table without its page info column and the whole
  /// result as the header's JSON, a waiting marker holding `markerPageInfo` when given, and the conversion not recorded.
  static func writeOneDotNineDotFiftyFourLayout(
    _ url: URL,
    result: InstantPersistedLiveQueryResult,
    markerPageInfo: InstantQueryPageInfo??
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(result), as: UTF8.self)
    _ = try rows(url, "ALTER TABLE instant_live_query_results DROP COLUMN page_info_json")
    _ = try rows(url, "UPDATE instant_live_query_results SET json = ? WHERE query_key = ?", [json, result.key])
    if let markerPageInfo {
      struct Marker: Encodable { var pageInfo: InstantQueryPageInfo? }
      let value = String(decoding: try encoder.encode(Marker(pageInfo: markerPageInfo)), as: UTF8.self)
      _ = try rows(
        url,
        "INSERT OR REPLACE INTO instant_sync_metadata (key, value, updated_at_ms) VALUES (?, ?, 1)",
        [Self.waitingMarkerPrefix + result.key, value]
      )
    }
    _ = try rows(url, "DELETE FROM instant_schema_migrations WHERE name = ?", [Self.conversionMigrationName])
  }

  /// The bootstrap step that converts a store 1.9.54 left.
  static let conversionMigrationName = "0034_live_query_results_are_their_rows"

  /// The key prefix of the marker 1.9.54 wrote for a result whose JSON write waited.
  static let waitingMarkerPrefix = "live-query-result-json-waiting:"
}
