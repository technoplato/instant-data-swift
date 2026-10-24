import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1072 (2026-10-24): the whole-store cost audit's report run. Every hot-path operation, metered on the generated
// store at a quarter of the phone's size and at its full size (and on a copy of a phone's own store when
// `INSTANT_REAL_SIZE_STORE` names one): the same change at both sizes should cost the same, so a row whose cost grows
// four-fold with the store is the audit's defect. One `REALSIZE` line per operation and size; the audit table in
// docs/audits/2026-10-24-whole-store-cost-audit.md is read from these lines.
//
// `INSTANT_REAL_SIZE_REPORT=1` runs it (minutes, release); `INSTANT_REAL_SIZE_REPORT_SCALES=0.25,1` picks the sizes,
// `INSTANT_REAL_SIZE_REPORT_ONLY=transact,prune` some operations. The smoke test below runs always: a tiny shape, so
// the fixture and the meter cannot rot.
//
// History:
// - 2026-10-24: #1072: the report and the smoke test.
// - 2026-10-24: #1072: progress lines on standard error, a deadline on every emission wait (the first full run hung on
//   one), a failed operation no longer ends the report, `INSTANT_REAL_SIZE_PROFILE_SECONDS` for a profiler, and the
//   calls Scribe makes at launch and on refusals (local reads, evictions, the failed list, discards).
// - 2026-10-24: #1072: a recording's minutes at the phone's size (`RealSizeRecordingReport`): CPU, bytes written, the
//   gate's holds and the footprint's peak per minute, for minutes 5, 60 and 120 before and after a change.

@Suite(.serialized)
struct RealSizeFixtureSmokeTests {
  @Test func aTinyFixtureGeneratesOpensAndMeters() async throws {
    let shape = RealSizeShape.phone.scaled(0.01)
    let session = try await RealSizeFixture.open(shape, label: "smoke")
    try await session.closing {
      let counts = try RealSizeStoreCounts(session.configuration.persistenceURL)
      #expect(counts.facts > 0)
      #expect(counts.attributes >= RealSizeAccount.scribeAttributeCount)
      #expect(counts.fileRecords == shape.deviceFileRecords)
      #expect((counts.outbox["failed"] ?? 0) == shape.refusedWrites)
      // The server's answers passed every accepted write's transaction, so none waits in the outbox: a phone's held 4
      // beside its 663 refused ones. Text transaction ids once left every accepted write there.
      #expect((counts.outbox["confirmed"] ?? 0) == 0)
      #expect(counts.unloadedResults > 0)
      print("REALSIZE-FIXTURE smoke counts: \(counts)")

      let recordingID = RealSizeID.make(.recording, 0)
      let write = try await RealSizeMeter.measure("transact", label: "smoke", iterations: 3, gate: session.gate) { index in
        try await session.runtime.transact(
          session.segmentWrite(recordingID: recordingID, line: 10_000 + index, revision: 0, id: RealSizeID.make(.write, index))
        )
      }
      #expect(write.allocations > 0)
      #expect(write.medianWall > .zero)
      #expect((write.gate?.acquisitions ?? 0) > 0)
      print(write.line)
    }
  }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["INSTANT_REAL_SIZE_REPORT"] != nil))
