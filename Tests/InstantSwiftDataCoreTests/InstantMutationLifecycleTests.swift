import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantMutationLifecycleTests {
  @Test
  func durableConfirmationPublishesTransactionSpecificAcceptance() async throws {
    let runtime = try await mutationLifecycleRuntime("accepted")
    let lifecycle = try await runtime.observeMutationLifecycle(id: "tx-accepted")
    var iterator = lifecycle.makeAsyncIterator()
    let initial = await iterator.next()
    expectNoDifference(initial, .waiting)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-accepted",
        operations: TodoExample.createOperations(
          id: "todo-accepted",
          text: "Optimistic",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_000),
          transactionID: "tx-accepted"
        )
      )
    )
    _ = try await runtime.confirmMutation(id: "tx-accepted")

    guard case let .serverAccepted(mutation) = await iterator.next() else {
      Issue.record("Expected transaction-specific server acceptance.")
      return
    }
    expectNoDifference(mutation.id, "tx-accepted")
    expectNoDifference(mutation.status, .confirmed)
  }

  @Test
  func durableFailurePublishesTransactionSpecificFailure() async throws {
    let runtime = try await mutationLifecycleRuntime("failed")
    let lifecycle = try await runtime.observeMutationLifecycle(id: "tx-failed")
    var iterator = lifecycle.makeAsyncIterator()
    let initial = await iterator.next()
    expectNoDifference(initial, .waiting)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-failed",
        operations: TodoExample.createOperations(
          id: "todo-failed",
          text: "Rejected",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_500_001),
          transactionID: "tx-failed"
        )
      )
    )
    _ = try await runtime.failMutation(id: "tx-failed", message: "permission denied")

    guard case let .failed(mutation) = await iterator.next() else {
      Issue.record("Expected transaction-specific failure.")
      return
    }
    expectNoDifference(mutation.id, "tx-failed")
    expectNoDifference(mutation.status, .failed)
    expectNoDifference(mutation.failureMessage, "permission denied")
  }
}

private func mutationLifecycleRuntime(_ suffix: String) async throws -> InstantRuntime {
  let cacheURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("instant-mutation-lifecycle-\(suffix)-\(UUID().uuidString).sqlite")
  return try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "mutation-lifecycle-\(suffix)",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
  )
}
