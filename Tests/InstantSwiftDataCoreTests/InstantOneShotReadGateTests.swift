// History
// 2026-10-25  #1134  Created. A one-shot read materialized its answer, hydrated it and wrote it to the query cache while
//                    holding the operation gate: 58 holds and about 1 s of gate a minute in #1074's recording exercise,
//                    holds of 1.2 s on a phone (build 121).

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A one-shot read answers from the device's store without the operation gate (#1134), as the local read does
/// (#1006): its answer is a local observation's first, and its query-cache row is written after it, only while no write
/// landed since the answer was read.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantOneShotReadGateTests {
  /// While another caller holds the operation gate, a one-shot read of the device's store answers with the rows it holds.
  @Test
  func aOneShotReadAnswersWhileAnotherCallerHoldsTheGate() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "one-shot-read-gate",
        persistenceURL: try InstantStoredResultReloadTests.temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    try await InstantOfflineRuntimeFixture.createTodo("held", in: runtime)
    let held = InstantPausePoint()
    let holder = Task {
      await runtime.holdingOperationGateForTesting { await held.pauseOnce() }
    }
    try await held.waitUntilEntered(within: .seconds(10))

    let rows = OneShotReadRows()
    let read = await InstantObserverRegistrationGateTests.finishes(within: .seconds(2)) {
      rows.set(try await runtime.query(TodoExample.query).map(\.id))
    }
    held.release()
    await holder.value
    try await read.work.value

    #expect(read.finished, "#1134: a one-shot read waited for the operation gate")
    #expect(rows.value == ["todo-held"], "the read answered \(rows.value)")
  }

  /// With no write meanwhile, a one-shot read still leaves its answer as the query's cached result.
  @Test
  func aOneShotReadStillCachesItsAnswer() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "one-shot-read-cache",
        persistenceURL: try InstantStoredResultReloadTests.temporaryCacheURL(),
        initialAttributes: TodoExample.attributes
      )
    )
    try await InstantOfflineRuntimeFixture.createTodo("cached", in: runtime)

    let answer = try await runtime.queryOnce(TodoExample.query)
    let cached = try await runtime.cachedQuery(TodoExample.query)

    #expect(cached?.emission.values == answer.values, "the cached result is the read's answer")
    #expect(answer.values.map(\.id) == ["todo-cached"])
  }
}

/// The rows a read answered, set from its task.
private final class OneShotReadRows: @unchecked Sendable {
  // SAFETY: `lock` guards `ids`.
  private let lock = NSLock()
  private var ids: [String] = []

  var value: [String] { lock.withLock { ids } }

  func set(_ ids: [String]) {
    lock.withLock { self.ids = ids }
  }
}
