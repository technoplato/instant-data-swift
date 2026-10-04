import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #540: a write refreshes only the pages it can change.
///
/// A live timeline's infinite query keeps a page for every 32 rows, and every page has the same filter (the
/// recording). Before 1.9.9 a write to any row that filter matched rebuilt every page that did not already hold the
/// row, so one partial-word save cost 1 + rows/32 page rebuilds: 26 at 800 rows, 45-120 saves a minute while Michael
/// talks (phone-perf's memory audit, 2026-10-04; build 88's MetricKit CPU report from Recording 194 had 8 of 35 samples
/// in `materializePageWithMetrics`). A page that the server's cursors cut cannot take a row that sorts outside them,
/// and a page still waiting for those cursors, or one the server answered empty, is empty whatever the store holds.
@Suite(.serialized)
struct InstantStorePageSkipTests {
  // MARK: - A live timeline's pages

  enum Timeline {
    static let namespace = "sections"
    static let recordingID = InstantAttribute(
      id: "sections/recordingID",
      namespace: namespace,
      name: "recordingID",
      valueType: .string,
      isIndexed: true
    )
    static let segmentIndex = InstantAttribute(
      id: "sections/segmentIndex",
      namespace: namespace,
      name: "segmentIndex",
      valueType: .number,
      isIndexed: true
    )
    static let text = InstantAttribute(
      id: "sections/text",
      namespace: namespace,
      name: "text",
      valueType: .string
    )
    static let pageSize = 32
    /// Four frozen pages of 32 and a live page of 20.
    static let rowCount = 148

    static func id(_ index: Int) -> String {
      "sec-\(String(format: "%04d", index))"
    }

    static func cursor(_ index: Int, inclusive: Bool = false) -> InstantQueryCursor {
      InstantQueryCursor(entityID: id(index), sortValue: .number(Double(index)), inclusive: inclusive)
    }

    static func rowTriples(
      id: String,
      recording: String,
      index: Double,
      text: String,
      txID: String,
      txTime: Int64
    ) -> [InstantTriple] {
      [
        InstantTriple(
          entityID: id,
          attributeID: recordingID.id,
          value: .string(recording),
          txID: txID,
          txTime: InstantTimestamp(milliseconds: txTime)
        ),
        InstantTriple(
          entityID: id,
          attributeID: segmentIndex.id,
          value: .number(index),
          txID: txID,
          txTime: InstantTimestamp(milliseconds: txTime)
        ),
        InstantTriple(
          entityID: id,
          attributeID: Self.text.id,
          value: .string(text),
          txID: txID,
          txTime: InstantTimestamp(milliseconds: txTime)
        ),
      ]
    }

    static func store() -> InstantStore {
      var triples: [InstantTriple] = []
      for index in 0..<rowCount {
        triples += rowTriples(
          id: id(index),
          recording: "rec-a",
          index: Double(index),
          text: "line \(index)",
          txID: "seed-\(index)",
          txTime: 1_000 + Int64(index)
        )
      }
      for index in 0..<10 {
        triples += rowTriples(
          id: "other-\(index)",
          recording: "rec-b",
          index: Double(index),
          text: "other \(index)",
          txID: "seed-other-\(index)",
          txTime: 2_000 + Int64(index)
        )
      }
      return InstantStore(
        snapshot: InstantStoreSnapshot(attributes: [recordingID, segmentIndex, text], triples: triples)
      )
    }

    static let filter = InstantQueryFilter.equals(field: recordingID.name, value: .string("rec-a"))

    /// Upstream `freezeForward`'s page: after the previous page's end, before its own end inclusive, no limit, with
    /// the server's cursors at its first and last rows.
    static func frozenPage(_ page: Int) -> (plan: InstantQueryPlan, remotePageInfo: InstantQueryRemotePageInfo) {
      let first = page * pageSize
      let last = first + pageSize - 1
      return (
        InstantQueryPlan(
          id: "timeline.frozen.\(page)",
          namespace: namespace,
          filters: [filter],
          order: InstantQueryOrder(segmentIndex.name),
          after: page == 0 ? cursor(0, inclusive: true) : cursor(first - 1),
          before: cursor(last, inclusive: true)
        ),
        .ready(
          InstantQueryPageInfo(
            startCursor: cursor(first),
            endCursor: cursor(last),
            hasPreviousPage: page > 0,
            hasNextPage: true
          )
        )
      )
    }

