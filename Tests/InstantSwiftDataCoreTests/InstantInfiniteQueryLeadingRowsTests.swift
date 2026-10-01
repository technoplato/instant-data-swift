import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Issue #300: a windowed live infinite query (`.window(maximumPageCount:)`) keeps paging when rows appear above its
/// first row. Those are new rows, or rows whose sort value moved them there: in Scribe's list, which orders by
/// `updatedAtMs`, a recording updated on another device.
///
/// Every test talks to ``InfiniteListModelServer``, a model of Instant's server for one `items` namespace ordered by
/// `value`. It answers each `add-query` from its rows with the server's cursor and page-info rules, and after each
/// change it sends one `refresh-ok` with the new result of every active query, as the server does after a transaction.
/// So the client pages against the answers the real server would give, whatever chunks it asks for.
@Suite(.serialized)
struct InstantInfiniteQueryLeadingRowsTests {
  /// The reported stall, reduced: a leading row fills a two-page window, and the page loaded next is evicted at once,
  /// so `loadNextPage` cannot advance while `canLoadNextPage` stays true.
  @Test
  func aFullWindowWithALeadingRowKeepsLoadingTheNextPage() async throws {
    let harness = try await InfiniteWindowHarness(
      values: Array(1...10),
      order: .ascending,
      pageSize: 2,
      maximumPageCount: 2
    )

    var window = try await harness.settledWindow("open the list")
    expectNoDifference(window, InfiniteWindow(values: [1, 2], canLoadPreviousPage: false, canLoadNextPage: true))

    // Upstream shows rows ordered before the first row (`infiniteQuery.e2e.test.ts`, "adding negative numbers").
    try await harness.insertAtTop()
    window = try await harness.settledWindow("show the row above the first row")
    expectNoDifference(window, InfiniteWindow(values: [0, 1, 2], canLoadPreviousPage: false, canLoadNextPage: true))

    // The leading row fills a page like any other, so the next page evicts it with the top of the window. The page
    // just loaded stays, and the next load advances again.
    window = try await harness.loadNextPage()
    expectNoDifference(window, InfiniteWindow(values: [1, 2, 3, 4], canLoadPreviousPage: true, canLoadNextPage: true))
    window = try await harness.loadNextPage()
    expectNoDifference(window, InfiniteWindow(values: [3, 4, 5, 6], canLoadPreviousPage: true, canLoadNextPage: true))
    window = try await harness.loadNextPage()
    expectNoDifference(window, InfiniteWindow(values: [5, 6, 7, 8], canLoadPreviousPage: true, canLoadNextPage: true))
    window = try await harness.loadNextPage()
    expectNoDifference(
      window,
      InfiniteWindow(values: [7, 8, 9, 10], canLoadPreviousPage: true, canLoadNextPage: false)
    )

    // Back up to the top, where the leading row is shown again.
    try await harness.page(.previous, untilTheWindowStopsAt: "the top of the list")
    window = try await harness.settledWindow("return to the top")
    #expect(window.values.first == 0)
    #expect(!window.canLoadPreviousPage)
    await harness.finish()
  }

  /// Scribe's list after the window slid down: a recording updated elsewhere moves above the list's first row. It must
  /// not be shown above the gap the window left, and it must not cost the window its bottom page.
  @Test
  func aRowThatMovesAboveTheTopAfterTheWindowSlidDoesNotBreakTheWindow() async throws {
    let harness = try await InfiniteWindowHarness(
      values: Array(1...10),
      order: .ascending,
      pageSize: 2,
      maximumPageCount: 2
    )
    _ = try await harness.settledWindow("open the list")
    _ = try await harness.loadNextPage()
    var window = try await harness.loadNextPage()
    expectNoDifference(window, InfiniteWindow(values: [3, 4, 5, 6], canLoadPreviousPage: true, canLoadNextPage: true))

    try await harness.moveToTop(value: 10)
    window = try await harness.settledWindow("move a row below the window above the top")
    expectNoDifference(window, InfiniteWindow(values: [3, 4, 5, 6], canLoadPreviousPage: true, canLoadNextPage: true))

    window = try await harness.loadNextPage()
    expectNoDifference(window, InfiniteWindow(values: [5, 6, 7, 8], canLoadPreviousPage: true, canLoadNextPage: true))
    window = try await harness.loadNextPage()
    expectNoDifference(window, InfiniteWindow(values: [7, 8, 9], canLoadPreviousPage: true, canLoadNextPage: false))

    try await harness.page(.previous, untilTheWindowStopsAt: "the top of the list")
    window = try await harness.settledWindow("return to the top")
    // Row 10 now sorts first (value 0).
    expectNoDifference(window.values.first, 0)
    #expect(!window.canLoadPreviousPage)
    await harness.finish()
  }

