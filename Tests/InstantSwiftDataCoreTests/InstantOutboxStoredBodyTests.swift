// History:
// - 2026-10-31: added (#1510, #1463): a live write's body is stored compressed and in its leaf, its lifecycle derived
//   from it; every budget keeps counting the JSON's bytes.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #1463, #1510: a phone's local save wrote 24.4 log pages, 4.7 of them its body. A `WITHOUT ROWID` cell keeps at most
/// 1,002 bytes on its leaf (4 KB pages), so a 6.9-17.9 KB body took two to four overflow pages, allocated from the free
/// list at the save (page 1 and a trunk page rewritten) and freed at the echo (both again). Compressed, and without its
/// 346-byte lifecycle beside it, 6 of the 8 live bodies on that phone's store fit their leaf. A lifecycle is the body
/// with its operations emptied, so a reader derives it; every budget still counts the JSON's bytes.
@Suite(.serialized)
struct InstantOutboxStoredBodyTests {
  /// Scribe's line writes (three interims, the final line, the recording's summary and its duration, for two lines) are
  /// stored compressed, with no lifecycle beside them, and none takes an overflow page.
  @Test
  func aLiveWritesBodyIsStoredCompressedInItsLeaf() async throws {
    let fixture = try await FastDrainFixture.make(
      suffix: "stored-body-leaf",
      serverSegmentCount: 4,
      pendingSegmentCount: 2
    )
    let database = fixture.configuration.persistenceURL
    defer { StoredBodyFile.remove(database) }

    #expect(
      try StoredBodyFile.strings("SELECT name FROM pragma_table_info('instant_outbox_bodies')", in: database)
        .contains("lifecycle_bytes"),
      "instant_outbox_bodies has no lifecycle_bytes column"
    )
    let rows = try StoredBodyFile.strings(
      """
      SELECT typeof(body.json) || ' ' || (length(CAST(body.json AS BLOB)) < outbox.encoded_body_bytes)
        || ' ' || (body.lifecycle_json IS NULL)
      FROM instant_outbox AS outbox JOIN instant_outbox_bodies AS body ON body.mutation_id = outbox.mutation_id
      ORDER BY outbox.created_at_ms, outbox.mutation_id
      """,
      in: database
    )
    #expect(!rows.isEmpty, "\(rows)")
    // Each row: its body a BLOB shorter than its JSON, and no lifecycle stored beside it.
    #expect(rows.allSatisfy { $0 == "blob 1 1" }, "\(rows)")
    let overflowPages = try StoredBodyFile.strings(
      "SELECT count(*) FROM dbstat WHERE name = 'instant_outbox_bodies' AND pagetype = 'overflow'",
      in: database
    )
    #expect(overflowPages == ["0"], "overflow pages of instant_outbox_bodies: \(overflowPages)")

