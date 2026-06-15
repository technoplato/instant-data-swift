import Foundation

public struct ReactionsRecipePayload: Hashable, Codable, Sendable {
  public var name: String
  public var directionAngle: Double
  public var rotationAngle: Double

  public init(
    name: String,
    directionAngle: Double,
    rotationAngle: Double
  ) {
    self.name = name
    self.directionAngle = directionAngle
    self.rotationAngle = rotationAngle
  }
}

public struct ReactionsRecipeReaction: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var symbol: String
  public var directionAngle: Double
  public var rotationAngle: Double
  public var userID: String
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    name: String,
    symbol: String,
    directionAngle: Double,
    rotationAngle: Double,
    userID: String,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.name = name
    self.symbol = symbol
    self.directionAngle = directionAngle
    self.rotationAngle = rotationAngle
    self.userID = userID
    self.createdAt = createdAt
  }
}

public enum ReactionsRecipeExample {
  public static let room = InstantRoomHandle(type: "topics-example", id: "123")
  public static let topic = "emoji"
  public static let reactionNames = ["fire", "wave", "confetti", "heart"]

  public static func containsReactionName(_ name: String) -> Bool {
    reactionNames.contains(name)
  }

  public static func symbol(forReactionName name: String) -> String? {
    switch name {
    case "fire":
      return "\u{1F525}"
    case "wave":
      return "\u{1F44B}"
    case "confetti":
      return "\u{1F389}"
    case "heart":
      return "\u{2764}\u{FE0F}"
    default:
      return nil
    }
  }

  public static func payload(
    name: String,
    directionAngle: Double,
    rotationAngle: Double
  ) -> JSONValue {
    payload(
      ReactionsRecipePayload(
        name: name,
        directionAngle: directionAngle,
        rotationAngle: rotationAngle
      )
    )
  }

  public static func payload(_ payload: ReactionsRecipePayload) -> JSONValue {
    .object([
      "directionAngle": .number(payload.directionAngle),
      "name": .string(payload.name),
      "rotationAngle": .number(payload.rotationAngle),
    ])
  }

  public static func recipePayload(from value: JSONValue) -> ReactionsRecipePayload? {
    guard case let .object(payload) = value,
      case let .string(name)? = payload["name"],
      containsReactionName(name),
      case let .number(directionAngle)? = payload["directionAngle"],
      directionAngle.isFinite,
      case let .number(rotationAngle)? = payload["rotationAngle"],
      rotationAngle.isFinite
    else {
      return nil
    }
    return ReactionsRecipePayload(
      name: name,
      directionAngle: directionAngle,
      rotationAngle: rotationAngle
    )
  }

  public static func reaction(
    from message: InstantRoomTopicMessage
  ) -> ReactionsRecipeReaction? {
    guard message.room == room,
      message.topic == topic,
      let payload = recipePayload(from: message.payload),
      let symbol = symbol(forReactionName: payload.name)
    else {
      return nil
    }
    return ReactionsRecipeReaction(
      id: message.id,
      name: payload.name,
      symbol: symbol,
      directionAngle: payload.directionAngle,
      rotationAngle: payload.rotationAngle,
      userID: message.userID,
      createdAt: message.createdAt
    )
  }

  public static func reactions(
    from messages: [InstantRoomTopicMessage]
  ) -> [ReactionsRecipeReaction] {
    messages.compactMap(reaction(from:))
  }
}
