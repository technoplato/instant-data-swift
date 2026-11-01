import Foundation
import SQLite3
import os

// History:
// - 2026-10-31: the pages each table, index and statement writes, minute by minute (#1510). A phone's local save wrote
//   102 KB and the store's meters said only which store call wrote it; the write-ahead log, read page by page on a
//   copy, put the save at 24.4 pages across 17 b-trees. This records the same reading in the running app.

/// What a store's SQLite wrote, page by page: by b-tree (a table, an index, or SQLite's own pages), by write statement,
/// and by the store call that committed it (#1510).
///
/// The file meter's VFS (``InstantSQLiteFileMeter``) sees every page SQLite writes to the write-ahead log and every
/// page a checkpoint copies into the database file. Which b-tree a page belongs to is learned from the pages SQLite
/// reads and writes anyway: a b-tree's root is in `sqlite_schema`, and each interior page names its children. Each
/// write statement's rows come from SQLite's change count, and the b-trees it writes from its `EXPLAIN`, once per
/// statement. Counts only: no page is copied, nothing is read that SQLite did not read, and a page the recorder cannot
/// place counts as ``InstantSQLiteWriteRecord/unnamed``.
///
///     let before = InstantSQLiteWriteRecorder.snapshot()
///     // ... a minute of writes
///     let minute = InstantSQLiteWriteRecorder.snapshot().subtracting(before)
///     minute.btrees["instant_outbox_write_keys_lookup_idx"]?.logPages
/// Switches that turn the recorder, or one of its parts, off, to measure what each part costs a write (#1510:
/// perf-gate-1491's bisect put the recorder at +0.26 ms a write in the tight loop). Read once, from the environment:
/// `INSTANT_SQLITE_WRITE_RECORDER=0` attaches none; `..._READS=0` learns nothing from the pages SQLite reads;
/// `..._STATEMENTS=0` counts no write statement; `..._WRITES=0` names no page the log takes.
enum InstantSQLiteWriteRecorderSwitches {
  private static let environment = ProcessInfo.processInfo.environment
  static let isOn = environment["INSTANT_SQLITE_WRITE_RECORDER"] != "0"
  static let learnsFromReads = environment["INSTANT_SQLITE_WRITE_RECORDER_READS"] != "0"
  static let countsStatements = environment["INSTANT_SQLITE_WRITE_RECORDER_STATEMENTS"] != "0"
  static let namesWrites = environment["INSTANT_SQLITE_WRITE_RECORDER_WRITES"] != "0"
}

public enum InstantSQLiteWriteRecorder {
  /// Every store's counts since the process started, a closed store's included.
  public static func snapshot() -> InstantSQLiteWriteRecord {
    let (open, closed) = registry.withLock { ($0.recorders.values.map { $0 }, $0.closed) }
    return open.reduce(closed) { $0.adding($1.record()) }
  }

  /// A recorder for the database at `path`, which every connection SQLite opens to it through the file meter's VFS
  /// reports to, its log included. Attach before the first connection opens; ``InstantSQLiteDatabaseWriteRecorder/
  /// detach()`` when the store closes. Nil when the meter's VFS is unavailable.
  static func attach(databaseAt path: String) -> InstantSQLiteDatabaseWriteRecorder? {
    guard InstantSQLiteWriteRecorderSwitches.isOn, InstantSQLiteFileMeter.registeredVFSName() != nil else { return nil }
    let name = InstantSQLiteFileMeter.fullPathname(path) ?? path
    let recorder = InstantSQLiteDatabaseWriteRecorder(databaseName: name)
    registry.withLock { $0.recorders[name] = recorder }
    return recorder
  }

  /// The recorder a file SQLite opens reports to: the database's own, or its log's (`<database>-wal`).
  static func recorder(forFileNamed name: String, isLog: Bool) -> InstantSQLiteDatabaseWriteRecorder? {
    let database = isLog ? String(name.dropLast(4)) : name
    guard !isLog || name.hasSuffix("-wal") else { return nil }
    return registry.withLock { $0.recorders[database] }
  }

  fileprivate static func detach(_ recorder: InstantSQLiteDatabaseWriteRecorder) {
    let record = recorder.record()
    registry.withLock { registry in
      if registry.recorders[recorder.databaseName] === recorder {
        registry.recorders[recorder.databaseName] = nil
      }
      registry.closed = registry.closed.adding(record)
    }
  }

  private struct Registry: Sendable {
    var recorders: [String: InstantSQLiteDatabaseWriteRecorder] = [:]
    /// What closed stores recorded, so a snapshot's counts never go back.
    var closed = InstantSQLiteWriteRecord()
  }

  private static let registry = OSAllocatedUnfairLock(initialState: Registry())
}

/// What ``InstantSQLiteWriteRecorder`` counted (#1510).
public struct InstantSQLiteWriteRecord: Sendable, Equatable {
  /// One b-tree's pages.
  public struct BTree: Sendable, Equatable {
    /// The table the b-tree stores or indexes; for SQLite's own pages, their name (``InstantSQLiteWriteRecord/headerPage``).
    public var table: String
    /// Whether the b-tree is an index: an `INDEX`, or the one SQLite keeps for a `UNIQUE` or `PRIMARY KEY` constraint.
    public var isIndex: Bool
    /// Pages written to the write-ahead log, each one frame (the page and a 24-byte header).
    public var logPages: Int
    /// Of ``logPages``, overflow pages: the part of a row too large for its leaf.
    public var overflowLogPages: Int
    /// Pages a checkpoint copied from the log into the database file.
    public var checkpointPages: Int

    public init(table: String, isIndex: Bool = false, logPages: Int = 0, overflowLogPages: Int = 0, checkpointPages: Int = 0) {
      self.table = table
      self.isIndex = isIndex
      self.logPages = logPages
      self.overflowLogPages = overflowLogPages
      self.checkpointPages = checkpointPages
    }
  }

  /// One write statement's runs, rows and pages.
  public struct Statement: Sendable, Equatable {
    /// Times it ran: steps to its end, each followed by a reset.
    public var runs: Int
    /// Rows it inserted, updated or deleted, its foreign-key actions' included.
    public var rows: Int
    /// Log pages of the b-trees it wrote that no other statement of the same transaction wrote.
    public var soleLogPages: Int
    /// Log pages of the b-trees it wrote together with other statements of the same transaction; each of them counts
    /// these, so they add up to more than the log took.
    public var sharedLogPages: Int
    /// The b-trees it writes, sorted: its `EXPLAIN`'s `OpenWrite`s, the statement's shape on disk.
    public var btrees: [String]

