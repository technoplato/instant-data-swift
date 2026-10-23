import Foundation
import os

// History:
// - #669: the meter, its operations, its counters and its dynamic-tracing signposts.
// - #1011: each operation's CPU on the main thread, so a host can name what else the main thread spent; the server
//   apply's staging and its query-result retractions under their own names, which a device profile showed outside the
//   plan's name or outside every name.

/// A library operation whose cost the energy meter adds up (#669).
///
/// Each case is a synchronous section of the library's work, measured where it runs: its count, the CPU time its thread
/// spent in it, and its wall time. ``connectAttempt`` spans awaits, so it has a count and wall time but no CPU time.
public enum InstantEnergyOperation: String, CaseIterable, Sendable {
  /// A local write's durable save: its facts and its outbox row in one SQLite transaction, `transact`'s durability
  /// point.
  case localSave
  /// The in-memory store applying one transaction to its indexes: a local write, an optimistic overlay peeled or
  /// replayed, or a server transaction.
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
  /// Planning a server apply in SQLite: opening the plan, reading the pending writes it peels and replays page by page,
  /// and the context its reduction reads.
  case serverApplyPlan
  /// Committing a server apply in SQLite: the server's facts, the rebased writes, and the query results.
  case serverApplyCommit
  /// Reading deferred values (long text and JSON kept on disk) back for an emission or a rebase.
  case deferredHydrate
  /// Pruning cached query results and the facts only they kept.
  case prune
  /// One attempt to open a live session: from the decision to open to the session's start, or the failure. Wall time
  /// only.
  case connectAttempt
  /// Encoding one frame as JSON for the WebSocket.
  case frameEncode
  /// Decoding one received WebSocket frame from JSON.
  case frameDecode
  /// Staging one page of a server apply's pending writes in SQLite (#1011): the apply's largest disk writer on a device.
  case serverApplyStage
  /// Reading which cached query facts a server result's replacements retract (#1011).
  case serverApplyRetractions

  /// The operation's slot in the meter's storage.
  fileprivate var index: Int {
    switch self {
    case .localSave: 0
    case .storePrepare: 1
    case .observerRefresh: 2
    case .outboxClaim: 3
    case .mutationEncode: 4
    case .acknowledgement: 5
    case .refreshTranslate: 6
    case .serverApplyPlan: 7
    case .serverApplyCommit: 8
    case .deferredHydrate: 9
    case .prune: 10
    case .connectAttempt: 11
    case .frameEncode: 12
    case .frameDecode: 13
    case .serverApplyStage: 14
    case .serverApplyRetractions: 15
    }
  }

  /// The operation's signpost name.
  fileprivate var signpostName: StaticString {
    switch self {
    case .localSave: "localSave"
    case .storePrepare: "storePrepare"
    case .observerRefresh: "observerRefresh"
    case .outboxClaim: "outboxClaim"
    case .mutationEncode: "mutationEncode"
    case .acknowledgement: "acknowledgement"
    case .refreshTranslate: "refreshTranslate"
    case .serverApplyPlan: "serverApplyPlan"
    case .serverApplyCommit: "serverApplyCommit"
    case .deferredHydrate: "deferredHydrate"
    case .prune: "prune"
    case .connectAttempt: "connectAttempt"
    case .frameEncode: "frameEncode"
    case .frameDecode: "frameDecode"
    case .serverApplyStage: "serverApplyStage"
    case .serverApplyRetractions: "serverApplyRetractions"
    }
  }
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
    /// Of ``cpuNanoseconds``, the sections that ran on the main thread (#1011).
    public var mainThreadCPUNanoseconds: UInt64

    public init(
      count: Int = 0,
      cpuNanoseconds: UInt64 = 0,
      wallNanoseconds: UInt64 = 0,
      mainThreadCPUNanoseconds: UInt64 = 0
    ) {
      self.count = count
      self.cpuNanoseconds = cpuNanoseconds
      self.wallNanoseconds = wallNanoseconds
      self.mainThreadCPUNanoseconds = mainThreadCPUNanoseconds
    }

