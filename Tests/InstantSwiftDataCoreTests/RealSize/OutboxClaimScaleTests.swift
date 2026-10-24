import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1108, #1114 (2026-10-24): the delivery pump's claim pass, after every write and every acknowledgement, read every
// ready outbox row to find the next write to deliver, refused writes included. Its candidate read and its continuation
// check filter `delivery_claim_state = ? AND (delivery_state = ? OR (legacy metadata))`; the `OR` left SQLite one plan,
// a search on the claim state alone and a sort, so each of the 663 refused writes on one phone's store was visited
// through its body's overflow pages. On the phone-shaped store the claim held the operation gate 402-524 ms of every
// recording minute, about 60% of the gate (#1072's recording minutes, Mac mini, release).
//
// History:
// - 2026-10-24: #1108: the scale test.

@Suite(.serialized)
struct OutboxClaimScaleTests {
  @Test("The pump's candidate read and continuation check visit no refused write: 400 of them cost what 7 do")
  func claimReadsDoNotGrowWithRefusedWrites() async throws {
    let few = RealSizeShape.phone.scaled(0.01)
    var many = few
    many.refusedWrites = 400

    let fewSteps = try await Self.claimReadSteps(few, label: "claim-few")
    let manySteps = try await Self.claimReadSteps(many, label: "claim-many")

    // SQLite's virtual-machine steps: a read that visited each refused write would take some ten more per row.
    #expect(
      manySteps.candidates <= fewSteps.candidates + 50,
      "The candidate read took \(manySteps.candidates) steps beside 400 refused writes against \(fewSteps.candidates) beside 7."
    )
    #expect(
      manySteps.check <= fewSteps.check + 50,
      "The continuation check took \(manySteps.check) steps beside 400 refused writes against \(fewSteps.check) beside 7."
    )
  }

  /// The claim reads' steps on a generated store of `shape`, once its writes settled: no write left to deliver, the
  /// refused ones kept.
  private static func claimReadSteps(_ shape: RealSizeShape, label: String) async throws -> (candidates: Int, check: Int) {
    let session = try await RealSizeFixture.open(shape, label: label)
    return try await session.closing {
      try await RealSizeGenerator.waitForSettledOutbox(session.runtime)
      let refused = await session.runtime.failedMutations(limit: 1_000).count
      #expect(refused == shape.refusedWrites)
      return try await session.runtime.persistence.automaticDeliveryCandidateReadStepsForTesting()
    }
  }
}