    public init(runs: Int = 0, rows: Int = 0, soleLogPages: Int = 0, sharedLogPages: Int = 0, btrees: [String] = []) {
      self.runs = runs
      self.rows = rows
      self.soleLogPages = soleLogPages
      self.sharedLogPages = sharedLogPages
      self.btrees = btrees
    }
  }

  /// By b-tree: a table's or an index's name, or one of SQLite's own pages (``headerPage``, ``freeList``, ``unnamed``).
  public var btrees: [String: BTree]
  /// By the statement's SQL, its runs of placeholders collapsed (`VALUES (?…)`), at most ``statementLimit`` of them
  /// and the rest under ``otherStatements``; ``noStatement`` holds the pages no recorded statement wrote.
  public var statements: [String: Statement]
  /// Log pages by the store call that committed them (`saveLocalMutation(...)`) and b-tree.
  public var calls: [String: [String: Int]]
  /// Write transactions that committed.
  public var commits: Int

  /// The database file's first page: its header (the free-page count, the file's size) and `sqlite_schema`'s root.
  public static let headerPage = "(page 1)"
  /// The free list's trunk pages, written when pages are freed or taken back into use.
  public static let freeList = "(free list)"
  /// Pages the recorder could not place.
  public static let unnamed = "(unnamed)"
  /// The statements past ``statementLimit``.
  public static let otherStatements = "(other statements)"
  /// Pages no recorded statement's b-trees hold: the header page, the free list, an unnamed page.
  public static let noStatement = "(no statement)"
  /// The store calls past ``callLimit``.
  public static let otherCalls = "(other calls)"
  /// The distinct statements a record names one by one.
  public static let statementLimit = 256
  /// The distinct store calls a record names one by one.
  public static let callLimit = 64

  public init(
    btrees: [String: BTree] = [:],
    statements: [String: Statement] = [:],
    calls: [String: [String: Int]] = [:],
    commits: Int = 0
  ) {
    self.btrees = btrees
    self.statements = statements
    self.calls = calls
    self.commits = commits
  }

  /// Every b-tree's log pages.
  public var logPages: Int { btrees.values.reduce(0) { $0 + $1.logPages } }

  /// Every b-tree's checkpoint pages.
  public var checkpointPages: Int { btrees.values.reduce(0) { $0 + $1.checkpointPages } }

  /// What was counted after `earlier`; a count that went down counts from zero.
  public func subtracting(_ earlier: Self) -> Self {
    func delta(_ new: Int, _ old: Int) -> Int { new >= old ? new - old : new }
    var btrees: [String: BTree] = [:]
    for (name, now) in self.btrees {
      let then = earlier.btrees[name]
      let difference = BTree(
        table: now.table,
        isIndex: now.isIndex,
        logPages: delta(now.logPages, then?.logPages ?? 0),
        overflowLogPages: delta(now.overflowLogPages, then?.overflowLogPages ?? 0),
        checkpointPages: delta(now.checkpointPages, then?.checkpointPages ?? 0)
      )
      if difference.logPages > 0 || difference.checkpointPages > 0 { btrees[name] = difference }
    }
    var statements: [String: Statement] = [:]
    for (sql, now) in self.statements {
      let then = earlier.statements[sql]
      let difference = Statement(
        runs: delta(now.runs, then?.runs ?? 0),
        rows: delta(now.rows, then?.rows ?? 0),
        soleLogPages: delta(now.soleLogPages, then?.soleLogPages ?? 0),
        sharedLogPages: delta(now.sharedLogPages, then?.sharedLogPages ?? 0),
        btrees: now.btrees
      )
      if difference.runs > 0 || difference.rows > 0 || difference.soleLogPages > 0 || difference.sharedLogPages > 0 {
        statements[sql] = difference
      }
    }
    var calls: [String: [String: Int]] = [:]
    for (call, pages) in self.calls {
      var differences: [String: Int] = [:]
      for (name, count) in pages {
        let difference = delta(count, earlier.calls[call]?[name] ?? 0)
        if difference > 0 { differences[name] = difference }
      }
      if !differences.isEmpty { calls[call] = differences }
    }
    return Self(btrees: btrees, statements: statements, calls: calls, commits: delta(commits, earlier.commits))
  }

  /// Both records' counts summed: two stores', or a closed store's and an open one's.
  public func adding(_ other: Self) -> Self {
    var sum = self
    for (name, counts) in other.btrees {
      var total = sum.btrees[name] ?? BTree(table: counts.table, isIndex: counts.isIndex)
      total.logPages += counts.logPages
      total.overflowLogPages += counts.overflowLogPages
      total.checkpointPages += counts.checkpointPages
      sum.btrees[name] = total
    }
    for (sql, counts) in other.statements {
      var total = sum.statements[sql] ?? Statement(btrees: counts.btrees)
      total.runs += counts.runs
      total.rows += counts.rows
      total.soleLogPages += counts.soleLogPages
      total.sharedLogPages += counts.sharedLogPages
      sum.statements[sql] = total
    }
    for (call, pages) in other.calls {
      sum.calls[call, default: [:]].merge(pages, uniquingKeysWith: +)
    }
    sum.commits += other.commits
    return sum
  }
}

/// One database's recorder (#1510): the file meter's VFS hands it the pages SQLite reads and writes for the database
/// and its log, the store hands it each write statement and the store call around each commit.
///
/// Which b-tree a page belongs to is one byte a page (``State/owners``): a root from `sqlite_schema`; each interior
/// page SQLite reads or writes names its children; a leaf names its rows' overflow pages, an overflow page the next one;
/// page 1 names the free list's first trunk page, a trunk page the next one. A commit's pages are placed together, the
/// links its own pages carry first, so a page taken from the free list and written into a b-tree in the same commit is
/// counted under its new b-tree.
// SAFETY: every mutable field is inside `state`, one `OSAllocatedUnfairLock`; `databaseName` is a `let`.
final class InstantSQLiteDatabaseWriteRecorder: @unchecked Sendable {
  let databaseName: String
  private let state = OSAllocatedUnfairLock(initialState: State())
  /// A read-only connection of the recorder's own, opened at the first `EXPLAIN` and closed at ``detach()``: on the
  /// store's writer an `EXPLAIN` of a write would reset `sqlite3_changes()`, which the store reads after a statement to
  /// check what it changed.
  private let explainer = OSAllocatedUnfairLock<OpaquePointer?>(uncheckedState: nil)

  init(databaseName: String) {
    self.databaseName = databaseName
  }

  /// What this database's connections wrote since it was attached.
  func record() -> InstantSQLiteWriteRecord {
    state.withLock { $0.record() }
  }

