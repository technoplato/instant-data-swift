import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// ADR 0015 / #155 — pure same-entity outbox supersession policy (offline).
///
/// Docs: docs/adr/0015-sqlite-data-parity-ergonomics/follow-on-outbox-same-entity-supersession.md
@Suite
struct OutboxSameEntitySupersessionTests {
  private let segmentNS = "recipe_transcription_segments"
  private let recordingNS = "recipe_recordings"

  // MARK: - High-churn open-segment sequences

  @Test
  func tenSameEntityUpsertsKeepOnlyLatest() {
    let entries = (1...10).map { i in
      OutboxSupersessionCandidate.singletonUpsert(
        id: "tx-\(i)",
        namespace: segmentNS,
        entityID: "seg-1",
        createdAtMs: Int64(i * 10),
        payloadRevisionMs: Int64(1_700_000_000_000 + i)
      )
    }

    let decision = OutboxSameEntitySupersession.decide(entries: entries)
    expectNoDifference(decision.keptIDs, ["tx-10"])
    expectNoDifference(decision.supersededIDs, (1...9).map { "tx-\($0)" })
    expectNoDifference(
      Set(decision.keptIDs).union(decision.supersededIDSet).count,
      10
    )
  }

  @Test
  func oneHundredSameEntityUpsertsKeepOnlyLatest() {
    let entries = (1...100).map { i in
      OutboxSupersessionCandidate.singletonUpsert(
        id: String(format: "tx-%03d", i),
        namespace: segmentNS,
        entityID: "seg-open",
        createdAtMs: Int64(i),
        payloadRevisionMs: Int64(i)
      )
    }

    let decision = OutboxSameEntitySupersession.decide(entries: entries)
    expectNoDifference(decision.keptIDs, ["tx-100"])
    #expect(decision.supersededIDs.count == 99)
    #expect(!decision.supersededIDSet.contains("tx-100"))
    #expect(decision.supersededIDSet.contains("tx-001"))
    #expect(decision.supersededIDSet.contains("tx-099"))

    let survivors = OutboxSameEntitySupersession.coalescing(entries: entries)
    expectNoDifference(survivors.map(\.id), ["tx-100"])
    expectNoDifference(survivors.first?.payloadRevisionMs, 100)
  }