    /// Upstream `pushNewForward`'s page at the bottom of the timeline: after the last frozen page, limit 32, which the
    /// server answered with rows 128-147.
    static func livePage() -> (plan: InstantQueryPlan, remotePageInfo: InstantQueryRemotePageInfo) {
      (
        InstantQueryPlan(
          id: "timeline.live",
          namespace: namespace,
          filters: [filter],
          order: InstantQueryOrder(segmentIndex.name),
          limit: pageSize,
          after: cursor(4 * pageSize - 1)
        ),
        .ready(
          InstantQueryPageInfo(
            startCursor: cursor(4 * pageSize),
            endCursor: cursor(rowCount - 1),
            hasPreviousPage: true,
            hasNextPage: false
          )
        )
      )
    }

    /// Another recording's page, which no write to this recording matches.
    static func otherRecordingPage() -> InstantQueryPlan {
      InstantQueryPlan(
        id: "timeline.other-recording",
        namespace: namespace,
        filters: [.equals(field: recordingID.name, value: .string("rec-b"))],
        order: InstantQueryOrder(segmentIndex.name),
        limit: 10
      )
    }
  }

  /// The pages a test observes, the last emission each published, and the streams that keep them observed.
  actor ObservedPages {
    private(set) var lastEmissionByQueryID: [String: InstantQueryEmission] = [:]
    private var streams: [AsyncStream<InstantQueryEmission>] = []

    func observe(
      _ plan: InstantQueryPlan,
      remotePageInfo: InstantQueryRemotePageInfo?,
      in store: InstantStore
    ) async throws {
      let stream = await store.observe(plan, remotePageInfo: remotePageInfo)
      var iterator = stream.makeAsyncIterator()
      let initial = try #require(await iterator.next())
      streams.append(stream)
      lastEmissionByQueryID[plan.id] = initial
    }

    func record(_ emissions: [InstantQueryEmission]) {
      for emission in emissions {
        lastEmissionByQueryID[emission.queryID] = emission
      }
    }

    func emission(_ queryID: String) -> InstantQueryEmission? {
      lastEmissionByQueryID[queryID]
    }
  }

  static func commit(
    _ operations: [InstantTripleOperation],
    id: String,
    to store: InstantStore,
    pages: ObservedPages
  ) async throws -> (emissions: [InstantQueryEmission], metrics: InstantStorePublishMetrics) {
    let prepared = try await store.prepareCurrent(InstantStoreTransaction(id: id, operations: operations))
    let committed = await store.commitAndPublish(prepared)
    await pages.record(committed.result.emissions)
    return (committed.result.emissions, await store.lastPublishMetrics)
  }

  static func observeTimeline(_ store: InstantStore) async throws -> ObservedPages {
    let pages = ObservedPages()
    for page in 0..<4 {
      let frozen = Timeline.frozenPage(page)
      try await pages.observe(frozen.plan, remotePageInfo: frozen.remotePageInfo, in: store)
    }
    let live = Timeline.livePage()
    try await pages.observe(live.plan, remotePageInfo: live.remotePageInfo, in: store)
    try await pages.observe(Timeline.otherRecordingPage(), remotePageInfo: nil, in: store)
    return pages
  }

  @Test
  func theTimelinesPagesShowTheirServerRanges() async throws {
    let store = Timeline.store()
    let pages = try await Self.observeTimeline(store)
    for page in 0..<4 {
      let emission = try #require(await pages.emission("timeline.frozen.\(page)"))
      expectNoDifference(
        emission.values.map(\.id),
        (page * 32..<(page + 1) * 32).map(Timeline.id)
      )
    }
    let live = try #require(await pages.emission("timeline.live"))
    expectNoDifference(live.values.map(\.id), (128..<148).map(Timeline.id))
  }

  @Test
  func aSaveToTheNewestSectionSplicesTheLivePageAndSkipsTheFrozenOnes() async throws {
    let store = Timeline.store()
    let pages = try await Self.observeTimeline(store)
    let saved = try await Self.commit(
      [
        .insert(
          InstantTriple(
            entityID: Timeline.id(147),
            attributeID: Timeline.text.id,
            value: .string("line 147, and more words"),
            txID: "save-147",
            txTime: InstantTimestamp(milliseconds: 5_000)
          )
        )
      ],
      id: "save-147",
      to: store,
      pages: pages
    )
    // Four frozen pages and the other recording's page cannot take section 147; the live page holds it.
    expectNoDifference(saved.metrics.skippedObserverCount, 5)
    expectNoDifference(saved.metrics.splicedObserverCount, 1)
    expectNoDifference(saved.metrics.rematerializedObserverCount, 0)
    expectNoDifference(saved.emissions.map(\.queryID), ["timeline.live"])
    let live = try #require(await pages.emission("timeline.live"))
    expectNoDifference(live.values.last?.values[Timeline.text.name], .one(.string("line 147, and more words")))
    try await Self.expectEveryPageEqualsItsRematerialization(store: store, pages: pages)
  }

