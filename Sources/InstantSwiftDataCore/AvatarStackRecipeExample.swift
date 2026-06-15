import Foundation

public struct AvatarStackRecipeMember: Hashable, Codable, Sendable, Identifiable {
  public var id: String { userID }
  public var userID: String
  public var name: String
  public var isViewer: Bool
  public var updatedAt: InstantTimestamp

  public init(
    userID: String,
    name: String,
    isViewer: Bool,
    updatedAt: InstantTimestamp
  ) {
    self.userID = userID
    self.name = name
    self.isViewer = isViewer
    self.updatedAt = updatedAt
  }
}

public struct AvatarStackRecipeSnapshot: Hashable, Codable, Sendable {
  public var viewerUserID: String?
  public var onlineCount: Int
  public var currentUser: AvatarStackRecipeMember?
  public var peers: [AvatarStackRecipeMember]
  public var members: [AvatarStackRecipeMember]

  public init(
    viewerUserID: String?,
    onlineCount: Int,
    currentUser: AvatarStackRecipeMember?,
    peers: [AvatarStackRecipeMember],
    members: [AvatarStackRecipeMember]
  ) {
    self.viewerUserID = viewerUserID
    self.onlineCount = onlineCount
    self.currentUser = currentUser
    self.peers = peers
    self.members = members
  }
}

public enum AvatarStackRecipeExample {
  public static let room = InstantRoomHandle(
    type: "avatars-example",
    id: "avatars-example-1234"
  )
  public static let nameKey = "name"

  public static func defaultName(forUserID userID: String) -> String {
    String(userID.prefix(6))
  }

  public static func presenceValues(name: String) -> [String: JSONValue] {
    [nameKey: .string(name)]
  }

  public static func member(
    from presence: InstantRoomPresenceMember,
    viewerUserID: String? = nil
  ) -> AvatarStackRecipeMember? {
    guard presence.room == room,
      case let .string(name)? = presence.values[nameKey]
    else {
      return nil
    }

    return AvatarStackRecipeMember(
      userID: presence.userID,
      name: name,
      isViewer: presence.userID == viewerUserID,
      updatedAt: presence.updatedAt
    )
  }

  public static func members(
    from presence: [InstantRoomPresenceMember],
    viewerUserID: String? = nil
  ) -> [AvatarStackRecipeMember] {
    presence.compactMap { member(from: $0, viewerUserID: viewerUserID) }
  }

  public static func snapshot(
    from presence: [InstantRoomPresenceMember],
    viewerUserID: String? = nil
  ) -> AvatarStackRecipeSnapshot {
    let members = members(from: presence, viewerUserID: viewerUserID)
    let currentUser = members.first { $0.isViewer }
    let peers = members.filter { member in
      guard let currentUser else {
        return true
      }
      return member.userID != currentUser.userID
    }
    return AvatarStackRecipeSnapshot(
      viewerUserID: viewerUserID,
      onlineCount: currentUser == nil ? members.count : peers.count + 1,
      currentUser: currentUser,
      peers: peers,
      members: members
    )
  }
}
