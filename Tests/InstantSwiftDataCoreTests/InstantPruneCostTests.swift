// History
// 2026-10-23  #654  Created. The live-query prune rebuilt the whole store to drop the results no query watches: build
//                   118 held the operation gate 1,385 ms and 4,168 ms in it in its first minutes on an iPhone, and the
//                   energy ledger named it the top cost.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #654: pruning the results no open query watches costs in proportion to what it drops, not to the store.
///
/// Each prune batch copied the hot store (`InstantStore.snapshot()`), built a dictionary of every fact to find the ones
/// it drops, diffed the whole store into SQLite, and rebuilt every index from the copy (`replaceSnapshot`). On build
/// 118 the iPhone's prune held the operation gate 1,385 ms and 4,168 ms in its first minutes, a transact waited 1,740 ms
/// behind it, and the energy ledger named it the top cost (8.1% of a core). Garbage collection in a replica should cost
/// in proportion to the garbage: the results it drops, the facts they held, and the entities those facts belong to.
@Suite(.serialized)
struct InstantPruneCostTests {
  /// The production pruning policy (`InstantRuntimeConfiguration.liveQueryResultPruningPolicy`).
  static let productionPolicy = InstantLiveQueryResultPruningPolicy(
    maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
    maxEntries: 1_000,
    maxTripleCount: 1_000_000
  )
  static let inactiveResultCount = 24
  static let todosPerInactiveResult = 150

  /// The open query. Its stored result holds the large store; its filter matches no todo, so its observer stays cheap.
  static let openQuery = InstantQueryPlan(
    id: "prune-cost.open",
    namespace: TodoExample.namespace,
    filters: [.equals(field: "isCompleted", value: .bool(true))]
  )

  /// A 40,000-fact store kept by the open query, and 24 closed queries' results, about 10,800 facts, that the prune
  /// drops: it copies nothing the size of the store, and keeps and drops what it always did.
  @Test
  func aPruneOnAFortyThousandFactStoreCopiesNothingTheSizeOfTheStore() async throws {
    let fixture = try await Fixture.bootstrapped(storeTodoCount: 13_334)
    #expect(fixture.storeFactCount >= 40_000)

    let outcome = try await fixture.prune()

    // It keeps and drops what it did before #654.
    expectNoDifference(outcome.pruned.removedQueryKeys.sorted(), fixture.inactiveKeys.sorted())
    expectNoDifference(outcome.pruned.unloadedQueryKeys.sorted(), fixture.inactiveKeys.sorted())
    expectNoDifference(outcome.pruned.remainingQueryKeys, [fixture.openKey])
    expectNoDifference(outcome.pruned.removedOrphanedTripleCount, Self.inactiveResultCount * Self.todosPerInactiveResult * 3 + 3)
    #expect(outcome.batchCount >= 2, "the prune ran in bounded batches")
    expectNoDifference(outcome.storeEntityIDs, fixture.keptEntityIDs)
    expectNoDifference(outcome.sqliteEntityIDs, fixture.keptEntityIDs)
    expectNoDifference(outcome.storeFactCount, fixture.storeFactCount + 6)

    // It copied nothing the size of the store.
    expectNoDifference(outcome.fullStoreCopyCount, 0, "InstantStore.snapshot() copies every fact the store holds")
    expectNoDifference(
      outcome.residency,
      InstantPersistenceCacheResidencyMetrics(),
      "a full load, a state rebuilt from the whole store, or the hot store replaced and indexed again"
    )

    // The store it left answers queries as a store built from the same facts does: its indexes lost exactly the
    // dropped entities.
    let rebuilt = InstantStore(snapshot: outcome.storeSnapshot)
    for plan in Self.indexCheckPlans {
      let pruned = await fixture.runtime.store.materialize(plan)
      let expected = await rebuilt.materialize(plan)
      expectNoDifference(pruned, expected, "\(plan.id)")
    }
    await fixture.close()
  }

