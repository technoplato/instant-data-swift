import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Library-78: a caller that is cancelled while its message is being written does not end the socket.
///
/// The live session wrote each message under a 5 s timeout that also ended on the caller's cancellation, and it treated
/// every failed write as a broken socket: it aborted the session, and the receive loop's failure reconnected. So
/// cancelling an observation while its add-query was being written closed a healthy socket and re-added every query.
/// The #388 property tests hit it when a windowed infinite query retired a chunk mid-send. Upstream `Reactor.js` writes
/// with a synchronous `ws.send`, which no caller can interrupt.
@Suite(.serialized)
struct InstantCancelledSendTests {
  /// Holds every add-query write until released.
  actor SendGate {
    private var isArmed = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var waiterCount: Int { waiting.count }

    func arm() { isArmed = true }

    func pass() async {
      guard isArmed else { return }
      await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
      isArmed = false
      let continuations = waiting
      waiting = []
      continuations.forEach { $0.resume() }
    }
  }

  actor ConnectionCounter {
    private(set) var count = 0
    func record() { count += 1 }
  }

  static func eventually(_ label: String, _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while await !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("Timed out after 5 seconds waiting until \(label).")
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test
  func anObservationCancelledWhileItsAddQueryIsWrittenLeavesTheSocketOpen() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let gate = SendGate()
    let connections = ConnectionCounter()
    let transport = InstantLiveTransportClient.immediate { _ in
      let inner = session.webSocketSession
      Task { await connections.record() }
      return InstantLiveWebSocketSession(
        send: { message in
          if message.op == "add-query" { await gate.pass() }
          try await inner.send(message)
        },
        receive: { try await inner.receive() },
        close: { await inner.close() },
        abort: { inner.abort() }
      )
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-cancelled-send-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "cancelled-send",
      persistenceURL: directory.appendingPathComponent("instant.sqlite"),
      initialAttributes: TodoExample.attributes,
      liveTransport: transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    try await Self.eventually("the socket opened") { await connections.count == 1 }

    await gate.arm()
    let observing = Task { await runtime.observeQueryLease(TodoExample.query) }
    try await Self.eventually("the add-query write began") { await gate.waiterCount == 1 }
    observing.cancel()
    try await Task.sleep(for: .milliseconds(100))
    await gate.release()
    _ = await observing.value

    // The write finished on the open socket. Nothing reconnected: the transport made one connection, and the server
    // saw one init.
    try await Task.sleep(for: .milliseconds(300))
    let connectionCount = await connections.count
    expectNoDifference(connectionCount, 1, upstreamSynchronousSendSource)
    let initCount = await session.sentMessages().filter { $0.op == "init" }.count
    expectNoDifference(initCount, 1, upstreamSynchronousSendSource)
    let status = try await runtime.connectionStatus()
    #expect(status.state == .opened || status.state == .authenticated, "the socket is still open: \(status.state)")
    _ = try await runtime.closeConnection()
  }
}

private let upstreamSynchronousSendSource =
  "upstream/instant/client/packages/core/src/Reactor.js _trySend (ws.send is synchronous; no caller can interrupt a write) [adapted: Swift awaits each write; the caller's cancellation no longer abandons it or ends the socket.]"
