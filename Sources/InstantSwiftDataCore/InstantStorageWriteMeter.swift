import Foundation
import os

// History:
// - 2026-10-23: the pages SQLite writes, counted for each store call (#1007). A device's recording wrote tens of
//   megabytes a minute to its local store and no meter said which store call wrote them.
// - 2026-10-27: SQLite's own counters for each store call (#1245): its statements' steps, full scans, sorts and
//   automatic indexes, its page cache's hits, misses and spills, so a call that writes many pages says how.

/// The pages SQLite writes for each of the store's write transactions, by the store call that ran it (#1007).
///
/// Every write transaction counts the pages its connection wrote between `BEGIN` and `COMMIT` or `ROLLBACK`
/// (`SQLITE_DBSTATUS_CACHE_WRITE`: pages written to the write-ahead log, and to the temporary file for temporary
/// tables). A checkpoint later copies a page from the log to the database file once per checkpoint cycle; that copy is
/// not counted here. A page is 4 KB, so the pages times 4,096 are the bytes each call asked SQLite to write.
public enum InstantStorageWriteMeter {
  /// Every store call's transactions and pages since the process started.
  public static func snapshot() -> InstantStorageWriteSnapshot {
    storage.withLock { InstantStorageWriteSnapshot(operations: $0.operations) }
  }

  /// Adds one transaction of `operation` that wrote `pages` with SQLite's `sqlite` counters, and returns the summary
  /// that is due, if one is: at most one every 30 s, of what was counted since the last.
  static func record(
    operation: StaticString,
    pages: Int,
    sqlite: InstantSQLiteCounters = InstantSQLiteCounters(),
    now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
  ) -> InstantStorageWriteSnapshot? {
    storage.withLock { state in
      let name = operation.description
      var measure = state.operations[name] ?? InstantStorageWriteSnapshot.Measure()
      measure.transactions += 1
      measure.pagesWritten += max(0, pages)
      measure.sqlite = measure.sqlite.adding(sqlite)
      state.operations[name] = measure
      guard now &- state.lastSummaryAt >= summaryIntervalNanoseconds else { return nil }
      let summary = InstantStorageWriteSnapshot(operations: state.operations)
        .subtracting(InstantStorageWriteSnapshot(operations: state.operationsAtLastSummary))
      state.lastSummaryAt = now
      state.operationsAtLastSummary = state.operations
      return summary
    }
  }

  static let summaryIntervalNanoseconds: UInt64 = 30_000_000_000

  private struct State: Sendable {
    var operations: [String: InstantStorageWriteSnapshot.Measure] = [:]
    var operationsAtLastSummary: [String: InstantStorageWriteSnapshot.Measure] = [:]
    var lastSummaryAt: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
  }

  private static let storage = OSAllocatedUnfairLock(initialState: State())
}

/// What ``InstantStorageWriteMeter`` counted (#1007).
public struct InstantStorageWriteSnapshot: Sendable, Equatable {
  public struct Measure: Sendable, Equatable {
    /// Write transactions the call ran, committed or rolled back.
    public var transactions: Int
    /// Pages SQLite wrote for them: to the write-ahead log, and to the temporary file for temporary tables.
    public var pagesWritten: Int
    /// SQLite's own counters for the call's statements and its page cache (#1245).
    public var sqlite: InstantSQLiteCounters

    public init(transactions: Int = 0, pagesWritten: Int = 0, sqlite: InstantSQLiteCounters = InstantSQLiteCounters()) {
      self.transactions = transactions
      self.pagesWritten = pagesWritten
      self.sqlite = sqlite
    }
  }

  /// By the store call's name, as Swift spells the function (`saveLocalMutation(_:)`).
  public var operations: [String: Measure]

  public init(operations: [String: Measure] = [:]) {
    self.operations = operations
  }

  /// Pages times 4,096: the bytes SQLite was asked to write.
  public var bytesWritten: Int { operations.values.reduce(0) { $0 + $1.pagesWritten } * 4_096 }