    /// What this measure added after `earlier`. A counter never goes back, so each field is at least zero.
    public func subtracting(_ earlier: Self) -> Self {
      func delta(_ new: UInt64, _ old: UInt64) -> UInt64 { new >= old ? new - old : 0 }
      return Self(
        count: max(0, count - earlier.count),
        cpuNanoseconds: delta(cpuNanoseconds, earlier.cpuNanoseconds),
        wallNanoseconds: delta(wallNanoseconds, earlier.wallNanoseconds),
        mainThreadCPUNanoseconds: delta(mainThreadCPUNanoseconds, earlier.mainThreadCPUNanoseconds)
      )
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
    var operations: [InstantEnergyOperation: Measure] = [:]
    for operation in InstantEnergyOperation.allCases {
      operations[operation] = self[operation].subtracting(earlier[operation])
    }
    return Self(
      operations: operations,
      transactions: max(0, transactions - earlier.transactions),
      outboxRowsWritten: max(0, outboxRowsWritten - earlier.outboxRowsWritten),
      outboxRowsSuperseded: max(0, outboxRowsSuperseded - earlier.outboxRowsSuperseded),
      reconnectAttempts: max(0, reconnectAttempts - earlier.reconnectAttempts)
    )
  }
}

/// Adds up what the library's operations cost (#669): how often each ran, the CPU time its synchronous work took on its
/// thread, and its wall time, from launch. Reading it is one lock and one copy.
///
/// A section reads its thread's CPU clock (`CLOCK_THREAD_CPUTIME_ID`) and the uptime clock at both ends and adds the
/// differences under one lock, without allocating. Each section is also a signpost interval in the
/// `com.instantdb.swift` subsystem's dynamic-tracing category, which costs a flag check when no one records.
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
  fileprivate let storage: InstantEnergyMeterStorage
  fileprivate let operation: InstantEnergyOperation
  fileprivate let cpuStart: UInt64
  fileprivate let wallStart: UInt64
  /// The signpost interval's id, or zero when no one records signposts.
  fileprivate let signpostID: UInt64

  /// Ends the section and adds its cost to the meter.
  package func end() {
    storage.end(self)
  }
}

/// One span being measured that may cross awaits (#669).
package struct InstantEnergySpan: Sendable {
  fileprivate let storage: InstantEnergyMeterStorage
  fileprivate let operation: InstantEnergyOperation
  fileprivate let wallStart: UInt64
  fileprivate let signpostID: UInt64

  /// Ends the span and adds its count and wall time to the meter.
  package func end() {
    storage.end(self)
  }
}

