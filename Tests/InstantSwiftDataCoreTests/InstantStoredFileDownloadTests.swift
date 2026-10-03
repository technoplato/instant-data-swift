import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Scribe #454: an iPad that played back a recording whose 1.96 GB audio it did not have held the whole file in memory
/// (`storedFileContents` returns `Data`), cached a copy, and Scribe wrote a second copy: a 4.4 GB footprint and 3.9 GB
/// more on disk. `downloadStoredFile(id:name:to:)` streams to the destination instead, through the transport's file
/// downloads, and keeps no copy of its own.
@Suite(.serialized)
struct InstantStoredFileDownloadTests {
  private let payload = Data((0..<300_000).map { UInt8($0 % 251) })

  @Test("The old read holds every byte in memory and keeps a cached copy of its own")
  func storedFileContentsHoldsTheWholeFileAndCachesACopy() async throws {
    let fixture = try await Fixture(payload: payload)
    defer { fixture.remove() }

    let contents = try await fixture.runtime.storedFileContents(id: "file-1", name: "recordings/audio.wav")

    // The whole file, as one value in memory.
    expectNoDifference(contents.data.count, payload.count)
    // And a second copy in the library's own file store.
    let cached = try #require(try await fixture.runtime.storedFiles().only)
    expectNoDifference(try Data(contentsOf: URL(fileURLWithPath: cached.localPath)), payload)
    expectNoDifference(await fixture.recorder.dataDownloads, 1)
  }

  @Test("A named file streams to its destination, with no data download and no copy of the library's own")
  func namedDownloadStreamsToTheDestination() async throws {
    let fixture = try await Fixture(payload: payload)
    defer { fixture.remove() }
    let destination = fixture.directory.appendingPathComponent("recording/audio.wav")

    let file = try await fixture.runtime.downloadStoredFile(
      id: "file-1",
      name: "recordings/audio.wav",
      to: destination
    )

    expectNoDifference(try Data(contentsOf: destination), payload)
    expectNoDifference(file.byteCount, Int64(payload.count))
    expectNoDifference(file.localPath, destination.path)
    expectNoDifference(file.name, "recordings/audio.wav")
    // Only the file download ran: nothing returned the file as data.
    expectNoDifference(await fixture.recorder.dataDownloads, 0)
    expectNoDifference(await fixture.recorder.fileDownloads.map(\.path), ["recordings/audio.wav"])
    // The destination holds the only copy, and the temporary file moved there.
    expectNoDifference(try await fixture.runtime.storedFiles(), [])
    let temporaryURL = try #require(await fixture.recorder.temporaryURLs.only)
    expectNoDifference(FileManager.default.fileExists(atPath: temporaryURL.path), false)
  }

  @Test("A download replaces a file already at the destination")
  func downloadReplacesTheDestination() async throws {
    let fixture = try await Fixture(payload: payload)
    defer { fixture.remove() }
    let destination = fixture.directory.appendingPathComponent("audio.wav")
    try Data("partial".utf8).write(to: destination)

    try await fixture.runtime.downloadStoredFile(id: "file-1", name: "recordings/audio.wav", to: destination)

    expectNoDifference(try Data(contentsOf: destination), payload)
  }

  @Test("A file the library already holds copies file to file, with no download")
  func heldFileCopiesWithoutDownloading() async throws {
    let fixture = try await Fixture(payload: payload)
    defer { fixture.remove() }
    let source = fixture.directory.appendingPathComponent("upload.bin")
    try payload.write(to: source)
    let uploaded = try await fixture.runtime.uploadFile(from: source, name: "uploads/upload.bin")
    let destination = fixture.directory.appendingPathComponent("copy/upload.bin")

    let file = try await fixture.runtime.downloadStoredFile(id: uploaded.id, to: destination)

    expectNoDifference(try Data(contentsOf: destination), payload)
    expectNoDifference(file.localPath, destination.path)
    expectNoDifference(await fixture.recorder.dataDownloads, 0)
    expectNoDifference(await fixture.recorder.fileDownloads, [])
  }

