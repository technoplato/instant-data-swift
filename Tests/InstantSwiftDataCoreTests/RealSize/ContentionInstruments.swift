// History
// 2026-10-24  #1074  Created. The phone logs a gate wait only past 250 ms, and a hold only as the wait it caused, so no
//                    run could say what a write, a read or an observer waited, at the median or the p99, while a
//                    prune, a server apply or a compaction held the operation gate. These instruments measure every
//                    wait and hold, how long a trivial call takes to come back from each executor, and how long each
//                    write's server acknowledgement waits to be recorded.

import Foundation

@testable import InstantSwiftDataCore

// MARK: - The operation gate's timeline

/// Every step on the operation gate while an exercise runs (#1074), from
/// ``InstantRuntimeConfiguration/operationGateTimeline``.
final class ContentionGateTimeline: @unchecked Sendable {
  // SAFETY: `lock` protects `events`; the gate appends on its actor while the exercise reads.
  private let lock = NSLock()
  private var events: [AsyncSerialGate.TimelineEvent] = []

  init() {
    events.reserveCapacity(1 << 16)
  }

  /// The closure for ``InstantRuntimeConfiguration/operationGateTimeline``: an append under a lock, nothing more,
  /// because the gate calls it on its own actor.
  var record: @Sendable (AsyncSerialGate.TimelineEvent) -> Void {
    { [self] event in lock.withLock { events.append(event) } }
  }

  var recorded: [AsyncSerialGate.TimelineEvent] { lock.withLock { events } }

  /// The gate's monotonic clock now, to mark the start and end of a measured window.
  static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

