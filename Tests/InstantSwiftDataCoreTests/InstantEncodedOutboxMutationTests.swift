import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A local write's outbox encodings are computed once, in admission, and the row stores the same bytes it always did
/// (#403). The receipt and wire digests are stored authority, so their bytes must never change.
@Suite(.serialized)
struct InstantEncodedOutboxMutationTests {
  @Test
  func aLocalWriteIsEncodedOnceAndStoresTheBytesItAlwaysDid() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantEncodedOutboxMutationTests-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: cacheURL.path + suffix))
      }
    }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "encoded-outbox-mutation",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    for index in 0..<3 {
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_123 + Int64(index) * 1_001)
      try await runtime.transact(
        InstantStoreTransaction(
          id: "encoded-\(index)",
          operations: TodoExample.createOperations(
            id: "encoded-todo-\(index)",
            text: "todo \(index) with \"quotes\", an emoji 🎙️, and a newline\n",
            createdAt: createdAt,
            transactionID: "encoded-\(index)"
          )
        ),
        createdAt: createdAt
      )
    }
    let encodedByStore = await runtime.persistence.encodedOutboxMutationCountForTesting()
    let mutations = await runtime.pendingMutations()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    expectNoDifference(encodedByStore, 0)
    expectNoDifference(mutations.count, 3)
    for mutation in mutations {
      let encoded = try InstantEncodedOutboxMutation(mutation)
      let receiptFingerprint = try mutation.optimisticEffectReceiptFingerprint()
      let wireFingerprint = try mutation.mutationWireIntentFingerprint()
      let stepCount = InstantOutboxDeliveryMetadata.stepCount(in: mutation)
      let body = String(decoding: try encoder.encode(mutation), as: UTF8.self)
      let lifecycleBody = String(
        decoding: try encoder.encode(mutation.compactedForMemory),
        as: UTF8.self
      )
      let storedReceiptFingerprint = try await runtime.persistence
        .optimisticEffectReceiptFingerprintForTesting(id: mutation.id)
      let storedStepCount = try await runtime.persistence.selectInt64ForTesting(
        "SELECT transport_step_count FROM instant_outbox WHERE mutation_id = '\(mutation.id)'"
      )
      let storedBodyByteCount = try await runtime.persistence.selectInt64ForTesting(
        "SELECT encoded_body_bytes FROM instant_outbox WHERE mutation_id = '\(mutation.id)'"
      )
      let storedBodyLength = try await runtime.persistence.selectInt64ForTesting(
        "SELECT length(CAST(json AS BLOB)) FROM instant_outbox WHERE mutation_id = '\(mutation.id)'"
      )

      #expect(receiptFingerprint != nil)
      expectNoDifference(encoded.receiptFingerprint, receiptFingerprint)
      expectNoDifference(encoded.wireFingerprint, wireFingerprint)
      expectNoDifference(encoded.stepCount, stepCount)
      expectNoDifference(encoded.body, body)
      expectNoDifference(encoded.lifecycleBody, lifecycleBody)
      expectNoDifference(storedReceiptFingerprint, receiptFingerprint)
      expectNoDifference(storedStepCount, Int64(stepCount))
      expectNoDifference(storedBodyByteCount, Int64(body.utf8.count))
      expectNoDifference(storedBodyLength, Int64(body.utf8.count))
    }
  }

  /// Admission hands back what it encoded, so the save that follows encodes nothing again.
  @Test
  func admissionReturnsTheEncodingsItComputed() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantEncodedOutboxMutationTests-\(UUID().uuidString).sqlite")
    defer {
      for suffix in ["", "-wal", "-shm"] {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: cacheURL.path + suffix))
      }
    }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "encoded-outbox-admission",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "admitted",
        operations: TodoExample.createOperations(
          id: "admitted-todo",
          text: "admitted",
          createdAt: createdAt,
          transactionID: "admitted"
        )
      ),
      createdAt: createdAt
    )
    let pending = await runtime.pendingMutations()
    let mutation = try #require(pending.first)

    let admitted = try InstantAutomaticOutboxAdmission.validateNewMutation(mutation)
    let recomputed = try InstantEncodedOutboxMutation(mutation)

    expectNoDifference(admitted.receiptFingerprint, recomputed.receiptFingerprint)
    expectNoDifference(admitted.wireFingerprint, recomputed.wireFingerprint)
    expectNoDifference(admitted.stepCount, recomputed.stepCount)
    expectNoDifference(admitted.body, recomputed.body)
    expectNoDifference(admitted.lifecycleBody, recomputed.lifecycleBody)
  }
}
