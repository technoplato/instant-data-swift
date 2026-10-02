import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A persistence turn runs its SQL in one SQLite transaction (#403). These pin what a warm transact runs in, and that a
/// write turn keeps the guarantees each method's own transaction gave: a method that throws leaves nothing behind, and
/// what finished before it stays written.
@Suite(.serialized)
struct SQLiteTurnTransactionTests {
  /// A warm transact runs every statement inside two SQLite transactions: its reads, then its save and the status it
  /// changed. Before, each method opened its own transaction and each statement outside one ran in its own.
  @Test
  func aWarmTransactRunsInTwoSQLiteTransactions() async throws {
    let cacheURL = Self.cacheURL()
    defer { Self.remove(cacheURL) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "turn-transaction",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    func create(_ index: Int) async throws {
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
      try await runtime.transact(
        InstantStoreTransaction(
          id: "turn-\(index)",
          operations: TodoExample.createOperations(
            id: "turn-todo-\(index)",
            text: "todo \(index)",
            createdAt: createdAt,
            transactionID: "turn-\(index)"
          )
        ),
        createdAt: createdAt
      )
    }
    try await create(0)

    await runtime.persistence.setOpensTurnTransactionsForTesting(false)
    let beforeUnbatched = await runtime.persistence.transactionCountsForTesting()
    try await create(1)
    let afterUnbatched = await runtime.persistence.transactionCountsForTesting()
    await runtime.persistence.setOpensTurnTransactionsForTesting(true)
    try await create(2)
    let afterTurns = await runtime.persistence.transactionCountsForTesting()

    let unbatched = afterUnbatched - beforeUnbatched
    let turns = afterTurns - afterUnbatched
    let pendingCount = await runtime.pendingMutations().count
    expectNoDifference(turns, SQLiteTransactionCounts(began: 2, statementsOutsideTransaction: 0))
    #expect(unbatched.began > turns.began)
    #expect(unbatched.statementsOutsideTransaction > 0)
    expectNoDifference(pendingCount, 3)
  }

  /// The methods in a read turn share its one transaction.
  @Test
  func aReadTurnBeginsOneTransaction() async throws {
    let (store, cacheURL) = try await Self.bootstrappedStore()
    defer { Self.remove(cacheURL) }
    let before = await store.transactionCountsForTesting()

    let pendingCount = try await store.run(inOneTransaction: .read) { persistence -> Int in
      _ = try persistence.loadMetadataValue(key: "turn-probe")
      _ = try persistence.synchronizationBlocker()
      return try persistence.countOutboxMutations(status: .pending)
    }

    let after = await store.transactionCountsForTesting()
    expectNoDifference(pendingCount, 0)
    expectNoDifference(after - before, SQLiteTransactionCounts(began: 1, statementsOutsideTransaction: 0))
  }

  /// A method that throws inside a write turn leaves none of its writes behind, as its own transaction's rollback did,
  /// and what ran before it stays written, as it did when it committed on its own. The turn then rethrows.
  @Test
  func aWriteTurnKeepsWhatFinishedBeforeAMethodThrew() async throws {
    let (store, cacheURL) = try await Self.bootstrappedStore()
    defer { Self.remove(cacheURL) }
    struct Abort: Error {}
    let before = await store.transactionCountsForTesting()

    await #expect(throws: Abort.self) {
      try await store.run(inOneTransaction: .write) { persistence in
        try persistence.saveMetadataValue(
          "kept",
          key: "turn-kept",
          updatedAt: InstantTimestamp(milliseconds: 1)
        )
        try persistence.executeInTransactionForTesting(
          [
            """
            INSERT OR REPLACE INTO instant_sync_metadata (key, value, updated_at_ms)
            VALUES ('turn-dropped', 'dropped', 1)
            """
          ],
          thenThrowing: Abort()
        )
      }
    }

    let after = await store.transactionCountsForTesting()
    let kept = try await store.loadMetadataValue(key: "turn-kept")
    let dropped = try await store.loadMetadataValue(key: "turn-dropped")
    expectNoDifference(after.began - before.began, 1)
    expectNoDifference(kept, "kept")
    expectNoDifference(dropped, nil)
  }

  private static func cacheURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SQLiteTurnTransactionTests-\(UUID().uuidString).sqlite")
  }

  private static func bootstrappedStore() async throws -> (SQLitePersistenceStore, URL) {
    let cacheURL = Self.cacheURL()
    let store = try SQLitePersistenceStore(fileURL: cacheURL)
    try await store.bootstrap()
    return (store, cacheURL)
  }

  private static func remove(_ cacheURL: URL) {
    for suffix in ["", "-wal", "-shm"] {
      try? FileManager.default.removeItem(at: URL(fileURLWithPath: cacheURL.path + suffix))
    }
  }
}
