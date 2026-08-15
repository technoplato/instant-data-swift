import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantFailedMutationRetryWindowTests {
  @Test
  func oneHealthyConnectionRetriesOneHundredOneRowsAsFiftyFiftyOne() async throws {
    let cacheURL = try temporaryRetryWindowCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let terminal = (0..<50).map { index in
      retryWindowMutation(
        index: index,
        prefix: "connection-terminal",
        failureMessage: "permission denied"
      )
    }
    let retryable = (0..<101).map { index in
      retryWindowMutation(
        index: index + terminal.count,
        prefix: "connection-retryable",
        failureMessage: "could not resolve deployed attribute"
      )
    }
    try await saveRuntimePreparedRetryWindowOutbox(
      terminal + retryable,
      to: persistence
    )
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "failed-retry-window-connection",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetFailedMutationRetryMetricsForTesting()

    let status = try await runtime.connect()
    try await waitForFailedMutationRetryDrain(
      runtime.persistence,
      completedWindowCount: 3,
      failedMutationCount: 50
    )
    let pendingMutationCount = try await runtime.persistence.countOutboxMutations(status: .pending)
    let failedMutationCount = try await runtime.persistence.countOutboxMutations(status: .failed)
    let queueWideReadCount = await runtime.persistence.localMutationQueueWideReadCountForTesting()

    expectNoDifference(status.state, .opened)
    expectNoDifference(pendingMutationCount, 101)
    expectNoDifference(failedMutationCount, 50)
    expectNoDifference(queueWideReadCount, 0)
    let retryMetrics = await runtime.persistence.failedMutationRetryMetricsForTesting()
    expectNoDifference(retryMetrics.completedWindowCount, 3)
    expectNoDifference(retryMetrics.totalCandidateRowCount, 103)
    expectNoDifference(retryMetrics.totalDecodedBodyCount, 101)
    #expect(
      retryMetrics.totalDecodedBodyByteCount
        <= 3 * InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    expectNoDifference(retryMetrics.maximumCandidateRowCount, 51)
    expectNoDifference(retryMetrics.maximumDecodedBodyCount, 50)
    #expect(
      retryMetrics.maximumDecodedBodyByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    expectNoDifference(retryMetrics.lastDecodedBodyCount, 1)
    expectNoDifference(retryMetrics.candidateSortCount, 0)
    expectNoDifference(retryMetrics.candidateFullScanStepCount, 0)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func connectReturnsBeforeRetryWindowsAndDeliveryAlternatesAfterEachWindow() async throws {
    let cacheURL = try temporaryRetryWindowCacheURL()
    let seedPersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await seedPersistence.bootstrap()
    let retryable = (0..<101).map { index in
      retryWindowMutation(
        index: index,
        prefix: "connection-suspended",
        failureMessage: "could not resolve deployed attribute"
      )
    }
    try await saveRuntimePreparedRetryWindowOutbox(
      retryable,
      to: seedPersistence
    )
    await seedPersistence.simulateUnexpectedConnectionCloseForTesting()

    let liveSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "failed-retry-window-suspended-connection",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: liveSession.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let suspension = RetryWindowPumpSuspension()
    await runtime.persistence.setFailedMutationRetryWindowLoadedHookForTesting { _ in
      await suspension.suspendIfNeeded()
    }
    await runtime.persistence.resetDecodedOutboxBodyCount()
    await runtime.persistence.resetFailedMutationRetryMetricsForTesting()

    let connectTask = Task { try await runtime.connect() }
    do {
      try await waitForRetryWindowPumpEntry(suspension, count: 1)
      // If the assertion below exposes the old synchronous connect sweep, its
      // timeout task cannot finish until the suspended connect task unwinds.
      // Release just after the 500 ms proof boundary so that failure stays
      // deterministic and the serialized suite cannot hang.
      let failureRelease = Task {
        try? await Task.sleep(for: .milliseconds(750))
        guard !Task.isCancelled else { return }
        await suspension.releaseAll()
      }
      defer { failureRelease.cancel() }
      let status = try await instantLiveWithTimeout(
        operation: "prove connect returns before the suspended retry window commits",
        timeoutMilliseconds: 500
      ) {
        try await connectTask.value
      }
      failureRelease.cancel()
      expectNoDifference(status.state, .opened)
      let metricsWhileFirstWindowIsSuspended =
        await runtime.persistence.failedMutationRetryMetricsForTesting()
      expectNoDifference(metricsWhileFirstWindowIsSuspended.completedWindowCount, 0)
      let failedWhileFirstWindowIsSuspended =
        try await runtime.persistence.countOutboxMutations(status: .failed)
      expectNoDifference(failedWhileFirstWindowIsSuspended, 101)

      await suspension.release(through: 1)
      try await waitForRetryWindowPumpEntry(suspension, count: 2)
      let sentBeforeSecondRetryWindow = await liveSession.sentMessages()
        .filter { $0.op == "transact" }
        .compactMap(\.clientEventID)
      expectNoDifference(
        sentBeforeSecondRetryWindow,
        Array(retryable.prefix(50)).map(\.id)
      )

      await suspension.releaseAll()
      try await waitForFailedMutationRetryDrain(
        runtime.persistence,
        completedWindowCount: 3
      )
      let pendingMutationCount =
        try await runtime.persistence.countOutboxMutations(status: .pending)
      expectNoDifference(pendingMutationCount, 101)
      let queueWideReadCount =
        await runtime.persistence.localMutationQueueWideReadCountForTesting()
      expectNoDifference(queueWideReadCount, 0)
    } catch {
      await suspension.releaseAll()
      connectTask.cancel()
      await runtime.persistence.setFailedMutationRetryWindowLoadedHookForTesting(nil)
      throw error
    }

    await runtime.persistence.setFailedMutationRetryWindowLoadedHookForTesting(nil)
    _ = try? await runtime.closeConnection()
  }

  @Test
  func legacyUnknownCandidateBlocksRetryBeforeCorruptOrLaterRows() async throws {
    let seedPersistence = try await retryWindowPersistence(
      suffix: "corrupt-legacy",
      mutations: [
        retryWindowMutation(
          index: 0,
          prefix: "corrupt-legacy",
          failureMessage: "service unavailable"
        ),
        retryWindowMutation(
          index: 1,
          prefix: "corrupt-legacy",
          failureMessage: "transaction timed out",
          overlayState: nil
        ),
        retryWindowMutation(
          index: 2,
          prefix: "corrupt-legacy",
          failureMessage: "temporarily unavailable"
        ),
      ]
    )
    let fileURL = await seedPersistence.fileURLForTesting()
    await seedPersistence.simulateUnexpectedConnectionCloseForTesting()
    try executeRetryWindowSQL(
      at: fileURL,
      sql:
        "UPDATE instant_outbox SET json = '{', encoded_body_bytes = 1, mutation_revision = mutation_revision + 1 WHERE mutation_id = 'tx-corrupt-legacy-00000'"
    )
    let persistence = try SQLitePersistenceStore(fileURL: fileURL)
    try await persistence.bootstrap()
    await persistence.resetDecodedOutboxBodyCount()

    do {
      _ = try await persistence.retryAutomaticFailedMutationWindow(
          after: nil,
          excludingMutationIDs: []
        )
      Issue.record("An unproven active effect must block retry before any body decode.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      expectNoDifference(error.operation, "admit automatic failed-mutation retry")
      expectNoDifference(error.localID, "tx-corrupt-legacy-00001")
      expectNoDifference(error.localMutationDisposition, .retainedUnknown)
    }

    let pendingMutationCount = try await persistence.countOutboxMutations(status: .pending)
    let failedMutationCount = try await persistence.countOutboxMutations(status: .failed)
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    let corruptQuarantine = try await persistence.quarantinedOutboxBodyForTesting(
      id: "tx-corrupt-legacy-00000"
    )
    let blocker = try await persistence.synchronizationBlocker()
    let queueWideReadCount = await persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(pendingMutationCount, 0)
    expectNoDifference(failedMutationCount, 3)
    expectNoDifference(decodedBodyCount, 0)
    expectNoDifference(corruptQuarantine, nil)
    expectNoDifference(
      blocker,
      InstantSynchronizationBlocker(
        reason: .unknownOptimisticEffectReceipt,
        firstMutationID: "tx-corrupt-legacy-00001",
        blockedMutationCount: 1
      )
    )
    expectNoDifference(queueWideReadCount, 0)
  }

  @Test
  func tenThousandDisjointRowsDecodeOnlyTheAdmittedRetryWindow() async throws {
    let terminal = (0..<9_950).map { index in
      retryWindowMutation(
        index: index,
        prefix: "ten-thousand",
        failureMessage: "permission denied"
      )
    }
    let retryable = (9_950..<10_000).map { index in
      retryWindowMutation(
        index: index,
        prefix: "ten-thousand",
        failureMessage: "operation timed out"
      )
    }
    let persistence = try await retryWindowPersistence(
      suffix: "ten-thousand",
      mutations: terminal + retryable
    )
    await persistence.resetDecodedOutboxBodyCount()
    await persistence.resetFailedMutationRetryMetricsForTesting()

    let application = try #require(
      await persistence.retryAutomaticFailedMutationWindow(
        after: nil,
        excludingMutationIDs: []
      )
    )

    expectNoDifference(application.retriedMutations.map(\.id), retryable.map(\.id))
    expectNoDifference(application.decodedBodyCount, 50)
    #expect(
      application.decodedBodyByteCount
        <= InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
    )
    let decodedBodyCount = await persistence.currentDecodedOutboxBodyCount()
    let queueWideReadCount = await persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(decodedBodyCount, 50)
    expectNoDifference(queueWideReadCount, 0)
    let metrics = await persistence.failedMutationRetryMetricsForTesting()
    expectNoDifference(metrics.completedWindowCount, 1)
    expectNoDifference(metrics.totalCandidateRowCount, 50)
    expectNoDifference(metrics.maximumCandidateRowCount, 50)
    expectNoDifference(metrics.maximumDecodedBodyCount, 50)
    expectNoDifference(metrics.candidateSortCount, 0)
    expectNoDifference(metrics.candidateFullScanStepCount, 0)
  }

  @Test
  func revisionRaceCommitsNothingAndTheReloadedWindowRetries() async throws {
    let persistence = try await retryWindowPersistence(
      suffix: "revision-race",
      mutations: (0..<2).map { index in
        retryWindowMutation(
          index: index,
          prefix: "revision-race",
          failureMessage: "service unavailable"
        )
      }
    )
    let fileURL = await persistence.fileURLForTesting()
    let race = RetryWindowRace()
    await persistence.setFailedMutationRetryWindowLoadedHookForTesting { mutationIDs in
      guard await race.take(), let mutationID = mutationIDs.first else { return }
      try executeRetryWindowSQL(
        at: fileURL,
        sql:
          "UPDATE instant_outbox SET mutation_revision = mutation_revision + 1 WHERE mutation_id = '\(mutationID)'"
      )
    }

    let stale = try await persistence.retryAutomaticFailedMutationWindow(
      after: nil,
      excludingMutationIDs: []
    )

    #expect(stale == nil)
    let pendingAfterStale = try await persistence.countOutboxMutations(status: .pending)
    let failedAfterStale = try await persistence.countOutboxMutations(status: .failed)
    expectNoDifference(pendingAfterStale, 0)
    expectNoDifference(failedAfterStale, 2)

    let committed = try #require(
      await persistence.retryAutomaticFailedMutationWindow(
        after: nil,
        excludingMutationIDs: []
      )
    )
    expectNoDifference(committed.retriedMutations.map(\.id), [
      "tx-revision-race-00000",
      "tx-revision-race-00001",
    ])
    let pendingAfterRetry = try await persistence.countOutboxMutations(status: .pending)
    let queueWideReadCount = await persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(pendingAfterRetry, 2)
    expectNoDifference(queueWideReadCount, 0)
    await persistence.setFailedMutationRetryWindowLoadedHookForTesting(nil)
  }
}

