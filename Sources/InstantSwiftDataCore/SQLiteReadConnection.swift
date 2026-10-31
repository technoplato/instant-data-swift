// History:
// - 2026-10-23: added (#1006): local reads read SQLite on their own read-only connection, beside the writer.
// - 2026-10-24: a reopened query reads its closed stored result here, before it takes the operation gate (#1131).
// - 2026-10-24: the prune reads and decodes its next batch's stored results here, before it takes the gate (#1129).
// - 2026-10-25: fact rows are read by `InstantFactRowReader` (#1150).
// - 2026-10-27: the lookup's statement is `entityIDsSQL(lookupAttributeIDs:)`, which a guard plans (#1244).
// - 2026-10-31: the prune's stored results are read from their header and ownership rows, as the writer reads them
//   (`InstantStoredLiveQueryResultRows`); no result's write waits, so none is left out for it (#1426).

import Foundation
import SQLite3
import os

/// A read-only connection to the store's SQLite file, for reads that must not wait for writes (#1006).
///
/// ``SQLitePersistenceStore`` reads and writes through one connection on one actor, so a read there waits behind every
/// write: on one device a server apply's commit held that actor 3 to 6 seconds while a transcript's text waited to be
/// read. The store's file is in WAL mode, where a second connection reads the last committed state while the writer
/// writes; SQLiteData reads the same way, through a `DatabasePool`'s readers. Each call here runs in one read
/// transaction, so it sees one committed state.
///
/// The connection opens on its first use, after the store's bootstrap made the schema. A failed open is tried again
/// on the next call; until it opens, callers read on the store.
actor SQLiteReadConnection {
  private let fileURL: URL
  private let deferredAttributeIDs: Set<String>
  private let lookupAttributeIDs: Set<String>
  private let handle = Handle()
  private let encoder: JSONEncoder
  private let decoder = JSONDecoder()
  /// Deferred values decoded here, added to the store's own count for tests and diagnostics.
  private let decodeMetrics = OSAllocatedUnfairLock(initialState: InstantDeferredValueDecodeMetrics())

  /// IDs per statement in a batched `IN` list.
  private static let batchSize = 500

  init(fileURL: URL, deferredAttributeIDs: Set<String>, lookupAttributeIDs: Set<String>) {
    self.fileURL = fileURL
    self.deferredAttributeIDs = deferredAttributeIDs
    self.lookupAttributeIDs = lookupAttributeIDs
    let encoder = JSONEncoder()
    // The store writes `value_json` with sorted keys; a lookup must compare the same bytes.
    encoder.outputFormatting = [.sortedKeys]
    self.encoder = encoder
  }

  /// The deferred values decoded on this connection.
  nonisolated var deferredValueDecodeMetrics: InstantDeferredValueDecodeMetrics {
    decodeMetrics.withLock { $0 }
  }

  /// `attributeIDs`' values of `entityIDs`, as ``SQLitePersistenceStore/loadDeferredValues(attributeIDs:entityIDs:)``
  /// reads them.
  func loadDeferredValues(attributeIDs: Set<String>, entityIDs: Set<String>) throws -> [InstantTriple] {
    let energy = InstantEnergyMeter.begin(.deferredHydrate)
    defer { energy.end() }
    let attributeIDs = attributeIDs.intersection(deferredAttributeIDs)
    guard !attributeIDs.isEmpty, !entityIDs.isEmpty else { return [] }
    let attributeList = attributeIDs.sorted()
    let attributePlaceholders = Array(repeating: "?", count: attributeList.count).joined(separator: ", ")
    var triples: [InstantTriple] = []
    var encodedByteCount = 0
    var reader = InstantFactRowReader(decoder: decoder)
    try readTransaction { connection in
      for batch in Self.batches(of: entityIDs) {
        let entityPlaceholders = Array(repeating: "?", count: batch.count).joined(separator: ", ")
        try Self.withStatement(
          """
          SELECT \(InstantFactRowReader.columns) FROM instant_triples
          WHERE attribute_id IN (\(attributePlaceholders)) AND entity_id IN (\(entityPlaceholders))
          ORDER BY entity_id, attribute_id, value_json
          """,
          bindings: attributeList + batch,
          on: connection
        ) { statement in
          try readFacts(statement, with: &reader, into: &triples) { _, byteCount in encodedByteCount += byteCount }
        }
      }
    }
    let (valueCount, byteCount) = (triples.count, encodedByteCount)
    decodeMetrics.withLock {
      $0.valueCount += valueCount
      $0.encodedByteCount += byteCount
    }
    return triples
  }

  /// The entities whose `attributeID` holds `value`, read through the lookup index (``InstantLocalLookupPolicy``,
  /// ``SQLitePersistenceStore/lookupIndexName``).
  func entityIDs(attributeID: String, value: InstantValue) throws -> Set<String> {
    let valueJSON = try String(decoding: encoder.encode(value), as: UTF8.self)
    var ids: Set<String> = []
    try readTransaction { connection in
      let rows = try Self.selectTexts(
        Self.entityIDsSQL(lookupAttributeIDs: lookupAttributeIDs),
        bindings: [attributeID, valueJSON],
        on: connection
      )
      ids = Set(rows)
    }
    return ids
  }

  /// The statement ``entityIDs(attributeID:value:)`` prepares. The index's own condition comes first, word for word, so
  /// SQLite can prove the partial index applies; INDEXED BY makes a missing index an error instead of a scan of the
  /// whole table. A lookup written any other way reads every fact (#1244: 402,191 rows, about 50 ms on a Mac, on one
  /// device's store); `FootgunGuardTests` plans this text.
  static func entityIDsSQL(lookupAttributeIDs: Set<String>) -> String {
    """
    SELECT entity_id FROM instant_triples INDEXED BY \(SQLitePersistenceStore.lookupIndexName)
    WHERE \(SQLitePersistenceStore.lookupIndexCondition(lookupAttributeIDs)) AND attribute_id = ? AND value_json = ?
    """
  }

  /// The facts of `entityIDs`, deferred values included, from one committed state: every fact, or only those of
  /// `attributeIDs`.
  func facts(of entityIDs: Set<String>, attributeIDs: Set<String>? = nil) throws -> [InstantTriple] {
    guard !entityIDs.isEmpty, attributeIDs?.isEmpty != true else { return [] }
    let attributeList = attributeIDs?.sorted() ?? []
    let attributeCondition =
      attributeIDs == nil
      ? ""
      : " AND attribute_id IN (" + Array(repeating: "?", count: attributeList.count).joined(separator: ", ") + ")"
    var triples: [InstantTriple] = []
    var deferredCount = 0
    var deferredByteCount = 0
    var reader = InstantFactRowReader(decoder: decoder)
    try readTransaction { connection in
      for batch in Self.batches(of: entityIDs) {
        let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ", ")
        try Self.withStatement(
          """
          SELECT \(InstantFactRowReader.columns) FROM instant_triples WHERE entity_id IN (\(placeholders))\(attributeCondition)
          ORDER BY entity_id, attribute_id, value_json
          """,
          bindings: batch + attributeList,
          on: connection
        ) { statement in
          try readFacts(statement, with: &reader, into: &triples) { triple, byteCount in
            guard deferredAttributeIDs.contains(triple.attributeID) else { return }
            deferredCount += 1
            deferredByteCount += byteCount
          }
        }
      }
    }
    if deferredCount > 0 {
      let (valueCount, byteCount) = (deferredCount, deferredByteCount)
      decodeMetrics.withLock {
        $0.valueCount += valueCount
        $0.encodedByteCount += byteCount
      }
    }
    return triples
  }

  /// The closed query result stored under `key`, decoded, if a prune unloaded one (#1006), as
  /// ``SQLitePersistenceStore/unloadedLiveQueryResult(key:)`` reads it (#1131): a reopened query reads it here before it
  /// takes the operation gate, which it held for the read and decode (1,718 ms for a 75,640-fact `$files` list).
  func unloadedLiveQueryResult(key: String) throws -> InstantUnloadedLiveQueryResultRead? {
    var read: InstantUnloadedLiveQueryResultRead?
    try readTransaction { connection in
      var statement: OpaquePointer?
      guard
        sqlite3_prepare_v2(
          connection,
          "SELECT triple_count, updated_at_ms, json FROM instant_unloaded_live_query_results WHERE query_key = ? LIMIT 1",
          -1,
          &statement,
          nil
        ) == SQLITE_OK, let statement
      else {
        throw Self.failure(operation: "prepare a local read", message: Self.errorMessage(connection), path: nil)
      }
      defer { sqlite3_finalize(statement) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK else {
        throw Self.failure(operation: "bind a local read", message: Self.errorMessage(connection), path: nil)
      }
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return }
      guard step == SQLITE_ROW, let json = sqlite3_column_text(statement, 2) else {
        throw Self.failure(operation: "step a local read", message: Self.errorMessage(connection), path: nil)
      }
      let tripleCount = Int(sqlite3_column_int64(statement, 0))
      let updatedAtMilliseconds = sqlite3_column_int64(statement, 1)
      let result: InstantPersistedLiveQueryResult
      do {
        result = try decoder.decode(InstantPersistedLiveQueryResult.self, from: Data(String(cString: json).utf8))
      } catch {
        throw Self.failure(
          operation: "decode a closed query result on the local read connection",
          message: "The stored result could not be decoded: \(error)",
          path: fileURL.path
        )
      }
      read = InstantUnloadedLiveQueryResultRead(
        result: result,
        rowTripleCount: tripleCount,
        rowUpdatedAtMilliseconds: updatedAtMilliseconds
      )
    }
    return read
  }

  /// The stored results of `keys`, read from their rows, each with what names its row, for the prune's next batch
  /// (#1129): it reads them here before it takes the operation gate, which it held 265 ms to decode the `$files` list.
  /// A key with no stored result is left out, as is one whose rows cannot be read: the batch reads it under the gate.
  func storedLiveQueryResults(keys: [String]) throws -> [String: InstantUnloadedLiveQueryResultRead] {
    var reads: [String: InstantUnloadedLiveQueryResultRead] = [:]
    try readTransaction { connection in
      let header = try Self.prepared(InstantStoredLiveQueryResultRows.headerSQL, on: connection)
      defer { sqlite3_finalize(header) }
      let facts = try Self.prepared(InstantStoredLiveQueryResultRows.factsSQL, on: connection)
      defer { sqlite3_finalize(facts) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      for key in keys {
        sqlite3_reset(header)
        guard sqlite3_bind_text(header, 1, key, -1, transient) == SQLITE_OK else {
          throw Self.failure(operation: "bind a local read", message: Self.errorMessage(connection), path: nil)
        }
        let step = sqlite3_step(header)
        if step == SQLITE_DONE { continue }
        guard step == SQLITE_ROW else {
          throw Self.failure(operation: "step a local read", message: Self.errorMessage(connection), path: nil)
        }
        guard let row = try? InstantStoredLiveQueryResultRows.Header(row: header, decoder: decoder) else { continue }
        sqlite3_reset(facts)
        guard
          sqlite3_bind_int64(facts, 1, row.queryID) == SQLITE_OK,
          sqlite3_bind_text(facts, 2, InstantStoredLiveQueryResultRows.unstoredFactTransactionID, -1, transient)
            == SQLITE_OK
        else {
          throw Self.failure(operation: "bind a local read", message: Self.errorMessage(connection), path: nil)
        }
        guard
          let result = try? InstantStoredLiveQueryResultRows.result(
            key: key,
            header: row,
            facts: facts,
            decoder: decoder
          )
        else { continue }
        reads[key] = InstantUnloadedLiveQueryResultRead(
          result: result,
          rowTripleCount: row.tripleCount,
          rowUpdatedAtMilliseconds: row.updatedAtMilliseconds
        )
      }
    }
    return reads
  }

  /// `sql`, prepared on `connection`.
  private static func prepared(_ sql: String, on connection: OpaquePointer) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      sqlite3_finalize(statement)
      throw failure(operation: "prepare a local read", message: errorMessage(connection), path: nil)
    }
    return statement
  }

  // MARK: - SQLite

  /// Runs `body` in one read transaction. A failure closes the connection, so the next read opens the store's file
  /// again: a file that was replaced or removed keeps failing on the handle that held it.
  private func readTransaction(_ body: (OpaquePointer) throws -> Void) throws {
    let connection = try open()
    do {
      try Self.execute("BEGIN DEFERRED", on: connection)
      do {
        try body(connection)
        try Self.execute("COMMIT", on: connection)
      } catch {
        try? Self.execute("ROLLBACK", on: connection)
        throw error
      }
    } catch {
      handle.close()
      throw error
    }
  }

  private func open() throws -> OpaquePointer {
    if let raw = handle.raw { return raw }
    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
    // #1245: through the file meter's VFS, so a read's sort spilled to a transient file counts.
    guard sqlite3_open_v2(fileURL.path, &opened, flags, InstantSQLiteFileMeter.registeredVFSName()) == SQLITE_OK,
      let opened
    else {
      let message = opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "SQLite could not open it."
      sqlite3_close_v2(opened)
      throw Self.failure(operation: "open the local read connection", message: message, path: fileURL.path)
    }
    // Five seconds, the codebase's bound for any wait; a WAL reader waits only while the file recovers.
    sqlite3_busy_timeout(opened, 5_000)
    do {
      try Self.execute("PRAGMA query_only = ON", on: opened)
      // A small page cache: reads here are pages of rows, and the writer keeps its own cache.
      try Self.execute("PRAGMA cache_size = -2048", on: opened)
    } catch {
      sqlite3_close_v2(opened)
      throw error
    }
    handle.raw = opened
    return opened
  }

  private static func batches(of ids: Set<String>) -> [[String]] {
    let sorted = ids.sorted()
    return stride(from: 0, to: sorted.count, by: batchSize).map {
      Array(sorted[$0..<min($0 + batchSize, sorted.count)])
    }
  }

  private static func execute(_ sql: String, on connection: OpaquePointer) throws {
    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
      throw failure(operation: "run '\(sql)' on the local read connection", message: errorMessage(connection), path: nil)
    }
  }

  /// `statement`'s facts through `reader`, a failure reported as this connection's.
  private func readFacts(
    _ statement: OpaquePointer,
    with reader: inout InstantFactRowReader,
    into triples: inout [InstantTriple],
    counting: (InstantTriple, Int) -> Void
  ) throws {
    do {
      try reader.read(statement, into: &triples, counting: counting)
    } catch let failure as InstantFactRowReader.ReadFailure {
      throw Self.failure(operation: failure.operation, message: failure.message, path: fileURL.path)
    }
  }

  /// `sql` prepared with `bindings`, for `body` to step; finalized after.
  private static func withStatement<Result>(
    _ sql: String,
    bindings: [String],
    on connection: OpaquePointer,
    _ body: (OpaquePointer) throws -> Result
  ) throws -> Result {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw failure(operation: "prepare a local read", message: errorMessage(connection), path: nil)
    }
    defer { sqlite3_finalize(statement) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, binding) in bindings.enumerated() {
      guard sqlite3_bind_text(statement, Int32(index + 1), binding, -1, transient) == SQLITE_OK else {
        throw failure(operation: "bind a local read", message: errorMessage(connection), path: nil)
      }
    }
    return try body(statement)
  }

  /// The first column of every row `sql` selects, as text.
  private static func selectTexts(
    _ sql: String,
    bindings: [String],
    on connection: OpaquePointer
  ) throws -> [String] {
    try withStatement(sql, bindings: bindings, on: connection) { statement in
      var texts: [String] = []
      while true {
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { break }
        guard result == SQLITE_ROW else {
          throw failure(operation: "step a local read", message: errorMessage(connection), path: nil)
        }
        if let text = sqlite3_column_text(statement, 0) {
          texts.append(String(cString: text))
        }
      }
      return texts
    }
  }

  /// SQLite's message with its extended result code, which names the failure ("disk I/O error" alone does not).
  static func errorMessage(_ connection: OpaquePointer?) -> String {
    let message = sqlite3_errmsg(connection).map { String(cString: $0) } ?? "Unknown SQLite error."
    return "\(message) (SQLite \(sqlite3_extended_errcode(connection)))"
  }

  static func failure(operation: String, message: String, path: String?) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: operation,
      message: message,
      recovery: path.map { "Inspect the local SQLite cache at \($0); reads use the store's own connection meanwhile." }
        ?? "Reads use the store's own connection meanwhile."
    )
  }

  /// The open connection, closed when the last reference goes.
  // SAFETY: only the enclosing `SQLiteReadConnection` actor reads or writes `raw`; `deinit` runs once no reference is
  // left, so no actor turn can use it then.
  private final class Handle: @unchecked Sendable {
    var raw: OpaquePointer?

    func close() {
      sqlite3_close_v2(raw)
      raw = nil
    }

    deinit {
      sqlite3_close_v2(raw)
    }
  }
}
