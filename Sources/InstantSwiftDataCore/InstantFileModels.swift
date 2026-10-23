import Foundation

#if canImport(Darwin)
  import Darwin
#endif

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

/// What ``InstantRuntime/evictStoredFiles(ids:)`` did with this device's copy of one stored file (#959).
public struct InstantStoredFileEviction: Hashable, Sendable {
  /// Why a copy stays.
  public enum Kept: Hashable, Sendable {
    /// This device holds no copy: there is no record of the file, or its record has none.
    case notHeld
    /// The client has no storage, so the copy is the only one.
    case noStorage
    /// Storage has no record of a file with this id.
    case notOnServer
    /// Storage's record of the file has another size than the copy.
    case sizeDiffers(serverByteCount: Int64)
  }

  public enum Outcome: Hashable, Sendable {
    /// The copy is gone and the record stays, not downloaded. `freedByteCount` is what the volume got back: the
    /// blocks only this copy held, which is next to nothing for an APFS clone of a file the app still keeps; nil
    /// where the file system does not say.
    case evicted(freedByteCount: Int64?)
    case kept(Kept)
  }

  public var id: String
  /// The name the file was stored under, empty when there is no record.
  public var name: String
  /// Where the copy was, empty when there was none.
  public var localPath: String
  /// The copy's size.
  public var byteCount: Int64
  public var outcome: Outcome

  public init(id: String, name: String, localPath: String, byteCount: Int64, outcome: Outcome) {
    self.id = id
    self.name = name
    self.localPath = localPath
    self.byteCount = byteCount
    self.outcome = outcome
  }
}

/// What a file costs the volume, as APFS counts it (#959).
enum InstantFileBlocks {
  /// The bytes only this file holds, which deleting it gives back: `ATTR_CMNEXT_PRIVATESIZE`. An APFS clone shares
  /// its blocks with the file it was cloned from until either changes, so it holds next to nothing of its own; a file
  /// written as new bytes holds all of its blocks. Nil where the file system does not say (not APFS, not Darwin).
  static func privateByteCount(atPath path: String) -> Int64? {
    #if canImport(Darwin)
      var request = attrlist()
      request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
      request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
      request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
      // The reply: its length, the attributes returned, then the private size.
      var reply = [UInt8](repeating: 0, count: 64)
      let result = reply.withUnsafeMutableBytes { buffer in
        getattrlist(
          path,
          &request,
          buffer.baseAddress,
          buffer.count,
          UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW)
        )
      }
      guard result == 0 else { return nil }
      return reply.withUnsafeBytes { buffer in
        let returned = buffer.loadUnaligned(
          fromByteOffset: MemoryLayout<UInt32>.size,
          as: attribute_set_t.self
        )
        guard returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
        return Int64(
          buffer.loadUnaligned(
            fromByteOffset: MemoryLayout<UInt32>.size + MemoryLayout<attribute_set_t>.size,
            as: off_t.self
          )
        )
      }
    #else
      return nil
    #endif
  }
}
