import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// The connection's state says what the socket is (#1024).
///
/// Builds 114, 115 and 116 read `.errored` for hours while the socket stayed open and the server accepted every write.
/// Each time, one one-shot query had failed first: on the iPhone (build 116, 15:53:10) Scribe cancelled it two seconds
/// after the socket opened; on the Mac (build 115, 14:13:14) the server answered its add-query with a 500
/// `operation-timed-out`. `queryOnceThroughLive` stored either failure as the connection's, and nothing rewrote it
/// while the socket stayed open, so every write's status said `.errored` again. Upstream `Reactor.js` sets `ERRORED`
/// only when `init` fails: a `queryOnce` that times out rejects only that query (`QUERY_ONCE_TIMEOUT`), and a server
/// error for an add-query reaches only that query's callbacks (`_handleReceiveError`). A socket that really fails
/// still reads `.errored`.
@Suite(.serialized)
struct InstantConnectionStateTruthTests {
  /// The iPhone's launch: a one-shot query cancelled before the server answers it.
  @Test
  func aCancelledOneShotQueryLeavesTheOpenConnectionOpen() async throws {
    let fixture = try await Self.connectedFixture("cancelled-query-once")
    let query = Task { try await fixture.runtime.queryOnce(TodoExample.query) }
    _ = try await Self.waitForAddQuery(in: fixture.session)
    query.cancel()
    await #expect(throws: CancellationError.self) { _ = try await query.value }

    try await Self.expectAcceptedWritesReadOpen(fixture, count: 3)
    _ = try await fixture.runtime.closeConnection()
  }

  /// The Mac's launch: the server answers one add-query with an error.
  @Test
  func aServerErrorForOneQueryLeavesTheOpenConnectionOpen() async throws {
    let fixture = try await Self.connectedFixture("server-error-query-once")
    let query = Task { try await fixture.runtime.queryOnce(TodoExample.query) }
    let addQuery = try await Self.waitForAddQuery(in: fixture.session)
    await fixture.session.enqueue(
      InstantReactorParityTests.addQueryError(
        to: try InstantLiveQueryEncoder.encode(TodoExample.query),
        clientEventID: addQuery.clientEventID,
        status: 500,
        type: "operation-timed-out",
        message: "Operation timed out: handle-receive"
      )
    )
    await #expect(throws: InstantError.self) { _ = try await query.value }

    try await Self.expectAcceptedWritesReadOpen(fixture, count: 3)
    _ = try await fixture.runtime.closeConnection()
  }

  /// A socket that fails still reads `.errored`, with its own error, until the next connection opens.
  @Test
  func aDroppedSocketStillReadsErrored() async throws {
    let fixture = try await Self.connectedFixture("dropped-socket")
    await fixture.session.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "receive Instant live message",
        message: "Socket is not connected",
        recovery: "Reconnect."
      )
    )
    try await Self.waitUntil("the drop to reach the connection's state") {
      try await fixture.runtime.connectionStatus().state == .errored
    }
    let status = try await fixture.runtime.connectionStatus()
    expectNoDifference(status.state, .errored)
    #expect(status.lastErrorMessage?.contains("Socket is not connected") == true)
    fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }
}

extension InstantConnectionStateTruthTests {
  struct Fixture {
    var runtime: InstantRuntime
    var session: LiveReactorParitySession
    var statuses: StatusRecorder
    var observation: Task<Void, Never>
  }

  /// Every connection status the runtime publishes, in order.
  actor StatusRecorder {
    private(set) var states: [InstantConnectionState] = []

    func append(_ state: InstantConnectionState) {
      states.append(state)
    }
  }

  /// One open scripted socket, with its reconnect parked in its first backoff so a drop stays visible.
  static func connectedFixture(_ name: String) async throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantConnectionStateTruthTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: name)
    ])
    let transport = LiveReactorParityTransport(sessions: [session])
    let reconnectSleep = LiveReactorParityReconnectSleep(suspendsUntilCancelled: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "connection-state-truth-\(name)",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveReconnectSleep = { try await reconnectSleep.sleep(milliseconds: $0) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let opened = try await runtime.connect()
    expectNoDifference(opened.state, .opened)
    let statuses = StatusRecorder()
    let stream = try await runtime.observeConnectionStatus()
    let observation = Task {
      for await status in stream {
        await statuses.append(status.state)
      }
    }
    return Fixture(runtime: runtime, session: session, statuses: statuses, observation: observation)
  }

  /// Writes `count` todos, answers each one's transact, and expects every status published meanwhile, and the
  /// status after, to say what the socket is: open.
  static func expectAcceptedWritesReadOpen(_ fixture: Fixture, count: Int) async throws {
    let before = await fixture.statuses.states.count
    for index in 0..<count {
      let id = "tx-truth-\(index)"
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
      try await fixture.runtime.transact(
        InstantStoreTransaction(
          id: id,
          operations: TodoExample.createOperations(
            id: "todo-\(id)",
            text: "truth \(index)",
            createdAt: createdAt,
            transactionID: id
          )
        ),
        createdAt: createdAt
      )
      try await waitUntil("the write \(id) to reach the socket") {
        await fixture.session.sentMessages().contains { $0.op == "transact" && $0.clientEventID == id }
      }
      await fixture.session.enqueue(
        InstantLiveMessage(op: "transact-ok", clientEventID: id, fields: ["tx-id": .string("server-\(id)")])
      )
      try await waitUntil("the server to accept \(id)") {
        await fixture.runtime.pendingMutations().allSatisfy { $0.id != id }
      }
    }
    try await waitUntil("a status for each accepted write") {
      await fixture.statuses.states.count >= before + count
    }
    fixture.observation.cancel()
    let published = await Array(fixture.statuses.states.dropFirst(before))
    expectNoDifference(published.filter { $0 != .opened }, [], "Published while the socket was open: \(published)")
    let status = try await fixture.runtime.connectionStatus()
    expectNoDifference(status.state, .opened)
    expectNoDifference(status.lastErrorMessage, nil)
  }

  static func waitForAddQuery(in session: LiveReactorParitySession) async throws -> InstantLiveMessage {
    try await waitUntil("the one-shot query's add-query to reach the socket") {
      await session.sentMessages().contains { $0.op == "add-query" }
    }
    return try #require(await session.sentMessages().last { $0.op == "add-query" })
  }

  struct WaitTimedOut: Error, CustomStringConvertible {
    var description: String
  }

  /// Polls `condition` every 2 ms for at most 5 s.
  static func waitUntil(
    _ description: String,
    _ condition: @Sendable () async throws -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !(try await condition()) {
      guard ContinuousClock.now < deadline else {
        throw WaitTimedOut(description: "Timed out after 5 s waiting for \(description).")
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
  }
}
