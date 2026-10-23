import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #959: copies the file store kept before an upload stopped keeping one (on one device 3,754 files, 25.9 GB of
/// logical size and 10.8 GB of real blocks) go through `evictStoredFiles(ids:)`, and only once storage's own record of
/// each file (`$files`, by id, through the open connection) has the copy's size. Every record stays, not downloaded, so
/// the file can be fetched again by the name it was stored under.
@Suite(.serialized)
struct InstantStoredFileEvictionTests {
  private let payload = Data((0..<300_000).map { UInt8($0 % 241) })

  @Test("A copy goes once storage's record of the file has its size; the others stay and say why")
  func evictsOnlyTheCopiesStorageHolds() async throws {
    let fixture = try await EvictionFixture(payload: payload, connects: true)
    defer { fixture.remove() }
    // Three copies this device holds: the old read kept each.
    for (id, name) in [
      ("same", "scribe/r/generation-1/audio-chunks/000000.wav"),
      ("differs", "scribe/r/generation-1/audio.wav"),
      ("missing", "scribe/r/generation-1/image.png"),
    ] {
      _ = try await fixture.runtime.storedFileContents(id: id, name: name)
    }
    // And a file uploaded since: its record, with no copy.
    let source = fixture.directory.appendingPathComponent("upload.bin")
    try payload.write(to: source)
    let uploaded = try await fixture.runtime.uploadFile(from: source, name: "scribe/r/generation-1/later.wav")
    let held = try await fixture.runtime.localStoredFiles().filter(\.isDownloaded)
    expectNoDifference(held.map(\.id).sorted(), ["differs", "missing", "same"])
    let sameCopy = try #require(held.first { $0.id == "same" }).localPath
    let differsCopy = try #require(held.first { $0.id == "differs" }).localPath
    let missingCopy = try #require(held.first { $0.id == "missing" }).localPath

    let evicting = Task {
      try await fixture.runtime.evictStoredFiles(ids: ["same", "differs", "missing", uploaded.id, "unknown"])
    }
    defer { evicting.cancel() }
    // Storage's records of the three held copies, asked by id over the connection.
    let query = try await fixture.waitForFilesQuery(sentMessageCount: 2)
    await fixture.answer(
      query: query,
      files: [
        .init(id: "same", name: "scribe/r/generation-1/audio-chunks/000000.wav", size: payload.count),
        .init(id: "differs", name: "scribe/r/generation-1/audio.wav", size: payload.count - 1),
      ]
    )
    let evictions = try await instantLiveWithTimeout(
      operation: "evict stored files",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds,
      onAbandon: { evicting.cancel() }
    ) {
      try await evicting.value
    }

    expectNoDifference(evictions.map(\.id), ["same", "differs", "missing", uploaded.id, "unknown"])
    let same = try #require(evictions.first)
    guard case .evicted(let freedByteCount) = same.outcome else {
      Issue.record("Expected the copy whose record has its size to go, got \(same.outcome).")
      return
    }
    // A copy written as new bytes frees its own blocks: at least its size.
    #expect((freedByteCount ?? 0) >= Int64(payload.count))
    expectNoDifference(same.localPath, sameCopy)
    expectNoDifference(same.byteCount, Int64(payload.count))
    expectNoDifference(
      evictions.dropFirst().map(\.outcome),
      [
        .kept(.sizeDiffers(serverByteCount: Int64(payload.count - 1))),
        .kept(.notOnServer),
        .kept(.notHeld),
        .kept(.notHeld),
      ]
    )
    // The evicted copy and its folder are gone; the kept ones are where they were.
    expectNoDifference(FileManager.default.fileExists(atPath: sameCopy), false)
    expectNoDifference(
      FileManager.default.fileExists(atPath: URL(fileURLWithPath: sameCopy).deletingLastPathComponent().path),
      false
    )
    expectNoDifference(FileManager.default.fileExists(atPath: differsCopy), true)
    expectNoDifference(FileManager.default.fileExists(atPath: missingCopy), true)
    // Every record stays; the evicted one is no longer downloaded.
    let records = try await fixture.runtime.localStoredFiles()
    expectNoDifference(
      records.map { "\($0.id) \($0.isDownloaded)" }.sorted(),
      ["differs true", "missing true", "same false", "\(uploaded.id) false"].sorted()
    )
    let sameRecord = try #require(records.first { $0.id == "same" })
    expectNoDifference(sameRecord.name, "scribe/r/generation-1/audio-chunks/000000.wav")
    expectNoDifference(sameRecord.byteCount, Int64(payload.count))
    let snapshot = try await fixture.runtime.storageSnapshot()
    expectNoDifference(snapshot.downloadedFileCount, 2)

    // The evicted file comes back from storage by the name it was stored under.
    let destination = fixture.directory.appendingPathComponent("again/000000.wav")
    try await fixture.runtime.downloadStoredFile(id: "same", to: destination)
    expectNoDifference(try Data(contentsOf: destination), payload)
    let fileDownloadPaths = await fixture.recorder.fileDownloadPaths
    expectNoDifference(fileDownloadPaths, ["scribe/r/generation-1/audio-chunks/000000.wav"])
  }

