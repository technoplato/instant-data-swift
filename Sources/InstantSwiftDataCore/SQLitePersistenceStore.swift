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

  public func cachedQueries(queryID: String) throws -> [InstantCachedQuery] {
    try selectJSON(
      "SELECT json FROM instant_query_cache WHERE query_id = ? ORDER BY updated_at_ms, cache_key",
      [.text(queryID)]
    )
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
    let sourceValues: URLResourceValues
    do {
      sourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    } catch {
      throw persistenceError(
        operation: "upload file",
        message: "Could not read source path '\(sourceURL.path)': \(error.localizedDescription)"
      )
    }
    guard sourceValues.isRegularFile == true else {
      throw persistenceError(
        operation: "upload file",
        message: "Source path '\(sourceURL.path)' is not a regular file."
      )
    }

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

  public func deleteStoredFile(appID: String, fileID: String) throws -> InstantStoredFile? {
    let rows: [InstantStoredFile] = try selectJSON(
      """
      SELECT json FROM instant_files
      WHERE app_id = ? AND file_id = ?
      LIMIT 1
      """,
      [.text(appID), .text(fileID)]
    )
    guard let file = rows.first else { return nil }

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
    limit: Int? = nil
  ) throws -> [InstantStreamChunk] {
    var sql =
      """
      SELECT json FROM instant_stream_chunks
      WHERE app_id = ? AND stream_id = ?
      ORDER BY chunk_index, chunk_id
      """
    var bindings: [SQLiteBinding] = [.text(appID), .text(streamID)]
    if let limit {
      sql.append("\nLIMIT ?")
      bindings.append(.int(Int64(limit)))
    }
    return try selectJSON(sql, bindings)
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

  private static let storeRevisionKey = "store_revision"
  private static let outboxRevisionKey = "outbox_revision"
}

private enum SQLiteBinding: Sendable {
  case int(Int64)
  case text(String)
  case null
}

private extension InstantError {
  var isSQLiteBusy: Bool {
    let lowercasedMessage = message.lowercased()
    return lowercasedMessage.contains("database is locked")
      || lowercasedMessage.contains("database schema is locked")
      || lowercasedMessage.contains("database table is locked")
  }
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
