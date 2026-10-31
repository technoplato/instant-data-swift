// History:
// - 2026-10-30: added (#1426): what a server refresh that restates a result writes to SQLite, by b-tree, when one of
//   its rows changed: a 50-row result against a 1-row one, in todo rows and in rows shaped like a phone's recordings;
//   and what a relaunch's answers write when the stored result did not change, or changed in one row.

import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

extension StorageIOExercises {
  /// Instant's server restates a live query's whole result after every transaction that changes it (upstream
  /// `session.clj` `handle-refresh!`), so a list of 50 rows arrives whole when one of them changed. The store merges
  /// the result's facts, so what it writes should follow the rows that changed, not the rows the frame carries
  /// (#1426): within twice what a 1-row result's refresh writes, plus ``RefreshWrites/fixedOverhead``.
  ///
  /// Measured 2026-10-30 on main (`2a6e6221`, laptop, debug): todo rows 9.0 log frames a refresh for 50 rows against
  /// 10.0 for 1; rows shaped like a phone's recordings, held by three results, 12.0 against 8.0. The reduced server
  /// apply leaves a resident fact with the same value alone (`.preserveExactResident`), so only the changed row reaches
  /// SQLite.
  @Test
  func aRefreshWritesWhatChangedNotWhatItRestates() async throws {
    for shape in [RefreshShape.todos, .recordings] {
      let fifty = try await RefreshWrites.measure(shape, rows: 50, label: "refresh-writes-\(shape.name)-50")
      let one = try await RefreshWrites.measure(shape, rows: 1, label: "refresh-writes-\(shape.name)-1")
      fifty.print("\(shape.name)-of50")
      one.print("\(shape.name)-of1")
      #expect(
        fifty.bytesPerRefresh <= 2 * one.bytesPerRefresh + RefreshWrites.fixedOverhead,
        "\(shape.name): 50 rows wrote \(fifty.bytesPerRefresh) B a refresh, 1 row \(one.bytesPerRefresh) B"
      )
    }
  }

  /// Five minutes of a recording's list refreshes, one every 6 s, each changing one row of three results that hold the
  /// same 50 rows shaped like a phone's recordings (#1426). Every five minutes each changed result's whole JSON was
  /// written again (#1123's interval): 85.4 KB a refresh for 50 rows against 33.7 KB for 1, 9.7 of the 50-row
  /// refresh's 20.7 log frames in `instant_live_query_results` (main `2a6e6221`, laptop, debug). The ownership rows
  /// hold exactly what each result holds after every refresh, and a result whose JSON waits is rebuilt from them at
  /// the next launch (#566), so the JSON waits for the app's flush instead.
  @Test
  func fiveMinutesOfListRefreshesWriteWhatChangedNotTheWholeResult() async throws {
    let fifty = try await RefreshWrites.measure(
      .recordings, rows: 50, label: "refresh-writes-interval-50", refreshes: 50, millisecondsApart: 6_000
    )
    let one = try await RefreshWrites.measure(
      .recordings, rows: 1, label: "refresh-writes-interval-1", refreshes: 50, millisecondsApart: 6_000
    )
    fifty.print("recordings-interval-of50")
    one.print("recordings-interval-of1")
    #expect(fifty.resultJSONWrites == 0, "the changed results' JSON was written \(fifty.resultJSONWrites) times")
    #expect(
      fifty.bytesPerRefresh <= 2 * one.bytesPerRefresh + RefreshWrites.fixedOverhead,
      "50 rows wrote \(fifty.bytesPerRefresh) B a refresh, 1 row \(one.bytesPerRefresh) B"
    )
  }
}

extension StorageIOExercises {
  /// After a relaunch the server answers each query again with its whole result (`add-query-ok`), and most results did
  /// not change while the app was closed: their facts, ownership rows and JSON are already on disk. The stored JSON is
  /// current at bootstrap (a result whose write waited is rebuilt from its ownership rows, #566), so an answer that
  /// restates it unchanged should write its row's count and time, not the whole JSON again, and one that changed one
  /// row should cost what that row costs (#1426).
  @Test
  func aRelaunchsAnswersWriteWhatChangedNotTheWholeResult() async throws {
    for shape in [RefreshShape.todos, .recordings] {
      for revision in [0, 1] {
        let step = "\(shape.name)-\(revision == 0 ? "unchanged" : "oneChanged")"
        let fifty = try await RelaunchWrites.measure(shape, rows: 50, revision: revision, label: "relaunch-\(step)-50")
        let one = try await RelaunchWrites.measure(shape, rows: 1, revision: revision, label: "relaunch-\(step)-1")
        fifty.print("\(step)-of50")
        one.print("\(step)-of1")
        #expect(fifty.resultJSONWrites == 0, "\(step): the result's JSON was written \(fifty.resultJSONWrites) times")
        #expect(
          fifty.writes.bytesPerRefresh <= 2 * one.writes.bytesPerRefresh + RefreshWrites.fixedOverhead,
          "\(step): 50 rows wrote \(fifty.writes.bytesPerRefresh) B, 1 row \(one.writes.bytesPerRefresh) B"
        )
      }
    }
  }
}

