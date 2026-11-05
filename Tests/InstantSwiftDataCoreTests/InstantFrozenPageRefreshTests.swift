import Foundation
import Testing

@testable import InstantSwiftDataCore

// History:
// - 2026-11-04: #1513: an infinite query freezes each full page as a live query between two cursors with no limit
//   (upstream `freezeForward`), so a 2,000-line transcript is eight frozen pages. Each new line of the recording entered
//   every frozen page's result set (it matches the page's filter), so each page was materialized again, from every line
//   of the recording or every line the device holds, for a line none of them could show. These tests hold the cost
//   (no frozen page refreshes for a line outside its cursors) and, over random writes inside and outside the pages, the
//   result (every observer equals a fresh materialization). Equality is asserted with `#expect`, which a release run
//   judges.

/// The live recording's transcript as an infinite query holds it (#1513): three frozen pages of 256 lines between
/// cursors, the live page of the 40 lines after them, and the newest lines by index; another recording's lines beside
/// it.
@Suite(.serialized)
struct InstantFrozenPageRefreshTests {
  /// A final line beyond the frozen pages is placed by the live page and the newest-lines window; no frozen page is
  /// materialized again, and none is refreshed.
  @Test
  func aFinalLineBeyondTheFrozenPagesLeavesThemAsTheyAre() async throws {
    var fixture = FrozenPageFixture()
    let store = try await fixture.seededStore()
    let readings = await fixture.observeEveryPage(in: store)
    defer { readings.forEach { $0.cancel() } }

    try await SpliceFixture.commit(fixture.newLine(recording: FrozenPageFixture.live), to: store)

    let metrics = await store.lastPublishMetrics
    #expect(metrics.rematerializedObserverCount == 0, "\(metrics)")
    // The three frozen pages, the live page (the line is past the server's last row of it) and the other recording's
    // window; the newest-lines window places the line.
    #expect(metrics.skippedObserverCount == 5, "\(metrics)")
    #expect(metrics.splicedObserverCount == 1, "\(metrics)")
    try await SpliceFixture.expectEveryObserverIsFresh(in: store, "after the final")
  }

  /// A line written below the newest, inside a frozen page's cursors (a second writer's line, #1117), is shown by that
  /// page: the page is refreshed and shows it.
  @Test
  func aLineInsideAFrozenPagesCursorsRefreshesThatPage() async throws {
    var fixture = FrozenPageFixture()
    let store = try await fixture.seededStore()
    let readings = await fixture.observeEveryPage(in: store)
    defer { readings.forEach { $0.cancel() } }

    try await SpliceFixture.commit(
      fixture.line(recording: FrozenPageFixture.live, index: 300.5, text: "a line written below the newest"),
      to: store
    )

    let observed = await store.observerResultsForTesting()
    let page = try #require(observed.first { $0.plan.id == "frozen.page.1" })
    #expect(page.values.contains { $0.id == FrozenPageFixture.lineID(FrozenPageFixture.live, 300.5) })
    try await SpliceFixture.expectEveryObserverIsFresh(in: store, "after the line below the newest")
  }

