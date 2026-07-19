import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStorageSnapshotTests {
  @Test
  func runtimeReportsDatabaseStreamAndDownloadedFileBytes() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-storage-status-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("recording.m4a")
    try Data([0, 1, 2, 3]).write(to: sourceURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "storage-status-test",
        persistenceURL: directory.appendingPathComponent("cache.sqlite")
      )
    )
    _ = try await runtime.signInWithRefreshToken("storage-refresh", userID: "storage-user")
    _ = try await runtime.uploadFile(
      from: sourceURL,
      name: "recording.m4a",
      contentType: "audio/mp4"
    )
    let stream = try await runtime.createStream(clientID: "storage-stream")
    _ = try await runtime.appendStreamContent(streamID: stream.id, content: "hello")

    let snapshot = try await runtime.storageSnapshot()
    #expect(snapshot.localCacheSize > 0)
    expectNoDifference(snapshot.streamCacheSize, 5)
    expectNoDifference(snapshot.downloadedFileSize, 4)
    expectNoDifference(snapshot.downloadedFileCount, 1)
  }
}
