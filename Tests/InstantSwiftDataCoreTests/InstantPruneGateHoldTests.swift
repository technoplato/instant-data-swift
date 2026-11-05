import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import SQLite3
import Testing

/// #303, item 6: pruning inactive live-query results holds the operation gate one bounded batch at a time.
///
/// In the experiment's large-store drop the first prune after 24 detail queries ended held the operation gate 5.8-13.2
/// s (the store fell from about 60,000 triples to 3,000), and the transact queued behind it was that lane's slowest
/// local write in 7 of 8 lanes. The prune now removes about `liveQueryResultPruneBatchTripleCount` result triples per
/// gate hold, so a local write waits for one batch, and the end state equals one prune's.
///
/// Since #1500 a closed query's result is unloaded where it is: its row is marked, its rows and facts stay on disk, and
/// under each batch's gates memory releases the entities no loaded result owns, no write waits on and no observer
/// shows. The prune unloads about as many result triples per gate hold as it removed.
@Suite(.serialized)
struct InstantPruneGateHoldTests {
  static let resultCount = 24
  static let todosPerResult = 150

  /// The open query (#1500): its filter shows no todo, so memory may release every closed result's entities, as a list
  /// left open shows none of the detail queries' rows that closed.
  static let openQuery = InstantQueryPlan(
    id: "prune-gate-hold.open",
    namespace: TodoExample.namespace,
    filters: [.equals(field: "isCompleted", value: .bool(true))]
  )

  /// Every todo the seed stores: each result's, the split entity and the entity with local data.
  static var seededTodoIDs: Set<String> {
    Set((0..<resultCount * todosPerResult).map { "prune-todo-\($0)" })
      .union(["prune-todo-1000000", "prune-todo-2000000"])
  }

  final class PausePoint: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var entered = false
    private var released = false
    private var storedBatchCount = 0

    func pauseOnce() async {
      let shouldPause = lock.withLock { () -> Bool in
        guard !entered else { return false }
        entered = true
        return !released
      }
      guard shouldPause else { return }
      await withCheckedContinuation { continuation in
        let resumeNow = lock.withLock { () -> Bool in
          if released { return true }
          self.continuation = continuation
          return false
        }
        if resumeNow { continuation.resume() }
      }
    }

    var didEnter: Bool { lock.withLock { entered } }

