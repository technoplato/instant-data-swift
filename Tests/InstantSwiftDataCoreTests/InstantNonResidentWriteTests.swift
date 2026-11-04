// History:
// - 2026-11-04: added (#1165): a write to an entity this device keeps on disk but not in memory, local or from the
//   server, reads the entity's own facts first: it keeps the facts it does not restate, and strict checks see it.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// A write to an entity kept on disk but not in memory (#1165).
///
/// After a relaunch, memory holds the facts a stored result owns and the outbox's effects; the rest stay on disk
/// (#1006, `InstantLocalReadTests.aRelaunchedStoreReadsTheLinesItKeepsOnDisk`). A write prepared against memory alone
/// handles such an entity whole, as a new one (`InstantStore` `usesWholeEntityScope`), and the save's diff reads every
/// row of the entity from SQLite and deletes each one the write did not restate (`saveChangedEntityFactsWithoutTransaction`,
/// `saveTripleDiffWithoutTransaction`). The server keeps the facts, since a transaction sends only its own; this device
/// lost them until a refresh brought them back, and offline it never did. A strict update of the entity threw, and a
/// strict create of it passed. A server refresh that restates part of the entity (a query that selects some fields)
/// took the same whole-entity save.
///
/// Upstream keeps one store per query result and has no entity on disk only; the residency sweep (#1145) and closed
/// results kept on disk (#1500) make such entities routine here, so a write reads the entity's facts first.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantNonResidentWriteTests {
  /// One attribute of a line kept on disk only, as an app moves a line: the line keeps its other facts on disk, and
  /// memory holds the whole line afterwards, so the recording's live lines show it.
  @Test
  func aWriteToALineKeptOnDiskKeepsItsOtherFacts() async throws {
    let (url, runtime) = try await Self.relaunchedStore()

    try await runtime.transact(
      InstantStoreTransaction(id: "move-line-0", operations: [.insert(Self.fact("line-0", "lines/index", .number(100)))]),
      createdAt: Self.now
    )

    expectNoDifference(
      try Self.facts(url, entityID: "line-0"),
      [
        "lines/id=\"line-0\"",
        "lines/index=100",
        "lines/recordingID=\"recording-1\"",
        "lines/text=\"Line 0\"",
      ]
    )
    let memory = try await InstantLocalReadTests.firstEmission(
      of: runtime, InstantLocalReadTests.recordingLines("recording-1")
    )
    expectNoDifference(memory.values.map(\.id), ["line-2", "line-0"], "the written line is in memory, whole")
  }

  /// A strict update (`requireEntityExists`, Scribe's `updateExisting`) of a line kept on disk only succeeds, as it does
  /// for a line in memory.
  @Test
  func aStrictUpdateOfALineKeptOnDiskSucceeds() async throws {
    let (url, runtime) = try await Self.relaunchedStore()

    try await runtime.transact(
      InstantStoreTransaction(
        id: "update-line-1",
        operations: [
          .requireEntityExists(entityID: "line-1", namespace: "lines"),
          .insert(Self.fact("line-1", "lines/index", .number(101))),
        ]
      ),
      createdAt: Self.now
    )

    expectNoDifference(
      try Self.facts(url, entityID: "line-1"),
      [
        "lines/id=\"line-1\"",
        "lines/index=101",
        "lines/recordingID=\"recording-1\"",
        "lines/text=\"Line 1\"",
      ]
    )
  }

  /// A strict create (`requireEntityMissing`) of a line kept on disk only fails, as it does for a line in memory, and
  /// leaves the line as it was.
  @Test
  func aStrictCreateOfALineKeptOnDiskFails() async throws {
    let (url, runtime) = try await Self.relaunchedStore()

    await #expect(throws: InstantError.self) {
      try await runtime.transact(
        InstantStoreTransaction(
          id: "create-line-1",
          operations: [
            .requireEntityMissing(entityID: "line-1", namespace: "lines"),
            .insert(Self.fact("line-1", "lines/index", .number(101))),
          ]
        ),
        createdAt: Self.now
      )
    }

    expectNoDifference(
      try Self.facts(url, entityID: "line-1"),
      [
        "lines/id=\"line-1\"",
        "lines/index=1",
        "lines/recordingID=\"recording-1\"",
        "lines/text=\"Line 1\"",
      ]
    )
  }

  /// A server refresh that restates one field of a line kept on disk only (a query that selects only `index`) keeps the
  /// line's other facts on disk, and memory holds the whole line afterwards.
  @Test
  func aServerRefreshOfPartOfALineKeptOnDiskKeepsItsOtherFacts() async throws {
    let (url, runtime) = try await Self.relaunchedStore()

    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      InstantStoreTransaction(
        id: "server-refresh-line-0",
        operations: [.insert(Self.fact("line-0", "lines/index", .number(100), txID: "server-refresh-line-0"))]
      ),
      attributesToMerge: []
    )

    expectNoDifference(
      try Self.facts(url, entityID: "line-0"),
      [
        "lines/id=\"line-0\"",
        "lines/index=100",
        "lines/recordingID=\"recording-1\"",
        "lines/text=\"Line 0\"",
      ]
    )
    let memory = try await InstantLocalReadTests.firstEmission(
      of: runtime, InstantLocalReadTests.recordingLines("recording-1")
    )
    expectNoDifference(memory.values.map(\.id), ["line-2", "line-0"], "the restated line is in memory, whole")
  }
}

