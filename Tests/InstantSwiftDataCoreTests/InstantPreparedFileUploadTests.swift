import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Scribe #481 uploads a recording's audio in a background `URLSession`, which the system runs while the app is
/// suspended or relaunched (#491). The library prepares that upload without sending it and records the finished one
/// without a copy of its own, so a record can name a file the library holds no copy of. Every read then falls through
/// to storage, as it does when the system purged a cached copy.
@Suite(.serialized)
struct InstantPreparedFileUploadTests {
  private let payload = Data((0..<200_000).map { UInt8($0 % 239) })

  // MARK: - A record without the library's own copy

  @Test("A record whose library copy is gone reads from storage, under the record's path")
  func aRecordWhoseCopyIsGoneReadsFromStorage() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }
    let source = try fixture.source("take.wav", payload)
    let uploaded = try await fixture.runtime.uploadFile(from: source, name: "recordings/r1/take.wav")
    try FileManager.default.removeItem(atPath: uploaded.localPath)

    let contents = try await fixture.runtime.storedFileContents(id: uploaded.id)

    expectNoDifference(contents.data, payload)
    let downloadPaths = await fixture.recorder.fileDownloadPaths
    expectNoDifference(downloadPaths, ["recordings/r1/take.wav"])
  }

  @Test("A record whose library copy is gone downloads to the destination, under the record's path")
  func aRecordWhoseCopyIsGoneDownloadsToTheDestination() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }
    let source = try fixture.source("take.wav", payload)
    let uploaded = try await fixture.runtime.uploadFile(from: source, name: "recordings/r1/take.wav")
    try FileManager.default.removeItem(atPath: uploaded.localPath)
    let destination = fixture.directory.appendingPathComponent("out/take.wav")

    let file = try await fixture.runtime.downloadStoredFile(id: uploaded.id, to: destination)

    expectNoDifference(try Data(contentsOf: destination), payload)
    expectNoDifference(file.localPath, destination.path)
    let downloadPaths = await fixture.recorder.fileDownloadPaths
    expectNoDifference(downloadPaths, ["recordings/r1/take.wav"])
  }
}

// MARK: - Fixture

private struct UploadFixture {
  let directory: URL
  let recorder: StorageRecorder
  let runtime: InstantRuntime

  init(
    payload: Data,
    now: @escaping @Sendable () -> InstantTimestamp = { InstantTimestamp(milliseconds: 1_700_000_000_000) }
  ) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-prepared-upload-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let recorder = StorageRecorder(directory: directory, payload: payload)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test")),
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        now: now,
        makeID: { "local-file-id" }
      ),
      storageTransport: recorder.client
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    self.directory = directory
    self.recorder = recorder
    self.runtime = runtime
  }

  /// Writes a source file outside the library's own file store.
  func source(_ name: String, _ data: Data) throws -> URL {
    let url = directory.appendingPathComponent("sources/\(name)")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
    return url
  }

  /// The regular files in the library's own file store, where `uploadFile` copies a source.
  func libraryCopies() -> [String] {
    let root = directory.appendingPathComponent("files", isDirectory: true)
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
    else { return [] }
    return enumerator.compactMap { item -> String? in
      guard let url = item as? URL,
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      else { return nil }
      return url.path
    }
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private actor StorageRecorder {
  private let directory: URL
  private let payload: Data
  private(set) var uploads = 0
  private(set) var fileDownloadPaths: [String] = []
  private(set) var deletedPaths: [String] = []

  init(directory: URL, payload: Data) {
    self.directory = directory
    self.payload = payload
  }

  nonisolated var client: InstantStorageTransportClient {
    InstantStorageTransportClient(
      upload: { _ in
        await self.recordUpload()
        return InstantStorageUploadResponse(id: "uploaded-file-id")
      },
      delete: { request in
        await self.record(deletedPath: request.path)
        return InstantStorageDeleteResponse(id: nil)
      },
      download: { _ in self.payload },
      downloadFile: { request in
        await self.record(fileDownloadPath: request.path)
        return self.payload
      },
      downloadToFile: { _ in
        try await self.writeTemporaryFile()
      },
      downloadFileToFile: { request in
        await self.record(fileDownloadPath: request.path)
        return try await self.writeTemporaryFile()
      }
    )
  }

  private func recordUpload() {
    uploads += 1
  }

  private func record(fileDownloadPath: String) {
    fileDownloadPaths.append(fileDownloadPath)
  }

  private func record(deletedPath: String) {
    deletedPaths.append(deletedPath)
  }

  private func writeTemporaryFile() throws -> URL {
    let url = directory.appendingPathComponent("tmp-\(UUID().uuidString)")
    try payload.write(to: url)
    return url
  }
}
