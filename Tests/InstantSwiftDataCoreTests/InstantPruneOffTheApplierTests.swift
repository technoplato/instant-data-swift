// History
// 2026-10-24  #1129  Created. The cadence prune ran inside the frame applier, holding the server-apply gate: in #1074's
//                    `prune-inline` exercise the refresh queued behind it applied after 1,815 ms against 45 ms for the
//                    one before it, and every acknowledgement queued behind waited for maintenance too.
// 2026-10-25  #1129  A result larger than a batch is released over several batches, marked until the last, and a
//                    release a crash cuts short is finished when the store opens again.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// The cadence prune runs in a task of its own (#1129), not inside the frame applier that applied the refresh which
/// triggered it: that refresh returns at once, and the frames behind it apply between the prune's batches.
///
/// Upstream `Reactor.js` collects unused query results lazily, at idle (`PersistedObject`'s garbage collection), never
/// inside `_handleReceive`. Swift prunes on its write cadence; this keeps the cadence and moves the work off the path
/// every server frame takes.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantPruneOffTheApplierTests {
  /// While the cadence prune a refresh triggered waits between two batches, that refresh has returned and the next
  /// refresh applies.
  @Test
  func aRefreshThatTriggersTheCadencePruneReturnsBeforeThePruneEnds() async throws {
    let pause = InstantPausePoint()
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-off-the-applier",
      persistenceURL: try InstantStoredResultReloadTests.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: .local
    )
    configuration.liveQueryResultPruningWriteInterval = 1
    configuration.onLiveQueryResultPruneBatchFinishedForTesting = { _ in await pause.pauseOnce() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(TodoExample.query)
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)

    let first = await InstantObserverRegistrationGateTests.finishes(within: .seconds(4)) {
      _ = try await runtime.applyLiveRefresh(Self.refresh(query: query, todo: "todo-1", transaction: "tx-prune-1"))
    }
    try await pause.waitUntilEntered(within: .seconds(10))
    let second = await InstantObserverRegistrationGateTests.finishes(within: .seconds(4)) {
      _ = try await runtime.applyLiveRefresh(Self.refresh(query: query, todo: "todo-2", transaction: "tx-prune-2"))
    }
    pause.release()
    try await first.work.value
    try await second.work.value

    #expect(first.finished, "#1129: the refresh waited for the cadence prune it triggered")
    #expect(second.finished, "#1129: the next refresh waited for a cadence prune between its batches")

    await observation.cancel()
    _ = try await runtime.closeConnection()
  }

  /// A result larger than a prune batch is released over several batches (#1129), each holding the operation gate for
  /// about a batch of facts, and the end state is one prune's: every result goes, an entity split across two results
  /// goes once both do, and an entity with local data stays. A batch took at least one whole result, so the closed
  /// `$files` list's 75,640 facts were one 1.7 s hold in #1074's `prune` exercise.
  @Test
  func aResultLargerThanABatchIsReleasedOverSeveralBatches() async throws {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let batches = InstantPruneBatchCounter()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-large-result",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    // Each seeded result holds about 450 facts.
    configuration.liveQueryResultPruneBatchTripleCount = 100
    configuration.onLiveQueryResultPruneBatchFinishedForTesting = { _ in batches.record() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(TodoExample.query)

    let pruned = try await runtime.pruneLiveQueryResults(
      policy: InstantStoredResultReloadTests.productionPolicy,
      now: configuration.now()
    )
    let survivors = Set(await runtime.store.snapshot().triples.map(\.entityID))

    #expect(
      batches.count >= InstantPruneGateHoldTests.resultCount * 4,
      "#1129: \(batches.count) batches for \(InstantPruneGateHoldTests.resultCount) results of about 450 facts each"
    )
    expectNoDifference(pruned.removedQueryKeys.count, InstantPruneGateHoldTests.resultCount)
    #expect(!survivors.contains("prune-todo-0"))
    #expect(!survivors.contains("prune-todo-1000000"), "the split entity goes once both its results do")
    #expect(survivors.contains("prune-todo-2000000"), "the entity with local data stays")

    await observation.cancel()
    _ = try? await runtime.closeConnection()
  }

  /// The prune's batch uses a result decoded on the read connection before the gate only while its row is the one read
  /// (#1129): a result the server restated since is decoded again under the gate, so the batch releases the facts the
  /// result holds now.
  @Test
  func aBatchDecodesAgainAResultRestatedSinceItsReadAhead() async throws {
    let persistence = try SQLitePersistenceStore(fileURL: try InstantStoredResultReloadTests.temporaryCacheURL())
    try await persistence.bootstrap()
    try await InstantStoredResultReloadTests.save(
      [InstantObserverRegistrationGateTests.closedResult(todos: 3, at: 1)],
      in: persistence
    )
    let readAhead = try await persistence.readConnection.storedLiveQueryResults(keys: ["query-closed"])
    #expect(readAhead.keys.sorted() == ["query-closed"])

    try await InstantStoredResultReloadTests.save(
      [InstantObserverRegistrationGateTests.closedResult(todos: 4, at: 2)],
      in: persistence
    )
    let batch = try await persistence.liveQueryResultPruneBatch(
      policy: InstantStoredResultReloadTests.productionPolicy,
      now: InstantTimestamp(milliseconds: 3),
      preservingQueryKeys: ["query-open-elsewhere"],
      maximumRemovedTripleCount: nil,
      carriedReleasedIdentities: [],
      predecoded: readAhead
    )

    #expect(batch.removedQueryKeys == ["query-closed"])
    #expect(
      batch.releasedEntityIDs == ["todo-0", "todo-1", "todo-2", "todo-3"],
      "#1129: the batch used a read-ahead of a row the server restated since: \(batch.releasedEntityIDs.sorted())"
    )
  }

  /// A batch that leaves a result's facts for later batches marks the result until the batch that checks the last of
  /// them (#1129): a crash between them leaves the mark for the store's next open.
  @Test
  func aBatchMarksTheResultWhoseFactsItLeftUntilTheLastAreChecked() async throws {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let pause = InstantPausePoint()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-release-marked",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveQueryResultPruneBatchTripleCount = 100
    configuration.onLiveQueryResultPruneBatchFinishedForTesting = { _ in await pause.pauseOnce() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(TodoExample.query)
    let now = configuration.now()

    let prune = Task {
      try await runtime.pruneLiveQueryResults(policy: InstantStoredResultReloadTests.productionPolicy, now: now)
    }
    try await pause.waitUntilEntered(within: .seconds(10))
    let markedBetweenBatches = try await runtime.persistence.pendingLiveQueryResultReleaseKeysForTesting()
    pause.release()
    _ = try await prune.value
    let markedAfter = try await runtime.persistence.pendingLiveQueryResultReleaseKeysForTesting()

    #expect(markedBetweenBatches == ["inactive-result-0"], "#1129: the batch left facts unchecked without a mark")
    #expect(markedAfter.isEmpty, "#1129: the mark outlived the release: \(markedAfter)")

    await observation.cancel()
    _ = try? await runtime.closeConnection()
  }

  /// A release a crash cut short is finished when the store opens again (#1129): the batch that unloaded a result and
  /// left its facts unchecked marked it, a collector meanwhile keeps the marked result's stored copy, and opening the
  /// store drops the facts no stored result owns, as the batches the crash took would have.
  @Test
  func aReleaseCutShortIsFinishedWhenTheStoreOpensAgain() async throws {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let now = InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    do {
      let persistence = try SQLitePersistenceStore(fileURL: url)
      try await persistence.bootstrap()
      // The first batch unloads the oldest result and checks none of its facts: what a crash right after it leaves.
      var batch = try await persistence.liveQueryResultPruneBatch(
        policy: InstantStoredResultReloadTests.productionPolicy,
        now: now,
        preservingQueryKeys: ["query-open-elsewhere"],
        maximumRemovedTripleCount: 100,
        carriedReleasedIdentities: []
      )
      #expect(batch.removedQueryKeys == ["inactive-result-0"])
      batch.releasedIdentities = []
      batch.pendingReleaseQueryKeys = batch.unloadedQueryKeys
      let application = try await persistence.applyLiveQueryResultPruneBatch(
        batch,
        policy: InstantStoredResultReloadTests.productionPolicy,
        now: now,
        residentFacts: []
      )
      #expect(application != nil)
      // A prune that would collect every unloaded copy keeps the marked one.
      let open = (1..<InstantPruneGateHoldTests.resultCount).map { "inactive-result-\($0)" }
      _ = try await persistence.liveQueryResultPruneBatch(
        policy: InstantLiveQueryResultPruningPolicy(maxAgeMilliseconds: 0, maxEntries: 0, maxTripleCount: 0),
        now: now,
        preservingQueryKeys: Set(open),
        maximumRemovedTripleCount: 100,
        carriedReleasedIdentities: []
      )
      let marked = try await persistence.pendingLiveQueryResultReleaseKeysForTesting()
      #expect(marked == ["inactive-result-0"], "#1129: the collector took the marked copy, or the mark went")
    }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "prune-release-cut-short",
        persistenceURL: url,
        initialAttributes: TodoExample.attributes,
        liveTransport: .local
      )
    )
    let survivors = Set(await runtime.store.snapshot().triples.map(\.entityID))
    let markedAfterOpen = try await runtime.persistence.pendingLiveQueryResultReleaseKeysForTesting()

    #expect(!survivors.contains("prune-todo-0"), "#1129: a fact the interrupted release left unchecked stayed")
    #expect(!survivors.contains("prune-todo-149"), "#1129: a fact the interrupted release left unchecked stayed")
    #expect(survivors.contains("prune-todo-150"), "a result still stored keeps its facts")
    #expect(survivors.contains("prune-todo-1000000"), "the split entity stays while its other result does")
    #expect(survivors.contains("prune-todo-2000000"), "the entity with local data stays")
    #expect(markedAfterOpen.isEmpty, "#1129: opening the store left the mark: \(markedAfterOpen)")

    _ = try? await runtime.closeConnection()
  }

  static func refresh(query: InstantLiveJSONValue, todo: String, transaction: String) -> InstantLiveRefreshOK {
    InstantLiveRefreshOK(
      clientEventID: "event-\(transaction)",
      processedTransactionID: transaction,
      attrs: liveReactorTodoServerAttrs,
      computations: [
        liveReactorTodoComputation(
          query: query,
          id: todo,
          text: todo,
          createdAt: InstantTimestamp(milliseconds: 1_700_000_001_129),
          processedTransactionID: transaction
        )
      ]
    )
  }
}

/// How many prune batches finished.
final class InstantPruneBatchCounter: @unchecked Sendable {
  // SAFETY: `lock` guards `batches`.
  private let lock = NSLock()
  private var batches = 0
  func record() { lock.withLock { batches += 1 } }
  var count: Int { lock.withLock { batches } }
}
