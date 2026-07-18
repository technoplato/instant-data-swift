import Dependencies
import Foundation
import InstantSwiftData

public struct InstantPlaybackRoomPresenceValue: Codable, Equatable, Sendable {
  public var userID: String
  public var displayName: String
  public var isPlaying: Bool
  public var offsetSeconds: Double
  public var focusedSegmentID: String?

  public init(
    userID: String,
    displayName: String,
    isPlaying: Bool,
    offsetSeconds: Double,
    focusedSegmentID: String?
  ) {
    self.userID = userID
    self.displayName = displayName
    self.isPlaying = isPlaying
    self.offsetSeconds = offsetSeconds
    self.focusedSegmentID = focusedSegmentID
  }
}

public struct InstantPlaybackRoomTopicValues: Codable, Equatable, Sendable {
  public var reaction: InstantPlaybackRoomReactionValue
  public var commentDraft: InstantPlaybackRoomCommentDraftValue
  public var commentCommitted: InstantPlaybackRoomCommentCommittedValue

  public init(
    reaction: InstantPlaybackRoomReactionValue,
    commentDraft: InstantPlaybackRoomCommentDraftValue,
    commentCommitted: InstantPlaybackRoomCommentCommittedValue
  ) {
    self.reaction = reaction
    self.commentDraft = commentDraft
    self.commentCommitted = commentCommitted
  }
}

public struct InstantPlaybackRoomReactionValue: Codable, Equatable, Sendable {
  public var emoji: String
  public var offsetSeconds: Double

  public init(emoji: String, offsetSeconds: Double) {
    self.emoji = emoji
    self.offsetSeconds = offsetSeconds
  }
}

public struct InstantPlaybackRoomCommentDraftValue: Codable, Equatable, Sendable {
  public var text: String
  public var offsetSeconds: Double

  public init(text: String, offsetSeconds: Double) {
    self.text = text
    self.offsetSeconds = offsetSeconds
  }
}

public struct InstantPlaybackRoomCommentCommittedValue: Codable, Equatable, Sendable {
  public var commentID: String

  public init(commentID: String) {
    self.commentID = commentID
  }
}

public struct InstantPlaybackRoomLiveValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var swiftUserID: String
  public var typeScriptUserID: String
  public var publishedPresence: InstantPlaybackRoomPresenceValue
  public var receivedPresence: InstantPlaybackRoomPresenceValue
  public var publishedTopics: InstantPlaybackRoomTopicValues
  public var receivedTopics: InstantPlaybackRoomTopicValues
  public var connectionState: String

  public init(
    roomType: String,
    roomID: String,
    swiftUserID: String,
    typeScriptUserID: String,
    publishedPresence: InstantPlaybackRoomPresenceValue,
    receivedPresence: InstantPlaybackRoomPresenceValue,
    publishedTopics: InstantPlaybackRoomTopicValues,
    receivedTopics: InstantPlaybackRoomTopicValues,
    connectionState: String
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.swiftUserID = swiftUserID
    self.typeScriptUserID = typeScriptUserID
    self.publishedPresence = publishedPresence
    self.receivedPresence = receivedPresence
    self.publishedTopics = publishedTopics
    self.receivedTopics = receivedTopics
    self.connectionState = connectionState
  }
}

