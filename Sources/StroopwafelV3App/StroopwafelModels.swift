import Foundation
import InstantSwiftData

public struct StroopwafelV3StringList:
  Codable, Equatable, ExpressibleByArrayLiteral, Hashable, InstantJSONWireValue, Sendable
{
  public var values: [String]

  public init(_ values: [String]) {
    self.values = values
  }

  public init(arrayLiteral elements: String...) {
    self.init(elements)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    values = try container.decode([String].self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(values)
  }

  public var instantValue: InstantValue {
    .json(.array(values.map(JSONValue.string)))
  }

  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .json(.array(rawValues)) = value else {
      throw stroopwafelDecodeError(
        value,
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation,
        expected: "a JSON string array"
      )
    }
    let values = try rawValues.map { value in
      guard case let .string(value) = value else {
        throw stroopwafelDecodeError(
          .json(.array(rawValues)),
          namespace: namespace,
          path: path,
          localID: localID,
          operation: operation,
          expected: "a JSON string array"
        )
      }
      return value
    }
    return Self(values)
  }
}

public struct StroopwafelV3ColorPrompt: Codable, Equatable, Hashable, Sendable {
  public var color: String
  public var label: String

  public init(color: String, label: String) {
    self.color = color
    self.label = label
  }
}

public struct StroopwafelV3ColorSequence:
  Codable, Equatable, ExpressibleByArrayLiteral, Hashable, InstantJSONWireValue, Sendable
{
  public var values: [StroopwafelV3ColorPrompt]

  public init(_ values: [StroopwafelV3ColorPrompt]) {
    self.values = values
  }

  public init(arrayLiteral elements: StroopwafelV3ColorPrompt...) {
    self.init(elements)
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    values = try container.decode([StroopwafelV3ColorPrompt].self)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(values)
  }

  public var instantValue: InstantValue {
    .json(
      .array(
        values.map { prompt in
          .object(["color": .string(prompt.color), "label": .string(prompt.label)])
        }
      )
    )
  }

  public static func decodeInstantValue(
    _ value: InstantValue?,
    namespace: String,
    path: String,
    localID: String?,
    operation: String
  ) throws -> Self {
    guard case let .json(.array(rawValues)) = value else {
      throw stroopwafelDecodeError(
        value,
        namespace: namespace,
        path: path,
        localID: localID,
        operation: operation,
        expected: "a JSON color-prompt array"
      )
    }
    let prompts = try rawValues.map { value in
      guard case let .object(object) = value,
        case let .string(color) = object["color"],
        case let .string(label) = object["label"]
      else {
        throw stroopwafelDecodeError(
          .json(.array(rawValues)),
          namespace: namespace,
          path: path,
          localID: localID,
          operation: operation,
          expected: "a JSON color-prompt array"
        )
      }
      return StroopwafelV3ColorPrompt(color: color, label: label)
    }
    return Self(prompts)
  }
}

@InstantEntity("$users")
public struct StroopwafelV3User: Codable, Equatable, Hashable, InstantEntityModel {
  public static let email = InstantAttributePath<Self, String?>("email")
  public static let handle = InstantAttributePath<Self, String?>("handle")
  public static let highScore = InstantAttributePath<Self, Int?>("highScore")
  public static let createdAt = InstantAttributePath<Self, String?>("created_at")
  public static let instantAttributes = StroopwafelExample.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var email: String?
  public var handle: String?
  public var highScore: Int?
  public var createdAt: String?

  public init(
    id: InstantID<Self>,
    email: String? = nil,
    handle: String? = nil,
    highScore: Int? = nil,
    createdAt: String? = nil
  ) {
    self.id = id
    self.email = email
    self.handle = handle
    self.highScore = highScore
    self.createdAt = createdAt
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    email = snapshot.optionalString("email")
    handle = snapshot.optionalString("handle")
    highScore = try snapshot.optionalInteger("highScore", operation: "decode Stroopwafel user")
    createdAt = snapshot.optionalString("created_at")
  }
}

@InstantEntity("rooms")
public struct StroopwafelV3Room: Codable, Equatable, Hashable, InstantEntityModel {
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let code = InstantAttributePath<Self, String?>("code")
  public static let hostID = InstantAttributePath<Self, String>("hostId")
  public static let readyIDs = InstantAttributePath<Self, StroopwafelV3StringList>("readyIds")
  public static let kickedIDs = InstantAttributePath<Self, StroopwafelV3StringList>("kickedIds")
  public static let currentGameID = InstantAttributePath<Self, String?>("currentGameId")
  public static let createdAt = InstantAttributePath<Self, String>("created_at")
  public static let deletedAt = InstantAttributePath<Self, String?>("deleted_at")
  public static let users = InstantAttributePath<Self, InstantID<StroopwafelV3User>>("users")
  public static let instantAttributes = StroopwafelExample.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var code: String?
  public var hostID: String
  @InstantWire(.json)
  public var readyIDs: StroopwafelV3StringList

