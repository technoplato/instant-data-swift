import Foundation

public enum InstantStorageOperationState: String, Hashable, Codable, Sendable {
  case idle
  case loading
  case success
  case error
}

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

public struct InstantFileUploadProgress: Hashable, Codable, Sendable, Identifiable {
  public var id: String { operationID }
  public var operationID: String
  public var appID: String
  public var fileID: String
  public var fileName: String
  public var contentType: String?
  public var state: InstantStorageOperationState
  public var completedByteCount: Int64
  public var totalByteCount: Int64
  public var progress: Double
  public var file: InstantStoredFile?
  public var errorMessage: String?
  public var updatedAt: InstantTimestamp

  public init(
    operationID: String,
    appID: String,
    fileID: String,
    fileName: String,
    contentType: String? = nil,
    state: InstantStorageOperationState,
    completedByteCount: Int64,
    totalByteCount: Int64,
    progress: Double,
    file: InstantStoredFile? = nil,
    errorMessage: String? = nil,
    updatedAt: InstantTimestamp
  ) {
    self.operationID = operationID
    self.appID = appID
    self.fileID = fileID
    self.fileName = fileName
    self.contentType = contentType
    self.state = state
    self.completedByteCount = completedByteCount
    self.totalByteCount = totalByteCount
    self.progress = progress
    self.file = file
    self.errorMessage = errorMessage
    self.updatedAt = updatedAt
  }
}
