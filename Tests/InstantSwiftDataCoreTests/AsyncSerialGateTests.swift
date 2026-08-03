import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite("Async serial gate")
struct AsyncSerialGateTests {
  // A queued waiter used to park until the holder handed it the baton, even
  // after its task was cancelled, because `withCheckedContinuation` cannot
  // observe cancellation. Scribe cancels the in-flight `transact` on every
  // "Retry automatic setup" tap, so the cancelled attempt kept the queue slot
  // and then ran the full optimistic write anyway.
  @Test("a task cancelled while queued surfaces cancellation instead of parking")
  func cancelledWaiterSurfacesCancellation() async throws {
    let gate = AsyncSerialGate(label: "test")
    await gate.enter()

    let outcomes = GateOutcomeRecorder()
    let waiter = Task {
      do {
        try await gate.enterUnlessCancelled()
        await outcomes.record("acquired")
        await gate.leave()
      } catch is CancellationError {
        await outcomes.record("cancelled")
      } catch {
        await outcomes.record("unexpected-\(error)")
      }
    }

    try await gate.waitForWaiterCount(1)
    waiter.cancel()
    await waiter.value

    #expect(await outcomes.recorded == ["cancelled"])
    #expect(await gate.waiterCount == 0)

    await gate.leave()
    #expect(await gate.isHeld == false)
  }

  @Test("a task cancelled before it waits never joins the queue")
  func waiterCancelledBeforeEnteringNeverJoinsTheQueue() async throws {
    let gate = AsyncSerialGate(label: "test")
    await gate.enter()

    let outcomes = GateOutcomeRecorder()
    let started = GateOutcomeRecorder()
    let waiter = Task {
      await started.record("started")
      while !Task.isCancelled {
        await Task.yield()
      }
      do {
        try await gate.enterUnlessCancelled()
        await outcomes.record("acquired")
        await gate.leave()
      } catch is CancellationError {
        await outcomes.record("cancelled")
      } catch {
        await outcomes.record("unexpected-\(error)")
      }
    }

    try await started.waitForCount(1)
    waiter.cancel()
    await waiter.value

    #expect(await outcomes.recorded == ["cancelled"])
    #expect(await gate.waiterCount == 0)

    await gate.leave()
    #expect(await gate.isHeld == false)
  }

  // Removing a cancelled waiter must not leave a resumed-but-unowned slot
  // behind, and `leave()` must not resume a continuation that cancellation
  // already resumed. A double resume of a `CheckedContinuation` traps, so this
  // test crashes the run rather than failing softly if the race regresses.
  @Test("cancelling a queued waiter releases the gate cleanly for the next caller")
  func cancelledWaiterDoesNotLeakOwnershipOrContinuations() async throws {
    let gate = AsyncSerialGate(label: "test")
    await gate.enter()

    let outcomes = GateOutcomeRecorder()
    let cancelled = Task {
      do {
        try await gate.enterUnlessCancelled()
        await outcomes.record("cancelled-task-acquired")
        await gate.leave()
      } catch {
        await outcomes.record("cancelled-task-threw")
      }
    }
    try await gate.waitForWaiterCount(1)

    let survivor = Task {
      await gate.enter()
      await outcomes.record("survivor-acquired")
      await gate.leave()
    }
    try await gate.waitForWaiterCount(2)

    cancelled.cancel()
    await cancelled.value
    #expect(await gate.waiterCount == 1)

    await gate.leave()
    await survivor.value

    #expect(await outcomes.recorded == ["cancelled-task-threw", "survivor-acquired"])
    #expect(await gate.isHeld == false)
    #expect(await gate.waiterCount == 0)
  }

