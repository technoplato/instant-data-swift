import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import SQLite3
import Testing

/// #654, #932 (2026-10-24): a file the device holds no record of, read or downloaded by id without a name, was found by a
/// one-shot query of every `$files` row the account can see, searched for that id. On build 121 that list was 9,455
/// files (75,640 facts, about 27 MB of result) and grew with every recording minute's audio chunk. Its answer took
/// longer than the query's 5 s, landed anyway (a server apply held the operation gate 2.3-5.8 s), and the next session
/// prune dropped the closed result again (3.8-6.0 s), once a minute while a recording's media downloaded. A lookup by id
/// now asks storage for that one file, so its cost does not grow with what the account has uploaded.
///
/// #1072 (2026-10-24): while nothing observes the device's files, an upload, a read by id and a delete read no other
/// file's record.
@Suite(.serialized)
struct InstantStoredFileLookupTests {
  private let payload = Data((0..<4_096).map { UInt8($0 % 239) })

  @Test(
    "A download by id with no name asks storage for that file alone, however many files the account holds",
    arguments: [40, 400]
  )
  func downloadByIDQueriesOnlyThatFile(accountFileCount: Int) async throws {
    let fixture = try await LookupFixture(payload: payload, accountFileCount: accountFileCount)
    defer { fixture.remove() }
    let wanted = fixture.files[7]
    let destination = fixture.directory.appendingPathComponent("media/picture.png")

    let mark = await fixture.addQueryCount()
    let downloading = Task {
      try await fixture.runtime.downloadStoredFile(id: wanted.id, to: destination)
    }
    defer { downloading.cancel() }
    let query = try await fixture.answerFilesQuery(after: mark)
    let file = try await instantLiveWithTimeout(
      operation: "download a stored file by id",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds,
      onAbandon: { downloading.cancel() }
    ) {
      try await downloading.value
    }

    // The question names the file.
    expectNoDifference(
      query,
      .object(["$files": .object(["$": .object(["where": .object(["id": .string(wanted.id)])])])])
    )
    // The bytes came from that file's own URL, and the record says what storage calls it.
    expectNoDifference(try Data(contentsOf: destination), payload)
    expectNoDifference(file.id, wanted.id)
    expectNoDifference(file.name, wanted.path)
    expectNoDifference(file.localPath, destination.path)
    let downloadedURLs = await fixture.storage.downloadedURLs
    expectNoDifference(downloadedURLs, [wanted.url])
    // The device holds that one file's facts, and the prune after the lookup drops only them.
    let stored = try await fixture.runtime.queryLocally(LookupFixture.everyFile)
    expectNoDifference(stored.values.map(\.id), [wanted.id])
    let pruned = try await fixture.runtime.pruneLiveQueryResults(policy: LookupFixture.pruningPolicy, now: fixture.now)
    expectNoDifference(pruned.removedOrphanedTripleCount, LookupFixture.attributeCount)
  }

  @Test("A read by id with no name asks storage for that file alone")
  func readByIDQueriesOnlyThatFile() async throws {
    let fixture = try await LookupFixture(payload: payload, accountFileCount: 40)
    defer { fixture.remove() }
    let wanted = fixture.files[12]

    let mark = await fixture.addQueryCount()
    let reading = Task {
      try await fixture.runtime.storedFileContents(id: wanted.id)
    }
    defer { reading.cancel() }
    let query = try await fixture.answerFilesQuery(after: mark)
    let contents = try await instantLiveWithTimeout(
      operation: "read a stored file by id",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds,
      onAbandon: { reading.cancel() }
    ) {
      try await reading.value
    }

    expectNoDifference(
      query,
      .object(["$files": .object(["$": .object(["where": .object(["id": .string(wanted.id)])])])])
    )
    expectNoDifference(contents.data, payload)
    expectNoDifference(contents.file.name, wanted.path)
    let downloadedURLs = await fixture.storage.downloadedURLs
    expectNoDifference(downloadedURLs, [wanted.url])
    let stored = try await fixture.runtime.queryLocally(LookupFixture.everyFile)
    expectNoDifference(stored.values.map(\.id), [wanted.id])
  }

