// History:
// - 2026-10-24: the storage audit's exercises (#1076): what one live write costs the disk at each of its steps (save,
//   claim, acknowledgement, the server's echo, the prune) and on the wire, and what an hour of recording does to the
//   store file, on a store holding as many transcript lines as the phone's; and the same writes delivered by the live
//   session on #1072's phone-shaped store.

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
    }
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
    startLine.print()

    let ledger = StorageIOLedger()
    let hour = StorageIOProbe.start()
    var interval = StorageIOProbe.start()
    var intervalLedger = StorageIOLedger()
    for minute in 1...settings.minutes {
      for _ in 0..<settings.linesPerMinute {
        try await cycle.writeLine(into: ledger, alsoInto: intervalLedger)
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
    end.add("amplification", Double(total.io.bytesWritten) / Double(max(1, ledger.logicalBytes(.save))))
    end.add("syncs", total.io.syncs)
    end.add("fullSyncs", total.io.files.values.reduce(0) { $0 + $1.fullSyncs })
    end.add("walRestarts", total.io.walRestarts)
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
          ledger.record(.prune, prune.stop())
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

/// The process's own accounting (`proc_pid_rusage`): logical bytes written to every file, and CPU time.
struct StorageIOProcess {
  var logicalWriteBytes: UInt64
  var cpuNanoseconds: UInt64

  static func now() -> Self {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
      }
    }
    guard result == 0 else { return Self(logicalWriteBytes: 0, cpuNanoseconds: 0) }
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let ticks = info.ri_user_time + info.ri_system_time
    return Self(
      logicalWriteBytes: info.ri_logical_writes,
      cpuNanoseconds: ticks * UInt64(timebase.numer) / UInt64(max(1, timebase.denom))
    )
  }

  func subtracting(_ earlier: Self) -> Self {
    Self(
      logicalWriteBytes: logicalWriteBytes &- earlier.logicalWriteBytes,
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
      total.truncates += counts.truncates
      files[kind] = total
    }
    return Self(
      files: files,
      walFramesByPage: walFramesByPage.merging(other.walFramesByPage, uniquingKeysWith: +),
      databaseWritesByPage: databaseWritesByPage.merging(other.databaseWritesByPage, uniquingKeysWith: +),
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
