// History
// 2026-11-04  #1517  Created. The delivery claim encoded each write's projected body twice, once to measure it and once
//                    more to check that measure against an identical input, and fingerprinted its forward wire intent
//                    twice, once for the body as stored, which the projected body's fingerprint always replaced before
//                    the claim committed. All four ran under the operation gate; on the phone (builds 248-249) the
//                    claim cost as much CPU as the save.
// 2026-11-04  #1523  The save, the claim and the acknowledgement each found the write's kept receipt fingerprint by
//                    hashing its whole transaction and rollback (about 180 us each on an M4); the stored bytes find it.
// 2026-11-04  #653   Red: a write saved while the connection is open and nothing waits ahead of it still takes a claim
//                    turn of the operation gate, which reads its body back and fingerprints it again (3.06 ms a claim on
//                    the phone, builds 248-249, more than the save's 2.79 ms).
// 2026-11-04  #1142  Red: every write's send started a task that slept until its acknowledgement deadline (about 6 s),
//                    and its acknowledgement cancelled it: one task and one timer a write.

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

  /// A write saved while the connection is open and nothing waits ahead of it is claimed by its own save and sent from
  /// there, as `Reactor.js` `pushOps` sends a mutation as it records it (`_trySendAuthed`): no claim turn of the
  /// operation gate, and every write still goes out once, in order, and is accepted (#653).
  @Test
  func aWriteSavedWithNothingAheadOfItIsClaimedByItsSave() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let holds = InstantGateHoldCounter()
    let runtime = try await InstantObserverRegistrationGateTests.runtime(
      "claim-at-save",
      transport: session.transport
    ) {
      $0.operationGateTimeline = holds.record
    }
    _ = try await runtime.connect()
    try await InstantConnectionStateTruthTests.waitUntil("the connection's first pass to finish") {
      await runtime.automaticMutationPumpIsIdleForTesting()
    }
    holds.reset()

    let writes = 6
    for index in 0..<writes {
      try await InstantOfflineRuntimeFixture.createTodo("save-claim-\(index)", in: runtime)
      try await InstantConnectionStateTruthTests.waitUntil("write \(index) to reach the socket") {
        await session.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-save-claim-\(index)" }
      }
      await session.enqueue(
        InstantLiveMessage(
          op: "transact-ok",
          clientEventID: "tx-save-claim-\(index)",
          fields: ["tx-id": .string("server-\(index)")]
        )
      )
      try await InstantConnectionStateTruthTests.waitUntil("the server to accept write \(index)") {
        await runtime.pendingMutations().isEmpty
      }
      try await InstantConnectionStateTruthTests.waitUntil("the pump to finish after write \(index)") {
        await runtime.automaticMutationPumpIsIdleForTesting()
      }
    }

    let claims = holds.count(of: "claim automatic outbox transport mutations for delivery")
    #expect(claims == 0, "\(claims) claim turns for \(writes) writes saved with nothing ahead of them")
    let sent = await session.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    #expect(sent == (0..<writes).map { "tx-save-claim-\($0)" }, "every write is sent once, in order: \(sent)")
    _ = try? await runtime.closeConnection()
  }

  /// Writes sent and acknowledged one at a time, each within its acknowledgement deadline, share one deadline wake:
  /// its task sleeps on and finds nothing to do, where each send started a task and each acknowledgement cancelled it
  /// (#1142).
  @Test
  func acknowledgedWritesShareOneDeadlineWake() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let runtime = try await InstantObserverRegistrationGateTests.runtime(
      "deadline-wake",
      transport: session.transport
    )
    _ = try await runtime.connect()
    try await InstantConnectionStateTruthTests.waitUntil("the connection's first pass to finish") {
      await runtime.automaticMutationPumpIsIdleForTesting()
    }
    let before = await runtime.mutationDeadlineWakeTaskCountForTesting()

    let writes = 6
    for index in 0..<writes {
      try await InstantOfflineRuntimeFixture.createTodo("wake-\(index)", in: runtime)
      try await InstantConnectionStateTruthTests.waitUntil("write \(index) to reach the socket") {
        await session.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-wake-\(index)" }
      }
      await session.enqueue(
        InstantLiveMessage(op: "transact-ok", clientEventID: "tx-wake-\(index)", fields: ["tx-id": .string("w-\(index)")])
      )
      try await InstantConnectionStateTruthTests.waitUntil("the server to accept write \(index)") {
        await runtime.pendingMutations().isEmpty
      }
    }

    let tasks = await runtime.mutationDeadlineWakeTaskCountForTesting() - before
    #expect(tasks <= 1, "\(tasks) deadline-wake tasks for \(writes) writes acknowledged within their deadlines")
    _ = try? await runtime.closeConnection()
  }

  /// Writes saved back to back on an open connection, some claimed by their saves and some by passes that waited for
  /// the operation gate meanwhile, reach the socket once each in the order they were made (#653).
  @Test
  func writesSavedBackToBackReachTheSocketInTheOrderTheyWereMade() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let runtime = try await InstantObserverRegistrationGateTests.runtime(
      "claim-at-save-burst",
      transport: session.transport
    ) { _ in }
    _ = try await runtime.connect()
    try await InstantConnectionStateTruthTests.waitUntil("the connection's first pass to finish") {
      await runtime.automaticMutationPumpIsIdleForTesting()
    }

    let writes = 10
    for index in 0..<writes {
      try await InstantOfflineRuntimeFixture.createTodo("burst-\(index)", in: runtime)
    }
    try await InstantConnectionStateTruthTests.waitUntil("every write to reach the socket") {
      await session.sentMessages().filter { $0.op == "transact" }.count >= writes
    }
    for index in 0..<writes {
      await session.enqueue(
        InstantLiveMessage(op: "transact-ok", clientEventID: "tx-burst-\(index)", fields: ["tx-id": .string("s-\(index)")])
      )
    }
    try await InstantConnectionStateTruthTests.waitUntil("the server to accept every write") {
      await runtime.pendingMutations().isEmpty
    }

    let sent = await session.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    #expect(sent == (0..<writes).map { "tx-burst-\($0)" }, "every write is sent once, in order: \(sent)")
    _ = try? await runtime.closeConnection()
  }
}
