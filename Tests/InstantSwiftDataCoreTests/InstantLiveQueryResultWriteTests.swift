import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Persisting a live query's result after every server refresh rewrote the whole result as one JSON blob.
///
/// On build 90 (library 1.9.7) iOS filed a disk-writes report for Michael's iPhone: 1,073.74 MB of file-backed memory
/// dirtied in 185 s right after launch (14:14-14:17, 2026-10-04), 92 of 99 samples under
/// `SQLitePersistenceStore.commitServerApplyPlan` and `saveLiveQueryResultWithoutTransaction`, which upserts
/// `json = excluded.json` for every refresh of every subscribed query. The live recording's queries hold about 1,100
/// segments with their words, so each refresh rewrote megabytes, and the WAL again. Upstream `Reactor.js` persists
/// `querySubs` through a `PersistedObject` that writes only the keys that changed, throttled (100 ms, then an idle
/// callback up to 1 s), and flushes before unload.
///
/// The stored JSON is also the previous result a later server result is compared with to retract what left it, so a
/// write that waits must not let a crash keep a fact the server deleted.
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
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-live-query-result-writes-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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

  /// The todo query's result as the server sends it: one join row per todo.
  static func todoResult(_ texts: [String]) -> [InstantLiveJSONValue] {
    [
      .object([
        "data": .object([
          "datalog-result": .object([
            "join-rows": .array(
              texts.enumerated().map { index, text in
                todoJoinRow(id: todoID(index), text: text, createdAt: 1_700_000_000_000 + Int64(index))
              }
            )
          ])
        ]),
        "child-nodes": .array([]),
      ])
    ]
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
    // A crash test must not have a timer write the JSON behind its back.
    configuration.liveQueryResultJSONFlushSleep = { _ in try await Task.sleep(for: .seconds(3_600)) }
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
  static func refresh(_ texts: [String], in fixture: Fixture) async throws {
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
              "instaql-result": .array(todoResult(texts)),
              "processed-tx-id": .string("server-tx-\(number)"),
            ])
          ]),
          "processed-tx-id": .string("server-tx-\(number)"),
        ]
      )
    )
    try await waitFor("the refresh's result to be saved") {
      await fixture.runtime.liveQueryResultJSONWriteStatsForTesting().saves > savesBefore
    }
  }

  // MARK: - Unchanged results

  @Test
  func aRefreshWhoseResultDidNotChangeWritesNoResultJSON() async throws {
    let texts = (0..<20).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-unchanged")
    let afterAnswer = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    #expect(afterAnswer.writes >= 1, "the server's answer is stored: \(afterAnswer)")

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

  // MARK: - Throttled writes

  @Test
  func refreshesWithinThirtySecondsWriteTheResultJSONOnceAndALaterOneWritesAgain() async throws {
    var texts = (0..<20).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-throttled")
    let afterAnswer = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()

    // Ten changed results, one second apart: one write per query per 30 s at most.
    for revision in 1...10 {
      fixture.clock.advance(by: 1_000)
      texts[revision % texts.count] = Self.longText(revision % texts.count, revision: revision)
      try await Self.refresh(texts, in: fixture)
    }
    let afterBurst = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    #expect(
      afterBurst.writes - afterAnswer.writes <= 1,
      "ten changed refreshes in 10 s wrote the result JSON \(afterBurst.writes - afterAnswer.writes) times"
    )

    // 31 s after the answer's write, the next changed result writes the newest result once.
    fixture.clock.advance(by: 21_000)
    texts[0] = Self.longText(0, revision: 99)
    try await Self.refresh(texts, in: fixture)
    let afterLater = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    #expect(afterLater.writes - afterBurst.writes >= 1, "the refresh after 30 s wrote the result")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  // MARK: - Writing what waited

  /// The app's flush on background or terminate writes every result whose write waited, and a new process opens the
  /// newest result without rebuilding it.
  @Test
  func theAppsFlushWritesTheResultsWhoseWriteWaited() async throws {
    let url = try Self.temporaryCacheURL()
    var texts = (0..<5).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-flush", url: url)
    fixture.clock.advance(by: 1_000)
    texts[2] = Self.longText(2, revision: 1)
    try await Self.refresh(texts, in: fixture)
    let waited = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()

    try await fixture.runtime.flushPendingLiveQueryResults()
    let flushed = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    expectNoDifference(flushed.writes - waited.writes, 1, "the flush wrote the result whose write waited")
    try await fixture.runtime.flushPendingLiveQueryResults()
    let again = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    expectNoDifference(again.writes, flushed.writes, "nothing waits after a flush")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  /// A query that unsubscribes is not refreshed again, so its result is written when it leaves.
  @Test
  func unsubscribingWritesTheQuerysResultIfItsWriteWaited() async throws {
    var texts = (0..<5).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-unsubscribe")
    fixture.clock.advance(by: 1_000)
    texts[1] = Self.longText(1, revision: 1)
    try await Self.refresh(texts, in: fixture)
    let waited = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    await fixture.observation.cancel()
    try await Self.waitFor("the unsubscribed query's result to be written") {
      await fixture.runtime.liveQueryResultJSONWriteStatsForTesting().writes > waited.writes
    }
    _ = try await fixture.runtime.closeConnection()
  }

  // MARK: - A crash between throttled writes

  /// A refresh whose JSON write waits leaves the stored JSON older than the facts. If the app is killed before the
  /// write, the next server result must still retract what left the result: the reopened store compares it with the
  /// newest result, not the older JSON.
  @Test
  func afterAKillBetweenThrottledWritesTheNextServerResultRetractsWhatLeftTheResult() async throws {
    let url = try Self.temporaryCacheURL()
    let clock = TestClock(1_791_150_000_000)
    let first = (0..<3).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(first, appID: "live-result-writes-crash", url: url, clock: clock)
    // A fourth todo arrives within 30 s of the stored answer, so its result's JSON write waits.
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
      "the todo the server deleted is retracted, not kept from the older stored JSON"
    )
    await observation.cancel()
    _ = try await reopened.closeConnection()
    _ = fixture
  }

  // MARK: - Measurement

  /// A 1,100-row live query refreshed 100 times, each refresh changing one row, about 1 s apart: the bytes of result JSON
  /// written and the SQLite pages written per refresh. The numbers go in the release notes.
  @Test
  func aLongRecordingsRefreshesWriteLittleResultJSON() async throws {
    var texts = (0..<1_100).map { Self.longText($0, revision: 0) }
    let fixture = try await Self.answeredTodos(texts, appID: "live-result-writes-measure")
    let before = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    let pagesBefore = await fixture.runtime.sqlitePagesWrittenForTesting()
    for revision in 1...100 {
      fixture.clock.advance(by: 1_000)
      texts[1_099 - (revision % 50)] = Self.longText(1_099 - (revision % 50), revision: revision)
      try await Self.refresh(texts, in: fixture)
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
    // 100 s of refreshes: at most four 30 s windows, so at most four whole-result writes.
    #expect(after.writes - before.writes <= 4, "result JSON writes over 100 s: \(after.writes - before.writes)")
    await fixture.observation.cancel()
    _ = try await fixture.runtime.closeConnection()
  }
}