  @InstantWire(.json)
  public var kickedIDs: StroopwafelV3StringList
  public var currentGameID: String?
  public var createdAt: String
  public var deletedAt: String?
  public var users: [StroopwafelV3User]

  public init(
    id: InstantID<Self>,
    code: String?,
    hostID: String,
    readyIDs: StroopwafelV3StringList,
    kickedIDs: StroopwafelV3StringList,
    currentGameID: String? = nil,
    createdAt: String,
    deletedAt: String? = nil,
    users: [StroopwafelV3User] = []
  ) {
    self.id = id
    self.code = code
    self.hostID = hostID
    self.readyIDs = readyIDs
    self.kickedIDs = kickedIDs
    self.currentGameID = currentGameID
    self.createdAt = createdAt
    self.deletedAt = deletedAt
    self.users = users
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(hostID) = snapshot.values["hostId"]?.first,
      case let .string(createdAt) = snapshot.values["created_at"]?.first
    else {
      throw stroopwafelDecodeError(
        nil,
        namespace: Self.instantNamespace,
        path: nil,
        localID: snapshot.id,
        operation: "decode Stroopwafel room",
        expected: "hostId and created_at strings"
      )
    }
    id = InstantID(rawValue: snapshot.id)
    code = snapshot.optionalString("code")
    self.hostID = hostID
    readyIDs = try .decodeInstantValue(
      snapshot.values["readyIds"]?.first,
      namespace: Self.instantNamespace,
      path: "readyIds",
      localID: snapshot.id,
      operation: "decode Stroopwafel room"
    )
    kickedIDs = try .decodeInstantValue(
      snapshot.values["kickedIds"]?.first,
      namespace: Self.instantNamespace,
      path: "kickedIds",
      localID: snapshot.id,
      operation: "decode Stroopwafel room"
    )
    currentGameID = snapshot.optionalString("currentGameId")
    self.createdAt = createdAt
    deletedAt = snapshot.optionalString("deleted_at")
    users = try snapshot.linked("users").map(StroopwafelV3User.init(linkedSnapshot:))
  }

  public static func forCode(_ value: String) -> InstantQuery<Self> {
    query.where(code == Optional(value)).include(users)
  }

  public var coreRecord: StroopwafelRoomRecord {
    StroopwafelRoomRecord(
      id: id.rawValue,
      code: code,
      hostID: hostID,
      readyIDs: readyIDs.values,
      kickedIDs: kickedIDs.values,
      currentGameID: currentGameID,
      createdAt: createdAt,
      deletedAt: deletedAt,
      users: users.map(\.coreRecord)
    )
  }
}

@InstantEntity("points")
public struct StroopwafelV3Point: Codable, Equatable, Hashable, InstantEntityModel {
  public static let value = InstantAttributePath<Self, Int>("val")
  public static let userID = InstantAttributePath<Self, String>("userId")
  public static let instantAttributes = StroopwafelExample.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var value: Int
  public var userID: String

