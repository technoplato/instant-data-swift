// History:
// - 2026-10-24: the storage audit's exercises (#1076): what one live write costs the disk at each of its steps (save,
//   claim, acknowledgement, the server's echo, the prune) and on the wire, and what an hour of recording does to the
//   store file, on a store holding as many transcript lines as the phone's; and the same writes delivered by the live
//   session on #1072's phone-shaped store.
// - 2026-10-24: each step's reads of the database file by b-tree (#1076): the phone-shaped store read about 416 MB a
//   write, and which table those pages belong to points at the statement. The time spent in syncs, and the bytes the
//   process's I/O wrote to the drive beside the logical bytes. And a replay of a live write's four transactions under
//   each checkpoint setting, because the store's own connection has no way to set them from a test.
// - 2026-10-24: the hour prints the store's own checkpoint setting, its checkpoints, and the most lines written between
//   two of them, which is what a power loss can take (#1118).

import Compression
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// The storage audit's exercises (#1076), measured the way SQLite's author would: bytes written, write calls and syncs
/// per kind of file, the write-ahead log's frames and the b-trees they belong to, the pages a checkpoint copies, the
/// store file's size and free pages, and the bytes each change puts on the wire.
///
/// A recording's writes are Scribe's, at the sizes the phone's store holds them (``StorageIOLineScript``: three interims
/// on the line's live row, the final line, the recording's summary and its duration tick; every write re-inserts the
/// whole row). `FastDrainServer` answers each with an acknowledgement and a `refresh-ok` carrying the full results of
/// the queries the write touched, on a clock the exercise moves at the recording's pace. Each exercise prints
/// `STORAGEIO <exercise> <step> key=value` lines in a fixed order, so a run before a fix and a run after it diff line
/// by line.
///
/// The exercises run only with `STORAGEIO_EXERCISES=1`; the counters' own check always runs.
///
///     STORAGEIO_EXERCISES=1 swift test --filter StorageIOExercises
@Suite(.serialized)
struct StorageIOExercises {
  /// The shim sees what SQLite writes: frames into the write-ahead log, pages a checkpoint copies, the syncs, and the
  /// b-tree each page belongs to.
  @Test
  func theCountersSeeWhatSQLiteWrites() throws {
    StorageIOCounters.install(asDefault: false)
    let run = try StorageIORun(label: "counters")
    defer { run.remove() }
    let url = run.directory.appendingPathComponent("counted.sqlite")
    var connection: OpaquePointer?
    try #require(
      sqlite3_open_v2(
        url.path,
        &connection,
        SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
        StorageIOCounters.vfsName
      ) == SQLITE_OK
    )
    defer { sqlite3_close_v2(connection) }
    try storageIOExecute(connection, "PRAGMA journal_mode = WAL")
    try storageIOExecute(connection, "PRAGMA wal_autocheckpoint = 0")
    try storageIOExecute(connection, "CREATE TABLE counted (id INTEGER PRIMARY KEY, body TEXT NOT NULL)")
    let before = StorageIOCounters.snapshot()
    for _ in 0..<10 {
      try storageIOExecute(connection, "BEGIN")
      for _ in 0..<100 {
        try storageIOExecute(connection, "INSERT INTO counted (body) VALUES (hex(randomblob(100)))")
      }
      try storageIOExecute(connection, "COMMIT")
    }
    let written = StorageIOCounters.snapshot().subtracting(before)
    #expect(written[.wal].bytesWritten > 0)
    #expect(written.walFrames >= 10, "ten commits each append at least one frame")
    #expect(
      written.walFrames * (written.pageSize + 24) <= written[.wal].bytesWritten,
      "every frame counted is a whole page and its header written"
    )
    #expect(written.databasePagesWritten == 0, "nothing is checkpointed yet")

    try storageIOExecute(connection, "PRAGMA wal_checkpoint(TRUNCATE)")
    let checkpointed = StorageIOCounters.snapshot().subtracting(before)
    #expect(checkpointed.databasePagesWritten > 0)
    #expect(checkpointed.databasePagesWritten <= written.walFramesByPage.count, "a checkpoint copies each page once")
    #expect(checkpointed[.database].syncs > 0, "a checkpoint syncs the database file")
    #expect(checkpointed[.wal].truncates > 0)

    let map = try StorageIOPageMap.read(store: url)
    #expect((map.byName(written.walFramesByPage)["counted"] ?? 0) > 0)

    // A second connection starts with an empty page cache, so it reads the checkpointed table from the file.
    var reader: OpaquePointer?
    try #require(sqlite3_open_v2(url.path, &reader, SQLITE_OPEN_READONLY, StorageIOCounters.vfsName) == SQLITE_OK)
    defer { sqlite3_close_v2(reader) }
    let beforeRead = StorageIOCounters.snapshot()
    #expect(try storageIOInteger(reader, "SELECT sum(length(body)) FROM counted") == 200_000)
    let read = StorageIOCounters.snapshot().subtracting(beforeRead)
    #expect((map.byName(read.databaseReadsByPage)["counted"] ?? 0) >= (map.pagesByName["counted"]?.pages ?? 0))
    #expect(read[.database].bytesRead >= read.databasePagesRead * read.pageSize)

    // Watching the run's directory still counts the files a connection opens afterwards: SQLite names them by their
    // resolved path, and the temporary directory is a symbolic link.
    StorageIOCounters.watch(directory: run.directory)
    defer { StorageIOCounters.watch(directory: nil) }
    var watched: OpaquePointer?
    try #require(sqlite3_open_v2(url.path, &watched, SQLITE_OPEN_READWRITE, StorageIOCounters.vfsName) == SQLITE_OK)
    defer { sqlite3_close_v2(watched) }
    let beforeWatched = StorageIOCounters.snapshot()
    try storageIOExecute(watched, "INSERT INTO counted (body) VALUES ('watched')")
    #expect(StorageIOCounters.snapshot().subtracting(beforeWatched)[.wal].writes > 0)
  }

  /// One live write's steps, each measured on its own: the local save, the claim that hands it to delivery, the
  /// server's acknowledgement, the server's echo (`refresh-ok`), and the minute's prune; and the bytes each change puts
  /// on the wire.
  ///
  /// `STORAGEIO_STEP_LINES` lines are measured (6 writes each, 50 by default: 300 writes, as #1007's write harness
  /// replayed), on a store that already holds `STORAGEIO_RECORDING_LINES` lines (7,000; the phone's held 7,139), the
  /// transcript query holding the newest `STORAGEIO_PAGE_LINES` (256).
  @Test
  func eachStepOfALiveWrite() async throws {
    guard let settings = StorageIOExerciseSettings.current else { return }
    StorageIOCounters.install(asDefault: true)
    let run = try StorageIORun(label: "steps")
    defer { run.remove() }
    var cycle = try await StorageIOWriteCycle.make(label: "steps", directory: run.directory, settings: settings)
    // A recording that is already running: its statements prepared, its pages cached.
    let warmup = StorageIOLedger()
    for _ in 0..<2 { try await cycle.writeLine(into: warmup) }

    let ledger = StorageIOLedger()
    let started = StorageIOProbe.start()
    for line in 1...settings.stepLines {
      try await cycle.writeLine(into: ledger)
      if line % settings.linesPerMinute == 0 { try await cycle.prune(into: ledger) }
    }
    let total = started.stop()
    let writes = ledger.count(.save)
    let store = cycle.configuration.persistenceURL

    var summary = StorageIOLine("steps", "settings")
    summary.add("writes", writes)
    summary.add("lines", settings.stepLines)
    summary.add("recordingLines", settings.recordingLines)
    summary.add("pageLines", settings.pageLines)
    summary.add("storeFacts", try StorageIOStoreFile.factCount(store))
    summary.add("seedSeconds", cycle.seedSeconds, digits: 0)
    summary.print()
    for step in StorageIOStep.allCases where ledger.count(step) > 0 {
      var line = StorageIOLine("steps", step.rawValue)
      line.add("count", ledger.count(step))
      line.add(io: ledger.io(step), per: writes)
      line.add("logicalKB", Double(ledger.logicalBytes(step)) / 1_024 / Double(max(1, writes)), digits: 2)
      line.add("cpuMs", Double(ledger.cpuNanoseconds(step)) / 1_000_000 / Double(max(1, writes)), digits: 2)
      line.print()
      for (call, measure) in ledger.calls(step).sorted(by: { $0.key < $1.key }) {
        var callLine = StorageIOLine("steps-calls", step.rawValue)
        callLine.add("call", String(call.prefix(while: { $0 != "(" })))
        callLine.add("transactions", Double(measure.transactions) / Double(max(1, writes)), digits: 2)
        callLine.add("pages", Double(measure.pagesWritten) / Double(max(1, writes)), digits: 2)
        callLine.print()
      }
    }
    var perWrite = StorageIOLine("steps", "all")
    perWrite.add("count", writes)
    perWrite.add(io: total.io, per: writes)
    perWrite.add("logicalKB", Double(ledger.logicalBytes(.save)) / 1_024 / Double(max(1, writes)), digits: 2)
    perWrite.add("amplification", Double(total.io.bytesWritten) / Double(max(1, ledger.logicalBytes(.save))))
    perWrite.add("processLogicalWriteKB", Double(total.process.logicalWriteBytes) / 1_024 / Double(max(1, writes)))
    perWrite.add("processDiskWriteKB", Double(total.process.diskWriteBytes) / 1_024 / Double(max(1, writes)))
    perWrite.add("cpuMs", Double(total.process.cpuNanoseconds) / 1_000_000 / Double(max(1, writes)), digits: 2)
    perWrite.print()
    var wire = StorageIOLine("steps", "wire")
    wire.add(wire: ledger.wire, per: writes)
    wire.print()

    // Which b-trees the log's frames belong to, per write, by each page's owner when the run ends.
    let map = try StorageIOPageMap.read(store: store)
    for step in StorageIOStep.allCases where ledger.count(step) > 0 {
      let frames = map.byName(ledger.io(step).walFramesByPage)
      for (name, count) in frames.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(12) {
        var line = StorageIOLine("steps-btrees", step.rawValue)
        line.add("btree", name)
        line.add("framesPerWrite", Double(count) / Double(max(1, writes)), digits: 2)
        line.print()
      }
      StorageIOLine.printReads("steps-reads", step.rawValue, ledger.io(step), map: map, per: writes)
      StorageIOLine.printOutboxShare("steps-outbox", step.rawValue, frames, per: writes)
    }
    StorageIOLine.printOutboxShare("steps-outbox", "all", map.byName(total.io.walFramesByPage), per: writes)
    let file = try StorageIOStoreFile.read(store)
    var fileLine = StorageIOLine("steps", "file")
    fileLine.add(file: file)
    fileLine.print()
    let largest = map.pagesByName.sorted { ($0.value.pages, $1.key) > ($1.value.pages, $0.key) }.prefix(12)
    for (name, measure) in largest {
      var line = StorageIOLine("steps-store", "btree")
      line.add("btree", name)
      line.add("pages", measure.pages)
      line.add("unusedPct", Double(measure.unusedBytes) * 100 / Double(max(1, measure.pages * file.pageSize)))
      line.print()
    }
    _ = try? await cycle.runtime.closeConnection()
  }

  /// An hour of recording (`STORAGEIO_MINUTES`, 60) on the same real-size store: `STORAGEIO_LINES_PER_MINUTE` lines a
  /// minute (15, so 90 writes), each write acknowledged and echoed, and the prune once a minute. Every five minutes:
  /// the store file's size, its free pages, what was written to it, and what went over the wire.
  @Test
  func theStoreOverASimulatedHour() async throws {
    guard let settings = StorageIOExerciseSettings.current else { return }
    StorageIOCounters.install(asDefault: true)
    let run = try StorageIORun(label: "hour")
    defer { run.remove() }
    var cycle = try await StorageIOWriteCycle.make(label: "hour", directory: run.directory, settings: settings)
    let store = cycle.configuration.persistenceURL
    let startFile = try StorageIOStoreFile.read(store)
    var startLine = StorageIOLine("hour", "start")
    startLine.add("minute", 0)
    startLine.add("storeFacts", try StorageIOStoreFile.factCount(store))
    startLine.add(file: startFile)
    startLine.add("walAutocheckpoint", Int(try await cycle.runtime.persistence.walAutocheckpointForTesting()))
    startLine.print()

    let ledger = StorageIOLedger()
    let hour = StorageIOProbe.start()
    var interval = StorageIOProbe.start()
    var intervalLedger = StorageIOLedger()
    // A checkpoint ends with the database file's full sync, after the log's: a power loss takes the lines written
    // since the last one (#1118).
    var checkpoints = StorageIOCounters.snapshot()[.database].fullSyncs
    var linesSinceCheckpoint = 0
    var powerLossReachLines = 0
    for minute in 1...settings.minutes {
      for _ in 0..<settings.linesPerMinute {
        try await cycle.writeLine(into: ledger, alsoInto: intervalLedger)
        linesSinceCheckpoint += 1
        let synced = StorageIOCounters.snapshot()[.database].fullSyncs
        if synced > checkpoints {
          powerLossReachLines = max(powerLossReachLines, linesSinceCheckpoint)
          linesSinceCheckpoint = 0
          checkpoints = synced
        }
      }
      try await cycle.prune(into: ledger)
      guard minute % 5 == 0 || minute == settings.minutes else { continue }
      let measured = interval.stop()
      let intervalWrites = intervalLedger.count(.save)
      let file = try StorageIOStoreFile.read(store)
      var line = StorageIOLine("hour", "minute")
      line.add("minute", minute)
      line.add("writes", ledger.count(.save))
      line.add(file: file)
      line.add("intervalWrites", intervalWrites)
      line.add(io: measured.io, per: intervalWrites)
      line.add(
        "processLogicalWriteKB",
        Double(measured.process.logicalWriteBytes) / 1_024 / Double(max(1, intervalWrites))
      )
      line.add("processDiskWriteKB", Double(measured.process.diskWriteBytes) / 1_024 / Double(max(1, intervalWrites)))
      line.add(wire: intervalLedger.wire, per: intervalWrites)
      line.print()
      interval = StorageIOProbe.start()
      intervalLedger = StorageIOLedger()
    }
    let total = hour.stop()
    let endFile = try StorageIOStoreFile.read(store)
    let writes = ledger.count(.save)
    var end = StorageIOLine("hour", "total")
    end.add("minutes", settings.minutes)
    end.add("writes", writes)
    end.add("logicalMB", Double(ledger.logicalBytes(.save)) / 1_048_576, digits: 2)
    end.add("sqliteWrittenMB", Double(total.io.bytesWritten) / 1_048_576)
    end.add("walWrittenMB", Double(total.io[.wal].bytesWritten) / 1_048_576)
    end.add("dbWrittenMB", Double(total.io[.database].bytesWritten) / 1_048_576)
    end.add("tempWrittenMB", Double(total.io[.temporary].bytesWritten) / 1_048_576)
    end.add("processLogicalWriteMB", Double(total.process.logicalWriteBytes) / 1_048_576)
    end.add("processDiskWriteMB", Double(total.process.diskWriteBytes) / 1_048_576)
    end.add("amplification", Double(total.io.bytesWritten) / Double(max(1, ledger.logicalBytes(.save))))
    end.add("syncs", total.io.syncs)
    end.add("fullSyncs", total.io.fullSyncs)
    end.add("syncSeconds", Double(total.io.syncNanoseconds) / 1_000_000_000, digits: 2)
    end.add("walRestarts", total.io.walRestarts)
    end.add("checkpoints", total.io[.database].fullSyncs)
    end.add("powerLossReachLines", max(powerLossReachLines, linesSinceCheckpoint))
    end.add(
      "powerLossReachSeconds",
      Double(max(powerLossReachLines, linesSinceCheckpoint)) * 60 / Double(max(1, settings.linesPerMinute)),
      digits: 0
    )
    end.add("fileGrowthMB", Double(endFile.databaseBytes - startFile.databaseBytes) / 1_048_576, digits: 2)
    end.add("pagesEnd", endFile.pageCount)
    end.add("freePagesEnd", endFile.freePages)
    end.add("sentMB", Double(ledger.wire.sentBytes) / 1_048_576, digits: 2)
    end.add("receivedMB", Double(ledger.wire.receivedBytes) / 1_048_576, digits: 2)
    end.add("storeFacts", try StorageIOStoreFile.factCount(store))
    end.add("cpuSeconds", Double(total.process.cpuNanoseconds) / 1_000_000_000)
    end.print()
    _ = try? await cycle.runtime.closeConnection()
  }

  /// Scribe's live writes delivered by the live session itself, on #1072's phone-shaped store (`RealSizeFixture`: the
  /// phone's 7,140 lines, 9,455 files, 4,264 upload records, 663 refused writes, 48 open and 355 closed queries; the
  /// phone's own store copy with `INSTANT_REAL_SIZE_STORE`): per write, what SQLite wrote and synced, the pages each
  /// store call wrote, and every frame on the wire both ways, as the scripted server counts them.
  ///
  /// A line is four revisions of its sixteen facts (three interims and the final, as the fixture's `segmentWrite`
  /// writes them) and the recording's duration tick; the server acknowledges each write and then sends the transcript
  /// page's whole result again (`refresh-ok`), as Instant does. `STORAGEIO_FIXTURE_SCALE` (1) scales the store.
  @Test
  func liveWritesOnThePhoneShapedStore() async throws {
    guard let settings = StorageIOExerciseSettings.current else { return }
    StorageIOCounters.install(asDefault: true)
    let run = try StorageIORun(label: "phone-shaped")
    defer { run.remove() }
    let frames = StorageIOFrameLog()
    let shape = settings.fixtureScale == 1 ? RealSizeShape.phone : RealSizeShape.phone.scaled(settings.fixtureScale)
    let openStarted = ContinuousClock.now
    let session = try await RealSizeFixture.open(shape, in: run.directory, onFrame: { frames.record($0) })
    let openSeconds = Double((ContinuousClock.now - openStarted).components.seconds)
    try await session.closing {
      let runtime = session.runtime
      let store = session.configuration.persistenceURL
      let recording = session.newRecording(90_001)
      _ = try await runtime.transact(recording.write, createdAt: session.clock.now())
      let addQueries = await session.server.addQueries
      let lease = await runtime.observeQueryLease(session.transcriptPage(recordingID: recording.id))
      let query = try await session.server.nextAddQuery(after: addQueries)
      if let answer = await session.server.answerTransaction(for: query) {
        _ = try await session.applies.wait(for: answer)
      }
      try await RealSizeGenerator.waitForSettledOutbox(runtime)
      var page = StorageIOTranscriptPage(recordingID: recording.id)

      // One line to warm the statements and the page cache, then the measured lines.
      try await page.write(line: 0, session: session, query: query, into: StorageIOLedger())
      frames.reset()
      let ledger = StorageIOLedger()
      let started = StorageIOProbe.start()
      let startFile = try StorageIOStoreFile.read(store)
      for line in 1...settings.stepLines {
        try await page.write(line: line, session: session, query: query, into: ledger)
        if line % settings.linesPerMinute == 0 {
          let prune = StorageIOProbe.start()
          _ = try await runtime.pruneLiveQueryResults(
            policy: session.configuration.liveQueryResultPruningPolicy,
            now: session.clock.now()
          )
          let pruned = prune.stop()
          ledger.record(.prune, pruned)
          // Each prune on its own: a backlog cleared once reads differently from a cost paid every minute.
          var pruneLine = StorageIOLine("phone-shaped-prune", "line\(line)")
          pruneLine.add("walFrames", pruned.io.walFrames)
          pruneLine.add("walWriteKB", Double(pruned.io[.wal].bytesWritten) / 1_024)
          pruneLine.add("dbReadKB", Double(pruned.io[.database].bytesRead) / 1_024)
          pruneLine.add("cpuMs", Double(pruned.process.cpuNanoseconds) / 1_000_000, digits: 2)
          let calls = pruned.calls.operations.sorted(by: { $0.key < $1.key })
          for (call, measure) in calls where measure.transactions > 0 {
            pruneLine.add(String(call.prefix(while: { $0 != "(" })), measure.pagesWritten)
          }
          pruneLine.print()
        }
      }
      let total = started.stop()
      let writes = settings.stepLines * StorageIOTranscriptPage.writesPerLine

      var summary = StorageIOLine("phone-shaped", "settings")
      summary.add("writes", writes)
      summary.add("lines", settings.stepLines)
      summary.add(
        "shape",
        shape.description.replacingOccurrences(of: " ", with: ",").replacingOccurrences(of: "=", with: ":")
      )
      summary.add("storeFacts", try StorageIOStoreFile.factCount(store))
      summary.add("openSeconds", openSeconds, digits: 0)
      summary.print()
      for step in StorageIOStep.allCases where ledger.count(step) > 0 {
        var line = StorageIOLine("phone-shaped", step.rawValue)
        line.add("count", ledger.count(step))
        line.add(io: ledger.io(step), per: writes)
        line.add("logicalKB", Double(ledger.logicalBytes(step)) / 1_024 / Double(writes), digits: 2)
        line.add("cpuMs", Double(ledger.cpuNanoseconds(step)) / 1_000_000 / Double(writes), digits: 2)
        line.print()
      }
      var all = StorageIOLine("phone-shaped", "all")
      all.add("count", writes)
      all.add(io: total.io, per: writes)
      all.add("processLogicalWriteKB", Double(total.process.logicalWriteBytes) / 1_024 / Double(writes))
      all.add("processDiskWriteKB", Double(total.process.diskWriteBytes) / 1_024 / Double(writes))
      all.add("cpuMs", Double(total.process.cpuNanoseconds) / 1_000_000 / Double(writes), digits: 2)
      all.print()
      for (call, measure) in total.calls.operations.sorted(by: { $0.key < $1.key }) where measure.transactions > 0 {
        var line = StorageIOLine("phone-shaped-calls", "all")
        line.add("call", String(call.prefix(while: { $0 != "(" })))
        line.add("transactions", Double(measure.transactions) / Double(writes), digits: 2)
        line.add("pages", Double(measure.pagesWritten) / Double(writes), digits: 2)
        line.print()
      }
      for (key, measure) in frames.snapshot().sorted(by: { $0.key < $1.key }) {
        var line = StorageIOLine("phone-shaped-wire", key)
        line.add("framesPerWrite", Double(measure.frames) / Double(writes), digits: 2)
        line.add("KBPerWrite", Double(measure.bytes) / 1_024 / Double(writes), digits: 2)
        line.add("largestKB", Double(measure.largest) / 1_024, digits: 1)
        line.print()
      }
      let map = try StorageIOPageMap.read(store: store)
      let byTree = map.byName(total.io.walFramesByPage)
      for (name, count) in byTree.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(12) {
        var line = StorageIOLine("phone-shaped-btrees", "all")
        line.add("btree", name)
        line.add("framesPerWrite", Double(count) / Double(writes), digits: 2)
        line.print()
      }
      for step in StorageIOStep.allCases where ledger.count(step) > 0 {
        StorageIOLine.printReads("phone-shaped-reads", step.rawValue, ledger.io(step), map: map, per: writes)
        StorageIOLine.printOutboxShare(
          "phone-shaped-outbox", step.rawValue, map.byName(ledger.io(step).walFramesByPage), per: writes
        )
      }
      StorageIOLine.printOutboxShare("phone-shaped-outbox", "all", byTree, per: writes)
      let endFile = try StorageIOStoreFile.read(store)
      var fileLine = StorageIOLine("phone-shaped", "file")
      fileLine.add(file: endFile)
      fileLine.add("growthPages", endFile.pageCount - startFile.pageCount)
      fileLine.add("freePagesStart", startFile.freePages)
      fileLine.print()
      await lease.cancel()
    }
  }
}

