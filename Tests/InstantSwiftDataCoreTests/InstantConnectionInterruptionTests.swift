import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// The connection status says why changes are not reaching Instant, as it happens (#2037).
///
/// On a cellular network that dropped every few minutes, a consuming app showed its users a failure where the network
/// was only weak: the status read `.errored` with the error as text, and a socket that died was saved as `.errored`
/// without being published, so an observer learned of it only at the next unrelated status. Upstream's server answers a
/// rate-limited operation over the socket with an `error` frame of status 400 and type `rate-limited` and keeps the
/// socket open; the library read that 400 as a refusal, so a rate-limited write failed for good and a rate-limited live
/// query was retired until relaunch.
@Suite(.serialized)
struct InstantConnectionInterruptionTests {
  static let cellular = InstantNetworkPathState(isSatisfied: true, isExpensive: true, interface: .cellular)

  /// On a network that does not carry the connection, a reconnect's failed attempt publishes the cause at once, on the
  /// path it met. A dropped socket alone reads as closed while the reconnect runs, as upstream's does: `Reactor.js` sets
  /// CLOSED for a drop and ERRORED only for a failed `init`.
  @Test
  func aFailedReconnectAttemptPublishesItsCause() async throws {
    let path = InstantNetworkPathMonitor(path: Self.cellular)
    let reconnect = ReconnectGate(freeWaits: 1)
    let fixture = try await Self.fixture(
      "failed-attempt",
      attempts: [.session(Self.openingSession("failed-attempt")), .failure(Self.openTimedOut)],
      path: path,
      reconnectSleep: { _ in try await reconnect.wait() }
    )
    await fixture.sessions[0].failReceive(Self.socketNotConnected)
    let published = try await fixture.statuses.first(within: InstantTestWait.hang) { $0.state == .errored }
    let status = try #require(published, "the failed attempt should publish its cause")
    expectNoDifference(status.interruption?.cause, .weakNetwork)
    expectNoDifference(status.interruption?.networkPath, "cellular expensive")
    #expect(status.interruption?.detail.contains("Timed out after 5000ms") == true)

    // The path goes away while the reconnect waits: the same failure now reads as no network.
    path.update(isSatisfied: false)
    let withoutPath = try await fixture.runtime.connectionStatus()
    expectNoDifference(withoutPath.interruption?.cause, .noNetwork)
    await fixture.close()
  }

  /// With no network path, a dropped socket waits for the path, and the next write that waits says why: no network. A
  /// recording writes every few seconds, so its screen says so as soon as the socket drops.
  @Test
  func withNoNetworkPathTheNextWriteSaysNoNetwork() async throws {
    let path = InstantNetworkPathMonitor(path: Self.cellular)
    let fixture = try await Self.fixture(
      "no-path",
      attempts: [.session(Self.openingSession("no-path"))],
      path: path
    )
    path.update(isSatisfied: false)
    await fixture.sessions[0].failReceive(Self.socketNotConnected)
    let deadline = ContinuousClock.now + InstantTestWait.hang
    var dropped = try await fixture.runtime.connectionStatus()
    while dropped.state != .errored, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
      dropped = try await fixture.runtime.connectionStatus()
    }
    expectNoDifference(dropped.interruption?.cause, .noNetwork)

