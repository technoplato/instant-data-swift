import Foundation

public enum InstantStorageOperationState: String, Hashable, Codable, Sendable {
  case idle
  case loading
  case success
  case error
}

public struct InstantStorageSnapshot: Hashable, Codable, Sendable {
  public var localCacheSize: Int64
  public var streamCacheSize: Int64
  public var downloadedFileSize: Int64
  public var downloadedFileCount: Int

  public init(
    localCacheSize: Int64,
    streamCacheSize: Int64,
    downloadedFileSize: Int64,
    downloadedFileCount: Int
  ) {
    self.localCacheSize = localCacheSize
    self.streamCacheSize = streamCacheSize
    self.downloadedFileSize = downloadedFileSize
    self.downloadedFileCount = downloadedFileCount
  }

  public static let empty = Self(
    localCacheSize: 0,
    streamCacheSize: 0,
    downloadedFileSize: 0,
    downloadedFileCount: 0
  )
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
  public var remoteURL: URL?

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
    self.init(
      id: id,
      appID: appID,
      name: name,
      contentType: contentType,
      byteCount: byteCount,
      localPath: localPath,
      ownerUserID: ownerUserID,
      createdAt: createdAt,
      updatedAt: updatedAt,
      remoteURL: nil
    )
  }

  public init(
    id: String,
    appID: String,
    name: String,
    contentType: String? = nil,
    byteCount: Int64,
    localPath: String,
    ownerUserID: String,
    createdAt: InstantTimestamp,
    updatedAt: InstantTimestamp,
    remoteURL: URL?
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
    self.remoteURL = remoteURL
  }

  public var isDownloaded: Bool { !localPath.isEmpty }

  /// The library's own copy of the file, if it still has one. A record of an upload another session ran has no
  /// `localPath` (#491), and the system may have purged a cached copy: then a read downloads from storage.
  var heldCopyURL: URL? {
    guard !localPath.isEmpty, FileManager.default.fileExists(atPath: localPath) else { return nil }
    return URL(fileURLWithPath: localPath)
  }
}

/// A storage upload the library prepared and did not send (#491): the request for an app to run on its own
/// `URLSession`, a background one included, which the system can finish while the app is suspended or relaunched.
///
/// ```swift
/// let upload = try await db.prepareFileUpload(from: audioURL, name: "recordings/\(id)/audio.wav")
/// backgroundSession.uploadTask(with: upload.request, fromFile: audioURL).resume()
/// ```
///
/// When the task finishes, ``InstantRuntime/completeFileUpload(path:statusCode:responseBody:sourceURL:contentType:)``
/// records the file from `path` and storage's answer, in this process or a later one.
public struct InstantPreparedFileUpload: Hashable, Sendable {
  /// The authenticated `PUT` to Instant storage, the request the live transport sends for `uploadFile`. Run it with
  /// `URLSession.uploadTask(with:fromFile:)` and `sourceURL`. It carries the refresh token current when it was
  /// prepared, so prepare it just before the upload starts.
  public var request: URLRequest
  /// The storage path the file uploads to, which completing the upload takes.
  public var path: String
  /// The file's size when the upload was prepared: the request's `Content-Length`.
  public var byteCount: Int64
  public var contentType: String?
  /// The file the request sends. The library never reads or copies it.
  public var sourceURL: URL

  public init(request: URLRequest, path: String, byteCount: Int64, contentType: String?, sourceURL: URL) {
    self.request = request
    self.path = path
    self.byteCount = byteCount
    self.contentType = contentType
    self.sourceURL = sourceURL
  }
}

public struct InstantStoredFileContents: Hashable, Codable, Sendable {
  public var file: InstantStoredFile
  public var byteCount: Int64
  public var data: Data

  public init(file: InstantStoredFile, data: Data) {
    self.file = file
    self.byteCount = Int64(data.count)
    self.data = data
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
