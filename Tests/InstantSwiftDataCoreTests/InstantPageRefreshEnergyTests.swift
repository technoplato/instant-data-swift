import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #654: a long list kept as pages, each page an observer of the same filtered query. Every write that a page's filters
/// admitted re-ran every page, so each interim transcript write, and its echo, re-ran every page of a long transcript
/// though only the newest page shows the line being written.
@Suite(.serialized)
struct InstantPageRefreshEnergyTests {
  /// An update that leaves an entity in its result sets at its place refreshes only the page that shows it (#654).
  @Test
  func anUpdateThatKeepsAnEntitysPlaceRefreshesOnlyThePageThatShowsIt() async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Self.attributes))
    for index in 0..<24 {
      try await Self.writeSegment(index, recording: "r1", wordCount: 1, at: index + 1, to: store)
    }
    let pages = (0..<6).map { Self.offsetPage(recording: "r1", page: $0, size: 4) }
    var readings: [Task<Void, Never>] = []
    for plan in pages {
      let stream = await store.observe(plan)
      readings.append(Task { for await _ in stream {} })
    }
    defer { readings.forEach { $0.cancel() } }

    try await Self.writeSegment(23, recording: "r1", wordCount: 2, at: 30, to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(
      metrics.splicedObserverCount + metrics.rematerializedObserverCount,
      1,
      "only the first page shows segment 23"
    )
    expectNoDifference(metrics.skippedObserverCount, 5)
    try await Self.expectEveryObserverIsCurrent(in: store, "after the update")
  }

  /// Random writes, alone and in batches published together, against offset pages, newest-first windows, an unfiltered
  /// window and cursor-bounded pages of two recordings: after every publication each observer holds, and was last
  /// handed, exactly what a fresh materialization of its plan returns (#654).
  @Test(arguments: [UInt64(6_541), 6_542, 6_543, 6_544, 6_545, 6_546])
  func everyObserverHoldsAFreshResultThroughRandomWrites(seed: UInt64) async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Self.attributes))
    var random = InfiniteWindowRandom(seed: seed)
    var segments: [Int: (recording: String, wordCount: Int)] = [:]
    var time = 1
    for index in 0..<24 {
      let recording = index % 3 == 0 ? "r2" : "r1"
      segments[index] = (recording, 1)
      try await Self.writeSegment(index, recording: recording, wordCount: 1, at: time, to: store)
      time += 1
    }
    var readings: [Task<Void, Never>] = []
    for (plan, remotePageInfo) in Self.observedPlans() {
      let stream = await store.observe(plan, remotePageInfo: remotePageInfo)
      readings.append(Task { for await _ in stream {} })
    }
    defer { readings.forEach { $0.cancel() } }
    try await Self.expectEveryObserverIsCurrent(in: store, "seed \(seed) at the start")

    var nextIndex = 24
    for step in 0..<80 {
      let writeCount = random.chance(25) ? random.int(2...4) : 1
      var transactions: [InstantStoreTransaction] = []
      for _ in 0..<writeCount {
        let existing = segments.keys.sorted()
        let kind = existing.isEmpty ? 0 : random.int(0...6)
        let index = existing.isEmpty ? nextIndex : existing[random.int(0...(existing.count - 1))]
        switch kind {
        case 0, 1:
          let recording = random.chance(50) ? "r1" : "r2"
          segments[nextIndex] = (recording, 1)
          transactions.append(Self.segmentTransaction(nextIndex, recording: recording, wordCount: 1, at: time))
          nextIndex += 1
        case 2, 3:
          let segment = segments[index]!
          segments[index] = (segment.recording, segment.wordCount + 1)
          transactions.append(
            Self.segmentTransaction(index, recording: segment.recording, wordCount: segment.wordCount + 1, at: time)
          )
        case 4:
          let segment = segments[index]!
          let recording = segment.recording == "r1" ? "r2" : "r1"
          segments[index] = (recording, segment.wordCount)
          transactions.append(
            Self.segmentTransaction(index, recording: recording, wordCount: segment.wordCount, at: time)
          )
        case 5:
          transactions.append(Self.orderTransaction(index, to: Double(random.int(0...(nextIndex + 8))) + 0.5, at: time))
        default:
          segments[index] = nil
          transactions.append(
            InstantStoreTransaction(
              id: "tx-delete-\(index)-\(time)",
              operations: [.deleteEntityInNamespace(entityID: Self.segmentID(index), namespace: Self.namespace)]
            )
          )
        }
        time += 1
      }
      if transactions.count == 1 {
        let prepared = try await store.prepareCurrent(transactions[0])
        _ = await store.commitAndPublish(prepared)
      } else {
        for transaction in transactions {
          let prepared = try await store.prepareCurrent(transaction)
          _ = await store.commitDeferringPublication(prepared)
        }
        await store.publishPendingChanges()
      }
      try await Self.expectEveryObserverIsCurrent(in: store, "seed \(seed) step \(step)")
    }
  }

  /// A snapshot replaced without refreshing observers leaves their results unverified, so the next write refreshes
  /// them as the check before #654 did, even one that changes an entity no page shows (#654).
  @Test
  func aReplacedSnapshotIsNotABaselineForTheSkip() async throws {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Self.attributes))
    for index in 0..<20 {
      try await Self.writeSegment(index, recording: "r1", wordCount: 1, at: index + 1, to: store)
    }
    let pages = (0..<3).map { Self.offsetPage(recording: "r1", page: $0, size: 4) }
    var readings: [Task<Void, Never>] = []
    for plan in pages {
      let stream = await store.observe(plan)
      readings.append(Task { for await _ in stream {} })
    }
    defer { readings.forEach { $0.cancel() } }
    var snapshot = await store.snapshot()
    snapshot.triples.removeAll { $0.entityID == Self.segmentID(19) }
    await store.replaceSnapshot(snapshot)

    // Segment 2 is on no page, and keeps its place.
    try await Self.writeSegment(2, recording: "r1", wordCount: 2, at: 30, to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount, 3)
    try await Self.expectEveryObserverIsCurrent(in: store, "after the replaced snapshot")
  }

  // MARK: - Helpers

  static let namespace = "energyPages"

  static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: namespace),
    InstantAttribute(
      id: "\(namespace)/recordingID",
      namespace: namespace,
      name: "recordingID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(namespace)/index",
      namespace: namespace,
      name: "index",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(id: "\(namespace)/wordCount", namespace: namespace, name: "wordCount", valueType: .number),
  ]

  static func segmentID(_ index: Int) -> String {
    "segment-\(index)"
  }

  static func time(_ step: Int) -> InstantTimestamp {
    InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(step) * 1_000)
  }

  /// Page `page` of a recording's segments, newest first, `size` to a page, by offset.
  static func offsetPage(recording: String, page: Int, size: Int) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "energy.pages.\(recording).offset.\(page)",
      namespace: namespace,
      filters: [.equals(field: "recordingID", value: .string(recording))],
      order: InstantQueryOrder("index", .descending),
      offset: page == 0 ? nil : page * size,
      limit: size
    )
  }

  /// Every plan the random test observes, with the remote page info its observer starts from.
  static func observedPlans() -> [(InstantQueryPlan, InstantQueryRemotePageInfo?)] {
    var plans: [(InstantQueryPlan, InstantQueryRemotePageInfo?)] = []
    for recording in ["r1", "r2"] {
      plans += (0..<4).map { (offsetPage(recording: recording, page: $0, size: 3), nil) }
      plans.append(
        (
          InstantQueryPlan(
            id: "energy.pages.\(recording).newest",
            namespace: namespace,
            filters: [.equals(field: "recordingID", value: .string(recording))],
            order: InstantQueryOrder("index", .descending),
            limit: 4
          ),
          nil
        )
      )
      // A frozen chunk, as an infinite query keeps one: the rows between two server cursors.
      let start = InstantQueryCursor(entityID: segmentID(15), sortValue: .number(15), inclusive: true)
      let end = InstantQueryCursor(entityID: segmentID(6), sortValue: .number(6), inclusive: true)
      plans.append(
        (
          InstantQueryPlan(
            id: "energy.pages.\(recording).frozen",
            namespace: namespace,
            filters: [.equals(field: "recordingID", value: .string(recording))],
            order: InstantQueryOrder("index", .descending),
            after: start,
            before: end
          ),
          .ready(InstantQueryPageInfo(startCursor: start, endCursor: end, hasPreviousPage: true, hasNextPage: true))
        )
      )
    }
    plans.append(
      (
        InstantQueryPlan(
          id: "energy.pages.oldest",
          namespace: namespace,
          order: InstantQueryOrder("index", .ascending),
          limit: 5
        ),
        nil
      )
    )
    return plans
  }

  static func segmentTransaction(
    _ index: Int,
    recording: String,
    wordCount: Int,
    at step: Int
  ) -> InstantStoreTransaction {
    let id = segmentID(index)
    let transactionID = "tx-segment-\(index)-\(step)"
    func insert(_ name: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(namespace)/\(name)",
          value: value,
          txID: transactionID,
          txTime: time(step)
        )
      )
    }
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
            value: .string(id),
            txID: transactionID,
            txTime: time(step)
          )
        ),
        insert("recordingID", .string(recording)),
        insert("index", .number(Double(index))),
        insert("wordCount", .number(Double(wordCount))),
      ]
    )
  }

  static func orderTransaction(_ index: Int, to value: Double, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-order-\(index)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        .insert(
          InstantTriple(
            entityID: segmentID(index),
            attributeID: "\(namespace)/index",
            value: .number(value),
            txID: transactionID,
            txTime: time(step)
          )
        )
      ]
    )
  }

  static func writeSegment(
    _ index: Int,
    recording: String,
    wordCount: Int,
    at step: Int,
    to store: InstantStore
  ) async throws {
    let prepared = try await store.prepareCurrent(
      segmentTransaction(index, recording: recording, wordCount: wordCount, at: step)
    )
    _ = await store.commitAndPublish(prepared)
  }

  /// Each observer's result, and the result it was last handed, equal a fresh materialization of its plan.
  static func expectEveryObserverIsCurrent(in store: InstantStore, _ description: String) async throws {
    let observed = await store.observerResultsForTesting()
    #expect(!observed.isEmpty)
    for result in observed {
      let fresh = await store.materializeEmission(result.plan, remotePageInfo: result.remotePageInfo)
      expectNoDifference(result.values, fresh.values, "\(description): \(result.plan.id) holds a stale result")
      expectNoDifference(result.pageInfo, fresh.pageInfo, "\(description): \(result.plan.id) holds stale page info")
      expectNoDifference(
        result.handedValues,
        fresh.values,
        "\(description): \(result.plan.id) was handed a stale result"
      )
      expectNoDifference(
        result.handedPageInfo,
        fresh.pageInfo,
        "\(description): \(result.plan.id) was handed stale page info"
      )
    }
  }
}
