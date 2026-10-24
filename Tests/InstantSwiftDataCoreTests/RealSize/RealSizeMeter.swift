import Darwin
import Foundation

@testable import InstantSwiftDataCore

// #1072 (2026-10-24): what one operation costs, counted the way an allocation-counting benchmark counts it.
//
// Every case of an operation whose cost grows with the whole store or account (#654, #932, #1035, #1006, #653) was
// found one at a time from a phone's measurements. The meter counts what such a defect spends, per operation: wall
// time, process CPU, instructions retired, heap allocations and their bytes, logical bytes written, the footprint and
// its peak, and the longest wait of a read queued behind the operation gate. Allocation and instruction counts barely
// move with the machine's load, so a budget on them fails on a regression instead of on a busy host; wall time is kept
// for the report and for generous ceilings.
//
// Timing runs with the allocation hook off (the hook takes a lock on every malloc and free); the counts come from a
// second pass of the same iterations with it on. Both are process-wide: the runtime's work runs on actor executors and
// the cooperative pool, not on the caller's thread, so a suite that meters must run serialized and alone
// (`--no-parallel`), or other tests' allocations land in its counts.
//
// History:
// - 2026-10-24: #1072: the meter of the whole-store cost audit and its CI budgets; extra counters plug in through
//   `RealSizeCounter` (the sibling audits' SQLite VFS and wire-byte counters, #1076).

/// A counter another audit plugs into the meter, such as a SQLite VFS that counts the bytes each file kind wrote.
///
/// `start()` runs right before the counted pass and `stop()` right after it; `stop()` returns the pass's totals, which
/// the meter divides by the iteration count and reports under the counter's own keys.
protocol RealSizeCounter: Sendable {
  func start()
  func stop() -> [String: Int]
}

/// What one operation cost at one size: per iteration, except where a field says otherwise.
struct RealSizeMeasurement: Sendable {
  var label: String
  var operation: String
  var iterations: Int
  /// Each timed iteration's wall time, sorted.
  var wall: [Duration]
  var cpuNanoseconds: UInt64
  var instructions: UInt64
  var logicalWriteBytes: UInt64
  var allocations: Int
  var allocatedBytes: Int
  var frees: Int
  var freedBytes: Int
  /// Reallocations, counted in `allocations` too: the logger no longer knows a reallocated block's old size, so
  /// `peakLiveBytes` counts a reallocation's whole new block.
  var reallocations: Int
  /// The whole counted pass: bytes the zones held at its end minus at its start (`malloc_zone_statistics`), exact.
  var netLiveBytes: Int
  /// The whole counted pass: the high-water mark of the hook's running allocated-minus-freed bytes.
  var peakLiveBytes: Int
  /// `phys_footprint` before the timed pass, after the counted pass, and the highest it reached in between.
  var footprintBefore: UInt64
  var footprintAfter: UInt64
  var footprintPeak: UInt64
  /// The longest a `connectionStatus()` read waited while the timed pass ran, when the meter probed the gate.
  var longestGateWait: Duration?
  /// The operation gate during the timed pass, from its timeline (#1074): the longest hold and its holder, the
  /// longest wait, and how many times the gate was taken per iteration.
  var gate: RealSizeGateLog.Summary?
  var extra: [String: Int] = [:]

  var medianWall: Duration { wall.isEmpty ? .zero : wall[wall.count / 2] }
  var maximumWall: Duration { wall.last ?? .zero }