struct RealSizeReport {
  @Test func everyOperationAtTwoSizes() async throws {
    let environment = ProcessInfo.processInfo.environment
    let scales = (environment["INSTANT_REAL_SIZE_REPORT_SCALES"] ?? "0.25,1").split(separator: ",").compactMap { Double($0) }
    let only = environment["INSTANT_REAL_SIZE_REPORT_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
    for scale in scales {
      let shape = scale == 1 ? RealSizeShape.phone : RealSizeShape.phone.scaled(scale)
      let label = environment["INSTANT_REAL_SIZE_STORE"] != nil && scale == 1 ? "phone-copy" : "x\(scale)"
      try await RealSizeOperations.report(shape, label: label, only: only)
    }
  }
}

/// A recording's minutes on the phone-sized store, as the consuming app records: each minute 15 transcript lines written
/// 5 times each (interims, then the final), every write answered by the server's refresh of the live window (the newest
/// 64 lines, as the app observes it), 11 uploads (a 60 s audio chunk and ten 6 s media segments), and one session prune.
/// One `REALSIZE-MINUTE` line per minute: the minute's process CPU, wall time and bytes written, the operation gate's
/// longest hold and whole hold, and the footprint with the minute's peak; `REALSIZE-RECORDING` repeats the lines of
/// minutes 5, 60 and 120 at the end.
///
/// `INSTANT_REAL_SIZE_RECORDING_MINUTES=120` runs it (minutes, release); `INSTANT_REAL_SIZE_RECORDING_LABEL` names the run.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["INSTANT_REAL_SIZE_RECORDING_MINUTES"] != nil))
struct RealSizeRecordingReport {
  @Test func recordingMinutesAtThePhonesSize() async throws {
    let environment = ProcessInfo.processInfo.environment
    let minutes = environment["INSTANT_REAL_SIZE_RECORDING_MINUTES"].flatMap(Int.init) ?? 120
    let label = environment["INSTANT_REAL_SIZE_RECORDING_LABEL"] ?? "recording"
    let session = try await RealSizeFixture.open(.phone, label: "recording-\(label)")
    try await session.closing {
      let runtime = session.runtime
      let server = session.server
      let recording = session.newRecording(80_000)
      try await runtime.transact(recording.write)
      let window = InstantQueryPlan(
        id: "real-size-live-window",
        namespace: "transcriptionSegments",
        filters: [.equals(field: "recordingID", value: .string(recording.id))],
        order: InstantQueryOrder("segmentIndex", .descending),
        limit: 64
      )
      let added = await server.addQueries
      let lease = await runtime.observeQueryLease(window)
      let windowQuery = try await server.nextAddQuery(after: added)
      let scratch = session.directory.appendingPathComponent("segment.m4s")
      try Data(repeating: 3, count: 16_384).write(to: scratch)
      var lines: [RealSizeEntity] = []
      var kept: [Int: String] = [:]
      for minute in 1...minutes {
        RealSizeProcess.resetFootprintPeak()
        session.gate.begin()
        let before = RealSizeProcess.usage()
        let started = ContinuousClock.now
        for lineInMinute in 0..<15 {
          let line = (minute - 1) * 15 + lineInMinute
          let id = RealSizeID.make(.write, 300_000 + line)
          for revision in 0..<5 {
            try await runtime.transact(
              session.segmentWrite(recordingID: recording.id, line: line, revision: revision, id: id)
            )
            let entity = RealSizeAccount.segment(recordingID: recording.id, line: line, revision: revision, serial: 0, id: id)
            if revision == 0 { lines.append(entity) } else { lines[lines.count - 1] = entity }
            let tx = await server.refresh(windowQuery, rows: lines.suffix(64).reversed().map { $0.joinRow() })
            _ = try await session.applies.wait(for: tx)
          }
          // The minute's uploads: ten media segments and the audio chunk, one after each of its first 11 lines.
          if lineInMinute < 11 {
            _ = try await runtime.uploadFile(
              from: scratch, name: "scribe/\(recording.id)/media/\(minute)-\(lineInMinute).m4s", contentType: "audio/mp4"
            )
          }
        }
        _ = try await runtime.pruneLiveQueryResults(
          policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now()
        )
        let wall = ContinuousClock.now - started
        let after = RealSizeProcess.usage()
        let gate = session.gate.end()
        func ms(_ duration: Duration) -> String {
          String(format: "%.1f", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
        }
        let report = "REALSIZE-MINUTE \(label) minute=\(minute) lines=\(lines.count)"
          + " cpuMs=\(String(format: "%.1f", Double(after.cpuNanoseconds - before.cpuNanoseconds) / 1e6))"
          + " wallMs=\(ms(wall)) writtenKB=\((after.logicalWriteBytes - before.logicalWriteBytes) / 1_024)"
          + " gateHoldMaxMs=\(ms(gate.longestHold)) gateHolder=\(gate.longestHolder.replacingOccurrences(of: " ", with: "_"))"
          + " gateHoldTotalMs=\(ms(gate.totalHold))"
          + " gateTop=\(gate.topHolders(3).map { "\($0.holder.replacingOccurrences(of: " ", with: "_")):\(ms($0.hold))" }.joined(separator: ","))"
          + " uploadGateMs=\(ms(gate.holdByHolder["savePreparedStoredFile(_:contentsOf:)"] ?? .zero))"
          + " footprintMB=\(after.footprint / 1_048_576)"
          + " footprintPeakMB=\(max(after.footprintIntervalPeak, after.footprint) / 1_048_576)"
        RealSizeOperations.line(report)
        if [5, 60, 120, minutes].contains(minute) { kept[minute] = report }
      }
      for minute in kept.keys.sorted() { RealSizeOperations.line("REALSIZE-RECORDING \(kept[minute]!)") }
      await lease.cancel()
    }
  }
}

/// The metered operations: each opens what it needs on one session and prints one line.
enum RealSizeOperations {
  /// A progress line, written at once to standard error. Standard output reaches a pipe in blocks, so the first report
  /// run, which hung 33 s in, showed nothing of where it stopped; these lines do.
  static func progress(_ message: String) {
    FileHandle.standardError.write(Data("REALSIZE-PROGRESS \(Date().formatted(.iso8601)) \(message)\n".utf8))
  }