private actor RetryWindowRace {
  private var isArmed = true

  func take() -> Bool {
    defer { isArmed = false }
    return isArmed
  }
}

private actor RetryWindowPumpSuspension {
  private var entryCount = 0
  private var releasedThroughEntry = 0
  private var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

  func suspendIfNeeded() async {
    entryCount += 1
    let entry = entryCount
    guard entry <= 2, releasedThroughEntry < entry else { return }
    await withCheckedContinuation { continuation in
      if releasedThroughEntry >= entry {
        continuation.resume()
      } else {
        releaseContinuations[entry] = continuation
      }
    }
  }

  func currentEntryCount() -> Int {
    entryCount
  }

  func release(through entry: Int) {
    releasedThroughEntry = max(releasedThroughEntry, entry)
    for key in releaseContinuations.keys.sorted() where key <= releasedThroughEntry {
      releaseContinuations.removeValue(forKey: key)?.resume()
    }
  }

  func releaseAll() {
    release(through: .max)
  }
}

private func retryWindowPersistence(
  suffix: String,
  mutations: [PendingMutation]
) async throws -> SQLitePersistenceStore {
  let persistence = try SQLitePersistenceStore(
    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-failed-retry-window-\(suffix)-\(UUID().uuidString).sqlite"
    )
  )
  try await persistence.bootstrap()
  try await saveRuntimePreparedRetryWindowOutbox(mutations, to: persistence)
  return persistence
}

