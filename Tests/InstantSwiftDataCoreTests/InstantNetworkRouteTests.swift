import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// The live socket asks for a route that is not expensive while the path has one, and a socket that may be on an
/// expensive network moves back to one (#1237).
///
/// On one device the Wi-Fi's internet link failed for about 45 s while the Wi-Fi itself stayed up and stayed the path's
/// primary interface. Wi-Fi Assist then opened the socket's reconnect over cellular, and the socket stayed there for the
/// remaining 57 minutes of the session; the system's "Better alternate path available" reached no handler, and the path
/// never changed, so nothing that watched it could move the socket back. Upstream `Reactor.js` starts a new socket on
/// every change to online (`_startSocket` closes an open previous transport). These tests drive the runtime through
/// scripted sessions, a scripted path, a scripted probe and a virtual clock; no network is involved.
@Suite(.serialized)
struct InstantNetworkRouteTests {
  // MARK: - The path and the preference

  @Test
  func aPathCountsEachChangeOfItsCostAndInterface() {
    let path = InstantNetworkPathMonitor(path: .wifi)
    let start = path.routeMark
    #expect(!path.update(.wifi), "The same answer is no change.")
    expectNoDifference(path.routeMark, start)
    #expect(path.update(.cellular))
    #expect(path.update(.wifi))
    expectNoDifference(path.routeMark.generation, start.generation + 2)
    expectNoDifference(path.snapshot.returnCount, 0, "The path was there throughout: no return.")
    path.update(isSatisfied: false)
    path.update(isSatisfied: true)
    expectNoDifference(path.snapshot.returnCount, 1)
  }

  @Test
  func connectionsAskForARouteThatIsNotExpensiveOnlyWhileThePathHasOne() {
    let now = ContinuousClock.now
    let preference = InstantRoutePreference()
    let cases: [(String, InstantNetworkPathState, Bool)] = [
      ("Wi-Fi", .wifi, true),
      ("wired", InstantNetworkPathState(isSatisfied: true, interface: .wired), true),
      ("Wi-Fi in Low Data Mode", InstantNetworkPathState(isSatisfied: true, isConstrained: true, interface: .wifi), true),
      ("cellular", .cellular, false),
      ("a personal hotspot", InstantNetworkPathState(isSatisfied: true, isExpensive: true, interface: .wifi), false),
      ("no path", InstantNetworkPathState(isSatisfied: false), false),
    ]
    for (name, path, asks) in cases {
      expectNoDifference(preference.asksForNonexpensiveRoute(on: path, generation: 0, now: now), asks, name)
    }
  }

  /// Apple's "Reducing networking and Bluetooth power usage" backs off retries "to prevent energy-draining retry loops".
  @Test
  func aFailureBacksOffAMinuteDoublingToThirtyTwoAndASuccessEndsIt() throws {
    let start = ContinuousClock.now
    var preference = InstantRoutePreference()
    preference.refused(generation: 4, now: start)
    #expect(!preference.asksForNonexpensiveRoute(on: .wifi, generation: 4, now: start + .seconds(59)))
    #expect(preference.asksForNonexpensiveRoute(on: .wifi, generation: 4, now: start + .seconds(60)))
    #expect(
      preference.asksForNonexpensiveRoute(on: .wifi, generation: 5, now: start + .seconds(1)),
      "A path that changed since the failure asks at once."
    )

    var backingOff = InstantRoutePreference()
    var now = start
    var waits: [Duration] = []
    for _ in 0..<8 {
      backingOff.refused(generation: 4, now: now)
      let endsAt = try #require(backingOff.refusal).endsAt
      waits.append(now.duration(to: endsAt))
      now = endsAt
    }
    expectNoDifference(waits, [60, 120, 240, 480, 960, 1_920, 1_920, 1_920].map { Duration.seconds($0) })
    let recovered = backingOff.succeeded()
    #expect(recovered, "A success after a failure is a recovery.")
    #expect(backingOff.refusal == nil)
    backingOff.refused(generation: 4, now: now)
    expectNoDifference(
      now.duration(to: try #require(backingOff.refusal).endsAt),
      .seconds(60),
      "A success resets the backoff."
    )
    var fresh = InstantRoutePreference()
    let freshRecovered = fresh.succeeded()
    #expect(!freshRecovered, "A success with no failure before it is no recovery.")
  }

