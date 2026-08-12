import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Characterization of the live-speech memory balloon (#044 / #155).
///
/// User invariant: every speech revision is a versioned put of one stable live
/// object. Connected peers still receive every revision. Domain cardinality and
/// view observation must not grow with revision count.
///
/// Instant TypeScript: `upstream/instant/client/packages/core/src/store.ts`
/// (`createStore`, EAV/AEV maps) and `Reactor.js` (`querySubs`, per-query
/// result stores). SQLite Data: `upstream/sqlite-data/Sources/SQLiteData/Fetch.swift`
/// plus `FetchKeyRequest.fetch(_:)` which runs SQL against SQLite and
/// invalidates by table.
///
/// Instant Swift Data instead rematerializes observers from the in-memory
/// `TripleIndexes` of the whole namespace on every `commitAndPublish`. These
/// tests record that current shape so a later live/finalized split can fail
/// them closed.
@Suite(.serialized)
struct InstantSameEntityLiveRevisionTests {
  private let revisionCount = 10_000
  private let siblingCount = 2_000

  @Test
  func tenThousandSameEntityPutsKeepCardinalityOne() async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Self.segmentAttributes))
    let baseline = try await applyLiveRevision(store: store, revision: 1, text: "I")
    expectNoDifference(baseline.result.tripleCount, 2)
    expectNoDifference(baseline.result.changedEntityIDs, ["segment-live"])

    var last = baseline
    for revision in 2...revisionCount {
      last = try await applyLiveRevision(
        store: store,
        revision: revision,
        text: String(repeating: "w", count: min(revision, 64))
      )
    }

    expectNoDifference(last.result.tripleCount, 2)
    expectNoDifference(last.result.changedEntityIDs, ["segment-live"])
    let live = await store.materialize(
      InstantQueryPlan(id: "live-only", namespace: "segments")
    )
    expectNoDifference(live.count, 1)
    expectNoDifference(live.first?.id, "segment-live")
    expectNoDifference(live.first?.string("text"), String(repeating: "w", count: 64))
  }

  @Test
  func unboundedNamespaceObservationRematerializesEverySiblingOnEachLivePut() async throws {
    let seed = Self.siblingTriples(count: siblingCount) + [
      Self.liveTriple(revision: 0, text: "")
    ]
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: Self.segmentAttributes, triples: seed)
    )
    let plan = InstantQueryPlan(id: "all-segments", namespace: "segments")
    let initial = await store.materialize(plan)
    expectNoDifference(initial.count, siblingCount + 1)
    let observation = await store.observe(plan)
    var iterator = observation.makeAsyncIterator()
    let seeded = await iterator.next()
    expectNoDifference(seeded?.values.count, siblingCount + 1)

    let first = try await applyLiveRevision(
      store: store,
      revision: 1,
      text: "I",
      publishing: true
    )
    expectNoDifference(first.result.emissions.count, 1)
    expectNoDifference(first.result.emissions.first?.values.count, siblingCount + 1)

    let later = try await applyLiveRevision(
      store: store,
      revision: 2,
      text: "I think",
      publishing: true
    )
    expectNoDifference(later.result.emissions.first?.values.count, siblingCount + 1)
    expectNoDifference(later.result.tripleCount, (siblingCount + 1) * 2)
  }

  @Test
  func rematerializeCostGrowsWithSiblingHistoryNotWithLiveRevisionNumber() async throws {
    func averageMaterializeNanoseconds(siblingCount: Int) async throws -> (
      averageNanoseconds: Double,
      lastCount: Int
    ) {
      let seed = Self.siblingTriples(count: siblingCount) + [
        Self.liveTriple(revision: 0, text: "")
      ]
      let store = InstantStore(
        snapshot: InstantStoreSnapshot(attributes: Self.segmentAttributes, triples: seed)
      )
      _ = try await applyLiveRevision(store: store, revision: 1, text: "I")
      return await store.measureMaterializeAverageNanoseconds(
        InstantQueryPlan(id: "all-segments", namespace: "segments"),
        iterations: 12
      )
    }

    let small = try await averageMaterializeNanoseconds(siblingCount: 100)
    let large = try await averageMaterializeNanoseconds(siblingCount: siblingCount)
    expectNoDifference(small.lastCount, 101)
    expectNoDifference(large.lastCount, siblingCount + 1)
    #expect(
      large.averageNanoseconds > small.averageNanoseconds * 1.5,
      """
      Materializing every segment cost \(small.averageNanoseconds) ns for 101 rows and \
      \(large.averageNanoseconds) ns for \(siblingCount + 1) rows. InstantStore walks the \
      in-memory TripleIndexes for the whole namespace (InstantStore.materialize). SQLite Data \
      FetchKeyRequest would SQL-select only live rows. This is the recording balloon: \
      observation work tracks finalized history, not the one live segment.
      """
    )
  }

  @Test
  func snapshotReconstructsEveryTripleWhileEntityLookupStaysLocal() async throws {
    let seed = Self.siblingTriples(count: siblingCount) + [
      Self.liveTriple(revision: 0, text: "I")
    ]
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: Self.segmentAttributes, triples: seed)
    )
    _ = try await applyLiveRevision(store: store, revision: 1, text: "I think")

    let snapshotStarted = DispatchTime.now().uptimeNanoseconds
    let snapshot = await store.snapshot()
    let snapshotElapsed = DispatchTime.now().uptimeNanoseconds - snapshotStarted
    expectNoDifference(snapshot.triples.count, (siblingCount + 1) * 2)

    let localStarted = DispatchTime.now().uptimeNanoseconds
    let liveTriples = await store.materialize(
      InstantQueryPlan(id: "live-one", namespace: "segments", limit: 1)
    )
    let localElapsed = DispatchTime.now().uptimeNanoseconds - localStarted
    expectNoDifference(liveTriples.count, 1)
    #expect(
      snapshotElapsed > localElapsed,
      """
      InstantStore.snapshot() walked every triple (\(snapshotElapsed) ns) while a one-row \
      materialize took \(localElapsed) ns. Upstream SQLite Data never builds a full-graph \
      snapshot to answer a FetchKeyRequest. Instant TypeScript querySubs store per-query \
      results, not a second full triple array.
      """
    )
  }
}