  /// The page above the first page has the original leading watcher's exact query, and the runtime keeps that query's
  /// last result: one row above the top and no more. Seeded from it, the new page would claim the top was reached, and
  /// the window would climb to the head in one call. A page loaded by `loadPreviousPage` must wait for the server.
  @Test
  func aPreviousPageWaitsForTheServerInsteadOfAnEarlierQuerysStoredResult() async throws {
    let harness = try await InfiniteWindowHarness(
      values: (1...24).map { $0 * 10 },
      order: .descending,
      pageSize: 3,
      maximumPageCount: 2
    )
    _ = try await harness.settledWindow("open the list")
    try await harness.insertAtTop()
    var window = try await harness.settledWindow("show a row above the first row")
    expectNoDifference(
      window,
      InfiniteWindow(values: [241, 240, 230, 220], canLoadPreviousPage: false, canLoadNextPage: true)
    )
    // The next page evicts the leading watcher with the top; its last result, [241] with no more above, stays stored.
    window = try await harness.loadNextPage()
    expectNoDifference(
      window,
      InfiniteWindow(values: [240, 230, 220, 210, 200, 190], canLoadPreviousPage: true, canLoadNextPage: true)
    )
    for _ in 1...6 {
      try await harness.insertAtTop()
    }
    _ = try await harness.settledWindow("add rows above the evicted top")

    window = try await harness.loadPreviousPage()
    expectNoDifference(
      window,
      InfiniteWindow(values: [243, 242, 241, 240, 230, 220], canLoadPreviousPage: true, canLoadNextPage: true)
    )
    try await harness.page(.previous, untilTheWindowStopsAt: "the top of the list")
    window = try await harness.settledWindow("return to the top")
    expectNoDifference(window.values.first, 247)
    await harness.finish()
  }

  /// #302, not #300: a row that moves above the top while the window's top is evicted keeps its old values at its old
  /// place until the window returns to the top. No active query covers its new place, and the shared store keeps a
  /// departed row's facts while another stored result owns them, here the cached result of its chunk before the
  /// chunk was frozen. Upstream reads each query from its own result, so there the row leaves the chunk at once.
  @Test
  func aRowThatMovesAboveTheTopWhileTheTopIsEvictedShowsItsOldValuesUntilTheWindowReturns() async throws {
    let harness = try await InfiniteWindowHarness(
      values: Array(1...12),
      order: .ascending,
      pageSize: 3,
      maximumPageCount: 2
    )
    _ = try await harness.settledWindow("open the list")
    _ = try await harness.loadNextPage()
    var window = try await harness.loadNextPage()
    expectNoDifference(
      window,
      InfiniteWindow(values: [4, 5, 6, 7, 8, 9], canLoadPreviousPage: true, canLoadNextPage: true)
    )

    try await harness.moveToTop(value: 5)
    await withKnownIssue("#302: the moved row keeps its old values at its old place") {
      window = try await harness.settledWindow("move a row inside the window above the top")
      expectNoDifference(window.values, [4, 6, 7, 8, 9])
      try await harness.page(.previous, untilTheWindowStopsAt: "the top of the list")
    }
    // At the top, the leading page holds the moved row's new value, and its old copy is gone.
    window = try await harness.settledWindow("return to the top")
    expectNoDifference(Array(window.values.prefix(2)), [0, 1])
    #expect(!window.canLoadPreviousPage)
    await harness.finish()
  }

  /// Scribe's recording timeline: sections newest first in a two-page window, with the live head arriving above the
  /// first row. Without navigation the window keeps showing the newest rows and never holds more than two pages,
  /// the bound `ScribeRecordingTimelineQuery.decode` enforces. After paging back and returning, it follows the head
  /// again.
  @Test
  func theWindowFollowsALiveHeadWithinItsPageBound() async throws {
    let harness = try await InfiniteWindowHarness(
      values: (1...8).map { $0 * 10 },
      order: .descending,
      pageSize: 4,
      maximumPageCount: 2
    )
    var window = try await harness.settledWindow("open the list")
    expectNoDifference(window, InfiniteWindow(values: [80, 70, 60, 50], canLoadPreviousPage: false, canLoadNextPage: true))

    for _ in 1...10 {
      try await harness.insertAtTop()
      window = try await harness.settledWindow("add a row at the live head")
      let newest = await harness.server.orderedValues().first
      expectNoDifference(window.values.first, newest)
      #expect(window.values.count <= 8)
      #expect(!window.canLoadPreviousPage)
    }
    // Upstream's reverse chunks: a full leading watcher froze at 81-84 and again at 85-88, and each new page evicted
    // the bottom page, so the window holds the watcher's 89-90 and the page it froze last.
    expectNoDifference(
      window,
      InfiniteWindow(values: [90, 89, 88, 87, 86, 85], canLoadPreviousPage: false, canLoadNextPage: true)
    )

    try await harness.page(.next, untilTheWindowStopsAt: "the end of the list")
    try await harness.page(.previous, untilTheWindowStopsAt: "the top of the list")
    for _ in 1...3 {
      try await harness.insertAtTop()
      window = try await harness.settledWindow("add a row at the live head after returning")
      let newest = await harness.server.orderedValues().first
      expectNoDifference(window.values.first, newest)
      #expect(window.values.count <= 8)
    }
    await harness.finish()
  }

  /// The Mac reproduction's shape (#299, 2026-09-30 15:57 EDT): 121 recordings ordered by `updatedAtMs` descending,
  /// pages of 12, a six-page window, and three recordings updated above the first row after the list opened. The list
  /// stalled at 63 rows with `canLoadNextPage` true; it must reach every recording, down and back up.
  @Test
  func theRecordingListReachesEveryRowWhenRowsMoveAboveItsFirstRow() async throws {
    let harness = try await InfiniteWindowHarness(
      values: (1...121).map { 1_000 - $0 },
      order: .descending,
      pageSize: 12,
      maximumPageCount: 6
    )
    var window = try await harness.settledWindow("open the list")
    expectNoDifference(window.values, Array((1...12).map { 1_000 - $0 }))

    for value in [881, 880, 879] {
      try await harness.moveToTop(value: value)
    }
    window = try await harness.settledWindow("show the three updated rows above the first row")
    expectNoDifference(Array(window.values.prefix(4)), [1_002, 1_001, 1_000, 999])

    try await harness.page(.next, untilTheWindowStopsAt: "the end of the list")
    try await harness.page(.previous, untilTheWindowStopsAt: "the top of the list")
    try await harness.page(.next, untilTheWindowStopsAt: "the end of the list")
    let seen = await harness.seenRowIDs()
    let rows = await harness.server.orderedRowIDs()
    expectNoDifference(rows.count, 121)
    expectNoDifference(Set(rows).subtracting(seen), [])
    await harness.finish()
  }