// MARK: - Checkpoint settings

extension StorageIOExercises {
  /// The store never sets `wal_autocheckpoint` or `journal_size_limit`, so Apple's defaults decide how often a commit
  /// checkpoints (1,000 frames) and that the log is cut back to 32 KB after each restart; and Apple's SQLite syncs
  /// every checkpoint with `F_FULLFSYNC`. The store's own connection offers no way to set them from a test, so this
  /// replays a live write's four transactions (save, claim, acknowledgement, echo) on a scratch store shaped like the
  /// store's hot tables, under each setting, and counts what reaches the files (#1076).
  ///
  /// `STORAGEIO_SETTINGS_WRITES` logical writes per setting (2,000).
  @Test
  func checkpointSettingsOnALiveWritePattern() throws {
    guard StorageIOExerciseSettings.current != nil else { return }
    StorageIOCounters.install(asDefault: false)
    let writes = max(100, ProcessInfo.processInfo.environment["STORAGEIO_SETTINGS_WRITES"].flatMap(Int.init) ?? 2_000)
    let candidates: [(name: String, pragmas: [String])] = [
      ("apple-defaults", []),
      ("no-truncate", ["PRAGMA journal_size_limit = -1"]),
      ("autocheckpoint-4000", ["PRAGMA wal_autocheckpoint = 4000", "PRAGMA journal_size_limit = -1"]),
      ("autocheckpoint-16000", ["PRAGMA wal_autocheckpoint = 16000", "PRAGMA journal_size_limit = -1"]),
    ]
    for candidate in candidates {
      let run = try StorageIORun(label: "settings-\(candidate.name)")
      defer { run.remove() }
      StorageIOCounters.watch(directory: run.directory)
      defer { StorageIOCounters.watch(directory: nil) }
      let url = run.directory.appendingPathComponent("replay.sqlite")
      var connection: OpaquePointer?
      try #require(
        sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, StorageIOCounters.vfsName)
          == SQLITE_OK
      )
      defer { sqlite3_close_v2(connection) }
      try storageIOExecute(connection, "PRAGMA journal_mode = WAL")
      try storageIOExecute(connection, "PRAGMA cache_size = -2048")
      for pragma in candidate.pragmas { try storageIOExecute(connection, pragma) }
      try StorageIOReplay.createSchema(connection)
      try StorageIOReplay.seed(connection, facts: 120_000)
      try storageIOExecute(connection, "PRAGMA wal_checkpoint(TRUNCATE)")