  /// The bytes the recorder's own collections hold (#1285): its bound, checked by its stress test.
  func retainedBytesForTesting() -> Int {
    state.withLock { $0.retainedBytes }
  }

  /// Stops counting this database's new connections; what it counted stays in ``InstantSQLiteWriteRecorder/snapshot()``.
  func detach() {
    InstantSQLiteWriteRecorder.detach(self)
    explainer.withLockUnchecked { connection in
      sqlite3_close_v2(connection)
      connection = nil
    }
  }

  // MARK: The store's side

  /// Reads the b-trees' roots from `sqlite_schema` on `connection`, when the schema changed since the last read.
  func reloadSchema(from connection: OpaquePointer?) {
    guard let connection else { return }
    let version = Self.integer("PRAGMA main.schema_version", on: connection)
    guard state.withLock({ $0.schemaVersion != version }) else { return }
    var rows: [State.SchemaRow] = []
    Self.query(
      "SELECT name, tbl_name, type, rootpage FROM main.sqlite_schema WHERE rootpage > 0",
      on: connection
    ) { statement in
      guard let name = sqlite3_column_text(statement, 0), let table = sqlite3_column_text(statement, 1),
        let type = sqlite3_column_text(statement, 2)
      else { return }
      rows.append(
        State.SchemaRow(
          name: String(cString: name),
          table: String(cString: table),
          isIndex: String(cString: type) == "index",
          rootPage: UInt32(truncatingIfNeeded: sqlite3_column_int64(statement, 3))
        )
      )
    }
    let schema = rows
    state.withLock { $0.loadSchema(schema, version: version) }
  }

  /// The store call whose write transaction begins on the writer connection.
  func beginTransaction(call: StaticString) {
    state.withLock { $0.beginTransaction(call: call) }
  }

  /// The write transaction ended, committed or rolled back.
  func endTransaction() {
    state.withLock { $0.endTransaction() }
  }

  /// The shape `sql` is recorded under (``InstantSQLiteWriteRecord/shape(of:)``); the b-trees `statement` writes are
  /// read from its `EXPLAIN` the first time a shape is seen.
  func shape(forSQL sql: String, statement: OpaquePointer) -> Int32 {
    let shape = InstantSQLiteWriteRecord.shape(of: sql)
    if let known = state.withLock({ $0.shapeIDs[shape] ?? ($0.hasRoomForShape ? nil : State.otherStatementsID) }) {
      return known
    }
    let roots = writtenRoots(of: sql)
    return state.withLock { $0.addShape(shape, sql: sql, writtenRoots: roots) }
  }

  /// A write statement of `shape` finished a use: it ran `runs` times and changed `rows` rows.
  func statementFinished(shape: Int32, runs: Int, rows: Int) {
    // A statement whose table the recorder's connection could not see yet (made in the writer's open transaction) is
    // explained again at a later use, a few times at most.
    if let sql = state.withLock({ $0.sqlToExplain(shape: Int(shape)) }) {
      let roots = writtenRoots(of: sql)
      state.withLock { $0.explained(shape: Int(shape), writtenRoots: roots) }
    }
    state.withLock { $0.statementFinished(shape: Int(shape), runs: runs, rows: rows) }
  }

  // MARK: The VFS's side

  /// SQLite wrote `count` bytes at `offset` of the database's log.
  func logWrite(_ bytes: UnsafeRawPointer, count: Int, offset: Int64) {
    guard InstantSQLiteWriteRecorderSwitches.namesWrites else { return }
    let buffer = UnsafeRawBufferPointer(start: bytes, count: max(0, count))
    state.withLockUnchecked { $0.logWrite(buffer, offset: Int(offset)) }
  }

  /// SQLite read `count` bytes at `offset` of the database's log, through `file`.
  func logRead(_ bytes: UnsafeRawPointer, count: Int, offset: Int64, file: UnsafeMutablePointer<sqlite3_file>) {
    guard InstantSQLiteWriteRecorderSwitches.learnsFromReads else { return }
    let buffer = UnsafeRawBufferPointer(start: bytes, count: max(0, count))
    // #1510: a leaf, an overflow page or a free page read teaches nothing the commit that writes it will not; only an
    // interior page (its children), page 1 and the log's header are worth the lock. Checked before taking it.
    guard Self.isWorthLearning(buffer, offset: offset) else { return }
    let frame = state.withLockUnchecked { $0.logRead(buffer, offset: Int(offset)) }
    // A frame an earlier process wrote: its header, read once, says which page this is.
    guard case let .unknownFrame(index, headerOffset) = frame else { return }
    var header = [UInt8](repeating: 0, count: 8)
    let result = header.withUnsafeMutableBytes {
      file.pointee.pMethods.pointee.xRead(file, $0.baseAddress, 8, sqlite3_int64(headerOffset))
    }
    guard result == SQLITE_OK else { return }
    let page = header.withUnsafeBytes { State.bigEndian32($0, 0) }
    state.withLockUnchecked { $0.learnFrame(index: index, page: page, content: buffer) }
  }

  /// The log was truncated (a checkpoint restarted it).
  func logTruncated() {
    state.withLock { $0.resetFrames() }
  }

  /// SQLite read `count` bytes at `offset` of the database file (from the file, or mapped).
  func databaseRead(_ bytes: UnsafeRawPointer, count: Int, offset: Int64) {
    guard InstantSQLiteWriteRecorderSwitches.learnsFromReads else { return }
    let buffer = UnsafeRawBufferPointer(start: bytes, count: max(0, count))
    guard offset == 0 || Self.isWorthLearning(buffer, offset: offset) else { return }
    state.withLockUnchecked { $0.databaseRead(buffer, offset: Int(offset)) }
  }

  /// Whether a page SQLite read can teach the recorder anything (#1510): an interior b-tree page (it names its children),
  /// page 1 (its header names the free list) or a log header or whole frame (they name pages). A leaf's links are learned
  /// when a commit writes it; reading every leaf's cells cost a prune of a 40,000-fact store more than its gate allows
  /// (InstantPruneCostTests).
  static func isWorthLearning(_ bytes: UnsafeRawBufferPointer, offset: Int64) -> Bool {
    guard !bytes.isEmpty else { return false }
    if offset == 0 { return true }
    let first = bytes[0]
    if first == 2 || first == 5 { return true }
    // A whole log frame (SQLite reads frames whole when it rebuilds the log's index): its 24-byte header, then the page.
    if bytes.count > 24 + 512, (offset - 32) % Int64(bytes.count) == 0 { return true }
    // Page 1 read from the log: "SQLite format 3\0" then its header.
    return bytes.count >= 16 && bytes[0] == 0x53 && bytes[1] == 0x51 && bytes[2] == 0x4C && bytes[15] == 0
  }