  /// A property test: slide windows down, up, down, and up again while rows are inserted at the top of the list at
  /// random (and, while the window includes the top, moved there). At every quiet point the window must be a
  /// contiguous run of the list with no row twice, its flags must never claim an end that is not there, each page load
  /// must move the window without skipping rows, and every row must be reached.
  @Test(arguments: InfiniteWindowScenario.all)
  func slidingWindowsReachEveryRowExactlyOnceWhileRowsArriveAtTheTop(
    scenario: InfiniteWindowScenario
  ) async throws {
    var random = InfiniteWindowRandom(seed: scenario.seed)
    let harness = try await InfiniteWindowHarness(
      values: (1...scenario.rowCount).map { $0 * 10 },
      order: scenario.order,
      pageSize: scenario.pageSize,
      maximumPageCount: scenario.maximumPageCount
    )
    _ = try await harness.settledWindow("open the list")
    // A budget of changes, so paging toward the top can outrun rows arriving there. The last pass back to the top makes
    // no changes: it reaches the rows inserted there after the window last left the top.
    var changesLeft = scenario.rowCount / 2
    let passes: [InfiniteWindowDirection] = [.next, .previous, .next, .previous]
    for (pass, direction) in passes.enumerated() {
      try await harness.page(direction, untilTheWindowStopsAt: direction.end) {
        guard pass < passes.count - 1, changesLeft > 0, random.chance(40) else { return }
        for _ in 0..<min(changesLeft, random.int(1...3)) {
          changesLeft -= 1
          let rows = await harness.server.orderedRowIDs()
          // Rows move only while the window includes the top, where the leading watcher receives their new values.
          // A move while the top is evicted leaves the row's old values in the shared store (#302).
          let window = try await harness.settledWindow("check the window before a change")
          if random.chance(50) || rows.isEmpty || window.canLoadPreviousPage {
            try await harness.insertAtTop()
          } else {
            try await harness.moveToTop(rowID: rows[random.int(0...(rows.count - 1))])
          }
        }
        _ = try await harness.settledWindow("apply changes at the top")
      }
    }
    let seen = await harness.seenRowIDs()
    let rows = await harness.server.orderedRowIDs()
    expectNoDifference(Set(rows).subtracting(seen), [], "rows the traversals never reached")
    await harness.finish()
  }
}

/// One property-test configuration. Seeds replay exactly (`InfiniteWindowRandom` is SplitMix64).
struct InfiniteWindowScenario: Sendable, CustomTestStringConvertible {
  var seed: UInt64
  var order: InfiniteListOrder
  var rowCount: Int
  var pageSize: Int
  var maximumPageCount: Int

  var testDescription: String {
    "seed \(seed), \(order), \(rowCount) rows, pages of \(pageSize), window \(maximumPageCount)"
  }

  static let all: [Self] = [
    Self(seed: 1, order: .descending, rowCount: 24, pageSize: 3, maximumPageCount: 2),
    Self(seed: 2, order: .ascending, rowCount: 24, pageSize: 3, maximumPageCount: 1),
    Self(seed: 3, order: .descending, rowCount: 30, pageSize: 4, maximumPageCount: 3),
    Self(seed: 4, order: .ascending, rowCount: 17, pageSize: 2, maximumPageCount: 2),
    Self(seed: 5, order: .descending, rowCount: 40, pageSize: 5, maximumPageCount: 4),
    Self(seed: 6, order: .descending, rowCount: 20, pageSize: 1, maximumPageCount: 3),
    Self(seed: 7, order: .ascending, rowCount: 36, pageSize: 6, maximumPageCount: 2),
    Self(seed: 8, order: .descending, rowCount: 25, pageSize: 3, maximumPageCount: 6),
  ]
}

/// SplitMix64, so a failing seed replays exactly.
struct InfiniteWindowRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func int(_ range: ClosedRange<Int>) -> Int {
    range.lowerBound + Int(next() % UInt64(range.count))
  }

  mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }
}

enum InfiniteListOrder: String, Sendable, CustomStringConvertible {
  case ascending = "asc"
  case descending = "desc"

  var description: String { self == .ascending ? "ascending" : "descending" }
}

enum InfiniteWindowDirection: Sendable {
  case next
  case previous

  var end: String { self == .next ? "the end of the list" : "the top of the list" }
}

/// What a snapshot shows: the rows' values in order and the two paging flags.
struct InfiniteWindow: Equatable, Sendable {
  var values: [Int]
  var canLoadPreviousPage: Bool
  var canLoadNextPage: Bool
}

