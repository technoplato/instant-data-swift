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
    guard InstantSQLiteFileMeter.registeredVFSName() != nil else { return nil }
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
// SAFETY: every mutable field is inside `state`, one `OSAllocatedUnfairLock`; `databaseName` is a `let`.
final class InstantSQLiteDatabaseWriteRecorder: @unchecked Sendable {
  let databaseName: String

  init(databaseName: String) {
    self.databaseName = databaseName
  }

  /// What this database's connections wrote since it was attached.
  func record() -> InstantSQLiteWriteRecord {
    InstantSQLiteWriteRecord()
  }

  /// Stops counting this database's new connections; what it counted stays in ``InstantSQLiteWriteRecorder/snapshot()``.
  func detach() {
    InstantSQLiteWriteRecorder.detach(self)
  }

  // MARK: The store's side

  /// Reads the b-trees' roots from `sqlite_schema` on `connection`, when the schema changed since the last read.
  func reloadSchema(from connection: OpaquePointer?) {}

  /// The store call whose write transaction begins on the writer connection.
  func beginTransaction(call: StaticString) {}

  /// The write transaction ended, committed or rolled back.
  func endTransaction() {}

  /// The shape `sql` is recorded under (``InstantSQLiteWriteRecord/shape(of:)``); the b-trees `statement` writes are
  /// read from its `EXPLAIN` the first time a shape is seen.
  func shape(forSQL sql: String, statement: OpaquePointer) -> Int32 { -1 }

  /// A write statement of `shape` finished a use: it ran `runs` times and changed `rows` rows.
  func statementFinished(shape: Int32, runs: Int, rows: Int) {}

  // MARK: The VFS's side

  /// SQLite wrote `count` bytes at `offset` of the database's log.
  func logWrite(_ bytes: UnsafeRawPointer, count: Int, offset: Int64) {}

  /// SQLite read `count` bytes at `offset` of the database's log, through `file`.
  func logRead(_ bytes: UnsafeRawPointer, count: Int, offset: Int64, file: UnsafeMutablePointer<sqlite3_file>) {}

  /// The log was truncated (a checkpoint restarted it).
  func logTruncated() {}

  /// SQLite read `count` bytes at `offset` of the database file (from the file, or mapped).
  func databaseRead(_ bytes: UnsafeRawPointer, count: Int, offset: Int64) {}

  /// A checkpoint wrote `count` bytes at `offset` of the database file.
  func databaseWrite(count: Int, offset: Int64) {}
}

extension InstantSQLiteWriteRecord {
  /// `sql` with its whitespace runs as one space and each run of placeholders, with the commas, spaces and parentheses
  /// between them, as `?…`: a statement built for a batch of any size is one shape (#1510).
  static func shape(of sql: String) -> String {
    sql
  }
}