  /// One stable line per measurement: `REALSIZE <label> op=<operation> key=value …`.
  var line: String {
    func ms(_ duration: Duration) -> String {
      String(format: "%.2f", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
    }
    var fields: [(String, String)] = [
      ("op", operation),
      ("n", String(iterations)),
      ("wallMs", ms(medianWall)),
      ("wallMaxMs", ms(maximumWall)),
      ("cpuMs", String(format: "%.2f", Double(cpuNanoseconds) / 1e6)),
      ("instructionsM", String(format: "%.2f", Double(instructions) / 1e6)),
      ("allocations", String(allocations)),
      ("allocatedKB", String(allocatedBytes / 1_024)),
      ("frees", String(frees)),
      ("reallocs", String(reallocations)),
      ("netLiveKB", String(netLiveBytes / 1_024)),
      ("peakLiveKB", String(peakLiveBytes / 1_024)),
      ("writtenKB", String(logicalWriteBytes / 1_024)),
      ("footprintMB", String(footprintAfter / 1_048_576)),
      ("footprintPeakMB", String(footprintPeak / 1_048_576)),
    ]
    if let longestGateWait { fields.append(("gateWaitMaxMs", ms(longestGateWait))) }
    if let gate {
      fields.append(("gateHoldMaxMs", ms(gate.longestHold)))
      fields.append(("gateHolder", gate.longestHolder.replacingOccurrences(of: " ", with: "_")))
      fields.append(("gateEntries", String(gate.acquisitions / max(1, iterations))))
    }
    for key in extra.keys.sorted() { fields.append((key, String(extra[key]!))) }
    return "REALSIZE \(label) " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
  }
}

enum RealSizeMeter {
  /// Runs `body` `warmup` times, then `iterations` times timed, then `iterations` times counted.
  ///
  /// `body` gets a running index (unique across the warm-up and both passes) so each call can make its own change,
  /// such as a new transcript line. Pass `gateProbe` to also report how long a read waited behind the operation gate
  /// during the timed pass; the probe's own reads take the gate briefly, so leave it off where that matters.
  static func measure(
    _ operation: String,
    label: String,
    iterations: Int = 5,
    warmup: Int = 1,
    gateProbe runtime: InstantRuntime? = nil,
    gate: RealSizeGateLog? = nil,
    counters: [any RealSizeCounter] = [],
    _ body: (Int) async throws -> Void
  ) async throws -> RealSizeMeasurement {
    precondition(iterations > 0)
    var index = 0
    for _ in 0..<warmup {
      try await body(index)
      index += 1
    }

    RealSizeProcess.resetFootprintPeak()
    let footprintBefore = RealSizeProcess.usage().footprint
    let probe = runtime.map(RealSizeGateProbe.init)
    gate?.begin()
    let usageBefore = RealSizeProcess.usage()
    var wall: [Duration] = []
    for _ in 0..<iterations {
      let started = ContinuousClock.now
      try await body(index)
      wall.append(ContinuousClock.now - started)
      index += 1
    }
    let usageAfter = RealSizeProcess.usage()
    let gateSummary = gate?.end()
    let longestGateWait = await probe?.stop()

    for counter in counters { counter.start() }
    let liveBefore = RealSizeProcess.zoneBytesInUse()
    RealSizeAllocations.start()
    do {
      for _ in 0..<iterations {
        try await body(index)
        index += 1
      }
    } catch {
      _ = RealSizeAllocations.stop()
      throw error
    }
    let counts = RealSizeAllocations.stop()
    let liveAfter = RealSizeProcess.zoneBytesInUse()
    var extra: [String: Int] = [:]
    for counter in counters {
      for (key, value) in counter.stop() { extra[key] = value / iterations }
    }
    let final = RealSizeProcess.usage()

    return RealSizeMeasurement(
      label: label,
      operation: operation,
      iterations: iterations,
      wall: wall.sorted(),
      cpuNanoseconds: (usageAfter.cpuNanoseconds - usageBefore.cpuNanoseconds) / UInt64(iterations),
      instructions: (usageAfter.instructions - usageBefore.instructions) / UInt64(iterations),
      logicalWriteBytes: (usageAfter.logicalWriteBytes - usageBefore.logicalWriteBytes) / UInt64(iterations),
      allocations: counts.allocations / iterations,
      allocatedBytes: counts.allocatedBytes / iterations,
      frees: counts.frees / iterations,
      freedBytes: counts.freedBytes / iterations,
      reallocations: counts.reallocations / iterations,
      netLiveBytes: liveAfter - liveBefore,
      peakLiveBytes: counts.peakLiveBytes,
      footprintBefore: footprintBefore,
      footprintAfter: final.footprint,
      footprintPeak: max(final.footprintIntervalPeak, final.footprint),
      longestGateWait: longestGateWait,
      gate: gateSummary,
      extra: extra
    )
  }
}

/// The process's counters from `proc_pid_rusage`, and the heap's bytes in use.
enum RealSizeProcess {
  struct Usage {
    var cpuNanoseconds: UInt64
    var instructions: UInt64
    var logicalWriteBytes: UInt64
    var footprint: UInt64
    var footprintIntervalPeak: UInt64
  }

