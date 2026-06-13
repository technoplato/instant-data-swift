import Foundation

public struct InstantStreamChunk: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var appID: String
  public var streamID: String
  public var index: Int64
  public var payload: JSONValue
  public var userID: String
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    appID: String,
    streamID: String,
    index: Int64,
    payload: JSONValue,
    userID: String,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.appID = appID
    self.streamID = streamID
    self.index = index
    self.payload = payload
    self.userID = userID
    self.createdAt = createdAt
  }
}