/// What a relaunch's answers wrote (#1426): a runtime answered with `rows` rows and closed, then a second runtime on
/// the same store answered with the last row at `revision`.
struct RelaunchWrites {
  var writes: RefreshWrites
  var resultJSONWrites: Int
  var resultJSONBytes: Int

  func print(_ step: String) {
    var line = StorageIOLine("relaunch-writes", step)
    line.add("resultJSONWrites", resultJSONWrites)
    line.add("resultJSONKB", Double(resultJSONBytes) / 1_024)
    line.print()
    writes.print(step)
  }

  static func measure(_ shape: RefreshShape, rows: Int, revision: Int, label: String) async throws -> Self {
    StorageIOCounters.install(asDefault: false)
    let directory = try InstantTestScratch.directory(label)
    StorageIOCounters.watch(directory: directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let url = directory.appendingPathComponent("instant.sqlite")
    let first = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await RefreshFixture.open(shape, rows: rows, url: url, appID: label)
    }
    try await first.runtime.flushPendingLiveQueryResults()
    await first.close()
    let second = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await RefreshFixture.start(
        shape,
        rows: rows,
        url: url,
        appID: label,
        startingAt: first.clock.now().milliseconds + 600_000
      )
    }
    try await Task.sleep(for: .milliseconds(200))
    let before = StorageIOCounters.snapshot()
    let callsBefore = InstantStorageWriteMeter.snapshot()
    let jsonBefore = await second.runtime.liveQueryResultJSONWriteStatsForTesting()
    try await second.answer(revision: revision)
    try await Task.sleep(for: .milliseconds(200))
    let io = StorageIOCounters.snapshot().subtracting(before)
    let calls = InstantStorageWriteMeter.snapshot().subtracting(callsBefore).operations
    let json = await second.runtime.liveQueryResultJSONWriteStatsForTesting()
    await second.close()
    return RelaunchWrites(
      writes: RefreshWrites(
        rows: rows,
        refreshes: 1,
        io: io,
        framesByBTree: try StorageIOPageMap.read(store: url).byName(io.walFramesByPage),
        calls: calls
      ),
      resultJSONWrites: json.writes - jsonBefore.writes,
      resultJSONBytes: json.bytes - jsonBefore.bytes
    )
  }
}

/// The rows a refresh restates, and how many live results hold them (#1426).
struct RefreshShape: Sendable {
  var name: String
  var attributes: [InstantAttribute]
  /// The attributes the server's `init-ok` names, under the ids its facts use.
  var serverAttributes: [InstantLiveJSONValue]
  var plans: [InstantQueryPlan]
  /// One row's facts as the server sends them, `[entity, attribute, value, created_at]`, at `revision` of what changes.
  var joinRow: @Sendable (_ row: Int, _ revision: Int) -> InstantLiveJSONValue

  /// Todo rows of about 1 KB of text each, held by one result.
  static let todos = RefreshShape(
    name: "todos",
    attributes: TodoExample.attributes,
    serverAttributes: liveReactorTodoServerAttrs,
    plans: [TodoExample.query],
    joinRow: { row, revision in
      InstantLiveQueryResultWriteTests.todoJoinRow(
        id: InstantLiveQueryResultWriteTests.todoID(row),
        text: InstantLiveQueryResultWriteTests.longText(row, revision: revision),
        createdAt: 1_700_000_000_000 + Int64(row)
      )
    }
  )

  /// Rows shaped like a phone's recordings list, from a copy of the phone's store (2026-10-30, sizes only): 16 facts
  /// and about 8.9 KB of values a row, 7.9 KB of them one build-info JSON. A final line changes the recording's update
  /// time, its speakers JSON and its newest preview line, and three of the phone's live results held every row.
  static let recordings = RefreshShape(
    name: "recordings",
    attributes: RecordingRows.attributes,
    serverAttributes: liveReactorServerAttrs(from: RecordingRows.attributes),
    plans: (0..<3).map(RecordingRows.plan),
    joinRow: { RecordingRows.joinRow($0, $1) }
  )

