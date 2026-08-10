import Foundation
import IssueReporting
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

struct InstantOutboxImmediateTailLoad: Sendable {
  var matchesRevisions: Bool
  var mutation: PendingMutation?
}

struct InstantOutboxAliasReplayLoad: Sendable {
  struct Alias: Sendable {
    var currentMutationID: String
    var isPending: Bool
  }

  var matchesRevisions: Bool
  var alias: Alias?
}

struct InstantMutationLifecycleResolution: Sendable {
  var observationID: String
  var event: InstantMutationLifecycleEvent
}

private struct InstantOutboxBodyRow: Sendable {
  var mutationID: String
  var createdAtMilliseconds: Int64
  var json: String
}

private enum InstantOutboxInvalidImmediateTail: Sendable {
  case bounded(row: InstantOutboxBodyRow, reason: String)
  case oversized(
    mutationID: String,
    createdAtMilliseconds: Int64,
    metadataByteCount: Int64,
    actualByteCount: Int64
  )

  var mutationID: String {
    switch self {
    case let .bounded(row, _): row.mutationID
    case let .oversized(mutationID, _, _, _): mutationID
    }
  }
}

private struct InstantOutboxDeliveryCandidateRow: Sendable {
  var mutationID: String
  var createdAtMilliseconds: Int64
  var metadataVersion: Int
  var transportStepCount: Int?
  var encodedBodyByteCount: Int
}

private struct InstantFailedOutboxLifecycleCandidateRow: Sendable {
  var mutationID: String
  var createdAtMilliseconds: Int64
  var lifecycleByteCount: Int?
  var bodyByteCount: Int
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
  private var decodedOutboxBodyByteCount = 0
  private var materializedOutboxBodyCount = 0
  private var materializedOutboxBodyByteCount = 0
  private var decodedOutboxLifecycleCount = 0
  private var decodedOutboxLifecycleByteCount = 0
  private var maximumAutomaticOutboxWindowBodyCount = 0
  private var maximumAutomaticOutboxWindowBodyByteCount = 0
  private var onInvalidImmediateSupersessionTailReadForTesting:
    (@Sendable (_ mutationID: String) async -> Void)?
  /// A regression sentinel: row-addressed local enqueue must never reconstruct
  /// the durable queue. Public/full-state APIs increment this when they do.
  private var localMutationQueueWideReadCount = 0

  package func resetDecodedOutboxBodyCount() {
    decodedOutboxBodyCount = 0
    decodedOutboxBodyByteCount = 0
    materializedOutboxBodyCount = 0
    materializedOutboxBodyByteCount = 0
    decodedOutboxLifecycleCount = 0
    decodedOutboxLifecycleByteCount = 0
    maximumAutomaticOutboxWindowBodyCount = 0
    maximumAutomaticOutboxWindowBodyByteCount = 0
  }

  package func currentDecodedOutboxBodyCount() -> Int {
    decodedOutboxBodyCount
  }

  package func currentDecodedOutboxBodyByteCount() -> Int {
    decodedOutboxBodyByteCount
  }

  package func currentMaterializedOutboxBodyCount() -> Int {
    materializedOutboxBodyCount
  }

  package func currentMaterializedOutboxBodyByteCount() -> Int {
    materializedOutboxBodyByteCount
  }

  package func currentDecodedOutboxLifecycleCount() -> Int {
    decodedOutboxLifecycleCount
  }

  package func currentDecodedOutboxLifecycleByteCount() -> Int {
    decodedOutboxLifecycleByteCount
  }

  package func maximumAutomaticOutboxWindowBodyCountForTesting() -> Int {
    maximumAutomaticOutboxWindowBodyCount
  }

  package func maximumAutomaticOutboxWindowBodyByteCountForTesting() -> Int {
    maximumAutomaticOutboxWindowBodyByteCount
  }

  package func setInvalidImmediateSupersessionTailReadHookForTesting(
    _ hook: (@Sendable (_ mutationID: String) async -> Void)?
  ) {
    onInvalidImmediateSupersessionTailReadForTesting = hook
  }

  package func outboxDeliveryStartedForTesting(id: String) throws -> Bool {
    try selectInt64(
      "SELECT delivery_started FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      [.text(id)]
    ) != 0
  }

  package func quarantinedOutboxBodyForTesting(id: String) throws -> String? {
    try selectScalar(
      "SELECT quarantine_json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
      [.text(id)]
    )
  }