/// A model of Instant's server for one `items` namespace with a numeric `value`, over one WebSocket session.
///
/// Queries are answered with the server's rules (`server/src/instant/db/datalog.clj`, pinned e7101761):
/// - rows order by `value`, then by entity id, both in the query's direction (`add-page-info` `order-by`);
/// - `after` and `before` compare the cursor's value and entity id, inclusive only when asked
///   (`add-cursor-comparisons`);
/// - `has-next-page?` is false with neither `limit` nor `before`, an overfetch check with `limit` and no `before`,
///   and otherwise whether any row of the whole list follows the page's last row; `has-previous-page?` is false
///   without `after`, and otherwise whether any row precedes the page's first row, or the page is empty
///   (`add-page-info` `has-next-query` and `has-previous-query`, `nested-sql-result->result`).
actor InfiniteListModelServer {
  private struct Row: Sendable {
    var id: String
    var value: Int
    var createdAtMilliseconds: Int64
    var valueChangedAtMilliseconds: Int64
  }

  private struct Position: Equatable {
    var value: Double
    var id: String
  }

  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private let order: InfiniteListOrder
  private var rows: [String: Row] = [:]
  private var clockMilliseconds: Int64 = 1_767_225_600_000
  private var transactionNumber = 0
  private var nextRowNumber: Int
  private var activeQueries: [InstantLiveJSONValue] = []
  private var outgoing: [InstantLiveMessage]
  private var receiveContinuation: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var isClosed = false
  private(set) var receivedMessageCount = 0
  /// Every query the client adds or removes, every change, and the harness's notes, for failure messages.
  private var operationLog: [String] = []
  /// While set, the answers to forward chunk queries (the list's order, after a cursor) wait for
  /// `releaseForwardAnswers()`, so the leading watcher answers first, as the Mac's kickstarts showed (#388).
  private var holdsForwardAnswers = false
  private var heldForwardAnswers: [InstantLiveMessage] = []

  func holdForwardAnswers() {
    holdsForwardAnswers = true
  }

  func releaseForwardAnswers() {
    holdsForwardAnswers = false
    let held = heldForwardAnswers
    heldForwardAnswers.removeAll()
    held.forEach(enqueue)
  }

  var heldForwardAnswerCount: Int { heldForwardAnswers.count }

  func note(_ line: String) {
    operationLog.append(line)
  }

  func recentOperations(_ count: Int) -> [String] {
    Array(operationLog.suffix(count))
  }

  init(values: [Int], order: InfiniteListOrder) {
    self.order = order
    self.nextRowNumber = values.count + 1
    self.outgoing = [liveReactorInitOK(attrs: infiniteLeadingRowsServerAttributes)]
    for (index, value) in values.enumerated() {
      let id = String(format: "item-%04d", index + 1)
      rows[id] = Row(
        id: id,
        value: value,
        createdAtMilliseconds: clockMilliseconds,
        valueChangedAtMilliseconds: clockMilliseconds
      )
    }
  }

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in self.webSocketSession }
  }

  nonisolated private var webSocketSession: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in try await self.receive(fromClient: message) },
      receive: {
        try self.abortState.check()
        return try await self.nextMessageForClient()
      },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  /// Every row id in the list's order.
  func orderedRowIDs() -> [String] {
    orderedRows().map(\.id)
  }

  /// Every row value in the list's order.
  func orderedValues() -> [Int] {
    orderedRows().map(\.value)
  }

  func value(ofRow id: String) -> Int? {
    rows[id]?.value
  }

  func rowID(withValue value: Int) -> String? {
    rows.values.first { $0.value == value }?.id
  }

  /// No reply is waiting to be read and the client is waiting for the next one.
  func isDrained() -> Bool {
    outgoing.isEmpty && receiveContinuation != nil
  }

  /// Adds a row ordered before every other row.
  @discardableResult
  func insertAtTop() -> Int {
    let value = topValue
    let id = String(format: "item-%04d", nextRowNumber)
    nextRowNumber += 1
    let now = tick()
    rows[id] = Row(id: id, value: value, createdAtMilliseconds: now, valueChangedAtMilliseconds: now)
    operationLog.append("insert \(id) at \(value)")
    refreshActiveQueries()
    return value
  }

  /// Gives a row a value ordered before every other row, as an update to Scribe's `updatedAtMs` does.
  @discardableResult
  func moveToTop(rowID id: String) -> Int? {
    guard let old = rows[id]?.value else { return nil }
    let value = topValue
    rows[id]?.value = value
    rows[id]?.valueChangedAtMilliseconds = tick()
    operationLog.append("move \(id) from \(old) to \(value)")
    refreshActiveQueries()
    return value
  }

  private var topValue: Int {
    let values = rows.values.map(\.value)
    switch order {
    case .ascending:
      return (values.min() ?? 1) - 1
    case .descending:
      return (values.max() ?? -1) + 1
    }
  }

  private func tick() -> Int64 {
    clockMilliseconds += 1
    return clockMilliseconds
  }

  private var processedTransactionID: String {
    "model-tx-\(transactionNumber)"
  }

  private func receive(fromClient message: InstantLiveMessage) throws {
    try abortState.check()
    receivedMessageCount += 1
    switch message.op {
    case "add-query":
      guard let query = message.fields["q"] else { return }
      activeQueries.append(query)
      let result = result(for: query)
      operationLog.append("add \(Self.describe(query)) -> \(Self.describe(result))")
      let answer = InstantLiveMessage(
        op: "add-query-ok",
        clientEventID: message.clientEventID,
        fields: [
          "q": query,
          "processed-tx-id": .string(processedTransactionID),
          "result": .array(result),
        ]
      )
      if holdsForwardAnswers, isForwardChunkQuery(query) {
        operationLog.append("  held until releaseForwardAnswers()")
        heldForwardAnswers.append(answer)
      } else {
        enqueue(answer)
      }
    case "remove-query":
      guard let query = message.fields["q"], let index = activeQueries.firstIndex(of: query) else { return }
      activeQueries.remove(at: index)
      operationLog.append("remove \(Self.describe(query))")
    default:
      break
    }
  }

  /// A query in the list's order that starts after a cursor: a forward chunk, not the starter or a reverse chunk.
  private func isForwardChunkQuery(_ query: InstantLiveJSONValue) -> Bool {
    let options = query.objectValue?["items"]?.objectValue?["$"]?.objectValue ?? [:]
    let direction: InfiniteListOrder =
      options["order"]?.objectValue?["value"]?.stringValue == "desc" ? .descending : .ascending
    return direction == order && options["after"] != nil
  }

  private func refreshActiveQueries() {
    transactionNumber += 1
    let computations = activeQueries.map { query in
      let result = result(for: query)
      operationLog.append("  refresh \(Self.describe(query)) -> \(Self.describe(result))")
      return InstantLiveJSONValue.object([
        "instaql-query": query,
        "instaql-result": .array(result),
        "processed-tx-id": .string(processedTransactionID),
      ])
    }
    enqueue(
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: "model-refresh-\(transactionNumber)",
        fields: [
          "attrs": .array([]),
          "computations": .array(computations),
          "processed-tx-id": .string(processedTransactionID),
        ]
      )
    )
  }

  private func result(for query: InstantLiveJSONValue) -> [InstantLiveJSONValue] {
    let options = query.objectValue?["items"]?.objectValue?["$"]?.objectValue ?? [:]
    let direction: InfiniteListOrder =
      options["order"]?.objectValue?["value"]?.stringValue == "desc" ? .descending : .ascending
    var limit: Int?
    if case let .number(number)? = options["limit"] {
      limit = Int(number)
    }
    let after = options["after"].flatMap(Self.position(fromCursor:))
    let afterInclusive = options["afterInclusive"] == .bool(true)
    let before = options["before"].flatMap(Self.position(fromCursor:))
    let beforeInclusive = options["beforeInclusive"] == .bool(true)

    let ordered = orderedRows(direction)
    let bounded = ordered.filter { row in
      let position = Self.position(of: row)
      if let after,
        !(Self.precedes(after, position, direction) || (afterInclusive && after == position))
      {
        return false
      }
      if let before,
        !(Self.precedes(position, before, direction) || (beforeInclusive && before == position))
      {
        return false
      }
      return true
    }
    let page = limit.map { Array(bounded.prefix($0)) } ?? bounded
    let hasNextPage: Bool
    if limit == nil, before == nil {
      hasNextPage = false
    } else if let limit, before == nil {
      hasNextPage = bounded.count > limit
    } else {
      hasNextPage = page.last.map { last in
        ordered.contains { Self.precedes(Self.position(of: last), Self.position(of: $0), direction) }
      } ?? false
    }
    let hasPreviousPage: Bool
    if after == nil {
      hasPreviousPage = false
    } else {
      hasPreviousPage = page.isEmpty
        || page.first.map { first in
          ordered.contains { Self.precedes(Self.position(of: $0), Self.position(of: first), direction) }
        } == true
    }

    let joinRows = page.map { row in
      InstantLiveJSONValue.array([
        .array([
          .string(row.id),
          .string("server-items-id"),
          .string(row.id),
          .number(Double(row.createdAtMilliseconds)),
        ]),
        .array([
          .string(row.id),
          .string("server-items-value"),
          .number(Double(row.value)),
          .number(Double(row.valueChangedAtMilliseconds)),
        ]),
      ])
    }
    return [
      .object([
        "child-nodes": .array([]),
        "data": .object([
          "datalog-result": .object(["join-rows": .array(joinRows)]),
          "page-info": .object([
            "items": .object([
              "end-cursor": page.last.map(Self.cursor(for:)) ?? .null,
              "has-next-page?": .bool(hasNextPage),
              "has-previous-page?": .bool(hasPreviousPage),
              "start-cursor": page.first.map(Self.cursor(for:)) ?? .null,
            ])
          ]),
        ]),
      ])
    ]
  }

  private func orderedRows(_ direction: InfiniteListOrder? = nil) -> [Row] {
    let direction = direction ?? order
    return rows.values.sorted {
      Self.precedes(Self.position(of: $0), Self.position(of: $1), direction)
    }
  }

  private static func position(of row: Row) -> Position {
    Position(value: Double(row.value), id: row.id)
  }

  private static func position(fromCursor cursor: InstantLiveJSONValue) -> Position? {
    guard let tuple = cursor.arrayValue,
      tuple.count == 4,
      let id = tuple[0].stringValue,
      case let .number(value) = tuple[2]
    else { return nil }
    return Position(value: value, id: id)
  }

  /// "desc limit 3 after 10 incl before 7 incl" for a query's options.
  private static func describe(_ query: InstantLiveJSONValue) -> String {
    let options = query.objectValue?["items"]?.objectValue?["$"]?.objectValue ?? [:]
    var parts = [options["order"]?.objectValue?["value"]?.stringValue ?? "asc"]
    if case let .number(limit)? = options["limit"] {
      parts.append("limit \(Int(limit))")
    }
    for (name, inclusive) in [("after", "afterInclusive"), ("before", "beforeInclusive")] {
      if let position = options[name].flatMap(Self.position(fromCursor:)) {
        parts.append("\(name) \(Int(position.value))\(options[inclusive] == .bool(true) ? " incl" : "")")
      }
    }
    return parts.joined(separator: " ")
  }

  /// "[9, 8, 7] next prev" for a result's rows and page flags.
  private static func describe(_ result: [InstantLiveJSONValue]) -> String {
    let data = result.first?.objectValue?["data"]?.objectValue
    let rows = data?["datalog-result"]?.objectValue?["join-rows"]?.arrayValue ?? []
    let values = rows.compactMap { row -> Int? in
      guard case let .number(value)? = row.arrayValue?.last?.arrayValue?[2] else { return nil }
      return Int(value)
    }
    let info = data?["page-info"]?.objectValue?["items"]?.objectValue
    let next = info?["has-next-page?"] == .bool(true) ? " next" : ""
    let previous = info?["has-previous-page?"] == .bool(true) ? " prev" : ""
    return "\(values)\(next)\(previous)"
  }

  private static func cursor(for row: Row) -> InstantLiveJSONValue {
    .array([
      .string(row.id),
      .string("server-items-value"),
      .number(Double(row.value)),
      .number(Double(row.valueChangedAtMilliseconds)),
    ])
  }

  private static func precedes(_ lhs: Position, _ rhs: Position, _ direction: InfiniteListOrder) -> Bool {
    switch direction {
    case .ascending:
      return lhs.value < rhs.value || (lhs.value == rhs.value && lhs.id < rhs.id)
    case .descending:
      return lhs.value > rhs.value || (lhs.value == rhs.value && lhs.id > rhs.id)
    }
  }

  private func enqueue(_ message: InstantLiveMessage) {
    guard !abortState.isAborted, !isClosed else { return }
    if let receiveContinuation {
      self.receiveContinuation = nil
      abortState.unregister(receiveContinuation.abortToken)
      receiveContinuation.continuation.resume(returning: message)
    } else {
      outgoing.append(message)
    }
  }

  private func nextMessageForClient() async throws -> InstantLiveMessage {
    try abortState.check()
    if !outgoing.isEmpty {
      return outgoing.removeFirst()
    }
    if isClosed {
      throw CancellationError()
    }
    let id = UUID()
    defer { clearReceiveContinuation(id: id) }
    return try await withCheckedThrowingContinuation { continuation in
      let continuation = InstantLiveTestThrowingContinuationBox(continuation)
      guard
        let abortToken = abortState.register({
          continuation.resume(throwing: CancellationError())
        })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      receiveContinuation = InstantLiveTestPendingOperation(
        id: id,
        abortToken: abortToken,
        continuation: continuation
      )
    }
  }

  private func clearReceiveContinuation(id: UUID) {
    guard let receiveContinuation, receiveContinuation.id == id else { return }
    abortState.unregister(receiveContinuation.abortToken)
    self.receiveContinuation = nil
  }

  private func close() {
    isClosed = true
    abortState.abort()
    receiveContinuation = nil
  }
}