  static func usage() -> Usage {
    var info = rusage_info_v4()
    _ = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
      }
    }
    return Usage(
      cpuNanoseconds: (info.ri_user_time + info.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom),
      instructions: info.ri_instructions,
      logicalWriteBytes: info.ri_logical_writes,
      footprint: info.ri_phys_footprint,
      footprintIntervalPeak: info.ri_interval_max_phys_footprint
    )
  }

  /// Starts a new `ri_interval_max_phys_footprint` interval. `proc_reset_footprint_interval` is in libproc but not in
  /// the SDK's headers, so it is looked up; without it the interval peak is the process's since launch.
  static func resetFootprintPeak() {
    typealias Reset = @convention(c) (pid_t) -> Int32
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "proc_reset_footprint_interval") else { return }
    _ = unsafeBitCast(symbol, to: Reset.self)(getpid())
  }

  /// Bytes every malloc zone holds now.
  static func zoneBytesInUse() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return statistics.size_in_use
  }

  private static let timebase: mach_timebase_info_data_t = {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return timebase
  }()
}

/// The operation gate's timeline (#1074) over a window: who held it longest, who waited longest.
///
/// The gate calls `record` on its own actor, in the same turn as each step, so it only appends under a lock, and only
/// while a window is open.
final class RealSizeGateLog: @unchecked Sendable {
  struct Summary: Sendable {
    var longestHold: Duration = .zero
    var longestHolder = "-"
    var longestWait: Duration = .zero
    var acquisitions = 0
  }

  // SAFETY: `lock` guards `events` and `recording`.
  private let lock = NSLock()
  private var events: [AsyncSerialGate.TimelineEvent] = []
  private var recording = false

  func record(_ event: AsyncSerialGate.TimelineEvent) {
    lock.withLock {
      guard recording else { return }
      events.append(event)
    }
  }

  func begin() {
    lock.withLock {
      events.removeAll(keepingCapacity: true)
      recording = true
    }
  }

  /// Closes the window and sums it: holds and waits pair a ticket's acquisition with its release and request.
  func end() -> Summary {
    let events = lock.withLock {
      recording = false
      return self.events
    }
    var requested: [UInt64: UInt64] = [:]
    var acquired: [UInt64: UInt64] = [:]
    var summary = Summary()
    for event in events {
      switch event.kind {
      case .requested:
        requested[event.ticket] = event.uptimeNanoseconds
      case .acquired:
        acquired[event.ticket] = event.uptimeNanoseconds
        summary.acquisitions += 1
        if let start = requested[event.ticket] {
          summary.longestWait = max(summary.longestWait, .nanoseconds(Int64(event.uptimeNanoseconds - start)))
        }
      case .released:
        guard let start = acquired[event.ticket] else { continue }
        let hold = Duration.nanoseconds(Int64(event.uptimeNanoseconds - start))
        if hold > summary.longestHold {
          summary.longestHold = hold
          summary.longestHolder = event.operation + (event.phase.map { " [\($0)]" } ?? "")
        }
      case .cancelled:
        break
      }
    }
    return summary
  }
}

/// Calls `connectionStatus()`, which waits for the operation gate like every transact, query and observe, back to back
/// while the timed pass runs, and keeps the longest wait: how long a read queued behind the measured operation.
private final class RealSizeGateProbe: @unchecked Sendable {
  // SAFETY: `lock` guards `longest` for every read and write.
  private let lock = NSLock()
  private var longest: Duration = .zero
  private var task: Task<Void, Never>?

  init(_ runtime: InstantRuntime) {
    task = Task { [weak self] in
      while !Task.isCancelled {
        let started = ContinuousClock.now
        _ = try? await runtime.connectionStatus()
        let waited = ContinuousClock.now - started
        guard let self else { return }
        self.lock.withLock { self.longest = max(self.longest, waited) }
        try? await Task.sleep(for: .milliseconds(2))
      }
    }
  }