  /// A checkpoint wrote `count` bytes at `offset` of the database file.
  func databaseWrite(count: Int, offset: Int64) {
    state.withLock { $0.databaseWrite(count: count, offset: Int(offset)) }
  }

  // MARK: SQLite, read directly

  /// The `main` b-trees' roots the statement `sql` opens for writing: its `EXPLAIN`'s `OpenWrite`s, its trigger and
  /// foreign-key programs' included, on the recorder's own read-only connection. Nil when it does not explain there.
  private func writtenRoots(of sql: String) -> [UInt32]? {
    explainer.withLockUnchecked { connection -> [UInt32]? in
      if connection == nil {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        // The system's VFS: the recorder's own reads are not the store's.
        if sqlite3_open_v2(databaseName, &opened, flags, nil) == SQLITE_OK {
          connection = opened
        } else {
          sqlite3_close_v2(opened)
          return nil
        }
      }
      guard let connection else { return nil }
      var roots: Set<UInt32> = []
      let explained = Self.query("EXPLAIN " + sql, on: connection) { statement in
        guard let opcode = sqlite3_column_text(statement, 1), String(cString: opcode) == "OpenWrite" else { return }
        // P3 is the database (0 is `main`); P5's OPFLAG_P2ISREG (0x02) means P2 names a register, not a root page.
        guard sqlite3_column_int64(statement, 4) == 0, sqlite3_column_int64(statement, 6) & 0x02 == 0 else { return }
        roots.insert(UInt32(truncatingIfNeeded: sqlite3_column_int64(statement, 3)))
      }
      return explained ? roots.sorted() : nil
    }
  }

  private static func integer(_ sql: String, on connection: OpaquePointer) -> Int64 {
    var value: Int64 = -1
    query(sql, on: connection) { value = sqlite3_column_int64($0, 0) }
    return value
  }

  /// Runs `sql` on `connection`, each row to `row`; false when it does not prepare.
  @discardableResult
  private static func query(_ sql: String, on connection: OpaquePointer, row: (OpaquePointer) -> Void) -> Bool {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
      sqlite3_finalize(statement)
      return false
    }
    defer { sqlite3_finalize(statement) }
    while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    return true
  }
}

extension InstantSQLiteDatabaseWriteRecorder {
  /// Everything one database's recorder keeps: counts, and what it learned of the file. Every collection is bounded:
  /// one byte a page up to ``maximumPages``, a log frame's page up to ``maximumFrames``, a commit's pages up to
  /// ``maximumPendingPages``, ``maximumBTrees`` b-trees, ``InstantSQLiteWriteRecord/statementLimit`` statements and
  /// ``InstantSQLiteWriteRecord/callLimit`` store calls.
  struct State: Sendable {
    // An owner byte: 0 unnamed, 1 page 1, 2 the free list, 3 sqlite_schema, then the schema's b-trees; the high bit
    // marks an overflow page of the b-tree the low bits name.
    static let unnamedID: UInt8 = 0
    static let headerID: UInt8 = 1
    static let freeListID: UInt8 = 2
    static let schemaTableID: UInt8 = 3
    static let overflowBit: UInt8 = 0x80
    /// 127, so the highest owner byte (an overflow page of b-tree 126) stays below the unresolved mark, 0xFF.
    static let maximumBTrees = 127
    static let unresolved: UInt8 = 0xFF
    static let maximumPages = 1 << 21
    static let maximumFrames = 1 << 14
    static let maximumPendingPages = 8_192
    static let maximumPendingLinks = 1 << 16
    /// A link's high bit: the link names an overflow page.
    static let overflowLink: UInt32 = 1 << 31
    static let noStatementID = 0
    static let otherStatementsID: Int32 = 1
    static let otherCallsID = InstantSQLiteWriteRecord.callLimit

    struct SchemaRow: Sendable {
      var name: String
      var table: String
      var isIndex: Bool
      var rootPage: UInt32
    }

    struct BTree: Sendable {
      var name: String
      var table: String
      var isIndex: Bool
      var logPages = 0
      var overflowLogPages = 0
      var checkpointPages = 0
    }

    struct Shape: Sendable {
      var sql: String
      var btreeIDs: [UInt8]
      /// The statement's own SQL while its b-trees are unknown (it did not explain yet), and the tries left.
      var unexplainedSQL: String?
      var explainTriesLeft = 0
      var runs = 0
      var rows = 0
      var soleLogPages = 0
      var sharedLogPages = 0
    }

    /// A page the commit being written wrote: its links are `links[linkStart..<linkStart + linkCount]`.
    struct PendingPage: Sendable {
      var page: UInt32
      var linkStart: Int32
      var linkCount: Int32
      /// A b-tree page (its links are children and overflow pages), page 1 (the free list's first trunk too), or another
      /// page (an overflow or trunk page: its one link is the next page).
      var isTreePage: Bool
      var freeListTrunk: UInt32
    }

    var schemaVersion: Int64 = -2
    var btrees: [BTree] = [
      BTree(name: InstantSQLiteWriteRecord.unnamed, table: InstantSQLiteWriteRecord.unnamed, isIndex: false),
      BTree(name: InstantSQLiteWriteRecord.headerPage, table: InstantSQLiteWriteRecord.headerPage, isIndex: false),
      BTree(name: InstantSQLiteWriteRecord.freeList, table: InstantSQLiteWriteRecord.freeList, isIndex: false),
      BTree(name: "sqlite_schema", table: "sqlite_schema", isIndex: false),
    ]
    var btreeIDs: [String: UInt8] = [:]
    var rootIDs: [UInt32: UInt8] = [:]
    var owners: [UInt8] = []

    var pageSize = 4_096
    /// Each log frame's page in the log's current generation; 0 when unknown.
    var framePages: [UInt32] = []
    /// A frame whose header came in its own write: its index, page and commit size, for the page that follows.
    var headerOnly: (index: Int, page: UInt32, commit: UInt32)?

    var pending: [PendingPage] = []
    var links: [UInt32] = []
    var resolved: [UInt8] = []
    var pendingIndex: [UInt32: Int] = [:]
    var parentOf: [UInt32: (index: Int, isOverflow: Bool)] = [:]
    var previousOf: [UInt32: Int] = [:]

    var shapes: [Shape] = [
      Shape(sql: InstantSQLiteWriteRecord.noStatement, btreeIDs: []),
      Shape(sql: InstantSQLiteWriteRecord.otherStatements, btreeIDs: []),
    ]
    var shapeIDs: [String: Int32] = [:]
    var transactionStatements: [(shape: Int, rows: Int)] = []
    /// Pages a commit outside a store transaction wrote, for the statement whose step committed them.
    var unclaimedPages: [Int] = Array(repeating: 0, count: State.maximumBTrees)
    var hasUnclaimedPages = false