  func result(rows: Int, changedRow: Int, revision: Int) -> [InstantLiveJSONValue] {
    [
      .object([
        "data": .object([
          "datalog-result": .object([
            "join-rows": .array((0..<rows).map { joinRow($0, $0 == changedRow ? revision : 0) })
          ])
        ]),
        "child-nodes": .array([]),
      ])
    ]
  }
}

enum RecordingRows {
  static let namespace = "recordings"
  static let fields: [(name: String, type: InstantValueType)] = [
    ("title", .string), ("startedAtMs", .number), ("updatedAtMs", .number), ("durationSeconds", .number),
    ("ownerUserID", .string), ("owner", .string), ("deviceIcon", .string), ("buildInfo", .string),
    ("clipboardEntries", .string), ("systemAudioContextEntries", .string), ("speakers", .string),
    ("captureGapsJSON", .string), ("location", .string), ("previewSegmentA", .string), ("previewSegmentB", .string),
  ]
  static let attributes: [InstantAttribute] = [.primaryKey(namespace: namespace)] + fields.map {
    InstantAttribute(id: "\(namespace)/\($0.name)", namespace: namespace, name: $0.name, valueType: $0.type)
  }

  static func plan(_ index: Int) -> InstantQueryPlan {
    InstantQueryPlan(id: "recordings.list.\(index)", namespace: namespace, limit: 1_000 + index)
  }

  static func id(_ row: Int) -> String { String(format: "00000000-0000-4000-8000-%012ld", row) }

  static let buildInfo = "{\"build\":\"" + String(repeating: "commit 0123456789abcdef branch main ", count: 216) + "\"}"
  static let captureGaps = "[" + String(repeating: "{\"startMs\":1000,\"endMs\":2000},", count: 11) + "{}]"
  static let location = "{\"latitude\":40.0,\"longitude\":-74.0,\"place\":\""
    + String(repeating: "x", count: 200) + "\"}"

  static func joinRow(_ row: Int, _ revision: Int) -> InstantLiveJSONValue {
    let entity = id(row)
    let createdAt = Double(1_790_000_000_000 + Int64(row) * 1_000)
    func fact(_ name: String, _ value: InstantLiveJSONValue) -> InstantLiveJSONValue {
      .array([.string(entity), .string("\(namespace)/\(name)"), value, .number(createdAt)])
    }
    return .array([
      fact("id", .string(entity)),
      fact("title", .string("Recording \(row) on a weekday morning")),
      fact("startedAtMs", .number(createdAt)),
      fact("updatedAtMs", .number(createdAt + Double(revision))),
      fact("durationSeconds", .number(Double(600 + row))),
      fact("ownerUserID", .string("11111111-2222-4333-8444-555555555555")),
      fact("owner", .string("11111111-2222-4333-8444-555555555555")),
      fact("deviceIcon", .string("iphone.gen3")),
      fact("buildInfo", .string(buildInfo)),
      fact("clipboardEntries", .string("[]")),
      fact("systemAudioContextEntries", .string("[]")),
      fact("speakers", .string("[{\"label\":\"Speaker 1\",\"lines\":\(revision)}]")),
      fact("captureGapsJSON", .string(captureGaps)),
      fact("location", .string(location)),
      fact("previewSegmentA", .string(String(format: "00000000-0000-4000-9000-%012ld", revision))),
      fact("previewSegmentB", .string(String(format: "00000000-0000-4000-9000-%012ld", max(0, revision - 1)))),
    ])
  }
}

/// A runtime holding `shape`'s results, answered by a scripted server (#1426).
struct RefreshFixture: Sendable {
  var shape: RefreshShape
  var rows: Int
  var runtime: InstantRuntime
  var session: LiveReactorParitySession
  var queries: [InstantLiveJSONValue]
  var leases: [InstantQueryObservationLease]
  var clock: InstantLiveQueryResultWriteTests.TestClock
  var url: URL

  /// A runtime on `url` whose queries the server has answered with `rows` rows.
  static func open(
    _ shape: RefreshShape,
    rows: Int,
    url: URL,
    appID: String,
    startingAt milliseconds: Int64 = 1_791_150_000_000
  ) async throws -> Self {
    let fixture = try await start(shape, rows: rows, url: url, appID: appID, startingAt: milliseconds)
    try await fixture.answer(revision: 0)
    return fixture
  }