      let started = StorageIOProbe.start()
      for write in 0..<writes { try StorageIOReplay.logicalWrite(write, on: connection) }
      let measured = started.stop()
      var line = StorageIOLine("settings", candidate.name)
      line.add("writes", writes)
      line.add(io: measured.io, per: writes)
      line.add("processDiskWriteKB", Double(measured.process.diskWriteBytes) / 1_024 / Double(writes))
      line.add("fullSyncsPerHour", Double(measured.io.fullSyncs) / Double(writes) * 5_400, digits: 0)
      line.add("syncSecondsPerHour", Double(measured.io.syncNanoseconds) / 1e9 / Double(writes) * 5_400, digits: 2)
      line.add("writtenMBPerHour", Double(measured.io.bytesWritten) / 1_048_576 / Double(writes) * 5_400, digits: 0)
      line.print()
    }
  }
}

/// A live write's four transactions on tables shaped like the store's hot ones: a fact table with a text primary key
/// and its row copy, an outbox row with a 2 KB body and nine indexes, a metadata row, and a query result rewritten
/// whole. Its frames per write land near the library's own (#1076's first baseline: 62.5).
enum StorageIOReplay {
  static func createSchema(_ connection: OpaquePointer?) throws {
    try storageIOExecute(
      connection,
      """
      CREATE TABLE facts (entity_id TEXT NOT NULL, attribute_id TEXT NOT NULL, value_json TEXT NOT NULL,
        tx_id TEXT NOT NULL, tx_time_ms INTEGER NOT NULL, json TEXT NOT NULL,
        PRIMARY KEY (entity_id, attribute_id, value_json))
      """
    )
    try storageIOExecute(
      connection,
      """
      CREATE TABLE box (mutation_id TEXT PRIMARY KEY NOT NULL, status TEXT NOT NULL, created_at_ms INTEGER NOT NULL,
        json TEXT NOT NULL, claim_state TEXT NOT NULL DEFAULT 'ready', claim_token TEXT, deadline_ms INTEGER,
        version INTEGER NOT NULL DEFAULT 0, overlay INTEGER NOT NULL DEFAULT 1, fingerprint TEXT, server_tx TEXT)
      """
    )
    for (index, columns) in [
      "claim_state, deadline_ms, created_at_ms", "status, version, created_at_ms", "overlay, version, created_at_ms",
      "overlay, fingerprint, created_at_ms", "status, server_tx, overlay, created_at_ms",
      "status, overlay, created_at_ms",
      "created_at_ms, version", "claim_state, created_at_ms", "fingerprint, created_at_ms",
    ].enumerated() {
      try storageIOExecute(connection, "CREATE INDEX box_\(index) ON box (\(columns), mutation_id)")
    }
    try storageIOExecute(connection, "CREATE TABLE meta (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
    try storageIOExecute(connection, "INSERT INTO meta VALUES ('cursor', '0')")
    try storageIOExecute(connection, "CREATE TABLE results (query_id INTEGER PRIMARY KEY, json TEXT NOT NULL)")
    try storageIOExecute(connection, "INSERT INTO results VALUES (1, hex(randomblob(4000)))")
  }

  static func seed(_ connection: OpaquePointer?, facts: Int) throws {
    try storageIOExecute(connection, "BEGIN")
    try storageIOExecute(
      connection,
      """
      WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < \(facts))
      INSERT INTO facts SELECT printf('entity-%08d', i / 16), printf('attribute-%02d', i % 16), hex(randomblob(12)),
        'seed', i, hex(randomblob(60)) FROM n
      """
    )
    try storageIOExecute(connection, "COMMIT")
  }

  /// Save (16 facts re-inserted, the outbox row, the cursor), claim, acknowledgement, echo (the row deleted, the
  /// result rewritten): four transactions, as the library commits them.
  static func logicalWrite(_ write: Int, on connection: OpaquePointer?) throws {
    let entity = String(format: "live-%08d", write / 6)
    let mutation = String(format: "mutation-%08d", write)
    try storageIOExecute(connection, "BEGIN IMMEDIATE")
    try storageIOExecute(
      connection,
      """
      WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n WHERE i + 1 < 16)
      INSERT OR REPLACE INTO facts SELECT '\(entity)', printf('attribute-%02d', i), printf('"value-%d"', i),
        '\(mutation)', \(write), hex(randomblob(60)) FROM n
      """
    )
    try storageIOExecute(
      connection,
      """
      INSERT INTO box (mutation_id, status, created_at_ms, json, fingerprint)
      VALUES ('\(mutation)', 'pending', \(write), hex(randomblob(1024)), hex(randomblob(16)))
      """
    )
    try storageIOExecute(connection, "UPDATE meta SET value = '\(write)' WHERE key = 'cursor'")
    try storageIOExecute(connection, "COMMIT")
    try storageIOExecute(
      connection,
      """
      UPDATE box SET claim_state = 'claimed', claim_token = 'token-\(write)', deadline_ms = \(write + 5_000)
      WHERE mutation_id = '\(mutation)'
      """
    )
    try storageIOExecute(connection, "BEGIN IMMEDIATE")
    try storageIOExecute(
      connection,
      """
      UPDATE box SET status = 'confirmed', server_tx = '\(write)', version = version + 1
      WHERE mutation_id = '\(mutation)'
      """
    )
    try storageIOExecute(connection, "UPDATE meta SET value = '\(write)-acked' WHERE key = 'cursor'")
    try storageIOExecute(connection, "COMMIT")
    try storageIOExecute(connection, "BEGIN IMMEDIATE")
    try storageIOExecute(connection, "DELETE FROM box WHERE mutation_id = '\(mutation)'")
    try storageIOExecute(connection, "UPDATE results SET json = hex(randomblob(4000)) WHERE query_id = 1")
    try storageIOExecute(connection, "COMMIT")
  }
}

// MARK: - Settings

/// What the exercises run, from the environment; `nil` unless `STORAGEIO_EXERCISES=1`.
struct StorageIOExerciseSettings {
  var stepLines: Int
  var recordingLines: Int
  var pageLines: Int
  var minutes: Int
  var linesPerMinute: Int
  var fixtureScale: Double