  @Test
  func aRecoveryWakesWhoeverWaitsForTheRouteAndCountsOnce() async {
    let path = InstantNetworkPathMonitor(path: .wifi)
    path.recordNonexpensiveRouteRefused()
    #expect(!path.asksForNonexpensiveRoute())
    let changes = path.routeChangeCount
    path.recordNonexpensiveRouteSucceeded()
    let woke = await withTaskGroup(of: Bool.self) { group in
      group.addTask { (try? await path.waitForRouteChange(after: changes)) != nil }
      group.addTask {
        try? await Task.sleep(for: .seconds(5))
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
    #expect(woke, "A recovery is a route change.")
    path.recordNonexpensiveRouteSucceeded()
    expectNoDifference(path.routeMark.recoveries, 1)
    #expect(path.asksForNonexpensiveRoute())
  }

  // MARK: - The socket's attempts

  @Test
  func anAttemptAsksForARouteThatIsNotExpensiveOnlyWhileThePathHasOne() async throws {
    let first = routeSession("route-wifi")
    let second = routeSession("route-cellular")
    let fixture = try await RouteFixture.connected(
      "attempt-access",
      path: .wifi,
      attempts: [.session(first), .session(second)]
    )
    fixture.path.update(.cellular)
    await first.failReceive(routeSocketNotConnected)
    try await fixture.transport.waitForConnectionCount(2)
    try await routeWait("the second socket to open") {
      try await fixture.runtime.connectionStatus().state == .opened
    }
    let access = await fixture.transport.connectionRequests().map(\.allowsExpensiveNetworkAccess)
    expectNoDifference(access, [false, true], "Wi-Fi asks for a route that is not expensive; cellular cannot.")
    await fixture.close()
  }

  @Test
  func anAttemptThatFailsOnARouteThatIsNotExpensiveIsFollowedByOneOnAnyNetwork() async throws {
    let refusalsBefore = InstantNetworkRouteMeter.snapshot().refusals
    let session = routeSession("route-fallback")
    let fixture = try await RouteFixture.started(
      "attempt-fallback",
      path: .wifi,
      attempts: [.failure(routeOpenTimedOut), .session(session)]
    )
    try await routeWait("the fallback socket to open") {
      try await fixture.runtime.connectionStatus().state == .opened
    }
    let access = await fixture.transport.connectionRequests().map(\.allowsExpensiveNetworkAccess)
    expectNoDifference(access, [false, true], "The socket never stays down because only cellular works.")
    #expect(!fixture.path.asksForNonexpensiveRoute(now: fixture.clock.now()))
    // The meter is the process's: other suites may add to it meanwhile.
    #expect(InstantNetworkRouteMeter.snapshot().refusals >= refusalsBefore + 1)
    expectNoDifference(fixture.diagnostics.events(named: "connection.nonexpensive-route-failed").count, 1)
    #expect(await fixture.runtime.liveRouteWatcherIsRunningForTesting(), "A socket on any network is watched.")
    await fixture.close()
  }

  // MARK: - The move

  /// The move replaces the session as any reconnect does, so the outbox goes on over the new socket: a write the server
  /// accepted before the move is not sent again, and a write made after it goes over the new socket only.
  @Test
  func aSocketThatOpenedOnCellularMovesOnceThePathIsWiFiAgainAndItsWritesFollowIt() async throws {
    let movesBefore = InstantNetworkRouteMeter.snapshot().moves
    let first = routeSession("route-move-1")
    let second = routeSession("route-move-2")
    let fixture = try await RouteFixture.connected(
      "move-path",
      path: .cellular,
      attempts: [.session(first), .session(second)]
    )
    try await fixture.transact("tx-route-before")
    try await routeWait("the first write to reach the first socket") {
      await first.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-route-before" }
    }
    await first.enqueue(
      InstantLiveMessage(op: "transact-ok", clientEventID: "tx-route-before", fields: ["tx-id": .string("server-1")])
    )
    try await routeWait("the server to accept the first write") {
      await fixture.runtime.pendingMutations().isEmpty
    }

    fixture.path.update(.wifi)

    try await fixture.transport.waitForConnectionCount(2)
    try await routeWait("the second socket to open") {
      let sessionID = await fixture.runtime.liveSessionIDForTesting()
      return try await fixture.runtime.connectionStatus().state == .opened && sessionID == "route-move-2"
    }
    try await fixture.transact("tx-route-after")
    try await routeWait("the second write to reach the second socket") {
      await second.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-route-after" }
    }
    let firstTransacts = await first.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    let secondTransacts = await second.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    expectNoDifference(firstTransacts, ["tx-route-before"])
    expectNoDifference(secondTransacts, ["tx-route-after"])
    let access = await fixture.transport.connectionRequests().map(\.allowsExpensiveNetworkAccess)
    expectNoDifference(access, [true, false], "The move asks for a route that is not expensive.")
    let moves = fixture.diagnostics.events(named: "network.path-reconnect")
    expectNoDifference(moves.count, 1)
    expectNoDifference(moves.first?.metadata["reason"], "path-changed")
    expectNoDifference(moves.first?.metadata["pathAtOpen"], "cellular expensive")
    expectNoDifference(moves.first?.metadata["path"], "wifi")
    #expect(InstantNetworkRouteMeter.snapshot().moves >= movesBefore + 1)
    let status = try await fixture.runtime.connectionStatus()
    expectNoDifference(status.state, .opened)
    expectNoDifference(status.lastErrorMessage, nil, "A move records no error.")
    await fixture.close()
  }

  @Test
  func aSocketThatOpenedOnARouteThatIsNotExpensiveNeverMoves() async throws {
    let session = routeSession("route-stays")
    let fixture = try await RouteFixture.connected(
      "never-moves",
      path: .wifi,
      attempts: [.session(session)]
    )
    #expect(await !fixture.runtime.liveRouteWatcherIsRunningForTesting(), "The system keeps it off cellular.")
    fixture.path.update(InstantNetworkPathState(isSatisfied: true, interface: .wired))
    try await Task.sleep(for: .milliseconds(200))
    let connections = await fixture.transport.connectionRequests().count
    expectNoDifference(connections, 1)
    expectNoDifference(fixture.diagnostics.events(named: "network.path-reconnect").count, 0)
    await fixture.close()
  }

  @Test
  func aSocketThatFellBackMovesWhenARequestFindsARouteThatIsNotExpensiveAgain() async throws {
    let first = routeSession("route-recover-1")
    let second = routeSession("route-recover-2")
    let fixture = try await RouteFixture.started(
      "move-recovered",
      path: .wifi,
      attempts: [.failure(routeOpenTimedOut), .session(first), .session(second)]
    )
    try await routeWait("the fallback socket to open") {
      try await fixture.runtime.connectionStatus().state == .opened
    }
    try await routeWait("the watcher to start") { await fixture.runtime.liveRouteWatcherIsRunningForTesting() }

    // A storage request on Wi-Fi went through: such a route works again.
    fixture.path.recordNonexpensiveRouteSucceeded()

    try await fixture.transport.waitForConnectionCount(3)
    let access = await fixture.transport.connectionRequests().map(\.allowsExpensiveNetworkAccess)
    expectNoDifference(access, [false, true, false])
    expectNoDifference(
      fixture.diagnostics.events(named: "network.path-reconnect").first?.metadata["reason"],
      "route-recovered"
    )
    await fixture.close()
  }

  @Test
  func aSocketThatFellBackProbesAfterTheBackoffAndMovesWhenTheProbeAnswers() async throws {
    let first = routeSession("route-probe-1")
    let second = routeSession("route-probe-2")
    let probes = RouteProbeScript(answers: [false, true])
    let fixture = try await RouteFixture.started(
      "move-probed",
      path: .wifi,
      attempts: [.failure(routeOpenTimedOut), .session(first), .session(second)],
      probe: { host, port in await probes.answer(host: host, port: port) }
    )
    try await fixture.transport.waitForConnectionCount(3)
    let access = await fixture.transport.connectionRequests().map(\.allowsExpensiveNetworkAccess)
    expectNoDifference(access, [false, true, false])
    let asked = await probes.asked
    expectNoDifference(asked.map(\.host), ["api.instantdb.com", "api.instantdb.com"])
    expectNoDifference(asked.map(\.port), [443, 443])
    let sleeps = await fixture.clock.sleeps
    expectNoDifference(sleeps, [60_000, 120_000], "One minute, then two after the first probe found no route.")
    expectNoDifference(
      fixture.diagnostics.events(named: "network.path-reconnect").first?.metadata["reason"],
      "probe-answered"
    )
    await fixture.close()
  }

  @Test
  func aSocketMovesAtMostOnceAMinute() async throws {
    let first = routeSession("route-minute-1")
    let second = routeSession("route-minute-2")
    let third = routeSession("route-minute-3")
    let fixture = try await RouteFixture.connected(
      "move-minute",
      path: .cellular,
      attempts: [.session(first), .failure(routeOpenTimedOut), .session(second), .session(third)]
    )
    fixture.path.update(.wifi)
    try await fixture.transport.waitForConnectionCount(3)
    try await routeWait("the second socket to open on any network") {
      try await fixture.runtime.connectionStatus().state == .opened
        && fixture.runtime.liveRouteWatcherIsRunningForTesting()
    }

    fixture.path.update(.cellular)
    fixture.path.update(.wifi)

    try await fixture.transport.waitForConnectionCount(4)
    let access = await fixture.transport.connectionRequests().map(\.allowsExpensiveNetworkAccess)
    expectNoDifference(access, [true, false, true, false])
    let sleeps = await fixture.clock.sleeps
    expectNoDifference(sleeps, [60_000], "The second move waited out the minute after the first.")
    expectNoDifference(fixture.diagnostics.events(named: "network.path-reconnect").count, 2)
    await fixture.close()
  }

  // MARK: - The live socket's request

  @Test
  func theLiveSocketsRequestCarriesTheAttemptsAccess() async throws {
    let request = InstantLiveSessionRequest(
      appID: "route-request",
      websocketURI: URL(string: "ws://127.0.0.1:1/runtime/session")!,
      allowsExpensiveNetworkAccess: false
    )
    let urlRequest = try request.urlRequest()
    expectNoDifference(urlRequest.allowsExpensiveNetworkAccess, false)
    expectNoDifference(urlRequest.url?.query, "app_id=route-request")
    let socket = try InstantURLSessionLiveWebSocket(request: urlRequest)
    expectNoDifference(socket.openingRequest?.allowsExpensiveNetworkAccess, false)
    expectNoDifference(socket.openingRequest?.timeoutInterval, 5, "The session's timeout, as a URL-opened socket had.")
    socket.abort()
    expectNoDifference(try InstantLiveSessionRequest(appID: "route-default").urlRequest().allowsExpensiveNetworkAccess, true)
  }
}

// MARK: - Fixtures

extension InstantNetworkPathState {
  static let wifi = Self(isSatisfied: true, interface: .wifi)
  static let cellular = Self(isSatisfied: true, isExpensive: true, interface: .cellular)
}

private let routeSocketNotConnected = InstantError(
  code: .networkFailed,
  operation: "receive Instant live message",
  message: "Socket is not connected",
  recovery: "Reconnect."
)

private let routeOpenTimedOut = InstantError(
  code: .networkFailed,
  operation: "open Instant live session",
  message: "Timed out after 5000ms waiting for Instant live transport.",
  recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
)

private func routeSession(_ sessionID: String) -> LiveReactorParitySession {
  LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: sessionID)])
}