  package func quarantinedOutboxBodyByteCountForTesting(id: String) throws -> Int {
    Int(try selectInt64(
      """
      SELECT COALESCE(length(CAST(quarantine_json AS BLOB)), 0)
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [.text(id)]
    ))
  }

  package func localMutationQueueWideReadCountForTesting() -> Int {
    localMutationQueueWideReadCount
  }

  package func outboxLifecycleCountsForTesting() throws
    -> (lifecycles: Int, aliases: Int)
  {
    (
      lifecycles: Int(try selectInt64("SELECT COUNT(*) FROM instant_outbox_lifecycles")),
      aliases: Int(try selectInt64("SELECT COUNT(*) FROM instant_outbox_lifecycle_aliases"))
    )
  }

  package func maximumOutboxLifecycleAliasMetadataByteCountForTesting() throws -> Int {
    Int(try selectInt64(
      """
      SELECT COALESCE(MAX(
        length(CAST(mutation_id AS BLOB)) + length(CAST(lifecycle_id AS BLOB))
      ), 0)
      FROM instant_outbox_lifecycle_aliases
      """
    ))
  }

  package func removeMutationLifecycleMetadataForTesting(id: String) throws {
    try transaction {
      let lifecycleID = try lifecycleIDWithoutTransaction(for: id) ?? id
      try execute(
        "DELETE FROM instant_outbox_lifecycle_aliases WHERE lifecycle_id = ?",
        [.text(lifecycleID)]
      )
      try execute(
        "DELETE FROM instant_outbox_lifecycles WHERE lifecycle_id = ?",
        [.text(lifecycleID)]
      )
    }
  }

  func outboxDeliveryClaimForTesting(id: String) throws
    -> InstantOutboxDeliveryClaim?
  {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT delivery_claim_state, delivery_claim_token, delivery_claimant_id,
             delivery_claim_deadline_ms, delivery_started
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(id)], to: statement)
    guard sqlite3_step(statement) == SQLITE_ROW,
      let stateBytes = sqlite3_column_text(statement, 0),
      let state = InstantOutboxDeliveryClaimState(rawValue: String(cString: stateBytes))
    else { return nil }
    return InstantOutboxDeliveryClaim(
      state: state,
      claimToken: sqlite3_column_text(statement, 1).map(String.init(cString:)),
      claimantID: sqlite3_column_text(statement, 2).map(String.init(cString:)),
      deadlineMilliseconds: sqlite3_column_type(statement, 3) == SQLITE_NULL
        ? nil
        : sqlite3_column_int64(statement, 3),
      deliveryStarted: sqlite3_column_int64(statement, 4) != 0
    )
  }

  package func claimOutboxMutationWithoutHydrationForTesting(
    id: String,
    claimantID: String,
    claimToken: String,
    deadlineMilliseconds: Int64
  ) throws -> Bool {
    try transaction {
      try claimOutboxMutationWithoutTransaction(
        id: id,
        claimantID: claimantID,
        claimToken: claimToken,
        deadlineMilliseconds: deadlineMilliseconds
      )
      return sqlite3_changes(connection.raw) == 1
    }
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

  private func adoptCachedState(_ state: InstantPersistenceState) {
    var thin = state
    // Durable outbox rows are cursor-addressed in SQLite. Keeping even compact
    // lifecycle shells here makes cold-start memory proportional to queue depth.
    thin.snapshot.outbox = []
    if !Self.retainFullTriplesInMemoryForTesting {
      if !thin.snapshot.store.triples.isEmpty {
        thin.snapshot.store = InstantStoreSnapshot(
          attributes: thin.snapshot.store.attributes,
          triples: []
        )
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
    try withSQLiteBusyRetry {
      try migrate(name: "0012_bounded_outbox_delivery") {
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_state TEXT")
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_metadata_version INTEGER NOT NULL DEFAULT 0"
        )
        try execute("ALTER TABLE instant_outbox ADD COLUMN transport_step_count INTEGER")
        try execute("ALTER TABLE instant_outbox ADD COLUMN lifecycle_json TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN quarantine_json TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN quarantine_lifecycle_json TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN encoded_body_bytes INTEGER")
        try execute("ALTER TABLE instant_outbox ADD COLUMN failure_message TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN confirmation_proven INTEGER")
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN optimistic_overlay_active INTEGER NOT NULL DEFAULT 1"
        )
        // Existing rows predate durable offer tracking and must be treated as
        // already offered. Only rows inserted by this version start false.
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_started INTEGER NOT NULL DEFAULT 1"
        )
        try execute(
          "ALTER TABLE instant_outbox ADD COLUMN delivery_claim_state TEXT NOT NULL DEFAULT 'ready'"
        )
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_claim_token TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_claimant_id TEXT")
        try execute("ALTER TABLE instant_outbox ADD COLUMN delivery_claim_deadline_ms INTEGER")
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox_write_keys (
            mutation_id TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            attribute_id TEXT NOT NULL,
            PRIMARY KEY (mutation_id, entity_id, attribute_id),
            FOREIGN KEY (mutation_id) REFERENCES instant_outbox (mutation_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_delivery_window_idx
          ON instant_outbox
            (delivery_claim_state, delivery_state, created_at_ms, mutation_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_delivery_deadline_idx
          ON instant_outbox
            (delivery_claim_state, delivery_claim_deadline_ms, created_at_ms, mutation_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_delivery_metadata_idx
          ON instant_outbox
            (status, delivery_metadata_version, created_at_ms, mutation_id)
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_write_keys_lookup_idx
          ON instant_outbox_write_keys (entity_id, attribute_id, mutation_id)
          """
        )
      }
    }
    try withSQLiteBusyRetry {
      try migrate(name: "0013_outbox_supersession_lifecycle") {
        // A lifecycle id is stable while the physical durable tail row is
        // replaced repeatedly. Aliases are append-only and let every returned
        // transaction id observe the one survivor after restart and pruning.
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox_lifecycles (
            lifecycle_id TEXT PRIMARY KEY NOT NULL,
            current_mutation_id TEXT NOT NULL,
            terminal_json TEXT
          )
          """
        )
        try execute(
          """
          CREATE TABLE IF NOT EXISTS instant_outbox_lifecycle_aliases (
            mutation_id TEXT PRIMARY KEY NOT NULL,
            lifecycle_id TEXT NOT NULL,
            FOREIGN KEY (lifecycle_id) REFERENCES instant_outbox_lifecycles (lifecycle_id)
              ON DELETE CASCADE
          )
          """
        )
        try execute(
          """
          CREATE INDEX IF NOT EXISTS instant_outbox_lifecycle_current_idx
          ON instant_outbox_lifecycles (current_mutation_id)
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
      let store: InstantStoreSnapshot
      if loaded.source == .sqlite {
        store = loaded.state.snapshot.store
      } else {
        guard let reloadedStore = try loadStoreSnapshot(
          expectedStoreRevision: loaded.state.storeRevision,
          expectedOutboxRevision: loaded.state.outboxRevision
        ) else { continue }
        store = reloadedStore
      }
      guard let outbox = try loadOutboxMutations(
        statuses: [.pending, .confirmed, .failed],
        expectedStoreRevision: loaded.state.storeRevision,
        expectedOutboxRevision: loaded.state.outboxRevision
      ) else { continue }
      var state = loaded.state
      state.snapshot.store = store
      state.snapshot.outbox = outbox
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

  private func loadStoreSnapshot(
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> InstantStoreSnapshot? {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return nil }
      return try loadStoreSnapshotWithoutTransaction(
        tracesStartupCollections: false
      )
    }
  }

  func loadStateWithDurableOutbox() throws -> InstantPersistenceState {
    for _ in 0..<5 {
      let loaded = try loadStateWithSource()
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

  func countOutboxMutations() throws -> Int {
    Int(try selectInt64("SELECT COUNT(*) FROM instant_outbox"))
  }

  func mutationDeliveryBarrierSummary() throws
    -> InstantMutationDeliveryBarrierSummary
  {
    try readTransaction {
      let outstandingPredicate =
        """
        (delivery_state = ? OR
          (delivery_metadata_version < ? AND status IN (?, ?)))
        """
      let outstandingBindings: [SQLiteBinding] = [
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantMutationStatus.confirmed.rawValue),
      ]
      let outstandingMutationCount = Int(try selectInt64(
        "SELECT COUNT(*) FROM instant_outbox WHERE \(outstandingPredicate)",
        outstandingBindings
      ))
      let firstOutstandingMutationID = try selectScalar(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE \(outstandingPredicate)
        ORDER BY created_at_ms, mutation_id
        LIMIT 1
        """,
        outstandingBindings
      )
      let firstOutstandingStatus = try selectScalar(
        """
        SELECT status FROM instant_outbox
        WHERE \(outstandingPredicate)
        ORDER BY created_at_ms, mutation_id
        LIMIT 1
        """,
        outstandingBindings
      )
      let sampleOutstandingMutationIDs = try selectStrings(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE \(outstandingPredicate)
        ORDER BY created_at_ms, mutation_id
        LIMIT 8
        """,
        outstandingBindings
      )
      return InstantMutationDeliveryBarrierSummary(
        outstandingMutationCount: outstandingMutationCount,
        firstOutstandingMutationID: firstOutstandingMutationID,
        firstOutstandingIsLocalOnlyConfirmation:
          firstOutstandingStatus == InstantMutationStatus.confirmed.rawValue,
        sampleOutstandingMutationIDs: sampleOutstandingMutationIDs,
        firstFailedMutation: try firstFailedMutationShellWithoutTransaction()
      )
    }
  }

  func loadFailedMutationLifecycles(
    limit: Int,
    maximumEncodedByteCount: Int = InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
  ) throws -> [PendingMutation] {
    precondition(limit >= 0)
    precondition(maximumEncodedByteCount >= 0)
    guard limit > 0 else { return [] }
    return try transaction {
      let candidates = try loadFailedOutboxLifecycleCandidatesWithoutTransaction(limit: limit)
      var mutations: [PendingMutation] = []
      var admittedByteCount = 0
      mutations.reserveCapacity(candidates.count)
      for candidate in candidates {
        let preferredByteCount = candidate.lifecycleByteCount ?? candidate.bodyByteCount
        if preferredByteCount > maximumEncodedByteCount {
          let quarantined = try quarantineOversizedOutboxMutationWithoutTransaction(
            id: candidate.mutationID,
            createdAtMilliseconds: candidate.createdAtMilliseconds,
            encodedBodyByteCount: max(candidate.bodyByteCount, preferredByteCount),
            maximumEncodedBodyByteCount: maximumEncodedByteCount
          )
          mutations.append(quarantined.compactedForMemory)
          continue
        }
        guard preferredByteCount <= maximumEncodedByteCount - admittedByteCount else { break }

        if let lifecycleByteCount = candidate.lifecycleByteCount,
          let lifecycleJSON = try selectScalar(
            "SELECT lifecycle_json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
            [.text(candidate.mutationID)]
          )
        {
          admittedByteCount += lifecycleByteCount
          decodedOutboxLifecycleCount += 1
          decodedOutboxLifecycleByteCount += lifecycleByteCount
          do {
            let mutation: PendingMutation = try decodeOutboxBody(lifecycleJSON)
            guard mutation.id == candidate.mutationID else {
              throw persistenceError(
                operation: "decode failed mutation lifecycle",
                message: "The lifecycle mutation id did not match its SQLite row id."
              )
            }
            mutations.append(mutation.compactedForMemory)
            continue
          } catch {
            reportIssue(
              "Instant found invalid lifecycle metadata for failed mutation '\(candidate.mutationID)': \(error)"
            )
          }
        }

        if candidate.bodyByteCount > maximumEncodedByteCount {
          let quarantined = try quarantineOversizedOutboxMutationWithoutTransaction(
            id: candidate.mutationID,
            createdAtMilliseconds: candidate.createdAtMilliseconds,
            encodedBodyByteCount: candidate.bodyByteCount,
            maximumEncodedBodyByteCount: maximumEncodedByteCount
          )
          mutations.append(quarantined.compactedForMemory)
          continue
        }
        guard candidate.bodyByteCount <= maximumEncodedByteCount - admittedByteCount else { break }
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: candidate.mutationID) else {
          continue
        }
        admittedByteCount += candidate.bodyByteCount
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += candidate.bodyByteCount
        do {
          var mutation: PendingMutation = try decodeOutboxBody(row.json)
          guard mutation.id == candidate.mutationID else {
            throw persistenceError(
              operation: "repair failed mutation lifecycle",
              message: "The durable mutation id did not match its SQLite row id."
            )
          }
          mutation.status = .failed
          try saveOutboxMutationWithoutTransaction(mutation)
          mutations.append(mutation.compactedForMemory)
        } catch {
          let quarantined = try quarantineInvalidOutboxMutationWithoutTransaction(
            row,
            reason: "Neither the failed lifecycle nor durable body could be decoded: \(error)"
          )
          mutations.append(quarantined.compactedForMemory)
        }
      }
      return mutations
    }
  }

  func latestOutboxCreationTimestamp(expectedOutboxRevision: Int64) throws
    -> (matchesRevision: Bool, timestamp: InstantTimestamp?)
  {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return (false, nil) }
      let timestamp = try selectScalar(
        "SELECT CAST(MAX(created_at_ms) AS TEXT) FROM instant_outbox"
      ).flatMap(Int64.init).map(InstantTimestamp.init(milliseconds:))
      return (true, timestamp)
    }
  }

  private func immediateOutboxTailIDWithoutTransaction() throws -> String? {
    try selectScalar(
      """
      SELECT mutation_id
      FROM instant_outbox
      ORDER BY created_at_ms DESC, mutation_id DESC
      LIMIT 1
      """
    )
  }

  private func isImmediateSupersessionTailEligibleWithoutTransaction(
    id mutationID: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1 FROM instant_outbox
        WHERE mutation_id = ? AND status = ?
          AND optimistic_overlay_active = 1
          AND delivery_state = ?
          AND delivery_metadata_version = ?
          AND encoded_body_bytes IS NOT NULL
          AND delivery_claim_state = ?
          AND delivery_started = 0
      )
      """,
      [
        .text(mutationID),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      ]
    ) == 1
  }

  /// Loads at most the one exact durable queue tail when it remains eligible
  /// for immediate supersession. Any other tail is an ordering barrier and is
  /// returned as `nil` without decoding its body.
  func loadImmediateSupersessionTail(
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) async throws -> InstantOutboxImmediateTailLoad {
    var invalidTail: InstantOutboxInvalidImmediateTail?
    let load = try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else {
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }

      var statement: OpaquePointer?
      try prepare(
        """
        SELECT mutation_id, status, optimistic_overlay_active,
               delivery_claim_state, delivery_started, delivery_state,
               delivery_metadata_version, encoded_body_bytes,
               created_at_ms, length(CAST(json AS BLOB))
        FROM instant_outbox
        ORDER BY created_at_ms DESC, mutation_id DESC
        LIMIT 1
        """,
        statement: &statement
      )
      defer { sqlite3_finalize(statement) }
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: nil)
      }
      guard code == SQLITE_ROW,
        let mutationIDBytes = sqlite3_column_text(statement, 0),
        let statusBytes = sqlite3_column_text(statement, 1),
        let claimStateBytes = sqlite3_column_text(statement, 3)
      else {
        throw persistenceError(
          operation: "read immediate supersession tail",
          message: lastErrorMessage()
        )
      }
      let mutationID = String(cString: mutationIDBytes)
      let status = String(cString: statusBytes)
      let claimState = String(cString: claimStateBytes)
      let deliveryState = sqlite3_column_text(statement, 5).map(String.init(cString:))
      guard status == InstantMutationStatus.pending.rawValue,
        sqlite3_column_int64(statement, 2) != 0,
        claimState == InstantOutboxDeliveryClaimState.ready.rawValue,
        sqlite3_column_int64(statement, 4) == 0,
        deliveryState == InstantOutboxDeliveryState.needsDelivery.rawValue,
        sqlite3_column_int64(statement, 6)
          == Int64(InstantOutboxDeliveryMetadata.currentVersion),
        sqlite3_column_type(statement, 7) != SQLITE_NULL,
        sqlite3_column_type(statement, 9) != SQLITE_NULL
      else {
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: nil)
      }

      let metadataByteCount = sqlite3_column_int64(statement, 7)
      let createdAtMilliseconds = sqlite3_column_int64(statement, 8)
      let actualByteCount = sqlite3_column_int64(statement, 9)
      let maximumByteCount = Int64(
        InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
      )
      if actualByteCount > maximumByteCount,
        metadataByteCount >= 0,
        metadataByteCount == actualByteCount
      {
        // A consistently normalized oversized row is a durable ordering
        // barrier. Delivery owns its existing SQLite-only quarantine policy;
        // enqueue neither materializes nor mutates it.
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: nil)
      }
      if actualByteCount < 0 || actualByteCount > maximumByteCount {
        invalidTail = .oversized(
          mutationID: mutationID,
          createdAtMilliseconds: createdAtMilliseconds,
          metadataByteCount: metadataByteCount,
          actualByteCount: actualByteCount
        )
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }

      guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else {
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }
      guard metadataByteCount >= 0,
        metadataByteCount == actualByteCount,
        row.json.utf8.count == Int(actualByteCount)
      else {
        invalidTail = .bounded(
          row: row,
          reason:
            "The normalized encoded_body_bytes value (\(metadataByteCount)) did not match the bounded SQLite body length (\(actualByteCount))."
        )
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }

      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
      do {
        let mutation: PendingMutation = try decodeOutboxBody(row.json)
        guard mutation.id == mutationID,
          mutation.status == .pending,
          mutation.optimisticOverlayState == .applied,
          mutation.rollbackTransaction != nil
        else {
          throw persistenceError(
            operation: "validate immediate supersession tail",
            message:
              "The normalized durable body disagreed with its pending, active-overlay SQLite row."
          )
        }
        return InstantOutboxImmediateTailLoad(matchesRevisions: true, mutation: mutation)
      } catch {
        invalidTail = .bounded(
          row: row,
          reason: "The immediate supersession tail could not be decoded and validated: \(error)"
        )
        return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
      }
    }
    guard let invalidTail else { return load }

    await onInvalidImmediateSupersessionTailReadForTesting?(invalidTail.mutationID)

    let didQuarantine = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision,
        try immediateOutboxTailIDWithoutTransaction() == invalidTail.mutationID,
        try isImmediateSupersessionTailEligibleWithoutTransaction(
          id: invalidTail.mutationID
        )
      else { return false }

      switch invalidTail {
      case let .bounded(row, reason):
        guard
          try selectScalar(
            "SELECT json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
            [.text(row.mutationID)]
          ) == row.json
        else { return false }
        _ = try quarantineInvalidOutboxMutationWithoutTransaction(row, reason: reason)

      case let .oversized(
        mutationID,
        createdAtMilliseconds,
        metadataByteCount,
        actualByteCount
      ):
        guard actualByteCount >= 0,
          try selectInt64(
            """
            SELECT EXISTS(
              SELECT 1 FROM instant_outbox
              WHERE mutation_id = ? AND created_at_ms = ?
                AND encoded_body_bytes = ?
                AND length(CAST(json AS BLOB)) = ?
            )
            """,
            [
              .text(mutationID),
              .int(createdAtMilliseconds),
              .int(metadataByteCount),
              .int(actualByteCount),
            ]
          ) == 1
        else { return false }
        _ = try quarantineOversizedOutboxMutationWithoutTransaction(
          id: mutationID,
          createdAtMilliseconds: createdAtMilliseconds,
          encodedBodyByteCount: Int(actualByteCount),
          maximumEncodedBodyByteCount:
            InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
        )
      }
      _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      return true
    }
    if didQuarantine {
      cachedState = nil
    }
    // A quarantine changes the outbox revision; a lost race also invalidates
    // this caller's revision pair. In both cases the runtime must reload before
    // preparing the new local mutation.
    return InstantOutboxImmediateTailLoad(matchesRevisions: false, mutation: nil)
  }

  /// Resolves a transaction id that no longer has a physical outbox row.
  /// Supersession aliases remain idempotence keys, so callers must consult
  /// this row-addressed lookup before admitting a same-id mutation as new.
  func loadOutboxAliasReplay(
    id mutationID: String,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxAliasReplayLoad {
    try readTransaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey)
          == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else {
        return InstantOutboxAliasReplayLoad(matchesRevisions: false, alias: nil)
      }

      var statement: OpaquePointer?
      try prepare(
        """
        SELECT lifecycles.current_mutation_id,
               lifecycles.terminal_json IS NOT NULL,
               current.status
        FROM instant_outbox_lifecycle_aliases AS aliases
        JOIN instant_outbox_lifecycles AS lifecycles
          ON lifecycles.lifecycle_id = aliases.lifecycle_id
        LEFT JOIN instant_outbox AS current
          ON current.mutation_id = lifecycles.current_mutation_id
        WHERE aliases.mutation_id = ?
        LIMIT 1
        """,
        statement: &statement
      )
      defer { sqlite3_finalize(statement) }
      try bind([.text(mutationID)], to: statement)
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE {
        return InstantOutboxAliasReplayLoad(matchesRevisions: true, alias: nil)
      }
      guard code == SQLITE_ROW,
        let currentMutationIDBytes = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(
          operation: "resolve superseded transaction id",
          message: lastErrorMessage()
        )
      }
      let isTerminal = sqlite3_column_int64(statement, 1) != 0
      let currentStatus = sqlite3_column_text(statement, 2).map(String.init(cString:))
      return InstantOutboxAliasReplayLoad(
        matchesRevisions: true,
        alias: InstantOutboxAliasReplayLoad.Alias(
          currentMutationID: String(cString: currentMutationIDBytes),
          isPending: !isTerminal && currentStatus == InstantMutationStatus.pending.rawValue
        )
      )
    }
  }

  /// Returns the observer key for a terminal event only while that event
  /// belongs to the current physical survivor. A delayed event for any
  /// superseded alias returns `nil` and must not wake the survivor's observers.
  func mutationLifecyclePublicationIdentity(for mutationID: String) throws -> String? {
    try readTransaction {
      guard let lifecycleID = try lifecycleIDWithoutTransaction(for: mutationID) else {
        return mutationID
      }
      let currentMutationID = try currentMutationIDWithoutTransaction(
        lifecycleID: lifecycleID
      )
      return currentMutationID == mutationID ? lifecycleID : nil
    }
  }

  func resolveMutationLifecycle(
    id mutationID: String
  ) throws -> InstantMutationLifecycleResolution {
    try readTransaction {
      let lifecycleID = try lifecycleIDWithoutTransaction(for: mutationID) ?? mutationID
      var currentMutationID = mutationID
      var terminalJSON: String?
      var statement: OpaquePointer?
      try prepare(
        """
        SELECT current_mutation_id, terminal_json
        FROM instant_outbox_lifecycles
        WHERE lifecycle_id = ?
        LIMIT 1
        """,
        statement: &statement
      )
      defer { sqlite3_finalize(statement) }
      try bind([.text(lifecycleID)], to: statement)
      if sqlite3_step(statement) == SQLITE_ROW {
        if let currentBytes = sqlite3_column_text(statement, 0) {
          currentMutationID = String(cString: currentBytes)
        }
        terminalJSON = sqlite3_column_text(statement, 1).map(String.init(cString:))
      }

      if let terminalJSON {
        decodedOutboxLifecycleCount += 1
        decodedOutboxLifecycleByteCount += terminalJSON.utf8.count
        let mutation: PendingMutation = try decodeOutboxBody(terminalJSON)
        if let event = lifecycleEvent(for: mutation) {
          return InstantMutationLifecycleResolution(
            observationID: lifecycleID,
            event: event
          )
        }
      }

      guard let row = try loadOutboxBodyRowWithoutTransaction(id: currentMutationID) else {
        return InstantMutationLifecycleResolution(
          observationID: lifecycleID,
          event: .waiting
        )
      }
      decodedOutboxBodyCount += 1
      decodedOutboxBodyByteCount += row.json.utf8.count
      let mutation: PendingMutation = try decodeOutboxBody(row.json)
      return InstantMutationLifecycleResolution(
        observationID: lifecycleID,
        event: lifecycleEvent(for: mutation) ?? .waiting
      )
    }
  }

  func currentOutboxRevision() throws -> Int64 {
    try readTransaction {
      try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
    }
  }

  /// Claims the explicit-flush selection before external transport I/O.
  /// Unlike automatic delivery, explicit flush intentionally preserves the
  /// caller's requested row-count semantics; it still shares the same durable
  /// claim/offered transition so a live runtime cannot select the rows twice.
  func claimPendingOutboxMutationsForExplicitFlush(
    limit: Int?,
    claimantID: String,
    claimToken: String,
    now: InstantTimestamp
  ) throws -> [PendingMutation] {
    precondition(limit.map { $0 >= 0 } ?? true)
    guard limit != 0 else { return [] }
    return try transaction {
      _ = try reclaimExpiredOutboxClaimsWithoutTransaction(
        nowMilliseconds: now.milliseconds
      )
      guard try !hasActiveOutboxClaimWithoutTransaction(
        excludingClaimantID: claimantID
      ) else {
        throw InstantError(
          code: .networkFailed,
          operation: "claim explicit outbox flush",
          message: "Another delivery lane already owns the ordered Instant outbox head.",
          recovery: "Wait for that five-second durable claim to finish or expire, then flush again."
        )
      }
      var sql =
        """
        SELECT candidate.mutation_id, candidate.created_at_ms, candidate.json
        FROM instant_outbox AS candidate
        WHERE candidate.status = ? AND candidate.delivery_claim_state = ?
          AND (
            candidate.delivery_state = ?
            OR (
              candidate.delivery_metadata_version < ?
              AND candidate.status IN (?, ?)
            )
          )
          AND NOT EXISTS (
            SELECT 1
            FROM instant_outbox AS barrier
            WHERE barrier.delivery_claim_state = ?
              AND (
                barrier.delivery_state = ?
                OR (
                  barrier.delivery_metadata_version < ?
                  AND barrier.status IN (?, ?)
                )
              )
              AND barrier.status != ?
              AND (
                barrier.created_at_ms < candidate.created_at_ms
                OR (
                  barrier.created_at_ms = candidate.created_at_ms
                  AND barrier.mutation_id < candidate.mutation_id
                )
              )
          )
        ORDER BY candidate.created_at_ms, candidate.mutation_id
        """
      var bindings: [SQLiteBinding] = [
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantMutationStatus.confirmed.rawValue),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .text(InstantMutationStatus.pending.rawValue),
        .text(InstantMutationStatus.confirmed.rawValue),
        .text(InstantMutationStatus.pending.rawValue),
      ]
      if let limit {
        sql += " LIMIT ?"
        bindings.append(.int(Int64(limit)))
      }
      let rows = try loadOutboxBodyRowsWithoutTransaction(sql, bindings)
      var mutations: [PendingMutation] = []
      mutations.reserveCapacity(rows.count)
      for row in rows {
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += row.json.utf8.count
        let mutation: PendingMutation = try decodeOutboxBody(row.json)
        guard mutation.id == row.mutationID else {
          throw persistenceError(
            operation: "claim explicit outbox flush",
            message: "Mutation '\(row.mutationID)' did not match its durable row id."
          )
        }
        try claimOutboxMutationWithoutTransaction(
          id: row.mutationID,
          claimantID: claimantID,
          claimToken: claimToken,
          deadlineMilliseconds: now.milliseconds
            + InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds
        )
        mutations.append(mutation)
      }
      return mutations
    }
  }

  /// Quarantines live-encoding failures by addressing only the offered rows.
  /// Their optimistic overlays remain applied and explicitly retained for a
  /// later schema-deployment retry; no queue-wide rollback/rebase is attempted.
  func failOutboxMutationsForDelivery(
    _ failuresByMutationID: [String: InstantMutationFailure],
    claimToken: String,
    expectedOutboxRevision: Int64
  ) throws -> InstantOutboxBatchFailureApplication? {
    guard !failuresByMutationID.isEmpty else {
      return InstantOutboxBatchFailureApplication(
        mutations: [],
        resultingOutboxRevision: expectedOutboxRevision,
        decodedBodyCount: 0,
        decodedBodyByteCount: 0
      )
    }
    return try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
          == expectedOutboxRevision
      else { return nil }

      var failedMutations: [PendingMutation] = []
      var bodyCount = 0
      var bodyByteCount = 0
      for mutationID in failuresByMutationID.keys.sorted() {
        guard try selectScalar(
          """
          SELECT delivery_claim_token FROM instant_outbox
          WHERE mutation_id = ? AND delivery_claim_state = ?
          LIMIT 1
          """,
          [
            .text(mutationID),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          ]
        ) == claimToken else { continue }
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else { continue }
        bodyCount += 1
        bodyByteCount += row.json.utf8.count
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += row.json.utf8.count
        do {
          var mutation: PendingMutation = try decodeOutboxBody(row.json)
          guard mutation.id == mutationID else {
            failedMutations.append(
              try quarantineInvalidOutboxMutationWithoutTransaction(
                row,
                reason: "The durable mutation id did not match its SQLite row id."
              )
            )
            continue
          }
          guard InstantOutboxDeliveryMetadata.state(for: mutation) == .needsDelivery else {
            continue
          }
          let failure = failuresByMutationID[mutationID]!
          mutation.status = .failed
          mutation.failureMessage = failure.message
          mutation.failure = failure
          // Encoding failed before server I/O. Retaining the already-applied
          // optimistic layer is the only bounded, truthful disposition; retry
          // will not duplicate it after the schema is deployed.
          try saveOutboxMutationWithoutTransaction(mutation)
          try execute(
            """
            UPDATE instant_outbox
            SET delivery_claim_state = ?, delivery_claim_token = NULL,
                delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL
            WHERE mutation_id = ? AND delivery_claim_token = ?
            """,
            [
              .text(InstantOutboxDeliveryClaimState.ready.rawValue),
              .text(mutationID),
              .text(claimToken),
            ]
          )
          failedMutations.append(mutation)
        } catch {
          failedMutations.append(
            try quarantineInvalidOutboxMutationWithoutTransaction(
              row,
              reason: "The durable mutation body could not be decoded while recording an encoding failure: \(error)"
            )
          )
        }
      }
      let resultingRevision: Int64
      if failedMutations.isEmpty {
        resultingRevision = expectedOutboxRevision
      } else {
        resultingRevision = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return InstantOutboxBatchFailureApplication(
        mutations: failedMutations.sorted(by: PendingMutation.creationOrder),
        resultingOutboxRevision: resultingRevision,
        decodedBodyCount: bodyCount,
        decodedBodyByteCount: bodyByteCount
      )
    }
  }

  /// Applies explicit-transport confirmations to only the token-owned rows.
  /// The claim remains held until the caller finishes the whole response
  /// disposition and releases unaddressed rows.
  func confirmExplicitlyFlushedOutboxMutations(
    _ results: [InstantMutationTransportResult],
    selectedMutations: [PendingMutation],
    claimToken: String
  ) throws -> [PendingMutation] {
    let confirmations = results.filter { $0.outcome == .confirmed }
    guard !confirmations.isEmpty else { return [] }
    let selectedByID = Dictionary(
      uniqueKeysWithValues: selectedMutations.map { ($0.id, $0) }
    )
    return try transaction {
      var confirmed: [PendingMutation] = []
      confirmed.reserveCapacity(confirmations.count)
      for result in confirmations {
        guard var selectedMutation = selectedByID[result.mutationID],
          selectedMutation.status == .pending
        else { continue }
        selectedMutation.status = .confirmed
        selectedMutation.failureMessage = nil
        selectedMutation.failure = nil
        selectedMutation.confirmationSource = result.acceptance == .serverAccepted
          ? .serverTransport
          : .localTransport
        let confirmationSource = selectedMutation.confirmationSource!.rawValue
        let deliveryState = result.acceptance == .serverAccepted
          ? InstantOutboxDeliveryState.serverAccepted
          : .needsDelivery
        let fallbackLifecycle = try encode(selectedMutation.compactedForMemory)
        // Mutate only lifecycle fields inside the *current* token-owned JSON.
        // A server refresh may have rebased transaction/rollback data while the
        // transport was suspended; SQL JSON mutation preserves that newer body.
        // The selected row is decoded afterward so the public flush result also
        // returns the full current transaction and rollback, not a lifecycle shell.
        try execute(
          """
          UPDATE instant_outbox
          SET status = ?, delivery_state = ?, failure_message = NULL,
              confirmation_proven = ?,
              encoded_body_bytes = length(CAST(
                json_remove(
                  json_set(json, '$.status', ?, '$.confirmationSource', ?),
                  '$.failureMessage', '$.failure'
                ) AS BLOB
              )),
              json = json_remove(
                json_set(json, '$.status', ?, '$.confirmationSource', ?),
                '$.failureMessage', '$.failure'
              ),
              lifecycle_json = json_remove(
                json_set(
                  COALESCE(lifecycle_json, ?),
                  '$.status', ?, '$.confirmationSource', ?
                ),
                '$.failureMessage', '$.failure'
              )
          WHERE mutation_id = ? AND status = ? AND delivery_claim_state = ?
            AND delivery_claim_token = ?
          """,
          [
            .text(InstantMutationStatus.confirmed.rawValue),
            .text(deliveryState.rawValue),
            .int(result.acceptance == .serverAccepted ? 1 : 0),
            .text(InstantMutationStatus.confirmed.rawValue),
            .text(confirmationSource),
            .text(InstantMutationStatus.confirmed.rawValue),
            .text(confirmationSource),
            .text(fallbackLifecycle),
            .text(InstantMutationStatus.confirmed.rawValue),
            .text(confirmationSource),
            .text(result.mutationID),
            .text(InstantMutationStatus.pending.rawValue),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
            .text(claimToken),
          ]
        )
        guard sqlite3_changes(connection.raw) == 1,
          let bodyJSON = try selectScalar(
            "SELECT json FROM instant_outbox WHERE mutation_id = ? LIMIT 1",
            [.text(result.mutationID)]
          )
        else { continue }
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += bodyJSON.utf8.count
        let mutation: PendingMutation = try decodeOutboxBody(bodyJSON)
        try saveMutationLifecycleWithoutTransaction(mutation)
        confirmed.append(mutation)
      }
      if !confirmed.isEmpty {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        cachedState = nil
      }
      return confirmed.sorted(by: PendingMutation.creationOrder)
    }
  }

  func renewOutboxClaim(
    token: String,
    claimantID: String,
    deadlineMilliseconds: Int64
  ) throws -> Bool {
    try transaction {
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_deadline_ms = ?
        WHERE delivery_claim_state = ? AND delivery_claim_token = ?
          AND delivery_claimant_id = ?
        """,
        [
          .int(deadlineMilliseconds),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(token),
          .text(claimantID),
        ]
      )
      return sqlite3_changes(connection.raw) > 0
    }
  }

  func outboxClaimMatches(id: String, token: String) throws -> Bool {
    try selectScalar(
      """
      SELECT delivery_claim_token FROM instant_outbox
      WHERE mutation_id = ? AND delivery_claim_state = ?
      LIMIT 1
      """,
      [
        .text(id),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
      ]
    ) == token
  }

  /// Atomically admits one automatic-delivery window.
  ///
  /// This `BEGIN IMMEDIATE` transition is the sole automatic admission
  /// authority. It reclaims expired durable claims, walks ready rows in strict
  /// queue order, normalizes legacy rows one body at a time, quarantines corrupt
  /// rows locally, and claims only the exact rows that fit all fixed budgets.
  /// `delivery_started` means "ever offered to the encoder/delivery path" and
  /// deliberately remains true after a claim is released or expires.
  func claimAutomaticOutboxDeliveryWindow(
    _ request: InstantAutomaticOutboxClaimRequest
  ) throws -> InstantAutomaticOutboxClaimWindow {
    precondition(request.maximumMutationCount >= 0)
    precondition(request.maximumStepCount >= 0)
    precondition(request.maximumBodyDecodeCount >= 0)
    precondition(request.maximumEncodedBodyByteCount >= 0)
    precondition(!request.claimantID.isEmpty)
    precondition(!request.claimToken.isEmpty)

    return try transaction {
      let startingRevisions = InstantPersistenceRevisions(
        store: try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey),
        outbox: try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      )
      let reclaimedMutationIDs = try reclaimExpiredOutboxClaimsWithoutTransaction(
        nowMilliseconds: request.now.milliseconds
      )
      // One claimant owns the queue-level delivery lane at a time. A claimant
      // may fill its own bounded window across pump passes, but another runtime
      // or the explicit mutation transport must wait for release/ACK/expiry so
      // two sockets cannot deliver same-key successors out of order.
      let hasForeignActiveClaim = try hasActiveOutboxClaimWithoutTransaction(
        excludingClaimantID: request.claimantID
      )
      let claimedCount = Int(try selectInt64(
        """
        SELECT COUNT(*) FROM instant_outbox
        WHERE delivery_claim_state = ?
        """,
        [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
      ))
      let claimedStepCount = Int(try selectInt64(
        """
        SELECT COALESCE(SUM(transport_step_count), 0) FROM instant_outbox
        WHERE delivery_claim_state = ?
        """,
        [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
      ))
      let claimedBodyByteCount = Int(try selectInt64(
        """
        SELECT COALESCE(SUM(encoded_body_bytes), 0) FROM instant_outbox
        WHERE delivery_claim_state = ?
        """,
        [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
      ))
      let remainingMutationCount = hasForeignActiveClaim
        ? 0
        : max(0, request.maximumMutationCount - claimedCount)
      let remainingStepCount = hasForeignActiveClaim
        ? 0
        : max(0, request.maximumStepCount - claimedStepCount)
      let remainingBodyByteCount = hasForeignActiveClaim
        ? 0
        : max(0, request.maximumEncodedBodyByteCount - claimedBodyByteCount)

      var bodyDecodeCount = 0
      var bodyByteCount = 0
      var failedMutations: [PendingMutation] = []
      var mutations: [PendingMutation] = []
      var admittedStepCount = 0
      var admittedBodyByteCount = 0
      var firstSelectedPosition: InstantOutboxDeliveryPosition?
      var didMakeNonSendingProgress = false
      var didChangeLifecycle = false

      if remainingMutationCount > 0, request.maximumBodyDecodeCount > 0 {
        let candidates = try loadAutomaticDeliveryCandidateRowsWithoutTransaction(
          limit: request.maximumBodyDecodeCount
        )
        mutations.reserveCapacity(min(remainingMutationCount, candidates.count))
        for candidate in candidates {
          guard mutations.count < remainingMutationCount else { break }
          if candidate.metadataVersion >= InstantOutboxDeliveryMetadata.currentVersion,
            let transportStepCount = candidate.transportStepCount
          {
            if transportStepCount > InstantAutomaticOutboxClaimLimits.maximumStepCount {
              failedMutations.append(
                try quarantineOverLimitStepOutboxMutationWithoutTransaction(
                  id: candidate.mutationID,
                  createdAtMilliseconds: candidate.createdAtMilliseconds,
                  transportStepCount: transportStepCount
                )
              )
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              continue
            }
            guard automaticDeliveryStepCountFits(
              transportStepCount,
              admittedStepCount: admittedStepCount,
              remainingStepCount: remainingStepCount
            ) else { break }
          }
          guard bodyDecodeCount < request.maximumBodyDecodeCount else { break }
          if candidate.encodedBodyByteCount > request.maximumEncodedBodyByteCount {
            failedMutations.append(
              try quarantineOversizedOutboxMutationWithoutTransaction(
                id: candidate.mutationID,
                createdAtMilliseconds: candidate.createdAtMilliseconds,
                encodedBodyByteCount: candidate.encodedBodyByteCount,
                maximumEncodedBodyByteCount: request.maximumEncodedBodyByteCount
              )
            )
            didChangeLifecycle = true
            didMakeNonSendingProgress = true
            continue
          }
          let fitsByteBudget =
            bodyByteCount <= remainingBodyByteCount
            && candidate.encodedBodyByteCount
              <= remainingBodyByteCount - bodyByteCount
          guard fitsByteBudget else { break }
          guard let row = try loadOutboxBodyRowWithoutTransaction(id: candidate.mutationID)
          else { continue }

          bodyDecodeCount += 1
          bodyByteCount += candidate.encodedBodyByteCount
          decodedOutboxBodyCount += 1
          decodedOutboxBodyByteCount += candidate.encodedBodyByteCount
          let candidatePosition = InstantOutboxDeliveryPosition(
            createdAtMilliseconds: row.createdAtMilliseconds,
            mutationID: row.mutationID
          )
          do {
            let mutation: PendingMutation = try decodeOutboxBody(row.json)
            guard mutation.id == row.mutationID else {
              failedMutations.append(
                try quarantineInvalidOutboxMutationWithoutTransaction(
                  row,
                  reason: "The durable mutation id did not match its SQLite row id."
                )
              )
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              continue
            }
            if candidate.metadataVersion < InstantOutboxDeliveryMetadata.currentVersion {
              try saveOutboxDeliveryMetadataWithoutTransaction(mutation)
              didMakeNonSendingProgress = true
            }
            guard InstantOutboxDeliveryMetadata.state(for: mutation) == .needsDelivery else {
              didMakeNonSendingProgress = true
              continue
            }
            let transportStepCount = InstantOutboxDeliveryMetadata.stepCount(in: mutation)
            if transportStepCount > InstantAutomaticOutboxClaimLimits.maximumStepCount {
              failedMutations.append(
                try quarantineOverLimitStepOutboxMutationWithoutTransaction(
                  id: candidate.mutationID,
                  createdAtMilliseconds: candidate.createdAtMilliseconds,
                  transportStepCount: transportStepCount
                )
              )
              didChangeLifecycle = true
              didMakeNonSendingProgress = true
              continue
            }
            guard automaticDeliveryStepCountFits(
              transportStepCount,
              admittedStepCount: admittedStepCount,
              remainingStepCount: remainingStepCount
            ) else {
              // This normalized row remains the ordered ready barrier. Because
              // it is outside the current claim, active-overlay successor proof
              // below includes its write keys.
              break
            }
            try claimOutboxMutationWithoutTransaction(
              id: mutation.id,
              claimantID: request.claimantID,
              claimToken: request.claimToken,
              deadlineMilliseconds: request.now.milliseconds
                + InstantAutomaticOutboxClaimLimits.claimTimeoutMilliseconds
            )
            mutations.append(mutation)
            admittedStepCount += transportStepCount
            admittedBodyByteCount += candidate.encodedBodyByteCount
            if firstSelectedPosition == nil {
              firstSelectedPosition = candidatePosition
            }
          } catch {
            failedMutations.append(
              try quarantineInvalidOutboxMutationWithoutTransaction(
                row,
                reason: "The durable mutation body could not be decoded: \(error)"
              )
            )
            didChangeLifecycle = true
            didMakeNonSendingProgress = true
            InstantDiagnostics.shared.record(
              error: error,
              subsystem: "instant-swift-data-core",
              category: "outbox",
              event: "outbox.mutation.body-invalid",
              message: "Skipped one malformed durable mutation body while claiming a bounded delivery window.",
              metadata: ["mutationID": row.mutationID],
              correlationID: row.mutationID
            )
          }
        }
      }

      let resultingOutboxRevision = didChangeLifecycle
        ? try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
        : startingRevisions.outbox
      let resultingRevisions = InstantPersistenceRevisions(
        store: startingRevisions.store,
        outbox: resultingOutboxRevision
      )
      let selectedWriteKeys = InstantVisibleWriteFilter.writeKeys(in: mutations)
      let visibleWriteFilter = try loadVisibleWriteFilterWithoutTransaction(
        for: selectedWriteKeys
      )
      let hasUnknownSuccessorWriteKeys = try firstSelectedPosition.map {
        try hasUnknownActiveOverlayAfterWithoutTransaction(
          $0,
          excludingClaimToken: request.claimToken
        )
      } ?? false
      var successorWriteKeys: Set<InstantVisibleWriteKey> = []
      if let firstSelectedPosition, !hasUnknownSuccessorWriteKeys {
        for key in selectedWriteKeys
        where try hasActiveOverlayWriteKeyAfterWithoutTransaction(
          key,
          position: firstSelectedPosition,
          excludingClaimToken: request.claimToken
        ) {
          successorWriteKeys.insert(key)
        }
      }
      let hasContinuationCandidate = try hasAutomaticDeliveryCandidateWithoutTransaction()
      let claimedAfterThisPass = claimedCount + mutations.count
      let claimedStepsAfterThisPass = claimedStepCount + admittedStepCount
      let claimedBodyBytesAfterThisPass = claimedBodyByteCount + admittedBodyByteCount
      let hasRemainingClaimCapacity =
        claimedAfterThisPass < request.maximumMutationCount
        && claimedStepsAfterThisPass < request.maximumStepCount
        && claimedBodyBytesAfterThisPass < request.maximumEncodedBodyByteCount
      let shouldContinueImmediately =
        didMakeNonSendingProgress && hasRemainingClaimCapacity && hasContinuationCandidate
      let nextClaimDeadlineMilliseconds = try minimumOutboxClaimDeadlineWithoutTransaction()

      maximumAutomaticOutboxWindowBodyCount = max(
        maximumAutomaticOutboxWindowBodyCount,
        bodyDecodeCount
      )
      maximumAutomaticOutboxWindowBodyByteCount = max(
        maximumAutomaticOutboxWindowBodyByteCount,
        bodyByteCount
      )
      InstantDiagnostics.shared.record(
        .trace,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.automatic-claim.completed",
        message: "Instant completed one bounded durable automatic-delivery claim.",
        metadata: [
          "decodedBodyCount": String(bodyDecodeCount),
          "decodedBodyByteCount": String(bodyByteCount),
          "claimedMutationCount": String(mutations.count),
          "claimedStepCount": String(admittedStepCount),
          "claimedEncodedBodyByteCount": String(admittedBodyByteCount),
          "alreadyClaimedMutationCount": String(claimedCount),
          "alreadyClaimedStepCount": String(claimedStepCount),
          "alreadyClaimedEncodedBodyByteCount": String(claimedBodyByteCount),
          "quarantinedMutationCount": String(failedMutations.count),
          "shouldContinueImmediately": String(shouldContinueImmediately),
          "nextClaimDeadlineMilliseconds": nextClaimDeadlineMilliseconds.map(String.init)
            ?? "none",
        ]
      )
      return InstantAutomaticOutboxClaimWindow(
        mutations: mutations.sorted(by: PendingMutation.creationOrder),
        failedMutations: failedMutations.sorted(by: PendingMutation.creationOrder),
        successorWriteKeys: successorWriteKeys,
        hasUnknownSuccessorWriteKeys: hasUnknownSuccessorWriteKeys,
        visibleWriteFilter: visibleWriteFilter,
        resultingRevisions: resultingRevisions,
        claimToken: mutations.isEmpty ? nil : request.claimToken,
        reclaimedMutationIDs: reclaimedMutationIDs,
        nextClaimDeadlineMilliseconds: nextClaimDeadlineMilliseconds,
        shouldContinueImmediately: shouldContinueImmediately,
        decodedBodyCount: bodyDecodeCount,
        decodedBodyByteCount: bodyByteCount
      )
    }
  }

  @discardableResult
  func releaseAutomaticOutboxClaim(token: String) throws -> Set<String> {
    guard !token.isEmpty else { return [] }
    return try transaction {
      let ids = Set(try selectStrings(
        """
        SELECT mutation_id FROM instant_outbox
        WHERE delivery_claim_state = ? AND delivery_claim_token = ?
        ORDER BY created_at_ms, mutation_id
        """,
        [
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(token),
        ]
      ))
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_state = ?, delivery_claim_token = NULL,
            delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL
        WHERE delivery_claim_state = ? AND delivery_claim_token = ?
        """,
        [
          .text(InstantOutboxDeliveryClaimState.ready.rawValue),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(token),
        ]
      )
      return ids
    }
  }

  /// Releases one retryable server response only while this runtime still owns
  /// the durable claim. The claimant predicate prevents a late socket event
  /// from releasing a row another runtime reclaimed after the five-second
  /// deadline.
  @discardableResult
  func releaseAutomaticOutboxClaim(
    id: String,
    claimantID: String
  ) throws -> Bool {
    guard !id.isEmpty, !claimantID.isEmpty else { return false }
    return try transaction {
      try execute(
        """
        UPDATE instant_outbox
        SET delivery_claim_state = ?, delivery_claim_token = NULL,
            delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL
        WHERE mutation_id = ? AND delivery_claim_state = ?
          AND delivery_claimant_id = ?
        """,
        [
          .text(InstantOutboxDeliveryClaimState.ready.rawValue),
          .text(id),
          .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          .text(claimantID),
        ]
      )
      return sqlite3_changes(connection.raw) == 1
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
        let encodedBody = try encode(mutation)
        try execute(
          """
          UPDATE instant_outbox
          SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
              transport_step_count = ?, encoded_body_bytes = ?, delivery_started = 1,
              lifecycle_json = ?, failure_message = NULL, confirmation_proven = 1,
              optimistic_overlay_active = ?, delivery_claim_state = ?,
              delivery_claim_token = NULL, delivery_claimant_id = NULL,
              delivery_claim_deadline_ms = NULL, json = ?
          WHERE mutation_id = ?
          """,
          [
            .text(mutation.status.rawValue),
            .text(InstantOutboxDeliveryState.serverAccepted.rawValue),
            .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
            .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
            .int(Int64(encodedBody.utf8.count)),
            .text(try encode(mutation.compactedForMemory)),
            .int(mutation.optimisticOverlayState == .removed ? 0 : 1),
            .text(InstantOutboxDeliveryClaimState.ready.rawValue),
            .text(encodedBody),
            .text(mutation.id),
          ]
        )
        try replaceOutboxWriteKeysWithoutTransaction(for: mutation)
        try saveMutationLifecycleWithoutTransaction(mutation)
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
      acceptance.mutation != nil
    {
      previousState.snapshot.outbox = []
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
    if ids == nil, limit == nil {
      localMutationQueueWideReadCount += 1
    }
    let loaded: (mutations: [PendingMutation], didQuarantine: Bool)? = try transaction {
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
      guard !statuses.isEmpty, ids?.isEmpty != true, limit != 0 else {
        return ([], false)
      }
      let statusPlaceholders = Array(repeating: "?", count: statuses.count)
        .joined(separator: ", ")
      var sql =
        "SELECT mutation_id FROM instant_outbox WHERE status IN (\(statusPlaceholders))"
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
      let mutationIDs = try selectStrings(sql, bindings)
      var mutations: [PendingMutation] = []
      mutations.reserveCapacity(mutationIDs.count)
      var didQuarantine = false
      for mutationID in mutationIDs {
        guard let row = try loadOutboxBodyRowWithoutTransaction(id: mutationID) else { continue }
        decodedOutboxBodyCount += 1
        decodedOutboxBodyByteCount += row.json.utf8.count
        do {
          let mutation: PendingMutation = try decodeOutboxBody(row.json)
          guard mutation.id == row.mutationID else {
            throw persistenceError(
              operation: "inspect durable outbox mutation",
              message: "The durable mutation id did not match its SQLite row id."
            )
          }
          mutations.append(mutation)
        } catch {
          let quarantined = try quarantineInvalidOutboxMutationWithoutTransaction(
            row,
            reason: "The durable mutation body could not be decoded during public inspection: \(error)"
          )
          didQuarantine = true
          if statuses.contains(InstantMutationStatus.failed.rawValue) {
            mutations.append(quarantined)
          }
        }
      }
      if didQuarantine {
        _ = try bumpMetadataRevisionWithoutTransaction(Self.outboxRevisionKey)
      }
      return (mutations, didQuarantine)
    }
    if loaded?.didQuarantine == true {
      cachedState = nil
    }
    return loaded?.mutations
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
          // The RAM cache holds the materialized store only. SQLite remains the
          // outbox authority; callers that need mutation bodies load addressed rows.
          return InstantPersistenceStateLoad(state: cachedState, source: .memory)
        }
        return InstantPersistenceStateLoad(
          state: try InstantPersistenceState(
            snapshot: loadCompactSnapshotWithoutTransaction(),
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

  private func loadCompactSnapshotWithoutTransaction() throws -> InstantPersistenceSnapshot {
    return InstantPersistenceSnapshot(
      store: try loadStoreSnapshotWithoutTransaction(),
      outbox: []
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
    localMutationQueueWideReadCount += 1
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
          snapshot: loadCompactSnapshotWithoutTransaction(),
          storeRevision: storeRevision,
          outboxRevision: outboxRevision
        )
      }
      var rows = try loadLiveQueryResultRowsWithoutTransaction()
      var protectedQueryKeys = preservingQueryKeys
      // Compact lifecycle rows deliberately omit transaction bodies. While any
      // mutation may still own optimistic state, preserve all persisted live
      // results instead of hydrating the complete durable queue just to derive
      // a narrower entity set. Pruning resumes once those lifecycle shells are
      // server-accepted or have a proven removed overlay.
      if try outboxRequiresConservativeLiveQueryPruningWithoutTransaction() {
        protectedQueryKeys.formUnion(rows.map(\.queryKey))
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
    requiredOutboxClaimMutationID: String? = nil,
    requiredOutboxClaimToken: String? = nil,
    expectedStoreRevision: Int64,
    expectedOutboxRevision: Int64
  ) throws -> Bool {
    precondition(
      (requiredOutboxClaimMutationID == nil) == (requiredOutboxClaimToken == nil),
      "A required outbox claim must include both its mutation id and token."
    )
    let didSave = try transaction {
      guard
        try loadMetadataRevisionWithoutTransaction(Self.storeRevisionKey) == expectedStoreRevision,
        try loadMetadataRevisionWithoutTransaction(Self.outboxRevisionKey) == expectedOutboxRevision
      else {
        return false
      }
      if let requiredOutboxClaimMutationID, let requiredOutboxClaimToken {
        guard try selectScalar(
          """
          SELECT delivery_claim_token FROM instant_outbox
          WHERE mutation_id = ? AND status = ? AND delivery_claim_state = ?
          LIMIT 1
          """,
          [
            .text(requiredOutboxClaimMutationID),
            .text(InstantMutationStatus.pending.rawValue),
            .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
          ]
        ) == requiredOutboxClaimToken else { return false }
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
    outbox: [PendingMutation]? = nil,
    pendingMutation: PendingMutation,
    supersedingImmediateTail: PendingMutation? = nil,
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

      var supersessionLifecycleID: String?
      if let supersedingImmediateTail {
        let supersedingImmediateTailID = supersedingImmediateTail.id
        // Claim/offered transitions intentionally do not bump the outbox
        // revision. Re-prove the exact physical tail and every eligibility
        // scalar under this write transaction before replacing evidence.
        guard
          try immediateOutboxTailIDWithoutTransaction() == supersedingImmediateTailID,
          try isImmediateSupersessionTailEligibleWithoutTransaction(
            id: supersedingImmediateTailID
          )
        else { return false }
        let lifecycleID =
          try lifecycleIDWithoutTransaction(for: supersedingImmediateTailID)
          ?? supersedingImmediateTailID
        supersessionLifecycleID = lifecycleID
        try execute(
          "DELETE FROM instant_outbox WHERE mutation_id = ?",
          [.text(supersedingImmediateTailID)]
        )
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
      try saveOutboxMutationWithoutTransaction(
        pendingMutation,
        lifecycleID: supersessionLifecycleID,
        advancingFromMutationID: supersedingImmediateTail?.id
      )
      if let supersedingImmediateTail, let supersessionLifecycleID {
        try saveMutationLifecycleAliasWithoutTransaction(
          mutationID: supersedingImmediateTail.id,
          lifecycleID: supersessionLifecycleID
        )
      }
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
      // SQLite is the queue authority. Runtime callers may pass a hydrated
      // snapshot for legacy retry/rebase work, but ordinary enqueue never
      // installs or copies it into the compact cache.
      cachedState.snapshot.outbox = outbox ?? []
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

  private func loadAutomaticDeliveryCandidateRowsWithoutTransaction(
    limit: Int
  ) throws -> [InstantOutboxDeliveryCandidateRow] {
    let sql =
      """
      SELECT
        mutation_id,
        created_at_ms,
        delivery_metadata_version,
        transport_step_count,
        COALESCE(encoded_body_bytes, length(CAST(json AS BLOB)))
      FROM instant_outbox
      WHERE delivery_claim_state = ?
        AND (
          delivery_state = ?
          OR (status IN (?, ?) AND delivery_metadata_version < ?)
        )
      ORDER BY created_at_ms, mutation_id
      LIMIT ?
      """
    let bindings: [SQLiteBinding] = [
      .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
      .text(InstantMutationStatus.pending.rawValue),
      .text(InstantMutationStatus.confirmed.rawValue),
      .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
      .int(Int64(limit)),
    ]
    return try loadOutboxDeliveryCandidateRowsWithoutTransaction(sql, bindings)
  }

  private func loadFailedOutboxLifecycleCandidatesWithoutTransaction(
    limit: Int
  ) throws -> [InstantFailedOutboxLifecycleCandidateRow] {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT mutation_id, created_at_ms,
             CASE WHEN lifecycle_json IS NULL
               THEN NULL ELSE length(CAST(lifecycle_json AS BLOB)) END,
             COALESCE(encoded_body_bytes, length(CAST(json AS BLOB)))
      FROM instant_outbox
      WHERE status = ? AND (
        delivery_metadata_version < ? OR lifecycle_json IS NULL OR
        LOWER(COALESCE(failure_message, '')) LIKE '%operation timed out%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%transaction timed out%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%service unavailable%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%temporarily unavailable%' OR
        LOWER(COALESCE(failure_message, '')) LIKE '%could not resolve%'
      )
      ORDER BY CASE
        WHEN LOWER(COALESCE(failure_message, '')) LIKE '%operation timed out%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%transaction timed out%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%service unavailable%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%temporarily unavailable%'
          OR LOWER(COALESCE(failure_message, '')) LIKE '%could not resolve%'
        THEN 0 ELSE 1 END,
        created_at_ms, mutation_id
      LIMIT ?
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind(
      [
        .text(InstantMutationStatus.failed.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(limit)),
      ],
      to: statement
    )
    var rows: [InstantFailedOutboxLifecycleCandidateRow] = []
    rows.reserveCapacity(limit)
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW,
        let mutationIDBytes = sqlite3_column_text(statement, 0)
      else {
        throw persistenceError(
          operation: "read failed mutation lifecycle candidates",
          message: lastErrorMessage()
        )
      }
      rows.append(
        InstantFailedOutboxLifecycleCandidateRow(
          mutationID: String(cString: mutationIDBytes),
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          lifecycleByteCount: sqlite3_column_type(statement, 2) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int64(statement, 2)),
          bodyByteCount: Int(sqlite3_column_int64(statement, 3))
        )
      )
    }
  }

  private func firstFailedMutationShellWithoutTransaction() throws -> PendingMutation? {
    var statement: OpaquePointer?
    try prepare(
      """
      SELECT mutation_id, created_at_ms, failure_message, optimistic_overlay_active
      FROM instant_outbox
      WHERE status = ?
      ORDER BY created_at_ms, mutation_id
      LIMIT 1
      """,
      statement: &statement
    )
    defer { sqlite3_finalize(statement) }
    try bind([.text(InstantMutationStatus.failed.rawValue)], to: statement)
    let code = sqlite3_step(statement)
    if code == SQLITE_DONE { return nil }
    guard code == SQLITE_ROW, let mutationIDBytes = sqlite3_column_text(statement, 0) else {
      throw persistenceError(
        operation: "read failed mutation summary",
        message: lastErrorMessage()
      )
    }
    let mutationID = String(cString: mutationIDBytes)
    let failureMessage = sqlite3_column_text(statement, 2).map(String.init(cString:))
      ?? "The Instant server rejected the mutation."
    var mutation = PendingMutation(
      id: mutationID,
      createdAt: InstantTimestamp(milliseconds: sqlite3_column_int64(statement, 1)),
      transaction: InstantStoreTransaction(id: mutationID, operations: []),
      status: .failed,
      failureMessage: failureMessage
    )
    mutation.failure = InstantMutationFailure(
      code: PendingMutation.failureCode(message: failureMessage),
      message: failureMessage
    )
    mutation.optimisticOverlayState = sqlite3_column_int64(statement, 3) == 0
      ? .removed
      : .applied
    return mutation
  }

  private func loadOutboxDeliveryCandidateRowsWithoutTransaction(
    _ sql: String,
    _ bindings: [SQLiteBinding]
  ) throws -> [InstantOutboxDeliveryCandidateRow] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var rows: [InstantOutboxDeliveryCandidateRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW else {
        throw persistenceError(
          operation: "read outbox delivery candidates",
          message: lastErrorMessage()
        )
      }
      guard let mutationID = sqlite3_column_text(statement, 0) else {
        throw persistenceError(
          operation: "read outbox delivery candidates",
          message: "SQLite returned a NULL mutation id."
        )
      }
      rows.append(
        InstantOutboxDeliveryCandidateRow(
          mutationID: String(cString: mutationID),
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          metadataVersion: Int(sqlite3_column_int64(statement, 2)),
          transportStepCount: sqlite3_column_type(statement, 3) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int64(statement, 3)),
          encodedBodyByteCount: Int(sqlite3_column_int64(statement, 4))
        )
      )
    }
  }

  private func loadOutboxBodyRowWithoutTransaction(
    id: String
  ) throws -> InstantOutboxBodyRow? {
    try loadOutboxBodyRowsWithoutTransaction(
      """
      SELECT mutation_id, created_at_ms, json
      FROM instant_outbox
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [.text(id)]
    ).first
  }

  private func automaticDeliveryStepCountFits(
    _ stepCount: Int,
    admittedStepCount: Int,
    remainingStepCount: Int
  ) -> Bool {
    guard stepCount >= 0 else { return false }
    return
      admittedStepCount <= remainingStepCount
      && stepCount <= remainingStepCount - admittedStepCount
  }

  private func claimOutboxMutationWithoutTransaction(
    id: String,
    claimantID: String,
    claimToken: String,
    deadlineMilliseconds: Int64
  ) throws {
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_started = 1, delivery_claim_state = ?, delivery_claim_token = ?,
          delivery_claimant_id = ?, delivery_claim_deadline_ms = ?
      WHERE mutation_id = ? AND delivery_claim_state = ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
        .text(claimantID),
        .int(deadlineMilliseconds),
        .text(id),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      ]
    )
    guard sqlite3_changes(connection.raw) == 1 else {
      throw persistenceError(
        operation: "claim automatic outbox mutation",
        message: "SQLite did not claim ready mutation '\(id)' exactly once."
      )
    }
  }

  private func reclaimExpiredOutboxClaimsWithoutTransaction(
    nowMilliseconds: Int64
  ) throws -> Set<String> {
    let ids = Set(try selectStrings(
      """
      SELECT mutation_id FROM instant_outbox
      WHERE delivery_claim_state = ? AND delivery_claim_deadline_ms <= ?
      ORDER BY created_at_ms, mutation_id
      LIMIT ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .int(nowMilliseconds),
        .int(Int64(InstantAutomaticOutboxClaimLimits.maximumMutationCount)),
      ]
    ))
    guard !ids.isEmpty else { return [] }
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_claim_state = ?, delivery_claim_token = NULL,
          delivery_claimant_id = NULL, delivery_claim_deadline_ms = NULL
      WHERE delivery_claim_state = ? AND delivery_claim_deadline_ms <= ?
      """,
      [
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .int(nowMilliseconds),
      ]
    )
    return ids
  }

  private func hasActiveOutboxClaimWithoutTransaction(
    excludingClaimantID claimantID: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1 FROM instant_outbox
        WHERE delivery_claim_state = ?
          AND (delivery_claimant_id IS NULL OR delivery_claimant_id != ?)
        LIMIT 1
      )
      """,
      [
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimantID),
      ]
    ) != 0
  }

  private func minimumOutboxClaimDeadlineWithoutTransaction() throws -> Int64? {
    try selectScalar(
      """
      SELECT CAST(MIN(delivery_claim_deadline_ms) AS TEXT)
      FROM instant_outbox
      WHERE delivery_claim_state = ?
      """,
      [.text(InstantOutboxDeliveryClaimState.claimed.rawValue)]
    ).flatMap(Int64.init)
  }

  private func decodeOutboxBody<Value: Decodable>(_ json: String) throws -> Value {
    guard let data = json.data(using: .utf8) else {
      throw persistenceError(
        operation: "decode outbox delivery row",
        message: "SQLite outbox JSON was not UTF-8."
      )
    }
    return try decoder.decode(Value.self, from: data)
  }

  private func saveOutboxDeliveryMetadataWithoutTransaction(
    _ mutation: PendingMutation
  ) throws {
    let encodedBody = try encode(mutation)
    try execute(
      """
      UPDATE instant_outbox
      SET delivery_state = ?, delivery_metadata_version = ?, transport_step_count = ?,
          encoded_body_bytes = ?, lifecycle_json = ?, failure_message = ?,
          confirmation_proven = ?, optimistic_overlay_active = ?
      WHERE mutation_id = ?
      """,
      [
        .text(InstantOutboxDeliveryMetadata.state(for: mutation).rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
        .int(Int64(encodedBody.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        mutation.failureMessage.map(SQLiteBinding.text) ?? .null,
        .int(InstantOutboxDeliveryMetadata.confirmationProven(in: mutation) ? 1 : 0),
        .int(mutation.optimisticOverlayState == .removed ? 0 : 1),
        .text(mutation.id),
      ]
    )
    try replaceOutboxWriteKeysWithoutTransaction(for: mutation)
  }

  private func quarantineInvalidOutboxMutationWithoutTransaction(
    _ row: InstantOutboxBodyRow,
    reason: String
  ) throws -> PendingMutation {
    let message =
      "Instant quarantined corrupt durable mutation '\(row.mutationID)'. \(reason)"
    var mutation = PendingMutation(
      id: row.mutationID,
      createdAt: InstantTimestamp(milliseconds: row.createdAtMilliseconds),
      transaction: InstantStoreTransaction(id: row.mutationID, operations: []),
      status: .failed,
      failureMessage: message
    )
    mutation.failure = InstantMutationFailure(
      code: .persistenceFailed,
      message: message
    )
    mutation.optimisticOverlayState = nil
    mutation.rollbackTransaction = nil
    let encodedMutation = try encode(mutation)
    let encodedLifecycle = try encode(mutation.compactedForMemory)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = 0, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = ?, confirmation_proven = 0, quarantine_json = ?,
          quarantine_lifecycle_json = lifecycle_json,
          optimistic_overlay_active = 1, delivery_claim_state = ?,
          delivery_claim_token = NULL, delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL, json = ?
      WHERE mutation_id = ?
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(encodedMutation.utf8.count)),
        .text(encodedLifecycle),
        .text(message),
        .text(row.json),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedMutation),
        .text(row.mutationID),
      ]
    )
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(row.mutationID)]
    )
    try saveMutationLifecycleWithoutTransaction(mutation)
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.quarantined-corrupt-body",
      message: message,
      metadata: ["mutationID": row.mutationID],
      correlationID: row.mutationID
    )
    reportIssue(
      """
      \(message)

      The row is now a visible failed mutation and later durable mutations remain deliverable. \
      Its original bytes remain in instant_outbox.quarantine_json at \(fileURL.path). Because \
      its optimistic state is unknown, automatic retry and discard are intentionally refused.
      """
    )
    return mutation
  }

  /// Moves an oversized body to durable quarantine using SQLite itself, so the
  /// automatic path never materializes the unbounded string in Swift memory.
  private func quarantineOversizedOutboxMutationWithoutTransaction(
    id: String,
    createdAtMilliseconds: Int64,
    encodedBodyByteCount: Int,
    maximumEncodedBodyByteCount: Int
  ) throws -> PendingMutation {
    let message =
      "Instant quarantined durable mutation '\(id)' because its \(encodedBodyByteCount)-byte body exceeds the \(maximumEncodedBodyByteCount)-byte automatic-delivery limit."
    var mutation = PendingMutation(
      id: id,
      createdAt: InstantTimestamp(milliseconds: createdAtMilliseconds),
      transaction: InstantStoreTransaction(id: id, operations: []),
      status: .failed,
      failureMessage: message
    )
    mutation.failure = InstantMutationFailure(code: .validationFailed, message: message)
    mutation.optimisticOverlayState = nil
    mutation.rollbackTransaction = nil
    let encodedMutation = try encode(mutation)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = 0, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = ?, confirmation_proven = 0, quarantine_json = json,
          quarantine_lifecycle_json = lifecycle_json,
          optimistic_overlay_active = 1, delivery_claim_state = ?,
          delivery_claim_token = NULL, delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL, json = ?
      WHERE mutation_id = ?
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(encodedMutation.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        .text(message),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedMutation),
        .text(id),
      ]
    )
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(id)]
    )
    try saveMutationLifecycleWithoutTransaction(mutation)
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.quarantined-oversized-body",
      message: message,
      metadata: [
        "mutationID": id,
        "encodedBodyByteCount": String(encodedBodyByteCount),
        "maximumEncodedBodyByteCount": String(maximumEncodedBodyByteCount),
      ],
      correlationID: id
    )
    reportIssue(
      """
      \(message)

      The row is a visible failed mutation. Its original bytes remain in instant_outbox.quarantine_json at \(fileURL.path), and its unknown optimistic state prevents automatic retry or discard.
      """
    )
    return mutation
  }

  /// Quarantines a legacy durable row whose normalized transport expansion is
  /// larger than the fixed automatic-delivery step limit. Current metadata lets
  /// this transition copy the raw JSON inside SQLite without decoding it.
  private func quarantineOverLimitStepOutboxMutationWithoutTransaction(
    id: String,
    createdAtMilliseconds: Int64,
    transportStepCount: Int
  ) throws -> PendingMutation {
    let maximumStepCount = InstantAutomaticOutboxClaimLimits.maximumStepCount
    let message =
      "Instant quarantined durable mutation '\(id)' because its \(transportStepCount) transport steps exceeds the \(maximumStepCount)-step automatic-delivery limit."
    var mutation = PendingMutation(
      id: id,
      createdAt: InstantTimestamp(milliseconds: createdAtMilliseconds),
      transaction: InstantStoreTransaction(id: id, operations: []),
      status: .failed,
      failureMessage: message
    )
    mutation.failure = InstantMutationFailure(code: .validationFailed, message: message)
    mutation.optimisticOverlayState = nil
    mutation.rollbackTransaction = nil
    let encodedMutation = try encode(mutation)
    try execute(
      """
      UPDATE instant_outbox
      SET status = ?, delivery_state = ?, delivery_metadata_version = ?,
          transport_step_count = 0, encoded_body_bytes = ?, lifecycle_json = ?,
          failure_message = ?, confirmation_proven = 0, quarantine_json = json,
          quarantine_lifecycle_json = lifecycle_json,
          optimistic_overlay_active = 1, delivery_claim_state = ?,
          delivery_claim_token = NULL, delivery_claimant_id = NULL,
          delivery_claim_deadline_ms = NULL, json = ?
      WHERE mutation_id = ?
      """,
      [
        .text(InstantMutationStatus.failed.rawValue),
        .text(InstantOutboxDeliveryState.invalid.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(encodedMutation.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        .text(message),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedMutation),
        .text(id),
      ]
    )
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(id)]
    )
    try saveMutationLifecycleWithoutTransaction(mutation)
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.quarantined-over-limit-steps",
      message: message,
      metadata: [
        "mutationID": id,
        "transportStepCount": String(transportStepCount),
        "maximumTransportStepCount": String(maximumStepCount),
      ],
      correlationID: id
    )
    reportIssue(
      """
      \(message)

      The row is a visible failed mutation. Its original bytes remain in instant_outbox.quarantine_json at \(fileURL.path), and its unknown optimistic state prevents automatic retry or discard.
      """
    )
    return mutation
  }

  private func replaceOutboxWriteKeysWithoutTransaction(
    for mutation: PendingMutation
  ) throws {
    try execute(
      "DELETE FROM instant_outbox_write_keys WHERE mutation_id = ?",
      [.text(mutation.id)]
    )
    let keys = InstantOutboxDeliveryMetadata.writeKeys(in: mutation)
      .sorted { lhs, rhs in
        (lhs.entityID, lhs.attributeID) < (rhs.entityID, rhs.attributeID)
      }
    for key in keys {
      try execute(
        """
        INSERT INTO instant_outbox_write_keys (mutation_id, entity_id, attribute_id)
        VALUES (?, ?, ?)
        """,
        [
          .text(mutation.id),
          .text(key.entityID),
          .text(key.attributeID),
        ]
      )
    }
  }

  /// Returns true when a later locally visible overlay cannot provide a
  /// trustworthy normalized write-key proof. Such an overlay is not
  /// authoritative server state, so delivery must conservatively preserve all
  /// selected writes rather than filtering one away.
  private func hasUnknownActiveOverlayAfterWithoutTransaction(
    _ position: InstantOutboxDeliveryPosition,
    excludingClaimToken claimToken: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox AS outbox
        WHERE (
          outbox.created_at_ms > ?
          OR (outbox.created_at_ms = ? AND outbox.mutation_id > ?)
        )
        AND outbox.optimistic_overlay_active != 0
        AND outbox.confirmation_proven = 0
        AND NOT (
          outbox.delivery_claim_state = ?
          AND COALESCE(outbox.delivery_claim_token, '') = ?
        )
        AND (
          outbox.delivery_metadata_version < ?
          OR NOT EXISTS (
            SELECT 1
            FROM instant_outbox_write_keys AS write_keys
            WHERE write_keys.mutation_id = outbox.mutation_id
          )
        )
        LIMIT 1
      )
      """,
      [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
      ]
    ) != 0
  }

  private func hasActiveOverlayWriteKeyAfterWithoutTransaction(
    _ key: InstantVisibleWriteKey,
    position: InstantOutboxDeliveryPosition,
    excludingClaimToken claimToken: String
  ) throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox_write_keys AS write_keys
        JOIN instant_outbox AS outbox
          ON outbox.mutation_id = write_keys.mutation_id
        WHERE (
          outbox.created_at_ms > ?
          OR (outbox.created_at_ms = ? AND outbox.mutation_id > ?)
        )
        AND outbox.optimistic_overlay_active != 0
        AND outbox.confirmation_proven = 0
        AND NOT (
          outbox.delivery_claim_state = ?
          AND COALESCE(outbox.delivery_claim_token, '') = ?
        )
        AND write_keys.entity_id = ?
        AND write_keys.attribute_id = ?
        LIMIT 1
      )
      """,
      [
        .int(position.createdAtMilliseconds),
        .int(position.createdAtMilliseconds),
        .text(position.mutationID),
        .text(InstantOutboxDeliveryClaimState.claimed.rawValue),
        .text(claimToken),
        .text(key.entityID),
        .text(key.attributeID),
      ]
    ) != 0
  }

  private func hasAutomaticDeliveryCandidateWithoutTransaction() throws -> Bool {
    let sql =
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox
        WHERE delivery_claim_state = ?
          AND (
            delivery_state = ?
            OR (status IN (?, ?) AND delivery_metadata_version < ?)
          )
        LIMIT 1
      )
      """
    let bindings: [SQLiteBinding] = [
      .text(InstantOutboxDeliveryClaimState.ready.rawValue),
      .text(InstantOutboxDeliveryState.needsDelivery.rawValue),
      .text(InstantMutationStatus.pending.rawValue),
      .text(InstantMutationStatus.confirmed.rawValue),
      .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
    ]
    return try selectInt64(sql, bindings) != 0
  }

  private func loadVisibleWriteFilterWithoutTransaction(
    for writeKeys: Set<InstantVisibleWriteKey>
  ) throws -> InstantVisibleWriteFilter {
    let attributeIDs = Set(writeKeys.map(\.attributeID)).sorted()
    var attributesByID: [String: InstantAttribute] = [:]
    attributesByID.reserveCapacity(attributeIDs.count)
    for attributeID in attributeIDs {
      let attributes: [InstantAttribute] = try selectJSON(
        "SELECT json FROM instant_attributes WHERE id = ? LIMIT 1",
        [.text(attributeID)]
      )
      if let attribute = attributes.first {
        attributesByID[attributeID] = attribute
      }
    }

    var newestVisibleWrite: [InstantVisibleWriteKey: InstantTimestamp] = [:]
    newestVisibleWrite.reserveCapacity(writeKeys.count)
    for key in writeKeys {
      guard let milliseconds = try selectScalar(
        """
        SELECT CAST(MAX(tx_time_ms) AS TEXT)
        FROM instant_triples
        WHERE entity_id = ? AND attribute_id = ?
        """,
        [.text(key.entityID), .text(key.attributeID)]
      ).flatMap(Int64.init)
      else { continue }
      newestVisibleWrite[key] = InstantTimestamp(milliseconds: milliseconds)
    }
    return InstantVisibleWriteFilter(
      attributesByID: attributesByID,
      newestVisibleWrite: newestVisibleWrite
    )
  }

  private func loadOutboxBodyRowsWithoutTransaction(
    _ sql: String,
    _ bindings: [SQLiteBinding] = []
  ) throws -> [InstantOutboxBodyRow] {
    var statement: OpaquePointer?
    try prepare(sql, statement: &statement)
    defer { sqlite3_finalize(statement) }
    try bind(bindings, to: statement)

    var rows: [InstantOutboxBodyRow] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { return rows }
      guard code == SQLITE_ROW else {
        throw persistenceError(operation: "read outbox delivery rows", message: lastErrorMessage())
      }
      guard
        let mutationID = sqlite3_column_text(statement, 0),
        let json = sqlite3_column_text(statement, 2)
      else {
        throw persistenceError(
          operation: "read outbox delivery rows",
          message: "SQLite returned a NULL bounded-delivery column."
        )
      }
      let body = String(cString: json)
      materializedOutboxBodyCount += 1
      materializedOutboxBodyByteCount += body.utf8.count
      rows.append(
        InstantOutboxBodyRow(
          mutationID: String(cString: mutationID),
          createdAtMilliseconds: sqlite3_column_int64(statement, 1),
          json: body
        )
      )
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

  private func outboxRequiresConservativeLiveQueryPruningWithoutTransaction() throws -> Bool {
    try selectInt64(
      """
      SELECT EXISTS(
        SELECT 1
        FROM instant_outbox
        WHERE optimistic_overlay_active != 0
        LIMIT 1
      )
      """,
      []
    ) != 0
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
    let mutationIDs = Set(mutations.map(\.id))
    let existingIDs = try selectStrings("SELECT mutation_id FROM instant_outbox")
    for id in existingIDs where !mutationIDs.contains(id) {
      try execute("DELETE FROM instant_outbox WHERE mutation_id = ?", [.text(id)])
    }
    for mutation in mutations {
      try saveOutboxMutationWithoutTransaction(mutation)
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
      try saveOutboxMutationWithoutTransaction(mutation)
    }
  }

  private func saveOutboxMutationWithoutTransaction(
    _ mutation: PendingMutation,
    lifecycleID requestedLifecycleID: String? = nil,
    advancingFromMutationID: String? = nil
  ) throws {
    let deliveryState = InstantOutboxDeliveryMetadata.state(for: mutation)
    let encodedBody = try encode(mutation)
    try execute(
      """
      INSERT INTO instant_outbox (
        mutation_id,
        status,
        created_at_ms,
        delivery_state,
        delivery_metadata_version,
        transport_step_count,
        encoded_body_bytes,
        delivery_started,
        lifecycle_json,
        failure_message,
        confirmation_proven,
        optimistic_overlay_active,
        delivery_claim_state,
        json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(mutation_id) DO UPDATE SET
        status = excluded.status,
        created_at_ms = excluded.created_at_ms,
        delivery_state = excluded.delivery_state,
        delivery_metadata_version = excluded.delivery_metadata_version,
        transport_step_count = excluded.transport_step_count,
        encoded_body_bytes = excluded.encoded_body_bytes,
        lifecycle_json = excluded.lifecycle_json,
        failure_message = excluded.failure_message,
        confirmation_proven = excluded.confirmation_proven,
        optimistic_overlay_active = excluded.optimistic_overlay_active,
        json = excluded.json
      """,
      [
        .text(mutation.id),
        .text(mutation.status.rawValue),
        .int(mutation.createdAt.milliseconds),
        .text(deliveryState.rawValue),
        .int(Int64(InstantOutboxDeliveryMetadata.currentVersion)),
        .int(Int64(InstantOutboxDeliveryMetadata.stepCount(in: mutation))),
        .int(Int64(encodedBody.utf8.count)),
        .text(try encode(mutation.compactedForMemory)),
        mutation.failureMessage.map(SQLiteBinding.text) ?? .null,
        .int(InstantOutboxDeliveryMetadata.confirmationProven(in: mutation) ? 1 : 0),
        .int(mutation.optimisticOverlayState == .removed ? 0 : 1),
        .text(InstantOutboxDeliveryClaimState.ready.rawValue),
        .text(encodedBody),
      ]
    )
    try replaceOutboxWriteKeysWithoutTransaction(for: mutation)
    try saveMutationLifecycleWithoutTransaction(
      mutation,
      lifecycleID: requestedLifecycleID,
      advancingFromMutationID: advancingFromMutationID
    )
  }

  private func lifecycleIDWithoutTransaction(
    for mutationID: String
  ) throws -> String? {
    try selectScalar(
      """
      SELECT lifecycle_id
      FROM instant_outbox_lifecycle_aliases
      WHERE mutation_id = ?
      LIMIT 1
      """,
      [.text(mutationID)]
    )
  }

  private func currentMutationIDWithoutTransaction(
    lifecycleID: String
  ) throws -> String? {
    try selectScalar(
      """
      SELECT current_mutation_id
      FROM instant_outbox_lifecycles
      WHERE lifecycle_id = ?
      LIMIT 1
      """,
      [.text(lifecycleID)]
    )
  }

  private func saveMutationLifecycleWithoutTransaction(
    _ mutation: PendingMutation,
    lifecycleID requestedLifecycleID: String? = nil,
    advancingFromMutationID: String? = nil
  ) throws {
    let existingLifecycleID = try lifecycleIDWithoutTransaction(for: mutation.id)
    // Ordinary mutations keep their existing row-addressed lifecycle behavior
    // and do not create permanent history tables. Durable lineage exists only
    // after an actual supersession chain starts.
    if let advancingFromMutationID {
      guard let lifecycleID = requestedLifecycleID,
        mutation.id != advancingFromMutationID,
        existingLifecycleID == nil
      else {
        throw persistenceError(
          operation: "advance outbox mutation lifecycle",
          message:
            "A supersession newcomer must have a distinct transaction id that has never belonged to a lifecycle."
        )
      }
      let terminalJSON = try terminalLifecycleJSON(for: mutation)

      let currentMutationID = try currentMutationIDWithoutTransaction(
        lifecycleID: lifecycleID
      )
      if let currentMutationID {
        guard currentMutationID == advancingFromMutationID else {
          throw persistenceError(
            operation: "advance outbox mutation lifecycle",
            message:
              "Lifecycle '\(lifecycleID)' no longer names predecessor '\(advancingFromMutationID)' as its current mutation."
          )
        }
        try execute(
          """
          UPDATE instant_outbox_lifecycles
          SET current_mutation_id = ?, terminal_json = ?
          WHERE lifecycle_id = ? AND current_mutation_id = ?
          """,
          [
            .text(mutation.id),
            terminalJSON.map(SQLiteBinding.text) ?? .null,
            .text(lifecycleID),
            .text(advancingFromMutationID),
          ]
        )
        guard try selectInt64("SELECT changes()") == 1 else {
          throw persistenceError(
            operation: "advance outbox mutation lifecycle",
            message: "SQLite did not advance the lifecycle from its proven predecessor."
          )
        }
      } else {
        guard lifecycleID == advancingFromMutationID else {
          throw persistenceError(
            operation: "create outbox mutation lifecycle",
            message: "A new lifecycle must be rooted at the replaced predecessor id."
          )
        }
        try execute(
          """
          INSERT INTO instant_outbox_lifecycles (
            lifecycle_id, current_mutation_id, terminal_json
          ) VALUES (?, ?, ?)
          """,
          [
            .text(lifecycleID),
            .text(mutation.id),
            terminalJSON.map(SQLiteBinding.text) ?? .null,
          ]
        )
      }
      try saveMutationLifecycleAliasWithoutTransaction(
        mutationID: mutation.id,
        lifecycleID: lifecycleID
      )
      return
    }

    guard requestedLifecycleID == nil, let lifecycleID = existingLifecycleID else {
      // Ordinary mutations do not create history. Passing a lifecycle without
      // a proven predecessor transition is never allowed to move its survivor.
      if requestedLifecycleID != nil {
        throw persistenceError(
          operation: "save outbox mutation lifecycle",
          message: "Lifecycle advancement requires an exact predecessor id."
        )
      }
      return
    }
    guard try currentMutationIDWithoutTransaction(lifecycleID: lifecycleID) == mutation.id
    else {
      throw persistenceError(
        operation: "save outbox mutation lifecycle",
        message:
          "Refused to move lifecycle '\(lifecycleID)' backward through stale alias '\(mutation.id)'."
      )
    }
    let terminalJSON = try terminalLifecycleJSON(for: mutation)
    try execute(
      """
      UPDATE instant_outbox_lifecycles
      SET terminal_json = ?
      WHERE lifecycle_id = ? AND current_mutation_id = ?
      """,
      [
        terminalJSON.map(SQLiteBinding.text) ?? .null,
        .text(lifecycleID),
        .text(mutation.id),
      ]
    )
  }

  private func saveMutationLifecycleAliasWithoutTransaction(
    mutationID: String,
    lifecycleID: String
  ) throws {
    try execute(
      """
      INSERT INTO instant_outbox_lifecycle_aliases (mutation_id, lifecycle_id)
      VALUES (?, ?)
      ON CONFLICT(mutation_id) DO NOTHING
      """,
      [.text(mutationID), .text(lifecycleID)]
    )
    guard try lifecycleIDWithoutTransaction(for: mutationID) == lifecycleID else {
      throw persistenceError(
        operation: "save outbox mutation lifecycle alias",
        message:
          "Transaction id '\(mutationID)' already belongs to another lifecycle and cannot be reassigned."
      )
    }
  }

  private func lifecycleEvent(
    for mutation: PendingMutation
  ) -> InstantMutationLifecycleEvent? {
    switch mutation.status {
    case .confirmed where mutation.provesServerAcceptance:
      .serverAccepted(mutation)
    case .failed:
      .failed(mutation)
    case .pending, .confirmed:
      nil
    }
  }

  private func terminalLifecycleJSON(for mutation: PendingMutation) throws -> String? {
    guard lifecycleEvent(for: mutation) != nil else { return nil }
    return try encode(mutation.compactedForMemory)
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
