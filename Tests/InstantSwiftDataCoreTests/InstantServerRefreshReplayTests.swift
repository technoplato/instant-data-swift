// History:
// - 2026-10-30: added (#1426): a recordings list refresh replayed on a copy of a phone's own store, by b-tree; the store
//   is copied as a file (a read-only open of a WAL store without its -shm fails), and an interval can be set.

import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

extension StorageIOExercises {
  /// #1426's list refresh on a copy of a phone's own store, named by `INSTANT_REFRESH_REPLAY_STORE` (never committed
  /// and never copied off the machine that holds it), through the server apply a live session runs. First a relaunch's
  /// answers: every stored result restated unchanged, one apply each, as each `add-query-ok` is applied. Then the
  /// recordings list results restated together, every fact stamped with the frame's transaction, with one recording's
  /// update time and speakers changed, `STORAGEIO_REPLAY_REFRESHES` (50) times 6 s apart. Prints counts only.
  @Test
  func aListRefreshOnACopyOfAPhonesStore() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let source = environment["INSTANT_REFRESH_REPLAY_STORE"], !source.isEmpty else { return }
    let refreshes = max(1, environment["STORAGEIO_REPLAY_REFRESHES"].flatMap(Int.init) ?? 50)
    // `STORAGEIO_REPLAY_INTERVAL_MS` writes a changed result's JSON once per interval, as before #1426 (300000).
    let interval = environment["STORAGEIO_REPLAY_INTERVAL_MS"].flatMap(Int64.init)
    StorageIOCounters.install(asDefault: false)
    let directory = try InstantTestScratch.directory("refresh-replay")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = directory.appendingPathComponent("store.sqlite")
    // A file copy, with its log: a read-only SQLite open of a WAL store whose -shm is gone cannot open it.
    for suffix in ["", "-wal"] where FileManager.default.fileExists(atPath: source + suffix) {
      try FileManager.default.copyItem(
        at: URL(fileURLWithPath: source + suffix),
        to: URL(fileURLWithPath: store.path + suffix)
      )
    }
    let lists = try ReplayedList.read(store)
    try #require(!lists.isEmpty, "the store holds no recordings list result")
    let changed = try #require(ReplayedList.newestRecording(in: lists), "no recording in the lists")
    StorageIOCounters.watch(directory: directory)
    defer { StorageIOCounters.watch(directory: nil) }
    let clock = InstantLiveQueryResultWriteTests.TestClock(
      (lists.map(\.updatedAt.milliseconds).max() ?? 1_790_000_000_000) + 60_000
    )
    let runtime = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(StorageIOCounters.vfsName) {
      var configuration = InstantRuntimeConfiguration(
        appID: "refresh-replay",
        persistenceURL: store,
        now: { clock.now() }
      )
      configuration.autoConnectLiveTransport = false
      // Scribe's policies (ScribeInstantBootstrap): the payloads that stay on disk, and the attributes reads look up.
      configuration.deferredValueResidency = InstantDeferredValueResidencyPolicy(attributeIDs: [
        "recordingRouteChunks/samplesJSON", "sharedRecordings/timeline", "transcriptionSegments/text",
        "transcriptionSegments/wordsJSON",
      ])
      configuration.localLookup = InstantLocalLookupPolicy(attributeIDs: [
        "recordingAttachments/recordingID", "recordings/id", "transcriptionSegments/recordingID",
        "transcriptionWords/recordingID", "transcriptions/recordingID",
      ])
      configuration.liveQueryResultJSONFlushSleep = { _ in try await Task.sleep(for: .seconds(36_000)) }
      if let interval { configuration.liveQueryResultJSONWriteIntervalMilliseconds = interval }
      configuration.liveQueryResultPruningWriteInterval = Int.max
      return try await InstantRuntime.bootstrap(configuration: configuration)
    }

    var summary = StorageIOLine("refresh-replay", "settings")
    summary.add("lists", lists.count)
    summary.add("listFacts", lists.map(\.triples.count).reduce(0, +))
    summary.add("refreshes", refreshes)
    summary.add("resultJSONIntervalMs", interval.map(String.init) ?? "none")
    summary.print()

