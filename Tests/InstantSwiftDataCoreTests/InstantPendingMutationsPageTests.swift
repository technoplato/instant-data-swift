import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #445: Scribe's Sync view lists pending writes while a recording keeps writing. `pendingMutations()` decodes every
/// pending row under the runtime's operation gate; on Michael's iPhone after a relaunch that read held the gate for
/// 4.1 s. `pendingMutations(limit:)` reads only the oldest rows, in send order, from SQLite.
@Suite(.serialized)
struct InstantPendingMutationsPageTests {
  /// A runtime whose live transport never connects, so every write stays pending.
  static func offlineRuntime(
    _ name: String,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: "pending-page-\(name)",
      persistenceURL: try InstantSupersededReplayTests.temporaryCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: InstantLiveTransportClient.connectionAttempts { _ in
        throw InstantError(
          code: .networkFailed,
          operation: "open pending-page test session",
          message: "The test network is offline.",
          recovery: "None; the test keeps every write pending."
        )
      }
    )
    configuration.autoConnectLiveTransport = false
    configure(&configuration)
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  /// Creates `todo-<name>` as transaction `tx-<name>`.
  static func createTodo(_ name: String, in runtime: InstantRuntime) async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-\(name)",
        operations: TodoExample.createOperations(
          id: "todo-\(name)",
          text: name,
          createdAt: createdAt,
          transactionID: "tx-\(name)"
        )
      ),
      createdAt: createdAt
    )
  }

  static func createTodos(_ count: Int, in runtime: InstantRuntime) async throws {
    for index in 0..<count {
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
      _ = try await runtime.transact(
        InstantStoreTransaction(
          id: "tx-\(index)",
          operations: TodoExample.createOperations(
            id: "todo-\(index)",
            text: "todo \(index)",
            createdAt: createdAt,
            transactionID: "tx-\(index)"
          )
        ),
        createdAt: createdAt
      )
    }
  }

  @Test
  func theOldestPendingMutationsComeInSendOrderWithoutAQueueWideRead() async throws {
    let runtime = try await Self.offlineRuntime("oldest")
    try await Self.createTodos(5, in: runtime)
    let wideReadsBefore = await runtime.persistence.localMutationQueueWideReadCountForTesting()

    let page = await runtime.pendingMutations(limit: 3)
    expectNoDifference(page.map(\.id), ["tx-0", "tx-1", "tx-2"])
    #expect(page.allSatisfy { $0.status == .pending })
    let wideReadsAfter = await runtime.persistence.localMutationQueueWideReadCountForTesting()
    expectNoDifference(wideReadsAfter, wideReadsBefore, "only the page's rows are read")

    let everything = await runtime.pendingMutations(limit: 10)
    expectNoDifference(everything.map(\.id), ["tx-0", "tx-1", "tx-2", "tx-3", "tx-4"])
    let none = await runtime.pendingMutations(limit: 0)
    expectNoDifference(none, [])
    let total = await runtime.pendingMutationCount()
    expectNoDifference(total, 5)
  }

  @Test
  func aPageMatchesTheFullListsPrefix() async throws {
    let runtime = try await Self.offlineRuntime("prefix")
    try await Self.createTodos(4, in: runtime)
    let full = await runtime.pendingMutations()
    let page = await runtime.pendingMutations(limit: 2)
    expectNoDifference(page, Array(full.prefix(2)))
  }
}
