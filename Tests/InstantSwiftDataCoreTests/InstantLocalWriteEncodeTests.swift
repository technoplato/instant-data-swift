// History
// 2026-10-31  #1491  Created. A new local write encoded its whole mutation to sorted-key JSON twice: once to count its
//                    bytes against the durable delivery limit, and once more for the body the store writes, which is
//                    the same text. The recording exercise's sample put the first encode at about 0.37 ms of the
//                    write's ~3 ms of CPU on an M4, inside the operation gate.
// 2026-10-31  #1491  The two SHA-256 digests a save writes formatted their bytes with String(format:), 32 strings
//                    joined, each time; the sample put it at about 0.11 ms a write.
// 2026-10-31  #1491  A new write's row write fingerprinted its forward wire intent, which decides only a row that
//                    already holds a server acceptance or was offered to delivery.

import CryptoKit
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

  /// A new write's row holds no server acceptance and was never offered to delivery, so its forward wire intent decides
  /// nothing at its save (#1491): the row write fingerprinted it anyway, a sorted-key encode and a SHA-256 a write.
  @Test
  func aNewLocalWriteFingerprintsNoWireIntent() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("no-wire-fingerprint")
    try await InstantOfflineRuntimeFixture.createTodo("warm", in: runtime)
    let before = await runtime.persistence.savedWireIntentFingerprintCountForTesting()

    for index in 0..<10 {
      try await InstantOfflineRuntimeFixture.createTodo("write-\(index)", in: runtime)
    }

    let fingerprints = await runtime.persistence.savedWireIntentFingerprintCountForTesting() - before
    #expect(fingerprints == 0, "10 new writes computed \(fingerprints) wire-intent fingerprints")
    let pendingCount = await runtime.pendingMutationCount()
    #expect(pendingCount == 11)
  }

  /// The two digests each save writes (its receipt and its wire intent) are SHA-256 as lowercase hex. Each formatted its
  /// 32 bytes with `String(format:)`, a string a byte, joined (#1491): 333 allocations a digest, 70 of them the hash's
  /// own on an M4. The hex now adds only its string.
  @Test
  func aDigestIsLowercaseHexWrittenInOneAllocation() {
    #expect(
      instantSHA256HexDigest(Data("abc".utf8))
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
    #expect(instantSHA256HexDigest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    // The hash's own allocations are SHA-256's, not the hex's: count what the hex adds to them.
    let data = Data(repeating: 0xA5, count: 4_096)
    let hash = RefreshCostTests.allocations(iterations: 20) { _ = SHA256.hash(data: data) }
    let digest = RefreshCostTests.allocations(iterations: 20) { _ = instantSHA256HexDigest(data) }
    #expect(digest - hash <= 1, "the hex added \(digest - hash) allocations to the hash's \(hash)")
  }
}
