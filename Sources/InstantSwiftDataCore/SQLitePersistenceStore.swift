import Foundation
import SQLite3

public struct InstantPersistenceSnapshot: Hashable, Codable, Sendable {
  public var store: InstantStoreSnapshot
  public var outbox: [PendingMutation]

  public init(store: InstantStoreSnapshot = InstantStoreSnapshot(), outbox: [PendingMutation] = [])
  {
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

enum InstantPersistenceStateSource: Equatable, Sendable {
  case memory
  case sqlite
}

struct InstantPersistenceStateLoad: Sendable {
  var state: InstantPersistenceState
  var source: InstantPersistenceStateSource
}

struct InstantPersistenceMetadataEntry: Sendable {
  var key: String
  var value: String
  var updatedAt: InstantTimestamp
}

private struct StoredTripleKey: Hashable {
  var entityID: String
  var attributeID: String
  var value: InstantValue

  init(_ triple: InstantTriple) {
    self.entityID = triple.entityID
    self.attributeID = triple.attributeID
    self.value = triple.value
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

public struct InstantLiveQueryResultPruningPolicy: Hashable, Codable, Sendable {
  public var maxAgeMilliseconds: Int64?
  public var maxEntries: Int?
  public var maxTripleCount: Int?

  public init(
    maxAgeMilliseconds: Int64? = nil,
    maxEntries: Int? = nil,
    maxTripleCount: Int? = nil
  ) {
    self.maxAgeMilliseconds = maxAgeMilliseconds
    self.maxEntries = maxEntries
    self.maxTripleCount = maxTripleCount
  }
}

public struct InstantLiveQueryResultPruningResult: Hashable, Codable, Sendable {
  public var removedQueryKeys: [String]
  public var remainingQueryKeys: [String]
  public var removedOrphanedTripleCount: Int
  public var remainingEntryCount: Int
  public var remainingTripleCount: Int

  public init(
    removedQueryKeys: [String],
    remainingQueryKeys: [String],
    removedOrphanedTripleCount: Int,
    remainingEntryCount: Int,
    remainingTripleCount: Int
  ) {
    self.removedQueryKeys = removedQueryKeys
    self.remainingQueryKeys = remainingQueryKeys
    self.removedOrphanedTripleCount = removedOrphanedTripleCount
    self.remainingEntryCount = remainingEntryCount
    self.remainingTripleCount = remainingTripleCount
  }
}

struct InstantLiveQueryResultPruningApplication: Sendable {
  var result: InstantLiveQueryResultPruningResult
  var state: InstantPersistenceState
}

private struct LiveQueryResultStorageRow: Sendable {
  var queryKey: String
  var updatedAtMilliseconds: Int64
  var tripleCount: Int
}

private let instantPersistenceDecodeQueue = DispatchQueue(
  label: "com.instantdb.swift.persistence-decode",
  qos: .userInitiated,
  attributes: .concurrent
)

// SAFETY: storage is only read/written under `lock` (NSLock); callers never
// touch `storage` except through store/joined which take the lock.
private final class JSONBatchDecodeResults<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Int: Result<[Value], InstantError>] = [:]

  func store(_ result: Result<[Value], InstantError>, at index: Int) {
    lock.withLock { storage[index] = result }
  }

  func joined(batchCount: Int) throws -> [Value] {
    try lock.withLock {
      var values: [Value]?
      for index in 0..<batchCount {
        guard let result = storage.removeValue(forKey: index) else {
          throw InstantError(
            code: .implementationFailed,
            operation: "assemble persisted JSON rows",
            message: "Decoded SQLite JSON batch \(index) was missing.",
            recovery: "Report this missing persistence batch to the Instant Swift maintainer."
          )
        }
        let batch = try result.get()
        if values == nil {
          values = batch
        } else {
          values?.append(contentsOf: batch)
        }
      }
      return values ?? []
    }
  }
}

struct InstantOutboxRowAcceptance: Sendable {
  var mutation: PendingMutation?
  var pendingMutationCount: Int
  var didChange: Bool
}

public actor SQLitePersistenceStore {
  private let fileURL: URL
  private let startupTrace: InstantStartupTrace
  private let connection: SQLiteConnection
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder
  private var cachedState: InstantPersistenceState?
  private var didTraceInitialStateLoad = false
  /// Test-visible count of durable outbox JSON bodies decoded by this actor.
  /// This pins acknowledgement and delivery complexity to their selected rows.
  private var decodedOutboxBodyCount = 0

  package func resetDecodedOutboxBodyCount() {
    decodedOutboxBodyCount = 0
  }

  package func currentDecodedOutboxBodyCount() -> Int {
    decodedOutboxBodyCount
  }

  /// Drop the full triples array from the in-memory persistence cache.
  ///
  /// InstantStore already holds the hot corpus as TripleIndexes (EAV/AEV/VAE).
  /// Keeping a second full `InstantStoreSnapshot.triples` in `cachedState` is the
  /// dual-residency floor (production readiness P2.1). Attributes + outbox +
  /// revisions stay resident; triples reload from SQLite on cache miss.
  ///
  /// Autoresearch: 2026-08-07-scribe-list-memory / #044.
  /// When true, keep the second full triples array in memory (legacy dual residency).
  /// Default false (P2.1 thin cache). Autoresearch A/B uses this toggle.
  nonisolated(unsafe) package static var retainFullTriplesInMemoryForTesting = false


  public func invalidateMemoryCache() {
    cachedState = nil
  }

  private static func memoryThinnedOutbox(_ mutations: [PendingMutation]) -> [PendingMutation] {
    mutations.map(\.compactedForMemory)
  }

  private func adoptCachedState(_ state: InstantPersistenceState) {
    var thin = state
    if !Self.retainFullTriplesInMemoryForTesting {
      if !thin.snapshot.store.triples.isEmpty {
        thin.snapshot.store = InstantStoreSnapshot(
          attributes: thin.snapshot.store.attributes,
          triples: []
        )
      }
      if thin.snapshot.outbox.contains(where: {
        !$0.transaction.operations.isEmpty
          || $0.rollbackTransaction?.operations.isEmpty == false
      }) {
        thin.snapshot.outbox = Self.memoryThinnedOutbox(thin.snapshot.outbox)
      }
    }
    cachedState = thin
    try? execute("PRAGMA shrink_memory")
  }



  public init(
    fileURL: URL,
    startupTrace: InstantStartupTrace = .disabled
  ) throws {
    self.fileURL = fileURL
    self.startupTrace = startupTrace
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys]
    self.decoder = JSONDecoder()
    let stopwatch = startupTrace.started(
      "sqlite.open",
      metadata: ["file": fileURL.lastPathComponent]
    )
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.open-started",
      message: "Opening the Instant SQLite cache.",
      metadata: ["path": fileURL.path]
    )
    do {
      self.connection = SQLiteConnection(try Self.openRawConnection(fileURL: fileURL))
      startupTrace.completed(
        "sqlite.open",
        since: stopwatch,
        metadata: ["file": fileURL.lastPathComponent]
      )
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.open-completed",
        message: "Opened the Instant SQLite cache.",
        metadata: ["path": fileURL.path]
      )
    } catch {
      startupTrace.failed(
        "sqlite.open",
        error: error,
        since: stopwatch,
        metadata: ["file": fileURL.lastPathComponent]
      )
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.open-failed",
        message: "Failed to open the Instant SQLite cache.",
        metadata: ["path": fileURL.path]
      )
      throw error
    }
  }

  private static func openRawConnection(fileURL: URL) throws -> OpaquePointer? {
    let directory = fileURL.deletingLastPathComponent()
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: directory.path) {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }

    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(fileURL.path, &opened, flags, nil) == SQLITE_OK
    else {
      let message =
        opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
        ?? "SQLite could not open \(fileURL.path)."
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "open local cache",
        message: message,
        recovery: "Check that the cache directory is writable, or choose another persistence path."
      )
    }
    do {
      try securePersistenceFile(at: fileURL)
    } catch {
      sqlite3_close(opened)
      throw InstantError(
        code: .persistenceFailed,
        operation: "secure local cache",
        message: "SQLite opened the local cache but could not restrict its file permissions: \(error)",
        recovery: "Choose a persistence path whose file permissions can be changed."
      )
    }
    guard sqlite3_busy_timeout(opened, 10_000) == SQLITE_OK else {
      let message =
        opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
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
      let message =
        opened.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
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

  private static func securePersistenceFile(at fileURL: URL) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: fileURL.path
    )
  }

  private static func securePersistenceFiles(at fileURL: URL) throws {
    let fileManager = FileManager.default
    for url in [
      fileURL,
      URL(fileURLWithPath: fileURL.path + "-wal"),
      URL(fileURLWithPath: fileURL.path + "-shm"),
    ] where fileManager.fileExists(atPath: url.path) {
      try securePersistenceFile(at: url)
    }
  }

  public func bootstrap() throws {
    let stopwatch = startupTrace.started(
      "sqlite.schema",
      metadata: ["file": fileURL.lastPathComponent]
    )
    do {
    try Self.securePersistenceFiles(at: fileURL)
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.bootstrap-started",
      message: "Bootstrapping the Instant SQLite schema.",
      metadata: ["path": fileURL.path]
    )
    startupTrace.completed(
      "sqlite.schema",
      since: stopwatch,
      metadata: ["file": fileURL.lastPathComponent]
    )
    } catch {
      startupTrace.failed(
        "sqlite.schema",
        error: error,
        since: stopwatch,
        metadata: ["file": fileURL.lastPathComponent]
      )
      throw error
    }
    try withSQLiteBusyRetry {
      try execute("PRAGMA journal_mode = WAL")
    // Keep SQLite page cache tiny once InstantStore holds the hot corpus.
    try execute("PRAGMA cache_size = 0")  // ~2MiB

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
        try execute(
          "ALTER TABLE instant_room_topic_messages_v2 RENAME TO instant_room_topic_messages")
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
    try withSQLiteBusyRetry {
      try migrate(name: "0011_live_query_result_ownership") {
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_live_query_results (
            query_key TEXT PRIMARY KEY NOT NULL,
            triple_count INTEGER NOT NULL,
            updated_at_ms INTEGER NOT NULL,
            json TEXT NOT NULL
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_live_query_triples (
            query_key TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            attribute_id TEXT NOT NULL,
            value_json TEXT NOT NULL,
            PRIMARY KEY (query_key, entity_id, attribute_id, value_json),
            FOREIGN KEY (query_key) REFERENCES instant_live_query_results (query_key)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_live_query_triples_identity_idx
          ON instant_live_query_triples (entity_id, attribute_id, value_json, query_key)
          """
        )
      }
    }
    try Self.securePersistenceFiles(at: fileURL)
    InstantDiagnostics.shared.record(
      .notice,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.bootstrap-completed",
      message: "Instant SQLite schema is ready.",
      metadata: ["path": fileURL.path]
    )
  }

  package func bootstrap(
    queryCachePruningPolicy: InstantQueryCachePruningPolicy,
    now: InstantTimestamp
  ) throws -> InstantQueryCachePruningResult? {
    try bootstrap()
    do {
      return try pruneQueryCache(policy: queryCachePruningPolicy, now: now)
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-cache.bootstrap-prune-failed",
        message: "Could not prune persisted query results during runtime bootstrap."
      )
      return nil
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
    for _ in 0..<5 {
      let loaded = try loadStateWithSource()
      guard loaded.source == .memory else { return loaded.state }
      guard let state = try readTransaction({ () -> InstantPersistenceState? in
        guard try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == loaded.state.storeRevision,
          try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
            == loaded.state.outboxRevision
        else {
          return nil
        }
        return try InstantPersistenceState(
          snapshot: loadSnapshotWithoutTransaction(tracesStartupCollections: false),
          storeRevision: loaded.state.storeRevision,
          outboxRevision: loaded.state.outboxRevision
        )
      }) else { continue }
      return state
    }
    throw persistenceError(
      operation: "load persisted state",
      message: "The Instant store or outbox changed repeatedly while reconstructing durable state."
    )
  }

  /// Loads the memory-thinned cache view used by runtime paths that need only
  /// store data, revisions, or outbox identity/status metadata. Call `loadState()`
  /// when transaction and rollback operation bodies are part of the contract.
  func loadCompactState() throws -> InstantPersistenceState {
    try loadStateWithSource().state
  }

  func loadStateWithDurableOutbox() throws -> InstantPersistenceState {
    for _ in 0..<5 {
      let loaded = try loadStateWithSource()
      guard loaded.source == .memory else { return loaded.state }
      guard let outbox = try loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        expectedStoreRevision: loaded.state.storeRevision,
        expectedOutboxRevision: loaded.state.outboxRevision
      ) else { continue }
      var state = loaded.state
      state.snapshot.outbox = outbox
      return state
    }
    throw persistenceError(
      operation: "load durable outbox state",
      message: "The Instant outbox changed repeatedly while reconstructing durable mutations."
    )
  }

  func countOutboxMutations(status: InstantMutationStatus) throws -> Int {
    Int(try selectInt64(
      "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
      [.text(status.rawValue)]
    ))
  }

  func currentOutboxRevision() throws -> Int64 {
    try readTransaction {
      try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
  }

  /// Applies one WebSocket `transact-ok` receipt with a revision-checked row
  /// update. Only the addressed mutation body is decoded; the remaining outbox
  /// stays as compact identity/status metadata in memory and untouched JSON in
  /// SQLite.
  func acceptOutboxMutation(
    id: String,
    serverTransactionID: String,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxRowAcceptance? {
    let previousState = cachedState
    let acceptance: InstantOutboxRowAcceptance? = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return nil }

      let rows: [PendingMutation] = try selectJSON(
        "SELECT json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
        [.text(id)]
      )
      decodedOutboxBodyCount += rows.count
      guard var mutation = rows.first else {
        return InstantOutboxRowAcceptance(
          mutation: nil,
          pendingMutationCount: Int(try selectInt64(
            "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
            [.text(InstantMutationStatus.pending.rawValue)]
          )),
          didChange: false
        )
      }

      let alreadyAccepted = mutation.status == .confirmed
        && mutation.provesServerAcceptance
      if !alreadyAccepted {
        mutation.status = .confirmed
        mutation.failureMessage = nil
        mutation.failure = nil
        mutation.serverTransactionID = serverTransactionID
        mutation.confirmationSource = .webSocketTransactOK
        try execute(
          """
          UPDATE instant_outbox
          SET status = ?, json = ?
          WHERE mutation_id = ?
          """,
          [
            .text(mutation.status.rawValue),
            .text(try encode(mutation)),
            .text(mutation.id),
          ]
        )
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return InstantOutboxRowAcceptance(
        mutation: mutation,
        pendingMutationCount: Int(try selectInt64(
          "SELECT COUNT(*) FROM instant_outbox WHERE status = ?",
          [.text(InstantMutationStatus.pending.rawValue)]
        )),
        didChange: !alreadyAccepted
      )
    }

    guard let acceptance else { return nil }
    if acceptance.didChange, var previousState,
      previousState.outboxRevision == expectedOutboxRevision,
      let mutation = acceptance.mutation
    {
      if let index = previousState.snapshot.outbox.firstIndex(where: { $0.id == mutation.id }) {
        previousState.snapshot.outbox[index] = mutation.compactedForMemory
      } else {
        previousState.snapshot.outbox.append(mutation.compactedForMemory)
        previousState.snapshot.outbox.sort(by: PendingMutation.creationOrder)
      }
      previousState.outboxRevision += 1
      // `previousState` is already the actor's memory-thinned cache, and the
      // addressed mutation was compacted above. Avoid forcing SQLite to shrink
      // its page cache once per acknowledgement while a receipt burst drains.
      cachedState = previousState
    } else if acceptance.didChange {
      cachedState = nil
    }
    return acceptance
  }

  func loadOutboxMutations(
    statuses: [InstantMutationStatus],
    ids: [String]? = nil,
    limit: Int? = nil,
    expectedStoreRevision: Int64? = nil,
    expectedOutboxRevision: Int64
  ) throws -> [PendingMutation]? {
    let statuses = Array(Set(statuses.map(\.rawValue))).sorted()
    let ids = ids.map { Array(Set($0)).sorted() }
    let mutations: [PendingMutation]? = try readTransaction {
      if let expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          != expectedStoreRevision
      {
        return nil
      }
      guard try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        == expectedOutboxRevision
      else {
        return nil
      }
      guard !statuses.isEmpty, ids?.isEmpty != true, limit != 0 else { return [] }
      let statusPlaceholders = Array(repeating: "?", count: statuses.count)
        .joined(separator: ", ")
      var sql =
        "SELECT json FROM instant_outbox WHERE status IN (\(statusPlaceholders))"
      var bindings = statuses.map(SQLiteBinding.text)
      if let ids {
        let idPlaceholders = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        sql += " AND mutation_id IN (\(idPlaceholders))"
        bindings.append(contentsOf: ids.map(SQLiteBinding.text))
      }
      sql += " ORDER BY created_at_ms, mutation_id"
      if let limit {
        sql += " LIMIT ?"
        bindings.append(.int(Int64(limit)))
      }
      return try selectJSON(sql, bindings)
    }
    decodedOutboxBodyCount += mutations?.count ?? 0
    return mutations
  }

  func loadStateWithSource() throws -> InstantPersistenceStateLoad {
    let startupStopwatch = didTraceInitialStateLoad
      ? nil
      : startupTrace.started(
        "sqlite.state-load",
        metadata: ["file": fileURL.lastPathComponent]
      )
    let startedAt = Date()
    do {
      let loaded = try readTransaction {
        let storeRevision = try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
        let outboxRevision = try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        if let cachedState,
          cachedState.storeRevision == storeRevision,
          cachedState.outboxRevision == outboxRevision
        {
          // Intentionally keep thinned outbox shells in the RAM cache. Callers that
          // need full ops (flush) must load from SQLite explicitly.
          return InstantPersistenceStateLoad(state: cachedState, source: .memory)
        }
        return InstantPersistenceStateLoad(
          state: try InstantPersistenceState(
            snapshot: loadSnapshotWithoutTransaction(),
            storeRevision: storeRevision,
            outboxRevision: outboxRevision
          ),
          source: .sqlite
        )
      }
      let state = loaded.state
      adoptCachedState(state)
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.state-loaded",
        message: "Loaded the Instant cache state.",
        metadata: [
          "attributeCount": String(state.snapshot.store.attributes.count),
          "tripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
          "storeRevision": String(state.storeRevision),
          "outboxRevision": String(state.outboxRevision),
          "source": loaded.source == .memory ? "memory" : "sqlite",
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      if let startupStopwatch {
        didTraceInitialStateLoad = true
        startupTrace.completed(
          "sqlite.state-load",
          since: startupStopwatch,
          metadata: [
            "attributeCount": String(state.snapshot.store.attributes.count),
            "tripleCount": String(state.snapshot.store.triples.count),
            "outboxCount": String(state.snapshot.outbox.count),
            "source": loaded.source == .memory ? "memory" : "sqlite",
          ]
        )
      }
      return loaded
    } catch {
      if let startupStopwatch {
        startupTrace.failed(
          "sqlite.state-load",
          error: error,
          since: startupStopwatch,
          metadata: ["file": fileURL.lastPathComponent]
        )
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "persistence",
        event: "sqlite.state-load-failed",
        message: "Failed to load the Instant cache state.",
        metadata: ["path": fileURL.path]
      )
      throw error
    }
  }

  private func loadSnapshotWithoutTransaction(
    tracesStartupCollections: Bool = true
  ) throws -> InstantPersistenceSnapshot {
    InstantPersistenceSnapshot(
      store: try loadStoreSnapshotWithoutTransaction(
        tracesStartupCollections: tracesStartupCollections
      ),
      outbox: try loadOutboxWithoutTransaction(
        tracesStartupCollections: tracesStartupCollections
      )
    )
  }

  private func loadStoreSnapshotWithoutTransaction(
    tracesStartupCollections: Bool = true
  ) throws -> InstantStoreSnapshot {
    let attributes: [InstantAttribute] = try loadStateCollection(
      phase: "sqlite.state-load.attributes",
      sql: "SELECT json FROM instant_attributes ORDER BY id",
      tracesStartupCollection: tracesStartupCollections
    )
    let triples: [InstantTriple] = try loadStateCollection(
      phase: "sqlite.state-load.triples",
      sql: "SELECT json FROM instant_triples ORDER BY entity_id, attribute_id, value_json",
      tracesStartupCollection: tracesStartupCollections
    )
    return InstantStoreSnapshot(attributes: attributes, triples: triples)
  }

  private func loadOutboxWithoutTransaction(
    tracesStartupCollections: Bool = true
  ) throws -> [PendingMutation] {
    let mutations: [PendingMutation] = try loadStateCollection(
      phase: "sqlite.state-load.outbox",
      sql: "SELECT json FROM instant_outbox ORDER BY created_at_ms, mutation_id",
      tracesStartupCollection: tracesStartupCollections
    )
    decodedOutboxBodyCount += mutations.count
    return mutations
  }

  private func loadStateCollection<Value: Decodable & Sendable>(
    phase: String,
    sql: String,
    tracesStartupCollection: Bool = true
  ) throws -> [Value] {
    let stopwatch = startupTrace.stopwatch()
    do {
      let selection: (values: [Value], batchCount: Int, encodedByteCount: Int) =
        try selectBatchedJSON(sql)
      if tracesStartupCollection {
        startupTrace.completed(
          phase,
          since: stopwatch,
          metadata: [
            "count": String(selection.values.count),
            "decodeBatchCount": String(selection.batchCount),
            "decodeConcurrency": "2",
            "decodeStrategy": "batched-json-array",
            "encodedByteCount": String(selection.encodedByteCount),
          ]
        )
      }
      return selection.values
    } catch {
      if tracesStartupCollection {
        startupTrace.failed(phase, error: error, since: stopwatch)
      }
      throw error
    }
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

  func loadStoreStateAndCachedQuery(
    cacheKey: String
  ) throws -> (state: InstantPersistenceState, cachedQuery: InstantCachedQuery?) {
    try readTransaction {
      let state = try InstantPersistenceState(
        snapshot: InstantPersistenceSnapshot(
          store: loadStoreSnapshotWithoutTransaction(),
          outbox: []
        ),
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

  func liveQueryResult(key: String) throws -> InstantPersistedLiveQueryResult? {
    try liveQueryResultWithoutTransaction(key: key)
  }

  func liveQueryReplacementRetractions(
    for replacements: [InstantLiveQueryResultReplacement]
  ) throws -> [InstantTripleOperation] {
    guard !replacements.isEmpty else { return [] }
    return try readTransaction {
      let replacementKeys = Set(replacements.map(\.key))
      var prospective: [String: [InstantLiveTripleIdentity: InstantTriple]] = [:]
      for key in replacementKeys {
        let triples = try liveQueryResultWithoutTransaction(key: key)?.triples ?? []
        prospective[key] = Self.indexLiveTriples(triples)
      }

      var removed: [InstantLiveTripleIdentity: InstantTriple] = [:]
      for replacement in replacements {
        let next = Self.indexLiveTriples(replacement.triples)
        let previous = prospective[replacement.key] ?? [:]
        for (identity, triple) in previous where next[identity] == nil {
          removed[identity] = triple
        }
        prospective[replacement.key] = next
      }

      let retainedByReplacements = Set(prospective.values.flatMap(\.keys))
      var retractions: [InstantTriple] = []
      for identity in removed.keys where !retainedByReplacements.contains(identity) {
        if try liveQueryTripleHasOwnerWithoutTransaction(
          identity,
          excludingQueryKeys: replacementKeys
        ) {
          continue
        }
        if let triple = removed[identity] {
          retractions.append(triple)
        }
      }
      return retractions
        .sorted {
          ($0.entityID, $0.attributeID, $0.value.comparableKey)
            < ($1.entityID, $1.attributeID, $1.value.comparableKey)
        }
        .map(InstantTripleOperation.retract)
    }
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
    cachedState = nil
  }

  public func saveOutbox(_ mutations: [PendingMutation]) throws {
    try transaction {
      try saveOutboxWithoutTransaction(mutations)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
    cachedState = nil
  }

  public func saveOutbox(
    _ mutations: [PendingMutation],
    replacing previousMutations: [PendingMutation]? = nil,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let previousState = cachedState
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else {
        return false
      }
      let previousMutations = try previousMutations
        ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
      try saveOutboxDiffWithoutTransaction(from: previousMutations, to: mutations)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave, var previousState,
      previousState.outboxRevision == expectedOutboxRevision
    {
      previousState.snapshot.outbox = mutations
      previousState.outboxRevision += 1
      adoptCachedState(previousState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  func saveOutbox(
    _ mutations: [PendingMutation],
    replacing previousMutations: [PendingMutation]? = nil,
    metadataEntries: [InstantPersistenceMetadataEntry],
    deletingMetadataKeys: [String] = [],
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let previousState = cachedState
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      let previousMutations = try previousMutations
        ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
      try saveOutboxDiffWithoutTransaction(from: previousMutations, to: mutations)
      for entry in metadataEntries {
        try saveMetadataValueWithoutTransaction(
          entry.value,
          key: entry.key,
          updatedAt: entry.updatedAt
        )
      }
      for key in deletingMetadataKeys {
        try deleteMetadataValueWithoutTransaction(key: key)
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave, var previousState,
      previousState.storeRevision == expectedStoreRevision,
      previousState.outboxRevision == expectedOutboxRevision
    {
      previousState.snapshot.outbox = mutations
      previousState.outboxRevision += 1
      adoptCachedState(previousState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
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
      ORDER BY created_at_ms, rowid
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
    _ = try regularFileByteCount(at: sourceURL, operation: "upload file")

    let directory =
      localFilesRootURL
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
    savedFile.byteCount = try regularFileByteCount(at: targetURL, operation: "upload file")
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

  public func saveDownloadedFile(
    _ file: InstantStoredFile,
    data: Data
  ) throws -> InstantStoredFile {
    let directory =
      localFilesRootURL
      .appendingPathComponent(sanitizedFileComponent(file.appID), isDirectory: true)
      .appendingPathComponent(sanitizedFileComponent(file.id), isDirectory: true)
    let targetURL = directory.appendingPathComponent(sanitizedFileComponent(file.name))
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: targetURL, options: .atomic)
    } catch {
      throw persistenceError(
        operation: "download file",
        message:
          "Could not cache downloaded file '\(file.name)' locally: \(error.localizedDescription)"
      )
    }

    var savedFile = file
    savedFile.byteCount = Int64(data.count)
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
    let attributes: [FileAttributeKey: Any]
    do {
      attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
    } catch {
      throw persistenceError(
        operation: operation,
        message: "Could not read source path '\(sourceURL.path)': \(error.localizedDescription)"
      )
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
      throw persistenceError(
        operation: operation,
        message: "Source path '\(sourceURL.path)' is not a regular file."
      )
    }
    return (attributes[.size] as? NSNumber)?.int64Value ?? 0
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

  public func storageSnapshot(appID: String) throws -> InstantStorageSnapshot {
    let files = try loadStoredFiles(appID: appID)
    let streamCacheSize = try selectInt64(
      """
      SELECT COALESCE(SUM(byte_count), 0)
      FROM instant_stream_content_chunks
      WHERE app_id = ?
      """,
      [.text(appID)]
    )
    return InstantStorageSnapshot(
      localCacheSize: localCacheFileSize(),
      streamCacheSize: streamCacheSize,
      downloadedFileSize: files.reduce(0) { $0 + $1.byteCount },
      downloadedFileCount: files.count
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

  public func ensureStreamMetadata(
    appID: String,
    streamID: String,
    clientID: String,
    userID: String,
    createdAt: InstantTimestamp
  ) throws -> InstantStreamMetadata {
    try transaction {
      if let existing = try streamMetadataWithoutTransaction(appID: appID, streamID: streamID) {
        guard existing.clientID == clientID else {
          throw streamValidationError(
            operation: "bootstrap stream metadata",
            localID: streamID,
            message:
              "Stream '\(streamID)' is already associated with client id '\(existing.clientID)', not '\(clientID)'.",
            recovery: "Reconnect using the client id returned by the canonical stream append."
          )
        }
        return existing
      }
      if let existing = try streamMetadataWithoutTransaction(appID: appID, clientID: clientID) {
        throw streamValidationError(
          operation: "bootstrap stream metadata",
          localID: clientID,
          message:
            "Stream client id '\(clientID)' already belongs to stream '\(existing.id)', not '\(streamID)'.",
          recovery: "Reconnect the client-id reader and inspect the canonical stream id."
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
        try shareSnapshotWithoutTransaction(
          appID: appID, shareID: $0.id, activeMembershipsOnly: true)
      }
    }
  }

  func pruneLiveQueryResults(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp,
    preservingQueryKeys: Set<String> = [],
    currentStoreSnapshot: InstantStoreSnapshot? = nil
  ) throws -> InstantLiveQueryResultPruningApplication {
    let application = try transaction {
      let storeRevision = try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      let outboxRevision = try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      let currentState: InstantPersistenceState
      if var cachedState,
        cachedState.storeRevision == storeRevision,
        cachedState.outboxRevision == outboxRevision
      {
        // Pruning protects rows touched by every active optimistic mutation. The
        // RAM cache intentionally stores pending transactions as empty shells,
        // so reconstruct their durable bodies only for this pruning transaction.
        if !cachedState.snapshot.outbox.isEmpty {
          cachedState.snapshot.outbox = try loadOutboxWithoutTransaction(
            tracesStartupCollections: false
          )
        }
        if cachedState.snapshot.store.triples.isEmpty {
          if let currentStoreSnapshot {
            cachedState.snapshot.store = currentStoreSnapshot
          } else {
            cachedState.snapshot.store = try loadStoreSnapshotWithoutTransaction(
              tracesStartupCollections: false
            )
          }
        }
        currentState = cachedState
      } else {
        currentState = try InstantPersistenceState(
          snapshot: loadSnapshotWithoutTransaction(),
          storeRevision: storeRevision,
          outboxRevision: outboxRevision
        )
      }
      var rows = try loadLiveQueryResultRowsWithoutTransaction()
      var protectedQueryKeys = preservingQueryKeys
      let optimisticProtection = Self.liveQueryPruningProtection(
        currentState.snapshot.outbox
      )
      if optimisticProtection.preservesAllQueryResults {
        protectedQueryKeys.formUnion(rows.map(\.queryKey))
      } else if !optimisticProtection.entityIDs.isEmpty {
        protectedQueryKeys.formUnion(
          try liveQueryKeysOwningEntityIDsWithoutTransaction(
            optimisticProtection.entityIDs
          )
        )
      }

      var removedRows: [LiveQueryResultStorageRow] = []
      func remove(_ row: LiveQueryResultStorageRow) -> Bool {
        guard !protectedQueryKeys.contains(row.queryKey) else { return false }
        rows.removeAll { $0.queryKey == row.queryKey }
        removedRows.append(row)
        return true
      }

      if let maxAgeMilliseconds = policy.maxAgeMilliseconds {
        let cutoff = now.milliseconds - Swift.max(0, maxAgeMilliseconds)
        for row in rows where row.updatedAtMilliseconds < cutoff {
          _ = remove(row)
        }
      }
      if let maxEntries = policy.maxEntries {
        let limit = Swift.max(0, maxEntries)
        while rows.count > limit {
          guard let row = rows.first(where: { !protectedQueryKeys.contains($0.queryKey) })
          else { break }
          _ = remove(row)
        }
      }
      if let maxTripleCount = policy.maxTripleCount {
        let limit = Swift.max(0, maxTripleCount)
        var tripleCount = rows.reduce(0) { $0 + $1.tripleCount }
        while tripleCount > limit {
          guard let row = rows.first(where: { !protectedQueryKeys.contains($0.queryKey) })
          else { break }
          guard remove(row) else { continue }
          tripleCount -= row.tripleCount
        }
      }

      guard !removedRows.isEmpty else {
        return InstantLiveQueryResultPruningApplication(
          result: InstantLiveQueryResultPruningResult(
            removedQueryKeys: [],
            remainingQueryKeys: rows.map(\.queryKey),
            removedOrphanedTripleCount: 0,
            remainingEntryCount: rows.count,
            remainingTripleCount: rows.reduce(0) { $0 + $1.tripleCount }
          ),
          state: currentState
        )
      }

      var snapshot = currentState.snapshot
      var removedIdentities: Set<InstantLiveTripleIdentity> = []
      for row in removedRows {
        guard let result = try liveQueryResultWithoutTransaction(key: row.queryKey) else {
          continue
        }
        for triple in result.triples {
          removedIdentities.insert(InstantLiveTripleIdentity(triple))
        }
        try execute(
          "DELETE FROM instant_live_query_results WHERE query_key = ?",
          [.text(row.queryKey)]
        )
      }

      let previousStore = snapshot.store
      let currentTriples = Dictionary(
        snapshot.store.triples.map { (InstantLiveTripleIdentity($0), $0) },
        uniquingKeysWith: { _, latest in latest }
      )
      var orphanedIdentities: Set<InstantLiveTripleIdentity> = []
      for identity in removedIdentities {
        guard
          !(try liveQueryTripleHasOwnerWithoutTransaction(
            identity,
            excludingQueryKeys: []
          )),
          currentTriples[identity] != nil
        else { continue }
        orphanedIdentities.insert(identity)
      }
      snapshot.store.triples.removeAll {
        orphanedIdentities.contains(InstantLiveTripleIdentity($0))
      }
      if snapshot.store != previousStore {
        try saveStoreSnapshotDiffWithoutTransaction(
          from: previousStore,
          to: snapshot.store
        )
      }
      let nextStoreRevision = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      return InstantLiveQueryResultPruningApplication(
        result: InstantLiveQueryResultPruningResult(
          removedQueryKeys: removedRows.map(\.queryKey),
          remainingQueryKeys: rows.map(\.queryKey),
          removedOrphanedTripleCount: orphanedIdentities.count,
          remainingEntryCount: rows.count,
          remainingTripleCount: rows.reduce(0) { $0 + $1.tripleCount }
        ),
        state: InstantPersistenceState(
          snapshot: snapshot,
          storeRevision: nextStoreRevision,
          outboxRevision: outboxRevision
        )
      )
    }
    adoptCachedState(application.state)
    return application
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
        try shareSnapshotWithoutTransaction(
          appID: appID, shareID: $0.id, activeMembershipsOnly: true)
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
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
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
    let revisions = try transaction {
      try saveStoreSnapshotWithoutTransaction(snapshot.store)
      try saveOutboxWithoutTransaction(snapshot.outbox)
      return (
        store: try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        outbox: try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
    }
    adoptCachedState(InstantPersistenceState(
      snapshot: snapshot,
      storeRevision: revisions.store,
      outboxRevision: revisions.outbox
    ))
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "persistence",
      event: "sqlite.snapshot-saved",
      message: "Saved an Instant cache snapshot.",
      metadata: [
        "attributeCount": String(snapshot.store.attributes.count),
        "tripleCount": String(snapshot.store.triples.count),
        "outboxCount": String(snapshot.outbox.count),
      ]
    )
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
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
    if didSave {
      adoptCachedState(InstantPersistenceState(
        snapshot: snapshot,
        storeRevision: expectedStoreRevision + 1,
        outboxRevision: expectedOutboxRevision + 1
      ))
    }
    return didSave
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveOutboxDiffWithoutTransaction(
        from: previousSnapshot.outbox,
        to: snapshot.outbox
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave {
      adoptCachedState(InstantPersistenceState(
        snapshot: snapshot,
        storeRevision: expectedStoreRevision + 1,
        outboxRevision: expectedOutboxRevision + 1
      ))
    }
    return didSave
  }

  func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot,
    metadataEntries: [InstantPersistenceMetadataEntry],
    deletingMetadataKeys: [String] = [],
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveOutboxDiffWithoutTransaction(
        from: previousSnapshot.outbox,
        to: snapshot.outbox
      )
      for entry in metadataEntries {
        try saveMetadataValueWithoutTransaction(
          entry.value,
          key: entry.key,
          updatedAt: entry.updatedAt
        )
      }
      for key in deletingMetadataKeys {
        try deleteMetadataValueWithoutTransaction(key: key)
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave {
      adoptCachedState(InstantPersistenceState(
        snapshot: snapshot,
        storeRevision: expectedStoreRevision + 1,
        outboxRevision: expectedOutboxRevision + 1
      ))
    }
    return didSave
  }

  func saveLocalMutation(
    changedEntityTriples: [String: [InstantTriple]],
    outbox: [PendingMutation],
    pendingMutation: PendingMutation,
    metadataEntries: [InstantPersistenceMetadataEntry] = [],
    deletingMetadataKeys: [String] = [],
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    // Dual-residency thin cache keeps attributes/outbox/revisions only. Empty
    // triples must not be treated as "entity has no triples" — fall back to SQLite.
    let cachedChangedEntityTriples: [String: [InstantTriple]]?
    if let cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.outboxRevision == expectedOutboxRevision,
      !cachedState.snapshot.store.triples.isEmpty
    {
      cachedChangedEntityTriples = Dictionary(
        uniqueKeysWithValues: changedEntityTriples.keys.map { entityID in
          (entityID, cachedTriples(in: cachedState.snapshot.store.triples, entityID: entityID))
        }
      )
    } else {
      cachedChangedEntityTriples = nil
    }

    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }

      for entityID in changedEntityTriples.keys.sorted() {
        let previousTriples = try cachedChangedEntityTriples?[entityID]
          ?? selectJSON(
            "SELECT json FROM instant_triples WHERE entity_id = ? ORDER BY attribute_id, value_json",
            [.text(entityID)]
          )
        try saveTripleDiffWithoutTransaction(
          from: previousTriples,
          to: changedEntityTriples[entityID, default: []]
        )
      }
      try execute(
        """
        INSERT OR REPLACE INTO instant_outbox (mutation_id, status, created_at_ms, json)
        VALUES (?, ?, ?, ?)
        """,
        [
          .text(pendingMutation.id),
          .text(pendingMutation.status.rawValue),
          .int(pendingMutation.createdAt.milliseconds),
          .text(try encode(pendingMutation)),
        ]
      )
      for entry in metadataEntries {
        try saveMetadataValueWithoutTransaction(
          entry.value,
          key: entry.key,
          updatedAt: entry.updatedAt
        )
      }
      for key in deletingMetadataKeys {
        try deleteMetadataValueWithoutTransaction(key: key)
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }

    if didSave, var cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.outboxRevision == expectedOutboxRevision
    {
      if !cachedState.snapshot.store.triples.isEmpty {
        replaceCachedTriples(
          in: &cachedState.snapshot.store.triples,
          with: changedEntityTriples
        )
      }
      cachedState.snapshot.outbox = outbox
      cachedState.storeRevision += 1
      cachedState.outboxRevision += 1
      adoptCachedState(cachedState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  public func saveStoreSnapshot(
    _ snapshot: InstantStoreSnapshot,
    replacing previousSnapshot: InstantStoreSnapshot,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      try saveStoreSnapshotDiffWithoutTransaction(from: previousSnapshot, to: snapshot)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      return true
    }
    if didSave, var cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.outboxRevision == expectedOutboxRevision
    {
      cachedState.snapshot.store = snapshot
      cachedState.storeRevision += 1
      adoptCachedState(cachedState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  public func saveSnapshot(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot? = nil,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      // `cachedState` is intentionally memory compacted: it may omit every
      // triple and every transaction body. It therefore cannot be the previous
      // side of a durable diff. Runtime callers pass the already-hydrated state;
      // direct callers fall back to one atomic SQLite read.
      let previousSnapshot = try previousSnapshot
        ?? loadSnapshotWithoutTransaction(tracesStartupCollections: false)
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot.store,
        to: snapshot.store
      )
      try saveOutboxDiffWithoutTransaction(
        from: previousSnapshot.outbox,
        to: snapshot.outbox
      )
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave {
      adoptCachedState(InstantPersistenceState(
        snapshot: snapshot,
        storeRevision: expectedStoreRevision + 1,
        outboxRevision: expectedOutboxRevision + 1
      ))
    }
    return didSave
  }

  public func saveOutbox(
    _ mutations: [PendingMutation],
    replacing previousMutations: [PendingMutation]? = nil,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let previousState = cachedState
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      let previousMutations = try previousMutations
        ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
      try saveOutboxDiffWithoutTransaction(from: previousMutations, to: mutations)
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didSave, var previousState,
      previousState.storeRevision == expectedStoreRevision,
      previousState.outboxRevision == expectedOutboxRevision
    {
      previousState.snapshot.outbox = mutations
      previousState.outboxRevision += 1
      adoptCachedState(previousState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  public func saveStoreSnapshot(
    _ snapshot: InstantStoreSnapshot,
    replacing previousSnapshot: InstantStoreSnapshot? = nil,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let previousState = cachedState
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      let previousSnapshot = try previousSnapshot
        ?? loadStoreSnapshotWithoutTransaction(tracesStartupCollections: false)
      try saveStoreSnapshotDiffWithoutTransaction(
        from: previousSnapshot,
        to: snapshot
      )
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      return true
    }
    if didSave, var previousState,
      previousState.storeRevision == expectedStoreRevision,
      previousState.outboxRevision == expectedOutboxRevision
    {
      previousState.snapshot.store = snapshot
      previousState.storeRevision += 1
      adoptCachedState(previousState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  func saveLiveRefresh(
    _ snapshot: InstantPersistenceSnapshot,
    replacing previousSnapshot: InstantPersistenceSnapshot? = nil,
    queryResults: [InstantPersistedLiveQueryResult],
    storeChanged: Bool,
    outboxChanged: Bool,
    metadataKey: String,
    metadataValue: String,
    metadataUpdatedAt: InstantTimestamp,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    let bumpsStoreRevision = storeChanged || !queryResults.isEmpty
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      if storeChanged {
        let previousStoreSnapshot = try previousSnapshot?.store
          ?? loadStoreSnapshotWithoutTransaction(tracesStartupCollections: false)
        try saveStoreSnapshotDiffWithoutTransaction(
          from: previousStoreSnapshot,
          to: snapshot.store
        )
      }
      if outboxChanged {
        let previousOutbox = try previousSnapshot?.outbox
          ?? loadOutboxWithoutTransaction(tracesStartupCollections: false)
        try saveOutboxDiffWithoutTransaction(
          from: previousOutbox,
          to: snapshot.outbox
        )
      }
      for result in queryResults {
        try saveLiveQueryResultWithoutTransaction(result)
      }
      try saveMetadataValueWithoutTransaction(
        metadataValue,
        key: metadataKey,
        updatedAt: metadataUpdatedAt
      )
      if bumpsStoreRevision {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
      }
      if outboxChanged {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return true
    }
    if didSave, var cachedState,
      cachedState.storeRevision == expectedStoreRevision,
      cachedState.outboxRevision == expectedOutboxRevision
    {
      if storeChanged {
        cachedState.snapshot.store = snapshot.store
      }
      if outboxChanged {
        cachedState.snapshot.outbox = snapshot.outbox
      }
      cachedState.storeRevision += bumpsStoreRevision ? 1 : 0
      cachedState.outboxRevision += outboxChanged ? 1 : 0
      adoptCachedState(cachedState)
    } else if didSave {
      cachedState = nil
    }
    return didSave
  }

  public func saveQueryCache(
    _ entry: InstantCachedQuery,
    expectedStoreRevision: Int64
  ) throws -> Bool {
    try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision
      else {
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
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision
      else {
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
      } catch let error as InstantError where error.code == .persistenceFailed && error.isSQLiteBusy
      {
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

  private func selectBatchedJSON<Value: Decodable & Sendable>(
    _ sql: String,
    maxRowsPerBatch: Int = 1_024,
    maxEncodedBytesPerBatch: Int = 1_024 * 1_024
  ) throws -> (values: [Value], batchCount: Int, encodedByteCount: Int) {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }

    let decodeResults = JSONBatchDecodeResults<Value>()
    let decodeGroup = DispatchGroup()
    let decodeSlots = DispatchSemaphore(value: 2)
    let persistencePath = fileURL.path
    var batchData = Data()
    batchData.reserveCapacity(maxEncodedBytesPerBatch + 1)
    batchData.append(0x5B)
    var batchRowCount = 0
    var totalRowCount = 0
    var batchCount = 0
    var encodedByteCount = 0

    func flushBatch() {
      guard batchRowCount > 0 else { return }
      batchData.append(0x5D)
      let data = batchData
      let batchIndex = batchCount
      let firstRowNumber = totalRowCount - batchRowCount + 1
      let lastRowNumber = totalRowCount
      decodeSlots.wait()
      decodeGroup.enter()
      instantPersistenceDecodeQueue.async {
        defer {
          decodeSlots.signal()
          decodeGroup.leave()
        }
        do {
          decodeResults.store(
            .success(try JSONDecoder().decode([Value].self, from: data)),
            at: batchIndex
          )
        } catch {
          decodeResults.store(
            .failure(
              InstantError(
                code: .persistenceFailed,
                operation: "decode persisted JSON rows",
                message:
                  "SQLite JSON rows \(firstRowNumber)-\(lastRowNumber) could not be decoded: \(error)",
                recovery:
                  "Inspect the local SQLite cache at \(persistencePath), then retry the command."
              )
            ),
            at: batchIndex
          )
        }
      }
      batchCount += 1
      batchData = Data()
      batchData.reserveCapacity(maxEncodedBytesPerBatch + 1)
      batchData.append(0x5B)
      batchRowCount = 0
    }

    defer { decodeGroup.wait() }
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        flushBatch()
        decodeGroup.wait()
        return (try decodeResults.joined(batchCount: batchCount), batchCount, encodedByteCount)
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read SQL", message: lastErrorMessage())
      }
      guard let bytes = sqlite3_column_text(statement, 0) else {
        throw persistenceError(operation: "decode row", message: "SQLite returned a NULL JSON row.")
      }
      let byteCount = Int(sqlite3_column_bytes(statement, 0))
      let separatorByteCount = batchRowCount == 0 ? 0 : 1
      if batchRowCount > 0,
        batchRowCount >= maxRowsPerBatch
          || batchData.count + separatorByteCount + byteCount + 1 > maxEncodedBytesPerBatch
      {
        flushBatch()
      }
      if batchRowCount > 0 {
        batchData.append(0x2C)
      }
      batchData.append(bytes, count: byteCount)
      batchRowCount += 1
      totalRowCount += 1
      encodedByteCount += byteCount
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

  private func selectStrings(
    _ sql: String,
    _ bindings: [SQLiteBinding] = []
  ) throws -> [String] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var values: [String] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return values }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read SQL", message: lastErrorMessage())
      }
      guard let cString = sqlite3_column_text(statement, 0) else {
        throw persistenceError(
          operation: "read SQL",
          message: "SQLite returned a NULL string row."
        )
      }
      values.append(String(cString: cString))
    }
  }

  private func selectInt64(_ sql: String, _ bindings: [SQLiteBinding] = []) throws -> Int64 {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return 0 }
    guard code == SQLITE_ROW else {
      throw persistenceError(operation: "read SQL", message: lastErrorMessage())
    }
    return sqlite3_column_int64(statement, 0)
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

  private func loadLiveQueryResultRowsWithoutTransaction() throws
    -> [LiveQueryResultStorageRow]
  {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT query_key, updated_at_ms, triple_count
      FROM instant_live_query_results
      ORDER BY updated_at_ms, query_key
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }

    var rows: [LiveQueryResultStorageRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return rows
      }
      guard code == SQLITE_ROW else {
        throw persistenceError(
          operation: "read live query result rows",
          message: lastErrorMessage()
        )
      }
      guard let queryKeyCString = sqlite3_column_text(statement, 0) else {
        throw persistenceError(
          operation: "read live query result rows",
          message: "SQLite returned a NULL live query result column."
        )
      }
      rows.append(
        LiveQueryResultStorageRow(
          queryKey: String(cString: queryKeyCString),
          updatedAtMilliseconds: sqlite3_column_int64(statement, 1),
          tripleCount: Int(sqlite3_column_int64(statement, 2))
        )
      )
    }
  }

  private static func liveQueryPruningProtection(
    _ mutations: [PendingMutation]
  ) -> (entityIDs: Set<String>, preservesAllQueryResults: Bool) {
    var entityIDs: Set<String> = []
    var preservesAllQueryResults = false
    for mutation in mutations where mutation.optimisticOverlayState != .removed
    {
      for operation in mutation.transaction.operations {
        switch operation {
        case let .requireEntityMissing(entityID, _),
          let .requireEntityExists(entityID, _),
          let .deleteEntity(entityID),
          let .deleteEntityInNamespace(entityID, _),
          let .ruleParams(entityID, _, _):
          entityIDs.insert(entityID)

        case let .requireTripleExists(entityID, _, _):
          entityIDs.insert(entityID)

        case let .merge(triple), let .insert(triple), let .retract(triple):
          entityIDs.insert(triple.entityID)
          if case let .ref(targetEntityID) = triple.value {
            entityIDs.insert(targetEntityID)
          }
          if case .lookupRef = triple.value {
            preservesAllQueryResults = true
          }

        case .requireEntityMissingByLookup,
          .requireEntityExistsByLookup,
          .mergeByLookup,
          .insertByLookup,
          .retractByLookup,
          .deleteEntityByLookup,
          .ruleParamsByLookup:
          preservesAllQueryResults = true
        }
      }
    }
    return (entityIDs, preservesAllQueryResults)
  }

  private func liveQueryResultWithoutTransaction(
    key: String
  ) throws -> InstantPersistedLiveQueryResult? {
    let results: [InstantPersistedLiveQueryResult] = try selectJSON(
      "SELECT json FROM instant_live_query_results WHERE query_key = ? LIMIT 1",
      [.text(key)]
    )
    return results.first
  }

  private func liveQueryTripleHasOwnerWithoutTransaction(
    _ identity: InstantLiveTripleIdentity,
    excludingQueryKeys: Set<String>
  ) throws -> Bool {
    var sql =
      """
      SELECT query_key
      FROM instant_live_query_triples
      WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
      """
    var bindings: [SQLiteBinding] = [
      .text(identity.entityID),
      .text(identity.attributeID),
      .text(try encode(identity.value)),
    ]
    if !excludingQueryKeys.isEmpty {
      sql += " AND query_key NOT IN ("
        + Array(repeating: "?", count: excludingQueryKeys.count).joined(separator: ", ")
        + ")"
      bindings.append(contentsOf: excludingQueryKeys.sorted().map(SQLiteBinding.text))
    }
    sql += " LIMIT 1"
    return try selectScalar(sql, bindings) != nil
  }

  private func liveQueryKeysOwningEntityIDsWithoutTransaction(
    _ entityIDs: Set<String>
  ) throws -> Set<String> {
    let entityIDs = entityIDs.sorted()
    var queryKeys: Set<String> = []
    for startIndex in stride(from: 0, to: entityIDs.count, by: 300) {
      let endIndex = Swift.min(startIndex + 300, entityIDs.count)
      let chunk = entityIDs[startIndex..<endIndex]
      let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
      queryKeys.formUnion(
        try selectStrings(
          """
          SELECT DISTINCT query_key
          FROM instant_live_query_triples
          WHERE entity_id IN (\(placeholders))
          """,
          chunk.map(SQLiteBinding.text)
        )
      )
    }
    return queryKeys
  }

  private static func indexLiveTriples(
    _ triples: [InstantTriple]
  ) -> [InstantLiveTripleIdentity: InstantTriple] {
    Dictionary(
      triples.map { (InstantLiveTripleIdentity($0), $0) },
      uniquingKeysWith: { _, latest in latest }
    )
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
      try insertTripleWithoutTransaction(triple)
    }
  }

  private func insertTripleWithoutTransaction(_ triple: InstantTriple) throws {
    try execute(
      """
      INSERT OR REPLACE INTO instant_triples
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

  private func saveTripleDiffWithoutTransaction(
    from previousTriples: [InstantTriple],
    to triples: [InstantTriple]
  ) throws {
    let previous = Dictionary(
      uniqueKeysWithValues: previousTriples.map { (StoredTripleKey($0), $0) }
    )
    let current = Dictionary(uniqueKeysWithValues: triples.map { (StoredTripleKey($0), $0) })
    for key in previous.keys where current[key] == nil {
      try execute(
        """
        DELETE FROM instant_triples
        WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
        """,
        [.text(key.entityID), .text(key.attributeID), .text(try encode(key.value))]
      )
    }
    for triple in triples where previous[StoredTripleKey(triple)] != triple {
      try insertTripleWithoutTransaction(triple)
    }
  }

  private func replaceCachedTriples(
    in triples: inout [InstantTriple],
    with changedEntityTriples: [String: [InstantTriple]]
  ) {
    for entityID in changedEntityTriples.keys.sorted() {
      let lowerBound = tripleIndex(in: triples, entityID: entityID, includingEqual: true)
      let upperBound = tripleIndex(in: triples, entityID: entityID, includingEqual: false)
      let replacement = changedEntityTriples[entityID, default: []].sorted {
        if $0.attributeID != $1.attributeID {
          return $0.attributeID < $1.attributeID
        }
        return $0.value.comparableKey < $1.value.comparableKey
      }
      triples.replaceSubrange(lowerBound..<upperBound, with: replacement)
    }
  }

  private func cachedTriples(
    in triples: [InstantTriple],
    entityID: String
  ) -> [InstantTriple] {
    let lowerBound = tripleIndex(in: triples, entityID: entityID, includingEqual: true)
    let upperBound = tripleIndex(in: triples, entityID: entityID, includingEqual: false)
    return Array(triples[lowerBound..<upperBound])
  }

  private func tripleIndex(
    in triples: [InstantTriple],
    entityID: String,
    includingEqual: Bool
  ) -> Int {
    var lowerBound = triples.startIndex
    var upperBound = triples.endIndex
    while lowerBound < upperBound {
      let distance = triples.distance(from: lowerBound, to: upperBound)
      let index = triples.index(lowerBound, offsetBy: distance / 2)
      let belongsBeforeBoundary = includingEqual
        ? triples[index].entityID < entityID
        : triples[index].entityID <= entityID
      if belongsBeforeBoundary {
        lowerBound = triples.index(after: index)
      } else {
        upperBound = index
      }
    }
    return lowerBound
  }

  private func saveStoreSnapshotDiffWithoutTransaction(
    from previousSnapshot: InstantStoreSnapshot,
    to snapshot: InstantStoreSnapshot
  ) throws {
    let previousAttributes = Dictionary(
      uniqueKeysWithValues: previousSnapshot.attributes.map { ($0.id, $0) }
    )
    let attributes = Dictionary(uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) })

    for id in previousAttributes.keys where attributes[id] == nil {
      try execute("DELETE FROM instant_attributes WHERE id = ?", [.text(id)])
    }
    for attribute in snapshot.attributes where previousAttributes[attribute.id] != attribute {
      try execute(
        "INSERT OR REPLACE INTO instant_attributes (id, json) VALUES (?, ?)",
        [.text(attribute.id), .text(try encode(attribute))]
      )
    }

    let previousTriples = Dictionary(
      uniqueKeysWithValues: previousSnapshot.triples.map { (StoredTripleKey($0), $0) }
    )
    let triples = Dictionary(
      uniqueKeysWithValues: snapshot.triples.map { (StoredTripleKey($0), $0) }
    )

    for (key, _) in previousTriples where triples[key] == nil {
      try execute(
        """
        DELETE FROM instant_triples
        WHERE entity_id = ? AND attribute_id = ? AND value_json = ?
        """,
        [.text(key.entityID), .text(key.attributeID), .text(try encode(key.value))]
      )
    }
    for triple in snapshot.triples where previousTriples[StoredTripleKey(triple)] != triple {
      try execute(
        """
        INSERT OR REPLACE INTO instant_triples
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

  private func saveOutboxDiffWithoutTransaction(
    from previousMutations: [PendingMutation],
    to mutations: [PendingMutation]
  ) throws {
    let previous = Dictionary(uniqueKeysWithValues: previousMutations.map { ($0.id, $0) })
    let current = Dictionary(uniqueKeysWithValues: mutations.map { ($0.id, $0) })

    for id in previous.keys where current[id] == nil {
      try execute("DELETE FROM instant_outbox WHERE mutation_id = ?", [.text(id)])
    }
    for mutation in mutations where previous[mutation.id] != mutation {
      try execute(
        """
        INSERT OR REPLACE INTO instant_outbox (mutation_id, status, created_at_ms, json)
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

  private func saveLiveQueryResultWithoutTransaction(
    _ result: InstantPersistedLiveQueryResult
  ) throws {
    try execute(
      """
      INSERT INTO instant_live_query_results
        (query_key, triple_count, updated_at_ms, json)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(query_key) DO UPDATE SET
        triple_count = excluded.triple_count,
        updated_at_ms = excluded.updated_at_ms,
        json = excluded.json
      """,
      [
        .text(result.key),
        .int(Int64(result.triples.count)),
        .int(result.updatedAt.milliseconds),
        .text(try encode(result)),
      ]
    )
    try execute(
      "DELETE FROM instant_live_query_triples WHERE query_key = ?",
      [.text(result.key)]
    )
    for triple in result.triples {
      try execute(
        """
        INSERT OR REPLACE INTO instant_live_query_triples
          (query_key, entity_id, attribute_id, value_json)
        VALUES (?, ?, ?, ?)
        """,
        [
          .text(result.key),
          .text(triple.entityID),
          .text(triple.attributeID),
          .text(try encode(triple.value)),
        ]
      )
    }
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

  private func deleteMetadataValueWithoutTransaction(key: String) throws {
    try execute(
      "DELETE FROM instant_sync_metadata WHERE key = ?",
      [.text(key)]
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

  private func nextStreamChunkIndexWithoutTransaction(appID: String, streamID: String) throws
    -> Int64
  {
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

  private func streamContentSizeWithoutTransaction(appID: String, streamID: String) throws -> Int64
  {
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

  private func localCacheFileSize() -> Int64 {
    [fileURL.path, fileURL.path + "-wal", fileURL.path + "-shm"].reduce(0) { size, path in
      let attributes = try? FileManager.default.attributesOfItem(atPath: path)
      let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
      return size + fileSize
    }
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

private struct QueryCacheStorageRow: Sendable {
  var cacheKey: String
  var json: String
  var updatedAtMilliseconds: Int64

  var byteCount: Int {
    json.utf8.count
  }
}

extension InstantError {
  fileprivate var isSQLiteBusy: Bool {
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