  public init(id: InstantID<Self>, value: Int, userID: String) {
    self.id = id
    self.value = value
    self.userID = userID
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .number(value) = snapshot.values["val"]?.first,
      value.rounded() == value,
      case let .string(userID) = snapshot.values["userId"]?.first
    else {
      throw stroopwafelDecodeError(
        nil,
        namespace: Self.instantNamespace,
        path: nil,
        localID: snapshot.id,
        operation: "decode Stroopwafel point",
        expected: "an integer val and string userId"
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.value = Int(value)
    self.userID = userID
  }

  public var coreRecord: StroopwafelPointRecord {
    StroopwafelPointRecord(id: id.rawValue, value: value, userID: userID)
  }
}

@InstantEntity("games")
public struct StroopwafelV3Game: Codable, Equatable, Hashable, InstantEntityModel {
  public static let identifier = InstantAttributePath<Self, String>("id")
  public static let status = InstantAttributePath<Self, String>("status")
  public static let playerIDs = InstantAttributePath<Self, StroopwafelV3StringList>("playerIds")
  public static let colors = InstantAttributePath<Self, StroopwafelV3ColorSequence>("colors")
  public static let createdAt = InstantAttributePath<Self, String>("created_at")
  public static let users = InstantAttributePath<Self, InstantID<StroopwafelV3User>>("users")
  public static let rooms = InstantAttributePath<Self, InstantID<StroopwafelV3Room>>("rooms")
  public static let points = InstantAttributePath<Self, InstantID<StroopwafelV3Point>>("points")
  public static let instantAttributes = StroopwafelExample.attributes.filter {
    $0.namespace == instantNamespace
  }

  public var id: InstantID<Self>
  public var status: String
  @InstantWire(.json)
  public var playerIDs: StroopwafelV3StringList

  @InstantWire(.json)
  public var colors: StroopwafelV3ColorSequence
  public var createdAt: String
  public var users: [StroopwafelV3User]
  public var rooms: [StroopwafelV3Room]
  public var points: [StroopwafelV3Point]

  public init(
    id: InstantID<Self>,
    status: String,
    playerIDs: StroopwafelV3StringList,
    colors: StroopwafelV3ColorSequence,
    createdAt: String,
    users: [StroopwafelV3User] = [],
    rooms: [StroopwafelV3Room] = [],
    points: [StroopwafelV3Point] = []
  ) {
    self.id = id
    self.status = status
    self.playerIDs = playerIDs
    self.colors = colors
    self.createdAt = createdAt
    self.users = users
    self.rooms = rooms
    self.points = points
  }

  public init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(status) = snapshot.values["status"]?.first,
      case let .string(createdAt) = snapshot.values["created_at"]?.first
    else {
      throw stroopwafelDecodeError(
        nil,
        namespace: Self.instantNamespace,
        path: nil,
        localID: snapshot.id,
        operation: "decode Stroopwafel game",
        expected: "status and created_at strings"
      )
    }
    id = InstantID(rawValue: snapshot.id)
    self.status = status
    playerIDs = try .decodeInstantValue(
      snapshot.values["playerIds"]?.first,
      namespace: Self.instantNamespace,
      path: "playerIds",
      localID: snapshot.id,
      operation: "decode Stroopwafel game"
    )
    colors = try .decodeInstantValue(
      snapshot.values["colors"]?.first,
      namespace: Self.instantNamespace,
      path: "colors",
      localID: snapshot.id,
      operation: "decode Stroopwafel game"
    )
    self.createdAt = createdAt
    users = try snapshot.linked("users").map(StroopwafelV3User.init(linkedSnapshot:))
    rooms = try snapshot.linked("rooms").map(StroopwafelV3Room.init(linkedSnapshot:))
    points = try snapshot.linked("points").map(StroopwafelV3Point.init(linkedSnapshot:))
  }

  public static func byID(_ id: InstantID<Self>) -> InstantQuery<Self> {
    query
      .where(identifier == id.rawValue)
      .include(users)
      .include(rooms, StroopwafelV3Room.query.include(StroopwafelV3Room.users))
      .include(points)
  }

  public var coreRecord: StroopwafelGameRecord {
    StroopwafelGameRecord(
      id: id.rawValue,
      status: status,
      playerIDs: playerIDs.values,
      colors: colors.values.map { .init(color: $0.color, label: $0.label) },
      createdAt: createdAt,
      users: users.map(\.coreRecord),
      rooms: rooms.map(\.coreRecord),
      points: points.map(\.coreRecord)
    )
  }
}

public enum StroopwafelV3Schema {
  public static let attributes = StroopwafelExample.attributes
}

extension StroopwafelV3User {
  fileprivate init(linkedSnapshot: InstantLinkedEntitySnapshot) throws {
    try self.init(snapshot: InstantEntitySnapshot(linkedSnapshot))
  }

  fileprivate var coreRecord: StroopwafelUserRecord {
    StroopwafelUserRecord(
      id: id.rawValue,
      email: email,
      handle: handle,
      highScore: highScore,
      createdAt: createdAt
    )
  }
}

extension StroopwafelV3Room {
  fileprivate init(linkedSnapshot: InstantLinkedEntitySnapshot) throws {
    try self.init(snapshot: InstantEntitySnapshot(linkedSnapshot))
  }
}

extension StroopwafelV3Point {
  fileprivate init(linkedSnapshot: InstantLinkedEntitySnapshot) throws {
    try self.init(snapshot: InstantEntitySnapshot(linkedSnapshot))
  }
}

extension InstantEntitySnapshot {
  fileprivate init(_ linked: InstantLinkedEntitySnapshot) {
    self.init(
      id: linked.id,
      namespace: linked.namespace,
      values: linked.values,
      links: linked.links
    )
  }

  fileprivate func optionalString(_ path: String) -> String? {
    guard case let .string(value) = values[path]?.first else { return nil }
    return value
  }

  fileprivate func optionalInteger(_ path: String, operation: String) throws -> Int? {
    guard let value = values[path]?.first, value != .null else { return nil }
    guard case let .number(number) = value, number.rounded() == number else {
      throw stroopwafelDecodeError(
        value,
        namespace: namespace,
        path: path,
        localID: id,
        operation: operation,
        expected: "an integer or null"
      )
    }
    return Int(number)
  }

  fileprivate func linked(_ name: String) -> [InstantLinkedEntitySnapshot] {
    links?[name] ?? []
  }
}

private func stroopwafelDecodeError(
  _ value: InstantValue?,
  namespace: String,
  path: String?,
  localID: String?,
  operation: String,
  expected: String
) -> InstantError {
  InstantError(
    code: .decodeFailed,
    operation: operation,
    namespace: namespace,
    path: path,
    localID: localID,
    message: "Expected \(expected), received \(String(describing: value)).",
    recovery: "Keep the Stroopwafel V3 model aligned with the pinned canonical schema."
  )
}
