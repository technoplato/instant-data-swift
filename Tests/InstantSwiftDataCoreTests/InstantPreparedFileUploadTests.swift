import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

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

// MARK: - Needs #491's API: a red run on the released code drops everything below this line.

extension InstantPreparedFileUploadTests {
  @Test("A prepared upload is the request the live transport sends, unsent, and the library keeps nothing")
  func aPreparedUploadIsTheLiveRequestUnsent() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }
    let source = try fixture.source("take.wav", payload)

    let prepared = try await fixture.runtime.prepareFileUpload(
      from: source,
      name: "recordings/r1/take.wav",
      contentType: "audio/wav"
    )

    expectNoDifference(prepared.path, "recordings/r1/take.wav")
    expectNoDifference(prepared.byteCount, Int64(payload.count))
    expectNoDifference(prepared.contentType, "audio/wav")
    expectNoDifference(prepared.sourceURL, source)
    let liveRequest = try await LiveUploadCapture.request(
      for: source,
      name: "recordings/r1/take.wav",
      contentType: "audio/wav"
    )
    expectNoDifference(prepared.request.url, liveRequest.url)
    expectNoDifference(prepared.request.httpMethod, "PUT")
    expectNoDifference(prepared.request.allHTTPHeaderFields, liveRequest.allHTTPHeaderFields)
    expectNoDifference(prepared.request.timeoutInterval, liveRequest.timeoutInterval)
    expectNoDifference(prepared.request.value(forHTTPHeaderField: "path"), "recordings/r1/take.wav")
    expectNoDifference(prepared.request.value(forHTTPHeaderField: "Authorization"), "Bearer refresh-token")
    expectNoDifference(prepared.request.value(forHTTPHeaderField: "Content-Length"), String(payload.count))
    // Nothing was sent, recorded, or copied.
    let uploads = await fixture.recorder.uploads
    expectNoDifference(uploads, 0)
    let storedFiles = try await fixture.runtime.storedFiles()
    expectNoDifference(storedFiles, [])
    expectNoDifference(fixture.libraryCopies(), [])
  }

  @Test("A prepared upload is named after its file unless a name is given")
  func aPreparedUploadIsNamedAfterItsFile() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }
    let source = try fixture.source("take.wav", payload)

    let prepared = try await fixture.runtime.prepareFileUpload(from: source)

    expectNoDifference(prepared.path, "take.wav")
    expectNoDifference(prepared.request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
  }

  @Test("An upload request gets 60 s plus 4 s for every MiB it sends")
  func anUploadRequestsTimeoutGrowsWithItsSize() throws {
    let apiURI = try #require(URL(string: "https://api.example.test"))
    func timeout(_ byteCount: Int64) -> TimeInterval {
      InstantStorageUploadRequest(
        appID: "app-1",
        apiURI: apiURI,
        path: "a.bin",
        sourceURL: URL(fileURLWithPath: "/tmp/a.bin"),
        byteCount: byteCount,
        refreshToken: "refresh-token"
      ).urlRequest.timeoutInterval
    }

    expectNoDifference(timeout(0), 60)
    expectNoDifference(timeout(1_048_576), 64)
    expectNoDifference(timeout(321 * 1_048_576), 1_344)
  }

  @Test("A finished upload is recorded without a copy, and the source stays where it is")
  func aFinishedUploadIsRecordedWithoutACopy() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }
    let source = try fixture.source("take.wav", payload)

    let file = try await fixture.runtime.completeFileUpload(
      path: "recordings/r1/take.wav",
      statusCode: 200,
      responseBody: Data(#"{"data":{"id":"server-file-1"}}"#.utf8),
      sourceURL: source,
      contentType: "audio/wav"
    )

    expectNoDifference(file.id, "server-file-1")
    expectNoDifference(file.name, "recordings/r1/take.wav")
    expectNoDifference(file.localPath, "")
    expectNoDifference(file.byteCount, Int64(payload.count))
    expectNoDifference(file.contentType, "audio/wav")
    expectNoDifference(file.ownerUserID, "user-1")
    let storedFiles = try await fixture.runtime.storedFiles()
    expectNoDifference(storedFiles, [file])
    expectNoDifference(fixture.libraryCopies(), [])
    expectNoDifference(try Data(contentsOf: source), payload)
  }

  @Test("A process that never prepared the upload completes it from the path and the answer alone")
  func aRelaunchedProcessCompletesTheUpload() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }

    let file = try await fixture.runtime.completeFileUpload(
      path: "recordings/r1/take.wav",
      statusCode: 200,
      responseBody: Data(#"{"data":{"id":"server-file-1"}}"#.utf8)
    )

    expectNoDifference(file.id, "server-file-1")
    expectNoDifference(file.byteCount, 0)
    expectNoDifference(file.contentType, nil)
    let storedFiles = try await fixture.runtime.storedFiles()
    expectNoDifference(storedFiles.map(\.id), ["server-file-1"])
  }

  @Test("Completing the same upload again changes nothing")
  func completingTheSameUploadAgainChangesNothing() async throws {
    var now = 1_700_000_000_000
    let clock = UploadTestClock(now)
    let fixture = try await UploadFixture(payload: payload, now: { clock.now() })
    defer { fixture.remove() }
    let source = try fixture.source("take.wav", payload)
    let body = Data(#"{"data":{"id":"server-file-1"}}"#.utf8)
    let first = try await fixture.runtime.completeFileUpload(
      path: "recordings/r1/take.wav", statusCode: 200, responseBody: body, sourceURL: source, contentType: "audio/wav"
    )
    now += 60_000
    clock.set(now)

    let second = try await fixture.runtime.completeFileUpload(
      path: "recordings/r1/take.wav", statusCode: 200, responseBody: body, sourceURL: source, contentType: "audio/wav"
    )

    expectNoDifference(second, first)
    let storedFiles = try await fixture.runtime.storedFiles()
    expectNoDifference(storedFiles, [first])
  }

  @Test(
    "A finished upload's status and body map as uploadFile's do, and nothing is recorded",
    arguments: [
      (401, #"{"data":{"id":"server-file-1"}}"#, InstantError.Code.permissionRejected),
      (403, #"{"data":{"id":"server-file-1"}}"#, InstantError.Code.permissionRejected),
      (500, #"{"data":{"id":"server-file-1"}}"#, InstantError.Code.networkFailed),
      (200, #"{"id":"server-file-1"}"#, InstantError.Code.decodeFailed),
    ]
  )
  func aFailedUploadMapsAsUploadFiles(statusCode: Int, body: String, code: InstantError.Code) async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }

    let error = await #expect(throws: InstantError.self) {
      try await fixture.runtime.completeFileUpload(
        path: "recordings/r1/take.wav",
        statusCode: statusCode,
        responseBody: Data(body.utf8)
      )
    }

    expectNoDifference(error?.code, code)
    let storedFiles = try await fixture.runtime.storedFiles()
    expectNoDifference(storedFiles, [])
  }

  @Test("After a completed upload, both reads fetch from storage under its path")
  func aCompletedUploadsReadsFetchFromStorage() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }
    let completed = try await fixture.runtime.completeFileUpload(
      path: "recordings/r1/take.wav",
      statusCode: 200,
      responseBody: Data(#"{"data":{"id":"server-file-1"}}"#.utf8),
      contentType: "audio/wav"
    )
    let destination = fixture.directory.appendingPathComponent("out/take.wav")

    let downloaded = try await fixture.runtime.downloadStoredFile(id: completed.id, to: destination)
    let contents = try await fixture.runtime.storedFileContents(id: completed.id)

    expectNoDifference(try Data(contentsOf: destination), payload)
    expectNoDifference(downloaded.contentType, "audio/wav")
    expectNoDifference(contents.data, payload)
    expectNoDifference(contents.file.contentType, "audio/wav")
    let downloadPaths = await fixture.recorder.fileDownloadPaths
    expectNoDifference(downloadPaths, ["recordings/r1/take.wav", "recordings/r1/take.wav"])
  }

  @Test("Deleting a completed upload's record deletes it in storage and leaves the source alone")
  func deletingACompletedUploadLeavesTheSourceAlone() async throws {
    let fixture = try await UploadFixture(payload: payload)
    defer { fixture.remove() }
    let source = try fixture.source("take.wav", payload)
    let completed = try await fixture.runtime.completeFileUpload(
      path: "recordings/r1/take.wav",
      statusCode: 200,
      responseBody: Data(#"{"data":{"id":"server-file-1"}}"#.utf8),
      sourceURL: source
    )

    try await fixture.runtime.deleteStoredFile(id: completed.id)

    let deletedPaths = await fixture.recorder.deletedPaths
    expectNoDifference(deletedPaths, ["recordings/r1/take.wav"])
    expectNoDifference(try Data(contentsOf: source), payload)
    let storedFiles = try await fixture.runtime.storedFiles()
    expectNoDifference(storedFiles, [])
  }
}

/// The request the live transport sends for an upload, captured from its HTTP client instead of the network.
private enum LiveUploadCapture {
  static func request(for source: URL, name: String, contentType: String?) async throws -> URLRequest {
    let captured = CapturedRequest()
    let transport = InstantStorageTransportClient.live(
      httpClient: InstantStorageHTTPClient(
        send: { _ in InstantStorageHTTPResponse(statusCode: 500, data: Data()) },
        uploadFile: { request, _ in
          captured.set(request)
          return InstantStorageHTTPResponse(statusCode: 200, data: Data(#"{"data":{"id":"uploaded-file-id"}}"#.utf8))
        }
      )
    )
    let byteCount = try #require(
      try FileManager.default.attributesOfItem(atPath: source.path)[.size] as? NSNumber
    ).int64Value
    _ = try await transport.upload(
      InstantStorageUploadRequest(
        appID: "app-1",
        apiURI: try #require(URL(string: "https://api.example.test")),
        path: name,
        sourceURL: source,
        byteCount: byteCount,
        refreshToken: "refresh-token",
        contentType: contentType
      )
    )
    return try #require(captured.value)
  }
}

private final class CapturedRequest: @unchecked Sendable {
  private let lock = NSLock()
  private var request: URLRequest?

  func set(_ request: URLRequest) {
    lock.withLock { self.request = request }
  }

  var value: URLRequest? {
    lock.withLock { request }
  }
}

private final class UploadTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var milliseconds: Int

  init(_ milliseconds: Int) {
    self.milliseconds = milliseconds
  }

  func set(_ milliseconds: Int) {
    lock.withLock { self.milliseconds = milliseconds }
  }

  func now() -> InstantTimestamp {
    InstantTimestamp(milliseconds: lock.withLock { Int64(milliseconds) })
  }
}