  static var current: Self? {
    let environment = ProcessInfo.processInfo.environment
    guard environment["STORAGEIO_EXERCISES"] == "1" else { return nil }
    func setting(_ key: String, _ fallback: Int) -> Int { environment[key].flatMap(Int.init) ?? fallback }
    return Self(
      stepLines: max(1, setting("STORAGEIO_STEP_LINES", 50)),
      recordingLines: max(0, setting("STORAGEIO_RECORDING_LINES", 7_000)),
      pageLines: max(1, setting("STORAGEIO_PAGE_LINES", 256)),
      minutes: max(1, setting("STORAGEIO_MINUTES", 60)),
      linesPerMinute: max(1, setting("STORAGEIO_LINES_PER_MINUTE", 15)),
      fixtureScale: environment["STORAGEIO_FIXTURE_SCALE"].flatMap(Double.init) ?? 1
    )
  }
}

/// A directory of the exercise's own under the temporary directory, removed afterwards.
struct StorageIORun {
  var directory: URL

  init(label: String) throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("storage-io-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

// MARK: - Scribe's writes at the phone's sizes

/// Scribe's schema for what a recording writes: `FastDrainSchema`'s recordings, transcriptions and live lines with
/// Scribe's own link shape, and the six line facts the phone's store holds that the fast-drain fixture leaves out.
enum StorageIOSchema {
  static let lineAttributes: [InstantAttribute] = [
    InstantAttribute(
      id: "transcriptionSegments/transcriptionID", namespace: "transcriptionSegments", name: "transcriptionID",
      valueType: .string, isRequired: false
    ),
    InstantAttribute(
      id: "transcriptionSegments/wallClockStartedAtMs", namespace: "transcriptionSegments",
      name: "wallClockStartedAtMs", valueType: .number, isRequired: false
    ),
    InstantAttribute(
      id: "transcriptionSegments/wallClockEndedAtMs", namespace: "transcriptionSegments", name: "wallClockEndedAtMs",
      valueType: .number, isRequired: false
    ),
    InstantAttribute(
      id: "transcriptionSegments/sentToInstantAtMs", namespace: "transcriptionSegments", name: "sentToInstantAtMs",
      valueType: .number, isRequired: false
    ),
    InstantAttribute(
      id: "transcriptionSegments/wordCount", namespace: "transcriptionSegments", name: "wordCount",
      valueType: .number, isRequired: false
    ),
    InstantAttribute(
      id: "transcriptionSegments/speaker", namespace: "transcriptionSegments", name: "speaker",
      valueType: .string, isRequired: false
    ),
  ]

  static let attributes = FastDrainSchema.scribeLinkAttributes + FastDrainSchema.liveLineAttributes + lineAttributes

  /// The attributes Scribe keeps out of memory (`ScribeInstantBootstrap.deferredValueResidency`).
  static let deferredAttributeIDs = ["transcriptionSegments/text", "transcriptionSegments/wordsJSON"]

  /// The attributes Scribe looks a recording's rows up by on disk (`ScribeInstantBootstrap.localLookup`).
  static let lookupAttributeIDs: Set<String> = ["recordings/id", "transcriptionSegments/recordingID"]
}

/// Scribe's writes for one transcript line, at the sizes the phone's store holds them (#1076): on the phone a line is
/// 16 facts, its `text` about 57 bytes of JSON and its `wordsJSON` about 458 (12 words of `{"end":…,"start":…,"text":…}`).
///
/// Three interims on the line's live row (ADR 0069: each replaces the row's words), the final line, which deletes the
/// live row and re-asserts the recording, the recording's summary, and its duration tick. Every write re-inserts the
/// whole row, as Scribe's `persist` does.
struct StorageIOLineScript {
  typealias Word = (text: String, start: Double, end: Double)

  static let wordsPerLine = 10

  var nextLineIndex: Int
  var deviceMilliseconds: Int64
  var writeCount = 0
  var wordCount = 0

  init(firstLineIndex: Int, deviceMilliseconds: Int64) {
    nextLineIndex = firstLineIndex
    self.deviceMilliseconds = deviceMilliseconds
  }

  mutating func nextLineWrites() -> [InstantStoreTransaction] {
    let index = nextLineIndex
    nextLineIndex += 1
    var writes: [InstantStoreTransaction] = []
    for update in 1...3 {
      writes.append(liveLineWrite(index: index, words: Self.words(line: index, count: Self.wordsPerLine * update / 3)))
    }
    let words = Self.words(line: index, count: Self.wordsPerLine)
    writes.append(finalWrite(index: index, words: words))
    wordCount += words.count
    writes.append(summaryWrite(lineIndex: index))
    writes.append(durationWrite())
    return writes
  }

  /// The writes of a line the server already holds, for the store's history.
  mutating func historyWrites() -> [InstantStoreTransaction] {
    let index = nextLineIndex
    nextLineIndex += 1
    let words = Self.words(line: index, count: Self.wordsPerLine)
    wordCount += words.count
    return [finalWrite(index: index, words: words, deletesLiveLine: false), summaryWrite(lineIndex: index)]
  }

  static func words(line: Int, count: Int) -> [Word] {
    (0..<count).map { word in
      let start = Double(line) * 4.25 + Double(word) * 0.41
      return ("word\(line % 97)-\(word)", start, start + 0.37)
    }
  }

  static func text(_ words: [Word]) -> String {
    words.map(\.text).joined(separator: " ")
  }

  static func wordsJSON(_ words: [Word]) -> String {
    let encoded = words.map { word in
      "{\"end\":\(String(format: "%.6f", word.end)),\"start\":\(String(format: "%.6f", word.start)),"
        + "\"text\":\"\(word.text)\"}"
    }
    return "[" + encoded.joined(separator: ",") + "]"
  }

  private mutating func stamp() -> (id: String, time: InstantTimestamp, milliseconds: Double) {
    deviceMilliseconds += 97
    writeCount += 1
    return (
      UUID().uuidString.lowercased(),
      InstantTimestamp(milliseconds: deviceMilliseconds),
      Double(deviceMilliseconds) + 0.25
    )
  }

  private mutating func liveLineWrite(index: Int, words: [Word]) -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let line = FastDrainSchema.liveLineID(index)
    func insert(_ attribute: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(InstantTriple(entityID: line, attributeID: "liveLines/\(attribute)", value: value, txID: id, txTime: time))
    }
    return InstantStoreTransaction(
      id: id,
      operations: [
        insert("id", .string(line)),
        insert("recordingID", .string(FastDrainSchema.recordingID)),
        insert("segmentID", .string(FastDrainSchema.segmentID(index))),
        insert("segmentIndex", .number(Double(index))),
        insert("text", .string(Self.text(words))),
        insert("wordsJSON", .string(Self.wordsJSON(words))),
        insert("updatedAtMs", .number(updatedAt)),
      ]
    )
  }

  private mutating func finalWrite(index: Int, words: [Word], deletesLiveLine: Bool = true) -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let segment = FastDrainSchema.segmentID(index)
    let recording = FastDrainSchema.recordingID
    func insert(_ attribute: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(
        InstantTriple(
          entityID: segment, attributeID: "transcriptionSegments/\(attribute)", value: value, txID: id, txTime: time
        )
      )
    }
    var operations: [InstantTripleOperation] = [
      .requireEntityExists(entityID: recording, namespace: "recordings"),
      .insert(InstantTriple(entityID: recording, attributeID: "recordings/id", value: .string(recording), txID: id, txTime: time)),
      insert("id", .string(segment)),
      insert("ownerUserID", .string(FastDrainSchema.ownerID)),
      insert("recordingID", .string(recording)),
      insert("transcriptionID", .string(FastDrainSchema.transcriptionID)),
      insert("segmentIndex", .number(Double(index))),
      insert("startTimeSeconds", .number(words.first?.start ?? 0)),
      insert("endTimeSeconds", .number(words.last?.end ?? 0)),
      insert("wallClockStartedAtMs", .number(Double(deviceMilliseconds) - 4_250)),
      insert("wallClockEndedAtMs", .number(Double(deviceMilliseconds))),
      insert("sentToInstantAtMs", .number(updatedAt)),
      insert("text", .string(Self.text(words))),
      insert("wordsJSON", .string(Self.wordsJSON(words))),
      insert("isFinal", .bool(true)),
      insert("wordCount", .number(Double(words.count))),
      insert("speaker", .string("speaker-1")),
      insert("updatedAtMs", .number(updatedAt)),
      // Scribe's link, written in its reverse form and materialized as `recordings/segments` on the recording.
      insert("recording", .ref(recording)),
    ]
    if deletesLiveLine {
      operations.append(.deleteEntity(FastDrainSchema.liveLineID(index)))
    }
    return InstantStoreTransaction(id: id, operations: operations)
  }

