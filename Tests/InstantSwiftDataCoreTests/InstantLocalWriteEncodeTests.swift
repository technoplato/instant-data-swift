// History
// 2026-10-31  #1491  Created. A new local write encoded its whole mutation to sorted-key JSON twice: once to count its
//                    bytes against the durable delivery limit, and once more for the body the store writes, which is
//                    the same text. The recording exercise's sample put the first encode at about 0.37 ms of the
//                    write's ~3 ms of CPU on an M4, inside the operation gate.

import CustomDump
import Foundation
import Testing
import os

@testable import InstantSwiftDataCore

/// What a new local write encodes to JSON on its way to the durable outbox (#1491).
@Suite(.serialized)
struct InstantLocalWriteEncodeTests {
  /// Each write's body is encoded once, for the row the store writes; the size bound reads that text's bytes.
  @Test
  func aNewLocalWriteEncodesItsBodyOnce() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("encode-once")
    try await InstantOfflineRuntimeFixture.createTodo("warm", in: runtime)

    let encodes = OSAllocatedUnfairLock(initialState: 0)
    try await InstantAutomaticOutboxAdmission.$bodyEncodesForTesting.withValue(encodes) {
      for index in 0..<10 {
        try await InstantOfflineRuntimeFixture.createTodo("write-\(index)", in: runtime)
      }
    }

    // `#expect`, not `expectNoDifference`: the release lane records no CustomDump issue.
    let count = encodes.withLock { $0 }
    #expect(count == 10, "10 writes encoded their bodies \(count) times")
    let pendingCount = await runtime.pendingMutationCount()
    #expect(pendingCount == 11)
  }

  /// A write whose body passes the limit still fails before anything commits, with the admission's error (#1491 moved
  /// the check onto the stored body's bytes).
  @Test
  func anOversizedNewWriteStillFailsBeforeItCommits() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("encode-once-oversized")
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let text = String(repeating: "x", count: InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes + 1_024)
    let transaction = InstantStoreTransaction(
      id: "tx-oversized",
      operations: TodoExample.createOperations(
        id: "todo-oversized", text: text, createdAt: createdAt, transactionID: "tx-oversized"
      )
    )

    do {
      _ = try await runtime.transact(transaction, createdAt: createdAt)
      Issue.record("Expected an oversized new write to fail before its local commit.")
    } catch let error as InstantError {
      #expect(error.code == .validationFailed)
      #expect(error.operation == "transact")
      #expect(error.localID == "tx-oversized")
      #expect(error.message.contains("8388608-byte durable delivery limit"), "\(error.message)")
    }

    let triples = await runtime.store.snapshot().triples
    let outboxCount = try await runtime.persistence.countOutboxMutations()
    #expect(triples.isEmpty)
    #expect(outboxCount == 0)

    try await InstantOfflineRuntimeFixture.createTodo("after", in: runtime)
    let pendingCount = await runtime.pendingMutationCount()
    #expect(pendingCount == 1)
  }
}
