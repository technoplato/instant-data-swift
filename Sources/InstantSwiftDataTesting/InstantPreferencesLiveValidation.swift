import Foundation

public struct InstantPreferencesLiveValidationDetails: Codable, Equatable, Sendable {
  public var userID: String
  public var phaseSequence: [String]
  public var connectionState: String
  public var localCacheSize: Int64
  public var streamCacheSize: Int64
  public var downloadedFileSizeBeforeClear: Int64
  public var downloadedFileCountBeforeClear: Int
  public var clearedFileCount: Int
  public var clearedBytes: Int64
  public var downloadedFileSizeAfterClear: Int64
  public var downloadedFileCountAfterClear: Int
  public var remainingFileNames: [String]

  public init(
    userID: String,
    phaseSequence: [String],
    connectionState: String,
    localCacheSize: Int64,
    streamCacheSize: Int64,
    downloadedFileSizeBeforeClear: Int64,
    downloadedFileCountBeforeClear: Int,
    clearedFileCount: Int,
    clearedBytes: Int64,
    downloadedFileSizeAfterClear: Int64,
    downloadedFileCountAfterClear: Int,
    remainingFileNames: [String]
  ) {
    self.userID = userID
    self.phaseSequence = phaseSequence
    self.connectionState = connectionState
    self.localCacheSize = localCacheSize
    self.streamCacheSize = streamCacheSize
    self.downloadedFileSizeBeforeClear = downloadedFileSizeBeforeClear
    self.downloadedFileCountBeforeClear = downloadedFileCountBeforeClear
    self.clearedFileCount = clearedFileCount
    self.clearedBytes = clearedBytes
    self.downloadedFileSizeAfterClear = downloadedFileSizeAfterClear
    self.downloadedFileCountAfterClear = downloadedFileCountAfterClear
    self.remainingFileNames = remainingFileNames
  }
}