    let before = await fixture.statuses.statuses.count
    try await Self.createTodo(fixture.runtime, id: "offline-1")
    let published = try await fixture.statuses.first(within: InstantTestWait.hang, after: before - 1) {
      $0.interruption != nil
    }
    let status = try #require(published, "the write should publish why its change waits")
    expectNoDifference(status.interruption?.cause, .noNetwork)
    expectNoDifference(status.pendingMutationCount, 1)
    await fixture.close()
  }

  /// The next open ends the interruption.
  @Test
  func theNextOpenEndsTheInterruption() async throws {
    let path = InstantNetworkPathMonitor(path: Self.cellular)
    let reconnect = ReconnectGate(freeWaits: 1)
    let fixture = try await Self.fixture(
      "reopened",
      attempts: [
        .session(Self.openingSession("reopened-1")),
        .failure(Self.openTimedOut),
        .session(Self.openingSession("reopened-2")),
      ],
      path: path,
      reconnectSleep: { _ in try await reconnect.wait() }
    )
    await fixture.sessions[0].failReceive(Self.socketNotConnected)
    let interrupted = try #require(
      try await fixture.statuses.firstIndex(within: InstantTestWait.hang) { $0.interruption != nil }
    )
    // The status stream keeps only its newest value, so the next attempt waits until the failure was seen.
    await reconnect.release()
    let reopened = try await fixture.statuses.first(within: InstantTestWait.hang, after: interrupted) {
      $0.state != .errored && $0.interruption == nil
    }
    #expect(reopened != nil, "the next session's open should publish a status with no interruption")
    let open = try await fixture.runtime.connectionStatus()
    expectNoDifference(open.interruption, nil)
    await fixture.close()
  }

  /// A write the server rate-limits stays queued, is offered again no sooner than the server's retry time, and the
  /// status says rate limited until the server accepts a write again.
  @Test
  func aRateLimitedWriteStaysQueuedAndWaitsForTheServersRetryTime() async throws {
    let retries = RetryRecorder()
    let fixture = try await Self.fixture(
      "rate-limited-write",
      sessions: [Self.openingSession("rate-limited-write")],
      path: nil,
      retries: retries
    )
    let mutationID = "tx-todo-rate-limited"
    try await Self.createTodo(fixture.runtime, id: "todo-rate-limited")
    try await fixture.sessions[0].waitForSentMessageCount(2)
    await fixture.sessions[0].enqueue(
      Self.rateLimited(answering: mutationID, op: "transact", hint: .object(["retry-after": .number(2)]))
    )
    let limited = try await fixture.statuses.first(within: InstantTestWait.hang) {
      $0.interruption?.cause == .rateLimited
    }
    let status = try #require(limited, "the status should say Instant limits this app")
    #expect(status.interruption?.retryAt != nil)
    let failed = await fixture.runtime.failedMutations().map(\.id)
    let pending = await fixture.runtime.pendingMutationCount()
    expectNoDifference(failed, [], "a rate limit is not a refusal")
    expectNoDifference(pending, 1)
    let delays = try await retries.waitForMutationDelays(mutationID, count: 1)
    #expect(delays.first.map { $0 >= 1_900 } == true, "the next offer waits for the server's two seconds: \(delays)")

    // The server takes the write when it is offered again: the interruption ends.
    try await fixture.sessions[0].waitForSentMessageCount(3)
    await fixture.sessions[0].enqueue(
      InstantLiveMessage(op: "transact-ok", clientEventID: mutationID, fields: ["tx-id": .string("server-tx-limited")])
    )
    let accepted = try await fixture.statuses.first(within: InstantTestWait.hang) {
      $0.pendingMutationCount == 0 && $0.interruption == nil
    }
    #expect(accepted != nil, "an accepted write should end the rate limit")
    await fixture.close()
  }

  /// A live query the server rate-limits is sent again on the same socket, not retired as a rejection.
  @Test
  func aRateLimitedLiveQueryIsSentAgainNotRetired() async throws {
    let fixture = try await Self.fixture(
      "rate-limited-query",
      sessions: [Self.openingSession("rate-limited-query")],
      path: nil,
      connects: false
    )
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let stream = await fixture.runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    _ = try await fixture.runtime.connect()
    let sent = try await InstantLiveQueryErrorRecoveryTests.addQueries(in: fixture.sessions[0], reaching: 1)
    let addQuery = try #require(sent.first)
    await fixture.sessions[0].enqueue(
      InstantReactorParityTests.addQueryError(
        to: query,
        clientEventID: addQuery.clientEventID,
        status: 400,
        type: "rate-limited",
        message: "You're making too many requests. Please email support@instantdb.com or ask for help in the Discord."
      )
    )
    let resent = try await InstantLiveQueryErrorRecoveryTests.addQueries(in: fixture.sessions[0], reaching: 2)
    expectNoDifference(resent.count, 2, "a rate-limited query should be sent again once the limit allows")
    await fixture.close()
  }

  /// An `init` the server answers with an error keeps the server's status and type, so its cause is known.
  @Test
  func anInitErrorKeepsTheServersStatusAndType() async throws {
    let session = LiveReactorParitySession(messages: [
      InstantLiveMessage(
        op: "error",
        clientEventID: nil,
        fields: [
          "message": .string("Operation timed out: handle-receive"),
          "type": .string("operation-timed-out"),
          "status": .number(500),
          "original-event": .object(["op": .string("init")]),
        ]
      )
    ])
    let fixture = try await Self.fixture("init-error", sessions: [session], path: nil, connects: false)
    do {
      _ = try await fixture.runtime.connect()
      Issue.record("connect should throw the init error")
    } catch let error as InstantError {
      expectNoDifference(error.serverStatus, 500)
      expectNoDifference(error.serverType, "operation-timed-out")
    }
    let afterInit = try await fixture.runtime.connectionStatus()
    expectNoDifference(afterInit.interruption?.cause, .serverUnreachable)
    await fixture.close()
  }
}

