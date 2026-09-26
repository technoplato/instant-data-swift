import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Writes must cost what they touch, not what the entity holds.
///
/// Scribe links every transcript segment to its recording, and the link fact lives on the
/// recording (`recordings/segments`, one value per segment). Each new segment and each summary
/// update therefore writes to an entity that grows for the whole recording. On 2026-09-24 a
/// 30-minute Mac soak showed `ScribeRecordingLibrary.persist` growing from 0.97 s to 2.88 s per
/// 30 s, with `TripleIndexes.materializedTriples(entityID:)` reached from
/// `PreparedStoreMutation.changedEntityTriples` and `previousChangedEntityTriples`: every write
/// copied, sorted, and re-persisted every link on the recording.
@Suite(.serialized)
struct InstantEntityWriteScopeTests {
  private static let segmentsAttribute = InstantAttribute(
    id: "recordings/segments",
    namespace: "recordings",
    name: "segments",
    valueType: .ref,
    isRequired: false,
    cardinality: .many,
    isIndexed: true,
    isUnique: true,
    forwardIdentity: "recordings/segments",
    reverseIdentity: "transcriptionSegments/recording",
    linkNamespace: "transcriptionSegments"
  )
  private static let updatedAtAttribute = InstantAttribute(
    id: "recordings/updatedAtMs",
    namespace: "recordings",
    name: "updatedAtMs",
    valueType: .number,
    isIndexed: true
  )
  private static let titleAttribute = InstantAttribute(
    id: "recordings/title",
    namespace: "recordings",
    name: "title",
    valueType: .string
  )
  private static let attributes = [segmentsAttribute, updatedAtAttribute, titleAttribute]

  private static func recordingTriples(segmentCount: Int) -> [InstantTriple] {
    let seed = InstantTimestamp(milliseconds: 1)
    var triples = [
      InstantTriple(
        entityID: "recording", attributeID: titleAttribute.id, value: .string("Long recording"),
        txID: "seed", txTime: seed),
      InstantTriple(
        entityID: "recording", attributeID: updatedAtAttribute.id, value: .number(1),
        txID: "seed", txTime: seed),
    ]
    triples += (0..<segmentCount).map { index in
      InstantTriple(
        entityID: "recording", attributeID: segmentsAttribute.id, value: .ref("segment-\(index)"),
        txID: "seed", txTime: seed)
    }
    return triples
  }

  // MARK: - One value into a large multi-value slot

