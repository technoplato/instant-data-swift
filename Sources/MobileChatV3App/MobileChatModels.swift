import AuthV3App
import Foundation
import InstantSwiftData

@InstantEntity("profiles")
public struct MobileChatProfile: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var displayName: String

  @InstantRelation(reverse: "profile")
  public var user: InstantID<AuthV3User>

  public var userID: InstantID<AuthV3User> { user }

  public static let displayName = InstantAttributePath<Self, String>("displayName")
  public static let user = InstantAttributePath<Self, InstantID<AuthV3User>>("user")
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: displayName.attributeID,
      namespace: instantNamespace,
      name: displayName.name,
      valueType: .string
    ),
    InstantAttribute(
      id: user.attributeID,
      namespace: instantNamespace,
      name: user.name,
      valueType: .ref,
      isRequired: false,
      isIndexed: true,
      isUnique: true,
      forwardIdentity: user.attributeID,
      reverseIdentity: AuthV3User.instantNamespace + "/profile",
      linkNamespace: AuthV3User.instantNamespace,
      onDelete: .cascade
    ),
  ]

  public init(id: InstantID<Self>, displayName: String, userID: InstantID<AuthV3User>) {
    self.id = id
    self.displayName = displayName
    self.user = userID
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(displayName) = snapshot.values["displayName"]?.first,
      case let .ref(userID) = snapshot.values["user"]?.first
    else {
      throw Self.decodeError(snapshot, expected: "displayName and userID")
    }
    id = InstantID(rawValue: snapshot.id)
    self.displayName = displayName
    self.user = InstantID(rawValue: userID)
  }
}

@InstantEntity("channels")
public struct MobileChatChannel: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>
  public var name: String

  public static let name = InstantAttributePath<Self, String>("name")
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: name.attributeID,
      namespace: instantNamespace,
      name: name.name,
      valueType: .string,
      isIndexed: true
    ),
  ]

  public init(id: InstantID<Self>, name: String) {
    self.id = id
    self.name = name
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(name) = snapshot.values["name"]?.first else {
      throw Self.decodeError(snapshot, expected: "name")
    }
    id = InstantID(rawValue: snapshot.id)
    self.name = name
  }
}

@InstantEntity("messages")
public struct MobileChatMessage: Hashable, Codable, InstantEntityModel {
  public var id: InstantID<Self>

  @InstantRelation(reverse: "messages", reverseMember: "channelMessages")
  public var channelID: InstantID<MobileChatChannel>

  @InstantRelation(reverse: "messages", reverseMember: "profileMessages")
  public var authorProfileID: InstantID<MobileChatProfile>?
  public var content: String
  public var timestampMilliseconds: Int64

  public static let channelID =
    InstantAttributePath<Self, InstantID<MobileChatChannel>>("channel")
  public static let authorProfileID =
    InstantAttributePath<Self, InstantID<MobileChatProfile>?>("author")
  public static let content = InstantAttributePath<Self, String>("content")
  public static let timestampMilliseconds = InstantAttributePath<Self, Int64>("timestamp")
  public static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: content.attributeID,
      namespace: instantNamespace,
      name: content.name,
      valueType: .string
    ),
    InstantAttribute(
      id: timestampMilliseconds.attributeID,
      namespace: instantNamespace,
      name: timestampMilliseconds.name,
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: authorProfileID.attributeID,
      namespace: instantNamespace,
      name: authorProfileID.name,
      valueType: .ref,
      isRequired: false,
      isIndexed: true,
      forwardIdentity: authorProfileID.attributeID,
      reverseIdentity: MobileChatProfile.instantNamespace + "/messages",
      linkNamespace: MobileChatProfile.instantNamespace,
      onDelete: .cascade
    ),
    InstantAttribute(
      id: channelID.attributeID,
      namespace: instantNamespace,
      name: channelID.name,
      valueType: .ref,
      isRequired: false,
      isIndexed: true,
      forwardIdentity: channelID.attributeID,
      reverseIdentity: MobileChatChannel.instantNamespace + "/messages",
      linkNamespace: MobileChatChannel.instantNamespace,
      onDelete: .cascade
    ),
  ]

  public init(
    id: InstantID<Self>,
    channelID: InstantID<MobileChatChannel>,
    authorProfileID: InstantID<MobileChatProfile>?,
    content: String,
    timestampMilliseconds: Int64
  ) {
    self.id = id
    self.channelID = channelID
    self.authorProfileID = authorProfileID
    self.content = content
    self.timestampMilliseconds = timestampMilliseconds
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .ref(channelID) = snapshot.values["channel"]?.first,
      case let .string(content) = snapshot.values["content"]?.first,
      case let .number(timestamp) = snapshot.values["timestamp"]?.first,
      timestamp.rounded() == timestamp
    else {
      throw Self.decodeError(snapshot, expected: "channelID, content, and integer timestamp")
    }
    let authorProfileID: InstantID<MobileChatProfile>?
    if case let .ref(authorID) = snapshot.values["author"]?.first {
      authorProfileID = InstantID(rawValue: authorID)
    } else {
      authorProfileID = nil
    }
    id = InstantID(rawValue: snapshot.id)
    self.channelID = InstantID(rawValue: channelID)
    self.authorProfileID = authorProfileID
    self.content = content
    self.timestampMilliseconds = Int64(timestamp)
  }
}