  @Test("A file storage does not hold fails as it did: no remote file for that id")
  func fileStorageDoesNotHoldFails() async throws {
    let fixture = try await LookupFixture(payload: payload, accountFileCount: 40)
    defer { fixture.remove() }
    let destination = fixture.directory.appendingPathComponent("missing.png")

    let mark = await fixture.addQueryCount()
    let downloading = Task {
      try await fixture.runtime.downloadStoredFile(id: "not-in-storage", to: destination)
    }
    defer { downloading.cancel() }
    _ = try await fixture.answerFilesQuery(after: mark)
    let error = await #expect(throws: InstantError.self) {
      try await instantLiveWithTimeout(
        operation: "download a file storage does not hold",
        timeoutMilliseconds: InstantTestWait.hangMilliseconds,
        onAbandon: { downloading.cancel() }
      ) {
        try await downloading.value
      }
    }

    expectNoDifference(error?.code, .validationFailed)
    expectNoDifference(error?.message, "No remote file exists for id 'not-in-storage'.")
    expectNoDifference(FileManager.default.fileExists(atPath: destination.path), false)
    let downloadedURLs = await fixture.storage.downloadedURLs
    expectNoDifference(downloadedURLs, [])
  }

  // Build 123's first minutes: the one whole-list query left. Scribe deletes a chunk it uploaded when the chunk's row could
  // not be written, and the delete found its file in every file the account holds; it timed out at 5 s, so the chunk
  // also stayed in storage.
  @Test("A delete of a file this device uploaded asks no query: its own record names the file")
  func deleteOfAnUploadedFileAsksNoQuery() async throws {
    let fixture = try await LookupFixture(payload: payload, accountFileCount: 400)
    defer { fixture.remove() }
    let source = fixture.directory.appendingPathComponent("chunk.wav")
    try payload.write(to: source)
    let uploaded = try await fixture.runtime.uploadFile(from: source, name: "scribe/recording/generation-1/audio-chunks/000007.wav")
    let queriesBefore = await fixture.addQueryCount()

    let deleted = try await fixture.runtime.deleteStoredFile(id: uploaded.id)

    expectNoDifference(deleted.id, uploaded.id)
    expectNoDifference(deleted.name, "scribe/recording/generation-1/audio-chunks/000007.wav")
    let deletedPaths = await fixture.storage.deletedPaths
    expectNoDifference(deletedPaths, ["scribe/recording/generation-1/audio-chunks/000007.wav"])
    let queriesAfter = await fixture.addQueryCount()
    expectNoDifference(queriesAfter - queriesBefore, 0)
    let records = try await fixture.runtime.localStoredFiles()
    expectNoDifference(records.map(\.id), [])
  }

  @Test("A delete of a file this device holds no record of asks storage for that file alone")
  func deleteOfARemoteFileQueriesOnlyThatFile() async throws {
    let fixture = try await LookupFixture(payload: payload, accountFileCount: 400)
    defer { fixture.remove() }
    let wanted = fixture.files[3]

    let mark = await fixture.addQueryCount()
    let deleting = Task { try await fixture.runtime.deleteStoredFile(id: wanted.id) }
    defer { deleting.cancel() }
    let query = try await fixture.answerFilesQuery(after: mark)
    let deleted = try await instantLiveWithTimeout(
      operation: "delete a stored file by id",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds,
      onAbandon: { deleting.cancel() }
    ) {
      try await deleting.value
    }

    expectNoDifference(
      query,
      .object(["$files": .object(["$": .object(["where": .object(["id": .string(wanted.id)])])])])
    )
    expectNoDifference(deleted.id, wanted.id)
    let deletedPaths = await fixture.storage.deletedPaths
    expectNoDifference(deletedPaths, [wanted.path])
    let stored = try await fixture.runtime.queryLocally(LookupFixture.everyFile)
    expectNoDifference(stored.values.map(\.id), [wanted.id])
  }

  // #1072 (2026-10-24): every upload, delete and download by id read back every file record this device keeps, only to
  // hand them to observations of its files, whether one was open or not; the upload did it holding the operation gate.
  // Scribe opens none and uploads about eleven times a minute while recording (a 60 s audio chunk and 6 s media
  // segments); with 4,264 records on one phone, each upload decoded about 3 MB of JSON. One record no reader can decode
  // stands in for that read here: a call that reads every record fails on it, after its work is done, and a failed
  // upload deletes the file storage just took.
  @Test("While nothing observes the device's files, an upload, a read by id and a delete read no other file's record")
  func fileCallsReadNoOtherRecordWhileUnobserved() async throws {
    let fixture = try await LookupFixture(payload: payload, accountFileCount: 40)
    defer { fixture.remove() }
    let storeURL = await fixture.runtime.persistence.fileURLForTesting()
    try insertUndecodableFileRecord(into: storeURL)
    let source = fixture.directory.appendingPathComponent("chunk.wav")
    try payload.write(to: source)

    let uploaded = try await fixture.runtime.uploadFile(
      from: source,
      name: "scribe/recording/generation-1/audio-chunks/000008.wav"
    )
    let deletedAfterUpload = await fixture.storage.deletedPaths
    expectNoDifference(deletedAfterUpload, [])

    let wanted = fixture.files[9]
    let mark = await fixture.addQueryCount()
    let reading = Task { try await fixture.runtime.storedFileContents(id: wanted.id) }
    defer { reading.cancel() }
    _ = try await fixture.answerFilesQuery(after: mark)
    let contents = try await instantLiveWithTimeout(
      operation: "read a stored file by id beside an undecodable record",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds,
      onAbandon: { reading.cancel() }
    ) {
      try await reading.value
    }
    expectNoDifference(contents.data, payload)

    let deleted = try await fixture.runtime.deleteStoredFile(id: uploaded.id)
    expectNoDifference(deleted.id, uploaded.id)
    let deletedPaths = await fixture.storage.deletedPaths
    expectNoDifference(deletedPaths, ["scribe/recording/generation-1/audio-chunks/000008.wav"])
  }

  // The amplifier in the same loop: the whole list's answer outlasted its one-shot query's 5 s and was applied anyway,
  // its facts and result written under the operation gate for no query, then dropped again by the next prune.
  // Upstream `Reactor.js` drops an add-query-ok whose query it no longer holds (`querySubs` has no entry for its hash).
  @Test("An answer that lands after its one-shot query ended is not applied: no query wants it")
  func answerAfterTheOneShotQueryEndedIsNotApplied() async throws {
    let fixture = try await LookupFixture(payload: payload, accountFileCount: 400)
    defer { fixture.remove() }
    let mark = await fixture.addQueryCount()
    let listing = Task { try await fixture.runtime.storedFiles() }
    defer { listing.cancel() }
    let query = try await fixture.waitForSent("add-query", after: mark)
    // The one-shot query ends unanswered, as one that waited past its 5 s does, and removes its query.
    let removals = await fixture.sentCount("remove-query")
    listing.cancel()
    _ = await listing.result
    _ = try await fixture.waitForSent("remove-query", after: removals)

    // Its answer lands late, then the open query's next answer, which the runtime applies after it.
    await fixture.session.enqueue(
      liveReactorAddQueryOK(query: query, processedTransactionID: "late-list", result: lookupResult(fixture.files))
    )
    await fixture.session.enqueue(
      liveReactorAddQueryOK(query: fixture.openQueryAnswer, processedTransactionID: "after-late-list", result: lookupResult([]))
    )
    try await instantLiveWithTimeout(
      operation: "wait for the open query's answer after the late list",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) {
      // The runtime applies frames in order, so once the second frame's transaction is processed the first was handled.
      while try await fixture.runtime.syncState().processedTransactionID != "after-late-list" {
        try await Task.sleep(for: .milliseconds(5))
      }
    }

    let stored = try await fixture.runtime.queryLocally(LookupFixture.everyFile)
    expectNoDifference(stored.values.count, 0)
  }
}

