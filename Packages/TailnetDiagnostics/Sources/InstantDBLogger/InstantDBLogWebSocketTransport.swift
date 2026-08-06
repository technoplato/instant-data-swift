import Foundation
import os

public enum InstantDBLogWireLimits {
  /// The complete device journal is eight MiB, so every batch is a subset of this ceiling.
  public static let maximumDeviceSpoolBytes = 8 * 1_024 * 1_024
  /// JSON array separators and the fixed batch envelope remain far below this reserved headroom.
  public static let maximumBatchEnvelopeBytes = 1 * 1_024 * 1_024
  public static let maximumMessageBytes = maximumDeviceSpoolBytes + maximumBatchEnvelopeBytes
}

public struct InstantDBLogWireEvent: Codable, Equatable, Identifiable, Sendable {
  public var entry: InstantDBLogEntry
  public var id: String
  public var isProtectedEvidence: Bool
  public var timestampMs: Double

  public init(entry: InstantDBLogEntry, isProtectedEvidence: Bool) {
    self.entry = entry
    self.id = entry.id
    self.isProtectedEvidence = isProtectedEvidence
    self.timestampMs = entry.timestampMs
  }
}

public struct InstantDBLogWireBatch: Codable, Equatable, Sendable {
  public var batchID: String
  public var events: [InstantDBLogWireEvent]
  public var protocolVersion: Int
  public var type: String

  public init(batchID: String, events: [InstantDBLogWireEvent]) {
    self.batchID = batchID
    self.events = events
    self.protocolVersion = 1
    self.type = "events"
  }
}

public struct InstantDBLogWireAcknowledgement: Codable, Equatable, Sendable {
  public var acceptedEventIDs: [String]
  public var batchID: String
  public var protocolVersion: Int
  public var type: String

  public init(batchID: String, acceptedEventIDs: [String]) {
    self.acceptedEventIDs = acceptedEventIDs
    self.batchID = batchID
    self.protocolVersion = 1
    self.type = "ack"
  }
}

struct InstantDBLogWebSocketChannel: Sendable {
  var send: @Sendable (Data) async throws -> Void
  var receive: @Sendable () async throws -> Data
  var cancel: @Sendable () -> Void
}

public enum InstantDBLogWebSocketError: Error, LocalizedError {
  case acknowledgementBatchMismatch(expected: String, actual: String)
  case invalidAcknowledgement
  case messageExceedsMaximumBytes(actual: Int, maximum: Int)
  case unsupportedMessage

  public var errorDescription: String? {
    switch self {
    case .acknowledgementBatchMismatch(let expected, let actual):
      "Diagnostics collector acknowledged batch \(actual) while \(expected) was in flight."
    case .invalidAcknowledgement:
      "Diagnostics collector returned an invalid acknowledgement."
    case .messageExceedsMaximumBytes(let actual, let maximum):
      "Diagnostics batch is \(actual) bytes and exceeds the \(maximum)-byte frame limit."
    case .unsupportedMessage:
      "Diagnostics collector returned an unsupported WebSocket message."
    }
  }
}

