import CustomDump
import InstantSwiftDataCore
import Testing

/// Source-compatibility coverage for the retired queue-wide projection.
///
/// Real eligibility is covered by `InstantOutboxSupersessionIntegrationTests`,
/// which exercises the exact durable tail, normalized assignment shape,
/// rollback, claims, barriers, aliases, restart, and delivery.
@Suite
struct OutboxSameEntitySupersessionTests {
  @Test
  func legacyDecisionNeverDropsOrReordersCandidates() {
    let entries = legacyCandidates()

    let decision = OutboxSameEntitySupersession.decide(entries: entries)

    expectNoDifference(decision.keptIDs, entries.map(\.id))
    expectNoDifference(decision.supersededIDs, [])
  }

  @Test
  func legacyApplicationAndCoalescingAreConservativeNoOps() {
    let entries = legacyCandidates()
    let unsafeHistoricalDecision = OutboxSupersessionDecision(
      keptIDs: ["newest-payload"],
      supersededIDs: ["older-tail", "delete-barrier"]
    )

    expectNoDifference(
      OutboxSameEntitySupersession.applying(unsafeHistoricalDecision, to: entries),
      entries
    )
    expectNoDifference(
      OutboxSameEntitySupersession.coalescing(entries: entries),
      entries
    )
  }

  @Test
  func legacyProjectionCannotAuthorizeReplacementOrUsePayloadRevision() {
    let entries = legacyCandidates()

    #expect(entries.allSatisfy { !OutboxSameEntitySupersession.isEligible($0) })
    expectNoDifference(
      entries.sorted(by: OutboxSameEntitySupersession.intentOrder).map(\.id),
      ["newest-payload", "delete-barrier", "older-tail"]
    )
  }

  private func legacyCandidates() -> [OutboxSupersessionCandidate] {
    [
      .init(
        id: "older-tail",
        entityKeys: [.init(namespace: "segments", entityID: "segment")],
        opKind: .upsert,
        createdAtMs: 30,
        payloadRevisionMs: 1
      ),
      .init(
        id: "delete-barrier",
        entityKeys: [.init(namespace: "segments", entityID: "segment")],
        opKind: .delete,
        createdAtMs: 20,
        payloadRevisionMs: 2
      ),
      .init(
        id: "newest-payload",
        entityKeys: [.init(namespace: "segments", entityID: "segment")],
        opKind: .upsert,
        createdAtMs: 10,
        payloadRevisionMs: 999
      ),
    ]
  }
}
