// Research for #1442, kept on its own branch and never on main: what one stream append costs the disk beside one
// outbox write, on the same store, measured by the storage audit's own counters (#1076).

import Darwin
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

  /// What a reader of a growing stream costs: `observeStreamContent` delivers everything from its byte offset so far,
  /// so an hour of appends grows every delivery. No server: the writer's own observation, the shape every reader has.
  @Test
  func aReaderHoldsTheWholeStream() async throws {
    let run = try StorageIORun(label: "stream-reader-1442")
    defer { run.remove() }
    let configuration = InstantRuntimeConfiguration(
      appID: "stream-reader-1442",
      persistenceURL: run.directory.appendingPathComponent("store.sqlite"),
      initialAttributes: []
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let metadata = try await runtime.createStream(clientID: "reader-1442")
    let delivered = LockIsolatedCounters()
    let reads = try await runtime.observeStreamContent(streamID: metadata.id)
    let reader = Task {
      for await read in reads {
        delivered.add(reads: 1, bytes: read.content.utf8.count)
        await Task.yield()
      }
    }
    var offset: Int64 = 0
    let startedAt = ContinuousClock.now
    var lastAt = startedAt
    func footprintMB() -> Double {
      var info = rusage_info_v4()
      let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
          proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
      }
      return result == 0 ? Double(info.ri_phys_footprint) / 1_048_576 : -1
    }
    for tick in 1...3_600 {
      let appended = try await runtime.appendStreamContent(
        streamID: metadata.id,
        content: Self.chunk,
        expectedOffset: offset
      )
      offset += appended.chunk.byteCount
      if tick % 600 == 0 {
        try await Task.sleep(for: .milliseconds(50))
        let now = ContinuousClock.now
        let (reads, bytes) = delivered.value
        var line = StorageIOLine("cost1442-reader", "tick\(tick)")
        line.add("streamMB", Double(offset) / 1_048_576, digits: 2)
        line.add("reads", reads)
        line.add("deliveredMB", Double(bytes) / 1_048_576, digits: 1)
        line.add("footprintMB", footprintMB(), digits: 1)
        line.add("msPerAppend", Double((now - lastAt).components.seconds) * 1_000 / 600 + Double((now - lastAt).components.attoseconds) / 1e15 / 600, digits: 2)
        line.print()
        lastAt = now
      }
    }
    reader.cancel()
    _ = try? await runtime.closeConnection()
  }
}

/// Counts a reader's deliveries from its task.
final class LockIsolatedCounters: @unchecked Sendable {
  private let lock = NSLock()
  private var reads = 0
  private var bytes = 0
  func add(reads: Int, bytes: Int) {
    lock.withLock {
      self.reads += reads
      self.bytes += bytes
    }
  }
  var value: (Int, Int) { lock.withLock { (reads, bytes) } }
}