actor InstantDBLogWebSocketTransport {
  typealias Connect = @Sendable (URLRequest) async throws -> InstantDBLogWebSocketChannel

  private var channel: InstantDBLogWebSocketChannel?
  private let connect: Connect
  private let endpoint: URL
  private let maximumMessageBytes: Int
  private let maximumReconnectAttempts: Int
  private let reportFailure: @Sendable (String) -> Void
  private let sleep: @Sendable (Duration) async -> Void
  private let token: String?

  init(
    endpoint: URL,
    token: String? = nil,
    maximumReconnectAttempts: Int = 4,
    maximumMessageBytes: Int = InstantDBLogWireLimits.maximumMessageBytes,
    connect: @escaping Connect,
    sleep: @escaping @Sendable (Duration) async -> Void = { duration in
      try? await Task.sleep(for: duration)
    },
    reportFailure: @escaping @Sendable (String) -> Void = { message in
      Logger(subsystem: "InstantDBLogger", category: "WebSocket").error(
        "\(message, privacy: .public)"
      )
    }
  ) {
    self.connect = connect
    self.endpoint = endpoint
    self.maximumMessageBytes = max(1, maximumMessageBytes)
    self.maximumReconnectAttempts = max(0, maximumReconnectAttempts)
    self.reportFailure = reportFailure
    self.sleep = sleep
    self.token = token
  }

  init(
    endpoint: URL,
    token: String? = nil,
    maximumReconnectAttempts: Int = 4,
    maximumMessageBytes: Int = InstantDBLogWireLimits.maximumMessageBytes,
    reportFailure: @escaping @Sendable (String) -> Void = { message in
      Logger(subsystem: "InstantDBLogger", category: "WebSocket").error(
        "\(message, privacy: .public)"
      )
    }
  ) {
    let session = InstantDBLogProcessWebSocketSession()
    self.init(
      endpoint: endpoint,
      token: token,
      maximumReconnectAttempts: maximumReconnectAttempts,
      maximumMessageBytes: maximumMessageBytes,
      connect: { request in session.connect(request: request) },
      reportFailure: reportFailure
    )
  }

  func send(_ batch: InstantDBLogWireBatch) async throws -> Set<String> {
    let payload = try JSONEncoder().encode(batch)
    guard payload.count <= maximumMessageBytes else {
      let error = InstantDBLogWebSocketError.messageExceedsMaximumBytes(
        actual: payload.count,
        maximum: maximumMessageBytes
      )
      reportFailure(error.localizedDescription)
      throw error
    }
    var attempt = 0
    while true {
      do {
        let channel = try await connectedChannel()
        try await channel.send(payload)
        let response = try await channel.receive()
        let acknowledgement = try JSONDecoder().decode(
          InstantDBLogWireAcknowledgement.self,
          from: response
        )
        guard acknowledgement.type == "ack", acknowledgement.protocolVersion == 1 else {
          throw InstantDBLogWebSocketError.invalidAcknowledgement
        }
        guard acknowledgement.batchID == batch.batchID else {
          throw InstantDBLogWebSocketError.acknowledgementBatchMismatch(
            expected: batch.batchID,
            actual: acknowledgement.batchID
          )
        }
        let submittedIDs = Set(batch.events.map(\.id))
        let acceptedIDs = Set(acknowledgement.acceptedEventIDs)
        guard acceptedIDs.isSubset(of: submittedIDs) else {
          throw InstantDBLogWebSocketError.invalidAcknowledgement
        }
        return acceptedIDs
      } catch {
        disconnect()
        reportFailure(error.localizedDescription)
        guard attempt < maximumReconnectAttempts else { throw error }
        let delayMilliseconds = min(5_000, 250 * (1 << min(attempt, 4)))
        attempt += 1
        await sleep(.milliseconds(delayMilliseconds))
      }
    }
  }

  func disconnect() {
    channel?.cancel()
    channel = nil
  }

  private func connectedChannel() async throws -> InstantDBLogWebSocketChannel {
    if let channel { return channel }
    var request = URLRequest(url: endpoint)
    request.timeoutInterval = 5
    if let token, !token.isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let channel = try await connect(request)
    self.channel = channel
    return channel
  }
}

private final class InstantDBLogProcessWebSocketSession: @unchecked Sendable {
  private let session: URLSession

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 5
    configuration.waitsForConnectivity = false
    session = URLSession(configuration: configuration)
  }

  func connect(request: URLRequest) -> InstantDBLogWebSocketChannel {
    let task = session.webSocketTask(with: request)
    task.resume()
    return InstantDBLogWebSocketChannel(
      send: { data in try await task.send(.data(data)) },
      receive: {
        switch try await task.receive() {
        case .data(let data):
          return data
        case .string(let string):
          return Data(string.utf8)
        @unknown default:
          throw InstantDBLogWebSocketError.unsupportedMessage
        }
      },
      cancel: { task.cancel(with: .goingAway, reason: nil) }
    )
  }
}