// MARK: - Fixtures

extension InstantConnectionInterruptionTests {
  struct Fixture {
    var runtime: InstantRuntime
    var sessions: [LiveReactorParitySession]
    var statuses: StatusRecorder
    var observation: Task<Void, Never>

    func close() async {
      observation.cancel()
      _ = try? await runtime.closeConnection()
    }
  }

  /// Every status the runtime publishes, in order.
  actor StatusRecorder {
    private(set) var statuses: [InstantConnectionStatus] = []

    func append(_ status: InstantConnectionStatus) {
      statuses.append(status)
    }

    /// The first published status after the one at `index` that matches, once one does or `timeout` passes.
    func first(
      within timeout: Duration,
      after index: Int = -1,
      where matches: @Sendable (InstantConnectionStatus) -> Bool
    ) async throws -> InstantConnectionStatus? {
      try await firstIndex(within: timeout, after: index, where: matches).map { statuses[$0] }
    }

    /// Where the first published status after the one at `index` that matches is, once one does or `timeout` passes.
    func firstIndex(
      within timeout: Duration,
      after index: Int = -1,
      where matches: @Sendable (InstantConnectionStatus) -> Bool
    ) async throws -> Int? {
      let deadline = ContinuousClock.now + timeout
      while true {
        if let found = statuses.indices.first(where: { $0 > index && matches(statuses[$0]) }) { return found }
        if ContinuousClock.now >= deadline { return nil }
        try await Task.sleep(for: .milliseconds(20))
      }
    }
  }

  actor RetryRecorder {
    private var retries: [(owner: InstantServerErrorRetryOwner, delay: UInt64)] = []

    func record(_ owner: InstantServerErrorRetryOwner, _ delay: UInt64) {
      retries.append((owner, delay))
    }

    func waitForMutationDelays(_ mutationID: String, count: Int) async throws -> [UInt64] {
      let deadline = ContinuousClock.now + InstantTestWait.hang
      while true {
        let delays = retries.filter { $0.owner == .mutation(mutationID) }.map(\.delay)
        if delays.count >= count || ContinuousClock.now >= deadline { return delays }
        try await Task.sleep(for: .milliseconds(20))
      }
    }
  }

