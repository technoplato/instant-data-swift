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

  /// #1104: the consuming app evicts after each launch, and each call read and decoded every record this device keeps
  /// to find the few it was given: 47,393 records and 19.1 MB of their JSON on a phone's store (2026-10-30), 13 of them
  /// with a copy. The storage snapshot decoded them all to count the copies.
  @Test("Eviction reads only the records it names, and the storage snapshot counts copies without reading records")
  func evictionAndTheSnapshotReadOnlyTheRecordsTheyNeed() async throws {
    let fixture = try await EvictionFixture(payload: payload, connects: false)
    defer { fixture.remove() }
    // One copy this device holds, beside 300 records of uploads that keep none.
    _ = try await fixture.runtime.storedFileContents(id: "held", name: "scribe/r/generation-1/audio.wav")
    for index in 0..<300 {
      _ = try await fixture.runtime.persistence.saveUploadedFileRecord(
        InstantStoredFile(
          id: "upload-\(index)",
          appID: "app-1",
          name: "scribe/r/generation-1/audio-chunks/\(index).wav",
          byteCount: 1_000,
          localPath: "",
          ownerUserID: "user-1",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index)),
          updatedAt: InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
        )
      )
    }

    await fixture.runtime.persistence.resetCacheResidencyMetricsForTesting()
    let evictions = try await fixture.runtime.evictStoredFiles(ids: ["upload-7"])
    expectNoDifference(evictions.map(\.outcome), [.kept(.notHeld)])
    let evictionReads = await fixture.runtime.persistence.cacheResidencyMetricsForTesting().storedFileRecordReadCount
    #expect(evictionReads == 1, "Evicting one file read \(evictionReads) records.")

    await fixture.runtime.persistence.resetCacheResidencyMetricsForTesting()
    let snapshot = try await fixture.runtime.storageSnapshot()
    expectNoDifference(snapshot.downloadedFileCount, 1)
    expectNoDifference(snapshot.downloadedFileSize, Int64(payload.count))
    let snapshotReads = await fixture.runtime.persistence.cacheResidencyMetricsForTesting().storedFileRecordReadCount
    #expect(snapshotReads == 0, "The storage snapshot read \(snapshotReads) records.")
  }

  /// #1105: the consuming app reads this device's whole list of file records after each launch (47,393 on a phone's
  /// store, 19.1 MB of JSON), and every record went through `JSONDecoder`. A record is read from its columns, and the
  /// fields only its JSON holds are read by SQLite: the same record the decoder made.
  @Test("This device's file records are read without decoding their JSON, and read as the decoder read them")
  func fileRecordsAreReadFromTheirColumns() async throws {
    let fixture = try await EvictionFixture(payload: payload, connects: false)
    defer { fixture.remove() }
    // A copy this device holds, and records of each shape an upload keeps.
    _ = try await fixture.runtime.storedFileContents(id: "held", name: "scribe/r/generation-1/audio.wav")
    let uploads = [
      InstantStoredFile(
        id: "plain", appID: "app-1", name: "a.wav", byteCount: 1, localPath: "", ownerUserID: "user-1",
        createdAt: InstantTimestamp(milliseconds: 1), updatedAt: InstantTimestamp(milliseconds: 2)
      ),
      InstantStoredFile(
        id: "typed", appID: "app-1", name: "b.png", contentType: "image/png", byteCount: 2_000_000_000_000,
        localPath: "", ownerUserID: "user-1", createdAt: InstantTimestamp(milliseconds: 3),
        updatedAt: InstantTimestamp(milliseconds: 4), remoteURL: URL(string: "https://files.example.test/b.png?x=1&y=2")
      ),
      InstantStoredFile(
        id: "quoted \"id\"", appID: "app-1", name: "c \"d\" ü/e.wav", contentType: "", byteCount: 0, localPath: "",
        ownerUserID: "", createdAt: InstantTimestamp(milliseconds: -5), updatedAt: InstantTimestamp(milliseconds: 6)
      ),
    ]
    for file in uploads {
      _ = try await fixture.runtime.persistence.saveUploadedFileRecord(file)
    }
    let decoded = try await fixture.runtime.persistence.storedFileRecordsDecodedFromJSONForTesting(appID: "app-1")
    #expect(decoded.count == 4)

    await fixture.runtime.persistence.resetCacheResidencyMetricsForTesting()
    let records = try await fixture.runtime.localStoredFiles()
    let byID = try await fixture.runtime.persistence.loadStoredFile(appID: "app-1", fileID: "typed")
    let byIDs = try await fixture.runtime.persistence.loadStoredFiles(appID: "app-1", ids: ["held", "quoted \"id\""])
    let metrics = await fixture.runtime.persistence.cacheResidencyMetricsForTesting()

    #expect(records == decoded)
    #expect(byID == decoded.first { $0.id == "typed" })
    #expect(byIDs.sorted { $0.id < $1.id } == decoded.filter { ["held", "quoted \"id\""].contains($0.id) }.sorted { $0.id < $1.id })
    #expect(metrics.storedFileRecordReadCount == 7)
    #expect(
      metrics.storedFileRecordJSONDecodeCount == 0,
      "\(metrics.storedFileRecordJSONDecodeCount) of \(metrics.storedFileRecordReadCount) records went through JSONDecoder."
    )
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
