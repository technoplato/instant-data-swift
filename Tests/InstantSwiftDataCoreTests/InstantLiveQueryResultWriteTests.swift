// History:
// - 2026-10-30: a changed result's JSON waits for the app's flush instead of being written every five minutes, and a
//   waiting result's marker holds its page info for the rebuild after a kill (#1426).
// - 2026-10-31: no result's JSON is written or waits: a stored result is its rows, read here from the header, the
//   ownership rows and the facts, so the flush, an unsubscribe and the close write nothing (#1426).

import CustomDump
import Foundation
import SQLite3
@testable import InstantSwiftDataCore
import Testing

/// Persisting a live query's result after every server refresh rewrote the whole result as one JSON blob.
///
/// On build 90 (library 1.9.7) iOS filed a disk-writes report for a phone: 1,073.74 MB of file-backed memory dirtied
/// in 185 s right after launch (14:14-14:17, 2026-10-04), 92 of 99 samples under
/// `SQLitePersistenceStore.commitServerApplyPlan` and `saveLiveQueryResultWithoutTransaction`, which upserted
/// `json = excluded.json` for every refresh of every subscribed query. The live recording's queries hold about 1,100
/// segments with their words, so each refresh rewrote megabytes, and the WAL again. Upstream `Reactor.js` persists
/// `querySubs` through a `PersistedObject` that writes only the keys that changed, throttled (100 ms, then an idle
/// callback up to 1 s), and flushes before unload.
///
/// The JSON then waited, first for an interval (#566, #1123) and then for the app's flush (1.9.54), with the newest
/// result in memory and a kill repaired at the next launch. Since #1426 a stored result is its ownership rows, its facts
/// and a narrow header, which every save writes exactly: no result's JSON is written, and nothing waits. The stored
/// result is also the previous result a later server result is compared with to retract what left it, so a kill must
/// not let a fact the server deleted stay.
@Suite(.serialized)
struct InstantLiveQueryResultWriteTests {
  /// A clock the test moves: every refresh is stamped with it.
  final class TestClock: @unchecked Sendable {
    // SAFETY: `lock` protects `milliseconds`.
    private let lock = NSLock()
    private var milliseconds: Int64

    init(_ milliseconds: Int64) {
      self.milliseconds = milliseconds
    }

    func now() -> InstantTimestamp {
      lock.lock()
      defer { lock.unlock() }
      return InstantTimestamp(milliseconds: milliseconds)
    }

    func advance(by delta: Int64) {
      lock.lock()
      milliseconds += delta
      lock.unlock()
    }
  }

  static func temporaryCacheURL() throws -> URL {
    // Removed when the process exits (#1021: these stores were never removed and filled the Mac mini).
    let directory = try InstantTestScratch.directory("instant-live-query-result-writes")
    return directory.appendingPathComponent("instant.sqlite")
  }

  /// One todo's facts in the server's datalog shape.
  static func todoJoinRow(id: String, text: String, createdAt: Int64) -> InstantLiveJSONValue {
    func fact(_ attributeID: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
      .array([.string(id), .string(attributeID), value, .number(Double(createdAt))])
    }
    return .array([
      fact("server-todos-id", .string(id)),
      fact("server-todos-text", .string(text)),
      fact("server-todos-is-completed", .bool(false)),
      fact("server-todos-created-at", .number(Double(createdAt))),
    ])
  }

  /// The todo query's result as the server sends it: one join row per todo, and the page info when `hasNextPage` is
  /// given.
  static func todoResult(_ texts: [String], hasNextPage: Bool? = nil) -> [InstantLiveJSONValue] {
    var data: [String: InstantLiveJSONValue] = [
      "datalog-result": .object([
        "join-rows": .array(
          texts.enumerated().map { index, text in
            todoJoinRow(id: todoID(index), text: text, createdAt: 1_700_000_000_000 + Int64(index))
          }
        )
      ])
    ]
    if let hasNextPage {
      data["page-info"] = .object([
        TodoExample.namespace: .object([
          "start-cursor": .null,
          "end-cursor": .null,
          "has-next-page?": .bool(hasNextPage),
          "has-previous-page?": .bool(false),
        ])
      ])
    }
    return [.object(["data": .object(data), "child-nodes": .array([])])]
  }