  private mutating func summaryWrite(lineIndex: Int) -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let recording = FastDrainSchema.recordingID
    let transcription = FastDrainSchema.transcriptionID
    func triple(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: id, txTime: time))
    }
    return InstantStoreTransaction(
      id: id,
      operations: [
        .requireEntityExists(entityID: recording, namespace: "recordings"),
        triple(recording, "recordings/id", .string(recording)),
        triple(recording, "recordings/updatedAtMs", .number(updatedAt)),
        triple(recording, "recordings/previewSegmentB", .ref(FastDrainSchema.segmentID(lineIndex))),
        triple(transcription, "transcriptions/id", .string(transcription)),
        triple(transcription, "transcriptions/segmentCount", .number(Double(lineIndex + 1))),
        triple(transcription, "transcriptions/wordCount", .number(Double(wordCount))),
        triple(transcription, "transcriptions/updatedAtMs", .number(updatedAt)),
        triple(transcription, "transcriptions/recording", .ref(recording)),
      ]
    )
  }

  private mutating func durationWrite() -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let recording = FastDrainSchema.recordingID
    func triple(_ attributeID: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(InstantTriple(entityID: recording, attributeID: attributeID, value: value, txID: id, txTime: time))
    }
    return InstantStoreTransaction(
      id: id,
      operations: [
        .requireEntityExists(entityID: recording, namespace: "recordings"),
        triple("recordings/id", .string(recording)),
        triple("recordings/durationSeconds", .number(Double(writeCount) * 1.5)),
        triple("recordings/updatedAtMs", .number(updatedAt)),
      ]
    )
  }
}

// MARK: - The write cycle

/// The steps of a live write the exercises measure.
enum StorageIOStep: String, CaseIterable {
  case save, claim, ack, echo, prune
  /// The live session's claim, send and acknowledgement together, as it runs them on its own (the fixture's exercise).
  case deliver
}

/// A recording's live writes against a runtime on a clock the exercise moves: Scribe's writes at the phone's sizes
/// answered by `FastDrainServer`, one write at a time, as a phone with an open socket delivers them.
struct StorageIOWriteCycle {
  var runtime: InstantRuntime
  var server: FastDrainServer
  var script: StorageIOLineScript
  var configuration: InstantRuntimeConfiguration
  let clock: StorageIOClock
  let millisecondsPerWrite: Int64
  let pageLines: Int
  var seedSeconds: Double
  var claimSequence = 0