extension InstantSameEntityLiveRevisionTests {
  fileprivate static let segmentAttributes = [
    InstantAttribute(
      id: "segments/text",
      namespace: "segments",
      name: "text",
      valueType: .string,
      cardinality: .one
    ),
    InstantAttribute(
      id: "segments/revision",
      namespace: "segments",
      name: "revision",
      valueType: .number,
      cardinality: .one
    ),
  ]

  fileprivate static func liveTriple(revision: Int, text: String) -> InstantTriple {
    InstantTriple(
      entityID: "segment-live",
      attributeID: "segments/text",
      value: .string(text),
      txID: "seed-live",
      txTime: InstantTimestamp(milliseconds: Int64(revision))
    )
  }

  fileprivate static func siblingTriples(count: Int) -> [InstantTriple] {
    (0..<count).flatMap { index in
      [
        InstantTriple(
          entityID: "segment-final-\(index)",
          attributeID: "segments/text",
          value: .string("final-\(index)"),
          txID: "seed-final-\(index)",
          txTime: InstantTimestamp(milliseconds: 1)
        ),
        InstantTriple(
          entityID: "segment-final-\(index)",
          attributeID: "segments/revision",
          value: .number(Double(index)),
          txID: "seed-final-\(index)",
          txTime: InstantTimestamp(milliseconds: 1)
        ),
      ]
    }
  }
}

private func applyLiveRevision(
  store: InstantStore,
  revision: Int,
  text: String,
  publishing: Bool = false
) async throws -> PreparedStoreMutation {
  let timestamp = InstantTimestamp(milliseconds: Int64(revision + 1_000))
  let transaction = InstantStoreTransaction(
    id: "live-\(revision)",
    operations: [
      .insert(
        InstantTriple(
          entityID: "segment-live",
          attributeID: "segments/text",
          value: .string(text),
          txID: "live-\(revision)",
          txTime: timestamp
        )
      ),
      .insert(
        InstantTriple(
          entityID: "segment-live",
          attributeID: "segments/revision",
          value: .number(Double(revision)),
          txID: "live-\(revision)",
          txTime: timestamp
        )
      ),
    ]
  )
  let prepared = try await store.prepareCurrent(transaction)
  if publishing {
    return await store.commitAndPublish(prepared)
  }
  return await store.commit(prepared)
}

private extension InstantEntitySnapshot {
  func string(_ field: String) -> String? {
    guard case let .string(value) = values[field]?.first else { return nil }
    return value
  }
}