  /// A runtime on `url` with `shape`'s queries subscribed and sent, not yet answered.
  static func start(
    _ shape: RefreshShape,
    rows: Int,
    url: URL,
    appID: String,
    startingAt milliseconds: Int64 = 1_791_150_000_000
  ) async throws -> Self {
    let clock = InstantLiveQueryResultWriteTests.TestClock(milliseconds)
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: shape.serverAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: shape.attributes,
      now: { clock.now() },
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    // A refresh's result JSON is written by the refreshes themselves, not by a timer behind the measurement's back.
    configuration.liveQueryResultJSONFlushSleep = { _ in try await Task.sleep(for: .seconds(3_600)) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    var leases: [InstantQueryObservationLease] = []
    for plan in shape.plans { leases.append(await runtime.observeQueryLease(plan)) }
    _ = try await runtime.connect()
    try await InstantLiveQueryResultWriteTests.waitFor("every add-query") {
      await session.sentMessages().filter { $0.op == "add-query" }.count >= shape.plans.count
    }
    return RefreshFixture(
      shape: shape,
      rows: rows,
      runtime: runtime,
      session: session,
      queries: try shape.plans.map(InstantLiveQueryEncoder.encode),
      leases: leases,
      clock: clock,
      url: url
    )
  }

  /// The server's first answer to every query, `rows` rows with the last at `revision`, applied and shown.
  func answer(revision: Int) async throws {
    for query in queries {
      await session.enqueue(
        liveReactorAddQueryOK(
          query: query,
          processedTransactionID: "server-tx-answer-\(clock.now().milliseconds)",
          result: shape.result(rows: rows, changedRow: rows - 1, revision: revision)
        )
      )
    }
    for plan in shape.plans {
      try await InstantLiveQueryResultWriteTests.waitFor("the answer to \(plan.id)") {
        guard try await runtime.isAnsweredOnCurrentSocketForTesting(plan) else { return false }
        return await runtime.store.materialize(plan).count == rows
      }
    }
  }

  /// One `refresh-ok` restating every result, the last row at `revision`, `milliseconds` after the last, and waits
  /// until each result is saved.
  func refresh(revision: Int, after milliseconds: Int64 = 1_000) async throws {
    let savesBefore = await runtime.liveQueryResultJSONWriteStatsForTesting().saves
    clock.advance(by: milliseconds)
    let number = clock.now().milliseconds
    let result = shape.result(rows: rows, changedRow: rows - 1, revision: revision)
    await session.enqueue(
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: "refresh-\(number)",
        fields: [
          "attrs": .array([]),
          "computations": .array(
            queries.map { query -> InstantLiveJSONValue in
              .object([
                "instaql-query": query,
                "instaql-result": .array(result),
                "processed-tx-id": .string("server-tx-\(number)"),
              ])
            }
          ),
          "processed-tx-id": .string("server-tx-\(number)"),
        ]
      )
    )
    let expected = savesBefore + queries.count
    try await InstantLiveQueryResultWriteTests.waitFor("the refresh's results to be saved", timeout: .seconds(60)) {
      await runtime.liveQueryResultJSONWriteStatsForTesting().saves >= expected
    }
  }

  func close() async {
    for lease in leases { await lease.cancel() }
    _ = try? await runtime.closeConnection()
  }
}

/// What a run of server refreshes wrote, each restating `rows` rows of which one changed (#1426).
struct RefreshWrites {
  var rows: Int
  var refreshes: Int
  var io: StorageIOSnapshot
  var framesByBTree: [String: Int]
  var calls: [String: InstantStorageWriteSnapshot.Measure]
  /// Times a result's whole JSON was written meanwhile.
  var resultJSONWrites = 0

  /// What a refresh writes whatever its result holds: two log frames, the database header's page (its change counter
  /// and free-page list) and the sync metadata's page (the processed transaction, the revisions).
  static let fixedOverhead = 2 * (4_096 + 24)

  /// The log's frames and the temporary files' bytes, per refresh: what SQLite wrote for it before any checkpoint.
  var bytesPerRefresh: Int {
    let temporary = io[.temporary].bytesWritten + io[.temporaryJournal].bytesWritten + io[.transient].bytesWritten
    return (io[.wal].bytesWritten + temporary) / max(1, refreshes)
  }

