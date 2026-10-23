import Foundation
import os

// History:
// - 2026-10-23: the pages SQLite writes, counted for each store call (#1007). A device's recording wrote tens of
//   megabytes a minute to its local store and no meter said which store call wrote them.

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

  /// Adds one transaction of `operation` that wrote `pages`, and returns the summary that is due, if one is: at most
  /// one every 30 s, of what was counted since the last.
  static func record(
    operation: StaticString,
    pages: Int,
    now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
  ) -> InstantStorageWriteSnapshot? {
    storage.withLock { state in
      let name = operation.description
      var measure = state.operations[name] ?? InstantStorageWriteSnapshot.Measure()
      measure.transactions += 1
      measure.pagesWritten += max(0, pages)
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

    public init(transactions: Int = 0, pagesWritten: Int = 0) {
      self.transactions = transactions
      self.pagesWritten = pagesWritten
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
        pagesWritten: max(0, measure.pagesWritten - before.pagesWritten)
      )
      if delta.transactions > 0 || delta.pagesWritten > 0 { operations[name] = delta }
    }
    return Self(operations: operations)
  }
}
