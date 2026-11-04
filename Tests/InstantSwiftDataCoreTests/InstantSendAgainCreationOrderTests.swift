import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// #1648: Send Again (`retryQuarantinedMutation`, #696) makes a quarantined mutation a new local write, so it takes its
/// place in the outbox after every write made before it. It passed a time read before the operation gate, which skips
/// the step past the outbox tail, so in the millisecond of another write it tied and went out in id order, possibly
/// first.
///
/// The suite shares its name with the typed API's creation-order suite in InstantSwiftDataTests, so one
/// `--filter InstantWriteCreationOrderTests` runs every transact path's case.
@Suite(.serialized)
struct InstantWriteCreationOrderTests {
  @Test
  func aMutationSentAgainGoesAfterTheWriteMadeBeforeItInTheSameMillisecond() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSendAgainCreationOrderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cacheURL = directory.appendingPathComponent("state.sqlite")
    let sameMillisecond = InstantTimestamp(milliseconds: 1_790_000_000_000)

    // A refused write with no preparation receipt, as an older store held it: bootstrap quarantines it.
    let heldAt = InstantTimestamp(milliseconds: sameMillisecond.milliseconds - 60_000)
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveOutbox([
      PendingMutation(
        id: "a-sent-again",
        createdAt: heldAt,
        transaction: InstantStoreTransaction(
          id: "a-sent-again",
          operations: TodoExample.createOperations(
            id: "todo-sent-again",
            text: "sent again",
            createdAt: heldAt,
            transactionID: "a-sent-again"
          )
        ),
        status: .failed,
        failureMessage: "Permission denied: not perms-pass?"
      )
    ])
    await persistence.simulateUnexpectedConnectionCloseForTesting()

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "send-again-creation-order",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { sameMillisecond }
      )
    )
    let held = try await runtime.quarantinedMutations(limit: 10)
    expectNoDifference(held.map(\.id), ["a-sent-again"])

    try await runtime.transact(
      InstantStoreTransaction(
        id: "z-written",
        operations: TodoExample.createOperations(
          id: "todo-written",
          text: "written",
          createdAt: sameMillisecond,
          transactionID: "z-written"
        )
      )
    )
    try await runtime.retryQuarantinedMutation(id: "a-sent-again")

    let pending = await runtime.pendingMutations(limit: 10)
    expectNoDifference(pending.map(\.id), ["z-written", "a-sent-again"])
    expectNoDifference(
      pending.map(\.createdAt.milliseconds),
      [sameMillisecond.milliseconds, sameMillisecond.milliseconds + 1]
    )
  }
}