    var callNames: [String] = []
    /// By the call name's address: a store call's name is a static string, so one address is one call.
    var callIDs: [UInt: Int] = [:]
    var callPages: [[Int]] = []
    var currentCall: Int?
    var commits = 0

    var hasRoomForShape: Bool { shapes.count < InstantSQLiteWriteRecord.statementLimit + 2 }

    /// The bytes the collections hold, their capacity counted (strings and dictionary entries roughly).
    var retainedBytes: Int {
      owners.capacity + framePages.capacity * 4 + pending.capacity * MemoryLayout<PendingPage>.stride
        + links.capacity * 4 + resolved.capacity + pagesByID.capacity * 8 + unclaimedPages.capacity * 8
        + otherCallPages.capacity * 8 + callPages.reduce(0) { $0 + $1.capacity * 8 }
        + (pendingIndex.capacity + previousOf.capacity + parentOf.capacity + rootIDs.capacity) * 24
        + shapes.reduce(0) { $0 + 96 + $1.sql.utf8.count + $1.btreeIDs.capacity + ($1.unexplainedSQL?.utf8.count ?? 0) }
        + shapeIDs.reduce(0) { $0 + 40 + $1.key.utf8.count } + btrees.count * 96 + callNames.count * 64
    }

    // MARK: Schema

    mutating func loadSchema(_ rows: [SchemaRow], version: Int64) {
      schemaVersion = version
      rootIDs.removeAll(keepingCapacity: true)
      for row in rows where row.rootPage > 1 {
        var id = btreeIDs[row.name]
        if id == nil, btrees.count < Self.maximumBTrees {
          id = UInt8(btrees.count)
          btreeIDs[row.name] = id
          btrees.append(BTree(name: row.name, table: row.table, isIndex: row.isIndex))
        }
        guard let id else { continue }
        rootIDs[row.rootPage] = id
        setOwner(row.rootPage, id)
      }
    }

    // MARK: Statements and transactions

    mutating func addShape(_ shape: String, sql: String, writtenRoots: [UInt32]?) -> Int32 {
      if let known = shapeIDs[shape] { return known }
      guard hasRoomForShape else { return Self.otherStatementsID }
      let id = Int32(shapes.count)
      shapes.append(Shape(sql: shape, btreeIDs: []))
      shapeIDs[shape] = id
      if let writtenRoots {
        explained(shape: Int(id), writtenRoots: writtenRoots)
      } else {
        shapes[Int(id)].unexplainedSQL = sql
        shapes[Int(id)].explainTriesLeft = 3
      }
      return id
    }

    /// The SQL to explain again before this use of `shape` counts, if its b-trees are still unknown.
    mutating func sqlToExplain(shape: Int) -> String? {
      guard shapes.indices.contains(shape), let sql = shapes[shape].unexplainedSQL else { return nil }
      guard shapes[shape].explainTriesLeft > 0 else {
        shapes[shape].unexplainedSQL = nil
        return nil
      }
      shapes[shape].explainTriesLeft -= 1
      return sql
    }

    mutating func explained(shape: Int, writtenRoots: [UInt32]?) {
      guard shapes.indices.contains(shape), let writtenRoots else { return }
      shapes[shape].btreeIDs = Set(writtenRoots.compactMap { rootIDs[$0] }).sorted()
      shapes[shape].unexplainedSQL = nil
    }

    mutating func statementFinished(shape: Int, runs: Int, rows: Int) {
      guard shapes.indices.contains(shape) else { return }
      shapes[shape].runs += runs
      shapes[shape].rows += rows
      guard rows > 0 else { return }
      if currentCall != nil {
        if let index = transactionStatements.firstIndex(where: { $0.shape == shape }) {
          transactionStatements[index].rows += rows
        } else if transactionStatements.count < 64 {
          transactionStatements.append((shape, rows))
        }
      } else if hasUnclaimedPages {
        // An autocommit statement: its step committed before it came back.
        for id in unclaimedPages.indices where unclaimedPages[id] > 0 {
          shapes[shape].soleLogPages += unclaimedPages[id]
          unclaimedPages[id] = 0
        }
        hasUnclaimedPages = false
      }
    }

    mutating func beginTransaction(call: StaticString) {
      flushUnclaimedPages()
      let key = UInt(bitPattern: call.utf8Start)
      if let known = callIDs[key] {
        currentCall = known
      } else if callNames.count < InstantSQLiteWriteRecord.callLimit {
        callIDs[key] = callNames.count
        currentCall = callNames.count
        callNames.append(call.description)
        callPages.append(Array(repeating: 0, count: Self.maximumBTrees))
      } else {
        currentCall = Self.otherCallsID
      }
      transactionStatements.removeAll(keepingCapacity: true)
    }

    mutating func endTransaction() {
      // Frames a transaction wrote before it rolled back (its page cache spilled) were written all the same.
      if !pending.isEmpty { resolvePending(committed: false) }
      currentCall = nil
      transactionStatements.removeAll(keepingCapacity: true)
    }

    private mutating func flushUnclaimedPages() {
      guard hasUnclaimedPages else { return }
      for id in unclaimedPages.indices where unclaimedPages[id] > 0 {
        shapes[Self.noStatementID].soleLogPages += unclaimedPages[id]
        unclaimedPages[id] = 0
      }
      hasUnclaimedPages = false
    }

    // MARK: The log

    mutating func resetFrames() {
      if !framePages.isEmpty { framePages.removeAll(keepingCapacity: true) }
      headerOnly = nil
    }

    mutating func logWrite(_ bytes: UnsafeRawBufferPointer, offset: Int) {
      var position = 0
      if offset == 0, bytes.count >= 32 {
        // The log's header: a new generation of frames, and the page size.
        let size = Int(Self.bigEndian32(bytes, 8))
        if size >= 512, size <= 65_536, size & (size - 1) == 0 { pageSize = size }
        resetFrames()
        position = 32
      }
      let frameSize = 24 + pageSize
      if let header = headerOnly, offset == 32 + header.index * frameSize + 24, bytes.count >= pageSize {
        // The page of a frame whose header came in the write before.
        headerOnly = nil
        written(page: header.page, content: UnsafeRawBufferPointer(rebasing: bytes[0..<pageSize]))
        if header.commit != 0 { resolvePending(committed: true) }
        return
      }
      guard offset + position >= 32 else { return }
      // The first frame header at or after the write's start.
      var frameStart = offset + position
      let remainder = (frameStart - 32) % frameSize
      if remainder != 0 { frameStart += frameSize - remainder }
      while frameStart + 24 <= offset + bytes.count {
        let local = frameStart - offset
        let page = Self.bigEndian32(bytes, local)
        let commit = Self.bigEndian32(bytes, local + 4)
        let index = (frameStart - 32) / frameSize
        setFramePage(index, page)
        if local + 24 + pageSize <= bytes.count {
          written(page: page, content: UnsafeRawBufferPointer(rebasing: bytes[(local + 24)..<(local + 24 + pageSize)]))
          if commit != 0 { resolvePending(committed: true) }
        } else {
          headerOnly = (index, page, commit)
        }
        frameStart += frameSize
      }
    }