  static func todoID(_ index: Int) -> String {
    String(format: "00000000-0000-4000-8000-%012ld", index)
  }

  /// A section's worth of words: about 1 KB of text per todo, so 1,100 todos make a result of about 1.2 MB, the size
  /// of a long live recording's segments with their words.
  static func longText(_ index: Int, revision: Int) -> String {
    "segment \(index) revision \(revision) " + String(repeating: "spoken words with timings ", count: 40)
  }

  struct Fixture {
    var runtime: InstantRuntime
    var session: LiveReactorParitySession
    var query: InstantLiveJSONValue
    var observation: InstantQueryObservationLease
    var clock: TestClock
    var url: URL
  }

  static func makeRuntime(
    url: URL,
    session: LiveReactorParitySession,
    clock: TestClock,
    appID: String
  ) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      now: { clock.now() },
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  /// Subscribes the todo query, has the server answer it with `texts`, and waits for the rows.
  static func answeredTodos(
    _ texts: [String],
    appID: String,
    url: URL? = nil,
    clock: TestClock = TestClock(1_791_150_000_000)
  ) async throws -> Fixture {
    let url = try url ?? temporaryCacheURL()
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let runtime = try await makeRuntime(url: url, session: session, clock: clock, appID: appID)
    let observation = await runtime.observeQueryLease(TodoExample.query)
    _ = try await runtime.connect()
    try await waitFor("the todo query's add-query") {
      await session.sentMessages().contains { $0.op == "add-query" }
    }
    await session.enqueue(
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "server-tx-0",
        result: todoResult(texts)
      )
    )
    let fixture = Fixture(
      runtime: runtime,
      session: session,
      query: query,
      observation: observation,
      clock: clock,
      url: url
    )
    try await waitForStoredTexts(texts, in: fixture)
    return fixture
  }

  static func waitFor(
    _ description: String,
    timeout: Duration = .seconds(10),
    _ condition: @Sendable () async throws -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + timeout
    while !(try await condition()) {
      guard ContinuousClock.now < deadline else {
        Issue.record("Timed out waiting for \(description).")
        throw CancellationError()
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  /// Waits until the store holds exactly these todo texts, in order.
  static func waitForStoredTexts(_ texts: [String], in fixture: Fixture) async throws {
    try await waitFor("the store to show \(texts.count) todos") {
      let rows = await fixture.runtime.store.materialize(TodoExample.query)
      return rows.count == texts.count
        && rows.map { $0.values["text"]?.first } == texts.map { InstantValue.string($0) as InstantValue? }
    }
  }

  /// Sends the server's refresh of the todo query with `texts` and waits until the runtime has saved its result.
  static func refresh(
    _ texts: [String],
    hasNextPage: Bool? = nil,
    in fixture: Fixture,
    timeout: Duration = .seconds(10)
  ) async throws {
    let savesBefore = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting().saves
    let number = fixture.clock.now().milliseconds
    await fixture.session.enqueue(
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: "refresh-\(number)",
        fields: [
          "attrs": .array([]),
          "computations": .array([
            .object([
              "instaql-query": fixture.query,
              "instaql-result": .array(todoResult(texts, hasNextPage: hasNextPage)),
              "processed-tx-id": .string("server-tx-\(number)"),
            ])
          ]),
          "processed-tx-id": .string("server-tx-\(number)"),
        ]
      )
    )
    try await waitFor("the refresh's result to be saved", timeout: timeout) {
      await fixture.runtime.liveQueryResultJSONWriteStatsForTesting().saves > savesBefore
    }
  }

  // MARK: - Unchanged results

  @Test
  func aRefreshWhoseResultDidNotChangeWritesNoResultJSON() async throws {
    let texts = (0..<20).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-unchanged")
    let afterAnswer = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    #expect(afterAnswer.writes == 0, "the server's answer is stored as its rows: \(afterAnswer)")
    #expect(try Self.storedTodoTexts(fixture.url) == texts, "the stored result holds the answer")

    for _ in 0..<5 {
      fixture.clock.advance(by: 60_000)
      try await Self.refresh(texts, in: fixture)
    }
    let afterRefreshes = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    expectNoDifference(
      afterRefreshes.writes - afterAnswer.writes,
      0,
      "five refreshes with the same result, a minute apart, wrote \(afterRefreshes.bytes - afterAnswer.bytes) bytes of result JSON"
    )
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  // MARK: - Nothing waits

  /// A changed result's whole JSON is never written (#1426): eleven changed refreshes over five minutes write none of
  /// it, each refresh's result is stored as it is applied, and the app's flush writes nothing. Until #1426 the refresh
  /// five minutes later wrote the whole JSON again (#1123's interval), the one write a refresh made that followed the
  /// result instead of the change, and then the JSON waited for the app's flush.
  @Test
  func changedRefreshesWriteNoResultJSONAndEachIsStored() async throws {
    var texts = (0..<20).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-changed")
    let afterAnswer = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()

    for revision in 1...10 {
      fixture.clock.advance(by: 1_000)
      texts[revision % texts.count] = Self.longText(revision % texts.count, revision: revision)
      try await Self.refresh(texts, in: fixture)
      #expect(try Self.storedTodoTexts(fixture.url) == texts, "refresh \(revision)'s result is stored")
    }
    fixture.clock.advance(by: 291_000)
    texts[0] = Self.longText(0, revision: 99)
    try await Self.refresh(texts, in: fixture)
    let beforeFlush = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    #expect(
      beforeFlush.writes == afterAnswer.writes,
      "eleven changed refreshes over five minutes wrote the result JSON \(beforeFlush.writes - afterAnswer.writes) times"
    )
    #expect(try Self.storedTodoTexts(fixture.url) == texts, "the stored result is the newest")

    try await fixture.runtime.flushPendingLiveQueryResults()
    let afterFlush = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    expectNoDifference(afterFlush.writes, beforeFlush.writes, "the flush writes nothing")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  /// Ten minutes of a foreground session's refreshes, ten seconds apart, each changing the result: none writes its whole
  /// JSON (#1426). Every 30 s it was twenty whole-result writes in ten minutes, and on #1076's exercise 3.90 of a live
  /// write's 54.9 log frames; every five minutes (#1123), two.
  @Test
  func tenMinutesOfRefreshesWriteNoResultJSON() async throws {
    var texts = (0..<20).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-ten-minutes")
    let afterAnswer = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()

    for revision in 1...60 {
      fixture.clock.advance(by: 10_000)
      texts[revision % texts.count] = Self.longText(revision % texts.count, revision: revision)
      try await Self.refresh(texts, in: fixture)
    }

    let writes = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting().writes - afterAnswer.writes
    #expect(writes == 0, "sixty changed refreshes over ten minutes wrote the result JSON \(writes) times")
    #expect(try Self.storedTodoTexts(fixture.url) == texts, "the stored result is the newest")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  /// A query that unsubscribes leaves its stored result as its last refresh stored it: nothing waited to be written.
  @Test
  func anUnsubscribeWritesNoResultJSON() async throws {
    var texts = (0..<5).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-unsubscribe")
    fixture.clock.advance(by: 1_000)
    texts[1] = Self.longText(1, revision: 1)
    try await Self.refresh(texts, in: fixture)
    let refreshed = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    await fixture.observation.cancel()
    try await Self.waitFor("the query's remove-query") {
      await fixture.session.sentMessages().contains { $0.op == "remove-query" }
    }
    let unsubscribed = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    expectNoDifference(unsubscribed.writes, refreshed.writes, "the unsubscribe wrote no result JSON")
    #expect(try Self.storedTodoTexts(fixture.url) == texts, "the stored result is the last refresh's")
    _ = try await fixture.runtime.closeConnection()
  }

  /// The next server result is compared with the stored result: a row that arrived and then left within seconds is
  /// retracted.
  @Test
  func aRowThatArrivesAndLeavesIsRetracted() async throws {
    let first = (0..<3).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(first, appID: "live-result-writes-in-session")
    fixture.clock.advance(by: 1_000)
    try await Self.refresh(first + [Self.longText(3, revision: 0)], in: fixture)
    try await Self.waitForStoredTexts(first + [Self.longText(3, revision: 0)], in: fixture)
    fixture.clock.advance(by: 1_000)
    try await Self.refresh(first, in: fixture)
    try await Self.waitForStoredTexts(first, in: fixture)
    let stats = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    #expect(stats.writes == 0, "no refresh wrote the result JSON: \(stats)")
    expectNoDifference(try Self.storedFactCount(fixture.url, entityID: Self.todoID(3)), 0, "the row's facts are retracted")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  // MARK: - A kill

  /// If the app is killed after a refresh, the next server result must still retract what left the result: the
  /// reopened store compares it with the result the killed process last stored. Until #1426 that refresh's JSON waited,
  /// and bootstrap rebuilt the result from its ownership rows; now the rows are the result.
  @Test
  func afterAKillTheNextServerResultRetractsWhatLeftTheResult() async throws {
    let url = try Self.temporaryCacheURL()
    let clock = TestClock(1_791_150_000_000)
    let first = (0..<3).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(first, appID: "live-result-writes-crash", url: url, clock: clock)
    // A fourth todo arrives.
    clock.advance(by: 2_000)
    let withFourth = first + [Self.longText(3, revision: 0)]
    try await Self.refresh(withFourth, in: fixture)

    // The app is killed: no flush, no close. A new process opens the same store.
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    clock.advance(by: 60_000)
    let reopened = try await Self.makeRuntime(url: url, session: session, clock: clock, appID: "live-result-writes-crash")
    let observation = await reopened.observeQueryLease(TodoExample.query)
    _ = try await reopened.connect()
    try await Self.waitFor("the reopened runtime's add-query") {
      await session.sentMessages().contains { $0.op == "add-query" }
    }
    // Meanwhile the fourth todo was deleted on the server: its answer holds the first three again.
    await session.enqueue(
      liveReactorAddQueryOK(
        query: fixture.query,
        processedTransactionID: "server-tx-after-kill",
        result: Self.todoResult(first)
      )
    )
    try await Self.waitFor("the reopened runtime to apply the server's answer") {
      try await reopened.isAnsweredOnCurrentSocketForTesting(TodoExample.query)
    }
    let rows = await reopened.store.materialize(TodoExample.query)
    expectNoDifference(
      rows.map(\.id),
      (0..<3).map(Self.todoID),
      "the todo the server deleted is retracted"
    )
    // The reopened store shows only the entities its stored results name, so the deleted todo can be missing from it
    // and still left in SQLite, where a later read of the entity would find it. The server's answer is compared with
    // the result the killed process last stored, so the deleted todo's facts leave SQLite too.
    let storedFourth = try Self.storedFactCount(url, entityID: Self.todoID(3))
    expectNoDifference(storedFourth, 0, "the deleted todo's facts are retracted from SQLite")
    await observation.cancel()
    _ = try await reopened.closeConnection()
    _ = fixture
  }

  /// After a kill, the stored result holds the newest refresh's page info and facts (#1426): its header holds the page
  /// info, written with each save. A window over a growing list moves its cursors with every new row.
  @Test
  func afterAKillTheStoredResultHoldsTheNewestPageInfo() async throws {
    let url = try Self.temporaryCacheURL()
    let clock = TestClock(1_791_150_000_000)
    let texts = (0..<3).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-page-info", url: url, clock: clock)
    clock.advance(by: 2_000)
    var changed = texts
    changed[1] = Self.longText(1, revision: 1)
    try await Self.refresh(changed, hasNextPage: true, in: fixture)

    // The app is killed: no flush, no close. A new process opens the same store an hour later.
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    clock.advance(by: 3_600_000)
    let reopened = try await Self.makeRuntime(
      url: url,
      session: session,
      clock: clock,
      appID: "live-result-writes-page-info"
    )
    #expect(try Self.storedPageInfo(url)?.hasNextPage == true, "the stored result holds the newest page info")
    #expect(try Self.storedTodoTexts(url) == changed, "the stored result holds the newest facts")
    _ = try await reopened.closeConnection()
    _ = fixture
  }

  /// The result the SQLite store at `url` holds for the todo query, read from its rows (#1426).
  static func storedTodoResult(_ url: URL) throws -> InstantPersistedLiveQueryResult? {
    let keys = try InstantStoredLiveQueryResultTests.rows(
      url,
      "SELECT query_key FROM instant_live_query_results WHERE substr(query_key, 1, 16) <> 'released-result:' LIMIT 1"
    )
    guard let key = keys.first?.first ?? nil else { return nil }
    return try InstantStoredLiveQueryResultTests.storedResult(url, key: key)
  }

  /// The todo texts the stored result at `url` holds, in row order.
  static func storedTodoTexts(_ url: URL) throws -> [String] {
    (try storedTodoResult(url)?.triples ?? [])
      .filter { $0.attributeID == TodoExample.attributes[1].id }
      .sorted { $0.entityID < $1.entityID }
      .compactMap { triple in
        guard case let .string(text) = triple.value else { return nil }
        return text
      }
  }

  /// The page info the stored result at `url` holds.
  static func storedPageInfo(_ url: URL) throws -> InstantQueryPageInfo? {
    try storedTodoResult(url)?.pageInfo
  }

  /// How many facts of `entityID` the SQLite store at `url` holds.
  static func storedFactCount(_ url: URL, entityID: String) throws -> Int {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(database)
      throw StoredFactCountFailure(message: "could not open \(url.path)")
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(database, "SELECT COUNT(*) FROM instant_triples WHERE entity_id = ?", -1, &statement, nil)
        == SQLITE_OK
    else {
      throw StoredFactCountFailure(message: String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, entityID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw StoredFactCountFailure(message: String(cString: sqlite3_errmsg(database)))
    }
    return Int(sqlite3_column_int64(statement, 0))
  }

  struct StoredFactCountFailure: Error, CustomStringConvertible {
    var message: String
    var description: String { message }
  }

  // MARK: - Measurement

  /// A 1,100-row live query refreshed 100 times, each refresh changing one row, about 1 s apart: the bytes of result JSON
  /// written (none since #1426) and the SQLite pages written per refresh. The numbers go in the release notes.
  @Test
  func aLongRecordingsRefreshesWriteLittleResultJSON() async throws {
    var texts = (0..<1_100).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-measure")
    let before = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    let pagesBefore = await fixture.runtime.sqlitePagesWrittenForTesting()
    for revision in 1...100 {
      fixture.clock.advance(by: 1_000)
      texts[1_099 - (revision % 50)] = Self.longText(1_099 - (revision % 50), revision: revision)
      // A debug build applies a 1,100-row refresh in about a second, and in more than 10 s on a loaded Mac
      // (library-79's dev-198c, load 160): the measurement waits longer than the other tests.
      try await Self.refresh(texts, in: fixture, timeout: .seconds(60))
    }
    let after = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    let pagesAfter = await fixture.runtime.sqlitePagesWrittenForTesting()
    let bytesPerRefresh = (after.bytes - before.bytes) / 100
    let pagesPerRefresh = Double(pagesAfter.pages - pagesBefore.pages) / 100
    print(
      "live-result-writes: 1,100 rows, 100 refreshes over 100 s: result JSON writes \(after.writes - before.writes), "
        + "bytes per refresh \(bytesPerRefresh), SQLite pages per refresh \(pagesPerRefresh) "
        + "(\(pagesAfter.pageSize) B each, \(Int(pagesPerRefresh * Double(pagesAfter.pageSize))) B)"
    )
    // A stored result is its rows (#1426): no refresh writes its JSON (at most four in 100 s before, #1123).
    #expect(after.writes - before.writes == 0, "result JSON writes over 100 s: \(after.writes - before.writes)")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }
}
