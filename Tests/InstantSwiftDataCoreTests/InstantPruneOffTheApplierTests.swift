// History
// 2026-10-24  #1129  Created. The cadence prune ran inside the frame applier, holding the server-apply gate: in #1074's
//                    `prune-inline` exercise the refresh queued behind it applied after 1,815 ms against 45 ms for the
//                    one before it, and every acknowledgement queued behind waited for maintenance too.
// 2026-10-25  #1129  A result larger than a batch is released over several batches, marked until the last, and a
//                    release a crash cuts short is finished when the store opens again.
// 2026-10-25  #1129  A large closed result's ownership rows stay on its released row until the batches that check
//                    them delete them: its first batch deleted them all in one cascade (150 ms and a 96 ms commit of the
//                    `$files` batch's 397 ms).
// 2026-10-25  #1129  A prune batch waits for a server apply in progress: one that committed between the apply's seed
//                    and its plan made the refresh behind the cadence prune plan again, behind the next batch.

import CustomDump
import Foundation
import SQLite3
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

  /// A closed result larger than a batch keeps its ownership rows, on a released row out of its key's way, until the
  /// batches that check its facts delete them (#1129): the batch that unloaded it deleted every row at once by cascade,
  /// 149.72 ms of the `$files` batch's 397 ms in #1074's `prune` exercise, and a 96.28 ms commit for them.
  @Test
  func aLargeResultsOwnershipRowsGoWithTheBatchesThatCheckThem() async throws {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let firstQueryID = try #require(Self.queryID(of: "inactive-result-0", at: url))
    let firstRows = Self.ownershipRowCount(queryID: firstQueryID, at: url)
    let pause = InstantPausePoint()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-released-row",
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
    let rowsAfterFirstBatch = Self.ownershipRowCount(queryID: firstQueryID, at: url)
    pause.release()
    _ = try await prune.value
    let rowsAfterPrune = Self.ownershipRowCount(queryID: firstQueryID, at: url)
    let survivors = Set(await runtime.store.snapshot().triples.map(\.entityID))

    #expect(firstRows > 400, "the seed gave the first result \(firstRows) ownership rows")
    #expect(
      rowsAfterFirstBatch > 100,
      "#1129: the batch that unloaded the result deleted its ownership rows at once: \(rowsAfterFirstBatch) left of \(firstRows)"
    )
    #expect(rowsAfterPrune == 0, "the prune left \(rowsAfterPrune) ownership rows of the released result")
    #expect(Self.releasedRowCount(at: url) == 0, "a released row outlived its release")
    #expect(!survivors.contains("prune-todo-0"))
    #expect(!survivors.contains("prune-todo-1000000"), "the split entity goes once both its results do")
    #expect(survivors.contains("prune-todo-2000000"), "the entity with local data stays")

    await observation.cancel()
    _ = try? await runtime.closeConnection()
  }

  /// A prune batch never commits inside a server apply (#1129): one that did, between the apply's seed and its plan,
  /// made the apply plan again, behind the next batch. In #1074's `prune-inline` exercise the refresh queued behind the
  /// cadence prune waited for one batch at its snapshot and another at its retry: 217.81 ms against 44.22 ms for the
  /// refresh before it.
  @Test
  func aPruneBatchWaitsForAServerApplyInProgress() async throws {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let pause = InstantPausePoint()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-inside-server-apply",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    // Each attempt of the apply takes a seed; one made stale by a prune batch takes another.
    let seeds = InstantPruneBatchCounter()
    configuration.onServerApplySeedLoadedForTesting = { _ in
      seeds.record()
      await pause.pauseOnce()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(TodoExample.query)
    let now = configuration.now()

    // A server apply between its seed and its plan, as a frame is while it plans outside the operation gate.
    let applying = Task {
      try await runtime.applyServerTransaction(
        InstantStoreTransaction(
          id: "tx-server-during-prune",
          operations: [
            .insert(
              InstantTriple(
                entityID: "server-todo",
                attributeID: "todos/text",
                value: .string("from the server"),
                txID: "tx-server-during-prune",
                txTime: InstantTimestamp(milliseconds: 1_700_000_303_500)
              )
            )
          ]
        )
      )
    }
    try await pause.waitUntilEntered(within: .seconds(10))
    let pruned = await InstantObserverRegistrationGateTests.finishes(within: .seconds(4)) {
      _ = try await runtime.pruneLiveQueryResults(policy: InstantStoredResultReloadTests.productionPolicy, now: now)
    }
    pause.release()
    _ = try await applying.value
    try await pruned.work.value

    #expect(!pruned.finished, "#1129: the prune ran its batches while a server apply was between its seed and its plan")
    #expect(seeds.count == 1, "#1129: a prune batch inside the server apply made it take \(seeds.count) seeds")

    await observation.cancel()
    _ = try? await runtime.closeConnection()
  }

  /// A released row a crash left is checked whole when the store opens again (#1129): the batch that unloaded a large
  /// result re-keyed its row with every ownership row it held, and opening the store drops the facts no stored result
  /// owns, as the batches the crash took would have.
  @Test
  func aReleasedRowACrashLeftIsCheckedWhenTheStoreOpensAgain() async throws {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let firstQueryID = try #require(Self.queryID(of: "inactive-result-0", at: url))
    let now = InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    do {
      let persistence = try SQLitePersistenceStore(fileURL: url)
      try await persistence.bootstrap()
      // The batch that unloads the oldest result, larger than the budget, and nothing after it.
      let batch = try await persistence.liveQueryResultPruneBatch(
        policy: InstantStoredResultReloadTests.productionPolicy,
        now: now,
        preservingQueryKeys: ["query-open-elsewhere"],
        maximumRemovedTripleCount: 100,
        carriedReleasedIdentities: []
      )
      #expect(batch.removedQueryKeys == ["inactive-result-0"])
      #expect(batch.decodedQueryKeys.isEmpty, "#1129: the batch decoded a result it releases over later batches")
      let application = try await persistence.applyLiveQueryResultPruneBatch(
        batch,
        policy: InstantStoredResultReloadTests.productionPolicy,
        now: now,
        residentFacts: []
      )
      #expect(application?.leftReleasedRows == true)
      #expect(try await persistence.releasedLiveQueryResultCountForTesting() == 1)
      #expect(Self.ownershipRowCount(queryID: firstQueryID, at: url) > 400, "the released row kept its ownership rows")
    }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "prune-released-row-cut-short",
        persistenceURL: url,
        initialAttributes: TodoExample.attributes,
        liveTransport: .local
      )
    )
    let survivors = Set(await runtime.store.snapshot().triples.map(\.entityID))
    let releasedAfterOpen = try await runtime.persistence.releasedLiveQueryResultCountForTesting()

    #expect(!survivors.contains("prune-todo-0"), "#1129: a fact the interrupted release left unchecked stayed")
    #expect(!survivors.contains("prune-todo-149"), "#1129: a fact the interrupted release left unchecked stayed")
    #expect(survivors.contains("prune-todo-150"), "a result still stored keeps its facts")
    #expect(survivors.contains("prune-todo-1000000"), "the split entity stays while its other result does")
    #expect(survivors.contains("prune-todo-2000000"), "the entity with local data stays")
    #expect(releasedAfterOpen == 0, "#1129: opening the store left \(releasedAfterOpen) released rows")
    #expect(Self.ownershipRowCount(queryID: firstQueryID, at: url) == 0)

    _ = try? await runtime.closeConnection()
  }

  /// A marker an earlier build left for a release a crash cut short is still finished when the store opens (#1129):
  /// builds from 2026-10-25 to the released rows deleted a large result's row with its ownership rows, marked it, and
  /// checked its facts over later batches from memory.
  @Test
  func aMarkAnEarlierBuildLeftIsFinishedWhenTheStoreOpensAgain() async throws {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    // That build's first batch: the copy unloaded, the row and its ownership rows deleted, the mark written. The copy
    // is the result as JSON, which the store reads from its rows since #1426.
    let unloaded = try #require(try InstantStoredLiveQueryResultTests.storedResult(url, key: "inactive-result-0"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(decoding: try encoder.encode(unloaded), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
    let marked = Self.execute(
      [
        "PRAGMA foreign_keys = ON",
        """
        INSERT INTO instant_unloaded_live_query_results (query_key, triple_count, updated_at_ms, json)
        SELECT query_key, triple_count, updated_at_ms, '\(json)' FROM instant_live_query_results
        WHERE query_key = 'inactive-result-0'
        """,
        "DELETE FROM instant_live_query_results WHERE query_key = 'inactive-result-0'",
        """
        INSERT INTO instant_sync_metadata (key, value, updated_at_ms)
        VALUES ('\(SQLitePersistenceStore.pendingLiveQueryResultReleaseMarkerPrefix)inactive-result-0', '1', 0)
        """,
      ],
      at: url
    )
    #expect(marked)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "prune-marked-cut-short",
        persistenceURL: url,
        initialAttributes: TodoExample.attributes,
        liveTransport: .local
      )
    )
    let survivors = Set(await runtime.store.snapshot().triples.map(\.entityID))
    let markedAfterOpen = try await runtime.persistence.pendingLiveQueryResultReleaseKeysForTesting()

    #expect(!survivors.contains("prune-todo-0"), "#1129: a fact the marked release left unchecked stayed")
    #expect(survivors.contains("prune-todo-150"), "a result still stored keeps its facts")
    #expect(survivors.contains("prune-todo-1000000"), "the split entity stays while its other result does")
    #expect(survivors.contains("prune-todo-2000000"), "the entity with local data stays")
    #expect(markedAfterOpen.isEmpty, "#1129: opening the store left the mark: \(markedAfterOpen)")

    _ = try? await runtime.closeConnection()
  }

  /// The `query_id` of the stored result under `key`, read from the store's file.
  static func queryID(of key: String, at url: URL) -> Int64? {
    integer("SELECT query_id FROM instant_live_query_results WHERE query_key = '\(key)'", at: url)
  }

  /// How many ownership rows the stored result `queryID` holds, read from the store's file.
  static func ownershipRowCount(queryID: Int64, at url: URL) -> Int {
    Int(integer("SELECT COUNT(*) FROM instant_live_query_triples WHERE query_id = \(queryID)", at: url) ?? -1)
  }

  /// How many stored results are released rows waiting for their facts' check (#1129).
  static func releasedRowCount(at url: URL) -> Int {
    Int(integer("SELECT COUNT(*) FROM instant_live_query_results WHERE query_key LIKE 'released-result:%'", at: url) ?? -1)
  }

  /// Runs `statements` on the store's file, in one transaction; false when one fails.
  static func execute(_ statements: [String], at url: URL) -> Bool {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return false }
    defer { sqlite3_close(database) }
    guard sqlite3_exec(database, statements[0], nil, nil, nil) == SQLITE_OK,
      sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK
    else { return false }
    for statement in statements.dropFirst() where sqlite3_exec(database, statement, nil, nil, nil) != SQLITE_OK {
      sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
      return false
    }
    return sqlite3_exec(database, "COMMIT", nil, nil, nil) == SQLITE_OK
  }

  private static func integer(_ sql: String, at url: URL) -> Int64? {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return sqlite3_column_int64(statement, 0)
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
