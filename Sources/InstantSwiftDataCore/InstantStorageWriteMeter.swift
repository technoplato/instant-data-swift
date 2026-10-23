import Foundation

/// The pages SQLite writes for each of the store's write transactions, by the store call that ran it (#1007).
public enum InstantStorageWriteMeter {
  /// Every store call's transactions and pages since the process started.
  public static func snapshot() -> InstantStorageWriteSnapshot {
    InstantStorageWriteSnapshot()
  }
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
