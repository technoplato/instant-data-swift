// History
// 2026-10-24  #1129  Created. The cadence prune ran inside the frame applier, holding the server-apply gate: in #1074's
//                    `prune-inline` exercise the refresh queued behind it applied after 1,815 ms against 45 ms for the
//                    one before it, and every acknowledgement queued behind waited for maintenance too.

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
