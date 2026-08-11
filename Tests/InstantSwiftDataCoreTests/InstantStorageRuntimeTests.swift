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
    expectNoDifference(upload.sourceURL, sourceURL)
    expectNoDifference(upload.byteCount, Int64(body.count))
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

  @Test("Cancellation during upload stops without retry or local persistence")
  func cancelledUploadDoesNotPersist() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "instant-storage-runtime-cancellation-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sourceURL = directory.appendingPathComponent("recording.wav")
    try Data("audio".utf8).write(to: sourceURL)
    let recorder = CancellableStorageTransportRecorder()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "app-1",
        persistenceURL: directory.appendingPathComponent("cache.sqlite")
      ),
      storageTransport: recorder.client
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let task = Task {
      try await runtime.uploadFile(from: sourceURL)
    }
    try await recorder.waitUntilStarted()
    task.cancel()
    do {
      _ = try await instantLiveWithTimeout(
        operation: "finish cancelled storage upload transport",
        timeoutMilliseconds: 5_000,
        onAbandon: { task.cancel() }
      ) {
        try await task.value
      }
      Issue.record("Expected the cancelled upload to stop.")
    } catch is CancellationError {
    }

    let requests = await recorder.uploadRequests()
    expectNoDifference(requests.count, 1)
    let files = try await runtime.storedFiles()
    expectNoDifference(files, [])
  }

  @Test("Upload progress cancellation aborts synchronously and exactly joins the transport")
  func uploadProgressCancellationAbortsAndExactlyJoinsTransport() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "instant-storage-progress-exact-cancellation-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sourceURL = directory.appendingPathComponent("recording.wav")
    try Data("audio".utf8).write(to: sourceURL)
    var lifetimeProbe: StorageLifecycleLifetimeProbe? = StorageLifecycleLifetimeProbe()
    weak var weakLifetimeProbe = lifetimeProbe
    let transport = StorageCancellationIgnoringPreparedUpload(
      lifetimeProbe: try #require(lifetimeProbe)
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "storage-progress-exact-cancellation",
        persistenceURL: directory.appendingPathComponent("cache.sqlite")
      ),
      storageTransport: .preparedOperations(
        upload: { request in
          transport.operation(for: request)
        },
        delete: { _ in
          InstantStorageTransportOperation(
            run: { InstantStorageDeleteResponse(id: nil) },
            abort: {}
          )
        }
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")

    let upload = try await runtime.uploadFileProgressLease(from: sourceURL)
    let progressLog = StorageUploadProgressLog()
    let progressConsumer = Task { [stream = upload.stream] () -> String? in
      do {
        for try await progress in stream {
          await progressLog.append(progress)
        }
        return nil
      } catch {
        return String(describing: error)
      }
    }
    defer { progressConsumer.cancel() }
    try await instantLiveWithTimeout(
      operation: "wait for upload progress loading state",
      timeoutMilliseconds: 5_000,
      onAbandon: { progressConsumer.cancel() }
    ) {
      while await progressLog.count == 0 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    let loadingStates = await progressLog.states
    expectNoDifference(loadingStates, [.loading])
    try await instantLiveWithTimeout(
      operation: "wait for prepared storage upload transport",
      timeoutMilliseconds: 5_000
    ) {
      while !transport.didEnter {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    lifetimeProbe = nil
    #expect(weakLifetimeProbe != nil)

    let completion = StorageLifecycleCompletionProbe()
    let cancellation = Task {
      await upload.cancelAndWait()
      completion.record()
    }
    defer {
      cancellation.cancel()
      transport.releaseWithRemoteSuccess()
    }
    try await instantLiveWithTimeout(
      operation: "wait for synchronous storage upload abort",
      timeoutMilliseconds: 5_000,
      onAbandon: { cancellation.cancel() }
    ) {
      while transport.abortCount != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    expectNoDifference(completion.didComplete, false)
    let filesBeforeTransportRelease = try await runtime.storedFiles()
    expectNoDifference(filesBeforeTransportRelease, [])

    transport.releaseWithRemoteSuccess()
    try await instantLiveWithTimeout(
      operation: "join cancellation-insensitive storage upload transport",
      timeoutMilliseconds: 5_000,
      onAbandon: { cancellation.cancel() }
    ) {
      await cancellation.value
    }
    let progressError = try await instantLiveWithTimeout(
      operation: "finish upload progress after exact cancellation",
      timeoutMilliseconds: 5_000,
      onAbandon: { progressConsumer.cancel() }
    ) {
      await progressConsumer.value
    }

    expectNoDifference(completion.didComplete, true)
    expectNoDifference(transport.abortCount, 1)
    expectNoDifference(transport.runCompletionCount, 1)
    let filesAfterTransportRelease = try await runtime.storedFiles()
    expectNoDifference(
      filesAfterTransportRelease,
      [],
      "A remote response acquired after cancellation must not persist locally."
    )
    let progressAfterCancellation = await progressLog.states
    expectNoDifference(progressError, nil)
    expectNoDifference(
      progressAfterCancellation,
      [.loading],
      "A remote response acquired after cancellation must not publish success."
    )
    #expect(
      weakLifetimeProbe == nil,
      "A retained cancelled upload lease must release the completed transport graph."
    )
    withExtendedLifetime(upload) {}
    try FileManager.default.removeItem(at: directory)
  }

  @Test("Stored files retain the newest snapshot and exactly cancel a blocked live merge")
  func storedFilesNewestSnapshotAndExactLiveCancellation() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "instant-stored-files-exact-live-cancellation-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cleanupBarrier = StorageObservationCleanupBarrier()
    let mergeBarrier = StorageRemoteMergeBarrier(
      blockingFileCount: 2
    )
    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: storageLiveServerAttributes)
    ])
    let storageRecorder = StorageTransportRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: "stored-files-exact-live-cancellation",
      persistenceURL: directory.appendingPathComponent("cache.sqlite"),
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.onStandardQueryObservationCleanupStartedForTesting = {
      await cleanupBarrier.pause()
    }
    configuration.onStoredFilesRemoteSnapshotMergedForTesting = { fileCount in
      await mergeBarrier.inspectMerged(fileCount: fileCount)
    }
    configuration.onStoredFilesRemoteSnapshotPublishedForTesting = { fileCount in
      mergeBarrier.recordPublished(fileCount: fileCount)
    }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: configuration,
      storageTransport: storageRecorder.client
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    _ = try await instantLiveWithTimeout(
      operation: "connect stored-files live observation fixture",
      timeoutMilliseconds: 5_000
    ) {
      try await runtime.connect()
    }

    let setup = Task {
      try await runtime.observeStoredFilesLease()
    }
    defer {
      setup.cancel()
      cleanupBarrier.release()
      mergeBarrier.release()
    }
    try await instantLiveWithTimeout(
      operation: "wait for stored-files queryOnce registration",
      timeoutMilliseconds: 5_000,
      onAbandon: { setup.cancel() }
    ) {
      await liveSession.waitForSentMessageCount(2)
    }
    let queryOnceMessages = await liveSession.sentMessages()
    let storedFilesQuery = try #require(queryOnceMessages.last?.fields["q"])
    await liveSession.enqueue(
      liveReactorAddQueryOK(
        query: storedFilesQuery,
        processedTransactionID: "stored-files-query-once-empty",
        result: storageLiveQueryResult([])
      )
    )
    let observation = try await instantLiveWithTimeout(
      operation: "finish stored-files live observation setup",
      timeoutMilliseconds: 5_000,
      onAbandon: { setup.cancel() }
    ) {
      try await setup.value
    }
    try await instantLiveWithTimeout(
      operation: "wait for persistent stored-files live registration",
      timeoutMilliseconds: 5_000
    ) {
      await liveSession.waitForSentMessageCount(4)
    }

    let firstRemoteFile = StorageRemoteFileFixture(
      id: "remote-file-1",
      name: "01-first.txt",
      url: "https://storage.example.test/remote-file-1",
      contentType: "text/plain"
    )
    let secondRemoteFile = StorageRemoteFileFixture(
      id: "remote-file-2",
      name: "02-second.txt",
      url: "https://storage.example.test/remote-file-2",
      contentType: "text/plain"
    )
    await liveSession.enqueue(
      liveReactorAddQueryOK(
        query: storedFilesQuery,
        processedTransactionID: "stored-files-first-snapshot",
        result: storageLiveQueryResult([firstRemoteFile])
      )
    )
    try await mergeBarrier.waitUntilPublished(fileCount: 1)
    let filesLog = StoredFilesObservationLog()
    let filesConsumer = Task { [stream = observation.stream] in
      for await files in stream {
        await filesLog.append(files)
      }
    }
    defer { filesConsumer.cancel() }
    try await instantLiveWithTimeout(
      operation: "read newest complete stored-files snapshot",
      timeoutMilliseconds: 5_000,
      onAbandon: { filesConsumer.cancel() }
    ) {
      while await filesLog.count == 0 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    let snapshotsBeforeCancellation = await filesLog.snapshots
    expectNoDifference(
      snapshotsBeforeCancellation,
      [["01-first.txt"]],
      "The initial empty snapshot is superseded before the consumer starts."
    )

    await liveSession.enqueue(
      liveReactorAddQueryOK(
        query: storedFilesQuery,
        processedTransactionID: "stored-files-blocked-second-snapshot",
        result: storageLiveQueryResult([firstRemoteFile, secondRemoteFile])
      )
    )
    try await mergeBarrier.waitUntilBlocked()

    let firstCompletion = StorageLifecycleCompletionProbe()
    let secondCompletion = StorageLifecycleCompletionProbe()
    let firstCancellation = Task {
      await observation.cancelAndWait()
      firstCompletion.record()
    }
    let repeatedCancellation = Task {
      await observation.cancelAndWait()
      secondCompletion.record()
    }
    defer {
      firstCancellation.cancel()
      repeatedCancellation.cancel()
    }
    try await cleanupBarrier.waitUntilBlockingEntry()
    let storeCountWhileCleanupIsBlocked = await runtime.store.activeObservationCount()
    let liveKeysWhileCleanupIsBlocked = await runtime.liveActiveQueryKeysForTesting()
    expectNoDifference(storeCountWhileCleanupIsBlocked, 1)
    expectNoDifference(liveKeysWhileCleanupIsBlocked.count, 1)
    expectNoDifference(firstCompletion.didComplete, false)
    expectNoDifference(secondCompletion.didComplete, false)

    mergeBarrier.release()
    try await mergeBarrier.waitUntilReleasedMergeReturned()
    expectNoDifference(
      firstCompletion.didComplete,
      false,
      "Exact cancellation still owns the blocked live query cleanup."
    )
    cleanupBarrier.release()
    try await instantLiveWithTimeout(
      operation: "finish exact stored-files cancellation",
      timeoutMilliseconds: 5_000,
      onAbandon: {
        firstCancellation.cancel()
        repeatedCancellation.cancel()
      }
    ) {
      await firstCancellation.value
      await repeatedCancellation.value
    }
    try await instantLiveWithTimeout(
      operation: "finish stored-files consumer after exact cancellation",
      timeoutMilliseconds: 5_000,
      onAbandon: { filesConsumer.cancel() }
    ) {
      await filesConsumer.value
    }

    let finalStoreCount = await runtime.store.activeObservationCount()
    let finalLiveKeys = await runtime.liveActiveQueryKeysForTesting()
    let cleanupEntryCount = cleanupBarrier.entryCount
    expectNoDifference(finalStoreCount, 0)
    expectNoDifference(finalLiveKeys, Set<String>())
    expectNoDifference(cleanupEntryCount, 1)
    expectNoDifference(firstCompletion.didComplete, true)
    expectNoDifference(secondCompletion.didComplete, true)
    let snapshotsAfterCancellation = await filesLog.snapshots
    expectNoDifference(
      snapshotsAfterCancellation,
      [["01-first.txt"]],
      "Cancellation after merge acquisition must not publish the blocked newer snapshot."
    )
    _ = try await instantLiveWithTimeout(
      operation: "close stored-files live observation fixture",
      timeoutMilliseconds: 5_000
    ) {
      try await runtime.closeConnection()
    }
    try FileManager.default.removeItem(at: directory)
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

private actor CancellableStorageTransportRecorder {
  private var requests: [InstantStorageUploadRequest] = []

  nonisolated var client: InstantStorageTransportClient {
    InstantStorageTransportClient(
      upload: { request in
        try await self.upload(request)
      },
      delete: { _ in InstantStorageDeleteResponse(id: nil) }
    )
  }

  func upload(
    _ request: InstantStorageUploadRequest
  ) async throws -> InstantStorageUploadResponse {
    requests.append(request)
    while true {
      try Task.checkCancellation()
      await Task.yield()
    }
  }

  func waitUntilStarted() async throws {
    try await instantLiveWithTimeout(
      operation: "wait for cancellable storage upload transport",
      timeoutMilliseconds: 5_000
    ) {
      while await self.requests.isEmpty {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  func uploadRequests() -> [InstantStorageUploadRequest] {
    requests
  }
}

// SAFETY: `lock` protects the exact transport request, continuation, probe,
// abort count, and completion count. The transport continuation deliberately
// ignores Task cancellation so the test can prove synchronous abort plus an
// exact externally released join.
private final class StorageCancellationIgnoringPreparedUpload: @unchecked Sendable {
  private let lock = NSLock()
  private var lifetimeProbe: StorageLifecycleLifetimeProbe?
  private var request: InstantStorageUploadRequest?
  private var continuation: CheckedContinuation<Void, Never>?
  private var entered = false
  private var released = false
  private var aborts = 0
  private var runCompletions = 0

  init(lifetimeProbe: StorageLifecycleLifetimeProbe) {
    self.lifetimeProbe = lifetimeProbe
  }

  var didEnter: Bool {
    lock.withLock { entered }
  }

  var abortCount: Int {
    lock.withLock { aborts }
  }

  var runCompletionCount: Int {
    lock.withLock { runCompletions }
  }

  func operation(
    for request: InstantStorageUploadRequest
  ) -> InstantStorageTransportOperation<InstantStorageUploadResponse> {
    let capturedProbe = lock.withLock { () -> StorageLifecycleLifetimeProbe in
      let capturedProbe = lifetimeProbe!
      lifetimeProbe = nil
      return capturedProbe
    }
    return InstantStorageTransportOperation(
      run: { [capturedProbe] in
        let response = await self.run(request)
        withExtendedLifetime(capturedProbe) {}
        return response
      },
      abort: { self.abort() }
    )
  }

  private func run(
    _ request: InstantStorageUploadRequest
  ) async -> InstantStorageUploadResponse {
    lock.withLock {
      self.request = request
      entered = true
    }
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        guard !released else { return true }
        self.continuation = continuation
        return false
      }
      if resumeImmediately {
        continuation.resume()
      }
    }
    lock.withLock { runCompletions += 1 }
    return InstantStorageUploadResponse(id: "remote-file-after-cancellation")
  }

  private func abort() {
    lock.withLock { aborts += 1 }
  }

  func releaseWithRemoteSuccess() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !released else { return nil }
      released = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

// SAFETY: `lock` protects the completion bit shared between the exact cleanup
// task and its observer.
private final class StorageLifecycleCompletionProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var completed = false

  var didComplete: Bool {
    lock.withLock { completed }
  }

  func record() {
    lock.withLock { completed = true }
  }
}

// SAFETY: the class has no mutable state. Tests use weak ownership to prove a
// retained completed lease does not retain its former cleanup graph.
private final class StorageLifecycleLifetimeProbe: @unchecked Sendable {}

private actor StorageUploadProgressLog {
  private var values: [InstantFileUploadProgress] = []

  var count: Int {
    values.count
  }

  var states: [InstantStorageOperationState] {
    values.map(\.state)
  }

  func append(_ progress: InstantFileUploadProgress) {
    values.append(progress)
  }
}

private actor StoredFilesObservationLog {
  private(set) var snapshots: [[String]] = []

  var count: Int {
    snapshots.count
  }

  func append(_ files: [InstantStoredFile]) {
    snapshots.append(files.map(\.name))
  }
}

// SAFETY: `lock` protects the one cancellation-insensitive cleanup
// continuation and its entry count. Test waits use a separate bounded,
// cancellation-cooperative poll.
private final class StorageObservationCleanupBarrier: @unchecked Sendable {
  private let lock = NSLock()
  private let blockingEntry: Int
  private var continuation: CheckedContinuation<Void, Never>?
  private var entered = 0
  private var released = false

  init(blockingEntry: Int = 1) {
    self.blockingEntry = blockingEntry
  }

  var entryCount: Int {
    lock.withLock { entered }
  }

  func pause() async {
    let shouldBlock = lock.withLock { () -> Bool in
      entered += 1
      return entered == blockingEntry
    }
    guard shouldBlock else { return }
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        guard !released else { return true }
        self.continuation = continuation
        return false
      }
      if resumeImmediately {
        continuation.resume()
      }
    }
  }

  func waitUntilBlockingEntry() async throws {
    try await instantLiveWithTimeout(
      operation: "wait for stored-files cleanup to start",
      timeoutMilliseconds: 5_000
    ) {
      while self.entryCount < self.blockingEntry {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  func release() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !released else { return nil }
      released = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

// SAFETY: `lock` protects the published snapshot counts and the one selected
// cancellation-insensitive merge continuation. Every test-side wait is a
// separate cancellation-cooperative 5,000-millisecond poll.
private final class StorageRemoteMergeBarrier: @unchecked Sendable {
  private let lock = NSLock()
  private let blockingFileCount: Int
  private var publishedFileCounts: [Int] = []
  private var continuation: CheckedContinuation<Void, Never>?
  private var enteredBlockedMerge = false
  private var blockedMergeReturned = false
  private var released = false

  init(blockingFileCount: Int) {
    self.blockingFileCount = blockingFileCount
  }

  func inspectMerged(fileCount: Int) async {
    let shouldBlock = lock.withLock { () -> Bool in
      guard fileCount == blockingFileCount else { return false }
      enteredBlockedMerge = true
      return true
    }
    guard shouldBlock else { return }
    await withCheckedContinuation { continuation in
      let resumeImmediately = lock.withLock { () -> Bool in
        guard !released else { return true }
        self.continuation = continuation
        return false
      }
      if resumeImmediately {
        continuation.resume()
      }
    }
    lock.withLock { blockedMergeReturned = true }
  }

  func recordPublished(fileCount: Int) {
    lock.withLock { publishedFileCounts.append(fileCount) }
  }

  func waitUntilPublished(fileCount: Int) async throws {
    try await instantLiveWithTimeout(
      operation: "wait for published stored-files snapshot",
      timeoutMilliseconds: 5_000
    ) {
      while !self.lock.withLock({ self.publishedFileCounts.contains(fileCount) }) {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  func waitUntilBlocked() async throws {
    try await instantLiveWithTimeout(
      operation: "wait for blocked stored-files merge",
      timeoutMilliseconds: 5_000
    ) {
      while !self.lock.withLock({ self.enteredBlockedMerge }) {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  func waitUntilReleasedMergeReturned() async throws {
    try await instantLiveWithTimeout(
      operation: "wait for cancelled stored-files merge to return",
      timeoutMilliseconds: 5_000
    ) {
      while !self.lock.withLock({ self.blockedMergeReturned }) {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  func release() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      guard !released else { return nil }
      released = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume()
  }
}

private struct StorageRemoteFileFixture: Sendable {
  var id: String
  var name: String
  var url: String
  var contentType: String
}

private let storageLiveServerAttributes = [
  liveReactorServerAttr(id: "server-files-id", name: "id", namespace: "$files"),
  liveReactorServerAttr(id: "server-files-path", name: "path", namespace: "$files"),
  liveReactorServerAttr(id: "server-files-url", name: "url", namespace: "$files"),
  liveReactorServerAttr(
    id: "server-files-content-type",
    name: "content-type",
    namespace: "$files"
  ),
]

private func storageLiveQueryResult(
  _ files: [StorageRemoteFileFixture]
) -> [InstantLiveJSONValue] {
  let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
  return [
    .object([
      "data": .object([
        "datalog-result": .object([
          "join-rows": .array(
            files.map { file in
              .array([
                storageLiveJoinRow(
                  entityID: file.id,
                  attributeID: "server-files-id",
                  value: .string(file.id),
                  timestamp: timestamp
                ),
                storageLiveJoinRow(
                  entityID: file.id,
                  attributeID: "server-files-path",
                  value: .string(file.name),
                  timestamp: timestamp
                ),
                storageLiveJoinRow(
                  entityID: file.id,
                  attributeID: "server-files-url",
                  value: .string(file.url),
                  timestamp: timestamp
                ),
                storageLiveJoinRow(
                  entityID: file.id,
                  attributeID: "server-files-content-type",
                  value: .string(file.contentType),
                  timestamp: timestamp
                ),
              ])
            }
          ),
        ])
      ]),
      "child-nodes": .array([]),
    ])
  ]
}

private func storageLiveJoinRow(
  entityID: String,
  attributeID: String,
  value: InstantLiveJSONValue,
  timestamp: InstantTimestamp
) -> InstantLiveJSONValue {
  .array([
    .string(entityID),
    .string(attributeID),
    value,
    .number(Double(timestamp.milliseconds)),
  ])
}

extension Array {
  fileprivate var only: Element? {
    count == 1 ? self[0] : nil
  }
}
