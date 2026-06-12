import Foundation
import SQLite3

public struct InstantPersistenceSnapshot: Hashable, Codable, Sendable {
  public var store: InstantStoreSnapshot
  public var outbox: [PendingMutation]

  public init(store: InstantStoreSnapshot = InstantStoreSnapshot(), outbox: [PendingMutation] = []) {
    self.store = store
    self.outbox = outbox
  }
}

public struct InstantPersistenceState: Hashable, Sendable {
  public var snapshot: InstantPersistenceSnapshot
  public var storeRevision: Int64

  public init(snapshot: InstantPersistenceSnapshot, storeRevision: Int64) {
    self.snapshot = snapshot
    self.storeRevision = storeRevision
  }
}

public actor SQLitePersistenceStore {
  private let fileURL: URL
  private let connection: SQLiteConnection
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(fileURL: URL) throws {
    self.fileURL = fileURL
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
    self.decoder = JSONDecoder()

    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(fileURL.path, &opened, flags, nil) == SQLITE_OK
    else {
      let message = opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not open \(fileURL.path)."
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "open local cache",
        message: message,
        recovery: "Check that the cache directory is writable, or choose another persistence path."
      )
    }
    guard sqlite3_busy_timeout(opened, 10_000) == SQLITE_OK else {
      let message = opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not configure a busy timeout for \(fileURL.path)."
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "configure local cache",
        message: message,
        recovery: "Check that the cache directory is writable, or choose another persistence path."
      )
    }
    self.connection = SQLiteConnection(opened)
  }

  public func bootstrap() throws {
    try execute("PRAGMA journal_mode = WAL")
    try execute("PRAGMA foreign_keys = ON")
    try execute(
      """
      CREATE TABLE IF NOT EXISTS instant_schema_migrations (
        name TEXT PRIMARY KEY NOT NULL,
        applied_at_ms INTEGER NOT NULL
      )
      """
    )
    try migrate(name: "0001_initial_cache") {
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_attributes (
          id TEXT PRIMARY KEY NOT NULL,
          json TEXT NOT NULL
        )
        """
      )
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_triples (
          entity_id TEXT NOT NULL,
          attribute_id TEXT NOT NULL,
          value_json TEXT NOT NULL,
          tx_id TEXT NOT NULL,
          tx_time_ms INTEGER NOT NULL,
          json TEXT NOT NULL,
          PRIMARY KEY (entity_id, attribute_id, value_json)
        )
        """
      )
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_outbox (
          mutation_id TEXT PRIMARY KEY NOT NULL,
          status TEXT NOT NULL,
          created_at_ms INTEGER NOT NULL,
          json TEXT NOT NULL
        )
        """
      )
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_local_ids (
          name TEXT PRIMARY KEY NOT NULL,
          entity_id TEXT NOT NULL
        )
        """
      )
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_auth_sessions (
          key TEXT PRIMARY KEY NOT NULL,
          json TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
        """
      )
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_query_cache (
          query_id TEXT PRIMARY KEY NOT NULL,
          json TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
        """
      )
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_sync_metadata (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
        """
      )
    }
  }

  public func loadSnapshot() throws -> InstantPersistenceSnapshot {
    try loadState().snapshot
  }

  public func loadState() throws -> InstantPersistenceState {
    try readTransaction {
      try InstantPersistenceState(
        snapshot: loadSnapshotWithoutTransaction(),
        storeRevision: loadStoreRevisionWithoutTransaction()
      )
    }
  }

  private func loadSnapshotWithoutTransaction() throws -> InstantPersistenceSnapshot {
    let attributes: [InstantAttribute] = try selectJSON(
      "SELECT json FROM instant_attributes ORDER BY id"
    )
    let triples: [InstantTriple] = try selectJSON(
      "SELECT json FROM instant_triples ORDER BY entity_id, attribute_id, value_json"
    )
    let outbox: [PendingMutation] = try selectJSON(
      "SELECT json FROM instant_outbox ORDER BY created_at_ms, mutation_id"
    )
    return InstantPersistenceSnapshot(
      store: InstantStoreSnapshot(attributes: attributes, triples: triples),
      outbox: outbox
    )
  }

  public func loadQueryCache() throws -> [InstantCachedQuery] {
    try selectJSON(
      "SELECT json FROM instant_query_cache ORDER BY updated_at_ms, query_id"
    )
  }

  public func cachedQuery(id: String) throws -> InstantCachedQuery? {
    let rows: [InstantCachedQuery] = try selectJSON(
      "SELECT json FROM instant_query_cache WHERE query_id = ? LIMIT 1",
      [.text(id)]
    )
    return rows.first
  }

  public func saveStoreSnapshot(_ snapshot: InstantStoreSnapshot) throws {
    try transaction {
      try saveStoreSnapshotWithoutTransaction(snapshot)
      _ = try bumpStoreRevisionWithoutTransaction()
    }
  }

  public func saveOutbox(_ mutations: [PendingMutation]) throws {
    try transaction {
      try saveOutboxWithoutTransaction(mutations)
    }
  }

  public func saveSnapshot(_ snapshot: InstantPersistenceSnapshot) throws {
    try transaction {
      try saveStoreSnapshotWithoutTransaction(snapshot.store)
      try saveOutboxWithoutTransaction(snapshot.outbox)
      _ = try bumpStoreRevisionWithoutTransaction()
    }
  }

  public func saveQueryCache(
    _ entry: InstantCachedQuery,
    expectedStoreRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadStoreRevisionWithoutTransaction() == expectedStoreRevision else {
        return false
      }

      try execute(
        """
        INSERT OR REPLACE INTO instant_query_cache (query_id, json, updated_at_ms)
        VALUES (?, ?, ?)
        """,
        [
          .text(entry.queryID),
          .text(try encode(entry)),
          .int(entry.updatedAt.milliseconds),
        ]
      )
      return true
    }
  }

  public func localID(named name: String, makeID: @Sendable () -> String) throws -> String {
    if let existing = try selectScalar(
      "SELECT entity_id FROM instant_local_ids WHERE name = ? LIMIT 1",
      [.text(name)]
    ) {
      return existing
    }

    let id = makeID()
    try execute(
      "INSERT OR IGNORE INTO instant_local_ids (name, entity_id) VALUES (?, ?)",
      [.text(name), .text(id)]
    )
    if let persisted = try selectScalar(
      "SELECT entity_id FROM instant_local_ids WHERE name = ? LIMIT 1",
      [.text(name)]
    ) {
      return persisted
    }

    throw persistenceError(
      operation: "resolve local id",
      message: "SQLite did not return a local id for name '\(name)' after inserting it."
    )
  }

  private func migrate(name: String, body: () throws -> Void) throws {
    let alreadyApplied: String? = try selectScalar(
      "SELECT name FROM instant_schema_migrations WHERE name = ? LIMIT 1",
      [.text(name)]
    )
    guard alreadyApplied == nil else { return }
    try transaction {
      try body()
      try execute(
        "INSERT INTO instant_schema_migrations (name, applied_at_ms) VALUES (?, ?)",
        [.text(name), .int(Self.nowMilliseconds())]
      )
    }
  }

  @discardableResult
  private func transaction<Value>(_ body: () throws -> Value) throws -> Value {
    try execute("BEGIN IMMEDIATE TRANSACTION")
    do {
      let value = try body()
      try execute("COMMIT")
      return value
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  @discardableResult
  private func readTransaction<Value>(_ body: () throws -> Value) throws -> Value {
    try execute("BEGIN DEFERRED TRANSACTION")
    do {
      let value = try body()
      try execute("COMMIT")
      return value
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func selectJSON<Value: Decodable>(
    _ sql: String,
    _ bindings: [SQLiteBinding] = []
  ) throws -> [Value] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var values: [Value] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return values
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read SQL", message: lastErrorMessage())
      }
      guard let cString = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(operation: "decode row", message: "SQLite returned a NULL JSON row.")
      }
      let json = String(cString: cString)
      guard let data = json.data(using: .utf8)
      else {
        throw persistenceError(operation: "decode row", message: "SQLite JSON was not UTF-8.")
      }
      values.append(try decoder.decode(Value.self, from: data))
    }
  }

  private func selectScalar(_ sql: String, _ bindings: [SQLiteBinding] = []) throws -> String? {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW else {
      throw persistenceError(operation: "read SQL", message: lastErrorMessage())
    }
    guard let cString = sqlite3_column_text(statement, 0) else { return nil }
    return String(cString: cString)
  }

  private func saveStoreSnapshotWithoutTransaction(_ snapshot: InstantStoreSnapshot) throws {
    try execute("DELETE FROM instant_attributes")
    try execute("DELETE FROM instant_triples")

    for attribute in snapshot.attributes {
      try execute(
        "INSERT INTO instant_attributes (id, json) VALUES (?, ?)",
        [.text(attribute.id), .text(try encode(attribute))]
      )
    }

    for triple in snapshot.triples {
      try execute(
        """
        INSERT INTO instant_triples
          (entity_id, attribute_id, value_json, tx_id, tx_time_ms, json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          .text(triple.entityID),
          .text(triple.attributeID),
          .text(try encode(triple.value)),
          .text(triple.txID),
          .int(triple.txTime.milliseconds),
          .text(try encode(triple)),
        ]
      )
    }
  }

  private func saveOutboxWithoutTransaction(_ mutations: [PendingMutation]) throws {
    try execute("DELETE FROM instant_outbox")
    for mutation in mutations {
      try execute(
        """
        INSERT INTO instant_outbox (mutation_id, status, created_at_ms, json)
        VALUES (?, ?, ?, ?)
        """,
        [
          .text(mutation.id),
          .text(mutation.status.rawValue),
          .int(mutation.createdAt.milliseconds),
          .text(try encode(mutation)),
        ]
      )
    }
  }

  private func loadStoreRevisionWithoutTransaction() throws -> Int64 {
    let value: String? = try selectScalar(
      "SELECT value FROM instant_sync_metadata WHERE key = ? LIMIT 1",
      [.text(Self.storeRevisionKey)]
    )
    return value.flatMap(Int64.init) ?? 0
  }

  private func bumpStoreRevisionWithoutTransaction() throws -> Int64 {
    let revision = try loadStoreRevisionWithoutTransaction() + 1
    try execute(
      """
      INSERT OR REPLACE INTO instant_sync_metadata (key, value, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      [
        .text(Self.storeRevisionKey),
        .text(String(revision)),
        .int(Self.nowMilliseconds()),
      ]
    )
    return revision
  }

  private func execute(_ sql: String, _ bindings: [SQLiteBinding] = []) throws {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_DONE || code == SQLITE_ROW else {
      throw persistenceError(operation: "execute SQL", message: lastErrorMessage())
    }
  }

  private func prepare(_ sql: String, statement: inout OpaquePointer?) throws {
    guard sqlite3_prepare_v2(connection.raw, sql, -1, &statement, nil) == SQLITE_OK else {
      throw persistenceError(operation: "prepare SQL", message: lastErrorMessage())
    }
  }

  private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer?) throws {
    for (offset, binding) in bindings.enumerated() {
      let index = Int32(offset + 1)
      let result: Int32
      switch binding {
      case let .int(value):
        result = sqlite3_bind_int64(statement, index, sqlite3_int64(value))
      case let .text(value):
        result = value.withCString {
          sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
        }
      case .null:
        result = sqlite3_bind_null(statement, index)
      }
      guard result == SQLITE_OK else {
        throw persistenceError(operation: "bind SQL", message: lastErrorMessage())
      }
    }
  }

  private func encode<Value: Encodable>(_ value: Value) throws -> String {
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
      throw persistenceError(operation: "encode JSON", message: "Encoded JSON was not UTF-8.")
    }
    return string
  }

  private func lastErrorMessage() -> String {
    connection.raw.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
      ?? "Unknown SQLite error."
  }

  private func persistenceError(operation: String, message: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the local SQLite cache at \(fileURL.path), then retry the command."
    )
  }

  private static func nowMilliseconds() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000).rounded())
  }

  private static let storeRevisionKey = "store_revision"
}

private enum SQLiteBinding: Sendable {
  case int(Int64)
  case text(String)
  case null
}

// SQLite's raw pointer is confined to SQLitePersistenceStore. The wrapper is
// immutable outside the actor and only closes the connection when released.
private final class SQLiteConnection: @unchecked Sendable {
  var raw: OpaquePointer?

  init(_ raw: OpaquePointer?) {
    self.raw = raw
  }

  deinit {
    sqlite3_close(raw)
  }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
