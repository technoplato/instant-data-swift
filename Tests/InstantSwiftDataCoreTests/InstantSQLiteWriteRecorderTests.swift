import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #1510: a phone's local save wrote 102 KB, and the store's meters said only which store call wrote it. Its
/// write-ahead log, read page by page on a copy, put a save at 24.4 pages across 17 b-trees: triples, outbox write
/// keys and their index, the body and its overflow, page 1 for a one-byte free-page count. Michael, typed 2026-10-31
/// 13:30: a recorder in the library, simple and bounded, per statement and per table, over time.
///
/// Each test reads its own database's recorder, and checks it against the log file itself: every frame's page,
/// named by `dbstat` through the system's VFS, which the recorder never sees.
@Suite
struct InstantSQLiteWriteRecorderTests {
  /// Rows that fill several leaves and an interior page, and rows too long for a leaf, in a `WITHOUT ROWID` table and its
  /// index and in a rowid table; then deletes that free pages. Every frame the log took is counted once, under the
  /// b-tree its page belonged to when it was written, the overflow pages apart, the free list's trunk under
  /// ``InstantSQLiteWriteRecord/freeList``.
  @Test
  func everyPageTheLogTakesIsNamedByItsBTree() throws {
    let database = try RecordedDatabase()
    defer { database.remove() }
    try database.execute("PRAGMA wal_autocheckpoint = 0")
    try database.execute("PRAGMA secure_delete = FAST")
    try database.execute("CREATE TABLE note (id TEXT PRIMARY KEY, body TEXT NOT NULL) WITHOUT ROWID")
    try database.execute("CREATE INDEX note_body ON note (substr(body, 1, 40))")
    try database.execute("CREATE TABLE line (id INTEGER PRIMARY KEY, text TEXT NOT NULL)")
    database.recorder.reloadSchema(from: database.connection)
    let setup = try LogFrames.read(database.logURL).count
    let before = database.recorder.record()

    try database.execute(
      """
      WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 600)
      INSERT INTO note (id, body) SELECT printf('note-%05d', x), printf('%.*c', 180 + x % 40, 'n') FROM n
      """
    )
    try database.execute(
      """
      WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 40)
      INSERT INTO note (id, body) SELECT printf('long-%05d', x), printf('%.*c', 6000 + x, 'l') FROM n
      """
    )
    try database.execute(
      """
      WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 300)
      INSERT INTO line (text) SELECT printf('%.*c', 120, 't') FROM n
      """
    )
    let inserted = try LogFrames.read(database.logURL)
    let afterInserts = try PageOwners.read(database.url)

    try database.execute("DELETE FROM note WHERE id LIKE 'long-%' AND CAST(substr(id, 6) AS INTEGER) % 2 = 0")
    try database.execute("DELETE FROM line WHERE id % 3 = 0")
    let all = try LogFrames.read(database.logURL)
    let afterDeletes = try PageOwners.read(database.url)

    var expected: [String: InstantSQLiteWriteRecord.BTree] = [:]
    for page in inserted[setup...] { expected.count(page, afterInserts) }
    for page in all[inserted.count...] { expected.count(page, afterDeletes) }
    let recorded = database.recorder.record().subtracting(before)

    #expect(recorded.btrees == expected, "\(diff(recorded.btrees, expected) ?? "")")
    #expect(recorded.logPages == all.count - setup)
    #expect(recorded.btrees[InstantSQLiteWriteRecord.unnamed] == nil)
    #expect((recorded.btrees["note"]?.overflowLogPages ?? 0) >= 40 * 2, "\(recorded.btrees)")
    #expect((recorded.btrees[InstantSQLiteWriteRecord.freeList]?.logPages ?? 0) >= 1, "\(recorded.btrees)")
  }