public enum InstantPlaybackRoomLiveValidation {
  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    swiftUserID: String,
    typeScriptUserID: String,
    roomID: String,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantPlaybackRoomLiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-playback-room-live-\(UUID().uuidString).sqlite")
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
      userID: "untrusted-swift-playback-user"
    )
    guard session.userID == swiftUserID else {
      throw validationFailure(
        operation: "validate playback room auth",
        message: "Server-verified Swift user did not match the expected room peer."
      )
    }

    let room = InstantRoomHandle(type: "recording.playback", id: roomID)
    let presenceStream = try await client.observeRoomPresence(room: room)
    let reactionStream = try await client.observeRoomTopicMessages(
      room: room,
      topic: "reaction"
    )
    let draftStream = try await client.observeRoomTopicMessages(
      room: room,
      topic: "commentDraft"
    )
    let committedStream = try await client.observeRoomTopicMessages(
      room: room,
      topic: "commentCommitted"
    )

    let expectedTypeScriptPresence = PlaybackPresence(
      userID: InstantID(rawValue: typeScriptUserID),
      displayName: "TypeScript Listener",
      isPlaying: false,
      offsetSeconds: 4.25,
      focusedSegmentID: InstantID(rawValue: "segment-typescript")
    )
    let expectedTypeScriptTopics = PlaybackTopics(
      reaction: PlaybackReaction(emoji: "typescript-wave", offsetSeconds: 4.25),
      commentDraft: PlaybackCommentDraft(text: "TypeScript draft", offsetSeconds: 4.25),
      commentCommitted: PlaybackCommentCommitted(commentID: "comment-typescript")
    )
    let remoteObservation = Task {
      try await withTimeout(operation: "observe TypeScript playback room payloads") {
        async let presence = matchingPresence(
          expectedTypeScriptPresence,
          in: presenceStream
        )
        async let reaction = matchingTopic(
          expectedTypeScriptTopics.reaction,
          in: reactionStream
        )
        async let draft = matchingTopic(
          expectedTypeScriptTopics.commentDraft,
          in: draftStream
        )
        async let committed = matchingTopic(
          expectedTypeScriptTopics.commentCommitted,
          in: committedStream
        )
        return try await PlaybackObservation(
          presence: presence,
          topics: PlaybackTopics(
            reaction: reaction,
            commentDraft: draft,
            commentCommitted: committed
          )
        )
      }
    }
    defer { remoteObservation.cancel() }

    _ = try await client.connect()
    _ = try await client.joinRoom(room)

    let swiftPresence = PlaybackPresence(
      userID: InstantID(rawValue: swiftUserID),
      displayName: "Swift Listener",
      isPlaying: true,
      offsetSeconds: 12.5,
      focusedSegmentID: InstantID(rawValue: "segment-swift")
    )
    let swiftTopics = PlaybackTopics(
      reaction: PlaybackReaction(emoji: "swift-wave", offsetSeconds: 12.5),
      commentDraft: PlaybackCommentDraft(text: "Swift draft", offsetSeconds: 12.5),
      commentCommitted: PlaybackCommentCommitted(commentID: "comment-swift")
    )
    let publishedPresence = try encodeObject(swiftPresence)
    let publishedTopics = try encodeTopics(swiftTopics)

    _ = try await client.setRoomPresence(room: room, values: publishedPresence)
    for topic in publishedTopics.keys.sorted() {
      guard let payload = publishedTopics[topic] else { continue }
      _ = try await client.publishRoomTopicMessage(
        room: room,
        topic: topic,
        payload: payload
      )
    }

    let observed = try await remoteObservation.value
    let status = try await client.connectionStatus()
    _ = try await client.leaveRoom(room)

    return ValidationEvidenceRow(
      caseID: "validation.live.playback-room",
      side: "swift",
      event: "bidirectional-payloads-observed",
      appID: appID,
      entityID: roomID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1000).rounded()),
      ok: true,
      details: InstantPlaybackRoomLiveValidationDetails(
        roomType: room.type,
        roomID: room.id,
        swiftUserID: swiftUserID,
        typeScriptUserID: typeScriptUserID,
        publishedPresence: swiftPresence.evidence,
        receivedPresence: observed.presence.evidence,
        publishedTopics: swiftTopics.evidence,
        receivedTopics: observed.topics.evidence,
        connectionState: status.state.rawValue
      )
    )
  }

  private static func matchingPresence(
    _ expected: PlaybackPresence,
    in stream: AsyncStream<[InstantRoomPresenceMember]>
  ) async throws -> PlaybackPresence {
    for await members in stream {
      for member in members {
        guard let value = try? decode(PlaybackPresence.self, from: .object(member.values)) else {
          continue
        }
        if value == expected { return value }
      }
    }
    throw validationFailure(
      operation: "observe TypeScript playback presence",
      message: "The presence stream ended before the exact TypeScript payload arrived."
    )
  }

  private static func matchingTopic<Value: Codable & Equatable & Sendable>(
    _ expected: Value,
    in stream: AsyncStream<[InstantRoomTopicMessage]>
  ) async throws -> Value {
    for await messages in stream {
      for message in messages {
        guard let value = try? decode(Value.self, from: message.payload) else { continue }
        if value == expected { return value }
      }
    }
    throw validationFailure(
      operation: "observe TypeScript playback topic",
      message: "The topic stream ended before the exact TypeScript payload arrived."
    )
  }

  private static func withTimeout<Value: Sendable>(
    operation: String,
    body: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
      group.addTask { try await body() }
      group.addTask {
        try await Task.sleep(for: .seconds(20))
        throw InstantError(
          code: .networkFailed,
          operation: operation,
          message: "Timed out after 20 seconds.",
          recovery: "Inspect both SDK room subscriptions and the exact playback payloads."
        )
      }
      guard let value = try await group.next() else {
        throw validationFailure(operation: operation, message: "No timeout task completed.")
      }
      group.cancelAll()
      return value
    }
  }

  private static func encodeTopics(_ topics: PlaybackTopics) throws -> [String: JSONValue] {
    [
      "commentCommitted": try encode(topics.commentCommitted),
      "commentDraft": try encode(topics.commentDraft),
      "reaction": try encode(topics.reaction),
    ]
  }

  private static func encodeObject<Value: Encodable>(_ value: Value) throws
    -> [String: JSONValue]
  {
    guard case let .object(object) = try encode(value) else {
      throw validationFailure(
        operation: "encode playback room presence",
        message: "Playback presence did not encode as a JSON object."
      )
    }
    return object
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
    case is NSNull:
      return .null
    case let value as Bool:
      return .bool(value)
    case let value as NSNumber:
      return .number(value.doubleValue)
    case let value as String:
      return .string(value)
    case let value as [Any]:
      return .array(try value.map(jsonValue(from:)))
    case let value as [String: Any]:
      return .object(try value.mapValues(jsonValue(from:)))
    default:
      throw validationFailure(
        operation: "encode playback room JSON",
        message: "Unsupported JSON value \(String(describing: value))."
      )
    }
  }

  private static func foundationValue(from value: JSONValue) -> Any {
    switch value {
    case .null:
      return NSNull()
    case let .bool(value):
      return value
    case let .number(value):
      return value
    case let .string(value):
      return value
    case let .array(values):
      return values.map(foundationValue(from:))
    case let .object(values):
      return values.mapValues(foundationValue(from:))
    }
  }

  private static func validationFailure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Keep the Swift and canonical TypeScript playback room contracts exact."
    )
  }
}