    func release() {
      let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
        released = true
        defer { self.continuation = nil }
        return self.continuation
      }
      continuation?.resume()
    }

    func recordBatch() { lock.withLock { storedBatchCount += 1 } }
    var batchCount: Int { lock.withLock { storedBatchCount } }
  }

  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-prune-gate-hold-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static func todoTriples(_ index: Int, text: String? = nil) -> [InstantTriple] {
    let id = "prune-todo-\(index)"
    let time = InstantTimestamp(milliseconds: 1_700_000_303_000 + Int64(index))
    return [
      InstantTriple(entityID: id, attributeID: "todos/id", value: .string(id), txID: "seed", txTime: time),
      InstantTriple(
        entityID: id,
        attributeID: "todos/text",
        value: .string(text ?? "seeded \(index)"),
        txID: "seed",
        txTime: time
      ),
      InstantTriple(entityID: id, attributeID: "todos/isCompleted", value: .bool(false), txID: "seed", txTime: time),
    ]
  }

  /// Seeds `resultCount` inactive results of `todosPerResult` todos each, plus the split and local-data entities.
  static func seed(at url: URL) async throws {
    let seededAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    let persistence = try SQLitePersistenceStore(fileURL: url)
    try await persistence.bootstrap()
    var results: [InstantPersistedLiveQueryResult] = []
    var triples: [InstantTriple] = []
    for result in 0..<resultCount {
      var resultTriples = (0..<todosPerResult).flatMap { todoTriples(result * todosPerResult + $0) }
      // One entity's facts are split across the first and the last result, which land in different batches.
      let split = todoTriples(1_000_000)
      if result == 0 { resultTriples.append(contentsOf: split.prefix(2)) }
      if result == resultCount - 1 { resultTriples.append(contentsOf: split.suffix(1)) }
      // Another entity has a fact no result owns, as data this device wrote that no query selects (#259).
      let local = todoTriples(2_000_000)
      if result == 1 { resultTriples.append(contentsOf: local.prefix(2)) }
      triples.append(contentsOf: resultTriples)
      results.append(
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(
            key: "inactive-result-\(result)",
            triples: resultTriples,
            pageInfo: nil
          ),
          // Recent, so the bootstrap prune's age cap keeps them for the prune under test.
          updatedAt: InstantTimestamp(milliseconds: seededAt + Int64(result))
        )
      )
    }
    triples.append(contentsOf: todoTriples(2_000_000).suffix(1))
    let saved = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples),
        outbox: []
      ),
      queryResults: results,
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.prune-gate-hold",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 100),
      expectedStoreRevision: 0,
      expectedOutboxRevision: 0,
      expectedAttributeRevision: 0
    )
    #expect(saved)
  }

  static func persistedResultCount(at url: URL) -> Int {
    countResults(at: url, where: "1")
  }

  /// How many stored results are loaded: not unloaded where they are (#1500).
  static func loadedResultCount(at url: URL) -> Int {
    countResults(at: url, where: "unloaded_at_ms IS NULL")
  }

  private static func countResults(at url: URL, where condition: String) -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return -1 }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT COUNT(*) FROM instant_live_query_results WHERE \(condition)",
        -1,
        &statement,
        nil
      ) == SQLITE_OK
    else { return -1 }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
    return Int(sqlite3_column_int64(statement, 0))
  }

  struct Outcome {
    var loadedResultsWhenTheWriteLanded: Int
    var batches: Int
    var pruned: InstantLiveQueryResultPruningResult
    var survivingTodoIDs: Set<String>
    /// The stored results' rows, and the entities `instant_triples` holds, once the prune ended (#1500).
    var storedResultCount: Int
    var storedTodoIDs: Set<String>
  }

  static func pruneWithAWriteQueued(batchTripleCount: Int?) async throws -> Outcome {
    let url = try temporaryCacheURL()
    try await seed(at: url)
    let pause = PausePoint()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-gate-hold",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveQueryResultPruneBatchTripleCount = batchTripleCount
    // #1107: every seeded result stays loaded at the launch, as the results of queries that closed in a session are; a
    // launch keeps only the newest ten.
    configuration.preloadedLiveQueryResultCount = .max
    configuration.onLiveQueryResultPruneActiveKeysCapturedForTesting = { _ in await pause.pauseOnce() }
    configuration.onLiveQueryResultPruneBatchFinishedForTesting = { _ in pause.recordBatch() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    // One live query is active, so every seeded result is inactive.
    let observation = await runtime.observeQueryLease(Self.openQuery)
    let policy = InstantLiveQueryResultPruningPolicy(
      maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
      maxEntries: 1_000,
      maxTripleCount: 1_000_000
    )
    let prune = Task { try await runtime.pruneLiveQueryResults(policy: policy, now: configuration.now()) }
    while !pause.didEnter { try await Task.sleep(for: .milliseconds(5)) }
    let write = Task {
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_303_999)
      try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-during-prune",
          operations: TodoExample.createOperations(
            id: "todo-written-during-prune",
            text: "dictation",
            createdAt: createdAt,
            transactionID: "tx-during-prune"
          )
        ),
        createdAt: createdAt
      )
      // #1500: an unloaded result keeps its row, marked; the loaded ones are the results the prune has yet to unload.
      return loadedResultCount(at: url)
    }
    while await runtime.operationGateWaiterCountForTesting() < 1 {
      try await Task.sleep(for: .milliseconds(5))
    }
    pause.release()
    let left = try await write.value
    let pruned = try await prune.value
    let snapshot = await runtime.store.snapshot()
    let storedResultCount = persistedResultCount(at: url)
    let storedTodoIDs = InstantPruneCostTests.Fixture.sqliteEntityIDs(at: url)
    await observation.cancel()
    _ = try? await runtime.closeConnection()
    return Outcome(
      loadedResultsWhenTheWriteLanded: left,
      batches: pause.batchCount,
      pruned: pruned,
      survivingTodoIDs: Set(snapshot.triples.map(\.entityID)),
      storedResultCount: storedResultCount,
      storedTodoIDs: storedTodoIDs
    )
  }

  @Test
  func aLocalWriteWaitsForOnePruneBatchNotTheWholePrune() async throws {
    let outcome = try await Self.pruneWithAWriteQueued(batchTripleCount: 2_000)
    // Each result holds about 450 triples, so a 2,000-triple batch unloads 4 of the 24 (#1500).
    #expect(
      outcome.loadedResultsWhenTheWriteLanded > 1,
      "the write landed after the first batch, not after all \(Self.resultCount) results were unloaded"
    )
    #expect(outcome.batches >= 5)
    // #1500: every closed result is unloaded where it is; the policy's limits collect none of them.
    expectNoDifference(outcome.pruned.unloadedQueryKeys.count, Self.resultCount)
    expectNoDifference(outcome.pruned.removedQueryKeys, [])
    expectNoDifference(outcome.pruned.remainingQueryKeys.count, 0, "only the active query's result could remain loaded")
    expectNoDifference(outcome.storedResultCount, Self.resultCount, "an unloaded result keeps its row")
    #expect(outcome.storedTodoIDs.isSuperset(of: Self.seededTodoIDs), "the unload deleted facts from disk")
    // Memory releases what no loaded result owns, no write waits on and no observer shows (#1145): the split entity
    // once both of its results are unloaded, and the entity with local data, whose rows stay on disk.
    #expect(!outcome.survivingTodoIDs.contains("prune-todo-1000000"))
    #expect(!outcome.survivingTodoIDs.contains("prune-todo-2000000"))
    #expect(!outcome.survivingTodoIDs.contains("prune-todo-0"))
    #expect(outcome.survivingTodoIDs.contains("todo-written-during-prune"))
  }

  @Test
  func withoutABatchBoundTheWriteWaitsForTheWholePrune() async throws {
    // The bound off is library-77's single hold: the write lands only after every result is unloaded.
    let outcome = try await Self.pruneWithAWriteQueued(batchTripleCount: nil)
    expectNoDifference(outcome.loadedResultsWhenTheWriteLanded, 0)
    expectNoDifference(outcome.batches, 1)
    // #1500: unloaded where they are, as the bounded prune leaves them.
    expectNoDifference(outcome.pruned.unloadedQueryKeys.count, Self.resultCount)
    expectNoDifference(outcome.pruned.removedQueryKeys, [])
    expectNoDifference(outcome.storedResultCount, Self.resultCount, "an unloaded result keeps its row")
    #expect(outcome.storedTodoIDs.isSuperset(of: Self.seededTodoIDs), "the unload deleted facts from disk")
    #expect(!outcome.survivingTodoIDs.contains("prune-todo-1000000"))
    #expect(!outcome.survivingTodoIDs.contains("prune-todo-2000000"))
  }
}