  /// A checkpoint copies each page the log holds into the database file once: counted under the b-tree the page last
  /// belonged to when the log took it.
  @Test
  func aCheckpointsCopiesAreNamedByTheirBTree() throws {
    let database = try RecordedDatabase()
    defer { database.remove() }
    try database.execute("PRAGMA wal_autocheckpoint = 0")
    try database.execute("CREATE TABLE note (id TEXT PRIMARY KEY, body TEXT NOT NULL) WITHOUT ROWID")
    try database.execute("CREATE INDEX note_body ON note (substr(body, 1, 40))")
    database.recorder.reloadSchema(from: database.connection)
    try database.execute(
      """
      WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n WHERE x < 500)
      INSERT INTO note (id, body) SELECT printf('note-%05d', x), printf('%.*c', 200 + x % 3000, 'c') FROM n
      """
    )
    let frames = try LogFrames.read(database.logURL)
    let owners = try PageOwners.read(database.url)
    let before = database.recorder.record()

    try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    let recorded = database.recorder.record().subtracting(before)

    var expected: [String: Int] = [:]
    for page in Set(frames) { expected[owners.name(of: page), default: 0] += 1 }
    #expect(recorded.btrees.mapValues(\.checkpointPages).filter { $0.value > 0 } == expected)
    #expect(recorded.checkpointPages == Set(frames).count)
  }

  /// A store call's pages are named by b-tree under the call, and its write statements by their rows and the
  /// b-trees they write; every page the call committed is in the call's count.
  @Test
  func aStoreCallsPagesAndItsStatementsAreNamed() async throws {
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLitePersistenceStore(
      fileURL: directory.appendingPathComponent("state.sqlite"),
      declaredAttributes: TodoExample.attributes
    )
    try await store.bootstrap()
    let before = await store.writeRecordForTesting()

    let triples = (0..<200).map { index in
      InstantTriple(
        entityID: "todo-\(index)",
        attributeID: TodoExample.attributes[1].id,
        value: .string(String(repeating: "words of todo \(index) ", count: 8)),
        txID: "tx-\(index)",
        txTime: InstantTimestamp(milliseconds: Int64(index) + 1)
      )
    }
    try await store.saveStoreSnapshot(InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples))
    let recorded = await store.writeRecordForTesting().subtracting(before)