  /// A report line, written at once to standard output (`print` buffers it until the process exits).
  static func line(_ text: String) {
    FileHandle.standardOutput.write(Data((text + "\n").utf8))
  }

  /// The first emission of `stream` that `condition` accepts, or an error after `timeout` that says what the stream
  /// emitted last, so a step that waits for an emission fails instead of hanging the run. A timeout cancels the task
  /// that reads `stream`, which finishes the stream: the caller's lease is spent.
  static func firstEmission(
    of stream: AsyncStream<InstantQueryEmission>,
    step: String,
    timeout: Duration = .seconds(30),
    where condition: @escaping @Sendable (InstantQueryEmission) -> Bool = { _ in true }
  ) async throws -> InstantQueryEmission {
    let seen = RealSizeSeenEmissions()
    let found = try await withThrowingTaskGroup(of: InstantQueryEmission?.self) { group in
      group.addTask {
        for await emission in stream {
          seen.record(emission)
          if condition(emission) { return emission }
        }
        seen.finished()
        return nil
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        return nil
      }
      defer { group.cancelAll() }
      return try await group.next() ?? nil
    }
    guard let found else {
      throw InstantError(
        code: .implementationFailed, operation: "wait for a real-size emission",
        message: "\(step): no emission matched within \(timeout); \(seen.summary).",
        recovery: "Check what the observed plan holds after the step's change."
      )
    }
    return found
  }