private func saveRuntimePreparedRetryWindowOutbox(
  _ mutations: [PendingMutation],
  to persistence: SQLitePersistenceStore
) async throws {
  let emptyStore = try await persistence.loadCompactState()
  let didSave = try await persistence.saveOutbox(
    mutations,
    replacing: [],
    metadataEntries: [],
    expectedStoreRevision: emptyStore.storeRevision,
    expectedOutboxRevision: emptyStore.outboxRevision
  )
  expectNoDifference(didSave, true)
}

private func retryWindowMutation(
  index: Int,
  prefix: String,
  failureMessage: String,
  overlayState: InstantOptimisticOverlayState? = .applied
) -> PendingMutation {
  let id = String(format: "tx-%@-%05d", prefix, index)
  let timestamp = InstantTimestamp(milliseconds: Int64(index + 1))
  let triple = InstantTriple(
    entityID: "todo-\(prefix)-\(index)",
    attributeID: "todos/text",
    value: .string("value-\(index)"),
    txID: id,
    txTime: timestamp
  )
  var mutation = PendingMutation(
    id: id,
    createdAt: timestamp,
    transaction: InstantStoreTransaction(id: id, operations: [.insert(triple)]),
    status: .failed,
    failureMessage: failureMessage
  )
  mutation.failure = InstantMutationFailure(
    code: PendingMutation.failureCode(message: failureMessage),
    message: failureMessage
  )
  mutation.optimisticOverlayState = overlayState
  if overlayState != nil {
    mutation.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion
  }
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-\(id)",
    operations: [.retract(triple)]
  )
  return mutation
}