  /// Random new lines (at the end, inside a page, on a page's boundary value), edits, deletes, lines that move, lines
  /// of the other recording, and new server page info for the pages: after every publication each observer holds, and
  /// was last handed, exactly what a fresh materialization of its plan returns.
  @Test(arguments: [UInt64(15_200), 15_201, 15_202, 15_203, 15_204, 15_205])
  func everyFrozenPageHoldsAFreshResultThroughRandomWrites(seed: UInt64) async throws {
    var fixture = FrozenPageFixture()
    let store = try await fixture.seededStore()
    let readings = await fixture.observeEveryPage(in: store)
    defer { readings.forEach { $0.cancel() } }
    try await SpliceFixture.expectEveryObserverIsFresh(in: store, "seed \(seed) at the start")

    var random = InfiniteWindowRandom(seed: seed)
    for step in 0..<80 {
      let writeCount = random.chance(25) ? random.int(2...4) : 1
      var transactions: [InstantStoreTransaction] = []
      for _ in 0..<writeCount {
        transactions.append(fixture.randomWrite(&random))
      }
      var pageInfo: [InstantLiveQueryResultReplacement] = []
      if random.chance(15) {
        let page = random.int(0...(FrozenPageFixture.frozenPageCount - 1))
        pageInfo.append(fixture.serverPageInfo(page: page, shiftedBy: random.int(-2...2)))
      }
      for (offset, transaction) in transactions.enumerated() {
        let prepared = try await store.prepareCurrent(transaction)
        _ = await store.commitDeferringPublication(
          prepared,
          installingLiveQueryPageInfo: offset == transactions.count - 1 ? pageInfo : []
        )
      }
      await store.publishPendingChanges()
      try await SpliceFixture.expectEveryObserverIsFresh(in: store, "seed \(seed) step \(step)")
    }
  }
}

/// Two recordings' lines and the pages an infinite query over the live recording's transcript holds (#1513).
struct FrozenPageFixture {
  static let lines = "frozenLines"
  static let pageSize = 256
  static let frozenPageCount = 3
  static let live = 0
  static let other = 1
  static let otherLineCount = 300
  /// The live page's lines when the store is seeded, after the frozen pages'.
  static let livePageLineCount = 40

  private var step = 100
  /// The indexes each recording holds, in the order they were written.
  private var indexes: [[Double]] = [
    (0..<(FrozenPageFixture.pageSize * FrozenPageFixture.frozenPageCount + FrozenPageFixture.livePageLineCount))
      .map(Double.init),
    (0..<FrozenPageFixture.otherLineCount).map(Double.init),
  ]
  private var deleted: Set<String> = []

  static let attributes: [InstantAttribute] = {
    func scalar(_ name: String, _ type: InstantValueType, indexed: Bool = false) -> InstantAttribute {
      InstantAttribute(id: "\(lines)/\(name)", namespace: lines, name: name, valueType: type, isIndexed: indexed)
    }
    return [
      .primaryKey(namespace: lines),
      scalar("recordingID", .string, indexed: true),
      scalar("index", .number, indexed: true),
      scalar("text", .string),
      scalar("updatedAtMs", .number, indexed: true),
    ]
  }()

  static func recordingID(_ recording: Int) -> String { "frozen-recording-\(recording)" }

  static func lineID(_ recording: Int, _ index: Double) -> String {
    index == index.rounded() ? "frozen-line-\(recording)-\(Int(index))" : "frozen-line-\(recording)-\(index)"
  }

  // MARK: - Plans

  /// Frozen page `page`: the lines after the previous page's last line (the first page from line 0, inclusive) up to and
  /// including its own last line, oldest first, with no limit, as `freezeForward` subscribes it.
  static func frozenPage(_ page: Int) -> InstantQueryPlan {
    let first = page * pageSize
    let last = first + pageSize - 1
    return InstantQueryPlan(
      id: "frozen.page.\(page)",
      namespace: lines,
      filters: [.equals(field: "recordingID", value: .string(recordingID(live)))],
      order: InstantQueryOrder("index", .ascending),
      after: page == 0
        ? cursor(live, 0, inclusive: true)
        : cursor(live, Double(first - 1), inclusive: false),
      before: cursor(live, Double(last), inclusive: true)
    )
  }