    // One more line's first write: the recorder names no overflow page of the body's b-tree in its save.
    var writer = fixture
    let before = await writer.runtime.persistence.writeRecordForTesting()
    _ = try await writer.writeSegments(1)
    let recorded = await writer.runtime.persistence.writeRecordForTesting().subtracting(before)
    let bodies = recorded.btrees["instant_outbox_bodies"]
    #expect((bodies?.logPages ?? 0) > 0, "\(recorded.btrees)")
    #expect(bodies?.overflowLogPages == 0, "\(recorded.btrees)")
    _ = try? await writer.runtime.closeConnection()
  }

  /// A stored body decodes to the write that was saved, field for field, after a relaunch: interims, finals with their
  /// rollbacks, a live line's delete, an attachment, and a write that failed (whose lifecycle is derived from its body).
  @Test
  func aStoredBodyDecodesToTheWriteThatWasSaved() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "stored-body-round-trip",
      serverSegmentCount: 2,
      pendingSegmentCount: 2,
      liveLines: true,
      attachments: true
    )
    let database = fixture.configuration.persistenceURL
    defer { StoredBodyFile.remove(database) }
    let pending = await fixture.runtime.pendingMutations()
    let failing = try #require(pending.last)
    let refused = try await fixture.runtime.failMutation(id: failing.id, message: "rejected by the server")
    let saved = await fixture.runtime.pendingMutations()

    try await fixture.relaunch()
    let loaded = await fixture.runtime.pendingMutations()
    let durable = try await fixture.runtime.persistence.loadState().snapshot.outbox

    expectNoDifference(loaded, saved)
    #expect(loaded == saved)
    // The failed write stays in the outbox, in its place, with its failure.
    #expect(durable.map(\.id) == pending.map(\.id), "\(durable.map(\.id))")
    let failed = try #require(durable.first { $0.id == failing.id })
    #expect(failed.status == .failed, "\(failed.status)")
    #expect(failed.failureMessage == refused.failureMessage, "\(String(describing: failed.failureMessage))")
    _ = try? await fixture.runtime.closeConnection()
  }

  /// A body and lifecycle an older version stored as text read the same, and its write is still claimed, accepted and
  /// confirmed: a store keeps working across the upgrade without rewriting what it holds.
  @Test
  func aBodyAnOlderVersionStoredAsTextStillReads() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "stored-body-text",
      serverSegmentCount: 2,
      pendingSegmentCount: 1
    )
    let database = fixture.configuration.persistenceURL
    defer { StoredBodyFile.remove(database) }
    let saved = await fixture.runtime.pendingMutations()
    _ = try? await fixture.runtime.closeConnection()

    // Each body as the release before stores it: the JSON as text, its lifecycle beside it.
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    for mutation in saved {
      let body = SQLitePersistenceStore.storedOutboxBody(mutation)
      try StoredBodyFile.execute(
        "UPDATE instant_outbox_bodies SET json = ?, lifecycle_json = ? WHERE mutation_id = ?",
        [
          String(decoding: try encoder.encode(body), as: UTF8.self),
          String(decoding: try encoder.encode(body.compactedForMemory), as: UTF8.self),
          mutation.id,
        ],
        in: database
      )
    }
    if try StoredBodyFile.strings("SELECT name FROM pragma_table_info('instant_outbox_bodies')", in: database)
      .contains("lifecycle_bytes")
    {
      try StoredBodyFile.execute("UPDATE instant_outbox_bodies SET lifecycle_bytes = NULL", [], in: database)
    }

    try await fixture.relaunch()
    let loaded = await fixture.runtime.pendingMutations()
    expectNoDifference(loaded, saved)
    #expect(loaded == saved)

    let (token, claimed) = try await fixture.claimWindow()
    let first = try #require(claimed.first)
    #expect(first.id == saved.first?.id)
    _ = try await fixture.acceptAndRefresh(first, claimToken: token)
    let remaining = await fixture.runtime.pendingMutations()
    #expect(!remaining.contains { $0.id == first.id }, "\(remaining.map(\.id))")
    _ = try? await fixture.runtime.closeConnection()
  }

  /// Every budget counts the JSON's bytes, as before: a row's `encoded_body_bytes` is its stored body's JSON size and
  /// its lifecycle's bytes are the lifecycle's JSON size, whatever the stored length.
  @Test
  func everyBudgetCountsTheJSONsBytes() async throws {
    let fixture = try await FastDrainFixture.make(
      suffix: "stored-body-budgets",
      serverSegmentCount: 2,
      pendingSegmentCount: 1
    )
    let database = fixture.configuration.persistenceURL
    defer { StoredBodyFile.remove(database) }
    let saved = await fixture.runtime.pendingMutations()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let expected = try saved.map { mutation in
      let body = SQLitePersistenceStore.storedOutboxBody(mutation)
      return "\(mutation.id) \(try encoder.encode(body).count) \(try encoder.encode(body.compactedForMemory).count)"
    }
    let hasLifecycleBytes = try StoredBodyFile.strings(
      "SELECT name FROM pragma_table_info('instant_outbox_bodies')",
      in: database
    ).contains("lifecycle_bytes")
    #expect(hasLifecycleBytes, "instant_outbox_bodies has no lifecycle_bytes column")
    let lifecycleBytes = hasLifecycleBytes
      ? "body.lifecycle_bytes" : "length(CAST(body.lifecycle_json AS BLOB))"
    let stored = try StoredBodyFile.strings(
      """
      SELECT outbox.mutation_id || ' ' || outbox.encoded_body_bytes || ' ' || \(lifecycleBytes)
      FROM instant_outbox AS outbox JOIN instant_outbox_bodies AS body ON body.mutation_id = outbox.mutation_id
      ORDER BY outbox.created_at_ms, outbox.mutation_id
      """,
      in: database
    )
    expectNoDifference(stored, expected)
    #expect(stored == expected)
    _ = try? await fixture.runtime.closeConnection()
  }
}