/// One runtime and one windowed infinite query against an ``InfiniteListModelServer``.
///
/// `settledWindow(_:)` waits until nothing is in flight: the navigation runner is idle, every chunk subscription has
/// its first result and none is being replaced, the server has no unread reply, and the runtime has applied every
/// frame. Every settled window is checked against the model (`checkWindow`).
final class InfiniteWindowHarness: Sendable {
  let server: InfiniteListModelServer
  let runtime: InstantRuntime
  let pageSize: Int
  let maximumPageCount: Int
  private let subscription: InstantInfiniteQuerySubscription
  private let recorder: InfiniteSnapshotRecorder
  private let recording: Task<Void, Never>

  init(
    values: [Int],
    order: InfiniteListOrder,
    pageSize: Int,
    maximumPageCount: Int
  ) async throws {
    let server = InfiniteListModelServer(values: values, order: order)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantInfiniteQueryLeadingRowsTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-leading-rows",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: infiniteLeadingRowsAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: server.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      InstantQueryPlan(
        id: "items.infinite.leading-rows",
        namespace: "items",
        order: InstantQueryOrder("value", order == .ascending ? .ascending : .descending),
        limit: pageSize
      ),
      retentionPolicy: .window(maximumPageCount: maximumPageCount)
    )
    let recorder = InfiniteSnapshotRecorder()
    self.server = server
    self.runtime = runtime
    self.pageSize = pageSize
    self.maximumPageCount = maximumPageCount
    self.subscription = subscription
    self.recorder = recorder
    self.recording = Task {
      for await snapshot in subscription.snapshots {
        await recorder.record(snapshot)
      }
    }
  }

  func insertAtTop() async throws {
    await server.insertAtTop()
  }

  func moveToTop(value: Int) async throws {
    let id = try #require(await server.rowID(withValue: value))
    await server.moveToTop(rowID: id)
  }

  func moveToTop(rowID: String) async throws {
    await server.moveToTop(rowID: rowID)
  }

  func loadNextPage(sourceLocation: SourceLocation = #_sourceLocation) async throws -> InfiniteWindow {
    await server.note("-- loadNextPage")
    subscription.loadNextPage()
    return try await settledWindow("load the next page", sourceLocation: sourceLocation)
  }

  func loadPreviousPage(sourceLocation: SourceLocation = #_sourceLocation) async throws -> InfiniteWindow {
    await server.note("-- loadPreviousPage")
    subscription.loadPreviousPage()
    return try await settledWindow("load the previous page", sourceLocation: sourceLocation)
  }

  /// Pages in one direction until the window reports its end, checking that every load moves the window without
  /// skipping a row. `beforeEachPage` runs at each quiet point before the next load.
  func page(
    _ direction: InfiniteWindowDirection,
    untilTheWindowStopsAt end: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    beforeEachPage: () async throws -> Void = {}
  ) async throws {
    var window = try await settledWindow("start paging to \(end)", sourceLocation: sourceLocation)
    var loads = 0
    while direction == .next ? window.canLoadNextPage : window.canLoadPreviousPage {
      let maximumLoads = 3 * (await server.orderedRowIDs().count / pageSize + 4)
      guard loads < maximumLoads else {
        Issue.record(
          "Paging to \(end) did not finish after \(loads) loads: \(window)",
          sourceLocation: sourceLocation
        )
        return
      }
      loads += 1
      try await beforeEachPage()
      let before = try await settledSnapshot("settle before a page load", sourceLocation: sourceLocation)
      await server.note("-- \(direction == .next ? "loadNextPage" : "loadPreviousPage") from \(infiniteWindow(before))")
      switch direction {
      case .next:
        subscription.loadNextPage()
      case .previous:
        subscription.loadPreviousPage()
      }
      let after = try await settledSnapshot("load a page toward \(end)", sourceLocation: sourceLocation)
      await checkProgress(from: before, to: after, direction: direction, sourceLocation: sourceLocation)
      window = infiniteWindow(after)
    }
  }

  func settledWindow(
    _ operation: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws -> InfiniteWindow {
    infiniteWindow(try await settledSnapshot(operation, sourceLocation: sourceLocation))
  }

  func seenRowIDs() async -> Set<String> {
    await recorder.seenAtQuietPoints
  }

  func finish() async {
    await subscription.unsubscribeAndWait()
    recording.cancel()
    _ = try? await runtime.closeConnection()
  }

  /// Waits until nothing is in flight, then checks the window. A live result can reach the query one actor hop after
  /// the runtime applied its frame, so a window that fails a check is settled and checked again before any issue is
  /// recorded: a broken window stays broken, a late result does not.
  private func settledSnapshot(
    _ operation: String,
    sourceLocation: SourceLocation
  ) async throws -> InstantInfiniteQuerySnapshot {
    var snapshot = try await quietSnapshot(operation, sourceLocation: sourceLocation)
    var problems = await windowProblems(snapshot)
    var retries = 0
    while !problems.isEmpty, retries < 5 {
      retries += 1
      try await Task.sleep(for: .milliseconds(50 * retries))
      snapshot = try await quietSnapshot(operation, sourceLocation: sourceLocation)
      problems = await windowProblems(snapshot)
    }
    for problem in problems {
      let report = await operationReport()
      Issue.record("After \"\(operation)\": \(problem)\(report)", sourceLocation: sourceLocation)
    }
    await recorder.recordQuietPoint(snapshot)
    return snapshot
  }

  /// The model server's last operations, attached to the first problem a test records.
  private func operationReport() async -> String {
    guard await recorder.claimOperationReport() else { return "" }
    let lines = await server.recentOperations(60)
    return "\nLast operations:\n" + lines.joined(separator: "\n")
  }

  private func quietSnapshot(
    _ operation: String,
    sourceLocation: SourceLocation
  ) async throws -> InstantInfiniteQuerySnapshot {
    let deadline = ContinuousClock.now + .seconds(5)
    var previousMarker: [Int]?
    var quietPolls = 0
    while ContinuousClock.now < deadline {
      let commands = subscription.commandResidencySnapshotForTesting()
      let residency = await subscription.residencySnapshotForTesting()
      let isDrained = await server.isDrained()
      let applierIsWaiting = await runtime.liveReceiverIsWaitingForAFrameForTesting()
      let marker = [await server.receivedMessageCount, await recorder.count]
      let isQuiet = commands.runnerTaskCount == 0
        && commands.pendingNavigationCount == 0
        && residency.awaitingResultSubscriptionCount == 0
        && residency.retiringSubscriptionCount == 0
        && residency.pendingSubscriptionCount == 0
        && isDrained
        && applierIsWaiting
        && marker == previousMarker
      quietPolls = isQuiet ? quietPolls + 1 : 0
      if quietPolls >= 2, let latest = await recorder.latest {
        return latest
      }
      previousMarker = marker
      try await Task.sleep(for: .milliseconds(10))
    }
    let residency = await subscription.residencySnapshotForTesting()
    Issue.record(
      "Waiting to \(operation): the query did not settle within 5 s (\(residency)).",
      sourceLocation: sourceLocation
    )
    throw InfiniteWindowDidNotSettle(operation: operation)
  }

  /// The window is a contiguous run of the list with no row twice, holds at most `maximumPageCount` pages, and never
  /// reports an end that is not there. Rows only ever arrive at the top here, so no page grows past `pageSize` and the
  /// window holds at most `maximumPageCount * pageSize` rows, the bound Scribe's timeline decode enforces.
  private func windowProblems(_ snapshot: InstantInfiniteQuerySnapshot) async -> [String] {
    let rows = await server.orderedRowIDs()
    let ids = snapshot.values.map(\.id)
    let shown = infiniteWindow(snapshot)
    var problems: [String] = []
    if Set(ids).count != ids.count {
      problems.append("a row is shown twice: \(shown.values)")
    }
    if let first = ids.first, let start = rows.firstIndex(of: first) {
      let expected = Array(rows[start..<min(rows.count, start + ids.count)])
      if expected != ids {
        let expectedValues = await values(of: expected)
        problems.append("the window is not a contiguous run of the list: \(shown.values), expected \(expectedValues)")
      }
    } else if !ids.isEmpty {
      problems.append("the window's first row is not in the list: \(shown.values)")
    } else if !rows.isEmpty {
      problems.append("the window is empty but the list has \(rows.count) rows")
    }
    if ids.count > maximumPageCount * pageSize {
      problems.append("the window holds \(ids.count) rows, more than \(maximumPageCount) pages of \(pageSize)")
    }
    if !snapshot.canLoadNextPage, ids.last != rows.last {
      problems.append("canLoadNextPage is false before the end of the list: \(shown.values)")
    }
    if !snapshot.canLoadPreviousPage, ids.first != rows.first {
      problems.append("canLoadPreviousPage is false below the top of the list: \(shown.values)")
    }
    return problems
  }

  /// A page load must move the window's leading edge past its old edge, and the new window must meet or overlap the
  /// old one, so no row is skipped. When the load finds nothing more, the window must report its end.
  private func checkProgress(
    from before: InstantInfiniteQuerySnapshot,
    to after: InstantInfiniteQuerySnapshot,
    direction: InfiniteWindowDirection,
    sourceLocation: SourceLocation
  ) async {
    let rows = await server.orderedRowIDs()
    let beforeIDs = before.values.map(\.id)
    let afterIDs = after.values.map(\.id)
    let shownBefore = infiniteWindow(before)
    let shownAfter = infiniteWindow(after)
    guard let beforeFirst = beforeIDs.first.flatMap(rows.firstIndex(of:)),
      let beforeLast = beforeIDs.last.flatMap(rows.firstIndex(of:)),
      let afterFirst = afterIDs.first.flatMap(rows.firstIndex(of:)),
      let afterLast = afterIDs.last.flatMap(rows.firstIndex(of:))
    else {
      Issue.record("A page load left an empty window: \(shownAfter)", sourceLocation: sourceLocation)
      return
    }
    var problem: String?
    switch direction {
    case .next:
      if afterLast > beforeLast {
        if afterFirst > beforeLast + 1 {
          problem = "loadNextPage skipped rows: \(shownBefore.values) -> \(shownAfter.values)"
        }
      } else if after.canLoadNextPage || afterLast != rows.count - 1 {
        problem = "loadNextPage did not advance: \(shownBefore) -> \(shownAfter)"
      }
    case .previous:
      if afterFirst < beforeFirst {
        if afterLast < beforeFirst - 1 {
          problem = "loadPreviousPage skipped rows: \(shownBefore.values) -> \(shownAfter.values)"
        }
      } else if after.canLoadPreviousPage || afterFirst != 0 {
        problem = "loadPreviousPage did not advance: \(shownBefore) -> \(shownAfter)"
      }
    }
    if let problem {
      let report = await operationReport()
      Issue.record("\(problem)\(report)", sourceLocation: sourceLocation)
    }
  }

  private func infiniteWindow(_ snapshot: InstantInfiniteQuerySnapshot) -> InfiniteWindow {
    InfiniteWindow(
      values: snapshot.values.map { entity in
        guard case let .one(.number(value)) = entity.values["value"] else { return Int.min }
        return Int(value)
      },
      canLoadPreviousPage: snapshot.canLoadPreviousPage,
      canLoadNextPage: snapshot.canLoadNextPage
    )
  }

  private func values(of ids: [String]) async -> [Int] {
    var values: [Int] = []
    for id in ids {
      values.append(await server.value(ofRow: id) ?? Int.min)
    }
    return values
  }
}