  func stop() async -> Duration {
    task?.cancel()
    await task?.value
    return lock.withLock { longest }
  }
}

/// Process-wide counts of the heap allocations made while the hook is installed.
///
/// libmalloc calls `malloc_logger` on every allocation and free while the pointer is set: it is the hook
/// MallocStackLogging installs. The symbol is exported but not declared in the SDK's headers, so it is looked up. The
/// hook must not allocate: its tally lives in memory allocated before it is installed, behind an unfair lock.
/// libmalloc calls it for a free before the zone frees the block, so `malloc_size` still names the block's size.
enum RealSizeAllocations {
  struct Counts {
    var allocations = 0
    var allocatedBytes = 0
    var frees = 0
    var freedBytes = 0
    var reallocations = 0
    var liveBytes = 0
    var peakLiveBytes = 0
  }

  /// Installs the hook with fresh counts. Not reentrant: one counted pass at a time.
  static func start() {
    guard let slot = loggerSlot else {
      preconditionFailure("libmalloc's malloc_logger is missing: allocations cannot be counted on this system.")
    }
    os_unfair_lock_lock(&tally.pointee.lock)
    tally.pointee.counts = Counts()
    os_unfair_lock_unlock(&tally.pointee.lock)
    slot.pointee = hook
  }

  /// Removes the hook and returns the counts since `start()`.
  static func stop() -> Counts {
    loggerSlot?.pointee = nil
    os_unfair_lock_lock(&tally.pointee.lock)
    let counts = tally.pointee.counts
    os_unfair_lock_unlock(&tally.pointee.lock)
    return counts
  }

  private typealias Logger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void

  private struct Tally {
    var lock = os_unfair_lock()
    var counts = Counts()
  }

  // libmalloc's malloc_logger types (malloc/malloc.h's MALLOC_LOG_TYPE_*, private): a realloc logs once, with both
  // the allocate and deallocate bits, after it finished.
  private static let allocateBit: UInt32 = 2
  private static let deallocateBit: UInt32 = 4
  private static let hasZoneBit: UInt32 = 8

  nonisolated(unsafe) private static let tally: UnsafeMutablePointer<Tally> = {
    let pointer = UnsafeMutablePointer<Tally>.allocate(capacity: 1)
    pointer.initialize(to: Tally())
    return pointer
  }()

  nonisolated(unsafe) private static let loggerSlot: UnsafeMutablePointer<Logger?>? = {
    // Touch the tally first: a lazy global initialized from inside the hook would allocate there.
    _ = tally
    return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")?.assumingMemoryBound(to: Logger?.self)
  }()

  private static let hook: Logger = { type, _, argument2, argument3, result, _ in
    guard type & RealSizeAllocations.hasZoneBit != 0 else { return }
    let allocates = type & RealSizeAllocations.allocateBit != 0
    let deallocates = type & RealSizeAllocations.deallocateBit != 0
    let tally = RealSizeAllocations.tally
    if allocates {
      // malloc and calloc: argument2 is the size; realloc: argument2 the old block, argument3 the new size.
      let requested = Int(deallocates ? argument3 : argument2)
      let block = result == 0 ? 0 : malloc_size(UnsafeRawPointer(bitPattern: result))
      os_unfair_lock_lock(&tally.pointee.lock)
      tally.pointee.counts.allocations += 1
      tally.pointee.counts.allocatedBytes += requested
      if deallocates { tally.pointee.counts.reallocations += 1 }
      tally.pointee.counts.liveBytes += block
      tally.pointee.counts.peakLiveBytes = max(tally.pointee.counts.peakLiveBytes, tally.pointee.counts.liveBytes)
      os_unfair_lock_unlock(&tally.pointee.lock)
    } else if deallocates, argument2 != 0 {
      let block = malloc_size(UnsafeRawPointer(bitPattern: argument2))
      os_unfair_lock_lock(&tally.pointee.lock)
      tally.pointee.counts.frees += 1
      tally.pointee.counts.freedBytes += block
      tally.pointee.counts.liveBytes -= block
      os_unfair_lock_unlock(&tally.pointee.lock)
    }
  }
}
