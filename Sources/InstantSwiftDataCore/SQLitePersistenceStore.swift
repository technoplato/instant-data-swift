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
  public var outboxRevision: Int64

  public init(
    snapshot: InstantPersistenceSnapshot,
    storeRevision: Int64,
    outboxRevision: Int64
  ) {
    self.snapshot = snapshot
    self.storeRevision = storeRevision
    self.outboxRevision = outboxRevision
  }
}

public struct InstantQueryCachePruningPolicy: Hashable, Codable, Sendable {
  public var maxAgeMilliseconds: Int64?
  public var maxEntries: Int?
  public var maxEncodedJSONBytes: Int?

  public init(
    maxAgeMilliseconds: Int64? = nil,
    maxEntries: Int? = nil,
    maxEncodedJSONBytes: Int? = nil
  ) {
    self.maxAgeMilliseconds = maxAgeMilliseconds
    self.maxEntries = maxEntries
    self.maxEncodedJSONBytes = maxEncodedJSONBytes
  }
}

public struct InstantQueryCachePruningResult: Hashable, Codable, Sendable {
  public var removedCacheKeys: [String]
  public var remainingCacheKeys: [String]
  public var remainingEntryCount: Int
  public var remainingEncodedJSONByteCount: Int

  public init(
    removedCacheKeys: [String],
    remainingCacheKeys: [String],
    remainingEntryCount: Int,
    remainingEncodedJSONByteCount: Int
  ) {
    self.removedCacheKeys = removedCacheKeys
    self.remainingCacheKeys = remainingCacheKeys
    self.remainingEntryCount = remainingEntryCount
    self.remainingEncodedJSONByteCount = remainingEncodedJSONByteCount
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
    self.connection = SQLiteConnection(try Self.openRawConnection(fileURL: fileURL))
  }

