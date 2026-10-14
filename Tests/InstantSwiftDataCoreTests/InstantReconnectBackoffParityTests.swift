import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// The reconnect loop's backoff and network gating, against upstream `Reactor.js` (#669).
///
/// Upstream keeps `_reconnectTimeoutMs` on the reactor: `_scheduleReconnect` waits it out, then grows it by a second up
/// to ten (`Math.min(this._reconnectTimeoutMs + 1000, 10000)`), and only `init-ok` (and a user change) resets it to
/// zero. The timer skips its attempt while `_isOnline` is false, and the `NetworkListener` starts the socket as soon as
/// the network returns. These tests drive the runtime through scripted connection attempts, a scripted network path, and
/// a reconnect sleep that records each wait. No network is involved.
@Suite(.serialized)
struct InstantReconnectBackoffParityTests {
  /// While the network path is missing the reconnect loop makes no attempt; when the path returns it makes one at once,
  /// and the delay keeps the growth of the wait it skipped. Upstream `_scheduleReconnect` grows `_reconnectTimeoutMs`
  /// before it checks `_isOnline`, and its listener calls `_startSocket` on the change to online.
  @Test
  func noAttemptWhileThePathIsMissingAndOneAttemptWhenItReturns() async throws {
    let transport = BackoffParityTransport(opensAttempts: [3])
    let path = InstantNetworkPathMonitor(isSatisfied: false)
    let sleeps = BackoffParitySleepRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try backoffParityConfiguration(
        appID: "backoff-path-missing",
        transport: transport,
        path: path,
        sleeps: sleeps,
        autoConnect: true
      )
    )

    try await backoffParityWait("the bootstrap attempt to fail and the reconnect to settle") {
      let attempts = await transport.attemptCount
      let waiting = await runtime.liveReconnectControllerIsWaitingForNetworkForTesting()
      return waiting || attempts >= 2
    }
    let attemptsWhileMissing = await transport.attemptCount
    expectNoDifference(attemptsWhileMissing, 1, "Only the bootstrap attempt runs while the path is missing.")

