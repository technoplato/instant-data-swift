// History
// 2026-11-04  #1517  Created. The delivery claim encoded each write's projected body twice, once to measure it and once
//                    more to check that measure against an identical input, and fingerprinted its forward wire intent
//                    twice, once for the body as stored, which the projected body's fingerprint always replaced before
//                    the claim committed. All four ran under the operation gate; on the phone (builds 248-249) the
//                    claim cost as much CPU as the save.
// 2026-11-04  #1523  The save, the claim and the acknowledgement each found the write's kept receipt fingerprint by
//                    hashing its whole transaction and rollback (about 180 us each on an M4); the stored bytes find it.

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// What one live write costs on its way from the outbox to the socket (#653, #1517).
@Suite(.serialized)
struct InstantWritePathCostTests {
  /// A write the claim projects without a required-scalar substitution is encoded once to measure its projected body,
  /// and its wire intent is fingerprinted once, for the projected body that goes out (#1517).
  @Test
  func aClaimEncodesEachProjectedBodyOnceAndFingerprintsItsWireIntentOnce() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "claim-encodes-once",
      serverSegmentCount: 2,
      pendingSegmentCount: 0
    )
    _ = try await fixture.writeSegments(3)
    let before = await fixture.runtime.persistence.claimEncodeCountsForTesting()

    let window = try await fixture.claimWindow()
    let after = await fixture.runtime.persistence.claimEncodeCountsForTesting()

    // `#expect`, not `expectNoDifference`: the release lane records no CustomDump issue.
    #expect(window.mutations.count == 3)
    let projected = after.projectedBodyEncodes - before.projectedBodyEncodes
    let fingerprints = after.wireIntentFingerprints - before.wireIntentFingerprints
    #expect(projected == 3, "3 claimed writes encoded their projected bodies \(projected) times")
    #expect(fingerprints == 3, "3 claimed writes fingerprinted their wire intents \(fingerprints) times")
    _ = try? await fixture.runtime.closeConnection()
  }

  /// The claim still records what it measured: a claimed write's row holds the projected body's exact byte count and
  /// its wire intent's fingerprint, and the acknowledgement accepts it against them (#1517). One write, so nothing
  /// after it narrows its projection and the projected body is the write itself.
  @Test
  func aClaimedWriteIsStillMeasuredFingerprintedAndAccepted() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "claim-measured",
      serverSegmentCount: 2,
      pendingSegmentCount: 0
    )
    _ = try await fixture.writeSegments(1)

    let window = try await fixture.claimWindow()
    #expect(window.mutations.count == 1)
    for mutation in window.mutations {
      let columns = try await fixture.runtime.persistence.outboxClaimColumnsForTesting(id: mutation.id)
      let claim = try #require(columns)
      let projectedBytes = try InstantBoundedOutboxDelivery.encodedProjectedBodyByteCount(mutation)
      let fingerprint = try mutation.mutationWireIntentFingerprint()
      #expect(claim.projectedBodyByteCount == projectedBytes)
      #expect(claim.payloadFingerprint == fingerprint)
      _ = try await fixture.runtime.acceptMutationIfPresent(
        id: mutation.id,
        serverTransactionID: "accepted-\(mutation.id)",
        claimToken: window.token
      )
    }
    let pending = try await fixture.pendingCount()
    #expect(pending == 0)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// A live write's save mints its receipt fingerprint, and its claim and acknowledgement check the row against it
  /// without hashing the write's transaction and rollback to find it: the row's stored bytes are the key (#1523).
  @Test
  func aWritesSaveClaimAndAcknowledgementFindItsReceiptWithoutHashingTheWrite() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "receipt-by-bytes",
      serverSegmentCount: 2,
      pendingSegmentCount: 0
    )
    let persistence = fixture.runtime.persistence
    let hashesBefore = await persistence.receiptInputsHashCountForTesting()
    let fingerprintsBefore = await persistence.optimisticEffectFingerprintCountForTesting()
    _ = try await fixture.writeSegments(2)

    let window = try await fixture.claimWindow()
    for mutation in window.mutations {
      let transactionID = fixture.server.accept(mutation.transaction.operations)
      _ = try await fixture.runtime.acceptMutationIfPresent(
        id: mutation.id,
        serverTransactionID: transactionID,
        claimToken: window.token
      )
    }
    let hashes = await persistence.receiptInputsHashCountForTesting() - hashesBefore
    let fingerprints = await persistence.optimisticEffectFingerprintCountForTesting() - fingerprintsBefore

    #expect(window.mutations.count == 2)
    #expect(hashes == 0, "2 writes' saves, claims and acknowledgements hashed their inputs \(hashes) times")
    #expect(fingerprints == 2, "2 writes were fingerprinted \(fingerprints) times; each save mints one")
    let pending = try await fixture.pendingCount()
    #expect(pending == 0)
    _ = try? await fixture.runtime.closeConnection()
  }
}