  private static func openRawConnection(fileURL: URL) throws -> OpaquePointer? {
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
    guard sqlite3_exec(opened, "PRAGMA foreign_keys = ON", nil, nil, nil) == SQLITE_OK else {
      let message = opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not enable foreign keys for \(fileURL.path)."
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "configure local cache",
        message: message,
        recovery: "Check that the cache directory is writable, or choose another persistence path."
      )
    }
    return opened
  }

  public func bootstrap() throws {
    try withSQLiteBusyRetry {
      try execute("PRAGMA journal_mode = WAL")
    }
    try execute("PRAGMA foreign_keys = ON")
    try withSQLiteBusyRetry {
      try execute(
        """
        CREATE TABLE IF NOT EXISTS instant_schema_migrations (
          name TEXT PRIMARY KEY NOT NULL,
          applied_at_ms INTEGER NOT NULL
        )
        """
      )
    }
    try withSQLiteBusyRetry {
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
    try withSQLiteBusyRetry {
      try migrate(name: "0002_magic_code_challenges") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_magic_code_challenges (
            key TEXT PRIMARY KEY NOT NULL,
            email TEXT NOT NULL,
            expires_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0003_plan_aware_query_cache") {
        let entries: [InstantCachedQuery] = try selectJSON(
          "SELECT json FROM instant_query_cache ORDER BY updated_at_ms, query_id"
        )
        try execute("DROP TABLE IF EXISTS instant_query_cache_v2")
        try execute(
          """
          CREATE TABLE instant_query_cache_v2 (
            cache_key TEXT PRIMARY KEY NOT NULL,
            query_id TEXT NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL
          )
          """
        )
        for entry in entries {
          try saveQueryCacheEntryWithoutTransaction(entry, tableName: "instant_query_cache_v2")
        }
        try execute("DROP TABLE instant_query_cache")
        try execute("ALTER TABLE instant_query_cache_v2 RENAME TO instant_query_cache")
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_query_cache_query_id_idx
          ON instant_query_cache (query_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0004_room_presence_and_topics") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_room_presence (
            app_id TEXT NOT NULL,
            room_type TEXT NOT NULL,
            room_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            json TEXT NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            PRIMARY KEY (app_id, room_type, room_id, user_id)
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_room_topic_messages (
            message_id TEXT NOT NULL,
            app_id TEXT NOT NULL,
            room_type TEXT NOT NULL,
            room_id TEXT NOT NULL,
            topic TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, message_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_room_topic_messages_room_idx
          ON instant_room_topic_messages (app_id, room_type, room_id, topic, created_at_ms, message_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0005_app_scoped_room_topic_messages") {
        let messages: [InstantRoomTopicMessage] = try selectJSON(
          "SELECT json FROM instant_room_topic_messages ORDER BY created_at_ms, message_id"
        )
        try execute("DROP TABLE IF EXISTS instant_room_topic_messages_v2")
        try execute(
          """
          CREATE TABLE instant_room_topic_messages_v2 (
            message_id TEXT NOT NULL,
            app_id TEXT NOT NULL,
            room_type TEXT NOT NULL,
            room_id TEXT NOT NULL,
            topic TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, message_id)
          )
          """
        )
        for message in messages {
          try saveRoomTopicMessageWithoutTransaction(
            message,
            tableName: "instant_room_topic_messages_v2"
          )
        }
        try execute("DROP TABLE instant_room_topic_messages")
        try execute("ALTER TABLE instant_room_topic_messages_v2 RENAME TO instant_room_topic_messages")
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_room_topic_messages_room_idx
          ON instant_room_topic_messages (app_id, room_type, room_id, topic, created_at_ms, message_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0006_local_files") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_files (
            app_id TEXT NOT NULL,
            file_id TEXT NOT NULL,
            name TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, file_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_files_app_idx
          ON instant_files (app_id, created_at_ms, file_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0007_local_stream_chunks") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_stream_chunks (
            app_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            chunk_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, stream_id, chunk_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_stream_chunks_stream_idx
          ON instant_stream_chunks (app_id, stream_id, chunk_index, chunk_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0008_local_shares") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_shares (
            app_id TEXT NOT NULL,
            share_id TEXT NOT NULL,
            root_namespace TEXT NOT NULL,
            root_id TEXT NOT NULL,
            owner_user_id TEXT NOT NULL,
            token TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            revoked_at_ms INTEGER,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, share_id)
          )
          """
        )
        try execute(
          """
          CREATE UNIQUE INDEX IF NOT EXISTS instant_shares_token_idx
          ON instant_shares (app_id, token)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_shares_owner_idx
          ON instant_shares (app_id, owner_user_id, created_at_ms, share_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_shares_root_idx
          ON instant_shares (app_id, root_id, root_namespace, revoked_at_ms, created_at_ms, share_id)
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_share_memberships (
            app_id TEXT NOT NULL,
            share_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL,
            accepted_at_ms INTEGER NOT NULL,
            revoked_at_ms INTEGER,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, share_id, user_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_share_memberships_user_idx
          ON instant_share_memberships (app_id, user_id, revoked_at_ms, accepted_at_ms, share_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0009_local_share_root_index") {
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_shares_root_idx
          ON instant_shares (app_id, root_id, root_namespace, revoked_at_ms, created_at_ms, share_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0010_local_byte_streams") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_streams (
            app_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            client_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            done INTEGER NOT NULL,
            size INTEGER,
            abort_reason TEXT,
            created_at_ms INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, stream_id),
            UNIQUE (app_id, client_id)
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_streams_client_idx
          ON instant_streams (app_id, client_id)
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_stream_content_chunks (
            app_id TEXT NOT NULL,
            stream_id TEXT NOT NULL,
            chunk_id TEXT NOT NULL,
            offset INTEGER NOT NULL,
            byte_count INTEGER NOT NULL,
            created_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL,
            PRIMARY KEY (app_id, stream_id, chunk_id),
            FOREIGN KEY (app_id, stream_id) REFERENCES instant_streams (app_id, stream_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_stream_content_chunks_stream_idx
          ON instant_stream_content_chunks (app_id, stream_id, offset, chunk_id)
          """
        )
      }
    }
  }

  func simulateUnexpectedConnectionCloseForTesting() {
    sqlite3_close(connection.raw)
    connection.raw = nil
  }

  public func loadSnapshot() throws -> InstantPersistenceSnapshot {
    try loadState().snapshot
  }

  public func loadState() throws -> InstantPersistenceState {
    try readTransaction {
      try InstantPersistenceState(
        snapshot: loadSnapshotWithoutTransaction(),
        storeRevision: loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        outboxRevision: loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
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
      "SELECT json FROM instant_query_cache ORDER BY updated_at_ms, query_id, cache_key"
    )
  }

  public func cachedQuery(cacheKey: String) throws -> InstantCachedQuery? {
    let rows: [InstantCachedQuery] = try selectJSON(
      "SELECT json FROM instant_query_cache WHERE cache_key = ? LIMIT 1",
      [.text(cacheKey)]
    )
    return rows.first
  }

  func loadStateAndCachedQuery(
    cacheKey: String
  ) throws -> (state: InstantPersistenceState, cachedQuery: InstantCachedQuery?) {
    try readTransaction {
      let state = try InstantPersistenceState(
        snapshot: loadSnapshotWithoutTransaction(),
        storeRevision: loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        outboxRevision: loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
      let rows: [InstantCachedQuery] = try selectJSON(
        "SELECT json FROM instant_query_cache WHERE cache_key = ? LIMIT 1",
        [.text(cacheKey)]
      )
      return (state: state, cachedQuery: rows.first)
    }
  }

  public func cachedQueries(queryID: String) throws -> [InstantCachedQuery] {
    try selectJSON(
      "SELECT json FROM instant_query_cache WHERE query_id = ? ORDER BY updated_at_ms, cache_key",
      [.text(queryID)]
    )
  }

  public func pruneQueryCache(
    policy: InstantQueryCachePruningPolicy,
    preservingCacheKeys: Set<String> = []
  ) throws -> InstantQueryCachePruningResult {
    try pruneQueryCache(
      policy: policy,
      now: InstantTimestamp(milliseconds: Self.nowMilliseconds()),
      preservingCacheKeys: preservingCacheKeys
    )
  }

  public func pruneQueryCache(
    policy: InstantQueryCachePruningPolicy,
    now: InstantTimestamp,
    preservingCacheKeys: Set<String> = []
  ) throws -> InstantQueryCachePruningResult {
    try transaction {
      var rows = try loadQueryCacheRowsWithoutTransaction()
      var removedCacheKeys: [String] = []

      func remove(_ row: QueryCacheStorageRow) throws -> Bool {
        guard !preservingCacheKeys.contains(row.cacheKey) else { return false }
        try execute(
          "DELETE FROM instant_query_cache WHERE cache_key = ?",
          [.text(row.cacheKey)]
        )
        rows.removeAll { $0.cacheKey == row.cacheKey }
        removedCacheKeys.append(row.cacheKey)
        return true
      }

      if let maxAgeMilliseconds = policy.maxAgeMilliseconds {
        let cutoff = now.milliseconds - Swift.max(0, maxAgeMilliseconds)
        for row in rows.filter({ $0.updatedAtMilliseconds < cutoff }) {
          _ = try remove(row)
        }
      }

      if let maxEntries = policy.maxEntries {
        let entryLimit = Swift.max(0, maxEntries)
        while rows.count > entryLimit {
          guard let candidate = rows.first(where: { !preservingCacheKeys.contains($0.cacheKey) })
          else { break }
          _ = try remove(candidate)
        }
      }

      if let maxEncodedJSONBytes = policy.maxEncodedJSONBytes {
        let byteLimit = Swift.max(0, maxEncodedJSONBytes)
        var byteCount = rows.reduce(0) { $0 + $1.byteCount }
        while byteCount > byteLimit {
          guard let candidate = rows.first(where: { !preservingCacheKeys.contains($0.cacheKey) })
          else { break }
          if try remove(candidate) {
            byteCount = rows.reduce(0) { $0 + $1.byteCount }
          } else {
            break
          }
        }
      }

      return InstantQueryCachePruningResult(
        removedCacheKeys: removedCacheKeys,
        remainingCacheKeys: rows.map(\.cacheKey),
        remainingEntryCount: rows.count,
        remainingEncodedJSONByteCount: rows.reduce(0) { $0 + $1.byteCount }
      )
    }
  }

  public func saveStoreSnapshot(_ snapshot: InstantStoreSnapshot) throws {
    try transaction {
      try saveStoreSnapshotWithoutTransaction(snapshot)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
    }
  }

  public func saveOutbox(_ mutations: [PendingMutation]) throws {
    try transaction {
      try saveOutboxWithoutTransaction(mutations)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
  }

  public func saveOutbox(
    _ mutations: [PendingMutation],
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        == expectedOutboxRevision
      else {
        return false
      }
      try saveOutboxWithoutTransaction(mutations)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
  }

  public func loadAuthSession(key: String) throws -> InstantAuthSession? {
    let rows: [InstantAuthSession] = try selectJSON(
      "SELECT json FROM instant_auth_sessions WHERE key = ? LIMIT 1",
      [.text(key)]
    )
    return rows.first
  }

  public func saveAuthSession(_ session: InstantAuthSession, key: String) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_auth_sessions (key, json, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      [
        .text(key),
        .text(try encode(session)),
        .int(session.updatedAt.milliseconds),
      ]
    )
  }

  public func deleteAuthSession(key: String) throws {
    try execute(
      "DELETE FROM instant_auth_sessions WHERE key = ?",
      [.text(key)]
    )
  }

  public func loadRoomPresence(
    appID: String,
    room: InstantRoomHandle
  ) throws -> [InstantRoomPresenceMember] {
    try selectJSON(
      """
      SELECT json FROM instant_room_presence
      WHERE app_id = ? AND room_type = ? AND room_id = ?
      ORDER BY updated_at_ms, user_id
      """,
      [.text(appID), .text(room.type), .text(room.id)]
    )
  }

  public func saveRoomPresence(_ member: InstantRoomPresenceMember) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_room_presence
        (app_id, room_type, room_id, user_id, json, updated_at_ms)
      VALUES (?, ?, ?, ?, ?, ?)
      """,
      [
        .text(member.appID),
        .text(member.room.type),
        .text(member.room.id),
        .text(member.userID),
        .text(try encode(member)),
        .int(member.updatedAt.milliseconds),
      ]
    )
  }

  public func deleteRoomPresence(
    appID: String,
    room: InstantRoomHandle,
    userID: String
  ) throws {
    try execute(
      """
      DELETE FROM instant_room_presence
      WHERE app_id = ? AND room_type = ? AND room_id = ? AND user_id = ?
      """,
      [.text(appID), .text(room.type), .text(room.id), .text(userID)]
    )
  }

  public func saveRoomTopicMessage(_ message: InstantRoomTopicMessage) throws {
    try saveRoomTopicMessageWithoutTransaction(message)
  }

  private func saveRoomTopicMessageWithoutTransaction(
    _ message: InstantRoomTopicMessage,
    tableName: String = "instant_room_topic_messages"
  ) throws {
    try execute(
      """
      INSERT OR REPLACE INTO \(tableName)
        (message_id, app_id, room_type, room_id, topic, created_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(message.id),
        .text(message.appID),
        .text(message.room.type),
        .text(message.room.id),
        .text(message.topic),
        .int(message.createdAt.milliseconds),
        .text(try encode(message)),
      ]
    )
  }

  public func loadRoomTopicMessages(
    appID: String,
    room: InstantRoomHandle,
    topic: String,
    limit: Int? = nil
  ) throws -> [InstantRoomTopicMessage] {
    let messages: [InstantRoomTopicMessage] = try selectJSON(
      """
      SELECT json FROM instant_room_topic_messages
      WHERE app_id = ? AND room_type = ? AND room_id = ? AND topic = ?
      ORDER BY created_at_ms, message_id
      """,
      [.text(appID), .text(room.type), .text(room.id), .text(topic)]
    )
    if let limit {
      return Array(messages.prefix(limit))
    }
    return messages
  }

  public func saveStoredFile(
    _ file: InstantStoredFile,
    contentsOf sourceURL: URL
  ) throws -> InstantStoredFile {
    let sourceValues = try regularFileResourceValues(at: sourceURL, operation: "upload file")

    let directory = localFilesRootURL
      .appendingPathComponent(sanitizedFileComponent(file.appID), isDirectory: true)
      .appendingPathComponent(sanitizedFileComponent(file.id), isDirectory: true)
    let targetURL = directory.appendingPathComponent(sanitizedFileComponent(file.name))
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: targetURL.path) {
        try FileManager.default.removeItem(at: targetURL)
      }
      try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    } catch {
      throw persistenceError(
        operation: "upload file",
        message:
          "Could not copy source path '\(sourceURL.path)' into local file storage: \(error.localizedDescription)"
      )
    }

    var savedFile = file
    savedFile.byteCount = Int64(sourceValues.fileSize ?? 0)
    savedFile.localPath = targetURL.path
    do {
      try execute(
        """
        INSERT OR REPLACE INTO instant_files
          (app_id, file_id, name, created_at_ms, updated_at_ms, json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          .text(savedFile.appID),
          .text(savedFile.id),
          .text(savedFile.name),
          .int(savedFile.createdAt.milliseconds),
          .int(savedFile.updatedAt.milliseconds),
          .text(try encode(savedFile)),
        ]
      )
    } catch {
      try? FileManager.default.removeItem(at: targetURL)
      throw error
    }
    return savedFile
  }

  public func regularFileByteCount(at sourceURL: URL, operation: String) throws -> Int64 {
    let sourceValues = try regularFileResourceValues(at: sourceURL, operation: operation)
    return Int64(sourceValues.fileSize ?? 0)
  }

  public func loadStoredFiles(appID: String) throws -> [InstantStoredFile] {
    try selectJSON(
      """
      SELECT json FROM instant_files
      WHERE app_id = ?
      ORDER BY created_at_ms, file_id
      """,
      [.text(appID)]
    )
  }

  public func loadStoredFile(appID: String, fileID: String) throws -> InstantStoredFile? {
    let rows: [InstantStoredFile] = try selectJSON(
      """
      SELECT json FROM instant_files
      WHERE app_id = ? AND file_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(fileID)]
    )
    return rows.first
  }

  public func readStoredFileContents(
    appID: String,
    fileID: String
  ) throws -> InstantStoredFileContents? {
    guard let file = try loadStoredFile(appID: appID, fileID: fileID) else {
      return nil
    }
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: file.localPath))
      return InstantStoredFileContents(file: file, data: data)
    } catch {
      throw persistenceError(
        operation: "read file",
        message: "Could not read stored file '\(file.localPath)': \(error.localizedDescription)"
      )
    }
  }

  public func deleteStoredFile(appID: String, fileID: String) throws -> InstantStoredFile? {
    guard let file = try loadStoredFile(appID: appID, fileID: fileID) else { return nil }

    try execute(
      "DELETE FROM instant_files WHERE app_id = ? AND file_id = ?",
      [.text(appID), .text(fileID)]
    )
    if FileManager.default.fileExists(atPath: file.localPath) {
      do {
        try FileManager.default.removeItem(atPath: file.localPath)
      } catch {
        throw persistenceError(
          operation: "delete file",
          message: "Could not remove stored file '\(file.localPath)': \(error.localizedDescription)"
        )
      }
    }
    return file
  }

  public func appendStreamChunk(
    appID: String,
    streamID: String,
    chunkID: String,
    payload: JSONValue,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamChunk {
    try transaction {
      let nextIndex = try nextStreamChunkIndexWithoutTransaction(appID: appID, streamID: streamID)
      let chunk = InstantStreamChunk(
        id: chunkID,
        appID: appID,
        streamID: streamID,
        index: nextIndex,
        payload: payload,
        userID: userID,
        createdAt: createdAt
      )
      try execute(
        """
        INSERT INTO instant_stream_chunks
          (app_id, stream_id, chunk_id, chunk_index, created_at_ms, json)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
          .text(chunk.appID),
          .text(chunk.streamID),
          .text(chunk.id),
          .int(chunk.index),
          .int(chunk.createdAt.milliseconds),
          .text(try encode(chunk)),
        ]
      )
      return chunk
    }
  }

  public func loadStreamChunks(
    appID: String,
    streamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) throws -> [InstantStreamChunk] {
    var sql =
      """
      SELECT json FROM instant_stream_chunks
      WHERE app_id = ? AND stream_id = ?
      ORDER BY chunk_index, chunk_id
      """
    var bindings: [SQLiteBinding] = [.text(appID), .text(streamID)]
    if let afterIndex {
      sql =
        """
        SELECT json FROM instant_stream_chunks
        WHERE app_id = ? AND stream_id = ? AND chunk_index > ?
        ORDER BY chunk_index, chunk_id
        """
      bindings.append(.int(afterIndex))
    }
    if let limit {
      sql.append("\nLIMIT ?")
      bindings.append(.int(Int64(limit)))
    }
    return try selectJSON(sql, bindings)
  }

  public func createStream(
    appID: String,
    streamID: String,
    clientID: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
    try transaction {
      if let existing = try streamMetadataWithoutTransaction(appID: appID, clientID: clientID) {
        throw streamValidationError(
          operation: "create stream",
          localID: clientID,
          message:
            "Stream client id '\(clientID)' already belongs to stream '\(existing.id)'.",
          recovery: "Choose a unique client id before creating another stream."
        )
      }
      if try streamMetadataWithoutTransaction(appID: appID, streamID: streamID) != nil {
        throw streamValidationError(
          operation: "create stream",
          localID: streamID,
          message: "Stream id '\(streamID)' already exists.",
          recovery: "Retry stream creation with a freshly generated stream id."
        )
      }
      let metadata = InstantStreamMetadata(
        id: streamID,
        appID: appID,
        clientID: clientID,
        userID: userID,
        createdAt: createdAt,
        updatedAt: createdAt
      )
      try insertStreamMetadataWithoutTransaction(metadata)
      return metadata
    }
  }

  public func loadStreamMetadata(
    appID: String,
    streamID: String
  ) throws -> InstantStreamMetadata? {
    try readTransaction {
      try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
    }
  }

  public func loadStreamMetadata(
    appID: String,
    clientID: String
  ) throws -> InstantStreamMetadata? {
    try readTransaction {
      try streamMetadataWithoutTransaction(appID: appID, clientID: clientID)
    }
  }

  public func loadStreamMetadata(appID: String) throws -> [InstantStreamMetadata] {
    try readTransaction {
      try selectJSON(
        """
        SELECT json FROM instant_streams
        WHERE app_id = ?
        ORDER BY created_at_ms, stream_id
        """,
        [.text(appID)]
      )
    }
  }

  public func appendStreamContent(
    appID: String,
    streamID: String,
    chunkID: String,
    content: String,
    expectedOffset: Int64?,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamContentAppend? {
    try transaction {
      guard var metadata = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
      else { return nil }
      guard metadata.done == false else {
        throw streamValidationError(
          operation: "append stream content",
          localID: streamID,
          message: "Stream '\(streamID)' is already closed.",
          recovery: "Create a new stream before appending more content."
        )
      }

      let offset = try streamContentSizeWithoutTransaction(appID: appID, streamID: streamID)
      if let expectedOffset, expectedOffset != offset {
        throw streamValidationError(
          operation: "append stream content",
          localID: streamID,
          message:
            "Stream '\(streamID)' is at byte offset \(offset), not expected offset \(expectedOffset).",
          recovery: "Read the stream metadata and retry with the current offset."
        )
      }

      let chunk = InstantStreamContentChunk(
        id: chunkID,
        appID: appID,
        streamID: streamID,
        offset: offset,
        byteCount: Int64(content.utf8.count),
        content: content,
        userID: userID,
        createdAt: createdAt
      )
      try execute(
        """
        INSERT INTO instant_stream_content_chunks
          (app_id, stream_id, chunk_id, offset, byte_count, created_at_ms, json)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        [
          .text(chunk.appID),
          .text(chunk.streamID),
          .text(chunk.id),
          .int(chunk.offset),
          .int(chunk.byteCount),
          .int(chunk.createdAt.milliseconds),
          .text(try encode(chunk)),
        ]
      )

      metadata.updatedAt = createdAt
      try saveStreamMetadataWithoutTransaction(metadata)
      return InstantStreamContentAppend(metadata: metadata, chunk: chunk, offset: offset)
    }
  }

  public func closeStream(
    appID: String,
    streamID: String,
    abortReason: String?,
    updatedAt: InstantTimestamp
  ) throws -> InstantStreamMetadata? {
    try transaction {
      guard var metadata = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
      else { return nil }
      guard metadata.done == false else { return metadata }
      metadata.done = true
      metadata.size = try streamContentSizeWithoutTransaction(appID: appID, streamID: streamID)
      metadata.abortReason = abortReason
      metadata.updatedAt = updatedAt
      try saveStreamMetadataWithoutTransaction(metadata)
      return metadata
    }
  }

  public func loadStreamContent(
    appID: String,
    streamID: String,
    byteOffset: Int64
  ) throws -> InstantStreamContentRead? {
    try readTransaction {
      guard let metadata = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID)
      else { return nil }
      return try streamContentReadWithoutTransaction(metadata: metadata, byteOffset: byteOffset)
    }
  }

  public func loadStreamContent(
    appID: String,
    clientID: String,
    byteOffset: Int64
  ) throws -> InstantStreamContentRead? {
    try readTransaction {
      guard let metadata = try streamMetadataWithoutTransaction(appID: appID, clientID: clientID)
      else { return nil }
      return try streamContentReadWithoutTransaction(metadata: metadata, byteOffset: byteOffset)
    }
  }

  public func createShare(
    _ share: InstantShare,
    ownerMembership: InstantShareMembership
  ) throws -> InstantShareSnapshot {
    try transaction {
      try saveShareWithoutTransaction(share)
      try saveShareMembershipWithoutTransaction(ownerMembership)
      return try shareSnapshotWithoutTransaction(appID: share.appID, shareID: share.id)
    }
  }

  public func acceptShare(
    appID: String,
    token: String,
    userID: String,
    acceptedAt: InstantTimestamp
  ) throws -> InstantShareSnapshot? {
    try transaction {
      guard let share = try shareWithoutTransaction(appID: appID, token: token),
        share.revokedAt == nil
      else {
        return nil
      }
      let existingMembership = try shareMembershipWithoutTransaction(
        appID: appID,
        shareID: share.id,
        userID: userID
      )
      if let existingMembership, existingMembership.revokedAt == nil {
        return try shareSnapshotWithoutTransaction(appID: appID, shareID: share.id)
      }
      try saveShareMembershipWithoutTransaction(
        InstantShareMembership(
          appID: appID,
          shareID: share.id,
          userID: userID,
          role: .reader,
          acceptedAt: acceptedAt
        )
      )
      return try shareSnapshotWithoutTransaction(appID: appID, shareID: share.id)
    }
  }

  public func loadShareSnapshot(appID: String, shareID: String) throws -> InstantShareSnapshot? {
    try readTransaction {
      guard try shareWithoutTransaction(appID: appID, shareID: shareID) != nil else { return nil }
      return try shareSnapshotWithoutTransaction(appID: appID, shareID: shareID)
    }
  }

  public func loadShareSnapshots(appID: String, userID: String) throws -> [InstantShareSnapshot] {
    try readTransaction {
      let shares: [InstantShare] = try selectJSON(
        """
        SELECT s.json FROM instant_shares s
        INNER JOIN instant_share_memberships m
          ON m.app_id = s.app_id AND m.share_id = s.share_id
        WHERE s.app_id = ? AND m.user_id = ?
          AND s.revoked_at_ms IS NULL AND m.revoked_at_ms IS NULL
        ORDER BY s.created_at_ms, s.share_id
        """,
        [.text(appID), .text(userID)]
      )
      return try shares.map {
        try shareSnapshotWithoutTransaction(appID: appID, shareID: $0.id, activeMembershipsOnly: true)
      }
    }
  }

  public func loadActiveShareSnapshots(
    appID: String,
    rootNamespace: String?,
    rootID: String
  ) throws -> [InstantShareSnapshot] {
    try readTransaction {
      var sql =
        """
        SELECT json FROM instant_shares
        WHERE app_id = ? AND root_id = ? AND revoked_at_ms IS NULL
        """
      var bindings: [SQLiteBinding] = [.text(appID), .text(rootID)]
      if let rootNamespace {
        sql.append("\nAND root_namespace = ?")
        bindings.append(.text(rootNamespace))
      }
      sql.append("\nORDER BY created_at_ms, share_id")
      let shares: [InstantShare] = try selectJSON(sql, bindings)
      return try shares.map {
        try shareSnapshotWithoutTransaction(appID: appID, shareID: $0.id, activeMembershipsOnly: true)
      }
    }
  }

  public func updateShareMembershipRole(
    appID: String,
    shareID: String,
    userID: String,
    role: InstantShareRole,
    updatedAt: InstantTimestamp
  ) throws -> InstantShareSnapshot? {
    try transaction {
      guard var share = try shareWithoutTransaction(appID: appID, shareID: shareID),
        share.revokedAt == nil,
        var membership = try shareMembershipWithoutTransaction(
          appID: appID,
          shareID: shareID,
          userID: userID
        ),
        membership.revokedAt == nil
      else {
        return nil
      }

      if membership.role != role {
        membership.role = role
        try saveShareMembershipWithoutTransaction(membership)
        share.updatedAt = updatedAt
        try saveShareWithoutTransaction(share)
      }
      return try shareSnapshotWithoutTransaction(
        appID: appID,
        shareID: shareID,
        activeMembershipsOnly: true
      )
    }
  }

  public func revokeShare(
    appID: String,
    shareID: String,
    revokedAt: InstantTimestamp
  ) throws -> InstantShareSnapshot? {
    try transaction {
      guard var share = try shareWithoutTransaction(appID: appID, shareID: shareID) else {
        return nil
      }
      if share.revokedAt != nil {
        return try shareSnapshotWithoutTransaction(appID: appID, shareID: shareID)
      }
      share.revokedAt = revokedAt
      share.updatedAt = revokedAt
      try saveShareWithoutTransaction(share)

      let memberships = try shareMembershipsWithoutTransaction(
        appID: appID,
        shareID: shareID,
        activeOnly: false
      )
      for var membership in memberships where membership.revokedAt == nil {
        membership.revokedAt = revokedAt
        try saveShareMembershipWithoutTransaction(membership)
      }
      return try shareSnapshotWithoutTransaction(appID: appID, shareID: shareID)
    }
  }

  public func loadMagicCodeChallenge(key: String) throws -> InstantMagicCodeChallenge? {
    let rows: [InstantMagicCodeChallenge] = try selectJSON(
      "SELECT json FROM instant_magic_code_challenges WHERE key = ? LIMIT 1",
      [.text(key)]
    )
    return rows.first
  }

  public func saveMagicCodeChallenge(_ challenge: InstantMagicCodeChallenge, key: String) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_magic_code_challenges
        (key, email, expires_at_ms, json, updated_at_ms)
      VALUES (?, ?, ?, ?, ?)
      """,
      [
        .text(key),
        .text(challenge.email),
        .int(challenge.expiresAt.milliseconds),
        .text(try encode(challenge)),
        .int(challenge.createdAt.milliseconds),
      ]
    )
  }

  public func deleteMagicCodeChallenge(key: String) throws {
    try execute(
      "DELETE FROM instant_magic_code_challenges WHERE key = ?",
      [.text(key)]
    )
  }

  public func loadMetadataValue(key: String) throws -> String? {
    try selectScalar(
      "SELECT value FROM instant_sync_metadata WHERE key = ? LIMIT 1",
      [.text(key)]
    )
  }

  public func saveMetadataValue(
    _ value: String,
    key: String,
    updatedAt: InstantTimestamp
  ) throws {
    try saveMetadataValueWithoutTransaction(value, key: key, updatedAt: updatedAt)
  }

  public func saveMetadataValue(
    _ value: String,
    key: String,
    updatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveMetadataValueWithoutTransaction(value, key: key, updatedAt: updatedAt)
      return true
    }
  }

  public func deleteMetadataValue(key: String) throws {
    try execute(
      "DELETE FROM instant_sync_metadata WHERE key = ?",
      [.text(key)]
    )
  }

  public func saveSnapshot(_ snapshot: InstantPersistenceSnapshot) throws {
    try transaction {
      try saveStoreSnapshotWithoutTransaction(snapshot.store)
      try saveOutboxWithoutTransaction(snapshot.outbox)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveStoreSnapshotWithoutTransaction(snapshot.store)
      try saveOutboxWithoutTransaction(snapshot.outbox)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveStoreSnapshotWithoutTransaction(snapshot.store)
      try saveOutboxWithoutTransaction(snapshot.outbox)
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
  }

  public func saveOutbox(
    _ mutations: [PendingMutation],
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveOutboxWithoutTransaction(mutations)
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
  }

  public func saveStoreSnapshot(
    _ snapshot: InstantStoreSnapshot,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveStoreSnapshotWithoutTransaction(snapshot)
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      return true
    }
  }

  public func saveQueryCache(
    _ entry: InstantCachedQuery,
    expectedStoreRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision else {
        return false
      }

      try saveQueryCacheEntryWithoutTransaction(entry)
      return true
    }
  }

  func saveQueryCache(
    _ entries: [InstantCachedQuery],
    expectedStoreRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision else {
        return false
      }

      for entry in entries {
        try saveQueryCacheEntryWithoutTransaction(entry)
      }
      return true
    }
  }

  func deleteQueryCache(cacheKey: String) throws {
    try execute(
      "DELETE FROM instant_query_cache WHERE cache_key = ?",
      [.text(cacheKey)]
    )
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

  public func loadLocalIDs() throws -> [InstantLocalID] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT name, entity_id FROM instant_local_ids
      ORDER BY name
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }

    var localIDs: [InstantLocalID] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return localIDs
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "list local ids", message: lastErrorMessage())
      }
      guard let name = sqlite3_column_text(statement, 0),
        let entityID = sqlite3_column_text(statement, 1)
      else {
        throw persistenceError(
          operation: "list local ids",
          message: "SQLite returned a NULL local id row."
        )
      }
      localIDs.append(
        InstantLocalID(
          name: String(cString: name),
          entityID: String(cString: entityID)
        )
      )
    }
  }

  private func migrate(name: String, body: () throws -> Void) throws {
    try transaction {
      let alreadyApplied: String? = try selectScalar(
        "SELECT name FROM instant_schema_migrations WHERE name = ? LIMIT 1",
        [.text(name)]
      )
      guard alreadyApplied == nil else { return }
      try body()
      try execute(
        "INSERT OR IGNORE INTO instant_schema_migrations (name, applied_at_ms) VALUES (?, ?)",
        [.text(name), .int(Self.nowMilliseconds())]
      )
    }
  }

  private func withSQLiteBusyRetry<Value>(_ operation: () throws -> Value) throws -> Value {
    var lastError: Error?
    for attempt in 0..<6 {
      do {
        return try operation()
      } catch let error as InstantError where error.code == .persistenceFailed && error.isSQLiteBusy {
        lastError = error
        Thread.sleep(forTimeInterval: 0.025 * Double(attempt + 1))
      }
    }

    if let lastError {
      throw lastError
    }
    return try operation()
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

  private func loadQueryCacheRowsWithoutTransaction() throws -> [QueryCacheStorageRow] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT cache_key, json, updated_at_ms
      FROM instant_query_cache
      ORDER BY updated_at_ms, query_id, cache_key
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }

    var rows: [QueryCacheStorageRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return rows
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read query cache rows", message: lastErrorMessage())
      }
      guard
        let cacheKeyCString = sqlite3_column_text(statement, 0),
        let jsonCString = sqlite3_column_text(statement, 1)
      else {
        throw persistenceError(
          operation: "read query cache rows",
          message: "SQLite returned a NULL query cache column."
        )
      }
      rows.append(
        QueryCacheStorageRow(
          cacheKey: String(cString: cacheKeyCString),
          json: String(cString: jsonCString),
          updatedAtMilliseconds: sqlite3_column_int64(statement, 2)
        )
      )
    }
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

  private func saveQueryCacheEntryWithoutTransaction(
    _ entry: InstantCachedQuery,
    tableName: String = "instant_query_cache"
  ) throws {
    try execute(
      """
      INSERT OR REPLACE INTO \(tableName) (cache_key, query_id, json, updated_at_ms)
      VALUES (?, ?, ?, ?)
      """,
      [
        .text(entry.cacheKey),
        .text(entry.queryID),
        .text(try encode(entry)),
        .int(entry.updatedAt.milliseconds),
      ]
    )
  }

  private func saveMetadataValueWithoutTransaction(
    _ value: String,
    key: String,
    updatedAt: InstantTimestamp
  ) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_sync_metadata (key, value, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      [
        .text(key),
        .text(value),
        .int(updatedAt.milliseconds),
      ]
    )
  }

  private func loadMetadataRevisionWithoutTransaction(_ key: String) throws -> Int64 {
    let value: String? = try selectScalar(
      "SELECT value FROM instant_sync_metadata WHERE key = ? LIMIT 1",
      [.text(key)]
    )
    return value.flatMap(Int64.init) ?? 0
  }

  private func bumpMetadataRevisionWithoutTransaction(_ key: String) throws -> Int64 {
    let revision = try loadMetadataRevisionWithoutTransaction(key) + 1
    try execute(
      """
      INSERT OR REPLACE INTO instant_sync_metadata (key, value, updated_at_ms)
      VALUES (?, ?, ?)
      """,
      [
        .text(key),
        .text(String(revision)),
        .int(Self.nowMilliseconds()),
      ]
    )
    return revision
  }

  private func nextStreamChunkIndexWithoutTransaction(appID: String, streamID: String) throws -> Int64 {
    let value: String? = try selectScalar(
      """
      SELECT CAST(COALESCE(MAX(chunk_index), -1) + 1 AS TEXT)
      FROM instant_stream_chunks
      WHERE app_id = ? AND stream_id = ?
      """,
      [.text(appID), .text(streamID)]
    )
    return value.flatMap(Int64.init) ?? 0
  }

  private func streamMetadataWithoutTransaction(
    appID: String,
    streamID: String
  ) throws -> InstantStreamMetadata? {
    let rows: [InstantStreamMetadata] = try selectJSON(
      """
      SELECT json FROM instant_streams
      WHERE app_id = ? AND stream_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(streamID)]
    )
    return rows.first
  }

  private func streamMetadataWithoutTransaction(
    appID: String,
    clientID: String
  ) throws -> InstantStreamMetadata? {
    let rows: [InstantStreamMetadata] = try selectJSON(
      """
      SELECT json FROM instant_streams
      WHERE app_id = ? AND client_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(clientID)]
    )
    return rows.first
  }

  private func insertStreamMetadataWithoutTransaction(_ metadata: InstantStreamMetadata) throws {
    try execute(
      """
      INSERT INTO instant_streams
        (app_id, stream_id, client_id, user_id, done, size, abort_reason,
         created_at_ms, updated_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(metadata.appID),
        .text(metadata.id),
        .text(metadata.clientID),
        .text(metadata.userID),
        .int(metadata.done ? Int64(1) : Int64(0)),
        metadata.size.map { .int($0) } ?? .null,
        metadata.abortReason.map { .text($0) } ?? .null,
        .int(metadata.createdAt.milliseconds),
        .int(metadata.updatedAt.milliseconds),
        .text(try encode(metadata)),
      ]
    )
  }

  private func saveStreamMetadataWithoutTransaction(_ metadata: InstantStreamMetadata) throws {
    try execute(
      """
      INSERT INTO instant_streams
        (app_id, stream_id, client_id, user_id, done, size, abort_reason,
         created_at_ms, updated_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(app_id, stream_id) DO UPDATE SET
        client_id = excluded.client_id,
        user_id = excluded.user_id,
        done = excluded.done,
        size = excluded.size,
        abort_reason = excluded.abort_reason,
        created_at_ms = excluded.created_at_ms,
        updated_at_ms = excluded.updated_at_ms,
        json = excluded.json
      """,
      [
        .text(metadata.appID),
        .text(metadata.id),
        .text(metadata.clientID),
        .text(metadata.userID),
        .int(metadata.done ? Int64(1) : Int64(0)),
        metadata.size.map { .int($0) } ?? .null,
        metadata.abortReason.map { .text($0) } ?? .null,
        .int(metadata.createdAt.milliseconds),
        .int(metadata.updatedAt.milliseconds),
        .text(try encode(metadata)),
      ]
    )
  }

  private func streamContentSizeWithoutTransaction(appID: String, streamID: String) throws -> Int64 {
    let value: String? = try selectScalar(
      """
      SELECT CAST(COALESCE(SUM(byte_count), 0) AS TEXT)
      FROM instant_stream_content_chunks
      WHERE app_id = ? AND stream_id = ?
      """,
      [.text(appID), .text(streamID)]
    )
    return value.flatMap(Int64.init) ?? 0
  }

  private func streamContentReadWithoutTransaction(
    metadata: InstantStreamMetadata,
    byteOffset: Int64
  ) throws -> InstantStreamContentRead {
    let currentSize = try streamContentSizeWithoutTransaction(
      appID: metadata.appID,
      streamID: metadata.id
    )
    guard byteOffset <= currentSize else {
      throw streamValidationError(
        operation: "read stream content",
        localID: metadata.id,
        message:
          "Stream '\(metadata.id)' contains \(currentSize) bytes, so byte offset \(byteOffset) is out of range.",
        recovery: "Read from an offset less than or equal to the stream byte count."
      )
    }

    let chunks: [InstantStreamContentChunk] = try selectJSON(
      """
      SELECT json FROM instant_stream_content_chunks
      WHERE app_id = ? AND stream_id = ? AND offset + byte_count > ?
      ORDER BY offset, chunk_id
      """,
      [.text(metadata.appID), .text(metadata.id), .int(byteOffset)]
    )

    var data = Data()
    for chunk in chunks {
      data.append(contentsOf: chunk.content.utf8)
    }
    if let firstChunk = chunks.first {
      let droppedByteCount = byteOffset - firstChunk.offset
      if droppedByteCount > 0 {
        data.removeFirst(Int(droppedByteCount))
      }
    }
    guard let content = String(data: data, encoding: .utf8) else {
      throw streamValidationError(
        operation: "read stream content",
        localID: metadata.id,
        message:
          "Stream '\(metadata.id)' cannot be decoded from byte offset \(byteOffset) as UTF-8.",
        recovery: "Resume from a UTF-8 character boundary when using Swift string streams."
      )
    }
    return InstantStreamContentRead(
      metadata: metadata,
      byteOffset: byteOffset,
      byteCount: Int64(data.count),
      content: content,
      done: metadata.done,
      abortReason: metadata.abortReason
    )
  }

  private func saveShareWithoutTransaction(_ share: InstantShare) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_shares
        (app_id, share_id, root_namespace, root_id, owner_user_id, token,
         created_at_ms, updated_at_ms, revoked_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(share.appID),
        .text(share.id),
        .text(share.rootNamespace),
        .text(share.rootID),
        .text(share.ownerUserID),
        .text(share.token),
        .int(share.createdAt.milliseconds),
        .int(share.updatedAt.milliseconds),
        share.revokedAt.map { .int($0.milliseconds) } ?? .null,
        .text(try encode(share)),
      ]
    )
  }

  private func saveShareMembershipWithoutTransaction(_ membership: InstantShareMembership) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_share_memberships
        (app_id, share_id, user_id, role, accepted_at_ms, revoked_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """,
      [
        .text(membership.appID),
        .text(membership.shareID),
        .text(membership.userID),
        .text(membership.role.rawValue),
        .int(membership.acceptedAt.milliseconds),
        membership.revokedAt.map { .int($0.milliseconds) } ?? .null,
        .text(try encode(membership)),
      ]
    )
  }

  private func shareWithoutTransaction(appID: String, shareID: String) throws -> InstantShare? {
    let shares: [InstantShare] = try selectJSON(
      """
      SELECT json FROM instant_shares
      WHERE app_id = ? AND share_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(shareID)]
    )
    return shares.first
  }

  private func shareWithoutTransaction(appID: String, token: String) throws -> InstantShare? {
    let shares: [InstantShare] = try selectJSON(
      """
      SELECT json FROM instant_shares
      WHERE app_id = ? AND token = ?
      LIMIT 1
      """,
      [.text(appID), .text(token)]
    )
    return shares.first
  }

  private func shareMembershipWithoutTransaction(
    appID: String,
    shareID: String,
    userID: String
  ) throws -> InstantShareMembership? {
    let memberships: [InstantShareMembership] = try selectJSON(
      """
      SELECT json FROM instant_share_memberships
      WHERE app_id = ? AND share_id = ? AND user_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(shareID), .text(userID)]
    )
    return memberships.first
  }

  private func shareMembershipsWithoutTransaction(
    appID: String,
    shareID: String,
    activeOnly: Bool
  ) throws -> [InstantShareMembership] {
    var sql =
      """
      SELECT json FROM instant_share_memberships
      WHERE app_id = ? AND share_id = ?
      """
    if activeOnly {
      sql.append("\nAND revoked_at_ms IS NULL")
    }
    sql.append("\nORDER BY accepted_at_ms, user_id")
    return try selectJSON(sql, [.text(appID), .text(shareID)])
  }

  private func shareSnapshotWithoutTransaction(
    appID: String,
    shareID: String,
    activeMembershipsOnly: Bool = false
  ) throws -> InstantShareSnapshot {
    guard let share = try shareWithoutTransaction(appID: appID, shareID: shareID) else {
      throw persistenceError(operation: "read share", message: "Share '\(shareID)' disappeared.")
    }
    let memberships = try shareMembershipsWithoutTransaction(
      appID: appID,
      shareID: shareID,
      activeOnly: activeMembershipsOnly
    )
    return InstantShareSnapshot(share: share, memberships: memberships)
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
    try ensureOpenConnection()
    guard sqlite3_prepare_v2(connection.raw, sql, -1, &statement, nil) == SQLITE_OK else {
      throw persistenceError(operation: "prepare SQL", message: lastErrorMessage())
    }
  }

  private func ensureOpenConnection() throws {
    guard connection.raw == nil else { return }
    try reopenConnection()
  }

  private func reopenConnection() throws {
    sqlite3_close(connection.raw)
    connection.raw = nil
    connection.raw = try Self.openRawConnection(fileURL: fileURL)
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

  private func streamValidationError(
    operation: String,
    localID: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      localID: localID,
      message: message,
      recovery: recovery
    )
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

  private var localFilesRootURL: URL {
    fileURL.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
  }

  private func sanitizedFileComponent(_ value: String) -> String {
    let sanitized = value.map { character in
      character == "/" || character == ":" || character == "\u{0}" ? "_" : character
    }
    let string = String(sanitized).trimmingCharacters(in: .whitespacesAndNewlines)
    return string.isEmpty || string == "." || string == ".." ? "file" : string
  }

  private func regularFileResourceValues(
    at sourceURL: URL,
    operation: String
  ) throws -> URLResourceValues {
    let sourceValues: URLResourceValues
    do {
      sourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    } catch {
      throw persistenceError(
        operation: operation,
        message: "Could not read source path '\(sourceURL.path)': \(error.localizedDescription)"
      )
    }
    guard sourceValues.isRegularFile == true else {
      throw persistenceError(
        operation: operation,
        message: "Source path '\(sourceURL.path)' is not a regular file."
      )
    }
    return sourceValues
  }

  private static let storeRevisionKey = "store_revision"
  private static let outboxRevisionKey = "outbox_revision"
}

private enum SQLiteBinding: Sendable {
  case int(Int64)
  case text(String)
  case null
}

private struct QueryCacheStorageRow: Sendable {
  var cacheKey: String
  var json: String
  var updatedAtMilliseconds: Int64

  var byteCount: Int {
    json.utf8.count
  }
}

private extension InstantError {
  var isSQLiteBusy: Bool {
    let lowercasedMessage = message.lowercased()
    return lowercasedMessage.contains("database is locked")
      || lowercasedMessage.contains("database schema is locked")
      || lowercasedMessage.contains("database table is locked")
  }
}

// SAFETY: SQLite's raw pointer is confined to the `SQLitePersistenceStore` actor.
// The wrapper is immutable outside that actor and only closes the connection when released.
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