  @Test("With the connection closed, eviction throws and every copy stays")
  func closedConnectionKeepsEveryCopy() async throws {
    let fixture = try await EvictionFixture(payload: payload, connects: false)
    defer { fixture.remove() }
    _ = try await fixture.runtime.storedFileContents(id: "same", name: "scribe/r/generation-1/audio.wav")
    let copy = try #require(try await fixture.runtime.localStoredFiles().first).localPath

    await #expect(throws: InstantError.self) {
      _ = try await fixture.runtime.evictStoredFiles(ids: ["same"])
    }

    expectNoDifference(FileManager.default.fileExists(atPath: copy), true)
    let record = try #require(try await fixture.runtime.localStoredFiles().first)
    expectNoDifference(record.isDownloaded, true)
  }

  @Test("A client without storage keeps every copy: each is the only one")
  func clientWithoutStorageKeepsEveryCopy() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-eviction-local-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        persistenceURL: directory.appendingPathComponent("cache.sqlite"),
        makeID: { "local-file" }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let source = directory.appendingPathComponent("note.txt")
    try payload.write(to: source)
    let uploaded = try await runtime.uploadFile(from: source, name: "notes/note.txt")
    expectNoDifference(uploaded.isDownloaded, true)

    let evictions = try await runtime.evictStoredFiles(ids: [uploaded.id])

    expectNoDifference(evictions.map(\.outcome), [.kept(.noStorage)])
    expectNoDifference(FileManager.default.fileExists(atPath: uploaded.localPath), true)
  }
}

private struct EvictionFixture {
  struct RemoteFile {
    var id: String
    var name: String
    var size: Int
  }

  let directory: URL
  let session: LiveReactorParitySession
  let recorder: EvictionStorageRecorder
  let runtime: InstantRuntime

  init(payload: Data, connects: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-eviction-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: evictionServerAttributes)])
    let recorder = EvictionStorageRecorder(directory: directory, payload: payload)
    var configuration = InstantRuntimeConfiguration(
      appID: "app-1",
      apiURI: try #require(URL(string: "https://api.example.test")),
      persistenceURL: directory.appendingPathComponent("cache.sqlite"),
      now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(
      configuration: configuration,
      storageTransport: recorder.client
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    if connects {
      _ = try await instantLiveWithTimeout(
        operation: "connect the eviction fixture",
        timeoutMilliseconds: InstantTestWait.hangMilliseconds
      ) {
        try await runtime.connect()
      }
    }
    self.directory = directory
    self.session = session
    self.recorder = recorder
    self.runtime = runtime
  }

  func waitForFilesQuery(sentMessageCount: Int) async throws -> InstantLiveJSONValue {
    try await instantLiveWithTimeout(
      operation: "wait for the $files query",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) {
      try await session.waitForSentMessageCount(sentMessageCount)
    }
    let message = try #require(await session.sentMessages().last)
    expectNoDifference(message.op, "add-query")
    return try #require(message.fields["q"])
  }

  func answer(query: InstantLiveJSONValue, files: [RemoteFile]) async {
    await session.enqueue(
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "files-by-id",
        result: evictionQueryResult(files)
      )
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private actor EvictionStorageRecorder {
  private let directory: URL
  private let payload: Data
  private(set) var fileDownloadPaths: [String] = []

  init(directory: URL, payload: Data) {
    self.directory = directory
    self.payload = payload
  }

  nonisolated var client: InstantStorageTransportClient {
    InstantStorageTransportClient(
      upload: { _ in InstantStorageUploadResponse(id: "uploaded-file-id") },
      delete: { _ in InstantStorageDeleteResponse(id: nil) },
      download: { _ in self.payload },
      downloadFile: { _ in self.payload },
      downloadToFile: { _ in try await self.writeTemporaryFile() },
      downloadFileToFile: { request in
        await self.record(fileDownloadPath: request.path)
        return try await self.writeTemporaryFile()
      }
    )
  }

  private func record(fileDownloadPath: String) {
    fileDownloadPaths.append(fileDownloadPath)
  }

  private func writeTemporaryFile() throws -> URL {
    let url = directory.appendingPathComponent("tmp-\(UUID().uuidString)")
    try payload.write(to: url)
    return url
  }
}

private let evictionServerAttributes = [
  liveReactorServerAttr(id: "server-files-id", name: "id", namespace: "$files"),
  liveReactorServerAttr(id: "server-files-path", name: "path", namespace: "$files"),
  liveReactorServerAttr(id: "server-files-size", name: "size", namespace: "$files", valueType: "number"),
]

private func evictionQueryResult(_ files: [EvictionFixture.RemoteFile]) -> [InstantLiveJSONValue] {
  let timestamp = Double(1_700_000_000_000)
  func row(_ entityID: String, _ attributeID: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
    .array([.string(entityID), .string(attributeID), value, .number(timestamp)])
  }
  return [
    .object([
      "data": .object([
        "datalog-result": .object([
          "join-rows": .array(
            files.map { file in
              .array([
                row(file.id, "server-files-id", .string(file.id)),
                row(file.id, "server-files-path", .string(file.name)),
                row(file.id, "server-files-size", .number(Double(file.size))),
              ])
            }
          )
        ])
      ]),
      "child-nodes": .array([]),
    ])
  ]
}