    enum LogReadResult {
      case done
      /// A frame's page, read without its header, from a frame this process did not write.
      case unknownFrame(index: Int, headerOffset: Int)
    }

    mutating func logRead(_ bytes: UnsafeRawBufferPointer, offset: Int) -> LogReadResult {
      let frameSize = 24 + pageSize
      if offset == 0, bytes.count >= 32 {
        let size = Int(Self.bigEndian32(bytes, 8))
        if size >= 512, size <= 65_536, size & (size - 1) == 0 { pageSize = size }
        return .done
      }
      guard offset >= 32 else { return .done }
      if bytes.count >= 24 + pageSize, (offset - 32) % frameSize == 0 {
        // A whole frame (SQLite reads the log this way when it rebuilds its index).
        let index = (offset - 32) / frameSize
        let page = Self.bigEndian32(bytes, 0)
        setFramePage(index, page)
        learn(page: page, content: UnsafeRawBufferPointer(rebasing: bytes[24..<(24 + pageSize)]))
        return .done
      }
      guard bytes.count >= pageSize, (offset - 32 - 24) % frameSize == 0 else { return .done }
      let index = (offset - 32 - 24) / frameSize
      let page = index < framePages.count ? framePages[index] : 0
      if page == 0 { return .unknownFrame(index: index, headerOffset: offset - 24) }
      learn(page: page, content: UnsafeRawBufferPointer(rebasing: bytes[0..<pageSize]))
      return .done
    }

    mutating func learnFrame(index: Int, page: UInt32, content: UnsafeRawBufferPointer) {
      guard page != 0, content.count >= pageSize else { return }
      setFramePage(index, page)
      learn(page: page, content: UnsafeRawBufferPointer(rebasing: content[0..<pageSize]))
    }

    private mutating func setFramePage(_ index: Int, _ page: UInt32) {
      guard index >= 0, index < Self.maximumFrames else { return }
      if index >= framePages.count {
        framePages.append(contentsOf: repeatElement(0, count: index + 1 - framePages.count))
      }
      framePages[index] = page
    }

    // MARK: The database file

    mutating func databaseRead(_ bytes: UnsafeRawBufferPointer, offset: Int) {
      if offset == 0, bytes.count >= 100 {
        let size = Int(Self.bigEndian16(bytes, 16))
        let pageSize = size == 1 ? 65_536 : size
        if pageSize >= 512, pageSize & (pageSize - 1) == 0 { self.pageSize = pageSize }
      }
      guard bytes.count >= pageSize, offset % pageSize == 0 else { return }
      learn(page: UInt32(truncatingIfNeeded: offset / pageSize + 1), content: UnsafeRawBufferPointer(rebasing: bytes[0..<pageSize]))
    }

    mutating func databaseWrite(count: Int, offset: Int) {
      guard count >= pageSize, offset % pageSize == 0 else { return }
      let first = offset / pageSize + 1
      for page in first..<(first + count / pageSize) {
        let pageOwner = page == 1 ? Self.headerID : self.owner(UInt32(truncatingIfNeeded: page))
        btrees[Int(pageOwner & ~Self.overflowBit)].checkpointPages += 1
      }
    }

    // MARK: Learning from pages SQLite reads

    /// What a page SQLite read says of the pages it points to, when its own b-tree is known.
    private mutating func learn(page: UInt32, content: UnsafeRawBufferPointer) {
      if page == 1 {
        let trunk = Self.bigEndian32(content, 32)
        if trunk > 1 { setOwner(trunk, Self.freeListID) }
      }
      let pageOwner = page == 1 ? Self.schemaTableID : self.owner(page)
      guard pageOwner != Self.unnamedID, pageOwner & Self.overflowBit == 0, pageOwner != Self.freeListID else { return }
      // Only an interior page's children: a leaf's overflow pages are learned when a commit writes the leaf.
      let header = page == 1 ? 100 : 0
      guard content.count > header, content[header] == 2 || content[header] == 5 else { return }
      let start = links.count
      Self.appendLinks(of: content, isPageOne: page == 1, pageSize: pageSize, to: &links)
      for link in links[start...] {
        let target = link & ~Self.overflowLink
        setOwner(target, link & Self.overflowLink != 0 ? pageOwner | Self.overflowBit : pageOwner)
      }
      links.removeSubrange(start...)
    }

    // MARK: A commit's pages

    private mutating func written(page: UInt32, content: UnsafeRawBufferPointer) {
      if pending.count >= Self.maximumPendingPages || links.count >= Self.maximumPendingLinks - 4_096 {
        // A transaction past the bound is placed in parts: a page whose parent comes in a later part keeps the b-tree
        // it had.
        resolvePending(committed: false)
      }
      let start = links.count
      let header = page == 1 ? 100 : 0
      let type = content.count > header ? content[header] : 0
      let isTreePage = type == 2 || type == 5 || type == 10 || type == 13
      var trunk: UInt32 = 0
      if page == 1 { trunk = Self.bigEndian32(content, 32) }
      if isTreePage {
        Self.appendLinks(of: content, isPageOne: page == 1, pageSize: pageSize, to: &links)
      } else if page != 1 {
        let next = Self.bigEndian32(content, 0)
        if next > 1 { links.append(next) }
      }
      pending.append(
        PendingPage(
          page: page,
          linkStart: Int32(start),
          linkCount: Int32(links.count - start),
          isTreePage: isTreePage || page == 1,
          freeListTrunk: trunk
        )
      )
    }

