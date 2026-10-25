// History:
// - 2026-10-23: a holder may name the entities it writes until its store commit, so a read made without the gate
//   waits only for a holder that may be writing what it read (#1006).
// - 2026-10-24: an optional timeline reports every request, acquisition, release and cancellation, so an exercise can
//   measure each caller's wait and each holder's hold, the short ones too (#1074).
// - 2026-10-25: a caller names what it writes as it enters, and the gate sets it as it hands the caller the gate, so a
//   holder that writes no store facts never reads as writing everything (#1133).

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
/// Queueing is first-in-first-out within a ``Priority``: when the gate is handed over, the waiter with the highest
/// priority goes next, and a waiter moves up one priority for every ``agingMilliseconds`` it has queued, so background
/// work is never starved (freeze-185 item 2). Cancelling a queued caller removes it from the middle of the queue
/// without reordering the callers that remain.
actor AsyncSerialGate {
  /// Which queued caller takes the gate next. On a phone a transcript write queued behind server catch-ups and
  /// hydrations, first come first served (freeze-185, 13:17:34): a local write or a read a caller awaits now goes ahead
  /// of background work.
  enum Priority: Int, Comparable, Sendable, CustomStringConvertible {
    /// Work no caller waits on: a prune, a retry window, an unbounded listing. A server apply is not: later frames,
    /// the writes' acknowledgements among them, wait for it, and its commit's work grows with every write it waits for.
    case background = 0
    /// Everything else.
    case standard = 1
    /// A local write, or a read a caller awaits.
    case interactive = 2

    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.rawValue < rhs.rawValue
    }

    var description: String {
      switch self {
      case .background: "background"
      case .standard: "standard"
      case .interactive: "interactive"
      }
    }
  }

  /// The gate's state as of now, read without a hop onto the gate (freeze-185 item 7), for an app's watchdog.
  struct Snapshot: Sendable, Equatable {
    /// The function that holds the gate, or nil when it is free.
    var holder: String?
    /// What the holder said it is doing, when it names its phases.
    var holderPhase: String?
    /// When the holder took the gate.
    var heldSince: Date?
    /// How many callers are queued.
    var waiterCount: Int
    /// When the longest-queued caller started waiting.
    var longestWaitingSince: Date?
  }
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
    /// Whose gate it is, when the gate was given an owner: the runtime's app ID for its operation gate.
    var owner: String? = nil
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
    /// The priority the caller queued with.
    var waitingPriority: Priority = .standard
    /// Whose gate it is, when the gate was given an owner: the runtime's app ID for its operation gate.
    var owner: String? = nil
  }

  /// One step in the gate's life, reported to the timeline closure given at `init` (#1074). The wait and stall reports
  /// name only waits past their thresholds; a timeline names every request, acquisition, release and cancellation, so
  /// an exercise can measure each caller's wait (acquisition minus request) and each holder's hold (release minus
  /// acquisition) under contention, the short ones too.
  struct TimelineEvent: Sendable, Equatable {
    enum Kind: String, Sendable {
      /// A caller asked for the gate.
      case requested
      /// The caller took the gate: at once when it was free, or when the holder before it left.
      case acquired
      /// The holder left.
      case released
      /// A queued caller was cancelled and never took the gate.
      case cancelled
    }

    var kind: Kind
    /// The gate's label, such as `operation`.
    var gate: String
    /// One per call to enter, shared by its request, its acquisition, and its release or cancellation.
    var ticket: UInt64
    /// The caller, as the wait and stall reports name it.
    var operation: String
    var priority: Priority
    /// On a release, the phase the holder named last.
    var phase: String? = nil
    /// When the step happened, on the gate's monotonic clock.
    var uptimeNanoseconds: UInt64
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
    let priority: Priority
    let enqueuedAt: Date
    let ticket: UInt64
    /// What the caller said it writes as it entered (``markHolderWrites(_:)``), set as it takes the gate (#1133).
    let writes: Set<String>?

    init(operation: String, priority: Priority, enqueuedAt: Date, ticket: UInt64, writes: Set<String>?) {
      self.operation = operation
      self.priority = priority
      self.enqueuedAt = enqueuedAt
      self.writes = writes
      self.ticket = ticket
    }

    var isWaiting: Bool {
      if case .waiting = state { return true }
      return false
    }
  }

  /// The parts of ``Snapshot`` the actor writes, behind a lock so a reader off the actor sees a whole value.
  private struct SnapshotState: Sendable {
    var holder: String?
    var holderPhase: String?
    var heldSince: Date?
    var waiterCount = 0
    var longestWaitingSince: Date?
  }

  private let label: String
  /// Whose gate this is, for its reports: two runtimes in one process each log an `operation` gate.
  private let owner: String?
  private let stallThresholdMilliseconds: UInt64
  private let waitReportThresholdMilliseconds: Int
  /// A queued caller moves up one ``Priority`` for every interval of this length it has waited.
  private let agingMilliseconds: Int
  private let report: @Sendable (StallReport) -> Void
  private let waitReport: @Sendable (WaitReport) -> Void

  /// Queued callers in the order they arrived.
  private var waiters: [Waiter] = [] {
    didSet {
      let count = waiters.count
      let longestWaitingSince = waiters.first?.enqueuedAt
      snapshotState.withLock {
        $0.waiterCount = count
        $0.longestWaitingSince = longestWaitingSince
      }
    }
  }
  private var holderOperation: String? {
    didSet {
      let holder = holderOperation
      snapshotState.withLock { $0.holder = holder }
    }
  }
  /// Mirrors the holder, its phase, its start and the queue for ``isHeldSnapshot`` and ``snapshot``. Written only on
  /// this actor, in the same turn as the state it mirrors; the lock exists so a reader off the actor sees a whole
  /// value. It guards one small value for one load or store: the "tiny, local isolation domain" a lock is for
  /// (Point-Free ep358 at 4:01). Contention grows with the work done under a lock (ep360 at 27:15), and there is none
  /// here.
  private let snapshotState = OSAllocatedUnfairLock(initialState: SnapshotState())
  private var holderPhase: String? {
    didSet {
      let phase = holderPhase
      snapshotState.withLock { $0.holderPhase = phase }
    }
  }
  /// The phase the holder named with ``markHolderPhase(_:)``, without a hop onto this actor (#473). Written by the
  /// holder between its enter and its leave, read and cleared on this actor; the lock makes each read and write whole.
  private let markedPhase = OSAllocatedUnfairLock<String?>(initialState: nil)
  /// The entities the holder writes from its SQLite save to its store commit, as it named them with
  /// ``markHolderWrites(_:)`` (#1006); nil until it does. Written by the holder, cleared on this actor when the gate
  /// changes hands.
  private let markedWrites = OSAllocatedUnfairLock<Set<String>?>(initialState: nil)
  private var holderAcquiredAt: Date? {
    didSet {
      let heldSince = holderAcquiredAt
      snapshotState.withLock { $0.heldSince = heldSince }
    }
  }
  private var stallCount = 0
  /// Whether the current holder's stall was reported. A holder is reported once, however long it holds the gate
  /// (freeze-185 item 2): the Mac logged a critical stall line every 5 s through a 331 s server catch-up. The next
  /// holder's wait report says how long the gate was held.
  private var stallReportedForHolder = false
  private var stallWatchdog: Task<Void, Never>?

  /// The clock waits and holds are timed by. A test that asserts no wait is reported passes one that stands still:
  /// on the wall clock, a quick handoff took over the 1 s report threshold under the whole test bundle's load (#1021).
  private let currentDate: @Sendable () -> Date

  /// Receives every step of the gate's life (#1074), on this actor and in the same turn as the step, so it must only
  /// record. Nil in production: each step then costs one nil check.
  private let timeline: (@Sendable (TimelineEvent) -> Void)?
  /// The monotonic clock the timeline is stamped with; a test passes one it moves by hand.
  private let uptimeNanoseconds: @Sendable () -> UInt64
  /// The last ticket given out; each call to enter takes the next.
  private var lastTicket: UInt64 = 0
  /// The holder's ticket and priority, for its release on the timeline.
  private var holderTicket: UInt64 = 0
  private var holderPriority: Priority = .standard

  init(
    label: String,
    owner: String? = nil,
    stallThresholdMilliseconds: UInt64 = 5_000,
    waitReportThresholdMilliseconds: Int = 250,
    agingMilliseconds: Int = 2_000,
    now: @escaping @Sendable () -> Date = { Date() },
    report: (@Sendable (StallReport) -> Void)? = nil,
    waitReport: (@Sendable (WaitReport) -> Void)? = nil,
    timeline: (@Sendable (TimelineEvent) -> Void)? = nil,
    uptimeNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
  ) {
    self.label = label
    self.owner = owner
    self.currentDate = now
    self.stallThresholdMilliseconds = stallThresholdMilliseconds
    self.waitReportThresholdMilliseconds = waitReportThresholdMilliseconds
    self.agingMilliseconds = agingMilliseconds
    self.report = report ?? { AsyncSerialGate.reportStallLoudly($0) }
    self.waitReport = waitReport ?? { AsyncSerialGate.reportWait($0) }
    self.timeline = timeline
    self.uptimeNanoseconds = uptimeNanoseconds
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
  nonisolated var isHeldSnapshot: Bool { snapshotState.withLock { $0.holder != nil } }

  /// The holder, its phase and start, and the queue, without a hop onto this actor (freeze-185 item 7). Like
  /// ``isHeldSnapshot``, the answer can change right after it is read.
  nonisolated var snapshot: Snapshot {
    let state = snapshotState.withLock { $0 }
    let phase = markedPhase.withLock { $0 }
    return Snapshot(
      holder: state.holder,
      holderPhase: state.holder == nil ? nil : state.holderPhase ?? phase,
      heldSince: state.heldSince,
      waiterCount: state.waiterCount,
      longestWaitingSince: state.longestWaitingSince
    )
  }

  /// How many callers are queued behind the holder.
  var waiterCount: Int { waiters.count }

  /// Acquires the gate, waiting if another caller holds it.
  ///
  /// This entry point cannot observe cancellation: resuming a queued caller
  /// without handing it ownership would let it run the critical section while
  /// another caller still holds the gate. Callers in a throwing context should
  /// prefer ``enterUnlessCancelled(operation:priority:writes:)``.
  ///
  /// - Parameter writes: The entities the caller writes before its store commit, as ``markHolderWrites(_:)`` names
  ///   them: empty for none, nil for any. Set as the caller takes the gate, so a caller that writes no store facts never
  ///   reads as writing everything, even before its first line runs (#1133).
  func enter(operation: String = #function, priority: Priority = .standard, writes: Set<String>? = nil) async {
    let ticket = request(operation: operation, priority: priority)
    if holderOperation == nil {
      acquire(operation: operation, priority: priority, ticket: ticket, writes: writes)
      return
    }
    // Only `enterUnlessCancelled` installs a cancellation handler, so no waiter
    // reached from here can be resumed with an error.
    try? await waitForBaton(
      operation: operation, priority: priority, ticket: ticket, writes: writes, honoringCancellation: false
    )
  }

  /// Acquires the gate, waiting if another caller holds it, and throws
  /// `CancellationError` if the calling task is cancelled while queued.
  ///
  /// A caller that throws here never acquired the gate and must not call
  /// ``leave()``. Cancellation is only honored *before* acquisition, so a
  /// critical section that has already started still runs to completion and
  /// cannot leave half-applied optimistic state behind.
  func enterUnlessCancelled(
    operation: String = #function,
    priority: Priority = .standard,
    writes: Set<String>? = nil
  ) async throws {
    if Task.isCancelled { throw CancellationError() }
    let ticket = request(operation: operation, priority: priority)
    if holderOperation == nil {
      acquire(operation: operation, priority: priority, ticket: ticket, writes: writes)
      return
    }
    try await waitForBaton(
      operation: operation, priority: priority, ticket: ticket, writes: writes, honoringCancellation: true
    )
  }

  /// Names what the current holder is doing, so stall and wait reports can say which part of a
  /// long critical section kept other callers queued. Cleared when the holder leaves.
  func setHolderPhase(_ phase: String?) {
    guard holderOperation != nil else { return }
    holderPhase = phase
  }

  /// ``setHolderPhase(_:)`` without a hop onto this actor (#473), for a holder on a hot path: a local write names its
  /// phases this way, so a stall says which one held the gate, at the cost of a lock instead of an actor turn. Call it
  /// only while holding the gate. Cleared when the holder leaves.
  nonisolated func markHolderPhase(_ phase: String?) {
    markedPhase.withLock { $0 = phase }
  }

  /// Names the entities the holder writes from now until its store commit: an empty set for none, nil for any (#1006).
  /// A read made without the gate then waits for this holder only when it may be writing what the read paired
  /// (``holderMayWrite(any:)``). A holder that names nothing is taken to write everything, as every holder was before.
  /// Call it only while holding the gate; it is cleared when the holder leaves.
  nonisolated func markHolderWrites(_ entityIDs: Set<String>?) {
    markedWrites.withLock { $0 = entityIDs }
  }

  /// Whether a holder may be writing any of `entityIDs`: false when no caller holds the gate, or when the holder named
  /// its writes and none of `entityIDs` is among them. Like ``isHeldSnapshot``, the answer can change right after it is
  /// read: a new holder starts by naming nothing, so it reads as writing everything.
  nonisolated func holderMayWrite(any entityIDs: Set<String>) -> Bool {
    guard isHeldSnapshot else { return false }
    guard let writes = markedWrites.withLock({ $0 }) else { return true }
    return !writes.isDisjoint(with: entityIDs)
  }

  /// What the holder named last with ``markHolderWrites(_:)`` or as it entered: nil for any. Read it only while
  /// holding the gate, to name something else for a while and then name this again.
  nonisolated var holderWrites: Set<String>? {
    markedWrites.withLock { $0 }
  }

  /// The phase the holder named last, by either entry point.
  private var currentHolderPhase: String? {
    holderPhase ?? markedPhase.withLock { $0 }
  }

  /// Releases the gate, handing it to the queued caller that goes next (``nextWaiterIndex(at:)``), if there is one.
  func leave() {
    stallCount = 0
    stallReportedForHolder = false
    let previousHolder = holderOperation
    let previousHolderPhase = currentHolderPhase
    let previousHolderAcquiredAt = holderAcquiredAt
    if let previousHolder {
      record(.released, ticket: holderTicket, operation: previousHolder, priority: holderPriority, phase: previousHolderPhase)
    }
    holderPhase = nil
    markedPhase.withLock { $0 = nil }
    markedWrites.withLock { $0 = nil }
    // Cancellation already resumed any waiter that is not waiting; it never took ownership.
    if waiters.contains(where: { !$0.isWaiting }) {
      waiters.removeAll { !$0.isWaiting }
    }
    let now = currentDate()
    if let index = nextWaiterIndex(at: now) {
      let waiter = waiters.remove(at: index)
      guard case .waiting(let continuation) = waiter.state else {
        reportIssue("Instant's \(label) gate chose a waiter that was not waiting; AsyncSerialGate has a bug.")
        holderOperation = nil
        holderAcquiredAt = nil
        stopStallWatchdog()
        return
      }
      waiter.state = .resumed
      // Before the holder: a read that sees the new holder sees what it said it writes (#1133).
      markedWrites.withLock { $0 = waiter.writes }
      holderOperation = waiter.operation
      holderAcquiredAt = now
      holderTicket = waiter.ticket
      holderPriority = waiter.priority
      record(.acquired, ticket: waiter.ticket, operation: waiter.operation, priority: waiter.priority)
      let waitMilliseconds = Self.milliseconds(since: waiter.enqueuedAt, to: now)
      // The report runs off this actor (#473): it records a diagnostics line and runs the app's handlers, and the
      // next holder, which resumes on this actor, must never wait for them.
      if waitMilliseconds >= waitReportThresholdMilliseconds, let previousHolder {
        let wait = WaitReport(
          label: label,
          waitingOperation: waiter.operation,
          waitMilliseconds: waitMilliseconds,
          previousHolder: previousHolder,
          previousHolderPhase: previousHolderPhase,
          previousHolderHeldMilliseconds: previousHolderAcquiredAt.map {
            Self.milliseconds(since: $0, to: now)
          } ?? 0,
          remainingWaiterCount: waiters.count,
          waitingPriority: waiter.priority,
          owner: owner
        )
        let waitReport = self.waitReport
        Task.detached(priority: .utility) { waitReport(wait) }
      }
      if waiters.isEmpty { stopStallWatchdog() }
      continuation.resume()
      return
    }

    holderOperation = nil
    holderAcquiredAt = nil
    stopStallWatchdog()
  }

  /// The queued caller that takes the gate next: the highest rank, where a caller's rank is its priority plus one for
  /// every ``agingMilliseconds`` it has waited, and the longest-queued caller among equal ranks. So within a priority
  /// the queue stays first in, first out, and a background caller that waited long enough goes ahead of newer
  /// interactive ones.
  private func nextWaiterIndex(at now: Date) -> Int? {
    var best: (index: Int, rank: Int)?
    for (index, waiter) in waiters.enumerated() where waiter.isWaiting {
      let waited = max(0, Self.milliseconds(since: waiter.enqueuedAt, to: now))
      let rank = waiter.priority.rawValue + (agingMilliseconds > 0 ? waited / agingMilliseconds : 0)
      if let current = best, rank <= current.rank { continue }
      best = (index, rank)
    }
    return best?.index
  }

  private func acquire(operation: String, priority: Priority, ticket: UInt64, writes: Set<String>?) {
    markedWrites.withLock { $0 = writes }
    holderOperation = operation
    holderPhase = nil
    markedPhase.withLock { $0 = nil }
    holderAcquiredAt = currentDate()
    holderTicket = ticket
    holderPriority = priority
    stallCount = 0
    stallReportedForHolder = false
    record(.acquired, ticket: ticket, operation: operation, priority: priority)
  }

  /// Gives a caller its ticket and reports its request.
  private func request(operation: String, priority: Priority) -> UInt64 {
    lastTicket &+= 1
    record(.requested, ticket: lastTicket, operation: operation, priority: priority)
    return lastTicket
  }

  private func record(
    _ kind: TimelineEvent.Kind,
    ticket: UInt64,
    operation: String,
    priority: Priority,
    phase: String? = nil
  ) {
    guard let timeline else { return }
    timeline(
      TimelineEvent(
        kind: kind,
        gate: label,
        ticket: ticket,
        operation: operation,
        priority: priority,
        phase: phase,
        uptimeNanoseconds: uptimeNanoseconds()
      )
    )
  }

  private func waitForBaton(
    operation: String,
    priority: Priority,
    ticket: UInt64,
    writes: Set<String>?,
    honoringCancellation: Bool
  ) async throws {
    let waiter = Waiter(
      operation: operation, priority: priority, enqueuedAt: currentDate(), ticket: ticket, writes: writes
    )
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
      record(.cancelled, ticket: waiter.ticket, operation: waiter.operation, priority: waiter.priority)
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
      record(.cancelled, ticket: waiter.ticket, operation: waiter.operation, priority: waiter.priority)
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

    let now = currentDate()
    let longestWaitMilliseconds = Self.milliseconds(since: longestWaiting.enqueuedAt, to: now)
    guard longestWaitMilliseconds >= Int(stallThresholdMilliseconds) else {
      // The current holder only just took the baton. Keep watching instead of
      // reporting a stall that has not happened yet.
      return true
    }
    // One report per holder; keep watching, so the next holder's stall is reported too.
    guard !stallReportedForHolder else { return true }
    stallReportedForHolder = true

    stallCount += 1
    // Reported off this actor (#473): the stall line is a critical diagnostics entry plus `reportIssue`, and on the
    // iPhone writing it held the gate's actor for seconds while the holder it reports waited to leave.
    let stall = StallReport(
      label: label,
      holder: holderOperation,
      holderHeldMilliseconds: Self.milliseconds(since: holderAcquiredAt, to: now),
      longestWaitingOperation: longestWaiting.operation,
      longestWaitMilliseconds: longestWaitMilliseconds,
      waiterCount: waiters.count,
      stallCount: stallCount,
      holderPhase: currentHolderPhase,
      owner: owner
    )
    let report = self.report
    Task.detached(priority: .utility) { report(stall) }
    return true
  }

  private static func milliseconds(since start: Date, to end: Date) -> Int {
    Int((end.timeIntervalSince(start) * 1_000).rounded())
  }

  /// A slow handoff is evidence, not a library bug: logged, never `reportIssue`d.
  private static func reportWait(_ wait: WaitReport) {
    let phase = wait.previousHolderPhase.map { " (phase: \($0))" } ?? ""
    var metadata: [String: String] = [
      "gate": wait.label,
      "waitingOperation": wait.waitingOperation,
      "waitMilliseconds": String(wait.waitMilliseconds),
      "previousHolder": wait.previousHolder,
      "previousHolderPhase": wait.previousHolderPhase ?? "",
      "previousHolderHeldMilliseconds": String(wait.previousHolderHeldMilliseconds),
      "remainingWaiterCount": String(wait.remainingWaiterCount),
      "waitingPriority": wait.waitingPriority.description,
    ]
    if let owner = wait.owner {
      metadata["owner"] = owner
    }
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
      metadata: metadata
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
    var metadata: [String: String] = [
      "gate": stall.label,
      "holder": stall.holder,
      "holderPhase": stall.holderPhase ?? "",
      "holderHeldMilliseconds": String(stall.holderHeldMilliseconds),
      "longestWaitingOperation": stall.longestWaitingOperation,
      "longestWaitMilliseconds": String(stall.longestWaitMilliseconds),
      "waiterCount": String(stall.waiterCount),
      "stallCount": String(stall.stallCount),
    ]
    if let owner = stall.owner {
      metadata["owner"] = owner
    }
    InstantDiagnostics.shared.record(
      .critical,
      subsystem: "instant-swift-data-core",
      category: "concurrency",
      event: "serial-gate.stalled",
      message: message,
      metadata: metadata
    )
    reportIssue(message)
  }
}
