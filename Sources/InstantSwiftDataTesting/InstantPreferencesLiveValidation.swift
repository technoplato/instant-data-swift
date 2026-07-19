import Dependencies
import Foundation
import InstantSwiftData

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

public enum InstantPreferencesLiveValidation {
  public static func run(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    refreshToken: String,
    expectedUserID: String,
    persistenceURL: URL? = nil
  ) async throws -> ValidationEvidenceRow<InstantPreferencesLiveValidationDetails> {
    let persistenceURL = persistenceURL ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-preferences-live-\(UUID().uuidString).sqlite")
    let fixtureDirectory = persistenceURL.deletingLastPathComponent()
      .appendingPathComponent("preferences-fixtures-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: fixtureDirectory) }

    let client = try await withDependencies {
      $0.context = .live
      try await $0.bootstrapInstantSwiftData(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: persistenceURL,
        context: .live
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client
      return client
    }

    let syncState = await MainActor.run { InstantSyncStatusState() }
    await MainActor.run { syncState.startObservationIfNeeded(using: client) }
    defer { Task { @MainActor in syncState.stopObservation() } }
    try await waitForPhase(.connected, state: syncState)

    let session = try await client.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-preferences-user"
    )
    guard session.userID == expectedUserID else {
      throw validationFailure(
        operation: "validate preferences auth",
        message: "Server-verified preferences user did not match the expected user."
      )
    }
    try await waitForPhase(.authenticated, state: syncState)

    let recordingURL = fixtureDirectory.appendingPathComponent("recording.m4a")
    let transcriptURL = fixtureDirectory.appendingPathComponent("transcript.txt")
    try Data([0, 1, 2, 3]).write(to: recordingURL)
    try Data([4, 5, 6]).write(to: transcriptURL)
    _ = try await client.uploadFile(
      from: recordingURL,
      name: "recording.m4a",
      contentType: "audio/mp4"
    )
    _ = try await client.uploadFile(
      from: transcriptURL,
      name: "transcript.txt",
      contentType: "text/plain"
    )
    let stream = try await client.createStream(clientID: "preferences-stream")
    _ = try await client.appendStreamContent(streamID: stream.id, content: "hello-stream")

    let storageState = await MainActor.run { InstantStorageStatusState() }
    let loadTask = await MainActor.run { storageState.load(using: client) }
    await loadTask.value
    let before = await MainActor.run { storageState.snapshot }
    guard before.localCacheSize > 0,
      before.streamCacheSize == 12,
      before.downloadedFileSize == 7,
      before.downloadedFileCount == 2
    else {
      throw validationFailure(
        operation: "validate preferences storage snapshot",
        message: "Live storage sizes did not match the exact local fixtures."
      )
    }

    let clearRecorder = await MainActor.run { PreferencesClearRecorder() }
    let clearTask = await MainActor.run {
      storageState.clearDownloadedFiles(
        matching: PreferencesAudioFile.self,
        using: client,
        onCleared: { clearRecorder.events.append($0) },
        onFailure: { clearRecorder.failures.append($0) }
      )
    }
    await clearTask.value
    let clearResult = await MainActor.run {
      (storageState.snapshot, clearRecorder.events, clearRecorder.failures)
    }
    guard clearResult.1 == [InstantStorageFilesClearedEvent(fileCount: 1, bytesRemoved: 4)],
      clearResult.2.isEmpty,
      clearResult.0.downloadedFileSize == 3,
      clearResult.0.downloadedFileCount == 1
    else {
      throw validationFailure(
        operation: "validate preferences clear downloaded audio",
        message: "Selective audio clearing did not report the exact completion event."
      )
    }
    let remainingFiles = try await client.storedFiles().map(\.name).sorted()
    guard remainingFiles == ["transcript.txt"] else {
      throw validationFailure(
        operation: "validate preferences remaining downloads",
        message: "Clearing audio removed a non-matching downloaded file."
      )
    }
    let status = try await client.connectionStatus()
    guard status.state == .authenticated else {
      throw validationFailure(
        operation: "validate preferences connection status",
        message: "Preferences validation did not finish authenticated."
      )
    }

    return ValidationEvidenceRow(
      caseID: "validation.live.preferences",
      side: "swift",
      event: "sync-and-storage-verified",
      appID: appID,
      entityID: expectedUserID,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: true,
      details: InstantPreferencesLiveValidationDetails(
        userID: expectedUserID,
        phaseSequence: [InstantSyncPhase.connected.rawValue, InstantSyncPhase.authenticated.rawValue],
        connectionState: status.state.rawValue,
        localCacheSize: before.localCacheSize,
        streamCacheSize: before.streamCacheSize,
        downloadedFileSizeBeforeClear: before.downloadedFileSize,
        downloadedFileCountBeforeClear: before.downloadedFileCount,
        clearedFileCount: clearResult.1[0].fileCount,
        clearedBytes: clearResult.1[0].bytesRemoved,
        downloadedFileSizeAfterClear: clearResult.0.downloadedFileSize,
        downloadedFileCountAfterClear: clearResult.0.downloadedFileCount,
        remainingFileNames: remainingFiles
      )
    )
  }

  private static func waitForPhase(
    _ expected: InstantSyncPhase,
    state: InstantSyncStatusState
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(15)
    while ContinuousClock.now < deadline {
      if await MainActor.run(body: { state.phase == expected }) { return }
      try await Task.sleep(for: .milliseconds(25))
    }
    let actual = await MainActor.run { state.phase.rawValue }
    throw validationFailure(
      operation: "wait for preferences sync phase",
      message: "Expected \(expected.rawValue), found \(actual)."
    )
  }

  private static func validationFailure(operation: String, message: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect the V3 preferences source contract and live runtime evidence."
    )
  }
}

private enum PreferencesAudioFile: InstantStoredFileMatcher {
  static func matches(_ file: InstantStoredFile) -> Bool {
    file.contentType?.hasPrefix("audio/") == true
  }
}

@MainActor
private final class PreferencesClearRecorder {
  var events: [InstantStorageFilesClearedEvent] = []
  var failures: [InstantError] = []
}