  /// Plans that read the namespace's entities, an indexed value and a cardinality-one indexed value.
  static let indexCheckPlans = [
    InstantQueryPlan(id: "prune-cost.all", namespace: TodoExample.namespace, order: InstantQueryOrder("text", .ascending)),
    InstantQueryPlan(
      id: "prune-cost.closed-text",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "text", value: .string("text of closed-todo-0"))]
    ),
    InstantQueryPlan(
      id: "prune-cost.kept-text",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "text", value: .string("text of store-todo-7"))]
    ),
    InstantQueryPlan(
      id: "prune-cost.open",
      namespace: TodoExample.namespace,
      filters: [.equals(field: "isCompleted", value: .bool(false))],
      order: InstantQueryOrder("text", .descending),
      limit: 50
    ),
  ]

  /// The longest hold of the operation gate, and the prune's CPU, at 4,000 and 40,000 facts: milliseconds either way,
  /// and about the same, because the prune drops the same results from both.
  @Test(.measurement)
  func aPruneHoldsTheGateForMillisecondsWhateverTheStoresSize() async throws {
    var measured: [(facts: Int, outcome: Fixture.Outcome)] = []
    for storeTodoCount in [1_334, 13_334] {
      let fixture = try await Fixture.bootstrapped(storeTodoCount: storeTodoCount)
      measured.append((fixture.storeFactCount, try await fixture.prune()))
      await fixture.close()
    }
    for (facts, outcome) in measured {
      print(
        """
        #654 prune at \(facts) facts: longest gate hold \(outcome.longestHold), batches \(outcome.batchCount), \
        whole prune \(outcome.duration), prune CPU \(outcome.pruneCPUMilliseconds) ms
        """
      )
    }
    let small = measured[0].outcome
    let large = measured[1].outcome
    #expect(
      large.longestHold < .milliseconds(250),
      "a write behind the prune at 40,000 facts waited \(large.longestHold)"
    )
    let ratio = large.longestHold / max(small.longestHold, .microseconds(1))
    // Before #654: 514 ms at 40,000 facts and 171 ms at 4,000 (3.0 times) on a Mac mini, in a debug build.
    #expect(ratio < 2, "the 40,000-fact store's longest hold was \(ratio) times the 4,000-fact store's")
  }

  // MARK: - Fixture

  struct Fixture {
    var runtime: InstantRuntime
    var url: URL
    var holds: BatchHolds
    var observation: InstantQueryObservationLease
    var openKey: String
    var inactiveKeys: [String]
    var keptEntityIDs: Set<String>
    var storeFactCount: Int

    struct Outcome {
      var pruned: InstantLiveQueryResultPruningResult
      var batchCount: Int
      var longestHold: Duration
      var duration: Duration
      var pruneCPUMilliseconds: Double
      var fullStoreCopyCount: Int
      var residency: InstantPersistenceCacheResidencyMetrics
      var storeEntityIDs: Set<String>
      var storeFactCount: Int
      var sqliteEntityIDs: Set<String>
      var storeSnapshot: InstantStoreSnapshot
    }

    /// Seeds a store of `storeTodoCount` todos (3 facts each) that the open query's result holds, and the closed
    /// queries' results, then starts a runtime on it with the open query observed.
    ///
    /// Each closed result holds 150 todos no other result holds. Three entities test the rules the prune keeps: one
    /// split between the first and the last closed result (dropped once both are), one with a fact no result holds
    /// (data this device wrote, kept whole, #259), and one the open result holds too (kept).
    static func bootstrapped(storeTodoCount: Int) async throws -> Fixture {
      let url = try InstantTestScratch.directory("instant-prune-cost").appendingPathComponent("instant.sqlite")
      let openKey = try InstantLiveQueryEncoder.registrationKey(for: InstantLiveQueryEncoder.encode(openQuery))
      let seededAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
      var results: [InstantPersistedLiveQueryResult] = []
      var storeTriples: [InstantTriple] = []

      let shared = todoTriples("shared-todo")
      let openTriples = (0..<storeTodoCount).flatMap { todoTriples("store-todo-\($0)") } + shared
      storeTriples += openTriples
      results.append(
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(key: openKey, triples: openTriples, pageInfo: nil),
          updatedAt: InstantTimestamp(milliseconds: seededAt)
        )
      )

      let split = todoTriples("split-todo")
      let local = todoTriples("local-todo")
      var inactiveKeys: [String] = []
      for result in 0..<inactiveResultCount {
        var triples = (0..<todosPerInactiveResult).flatMap {
          todoTriples("closed-todo-\(result * todosPerInactiveResult + $0)")
        }
        if result == 0 { triples += split.prefix(2) }
        if result == inactiveResultCount - 1 { triples += split.suffix(1) }
        if result == 1 { triples += local.prefix(2) }
        if result == 2 { triples += shared }
        storeTriples += triples.filter { $0.entityID != "shared-todo" }
        let key = "closed-result-\(result)"
        inactiveKeys.append(key)
        results.append(
          InstantPersistedLiveQueryResult(
            replacement: InstantLiveQueryResultReplacement(key: key, triples: triples, pageInfo: nil),
            updatedAt: InstantTimestamp(milliseconds: seededAt + 1 + Int64(result))
          )
        )
      }
      // The local todo's last fact is one no result holds.
      storeTriples += local.suffix(1)

      let persistence = try SQLitePersistenceStore(fileURL: url)
      try await persistence.bootstrap()
      let saved = try await persistence.saveLiveRefresh(
        InstantPersistenceSnapshot(
          store: InstantStoreSnapshot(attributes: TodoExample.attributes, triples: storeTriples),
          outbox: []
        ),
        queryResults: results,
        storeChanged: true,
        outboxChanged: false,
        metadataKey: "test.prune-cost",
        metadataValue: "seeded",
        metadataUpdatedAt: InstantTimestamp(milliseconds: 100),
        expectedStoreRevision: 0,
        expectedOutboxRevision: 0,
        expectedAttributeRevision: 0
      )
      #expect(saved)
      await persistence.simulateUnexpectedConnectionCloseForTesting()

      let holds = BatchHolds()
      let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
      var configuration = InstantRuntimeConfiguration(
        appID: "prune-cost",
        persistenceURL: url,
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
      configuration.autoConnectLiveTransport = false
      configuration.onLiveQueryResultPruneActiveKeysCapturedForTesting = { _ in holds.batchStarted() }
      configuration.onLiveQueryResultPruneBatchFinishedForTesting = { _ in holds.batchFinished() }
      let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
      let observation = await runtime.observeQueryLease(openQuery)

      var keptEntityIDs = Set((0..<storeTodoCount).map { "store-todo-\($0)" })
      keptEntityIDs.formUnion(["shared-todo", "local-todo"])
      return Fixture(
        runtime: runtime,
        url: url,
        holds: holds,
        observation: observation,
        openKey: openKey,
        inactiveKeys: inactiveKeys,
        keptEntityIDs: keptEntityIDs,
        storeFactCount: storeTodoCount * 3
      )
    }

    func prune() async throws -> Outcome {
      await runtime.resetPersistenceCacheResidencyMetricsForTesting()
      await runtime.store.resetFullCopyCountForTesting()
      let cpuBefore = InstantEnergyMeter.snapshot()[.prune].cpuNanoseconds
      let started = ContinuousClock.now
      let pruned = try await runtime.pruneLiveQueryResults(policy: productionPolicy, now: runtime.configuration.now())
      let duration = started.duration(to: .now)
      let cpu = InstantEnergyMeter.snapshot()[.prune].cpuNanoseconds - cpuBefore
      // Read before the snapshot below, which is itself a full copy.
      let fullStoreCopyCount = await runtime.store.fullCopyCountForTesting
      let residency = await runtime.persistenceCacheResidencyMetricsForTesting()
      let snapshot = await runtime.store.snapshot()
      return Outcome(
        pruned: pruned,
        batchCount: holds.count,
        longestHold: holds.longest,
        duration: duration,
        pruneCPUMilliseconds: Double(cpu) / 1_000_000,
        fullStoreCopyCount: fullStoreCopyCount,
        residency: residency,
        storeEntityIDs: Set(snapshot.triples.map(\.entityID)),
        storeFactCount: snapshot.triples.count,
        sqliteEntityIDs: Self.sqliteEntityIDs(at: url),
        storeSnapshot: snapshot
      )
    }

    func close() async {
      await observation.cancel()
      _ = try? await runtime.closeConnection()
    }

    static func todoTriples(_ id: String) -> [InstantTriple] {
      let time = InstantTimestamp(milliseconds: 1_700_000_654_000)
      return [
        InstantTriple(entityID: id, attributeID: "todos/id", value: .string(id), txID: "seed", txTime: time),
        InstantTriple(entityID: id, attributeID: "todos/text", value: .string("text of \(id)"), txID: "seed", txTime: time),
        InstantTriple(entityID: id, attributeID: "todos/isCompleted", value: .bool(false), txID: "seed", txTime: time),
      ]
    }

    static func sqliteEntityIDs(at url: URL) -> Set<String> {
      var database: OpaquePointer?
      guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
      defer { sqlite3_close(database) }
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(database, "SELECT DISTINCT entity_id FROM instant_triples", -1, &statement, nil)
        == SQLITE_OK
      else { return [] }
      defer { sqlite3_finalize(statement) }
      var entityIDs: Set<String> = []
      while sqlite3_step(statement) == SQLITE_ROW {
        if let text = sqlite3_column_text(statement, 0) { entityIDs.insert(String(cString: text)) }
      }
      return entityIDs
    }
  }

  /// How long each prune batch held the operation gate: from the batch's first step under the gate
  /// (`onLiveQueryResultPruneActiveKeysCapturedForTesting`) to its release (`onLiveQueryResultPruneBatchFinishedForTesting`).
  final class BatchHolds: @unchecked Sendable {
    // SAFETY: `lock` protects `startedAt` and `holds`; the prune's hooks call in from any thread.
    private let lock = NSLock()
    private var startedAt: ContinuousClock.Instant?
    private var holds: [Duration] = []

    func batchStarted() {
      lock.withLock { startedAt = .now }
    }

    func batchFinished() {
      lock.withLock {
        if let startedAt { holds.append(startedAt.duration(to: .now)) }
        startedAt = nil
      }
    }

    var count: Int { lock.withLock { holds.count } }
    var longest: Duration { lock.withLock { holds.max() ?? .zero } }
  }
}