private struct InfiniteWindowDidNotSettle: Error, CustomStringConvertible {
  var operation: String

  var description: String {
    "The infinite query did not settle while waiting to \(operation)."
  }
}

private actor InfiniteSnapshotRecorder {
  private(set) var latest: InstantInfiniteQuerySnapshot?
  private(set) var count = 0
  private(set) var seenAtQuietPoints: Set<String> = []

  private var hasReportedOperations = false

  func record(_ snapshot: InstantInfiniteQuerySnapshot) {
    latest = snapshot
    count += 1
  }

  /// True once per test, so only the first recorded problem carries the operation log.
  func claimOperationReport() -> Bool {
    defer { hasReportedOperations = true }
    return !hasReportedOperations
  }

  func recordQuietPoint(_ snapshot: InstantInfiniteQuerySnapshot) {
    seenAtQuietPoints.formUnion(snapshot.values.map(\.id))
  }
}

private let infiniteLeadingRowsAttributes: [InstantAttribute] = [
  .primaryKey(namespace: "items"),
  InstantAttribute(
    id: "items/value",
    namespace: "items",
    name: "value",
    valueType: .number,
    isIndexed: true
  ),
]

private let infiniteLeadingRowsServerAttributes: [InstantLiveJSONValue] = [
  infiniteLeadingRowsServerAttribute(id: "server-items-id", name: "id", valueType: "string"),
  infiniteLeadingRowsServerAttribute(id: "server-items-value", name: "value", valueType: "number"),
]

private func infiniteLeadingRowsServerAttribute(
  id: String,
  name: String,
  valueType: String
) -> InstantLiveJSONValue {
  .object([
    "cardinality": .string("one"),
    "forward-identity": .array([
      .string("identity-\(id)"),
      .string("items"),
      .string(name),
    ]),
    "id": .string(id),
    "index?": .bool(name == "value"),
    "unique?": .bool(name == "id"),
    "value-type": .string(valueType),
  ])
}