    let call = try #require(recorded.calls["saveStoreSnapshot(_:)"], "calls: \(recorded.calls)")
    #expect(call.values.reduce(0, +) == recorded.logPages, "calls: \(recorded.calls), btrees: \(recorded.btrees)")
    #expect((call["instant_triples"] ?? 0) >= 8, "call: \(call)")
    #expect(recorded.btrees[InstantSQLiteWriteRecord.unnamed] == nil, "\(recorded.btrees)")
    let insert = try #require(
      recorded.statements.first { $0.key.contains("INSERT") && $0.key.contains("instant_triples") },
      "statements: \(recorded.statements.keys.sorted())"
    )
    #expect(insert.value.rows >= 200, "\(insert)")
    #expect(insert.value.btrees.contains("instant_triples"), "\(insert)")
    #expect(insert.value.soleLogPages + insert.value.sharedLogPages >= 8, "\(insert)")
  }

  /// A local write's save names the outbox's tables: its row, its body, its write keys and their index, each by the
  /// statement that wrote it.
  @Test
  func aLocalWritesSaveNamesTheOutboxTablesAndStatements() async throws {
    let directory = try Self.temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "write-recorder-1510",
        persistenceURL: directory.appendingPathComponent("state.sqlite"),
        initialAttributes: TodoExample.attributes
      )
    )
    let before = await runtime.persistence.writeRecordForTesting()

    _ = try await runtime.transact(
      operations: TodoExample.createOperations(
        id: "todo-1510",
        text: "a line the recorder names",
        createdAt: InstantTimestamp(milliseconds: 1_793_467_733_514),
        transactionID: "tx-1510"
      )
    )
    let recorded = await runtime.persistence.writeRecordForTesting().subtracting(before)
    _ = try? await runtime.closeConnection()

    let save = try #require(
      recorded.calls.first { $0.key.hasPrefix("saveLocalMutation") }?.value,
      "calls: \(recorded.calls)"
    )
    for table in ["instant_triples", "instant_outbox", "instant_outbox_bodies", "instant_outbox_write_keys"] {
      #expect((save[table] ?? 0) >= 1, "\(table): \(save)")
    }
    #expect(recorded.btrees[InstantSQLiteWriteRecord.unnamed] == nil, "\(recorded.btrees)")
    let writeKeys = try #require(
      recorded.statements.first { $0.key.contains("INSERT") && $0.key.contains("instant_outbox_write_keys") },
      "statements: \(recorded.statements.keys.sorted())"
    )
    #expect(writeKeys.value.rows >= 4, "\(writeKeys)")
    #expect(writeKeys.value.btrees.contains("instant_outbox_write_keys_lookup_idx"), "\(writeKeys)")
  }

  /// A statement built for a batch of any size is one shape: its placeholder lists collapse.
  @Test
  func aStatementBuiltForABatchIsOneShape() {
    func batch(_ rows: Int) -> String {
      "INSERT INTO t (a, b)\n      VALUES " + Array(repeating: "(?, ?)", count: rows).joined(separator: ", ")
    }
    expectNoDifference(InstantSQLiteWriteRecord.shape(of: batch(1)), "INSERT INTO t (a, b) VALUES (?…)")
    expectNoDifference(InstantSQLiteWriteRecord.shape(of: batch(50)), InstantSQLiteWriteRecord.shape(of: batch(2)))
    expectNoDifference(
      InstantSQLiteWriteRecord.shape(of: "DELETE FROM t WHERE a = ? AND b IN (?, ?, ?)"),
      "DELETE FROM t WHERE a = ? AND b IN (?…)"
    )
  }

  /// A thousand distinct write statements: the record names at most ``InstantSQLiteWriteRecord/statementLimit`` and
  /// counts the rest's rows under ``InstantSQLiteWriteRecord/otherStatements``.
  @Test
  func theRecordNamesAtMostItsLimitOfStatements() throws {
    let database = try RecordedDatabase()
    defer { database.remove() }
    try database.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, x INTEGER)")
    database.recorder.reloadSchema(from: database.connection)
    var cache = SQLiteStatementCache()
    cache.recorder = database.recorder
    for index in 0..<1_000 {
      let statement = cache.checkOut("INSERT INTO t (x) VALUES (\(index))", on: database.connection).statement
      _ = sqlite3_step(statement)
      cache.checkIn(statement)
    }
    cache.finalizeAll()
    let recorded = database.recorder.record()

    #expect(recorded.statements.count <= InstantSQLiteWriteRecord.statementLimit + 1)
    #expect(recorded.statements.values.reduce(0) { $0 + $1.rows } == 1_000)
    #expect((recorded.statements[InstantSQLiteWriteRecord.otherStatements]?.rows ?? 0) >= 1_000 - 256)
  }

  /// The store reads `sqlite3_changes()` after a statement to check what it changed (a claim, an acknowledgement): the
  /// recorder's first sight of a write statement, which explains it, must leave that count as the statement set it.
  /// On the writer itself an `EXPLAIN` reset it, and the outbox quarantined the first claim of each shape.
  @Test
  func recordingAStatementLeavesTheConnectionsChangeCount() throws {
    let database = try RecordedDatabase()
    defer { database.remove() }
    try database.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, x INTEGER)")
    try database.execute("INSERT INTO t (x) VALUES (1), (2), (3)")
    database.recorder.reloadSchema(from: database.connection)
    var cache = SQLiteStatementCache()
    cache.recorder = database.recorder
    defer { cache.finalizeAll() }

    let statement = cache.checkOut("UPDATE t SET x = x + 1 WHERE x >= ?", on: database.connection).statement
    sqlite3_bind_int64(statement, 1, 2)
    #expect(sqlite3_step(statement) == SQLITE_DONE)
    cache.checkIn(statement)

    #expect(sqlite3_changes(database.connection) == 2)
    let recorded = database.recorder.record()
    let update = try #require(recorded.statements.first { $0.key.hasPrefix("UPDATE t") }?.value, "\(recorded)")
    #expect(update.rows == 2)
    #expect(update.btrees == ["t"])
  }

  /// #1285 rule 5: a million log frames, each a page the recorder parses, on a 256 KB stack: constant stack depth (it
  /// returns), bounded time a frame, and the recorder's own collections under 1 MB. Its own: the process's footprint
  /// moves with the suites that run beside it (it grew 110 MB here while the outbox suites' 10,000-row tests ran).
  @Test
  func aMillionFramesAtAConstantStackAndBoundedMemory() throws {
    let recorder = InstantSQLiteDatabaseWriteRecorder(databaseName: "/stress/\(UUID().uuidString).sqlite")
    let elapsed = LockedValue<Double?>(nil)
    let thread = Thread {
      let started = ContinuousClock.now
      LogFrames.writeSynthetic(frames: 1_000_000, to: recorder)
      let duration = ContinuousClock.now - started
      elapsed.set(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }
    thread.stackSize = 256 * 1_024
    thread.start()
    let deadline = Date().addingTimeInterval(120)
    while elapsed.get() == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    let seconds = try #require(elapsed.get(), "the million frames did not finish in 120 s")

    #expect(seconds / 1_000_000 < 20e-6, "seconds a frame: \(seconds / 1_000_000)")
    #expect(recorder.retainedBytesForTesting() < 1_024 * 1_024, "retained: \(recorder.retainedBytesForTesting())")
    #expect(recorder.record().logPages == 1_000_000)
  }

  private static func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSQLiteWriteRecorderTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

}

