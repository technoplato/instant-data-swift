import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: a commit that names an entity the store holds neither before nor after it (the delete of a row that is already
/// gone, or never existed) resolved to no namespace, and the store then refreshed every observer from the whole store.
/// An app that deletes a short-lived row with each final write (a line's live row), and replays those pending writes
/// over each server apply, paid a full refresh of every observer for a change no result can show: an entity with no
/// facts and no references before or after a commit is in no result before it and in none after it.
@Suite(.serialized)
struct InstantUnresolvedEntityRefreshTests {
  /// A delete of a row the store does not hold refreshes no observer whose result is verified.
  @Test
  func aDeleteOfARowTheStoreDoesNotHoldRefreshesNoVerifiedObserver() async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.screenPlans(), in: store)
    defer { readings.forEach { $0.cancel() } }

    try await Self.commit(Self.deleteLiveRow("live-gone", at: 40), to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount, 0)
    expectNoDifference(metrics.splicedObserverCount, 0)
    expectNoDifference(metrics.skippedObserverCount, Self.screenPlans().count)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(
      in: store,
      "after deleting a row the store does not hold"
    )
  }

  /// A line's final (its segment, and the delete of its live row, already gone) refreshes only the results the new
  /// segment can reach: the list and the line's own transcript, not the other recording's transcript or the live rows.
  @Test
  func aFinalThatDeletesAGoneLiveRowRefreshesOnlyWhatItsSegmentReaches() async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.screenPlans(), in: store)
    defer { readings.forEach { $0.cancel() } }

    try await Self.commit(
      Self.finalTransaction(segment: 6, recording: "r1", deletingLiveRow: "live-gone", at: 40),
      to: store
    )

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount + metrics.splicedObserverCount, 2)
    expectNoDifference(metrics.skippedObserverCount, 2)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after the final")
  }

  /// A row the store does not hold, published with an update to a recording the list shows, still lets the list splice
  /// that recording's row in place instead of materializing every row again.
  @Test
  func aGoneRowBesideAnUpdateStillLetsTheListSpliceTheUpdatedRow() async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.screenPlans(), in: store)
    defer { readings.forEach { $0.cancel() } }

    // The same order value, so the row keeps its place and can be spliced.
    let rename = Self.recordingTransaction("r1", title: "Renamed", updatedAtMs: 1, at: 40)
    try await Self.commit(
      InstantStoreTransaction(
        id: "tx-rename-and-gone-row",
        operations: rename.operations + Self.deleteLiveRow("live-gone", at: 40).operations
      ),
      to: store
    )

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.splicedObserverCount, 1)
    expectNoDifference(metrics.rematerializedObserverCount, 0)
    expectNoDifference(metrics.skippedObserverCount, 3)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after the rename")
  }

  /// A snapshot replaced without refreshing observers leaves their results unverified (#654). An unverified observer
  /// may still show the row a delete names, though the store no longer holds it, so it refreshes as before.
  @Test
  func anUnverifiedObserverStillRefreshesForADeleteOfARowTheStoreNoLongerHolds() async throws {
    let store = try await Self.seededStore()
    let plans = Self.screenPlans()
    let readings = await Self.observe(plans, in: store)
    defer { readings.forEach { $0.cancel() } }
    var snapshot = await store.snapshot()
    snapshot.triples.removeAll { $0.entityID == Self.segmentID(5, recording: "r1") }
    await store.replaceSnapshot(snapshot)

    try await Self.commit(Self.deleteSegment(5, recording: "r1", at: 40), to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount + metrics.splicedObserverCount, plans.count)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after deleting the gone segment")
  }

  /// Random finals, interims, renames and deletes, some of rows already gone or never written, alone and in batches
  /// published together: after every publication each observer holds, and was last handed, exactly what a fresh
  /// materialization of its plan returns.
  @Test(arguments: [UInt64(10_071), 10_072, 10_073, 10_074, 10_075, 10_076])
  func everyObserverHoldsAFreshResultThroughWritesThatNameGoneRows(seed: UInt64) async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.screenPlans() + Self.extraPlans(), in: store)
    defer { readings.forEach { $0.cancel() } }
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "seed \(seed) at the start")

    var random = InfiniteWindowRandom(seed: seed)
    var segments: [String: Set<Int>] = ["r1": Set(0..<6), "r2": Set(0..<6)]
    var nextIndex = ["r1": 6, "r2": 6]
    var liveRows: Set<String> = ["live-r1"]
    var time = 100
    for step in 0..<60 {
      let writeCount = random.chance(30) ? random.int(2...4) : 1
      var transactions: [InstantStoreTransaction] = []
      for _ in 0..<writeCount {
        let recording = random.chance(50) ? "r1" : "r2"
        let liveRow = "live-\(recording)-\(random.int(0...3))"
        switch random.int(0...7) {
        case 0, 1:
          let index = nextIndex[recording]!
          nextIndex[recording] = index + 1
          segments[recording]!.insert(index)
          // Half of the finals delete a live row that was written; the rest one that is already gone or never was.
          let written = liveRows.sorted()
          let deleted = random.chance(50) && !written.isEmpty
            ? written[random.int(0...(written.count - 1))]
            : "never-\(time)"
          liveRows.remove(deleted)
          transactions.append(
            Self.finalTransaction(segment: index, recording: recording, deletingLiveRow: deleted, at: time)
          )
        case 2:
          liveRows.insert(liveRow)
          transactions.append(Self.liveRowTransaction(liveRow, recording: recording, index: random.int(0...9), at: time))
        case 3:
          liveRows.remove(liveRow)
          transactions.append(Self.deleteLiveRow(liveRow, at: time))
        case 4:
          transactions.append(
            Self.recordingTransaction(recording, title: "Title \(time)", updatedAtMs: Double(time), at: time)
          )
        case 5:
          // A segment that may be gone already: the delete names it either way.
          let index = random.int(0...(nextIndex[recording]! - 1))
          segments[recording]!.remove(index)
          transactions.append(Self.deleteSegment(index, recording: recording, at: time))
        case 6:
          let shown = segments[recording]!.sorted()
          if !shown.isEmpty {
            let index = shown[random.int(0...(shown.count - 1))]
            transactions.append(Self.segmentWordsTransaction(index, recording: recording, words: time, at: time))
          }
        default:
          transactions.append(Self.deleteLiveRow("never-\(time)", at: time))
        }
        time += 1
      }
      if transactions.count == 1 {
        try await Self.commit(transactions[0], to: store)
      } else {
        for transaction in transactions {
          let prepared = try await store.prepareCurrent(transaction)
          _ = await store.commitDeferringPublication(prepared)
        }
        await store.publishPendingChanges()
      }
      try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "seed \(seed) step \(step)")
    }
  }

  // MARK: - Helpers

  static let recordings = "unresolvedRecordings"
  static let segments = "unresolvedSegments"
  static let liveRows = "unresolvedLiveRows"

  static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: recordings),
    InstantAttribute(id: "\(recordings)/title", namespace: recordings, name: "title", valueType: .string),
    InstantAttribute(
      id: "\(recordings)/updatedAtMs",
      namespace: recordings,
      name: "updatedAtMs",
      valueType: .number,
      isIndexed: true
    ),
    .primaryKey(namespace: segments),
    InstantAttribute(
      id: "\(segments)/recordingID",
      namespace: segments,
      name: "recordingID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(id: "\(segments)/index", namespace: segments, name: "index", valueType: .number, isIndexed: true),
    InstantAttribute(id: "\(segments)/words", namespace: segments, name: "words", valueType: .number),
    InstantAttribute(
      id: "\(segments)/recording",
      namespace: segments,
      name: "recording",
      valueType: .ref,
      cardinality: .one,
      isIndexed: true,
      forwardIdentity: "\(segments)/recording",
      reverseIdentity: "\(recordings)/segments",
      linkNamespace: recordings
    ),
    .primaryKey(namespace: liveRows),
    InstantAttribute(
      id: "\(liveRows)/recordingID",
      namespace: liveRows,
      name: "recordingID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(id: "\(liveRows)/index", namespace: liveRows, name: "index", valueType: .number, isIndexed: true),
  ]

  /// The list (each recording with its two newest segments), each recording's newest segments, and one recording's live
  /// rows: the shape of a recording screen over a recordings list.
  static func screenPlans() -> [InstantQueryPlan] {
    [
      InstantQueryPlan(
        id: "unresolved.list",
        namespace: recordings,
        order: InstantQueryOrder("updatedAtMs", .descending),
        limit: 10,
        includes: [
          InstantQueryInclude(
            "segments",
            direction: .reverse,
            query: InstantQueryPlan(
              id: "unresolved.list.segments",
              namespace: segments,
              order: InstantQueryOrder("index", .descending),
              limit: 2
            )
          )!
        ]
      ),
      window(recording: "r1"),
      window(recording: "r2"),
      InstantQueryPlan(
        id: "unresolved.live.r1",
        namespace: liveRows,
        filters: [.equals(field: "recordingID", value: .string("r1"))],
        order: InstantQueryOrder("index", .ascending),
        limit: 8
      ),
    ]
  }

  /// More shapes for the random test: the other recording's live rows, an offset page, and every live row.
  static func extraPlans() -> [InstantQueryPlan] {
    [
      InstantQueryPlan(
        id: "unresolved.live.r2",
        namespace: liveRows,
        filters: [.equals(field: "recordingID", value: .string("r2"))],
        order: InstantQueryOrder("index", .ascending),
        limit: 8
      ),
      InstantQueryPlan(
        id: "unresolved.page.r1",
        namespace: segments,
        filters: [.equals(field: "recordingID", value: .string("r1"))],
        order: InstantQueryOrder("index", .descending),
        offset: 4,
        limit: 4
      ),
      InstantQueryPlan(id: "unresolved.live.all", namespace: liveRows),
    ]
  }

  static func window(recording: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "unresolved.window.\(recording)",
      namespace: segments,
      filters: [.equals(field: "recordingID", value: .string(recording))],
      order: InstantQueryOrder("index", .descending),
      limit: 4
    )
  }

  /// Two recordings with six segments each, and one live row of r1.
  static func seededStore() async throws -> InstantStore {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    var time = 1
    for recording in ["r1", "r2"] {
      try await commit(recordingTransaction(recording, title: recording, updatedAtMs: Double(time), at: time), to: store)
      time += 1
      for index in 0..<6 {
        try await commit(segmentTransaction(index, recording: recording, at: time), to: store)
        time += 1
      }
    }
    try await commit(liveRowTransaction("live-r1", recording: "r1", index: 6, at: time), to: store)
    return store
  }

  static func observe(_ plans: [InstantQueryPlan], in store: InstantStore) async -> [Task<Void, Never>] {
    var readings: [Task<Void, Never>] = []
    for plan in plans {
      let stream = await store.observe(plan)
      readings.append(Task { for await _ in stream {} })
    }
    return readings
  }

  static func commit(_ transaction: InstantStoreTransaction, to store: InstantStore) async throws {
    let prepared = try await store.prepareCurrent(transaction)
    _ = await store.commitAndPublish(prepared)
  }

  static func segmentID(_ index: Int, recording: String) -> String {
    "segment-\(recording)-\(index)"
  }

  static func insert(
    _ entityID: String,
    _ attributeID: String,
    _ value: InstantValue,
    _ transactionID: String,
    at step: Int
  ) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID,
        value: value,
        txID: transactionID,
        txTime: InstantPageRefreshEnergyTests.time(step)
      )
    )
  }

  static func recordingTransaction(
    _ recording: String,
    title: String,
    updatedAtMs: Double,
    at step: Int
  ) -> InstantStoreTransaction {
    let transactionID = "tx-recording-\(recording)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(recording, InstantAttribute.primaryKeyID(namespace: recordings), .string(recording), transactionID, at: step),
        insert(recording, "\(recordings)/title", .string(title), transactionID, at: step),
        insert(recording, "\(recordings)/updatedAtMs", .number(updatedAtMs), transactionID, at: step),
      ]
    )
  }

  static func segmentOperations(
    _ index: Int,
    recording: String,
    _ transactionID: String,
    at step: Int
  ) -> [InstantTripleOperation] {
    let id = segmentID(index, recording: recording)
    return [
      insert(id, InstantAttribute.primaryKeyID(namespace: segments), .string(id), transactionID, at: step),
      insert(id, "\(segments)/recordingID", .string(recording), transactionID, at: step),
      insert(id, "\(segments)/index", .number(Double(index)), transactionID, at: step),
      insert(id, "\(segments)/words", .number(1), transactionID, at: step),
      insert(id, "\(segments)/recording", .ref(recording), transactionID, at: step),
    ]
  }

  static func segmentTransaction(_ index: Int, recording: String, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-segment-\(recording)-\(index)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: segmentOperations(index, recording: recording, transactionID, at: step)
    )
  }

  static func segmentWordsTransaction(
    _ index: Int,
    recording: String,
    words: Int,
    at step: Int
  ) -> InstantStoreTransaction {
    let transactionID = "tx-words-\(recording)-\(index)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(segmentID(index, recording: recording), "\(segments)/words", .number(Double(words)), transactionID, at: step)
      ]
    )
  }

  /// A line's final: its segment, and the delete of its live row in the same transaction.
  static func finalTransaction(
    segment index: Int,
    recording: String,
    deletingLiveRow liveRow: String,
    at step: Int
  ) -> InstantStoreTransaction {
    let transactionID = "tx-final-\(recording)-\(index)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: segmentOperations(index, recording: recording, transactionID, at: step)
        + [.deleteEntityInNamespace(entityID: liveRow, namespace: liveRows)]
    )
  }

  static func liveRowTransaction(_ id: String, recording: String, index: Int, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-live-\(id)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(id, InstantAttribute.primaryKeyID(namespace: liveRows), .string(id), transactionID, at: step),
        insert(id, "\(liveRows)/recordingID", .string(recording), transactionID, at: step),
        insert(id, "\(liveRows)/index", .number(Double(index)), transactionID, at: step),
      ]
    )
  }

  static func deleteLiveRow(_ id: String, at step: Int) -> InstantStoreTransaction {
    InstantStoreTransaction(
      id: "tx-delete-live-\(id)-\(step)",
      operations: [.deleteEntityInNamespace(entityID: id, namespace: liveRows)]
    )
  }

  static func deleteSegment(_ index: Int, recording: String, at step: Int) -> InstantStoreTransaction {
    InstantStoreTransaction(
      id: "tx-delete-segment-\(recording)-\(index)-\(step)",
      operations: [.deleteEntityInNamespace(entityID: segmentID(index, recording: recording), namespace: segments)]
    )
  }
}