    path.update(isSatisfied: true)
    try await backoffParityWait("the reconnect to open a session after the path returned") {
      try await runtime.connectionStatus().state == .opened
    }
    let attempts = await transport.attemptCount
    expectNoDifference(attempts, 3, "The return's attempt fails; the next one, a second later, opens.")
    let delays = await sleeps.delays
    expectNoDifference(delays, [0, 1_000], "The skipped wait still grew the delay.")
    _ = try await runtime.closeConnection()
  }

  /// A path that drops and returns while the loop waits out its backoff ends the wait at once, as the upstream listener
  /// starts the socket on the change to online without waiting for the pending timer.
  @Test
  func aPathThatReturnsDuringTheBackoffEndsTheWait() async throws {
    let transport = BackoffParityTransport(opensAttempts: [3])
    let path = InstantNetworkPathMonitor(isSatisfied: true)
    let sleeps = BackoffParitySleepRecorder(parksDelays: [1_000])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try backoffParityConfiguration(
        appID: "backoff-path-returns",
        transport: transport,
        path: path,
        sleeps: sleeps,
        autoConnect: true
      )
    )

    try await withBackoffParityCleanup({ await sleeps.releaseParked() }) {
      try await backoffParityWait("the reconnect to wait out its one-second backoff") {
        await sleeps.parkedDelay == 1_000
      }
      let attemptsBeforeTheDrop = await transport.attemptCount
      expectNoDifference(attemptsBeforeTheDrop, 2)

      path.update(isSatisfied: false)
      path.update(isSatisfied: true)
      try await backoffParityWait("the returned path to start an attempt without the backoff") {
        try await runtime.connectionStatus().state == .opened
      }
      let attempts = await transport.attemptCount
      expectNoDifference(attempts, 3)
      _ = try await runtime.closeConnection()
    }
  }

  /// The delay grows by a second per failed attempt up to ten and holds there, and a session that reaches `init-ok`
  /// resets it: the reconnect after that session dies waits zero, then one second.
  @Test
  func theDelayGrowsToTenSecondsAndOnlyAnOpenedSessionResetsIt() async throws {
    // Attempt 1 is the bootstrap's; 2-13 are the loop's; 13 opens. After that session dies, 14 fails and 15 opens.
    let transport = BackoffParityTransport(opensAttempts: [13, 15])
    let sleeps = BackoffParitySleepRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try backoffParityConfiguration(
        appID: "backoff-growth",
        transport: transport,
        path: nil,
        sleeps: sleeps,
        autoConnect: true
      )
    )

    try await backoffParityWait("the thirteenth attempt to open a session") {
      try await runtime.connectionStatus().state == .opened
    }
    let delaysUntilOpen = await sleeps.delays
    expectNoDifference(
      delaysUntilOpen,
      [0, 1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000, 9_000, 10_000, 10_000]
    )

    let socket = try #require(await transport.socket(13))
    await socket.die(with: backoffParitySocketNotConnected)
    try await backoffParityWait("the reconnect after the opened session died to open again") {
      let attempts = await transport.attemptCount
      let state = try await runtime.connectionStatus().state
      return attempts == 15 && state == .opened
    }
    let delays = await sleeps.delays
    expectNoDifference(Array(delays.dropFirst(delaysUntilOpen.count)), [0, 1_000], "init-ok reset the delay.")
    _ = try await runtime.closeConnection()
  }

  /// An explicit `connect()` that fails ends the scheduled reconnect but does not reset its delay: only `init-ok` does.
  /// The next scheduled reconnect waits out the delay the cancelled one was waiting for.
  @Test
  func aFailedExplicitConnectKeepsTheBackoff() async throws {
    let transport = BackoffParityTransport(opensAttempts: [6])
    let sleeps = BackoffParitySleepRecorder(parksDelays: [2_000])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: try backoffParityConfiguration(
        appID: "backoff-explicit-connect",
        transport: transport,
        path: nil,
        sleeps: sleeps,
        autoConnect: true
      )
    )

    try await withBackoffParityCleanup({ await sleeps.releaseParked() }) {
      try await backoffParityWait("the reconnect to wait out its two-second backoff") {
        await sleeps.parkedDelay == 2_000
      }
      // Attempt 4: the explicit connect cancels the scheduled reconnect and fails.
      await #expect(throws: (any Error).self) {
        _ = try await runtime.connect()
      }
      await sleeps.stopParking()
      // Attempt 5: a write's delivery connects, fails, and schedules the next reconnect; attempt 6 opens.
      try await transactBackoffParityTodo(id: "tx-after-explicit-connect", on: runtime)
      try await backoffParityWait("the next scheduled reconnect to open a session") {
        try await runtime.connectionStatus().state == .opened
      }
      let attempts = await transport.attemptCount
      expectNoDifference(attempts, 6)
      let delays = await sleeps.delays
      expectNoDifference(delays, [0, 1_000, 2_000, 2_000], "The cancelled wait's delay carried over.")
      _ = try await runtime.closeConnection()
    }
  }

  /// Measures the reconnect attempts of a 37-minute outage on a virtual clock: the network path is missing for the first
  /// 13 minutes and the server never answers afterwards, so every attempt times out after the five-second open
  /// deadline. Prints the attempts in the first 37 and 60 minutes.
  @Test
  func anOutageWithTheNetworkMissingFor13MinutesMakesNoAttemptsUntilItReturns() async throws {
    let clock = BackoffParityVirtualClock(
      endMilliseconds: 60 * 60 * 1_000,
      pathReturnsAtMilliseconds: 13 * 60 * 1_000
    )
    let path = InstantNetworkPathMonitor(isSatisfied: false)
    await clock.setPath(path)
    let transport = BackoffParityTransport(opensAttempts: [], clock: clock)
    var configuration = try backoffParityConfiguration(
      appID: "backoff-outage-replay",
      transport: transport,
      path: path,
      sleeps: nil,
      autoConnect: true
    )
    configuration.liveReconnectSleep = { milliseconds in try await clock.sleep(milliseconds) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    // When the loop waits for the path, nothing advances the virtual clock: jump it to the path's return.
    let driver = Task {
      while !Task.isCancelled {
        if await runtime.liveReconnectControllerIsWaitingForNetworkForTesting() {
          await clock.jumpToPathReturn()
        }
        if await clock.reachedEnd { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
      }
    }
    try await backoffParityWait("the virtual hour to pass", timeoutMilliseconds: 30_000) {
      await clock.reachedEnd
    }
    driver.cancel()
    let attemptTimes = await transport.attemptTimes
    let in37Minutes = attemptTimes.filter { $0 < 37 * 60 * 1_000 }.count
    let in60Minutes = attemptTimes.filter { $0 < 60 * 60 * 1_000 }.count
    let whileMissing = attemptTimes.filter { $0 < 13 * 60 * 1_000 }.count
    print(
      "reconnect-replay: attempts while the path was missing (0-13 min) \(whileMissing), in 37 min \(in37Minutes), in 60 min \(in60Minutes)"
    )
    expectNoDifference(whileMissing, 1, "Only the first attempt, made before the loop read the path.")
    #expect(in37Minutes <= 100)
    _ = try await runtime.closeConnection()
  }
}

// MARK: - Fixtures

private let backoffParitySocketNotConnected = NSError(
  domain: NSPOSIXErrorDomain,
  code: 57,
  userInfo: [NSLocalizedDescriptionKey: "Socket is not connected"]
)

private let backoffParityOpenTimedOut = InstantError(
  code: .networkFailed,
  operation: "open Instant live session",
  message: "Timed out after 5000ms waiting for Instant live transport.",
  recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
)

/// One scripted socket: it answers `init` with `init-ok`, then waits for frames until `die(with:)`.
private actor BackoffParitySocket {
  private let abortState = InstantLiveTestWireAbortState()
  private var frames: [InstantLiveMessage]
  private var pendingReceive: InstantLiveTestThrowingContinuationBox<InstantLiveMessage>?
  private var pendingAbortToken: UUID?
  private var death: (any Error)?
  private var isClosed = false

  init(sessionID: String) {
    frames = [liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: sessionID)]
  }

  nonisolated var session: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { _ in try await self.send() },
      receive: { try await self.receive() },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  func die(with error: any Error) {
    guard death == nil else { return }
    death = error
    takePendingReceive()?.resume(throwing: error)
  }

  private func send() throws {
    try abortState.check()
    if let death { throw death }
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !frames.isEmpty {
      return frames.removeFirst()
    }
    if let death { throw death }
    if isClosed { throw CancellationError() }
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
      pendingReceive = continuation
      pendingAbortToken = abortToken
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
  }

  private func takePendingReceive() -> InstantLiveTestThrowingContinuationBox<InstantLiveMessage>? {
    guard let pending = pendingReceive else { return nil }
    pendingReceive = nil
    if let token = pendingAbortToken {
      abortState.unregister(token)
      pendingAbortToken = nil
    }
    return pending
  }
}