/// The meter's state: the process-wide one behind ``InstantEnergyMeter``, or a test's own (#669).
///
/// The lock guards fixed-size arrays updated in place: no allocation on the hot path, and one short critical section
/// per measurement, the "tiny, local isolation domain" a lock is for.
package final class InstantEnergyMeterStorage: Sendable {
  private struct State: Sendable {
    var counts = [Int](repeating: 0, count: InstantEnergyOperation.allCases.count)
    var cpuNanoseconds = [UInt64](repeating: 0, count: InstantEnergyOperation.allCases.count)
    var wallNanoseconds = [UInt64](repeating: 0, count: InstantEnergyOperation.allCases.count)
    var events = [Int](repeating: 0, count: InstantEnergyEvent.allCases.count)
  }

  /// `OSLog` predates `Sendable`; the handle is immutable and the logging calls are thread-safe.
  ///
  /// The dynamic-tracing category keeps the signposts off until a performance tool records them (`os/signpost.h`,
  /// `OS_LOG_CATEGORY_DYNAMIC_TRACING`): a plain category enables them whenever logging is enabled, and each section
  /// would then pay for an id and two signposts on every call.
  // SAFETY: `log` is a `let` set once at initialization and never mutated, and the os_signpost functions that read it
  // are safe to call from any thread or executor, so sharing the handle needs no lock.
  private struct SignpostLog: @unchecked Sendable {
    let log = OSLog(subsystem: "com.instantdb.swift", category: .dynamicTracing)
  }

  private static let signposts = SignpostLog()
  private let state = OSAllocatedUnfairLock(initialState: State())

  package init() {}

  package func begin(_ operation: InstantEnergyOperation) -> InstantEnergyInterval {
    let signpostID = Self.beginSignpost(operation)
    return InstantEnergyInterval(
      storage: self,
      operation: operation,
      cpuStart: clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID),
      wallStart: clock_gettime_nsec_np(CLOCK_UPTIME_RAW),
      signpostID: signpostID
    )
  }

  package func beginSpan(_ operation: InstantEnergyOperation) -> InstantEnergySpan {
    let signpostID = Self.beginSignpost(operation)
    return InstantEnergySpan(
      storage: self,
      operation: operation,
      wallStart: clock_gettime_nsec_np(CLOCK_UPTIME_RAW),
      signpostID: signpostID
    )
  }

  fileprivate func end(_ interval: InstantEnergyInterval) {
    let cpuNow = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    let wallNow = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let cpu = cpuNow >= interval.cpuStart ? cpuNow - interval.cpuStart : 0
    let wall = wallNow >= interval.wallStart ? wallNow - interval.wallStart : 0
    let index = interval.operation.index
    state.withLock { state in
      state.counts[index] &+= 1
      state.cpuNanoseconds[index] &+= cpu
      state.wallNanoseconds[index] &+= wall
    }
    Self.endSignpost(interval.operation, id: interval.signpostID)
  }

  fileprivate func end(_ span: InstantEnergySpan) {
    let wallNow = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    let wall = wallNow >= span.wallStart ? wallNow - span.wallStart : 0
    let index = span.operation.index
    state.withLock { state in
      state.counts[index] &+= 1
      state.wallNanoseconds[index] &+= wall
    }
    Self.endSignpost(span.operation, id: span.signpostID)
  }

  package func record(_ event: InstantEnergyEvent, count: Int = 1) {
    let index = event.rawValue
    state.withLock { state in
      state.events[index] &+= count
    }
  }

  package func snapshot() -> InstantEnergySnapshot {
    let current = state.withLock { $0 }
    var operations: [InstantEnergyOperation: InstantEnergySnapshot.Measure] = [:]
    for operation in InstantEnergyOperation.allCases {
      let index = operation.index
      operations[operation] = InstantEnergySnapshot.Measure(
        count: current.counts[index],
        cpuNanoseconds: current.cpuNanoseconds[index],
        wallNanoseconds: current.wallNanoseconds[index]
      )
    }
    return InstantEnergySnapshot(
      operations: operations,
      transactions: current.events[InstantEnergyEvent.transaction.rawValue],
      outboxRowsWritten: current.events[InstantEnergyEvent.outboxRowWritten.rawValue],
      outboxRowsSuperseded: current.events[InstantEnergyEvent.outboxRowSuperseded.rawValue],
      reconnectAttempts: current.events[InstantEnergyEvent.reconnectAttempt.rawValue]
    )
  }

  private static func beginSignpost(_ operation: InstantEnergyOperation) -> UInt64 {
    let log = signposts.log
    guard log.signpostsEnabled else { return 0 }
    let id = OSSignpostID(log: log)
    os_signpost(.begin, log: log, name: operation.signpostName, signpostID: id)
    return id.rawValue
  }

  private static func endSignpost(_ operation: InstantEnergyOperation, id: UInt64) {
    guard id != 0 else { return }
    os_signpost(.end, log: signposts.log, name: operation.signpostName, signpostID: OSSignpostID(id))
  }
}