/// A runtime over scripted sessions, a scripted path and a virtual route clock, with its diagnostics recorded.
private struct RouteFixture {
  let runtime: InstantRuntime
  let transport: LiveReactorParityTransport
  let path: InstantNetworkPathMonitor
  let clock: RouteVirtualClock
  let diagnostics: RouteDiagnostics

  /// Bootstraps without connecting, then connects once.
  static func connected(
    _ name: String,
    path state: InstantNetworkPathState,
    attempts: [LiveReactorParityTransportAttempt],
    probe: InstantNetworkPath.Probe? = nil
  ) async throws -> Self {
    let fixture = try await make(name, path: state, attempts: attempts, probe: probe, autoConnect: false)
    let opened = try await fixture.runtime.connect()
    expectNoDifference(opened.state, .opened)
    return fixture
  }

  /// Bootstraps and lets the runtime connect, and reconnect, by itself.
  static func started(
    _ name: String,
    path state: InstantNetworkPathState,
    attempts: [LiveReactorParityTransportAttempt],
    probe: InstantNetworkPath.Probe? = nil
  ) async throws -> Self {
    try await make(name, path: state, attempts: attempts, probe: probe, autoConnect: true)
  }

  private static func make(
    _ name: String,
    path state: InstantNetworkPathState,
    attempts: [LiveReactorParityTransportAttempt],
    probe: InstantNetworkPath.Probe?,
    autoConnect: Bool
  ) async throws -> Self {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantNetworkRouteTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = InstantNetworkPathMonitor(path: state)
    let transport = LiveReactorParityTransport(attempts: attempts)
    var liveTransport = transport.transport
    liveTransport.networkPath = InstantNetworkPath(monitor: path, probe: probe)
    let clock = RouteVirtualClock()
    var configuration = InstantRuntimeConfiguration(
      appID: "network-route-\(name)",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      liveTransport: liveTransport
    )
    configuration.autoConnectLiveTransport = autoConnect
    configuration.liveReconnectSleep = { _ in }
    configuration.liveRouteSleep = { milliseconds in await clock.sleep(milliseconds) }
    configuration.liveRouteNow = { clock.now() }
    let diagnostics = RouteDiagnostics(appID: configuration.appID)
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    return Self(runtime: runtime, transport: transport, path: path, clock: clock, diagnostics: diagnostics)
  }