  // Regression guard: `waiters.removeFirst()` is already FIFO. Cancellation
  // support removes waiters from the middle of the queue, which must not
  // reorder the survivors.
  @Test("waiters acquire the gate in first-in-first-out order")
  func waitersAcquireInFIFOOrder() async throws {
    let gate = AsyncSerialGate(label: "test")
    await gate.enter()

    let outcomes = GateOutcomeRecorder()
    var waiters: [Task<Void, Never>] = []
    for index in 0..<5 {
      waiters.append(
        Task {
          await gate.enter()
          await outcomes.record("waiter-\(index)")
          await gate.leave()
        }
      )
      try await gate.waitForWaiterCount(index + 1)
    }

    await gate.leave()
    for waiter in waiters { await waiter.value }

    #expect(
      await outcomes.recorded == [
        "waiter-0", "waiter-1", "waiter-2", "waiter-3", "waiter-4",
      ]
    )
  }

  @Test("cancelling a middle waiter preserves first-in-first-out order for the rest")
  func cancellingAMiddleWaiterPreservesFIFOOrder() async throws {
    let gate = AsyncSerialGate(label: "test")
    await gate.enter()

    let outcomes = GateOutcomeRecorder()
    var waiters: [Task<Void, Never>] = []
    for index in 0..<4 {
      waiters.append(
        Task {
          do {
            try await gate.enterUnlessCancelled()
            await outcomes.record("waiter-\(index)")
            await gate.leave()
          } catch {
            await outcomes.record("waiter-\(index)-cancelled")
          }
        }
      )
      try await gate.waitForWaiterCount(index + 1)
    }

    waiters[1].cancel()
    await waiters[1].value
    #expect(await gate.waiterCount == 3)

    await gate.leave()
    for waiter in waiters { await waiter.value }

    #expect(
      await outcomes.recorded == [
        "waiter-1-cancelled", "waiter-0", "waiter-2", "waiter-3",
      ]
    )
  }

  // A gate that stalls silently turns every queued transact, query, observe,
  // and connection-status call into an unexplained hang. The repository rule is
  // that an unfinished local write is a loud failure, so the gate must name the
  // holder that is not leaving.
  @Test("a holder that stalls past the threshold reports a named stall")
  func stalledHolderReportsANamedStall() async throws {
    let reports = GateStallReportRecorder()
    let gate = AsyncSerialGate(
      label: "operation",
      stallThresholdMilliseconds: 50,
      report: { report in Task { await reports.record(report) } }
    )

    await gate.enter(operation: "transact(_:createdAt:source:)")
    let waiter = Task {
      await gate.enter(operation: "queryOnce(_:)")
      await gate.leave()
    }
    try await gate.waitForWaiterCount(1)

    let first = try await reports.waitForFirst()
    #expect(first.label == "operation")
    #expect(first.holder == "transact(_:createdAt:source:)")
    #expect(first.longestWaitingOperation == "queryOnce(_:)")
    #expect(first.waiterCount == 1)
    #expect(first.stallCount == 1)
    #expect(first.longestWaitMilliseconds >= 50)

    await gate.leave()
    await waiter.value
  }

  @Test("a gate that is not contended never reports a stall")
  func uncontendedGateNeverReportsAStall() async throws {
    let reports = GateStallReportRecorder()
    let gate = AsyncSerialGate(
      label: "operation",
      stallThresholdMilliseconds: 20,
      report: { report in Task { await reports.record(report) } }
    )

    for _ in 0..<3 {
      await gate.enter(operation: "transact(_:createdAt:source:)")
      await gate.leave()
    }
    try await Task.sleep(for: .milliseconds(120))

    #expect(await reports.recorded.isEmpty)
  }

  @Test("stall reporting stops once the queue drains")
  func stallReportingStopsOnceTheQueueDrains() async throws {
    let reports = GateStallReportRecorder()
    let gate = AsyncSerialGate(
      label: "operation",
      stallThresholdMilliseconds: 30,
      report: { report in Task { await reports.record(report) } }
    )

    await gate.enter(operation: "holder()")
    let waiter = Task {
      await gate.enter(operation: "waiter()")
      await gate.leave()
    }
    try await gate.waitForWaiterCount(1)
    _ = try await reports.waitForFirst()

    await gate.leave()
    await waiter.value

    let settled = await reports.recorded.count
    try await Task.sleep(for: .milliseconds(150))
    #expect(await reports.recorded.count == settled)
  }
}

private actor GateOutcomeRecorder {
  private var values: [String] = []

  func record(_ value: String) {
    values.append(value)
  }

  var recorded: [String] { values }

  func waitForCount(_ count: Int, timeout: Duration = .seconds(5)) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while values.count < count {
      if ContinuousClock.now >= deadline {
        throw GateTestTimeout(reason: "expected \(count) outcomes, saw \(values.count)")
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }
}

private actor GateStallReportRecorder {
  private var values: [AsyncSerialGate.StallReport] = []

  func record(_ value: AsyncSerialGate.StallReport) {
    values.append(value)
  }

  var recorded: [AsyncSerialGate.StallReport] { values }

  func waitForFirst(timeout: Duration = .seconds(5)) async throws -> AsyncSerialGate.StallReport {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while values.isEmpty {
      if ContinuousClock.now >= deadline {
        throw GateTestTimeout(reason: "no stall report arrived")
      }
      try await Task.sleep(for: .milliseconds(2))
    }
    return values[0]
  }
}

private struct GateTestTimeout: Error, CustomStringConvertible {
  var reason: String
  var description: String { "Timed out waiting on the gate under test: \(reason)" }
}

extension AsyncSerialGate {
  /// Test-only probe that waits until the queue reaches `count`, so a test can
  /// prove a waiter is genuinely enqueued before cancelling it instead of
  /// guessing with a sleep.
  fileprivate func waitForWaiterCount(_ count: Int, timeout: Duration = .seconds(5)) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while waiterCount != count {
      if ContinuousClock.now >= deadline {
        throw GateTestTimeout(reason: "expected \(count) waiters, saw \(waiterCount)")
      }
      try await Task.sleep(for: .milliseconds(2))
    }
  }
}
