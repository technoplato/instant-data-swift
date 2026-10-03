import Foundation

public struct InstantRoomHandle: Hashable, Codable, Sendable {
  public static let defaultType = "_defaultRoomType"
  public static let defaultID = "_defaultRoomId"
  public static let `default` = Self()

  public var type: String
  public var id: String

  public init(
    type: String = Self.defaultType,
    id: String = Self.defaultID
  ) {
    self.type = type
    self.id = id
  }
}

/// One member of a room's presence: a peer's session, or presence this runtime published.
///
/// Peers are keyed by session, as `Reactor.js` keys them (`_setPresencePeers`; `peerId` in presence.ts), so two
/// agents or devices signed in as one user are two members, and a session of this runtime's own user is a peer, not
/// this runtime.
public struct InstantRoomPresenceMember: Hashable, Codable, Sendable, Identifiable {
  /// Unique within a room: a peer's session id, or for this runtime's own presence the user id it published under.
  public var id: String {
    if let peerID {
      return "\(appID):\(room.type):\(room.id):peer:\(peerID)"
    }
    return "\(appID):\(room.type):\(room.id):\(userID)"
  }
  public var appID: String
  public var room: InstantRoomHandle
  /// The signed-in user of the session that published the values. A session without a user (an admin-token client)
  /// reports its peer id here, as the server's envelope has no user.
  public var userID: String
  /// The server's session id of the peer that published the values, `Reactor.js`'s `peerId`; `nil` for presence this
  /// runtime published.
  public var peerID: String?
  public var values: [String: JSONValue]
  /// When these values last changed, as this runtime saw them: a peer's is when its frame arrived with new values.
  public var updatedAt: InstantTimestamp

  /// Presence this runtime publishes is built with `peerID` nil; the runtime fills a peer's from the server.
  public init(
    appID: String,
    room: InstantRoomHandle,
    userID: String,
    peerID: String? = nil,
    values: [String: JSONValue],
    updatedAt: InstantTimestamp
  ) {
    self.appID = appID
    self.room = room
    self.userID = userID
    self.peerID = peerID
    self.values = values
    self.updatedAt = updatedAt
  }

  /// Whether this runtime published these values, rather than a peer's session.
  public var isLocal: Bool { peerID == nil }
}

extension InstantRoomPresenceMember {
  /// The order presence lists use: by user id; within one user, this runtime's own presence first, then each peer
  /// by session id. Stable across frames, so an observer's rows keep their places.
  static func presenceOrder(_ lhs: Self, _ rhs: Self) -> Bool {
    if lhs.userID != rhs.userID { return lhs.userID < rhs.userID }
    switch (lhs.peerID, rhs.peerID) {
    case (nil, nil): return false
    case (nil, _): return true
    case (_, nil): return false
    case let (left?, right?): return left < right
    }
  }
}

/// Which part of a room's presence an observation sees, as the options of `Reactor.js`'s `subscribePresence`
/// (`keys`, `peers`, `user`; presence.ts `buildPresenceSlice`). An observation emits only when its part changed.
///
/// ```swift
/// let agents = try await runtime.observeRoomPresence(
///   room: room,
///   selection: InstantRoomPresenceSelection(keys: ["agents"], includesLocal: false)
/// )
/// ```
public struct InstantRoomPresenceSelection: Hashable, Sendable {
  /// Only these keys of each member's values, `nil` for every key.
  public var keys: Set<String>?
  /// Only these peers, by session id, `nil` for every peer.
  public var peerIDs: Set<String>?
  /// Whether the presence this runtime published is included.
  public var includesLocal: Bool

  public init(keys: Set<String>? = nil, peerIDs: Set<String>? = nil, includesLocal: Bool = true) {
    self.keys = keys
    self.peerIDs = peerIDs
    self.includesLocal = includesLocal
  }

  /// Every member with every key.
  public static let all = Self()

  /// The selected part of `members`, in their order.
  public func apply(to members: [InstantRoomPresenceMember]) -> [InstantRoomPresenceMember] {
    members.compactMap { member in
      if member.isLocal {
        guard includesLocal else { return nil }
      } else if let peerIDs, let peerID = member.peerID, !peerIDs.contains(peerID) {
        return nil
      }
      guard let keys else { return member }
      var selected = member
      selected.values = member.values.filter { keys.contains($0.key) }
      return selected
    }
  }

  /// Whether two selected parts differ for an observer. With `keys`, a member's `updatedAt` moves when any of its
  /// values change, so it is left out: only the selected values count, as `hasPresenceResponseChanged` compares them.
  func changed(from old: [InstantRoomPresenceMember], to new: [InstantRoomPresenceMember]) -> Bool {
    guard keys != nil else { return old != new }
    guard old.count == new.count else { return true }
    return zip(old, new).contains { lhs, rhs in
      lhs.id != rhs.id || lhs.userID != rhs.userID || lhs.peerID != rhs.peerID || lhs.values != rhs.values
    }
  }
}

/// One message on a room topic: published by this runtime, or broadcast by a peer's session.
public struct InstantRoomTopicMessage: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var appID: String
  public var room: InstantRoomHandle
  public var topic: String
  public var userID: String
  /// The server's session id of the peer that broadcast the message, as `Reactor.js` hands each topic subscriber the
  /// sender's peer; `nil` for a message this runtime published.
  public var peerID: String?
  public var payload: JSONValue
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    appID: String,
    room: InstantRoomHandle,
    topic: String,
    userID: String,
    peerID: String? = nil,
    payload: JSONValue,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.appID = appID
    self.room = room
    self.topic = topic
    self.userID = userID
    self.peerID = peerID
    self.payload = payload
    self.createdAt = createdAt
  }

  /// Whether this runtime published the message, rather than a peer's session.
  public var isLocal: Bool { peerID == nil }
}