  @Test
  func payloadRevisionBeatsCreatedAtWhenTheyDisagree() {
    // Older wall-clock enqueue but higher payload revision (monotonic speech clock).
    let olderClockNewerPayload = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-late-payload",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 100,
      payloadRevisionMs: 500
    )
    let newerClockOlderPayload = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-early-payload",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 200,
      payloadRevisionMs: 100
    )

    let decision = OutboxSameEntitySupersession.decide(
      entries: [newerClockOlderPayload, olderClockNewerPayload]
    )
    expectNoDifference(decision.keptIDs, ["tx-late-payload"])
    expectNoDifference(decision.supersededIDs, ["tx-early-payload"])
  }

  @Test
  func singlePendingUpsertIsNeverSuperseded() {
    let only = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-only",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 1,
      payloadRevisionMs: 1
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [only])
    expectNoDifference(decision.keptIDs, ["tx-only"])
    expectNoDifference(decision.supersededIDs, [])
  }

  // MARK: - Multi-entity independence

  @Test
  func differentEntityIDsDoNotSupersedeEachOther() {
    let a = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-a",
      namespace: segmentNS,
      entityID: "seg-a",
      createdAtMs: 1,
      payloadRevisionMs: 1
    )
    let b = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-b",
      namespace: segmentNS,
      entityID: "seg-b",
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [a, b])
    expectNoDifference(Set(decision.keptIDs), ["tx-a", "tx-b"])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func differentNamespacesDoNotSupersedeEachOther() {
    let segment = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-seg",
      namespace: segmentNS,
      entityID: "same-id",
      createdAtMs: 1,
      payloadRevisionMs: 1
    )
    let recording = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-rec",
      namespace: recordingNS,
      entityID: "same-id",
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [segment, recording])
    expectNoDifference(Set(decision.keptIDs), ["tx-seg", "tx-rec"])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func twoEntitiesEachChurnKeepOnePerEntity() {
    var entries: [OutboxSupersessionCandidate] = []
    for i in 1...20 {
      entries.append(
        .singletonUpsert(
          id: "tx-seg-\(i)",
          namespace: segmentNS,
          entityID: "seg-1",
          createdAtMs: Int64(i * 2),
          payloadRevisionMs: Int64(i)
        )
      )
      entries.append(
        .singletonUpsert(
          id: "tx-rec-\(i)",
          namespace: recordingNS,
          entityID: "rec-1",
          createdAtMs: Int64(i * 2 + 1),
          payloadRevisionMs: Int64(i)
        )
      )
    }

    let decision = OutboxSameEntitySupersession.decide(entries: entries)
    expectNoDifference(Set(decision.keptIDs), ["tx-seg-20", "tx-rec-20"])
    #expect(decision.supersededIDs.count == 38)
  }

  // MARK: - Non-superseded cases

  @Test
  func failedTerminalIsNeverSuperseded() {
    let failed = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-failed",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 1,
      payloadRevisionMs: 1,
      status: .failed
    )
    let later = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-later",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [failed, later])
    expectNoDifference(Set(decision.keptIDs), ["tx-failed", "tx-later"])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func permissionPoisonIsNeverSuperseded() {
    let poison = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-poison",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 1,
      payloadRevisionMs: 1,
      isPermissionPoison: true
    )
    // Poison can still be "pending" status in some isolation paths; flag wins.
    let later = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-later",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [poison, later])
    expectNoDifference(Set(decision.keptIDs), ["tx-poison", "tx-later"])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func deleteDoesNotSupersedeOrGetSupersededByUpsert() {
    let upsert1 = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-up-1",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 1,
      payloadRevisionMs: 1
    )
    let delete = OutboxSupersessionCandidate(
      id: "tx-del",
      entityKeys: [OutboxSupersessionEntityKey(namespace: segmentNS, entityID: "seg-1")],
      opKind: .delete,
      status: .pending,
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let upsert2 = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-up-2",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 3,
      payloadRevisionMs: 3
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [upsert1, delete, upsert2])
    // Upserts still coalesce with each other; delete stays.
    expectNoDifference(Set(decision.keptIDs), ["tx-up-2", "tx-del"])
    expectNoDifference(decision.supersededIDs, ["tx-up-1"])
  }

  @Test
  func mediaIsNeverSuperseded() {
    let media = OutboxSupersessionCandidate(
      id: "tx-media",
      entityKeys: [OutboxSupersessionEntityKey(namespace: "files", entityID: "file-1")],
      opKind: .media,
      status: .pending,
      createdAtMs: 1,
      payloadRevisionMs: 1
    )
    let media2 = OutboxSupersessionCandidate(
      id: "tx-media-2",
      entityKeys: [OutboxSupersessionEntityKey(namespace: "files", entityID: "file-1")],
      opKind: .media,
      status: .pending,
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [media, media2])
    expectNoDifference(Set(decision.keptIDs), ["tx-media", "tx-media-2"])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func multiEntityBatchIsNotEligibleV1() {
    let multi = OutboxSupersessionCandidate(
      id: "tx-multi",
      entityKeys: [
        OutboxSupersessionEntityKey(namespace: recordingNS, entityID: "rec-1"),
        OutboxSupersessionEntityKey(namespace: segmentNS, entityID: "seg-1"),
      ],
      opKind: .upsert,
      status: .pending,
      createdAtMs: 1,
      payloadRevisionMs: 1
    )
    let multi2 = OutboxSupersessionCandidate(
      id: "tx-multi-2",
      entityKeys: [
        OutboxSupersessionEntityKey(namespace: recordingNS, entityID: "rec-1"),
        OutboxSupersessionEntityKey(namespace: segmentNS, entityID: "seg-1"),
      ],
      opKind: .upsert,
      status: .pending,
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [multi, multi2])
    expectNoDifference(Set(decision.keptIDs), ["tx-multi", "tx-multi-2"])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func inFlightToServerIsNotSuperseded() {
    let inFlight = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-inflight",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 1,
      payloadRevisionMs: 1,
      isInFlightToServer: true
    )
    let later = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-later",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [inFlight, later])
    expectNoDifference(Set(decision.keptIDs), ["tx-inflight", "tx-later"])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func confirmedIsNeverSuperseded() {
    let confirmed = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-ok",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 1,
      payloadRevisionMs: 1,
      status: .confirmed
    )
    let later = OutboxSupersessionCandidate.singletonUpsert(
      id: "tx-later",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 2,
      payloadRevisionMs: 2
    )
    let decision = OutboxSameEntitySupersession.decide(entries: [confirmed, later])
    expectNoDifference(Set(decision.keptIDs), ["tx-ok", "tx-later"])
    expectNoDifference(decision.supersededIDs, [])
  }

  // MARK: - Mixed speech load

  @Test
  func speechChurnPlusUnrelatedNeighbors() {
    var entries: [OutboxSupersessionCandidate] = []
    // 50 open-segment updates
    for i in 1...50 {
      entries.append(
        .singletonUpsert(
          id: "tx-seg-\(i)",
          namespace: segmentNS,
          entityID: "seg-open",
          createdAtMs: Int64(i * 3),
          payloadRevisionMs: Int64(1_000 + i)
        )
      )
    }
    // One recording ensure, one delete of another segment, one media
    entries.append(
      .singletonUpsert(
        id: "tx-rec",
        namespace: recordingNS,
        entityID: "rec-1",
        createdAtMs: 1,
        payloadRevisionMs: 1
      )
    )
    entries.append(
      OutboxSupersessionCandidate(
        id: "tx-del-other",
        entityKeys: [OutboxSupersessionEntityKey(namespace: segmentNS, entityID: "seg-old")],
        opKind: .delete,
        status: .pending,
        createdAtMs: 2,
        payloadRevisionMs: 2
      )
    )
    entries.append(
      OutboxSupersessionCandidate(
        id: "tx-media",
        entityKeys: [OutboxSupersessionEntityKey(namespace: "files", entityID: "f1")],
        opKind: .media,
        status: .pending,
        createdAtMs: 3,
        payloadRevisionMs: 3
      )
    )
    // Failed poison from earlier attempt on same segment — keep evidence
    entries.append(
      .singletonUpsert(
        id: "tx-poison",
        namespace: segmentNS,
        entityID: "seg-open",
        createdAtMs: 0,
        payloadRevisionMs: 0,
        status: .failed,
        isPermissionPoison: true
      )
    )

    let decision = OutboxSameEntitySupersession.decide(entries: entries)
    expectNoDifference(
      Set(decision.keptIDs),
      ["tx-seg-50", "tx-rec", "tx-del-other", "tx-media", "tx-poison"]
    )
    #expect(decision.supersededIDs.count == 49)
    #expect(decision.supersededIDSet.contains("tx-seg-1"))
    #expect(decision.supersededIDSet.contains("tx-seg-49"))
    #expect(!decision.supersededIDSet.contains("tx-seg-50"))
  }

  @Test
  func emptyInput() {
    let decision = OutboxSameEntitySupersession.decide(entries: [])
    expectNoDifference(decision.keptIDs, [])
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func isEligibleMatchesRecipeRules() {
    let eligible = OutboxSupersessionCandidate.singletonUpsert(
      id: "ok",
      namespace: segmentNS,
      entityID: "seg-1",
      createdAtMs: 1
    )
    #expect(OutboxSameEntitySupersession.isEligible(eligible))

    var poison = eligible
    poison.id = "poison"
    poison.isPermissionPoison = true
    #expect(!OutboxSameEntitySupersession.isEligible(poison))

    var inFlight = eligible
    inFlight.id = "flight"
    inFlight.isInFlightToServer = true
    #expect(!OutboxSameEntitySupersession.isEligible(inFlight))

    var multi = eligible
    multi.id = "multi"
    multi.entityKeys = [
      OutboxSupersessionEntityKey(namespace: segmentNS, entityID: "a"),
      OutboxSupersessionEntityKey(namespace: segmentNS, entityID: "b"),
    ]
    #expect(!OutboxSameEntitySupersession.isEligible(multi))
  }
}
