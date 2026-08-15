import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantPendingMutationCompatibilityTests {
  @Test
  func receiptDigestMatchesThePortableSHA256Contract() {
    expectNoDifference(
      instantSHA256HexDigest(Data("abc".utf8)),
      "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    )
  }

  @Test
  func knownNoEffectReceiptKeepsTheLegacyAppliedOverlayEncoding() throws {
    var mutation = PendingMutation(
      id: "tx-compatible-no-effect",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
      transaction: InstantStoreTransaction(
        id: "tx-compatible-no-effect",
        operations: [.deleteEntity("todo-compatible-no-effect")]
      )
    )
    mutation.optimisticOverlayState = .applied
    mutation.optimisticEffectReceiptVersion =
      PendingMutation.currentOptimisticEffectReceiptVersion

    let encoded = try JSONEncoder().encode(mutation)
    let object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    expectNoDifference(object["optimisticOverlayState"] as? String, "applied")
    expectNoDifference(
      object["optimisticEffectReceiptVersion"] as? Int,
      PendingMutation.currentOptimisticEffectReceiptVersion
    )
    #expect(!String(decoding: encoded, as: UTF8.self).contains("replayableWithoutMaterializedEffect"))

    // The released decoder knew only `applied` and `removed`. It ignores the
    // additive version key and therefore remains able to open the new row.
    let legacy = try JSONDecoder().decode(LegacyPendingMutationBody.self, from: encoded)
    expectNoDifference(legacy.id, mutation.id)
    expectNoDifference(legacy.optimisticOverlayState, .applied)
    expectNoDifference(legacy.rollbackTransaction, nil)

    let roundTripped = try JSONDecoder().decode(PendingMutation.self, from: encoded)
    expectNoDifference(roundTripped.optimisticOverlayState, .applied)
    expectNoDifference(
      roundTripped.optimisticEffectReceiptVersion,
      PendingMutation.currentOptimisticEffectReceiptVersion
    )
    switch roundTripped.optimisticEffectReceipt {
    case .noCurrentMaterializedEffect:
      break
    case .unknown, .materialized:
      Issue.record("The additive receipt version must preserve the known no-effect proof.")
    }
  }

  @Test
  func legacyAppliedWithoutVersionRemainsUnknown() throws {
    var mutation = PendingMutation(
      id: "tx-legacy-ambiguous-no-effect",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_001),
      transaction: InstantStoreTransaction(
        id: "tx-legacy-ambiguous-no-effect",
        operations: [.deleteEntity("todo-legacy-ambiguous-no-effect")]
      )
    )
    mutation.optimisticOverlayState = .applied
    mutation.optimisticEffectReceiptVersion = nil

    let decoded = try JSONDecoder().decode(
      PendingMutation.self,
      from: JSONEncoder().encode(mutation)
    )
    expectNoDifference(decoded.isLegacyUnknownOverlayCandidate, true)
    expectNoDifference(decoded.provesReplayableOptimisticEffectReceipt, false)
    expectNoDifference(try decoded.optimisticEffectReceiptFingerprint(), nil)
  }
}

private enum LegacyOptimisticOverlayState: String, Codable {
  case applied
  case removed
}

private struct LegacyPendingMutationBody: Decodable {
  var id: String
  var createdAt: InstantTimestamp
  var transaction: InstantStoreTransaction
  var status: InstantMutationStatus
  var failureMessage: String?
  var rollbackTransaction: InstantStoreTransaction?
  var optimisticOverlayState: LegacyOptimisticOverlayState?
}