/// Counts connection attempts; the attempts in `opensAttempts` (1-based) open a session, every other one fails as a
/// connection that timed out. With a virtual clock, each failed attempt also takes the five-second open deadline.
private actor BackoffParityTransport {
  private let opensAttempts: Set<Int>
  private let clock: BackoffParityVirtualClock?
  private var sockets: [Int: BackoffParitySocket] = [:]
  private(set) var attemptCount = 0
  private(set) var attemptTimes: [Int64] = []

  init(opensAttempts: Set<Int>, clock: BackoffParityVirtualClock? = nil) {
    self.opensAttempts = opensAttempts
    self.clock = clock
  }

  nonisolated var client: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let connection = InstantLiveTestConnectionContinuation()
      return InstantLiveConnectionAttempt(
        connect: {
          connection.start { try await self.open() }
          return try await connection.connect()
        },
        abort: { connection.abort() }
      )
    }
  }

  func socket(_ attempt: Int) -> BackoffParitySocket? {
    sockets[attempt]
  }

  private func open() async throws -> InstantLiveWebSocketSession {
    attemptCount += 1
    let attempt = attemptCount
    if let clock {
      attemptTimes.append(await clock.now)
      try await clock.spendOpenDeadline()
    }
    guard opensAttempts.contains(attempt) else {
      throw backoffParityOpenTimedOut
    }
    let socket = BackoffParitySocket(sessionID: "backoff-parity-\(attempt)")
    sockets[attempt] = socket
    return socket.session
  }
}