private enum PlaybackUser {}
private enum PlaybackSegment {}

private struct PlaybackPresence: Codable, Equatable, Sendable {
  var userID: InstantID<PlaybackUser>
  var displayName: String
  var isPlaying: Bool
  var offsetSeconds: Double
  var focusedSegmentID: InstantID<PlaybackSegment>?
}

private struct PlaybackReaction: Codable, Equatable, Sendable {
  var emoji: String
  var offsetSeconds: Double
}

private struct PlaybackCommentDraft: Codable, Equatable, Sendable {
  var text: String
  var offsetSeconds: Double
}

private struct PlaybackCommentCommitted: Codable, Equatable, Sendable {
  var commentID: String
}

private struct PlaybackTopics: Sendable {
  var reaction: PlaybackReaction
  var commentDraft: PlaybackCommentDraft
  var commentCommitted: PlaybackCommentCommitted
}

private struct PlaybackObservation: Sendable {
  var presence: PlaybackPresence
  var topics: PlaybackTopics
}

private extension PlaybackPresence {
  var evidence: InstantPlaybackRoomPresenceValue {
    InstantPlaybackRoomPresenceValue(
      userID: userID.rawValue,
      displayName: displayName,
      isPlaying: isPlaying,
      offsetSeconds: offsetSeconds,
      focusedSegmentID: focusedSegmentID?.rawValue
    )
  }
}

private extension PlaybackTopics {
  var evidence: InstantPlaybackRoomTopicValues {
    InstantPlaybackRoomTopicValues(
      reaction: InstantPlaybackRoomReactionValue(
        emoji: reaction.emoji,
        offsetSeconds: reaction.offsetSeconds
      ),
      commentDraft: InstantPlaybackRoomCommentDraftValue(
        text: commentDraft.text,
        offsetSeconds: commentDraft.offsetSeconds
      ),
      commentCommitted: InstantPlaybackRoomCommentCommittedValue(
        commentID: commentCommitted.commentID
      )
    )
  }
}
