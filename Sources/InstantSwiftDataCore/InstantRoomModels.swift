import Foundation

public struct InstantRoomHandle: Hashable, Codable, Sendable {
  public var type: String
  public var id: String

  public init(type: String, id: String) {
    self.type = type
    self.id = id
  }
}

public struct InstantRoomPresenceMember: Hashable, Codable, Sendable, Identifiable {
  public var id: String { "\(appID):\(room.type):\(room.id):\(userID)" }
  public var appID: String
  public var room: InstantRoomHandle
  public var userID: String
  public var values: [String: JSONValue]
  public var updatedAt: InstantTimestamp

  public init(
    appID: String,
    room: InstantRoomHandle,
    userID: String,
    values: [String: JSONValue],
    updatedAt: InstantTimestamp
  ) {
    self.appID = appID
    self.room = room
    self.userID = userID
    self.values = values
    self.updatedAt = updatedAt
  }
}

public struct InstantRoomTopicMessage: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var appID: String
  public var room: InstantRoomHandle
  public var topic: String
  public var userID: String
  public var payload: JSONValue
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    appID: String,
    room: InstantRoomHandle,
    topic: String,
    userID: String,
    payload: JSONValue,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.appID = appID
    self.room = room
    self.topic = topic
    self.userID = userID
    self.payload = payload
    self.createdAt = createdAt
  }
}