// MARK: - Fixtures

extension InstantNonResidentWriteTests {
  static let now = InstantTimestamp(milliseconds: 1_790_900_000_000)

  static func fact(
    _ entityID: String, _ attributeID: String, _ value: InstantValue, txID: String = "local"
  ) -> InstantTriple {
    InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: txID, txTime: now)
  }

  /// A store as a relaunch finds it: three lines of one recording, the newest owned by a stored result (in memory), the
  /// other two on disk only; and a runtime opened on it, whose memory holds line-2 alone.
  static func relaunchedStore() async throws -> (URL, InstantRuntime) {
    let url = try InstantLocalReadTests.temporaryCacheURL()
    let lines = (0..<3).map { InstantLocalReadTests.line($0, recordingID: "recording-1") }
    try await InstantLocalReadTests.seed(url, lines: lines, ownedBy: ["preview": lines.suffix(1)])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantLocalReadTests.configuration(url, lookup: true)
    )
    let memory = try await InstantLocalReadTests.firstEmission(
      of: runtime, InstantLocalReadTests.recordingLines("recording-1")
    )
    expectNoDifference(memory.values.map(\.id), ["line-2"], "line-0 and line-1 are on disk, not in memory")
    return (url, runtime)
  }

  /// `entityID`'s facts as SQLite holds them: each attribute with its value's text.
  static func facts(_ store: URL, entityID: String) throws -> [String] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      defer { sqlite3_close_v2(connection) }
      throw StorageIOError("open \(store.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    let sql = "SELECT attribute_id, value_json FROM instant_triples WHERE entity_id = ? ORDER BY attribute_id"
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, entityID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    var facts: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let attribute = String(cString: sqlite3_column_text(statement, 0))
      let value = String(cString: sqlite3_column_text(statement, 1))
      facts.append("\(attribute)=\(Self.plain(value))")
    }
    return facts
  }

  /// A stored value's text with the library's enum wrapper taken off (`{"string":{"_0":"x"}}` reads `"x"`), so the
  /// expectation reads as the value.
  static func plain(_ stored: String) -> String {
    guard let data = stored.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let (_, wrapped) = object.first,
      let inner = (wrapped as? [String: Any])?["_0"]
    else { return stored }
    if let string = inner as? String { return "\"\(string)\"" }
    if let number = inner as? NSNumber { return number.stringValue }
    return stored
  }
}