  @Test("A failed download leaves the destination as it was and no temporary file")
  func failedDownloadLeavesNoTrace() async throws {
    let fixture = try await Fixture(payload: payload, failsFileDownloads: true)
    defer { fixture.remove() }
    let destination = fixture.directory.appendingPathComponent("audio.wav")
    try Data("before".utf8).write(to: destination)

    await #expect(throws: InstantError.self) {
      try await fixture.runtime.downloadStoredFile(id: "file-1", name: "recordings/audio.wav", to: destination)
    }

    expectNoDifference(try Data(contentsOf: destination), Data("before".utf8))
    for temporaryURL in await fixture.recorder.temporaryURLs {
      expectNoDifference(FileManager.default.fileExists(atPath: temporaryURL.path), false)
    }
  }

  @Test("A transport that only returns data still downloads, through a temporary file")
  func dataOnlyTransportDownloadsThroughATemporaryFile() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-download-data-only-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let payload = self.payload
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test")),
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        now: { InstantTimestamp(milliseconds: 1_700_000_000_000) }
      ),
      storageTransport: InstantStorageTransportClient(
        upload: { _ in InstantStorageUploadResponse(id: "file-1") },
        delete: { _ in InstantStorageDeleteResponse(id: "file-1") },
        downloadFile: { _ in payload }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let destination = directory.appendingPathComponent("audio.wav")

    try await runtime.downloadStoredFile(id: "file-1", name: "recordings/audio.wav", to: destination)

    expectNoDifference(try Data(contentsOf: destination), payload)
    expectNoDifference(try await runtime.storedFiles(), [])
  }
}

private struct Fixture {
  let directory: URL
  let recorder: DownloadRecorder
  let runtime: InstantRuntime

  init(payload: Data, failsFileDownloads: Bool = false) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-download-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let recorder = DownloadRecorder(directory: directory, payload: payload, failsFileDownloads: failsFileDownloads)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test")),
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
        makeID: { "local-file-id" }
      ),
      storageTransport: recorder.client
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    self.directory = directory
    self.recorder = recorder
    self.runtime = runtime
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private actor DownloadRecorder {
  private let directory: URL
  private let payload: Data
  private let failsFileDownloads: Bool
  private(set) var dataDownloads = 0
  private(set) var fileDownloads: [InstantStorageFileDownloadRequest] = []
  private(set) var temporaryURLs: [URL] = []

  init(directory: URL, payload: Data, failsFileDownloads: Bool) {
    self.directory = directory
    self.payload = payload
    self.failsFileDownloads = failsFileDownloads
  }

  nonisolated var client: InstantStorageTransportClient {
    InstantStorageTransportClient(
      upload: { _ in InstantStorageUploadResponse(id: "uploaded-file-id") },
      delete: { _ in InstantStorageDeleteResponse(id: nil) },
      download: { _ in
        await self.recordDataDownload()
        return self.payload
      },
      downloadFile: { _ in
        await self.recordDataDownload()
        return self.payload
      },
      downloadToFile: { _ in
        try await self.writeTemporaryFile()
      },
      downloadFileToFile: { request in
        await self.record(fileDownload: request)
        return try await self.writeTemporaryFile()
      }
    )
  }

  private func recordDataDownload() {
    dataDownloads += 1
  }

  private func record(fileDownload: InstantStorageFileDownloadRequest) {
    fileDownloads.append(fileDownload)
  }

  /// What the live transport's download task hands over: a temporary file with the body.
  private func writeTemporaryFile() throws -> URL {
    let url = directory.appendingPathComponent("tmp-\(UUID().uuidString)")
    temporaryURLs.append(url)
    if failsFileDownloads {
      throw InstantError(
        code: .networkFailed,
        operation: "download file",
        message: "The test transport failed the download.",
        recovery: "None; the test expects it."
      )
    }
    try payload.write(to: url)
    return url
  }
}

extension Collection {
  fileprivate var only: Element? {
    count == 1 ? first : nil
  }
}