  /// What was counted after `earlier`.
  public func subtracting(_ earlier: Self) -> Self {
    var operations: [String: Measure] = [:]
    for (name, measure) in self.operations {
      let before = earlier.operations[name] ?? Measure()
      let delta = Measure(
        transactions: max(0, measure.transactions - before.transactions),
        pagesWritten: max(0, measure.pagesWritten - before.pagesWritten),
        sqlite: measure.sqlite.subtracting(before.sqlite)
      )
      if delta.transactions > 0 || delta.pagesWritten > 0 { operations[name] = delta }
    }
    return Self(operations: operations)
  }
}

/// SQLite's own counters for some statements and a page cache (#1245): `sqlite3_stmt_status` for what the statements
/// did, `sqlite3_db_status` for what the connection's page cache did meanwhile.
public struct InstantSQLiteCounters: Sendable, Equatable {
  /// Steps of SQLite's virtual machine (`SQLITE_STMTSTATUS_VM_STEP`): the statements' work, roughly one per row visited
  /// and per value moved.
  public var virtualMachineSteps: Int
  /// Steps forward in a table or an index as part of a full scan (`SQLITE_STMTSTATUS_FULLSCAN_STEP`): a statement that
  /// visits every row where an index would find a few.
  public var fullScanSteps: Int
  /// Sorts (`SQLITE_STMTSTATUS_SORT`): an `ORDER BY` or `GROUP BY` no index serves.
  public var sorts: Int
  /// Rows put into automatic indexes (`SQLITE_STMTSTATUS_AUTOINDEX`): an index SQLite builds for one statement, and
  /// drops after it, because no stored index serves a join or a lookup.
  public var automaticIndexRows: Int
  /// Times a statement was prepared again because the schema changed under it (`SQLITE_STMTSTATUS_REPREPARE`).
  public var reprepares: Int
  /// Pages found in the page cache (`SQLITE_DBSTATUS_CACHE_HIT`).
  public var cacheHits: Int
  /// Pages read from the file because the cache did not hold them (`SQLITE_DBSTATUS_CACHE_MISS`).
  public var cacheMisses: Int
  /// Dirty pages written out in the middle of a transaction because the cache was full (`SQLITE_DBSTATUS_CACHE_SPILL`).
  public var cacheSpills: Int

  public init(
    virtualMachineSteps: Int = 0,
    fullScanSteps: Int = 0,
    sorts: Int = 0,
    automaticIndexRows: Int = 0,
    reprepares: Int = 0,
    cacheHits: Int = 0,
    cacheMisses: Int = 0,
    cacheSpills: Int = 0
  ) {
    self.virtualMachineSteps = virtualMachineSteps
    self.fullScanSteps = fullScanSteps
    self.sorts = sorts
    self.automaticIndexRows = automaticIndexRows
    self.reprepares = reprepares
    self.cacheHits = cacheHits
    self.cacheMisses = cacheMisses
    self.cacheSpills = cacheSpills
  }

  /// Both counts summed.
  public func adding(_ other: Self) -> Self {
    Self(
      virtualMachineSteps: virtualMachineSteps + other.virtualMachineSteps,
      fullScanSteps: fullScanSteps + other.fullScanSteps,
      sorts: sorts + other.sorts,
      automaticIndexRows: automaticIndexRows + other.automaticIndexRows,
      reprepares: reprepares + other.reprepares,
      cacheHits: cacheHits + other.cacheHits,
      cacheMisses: cacheMisses + other.cacheMisses,
      cacheSpills: cacheSpills + other.cacheSpills
    )
  }

  /// What was counted after `earlier`; a count that went down (SQLite's 32-bit counters wrap) is zero.
  public func subtracting(_ earlier: Self) -> Self {
    Self(
      virtualMachineSteps: max(0, virtualMachineSteps - earlier.virtualMachineSteps),
      fullScanSteps: max(0, fullScanSteps - earlier.fullScanSteps),
      sorts: max(0, sorts - earlier.sorts),
      automaticIndexRows: max(0, automaticIndexRows - earlier.automaticIndexRows),
      reprepares: max(0, reprepares - earlier.reprepares),
      cacheHits: max(0, cacheHits - earlier.cacheHits),
      cacheMisses: max(0, cacheMisses - earlier.cacheMisses),
      cacheSpills: max(0, cacheSpills - earlier.cacheSpills)
    )
  }
}