  @Test
  func aNewSectionPastTheLivePagesServerEndRefreshesNoPage() async throws {
    let store = Timeline.store()
    let pages = try await Self.observeTimeline(store)
    let appended = try await Self.commit(
      Timeline.rowTriples(
        id: Timeline.id(148),
        recording: "rec-a",
        index: 148,
        text: "line 148",
        txID: "append-148",
        txTime: 5_000
      ).map(InstantTripleOperation.insert),
      id: "append-148",
      to: store,
      pages: pages
    )
    // Section 148 sorts after the live page's server end cursor, so that page leaves it out until the server answers
    // with a new end, as upstream `instaql.ts` cuts a non-leading page. No page can change.
    expectNoDifference(appended.metrics.skippedObserverCount, 6)
    expectNoDifference(appended.metrics.splicedObserverCount, 0)
    expectNoDifference(appended.metrics.rematerializedObserverCount, 0)
    expectNoDifference(appended.emissions, [])
    try await Self.expectEveryPageEqualsItsRematerialization(store: store, pages: pages)
  }

  @Test
  func aRowThatSortsInsideAFrozenPageRefreshesThatPageOnly() async throws {
    let store = Timeline.store()
    let pages = try await Self.observeTimeline(store)
    let inserted = try await Self.commit(
      Timeline.rowTriples(
        id: "sec-0040b",
        recording: "rec-a",
        index: 40.5,
        text: "a correction between 40 and 41",
        txID: "insert-40.5",
        txTime: 5_000
      ).map(InstantTripleOperation.insert),
      id: "insert-40.5",
      to: store,
      pages: pages
    )
    expectNoDifference(inserted.metrics.skippedObserverCount, 5)
    expectNoDifference(inserted.metrics.rematerializedObserverCount, 1)
    expectNoDifference(inserted.emissions.map(\.queryID), ["timeline.frozen.1"])
    let page = try #require(await pages.emission("timeline.frozen.1"))
    expectNoDifference(
      page.values.map(\.id),
      (32...40).map(Timeline.id) + ["sec-0040b"] + (41...63).map(Timeline.id)
    )
    try await Self.expectEveryPageEqualsItsRematerialization(store: store, pages: pages)
  }

  @Test
  func aPageWaitingForTheServerOrAnsweredEmptyIsNotRefreshed() async throws {
    let store = Timeline.store()
    let pages = ObservedPages()
    let frozen = Timeline.frozenPage(0)
    var waiting = frozen.plan
    waiting.id = "timeline.waiting"
    try await pages.observe(waiting, remotePageInfo: .waiting, in: store)
    var answeredEmpty = frozen.plan
    answeredEmpty.id = "timeline.answered-empty"
    try await pages.observe(
      answeredEmpty,
      remotePageInfo: .ready(
        InstantQueryPageInfo(startCursor: nil, endCursor: nil, hasPreviousPage: false, hasNextPage: false)
      ),
      in: store
    )
    expectNoDifference(await pages.emission("timeline.waiting")?.values, [])
    expectNoDifference(await pages.emission("timeline.answered-empty")?.values, [])
    let saved = try await Self.commit(
      [
        .insert(
          InstantTriple(
            entityID: Timeline.id(0),
            attributeID: Timeline.text.id,
            value: .string("line 0, edited"),
            txID: "edit-0",
            txTime: InstantTimestamp(milliseconds: 5_000)
          )
        )
      ],
      id: "edit-0",
      to: store,
      pages: pages
    )
    expectNoDifference(saved.metrics.skippedObserverCount, 2)
    expectNoDifference(saved.metrics.rematerializedObserverCount, 0)
    try await Self.expectEveryPageEqualsItsRematerialization(store: store, pages: pages)
  }

  // MARK: - Rows that stop matching

