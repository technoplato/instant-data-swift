import AuthV3App
import Dependencies
import Foundation
import InstantSwiftData
import MobileChatV3App

@MainActor
private final class MobileChatV3MessageOutcome {
  var accepted = false
  var failure: InstantError?
}

public struct InstantMobileChatV3LiveValidationDetails: Codable, Equatable, Sendable {
  public var direction: String
  public var userID: String
  public var profileID: String
  public var displayName: String
  public var channelID: String
  public var channelName: String
  public var messageID: String
  public var messageChannelID: String
  public var authorProfileID: String
  public var content: String
  public var timestampMilliseconds: Int64
  public var connectionState: String
  public var pendingMutationCount: Int

  public init(
    direction: String,
    userID: String,
    profileID: String,
    displayName: String,
    channelID: String,
    channelName: String,
    messageID: String,
    messageChannelID: String,
    authorProfileID: String,
    content: String,
    timestampMilliseconds: Int64,
    connectionState: String,
    pendingMutationCount: Int
  ) {
    self.direction = direction
    self.userID = userID
    self.profileID = profileID
    self.displayName = displayName
    self.channelID = channelID
    self.channelName = channelName
    self.messageID = messageID
    self.messageChannelID = messageChannelID
    self.authorProfileID = authorProfileID
    self.content = content
    self.timestampMilliseconds = timestampMilliseconds
    self.connectionState = connectionState
    self.pendingMutationCount = pendingMutationCount
  }
}

public struct InstantMobileChatV3RoomValidationDetails: Codable, Equatable, Sendable {
  public var roomType: String
  public var roomID: String
  public var peerCount: Int
  public var presence: MobileChatPresence
  public var typing: MobileChatTypingEvent
  public var emoji: MobileChatReaction
  public var peerCountAfterDisconnect: Int
  public var receivedPresence: MobileChatPresence?
  public var receivedTyping: MobileChatTypingEvent?
  public var receivedEmoji: MobileChatReaction?

  public init(
    roomType: String,
    roomID: String,
    peerCount: Int,
    presence: MobileChatPresence,
    typing: MobileChatTypingEvent,
    emoji: MobileChatReaction,
    peerCountAfterDisconnect: Int,
    receivedPresence: MobileChatPresence? = nil,
    receivedTyping: MobileChatTypingEvent? = nil,
    receivedEmoji: MobileChatReaction? = nil
  ) {
    self.roomType = roomType
    self.roomID = roomID
    self.peerCount = peerCount
    self.presence = presence
    self.typing = typing
    self.emoji = emoji
    self.peerCountAfterDisconnect = peerCountAfterDisconnect
    self.receivedPresence = receivedPresence
    self.receivedTyping = receivedTyping
    self.receivedEmoji = receivedEmoji
  }
}

public struct InstantMobileChatV3WriteValidationDetails: Codable, Equatable, Sendable {
  public var graph: InstantMobileChatV3LiveValidationDetails
  public var room: InstantMobileChatV3RoomValidationDetails

  public init(
    graph: InstantMobileChatV3LiveValidationDetails,
    room: InstantMobileChatV3RoomValidationDetails
  ) {
    self.graph = graph
    self.room = room
  }
}

public struct InstantMobileChatV3SessionValidationDetails: Codable, Equatable, Sendable {
  public var swift: InstantMobileChatV3LiveValidationDetails
  public var observedTypeScript: InstantMobileChatV3LiveValidationDetails
  public var room: InstantMobileChatV3RoomValidationDetails

  public init(
    swift: InstantMobileChatV3LiveValidationDetails,
    observedTypeScript: InstantMobileChatV3LiveValidationDetails,
    room: InstantMobileChatV3RoomValidationDetails
  ) {
    self.swift = swift
    self.observedTypeScript = observedTypeScript
    self.room = room
  }
}

