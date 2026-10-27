// History:
// - 2026-10-24: added (#1124): the live socket counts its frames and bytes by op, each way, and the device log reports
//   them once a minute, so a phone's bytes per change can be measured.

import CustomDump
import Foundation
import Network
import Testing

@testable import InstantSwiftDataCore

@Suite
struct InstantWireMeterTests {
  /// One frame sent and one received through the URLSession socket, against a WebSocket server on the loopback
  /// interface: each counted under its op and direction with its text's size, as the library encoded and decoded it.
  @Test
  func theSocketCountsEachFrameByOpAndDirection() async throws {
    let reply = #"{"op":"refresh-ok","processed-tx-id":7}"#
    let server = try await LoopbackWebSocketServer.start(reply: reply)
    defer { server.stop() }
    let meter = InstantWireMeterStorage()
    let socket = try InstantURLSessionLiveWebSocket(url: server.url, wireMeter: meter)
    let message = InstantLiveMessage(op: "transact", clientEventID: "event-1", fields: ["tx-steps": .array([])])

    try await socket.send(message)
    let received = try await socket.receive()
    await socket.close()

    expectNoDifference(received.op, "refresh-ok")
    expectNoDifference(
      meter.snapshot(),
      InstantWireSnapshot(
        sent: ["transact": InstantWireSnapshot.Measure(frames: 1, bytes: try JSONEncoder().encode(message).count)],
        received: ["refresh-ok": InstantWireSnapshot.Measure(frames: 1, bytes: reply.utf8.count)]
      )
    )
  }

  /// The meter hands back a summary once a minute of traffic has passed: what that minute added, by op and direction,
  /// which the socket logs as `network.wire-summary`.
  @Test
  func aSummaryCoversWhatTheMinuteAdded() {
    let meter = InstantWireMeterStorage(now: 0)
    let minute = InstantWireMeterStorage.summaryIntervalNanoseconds

    let early = [
      meter.record(.sent, op: "transact", bytes: 1_150, now: 1),
      meter.record(.received, op: "transact-ok", bytes: 210, now: 2),
    ]
    let first = meter.record(.received, op: "refresh-ok", bytes: 129_100, now: minute)
    let quiet = meter.record(.sent, op: "transact", bytes: 1_200, now: minute + 1)
    let second = meter.record(.received, op: "refresh-ok", bytes: 128_000, now: 2 * minute)

    expectNoDifference(early, [nil, nil])
    expectNoDifference(
      first,
      InstantWireSnapshot(
        sent: ["transact": InstantWireSnapshot.Measure(frames: 1, bytes: 1_150)],
        received: [
          "transact-ok": InstantWireSnapshot.Measure(frames: 1, bytes: 210),
          "refresh-ok": InstantWireSnapshot.Measure(frames: 1, bytes: 129_100),
        ]
      )
    )
    expectNoDifference(quiet, nil)
    expectNoDifference(
      second?.logMetadata,
      [
        "sentFrames": "1", "sentBytes": "1200", "receivedFrames": "1", "receivedBytes": "128000",
        "sent.transact": "1/1200", "received.refresh-ok": "1/128000",
      ]
    )
    expectNoDifference(meter.snapshot().receivedBytes, 210 + 129_100 + 128_000)
  }
}

/// A WebSocket server on the loopback interface that answers each message it receives with one text frame.
private final class LoopbackWebSocketServer: @unchecked Sendable {
  // SAFETY: `connections` is touched only on `queue`; `port` is set once, before `start` returns the server.
  private let listener: NWListener
  private let reply: String
  private let queue = DispatchQueue(label: "instant-wire-meter-tests.server")
  private var connections: [NWConnection] = []
  private var port: UInt16 = 0

  var url: URL { URL(string: "ws://127.0.0.1:\(port)/runtime/session")! }

  private init(listener: NWListener, reply: String) {
    self.listener = listener
    self.reply = reply
  }

  static func start(reply: String) async throws -> LoopbackWebSocketServer {
    let parameters = NWParameters.tcp
    parameters.acceptLocalOnly = true
    parameters.requiredInterfaceType = .loopback
    let webSocket = NWProtocolWebSocket.Options()
    webSocket.autoReplyPing = true
    parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
    let listener = try NWListener(using: parameters)
    let server = LoopbackWebSocketServer(listener: listener, reply: reply)
    listener.newConnectionHandler = { [server] connection in server.accept(connection) }
    server.port = try await withCheckedThrowingContinuation { continuation in
      let once = ResumeOnce()
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
        case .failed(let error):
          if once.claim() { continuation.resume(throwing: error) }
        default:
          break
        }
      }
      listener.start(queue: server.queue)
    }
    return server
  }

  private func accept(_ connection: NWConnection) {
    connections.append(connection)
    connection.start(queue: queue)
    answer(connection)
  }

  private func answer(_ connection: NWConnection) {
    connection.receiveMessage { [weak self] data, _, _, error in
      guard let self, error == nil, data != nil else { return }
      let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
      let context = NWConnection.ContentContext(identifier: "reply", metadata: [metadata])
      connection.send(
        content: Data(self.reply.utf8),
        contentContext: context,
        isComplete: true,
        completion: .contentProcessed { _ in }
      )
      self.answer(connection)
    }
  }

  func stop() {
    queue.async {
      for connection in self.connections { connection.cancel() }
      self.connections = []
    }
    listener.cancel()
  }
}

/// Lets a callback that may run more than once resume its continuation once.
private final class ResumeOnce: @unchecked Sendable {
  // SAFETY: `lock` guards `claimed`.
  private let lock = NSLock()
  private var claimed = false

  func claim() -> Bool {
    lock.withLock {
      defer { claimed = true }
      return !claimed
    }
  }
}