  /// Waits until `operation` has entered the gate at least once since `instant`, every such entry has left, and none
  /// has asked again for `quiet`; or until `timeout`. How an exercise waits for a holder it cannot await, such as the
  /// prune the frame applier runs inline after a refresh (its batches ask again right after each release).
  func waitUntilSettled(
    _ operation: String,
    requestedAfter instant: UInt64,
    quiet: Duration = .milliseconds(100),
    timeout: Duration = .seconds(300)
  ) async {
    let deadline = ContinuousClock.now + timeout
    let quietNanoseconds = UInt64(quiet.contentionMilliseconds * 1_000_000)
    while ContinuousClock.now < deadline {
      let entries = recorded.filter { $0.operation == operation && $0.uptimeNanoseconds > instant }
      let requested = Set(entries.filter { $0.kind == .requested }.map(\.ticket))
      let finished = Set(entries.filter { $0.kind == .released || $0.kind == .cancelled }.map(\.ticket))
      if let last = entries.last, !requested.isEmpty, requested.isSubset(of: finished),
        Self.now() &- last.uptimeNanoseconds > quietNanoseconds
      {
        return
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }
}

/// What a timeline adds up to: each caller's wait, each holder's hold, and whom each caller waited behind.
struct ContentionGateAnalysis {
  /// One call to enter, from its request to its release or cancellation.
  struct Entry {
    var ticket: UInt64
    var operation: String
    var priority: AsyncSerialGate.Priority
    var requestedAt: UInt64
    var acquiredAt: UInt64?
    var releasedAt: UInt64?
    var cancelledAt: UInt64?
    var phase: String?

    /// How long it queued, in milliseconds: request to acquisition, or to cancellation.
    var waitMilliseconds: Double? {
      guard let end = acquiredAt ?? cancelledAt else { return nil }
      return Double(end &- requestedAt) / 1_000_000
    }

    /// How long it held the gate, in milliseconds.
    var holdMilliseconds: Double? {
      guard let acquiredAt, let releasedAt else { return nil }
      return Double(releasedAt &- acquiredAt) / 1_000_000
    }
  }

  /// A caller kind behind a holder kind: the time it spent queued while that holder held the gate.
  struct Behind: Hashable {
    var waiter: String
    var holder: String
  }

  /// The calls requested inside the window, in ticket order: their waits and holds are the ones reported.
  var entries: [Entry]
  /// Every hold on the timeline, in order, so a wait inside the window is split among holds that began before it.
  private var allHolds: [(start: UInt64, end: UInt64, operation: String)]

  /// The entries requested inside `window` (the gate's clock), in ticket order.
  init(_ events: [AsyncSerialGate.TimelineEvent], window: ClosedRange<UInt64>? = nil) {
    var byTicket: [UInt64: Entry] = [:]
    for event in events {
      switch event.kind {
      case .requested:
        byTicket[event.ticket] = Entry(
          ticket: event.ticket,
          operation: event.operation,
          priority: event.priority,
          requestedAt: event.uptimeNanoseconds
        )
      case .acquired:
        byTicket[event.ticket]?.acquiredAt = event.uptimeNanoseconds
      case .released:
        byTicket[event.ticket]?.releasedAt = event.uptimeNanoseconds
        byTicket[event.ticket]?.phase = event.phase
      case .cancelled:
        byTicket[event.ticket]?.cancelledAt = event.uptimeNanoseconds
      }
    }
    let all = byTicket.values.sorted { $0.ticket < $1.ticket }
    entries = all.filter { entry in window.map { $0.contains(entry.requestedAt) } ?? true }
    allHolds = all
      .compactMap { entry -> (start: UInt64, end: UInt64, operation: String)? in
        guard let start = entry.acquiredAt, let end = entry.releasedAt else { return nil }
        return (start, end, entry.operation)
      }
      .sorted { $0.start < $1.start }
  }

  /// Each caller kind's waits, keyed by the operation the gate names and its priority.
  func waits() -> [String: [Double]] {
    var waits: [String: [Double]] = [:]
    for entry in entries {
      guard let wait = entry.waitMilliseconds else { continue }
      waits["\(entry.operation)|\(entry.priority)", default: []].append(wait)
    }
    return waits
  }

  /// Each holder kind's holds, keyed by the operation the gate names.
  func holds() -> [String: [Double]] {
    var holds: [String: [Double]] = [:]
    for entry in entries {
      guard let hold = entry.holdMilliseconds else { continue }
      holds[entry.operation, default: []].append(hold)
    }
    return holds
  }

  /// Each holder kind's holds by the phase it named last before it left: where in the holder the time ended.
  func holdsByPhase() -> [String: [Double]] {
    var holds: [String: [Double]] = [:]
    for entry in entries {
      guard let hold = entry.holdMilliseconds else { continue }
      holds["\(entry.operation)|\(entry.phase ?? "-")", default: []].append(hold)
    }
    return holds
  }

  /// For each caller kind and holder kind, the milliseconds the callers spent queued while that holder held the gate.
  /// Holds never overlap, because the gate is serial, so each wait is split exactly among the holds it spans.
  func behind() -> [Behind: [Double]] {
    let holds = allHolds
    var behind: [Behind: [Double]] = [:]
    for entry in entries {
      guard let end = entry.acquiredAt ?? entry.cancelledAt, end > entry.requestedAt else { continue }
      // The first hold that ends after this caller asked.
      var low = 0
      var high = holds.count
      while low < high {
        let middle = (low + high) / 2
        if holds[middle].end <= entry.requestedAt { low = middle + 1 } else { high = middle }
      }
      var index = low
      var perHolder: [String: UInt64] = [:]
      while index < holds.count, holds[index].start < end {
        let overlap = min(end, holds[index].end) &- max(entry.requestedAt, holds[index].start)
        if Int64(bitPattern: overlap) > 0 { perHolder[holds[index].operation, default: 0] += overlap }
        index += 1
      }
      for (holder, nanoseconds) in perHolder {
        behind[Behind(waiter: entry.operation, holder: holder), default: []].append(Double(nanoseconds) / 1_000_000)
      }
    }
    return behind
  }
}

// MARK: - Executor probes

/// One timed sample: when it started on the gate's clock, and how long it took.
struct ContentionSample: Sendable {
  var startedAt: UInt64
  var milliseconds: Double
}

extension Array where Element == ContentionSample {
  /// The samples that started inside `window`, in milliseconds; every sample when `window` is nil.
  func milliseconds(in window: ClosedRange<UInt64>?) -> [Double] {
    compactMap { sample in (window.map { $0.contains(sample.startedAt) } ?? true) ? sample.milliseconds : nil }
  }
}

/// How long a trivial call on one executor takes to come back, sampled every `interval` while an exercise runs
/// (#1074). An actor runs one job at a time, so a probe that queues behind a long job measures what any new caller of
/// that executor would wait at that moment: head-of-line blocking, without changing the code under test.
final class ContentionProbe: @unchecked Sendable {
  let name: String
  // SAFETY: `lock` protects `samples`; the probe's task appends while the exercise reads.
  private let lock = NSLock()
  private var samples: [ContentionSample] = []

  init(_ name: String) {
    self.name = name
  }

  var recorded: [ContentionSample] { lock.withLock { samples } }

  /// Starts sampling at `priority`; cancel the returned task to stop.
  func start(
    every interval: Duration = .milliseconds(20),
    priority: TaskPriority = .userInitiated,
    _ ping: @escaping @Sendable () async -> Void
  ) -> Task<Void, Never> {
    Task(priority: priority) { [self] in
      while !Task.isCancelled {
        let startedAt = ContentionGateTimeline.now()
        let started = ContinuousClock.now
        await ping()
        let sample = ContentionSample(startedAt: startedAt, milliseconds: started.duration(to: .now).contentionMilliseconds)
        lock.withLock { samples.append(sample) }
        try? await Task.sleep(for: interval)
      }
    }
  }
}

// MARK: - Caller latencies

/// The wall time of each call an exercise's callers make, by caller kind (#1074): what the app would see.
final class ContentionLatencies: @unchecked Sendable {
  // SAFETY: `lock` protects `samples`; callers on many tasks append.
  private let lock = NSLock()
  private var samples: [String: [ContentionSample]] = [:]

  func record(_ kind: String, startedAt: UInt64, _ duration: Duration) {
    let sample = ContentionSample(startedAt: startedAt, milliseconds: duration.contentionMilliseconds)
    lock.withLock { samples[kind, default: []].append(sample) }
  }

  /// Runs `body`, recording its wall time under `kind`, and returns what it returned.
  @discardableResult
  func time<Result>(_ kind: String, _ body: () async throws -> Result) async rethrows -> Result {
    let startedAt = ContentionGateTimeline.now()
    let started = ContinuousClock.now
    defer { record(kind, startedAt: startedAt, started.duration(to: .now)) }
    return try await body()
  }

  var recorded: [String: [ContentionSample]] { lock.withLock { samples } }
}

/// How long each write waited for the server's acknowledgement to be recorded on the device (#1074), from the
/// runtime's own `transaction.server-accepted` record: what a sync-status badge waits for. The acknowledgement queues in
/// the frame applier behind every frame received before it, so this shows a long apply or an inline prune holding up
/// the socket, which the operation gate's waits do not. Recorded under `write.accepted` in the exercise's latencies.
final class ContentionAcceptances: @unchecked Sendable {
  // SAFETY: `lock` protects `started` and `token`; the handler runs on the runtime's tasks while lanes register writes.
  private let lock = NSLock()
  private var started: [String: UInt64] = [:]
  private var token: UUID?

  init(latencies: ContentionLatencies) {
    let token = InstantDiagnostics.shared.addHandler { [weak self] entry in
      guard let self, entry.event == "transaction.server-accepted", let id = entry.correlationID else { return }
      let at = ContentionGateTimeline.now()
      guard let startedAt = self.lock.withLock({ self.started.removeValue(forKey: id) }) else { return }
      latencies.record("write.accepted", startedAt: startedAt, .nanoseconds(Int64(at &- startedAt)))
    }
    lock.withLock { self.token = token }
  }

  /// Registers a write before it is made, so an acknowledgement that arrives first is still matched.
  func expect(_ transactionID: String, startedAt: UInt64) {
    lock.withLock { started[transactionID] = startedAt }
  }

  /// Writes made since `instant` whose acknowledgement has not been recorded.
  func unaccepted(since instant: UInt64) -> Int {
    lock.withLock { started.values.filter { $0 >= instant }.count }
  }

  func stop() {
    let token = lock.withLock { () -> UUID? in
      defer { self.token = nil }
      return self.token
    }
    if let token { InstantDiagnostics.shared.removeHandler(token) }
  }
}

// MARK: - Statistics and the report

/// Count, median, p99, worst and total of a set of milliseconds, by nearest rank.
struct ContentionStats: Equatable {
  var count: Int
  var median: Double
  var p99: Double
  var worst: Double
  var total: Double

  init(count: Int, median: Double, p99: Double, worst: Double, total: Double) {
    self.count = count
    self.median = median
    self.p99 = p99
    self.worst = worst
    self.total = total
  }

  init(_ samples: [Double]) {
    let sorted = samples.sorted()
    count = sorted.count
    total = sorted.reduce(0, +)
    worst = sorted.last ?? 0
    median = Self.rank(50, in: sorted)
    p99 = Self.rank(99, in: sorted)
  }

  /// The nearest-rank percentile: the smallest sample with at least `percent` of the samples at or below it.
  static func rank(_ percent: Double, in sorted: [Double]) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = Int((percent / 100 * Double(sorted.count)).rounded(.up)) - 1
    return sorted[min(max(index, 0), sorted.count - 1)]
  }

  var fields: [(String, String)] {
    [
      ("n", String(count)),
      ("p50_ms", ContentionReport.milliseconds(median)),
      ("p99_ms", ContentionReport.milliseconds(p99)),
      ("worst_ms", ContentionReport.milliseconds(worst)),
      ("total_ms", ContentionReport.milliseconds(total)),
    ]
  }
}

/// The exercises' stable output (#1074): one `CONTENTION <exercise> <metric> key=value ...` line per number, in a
/// fixed order, so a later run of the same exercise compares line by line. A value with a space is quoted.
enum ContentionReport {
  static func line(_ exercise: String, _ metric: String, _ fields: [(String, String)]) -> String {
    let rendered = fields.map { key, value in
      value.contains(" ") || value.isEmpty ? "\(key)=\"\(value)\"" : "\(key)=\(value)"
    }
    return (["CONTENTION", exercise, metric] + rendered).joined(separator: " ")
  }