  /// Adding one link must not copy the slot's other links.
  ///
  /// Measured 2026-09-26 (Debug, M1 Max): copying the slot per insert cost 0.041 s for 500
  /// inserts at 2,000 links and 0.27 s at 16,000; in place costs 0.004 s and 0.019 s. The
  /// remaining growth is ordinary dictionary regrowth, so the guard is an absolute bound at a
  /// size where per-insert copying is unmistakable.
  @Test
  func addingOneLinkDoesNotScaleWithTheLinksAlreadyOnTheEntity() {
    func addFiveHundredLinks(toRecordingWith existingCount: Int) -> Duration {
      let attributes = AttributeStore(attributes: Self.attributes)
      var indexes = TripleIndexes(
        triples: Self.recordingTriples(segmentCount: existingCount),
        attributes: attributes
      )
      var changed: Set<String> = []
      let started = ContinuousClock.now
      for index in 0..<500 {
        indexes.applyInsert(
          InstantTriple(
            entityID: "recording", attributeID: Self.segmentsAttribute.id,
            value: .ref("new-segment-\(index)"), txID: "tx-\(index)",
            txTime: InstantTimestamp(milliseconds: 2 + Int64(index))),
          attributes: attributes,
          into: &changed
        )
      }
      let elapsed = ContinuousClock.now - started
      expectNoDifference(indexes.triples(entityID: "recording").count, existingCount + 502)
      return elapsed
    }

    let large = addFiveHundredLinks(toRecordingWith: 32_000)
    #expect(
      large < .milliseconds(150),
      """
      500 single-link inserts cost \(large) with 32,000 existing links (copying the slot per \
      insert measured 0.27 s at 16,000). Inserting one value copied the whole multi-value slot.
      """
    )
  }

  // MARK: - Prepared mutations carry only touched facts

  /// A write that adds one link and updates one field captures and reports only those facts.
  @Test
  func preparedWriteCapturesOnlyTheFactsItTouches() async throws {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: Self.attributes,
        triples: Self.recordingTriples(segmentCount: 5_000)
      )
    )
    let newTime = InstantTimestamp(milliseconds: 9)
    let prepared = try await store.prepareCurrent(
      InstantStoreTransaction(
        id: "segment-write",
        operations: [
          .insert(InstantTriple(
            entityID: "recording", attributeID: Self.updatedAtAttribute.id, value: .number(9),
            txID: "segment-write", txTime: newTime)),
          .insert(InstantTriple(
            entityID: "recording", attributeID: Self.segmentsAttribute.id,
            value: .ref("segment-new"), txID: "segment-write", txTime: newTime)),
        ]
      )
    )

    let before = prepared.previousChangedEntityTriples["recording", default: []]
    let after = prepared.changedEntityTriples["recording", default: []]
    expectNoDifference(
      before.map { "\($0.attributeID)=\($0.value)" }.sorted(),
      ["recordings/updatedAtMs=\(InstantValue.number(1))"]
    )
    expectNoDifference(
      after.map { "\($0.attributeID)=\($0.value)" }.sorted(),
      [
        "recordings/segments=\(InstantValue.ref("segment-new"))",
        "recordings/updatedAtMs=\(InstantValue.number(9))",
      ]
    )

    // The inverse removes exactly what the write added and restores the old field. It never
    // deletes the pre-existing entity.
    let rollback = try #require(
      InstantRuntime.rollbackTransaction(mutationID: "segment-write", prepared: prepared)
    )
    #expect(!rollback.operations.contains { if case .deleteEntity = $0 { true } else { false } })
    expectNoDifference(rollback.operations.count, 3)
  }

  /// Deleting one segment removes one link from its recording; the recording's other links are
  /// neither captured nor rewritten. A cascading link would widen to the whole entity instead
  /// (`deleteEntityCascadesAcrossRelaunchAndPreservesOriginalPendingMutation`).
  @Test
  func deletingASegmentScopesItsRecordingToTheRemovedLink() async throws {
    let segmentText = InstantAttribute(
      id: "transcriptionSegments/text",
      namespace: "transcriptionSegments",
      name: "text",
      valueType: .string
    )
    var triples = Self.recordingTriples(segmentCount: 5_000)
    triples.append(
      InstantTriple(
        entityID: "segment-7", attributeID: segmentText.id, value: .string("hello"),
        txID: "seed", txTime: InstantTimestamp(milliseconds: 1)))
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: Self.attributes + [segmentText], triples: triples)
    )
    let prepared = try await store.prepareCurrent(
      InstantStoreTransaction(id: "delete-segment", operations: [.deleteEntity("segment-7")])
    )

    expectNoDifference(
      prepared.factScope["recording"],
      .facts(attributeIDs: [], values: [Self.segmentsAttribute.id: [.ref("segment-7")]])
    )
    expectNoDifference(
      prepared.previousChangedEntityTriples["recording", default: []].map(\.value),
      [.ref("segment-7")]
    )
    expectNoDifference(prepared.changedEntityTriples["recording", default: []], [])
    expectNoDifference(prepared.factScope["segment-7"], .wholeEntity)
  }

  /// Preparing that write must not materialize, sort, or diff the entity's other facts.
  ///
  /// Measured 2026-09-26 (Debug, M1 Max): whole-entity capture cost 2.0 s for 50 writes at 1,000
  /// links and 33.4 s at 16,000; scoped capture costs 0.010 s and 0.13 s. A ratio cannot tell
  /// the two apart, because what remains is still linear: preparing on a copy of the hot store
  /// copies each large map the write mutates (the link slot, its value index, the reverse-link
  /// index) once per transaction. The absolute bound catches a return to whole-entity work.
  @Test
  func preparingAWriteDoesNotScaleWithTheLinksAlreadyOnTheEntity() async throws {
    func prepareFiftyWrites(onRecordingWith segmentCount: Int) async throws -> Duration {
      let store = InstantStore(
        snapshot: InstantStoreSnapshot(
          attributes: Self.attributes,
          triples: Self.recordingTriples(segmentCount: segmentCount)
        )
      )
      let started = ContinuousClock.now
      for index in 0..<50 {
        let time = InstantTimestamp(milliseconds: 10 + Int64(index))
        let prepared = try await store.prepareCurrent(
          InstantStoreTransaction(
            id: "write-\(index)",
            operations: [
              .insert(InstantTriple(
                entityID: "recording", attributeID: Self.updatedAtAttribute.id,
                value: .number(Double(10 + index)), txID: "write-\(index)", txTime: time)),
              .insert(InstantTriple(
                entityID: "recording", attributeID: Self.segmentsAttribute.id,
                value: .ref("segment-new-\(index)"), txID: "write-\(index)", txTime: time)),
            ]
          )
        )
        _ = prepared.previousChangedEntityTriples
        _ = prepared.changedEntityTriples
        _ = InstantRuntime.rollbackTransaction(mutationID: "write-\(index)", prepared: prepared)
      }
      return ContinuousClock.now - started
    }

    let small = try await prepareFiftyWrites(onRecordingWith: 1_000)
    let large = try await prepareFiftyWrites(onRecordingWith: 16_000)
    #expect(
      large < .seconds(2),
      """
      50 prepared writes cost \(small) on a recording with 1,000 links and \(large) with 16,000 \
      (whole-entity capture measured 33.4 s). A write is materializing, sorting, or diffing \
      every fact on the entity it touches.
      """
    )
  }
}
