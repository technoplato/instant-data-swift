import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #653: the write path did work whose result nobody sees. Each test here pins one saving and the behavior that must
/// not change with it.
@Suite(.serialized)
struct InstantWritePathEnergyTests {
  // MARK: - SQLite's page cache

  /// The cache is bounded at 2 MiB per connection, and a save no longer empties it: the pages the next save reads
  /// are still in memory (#653).
  @Test
  func thePageCacheIsBoundedAtTwoMebibytesAndStaysWarmBetweenSaves() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("page-cache-warm")
    try await InstantOfflineRuntimeFixture.createTodo("first", in: runtime)
    try await InstantOfflineRuntimeFixture.createTodo("second", in: runtime)

    let status = try await runtime.persistence.pageCacheStatusForTesting()
    expectNoDifference(status.cacheSize, -2_048)
    #expect(status.usedBytes > 0, "a save left SQLite's page cache empty")
  }

  /// Reading a store far larger than the cache keeps the cache within its bound (#653).
  @Test
  func readingALargeStoreKeepsThePageCacheWithinItsBound() async throws {
    let persistence = try SQLitePersistenceStore(fileURL: try Self.temporaryCacheURL("page-cache-bound"))
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: Self.largeStoreAttributes, triples: Self.largeStoreTriples(count: 20_000))
    )
    await persistence.invalidateMemoryCache()

    let state = try await persistence.loadState()

    expectNoDifference(state.snapshot.store.triples.count, 20_000)
    let status = try await persistence.pageCacheStatusForTesting()
    #expect(status.usedBytes > 1_048_576, "the read did not fill the cache")
    #expect(status.usedBytes <= 2_621_440, "the cache grew past 2 MiB and its page headers")
  }

  /// A memory warning releases the cache, which no save does any more (#653).
  @Test
  func aMemoryWarningReleasesThePageCache() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("page-cache-release")
    try await InstantOfflineRuntimeFixture.createTodo("first", in: runtime)
    try await InstantOfflineRuntimeFixture.createTodo("second", in: runtime)
    let warm = try await runtime.persistence.pageCacheStatusForTesting()

    await runtime.persistence.releaseMemory()

    let released = try await runtime.persistence.pageCacheStatusForTesting()
    print("#653 page cache: \(warm.usedBytes) B warm, \(released.usedBytes) B after a memory warning")
    #expect(released.usedBytes < warm.usedBytes, "warm: \(warm.usedBytes) B, released: \(released.usedBytes) B")
    try await InstantOfflineRuntimeFixture.createTodo("third", in: runtime)
    let pendingCount = await runtime.pendingMutationCount()
    expectNoDifference(pendingCount, 3, "the store keeps working after the release")
  }

  // MARK: - Prepared statements

  /// Every statement was prepared and finalized on each call, so SQLite parsed and planned the same SQL again for
  /// every save. On a device database's copy SQLite ran 17% fewer instructions per write with a 2 MiB page cache, and
  /// 23% fewer with reused statements as well (#653).
  @Test
  func repeatedSavesReuseTheirPreparedStatements() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("statement-reuse")
    try await InstantOfflineRuntimeFixture.createTodo("warm-1", in: runtime)
    try await InstantOfflineRuntimeFixture.createTodo("warm-2", in: runtime)
    let preparedBefore = await runtime.persistence.preparedStatementCountForTesting()

    for index in 0..<10 {
      try await InstantOfflineRuntimeFixture.createTodo("reuse-\(index)", in: runtime)
    }

    let preparedAfter = await runtime.persistence.preparedStatementCountForTesting()
    let pendingCount = await runtime.pendingMutationCount()
    expectNoDifference(preparedAfter - preparedBefore, 0)
    expectNoDifference(pendingCount, 12, "every write is still durable in the outbox")
  }

  /// A statement in use is never handed out twice, an idle one is reset, DDL is not kept, and the cache stays within
  /// its capacity (#653).
  @Test
  func theStatementCacheHandsOutEachStatementOnceAndStaysBounded() throws {
    var database: OpaquePointer?
    try #require(sqlite3_open(":memory:", &database) == SQLITE_OK)
    defer { sqlite3_close_v2(database) }
    var cache = SQLiteStatementCache(capacity: 2)

    let outer = cache.checkOut("SELECT 1", on: database)
    let nested = cache.checkOut("SELECT 1", on: database)
    #expect(outer.statement != nil)
    #expect(nested.statement != nil)
    #expect(outer.statement != nested.statement, "a nested use of the same SQL gets its own statement")
    #expect(sqlite3_step(outer.statement) == SQLITE_ROW)
    cache.checkIn(nested.statement)
    cache.checkIn(outer.statement)
    expectNoDifference(cache.idleCount, 1)
    let reused = cache.checkOut("SELECT 1", on: database)
    #expect(reused.statement == nested.statement)
    #expect(sqlite3_stmt_busy(reused.statement) == 0, "a statement comes back reset")
    cache.checkIn(reused.statement)

    for sql in ["SELECT 2", "SELECT 3", "SELECT 4"] {
      let statement = cache.checkOut(sql, on: database)
      cache.checkIn(statement.statement)
    }
    expectNoDifference(cache.idleCount, 2)
    expectNoDifference(cache.preparedCount, 5)

    // DDL runs once: it is not kept.
    let ddl = cache.checkOut("CREATE TABLE kept_once (value INTEGER)", on: database)
    #expect(sqlite3_step(ddl.statement) == SQLITE_DONE)
    cache.checkIn(ddl.statement)
    expectNoDifference(cache.idleCount, 2)

    // A statement checked out when its connection closes is finalized when it comes back, not kept.
    let open = cache.checkOut("SELECT 5", on: database)
    cache.finalizeAll()
    cache.checkIn(open.statement)
    expectNoDifference(cache.idleCount, 0)
    let invalid = cache.checkOut("SELECT FROM", on: database)
    #expect(invalid.statement == nil)
    #expect(invalid.resultCode != SQLITE_OK)
  }

  /// The statements a store keeps are finalized when its connection closes, and the reopened connection prepares its
  /// own (#653).
  @Test
  func aReopenedConnectionPreparesItsOwnStatements() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("statement-reopen")
    try await InstantOfflineRuntimeFixture.createTodo("before-close", in: runtime)
    let before = await runtime.persistence.statementCacheStatusForTesting()
    print("#653 statement cache: \(before.idleCount) statements kept, \(before.statementBytes) B")
    #expect(before.idleCount > 0)
    #expect(before.idleCount <= SQLiteStatementCache.defaultCapacity)
    #expect(before.statementBytes < 2_097_152, "the kept statements use \(before.statementBytes) B")

    await runtime.persistence.simulateUnexpectedConnectionCloseForTesting()
    try await InstantOfflineRuntimeFixture.createTodo("after-close", in: runtime)

    let pendingCount = await runtime.pendingMutationCount()
    expectNoDifference(pendingCount, 2)
    let todos = try await runtime.query(TodoExample.query)
    expectNoDifference(Set(todos.map(\.id)), ["todo-before-close", "todo-after-close"])
  }

  // MARK: - Equal results

  /// A commit that could change a query's result handed its observers the result again, equal or not, and each
  /// handed result costs the reader a deferred-value read and its consumer an update. Upstream `Reactor.js`
  /// `notifyOne` does not call a query's callbacks with data deep-equal to the previous result (#653).
  @Test
  func anObserverIsNotHandedAResultEqualToTheOneItWasLastHanded() async throws {
    let runtime = try await InstantOfflineRuntimeFixture.offlineRuntime("equal-result")
    let plan = InstantQueryPlan(
      id: "energy.first-two",
      namespace: TodoExample.namespace,
      order: InstantQueryOrder("createdAt", .ascending),
      limit: 2
    )
    let reader = EqualResultReader()
    let stream = await runtime.observeLocally(plan)
    let reading = Task { for await emission in stream { await reader.record(emission) } }
    defer { reading.cancel() }
    try await Self.createTodo("a", at: 1, in: runtime)
    try await Self.createTodo("b", at: 2, in: runtime)
    // A third todo fills the window past its limit, so the page already has a next page. The first version of this
    // test made the third todo the equal write, but it turns the page's `hasNextPage` from false to true, which a
    // reader can see, so that result is not equal and is rightly handed over.
    try await Self.createTodo("c", at: 3, in: runtime)
    let handedBefore = await runtime.store.observerYieldCountsForTesting()[plan.id] ?? 0

    // A later todo falls outside the first two and the page still has a next page: the query runs again and its
    // result, values and page info, is the same.
    try await Self.createTodo("d", at: 4, in: runtime)
    let handedAfterEqual = await runtime.store.observerYieldCountsForTesting()[plan.id] ?? 0
    expectNoDifference(handedAfterEqual - handedBefore, 0, "an equal result is not handed again")

    // A change inside the window is handed.
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-a2",
        operations: TodoExample.updateTextOperations(
          id: "todo-a",
          text: "a2",
          updatedAt: Self.todoTime(5),
          transactionID: "tx-a2"
        )
      ),
      createdAt: Self.todoTime(5)
    )
    let handedAfterChange = await runtime.store.observerYieldCountsForTesting()[plan.id] ?? 0
    expectNoDifference(handedAfterChange - handedBefore, 1)
    try await reader.waitUntilCurrent(with: runtime.query(plan), "the reader sees a2")
  }

  /// Pages of a long list that a write cannot reach keep their result: an update of an entity on the first page, its
  /// order unchanged, leaves every other page as it was, and those pages are not handed their result again. A new
  /// entity at the top shifts every offset page, and each is handed its new result (#653).
  @Test
  func pagesAWriteCannotReachAreNotHandedTheirResultAgain() async throws {
    let runtime = try await Self.pageRuntime("equal-result-pages")
    for index in 0..<24 {
      try await Self.writeSegment(index, recording: "r1", wordCount: 1, at: index + 1, in: runtime)
    }
    let pages = (0..<6).map { Self.pagePlan(recording: "r1", page: $0, size: 4) }
    var readers: [EqualResultReader] = []
    var readings: [Task<Void, Never>] = []
    for plan in pages {
      let reader = EqualResultReader()
      let stream = await runtime.observeLocally(plan)
      readers.append(reader)
      readings.append(Task { for await emission in stream { await reader.record(emission) } })
    }
    defer { readings.forEach { $0.cancel() } }
    let handedBefore = await runtime.store.observerYieldCountsForTesting()

    // The newest segment, on the first page, gets another word.
    try await Self.writeSegment(23, recording: "r1", wordCount: 2, at: 30, in: runtime)
    let handedAfterUpdate = await runtime.store.observerYieldCountsForTesting()
    expectNoDifference(
      pages.map { (handedAfterUpdate[$0.id] ?? 0) - (handedBefore[$0.id] ?? 0) },
      [1, 0, 0, 0, 0, 0],
      "only the page that shows the segment is handed its result"
    )

    // A new segment at the top moves one segment down into each later page.
    try await Self.writeSegment(24, recording: "r1", wordCount: 1, at: 31, in: runtime)
    let handedAfterInsert = await runtime.store.observerYieldCountsForTesting()
    expectNoDifference(
      pages.map { (handedAfterInsert[$0.id] ?? 0) - (handedAfterUpdate[$0.id] ?? 0) },
      [1, 1, 1, 1, 1, 1]
    )
    for (plan, reader) in zip(pages, readers) {
      try await reader.waitUntilCurrent(with: runtime.query(plan), "page \(plan.id) is current")
    }
  }

  /// A deferred value is not kept in memory, so a write of it alone leaves the store's copy of a result equal; its
  /// observers are still handed the result, with the new value read from SQLite (#653).
  @Test
  func aChangeToADeferredValueAloneIsStillHandedOver() async throws {
    let runtime = try await Self.pageRuntime("equal-result-deferred")
    try await Self.writeSegment(0, recording: "r1", wordCount: 1, text: "first", at: 1, in: runtime)
    let plan = Self.pagePlan(recording: "r1", page: 0, size: 4)
    let reader = EqualResultReader()
    let stream = await runtime.observeLocally(plan)
    let reading = Task { for await emission in stream { await reader.record(emission) } }
    defer { reading.cancel() }
    try await reader.waitUntilCurrent(with: runtime.query(plan), "the reader sees the first text")

    try await Self.writeSegmentText(0, text: "second", at: 2, in: runtime)

    let current = try await runtime.query(plan)
    expectNoDifference(current.first?.values["text"], .one(.string("second")))
    try await reader.waitUntilCurrent(with: current, "the reader sees the second text")
  }

  /// Random inserts, updates, text-only updates, moves between recordings, reorders and deletes against the newest
  /// segments of two recordings and an unfiltered list: after every write each reader holds what a fresh query returns,
  /// so no reader is left with a result the store moved past (#653).
  @Test(arguments: [UInt64(653), 654, 655])
  func readersStayCurrentThroughRandomWrites(seed: UInt64) async throws {
    var plans: [InstantQueryPlan] = []
    for recording in ["r1", "r2"] {
      plans += [2, 5].map { size in
        InstantQueryPlan(
          id: "energy.newest.\(recording).\(size)",
          namespace: Self.pageNamespace,
          filters: [.equals(field: "recordingID", value: .string(recording))],
          order: InstantQueryOrder("index", .descending),
          limit: size
        )
      }
    }
    plans.append(
      InstantQueryPlan(
        id: "energy.oldest",
        namespace: Self.pageNamespace,
        order: InstantQueryOrder("index", .ascending),
        limit: 5
      )
    )
    try await Self.checkReadersThroughRandomWrites(
      seed: seed,
      plans: plans,
      operations: [.insert, .update, .textOnly, .move, .reorder, .delete]
    )
  }

  /// The same against offset pages, with the writes that keep every segment in its recording: inserts, updates,
  /// text-only updates and reorders (#653).
  @Test(arguments: [UInt64(656), 657, 658])
  func offsetPagesStayCurrentThroughRandomWrites(seed: UInt64) async throws {
    var plans: [InstantQueryPlan] = []
    for recording in ["r1", "r2"] {
      plans += (0..<4).map { Self.pagePlan(recording: recording, page: $0, size: 3) }
    }
    try await Self.checkReadersThroughRandomWrites(
      seed: seed,
      plans: plans,
      operations: [.insert, .update, .textOnly, .reorder]
    )
  }

  // MARK: - Helpers

  static func todoTime(_ step: Int) -> InstantTimestamp {
    InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(step) * 1_000)
  }

  /// Creates `todo-<name>` with its creation time `step` seconds after the fixture's base time.
  static func createTodo(_ name: String, at step: Int, in runtime: InstantRuntime) async throws {
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-\(name)",
        operations: TodoExample.createOperations(
          id: "todo-\(name)",
          text: name,
          createdAt: todoTime(step),
          transactionID: "tx-\(name)"
        )
      ),
      createdAt: todoTime(step)
    )
  }

  static let pageNamespace = "energyPageSegments"

  static let pageAttributes: [InstantAttribute] = [
    .primaryKey(namespace: pageNamespace),
    InstantAttribute(
      id: "\(pageNamespace)/recordingID",
      namespace: pageNamespace,
      name: "recordingID",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(pageNamespace)/index",
      namespace: pageNamespace,
      name: "index",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(id: "\(pageNamespace)/wordCount", namespace: pageNamespace, name: "wordCount", valueType: .number),
    InstantAttribute(id: "\(pageNamespace)/text", namespace: pageNamespace, name: "text", valueType: .string),
  ]

  /// An offline runtime whose segments keep `text` on disk only, as a transcript keeps its words.
  static func pageRuntime(_ name: String) async throws -> InstantRuntime {
    try await InstantOfflineRuntimeFixture.offlineRuntime(name) { configuration in
      configuration.initialAttributes = pageAttributes
      configuration.deferredValueResidency = InstantDeferredValueResidencyPolicy(
        attributeIDs: ["\(pageNamespace)/text"]
      )
    }
  }

  static func segmentID(_ index: Int) -> String {
    "segment-\(index)"
  }

  /// Page `page` of a recording's segments, newest first, `size` to a page.
  static func pagePlan(recording: String, page: Int, size: Int) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "energy.pages.\(recording).\(page)",
      namespace: pageNamespace,
      filters: [.equals(field: "recordingID", value: .string(recording))],
      order: InstantQueryOrder("index", .descending),
      offset: page == 0 ? nil : page * size,
      limit: size
    )
  }

  /// Writes every field of segment `index`.
  static func writeSegment(
    _ index: Int,
    recording: String,
    wordCount: Int,
    text: String? = nil,
    at step: Int,
    in runtime: InstantRuntime
  ) async throws {
    let id = segmentID(index)
    let transactionID = "tx-segment-\(index)-\(step)"
    let time = todoTime(step)
    func insert(_ name: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(pageNamespace)/\(name)",
          value: value,
          txID: transactionID,
          txTime: time
        )
      )
    }
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .insert(
            InstantTriple(
              entityID: id,
              attributeID: InstantAttribute.primaryKeyID(namespace: pageNamespace),
              value: .string(id),
              txID: transactionID,
              txTime: time
            )
          ),
          insert("recordingID", .string(recording)),
          insert("index", .number(Double(index))),
          insert("wordCount", .number(Double(wordCount))),
          insert("text", .string(text ?? "words \(wordCount)")),
        ]
      ),
      createdAt: time
    )
  }

  /// Writes only segment `index`'s text, which is kept on disk only.
  static func writeSegmentText(_ index: Int, text: String, at step: Int, in runtime: InstantRuntime) async throws {
    let transactionID = "tx-text-\(index)-\(step)"
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .insert(
            InstantTriple(
              entityID: segmentID(index),
              attributeID: "\(pageNamespace)/text",
              value: .string(text),
              txID: transactionID,
              txTime: todoTime(step)
            )
          )
        ]
      ),
      createdAt: todoTime(step)
    )
  }

  /// Moves segment `index` to another place in its recording's order.
  static func writeSegmentIndex(_ index: Int, to value: Double, at step: Int, in runtime: InstantRuntime) async throws {
    let transactionID = "tx-index-\(index)-\(step)"
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .insert(
            InstantTriple(
              entityID: segmentID(index),
              attributeID: "\(pageNamespace)/index",
              value: .number(value),
              txID: transactionID,
              txTime: todoTime(step)
            )
          )
        ]
      ),
      createdAt: todoTime(step)
    )
  }

  enum RandomSegmentWrite: CaseIterable {
    case insert, update, textOnly, move, reorder, delete
  }

  /// Seeds 16 segments in two recordings, observes `plans`, then makes 48 random writes of the kinds in `operations`,
  /// waiting after each until every reader holds what a fresh query returns.
  static func checkReadersThroughRandomWrites(
    seed: UInt64,
    plans: [InstantQueryPlan],
    operations: [RandomSegmentWrite]
  ) async throws {
    let runtime = try await pageRuntime("equal-result-random-\(seed)")
    var random = InfiniteWindowRandom(seed: seed)
    var segments: [Int: (recording: String, wordCount: Int)] = [:]
    var time = 1
    for index in 0..<16 {
      let recording = index % 3 == 0 ? "r2" : "r1"
      segments[index] = (recording, 1)
      try await writeSegment(index, recording: recording, wordCount: 1, at: time, in: runtime)
      time += 1
    }
    var readers: [EqualResultReader] = []
    var readings: [Task<Void, Never>] = []
    for plan in plans {
      let reader = EqualResultReader()
      let stream = await runtime.observeLocally(plan)
      readers.append(reader)
      readings.append(Task { for await emission in stream { await reader.record(emission) } })
    }
    defer { readings.forEach { $0.cancel() } }
    var nextIndex = 16
    for step in 0..<48 {
      let existing = segments.keys.sorted()
      let operation = operations[random.int(0...(operations.count - 1))]
      guard operation != .insert, !existing.isEmpty else {
        let recording = random.chance(50) ? "r1" : "r2"
        segments[nextIndex] = (recording, 1)
        try await writeSegment(nextIndex, recording: recording, wordCount: 1, at: time, in: runtime)
        nextIndex += 1
        time += 1
        try await waitUntilEveryReaderIsCurrent(readers, plans: plans, runtime: runtime, "seed \(seed) step \(step)")
        continue
      }
      let index = existing[random.int(0...(existing.count - 1))]
      let segment = segments[index]!
      switch operation {
      case .insert:
        break
      case .update:
        segments[index] = (segment.recording, segment.wordCount + 1)
        try await writeSegment(
          index,
          recording: segment.recording,
          wordCount: segment.wordCount + 1,
          at: time,
          in: runtime
        )
      case .textOnly:
        try await writeSegmentText(index, text: "step \(step)", at: time, in: runtime)
      case .move:
        let recording = segment.recording == "r1" ? "r2" : "r1"
        segments[index] = (recording, segment.wordCount)
        try await writeSegment(index, recording: recording, wordCount: segment.wordCount, at: time, in: runtime)
      case .reorder:
        try await writeSegmentIndex(index, to: Double(nextIndex) + 0.5, at: time, in: runtime)
      case .delete:
        segments[index] = nil
        _ = try await runtime.transact(
          InstantStoreTransaction(
            id: "tx-delete-\(index)-\(time)",
            operations: [.deleteEntityInNamespace(entityID: segmentID(index), namespace: pageNamespace)]
          ),
          createdAt: todoTime(time)
        )
      }
      time += 1
      try await waitUntilEveryReaderIsCurrent(readers, plans: plans, runtime: runtime, "seed \(seed) step \(step)")
    }
  }

  static func waitUntilEveryReaderIsCurrent(
    _ readers: [EqualResultReader],
    plans: [InstantQueryPlan],
    runtime: InstantRuntime,
    _ description: String
  ) async throws {
    for (plan, reader) in zip(plans, readers) {
      try await reader.waitUntilCurrent(with: runtime.query(plan), "\(description): \(plan.id) is current")
    }
  }

  static func temporaryCacheURL(_ name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-write-path-energy-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }

  static let largeStoreAttributes = [
    InstantAttribute(
      id: "energy-large/value",
      namespace: "energy-large",
      name: "value",
      valueType: .string,
      cardinality: .one,
      isIndexed: true,
      isUnique: false
    )
  ]

  static func largeStoreTriples(count: Int) -> [InstantTriple] {
    (0..<count).map { index in
      InstantTriple(
        entityID: "large-entity-\(index)",
        attributeID: "energy-large/value",
        value: .string("value-\(index)-" + String(repeating: "x", count: 64)),
        txID: "seed-\(index)",
        txTime: InstantTimestamp(milliseconds: Int64(index + 1))
      )
    }
  }
}

/// The emissions one observer was handed, for a test to wait on.
actor EqualResultReader {
  private(set) var emissions: [InstantQueryEmission] = []

  func record(_ emission: InstantQueryEmission) {
    emissions.append(emission)
  }

  /// Waits until the newest emission shows `expected`, at most 5 s.
  func waitUntilCurrent(
    with expected: [InstantEntitySnapshot],
    _ description: String
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while emissions.last?.values != expected {
      guard ContinuousClock.now < deadline else {
        expectNoDifference(emissions.last?.values, expected, "Timed out after 5000 ms waiting until \(description).")
        return
      }
      try await Task.sleep(nanoseconds: 2_000_000)
    }
  }
}
