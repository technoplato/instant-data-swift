// History:
// - 2026-11-19: added (#2209, #2551): a prune that removes only facts memory had let go installs the revision it moved.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #2209 (#2551): a prune batch that collects a closed result whose entities memory had already let go (#1500) deletes
/// their facts from disk only, and moves the store's revision to say so. The runtime installed a batch's revision only
/// when memory lost facts too, so the next local write found its installed revision behind SQLite's, re-read every
/// resident fact and rebuilt the hot store's indexes: 0.5-1 s inside a save on a phone (1.9.82), 355 samples of a
/// 3.6-hour Power Profiler trace (1.9.86). Memory already matched the disk for every fact it held.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantPruneRevisionInstallTests {
  /// A closed list is unloaded where it is and memory lets its three todos go; a second prune collects it, deleting
  /// their twelve facts from disk alone; then one local write. It reloads nothing, and memory shows what the disk holds.
  @Test
  func aLocalWriteAfterAPruneOfFactsOnlyTheDiskHeldDoesNotReloadTheStore() async throws {
    let url = try InstantStoredResultReloadTests.temporaryCacheURL()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-revision-install",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let keepAlive = await runtime.observeQueryLease(InstantStoredResultReloadTests.keepAliveTodosQuery)
    _ = try await runtime.connect()
    let keepAliveQuery = try await InstantStoredResultReloadTests.registeredQuery(number: 1, in: session)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: keepAliveQuery,
        processedTransactionID: "tx-keep-alive",
        result: InstantStoredResultReloadTests.todoResult([("todo-keep", "keep", 10)])
      )
    )
    let list = await runtime.observeQueryLease(TodoExample.query)
    let listQuery = try await InstantStoredResultReloadTests.registeredQuery(number: 2, in: session)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: listQuery,
        processedTransactionID: "tx-list",
        result: InstantStoredResultReloadTests.todoResult([("todo-1", "one", 1), ("todo-2", "two", 2), ("todo-3", "three", 3)])
      )
    )
    _ = try await InstantStoredResultReloadTests.emission(of: list.stream, operation: "show the server's list") {
      Set(["todo-1", "todo-2", "todo-3"]).isSubset(of: $0.values.map(\.id))
    }
    await list.cancel()
    try await InstantStoredResultReloadTests.waitForOp("remove-query", count: 1, in: session)

    // The closed list is unloaded where it is, and memory lets its todos go (#1500).
    _ = try await runtime.pruneLiveQueryResults(
      policy: InstantStoredResultReloadTests.productionPolicy,
      now: InstantStoredResultReloadTests.pruneTime
    )
    try await Self.expectMemoryShows(["todo-keep"], on: runtime, operation: "read memory after the unload")

    // The limits collect it: its facts leave the disk, which alone held them.
    let collected = try await runtime.pruneLiveQueryResults(
      policy: InstantLiveQueryResultPruningPolicy(maxAgeMilliseconds: 1),
      now: InstantStoredResultReloadTests.pruneTime
    )
    expectNoDifference(collected.removedOrphanedTripleCount, 12)
    expectNoDifference(
      try InstantUnloadInPlaceTests.scalar(
        url,
        "SELECT COUNT(*) FROM instant_triples WHERE entity_id IN ('todo-1', 'todo-2', 'todo-3')"
      ),
      0
    )
    await runtime.resetPersistenceCacheResidencyMetricsForTesting()

    _ = try await runtime.transact(
      operations: TodoExample.createOperations(
        id: "todo-local",
        text: "written here",
        createdAt: InstantTimestamp(milliseconds: 20),
        transactionID: "local-write"
      )
    )

    let metrics = await runtime.persistenceCacheResidencyMetricsForTesting()
    expectNoDifference(metrics.storeSnapshotReplacementCount, 0)
    expectNoDifference(metrics.fullStateReconstructionCount, 0)
    try await Self.expectMemoryShows(["todo-keep", "todo-local"], on: runtime, operation: "read memory after the write")
    expectNoDifference(
      Set(try SQLiteFile.strings(url, "SELECT DISTINCT entity_id FROM instant_triples")),
      ["todo-keep", "todo-local"]
    )

    await keepAlive.cancel()
    _ = try await runtime.closeConnection()
  }

  /// What the hot store shows for the todo list, read locally, as a set of ids.
  static func expectMemoryShows(
    _ ids: Set<String>,
    on runtime: InstantRuntime,
    operation: String
  ) async throws {
    let local = await runtime.observeLocallyLease(TodoExample.query)
    let emission = try await InstantStoredResultReloadTests.emission(of: local.stream, operation: operation) { _ in true }
    await local.cancel()
    expectNoDifference(Set(emission.values.map(\.id)), ids)
  }
}