  /// A runtime configured as Scribe configures it, on a store that holds `settings.recordingLines` lines of one
  /// recording the server already has, and the stored results of the queries Scribe keeps open while it records.
  static func make(label: String, directory: URL, settings: StorageIOExerciseSettings) async throws -> Self {
    let attributes = StorageIOSchema.attributes
    let clock = StorageIOClock(milliseconds: 1_790_700_000_000)
    var configuration = InstantRuntimeConfiguration(
      appID: "storage-io-\(label)",
      persistenceURL: directory.appendingPathComponent("store.sqlite"),
      initialAttributes: attributes,
      now: { clock.now() }
    )
    configuration.reducesServerApplyToAffectedOverlays = true
    configuration.deferredValueResidency = InstantDeferredValueResidencyPolicy(
      attributeIDs: StorageIOSchema.deferredAttributeIDs
    )
    configuration.localLookup = InstantLocalLookupPolicy(attributeIDs: StorageIOSchema.lookupAttributeIDs)
    // The exercise prunes once a minute itself, where the runtime prunes every 64 result writes on its own.
    configuration.liveQueryResultPruningWriteInterval = Int.max
    // A result's JSON waits 30 s of the recording's time, not of the exercise's.
    configuration.liveQueryResultJSONFlushSleep = { milliseconds in try await clock.sleep(milliseconds: milliseconds) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let seedStarted = ContinuousClock.now
    var server = FastDrainServer(serverMilliseconds: clock.milliseconds, attributes: attributes)
    server.timelineWindow = settings.pageLines
    server.registeredQueries.append(.liveLines)
    // The recording's history: the server accepts every line, and the store holds every fact of it, as the phone's
    // store holds the lines of its recordings. The server's facts (links in their forward form) are applied as server
    // transactions of 250 lines, then the recording and its transcription, then the queries' results.
    var history = StorageIOLineScript(firstLineIndex: 0, deviceMilliseconds: clock.milliseconds - 86_400_000)
    let summaryEntities: Set<String> = [FastDrainSchema.recordingID, FastDrainSchema.transcriptionID]
    var batchEntities: Set<String> = []
    for line in 0..<settings.recordingLines {
      for write in history.historyWrites() {
        _ = server.accept(write.operations)
        batchEntities.formUnion(write.operations.compactMap(\.storageIOInsertedTriple).map(\.entityID))
      }
      let isLast = line + 1 == settings.recordingLines
      guard (line + 1) % 250 == 0 || isLast else { continue }
      let transactionID = String(server.lastTransactionNumber)
      _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
        InstantStoreTransaction(
          id: transactionID,
          operations: server.storageIOTriples(of: batchEntities.subtracting(summaryEntities), transactionID: transactionID)
            .map(InstantTripleOperation.insert)
        ),
        attributesToMerge: []
      )
      batchEntities.removeAll(keepingCapacity: true)
      if isLast {
        _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
          InstantStoreTransaction(
            id: transactionID,
            operations: server.storageIOTriples(of: summaryEntities, transactionID: transactionID)
              .map(InstantTripleOperation.insert)
          ),
          attributesToMerge: []
        )
      }
    }
    let seed = server.frame(
      queries: server.registeredQueries,
      processedTransactionID: String(server.lastTransactionNumber)
    )
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      seed.transaction,
      attributesToMerge: [],
      liveQueryResultReplacements: seed.replacements
    )
    // Each exercise starts on an empty write-ahead log.
    try StorageIOStoreFile.checkpoint(configuration.persistenceURL)
    return Self(
      runtime: runtime,
      server: server,
      script: StorageIOLineScript(firstLineIndex: settings.recordingLines, deviceMilliseconds: clock.milliseconds),
      configuration: configuration,
      clock: clock,
      millisecondsPerWrite: Int64(60_000 / max(1, settings.linesPerMinute * 6)),
      pageLines: settings.pageLines,
      seedSeconds: Double((ContinuousClock.now - seedStarted).components.seconds)
    )
  }

  /// One transcript line's six writes, each saved, claimed, sent, acknowledged and echoed before the next.
  mutating func writeLine(into ledger: StorageIOLedger, alsoInto second: StorageIOLedger? = nil) async throws {
    let ledgers = [ledger] + (second.map { [$0] } ?? [])
    func record(_ step: StorageIOStep, _ measured: StorageIOProbe, logicalBytes: Int = 0) {
      for ledger in ledgers { ledger.record(step, measured, logicalBytes: logicalBytes) }
    }
    for write in script.nextLineWrites() {
      clock.advance(by: millisecondsPerWrite)
      let save = StorageIOProbe.start()
      _ = try await runtime.transact(write, createdAt: clock.now())
      record(.save, save.stop(), logicalBytes: write.storageIOLogicalByteCount)

      claimSequence += 1
      let token = "storage-io-claim-\(claimSequence)"
      let claim = StorageIOProbe.start()
      let window = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
        InstantAutomaticOutboxClaimRequest(
          claimantID: runtime.automaticDeliveryClaimantIDForTesting(),
          claimToken: token,
          now: clock.now(),
          maximumMutationCount: 50
        )
      )
      record(.claim, claim.stop())

      let operationsByID = Dictionary(
        window.mutations.map { ($0.id, $0.transaction.operations) },
        uniquingKeysWith: { first, _ in first }
      )
      for mutation in InstantBoundedOutboxDelivery.transportMutations(in: window) {
        let operations = operationsByID[mutation.mutationID] ?? []
        // What the live session sends: one `transact` frame of the write's steps.
        let sent = try StorageIOWire.transactFrame(mutation)
        let transactionID = server.accept(operations)
        let ack = StorageIOProbe.start()
        _ = try await runtime.acceptMutationIfPresent(
          id: mutation.mutationID,
          serverTransactionID: transactionID,
          claimToken: token
        )
        record(.ack, ack.stop())

        // The page the newest line is on: a transcript query of `pageLines` lines holds the lines of its page.
        let onPage = script.nextLineIndex % pageLines
        server.timelineWindow = onPage == 0 ? pageLines : onPage
        let touched = Set(operations.compactMap(\.storageIOInsertedTriple).map(\.entityID))
        let deleted = Set(operations.compactMap(\.storageIODeletedEntityID))
        let frame = server.frame(
          queries: server.queries(touching: touched.union(deleted), deleting: deleted),
          processedTransactionID: transactionID
        )
        let received = [
          try StorageIOWire.transactOKFrame(mutation, transactionID: transactionID),
          try StorageIOWire.refreshOKFrame(frame.replacements, processedTransactionID: transactionID),
        ].compactMap { $0 }
        for ledger in ledgers {
          ledger.recordWire(
            sent: [sent],
            received: received,
            refreshTriples: frame.replacements.reduce(0) { $0 + $1.triples.count },
            changedTriples: operations.count
          )
        }
        let echo = StorageIOProbe.start()
        _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
          frame.transaction,
          attributesToMerge: [],
          liveQueryResultReplacements: frame.replacements
        )
        record(.echo, echo.stop())
      }
    }
  }

  /// The session prune, as the runtime runs it about once a minute while a recording writes.
  func prune(into ledger: StorageIOLedger) async throws {
    let prune = StorageIOProbe.start()
    _ = try await runtime.pruneLiveQueryResults(policy: configuration.liveQueryResultPruningPolicy, now: clock.now())
    ledger.record(.prune, prune.stop())
  }
}

extension FastDrainServer {
  /// Every fact the server holds for `entities`, as server triples stamped with `transactionID`.
  func storageIOTriples(of entities: Set<String>, transactionID: String) -> [InstantTriple] {
    entities.sorted().flatMap { entityID in
      (facts[entityID] ?? [:]).sorted { $0.key < $1.key }.flatMap { attributeID, values in
        values.map { value, txTime in
          InstantTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            txID: transactionID,
            txTime: InstantTimestamp(milliseconds: txTime)
          )
        }
      }
    }
  }
}

extension InstantTripleOperation {
  var storageIOInsertedTriple: InstantTriple? {
    if case let .insert(triple) = self { return triple }
    return nil
  }

  var storageIODeletedEntityID: String? {
    if case let .deleteEntity(entityID) = self { return entityID }
    return nil
  }
}

extension InstantStoreTransaction {
  /// The bytes of what the write changes, as JSON: each operation's entity, attribute and value. The floor any store
  /// must write for it, against which the exercises divide what SQLite wrote.
  var storageIOLogicalByteCount: Int {
    (try? JSONEncoder().encode(operations).count) ?? 0
  }
}

/// The recording's clock: the exercise moves it a write's worth at a time, and a sleep on it waits for the recording's
/// time to pass, so the runtime's 30 s result-JSON interval sees a recording's minutes.
final class StorageIOClock: @unchecked Sendable {
  // SAFETY: `lock` guards `value`.
  private let lock = NSLock()
  private var value: Int64

  init(milliseconds: Int64) { value = milliseconds }

  var milliseconds: Int64 { lock.withLock { value } }
  func now() -> InstantTimestamp { InstantTimestamp(milliseconds: milliseconds) }
  func advance(by delta: Int64) { lock.withLock { value += delta } }

