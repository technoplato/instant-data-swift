import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Connection survival for Recording 023 (#296).
///
/// Build 72 opened more than one replacement connection for each socket death: the reconnect controller and the
/// delivery pump both reacted to the same loss. These tests drive the runtime through scripted sockets. No network is
/// involved.
@Suite(.serialized)
struct InstantLiveConnectionSurvivalTests {
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