    /// Places the pending pages, counts them and forgets them.
    mutating func resolvePending(committed: Bool) {
      guard !pending.isEmpty else { return }
      pendingIndex.removeAll(keepingCapacity: true)
      parentOf.removeAll(keepingCapacity: true)
      previousOf.removeAll(keepingCapacity: true)
      var freeListHead: UInt32 = 0
      for (index, entry) in pending.enumerated() {
        pendingIndex[entry.page] = index
        if entry.page == 1, entry.freeListTrunk > 1 { freeListHead = entry.freeListTrunk }
        let range = Int(entry.linkStart)..<Int(entry.linkStart + entry.linkCount)
        if entry.isTreePage {
          for link in links[range] {
            parentOf[link & ~Self.overflowLink] = (index, link & Self.overflowLink != 0)
          }
        } else if let next = links[range].first {
          previousOf[next] = index
        }
      }
      resolved.removeAll(keepingCapacity: true)
      resolved.append(contentsOf: repeatElement(Self.unresolved, count: pending.count))
      var path: [Int] = []
      for index in pending.indices where resolved[index] == Self.unresolved {
        // Up through the commit's own links to a page whose b-tree is known, then down again.
        path.removeAll(keepingCapacity: true)
        var current = index
        var steps = 0
        while true {
          steps += 1
          if resolved[current] != Self.unresolved { break }
          let page = pending[current].page
          if page == 1 {
            resolved[current] = Self.headerID
            break
          }
          if let root = rootIDs[page] {
            resolved[current] = root
            break
          }
          if page == freeListHead {
            resolved[current] = Self.freeListID
            break
          }
          path.append(current)
          // A cycle of links (a page that does not parse as SQLite wrote it) ends here, unnamed.
          if steps > pending.count + 1 { break }
          if let parent = parentOf[page] {
            current = parent.index
            continue
          }
          if let previous = previousOf[page] {
            current = previous
            continue
          }
          path.removeLast()
          resolved[current] = owner(page)
          break
        }
        // Assign along the path, nearest the base first.
        for step in path.reversed() {
          let page = pending[step].page
          var owner = Self.unnamedID
          if let parent = parentOf[page] {
            let parentOwner = resolved[parent.index]
            if parentOwner != Self.unresolved { owner = Self.child(of: parentOwner, isOverflow: parent.isOverflow) }
          } else if let previous = previousOf[page] {
            // An overflow page's or a trunk page's next page is another of the same; any other page keeps its b-tree.
            let previousOwner = resolved[previous]
            let isChain = previousOwner != Self.unresolved
              && (previousOwner & Self.overflowBit != 0 || previousOwner == Self.freeListID)
            owner = isChain ? previousOwner : self.owner(page)
          }
          resolved[step] = owner
        }
      }
      // Remember every placed page, and every page the commit's pages point to.
      for (index, entry) in pending.enumerated() {
        let owner = resolved[index]
        if entry.page != 1 { setOwner(entry.page, owner) }
        let range = Int(entry.linkStart)..<Int(entry.linkStart + entry.linkCount)
        if entry.isTreePage {
          let parentOwner = entry.page == 1 ? Self.schemaTableID : owner
          for link in links[range] where pendingIndex[link & ~Self.overflowLink] == nil {
            setOwner(link & ~Self.overflowLink, Self.child(of: parentOwner, isOverflow: link & Self.overflowLink != 0))
          }
          if entry.freeListTrunk > 1, pendingIndex[entry.freeListTrunk] == nil {
            setOwner(entry.freeListTrunk, Self.freeListID)
          }
        } else if let next = links[range].first, pendingIndex[next] == nil,
          owner & Self.overflowBit != 0 || owner == Self.freeListID
        {
          setOwner(next, owner)
        }
      }
      count(committed: committed)
      pending.removeAll(keepingCapacity: true)
      links.removeAll(keepingCapacity: true)
    }

    private mutating func count(committed: Bool) {
      if committed { commits += 1 }
      pagesByID.removeAll(keepingCapacity: true)
      pagesByID.append(contentsOf: repeatElement(0, count: btrees.count))
      for index in pending.indices {
        let owner = resolved[index]
        let id = Int(owner & ~Self.overflowBit)
        guard id < btrees.count else { continue }
        btrees[id].logPages += 1
        if owner & Self.overflowBit != 0 { btrees[id].overflowLogPages += 1 }
        pagesByID[id] += 1
        if let call = currentCall {
          if call < callPages.count {
            callPages[call][id] += 1
          } else {
            otherCallPages[id] += 1
          }
        }
      }
      // Each b-tree's pages go to the statements of the transaction that write it.
      for id in pagesByID.indices where pagesByID[id] > 0 {
        let pages = pagesByID[id]
        var writers = 0
        var onlyWriter = 0
        for statement in transactionStatements where shapes[statement.shape].btreeIDs.contains(UInt8(id)) {
          writers += 1
          onlyWriter = statement.shape
        }
        if writers == 0, currentCall == nil {
          unclaimedPages[id] += pages
          hasUnclaimedPages = true
        } else if writers == 0 {
          shapes[Self.noStatementID].soleLogPages += pages
        } else if writers == 1 {
          shapes[onlyWriter].soleLogPages += pages
        } else {
          for statement in transactionStatements where shapes[statement.shape].btreeIDs.contains(UInt8(id)) {
            shapes[statement.shape].sharedLogPages += pages
          }
        }
      }
    }

    var pagesByID: [Int] = []

    var otherCallPages: [Int] = Array(repeating: 0, count: State.maximumBTrees)

    // MARK: Owners

    func owner(_ page: UInt32) -> UInt8 {
      let index = Int(page)
      return index < owners.count ? owners[index] : Self.unnamedID
    }

    mutating func setOwner(_ page: UInt32, _ owner: UInt8) {
      let index = Int(page)
      guard index > 1, index < Self.maximumPages else { return }
      if index >= owners.count {
        owners.append(contentsOf: repeatElement(0, count: max(index + 1 - owners.count, min(owners.count, 65_536))))
      }
      owners[index] = owner
    }

    static func child(of parent: UInt8, isOverflow: Bool) -> UInt8 {
      if parent == headerID { return schemaTableID }
      if isOverflow || parent & overflowBit != 0 { return parent == freeListID ? parent : parent | overflowBit }
      return parent
    }

    // MARK: The record