  static func milliseconds(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  /// Prints and returns the lines for every caller kind's waits, every holder's holds, and whom each kind waited
  /// behind, worst total first within each block, then the probes and the callers' own latencies, all inside `window`
  /// when one is given (the gate's own entries are windowed by the analysis).
  @discardableResult
  static func print(
    exercise: String,
    gate: ContentionGateAnalysis,
    probes: [ContentionProbe] = [],
    latencies: ContentionLatencies? = nil,
    window: ClosedRange<UInt64>? = nil
  ) -> [String] {
    var lines: [String] = []
    func byTotal<Key>(_ groups: [Key: [Double]]) -> [(key: Key, value: [Double])] {
      groups.map { (key: $0.key, value: $0.value) }.sorted { left, right in
        let (l, r) = (ContentionStats(left.value).total, ContentionStats(right.value).total)
        return l != r ? l > r : String(describing: left.key) < String(describing: right.key)
      }
    }
    for (key, samples) in byTotal(gate.waits()) {
      let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
      lines.append(
        line(
          exercise, "gate.wait",
          [("caller", parts[0]), ("priority", parts.count > 1 ? parts[1] : "")] + ContentionStats(samples).fields
        )
      )
    }
    for (holder, samples) in byTotal(gate.holds()) {
      lines.append(line(exercise, "gate.hold", [("holder", holder)] + ContentionStats(samples).fields))
    }
    for (key, samples) in byTotal(gate.holdsByPhase()) {
      let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
      lines.append(
        line(
          exercise, "gate.hold.phase",
          [("holder", parts[0]), ("last_phase", parts.count > 1 ? parts[1] : "-")] + ContentionStats(samples).fields
        )
      )
    }
    for (pair, samples) in byTotal(gate.behind()) {
      lines.append(
        line(exercise, "gate.behind", [("caller", pair.waiter), ("holder", pair.holder)] + ContentionStats(samples).fields)
      )
    }
    for probe in probes {
      let samples = probe.recorded.milliseconds(in: window)
      lines.append(line(exercise, "probe", [("executor", probe.name)] + ContentionStats(samples).fields))
    }
    if let latencies {
      for (kind, samples) in latencies.recorded.sorted(by: { $0.key < $1.key }) {
        let inWindow = samples.milliseconds(in: window)
        guard !inWindow.isEmpty else { continue }
        lines.append(line(exercise, "call", [("caller", kind)] + ContentionStats(inWindow).fields))
      }
    }
    for rendered in lines { Swift.print(rendered) }
    return lines
  }
}

extension Duration {
  /// This duration in milliseconds, as a `Double`.
  var contentionMilliseconds: Double {
    let (seconds, attoseconds) = components
    return Double(seconds) * 1_000 + Double(attoseconds) / 1_000_000_000_000_000
  }
}