  static func report(_ shape: RealSizeShape, label: String, only: Set<String>?) async throws {
    func wanted(_ name: String) -> Bool { only?.contains(name) ?? true }
    func emit(_ measurement: RealSizeMeasurement) { line(measurement.line) }
    progress("\(label) shape \(shape)")

    // Launch: a fresh copy of the store for every boot, copied before the clock starts.
    if wanted("launch") {
      progress("\(label) launch starts")
      let source = try await RealSizeFixture.store(shape)
      let account = RealSizeAccount(shape)
      var copies: [URL] = []
      for _ in 0..<4 {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("real-size-launch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try RealSizeFixture.copyStore(from: source, to: directory.appendingPathComponent("cache.sqlite"))
        copies.append(directory)
      }
      defer { for directory in copies { try? FileManager.default.removeItem(at: directory) } }
      emit(
        try await RealSizeMeter.measure("launch", label: label, iterations: 1, warmup: 0) { index in
          let directory = copies[index]
          let session = try await RealSizeFixture.boot(
            shape: shape, account: account, storeURL: directory.appendingPathComponent("cache.sqlite"),
            directory: directory, removesDirectory: false, onFrame: nil, configure: { _ in }
          )
          await session.close()
        }
      )
    }

    progress("\(label) session opens")
    let session = try await RealSizeFixture.open(shape, label: "report-\(label)")
    try await session.closing {
      try await operations(on: session, label: label, wanted: wanted, skipping: [], emit: emit)
    }
    progress("\(label) done")
  }

  /// Meters every operation of the groups `wanted` names on `session`, except the ones `skipping` names, and hands
  /// each measurement to `emit`: the report prints them, the budgets (`RealSizeBudgetTests`) hold them.
  static func operations(
    on session: RealSizeSession,
    label: String,
    wanted: (String) -> Bool,
    skipping: Set<String>,
    emit: (RealSizeMeasurement) -> Void
  ) async throws {
    let runtime = session.runtime
    let server = session.server
    let profileSeconds = ProcessInfo.processInfo.environment["INSTANT_REAL_SIZE_PROFILE_SECONDS"].flatMap(Double.init)
    // Meters one operation and prints its line. Every measurement reads the operation gate's timeline: the longest
    // hold, its holder, the longest wait. A failure prints a `failed=` line and the report goes on to the next one.
    // With `INSTANT_REAL_SIZE_PROFILE_SECONDS`, the operation first repeats that long, so a profiler can attach.
    func meter(
      _ operation: String, iterations: Int, warmup: Int, prepare: ((Int) async throws -> Void)? = nil,
      _ body: (Int) async throws -> Void
    ) async {
      guard !skipping.contains(operation) else { return }
      progress("\(label) \(operation) starts")
      do {
        if let profileSeconds {
          progress("\(label) \(operation) repeats for \(profileSeconds) s in pid \(getpid())")
          let until = ContinuousClock.now + .seconds(profileSeconds)
          var index = 1_000_000
          while ContinuousClock.now < until {
            try await prepare?(index)
            try await body(index)
            index += 1
          }
        }
        emit(
          try await RealSizeMeter.measure(
            operation, label: label, iterations: iterations, warmup: warmup, gate: session.gate, prepare: prepare, body
          )
        )
      } catch {
        let reason = String(describing: error).replacingOccurrences(of: "\n", with: " ")
        line("REALSIZE \(label) op=\(operation) failed=\(reason.replacingOccurrences(of: " ", with: "_"))")
        progress("\(label) \(operation) failed: \(reason)")
      }
    }

    // Lets the work earlier steps left running end before the next group: an outbox pump pass after a write's
    // acknowledgement, counted process-wide, lands in whatever is measured next.
    func settle() async throws {
      try await RealSizeGenerator.waitForSettledOutbox(runtime)
      try await Task.sleep(for: .milliseconds(50))
    }

    // The recording: a new recording's live transcript page, as Scribe holds it open while recording.
    let recording = session.newRecording(90_000)
    try await runtime.transact(recording.write)
    let page = session.transcriptPage(recordingID: recording.id)
    let added = await server.addQueries
    let pageLease = await runtime.observeQueryLease(page)
    let pageQuery = try await server.nextAddQuery(after: added)
    var lines: [RealSizeEntity] = []
    func writeLine(_ index: Int, revision: Int) -> InstantStoreTransaction {
      let id = RealSizeID.make(.write, 100_000 + index / 5)
      return session.segmentWrite(recordingID: recording.id, line: index / 5, revision: revision, id: id)
    }

    // The lines the server's refreshes of the page hold.
    for index in 0..<128 {
      lines.append(
        RealSizeAccount.segment(recordingID: recording.id, line: index, revision: 4, serial: 0, id: RealSizeID.make(.write, 200_000 + index))
      )
    }

    if wanted("transact") {
      await meter("transact", iterations: 25, warmup: 5) { index in
        try await runtime.transact(writeLine(index, revision: index % 5))
      }
    }
    try await RealSizeGenerator.waitForSettledOutbox(runtime)

    // The server's echo: the page's refresh with every line the recording has, the newest changed.
    if wanted("server-apply") {
      await meter("server-apply.refresh-128", iterations: 10, warmup: 2) { index in
        lines[index % lines.count] = RealSizeAccount.segment(
          recordingID: recording.id, line: index % lines.count, revision: index % 5, serial: 0,
          id: lines[index % lines.count].id
        )
        let tx = await server.refresh(pageQuery, rows: lines.map { $0.joinRow() })
        _ = try await session.applies.wait(for: tx)
      }
    }

    if wanted("prune") {
      await meter("prune", iterations: 5, warmup: 1) { _ in
        _ = try await runtime.pruneLiveQueryResults(
          policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now()
        )
      }
      // A prune of the one result a closed 32-line page left (a one-shot query, uncounted): it should cost that
      // result's facts at every size, not the store's (#654).
      await meter(
        "prune.one-closed-page", iterations: 5, warmup: 1,
        prepare: { index in
          var closed = session.transcriptPage(recordingID: RealSizeID.make(.recording, 3 + index % 7))
          closed.id = "real-size-closed-page-\(index)"
          closed.limit = 32
          _ = try await runtime.queryOnce(closed)
        }
      ) { _ in
        _ = try await runtime.pruneLiveQueryResults(
          policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now()
        )
      }
    }

    if wanted("query") {
      let other = session.transcriptPage(recordingID: RealSizeID.make(.recording, 1))
      await meter("queryOnce.transcript-page", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.queryOnce(other)
      }
      // The local reader's answer to the same page (#1006): no server, no gate.
      await meter("queryLocally.transcript-page", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.queryLocally(other)
      }
      // The same 32 rows at every size: a cost that differs between sizes grows with the store, not the answer.
      var first32 = other
      first32.id = "real-size-first-32"
      first32.limit = 32
      await meter("queryOnce.first-32", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.queryOnce(first32)
      }
      // The local reader re-ranks every line of the recording on disk (#1072's audit), so its scale check reads the
      // session's own recording, which has the same lines at every size.
      var ownFirst32 = page
      ownFirst32.id = "real-size-own-first-32"
      ownFirst32.limit = 32
      await meter("queryLocally.first-32", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.queryLocally(ownFirst32)
      }
    }

    if wanted("observe") {
      let other = session.transcriptPage(recordingID: RealSizeID.make(.recording, 2))
      await meter("observe.first-emission", iterations: 10, warmup: 2) { _ in
        let lease = await runtime.observeQueryLease(other)
        _ = try await firstEmission(of: lease.stream, step: "observe.first-emission")
        await lease.cancel()
      }
      // The same 32 rows at every size, for the scale check.
      var other32 = other
      other32.id = "real-size-observe-32"
      other32.limit = 32
      await meter("observe.first-emission-32", iterations: 10, warmup: 2) { _ in
        let lease = await runtime.observeQueryLease(other32)
        _ = try await firstEmission(of: lease.stream, step: "observe.first-emission-32")
        await lease.cancel()
      }
      // A line the page shows, written again with a new revision each time, so the page's emission that holds that
      // revision is the one this write caused (the stream keeps only its newest emission). A new line past the
      // server's page end stays out of the page until the server's next refresh adds it (a page is bounded by its
      // cursors, as upstream's), so the first report waited on one for good.
      if !wanted("server-apply") {
        _ = try await session.applies.wait(for: await server.refresh(pageQuery, rows: lines.map { $0.joinRow() }))
      }
      await meter("observe.emission-after-write", iterations: 10, warmup: 2) { index in
        let line = index % lines.count
        let revision = 10 + index % 1_000
        try await runtime.transact(
          session.segmentWrite(recordingID: recording.id, line: line, revision: revision, id: lines[line].id)
        )
        let lineID = lines[line].id
        let wordCount = InstantValue.number(Double(6 + 2 * revision))
        _ = try await firstEmission(of: pageLease.stream, step: "observe.emission-after-write") { emission in
          emission.values.contains { $0.id == lineID && $0.values["wordCount"]?.first == wordCount }
        }
      }
    }

    if wanted("files") {
      try await settle()
      let local = (try await runtime.persistence.loadStoredFiles(appID: RealSizeAccount.appID)).first
      let scratch = session.directory.appendingPathComponent("upload.wav")
      try Data(repeating: 1, count: 16_384).write(to: scratch)
      await meter("uploadFile", iterations: 10, warmup: 2) { index in
        _ = try await runtime.uploadFile(from: scratch, name: "scribe/new/chunk-\(index).wav", contentType: "audio/wav")
      }
      await meter("localStoredFiles", iterations: 5, warmup: 1) { _ in
        _ = try await runtime.localStoredFiles()
      }
      await meter("storageSnapshot", iterations: 5, warmup: 1) { _ in
        _ = try await runtime.storageSnapshot()
      }
      if let local {
        await meter("downloadStoredFile.by-id-with-record", iterations: 5, warmup: 1) { index in
          _ = try await runtime.downloadStoredFile(
            id: local.id, to: session.directory.appendingPathComponent("download-\(index)")
          )
        }
      }
      if let remote = (session.account.entities["$files"] ?? []).last {
        await meter("downloadStoredFile.by-id-without-record", iterations: 5, warmup: 1) { index in
          _ = try? await runtime.downloadStoredFile(
            id: remote.id, to: session.directory.appendingPathComponent("remote-\(index)")
          )
        }
      }
      await meter("deleteStoredFile.uploaded", iterations: 5, warmup: 1) { index in
        let file = try await runtime.uploadFile(from: scratch, name: "scribe/delete/\(index).wav", contentType: "audio/wav")
        _ = try await runtime.deleteStoredFile(id: file.id)
      }
      // Scribe's launch cleanup evicts held copies 200 ids at a time.
      let batch = Array((try await runtime.persistence.loadStoredFiles(appID: RealSizeAccount.appID)).prefix(200).map(\.id))
      await meter("evictStoredFiles.200", iterations: 3, warmup: 1) { _ in
        _ = try? await runtime.evictStoredFiles(ids: batch)
      }
    }

    if wanted("outbox") {
      try await settle()
      await meter("pendingMutationCount", iterations: 20, warmup: 2) { _ in
        _ = await runtime.pendingMutationCount()
      }
      await meter("pendingMutations(limit:50)", iterations: 10, warmup: 2) { _ in
        _ = await runtime.pendingMutations(limit: 50)
      }
      await meter("pendingMutations", iterations: 3, warmup: 1) { _ in
        _ = await runtime.pendingMutations()
      }
      await meter("failedMutations(limit:50)", iterations: 10, warmup: 2) { _ in
        _ = await runtime.failedMutations(limit: 50)
      }
      // Scribe's sync status reads these two on every refused write and server error.
      await meter("failedMutations(limit:500)", iterations: 5, warmup: 1) { _ in
        _ = await runtime.failedMutations(limit: 500)
      }
      await meter("failedMutationSupersessions", iterations: 3, warmup: 1) { _ in
        _ = try await runtime.failedMutationSupersessions()
      }
      await meter("failedMutations", iterations: 3, warmup: 1) { _ in
        _ = await runtime.failedMutations()
      }
      await meter("quarantinedMutationCount", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.quarantinedMutationCount()
      }
      // Scribe's recovery pass discards up to 32 refused writes at each launch and return to the foreground.
      let refused = await runtime.failedMutations(limit: 8).map(\.id)
      await meter("discardFailedMutation", iterations: min(3, max(1, refused.count - 1)), warmup: refused.count > 1 ? 1 : 0) { index in
        guard index < refused.count else { return }
        _ = try await runtime.discardFailedMutation(id: refused[index])
      }
    }

    if wanted("status") {
      try await settle()
      await meter("connectionStatus", iterations: 20, warmup: 2) { _ in
        _ = try await runtime.connectionStatus()
      }
      await meter("syncState", iterations: 10, warmup: 2) { _ in
        _ = try await runtime.syncState()
      }
      await meter("cachedQueries", iterations: 5, warmup: 1) { _ in
        _ = try await runtime.cachedQueries()
      }
    }

    if wanted("refused-write") {
      await server.setWriteAnswer(.refuse)
      // Waits on the pending count (one indexed COUNT a poll): polling the failed list would meter that list's reads.
      await meter("refused-write", iterations: 5, warmup: 1) { index in
        try await runtime.transact(writeLine(5_000 + index * 5, revision: 2))
        try await RealSizeGenerator.waitForSettledOutbox(runtime, timeout: .seconds(60))
      }
      await server.setWriteAnswer(.accept)
    }

    if wanted("compact") {
      await meter("compactLocalCache", iterations: 1, warmup: 0) { _ in
        _ = try await runtime.compactLocalCache()
      }
    }

    // Last: the whole \$files list loads every file the account holds into the store, which every later step would pay
    // for (a discard measured after it held the gate 1.7 s, against 112 ms on the store as launched).
    if wanted("files-lists") {
      try await settle()
      await meter("storedFiles", iterations: 3, warmup: 1) { _ in
        _ = try await runtime.storedFiles()
      }
      await meter("observeStoredFiles.first-emission", iterations: 3, warmup: 1) { _ in
        let stream = try await runtime.observeStoredFiles()
        for await _ in stream { break }
      }
    }
    await pageLease.cancel()
  }
}

/// What a waiting step's stream emitted, for its timeout's message.
private final class RealSizeSeenEmissions: @unchecked Sendable {
  // SAFETY: `lock` guards every stored property.
  private let lock = NSLock()
  private var count = 0
  private var newest = "none"
  private var didFinish = false

  func record(_ emission: InstantQueryEmission) {
    let newest = "sequence \(emission.sequence) with \(emission.values.count) rows"
    lock.withLock {
      count += 1
      self.newest = newest
    }
  }

  func finished() { lock.withLock { didFinish = true } }

  var summary: String {
    lock.withLock { "\(count) emissions seen, the newest \(newest)\(didFinish ? ", then the stream finished" : "")" }
  }
}