/// A database opened through the file meter's VFS, with a write recorder attached before it opened.
private struct RecordedDatabase {
  let directory: URL
  let url: URL
  let connection: OpaquePointer
  let recorder: InstantSQLiteDatabaseWriteRecorder

  var logURL: URL { URL(fileURLWithPath: url.path + "-wal") }

  init() throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSQLiteWriteRecorderTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    url = directory.appendingPathComponent("raw.sqlite")
    recorder = try #require(InstantSQLiteWriteRecorder.attach(databaseAt: url.path))
    let vfs = try #require(InstantSQLiteFileMeter.registeredVFSName())
    var opened: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(url.path, &opened, flags, vfs) == SQLITE_OK, let opened else {
      sqlite3_close_v2(opened)
      throw CocoaError(.fileWriteUnknown)
    }
    connection = opened
    try execute("PRAGMA journal_mode = WAL")
  }

  func execute(_ sql: String) throws {
    var message: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(connection, sql, nil, nil, &message) == SQLITE_OK else {
      let text = message.map { String(cString: $0) } ?? "unknown"
      sqlite3_free(message)
      throw StorageIOError("\(sql): \(text)")
    }
  }

  func remove() {
    sqlite3_close_v2(connection)
    recorder.detach()
    try? FileManager.default.removeItem(at: directory)
  }
}

/// The log file's frames, read from the file itself.
private enum LogFrames {
  /// Each frame's page number, in order, while the frames' salts match the log header's.
  static func read(_ url: URL) throws -> [UInt32] {
    let data = try Data(contentsOf: url)
    guard data.count >= 32 else { return [] }
    let pageSize = Int(bigEndian32(data, 8))
    let salts = (bigEndian32(data, 16), bigEndian32(data, 20))
    var pages: [UInt32] = []
    var offset = 32
    while offset + 24 + pageSize <= data.count {
      guard (bigEndian32(data, offset + 8), bigEndian32(data, offset + 12)) == salts else { break }
      pages.append(bigEndian32(data, offset))
      offset += 24 + pageSize
    }
    return pages
  }

