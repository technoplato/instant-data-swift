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

public struct InstantStreamMetadata: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var appID: String
  public var clientID: String
  public var done: Bool
  public var size: Int64?
  public var abortReason: String?
  public var userID: String
  public var createdAt: InstantTimestamp
  public var updatedAt: InstantTimestamp

  public init(
    id: String,
    appID: String,
    clientID: String,
    done: Bool = false,
    size: Int64? = nil,
    abortReason: String? = nil,
    userID: String,
    createdAt: InstantTimestamp,
    updatedAt: InstantTimestamp
  ) {
    self.id = id
    self.appID = appID
    self.clientID = clientID
    self.done = done
    self.size = size
    self.abortReason = abortReason
    self.userID = userID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

public struct InstantStreamContentChunk: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var appID: String
  public var streamID: String
  public var offset: Int64
  public var byteCount: Int64
  public var content: String
  public var userID: String
  public var createdAt: InstantTimestamp

  public init(
    id: String,
    appID: String,
    streamID: String,
    offset: Int64,
    byteCount: Int64,
    content: String,
    userID: String,
    createdAt: InstantTimestamp
  ) {
    self.id = id
    self.appID = appID
    self.streamID = streamID
    self.offset = offset
    self.byteCount = byteCount
    self.content = content
    self.userID = userID
    self.createdAt = createdAt
  }
}

public struct InstantStreamContentAppend: Hashable, Codable, Sendable {
  public var metadata: InstantStreamMetadata
  public var chunk: InstantStreamContentChunk
  public var offset: Int64

  public init(
    metadata: InstantStreamMetadata,
    chunk: InstantStreamContentChunk,
    offset: Int64
  ) {
    self.metadata = metadata
    self.chunk = chunk
    self.offset = offset
  }
}

public struct InstantStreamContentRead: Hashable, Codable, Sendable {
  public var metadata: InstantStreamMetadata
  public var byteOffset: Int64
  public var byteCount: Int64
  public var content: String
  public var done: Bool
  public var abortReason: String?

  public init(
    metadata: InstantStreamMetadata,
    byteOffset: Int64,
    byteCount: Int64,
    content: String,
    done: Bool,
    abortReason: String? = nil
  ) {
    self.metadata = metadata
    self.byteOffset = byteOffset
    self.byteCount = byteCount
    self.content = content
    self.done = done
    self.abortReason = abortReason
  }
}
