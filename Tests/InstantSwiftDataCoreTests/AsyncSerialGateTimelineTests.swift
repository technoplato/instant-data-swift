// History
// 2026-10-24  #1074  Created. The gate reported a wait only past 250 ms and a hold only through that wait, so no
//                    exercise could say what every caller waited or every holder held. The timeline the exercises read
//                    is pinned here.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// The operation gate's timeline (#1074): every request, acquisition, release and cancellation, so an exercise can
/// measure each caller's wait and each holder's hold under contention, the short ones included.
@Suite("Async serial gate timeline")
struct AsyncSerialGateTimelineTests {
  @Test("a free gate reports the request, the acquisition at once, and the release with its phase")
  func freeGate() async {
    let clock = TimelineClock()
    let timeline = TimelineRecorder()
    let gate = AsyncSerialGate(label: "operation", timeline: timeline.record, uptimeNanoseconds: clock.read)

    clock.now = 1_000
    await gate.enter(operation: "transact", priority: .interactive)
    clock.now = 4_000
    gate.markHolderPhase("save")
    await gate.leave()

    expectNoDifference(
      timeline.events,
      [
        .init(kind: .requested, gate: "operation", ticket: 1, operation: "transact", priority: .interactive, uptimeNanoseconds: 1_000),
        .init(kind: .acquired, gate: "operation", ticket: 1, operation: "transact", priority: .interactive, uptimeNanoseconds: 1_000),
        .init(
          kind: .released, gate: "operation", ticket: 1, operation: "transact", priority: .interactive, phase: "save",
          uptimeNanoseconds: 4_000
        ),
      ]
    )
  }

  @Test("a queued caller's acquisition follows the holder's release, under the ticket of its request")
  func queuedCaller() async throws {
    let clock = TimelineClock()
    let timeline = TimelineRecorder()
    let gate = AsyncSerialGate(label: "operation", timeline: timeline.record, uptimeNanoseconds: clock.read)

    clock.now = 10
    await gate.enter(operation: "prune", priority: .background)
    await gate.setHolderPhase("retract")
    clock.now = 20
    let writer = Task { await gate.enter(operation: "transact", priority: .interactive) }
    try await gate.waitForTimelineWaiterCount(1)
    clock.now = 70
    await gate.leave()
    await writer.value
    clock.now = 75
    await gate.leave()

    expectNoDifference(
      timeline.events,
      [
        .init(kind: .requested, gate: "operation", ticket: 1, operation: "prune", priority: .background, uptimeNanoseconds: 10),
        .init(kind: .acquired, gate: "operation", ticket: 1, operation: "prune", priority: .background, uptimeNanoseconds: 10),
        .init(kind: .requested, gate: "operation", ticket: 2, operation: "transact", priority: .interactive, uptimeNanoseconds: 20),
        .init(
          kind: .released, gate: "operation", ticket: 1, operation: "prune", priority: .background, phase: "retract",
          uptimeNanoseconds: 70
        ),
        .init(kind: .acquired, gate: "operation", ticket: 2, operation: "transact", priority: .interactive, uptimeNanoseconds: 70),
        .init(kind: .released, gate: "operation", ticket: 2, operation: "transact", priority: .interactive, uptimeNanoseconds: 75),
      ]
    )
  }

  @Test("a queued caller cancelled before it takes the gate reports its cancellation and never an acquisition")
  func cancelledCaller() async throws {
    let clock = TimelineClock()
    let timeline = TimelineRecorder()
    let gate = AsyncSerialGate(label: "operation", timeline: timeline.record, uptimeNanoseconds: clock.read)

    await gate.enter(operation: "compact")
    let reader = Task { try await gate.enterUnlessCancelled(operation: "query", priority: .interactive) }
    try await gate.waitForTimelineWaiterCount(1)
    clock.now = 50
    reader.cancel()
    await #expect(throws: CancellationError.self) { try await reader.value }
    clock.now = 90
    await gate.leave()

    expectNoDifference(
      timeline.events.map { "\($0.kind) \($0.ticket) \($0.operation) \($0.uptimeNanoseconds)" },
      ["requested 1 compact 0", "acquired 1 compact 0", "requested 2 query 0", "cancelled 2 query 50", "released 1 compact 90"]
    )
  }

  @Test("a runtime hands its operation gate's timeline to the configuration's closure")
  func runtimeOperationGate() async throws {
    let directory = try InstantTestScratch.directory("instant-gate-timeline")
    let timeline = TimelineRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: "gate-timeline",
      persistenceURL: directory.appendingPathComponent("instant.sqlite"),
      initialAttributes: TodoExample.attributes
    )
    configuration.operationGateTimeline = timeline.record
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await runtime.transact(
      operations: TodoExample.createOperations(
        id: "todo-1",
        text: "one",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
        transactionID: "tx-gate-timeline"
      )
    )

    let transact = timeline.events.filter { $0.operation == "transact(_:createdAt:source:)" }
    expectNoDifference(transact.map(\.kind), [.requested, .acquired, .released])
    expectNoDifference(Set(transact.map(\.ticket)).count, 1)
    expectNoDifference(Set(transact.map(\.priority)), [.interactive])
    expectNoDifference(Set(transact.map(\.gate)), ["operation"])
  }
}

/// A clock the test moves by hand, so every wait and hold in a timeline is exact.
private final class TimelineClock: @unchecked Sendable {
  // SAFETY: `lock` protects `value`; the gate reads it on its actor while the test sets it.
  private let lock = NSLock()
  private var value: UInt64 = 0

  var now: UInt64 {
    get { lock.withLock { value } }
    set { lock.withLock { value = newValue } }
  }

  var read: @Sendable () -> UInt64 { { [self] in now } }
}

/// Every timeline event in the order the gate reported it.
private final class TimelineRecorder: @unchecked Sendable {
  // SAFETY: `lock` protects `recorded`; the gate appends on its actor while the test reads.
  private let lock = NSLock()
  private var recorded: [AsyncSerialGate.TimelineEvent] = []

  var events: [AsyncSerialGate.TimelineEvent] { lock.withLock { recorded } }

  var record: @Sendable (AsyncSerialGate.TimelineEvent) -> Void {
    { [self] event in lock.withLock { recorded.append(event) } }
  }
}

extension AsyncSerialGate {
  /// Waits until `count` callers are queued, so a test acts on a waiter that really queued instead of sleeping.
  fileprivate func waitForTimelineWaiterCount(_ count: Int, timeout: Duration = .seconds(5)) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while waiterCount != count {
      if ContinuousClock.now >= deadline {
        Issue.record("expected \(count) queued callers, saw \(waiterCount)")
        return
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }
}
