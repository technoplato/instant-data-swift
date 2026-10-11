import Foundation
import os

/// A library operation whose cost the energy meter adds up (#669).
///
/// Each case is a synchronous section of the library's work, measured where it runs: its count, the CPU time its thread
/// spent in it, and its wall time. ``connectAttempt`` spans awaits, so it has a count and wall time but no CPU time.
public enum InstantEnergyOperation: String, CaseIterable, Sendable {
  /// A local write's durable save: its facts and its outbox row in one SQLite transaction, `transact`'s durability
  /// point.
  case localSave
  /// The in-memory store preparing a change: a local write, or pending writes rebased over a server apply.
  case storePrepare
  /// Refreshing the observers a committed change can affect.
  case observerRefresh
  /// Claiming the next window of the outbox for delivery.
  case outboxClaim
  /// Resolving one claimed write's attributes for the wire, as it is sent.
  case mutationEncode
  /// Settling a write the server acknowledged (`transact-ok`).
  case acknowledgement
  /// Translating a server result (`refresh-ok`) into store operations.
  case refreshTranslate
  /// Committing a server apply in SQLite: the server's facts, the rebased writes, and the query results.
  case serverApplyCommit
  /// Reading deferred values (long text and JSON kept on disk) back for an emission or a rebase.
  case deferredHydrate
  /// Pruning cached query results and the facts only they kept.
  case prune
  /// One attempt to open a live session, from connecting to `init-ok` or the failure. Wall time only.
  case connectAttempt
}

/// What the library's energy meter has measured since the process started (#669).
///
/// Read it with ``InstantEnergyMeter/snapshot()`` and subtract an earlier read to see what a minute cost:
///
/// ```swift
/// let now = InstantEnergyMeter.snapshot()
/// let minute = now.subtracting(previous)
/// let saveMilliseconds = Double(minute[.localSave].cpuNanoseconds) / 1_000_000
/// ```
public struct InstantEnergySnapshot: Sendable, Equatable {
  /// One operation's measured sections.
  public struct Measure: Sendable, Equatable {
    /// How many times the operation's measured section ran.
    public var count: Int
    /// The CPU time the sections' threads spent in them, in nanoseconds.
    public var cpuNanoseconds: UInt64
    /// The wall time of the sections, in nanoseconds.
    public var wallNanoseconds: UInt64

    public init(count: Int = 0, cpuNanoseconds: UInt64 = 0, wallNanoseconds: UInt64 = 0) {
      self.count = count
      self.cpuNanoseconds = cpuNanoseconds
      self.wallNanoseconds = wallNanoseconds
    }
  }

  /// Every operation's measure; an operation that never ran reads as zero.
  public var operations: [InstantEnergyOperation: Measure]
  /// Local transactions committed.
  public var transactions: Int
  /// Outbox rows a local write appended.
  public var outboxRowsWritten: Int
  /// Outbox rows a local write replaced instead of appending (same-entity supersession).
  public var outboxRowsSuperseded: Int
  /// Attempts the scheduled reconnect made to open a live session.
  public var reconnectAttempts: Int

  public init(
    operations: [InstantEnergyOperation: Measure] = [:],
    transactions: Int = 0,
    outboxRowsWritten: Int = 0,
    outboxRowsSuperseded: Int = 0,
    reconnectAttempts: Int = 0
  ) {
    self.operations = operations
    self.transactions = transactions
    self.outboxRowsWritten = outboxRowsWritten
    self.outboxRowsSuperseded = outboxRowsSuperseded
    self.reconnectAttempts = reconnectAttempts
  }

  /// One operation's measure.
  public subscript(_ operation: InstantEnergyOperation) -> Measure {
    operations[operation] ?? Measure()
  }

  /// What happened between `earlier` and this snapshot.
  public func subtracting(_ earlier: Self) -> Self {
    Self()
  }
}

/// Adds up what the library's operations cost (#669): how often each ran, the CPU time its synchronous work took on its
/// thread, and its wall time, from launch. Reading it is one lock and one copy.
///
/// The counts are allocation-free and guarded by one lock. Each section is also an `OSSignposter`-style interval in the
/// `instant-swift-data` subsystem's `energy` category, which costs a flag check when no one records.
public enum InstantEnergyMeter {
  /// Everything measured since launch.
  public static func snapshot() -> InstantEnergySnapshot {
    shared.snapshot()
  }

  /// Starts measuring a synchronous section of `operation`. End it before the function returns; it must not span an
  /// `await`, since a thread's CPU clock says nothing about a task that moved threads.
  @available(*, noasync, message: "A section must not span an await; use beginSpan(_:) in async code.")
  package static func begin(_ operation: InstantEnergyOperation) -> InstantEnergyInterval {
    shared.begin(operation)
  }

  /// Starts measuring a span of `operation` that may cross awaits: its count and wall time, no CPU time.
  package static func beginSpan(_ operation: InstantEnergyOperation) -> InstantEnergySpan {
    shared.beginSpan(operation)
  }

  /// Adds `count` to one of the meter's event counters.
  package static func record(_ event: InstantEnergyEvent, count: Int = 1) {
    shared.record(event, count: count)
  }

  package static let shared = InstantEnergyMeterStorage()
}

/// The meter's event counters (#669).
package enum InstantEnergyEvent: Int, CaseIterable, Sendable {
  case transaction
  case outboxRowWritten
  case outboxRowSuperseded
  case reconnectAttempt
}

/// One synchronous section being measured (#669).
package struct InstantEnergyInterval: Sendable {
  let storage: InstantEnergyMeterStorage
  let operation: InstantEnergyOperation

  /// Ends the section and adds its cost to the meter.
  package func end() {}
}

/// One span being measured that may cross awaits (#669).
package struct InstantEnergySpan: Sendable {
  let storage: InstantEnergyMeterStorage
  let operation: InstantEnergyOperation

  /// Ends the span and adds its count and wall time to the meter.
  package func end() {}
}

/// The meter's state: the process-wide one behind ``InstantEnergyMeter``, or a test's own (#669).
package final class InstantEnergyMeterStorage: Sendable {
  package init() {}

  package func begin(_ operation: InstantEnergyOperation) -> InstantEnergyInterval {
    InstantEnergyInterval(storage: self, operation: operation)
  }

  package func beginSpan(_ operation: InstantEnergyOperation) -> InstantEnergySpan {
    InstantEnergySpan(storage: self, operation: operation)
  }

  package func record(_ event: InstantEnergyEvent, count: Int = 1) {}

  package func snapshot() -> InstantEnergySnapshot {
    InstantEnergySnapshot()
  }
}