/// A connected runtime whose scripted server holds `accountFileCount` files and answers each `$files` query as Instant
/// does: the rows its where clause selects, every row when it has none. One other query stays open, as an app's always
/// do, so a session prune unloads the results of closed queries.
private struct LookupFixture {
  struct RemoteFile: Sendable {
    var id: String
    var path: String
    var url: URL
  }

  static let attributeCount = 4
  static let everyFile = InstantQueryPlan(id: "lookup-test-every-file", namespace: "$files")
  static let openQuery = InstantQueryPlan(
    id: "lookup-test-open-query",
    namespace: "$files",
    filters: [.equals(field: "path", value: .string("open/query/selects/nothing"))]
  )
  static let pruningPolicy = InstantLiveQueryResultPruningPolicy(
    maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
    maxEntries: 1_000,
    maxTripleCount: 1_000_000
  )

  let directory: URL
  let files: [RemoteFile]
  let now = InstantTimestamp(milliseconds: 1_700_000_000_000)
  let openQuery: InstantQueryObservationLease
  let openQueryAnswer: InstantLiveJSONValue
  let runtime: InstantRuntime
  let session: LiveReactorParitySession
  let storage: LookupStorageRecorder

  init(payload: Data, accountFileCount: Int) async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-file-lookup-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let files = try (0..<accountFileCount).map { index in
      let id = String(format: "file-%05d", index)
      return RemoteFile(
        id: id,
        path: "scribe/recording/generation-1/pictures/\(id).png",
        url: try #require(URL(string: "https://storage.example.test/signed/\(id)?signature=s"))
      )
    }
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: lookupServerAttributes)])
    let storage = LookupStorageRecorder(directory: directory, payload: payload)
    var configuration = InstantRuntimeConfiguration(
      appID: "app-1",
      apiURI: try #require(URL(string: "https://api.example.test")),
      persistenceURL: directory.appendingPathComponent("cache.sqlite"),
      now: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration, storageTransport: storage.client)
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    _ = try await instantLiveWithTimeout(
      operation: "connect the file lookup fixture",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) {
      try await runtime.connect()
    }
    let mark = await Self.addQueryCount(session)
    let openQuery = await runtime.observeQueryLease(Self.openQuery)
    let openQueryAnswer = try await Self.answerFilesQuery(session: session, files: files, after: mark)
    self.directory = directory
    self.files = files
    self.openQuery = openQuery
    self.openQueryAnswer = openQueryAnswer
    self.runtime = runtime
    self.session = session
    self.storage = storage
  }

  func addQueryCount() async -> Int {
    await Self.addQueryCount(session)
  }

  /// Waits for the `add-query` after the first `mark`, answers it with the files its where clause selects, and returns
  /// its `q`.
  func answerFilesQuery(after mark: Int) async throws -> InstantLiveJSONValue {
    try await Self.answerFilesQuery(session: session, files: files, after: mark)
  }

  private static func addQueryCount(_ session: LiveReactorParitySession) async -> Int {
    await session.sentMessages().filter { $0.op == "add-query" }.count
  }

  func sentCount(_ op: String) async -> Int {
    await session.sentMessages().filter { $0.op == op }.count
  }

  /// Waits for the message `op` after the first `mark` of them, and returns its `q`.
  func waitForSent(_ op: String, after mark: Int) async throws -> InstantLiveJSONValue {
    try await instantLiveWithTimeout(
      operation: "wait for \(op)",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) { () -> InstantLiveJSONValue in
      while true {
        let sent = await session.sentMessages()
        let matching = sent.filter { $0.op == op }
        if matching.count > mark, let query = matching[mark].fields["q"] { return query }
        try await session.waitForSentMessageCount(sent.count + 1)
      }
    }
  }

  private static func answerFilesQuery(
    session: LiveReactorParitySession,
    files: [RemoteFile],
    after mark: Int
  ) async throws -> InstantLiveJSONValue {
    let query = try await instantLiveWithTimeout(
      operation: "wait for a $files query",
      timeoutMilliseconds: InstantTestWait.hangMilliseconds
    ) { () -> InstantLiveJSONValue in
      while true {
        let sent = await session.sentMessages()
        let queries = sent.filter { $0.op == "add-query" }
        if queries.count > mark, let query = queries[mark].fields["q"] { return query }
        try await session.waitForSentMessageCount(sent.count + 1)
      }
    }
    let selected: [RemoteFile]
    let clause = query.objectValue?["$files"]?.objectValue?["$"]?.objectValue?["where"]?.objectValue
    if case let .string(id)? = clause?["id"] {
      selected = files.filter { $0.id == id }
    } else if clause?["path"] != nil {
      selected = []
    } else {
      selected = files
    }
    await session.enqueue(
      liveReactorAddQueryOK(query: query, processedTransactionID: "files-answer-\(mark)", result: lookupResult(selected))
    )
    return query
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

/// Writes a file record no reader can decode beside the device's own, through a second connection to the store's file.
private func insertUndecodableFileRecord(into storeURL: URL) throws {
  var connection: OpaquePointer?
  defer { sqlite3_close(connection) }
  try #require(sqlite3_open_v2(storeURL.path, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
  sqlite3_busy_timeout(connection, 5_000)
  let insert = """
    INSERT INTO instant_files (app_id, file_id, name, created_at_ms, updated_at_ms, json)
    VALUES ('app-1', 'undecodable-record', 'undecodable.bin', 0, 0, '{"not": "a stored file"}')
    """
  try #require(sqlite3_exec(connection, insert, nil, nil, nil) == SQLITE_OK)
}

private actor LookupStorageRecorder {
  private let directory: URL
  private let payload: Data
  private(set) var downloadedURLs: [URL] = []
  private(set) var deletedPaths: [String] = []

  init(directory: URL, payload: Data) {
    self.directory = directory
    self.payload = payload
  }

  nonisolated var client: InstantStorageTransportClient {
    InstantStorageTransportClient(
      upload: { _ in InstantStorageUploadResponse(id: "uploaded-file-id") },
      delete: { request in
        await self.recordDelete(request.path)
        return InstantStorageDeleteResponse(id: nil)
      },
      downloadToFile: { request in
        await self.record(request.url)
        return try await self.writeTemporaryFile()
      },
      downloadFileToFile: { _ in
        throw InstantError(
          code: .networkFailed,
          operation: "download file",
          message: "This fixture's storage downloads by URL only.",
          recovery: "Download by id, without a name."
        )
      }
    )
  }

  private func record(_ url: URL) {
    downloadedURLs.append(url)
  }

  private func recordDelete(_ path: String) {
    deletedPaths.append(path)
  }

  private func writeTemporaryFile() throws -> URL {
    let url = directory.appendingPathComponent("tmp-\(UUID().uuidString)")
    try payload.write(to: url)
    return url
  }
}

private let lookupServerAttributes = [
  liveReactorServerAttr(id: "server-files-id", name: "id", namespace: "$files"),
  liveReactorServerAttr(id: "server-files-path", name: "path", namespace: "$files"),
  liveReactorServerAttr(id: "server-files-url", name: "url", namespace: "$files"),
  liveReactorServerAttr(id: "server-files-content-type", name: "content-type", namespace: "$files"),
]

private func lookupResult(_ files: [LookupFixture.RemoteFile]) -> [InstantLiveJSONValue] {
  let timestamp = Double(1_700_000_000_000)
  func row(_ entityID: String, _ attributeID: String, _ value: String) -> InstantLiveJSONValue {
    .array([.string(entityID), .string(attributeID), .string(value), .number(timestamp)])
  }
  return [
    .object([
      "data": .object([
        "datalog-result": .object([
          "join-rows": .array(
            files.map { file in
              .array([
                row(file.id, "server-files-id", file.id),
                row(file.id, "server-files-path", file.path),
                row(file.id, "server-files-url", file.url.absoluteString),
                row(file.id, "server-files-content-type", "image/png"),
              ])
            }
          )
        ])
      ]),
      "child-nodes": .array([]),
    ])
  ]
}