  /// `frames` log frames handed to `recorder` as SQLite writes them: a header and 25 b-tree leaves a transaction, the
  /// last one committing.
  static func writeSynthetic(frames: Int, to recorder: InstantSQLiteDatabaseWriteRecorder) {
    let pageSize = 4_096
    var header = [UInt8](repeating: 0, count: 32)
    store(0x377F_0682, at: 0, in: &header)
    store(3_007_000, at: 4, in: &header)
    store(UInt32(pageSize), at: 8, in: &header)
    header.withUnsafeBytes { recorder.logWrite($0.baseAddress!, count: 32, offset: 0) }
    var frame = [UInt8](repeating: 0, count: 24 + pageSize)
    // A table leaf with 40 cells of 90 bytes each.
    frame[24] = 13
    store16(40, at: 24 + 3, in: &frame)
    for cell in 0..<40 {
      let offset = 400 + cell * 90
      store16(UInt16(offset), at: 24 + 8 + cell * 2, in: &frame)
      frame[24 + offset] = 80
      frame[24 + offset + 1] = UInt8(cell)
    }
    for index in 0..<frames {
      let slot = index % 4_000
      store(UInt32(2 + index % 3_000), at: 0, in: &frame)
      store(index % 25 == 24 ? 3_002 : 0, at: 4, in: &frame)
      frame.withUnsafeBytes {
        recorder.logWrite($0.baseAddress!, count: 24 + pageSize, offset: Int64(32 + slot * (24 + pageSize)))
      }
    }
  }

  static func bigEndian32(_ data: Data, _ offset: Int) -> UInt32 {
    data[data.startIndex + offset..<data.startIndex + offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
  }

  private static func store(_ value: UInt32, at offset: Int, in bytes: inout [UInt8]) {
    for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (24 - 8 * index)) }
  }

  private static func store16(_ value: UInt16, at offset: Int, in bytes: inout [UInt8]) {
    bytes[offset] = UInt8(value >> 8)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value)
  }
}

/// Each page's b-tree, read with `dbstat` through the system's VFS.
private struct PageOwners {
  var byPage: [UInt32: (name: String, isOverflow: Bool)]
  var tables: [String: (table: String, isIndex: Bool)]

  static func read(_ url: URL) throws -> Self {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, "unix") == SQLITE_OK, let connection else {
      sqlite3_close_v2(connection)
      throw StorageIOError("open \(url.lastPathComponent) for dbstat")
    }
    defer { sqlite3_close_v2(connection) }
    var owners = Self(byPage: [:], tables: [:])
    try query(connection, "SELECT name, pageno, pagetype FROM dbstat") { statement in
      let name = String(cString: sqlite3_column_text(statement, 0))
      let page = UInt32(sqlite3_column_int64(statement, 1))
      let type = String(cString: sqlite3_column_text(statement, 2))
      owners.byPage[page] = (name, type == "overflow")
    }
    try query(connection, "SELECT name, tbl_name, type FROM sqlite_schema WHERE rootpage > 0") { statement in
      owners.tables[String(cString: sqlite3_column_text(statement, 0))] = (
        String(cString: sqlite3_column_text(statement, 1)),
        String(cString: sqlite3_column_text(statement, 2)) == "index"
      )
    }
    return owners
  }

  /// The recorder's name for `page`: page 1, a b-tree's name, or the free list for a page no b-tree holds.
  func name(of page: UInt32) -> String {
    if page == 1 { return InstantSQLiteWriteRecord.headerPage }
    return byPage[page]?.name ?? InstantSQLiteWriteRecord.freeList
  }

  private static func query(_ connection: OpaquePointer, _ sql: String, row: (OpaquePointer) -> Void) throws {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
    }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
  }
}

extension [String: InstantSQLiteWriteRecord.BTree] {
  /// Counts one log page under its owner in `owners`.
  fileprivate mutating func count(_ page: UInt32, _ owners: PageOwners) {
    let name = owners.name(of: page)
    let table = owners.tables[name]
    var counts = self[name] ?? InstantSQLiteWriteRecord.BTree(table: table?.table ?? name, isIndex: table?.isIndex ?? false)
    counts.logPages += 1
    if page != 1, owners.byPage[page]?.isOverflow == true { counts.overflowLogPages += 1 }
    self[name] = counts
  }
}

/// A value two threads share: set once by one, read by the other.
private final class LockedValue<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func get() -> Value { lock.withLock { value } }
  func set(_ newValue: Value) { lock.withLock { value = newValue } }
}
