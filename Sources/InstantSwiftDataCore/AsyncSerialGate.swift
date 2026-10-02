import Foundation
import IssueReporting
import os

/// Serializes the multi-await critical sections of ``InstantRuntime``.
///
/// Upstream parity note: the canonical Instant client
/// (`upstream/instant/client/packages/core/src/Reactor.js`) has no equivalent
/// primitive, because JavaScript runs the reactor on a single event loop and a
/// synchronous block of reactor work cannot interleave with another. Swift's
/// runtime is an actor whose `await` points are reentrant, so a critical
/// section that spans several awaits needs explicit serialization. This gate is
/// therefore a deliberate Swift-side adaptation with no upstream counterpart to
/// mirror; its cancellation contract follows the standard Swift structured
/// concurrency shape (`withTaskCancellationHandler` around a throwing
/// continuation) rather than inventing a local mechanism.
///
/// Queueing is first-in-first-out. Cancelling a queued caller removes it from
/// the middle of the queue without reordering the callers that remain.
actor AsyncSerialGate {
  /// Emitted when the gate has been held long enough that a caller waiting on
  /// it can no longer be explained by ordinary contention.
  struct StallReport: Sendable, Equatable {
    /// Which gate stalled, for example `operation` or `connection`.
    var label: String
    /// The function that acquired the gate and has not left it.
    var holder: String
    /// How long the current holder has held the gate.
    var holderHeldMilliseconds: Int
    /// The function that has been queued the longest.
    var longestWaitingOperation: String
    /// How long that caller has been queued.
    var longestWaitMilliseconds: Int
    /// How many callers are queued behind the holder.
    var waiterCount: Int
    /// How many times this stall has already been reported for this holder.
    var stallCount: Int
    /// What the holder was doing, when it names its phases (``setHolderPhase(_:)``).
    var holderPhase: String? = nil
  }

  /// Emitted when a caller acquires the gate after queuing past the wait threshold, so a slow
  /// local write names the holder, and the phase, it waited behind (#277).
  struct WaitReport: Sendable, Equatable {
    /// Which gate the caller waited on.
    var label: String
    /// The function that waited and now holds the gate.
    var waitingOperation: String
    /// How long it was queued.
    var waitMilliseconds: Int
    /// The holder that handed over the gate.
    var previousHolder: String
    /// The phase that holder named last, if it names its phases.
    var previousHolderPhase: String?
    /// How long that holder held the gate.
    var previousHolderHeldMilliseconds: Int
    /// Callers still queued after this handoff.
    var remainingWaiterCount: Int
  }

  // SAFETY: every stored property is read and written only on the enclosing
  // `AsyncSerialGate` actor, which owns the reference for its whole lifetime.
  private final class Waiter: @unchecked Sendable {
    enum State {
      /// The cancellation handler is installed but the continuation has not
      /// been created yet.
      case pending
      /// Queued and resumable.
      case waiting(CheckedContinuation<Void, any Error>)
      /// Cancelled before the continuation existed; resume as soon as it does.
      case cancelledBeforeWaiting
      /// Already resumed exactly once, by either `leave` or cancellation.
      case resumed
    }

    var state: State = .pending
    let operation: String
    let enqueuedAt: Date

    init(operation: String, enqueuedAt: Date) {
      self.operation = operation
      self.enqueuedAt = enqueuedAt
    }
  }

  private let label: String
  private let stallThresholdMilliseconds: UInt64
  private let waitReportThresholdMilliseconds: Int
  private let report: @Sendable (StallReport) -> Void
  private let waitReport: @Sendable (WaitReport) -> Void

  private var waiters: [Waiter] = []
  private var holderOperation: String? {
    didSet {
      let isHeld = holderOperation != nil
      heldFlag.withLock { $0 = isHeld }
    }
  }
  /// Mirrors `holderOperation != nil` for ``isHeldSnapshot``. Written only on this actor, in the same turn as
  /// `holderOperation`; the lock exists so a reader off the actor sees a whole value. It guards one Bool for one load
  /// or store: the "tiny, local isolation domain" a lock is for (Point-Free ep358 at 4:01). Contention grows with the
  /// work done under a lock (ep360 at 27:15), and there is none here.
  private let heldFlag = OSAllocatedUnfairLock(initialState: false)
  private var holderPhase: String?
  private var holderAcquiredAt: Date?
  private var stallCount = 0
  private var stallWatchdog: Task<Void, Never>?

  init(
    label: String,
    stallThresholdMilliseconds: UInt64 = 5_000,
    waitReportThresholdMilliseconds: Int = 250,
    report: (@Sendable (StallReport) -> Void)? = nil,
    waitReport: (@Sendable (WaitReport) -> Void)? = nil
  ) {
    self.label = label
    self.stallThresholdMilliseconds = stallThresholdMilliseconds
    self.waitReportThresholdMilliseconds = waitReportThresholdMilliseconds
    self.report = report ?? { AsyncSerialGate.reportStallLoudly($0) }
    self.waitReport = waitReport ?? { AsyncSerialGate.reportWait($0) }
  }

  deinit {
    stallWatchdog?.cancel()
  }

  /// Whether some caller currently holds the gate.
  var isHeld: Bool { holderOperation != nil }

  /// ``isHeld`` without a hop onto this actor (#403). It changes in the same actor turn as the holder, so a reader
  /// sees a value the gate really had; like `await isHeld`, the answer can change right after it is read. Use it only
  /// where that is fine, as `transact`'s supersession check is: the server apply it defers to revalidates under the
  /// operation gate.
  nonisolated var isHeldSnapshot: Bool { heldFlag.withLock { held in held } }

  /// How many callers are queued behind the holder.
  var waiterCount: Int { waiters.count }

  /// Acquires the gate, waiting if another caller holds it.
  ///
  /// This entry point cannot observe cancellation: resuming a queued caller
  /// without handing it ownership would let it run the critical section while
  /// another caller still holds the gate. Callers in a throwing context should
  /// prefer ``enterUnlessCancelled(operation:)``.
  func enter(operation: String = #function) async {
    if holderOperation == nil {
      acquire(operation: operation)
      return
    }
    // Only `enterUnlessCancelled` installs a cancellation handler, so no waiter
    // reached from here can be resumed with an error.
    try? await waitForBaton(operation: operation, honoringCancellation: false)
  }

  /// Acquires the gate, waiting if another caller holds it, and throws
  /// `CancellationError` if the calling task is cancelled while queued.
  ///
  /// A caller that throws here never acquired the gate and must not call
  /// ``leave()``. Cancellation is only honored *before* acquisition, so a
  /// critical section that has already started still runs to completion and
  /// cannot leave half-applied optimistic state behind.
  func enterUnlessCancelled(operation: String = #function) async throws {
    if Task.isCancelled { throw CancellationError() }
    if holderOperation == nil {
      acquire(operation: operation)
      return
    }
    try await waitForBaton(operation: operation, honoringCancellation: true)
  }

  /// Names what the current holder is doing, so stall and wait reports can say which part of a
  /// long critical section kept other callers queued. Cleared when the holder leaves.
  func setHolderPhase(_ phase: String?) {
    guard holderOperation != nil else { return }
    holderPhase = phase
  }

  /// Releases the gate, handing it to the longest-queued caller if there is one.
  func leave() {
    stallCount = 0
    let previousHolder = holderOperation
    let previousHolderPhase = holderPhase
    let previousHolderAcquiredAt = holderAcquiredAt
    holderPhase = nil
    while let waiter = waiters.first {
      waiters.removeFirst()
      guard case .waiting(let continuation) = waiter.state else {
        // Cancellation already resumed this waiter; it never took ownership.
        continue
      }
      waiter.state = .resumed
      let now = Date()
      holderOperation = waiter.operation
      holderAcquiredAt = now
      let waitMilliseconds = Self.milliseconds(since: waiter.enqueuedAt, to: now)
      if waitMilliseconds >= waitReportThresholdMilliseconds, let previousHolder {
        waitReport(
          WaitReport(
            label: label,
            waitingOperation: waiter.operation,
            waitMilliseconds: waitMilliseconds,
            previousHolder: previousHolder,
            previousHolderPhase: previousHolderPhase,
            previousHolderHeldMilliseconds: previousHolderAcquiredAt.map {
              Self.milliseconds(since: $0, to: now)
            } ?? 0,
            remainingWaiterCount: waiters.count
          )
        )
      }
      continuation.resume()
      return
    }

    holderOperation = nil
    holderAcquiredAt = nil
    stopStallWatchdog()
  }

  private func acquire(operation: String) {
    holderOperation = operation
    holderPhase = nil
    holderAcquiredAt = Date()
    stallCount = 0
  }

  private func waitForBaton(operation: String, honoringCancellation: Bool) async throws {
    let waiter = Waiter(operation: operation, enqueuedAt: Date())
    guard honoringCancellation else {
      return try await withCheckedThrowingContinuation { continuation in
        attach(continuation, to: waiter)
      }
    }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        attach(continuation, to: waiter)
      }
    } onCancel: {
      // The handler runs off the actor, so the removal has to hop back onto it.
      // Every transition below happens on the actor, which is what makes a
      // double resume between this hop and `leave()` impossible.
      Task { await self.cancelWaiter(waiter) }
    }
  }

  private func attach(_ continuation: CheckedContinuation<Void, any Error>, to waiter: Waiter) {
    switch waiter.state {
    case .cancelledBeforeWaiting:
      waiter.state = .resumed
      continuation.resume(throwing: CancellationError())
    case .pending:
      waiter.state = .waiting(continuation)
      waiters.append(waiter)
      startStallWatchdogIfNeeded()
    case .waiting, .resumed:
      reportIssue(
        """
        Instant's \(label) gate attached two continuations to one waiter. This \
        is a library bug in AsyncSerialGate; the waiter state machine should \
        make it unreachable.
        """
      )
      continuation.resume(throwing: CancellationError())
    }
  }

  private func cancelWaiter(_ waiter: Waiter) {
    switch waiter.state {
    case .pending:
      // Cancelled between installing the handler and creating the
      // continuation; `attach` resumes it as soon as it exists.
      waiter.state = .cancelledBeforeWaiting
    case .waiting(let continuation):
      waiters.removeAll { $0 === waiter }
      waiter.state = .resumed
      if waiters.isEmpty { stopStallWatchdog() }
      continuation.resume(throwing: CancellationError())
    case .cancelledBeforeWaiting, .resumed:
      break
    }
  }

  private func startStallWatchdogIfNeeded() {
    guard stallWatchdog == nil else { return }
    let intervalNanoseconds = stallThresholdMilliseconds * 1_000_000
    stallWatchdog = Task { [weak self] in
      while true {
        do {
          try await Task.sleep(nanoseconds: intervalNanoseconds)
        } catch {
          return
        }
        guard let self, await self.reportStallIfBlocked() else { return }
      }
    }
  }

  private func stopStallWatchdog() {
    stallWatchdog?.cancel()
    stallWatchdog = nil
  }

  private func reportStallIfBlocked() -> Bool {
    guard
      let longestWaiting = waiters.first,
      let holderOperation,
      let holderAcquiredAt
    else {
      stallWatchdog = nil
      return false
    }

    let now = Date()
    let longestWaitMilliseconds = Self.milliseconds(since: longestWaiting.enqueuedAt, to: now)
    guard longestWaitMilliseconds >= Int(stallThresholdMilliseconds) else {
      // The current holder only just took the baton. Keep watching instead of
      // reporting a stall that has not happened yet.
      return true
    }

    stallCount += 1
    report(
      StallReport(
        label: label,
        holder: holderOperation,
        holderHeldMilliseconds: Self.milliseconds(since: holderAcquiredAt, to: now),
        longestWaitingOperation: longestWaiting.operation,
        longestWaitMilliseconds: longestWaitMilliseconds,
        waiterCount: waiters.count,
        stallCount: stallCount,
        holderPhase: holderPhase
      )
    )
    return true
  }

  private static func milliseconds(since start: Date, to end: Date) -> Int {
    Int((end.timeIntervalSince(start) * 1_000).rounded())
  }

  /// A slow handoff is evidence, not a library bug: logged, never `reportIssue`d.
  private static func reportWait(_ wait: WaitReport) {
    let phase = wait.previousHolderPhase.map { " (phase: \($0))" } ?? ""
    InstantDiagnostics.shared.record(
      wait.waitMilliseconds >= 1_000 ? .warning : .info,
      subsystem: "instant-swift-data-core",
      category: "concurrency",
      event: "serial-gate.waited",
      message: """
        \(wait.waitingOperation) waited \(wait.waitMilliseconds) ms for Instant's \(wait.label) \
        gate behind \(wait.previousHolder)\(phase), which held it \
        \(wait.previousHolderHeldMilliseconds) ms.
        """,
      metadata: [
        "gate": wait.label,
        "waitingOperation": wait.waitingOperation,
        "waitMilliseconds": String(wait.waitMilliseconds),
        "previousHolder": wait.previousHolder,
        "previousHolderPhase": wait.previousHolderPhase ?? "",
        "previousHolderHeldMilliseconds": String(wait.previousHolderHeldMilliseconds),
        "remainingWaiterCount": String(wait.remainingWaiterCount),
      ]
    )
  }

  private static func reportStallLoudly(_ stall: StallReport) {
    let phase = stall.holderPhase.map { " (phase: \($0))" } ?? ""
    let message = """
      Instant's \(stall.label) gate has been held by \(stall.holder)\(phase) for \
      \(stall.holderHeldMilliseconds) ms. \(stall.waiterCount) caller(s) are \
      queued behind it; \(stall.longestWaitingOperation) has waited \
      \(stall.longestWaitMilliseconds) ms. Every transact, query, observe, and \
      connection-status call on this gate is blocked until \(stall.holder) \
      calls leave(). Look at \(stall.holder) in \
      Sources/InstantSwiftDataCore/InstantRuntime.swift for an await that never \
      returns or an early return that skips its leave().
      """
    InstantDiagnostics.shared.record(
      .critical,
      subsystem: "instant-swift-data-core",
      category: "concurrency",
      event: "serial-gate.stalled",
      message: message,
      metadata: [
        "gate": stall.label,
        "holder": stall.holder,
        "holderPhase": stall.holderPhase ?? "",
        "holderHeldMilliseconds": String(stall.holderHeldMilliseconds),
        "longestWaitingOperation": stall.longestWaitingOperation,
        "longestWaitMilliseconds": String(stall.longestWaitMilliseconds),
        "waiterCount": String(stall.waiterCount),
        "stallCount": String(stall.stallCount),
      ]
    )
    reportIssue(message)
  }
}