public enum InstantMobileChatV3LiveValidation {
  public static func write(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    profileID: String,
    displayName: String,
    channelID: String,
    channelName: String,
    messageID: String,
    content: String,
    timestampMilliseconds: Int64,
    expectedPeerProfileID: String,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantMobileChatV3WriteValidationDetails> {
    let client = try await liveClient(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(
      client,
      refreshToken: refreshToken,
      expectedUserID: expectedUserID
    )

    let room = InstantRoomHandle(type: MobileChatRoom.roomType, id: channelID)
    let presenceStream = try await client.observeRoomPresence(room: room)
    let typingStream = try await client.observeRoomTopicMessages(
      room: room,
      topic: MobileChatRoom.Topic.typing.rawValue
    )
    let emojiStream = try await client.observeRoomTopicMessages(
      room: room,
      topic: MobileChatRoom.Topic.emoji.rawValue
    )
    let expectedPeerPresence = MobileChatPresence(
      profileID: expectedPeerProfileID,
      displayName: "TypeScript Chatter"
    )
    let expectedPeerTyping = MobileChatTypingEvent(isTyping: false)
    let expectedPeerEmoji = MobileChatReaction(
      name: .heart,
      directionAngle: 45,
      rotationAngle: 270
    )
    let remoteRoom = Task {
      try await withTimeout(operation: "observe TypeScript Mobile Chat room payloads") {
        async let presence = matchingPresence(
          expectedPeerPresence,
          in: presenceStream
        )
        async let typing = matchingTopic(expectedPeerTyping, in: typingStream)
        async let emoji = matchingTopic(expectedPeerEmoji, in: emojiStream)
        return try await (presence, typing, emoji)
      }
    }
    defer { remoteRoom.cancel() }

    _ = try await client.joinRoom(room)
    let swiftPresence = MobileChatPresence(profileID: profileID, displayName: displayName)
    let swiftTyping = MobileChatTypingEvent(isTyping: true)
    let swiftEmoji = MobileChatReaction(name: .wave, directionAngle: 90, rotationAngle: 180)
    _ = try await client.setRoomPresence(
      room: room,
      values: try encodeObject(swiftPresence)
    )
    _ = try await client.publishRoomTopicMessage(
      room: room,
      topic: MobileChatRoom.Topic.typing.rawValue,
      payload: try encode(swiftTyping)
    )
    _ = try await client.publishRoomTopicMessage(
      room: room,
      topic: MobileChatRoom.Topic.emoji.rawValue,
      payload: try encode(swiftEmoji)
    )

    let typedProfileID = InstantID<MobileChatProfile>(rawValue: profileID)
    let typedChannelID = InstantID<MobileChatChannel>(rawValue: channelID)
    try await sendAndRequireServerAcceptance(
      CreateMobileChatProfile(
        id: typedProfileID,
        userID: InstantID<AuthV3User>(rawValue: expectedUserID),
        displayName: displayName
      ),
      using: client,
      operation: "create Mobile Chat V3 profile"
    )
    try await sendAndRequireServerAcceptance(
      CreateMobileChatChannel(id: typedChannelID, name: channelName),
      using: client,
      operation: "create Mobile Chat V3 channel"
    )
    try await sendAndRequireServerAcceptance(
      SendMobileChatMessage(
        id: InstantID(rawValue: messageID),
        channelID: typedChannelID,
        authorProfileID: typedProfileID,
        content: content,
        timestampMilliseconds: timestampMilliseconds
      ),
      using: client,
      operation: "send Mobile Chat V3 message"
    )

    let graph = try await evidence(
      direction: "swift-to-typescript",
      userID: expectedUserID,
      profileID: profileID,
      displayName: displayName,
      channelID: channelID,
      channelName: channelName,
      messageID: messageID,
      authorProfileID: profileID,
      content: content,
      timestampMilliseconds: timestampMilliseconds,
      client: client
    )
    let observedRoom = try await remoteRoom.value
    _ = try await client.publishRoomTopicMessage(
      room: room,
      topic: MobileChatRoom.Topic.emoji.rawValue,
      payload: try encode(
        MobileChatReaction(name: .confetti, directionAngle: 0, rotationAngle: 0)
      )
    )
    let peerCountAfterDisconnect = try await waitForNoPeers(in: presenceStream)
    _ = try await client.leaveRoom(room)
    _ = try await client.closeConnection()

    return ValidationEvidenceRow(
      caseID: "validation.live.mobile-chat-v3",
      side: "swift",
      event: "swift-graph-and-room-observed",
      appID: appID,
      entityID: messageID,
      timestampMs: milliseconds(Date()),
      ok: true,
      details: InstantMobileChatV3WriteValidationDetails(
        graph: graph,
        room: InstantMobileChatV3RoomValidationDetails(
          roomType: room.type,
          roomID: room.id,
          peerCount: observedRoom.0.peerCount,
          presence: swiftPresence,
          typing: swiftTyping,
          emoji: swiftEmoji,
          peerCountAfterDisconnect: peerCountAfterDisconnect,
          receivedPresence: observedRoom.0.presence,
          receivedTyping: observedRoom.1,
          receivedEmoji: observedRoom.2
        )
      )
    )
  }

  public static func observe(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    profileID: String,
    displayName: String,
    channelID: String,
    channelName: String,
    messageID: String,
    content: String,
    timestampMilliseconds: Int64,
    persistenceURL: URL? = nil
  ) -> AsyncThrowingStream<
    ValidationEvidenceRow<InstantMobileChatV3LiveValidationDetails>,
    Error
  > {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let client = try await liveClient(
            appID: appID,
            apiURI: apiURI,
            websocketURI: websocketURI,
            persistenceURL: persistenceURL
          )
          try await authenticate(
            client,
            refreshToken: refreshToken,
            expectedUserID: expectedUserID
          )

          let profiles = FetchAll<MobileChatProfile>()
          let channels = FetchAll<MobileChatChannel>()
          let messages = FetchAll<MobileChatMessage>()
          let profileTask = Task {
            try await profiles.task(MobileChatProfile.query, using: client)
          }
          let channelTask = Task {
            try await channels.task(MobileChatChannel.query, using: client)
          }
          let messageTask = Task {
            try await messages.task(
              MobileChatMessage.query
                .where(MobileChatMessage.channelID == InstantID(rawValue: channelID))
                .order(MobileChatMessage.timestampMilliseconds, .ascending),
              using: client
            )
          }
          defer {
            profileTask.cancel()
            channelTask.cancel()
            messageTask.cancel()
          }

          let ready = try await evidence(
              direction: "typescript-to-swift",
              userID: expectedUserID,
              profileID: profileID,
              displayName: displayName,
              channelID: channelID,
              channelName: channelName,
              messageID: messageID,
              authorProfileID: profileID,
              content: content,
              timestampMilliseconds: timestampMilliseconds,
              client: client
            )
          continuation.yield(
            evidenceRow(
              ready,
              appID: appID,
              event: "observer-ready"
            )
          )
          let observed = try await waitForGraph(
            profileID: profileID,
            displayName: displayName,
            channelID: channelID,
            channelName: channelName,
            messageID: messageID,
            content: content,
            timestampMilliseconds: timestampMilliseconds,
            profiles: profiles,
            channels: channels,
            messages: messages
          )
          guard let observedAuthorProfileID = observed.message.authorProfileID?.rawValue else {
            throw failure(
              operation: "observe TypeScript Mobile Chat V3 author",
              message: "The exact message was missing its canonical author relation."
            )
          }
          let observedDetails = try await evidence(
              direction: "typescript-to-swift",
              userID: observed.profile.userID.rawValue,
              profileID: observed.profile.id.rawValue,
              displayName: observed.profile.displayName,
              channelID: observed.channel.id.rawValue,
              channelName: observed.channel.name,
              messageID: observed.message.id.rawValue,
              authorProfileID: observedAuthorProfileID,
              content: observed.message.content,
              timestampMilliseconds: observed.message.timestampMilliseconds,
              client: client
            )
          continuation.yield(
            evidenceRow(
              observedDetails,
              appID: appID,
              event: "typescript-graph-observed"
            )
          )
          profileTask.cancel()
          channelTask.cancel()
          messageTask.cancel()
          _ = try? await profileTask.value
          _ = try? await channelTask.value
          _ = try? await messageTask.value
          _ = try await client.closeConnection()
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func liveClient(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantSwiftDataClient {
    try await withDependencies {
      $0.context = .live
      $0.instantLiveTransport = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL
          ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-mobile-chat-v3-live-\(UUID().uuidString).sqlite"),
        context: .live,
        initialAttributes:
          AuthV3User.instantAttributes
          + MobileChatProfile.instantAttributes
          + MobileChatChannel.instantAttributes
          + MobileChatMessage.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }
  }

  private static func authenticate(
    _ client: InstantSwiftDataClient,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-mobile-chat-v3-user"
    )
    guard session.userID == expectedUserID else {
      throw failure(
        operation: "authenticate Mobile Chat V3",
        message: "Server-verified user did not match the expected app user."
      )
    }
    _ = try await client.connect()
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      if try await client.connectionStatus().state == .authenticated { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw failure(
      operation: "wait for Mobile Chat V3 authentication",
      message: "The live client did not reach authenticated state."
    )
  }

  private static func sendAndRequireServerAcceptance<Message: InstantMessage>(
    _ message: Message,
    using client: InstantSwiftDataClient,
    operation: String
  ) async throws {
    let outcome = await MainActor.run { MobileChatV3MessageOutcome() }
    let task = client.send(
      message,
      onServerAccepted: { _ in outcome.accepted = true },
      onFailure: { outcome.failure = $0 }
    )
    defer { task.cancel() }
    try await withTimeout(operation: operation) { await task.value }
    let result = await MainActor.run { (outcome.accepted, outcome.failure) }
    if let failure = result.1 { throw failure }
    guard result.0 else {
      throw failure(
        operation: operation,
        message: "The app message completed without server acceptance."
      )
    }
  }

  private static func waitForGraph(
    profileID: String,
    displayName: String,
    channelID: String,
    channelName: String,
    messageID: String,
    content: String,
    timestampMilliseconds: Int64,
    profiles: FetchAll<MobileChatProfile>,
    channels: FetchAll<MobileChatChannel>,
    messages: FetchAll<MobileChatMessage>
  ) async throws -> (
    profile: MobileChatProfile,
    channel: MobileChatChannel,
    message: MobileChatMessage
  ) {
    try await withTimeout(operation: "observe TypeScript Mobile Chat V3 graph") {
      while true {
        if let profile = profiles.wrappedValue.first(where: {
          $0.id.rawValue == profileID && $0.displayName == displayName
        }), let channel = channels.wrappedValue.first(where: {
          $0.id.rawValue == channelID && $0.name == channelName
        }), let message = messages.wrappedValue.first(where: {
          $0.id.rawValue == messageID
            && $0.channelID.rawValue == channelID
            && $0.authorProfileID?.rawValue == profileID
            && $0.content == content
            && $0.timestampMilliseconds == timestampMilliseconds
        }) {
          return (profile, channel, message)
        }
        if let error = profiles.loadError ?? channels.loadError ?? messages.loadError {
          throw error
        }
        try await Task.sleep(for: .milliseconds(25))
      }
    }
  }

  private static func evidence(
    direction: String,
    userID: String,
    profileID: String,
    displayName: String,
    channelID: String,
    channelName: String,
    messageID: String,
    authorProfileID: String,
    content: String,
    timestampMilliseconds: Int64,
    client: InstantSwiftDataClient
  ) async throws -> InstantMobileChatV3LiveValidationDetails {
    let status = try await client.connectionStatus()
    let pendingMutationCount = await client.pendingMutations().count
    guard status.state == .authenticated, pendingMutationCount == 0 else {
      throw failure(
        operation: "record Mobile Chat V3 evidence",
        message: "Expected authenticated state with zero pending mutations."
      )
    }
    return InstantMobileChatV3LiveValidationDetails(
      direction: direction,
      userID: userID,
      profileID: profileID,
      displayName: displayName,
      channelID: channelID,
      channelName: channelName,
      messageID: messageID,
      messageChannelID: channelID,
      authorProfileID: authorProfileID,
      content: content,
      timestampMilliseconds: timestampMilliseconds,
      connectionState: status.state.rawValue,
      pendingMutationCount: pendingMutationCount
    )
  }

  private static func evidenceRow(
    _ details: InstantMobileChatV3LiveValidationDetails,
    appID: String,
    event: String
  ) -> ValidationEvidenceRow<InstantMobileChatV3LiveValidationDetails> {
    ValidationEvidenceRow(
      caseID: "validation.live.mobile-chat-v3",
      side: "swift",
      event: event,
      appID: appID,
      entityID: details.messageID,
      timestampMs: milliseconds(Date()),
      ok: true,
      details: details
    )
  }

  private static func matchingPresence(
    _ expected: MobileChatPresence,
    in stream: AsyncStream<[InstantRoomPresenceMember]>
  ) async throws -> (
    presence: MobileChatPresence,
    peerCount: Int
  ) {
    for await members in stream {
      for member in members {
        guard let value = try? decode(
          MobileChatPresence.self,
          from: .object(member.values)
        ) else { continue }
        if value == expected {
          return (value, members.count + 1)
        }
      }
    }
    throw failure(
      operation: "observe Mobile Chat V3 presence",
      message: "The room ended before the exact peer joined."
    )
  }

  private static func waitForNoPeers(
    in stream: AsyncStream<[InstantRoomPresenceMember]>
  ) async throws -> Int {
    try await withTimeout(operation: "observe Mobile Chat V3 peer cleanup") {
      for await members in stream where members.isEmpty { return 1 }
      throw failure(
        operation: "observe Mobile Chat V3 peer cleanup",
        message: "The presence stream ended before the peer departed."
      )
    }
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
    throw failure(
      operation: "observe Mobile Chat V3 topic",
      message: "The topic stream ended before the exact peer payload arrived."
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
        throw failure(operation: operation, message: "Timed out after 20 seconds.")
      }
      guard let value = try await group.next() else {
        throw failure(operation: operation, message: "No validation task completed.")
      }
      group.cancelAll()
      return value
    }
  }

  private static func encodeObject<Value: Encodable>(_ value: Value) throws
    -> [String: JSONValue]
  {
    guard case let .object(object) = try encode(value) else {
      throw failure(
        operation: "encode Mobile Chat V3 presence",
        message: "Presence did not encode as a JSON object."
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
      throw failure(
        operation: "encode Mobile Chat V3 JSON",
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

  private static func milliseconds(_ date: Date) -> Int64 {
    Int64((date.timeIntervalSince1970 * 1_000).rounded())
  }

  private static func failure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Keep Mobile Chat V3 exact across the Swift and canonical TypeScript SDKs."
    )
  }
}
