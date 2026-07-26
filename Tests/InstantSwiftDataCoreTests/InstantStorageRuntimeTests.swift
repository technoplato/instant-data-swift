import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantStorageRuntimeTests {
  @Test("Live storage uses the server file id, caches bytes, and deletes remotely first")
  func liveUploadAndDelete() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-storage-runtime-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistenceURL = directory.appendingPathComponent("cache.sqlite")
    let sourceURL = directory.appendingPathComponent("App.tsx")
    let body = Data("export default function App() {}".utf8)
    try body.write(to: sourceURL)
    let recorder = StorageTransportRecorder()
    let storageTransport = recorder.client
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        persistenceURL: persistenceURL,
        now: { timestamp },
        makeID: { "local-file-id" }
      ),
      storageTransport: storageTransport
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let uploaded = try await runtime.uploadFile(
      from: sourceURL,
      name: " builds/App.tsx ",
      contentType: " text/typescript "
    )

    expectNoDifference(uploaded.id, "remote-file-id")
    expectNoDifference(uploaded.name, "builds/App.tsx")
    expectNoDifference(uploaded.byteCount, Int64(body.count))
    let storedContents = try await runtime.storedFileContents(id: uploaded.id)
    expectNoDifference(storedContents.data, body)
    let upload = try #require(await recorder.uploadRequests().only)
    expectNoDifference(upload.appID, "app-1")
    expectNoDifference(upload.apiURI.absoluteString, "https://api.example.test/custom")
    expectNoDifference(upload.path, "builds/App.tsx")
    expectNoDifference(upload.data, body)
    expectNoDifference(upload.refreshToken, "refresh-token")
    expectNoDifference(upload.contentType, "text/typescript")

    let deleted = try await runtime.deleteStoredFile(id: uploaded.id)

    expectNoDifference(deleted, uploaded)
    let remainingFiles = try await runtime.storedFiles()
    expectNoDifference(remainingFiles, [])
    expectNoDifference(FileManager.default.fileExists(atPath: uploaded.localPath), false)
    let delete = try #require(await recorder.deleteRequests().only)
    expectNoDifference(delete.appID, "app-1")
    expectNoDifference(delete.apiURI.absoluteString, "https://api.example.test/custom")
    expectNoDifference(delete.path, "builds/App.tsx")
    expectNoDifference(delete.refreshToken, "refresh-token")
  }

  @Test("A failed live upload does not create a local file")
  func failedLiveUploadDoesNotPersist() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-storage-runtime-failure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("App.tsx")
    try Data("code".utf8).write(to: sourceURL)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        persistenceURL: directory.appendingPathComponent("cache.sqlite")
      ),
      storageTransport: InstantStorageTransportClient(
        upload: { _ in
          throw InstantError(
            code: .networkFailed,
            operation: "upload file",
            message: "offline",
            recovery: "retry"
          )
        },
        delete: { _ in InstantStorageDeleteResponse(id: nil) }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    do {
      _ = try await runtime.uploadFile(from: sourceURL)
      Issue.record("Expected the live storage upload to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .networkFailed)
      expectNoDifference(error.operation, "upload file")
    }
    let files = try await runtime.storedFiles()
    expectNoDifference(files, [])
  }

  @Test("A named remote file downloads without waiting for the live query transport")
  func namedRemoteDownloadDoesNotRequireLiveQueryTransport() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-storage-runtime-download-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = StorageTransportRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test/custom")),
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        now: { InstantTimestamp(milliseconds: 1_700_000_000_000) }
      ),
      storageTransport: recorder.client
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let contents = try await runtime.storedFileContents(
      id: "remote-file-id",
      name: "scribe/recording/audio.wav"
    )

    expectNoDifference(contents.data, Data("remote bytes".utf8))
    expectNoDifference(contents.file.id, "remote-file-id")
    expectNoDifference(contents.file.name, "scribe/recording/audio.wav")
    let request = try #require(await recorder.downloadFileRequests().only)
    expectNoDifference(request.appID, "app-1")
    expectNoDifference(request.apiURI.absoluteString, "https://api.example.test/custom")
    expectNoDifference(request.path, "scribe/recording/audio.wav")
    expectNoDifference(request.refreshToken, "refresh-token")
  }
}

private actor StorageTransportRecorder {
  private var uploads: [InstantStorageUploadRequest] = []
  private var deletes: [InstantStorageDeleteRequest] = []
  private var fileDownloads: [InstantStorageFileDownloadRequest] = []

  nonisolated var client: InstantStorageTransportClient {
    InstantStorageTransportClient(
      upload: { request in
        await self.record(upload: request)
        return InstantStorageUploadResponse(id: "remote-file-id")
      },
      delete: { request in
        await self.record(delete: request)
        return InstantStorageDeleteResponse(id: "remote-file-id")
      },
      downloadFile: { request in
        await self.record(downloadFile: request)
        return Data("remote bytes".utf8)
      }
    )
  }

  func record(upload: InstantStorageUploadRequest) {
    uploads.append(upload)
  }

  func record(delete: InstantStorageDeleteRequest) {
    deletes.append(delete)
  }

  func record(downloadFile: InstantStorageFileDownloadRequest) {
    fileDownloads.append(downloadFile)
  }

  func uploadRequests() -> [InstantStorageUploadRequest] {
    uploads
  }

  func deleteRequests() -> [InstantStorageDeleteRequest] {
    deletes
  }

  func downloadFileRequests() -> [InstantStorageFileDownloadRequest] {
    fileDownloads
  }
}

extension Array {
  fileprivate var only: Element? {
    count == 1 ? self[0] : nil
  }
}