    func record() -> InstantSQLiteWriteRecord {
      var record = InstantSQLiteWriteRecord(commits: commits)
      for btree in btrees where btree.logPages > 0 || btree.checkpointPages > 0 {
        record.btrees[btree.name] = InstantSQLiteWriteRecord.BTree(
          table: btree.table,
          isIndex: btree.isIndex,
          logPages: btree.logPages,
          overflowLogPages: btree.overflowLogPages,
          checkpointPages: btree.checkpointPages
        )
      }
      for shape in shapes where shape.runs > 0 || shape.soleLogPages > 0 || shape.sharedLogPages > 0 {
        record.statements[shape.sql] = InstantSQLiteWriteRecord.Statement(
          runs: shape.runs,
          rows: shape.rows,
          soleLogPages: shape.soleLogPages,
          sharedLogPages: shape.sharedLogPages,
          btrees: shape.btreeIDs.map { btrees[Int($0)].name }.sorted()
        )
      }
      for (call, name) in callNames.enumerated() {
        let pages = callPages[call]
        var byName: [String: Int] = [:]
        for id in pages.indices where pages[id] > 0 && id < btrees.count { byName[btrees[id].name] = pages[id] }
        if !byName.isEmpty { record.calls[name] = byName }
      }
      var others: [String: Int] = [:]
      for id in otherCallPages.indices where otherCallPages[id] > 0 && id < btrees.count {
        others[btrees[id].name] = otherCallPages[id]
      }
      if !others.isEmpty { record.calls[InstantSQLiteWriteRecord.otherCalls] = others }
      return record
    }

    // MARK: Pages

    static func bigEndian32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
      guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
      return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 | UInt32(bytes[offset + 2]) << 8
        | UInt32(bytes[offset + 3])
    }

    static func bigEndian16(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
      guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
      return UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
    }

    /// The pages a b-tree page points to, appended to `links`: an interior page's children, and each cell's first
    /// overflow page (with ``overflowLink``). Every offset is checked against the page; a page that does not parse adds
    /// what it parsed so far.
    static func appendLinks(
      of page: UnsafeRawBufferPointer,
      isPageOne: Bool,
      pageSize: Int,
      to links: inout [UInt32]
    ) {
      let header = isPageOne ? 100 : 0
      let size = min(page.count, pageSize)
      guard size > header + 12 else { return }
      let type = page[header]
      let isInterior = type == 2 || type == 5
      let isTable = type == 5 || type == 13
      guard isInterior || type == 10 || type == 13 else { return }
      let cellCount = Int(bigEndian16(page, header + 3))
      let pointerArray = header + (isInterior ? 12 : 8)
      guard pointerArray + 2 * cellCount <= size else { return }
      if isInterior {
        let rightMost = bigEndian32(page, header + 8)
        if rightMost > 1 { links.append(rightMost) }
      }
      // The local payload bounds (SQLite's file format, section 1.6), for a page with no reserved bytes.
      let usable = pageSize
      let maximumLocal = isTable ? usable - 35 : (usable - 12) * 64 / 255 - 23
      let minimumLocal = (usable - 12) * 32 / 255 - 23
      for cell in 0..<cellCount {
        var offset = Int(bigEndian16(page, pointerArray + 2 * cell))
        guard offset >= pointerArray + 2 * cellCount, offset < size else { return }
        if isInterior {
          let child = bigEndian32(page, offset)
          if child > 1 { links.append(child) }
          offset += 4
          // An interior table cell holds a rowid and no payload.
          if isTable { continue }
        }
        guard let (payload, afterPayloadSize) = varint(page, offset, limit: size) else { return }
        offset = afterPayloadSize
        if isTable {
          guard let (_, afterRowid) = varint(page, offset, limit: size) else { return }
          offset = afterRowid
        }
        guard payload > Int64(maximumLocal), payload < Int64(Int32.max) else { continue }
        let total = Int(payload)
        let spill = minimumLocal + (total - minimumLocal) % (usable - 4)
        let local = spill <= maximumLocal ? spill : minimumLocal
        let first = bigEndian32(page, offset + local)
        if first > 1 { links.append(first | overflowLink) }
      }
    }

    /// A SQLite varint at `offset`, and the offset after it; nil past `limit`.
    static func varint(_ bytes: UnsafeRawBufferPointer, _ offset: Int, limit: Int) -> (Int64, Int)? {
      var value: Int64 = 0
      for index in 0..<9 {
        guard offset + index < limit else { return nil }
        let byte = bytes[offset + index]
        if index == 8 { return ((value << 8) | Int64(byte), offset + 9) }
        value = (value << 7) | Int64(byte & 0x7F)
        if byte & 0x80 == 0 { return (value, offset + index + 1) }
      }
      return nil
    }
  }
}

extension InstantSQLiteWriteRecord {
  /// `sql` with its whitespace runs as one space and each run of two or more placeholders, with the commas, spaces and
  /// parentheses between them, as `?…`: a statement built for a batch of any size is one shape (#1510). The first 16 KB
  /// are read.
  static func shape(of sql: String) -> String {
    var collapsed: [UInt8] = []
    collapsed.reserveCapacity(min(sql.utf8.count, 16_384))
    var lastWasSpace = true
    for byte in sql.utf8.prefix(16_384) {
      if byte == 0x20 || byte == 0x0A || byte == 0x09 || byte == 0x0D {
        if !lastWasSpace { collapsed.append(0x20) }
        lastWasSpace = true
      } else {
        collapsed.append(byte)
        lastWasSpace = false
      }
    }
    if collapsed.last == 0x20 { collapsed.removeLast() }
    func isRun(_ byte: UInt8) -> Bool {
      byte == UInt8(ascii: "?") || byte == UInt8(ascii: ",") || byte == 0x20 || byte == UInt8(ascii: "(")
        || byte == UInt8(ascii: ")")
    }
    var output: [UInt8] = []
    output.reserveCapacity(collapsed.count)
    var index = 0
    while index < collapsed.count {
      guard isRun(collapsed[index]) else {
        output.append(collapsed[index])
        index += 1
        continue
      }
      var end = index
      var placeholders = 0
      while end < collapsed.count, isRun(collapsed[end]) {
        if collapsed[end] == UInt8(ascii: "?") { placeholders += 1 }
        end += 1
      }
      guard placeholders >= 2 else {
        output.append(contentsOf: collapsed[index..<end])
        index = end
        continue
      }
      // The run's leading spaces and commas, and its trailing spaces, stay as they are.
      var coreStart = index
      while coreStart < end, collapsed[coreStart] == 0x20 || collapsed[coreStart] == UInt8(ascii: ",") {
        coreStart += 1
      }
      var coreEnd = end
      while coreEnd > coreStart, collapsed[coreEnd - 1] == 0x20 { coreEnd -= 1 }
      output.append(contentsOf: collapsed[index..<coreStart])
      if collapsed[coreStart] == UInt8(ascii: "(") { output.append(UInt8(ascii: "(")) }
      output.append(contentsOf: Array("?…".utf8))
      if collapsed[coreEnd - 1] == UInt8(ascii: ")") { output.append(UInt8(ascii: ")")) }
      output.append(contentsOf: collapsed[coreEnd..<end])
      index = end
    }
    return String(decoding: output, as: UTF8.self)
  }
}