/// The store's file read and written through its own connection, as another process would (#1463's tests).
private enum StoredBodyFile {
  static func strings(_ sql: String, in url: URL) throws -> [String] {
    try withConnection(url) { connection in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        throw StorageIOError("\(sql): \(String(cString: sqlite3_errmsg(connection)))")
      }
      defer { sqlite3_finalize(statement) }
      var values: [String] = []
      while sqlite3_step(statement) == SQLITE_ROW {
        values.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "NULL")
      }
      return values
    }
  }

  static func execute(_ sql: String, _ texts: [String], in url: URL) throws {
    try withConnection(url) { connection in
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        throw StorageIOError("\(sql): \(String(cString: sqlite3_errmsg(connection)))")
      }
      defer { sqlite3_finalize(statement) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      for (index, text) in texts.enumerated() {
        sqlite3_bind_text(statement, Int32(index + 1), text, -1, transient)
      }
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw StorageIOError("\(sql): \(String(cString: sqlite3_errmsg(connection)))")
      }
    }
  }

  static func remove(_ url: URL) {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
  }

  private static func withConnection<Value>(_ url: URL, _ body: (OpaquePointer) throws -> Value) throws -> Value {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let connection else {
      sqlite3_close_v2(connection)
      throw StorageIOError("could not open \(url.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    sqlite3_busy_timeout(connection, 5_000)
    return try body(connection)
  }
}

/// A body column's JSON as a test reads it from the file (#1463): a compressed body inflated, text as it is, nil for
/// NULL or a value that does not inflate.
func storedOutboxBodyJSON(_ statement: OpaquePointer?, _ column: Int32) -> String? {
  switch sqlite3_column_type(statement, column) {
  case SQLITE_NULL:
    return nil
  case SQLITE_BLOB:
    guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
    let count = Int(sqlite3_column_bytes(statement, column))
    return InstantOutboxStoredBody.json(fromCompressed: UnsafeRawBufferPointer(start: bytes, count: count))
  default:
    return sqlite3_column_text(statement, column).map { String(cString: $0) }
  }
}

/// Writes every compressed outbox body in `url` back as its JSON text, with its lifecycle beside it and no
/// `lifecycle_bytes`: the shape a release before #1463 stores, for fixtures that rebuild an older store.
func rewriteStoredOutboxBodiesAsText(in url: URL) throws {
  var connection: OpaquePointer?
  guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let connection else {
    sqlite3_close_v2(connection)
    throw StorageIOError("could not open \(url.lastPathComponent)")
  }
  defer { sqlite3_close_v2(connection) }
  sqlite3_busy_timeout(connection, 5_000)
  func rows(_ sql: String, _ read: (OpaquePointer?) throws -> Void) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError("\(sql): \(String(cString: sqlite3_errmsg(connection)))")
    }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW { try read(statement) }
  }
  var hasLifecycleBytes = false
  try rows("SELECT name FROM pragma_table_info('instant_outbox_bodies')") { statement in
    if sqlite3_column_text(statement, 0).map({ String(cString: $0) }) == "lifecycle_bytes" { hasLifecycleBytes = true }
  }
  var bodies: [(id: String, json: String)] = []
  try rows("SELECT mutation_id, json FROM instant_outbox_bodies WHERE typeof(json) = 'blob'") { statement in
    guard let id = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
      let json = storedOutboxBodyJSON(statement, 1)
    else { throw StorageIOError("a compressed outbox body did not inflate") }
    bodies.append((id, json))
  }
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  let update = hasLifecycleBytes
    ? "UPDATE instant_outbox_bodies SET json = ?, lifecycle_json = ?, lifecycle_bytes = NULL WHERE mutation_id = ?"
    : "UPDATE instant_outbox_bodies SET json = ?, lifecycle_json = ? WHERE mutation_id = ?"
  for body in bodies {
    let mutation = try JSONDecoder().decode(PendingMutation.self, from: Data(body.json.utf8))
    let lifecycle = String(decoding: try encoder.encode(mutation.compactedForMemory), as: UTF8.self)
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, update, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError("\(update): \(String(cString: sqlite3_errmsg(connection)))")
    }
    defer { sqlite3_finalize(statement) }
    for (index, text) in [body.json, lifecycle, body.id].enumerated() {
      sqlite3_bind_text(statement, Int32(index + 1), text, -1, transient)
    }
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw StorageIOError("\(update): \(String(cString: sqlite3_errmsg(connection)))")
    }
  }
}