  /// The live page after the frozen ones: the next 256 lines after the last frozen line.
  static func livePage() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "frozen.live-page",
      namespace: lines,
      filters: [.equals(field: "recordingID", value: .string(recordingID(live)))],
      order: InstantQueryOrder("index", .ascending),
      limit: pageSize,
      after: cursor(live, Double(pageSize * frozenPageCount - 1), inclusive: false)
    )
  }

  /// The live recording's newest 64 lines by index, as the transcript's tail reads them.
  static func newestLines() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "frozen.newest",
      namespace: lines,
      filters: [.equals(field: "recordingID", value: .string(recordingID(live)))],
      order: InstantQueryOrder("index", .descending),
      limit: 64
    )
  }

  /// The other recording's oldest 32 lines.
  static func otherRecordingWindow() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "frozen.other",
      namespace: lines,
      filters: [.equals(field: "recordingID", value: .string(recordingID(other)))],
      order: InstantQueryOrder("index", .ascending),
      limit: 32
    )
  }

  static func cursor(_ recording: Int, _ index: Double, inclusive: Bool) -> InstantQueryCursor {
    InstantQueryCursor(entityID: lineID(recording, index), sortValue: .number(index), inclusive: inclusive)
  }

  /// The page info the server reports for frozen page `page`: its first and last lines, moved `shift` lines (the server
  /// restating the page after lines came or went).
  func serverPageInfo(page: Int, shiftedBy shift: Int = 0) -> InstantLiveQueryResultReplacement {
    let first = Double(max(0, page * Self.pageSize + shift))
    let last = Double(page * Self.pageSize + Self.pageSize - 1 + shift)
    return InstantLiveQueryResultReplacement(
      key: "frozen.page.\(page).key",
      triples: [],
      pageInfo: InstantQueryPageInfo(
        startCursor: Self.cursor(Self.live, first, inclusive: true),
        endCursor: Self.cursor(Self.live, last, inclusive: true),
        hasPreviousPage: page > 0,
        hasNextPage: true
      )
    )
  }

  /// Observes the frozen pages and the live page as live queries with the server's page info, and the two windows as
  /// local observers.
  func observeEveryPage(in store: InstantStore) async -> [Task<Void, Never>] {
    var readings = await SpliceFixture.observe([Self.newestLines(), Self.otherRecordingWindow()], in: store)
    for page in 0..<Self.frozenPageCount {
      let lease = await store.observeLiveQueryLease(
        Self.frozenPage(page),
        registrationKey: "frozen.page.\(page).key",
        remotePageInfo: .ready(serverPageInfo(page: page).pageInfo!)
      )
      readings.append(Task { for await _ in lease.stream {} })
    }
    let firstLive = Double(Self.pageSize * Self.frozenPageCount)
    let live = await store.observeLiveQueryLease(
      Self.livePage(),
      registrationKey: "frozen.live-page.key",
      remotePageInfo: .ready(
        InstantQueryPageInfo(
          startCursor: Self.cursor(Self.live, firstLive, inclusive: true),
          endCursor: Self.cursor(Self.live, firstLive + Double(Self.livePageLineCount - 1), inclusive: true),
          hasPreviousPage: true,
          hasNextPage: false
        )
      )
    )
    readings.append(Task { for await _ in live.stream {} })
    return readings
  }

  // MARK: - Store

  mutating func seededStore() async throws -> InstantStore {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Self.attributes))
    for recording in [Self.live, Self.other] {
      let operations = indexes[recording].flatMap { index in
        Self.lineOperations(recording: recording, index: index, text: "line \(index)", updatedAtMs: index)
      }
      try await SpliceFixture.commit(transaction(operations), to: store)
    }
    return store
  }

  // MARK: - Writes

  /// The recording's next line, after its newest.
  mutating func newLine(recording: Int) -> InstantStoreTransaction {
    let index = (indexes[recording].max() ?? -1).rounded(.down) + 1
    return line(recording: recording, index: index, text: "line \(index)")
  }

  /// A new line with `index`, which another line already has: its id orders the two.
  mutating func twin(recording: Int, index: Double) -> InstantStoreTransaction {
    let id = "frozen-line-\(recording)-\(Int(index))-\(step % 2 == 0 ? "a" : "z")\(step)"
    return transaction(
      SpliceFixture.entity(
        id,
        Self.lines,
        [
          "recordingID": .string(Self.recordingID(recording)),
          "index": .number(index),
          "text": .string("twin \(step)"),
          "updatedAtMs": .number(Double(step)),
        ]
      )
    )
  }

  /// A line at `index`, new or written again.
  mutating func line(recording: Int, index: Double, text: String) -> InstantStoreTransaction {
    if !indexes[recording].contains(index) {
      indexes[recording].append(index)
    }
    deleted.remove(Self.lineID(recording, index))
    return transaction(Self.lineOperations(recording: recording, index: index, text: text, updatedAtMs: Double(step)))
  }

  mutating func randomWrite(_ random: inout InfiniteWindowRandom) -> InstantStoreTransaction {
    let recording = random.chance(80) ? Self.live : Self.other
    let lastFrozen = Self.pageSize * Self.frozenPageCount - 1
    switch random.int(0...9) {
    case 0, 1, 2:
      return newLine(recording: recording)
    case 3:
      // A line written below the newest, inside a page, or a second line with a page's first or last index, which its
      // id places before or after that line.
      guard random.chance(50) else {
        return line(recording: recording, index: Double(random.int(0...lastFrozen)) + 0.5, text: "written below \(step)")
      }
      let boundary = max(0, Double(random.int(0...Self.frozenPageCount) * Self.pageSize) - (random.chance(50) ? 1 : 0))
      return twin(recording: recording, index: boundary)
    case 4, 5:
      // A line edited, shown or not.
      let index = indexes[recording][random.int(0...(indexes[recording].count - 1))]
      return line(recording: recording, index: index, text: "edit \(step)")
    case 6:
      // A line deleted.
      let index = indexes[recording][random.int(0...(indexes[recording].count - 1))]
      let id = Self.lineID(recording, index)
      guard deleted.insert(id).inserted else { return newLine(recording: recording) }
      return transaction([.deleteEntityInNamespace(entityID: id, namespace: Self.lines)])
    case 7:
      // A line moves: its index changes, into a page, out of one, or past the last one.
      let index = indexes[recording][random.int(0...(indexes[recording].count - 1))]
      let id = Self.lineID(recording, index)
      guard !deleted.contains(id) else { return newLine(recording: recording) }
      let moved = Double(random.int(0...(lastFrozen + 40))) + 0.25
      return transaction([SpliceFixture.insert(id, "\(Self.lines)/index", .number(moved))])
    case 8:
      // A line moves to the other recording, or back.
      let index = indexes[recording][random.int(0...(indexes[recording].count - 1))]
      let id = Self.lineID(recording, index)
      guard !deleted.contains(id) else { return newLine(recording: recording) }
      let target = random.chance(50) ? Self.live : Self.other
      return transaction([SpliceFixture.insert(id, "\(Self.lines)/recordingID", .string(Self.recordingID(target)))])
    default:
      // Several new lines at once, as a frame that restates a few.
      var operations: [InstantTripleOperation] = []
      for _ in 0..<random.int(2...5) {
        let index = (indexes[recording].max() ?? -1).rounded(.down) + 1
        indexes[recording].append(index)
        operations += Self.lineOperations(recording: recording, index: index, text: "line \(index)", updatedAtMs: Double(step))
      }
      return transaction(operations)
    }
  }

  private mutating func transaction(_ operations: [InstantTripleOperation]) -> InstantStoreTransaction {
    step += 1
    let transactionID = "frozen-tx-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: operations.map { operation in
        guard case var .insert(triple) = operation else { return operation }
        triple.txID = transactionID
        triple.txTime = InstantPageRefreshEnergyTests.time(step)
        return .insert(triple)
      }
    )
  }

  private static func lineOperations(recording: Int, index: Double, text: String, updatedAtMs: Double)
    -> [InstantTripleOperation]
  {
    SpliceFixture.entity(
      lineID(recording, index),
      lines,
      [
        "recordingID": .string(recordingID(recording)),
        "index": .number(index),
        "text": .string(text),
        "updatedAtMs": .number(updatedAtMs),
      ]
    )
  }
}