  func transact(_ id: String) async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: id,
        operations: TodoExample.createOperations(id: "todo-\(id)", text: id, createdAt: createdAt, transactionID: id)
      ),
      createdAt: createdAt
    )
  }

  func close() async {
    _ = try? await runtime.closeConnection()
    diagnostics.stop()
  }
}

/// A clock that moves only when the route watcher sleeps: each sleep returns at once and moves it on.
private final class RouteVirtualClock: Sendable {
  private let start = ContinuousClock.now
  private let state = LockedValue(InstantRouteClockState())

  func now() -> ContinuousClock.Instant {
    start + state.withLock { $0.elapsed }
  }

  func sleep(_ milliseconds: UInt64) async {
    state.withLock {
      $0.elapsed += .milliseconds(Int64(milliseconds))
      $0.sleeps.append(milliseconds)
    }
    await Task.yield()
  }

  var sleeps: [UInt64] {
    get async { state.withLock { $0.sleeps } }
  }
}

private struct InstantRouteClockState: Sendable {
  var elapsed: Duration = .zero
  var sleeps: [UInt64] = []
}

/// A value behind a lock, for the fixtures' synchronous reads.
private final class LockedValue<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
    lock.lock()
    defer { lock.unlock() }
    return body(&value)
  }
}

/// The probe's answers in order; `false` once they run out.
private actor RouteProbeScript {
  private var answers: [Bool]
  private(set) var asked: [(host: String, port: Int)] = []

  init(answers: [Bool]) {
    self.answers = answers
  }

  func answer(host: String, port: Int) -> Bool {
    asked.append((host, port))
    return answers.isEmpty ? false : answers.removeFirst()
  }
}

/// The library's diagnostics for one fixture's app while it runs: other suites' runtimes log beside it.
private final class RouteDiagnostics: Sendable {
  private let entries = LockedValue<[InstantDiagnosticEntry]>([])
  private let token = LockedValue<UUID?>(nil)

  init(appID: String) {
    let entries = entries
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.metadata["appID"] == appID else { return }
      entries.withLock { $0.append(entry) }
    }
    self.token.withLock { $0 = token }
  }

  func events(named name: String) -> [InstantDiagnosticEntry] {
    entries.withLock { $0.filter { $0.event == name } }
  }

  func stop() {
    if let token = token.withLock({ $0 }) {
      InstantDiagnostics.shared.removeHandler(token)
    }
  }
}

/// Polls `condition` every 2 ms until it holds, up to the hang bound.
private func routeWait(
  _ description: String,
  _ condition: @Sendable () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + .milliseconds(Int64(InstantTestWait.hangMilliseconds))
  while !(try await condition()) {
    guard ContinuousClock.now < deadline else {
      Issue.record("Timed out waiting for \(description).")
      throw CancellationError()
    }
    try await Task.sleep(nanoseconds: 2_000_000)
  }
}
