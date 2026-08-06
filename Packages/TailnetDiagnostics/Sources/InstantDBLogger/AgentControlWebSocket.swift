import Foundation
import os

/// A bidirectional text channel on the diagnostics collector, reusing the transport that already
/// carries device logs.
///
/// The agent control lane deliberately rides the same WebSocket stack as `InstantDBLogWebSocket`
/// `Transport` — same `URLSession` configuration, same framing, same collector process — because a
/// second, differently-behaving socket would be one more thing to debug when the app is already the
/// suspect. It differs only in path (`/scribe-agent`) and in being long-lived rather than
/// batch-oriented.
public struct AgentControlWebSocketChannel: Sendable {
  public var cancel: @Sendable () -> Void
  public var receive: @Sendable () async throws -> Data
  public var send: @Sendable (Data) async throws -> Void

  public init(
    send: @escaping @Sendable (Data) async throws -> Void,
    receive: @escaping @Sendable () async throws -> Data,
    cancel: @escaping @Sendable () -> Void
  ) {
    self.cancel = cancel
    self.receive = receive
    self.send = send
  }
}

public enum AgentControlWebSocketError: Error, LocalizedError {
  case unsupportedMessage

  public var errorDescription: String? {
    switch self {
    case .unsupportedMessage:
      "The agent control collector returned an unsupported WebSocket message."
    }
  }
}

/// Opens agent-control channels with the same `URLSession` policy the diagnostics writer uses.
public final class AgentControlWebSocketSession: @unchecked Sendable {
  private let session: URLSession

  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    // The control lane holds an idle socket between commands, so it must not inherit the
    // diagnostics writer's short request timeout.
    configuration.timeoutIntervalForRequest = 300
    configuration.waitsForConnectivity = false
    session = URLSession(configuration: configuration)
  }

  public func connect(request: URLRequest) -> AgentControlWebSocketChannel {
    let task = session.webSocketTask(with: request)
    task.resume()
    return AgentControlWebSocketChannel(
      send: { data in try await task.send(.data(data)) },
      receive: {
        switch try await task.receive() {
        case .data(let data):
          return data
        case .string(let string):
          return Data(string.utf8)
        @unknown default:
          throw AgentControlWebSocketError.unsupportedMessage
        }
      },
      cancel: { task.cancel(with: .goingAway, reason: nil) }
    )
  }
}
