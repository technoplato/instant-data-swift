// Research for #1442, kept on its own branch and never on main: what one stream append costs the disk beside one
// outbox write, on the same store, measured by the storage audit's own counters (#1076).

import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct StreamAppendCost1442 {
  /// A line in progress as JSON, at the size of a long line (Recording 331: p50 358 bytes of words, p95 997).
  static let chunk: String = {
    let words = (0..<14).map { #"{"text":"transcribe","start":\#(Double($0) * 0.32),"end":\#(Double($0) * 0.32 + 0.3)}"# }
    return #"{"segmentID":"1622da4c-c382-4d55-9f14-8878803e6137","segmentIndex":812,"text":"transcribe transcribe transcribe transcribe transcribe transcribe","wordsJSON":[\#(words.joined(separator: ","))],"updatedAtMs":1793408531372}"# + "\n"
  }()

  @Test
  func aStreamAppendBesideAnOutboxWrite() async throws {
    let settings = StorageIOExerciseSettings(
      stepLines: 40,
      recordingLines: 2_000,
      pageLines: 256,
      minutes: 1,
      linesPerMinute: 15,
      fixtureScale: 1
    )
    StorageIOCounters.install(asDefault: true)
    let run = try StorageIORun(label: "stream-1442")
    defer { run.remove() }
    var cycle = try await StorageIOWriteCycle.make(label: "stream-1442", directory: run.directory, settings: settings)
    let store = cycle.configuration.persistenceURL
    let warmup = StorageIOLedger()
    for _ in 0..<2 { try await cycle.writeLine(into: warmup) }

    let ledger = StorageIOLedger()
    for _ in 1...settings.stepLines { try await cycle.writeLine(into: ledger) }
    let writes = ledger.count(.save)
    var settingsLine = StorageIOLine("cost1442", "settings")
    settingsLine.add("writes", writes)
    settingsLine.add("recordingLines", settings.recordingLines)
    settingsLine.add("chunkBytes", Self.chunk.utf8.count)
    settingsLine.print()
    for step in StorageIOStep.allCases where ledger.count(step) > 0 {
      var line = StorageIOLine("cost1442-outbox", step.rawValue)
      line.add("count", ledger.count(step))
      line.add(io: ledger.io(step), per: writes)
      line.add("cpuMs", Double(ledger.cpuNanoseconds(step)) / 1_000_000 / Double(max(1, writes)), digits: 2)
      line.print()
    }

    _ = try await cycle.runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let metadata = try await cycle.runtime.createStream(clientID: "scribe-live-lines-1442")
    var offset: Int64 = 0
    func append(_ count: Int) async throws {
      for _ in 0..<count {
        let appended = try await cycle.runtime.appendStreamContent(
          streamID: metadata.id,
          content: Self.chunk,
          expectedOffset: offset
        )
        offset += appended.chunk.byteCount
      }
    }
    try await append(50)
    try StorageIOStoreFile.checkpoint(store)

    let appends = 600
    let started = StorageIOProbe.start()
    try await append(appends)
    let measured = started.stop()
    var line = StorageIOLine("cost1442-stream", "append")
    line.add("count", appends)
    line.add(io: measured.io, per: appends)
    line.add("cpuMs", Double(measured.process.cpuNanoseconds) / 1_000_000 / Double(appends), digits: 2)
    line.add("processLogicalWriteKB", Double(measured.process.logicalWriteBytes) / 1_024 / Double(appends))
    line.print()

    let map = try StorageIOPageMap.read(store: store)
    let frames = map.byName(measured.io.walFramesByPage)
    for (name, count) in frames.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(12) {
      var line = StorageIOLine("cost1442-stream-btrees", "append")
      line.add("btree", name)
      line.add("framesPerAppend", Double(count) / Double(appends), digits: 2)
      line.print()
    }
    for step in StorageIOStep.allCases where ledger.count(step) > 0 {
      let frames = map.byName(ledger.io(step).walFramesByPage)
      for (name, count) in frames.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(8) {
        var line = StorageIOLine("cost1442-outbox-btrees", step.rawValue)
        line.add("btree", name)
        line.add("framesPerWrite", Double(count) / Double(max(1, writes)), digits: 2)
        line.print()
      }
    }
    _ = try? await cycle.runtime.closeConnection()
  }
}
