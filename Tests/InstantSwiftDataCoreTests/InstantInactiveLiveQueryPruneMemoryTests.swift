import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Session prune must unload inactive querySubs (#044 / #155).
///
/// TypeScript `Reactor.js` `_cleanupQuery` calls `querySubs.unloadKey(hash)`
/// when a query has no listeners, even while `pendingMutations` exist.
/// Optimistic state lives on the mutation journal, not on stale pages.
///
/// Swift `pruneLiveQueryResults` used to union every persisted query key into
/// the protected set whenever the outbox had an optimistic overlay. Production
/// policy is `maxEntries: 1_000`, so inactive infinite-query pages never
/// unloaded during live speech. Mac soak of trial 3 then bootstrapped 92 keys
/// / 372 of 426 entities — scoped InstantStore load ≈ the full corpus.
///
/// When `preservingQueryKeys` is non-empty (session prune with active
/// listeners), unload keys that are not in that set. Bootstrap with an empty
/// preserving set keeps today's age/count + conservative-all so offline cache
/// survives until the app resubscribes. InstantRuntime is unedited.
@Suite(.serialized)
struct InstantInactiveLiveQueryPruneMemoryTests {
  private let pageSize = 32
  private let stalePageCount = 20

  @Test
  func sessionPruneUnloadsInactivePagesWhileOutboxHasOptimisticOverlay() async throws {
    let cacheURL = temporaryInactivePruneCacheURL("session-unload")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()

    let activeKey = "query-active-page"
    var queryResults: [InstantPersistedLiveQueryResult] = []
    var allTriples: [InstantTriple] = []
    for page in 0..<stalePageCount {
      let start = page * pageSize
      let triples = (start..<(start + pageSize)).flatMap(todoTriples(index:))
      allTriples.append(contentsOf: triples)
      queryResults.append(
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(
            key: page == 0 ? activeKey : "query-stale-page-\(page)",
            triples: triples,
            pageInfo: nil
          ),
          updatedAt: InstantTimestamp(milliseconds: Int64(page + 1))
        )
      )
    }

    let mutation = PendingMutation(
      id: "live-put-on-active-page",
      createdAt: InstantTimestamp(milliseconds: 100),
      transaction: InstantStoreTransaction(
        id: "live-put-on-active-page",
        operations: TodoExample.updateTextOperations(
          id: todoEntityID(0),
          text: "Pending live revision",
          updatedAt: InstantTimestamp(milliseconds: 100),
          transactionID: "live-put-on-active-page"
        )
      )
    )
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: TodoExample.attributes,
          triples: allTriples
        ),
        outbox: [mutation]
      ),
      queryResults: queryResults,
      storeChanged: true,
      outboxChanged: true,
      metadataKey: "test.inactive-live-query-prune",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 100),
      expectedStoreRevision: 0,
      expectedOutboxRevision: 0,
      expectedAttributeRevision: 0
    )
    expectNoDifference(didSave, true)

    let application = try await persistence.pruneLiveQueryResults(
      policy: InstantLiveQueryResultPruningPolicy(
        maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
        maxEntries: 1_000,
        maxTripleCount: 1_000_000
      ),
      now: InstantTimestamp(milliseconds: 101),
      preservingQueryKeys: [activeKey]
    )

    expectNoDifference(application.result.remainingQueryKeys, [activeKey])
    expectNoDifference(application.result.remainingEntryCount, 1)
    expectNoDifference(application.result.removedQueryKeys.count, stalePageCount - 1)

    let reloaded = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reloaded.bootstrap()
    let loaded = try await reloaded.loadCompactState()
    let hotEntityIDs = Set(loaded.snapshot.store.triples.map(\.entityID))
    expectNoDifference(hotEntityIDs.count, pageSize)
    expectNoDifference(
      hotEntityIDs,
      Set((0..<pageSize).map(todoEntityID))
    )
    print("session_prune_remaining_query_keys: \(application.result.remainingEntryCount)")
    print("session_prune_hot_store_entity_count: \(hotEntityIDs.count)")
  }

  @Test
  func bootstrapPruneWithEmptyPreservingKeysKeepsCacheWhenOutboxIsPending() async throws {
    let cacheURL = temporaryInactivePruneCacheURL("bootstrap-keep")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let first = persistedTodoResult(key: "query-one", index: 0)
    let second = persistedTodoResult(key: "query-two", index: 1)
    let mutation = PendingMutation(
      id: "bootstrap-pending",
      createdAt: InstantTimestamp(milliseconds: 3),
      transaction: InstantStoreTransaction(
        id: "bootstrap-pending",
        operations: TodoExample.updateTextOperations(
          id: todoEntityID(0),
          text: "Pending",
          updatedAt: InstantTimestamp(milliseconds: 3),
          transactionID: "bootstrap-pending"
        )
      )
    )
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: TodoExample.attributes,
          triples: first.triples + second.triples
        ),
        outbox: [mutation]
      ),
      queryResults: [first, second],
      storeChanged: true,
      outboxChanged: true,
      metadataKey: "test.inactive-live-query-bootstrap-keep",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 3),
      expectedStoreRevision: 0,
      expectedOutboxRevision: 0,
      expectedAttributeRevision: 0
    )
    expectNoDifference(didSave, true)

    let application = try await persistence.pruneLiveQueryResults(
      policy: InstantLiveQueryResultPruningPolicy(maxEntries: 0),
      now: InstantTimestamp(milliseconds: 4)
    )
    expectNoDifference(Set(application.result.remainingQueryKeys), [first.key, second.key])
    expectNoDifference(application.result.removedQueryKeys, [])
  }
}

private func todoEntityID(_ index: Int) -> String {
  "todo-\(index)"
}

private func todoTriples(index: Int) -> [InstantTriple] {
  let entityID = todoEntityID(index)
  let timestamp = InstantTimestamp(milliseconds: Int64(index + 1))
  return TodoExample.createOperations(
    id: entityID,
    text: "Todo \(index)",
    createdAt: timestamp,
    transactionID: "seed-\(entityID)"
  ).compactMap { operation in
    guard case let .insert(triple) = operation else { return nil }
    return triple
  }
}

private func persistedTodoResult(
  key: String,
  index: Int
) -> InstantPersistedLiveQueryResult {
  InstantPersistedLiveQueryResult(
    replacement: InstantLiveQueryResultReplacement(
      key: key,
      triples: todoTriples(index: index),
      pageInfo: nil
    ),
    updatedAt: InstantTimestamp(milliseconds: Int64(index + 1))
  )
}

private func temporaryInactivePruneCacheURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "InstantInactiveLiveQueryPruneMemoryTests-\(name)-\(UUID().uuidString)"
    )
    .appendingPathComponent("state.sqlite")
}
