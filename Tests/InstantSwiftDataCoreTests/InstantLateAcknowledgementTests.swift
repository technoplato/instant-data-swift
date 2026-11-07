// History:
// - 2026-11-06: created (#1942). The Mac's after-measurement on 1.9.80 never reached its new keep: the one late write
//   there was kept by #296's frame deferral, because a frame was being applied at its deadline. These tests pass a
//   write's deadline with no frame being applied, and tell a slow session from a quiet one by a single frame in the
//   interval before it. They use only API v1.9.79 also has, so the same file runs against both releases.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A write's missed acknowledgement deadline asks whether its session went quiet, not whether the write was lost
/// (#1942).
///
/// On a busy Mac one write's answer came 6.3 s after it was sent while its session kept delivering frames; the expiry of
/// its claim replaced the session 16 times in 13 minutes, and the next session accepted the same write 1.6 s later.
/// Upstream `Reactor.js` (`_sendMutation`, at e71017612aed4031710a35e2fcace30d38d557ac) fails only the transaction when
/// its 6 s timer fires and never closes the socket for it. Swift keeps the write durable, so the deadline decides
/// between two sessions that owe the same answer:
///
/// - Slow: the applier took a frame in the interval before the deadline. The claim is kept one interval later
///   (`outbox.mutation.ack-late-kept`), and the answer settles the write on the connection it was sent on.
/// - Quiet: the applier took nothing for the whole interval, as on a half-open socket. The session is replaced
///   (`outbox.mutation.ack-timeout-batch`), and the write goes out again on the next one.
///
/// Both tests share one history but for a frame 3 s before the deadline. In both, no frame is being applied when the
/// deadline passes, so #296's deferral, which keeps claims only while a frame is being applied, can keep neither.
@Suite(.serialized)
struct InstantLateAcknowledgementTests {
  /// The slow session. v1.9.79 replaced every session whose write passed its deadline while no frame was being applied,
  /// so there this ends exactly as the quiet session does.
  @Test
  func aLateAnswerWithNoFrameBeingAppliedKeepsASessionThatStillDeliversFrames() async throws {
    let run = try await OwedAnswerRun(prefix: "late-ack-slow")
    defer { run.stopCapturing() }

    run.clock.advance(by: 3_000)
    try await run.deliverAFrameTheApplierTakes()
    run.clock.advance(by: 3_000)
    let outcome = try await run.passTheDeadlineAndSettleTheWrite()

    expectNoDifference(
      outcome,
      OwedAnswerOutcome(
        verdict: .kept,
        keptLate: [run.writeID],
        expiredAsTimeouts: [],
        keptClaimDeadline: 112_000,
        connections: 1,
        offeredOnFirstSession: [run.writeID],
        offeredOnReplacement: [],
        pendingWrites: 0
      ),
      "The session took a frame 3 s before the deadline: the answer is late, not lost."
    )
    #expect(outcome.verdict == .kept, "Kept by the late keep, with no frame being applied at the deadline.")
    #expect(outcome.connections == 1)
    let quiet = run.capture.entries(named: "outbox.mutation.ack-late-kept")
      .map { Int64($0.metadata["quietMilliseconds"] ?? "") }
    #expect(quiet.allSatisfy { ($0 ?? .max) < 6_000 }, "The keep saw a frame within one interval: \(quiet)")
    _ = try? await run.runtime.closeConnection()
  }