  /// A row the page does not show can still change it by leaving the rows its filters match: an offset page's window
  /// moves up, and a limited page loses its next page. 1.9.8 asked only whether the row matches after the write.
  @Test
  func aRowThatStopsMatchingRefreshesTheLocalPagesItShifts() async throws {
    var triples: [InstantTriple] = []
    for (index, id) in ["a1", "a2", "a3"].enumerated() {
      triples += [
        InstantTriple(
          entityID: id,
          attributeID: Items.group.id,
          value: .string("a"),
          txID: "seed-\(id)",
          txTime: InstantTimestamp(milliseconds: 1_000 + Int64(index))
        ),
        InstantTriple(
          entityID: id,
          attributeID: Items.rank.id,
          value: .number(Double(index + 1)),
          txID: "seed-\(id)",
          txTime: InstantTimestamp(milliseconds: 1_000 + Int64(index))
        ),
      ]
    }
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Items.fields, triples: triples))
    let groupA = InstantQueryFilter.equals(field: Items.group.name, value: .string("a"))
    let limited = InstantQueryPlan(
      id: "items.limited",
      namespace: Items.namespace,
      filters: [groupA],
      order: InstantQueryOrder(Items.rank.name),
      limit: 2
    )
    let offset = InstantQueryPlan(
      id: "items.offset",
      namespace: Items.namespace,
      filters: [groupA],
      order: InstantQueryOrder(Items.rank.name),
      offset: 1,
      limit: 1
    )
    let pages = ObservedPages()
    try await pages.observe(limited, remotePageInfo: nil, in: store)
    try await pages.observe(offset, remotePageInfo: nil, in: store)
    expectNoDifference(await pages.emission(limited.id)?.values.map(\.id), ["a1", "a2"])
    expectNoDifference(await pages.emission(limited.id)?.pageInfo?.hasNextPage, true)
    expectNoDifference(await pages.emission(offset.id)?.values.map(\.id), ["a2"])

    // a3 leaves group a: neither page shows it, and neither has a next page any more.
    _ = try await Self.commit(
      [
        .insert(
          InstantTriple(
            entityID: "a3",
            attributeID: Items.group.id,
            value: .string("b"),
            txID: "move-a3",
            txTime: InstantTimestamp(milliseconds: 2_000)
          )
        )
      ],
      id: "move-a3",
      to: store,
      pages: pages
    )
    expectNoDifference(await pages.emission(limited.id)?.values.map(\.id), ["a1", "a2"])
    expectNoDifference(await pages.emission(limited.id)?.pageInfo?.hasNextPage, false)
    expectNoDifference(await pages.emission(offset.id)?.pageInfo?.hasNextPage, false)

    // a1 leaves group a: only a2 is left, so the offset page, which skips the first row, is empty.
    _ = try await Self.commit(
      [
        .insert(
          InstantTriple(
            entityID: "a1",
            attributeID: Items.group.id,
            value: .string("b"),
            txID: "move-a1",
            txTime: InstantTimestamp(milliseconds: 2_001)
          )
        )
      ],
      id: "move-a1",
      to: store,
      pages: pages
    )
    for plan in [limited, offset] {
      let expected = await store.materializePage(plan)
      let emission = await pages.emission(plan.id)
      expectNoDifference(emission?.values, expected.values, "\(plan.id)")
      expectNoDifference(emission?.pageInfo, expected.pageInfo, "\(plan.id)")
    }
    expectNoDifference(await pages.emission(offset.id)?.values.map(\.id), [])
  }

  // MARK: - Differential property test

  /// Every page equals a full rematerialization after every random write, so a page the store skipped still shows
  /// what it would have rebuilt. The pages are random shapes (filters, orders, cursors with and without sort values,
  /// offsets, `first`, `last` and `limit` alone and together, no page info, waiting, or the server's cursors), the
  /// writes random inserts, field changes, retractions, deletes and writes to another namespace. The test also counts
  /// the pages skipped that 1.9.8 would have rebuilt (a changed row matched the page's filters), so it fails on a store
  /// that never skips by range.
  @Test
  func everyPageEqualsItsRematerializationAfterEveryRandomWrite() async throws {
    var rangeSkips = 0
    var refreshes = 0
    var comparisons = 0
    for seed in UInt64(0)..<UInt64(24) {
      let outcome = try await Self.runDifferentialSeed(seed, steps: 30, pageCount: 24)
      rangeSkips += outcome.rangeSkips
      refreshes += outcome.refreshes
      comparisons += outcome.comparisons
      if outcome.failed { break }
    }
    #expect(
      rangeSkips > 0,
      "No page was skipped that a changed row's filter match would have rebuilt (\(refreshes) refreshes, \(comparisons) comparisons)."
    )
  }

  struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  enum Items {
    static let namespace = "items"
    static let group = InstantAttribute(
      id: "items/group",
      namespace: namespace,
      name: "group",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    )
    static let rank = InstantAttribute(
      id: "items/rank",
      namespace: namespace,
      name: "rank",
      valueType: .number,
      isRequired: false,
      isIndexed: true
    )
    static let score = InstantAttribute(
      id: "items/score",
      namespace: namespace,
      name: "score",
      valueType: .number,
      isRequired: false
    )
    static let label = InstantAttribute(
      id: "items/label",
      namespace: namespace,
      name: "label",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    )
    static let otherName = InstantAttribute(
      id: "others/name",
      namespace: "others",
      name: "name",
      valueType: .string,
      isRequired: false
    )
    static let fields = [group, rank, score, label]
    static let groups = ["a", "b", "c"]
    static let labels = ["a", "A", "b", "B", "ä", "c"]

    static func randomValue(for attribute: InstantAttribute, using rng: inout SplitMix64) -> InstantValue {
      switch attribute.id {
      case group.id:
        return .string(groups.randomElement(using: &rng)!)
      case rank.id:
        return .number(Double(Int.random(in: 0..<12, using: &rng)))
      case score.id:
        return .number(Double(Int.random(in: 0..<12, using: &rng)) / 2)
      default:
        return .string(labels.randomElement(using: &rng)!)
      }
    }
  }

  struct DifferentialOutcome {
    var rangeSkips = 0
    var refreshes = 0
    var comparisons = 0
    var failed = false
  }

  static func runDifferentialSeed(
    _ seed: UInt64,
    steps: Int,
    pageCount: Int
  ) async throws -> DifferentialOutcome {
    var rng = SplitMix64(state: seed &* 0x2545_F491_4F6C_DD1D &+ 1)
    var outcome = DifferentialOutcome()
    var txTime: Int64 = 1_000
    var nextEntity = 0
    func newEntityID(_ rng: inout SplitMix64) -> String {
      nextEntity += 1
      // Random hex prefixes, so the entity ID tie-break does not follow creation order.
      return String(format: "%04lx-%03ld", Int.random(in: 0..<0xFFFF, using: &rng), nextEntity)
    }

    var seedTriples: [InstantTriple] = []
    for _ in 0..<30 {
      let id = newEntityID(&rng)
      txTime += 1
      var wroteField = false
      for attribute in Items.fields where Double.random(in: 0..<1, using: &rng) < 0.85 {
        wroteField = true
        seedTriples.append(
          InstantTriple(
            entityID: id,
            attributeID: attribute.id,
            value: Items.randomValue(for: attribute, using: &rng),
            txID: "seed-\(seed)-\(id)",
            txTime: InstantTimestamp(milliseconds: txTime)
          )
        )
      }
      if !wroteField {
        seedTriples.append(
          InstantTriple(
            entityID: id,
            attributeID: Items.group.id,
            value: .string("a"),
            txID: "seed-\(seed)-\(id)",
            txTime: InstantTimestamp(milliseconds: txTime)
          )
        )
      }
    }
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: Items.fields + [Items.otherName],
        triples: seedTriples
      )
    )

    var model = await currentModel(of: store)
    var planByID: [String: (plan: InstantQueryPlan, remotePageInfo: InstantQueryRemotePageInfo?)] = [:]
    let pages = ObservedPages()
    for index in 0..<pageCount {
      let page = randomPage(index: index, seed: seed, model: model, using: &rng)
      planByID[page.plan.id] = page
      try await pages.observe(page.plan, remotePageInfo: page.remotePageInfo, in: store)
    }

    // The runtime commits a write under its gate and publishes after it (#473): commits made before a publication are
    // published together. About half the steps commit that way, published after one to three commits.
    var tickets: [InstantStorePublicationTicket] = []
    var deferredChangedEntityIDs: Set<String> = []
    var deferredOperations: [InstantTripleOperation] = []
    var publishAfter = 1
    var previous = await pages.lastEmissionByQueryID
    var previousModel = model
    for step in 0..<steps {
      txTime += 1
      let operations = randomOperations(model: model, txTime: txTime, step: step, newEntityID: newEntityID, using: &rng)
      let transactionID = "step-\(seed)-\(step)"
      if tickets.isEmpty {
        previous = await pages.lastEmissionByQueryID
        previousModel = model
      }
      let prepared = try await store.prepareCurrent(
        InstantStoreTransaction(id: transactionID, operations: operations)
      )
      var changedEntityIDs = prepared.result.changedEntityIDs
      let refreshedQueryIDs: Set<String>
      if Bool.random(using: &rng) {
        let committed = await store.commitDeferringPublication(prepared)
        if let ticket = committed.publication { tickets.append(ticket) }
        deferredChangedEntityIDs.formUnion(changedEntityIDs)
        deferredOperations += operations
        if tickets.count == 1 { publishAfter = Int.random(in: 1...3, using: &rng) }
        model = await currentModel(of: store)
        guard tickets.count >= publishAfter || step == steps - 1 else { continue }
        var emissions: [InstantQueryEmission] = []
        for ticket in tickets {
          emissions = await store.publishCommittedChanges(ticket)
        }
        await pages.record(emissions)
        refreshedQueryIDs = Set(emissions.map(\.queryID))
        changedEntityIDs = deferredChangedEntityIDs
        tickets = []
        deferredChangedEntityIDs = []
      } else {
        if !tickets.isEmpty {
          // An immediate commit publishes the pending ones first; take their emissions as the runtime would.
          var emissions: [InstantQueryEmission] = []
          for ticket in tickets {
            emissions = await store.publishCommittedChanges(ticket)
          }
          await pages.record(emissions)
          tickets = []
          deferredChangedEntityIDs = []
          deferredOperations = []
          previous = await pages.lastEmissionByQueryID
          previousModel = await currentModel(of: store)
        }
        let committed = await store.commitAndPublish(prepared)
        await pages.record(committed.result.emissions)
        refreshedQueryIDs = Set(committed.result.emissions.map(\.queryID))
        model = await currentModel(of: store)
      }
      let publishedOperations = deferredOperations.isEmpty ? operations : deferredOperations
      deferredOperations = []
      outcome.refreshes += refreshedQueryIDs.count
      // 1.9.8 skipped a namespace-local page only when no changed row is an item, or none matched its filters.
      let itemsChanged = changedEntityIDs.contains { model.rows[$0] != nil || previousModel.rows[$0] != nil }

      for (queryID, page) in planByID.sorted(by: { $0.key < $1.key }) {
        let expected = await store.materializePage(page.plan, remotePageInfo: page.remotePageInfo)
        let actual = await pages.emission(queryID)
        outcome.comparisons += 1
        if actual?.values != expected.values || actual?.pageInfo != expected.pageInfo {
          Issue.record(
            """
            Seed \(seed), step \(step): page \(queryID) shows \(actual?.values.map(\.id) ?? []) \
            (\(String(describing: actual?.pageInfo))) but rematerializes to \(expected.values.map(\.id)) \
            (\(String(describing: expected.pageInfo))). Refreshed: \(refreshedQueryIDs.contains(queryID)). \
            Plan: \(page.plan). Remote page info: \(String(describing: page.remotePageInfo)). \
            Operations: \(publishedOperations).
            """
          )
          outcome.failed = true
          return outcome
        }
        guard !refreshedQueryIDs.contains(queryID), itemsChanged else { continue }
        let filterMatches = await store.materialize(
          InstantQueryPlan(id: "probe.\(queryID)", namespace: Items.namespace, filters: page.plan.filters)
        )
        let matchingIDs = Set(filterMatches.map(\.id))
        let heldIDs = Set(previous[queryID]?.values.map(\.id) ?? [])
        if page.plan.filters.isEmpty
          || !matchingIDs.isDisjoint(with: changedEntityIDs)
          || !heldIDs.isDisjoint(with: changedEntityIDs)
        {
          outcome.rangeSkips += 1
        }
      }
    }
    return outcome
  }

  struct Model {
    /// Item ID → attribute ID → value.
    var rows: [String: [String: InstantValue]] = [:]
    var otherIDs: [String] = []
  }

  static func currentModel(of store: InstantStore) async -> Model {
    var model = Model()
    for triple in await store.snapshot().triples {
      if triple.attributeID == Items.otherName.id {
        model.otherIDs.append(triple.entityID)
      } else {
        model.rows[triple.entityID, default: [:]][triple.attributeID] = triple.value
      }
    }
    return model
  }

  static func randomCursor(
    model: Model,
    order: InstantQueryOrder,
    using rng: inout SplitMix64
  ) -> InstantQueryCursor {
    let ids = model.rows.keys.sorted()
    let id = Double.random(in: 0..<1, using: &rng) < 0.85
      ? ids.randomElement(using: &rng)!
      : "ffff-\(Int.random(in: 0..<999, using: &rng))"
    let inclusive = Bool.random(using: &rng)
    let roll = Double.random(in: 0..<1, using: &rng)
    if roll < 0.12 {
      return InstantQueryCursor(entityID: id, sortValue: nil, inclusive: inclusive)
    }
    if roll < 0.17 {
      return InstantQueryCursor(entityID: id, sortValue: .null, inclusive: inclusive)
    }
    let attribute = Items.fields.first { $0.name == order.field }
    if let attribute {
      let value = roll < 0.75
        ? (model.rows[id]?[attribute.id] ?? Items.randomValue(for: attribute, using: &rng))
        : Items.randomValue(for: attribute, using: &rng)
      return InstantQueryCursor(entityID: id, sortValue: value, inclusive: inclusive)
    }
    // Server creation time: the seed and the steps write at 1,001 ms and after.
    return InstantQueryCursor(
      entityID: id,
      sortValue: .number(Double(1_000 + Int.random(in: 0..<80, using: &rng))),
      inclusive: inclusive
    )
  }

  static func randomPage(
    index: Int,
    seed: UInt64,
    model: Model,
    using rng: inout SplitMix64
  ) -> (plan: InstantQueryPlan, remotePageInfo: InstantQueryRemotePageInfo?) {
    let orders: [InstantQueryOrder?] = [
      InstantQueryOrder(Items.rank.name),
      InstantQueryOrder(Items.rank.name, .descending),
      InstantQueryOrder(Items.score.name),
      InstantQueryOrder(Items.score.name, .descending),
      InstantQueryOrder(Items.label.name),
      InstantQueryOrder(Items.label.name, .descending),
      .serverCreatedAt,
      .serverCreatedAtDescending,
      nil,
    ]
    let order = orders.randomElement(using: &rng)!
    let effectiveOrder = order ?? .serverCreatedAt

    let filters: [InstantQueryFilter]
    switch Double.random(in: 0..<1, using: &rng) {
    case ..<0.25:
      filters = []
    case ..<0.6:
      filters = [.equals(field: Items.group.name, value: .string(Items.groups.randomElement(using: &rng)!))]
    case ..<0.7:
      filters = [.greaterThanOrEqual(field: Items.rank.name, value: .number(Double(Int.random(in: 0..<12, using: &rng))))]
    case ..<0.8:
      filters = [
        .or([
          .equals(field: Items.group.name, value: .string("a")),
          .lessThan(field: Items.rank.name, value: .number(3)),
        ])
      ]
    case ..<0.9:
      filters = [.in(field: Items.group.name, values: [.string("a"), .string("b")])]
    default:
      filters = [Bool.random(using: &rng) ? .isNull(field: Items.label.name) : .isNotNull(field: Items.label.name)]
    }

    func count() -> Int { Int.random(in: 1...6, using: &rng) }
    func cursor() -> InstantQueryCursor { randomCursor(model: model, order: effectiveOrder, using: &rng) }

    var offset: Int?
    var limit: Int?
    var first: Int?
    var last: Int?
    var after: InstantQueryCursor?
    var before: InstantQueryCursor?
    switch Int.random(in: 0..<17, using: &rng) {
    case 0: break
    case 1: limit = count()
    case 2: first = count()
    case 3: last = count()
    case 4: first = count(); last = count()
    case 5: limit = count(); last = count()
    case 6: offset = Int.random(in: 1...4, using: &rng); limit = count()
    case 7: after = cursor()
    case 8: after = cursor(); limit = count()
    case 9: before = cursor()
    case 10: before = cursor(); last = count()
    case 11: after = cursor(); before = cursor()
    case 12: after = cursor(); before = cursor(); limit = count()
    // Both ends kept from a cut: the server's cursors do not settle these.
    case 13: after = cursor(); first = count(); last = count()
    case 14: before = cursor(); limit = count(); last = count()
    case 15: offset = Int.random(in: 1...4, using: &rng); first = count(); last = count()
    default: offset = Int.random(in: 1...4, using: &rng)
    }
    let selectedFields: [String]? = Double.random(in: 0..<1, using: &rng) < 0.2
      ? [Items.group.name, Items.label.name]
      : nil

    let plan = InstantQueryPlan(
      id: "page-\(seed)-\(index)",
      namespace: Items.namespace,
      filters: filters,
      order: order,
      offset: offset,
      limit: limit,
      first: first,
      after: after,
      last: last,
      before: before,
      selectedFields: selectedFields
    )

    let remotePageInfo: InstantQueryRemotePageInfo?
    switch Double.random(in: 0..<1, using: &rng) {
    case ..<0.3:
      remotePageInfo = nil
    case ..<0.4:
      remotePageInfo = .waiting
    case ..<0.47:
      remotePageInfo = .ready(
        InstantQueryPageInfo(startCursor: nil, endCursor: nil, hasPreviousPage: false, hasNextPage: false)
      )
    default:
      remotePageInfo = .ready(
        InstantQueryPageInfo(
          startCursor: cursor(),
          endCursor: Double.random(in: 0..<1, using: &rng) < 0.9 ? cursor() : nil,
          hasPreviousPage: Bool.random(using: &rng),
          hasNextPage: Bool.random(using: &rng)
        )
      )
    }
    return (plan, remotePageInfo)
  }

  static func randomOperations(
    model: Model,
    txTime: Int64,
    step: Int,
    newEntityID: (inout SplitMix64) -> String,
    using rng: inout SplitMix64
  ) -> [InstantTripleOperation] {
    let txID = "tx-\(step)-\(txTime)"
    let time = InstantTimestamp(milliseconds: txTime)
    var operations: [InstantTripleOperation] = []
    let ids = model.rows.keys.sorted()
    for _ in 0..<Int.random(in: 1...3, using: &rng) {
      let roll = Double.random(in: 0..<1, using: &rng)
      if roll < 0.28 || ids.isEmpty {
        let id = newEntityID(&rng)
        var wroteField = false
        for attribute in Items.fields where Double.random(in: 0..<1, using: &rng) < 0.85 {
          wroteField = true
          operations.append(
            .insert(
              InstantTriple(
                entityID: id,
                attributeID: attribute.id,
                value: Items.randomValue(for: attribute, using: &rng),
                txID: txID,
                txTime: time
              )
            )
          )
        }
        if !wroteField {
          operations.append(
            .insert(
              InstantTriple(entityID: id, attributeID: Items.group.id, value: .string("b"), txID: txID, txTime: time)
            )
          )
        }
      } else if roll < 0.66 {
        let id = ids.randomElement(using: &rng)!
        let attribute = Items.fields.randomElement(using: &rng)!
        operations.append(
          .insert(
            InstantTriple(
              entityID: id,
              attributeID: attribute.id,
              value: Items.randomValue(for: attribute, using: &rng),
              txID: txID,
              txTime: time
            )
          )
        )
      } else if roll < 0.74 {
        // The same value again: the row's fields do not change.
        let id = ids.randomElement(using: &rng)!
        if let field = model.rows[id]?.sorted(by: { $0.key < $1.key }).randomElement(using: &rng) {
          operations.append(
            .insert(InstantTriple(entityID: id, attributeID: field.key, value: field.value, txID: txID, txTime: time))
          )
        }
      } else if roll < 0.84 {
        let id = ids.randomElement(using: &rng)!
        if let field = model.rows[id]?.sorted(by: { $0.key < $1.key }).randomElement(using: &rng) {
          operations.append(
            .retract(InstantTriple(entityID: id, attributeID: field.key, value: field.value, txID: txID, txTime: time))
          )
        }
      } else if roll < 0.93 {
        operations.append(.deleteEntity(ids.randomElement(using: &rng)!))
      } else {
        operations.append(
          .insert(
            InstantTriple(
              entityID: model.otherIDs.randomElement(using: &rng) ?? "other-\(step)",
              attributeID: Items.otherName.id,
              value: .string("other \(step)"),
              txID: txID,
              txTime: time
            )
          )
        )
      }
    }
    return operations
  }

  static func expectEveryPageEqualsItsRematerialization(
    store: InstantStore,
    pages: ObservedPages
  ) async throws {
    let observed = await pages.lastEmissionByQueryID
    var plans: [String: (InstantQueryPlan, InstantQueryRemotePageInfo?)] = [:]
    for page in 0..<4 {
      let frozen = Timeline.frozenPage(page)
      plans[frozen.plan.id] = (frozen.plan, frozen.remotePageInfo)
    }
    let live = Timeline.livePage()
    plans[live.plan.id] = (live.plan, live.remotePageInfo)
    plans[Timeline.otherRecordingPage().id] = (Timeline.otherRecordingPage(), nil)
    var waiting = Timeline.frozenPage(0).plan
    waiting.id = "timeline.waiting"
    plans[waiting.id] = (waiting, .waiting)
    var answeredEmpty = Timeline.frozenPage(0).plan
    answeredEmpty.id = "timeline.answered-empty"
    plans[answeredEmpty.id] = (
      answeredEmpty,
      .ready(InstantQueryPageInfo(startCursor: nil, endCursor: nil, hasPreviousPage: false, hasNextPage: false))
    )
    for (queryID, emission) in observed.sorted(by: { $0.key < $1.key }) {
      let (plan, remotePageInfo) = try #require(plans[queryID])
      let expected = await store.materializePage(plan, remotePageInfo: remotePageInfo)
      expectNoDifference(emission.values, expected.values, "\(queryID)")
      expectNoDifference(emission.pageInfo, expected.pageInfo, "\(queryID)")
    }
  }
}