    // A relaunch's first answers: each stored result restated as it is.
    let stored = try ReplayedList.read(store, keysLike: "%")
    let launchBefore = StorageIOCounters.snapshot()
    let launchJSONBefore = await runtime.liveQueryResultJSONWriteStatsForTesting()
    for (index, result) in stored.enumerated() {
      clock.advance(by: 100)
      let frame = ReplayedList.frame([result], changing: "", round: 0, transactionID: "refresh-replay-answer-\(index)")
      _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
        frame.transaction,
        attributesToMerge: [],
        liveQueryResultReplacements: frame.replacements,
        receivedAt: clock.now()
      )
    }
    let launch = StorageIOCounters.snapshot().subtracting(launchBefore)
    let launchJSON = await runtime.liveQueryResultJSONWriteStatsForTesting()
    var answers = StorageIOLine("refresh-replay", "relaunch-answers")
    answers.add("results", stored.count)
    answers.add("facts", stored.map(\.triples.count).reduce(0, +))
    answers.add("resultJSONWrites", launchJSON.writes - launchJSONBefore.writes)
    answers.add("resultJSONKB", Double(launchJSON.bytes - launchJSONBefore.bytes) / 1_024)
    answers.add(io: launch)
    answers.print()

    var measured = StorageIOSnapshot()
    var calls = InstantStorageWriteSnapshot()
    for round in 0..<(refreshes + 1) {
      clock.advance(by: 6_000)
      let frame = ReplayedList.frame(lists, changing: changed, round: round + 1)
      let before = StorageIOCounters.snapshot()
      let callsBefore = InstantStorageWriteMeter.snapshot()
      _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
        frame.transaction,
        attributesToMerge: [],
        liveQueryResultReplacements: frame.replacements,
        receivedAt: clock.now()
      )
      let io = StorageIOCounters.snapshot().subtracting(before)
      let call = InstantStorageWriteMeter.snapshot().subtracting(callsBefore)
      if round == 0 {
        // The first change after the answers warms the statements and the page cache; it is printed on its own.
        var first = StorageIOLine("refresh-replay", "first")
        first.add(io: io)
        first.print()
        continue
      }
      measured = measured.adding(io)
      calls = InstantStorageWriteSnapshot(operations: calls.operations.merging(call.operations) {
        InstantStorageWriteSnapshot.Measure(
          transactions: $0.transactions + $1.transactions,
          pagesWritten: $0.pagesWritten + $1.pagesWritten
        )
      })
    }
    _ = try? await runtime.closeConnection()
    let written = RefreshWrites(
      rows: lists.map(\.triples.count).reduce(0, +),
      refreshes: refreshes,
      io: measured,
      framesByBTree: try StorageIOPageMap.read(store: store).byName(measured.walFramesByPage),
      calls: calls.operations
    )
    written.print("replay")
  }
}

/// A recordings list result as a phone's store holds it (#1426).
struct ReplayedList {
  var key: String
  var triples: [InstantTriple]
  var pageInfo: InstantQueryPageInfo?
  var updatedAt: InstantTimestamp

  /// The store's recordings list results, or the results whose keys are like `pattern`, decoded from their stored JSON.
  static func read(
    _ store: URL,
    keysLike pattern: String = #"%"recordings"%deletedAtMs%"#
  ) throws -> [ReplayedList] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      defer { sqlite3_close_v2(connection) }
      throw StorageIOError("open \(store.lastPathComponent)")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    let sql = """
      SELECT json FROM instant_live_query_results
      WHERE query_key LIKE ? AND substr(query_key, 1, 16) <> 'released-result:'
      ORDER BY query_key
      """
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
      throw StorageIOError(String(cString: sqlite3_errmsg(connection)))
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, pattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    var lists: [ReplayedList] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let bytes = Data(bytes: sqlite3_column_blob(statement, 0), count: Int(sqlite3_column_bytes(statement, 0)))
      let result = try JSONDecoder().decode(InstantPersistedLiveQueryResult.self, from: bytes)
      lists.append(
        ReplayedList(key: result.key, triples: result.triples, pageInfo: result.pageInfo, updatedAt: result.updatedAt)
      )
    }
    return lists
  }

  /// The recording updated last, by `recordings/updatedAtMs`.
  static func newestRecording(in lists: [ReplayedList]) -> String? {
    func milliseconds(_ triple: InstantTriple) -> Double {
      if case let .number(value) = triple.value { return value }
      return 0
    }
    return lists.flatMap(\.triples)
      .filter { $0.attributeID == "recordings/updatedAtMs" }
      .max { milliseconds($0) < milliseconds($1) }?
      .entityID
  }

  /// One frame restating every list, each fact stamped with the frame's transaction as the translator stamps a
  /// refresh's facts, with `entityID`'s update time and speakers at `round`.
  static func frame(
    _ lists: [ReplayedList],
    changing entityID: String,
    round: Int,
    transactionID: String? = nil
  ) -> (transaction: InstantStoreTransaction, replacements: [InstantLiveQueryResultReplacement]) {
    let transactionID = transactionID ?? "refresh-replay-\(round)"
    func restated(_ triple: InstantTriple) -> InstantTriple {
      var triple = triple
      triple.txID = transactionID
      guard triple.entityID == entityID else { return triple }
      switch (triple.attributeID, triple.value) {
      case let ("recordings/updatedAtMs", .number(milliseconds)):
        triple.value = .number(milliseconds + Double(round) * 6_000)
      case let ("recordings/speakers", .string(json)):
        triple.value = .string(json + String(round % 10))
      default:
        break
      }
      return triple
    }
    let replacements = lists.map {
      InstantLiveQueryResultReplacement(key: $0.key, triples: $0.triples.map(restated), pageInfo: $0.pageInfo)
    }
    var seen: Set<InstantLiveTripleIdentity> = []
    var operations: [InstantTripleOperation] = []
    for replacement in replacements {
      for triple in replacement.triples where seen.insert(InstantLiveTripleIdentity(triple)).inserted {
        operations.append(.insert(triple))
      }
    }
    return (InstantStoreTransaction(id: transactionID, operations: operations), replacements)
  }
}
