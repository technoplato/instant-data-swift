import Foundation

public struct InstantStoredFile: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var appID: String
  public var name: String
  public var contentType: String?
  public var byteCount: Int64
  public var localPath: String
  public var ownerUserID: String
  public var createdAt: InstantTimestamp
  public var updatedAt: InstantTimestamp

  public init(
    id: String,
    appID: String,
    name: String,
    contentType: String? = nil,
    byteCount: Int64,
    localPath: String,
    ownerUserID: String,
    createdAt: InstantTimestamp,
    updatedAt: InstantTimestamp
  ) {
    self.id = id
    self.appID = appID
    self.name = name
    self.contentType = contentType
    self.byteCount = byteCount
    self.localPath = localPath
    self.ownerUserID = ownerUserID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
