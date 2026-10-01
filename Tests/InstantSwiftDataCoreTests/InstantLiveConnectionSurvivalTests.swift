import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Connection survival for Recording 023 (#296).
///
/// Build 72 lost its socket after every long server frame and opened more than one replacement for each loss. Two
/// facts explain the first defect:
/// - The server pings every 5 s and closes a client that sends nothing, not even a pong, for its idle timeout
///   (upstream `server/src/instant/lib/ring/websocket.clj`, `straight-jacket-run-ping-job`). Measured on Instant's
///   hosted server through the throwaway app bd40c50a, that is about 20-30 s.
/// - URLSession answers a server ping only while a `receive()` is outstanding (measured; see
///   `InstantURLSessionKeepaliveLiveTests`).
///
/// The receive loop applied each frame before it called `receive()` again, so a 26-37 s apply meant no pongs. The
/// other defect: the reconnect controller and the delivery pump both reacted to the same loss. These tests drive the
/// runtime through scripted sockets. No network is involved.
@Suite(.serialized)
struct InstantLiveConnectionSurvivalTests {
  /// A frame the runtime applies for a long time must not stop the socket from reading. Upstream `Reactor.js` handles
  /// each frame synchronously in `_handleReceive`, and a browser answers pings below JavaScript either way. A Swift
  /// transport such as URLSession answers them only while a `receive()` is outstanding.
  @Test
  func aLongFrameApplyKeepsAReceiveOutstandingSoServerPingsAreAnswered() async throws {
    let transport = SurvivalTransport()
    let gate = SurvivalApplyGate()
    var configuration = try survivalConfiguration(appID: "survival-keepalive", transport: transport)
    configuration.onLiveReceiverEventAcquiredForTesting = { await gate.enter() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await withSurvivalCleanup({ await gate.release() }) {
      _ = try await runtime.connect()
      let socket = try #require(await transport.socket(0))

      await socket.push(survivalLongFrame)
      try await waitUntil("the runtime to start applying the long frame") {
        await gate.enteredCount == 1
      }
      try await waitUntil("a receive() outstanding while the long frame applies") {
        await socket.hasOutstandingReceive
      }
      let ping = await socket.serverPing()
      expectNoDifference(ping, .answered)

      await gate.release()
      _ = try await runtime.closeConnection()
    }
  }

  /// Answers that arrive while an earlier frame applies are applied afterwards, one at a time, in arrival order. Each
  /// one still carries the claim token of its own offer, so each write is accepted exactly when its answer applies.
  @Test
  func framesThatArriveDuringALongApplyAreAppliedInArrivalOrder() async throws {
    let transport = SurvivalTransport()
    let gate = SurvivalApplyGate()
    let runtimeBox = SurvivalRuntimeBox()
    let pendingAtEachFrame = SurvivalRecorder<[String]>()
    var configuration = try survivalConfiguration(appID: "survival-order", transport: transport)
    configuration.onLiveReceiverEventAcquiredForTesting = {
      if let runtime = await runtimeBox.runtime {
        await pendingAtEachFrame.append(await runtime.pendingMutations().map(\.id).sorted())
      }
      await gate.enter()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await runtimeBox.set(runtime)
    let ids = ["tx-order-a", "tx-order-b", "tx-order-c"]

    try await withSurvivalCleanup({ await gate.release() }) {
      _ = try await runtime.connect()
      let socket = try #require(await transport.socket(0))
      for (index, id) in ids.enumerated() {
        try await transactSurvivalTodo(id: id, index: index, on: runtime)
      }
      try await waitUntil("the pump to offer all three writes") {
        await socket.sentTransactIDs == ids
      }

      await socket.push(survivalLongFrame)
      try await waitUntil("the runtime to start applying the long frame") {
        await gate.enteredCount == 1
      }
      for id in ids {
        await socket.push(survivalTransactOK(id))
      }
      try await waitUntil("the socket to hand over every answer while the long frame applies") {
        await socket.isCaughtUp
      }

      await gate.release()
      try await waitUntil("all three answers to be applied") {
        await runtime.pendingMutations().isEmpty
      }
      let observed = await pendingAtEachFrame.values
      expectNoDifference(
        observed,
        [ids, ids, ["tx-order-b", "tx-order-c"], ["tx-order-c"]],
        "The long frame, then a, b, and c, each applied only after the one before it finished."
      )
      _ = try await runtime.closeConnection()
    }
  }

  /// Replacing the connection while a frame applies drops every frame that arrived on the old connection. A buffered
  /// answer must never be applied after its connection was replaced.
  @Test
  func anAnswerThatArrivedOnAReplacedConnectionIsNeverApplied() async throws {
    let transport = SurvivalTransport()
    let gate = SurvivalApplyGate()
    var configuration = try survivalConfiguration(appID: "survival-replaced", transport: transport)
    configuration.onLiveReceiverEventAcquiredForTesting = { await gate.enter() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let id = "tx-replaced-a"

    try await withSurvivalCleanup({ await gate.release() }) {
      _ = try await runtime.connect()
      let socket = try #require(await transport.socket(0))
      try await transactSurvivalTodo(id: id, index: 0, on: runtime)
      try await waitUntil("the pump to offer the write") { await socket.sentTransactIDs == [id] }

      await socket.push(survivalLongFrame)
      try await waitUntil("the runtime to start applying the long frame") {
        await gate.enteredCount == 1
      }
      await socket.push(survivalTransactOK(id))
      try await waitUntil("the socket to hand over the answer while the long frame applies") {
        await socket.isCaughtUp
      }

      let replacement = Task { try await runtime.connect() }
      try await waitUntil("the replacement to close the old socket") { await socket.isClosed }
      await gate.release()
      _ = try await replacement.value

      let appliedFrameCount = await gate.enteredCount
      expectNoDifference(appliedFrameCount, 1, "Only the long frame reached the applier.")
      let pending = await runtime.pendingMutations().map(\.id)
      expectNoDifference(pending, [id], "The old connection's answer was not applied.")
      _ = try await runtime.closeConnection()
    }
  }

  /// A failed send aborts the socket, and the frames taken from it before the failure are not applied. This keeps the
  /// build-72 behaviour: its next `receive()` failed at that point. The failure still leads to exactly one reconnect.
  @Test
  func framesTakenBeforeAFailedSendAreNotApplied() async throws {
    let transport = SurvivalTransport()
    let gate = SurvivalApplyGate()
    var configuration = try survivalConfiguration(appID: "survival-send-failure", transport: transport)
    configuration.onLiveReceiverEventAcquiredForTesting = { await gate.enter() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let first = "tx-send-failure-a"
    let second = "tx-send-failure-b"

    try await withSurvivalCleanup({ await gate.release() }) {
      _ = try await runtime.connect()
      let socket = try #require(await transport.socket(0))
      try await transactSurvivalTodo(id: first, index: 0, on: runtime)
      try await waitUntil("the pump to offer the first write") { await socket.sentTransactIDs == [first] }

      await socket.push(survivalLongFrame)
      try await waitUntil("the runtime to start applying the long frame") {
        await gate.enteredCount == 1
      }
      await socket.push(survivalTransactOK(first))
      try await waitUntil("the socket to hand over the answer while the long frame applies") {
        await socket.isCaughtUp
      }

      await socket.dieOnNextSend(of: "transact", with: survivalSocketNotConnected)
      try await transactSurvivalTodo(id: second, index: 1, on: runtime)
      try await waitUntil("the second write's send to kill the socket") { await socket.isDead }
      await gate.release()

      try await waitUntil("both writes to be offered again on one replacement") {
        await transport.socket(1)?.sentTransactIDs == [first, second]
      }
      let appliedFrameCount = await gate.enteredCount
      expectNoDifference(appliedFrameCount, 1, "The answer taken before the failed send was not applied.")
      let attempts = await transport.attemptCount
      expectNoDifference(attempts, 2, "One replacement connection.")
      _ = try await runtime.closeConnection()
    }
  }

  /// The reader's buffer hands frames over in arrival order. The reader's terminal error comes only after every earlier
  /// frame, and a full buffer makes the reader wait instead of growing.
  @Test
  func theReceiveBufferKeepsArrivalOrderAndMakesAFullReaderWait() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 2)
    let firstAccepted = await frames.append(InstantLiveMessage(op: "first"))
    let secondAccepted = await frames.append(InstantLiveMessage(op: "second"))
    expectNoDifference([firstAccepted, secondAccepted], [true, true])

    let thirdAppend = Task { await frames.append(InstantLiveMessage(op: "third")) }
    try await waitUntil("the reader to wait on the full buffer") { frames.readerIsWaitingForTesting }
    expectNoDifference(frames.bufferedCountForTesting, 2)
    let taken = try await frames.next()
    expectNoDifference(taken.op, "first")
    let thirdAccepted = await thirdAppend.value
    expectNoDifference(thirdAccepted, true)

    frames.finish(throwing: survivalSocketNotConnected)
    let second = try await frames.next()
    let third = try await frames.next()
    expectNoDifference([second.op, third.op], ["second", "third"])
    do {
      _ = try await frames.next()
      Issue.record("The reader's terminal error must follow the last frame.")
    } catch {
      expectNoDifference((error as NSError).code, 57)
    }
    let acceptedAfterFailure = await frames.append(InstantLiveMessage(op: "late"))
    expectNoDifference(acceptedAfterFailure, false)
  }

  /// A cancelled applier stops waiting. Closing the buffer drops what is waiting and releases a reader that waits on
  /// a full buffer, so a stopped applier never leaves its reader behind.
  @Test
  func closingTheReceiveBufferReleasesAWaitingReader() async throws {
    let frames = InstantLiveReceivedFrames(capacity: 1)
    let applier = Task { try await frames.next() }
    try await waitUntil("the applier to wait for a frame") { frames.applierIsWaitingForTesting }
    applier.cancel()
    switch await applier.result {
    case .success(let frame):
      Issue.record("A cancelled applier took \(frame.op).")
    case .failure(let error):
      #expect(error is CancellationError)
    }

    let firstAccepted = await frames.append(InstantLiveMessage(op: "first"))
    expectNoDifference(firstAccepted, true)
    let blockedAppend = Task { await frames.append(InstantLiveMessage(op: "second")) }
    try await waitUntil("the reader to wait on the full buffer") { frames.readerIsWaitingForTesting }
    frames.close()
    let blockedAccepted = await blockedAppend.value
    expectNoDifference(blockedAccepted, false)
    expectNoDifference(frames.bufferedCountForTesting, 0)
    do {
      _ = try await frames.next()
      Issue.record("A closed buffer has no frames.")
    } catch {
      #expect(error is CancellationError)
    }
  }

  /// Recording 023 on build 72: each socket death logged `connection.open-started` from the delivery pump and from the
  /// reconnect controller within 1 ms, then a third `open-started`. Here the reconnect's handshake is slow, and a new
  /// write arrives meanwhile. Exactly one replacement connection may open.
  @Test
  func aSocketDeathDuringDeliveryOpensExactlyOneReplacement() async throws {
    let transport = SurvivalTransport()
    await transport.holdAttempts(from: 2)
    var configuration = try survivalConfiguration(appID: "survival-one-replacement", transport: transport)
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let first = "tx-one-replacement-a"
    let second = "tx-one-replacement-b"

    try await withSurvivalCleanup({ await transport.releaseHeldAttempts() }) {
      try await waitUntil("the automatic connection to open") {
        try await runtime.connectionStatus().state == .opened
      }
      let socket = try #require(await transport.socket(0))
      // The server already closed the socket: the next send and the pending receive fail with POSIX 57.
      await socket.dieOnNextSend(of: "transact", with: survivalSocketNotConnected)
      try await transactSurvivalTodo(id: first, index: 0, on: runtime)
      try await waitUntil("the reconnect's attempt to start its handshake") {
        await transport.attemptCount == 2
      }

      try await transactSurvivalTodo(id: second, index: 1, on: runtime)
      try await waitUntil("the pump to settle or to start its own connection") {
        let pumpIsIdle = await runtime.automaticMutationPumpIsIdleForTesting()
        let attempts = await transport.attemptCount
        return pumpIsIdle || attempts >= 3
      }
      await transport.releaseHeldAttempts()
      try await waitUntil("both writes to be offered on the replacement") {
        await transport.lastSocket?.sentTransactIDs == [first, second]
      }

      let attempts = await transport.attemptCount
      expectNoDifference(attempts, 2, "The first connection and exactly one replacement.")
      _ = try await runtime.closeConnection()
    }
  }

  /// A reconnect that was scheduled for a lost socket must not replace a session that opened after the loss. On a
  /// device that other session came from the delivery pump, which reached the connection gate first. Here, signing
  /// in opens it (`reconnectAfterAuthChangeIfNeeded`) while the reconnect waits out its backoff.
  ///
  /// Upstream `_startSocket` closes an open previous transport. It only runs from `_scheduleReconnect` or the network
  /// listener, so it rarely meets a session this fresh. Swift has more connection paths, and replacing a fresh session
  /// re-adds every query, which in Recording 023 means another 26-37 s apply.
  @Test
  func aScheduledReconnectReusesASessionThatOpenedAfterTheLoss() async throws {
    let transport = SurvivalTransport()
    await transport.failAttempt(2, with: survivalSocketNotConnected)
    let backoff = SurvivalBackoffGate()
    var configuration = try survivalConfiguration(appID: "survival-reuse", transport: transport)
    configuration.autoConnectLiveTransport = true
    configuration.liveReconnectSleep = { milliseconds in try await backoff.sleep(milliseconds) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await withSurvivalCleanup({ await backoff.release() }) {
      try await waitUntil("the automatic connection to open") {
        try await runtime.connectionStatus().state == .opened
      }
      let socket = try #require(await transport.socket(0))
      await socket.die(with: survivalSocketNotConnected)
      try await waitUntil("the reconnect to wait out its backoff after one failed attempt") {
        await backoff.isWaiting
      }

      _ = try await runtime.signInAsGuest()
      try await waitUntil("sign-in to open a session") {
        let attempts = await transport.attemptCount
        let state = try await runtime.connectionStatus().state
        return attempts == 3 && state == .authenticated
      }
      let signedInSocket = try #require(await transport.socket(2))

      await backoff.release()
      try await waitUntil("the scheduled reconnect to finish") {
        await runtime.liveReconnectControllerIsIdleForTesting()
      }
      let attempts = await transport.attemptCount
      expectNoDifference(attempts, 3, "The reconnect reused the signed-in session.")
      let signedInSocketIsClosed = await signedInSocket.isClosed
      expectNoDifference(signedInSocketIsClosed, false)
      _ = try await runtime.closeConnection()
    }
  }

  /// While a reconnect waits out its backoff, a local write must neither start a connection nor cancel the wait.
  /// Upstream `_trySend` never starts a socket, and `_reconnectTimeoutMs` lives on the reactor and resets only on
  /// init-ok. Build 72's pump cancelled the controller and connected at once, so every write reset the backoff.
  @Test
  func aWriteDuringReconnectBackoffNeitherConnectsNorCancelsTheBackoff() async throws {
    let transport = SurvivalTransport()
    await transport.failAttempt(2, with: survivalSocketNotConnected)
    let backoff = SurvivalBackoffGate()
    var configuration = try survivalConfiguration(appID: "survival-backoff", transport: transport)
    configuration.autoConnectLiveTransport = true
    configuration.liveReconnectSleep = { milliseconds in try await backoff.sleep(milliseconds) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let id = "tx-during-backoff"

    try await withSurvivalCleanup({ await backoff.release() }) {
      try await waitUntil("the automatic connection to open") {
        try await runtime.connectionStatus().state == .opened
      }
      let socket = try #require(await transport.socket(0))
      await socket.die(with: survivalSocketNotConnected)
      try await waitUntil("the reconnect to wait out its backoff after one failed attempt") {
        await backoff.isWaiting
      }
      let waitedDelay = await backoff.waitingDelay
      expectNoDifference(waitedDelay, 1_000)

      try await transactSurvivalTodo(id: id, index: 0, on: runtime)
      try await waitUntil("the pump to settle") {
        await runtime.automaticMutationPumpIsIdleForTesting()
      }
      let attemptsDuringBackoff = await transport.attemptCount
      expectNoDifference(attemptsDuringBackoff, 2, "No connection starts during the backoff.")
      let cancellations = await backoff.cancellationCount
      expectNoDifference(cancellations, 0, "The write did not cancel the backoff.")

      await backoff.release()
      try await waitUntil("the reconnect to deliver the write") {
        await transport.socket(2)?.sentTransactIDs == [id]
      }
      let attempts = await transport.attemptCount
      expectNoDifference(attempts, 3)
      _ = try await runtime.closeConnection()
    }
  }
}

// MARK: - Scripted sockets

private let survivalSocketNotConnected = NSError(
  domain: NSPOSIXErrorDomain,
  code: 57,
  userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
)

/// An unknown op: the runtime records it as the frame being applied and ignores it otherwise. The apply gate holds
/// it to stand in for Recording 023's 26-37 s rebase.
private let survivalLongFrame = InstantLiveMessage(op: "survival-long-frame", clientEventID: nil, fields: [:])

private func survivalTransactOK(_ id: String) -> InstantLiveMessage {
  InstantLiveMessage(op: "transact-ok", clientEventID: id, fields: ["tx-id": .string("server-\(id)")])
}

/// One scripted Instant socket.
///
/// Pushed frames reach `receive()` in order. The socket records whether a `receive()` is outstanding, which is the
/// only time URLSession answers a server ping. `die(with:)` ends the socket the way the server's close did in
/// Recording 023: the pending receive and every later send fail with the same error.
private actor SurvivalSocket {
  enum Ping: Equatable {
    case answered
    case unanswered
  }

  private struct PendingReceive {
    var id: UUID
    var abortToken: UUID
    var continuation: InstantLiveTestThrowingContinuationBox<InstantLiveMessage>
  }

  private let abortState = InstantLiveTestWireAbortState()
  private var frames: [InstantLiveMessage]
  private var pendingReceive: PendingReceive?
  private var death: (any Error)?
  private var sendDeath: (op: String, error: any Error)?
  private var sent: [InstantLiveMessage] = []
  private(set) var isClosed = false

  init(frames: [InstantLiveMessage]) {
    self.frames = frames
  }

  nonisolated var session: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in try await self.send(message) },
      receive: { try await self.receive() },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  var hasOutstandingReceive: Bool { pendingReceive != nil }

  /// Every pushed frame has been handed to a `receive()`, and another `receive()` is waiting.
  var isCaughtUp: Bool { frames.isEmpty && pendingReceive != nil }

  var isDead: Bool { death != nil }

  var sentTransactIDs: [String] {
    sent.filter { $0.op == "transact" }.compactMap(\.clientEventID)
  }

  /// A server ping gets its pong only while a `receive()` is outstanding (URLSession, measured for #296).
  func serverPing() -> Ping {
    pendingReceive == nil ? .unanswered : .answered
  }

  func push(_ frame: InstantLiveMessage) {
    guard death == nil, !isClosed else { return }
    if let pending = takePendingReceive() {
      pending.continuation.resume(returning: frame)
    } else {
      frames.append(frame)
    }
  }

  func die(with error: any Error) {
    guard death == nil else { return }
    death = error
    takePendingReceive()?.continuation.resume(throwing: error)
  }

  func dieOnNextSend(of op: String, with error: any Error) {
    sendDeath = (op, error)
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    if let death { throw death }
    if let sendDeath, sendDeath.op == message.op {
      self.sendDeath = nil
      die(with: sendDeath.error)
      throw sendDeath.error
    }
    sent.append(message)
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !frames.isEmpty {
      return frames.removeFirst()
    }
    if let death { throw death }
    if isClosed { throw CancellationError() }
    let id = UUID()
    defer { clearPendingReceive(id: id) }
    return try await withCheckedThrowingContinuation { rawContinuation in
      let continuation = InstantLiveTestThrowingContinuationBox(rawContinuation)
      guard
        let abortToken = abortState.register({
          continuation.resume(throwing: CancellationError())
        })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      pendingReceive = PendingReceive(id: id, abortToken: abortToken, continuation: continuation)
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
  }

  private func takePendingReceive() -> PendingReceive? {
    guard let pending = pendingReceive else { return nil }
    pendingReceive = nil
    abortState.unregister(pending.abortToken)
    return pending
  }

  private func clearPendingReceive(id: UUID) {
    guard pendingReceive?.id == id else { return }
    _ = takePendingReceive()
  }
}

/// Opens a fresh `SurvivalSocket`, with `init-ok` queued, for every connection attempt, and counts the attempts.
///
/// `holdAttempts(from:)` makes later attempts wait for `releaseHeldAttempts()`, the way a real WebSocket handshake
/// leaves time for a second reconnect path to act.
private actor SurvivalTransport {
  private var sockets: [SurvivalSocket] = []
  private var holdsAttemptsFrom = Int.max
  private var heldAttempts: [CheckedContinuation<Void, Never>] = []
  private var failingAttempts: [Int: any Error] = [:]

  var attemptCount: Int { sockets.count }

  var lastSocket: SurvivalSocket? { sockets.last }

  nonisolated var client: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          connection.start { try await self.openSocket() }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  func socket(_ index: Int) -> SurvivalSocket? {
    sockets.indices.contains(index) ? sockets[index] : nil
  }

  func holdAttempts(from attempt: Int) {
    holdsAttemptsFrom = attempt
  }

  func releaseHeldAttempts() {
    holdsAttemptsFrom = .max
    let held = heldAttempts
    heldAttempts.removeAll()
    for attempt in held {
      attempt.resume()
    }
  }

  func failAttempt(_ attempt: Int, with error: any Error) {
    failingAttempts[attempt] = error
  }

  private func openSocket() async throws -> InstantLiveWebSocketSession {
    let socket = SurvivalSocket(frames: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "survival-\(sockets.count + 1)")
    ])
    sockets.append(socket)
    let attempt = sockets.count
    if let error = failingAttempts[attempt] {
      throw error
    }
    if attempt >= holdsAttemptsFrom {
      await withCheckedContinuation { heldAttempts.append($0) }
    }
    return socket.session
  }
}

/// Holds frames in the runtime's applier through `onLiveReceiverEventAcquiredForTesting`, which runs after the live
/// session marks a frame as the one being applied. It stands in for a long optimistic rebase.
private actor SurvivalApplyGate {
  private var holds = true
  private var parked: [CheckedContinuation<Void, Never>] = []
  private(set) var enteredCount = 0

  func enter() async {
    enteredCount += 1
    guard holds else { return }
    await withCheckedContinuation { parked.append($0) }
  }

  func release() {
    holds = false
    let parked = parked
    self.parked.removeAll()
    for frame in parked {
      frame.resume()
    }
  }
}

/// Parks the reconnect controller in its first real backoff (a delay above zero) until `release()`.
private actor SurvivalBackoffGate {
  private var released = false
  private(set) var isWaiting = false
  private(set) var waitingDelay: UInt64?
  private(set) var cancellationCount = 0

  func sleep(_ milliseconds: UInt64) async throws {
    guard milliseconds > 0, !released, waitingDelay == nil else { return }
    waitingDelay = milliseconds
    isWaiting = true
    defer { isWaiting = false }
    do {
      while !released {
        try await Task.sleep(nanoseconds: 1_000_000)
      }
    } catch {
      cancellationCount += 1
      throw error
    }
  }

  func release() {
    released = true
  }
}

private actor SurvivalRuntimeBox {
  private(set) var runtime: InstantRuntime?

  func set(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }
}

private actor SurvivalRecorder<Value: Sendable> {
  private(set) var values: [Value] = []

  func append(_ value: Value) {
    values.append(value)
  }
}

private struct SurvivalWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

// MARK: - Helpers

/// A frozen clock keeps every delivery claim inside its acknowledgement deadline, so no deadline replaces a
/// connection behind a test's back.
private func survivalConfiguration(
  appID: String,
  transport: SurvivalTransport
) throws -> InstantRuntimeConfiguration {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantLiveConnectionSurvivalTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: directory.appendingPathComponent("state.sqlite"),
    initialAttributes: TodoExample.attributes,
    now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
    liveTransport: transport.client
  )
  configuration.autoConnectLiveTransport = false
  return configuration
}

private func transactSurvivalTodo(id: String, index: Int, on runtime: InstantRuntime) async throws {
  let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
  try await runtime.transact(
    InstantStoreTransaction(
      id: id,
      operations: TodoExample.createOperations(
        id: "todo-\(id)",
        text: "survival \(id)",
        createdAt: createdAt,
        transactionID: id
      )
    ),
    createdAt: createdAt
  )
}

/// Polls `condition` every 2 ms for at most 5 s (the codebase's timeout rule).
private func waitUntil(
  _ description: String,
  timeoutMilliseconds: Int = 5_000,
  _ condition: @Sendable () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)
  while !(try await condition()) {
    guard ContinuousClock.now < deadline else {
      throw SurvivalWaitTimedOut(
        description: "Timed out after \(timeoutMilliseconds) ms waiting for \(description)."
      )
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
}

/// Runs `cleanup` after `body`, including when `body` throws, so a failed wait never leaves a parked task behind.
private func withSurvivalCleanup(
  _ cleanup: @Sendable () async -> Void,
  _ body: () async throws -> Void
) async throws {
  do {
    try await body()
  } catch {
    await cleanup()
    throw error
  }
  await cleanup()
}
