import Dependencies
import Foundation
import InstantSwiftData
import PresenceRecipesV3App

public struct InstantReactionsV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var topic: String
  public var publishedPayload: ReactionsV3Payload
  public var observedPayload: ReactionsV3Payload
  public var ignoredInvalidName: String
  public var connectionState: String

  public init(
    roomType: String,
    roomID: String,
    topic: String,
    publishedPayload: ReactionsV3Payload,
    observedPayload: ReactionsV3Payload,
    ignoredInvalidName: String,
    connectionState: String
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.topic = topic
    self.publishedPayload = publishedPayload
    self.observedPayload = observedPayload
    self.ignoredInvalidName = ignoredInvalidName
    self.connectionState = connectionState
  }
}

public enum InstantReactionsV3LiveValidation {
  public static let swiftPayload = ReactionsV3Payload(
    name: ReactionsV3Name.heart.rawValue,
    directionAngle: 45,
    rotationAngle: 270
  )

  public static let typeScriptPayload = ReactionsV3Payload(
    name: ReactionsV3Name.wave.rawValue,
    directionAngle: 90,
    rotationAngle: 180
  )

  public static let invalidPayload = ReactionsV3Payload(
    name: "sparkle",
    directionAngle: 135,
    rotationAngle: 315
  )

  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    roomID: String,
    persistenceURL: URL? = nil,
    onPayloadsObserved: @escaping @Sendable () -> Void = {}
  ) async throws -> ValidationEvidenceRow<InstantReactionsV3LiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-reactions-v3-live-\(UUID().uuidString).sqlite")
    let client = try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        context: .live
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }

    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-swift-reactions-user"
    )
    guard session.userID == expectedUserID else {
      throw failure(
        operation: "validate reactions auth",
        message: "Server-verified Swift user did not match the expected reactions peer."
      )
    }

    let room = InstantRoomHandle(type: ReactionsV3Room.roomType, id: roomID)
    let topic = ReactionsV3Room.Topic.emoji.rawValue
    let stream = try await client.observeRoomTopicMessages(room: room, topic: topic)
    _ = try await client.connect()
    _ = try await client.joinRoom(room)

    let remotePayloads = Task {
      try await withTimeout(operation: "observe TypeScript reactions payloads") {
        try await matchingRemotePayloads(in: stream)
      }
    }
    defer { remotePayloads.cancel() }

    _ = try await client.publishRoomTopicMessage(
      room: room,
      topic: topic,
      payload: try encode(swiftPayload)
    )

    let observed = try await remotePayloads.value
    onPayloadsObserved()
    let status = try await client.connectionStatus()
    _ = try await client.leaveRoom(room)
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.reactions-v3",
      side: "swift",
      event: "bidirectional-topic-payloads-observed",
      appID: appID,
      entityID: roomID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantReactionsV3LiveValidationDetails(
        roomType: room.type,
        roomID: room.id,
        topic: topic,
        publishedPayload: swiftPayload,
        observedPayload: observed.valid,
        ignoredInvalidName: observed.invalid.name,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func matchingRemotePayloads(
    in stream: AsyncStream<[InstantRoomTopicMessage]>
  ) async throws -> (valid: ReactionsV3Payload, invalid: ReactionsV3Payload) {
    var valid: ReactionsV3Payload?
    var invalid: ReactionsV3Payload?
    for await messages in stream {
      try Task.checkCancellation()
      for message in messages where message.topic == ReactionsV3Room.Topic.emoji.rawValue {
        guard let payload = try? decode(ReactionsV3Payload.self, from: message.payload) else {
          continue
        }
        if payload == typeScriptPayload {
          valid = payload
        } else if payload == invalidPayload {
          invalid = payload
        }
      }
      if let valid, let invalid { return (valid, invalid) }
    }
    throw failure(
      operation: "observe TypeScript reactions payloads",
      message: "The topic ended before the exact valid and invalid payloads arrived."
    )
  }

  private static func withTimeout<Value: Sendable>(
    operation: String,
    _ body: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: .seconds(30))
        throw failure(operation: operation, message: "Timed out after 30 seconds.")
      }
      guard let value = try await group.next() else {
        throw failure(operation: operation, message: "No result was produced.")
      }
      group.cancelAll()
      return value
    }
  }

  private static func encode<Value: Encodable>(_ value: Value) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try jsonValue(
      from: JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    )
  }

  private static func decode<Value: Decodable>(
    _ type: Value.Type,
    from value: JSONValue
  ) throws -> Value {
    let data = try JSONSerialization.data(
      withJSONObject: foundationValue(from: value),
      options: [.fragmentsAllowed, .sortedKeys]
    )
    return try JSONDecoder().decode(type, from: data)
  }

  private static func jsonValue(from value: Any) throws -> JSONValue {
    switch value {
    case is NSNull: .null
    case let value as Bool: .bool(value)
    case let value as NSNumber: .number(value.doubleValue)
    case let value as String: .string(value)
    case let value as [Any]: .array(try value.map(jsonValue(from:)))
    case let value as [String: Any]: .object(try value.mapValues(jsonValue(from:)))
    default:
      throw failure(
        operation: "encode reactions JSON",
        message: "Unsupported JSON value \(String(describing: value))."
      )
    }
  }

  private static func foundationValue(from value: JSONValue) -> Any {
    switch value {
    case .null: NSNull()
    case let .bool(value): value
    case let .number(value): value
    case let .string(value): value
    case let .array(values): values.map(foundationValue(from:))
    case let .object(values): values.mapValues(foundationValue(from:))
    }
  }

  private static func failure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the canonical TypeScript reactions peer and topic lifecycle."
    )
  }
}