  func print(_ step: String) {
    var line = StorageIOLine("refresh-writes", step)
    line.add("rows", rows)
    line.add("refreshes", refreshes)
    line.add("bytesPerRefresh", bytesPerRefresh)
    line.add("resultJSONWrites", resultJSONWrites)
    line.add(io: io, per: refreshes)
    line.print()
    for (name, frames) in framesByBTree.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
      var tree = StorageIOLine("refresh-writes-btrees", step)
      tree.add("btree", name)
      tree.add("framesPerRefresh", Double(frames) / Double(max(1, refreshes)), digits: 2)
      tree.print()
    }
    for (call, measure) in calls.sorted(by: { $0.key < $1.key }) where measure.transactions > 0 {
      var callLine = StorageIOLine("refresh-writes-calls", step)
      callLine.add("call", String(call.prefix(while: { $0 != "(" })))
      callLine.add("transactions", Double(measure.transactions) / Double(max(1, refreshes)), digits: 2)
      callLine.add("pages", Double(measure.pagesWritten) / Double(max(1, refreshes)), digits: 2)
      callLine.print()
    }
  }

  /// Answers `shape`'s results with `rows` rows, refreshes them twice to warm the statements and the page cache, and
  /// then counts `refreshes` refreshes `millisecondsApart`, each changing the last row.
  static func measure(
    _ shape: RefreshShape,
    rows: Int,
    label: String,
    refreshes: Int = 6,
    millisecondsApart: Int64 = 1_000
  ) async throws -> Self {
    StorageIOCounters.install(asDefault: false)
    let directory = try InstantTestScratch.directory(label)
    StorageIOCounters.watch(directory: directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let url = directory.appendingPathComponent("instant.sqlite")
    let fixture = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await RefreshFixture.open(shape, rows: rows, url: url, appID: label)
    }
    var revision = 0
    for _ in 0..<2 {
      revision += 1
      try await fixture.refresh(revision: revision)
    }
    try await Task.sleep(for: .milliseconds(200))

    let before = StorageIOCounters.snapshot()
    let callsBefore = InstantStorageWriteMeter.snapshot()
    let jsonBefore = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    for _ in 0..<refreshes {
      revision += 1
      try await fixture.refresh(revision: revision, after: millisecondsApart)
    }
    try await Task.sleep(for: .milliseconds(200))
    let io = StorageIOCounters.snapshot().subtracting(before)
    let calls = InstantStorageWriteMeter.snapshot().subtracting(callsBefore).operations
    let json = await fixture.runtime.liveQueryResultJSONWriteStatsForTesting()
    for plan in shape.plans {
      #expect(await fixture.runtime.store.materialize(plan).count == rows, "\(plan.id) after the refreshes")
    }
    await fixture.close()
    let map = try StorageIOPageMap.read(store: url)
    return RefreshWrites(
      rows: rows,
      refreshes: refreshes,
      io: io,
      framesByBTree: map.byName(io.walFramesByPage),
      calls: calls,
      resultJSONWrites: json.writes - jsonBefore.writes
    )
  }
}

extension StorageIOExercises {
  /// Where a live write's four steps put their log frames, by b-tree, when each write after a line's first is saved
  /// before the previous one's echo, as a phone saves its next interim while the server's answer to the last is on its
  /// way (#1426, #1119): what a recording's ~2,550 server applies an hour each write, beside the save, claim and
  /// acknowledgement. Prints `STORAGEIO echo-writes` lines; asserts nothing.
  @Test
  func aLiveWritesStepsByBTree() async throws {
    StorageIOCounters.install(asDefault: false)
    let run = try StorageIORun(label: "echo-btrees")
    defer { run.remove() }
    StorageIOCounters.watch(directory: run.directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let settings = StorageIOExerciseSettings(
      stepLines: 8, recordingLines: 300, pageLines: 16, minutes: 1, linesPerMinute: 15, fixtureScale: 1
    )
    var cycle = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      try await StorageIOWriteCycle.make(label: "echo-btrees", directory: run.directory, settings: settings)
    }
    try await cycle.writeLine(into: StorageIOLedger(), overlapping: true)
    let ledger = StorageIOLedger()
    for _ in 0..<settings.stepLines { try await cycle.writeLine(into: ledger, overlapping: true) }
    let map = try StorageIOPageMap.read(store: cycle.configuration.persistenceURL)
    let writes = max(1, ledger.count(.save))
    for step in [StorageIOStep.save, .claim, .ack, .echo] where ledger.count(step) > 0 {
      var line = StorageIOLine("echo-writes", step.rawValue)
      line.add("count", ledger.count(step))
      line.add(io: ledger.io(step), per: writes)
      line.print()
      let frames = map.byName(ledger.io(step).walFramesByPage)
      for (name, count) in frames.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
        var tree = StorageIOLine("echo-writes-btrees", step.rawValue)
        tree.add("btree", name)
        tree.add("framesPerWrite", Double(count) / Double(writes), digits: 2)
        tree.print()
      }
    }
    _ = try? await cycle.runtime.closeConnection()
  }
}
