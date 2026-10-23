import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #959: an upload keeps no copy of its bytes. Storage holds the file once the upload returns, as upstream's
/// `StorageAPI.uploadFile`, which keeps nothing; the device keeps the file's record (id, name, size), and a read downloads
/// it by the name it was stored under. Every upload used to be copied into the file store and kept for good: on one
/// device 3,754 files, 25.9 GB of logical size, 10.8 GB of it real blocks.
@Suite(.serialized)
struct InstantStoredFileUploadTests {
  @Test("An upload through storage keeps the file's record and no copy of its bytes")
  func uploadKeepsNoCopy() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-upload-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("App.tsx")
    let body = Data("export default function App() {}".utf8)
    try body.write(to: sourceURL)
    let recorder = UploadRecorder()
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test")),
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        now: { timestamp },
        makeID: { "local-file-id" }
      ),
      storageTransport: recorder.client
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let uploaded = try await runtime.uploadFile(
      from: sourceURL,
      name: " builds/App.tsx ",
      contentType: " text/typescript "
    )

    expectNoDifference(
      uploaded,
      InstantStoredFile(
        id: "remote-file-id",
        appID: "app-1",
        name: "builds/App.tsx",
        contentType: "text/typescript",
        byteCount: Int64(body.count),
        localPath: "",
        ownerUserID: "user-1",
        createdAt: timestamp,
        updatedAt: timestamp
      )
    )
    expectNoDifference(uploaded.isDownloaded, false)
    let filesDirectory = directory.appendingPathComponent("files", isDirectory: true)
    expectNoDifference(regularFiles(under: filesDirectory), [])
    // The record lists the file with no connection, and takes no room.
    let listedFiles = try await runtime.storedFiles()
    expectNoDifference(listedFiles, [uploaded])
    let snapshot = try await runtime.storageSnapshot()
    expectNoDifference(snapshot.downloadedFileCount, 0)
    expectNoDifference(snapshot.downloadedFileSize, 0)
    let uploadPaths = await recorder.uploadPaths
    expectNoDifference(uploadPaths, ["builds/App.tsx"])

    // A read downloads the file by the name it was stored under, with no list of every file, and keeps the record's
    // details.
    let contents = try await runtime.storedFileContents(id: uploaded.id)
    expectNoDifference(contents.data, Data("remote bytes".utf8))
    expectNoDifference(contents.file.contentType, "text/typescript")
    let downloadPaths = await recorder.downloadPaths
    expectNoDifference(downloadPaths, ["builds/App.tsx"])

    // Deleting removes the record and the read's cached copy.
    let deleted = try await runtime.deleteStoredFile(id: uploaded.id)
    expectNoDifference(deleted.id, uploaded.id)
    let remainingFiles = try await runtime.storedFiles()
    expectNoDifference(remainingFiles, [])
    expectNoDifference(regularFiles(under: filesDirectory), [])
  }
}

private actor UploadRecorder {
  private(set) var uploadPaths: [String] = []
  private(set) var downloadPaths: [String] = []

  nonisolated var client: InstantStorageTransportClient {
    InstantStorageTransportClient(
      upload: { request in
        await self.record(upload: request.path)
        return InstantStorageUploadResponse(id: "remote-file-id")
      },
      delete: { _ in InstantStorageDeleteResponse(id: "remote-file-id") },
      downloadFile: { request in
        await self.record(download: request.path)
        return Data("remote bytes".utf8)
      }
    )
  }

  private func record(upload path: String) {
    uploadPaths.append(path)
  }

  private func record(download path: String) {
    downloadPaths.append(path)
  }
}

/// The regular files under `directory`, as paths relative to it, sorted; none when it does not exist (#959).
func regularFiles(under directory: URL) -> [String] {
  guard
    let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey]
    )
  else { return [] }
  let base = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
  return enumerator.compactMap { item -> String? in
    guard let url = item as? URL,
      (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
    else { return nil }
    let path = url.standardizedFileURL.resolvingSymlinksInPath().path
    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
  }
  .sorted()
}