public struct MobileChatPresence: Codable, Equatable, Sendable {
  public var profileID: String
  public var displayName: String

  public init(profileID: String, displayName: String) {
    self.profileID = profileID
    self.displayName = displayName
  }

  private enum CodingKeys: String, CodingKey {
    case profileID = "profileId"
    case displayName
  }
}

public struct MobileChatTypingEvent: Codable, Equatable, Sendable {
  public var isTyping: Bool

  public init(isTyping: Bool) {
    self.isTyping = isTyping
  }
}

public enum MobileChatReactionName: String, Codable, CaseIterable, Sendable {
  case fire
  case wave
  case confetti
  case heart
}

public struct MobileChatReaction: Codable, Equatable, Sendable {
  public var name: MobileChatReactionName
  public var directionAngle: Double
  public var rotationAngle: Double

  public init(
    name: MobileChatReactionName,
    directionAngle: Double,
    rotationAngle: Double
  ) {
    self.name = name
    self.directionAngle = directionAngle
    self.rotationAngle = rotationAngle
  }
}

public struct MobileChatRoom: InstantRoomSchema {
  public typealias Presence = MobileChatPresence
  public static let roomType = "chat"

  public enum Topic: String, InstantRoomTopic {
    public typealias RoomSchema = MobileChatRoom
    case typing
    case emoji
  }
}

public struct MobileChatProfileCreated: Hashable, Sendable {
  public var id: InstantID<MobileChatProfile>
}

public struct CreateMobileChatProfile: InstantMessage {
  public var id: InstantID<MobileChatProfile>
  public var userID: InstantID<AuthV3User>
  public var displayName: String

  public init(
    id: InstantID<MobileChatProfile>,
    userID: InstantID<AuthV3User>,
    displayName: String
  ) {
    self.id = id
    self.userID = userID
    self.displayName = displayName
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<MobileChatProfileCreated>
  {
    _ = client
    return InstantPreparedMessage(change: MobileChatProfileCreated(id: id)) {
      MobileChatProfile.create(
        id: id,
        MobileChatProfile.displayName.set(displayName),
        MobileChatProfile.user.set(userID)
      )
    }
  }
}

public struct MobileChatChannelCreated: Hashable, Sendable {
  public var id: InstantID<MobileChatChannel>
}

public struct CreateMobileChatChannel: InstantMessage {
  public var id: InstantID<MobileChatChannel>
  public var name: String

  public init(id: InstantID<MobileChatChannel>, name: String) {
    self.id = id
    self.name = name
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<MobileChatChannelCreated>
  {
    _ = client
    return InstantPreparedMessage(change: MobileChatChannelCreated(id: id)) {
      MobileChatChannel.create(
        id: id,
        MobileChatChannel.name.set(name)
      )
    }
  }
}

public struct MobileChatMessageSent: Hashable, Sendable {
  public var id: InstantID<MobileChatMessage>
}

public struct SendMobileChatMessage: InstantMessage {
  public var id: InstantID<MobileChatMessage>
  public var channelID: InstantID<MobileChatChannel>
  public var authorProfileID: InstantID<MobileChatProfile>?
  public var content: String
  public var timestampMilliseconds: Int64

  public init(
    id: InstantID<MobileChatMessage>,
    channelID: InstantID<MobileChatChannel>,
    authorProfileID: InstantID<MobileChatProfile>?,
    content: String,
    timestampMilliseconds: Int64
  ) {
    self.id = id
    self.channelID = channelID
    self.authorProfileID = authorProfileID
    self.content = content
    self.timestampMilliseconds = timestampMilliseconds
  }

  public func prepare(using client: InstantSwiftDataClient) async throws
    -> InstantPreparedMessage<MobileChatMessageSent>
  {
    _ = client
    return InstantPreparedMessage(change: MobileChatMessageSent(id: id)) {
      MobileChatMessage.create(
        id: id,
        MobileChatMessage.channelID.set(channelID),
        MobileChatMessage.authorProfileID.set(authorProfileID),
        MobileChatMessage.content.set(content),
        MobileChatMessage.timestampMilliseconds.set(timestampMilliseconds)
      )
    }
  }
}

extension InstantEntityModel {
  fileprivate static func decodeError(
    _ snapshot: InstantEntitySnapshot,
    expected: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode Mobile Chat V3 entity",
      namespace: instantNamespace,
      localID: snapshot.id,
      message: "Expected \(expected).",
      recovery: "Keep the Mobile Chat V3 app model aligned with its generated schema."
    )
  }
}
