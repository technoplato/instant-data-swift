// History:
// - 2026-10-28: the gate's waits and holds count only the time the process ran, with the time it was suspended or the
//   device slept reported beside them (#1319).

import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #1319: on a phone the operation gate reported a prune batch holding it 2,236,773 ms and an outbox release waiting
/// 391,652 ms behind it. Almost all of that was iOS suspending the app (1,563.8 s, its watchdog said) and the phone
/// asleep (about 681 s): the gate timed holds on the wall clock. A measure of a stall counts the time the process ran.
@Suite(.serialized)
struct AsyncSerialGateSuspensionTests {
  @Test
  func aHoldAcrossASuspensionReportsTheTimeItRanWithTheSuspensionBesideIt() async throws {
    let clock = ManualGateClock()
    let waits = GateWaitReportRecorder()
    let gate = AsyncSerialGate(
      label: "operation",
      waitReportThresholdMilliseconds: 250,
      waitReport: { report in Task { await waits.record(report) } },
      clock: clock.gateClock
    )

    await gate.enter(operation: "pruneLiveQueryResults(policy:now:)")
    clock.run(seconds: 1)
    let waiter = Task {
      await gate.enter(operation: "release automatic outbox claims for disconnected session")
      await gate.leave()
    }
    try await gate.waitForWaiterCount(1)
    clock.suspendProcess(seconds: 1_200)
    clock.sleepDevice(seconds: 600)
    clock.run(seconds: 1)
    await gate.leave()
    await waiter.value

    let report = try await waits.waitForFirst()
    expectNoDifference(report.waitMilliseconds, 1_000)
    expectNoDifference(report.waitSuspendedMilliseconds, 1_800_000)
    expectNoDifference(report.previousHolderHeldMilliseconds, 2_000)
    expectNoDifference(report.previousHolderSuspendedMilliseconds, 1_800_000)
  }

  @Test
  func aSuspensionAloneNeverMakesAStall() async throws {
    let clock = ManualGateClock()
    let stalls = GateStallReportRecorder()
    let gate = AsyncSerialGate(
      label: "operation",
      stallThresholdMilliseconds: 50,
      report: { report in Task { await stalls.record(report) } },
      clock: clock.gateClock
    )

    await gate.enter(operation: "pruneLiveQueryResults(policy:now:)")
    let waiter = Task {
      await gate.enter(operation: "schedule live reconnect")
      await gate.leave()
    }
    try await gate.waitForWaiterCount(1)
    clock.suspendProcess(seconds: 1_800)
    // The stall check runs every 50 ms of real time; four of them see a wait that ran no time at all.
    try await Task.sleep(for: .milliseconds(250))
    #expect(await stalls.recorded.isEmpty, "a wait that only spans a suspension is no stall")

    clock.run(seconds: 0.06)
    let stall = try await stalls.waitForFirst()
    expectNoDifference(stall.holderHeldMilliseconds, 60)
    expectNoDifference(stall.holderSuspendedMilliseconds, 1_800_000)
    expectNoDifference(stall.longestWaitMilliseconds, 60)
    expectNoDifference(stall.longestWaitSuspendedMilliseconds, 1_800_000)

    await gate.leave()
    await waiter.value
  }

  @Test
  func aBackgroundCallerAgesOnlyWhileTheProcessRuns() async throws {
    let clock = ManualGateClock()
    let gate = AsyncSerialGate(label: "operation", agingMilliseconds: 2_000, clock: clock.gateClock)
    let order = OrderRecorder()

    await gate.enter(operation: "holder")
    let background = Task {
      await gate.enter(operation: "prune batch", priority: .background)
      order.append("prune batch")
      await gate.leave()
    }
    try await gate.waitForWaiterCount(1)
    // Thirty minutes suspended would have aged the prune 900 ranks past an interactive write.
    clock.suspendProcess(seconds: 1_800)
    let interactive = Task {
      await gate.enter(operation: "transact", priority: .interactive)
      order.append("transact")
      await gate.leave()
    }
    try await gate.waitForWaiterCount(2)
    await gate.leave()
    await background.value
    await interactive.value

    expectNoDifference(order.values, ["transact", "prune batch"])
  }