  func sleep(milliseconds: UInt64) async throws {
    let deadline = self.milliseconds + Int64(milliseconds)
    while self.milliseconds < deadline {
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}

/// A recording's live transcript page on #1072's fixture: each line's writes, acknowledged by the scripted server,
/// then the page's whole result sent again, as Instant's `refresh-ok` does.
struct StorageIOTranscriptPage {
  static let writesPerLine = 5

  var recordingID: String
  var rows: [String: InstantLiveJSONValue] = [:]
  var tick = 0

  init(recordingID: String) {
    self.recordingID = recordingID
  }

  mutating func write(
    line: Int,
    session: RealSizeSession,
    query: InstantLiveJSONValue,
    into ledger: StorageIOLedger
  ) async throws {
    let segmentID = RealSizeID.make(.segment, 900_000 + line)
    for revision in 1...4 {
      let write = session.segmentWrite(recordingID: recordingID, line: line, revision: revision, id: segmentID)
      try await deliver(write, session: session, into: ledger)
      rows[segmentID] = RealSizeAccount.segment(
        recordingID: recordingID, line: line, revision: revision, serial: 0, id: segmentID
      ).joinRow()
      let echo = StorageIOProbe.start()
      let transaction = await session.server.refresh(query, rows: rows.keys.sorted().compactMap { rows[$0] })
      _ = try await session.applies.wait(for: transaction)
      ledger.record(.echo, echo.stop())
    }
    tick += 1
    let time = session.clock.advance()
    func triple(_ field: String, _ value: InstantValue) -> InstantTripleOperation {
      .merge(InstantTriple(entityID: recordingID, attributeID: "recordings/\(field)", value: value, txID: "tick", txTime: time))
    }
    try await deliver(
      InstantStoreTransaction(
        id: UUID().uuidString.lowercased(),
        operations: [triple("durationSeconds", .number(Double(tick) * 4)), triple("updatedAtMs", .number(Double(time.milliseconds)))]
      ),
      session: session,
      into: ledger
    )
  }

  /// Saves the write, then waits until the live session claimed and sent it and the server acknowledged it.
  private func deliver(
    _ write: InstantStoreTransaction,
    session: RealSizeSession,
    into ledger: StorageIOLedger
  ) async throws {
    let save = StorageIOProbe.start()
    _ = try await session.runtime.transact(write, createdAt: session.clock.now())
    ledger.record(.save, save.stop(), logicalBytes: write.storageIOLogicalByteCount)
    let deliver = StorageIOProbe.start()
    try await RealSizeGenerator.waitForSettledOutbox(session.runtime)
    ledger.record(.deliver, deliver.stop())
  }
}

/// Every frame the fixture's scripted server sent or received, by direction and op (#1076).
final class StorageIOFrameLog: @unchecked Sendable {
  struct Measure {
    var frames = 0
    var bytes = 0
    var largest = 0
  }

  // SAFETY: `lock` guards `measures`.
  private let lock = NSLock()
  private var measures: [String: Measure] = [:]

  func record(_ frame: RealSizeFrame) {
    let key = "\(frame.direction == .toServer ? "sent" : "received")-\(frame.op)"
    lock.withLock {
      var measure = measures[key] ?? Measure()
      measure.frames += 1
      measure.bytes += frame.encodedBytes
      measure.largest = max(measure.largest, frame.encodedBytes)
      measures[key] = measure
    }
  }

  func reset() { lock.withLock { measures = [:] } }
  func snapshot() -> [String: Measure] { lock.withLock { measures } }
}

// MARK: - The wire

/// The frames one change puts on the socket, encoded as the live transport encodes them (#1076): the `transact` the
/// session sends (`InstantLiveMessage.transact`, `JSONEncoder`), and the `transact-ok` and `refresh-ok` the server
/// answers with. Ids are the fixture's (24-36 characters; the server's attribute ids are 36-character UUIDs), the
/// `refresh-ok` carries no `attrs` (the session advertises v0.22.75, #303), and its join rows hold one row per entity.
/// WebSocket and TLS framing are not counted.
enum StorageIOWire {
  static func transactFrame(_ mutation: InstantTransportMutation) throws -> Data {
    try JSONEncoder().encode(InstantLiveMessage.transact(mutation.txSteps, clientEventID: mutation.mutationID))
  }

  static func transactOKFrame(_ mutation: InstantTransportMutation, transactionID: String) throws -> Data {
    try JSONEncoder().encode(
      InstantLiveMessage(op: "transact-ok", clientEventID: mutation.mutationID, fields: ["tx-id": .string(transactionID)])
    )
  }

  /// The `refresh-ok` that restates `replacements`, or `nil` when the write changed no query the device holds.
  static func refreshOKFrame(
    _ replacements: [InstantLiveQueryResultReplacement],
    processedTransactionID: String
  ) throws -> Data? {
    guard !replacements.isEmpty else { return nil }
    let computations: [InstantLiveJSONValue] = replacements.map { replacement in
      let byEntity = Dictionary(grouping: replacement.triples, by: \.entityID)
      let rows: [InstantLiveJSONValue] = byEntity.keys.sorted().map { entityID in
        .array(
          byEntity[entityID, default: []].map { triple in
            .array([
              .string(triple.entityID),
              .string(triple.attributeID),
              wireValue(triple.value),
              .number(Double(triple.txTime.milliseconds)),
            ])
          }
        )
      }
      return .object([
        "instaql-query": .object([replacement.key: .object([:])]),
        "instaql-result": .array([
          .object(["data": .object(["datalog-result": .object(["join-rows": .array(rows)])])])
        ]),
      ])
    }
    return try JSONEncoder().encode(
      InstantLiveMessage(
        op: "refresh-ok",
        clientEventID: nil,
        fields: [
          "attrs": .array([]),
          "computations": .array(computations),
          "processed-tx-id": .string(processedTransactionID),
        ]
      )
    )
  }

  /// The frame's size compressed alone with zlib's DEFLATE (Apple's `COMPRESSION_ZLIB`, level 5): what
  /// permessage-deflate would send without a shared window between frames, which saves less than one with it.
  static func deflatedByteCount(_ frame: Data) -> Int {
    guard !frame.isEmpty else { return 0 }
    let capacity = frame.count + 4_096
    var output = [UInt8](repeating: 0, count: capacity)
    let count = frame.withUnsafeBytes { raw -> Int in
      guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
      return compression_encode_buffer(&output, capacity, source, frame.count, nil, COMPRESSION_ZLIB)
    }
    return count == 0 ? frame.count : count
  }

  /// Bytes `JSONEncoder` spends escaping `/` as `\/` in the frame (the live transport does not pass
  /// `.withoutEscapingSlashes`).
  static func escapedSlashByteCount(_ frame: Data) -> Int {
    var count = 0
    var previous: UInt8 = 0
    for byte in frame {
      if previous == UInt8(ascii: "\\"), byte == UInt8(ascii: "/") { count += 1 }
      previous = byte
    }
    return count
  }

  static func wireValue(_ value: InstantValue) -> InstantLiveJSONValue {
    switch value {
    case .null: .null
    case let .string(string): .string(string)
    case let .number(number): .number(number)
    case let .bool(bool): .bool(bool)
    case let .date(date): .number(date.timeIntervalSince1970 * 1_000)
    case let .ref(id): .string(id)
    case let .json(json):
      (try? JSONEncoder().encode(json)).flatMap { try? JSONDecoder().decode(InstantLiveJSONValue.self, from: $0) }
        ?? .null
    case let .lookupRef(lookup): .string(String(describing: lookup))
    }
  }
}

/// What the wire carried for a run of changes.
struct StorageIOWireTotals {
  var changes = 0
  var sentFrames = 0
  var sentBytes = 0
  var receivedFrames = 0
  var receivedBytes = 0
  /// The same frames, each compressed alone (``StorageIOWire/deflatedByteCount(_:)``).
  var sentDeflatedBytes = 0
  var receivedDeflatedBytes = 0
  var escapedSlashBytes = 0
  /// The triples the `refresh-ok` frames restated, against the operations the changes held.
  var refreshTriples = 0
  var changedTriples = 0
}

// MARK: - Measuring

/// The counters at one moment: SQLite's file calls (the shim), the store's pages per store call, and the process.
struct StorageIOProbe {
  var io: StorageIOSnapshot
  var calls: InstantStorageWriteSnapshot
  var process: StorageIOProcess

  static func start() -> Self {
    Self(io: StorageIOCounters.snapshot(), calls: InstantStorageWriteMeter.snapshot(), process: .now())
  }

  /// What was counted since `start()`.
  func stop() -> Self {
    let now = Self.start()
    return Self(
      io: now.io.subtracting(io),
      calls: now.calls.subtracting(calls),
      process: now.process.subtracting(process)
    )
  }
}

/// The process's own accounting (`proc_pid_rusage`): logical bytes written to every file, the bytes its I/O wrote
/// to the drive, and CPU time.
struct StorageIOProcess {
  var logicalWriteBytes: UInt64
  /// `ri_diskio_byteswritten`: what reached the drive on the process's behalf, after the file system's own
  /// coalescing and metadata.
  var diskWriteBytes: UInt64
  var cpuNanoseconds: UInt64

  static func now() -> Self {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
      }
    }
    guard result == 0 else { return Self(logicalWriteBytes: 0, diskWriteBytes: 0, cpuNanoseconds: 0) }
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let ticks = info.ri_user_time + info.ri_system_time
    return Self(
      logicalWriteBytes: info.ri_logical_writes,
      diskWriteBytes: info.ri_diskio_byteswritten,
      cpuNanoseconds: ticks * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
    )
  }

  func subtracting(_ earlier: Self) -> Self {
    Self(
      logicalWriteBytes: logicalWriteBytes &- earlier.logicalWriteBytes,
      diskWriteBytes: diskWriteBytes &- earlier.diskWriteBytes,
      cpuNanoseconds: cpuNanoseconds &- earlier.cpuNanoseconds
    )
  }
}

/// What each step cost, summed over the steps it ran.
final class StorageIOLedger {
  private var counts: [StorageIOStep: Int] = [:]
  private var io: [StorageIOStep: StorageIOSnapshot] = [:]
  private var calls: [StorageIOStep: [String: InstantStorageWriteSnapshot.Measure]] = [:]
  private var logical: [StorageIOStep: Int] = [:]
  private var cpu: [StorageIOStep: UInt64] = [:]
  private(set) var wire = StorageIOWireTotals()

