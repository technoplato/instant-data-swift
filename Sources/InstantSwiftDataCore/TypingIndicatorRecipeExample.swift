import Foundation

public struct TypingIndicatorRecipeMember: Hashable, Codable, Sendable, Identifiable {
  public var id: String { userID }
  public var userID: String
  public var presenceID: String?
  public var isTyping: Bool
  public var updatedAt: InstantTimestamp

  public init(
    userID: String,
    presenceID: String?,
    isTyping: Bool,
    updatedAt: InstantTimestamp
  ) {
    self.userID = userID
    self.presenceID = presenceID
    self.isTyping = isTyping
    self.updatedAt = updatedAt
  }
}

public enum TypingIndicatorRecipeExample {
  public static let room = InstantRoomHandle(
    type: "typing-indicator-example",
    id: "1234"
  )
  public static let inputName = "chat-input"
  public static let idKey = "id"

  public static func presenceValues(
    presenceID: String,
    isTyping: Bool
  ) -> [String: JSONValue] {
    [
      idKey: .string(presenceID),
      inputName: .bool(isTyping),
    ]
  }

  public static func member(
    from presence: InstantRoomPresenceMember
  ) -> TypingIndicatorRecipeMember? {
    guard presence.room == room else {
      return nil
    }

    let presenceID: String?
    if case let .string(value)? = presence.values[idKey] {
      presenceID = value
    } else {
      presenceID = nil
    }

    let isTyping: Bool
    switch presence.values[inputName] {
    case .bool(true)?:
      isTyping = true
    default:
      isTyping = false
    }

    return TypingIndicatorRecipeMember(
      userID: presence.userID,
      presenceID: presenceID,
      isTyping: isTyping,
      updatedAt: presence.updatedAt
    )
  }

  public static func members(
    from presence: [InstantRoomPresenceMember]
  ) -> [TypingIndicatorRecipeMember] {
    presence.compactMap(member(from:))
  }

  public static func activeMembers(
    from presence: [InstantRoomPresenceMember],
    excludingUserID: String? = nil
  ) -> [TypingIndicatorRecipeMember] {
    members(from: presence)
      .filter(\.isTyping)
      .filter { member in
        guard let excludingUserID else {
          return true
        }
        return member.userID != excludingUserID
      }
  }

  public static func typingInfo(activeCount: Int) -> String? {
    switch activeCount {
    case 0:
      return nil
    case 1:
      return "1 person is typing..."
    default:
      return "\(activeCount) people are typing..."
    }
  }
}