  @Test
  func theProcessSuspensionsAnAppRecordsAreSubtractedWhereTheyOverlap() {
    InstantProcessSuspensions.resetForTesting()
    defer { InstantProcessSuspensions.resetForTesting() }
    InstantProcessSuspensions.record(suspensionEndingAtUptime: 10_000_000_000, nanoseconds: 4_000_000_000)
    InstantProcessSuspensions.record(suspensionEndingAtUptime: 20_000_000_000, nanoseconds: 2_000_000_000)

    expectNoDifference(InstantProcessSuspensions.suspendedNanoseconds(fromUptime: 0, toUptime: 30_000_000_000), 6_000_000_000)
    expectNoDifference(
      InstantProcessSuspensions.suspendedNanoseconds(fromUptime: 8_000_000_000, toUptime: 19_000_000_000),
      3_000_000_000,
      "2 s of the first and 1 s of the second"
    )
    expectNoDifference(InstantProcessSuspensions.suspendedNanoseconds(fromUptime: 10_000_000_000, toUptime: 18_000_000_000), 0)
  }

  /// The diagnostics rule's stress (#1285): a million recorded resumes keep the record bounded, and the answer right.
  @Test
  func aMillionRecordedResumesKeepTheRecordBounded() {
    InstantProcessSuspensions.resetForTesting()
    defer { InstantProcessSuspensions.resetForTesting() }
    for index in 1...1_000_000 {
      InstantProcessSuspensions.record(
        suspensionEndingAtUptime: UInt64(index) * 10_000_000_000,
        nanoseconds: 1_000_000_000
      )
    }
    #expect(InstantProcessSuspensions.recordedCountForTesting <= InstantProcessSuspensions.capacity)
    expectNoDifference(
      InstantProcessSuspensions.suspendedNanoseconds(
        fromUptime: 999_998 * 10_000_000_000,
        toUptime: 1_000_000 * 10_000_000_000
      ),
      2_000_000_000,
      "the two newest suspensions inside the span"
    )
  }
}

/// The gate's clocks, moved by hand: running time, a suspension of the process, the device asleep.
final class ManualGateClock: @unchecked Sendable {
  // SAFETY: `lock` guards every stored property below it.
  private let lock = NSLock()
  private var elapsed: UInt64 = 1_000_000_000
  private var uptime: UInt64 = 1_000_000_000
  private var suspensions: [(start: UInt64, end: UInt64)] = []

  /// The process runs for `seconds`.
  func run(seconds: Double) {
    let nanoseconds = UInt64(seconds * 1e9)
    lock.withLock {
      elapsed += nanoseconds
      uptime += nanoseconds
    }
  }

  /// The device is awake and the process suspended for `seconds`, and its watchdog records it on resume.
  func suspendProcess(seconds: Double) {
    let nanoseconds = UInt64(seconds * 1e9)
    lock.withLock {
      suspensions.append((uptime, uptime + nanoseconds))
      elapsed += nanoseconds
      uptime += nanoseconds
    }
  }

  /// The device sleeps for `seconds`: the uptime clock stops.
  func sleepDevice(seconds: Double) {
    let nanoseconds = UInt64(seconds * 1e9)
    lock.withLock { elapsed += nanoseconds }
  }

  var gateClock: AsyncSerialGate.Clock {
    AsyncSerialGate.Clock(
      now: { [self] in
        lock.withLock { AsyncSerialGate.Instant(elapsedNanoseconds: elapsed, uptimeNanoseconds: uptime) }
      },
      suspendedNanoseconds: { [self] start, end in
        lock.withLock {
          suspensions.reduce(0) { total, span in
            let from = max(span.start, start)
            let to = min(span.end, end)
            return to > from ? total + (to - from) : total
          }
        }
      }
    )
  }
}

private final class OrderRecorder: @unchecked Sendable {
  // SAFETY: `lock` guards `stored`.
  private let lock = NSLock()
  private var stored: [String] = []

  func append(_ value: String) { lock.withLock { stored.append(value) } }

  var values: [String] { lock.withLock { stored } }
}