  /// The quiet session. v1.9.79 replaced it the same way, so this passes there too: it guards that 1.9.80's keep did not
  /// make a session that stopped delivering frames immortal.
  @Test
  func aSessionThatTookNoFrameForAWholeIntervalIsReplacedAtTheDeadline() async throws {
    var outcome: OwedAnswerOutcome?
    // The replacement reports the expired claim as an issue. The whole run sits inside, because the runtime's tasks
    // carry the known-issue scope they were started in.
    try await withKnownIssue {
      let run = try await OwedAnswerRun(prefix: "late-ack-quiet")
      defer { run.stopCapturing() }

      run.clock.advance(by: 3_000)
      // The session delivers nothing in the interval.
      run.clock.advance(by: 3_000)
      outcome = try await run.passTheDeadlineAndSettleTheWrite()
      _ = try? await run.runtime.closeConnection()
    } matching: { issue in
      issue.description.contains("did not acknowledge")
    }

    let writeID = OwedAnswerRun.writeID(prefix: "late-ack-quiet")
    expectNoDifference(
      outcome,
      OwedAnswerOutcome(
        verdict: .replaced,
        keptLate: [],
        expiredAsTimeouts: [writeID],
        keptClaimDeadline: nil,
        connections: 2,
        offeredOnFirstSession: [writeID],
        offeredOnReplacement: [writeID],
        pendingWrites: 0
      ),
      "Nothing for a whole interval: the session is replaced, and the write is answered on the next one."
    )
    #expect(outcome?.verdict == .replaced, "A session that went quiet must still be replaced.")
    #expect(outcome?.connections == 2)
  }
}

private enum OwedAnswerVerdict: Equatable {
  /// `outbox.mutation.ack-late-kept` named the write: its claim moved one interval later, on the same session.
  case kept
  /// `outbox.mutation.ack-timeout-batch` named the write: its claim expired, and the session was replaced.
  case replaced
}

private struct OwedAnswerOutcome: Equatable {
  var verdict: OwedAnswerVerdict
  var keptLate: [String]
  var expiredAsTimeouts: [String]
  /// The deadline the kept claim moved to, read right after the keep; nil when nothing was kept.
  var keptClaimDeadline: Int64?
  var connections: Int
  var offeredOnFirstSession: [String]
  var offeredOnReplacement: [String]
  var pendingWrites: Int
}

/// One runtime with one write owed an answer (#1942): saved before the session opens, and sent by the first delivery
/// pass at 100,000 ms on the test's clock, so its deadline is 106,000 ms. The clock, the deadline wakes and the
/// reconnect delays are the test's: nothing waits on wall time.
///
/// Self-contained and built only on API v1.9.79 also has, so that one file shows both releases' behaviour.
private struct OwedAnswerRun: Sendable {
  let writeID: String
  let clock: OwedAnswerClock
  let runtime: InstantRuntime
  let capture: OwedAnswerDiagnostics
  private let deadlineSleep: OwedAnswerHeldSleep
  private let reconnectSleep: OwedAnswerHeldSleep
  private let firstSession: LiveReactorParitySession
  private let replacementSession: LiveReactorParitySession
  private let transport: LiveReactorParityTransport
  private let reads: OwedAnswerReaderRequests
  private let diagnosticsHandler: UUID

  static func writeID(prefix: String) -> String {
    "tx-\(prefix)"
  }