/// Records every reconnect wait and returns at once, except a delay in `parksDelays`, which waits until released.
private actor BackoffParitySleepRecorder {
  private var parksDelays: Set<UInt64>
  private(set) var delays: [UInt64] = []
  private(set) var parkedDelay: UInt64?
  private var released = false

  init(parksDelays: Set<UInt64> = []) {
    self.parksDelays = parksDelays
  }

  func sleep(_ milliseconds: UInt64) async throws {
    delays.append(milliseconds)
    guard parksDelays.contains(milliseconds), !released else { return }
    parksDelays.remove(milliseconds)
    parkedDelay = milliseconds
    defer { parkedDelay = nil }
    while !released {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  /// Later waits return at once, and nothing parks again.
  func stopParking() {
    parksDelays.removeAll()
  }

  func releaseParked() {
    released = true
  }
}

/// A clock that only moves when the reconnect loop waits or an attempt spends its open deadline.
private actor BackoffParityVirtualClock {
  private let endMilliseconds: Int64
  private let pathReturnsAtMilliseconds: Int64
  private var path: InstantNetworkPathMonitor?
  private(set) var now: Int64 = 0

  init(endMilliseconds: Int64, pathReturnsAtMilliseconds: Int64) {
    self.endMilliseconds = endMilliseconds
    self.pathReturnsAtMilliseconds = pathReturnsAtMilliseconds
  }

  var reachedEnd: Bool { now >= endMilliseconds }

  func setPath(_ path: InstantNetworkPathMonitor) {
    self.path = path
  }

  func sleep(_ milliseconds: UInt64) async throws {
    try await advance(by: Int64(milliseconds))
  }

  func spendOpenDeadline() async throws {
    try await advance(by: Int64(instantLiveOperationTimeoutMilliseconds))
  }

  func jumpToPathReturn() {
    guard now < pathReturnsAtMilliseconds else { return }
    now = pathReturnsAtMilliseconds
    path?.update(isSatisfied: true)
  }

  /// Advances the clock; at the end of the measured hour the caller waits until it is cancelled.
  private func advance(by milliseconds: Int64) async throws {
    now += milliseconds
    if now >= pathReturnsAtMilliseconds {
      path?.update(isSatisfied: true)
    }
    if now >= endMilliseconds {
      while true {
        try await Task.sleep(nanoseconds: 1_000_000)
      }
    }
  }
}

private func backoffParityConfiguration(
  appID: String,
  transport: BackoffParityTransport,
  path: InstantNetworkPathMonitor?,
  sleeps: BackoffParitySleepRecorder?,
  autoConnect: Bool
) throws -> InstantRuntimeConfiguration {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantReconnectBackoffParityTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  var liveTransport = transport.client
  if let path {
    liveTransport.networkPath = InstantNetworkPath(monitor: path)
  }
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: directory.appendingPathComponent("state.sqlite"),
    initialAttributes: TodoExample.attributes,
    now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
    liveTransport: liveTransport
  )
  configuration.autoConnectLiveTransport = autoConnect
  if let sleeps {
    configuration.liveReconnectSleep = { milliseconds in try await sleeps.sleep(milliseconds) }
  }
  return configuration
}

private func transactBackoffParityTodo(id: String, on runtime: InstantRuntime) async throws {
  let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
  try await runtime.transact(
    InstantStoreTransaction(
      id: id,
      operations: TodoExample.createOperations(
        id: "todo-\(id)",
        text: "backoff \(id)",
        createdAt: createdAt,
        transactionID: id
      )
    ),
    createdAt: createdAt
  )
}

private struct BackoffParityWaitTimedOut: Error, CustomStringConvertible {
  var description: String
}

/// Polls `condition` every 2 ms for at most 5 s (the codebase's timeout rule), or `timeoutMilliseconds`.
private func backoffParityWait(
  _ description: String,
  timeoutMilliseconds: Int = 5_000,
  _ condition: @Sendable () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + .milliseconds(timeoutMilliseconds)
  while !(try await condition()) {
    guard ContinuousClock.now < deadline else {
      throw BackoffParityWaitTimedOut(
        description: "Timed out after \(timeoutMilliseconds) ms waiting for \(description)."
      )
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
}

/// Runs `cleanup` after `body`, including when `body` throws, so a failed wait never leaves a parked task behind.
private func withBackoffParityCleanup(
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