private func temporaryRetryWindowCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    "InstantFailedMutationRetryWindowTests-\(UUID().uuidString)"
  )
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func waitForFailedMutationRetryDrain(
  _ persistence: SQLitePersistenceStore,
  completedWindowCount: Int,
  failedMutationCount expectedFailedMutationCount: Int = 0
) async throws {
  try await instantLiveWithTimeout(
    operation: "wait for failed-mutation retry pump to drain",
    timeoutMilliseconds: 5_000
  ) {
    while true {
      let metrics = await persistence.failedMutationRetryMetricsForTesting()
      let failedMutationCount = try await persistence.countOutboxMutations(status: .failed)
      guard
        metrics.completedWindowCount < completedWindowCount
          || failedMutationCount != expectedFailedMutationCount
      else { return }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}

private func waitForRetryWindowPumpEntry(
  _ suspension: RetryWindowPumpSuspension,
  count: Int
) async throws {
  try await instantLiveWithTimeout(
    operation: "wait for suspended failed-mutation retry window \(count)",
    timeoutMilliseconds: 5_000
  ) {
    while await suspension.currentEntryCount() < count {
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}

private func executeRetryWindowSQL(at url: URL, sql: String) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw InstantError(
      code: .persistenceFailed,
      operation: "open failed-retry-window test database",
      message: "SQLite could not open the test database.",
      recovery: "Inspect the retry-window test database path."
    )
  }
  defer { sqlite3_close(database) }
  guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
    throw InstantError(
      code: .persistenceFailed,
      operation: "mutate failed-retry-window test database",
      message: database.flatMap(sqlite3_errmsg).map(String.init(cString:)) ?? "SQLite failed.",
      recovery: "Inspect the retry-window test SQL."
    )
  }
}