  /// A reconnect wait that ends when the test releases it.
  actor ReconnectGate {
    private var freeWaits: Int
    private var isReleased = false

    /// The first `freeWaits` waits end at once; later ones wait for `release()`.
    init(freeWaits: Int = 0) {
      self.freeWaits = freeWaits
    }

    func wait() async throws {
      if freeWaits > 0 {
        freeWaits -= 1
        return
      }
      while !isReleased {
        try await Task.sleep(for: .milliseconds(5))
      }
    }

    func release() {
      isReleased = true
    }
  }

  /// A socket that died under the receive loop.
  static let socketNotConnected = InstantError(
    code: .networkFailed,
    operation: "receive Instant live message",
    message: "Socket is not connected",
    recovery: "Reconnect."
  )

  /// An open that met the five-second deadline: what a weak network, and no network, look like to the socket.
  static let openTimedOut = InstantError(
    code: .networkFailed,
    operation: "open Instant live session",
    message: "Timed out after 5000ms waiting for Instant live transport.",
    recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
  )

  static func openingSession(_ sessionID: String) -> LiveReactorParitySession {
    LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: sessionID)])
  }

  /// A runtime on scripted sessions, one per connection, with its published statuses recorded. Its reconnect parks in
  /// its first wait unless the test gives its own wait, so a drop stays visible.
  static func fixture(
    _ name: String,
    sessions: [LiveReactorParitySession] = [],
    attempts: [LiveReactorParityTransportAttempt]? = nil,
    path: InstantNetworkPathMonitor?,
    reconnectSleep: (@Sendable (UInt64) async throws -> Void)? = nil,
    connects: Bool = true,
    retries: RetryRecorder? = nil
  ) async throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantConnectionInterruptionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let attempts = attempts ?? sessions.map { .session($0) }
    var transport = LiveReactorParityTransport(attempts: attempts).transport
    if let path {
      transport.networkPath = InstantNetworkPath(monitor: path)
    }
    var configuration = InstantRuntimeConfiguration(
      appID: "connection-interruption-\(name)",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport
    )
    configuration.autoConnectLiveTransport = false
    if let reconnectSleep {
      configuration.liveReconnectSleep = reconnectSleep
    } else {
      let parked = LiveReactorParityReconnectSleep(suspendsUntilCancelled: true)
      configuration.liveReconnectSleep = { try await parked.sleep(milliseconds: $0) }
    }
    configuration.liveServerErrorRetryPolicy = InstantServerErrorRetryPolicy(jitter: { 1 })
    if let retries {
      configuration.onServerErrorRetryScheduledForTesting = { owner, _, delay in
        await retries.record(owner, delay)
      }
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let statuses = StatusRecorder()
    let stream = try await runtime.observeConnectionStatus()
    let observation = Task {
      for await status in stream {
        await statuses.append(status)
      }
    }
    if connects {
      let opened = try await runtime.connect()
      expectNoDifference(opened.state, .opened)
    }
    let opened = attempts.compactMap { attempt -> LiveReactorParitySession? in
      if case let .session(session) = attempt { return session }
      return nil
    }
    return Fixture(runtime: runtime, sessions: opened, statuses: statuses, observation: observation)
  }

  static func createTodo(_ runtime: InstantRuntime, id: String) async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_794_095_640_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-\(id)",
        operations: TodoExample.createOperations(
          id: id,
          text: "written while Instant limits this app",
          createdAt: createdAt,
          transactionID: "tx-\(id)"
        )
      ),
      createdAt: createdAt
    )
  }

  /// The server's answer to a rate-limited operation over the socket: status 400, type `rate-limited`.
  static func rateLimited(answering clientEventID: String, op: String, hint: InstantLiveJSONValue?) -> InstantLiveMessage {
    var fields: [String: InstantLiveJSONValue] = [
      "message": .string("Your request exceeded the rate limit."),
      "type": .string("rate-limited"),
      "status": .number(400),
      "original-event": .object(["client-event-id": .string(clientEventID), "op": .string(op)]),
    ]
    if let hint { fields["hint"] = hint }
    return InstantLiveMessage(op: "error", clientEventID: clientEventID, fields: fields)
  }
}