  init(prefix: String) async throws {
    let writeID = Self.writeID(prefix: prefix)
    let clock = OwedAnswerClock(milliseconds: 100_000)
    let deadlineSleep = OwedAnswerHeldSleep()
    let reconnectSleep = OwedAnswerHeldSleep()
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "\(prefix)-first")
    ])
    let replacementSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "\(prefix)-replacement")
    ])
    let transport = LiveReactorParityTransport(sessions: [firstSession, replacementSession])
    let reads = OwedAnswerReaderRequests()
    let capture = OwedAnswerDiagnostics(prefix: prefix)
    let cacheURL = try InstantTestScratch.directory("InstantLateAcknowledgementTests")
      .appendingPathComponent("state.sqlite")
    var configuration = InstantRuntimeConfiguration(
      appID: "late-acknowledgement-\(prefix)",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { clock.now() },
      liveTransport: transport.transport.mapSessions { reads.counting($0) }
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveMutationDeadlineSleep = { milliseconds in
      try await deadlineSleep.sleep(milliseconds: milliseconds)
    }
    configuration.liveReconnectSleep = { milliseconds in
      try await reconnectSleep.sleep(milliseconds: milliseconds)
    }
    let diagnosticsHandler = InstantDiagnostics.shared.addHandler { capture.record($0) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: writeID,
        operations: [
          .insert(
            InstantTriple(
              entityID: "\(prefix)-todo",
              attributeID: "todos/text",
              value: .string("owed an answer"),
              txID: writeID,
              txTime: clock.now()
            )
          )
        ]
      )
    )
    _ = try await runtime.connect()
    try await instantLiveWithTimeout(
      operation: "wait for the write's offer and its deadline wake",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) {
      try await firstSession.waitForSentMessageCount(2)
      while true {
        try Task.checkCancellation()
        if await deadlineSleep.hasPending(), await runtime.automaticMutationPumpIsIdleForTesting() { return }
        await Task.yield()
      }
    }
    let deadline = try await runtime.persistence.outboxDeliveryClaimForTesting(id: writeID)?.deadlineMilliseconds
    expectNoDifference(deadline, 106_000, "Offered at 100,000 ms, first in flight: 6 s.")

    self.writeID = writeID
    self.clock = clock
    self.runtime = runtime
    self.capture = capture
    self.deadlineSleep = deadlineSleep
    self.reconnectSleep = reconnectSleep
    self.firstSession = firstSession
    self.replacementSession = replacementSession
    self.transport = transport
    self.reads = reads
    self.diagnosticsHandler = diagnosticsHandler
  }

  func stopCapturing() {
    InstantDiagnostics.shared.removeHandler(diagnosticsHandler)
  }

  /// One frame the session delivers, applied before this returns. The runtime ignores its op; what the deadline reads is
  /// that the applier took a frame.
  func deliverAFrameTheApplierTakes() async throws {
    let handedOver = reads.counts.handedOver
    await firstSession.enqueue(InstantLiveMessage(op: "frame-for-test", clientEventID: nil, fields: [:]))
    try await instantLiveWithTimeout(
      operation: "wait for the session's applier to apply the frame",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) { [reads, runtime] in
      // The reader asks for its next frame only once it has handed this one to the applier, and a waiting applier has
      // applied every frame it was handed.
      while reads.counts.calls < handedOver + 2 {
        try Task.checkCancellation()
        await Task.yield()
      }
      while await !runtime.liveReceiverIsWaitingForAFrameForTesting() {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  /// Passes the write's deadline, which the test's clock has reached, then lets the write settle: a kept write is
  /// answered on its own connection 1.6 s past the deadline, as the incident's write was on the next session; a write
  /// whose session was replaced is answered on the replacement.
  func passTheDeadlineAndSettleTheWrite() async throws -> OwedAnswerOutcome {
    let frameBeingApplied = await runtime.liveFrameBeingAppliedForTesting()
    expectNoDifference(
      frameBeingApplied,
      nil,
      "No frame is being applied as the deadline passes, so #296's deferral cannot keep the session."
    )
    #expect(frameBeingApplied == nil)
    await deadlineSleep.resumePending()
    let verdict = try await instantLiveWithTimeout(
      operation: "wait for the deadline pass to keep the write's claim or replace its session",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) { [capture] () async throws -> OwedAnswerVerdict in
      while true {
        try Task.checkCancellation()
        if !capture.entries(named: "outbox.mutation.ack-late-kept").isEmpty { return .kept }
        if !capture.entries(named: "outbox.mutation.ack-timeout-batch").isEmpty { return .replaced }
        await Task.yield()
      }
    }

    var keptClaimDeadline: Int64?
    switch verdict {
    case .kept:
      keptClaimDeadline = try await runtime.persistence.outboxDeliveryClaimForTesting(id: writeID)?
        .deadlineMilliseconds
      clock.advance(by: 1_600)
      try await answerTheWrite(on: firstSession)
    case .replaced:
      try await instantLiveWithTimeout(
        operation: "wait for the replacement session to take the write",
        timeoutMilliseconds: InstantTestWait.hangMilliseconds
      ) { [reconnectSleep, replacementSession] in
        while await !replacementSession.sentMessages().contains(where: { $0.op == "transact" }) {
          try Task.checkCancellation()
          // The reconnect's delay, and any delivery retry behind it, elapse at once.
          await reconnectSleep.resumePending()
          await Task.yield()
        }
      }
      try await answerTheWrite(on: replacementSession)
    }

    let keptLate = capture.entries(named: "outbox.mutation.ack-late-kept").compactMap {
      $0.metadata["firstMutationID"]
    }
    let expiredAsTimeouts = capture.entries(named: "outbox.mutation.ack-timeout-batch").flatMap {
      ($0.metadata["expiredMutationIDs"] ?? "").split(separator: ",").map(String.init)
    }
    let connections = await transport.connectionRequests().count
    let offeredOnFirstSession = await offers(on: firstSession)
    let offeredOnReplacement = await offers(on: replacementSession)
    let pendingWrites = try await runtime.persistence.countOutboxMutations(status: .pending)
    return OwedAnswerOutcome(
      verdict: verdict,
      keptLate: keptLate,
      expiredAsTimeouts: expiredAsTimeouts,
      keptClaimDeadline: keptClaimDeadline,
      connections: connections,
      offeredOnFirstSession: offeredOnFirstSession,
      offeredOnReplacement: offeredOnReplacement,
      pendingWrites: pendingWrites
    )
  }

  private func answerTheWrite(on session: LiveReactorParitySession) async throws {
    await session.enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: writeID,
        fields: ["tx-id": .string("server-\(writeID)")]
      )
    )
    try await instantLiveWithTimeout(
      operation: "wait for the answer to settle the write",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) { [runtime] in
      while try await runtime.persistence.countOutboxMutations(status: .pending) != 0 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  private func offers(on session: LiveReactorParitySession) async -> [String] {
    await session.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
  }
}

/// The time the runtime reads for acknowledgement deadlines; it moves only when the test moves it.
private final class OwedAnswerClock: @unchecked Sendable {
  private let lock = NSLock()
  private var milliseconds: Int64

  init(milliseconds: Int64) {
    self.milliseconds = milliseconds
  }

  func now() -> InstantTimestamp {
    lock.withLock { InstantTimestamp(milliseconds: milliseconds) }
  }

  func advance(by delta: Int64) {
    lock.withLock { milliseconds += delta }
  }
}

/// Holds every sleep the runtime asks for until the test resumes it, so a wake happens only after the test has moved
/// the clock to it.
private actor OwedAnswerHeldSleep {
  private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
  private var nextID = 0

  func sleep(milliseconds: UInt64) async throws {
    let id = nextID
    nextID += 1
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          pending[id] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  func hasPending() -> Bool {
    !pending.isEmpty
  }

  func resumePending() {
    let resumed = pending
    pending.removeAll()
    for (_, continuation) in resumed.sorted(by: { $0.key < $1.key }) { continuation.resume() }
  }

  private func cancel(_ id: Int) {
    pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }
}

/// Counts what the runtime's reader asks the scripted sessions for. v1.9.79 has no count of the frames its applier took
/// that a test can read, so a test learns that the reader handed a frame over from its next request: it asks again only
/// after that.
private final class OwedAnswerReaderRequests: @unchecked Sendable {
  private let lock = NSLock()
  private var calls = 0
  private var handedOver = 0

  var counts: (calls: Int, handedOver: Int) {
    lock.withLock { (calls, handedOver) }
  }

  func counting(_ session: InstantLiveWebSocketSession) -> InstantLiveWebSocketSession {
    var session = session
    let receive = session.receive
    session.receive = {
      self.lock.withLock { self.calls += 1 }
      let message = try await receive()
      self.lock.withLock { self.handedOver += 1 }
      return message
    }
    return session
  }
}

/// Keeps the library diagnostics whose metadata mentions one test's prefix. Suites run in parallel and share the
/// handler list.
private final class OwedAnswerDiagnostics: @unchecked Sendable {
  private let lock = NSLock()
  private let prefix: String
  private var captured: [InstantDiagnosticEntry] = []

  init(prefix: String) {
    self.prefix = prefix
  }

  func record(_ entry: InstantDiagnosticEntry) {
    guard entry.metadata.values.contains(where: { $0.contains(prefix) }) else { return }
    lock.withLock { captured.append(entry) }
  }

  func entries(named event: String) -> [InstantDiagnosticEntry] {
    lock.withLock { captured.filter { $0.event == event } }
  }
}