  func record(_ step: StorageIOStep, _ measured: StorageIOProbe, logicalBytes: Int = 0) {
    counts[step, default: 0] += 1
    io[step] = (io[step] ?? StorageIOSnapshot()).adding(measured.io)
    var stepCalls = calls[step] ?? [:]
    for (name, measure) in measured.calls.operations {
      var total = stepCalls[name] ?? InstantStorageWriteSnapshot.Measure()
      total.transactions += measure.transactions
      total.pagesWritten += measure.pagesWritten
      stepCalls[name] = total
    }
    calls[step] = stepCalls
    logical[step, default: 0] += logicalBytes
    cpu[step, default: 0] += measured.process.cpuNanoseconds
  }

  func recordWire(sent: [Data], received: [Data], refreshTriples: Int, changedTriples: Int) {
    wire.changes += 1
    wire.sentFrames += sent.count
    wire.receivedFrames += received.count
    for frame in sent {
      wire.sentBytes += frame.count
      wire.sentDeflatedBytes += StorageIOWire.deflatedByteCount(frame)
      wire.escapedSlashBytes += StorageIOWire.escapedSlashByteCount(frame)
    }
    for frame in received {
      wire.receivedBytes += frame.count
      wire.receivedDeflatedBytes += StorageIOWire.deflatedByteCount(frame)
      wire.escapedSlashBytes += StorageIOWire.escapedSlashByteCount(frame)
    }
    wire.refreshTriples += refreshTriples
    wire.changedTriples += changedTriples
  }

  func count(_ step: StorageIOStep) -> Int { counts[step] ?? 0 }
  func io(_ step: StorageIOStep) -> StorageIOSnapshot { io[step] ?? StorageIOSnapshot() }
  func calls(_ step: StorageIOStep) -> [String: InstantStorageWriteSnapshot.Measure] { calls[step] ?? [:] }
  func logicalBytes(_ step: StorageIOStep) -> Int { logical[step] ?? 0 }
  func cpuNanoseconds(_ step: StorageIOStep) -> UInt64 { cpu[step] ?? 0 }
}

extension StorageIOSnapshot {
  /// The sum of two intervals' counts.
  func adding(_ other: Self) -> Self {
    var files = self.files
    for (kind, counts) in other.files {
      var total = files[kind] ?? StorageIOCounts()
      total.opens += counts.opens
      total.writes += counts.writes
      total.bytesWritten += counts.bytesWritten
      total.reads += counts.reads
      total.bytesRead += counts.bytesRead
      total.syncs += counts.syncs
      total.fullSyncs += counts.fullSyncs
      total.syncNanoseconds &+= counts.syncNanoseconds
      total.truncates += counts.truncates
      files[kind] = total
    }
    return Self(
      files: files,
      walFramesByPage: walFramesByPage.merging(other.walFramesByPage, uniquingKeysWith: +),
      databaseWritesByPage: databaseWritesByPage.merging(other.databaseWritesByPage, uniquingKeysWith: +),
      databaseReadsByPage: databaseReadsByPage.merging(other.databaseReadsByPage, uniquingKeysWith: +),
      walRestarts: walRestarts + other.walRestarts,
      deletes: deletes + other.deletes,
      pageSize: other.pageSize
    )
  }
}

/// The store file as SQLite and the file system see it, read on a connection that bypasses the shim.
struct StorageIOStoreFile {
  var pageSize: Int
  var pageCount: Int
  var freePages: Int
  var databaseBytes: Int
  var walBytes: Int

  static func read(_ store: URL) throws -> Self {
    let connection = try open(store, flags: SQLITE_OPEN_READONLY)
    defer { sqlite3_close_v2(connection) }
    func size(_ path: String) -> Int {
      ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue ?? 0
    }
    return Self(
      pageSize: try storageIOInteger(connection, "PRAGMA page_size"),
      pageCount: try storageIOInteger(connection, "PRAGMA page_count"),
      freePages: try storageIOInteger(connection, "PRAGMA freelist_count"),
      databaseBytes: size(store.path),
      walBytes: size(store.path + "-wal")
    )
  }

  /// The facts the store holds on disk.
  static func factCount(_ store: URL) throws -> Int {
    let connection = try open(store, flags: SQLITE_OPEN_READONLY)
    defer { sqlite3_close_v2(connection) }
    return try storageIOInteger(connection, "SELECT count(*) FROM instant_triples")
  }

  /// Copies the write-ahead log into the store and empties it, on a connection that bypasses the shim.
  static func checkpoint(_ store: URL) throws {
    let connection = try open(store, flags: SQLITE_OPEN_READWRITE)
    defer { sqlite3_close_v2(connection) }
    try storageIOExecute(connection, "PRAGMA wal_checkpoint(TRUNCATE)")
  }

  private static func open(_ store: URL, flags: Int32) throws -> OpaquePointer? {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, flags, "unix") == SQLITE_OK else {
      sqlite3_close_v2(connection)
      throw StorageIOError("open \(store.lastPathComponent)")
    }
    sqlite3_busy_timeout(connection, 10_000)
    return connection
  }
}

extension StorageIOLine {
  /// The b-trees whose pages a step read from the database file, the most read first, in KB per write.
  static func printReads(
    _ exercise: String,
    _ step: String,
    _ io: StorageIOSnapshot,
    map: StorageIOPageMap,
    per count: Int,
    limit: Int = 8
  ) {
    let reads = map.byName(io.databaseReadsByPage)
    for (name, pages) in reads.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(limit) {
      var line = StorageIOLine(exercise, step)
      line.add("btree", name)
      line.add("readKBPerWrite", Double(pages * io.pageSize) / 1_024 / Double(max(1, count)))
      let distinct = io.databaseReadsByPage.keys.filter { (map.nameByPage[$0] ?? "(free or other)") == name }
      line.add("distinctPages", distinct.count)
      line.print()
    }
  }

  /// The frames a step wrote on the outbox's own b-trees (its table, indexes, write keys and effect entities) against
  /// all its frames: the outbox's share of a write's log (#1076's finding 2).
  static func printOutboxShare(_ exercise: String, _ step: String, _ framesByName: [String: Int], per count: Int) {
    let outbox = framesByName.filter {
      $0.key.hasPrefix("instant_outbox") || $0.key.hasPrefix("sqlite_autoindex_instant_outbox")
    }
    var line = StorageIOLine(exercise, step)
    line.add("outboxFramesPerWrite", Double(outbox.values.reduce(0, +)) / Double(max(1, count)), digits: 2)
    line.add("framesPerWrite", Double(framesByName.values.reduce(0, +)) / Double(max(1, count)), digits: 2)
    line.add("outboxBtrees", outbox.count)
    line.print()
  }

  mutating func add(file: StorageIOStoreFile) {
    add("dbMB", Double(file.databaseBytes) / 1_048_576, digits: 2)
    add("walMB", Double(file.walBytes) / 1_048_576, digits: 2)
    add("pages", file.pageCount)
    add("freePages", file.freePages)
    add("freeMB", Double(file.freePages * file.pageSize) / 1_048_576, digits: 2)
  }

  /// Bytes on the wire per write: sent (`transact`), received (`transact-ok` and `refresh-ok`), and how many triples
  /// the `refresh-ok` restated for each operation the write changed.
  mutating func add(wire: StorageIOWireTotals, per count: Int) {
    let divisor = Double(max(1, count))
    add("sentFrames", Double(wire.sentFrames) / divisor, digits: 2)
    add("sentKB", Double(wire.sentBytes) / 1_024 / divisor, digits: 2)
    add("receivedFrames", Double(wire.receivedFrames) / divisor, digits: 2)
    add("receivedKB", Double(wire.receivedBytes) / 1_024 / divisor, digits: 2)
    add("sentDeflatedKB", Double(wire.sentDeflatedBytes) / 1_024 / divisor, digits: 2)
    add("receivedDeflatedKB", Double(wire.receivedDeflatedBytes) / 1_024 / divisor, digits: 2)
    add("escapedSlashBytes", Double(wire.escapedSlashBytes) / divisor, digits: 1)
    add("refreshTriples", Double(wire.refreshTriples) / divisor, digits: 1)
    add("changedTriples", Double(wire.changedTriples) / divisor, digits: 1)
  }
}

func storageIOExecute(_ connection: OpaquePointer?, _ sql: String) throws {
  var message: UnsafeMutablePointer<CChar>?
  guard sqlite3_exec(connection, sql, nil, nil, &message) == SQLITE_OK else {
    defer { sqlite3_free(message) }
    throw StorageIOError("\(sql): \(message.map { String(cString: $0) } ?? "failed")")
  }
}

func storageIOInteger(_ connection: OpaquePointer?, _ sql: String) throws -> Int {
  var statement: OpaquePointer?
  guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
    throw StorageIOError("\(sql): \(String(cString: sqlite3_errmsg(connection)))")
  }
  defer { sqlite3_finalize(statement) }
  guard sqlite3_step(statement) == SQLITE_ROW else { throw StorageIOError("\(sql) returned no row") }
  return Int(sqlite3_column_int64(statement, 0))
}
