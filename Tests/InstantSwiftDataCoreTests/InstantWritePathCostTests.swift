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
// 2026-11-04  #653   Red: a window a write's save claimed, still on the pump when its session ended, went out on the
//                    next session ahead of the older write the disconnect put back.
// 2026-11-04  #653   Red: every delivery claim read and decoded its writes' attributes from SQLite, one statement per
//                    attribute: a quarter of the claim a write's save makes (job 1797-b's sample of the recording
//                    exercise).
// 2026-11-04  #1523  Red: a server apply's body pages and staging looked a pending write's kept receipt up by its
//                    inputs, which the save no longer keys it by, and fingerprinted it again; a body the echo changed
//                    was then fingerprinted again at its acknowledgement (+200 us a call in jobs 1797-a and 1797-b).
// 2026-11-04  #1517  Red: a write its own save claimed was encoded once more to measure its projected body, which is the
//                    write itself, already encoded by the save (27 of the claim at save's 100 samples in job 1797-b).

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
    _ = try await Self.writeOneInterimPerSegment(3, in: &fixture)
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
    _ = try await Self.writeOneInterimPerSegment(1, in: &fixture)

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
    _ = try await Self.writeOneInterimPerSegment(2, in: &fixture)

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

  /// A server apply that replays pending writes finds each one's kept receipt fingerprint by the bytes its row stores,
  /// and keeps the fingerprint of a body it changes with the bytes it stages, so it mints one only for a receipt it
  /// changes and the acknowledgements after it mint none (#1523). Since 1ef4aa2f the save kept the fingerprint by its
  /// stored bytes only, while the echo's body pages and staging looked it up by the write's inputs: in jobs 1797-a and
  /// 1797-b the acknowledgement cost about 200 us more a call (411.7 -> 618.7 us), a full fingerprint in 14 of its 40
  /// samples.
  @Test
  func aServerApplyAndTheAcknowledgementsAfterItFindTheReceiptByTheStoredBytes() async throws {
    // The reduced apply patches pending writes' receipts without replaying them; the full rebase, which the recording
    // exercise's store still takes for some frames, loads their body pages and stages each one again.
    var fixture = try await FastDrainFixture.make(
      suffix: "receipt-after-echo",
      serverSegmentCount: 2,
      pendingSegmentCount: 0,
      reducesServerApply: false
    )
    let persistence = fixture.runtime.persistence
    _ = try await Self.writeOneInterimPerSegment(3, in: &fixture)
    let window = try await fixture.claimWindow()
    #expect(window.mutations.count == 3)
    let first = try #require(window.mutations.first)
    let later = Array(window.mutations.dropFirst())
    var receiptsBefore: [String: String] = [:]
    for mutation in later {
      receiptsBefore[mutation.id] = try await persistence.optimisticEffectReceiptFingerprintForTesting(id: mutation.id)
    }

    // The server accepts the first write and echoes the queries it touched, under which the later two are pending.
    let beforeEcho = await persistence.optimisticEffectFingerprintCountForTesting()
    let echo = try await fixture.acceptAndRefresh(first, claimToken: window.token)
    let echoMints = await persistence.optimisticEffectFingerprintCountForTesting() - beforeEcho
    var changedReceipts = 0
    for mutation in later {
      let receipt = try await persistence.optimisticEffectReceiptFingerprintForTesting(id: mutation.id)
      if receipt != receiptsBefore[mutation.id] { changedReceipts += 1 }
    }

    let beforeAcknowledgements = await persistence.optimisticEffectFingerprintCountForTesting()
    for mutation in later {
      let transactionID = fixture.server.accept(mutation.transaction.operations)
      _ = try await fixture.runtime.acceptMutationIfPresent(
        id: mutation.id,
        serverTransactionID: transactionID,
        claimToken: window.token
      )
    }
    let acknowledgementMints =
      await persistence.optimisticEffectFingerprintCountForTesting() - beforeAcknowledgements

    #expect(echo.isRebase, "the echo replayed \(echo.plannedBodyCount) pending writes; this test needs it to replay them")
    #expect(
      echoMints == changedReceipts,
      "the echo fingerprinted writes \(echoMints) times and changed \(changedReceipts) of their receipts"
    )
    #expect(
      acknowledgementMints == 0,
      "\(later.count) acknowledgements after the echo fingerprinted writes \(acknowledgementMints) times"
    )
    let pending = try await fixture.pendingCount()
    #expect(pending == 0)
    _ = try? await fixture.runtime.closeConnection()
  }

  /// A write its own save claims is measured by the body its save encoded, not encoded again: with nothing after it and
  /// every operation as it was written, its projection is the write itself, and a pending write's stored body is its
  /// sorted-key encoding (#1517). In job 1797-b's sample of the recording exercise the measuring encode was 27 of the
  /// claim at save's 100 samples.
  @Test
  func aWriteClaimedByItsSaveIsMeasuredByTheBodyItsSaveEncoded() async throws {
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let runtime = try await InstantObserverRegistrationGateTests.runtime(
      "claim-at-save-measured",
      transport: session.transport
    ) { _ in }
    _ = try await runtime.connect()
    try await InstantConnectionStateTruthTests.waitUntil("the connection's first pass to finish") {
      await runtime.automaticMutationPumpIsIdleForTesting()
    }
    let persistence = runtime.persistence
    let claimedBefore = await persistence.claimedAtSaveCountForTesting()
    let encodesBefore = await persistence.claimEncodeCountsForTesting().projectedBodyEncodes

    let writes = 3
    for index in 0..<writes {
      let id = "tx-measured-\(index)"
      try await InstantOfflineRuntimeFixture.createTodo("measured-\(index)", in: runtime)
      try await InstantConnectionStateTruthTests.waitUntil("write \(index) to reach the socket") {
        await session.sentMessages().contains { $0.op == "transact" && $0.clientEventID == id }
      }
      // Still claimed: its row holds what the claim measured, which is the write's exact sorted-key size.
      let pending = await runtime.pendingMutations()
      let mutation = try #require(pending.first { $0.id == id })
      let claimColumns = try await persistence.outboxClaimColumnsForTesting(id: id)
      let columns = try #require(claimColumns)
      let exact = try InstantBoundedOutboxDelivery.encodedProjectedBodyByteCount(mutation)
      #expect(columns.projectedBodyByteCount == exact, "write \(index): measured \(String(describing: columns.projectedBodyByteCount)), exact \(exact)")
      await session.enqueue(
        InstantLiveMessage(op: "transact-ok", clientEventID: id, fields: ["tx-id": .string("measured-\(index)")])
      )
      try await InstantConnectionStateTruthTests.waitUntil("the server to accept write \(index)") {
        await runtime.pendingMutations().isEmpty
      }
    }

    let claimed = await persistence.claimedAtSaveCountForTesting() - claimedBefore
    let encodes = await persistence.claimEncodeCountsForTesting().projectedBodyEncodes - encodesBefore
    #expect(claimed == writes, "\(claimed) of \(writes) writes were claimed by their saves")
    #expect(encodes == 0, "\(writes) writes claimed by their saves encoded their projected bodies \(encodes) times")
    _ = try? await runtime.closeConnection()
  }

  /// A delivery claim's visible-write filter finds its writes' attributes in the store's decoded copy, read again only
  /// after an attribute changes, where each claim read and decoded them from SQLite one by one (#653).
  @Test
  func claimsReuseTheStoredAttributesForTheirVisibleWriteFilters() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "claim-attributes",
      serverSegmentCount: 2,
      pendingSegmentCount: 0
    )
    let persistence = fixture.runtime.persistence
    _ = try await Self.writeOneInterimPerSegment(1, in: &fixture)
    _ = try await fixture.claimWindow()
    let before = await persistence.visibleWriteFilterAttributeReadCountForTesting()

    var claimed = 0
    for _ in 0..<3 {
      _ = try await Self.writeOneInterimPerSegment(1, in: &fixture)
      claimed += try await fixture.claimWindow().mutations.count
    }
    let reads = await persistence.visibleWriteFilterAttributeReadCountForTesting() - before

    #expect(claimed == 3)
    #expect(reads == 0, "3 claims after the first read attributes from SQLite \(reads) times")
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
    // One task sleeps through every write; a second only if a slow run outlasts the first deadline (about 6 s).
    #expect(tasks <= 2, "\(tasks) deadline-wake tasks for \(writes) writes acknowledged within their deadlines")
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

  /// A write its save claimed waits on the pump while the session it was claimed for ends, which puts back the older
  /// write that was in flight. The next session gets the older write first: a window claimed at save goes out only on
  /// the session it was claimed for, as a pass's window, claimed from the head, goes out after every write before it
  /// (#653).
  @Test
  func aWriteClaimedAtSaveIsNotSentAheadOfAnOlderWriteOnTheNextSession() async throws {
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "claimed-at-save-first")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "claimed-at-save-second")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second])
    let hold = ClaimedAtSaveDeliveryHold(mutationID: "tx-ended-b")
    let runtime = try await InstantObserverRegistrationGateTests.runtime(
      "claim-at-save-session-ends",
      transport: transport.transport
    ) {
      $0.onClaimedAtSaveDeliveryStartingForTesting = { ids in await hold.pass(ids) }
    }
    _ = try await runtime.connect()
    try await InstantConnectionStateTruthTests.waitUntil("the connection's first pass to finish") {
      await runtime.automaticMutationPumpIsIdleForTesting()
    }

    try await InstantOfflineRuntimeFixture.createTodo("ended-a", in: runtime)
    try await InstantConnectionStateTruthTests.waitUntil("the older write to reach the first socket") {
      await first.sentMessages().contains { $0.op == "transact" && $0.clientEventID == "tx-ended-a" }
    }
    try await InstantOfflineRuntimeFixture.createTodo("ended-b", in: runtime)
    try await InstantConnectionStateTruthTests.waitUntil("the newer write's window to reach the pump") {
      await hold.isHolding
    }
    let claimedAtSave = await runtime.persistence.claimedAtSaveCountForTesting()
    #expect(claimedAtSave == 2, "both writes were claimed by their saves: \(claimedAtSave)")

    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "end the first session",
        message: "The scripted first connection ended.",
        recovery: "Reconnect and send the outbox again."
      )
    )
    try await InstantConnectionStateTruthTests.waitUntil("the second session to open") {
      await transport.connectionRequests().count == 2 && runtime.connectionHealth().isOpen
    }
    await hold.open()
    try await InstantConnectionStateTruthTests.waitUntil("both writes to reach the second socket") {
      await second.sentMessages().filter { $0.op == "transact" }.count >= 2
    }

    let sent = await second.sentMessages().filter { $0.op == "transact" }.compactMap(\.clientEventID)
    #expect(sent == ["tx-ended-a", "tx-ended-b"], "the next session gets the older write first: \(sent)")
    guard sent == ["tx-ended-a", "tx-ended-b"] else {
      _ = try? await runtime.closeConnection()
      return
    }
    for id in sent {
      await second.enqueue(InstantLiveMessage(op: "transact-ok", clientEventID: id, fields: ["tx-id": .string("s-\(id)")]))
    }
    try await InstantConnectionStateTruthTests.waitUntil("the server to accept both writes") {
      await runtime.pendingMutations().isEmpty
    }
    _ = try? await runtime.closeConnection()
  }

  /// Saves each of `count` segments' first interim write alone: one outbox row per segment, none superseding another
  /// and none narrowing another's projection, as `FastDrainFixture.writeSegments` (six writes a segment) would.
  static func writeOneInterimPerSegment(_ count: Int, in fixture: inout FastDrainFixture) async throws -> [String] {
    var ids: [String] = []
    for _ in 0..<count {
      let write = fixture.script.nextSegmentWrites()[0]
      _ = try await fixture.runtime.transact(
        write,
        createdAt: InstantTimestamp(milliseconds: fixture.script.deviceMilliseconds)
      )
      ids.append(write.id)
    }
    return ids
  }
}

/// Holds the pump's send of the window a write's save claimed for `mutationID` until ``open()`` (#653).
private actor ClaimedAtSaveDeliveryHold {
  let mutationID: String
  private(set) var isHolding = false
  private var isOpen = false
  private var release: CheckedContinuation<Void, Never>?

  init(mutationID: String) {
    self.mutationID = mutationID
  }

  func pass(_ mutationIDs: [String]) async {
    guard !isOpen, mutationIDs.contains(mutationID) else { return }
    await withCheckedContinuation { continuation in
      release = continuation
      isHolding = true
    }
  }

  func open() {
    isOpen = true
    release?.resume()
    release = nil
  }
}
