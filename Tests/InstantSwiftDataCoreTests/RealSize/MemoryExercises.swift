import Darwin
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

// #1075 (2026-10-24): the memory audit's exercises, one per hot path it found Scribe running while it records, each
// at the phone's real size (#1072's generated store, or a copy of a phone's own store through `INSTANT_REAL_SIZE_STORE`).
// Each prints one `MEMORY` line per measurement in a stable form, so the same exercise measures a fix later:
//
//     MEMORY <exercise> <label> n=… allocations=… allocatedKB=… frees=… retainedKB=… peakLiveKB=… footprintPeakMB=… …
//
// Per operation (a metered operation divides by its iterations): `allocations` and `allocatedKB` (heap allocations and
// the bytes they asked for, from libmalloc's logger hook), `retainedKB` (heap bytes still held after the counted pass,
// per iteration, from the zones' bytes in use: growth that stays), `peakLiveKB` (the highest the pass's live heap
// bytes rose above its start: the transient high-water mark, for the whole pass), `footprintPeakMB` (the process's
// `phys_footprint` high-water mark). Allocation counts barely move with the host's load, so they compare across runs
// and machines; wall time is printed for context only.
//
// The sessions run with Scribe's configuration of the library: transcript text and words deferred to disk until a
// selected page hydrates them, a local lookup index of a recording's lines, and the diagnostics floor at `.debug` with
// one handler (the apply waiter's; Scribe runs `.info` with five, which E09 prices).
//
// The counts are process-wide (the runtime works on actor executors and the cooperative pool, not the caller's
// thread), so the suite runs serialized and alone: `INSTANT_MEMORY_EXERCISES=1`, release, filtered to `MemoryExercises`
// (scripts/memory-exercises/run-memory-exercises.sh). `INSTANT_MEMORY_EXERCISES_SCALE` sizes the store against the
// phone's (default 1).
//
// History:
// - 2026-10-24: #1075: the first exercises and their baseline (docs/audits/2026-10-24-memory-audit.md).
// - 2026-10-24: #1147: each line's entity is built before the counted passes, and the waits park on the apply waiter
//   instead of polling, so a pass counts the library's work and as little of the harness's as it can (the polling was
//   under 1% of E03's refresh in the allocation-site recording, `MemorySiteExercises`).
// - 2026-10-25: #1148: E09 stops the session's apply log, a diagnostics handler, so its "no sink" pass has none.
// - 2026-10-25: #1150: E14 holds a per-page budget, tightened as each step of the fix lands.
// - 2026-10-25: #1147: E03 holds a budget for Scribe's 64-line window, tightened as each step lands.

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["INSTANT_MEMORY_EXERCISES"] != nil))
struct MemoryExercises {
  static var shape: RealSizeShape {
    let scale = ProcessInfo.processInfo.environment["INSTANT_MEMORY_EXERCISES_SCALE"].flatMap(Double.init) ?? 1
    return scale == 1 ? .phone : .phone.scaled(scale)
  }

  static var label: String {
    if isPhoneCopy { return "phone-copy" }
    return shape == .phone ? "phone" : "scaled"
  }

  /// A copy of a phone's own store stands in for the generated one (`INSTANT_REAL_SIZE_STORE`): its schema is the
  /// app's, so a session keeps the stored attributes instead of declaring the generated account's.
  static var isPhoneCopy: Bool {
    ProcessInfo.processInfo.environment["INSTANT_REAL_SIZE_STORE"] != nil && shape == .phone
  }

  /// The account's longest recording (2,318 lines on the phone) and its line count.
  static var longestRecording: (id: String, lines: Int) {
    (RealSizeID.make(.recording, 0), shape.transcriptLines.first ?? 0)
  }

  /// E00: the harness's own cost inside a counted pass, to subtract: one wait for the server's acknowledgment when
  /// nothing is pending (E04 and E09 wait after every write), and one wait for an emission already buffered (E05, E10).
  @Test func e00Harness() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e00", waitsForApplies: false).closing { context in
      let measurement = try await RealSizeMeter.measure("ack-wait", label: Self.label, iterations: 50, warmup: 5) { _ in
        try await MemoryExerciseSession.waitUntilAcknowledged(context.runtime)
      }
      MemoryReport.print("E00.harness.ack-wait-idle", measurement, label: Self.label)
    }
    let buffered = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let measurement = try await RealSizeMeter.measure("emission-wait", label: Self.label, iterations: 50, warmup: 5) { index in
      buffered.continuation.yield(index)
      _ = try await MemoryStreams.first(buffered.stream, "a buffered element") { $0 == index }
    }
    MemoryReport.print("E00.harness.emission-wait-buffered", measurement, label: Self.label)
  }

  /// E01: a server answer frame decoded whole. The account's whole `$files` list (9,455 files, about 75,640 facts) as
  /// one `add-query-ok`, the frame an older build decoded whole (27 MB), and a transcript page's `refresh-ok` at 64
  /// lines (Scribe's live window) and 256 (a history page).
  @Test func e01DecodeWholeAnswerFrames() async throws {
    let account = RealSizeAccount(Self.shape)
    let query = InstantLiveJSONValue.object(["$files": .object(["$": .object([:])])])
    let files = (account.entities["$files"] ?? []).map { $0.joinRow() }
    var frames = [("files-answer", MemoryReplayServer.encoded(MemoryReplayServer.addQueryOKFrame(query, rows: files, tx: "e01-files")), files.count)]
    for rows in [64, 256] {
      let lines = (account.entities["transcriptionSegments"] ?? []).prefix(rows).map { $0.joinRow() }
      frames.append(("page-refresh-\(rows)", MemoryReplayServer.encoded(MemoryReplayServer.refreshFrame(query, rows: Array(lines), tx: "e01-page")), lines.count))
    }
    for (name, frame, rows) in frames {
      let measurement = try await RealSizeMeter.measure(name, label: Self.label, iterations: 3, warmup: 1) { _ in
        _ = try InstantLiveMessage.decoded(fromFrame: frame)
      }
      MemoryReport.print(
        "E01.decode.\(name)", measurement, label: Self.label,
        extra: [
          ("rows", String(rows)), ("frameKB", String(frame.utf8.count / 1_024)),
          ("allocationsPerRow", MemoryReport.ratio(measurement.allocations, rows)),
          ("peakOverFrame", MemoryReport.ratio(measurement.peakLiveBytes, frame.utf8.count)),
        ]
      )
    }
  }

  /// E02: the whole `$files` answer applied: the first observation of the account's file list, as an older build left
  /// it subscribed: decode, translate to facts, persist the result, emit. One-shot (the second observation finds the
  /// facts resident), then what stays after the lease ends and after a prune.
  @Test func e02ApplyWholeFilesAnswer() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e02").closing { context in
      let files = await context.session.server.filesRows()
      await context.server.prepareAnswer(namespace: "$files", rows: files)
      let plan = InstantQueryPlan(id: "real-size-files", namespace: "$files")
      let triplesBefore = await context.runtime.store.currentTripleCount()
      let writesBefore = await context.runtime.liveQueryResultJSONWriteStatsForTesting()

      var lease: InstantQueryObservationLease?
      var emitted = 0
      let first = try await MemoryOnce.measure {
        let observed = await context.runtime.observeQueryLease(plan)
        lease = observed
        emitted = try await MemoryStreams.first(observed.stream, within: .seconds(900), "e02: the whole $files answer") {
          $0.values.count >= files.count
        }.values.count
      }
      let triplesAfter = await context.runtime.store.currentTripleCount()
      let writesAfter = await context.runtime.liveQueryResultJSONWriteStatsForTesting()
      MemoryReport.print(
        "E02.apply.files-answer.first-observe", first, label: Self.label,
        extra: [
          ("rows", String(files.count)), ("emitted", String(emitted)),
          ("residentFactsAdded", String(triplesAfter - triplesBefore)),
          ("retainedPerFactB", MemoryReport.ratio(first.netLiveBytes, max(1, triplesAfter - triplesBefore))),
          ("resultJSONWrittenKB", String((writesAfter.bytes - writesBefore.bytes) / 1_024)),
        ]
      )

      let released = try await MemoryOnce.measure {
        await lease?.cancel()
        lease = nil
        _ = try await context.runtime.pruneLiveQueryResults(
          policy: context.session.configuration.liveQueryResultPruningPolicy, now: context.session.clock.now()
        )
      }
      MemoryReport.print(
        "E02.apply.files-answer.cancel-and-prune", released, label: Self.label,
        extra: [("residentFactsAfter", String(await context.runtime.store.currentTripleCount()))]
      )
    }
  }

  /// E03: a transcript page's `refresh-ok` applied at 32, 64, 128 and 256 lines: what each row of the page costs on
  /// every refresh, since the server sends the whole page after every write that touches it.
  @Test func e03ApplyPageRefreshPerRow() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e03").closing { context in
      let recordingID = RealSizeID.make(.write, 700_000)
      for rows in [32, 64, 128, 256] {
        let page = try await MemoryOpenPage.open(
          context, recordingID: recordingID, rows: rows, firstLine: rows * 1_000, idBase: 2_000_000 + rows * 1_000,
          id: "e03-page-\(rows)"
        )
        // Every iteration's frame is encoded before the counted pass, one line changed each time, as a refresh after a
        // write carries it.
        let iterations = 8
        let frames = await page.frames(count: 1 + 2 * iterations)
        let contexts = await context.runtime.liveRefreshAttributeContextBuildCountForTesting()
        let writes = await context.runtime.liveQueryResultJSONWriteStatsForTesting()
        let measurement = try await RealSizeMeter.measure("refresh-\(rows)", label: Self.label, iterations: iterations, warmup: 1) { index in
          await context.server.push(encoded: frames[index].frame)
          try await context.waitApplies.wait(for: frames[index].tx)
        }
        let contextsAfter = await context.runtime.liveRefreshAttributeContextBuildCountForTesting()
        let writesAfter = await context.runtime.liveQueryResultJSONWriteStatsForTesting()
        MemoryReport.print(
          "E03.apply.page-refresh-\(rows)", measurement, label: Self.label,
          extra: [
            ("rows", String(rows)), ("frameKB", String(frames[0].frame.utf8.count / 1_024)),
            ("allocationsPerRow", MemoryReport.ratio(measurement.allocations, rows)),
            ("allocatedPerRowB", MemoryReport.ratio(measurement.allocatedBytes, rows)),
            ("attributeContextBuilds", String(contextsAfter - contexts)),
            ("resultJSONWrites", String(writesAfter.writes - writes.writes)),
          ]
        )
        if rows == 64 {
          // #1147: Scribe's live window. 23,947 allocations and 22,769 KB a refresh on the Mac mini before #1147, 8,911 and
          // 10,691 KB once its steps 1-4 and #1150's column reader landed; the bound tightens with each step, toward the
          // issue's 5,000 allocations and 4 MB.
          #expect(measurement.allocations < 7_000, "E03 allocated \(measurement.allocations) times a 64-line refresh.")
          #expect(
            measurement.allocatedBytes < 8 * 1_024 * 1_024,
            "E03 allocated \(measurement.allocatedBytes / 1_024) KB a 64-line refresh."
          )
        }
        await page.close()
      }
    }
  }

  /// E04: Scribe's writes, end to end (materialize, outbox, frame, the server's `transact-ok`), and what each leaves
  /// behind: a finished line on a new recording and on the account's longest (its 2,318 lines linked to it, as the
  /// phone's longest links 2,364), the duration heartbeat (twelve a minute), and an interim of a line in progress.
  @Test func e04Writes() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e04").closing { context in
      let runtime = context.runtime
      let clock = context.session.clock
      let fresh = RealSizeAccount.recording(id: RealSizeID.make(.write, 800_000), index: 800_000)
      try await runtime.transact(MemoryScribeWrites.transaction { MemoryScribeWrites.update(fresh, at: clock.advance(), txID: $0) })
      let (longestID, _) = Self.longestRecording
      let longest = try #require(context.session.account.entities["recordings"]?.first { $0.id == longestID })
      let linked = try await MemoryScribeWrites.seedLinks(context, recordingID: longestID)
      let iterations = 200
      let warmup = 20

      for (name, recording, base, links) in [("final-line", fresh, 0, 0), ("final-line-long-recording", longest, 100_000, linked)] {
        // The lines in progress each final deletes, written beforehand.
        let lives = (0..<(warmup + 2 * iterations)).map { MemoryScribeWrites.liveLine(recordingID: recording.id, line: base + $0, words: 9, at: clock.now()) }
        // Fifteen rows a transaction: each is sixteen steps, and a write may expand to at most 256 (the outbox's
        // durable delivery limit).
        for chunk in stride(from: 0, to: lives.count, by: 15) {
          try await runtime.transact(MemoryScribeWrites.transaction { txID in
            lives[chunk..<min(lives.count, chunk + 15)].flatMap { MemoryScribeWrites.update($0, at: clock.advance(), txID: txID) }
          })
        }
        try await MemoryExerciseSession.settle(runtime)
        let energy = InstantEnergyMeter.snapshot()
        // Each line is built before the counted passes: generating a line's words is the harness's work (#1147). The
        // write itself is assembled in the pass, at its time.
        let lines = (0..<(warmup + 2 * iterations)).map { index in
          RealSizeAccount.segment(
            recordingID: recording.id, line: base + index, revision: 4, serial: 0, id: RealSizeID.make(.write, 810_000 + base + index)
          )
        }
        let measurement = try await RealSizeMeter.measure("transact.\(name)", label: Self.label, iterations: iterations, warmup: warmup) { index in
          try await runtime.transact(
            MemoryScribeWrites.finalLine(lines[index], recording: recording, liveLine: (lives[index].id, lives[index].namespace), at: clock.advance())
          )
          try await MemoryExerciseSession.waitUntilAcknowledged(runtime)
        }
        MemoryReport.print(
          "E04.transact.\(name)", measurement, label: Self.label,
          extra: [("linkedLinesBefore", String(links)), ("factsPerWrite", "19")]
            + MemoryEnergy.operations(since: energy, iterations: warmup + 2 * iterations)
        )
      }

      var energy = InstantEnergyMeter.snapshot()
      let heartbeat = try await RealSizeMeter.measure("transact.heartbeat", label: Self.label, iterations: iterations, warmup: warmup) { index in
        try await runtime.transact(MemoryScribeWrites.transaction { txID in
          let time = clock.advance()
          var recording = fresh
          recording.values["durationSeconds"] = .number(Double(index * 5))
          recording.values["updatedAtMs"] = .number(Double(time.milliseconds))
          return MemoryScribeWrites.updateExisting(recording, fields: ["durationSeconds", "updatedAtMs"], at: time, txID: txID)
        })
        try await MemoryExerciseSession.waitUntilAcknowledged(runtime)
      }
      MemoryReport.print(
        "E04.transact.heartbeat", heartbeat, label: Self.label,
        extra: [("factsPerWrite", "3")] + MemoryEnergy.operations(since: energy, iterations: warmup + 2 * iterations)
      )
      energy = InstantEnergyMeter.snapshot()

      // Two interims a line: the first writes the line in progress, the second rewrites it with more words.
      let interims = (0..<(warmup + 2 * iterations)).map { index in
        MemoryScribeWrites.liveLine(recordingID: fresh.id, line: 900_000 + index / 2, words: 3 + 6 * (index % 2), at: clock.now())
      }
      let interim = try await RealSizeMeter.measure("transact.interim", label: Self.label, iterations: iterations, warmup: warmup) { index in
        try await runtime.transact(MemoryScribeWrites.transaction { MemoryScribeWrites.update(interims[index], at: clock.advance(), txID: $0) })
        try await MemoryExerciseSession.waitUntilAcknowledged(runtime)
      }
      MemoryReport.print(
        "E04.transact.interim", interim, label: Self.label,
        extra: [("factsPerWrite", "16")] + MemoryEnergy.operations(since: energy, iterations: warmup + 2 * iterations)
      )
    }
  }

  /// E05: a new line on an open tail of the longest recording, newest first, at 64 lines (Scribe's live window) and
  /// 256, end to end as Scribe sees it: the local write, the server's acknowledgment, its refresh of the window with the
  /// new line first, and the emission that shows it. A limited window shows a new local line only once the server's
  /// refresh includes it (the exercise's first version waited for a local emission that never came).
  @Test func e05NewLineInWindow() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e05").closing { context in
      let (recordingID, lines) = Self.longestRecording
      let recording = try #require(context.session.account.entities["recordings"]?.first { $0.id == recordingID })
      let linked = try await MemoryScribeWrites.seedLinks(context, recordingID: recordingID)
      for rows in [64, 256] {
        let base = 100_000 + rows * 1_000
        let tail = try await MemoryTail.open(
          context, plan: MemoryExerciseSession.tailPlan(id: "e05-tail-\(rows)", recordingID: recordingID, rows: rows),
          expectedRows: min(rows, lines)
        )
        let iterations = 20
        let frames = await tail.frames(count: 3 + 2 * iterations) { index in
          RealSizeAccount.segment(
            recordingID: recordingID, line: base + index, revision: 4, serial: 0, id: RealSizeID.make(.write, 820_000 + base + index)
          )
        }
        let energy = InstantEnergyMeter.snapshot()
        let newLines = (0..<(3 + 2 * iterations)).map { index in
          RealSizeAccount.segment(recordingID: recordingID, line: base + index, revision: 4, serial: 0, id: frames[index].id)
        }
        let measurement = try await RealSizeMeter.measure("new-line-\(rows)", label: Self.label, iterations: iterations, warmup: 3) { index in
          try await tail.writeAndShow(
            frames[index], MemoryScribeWrites.finalLine(newLines[index], recording: recording, liveLine: nil, at: context.session.clock.advance())
          )
        }
        let publish = await context.runtime.store.lastPublishMetrics
        MemoryReport.print(
          "E05.window.new-line-\(rows)", measurement, label: Self.label,
          extra: [
            ("rows", String(tail.rows)), ("allocationsPerRow", MemoryReport.ratio(measurement.allocations, tail.rows)),
            ("linkedLinesBefore", String(linked)),
            ("lastRematerialized", String(publish.rematerializedObserverCount)),
            ("lastMaterializedSnapshots", String(publish.materializedSnapshotCount)),
          ] + MemoryEnergy.operations(since: energy, iterations: 3 + 2 * iterations)
        )
        await tail.close()
        try await MemoryExerciseSession.settle(context.runtime)
      }
    }
  }

  /// E06: observers opened and closed: what each distinct query leaves behind once its lease ended (Scribe's agent
  /// replies once registered about 380 new query keys in 16 minutes).
  @Test func e06ObserveChurn() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e06").closing { context in
      let runtime = context.runtime
      let count = 300
      let keysBefore = await runtime.liveActiveQueryKeysForTesting().count
      let resultKeysBefore = await runtime.liveQueryResultActiveKeysForTesting().count
      let energy = InstantEnergyMeter.snapshot()
      let churn = try await MemoryOnce.measure {
        for index in 0..<count {
          let plan = InstantQueryPlan(
            id: "e06-churn-\(index)", namespace: "agentResponses",
            filters: [.equals(field: "recordingID", value: .string("e06-thread-\(index)"))], limit: 20
          )
          let added = await context.server.addQueries
          let lease = await runtime.observeQueryLease(plan)
          _ = try await MemoryStreams.first(lease.stream, "e06: a churned query's first emission") { _ in true }
          _ = await context.server.nextAddQuery(after: added)
          await lease.cancel()
        }
        try await MemoryExerciseSession.settle(runtime)
      }
      MemoryReport.print(
        "E06.observe.churn", churn, label: Self.label,
        extra: [
          ("leases", String(count)), ("retainedPerLeaseB", MemoryReport.ratio(churn.netLiveBytes, count)),
          ("activeQueryKeys", "\(keysBefore)->\(await runtime.liveActiveQueryKeysForTesting().count)"),
          ("resultKeys", "\(resultKeysBefore)->\(await runtime.liveQueryResultActiveKeysForTesting().count)"),
          ("observers", String(await runtime.store.activeObservationCount())),
        ] + MemoryEnergy.operations(since: energy, iterations: count)
      )
    }
  }

  /// E07: launch: what the store's resident set costs in memory once the runtime is up, per resident fact, and the
  /// launch's transient peak.
  @Test func e07LaunchResident() async throws {
    let shape = Self.shape
    // A store as a session leaves it (the stale confirmed writes pruned, the link attribute stored), so the launch
    // measured is a relaunch of the phone's shape.
    let prepared = FileManager.default.temporaryDirectory.appendingPathComponent("real-size-sessions/e07-prepared-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: prepared) }
    try await MemoryExerciseSession.open(shape, label: "e07-prepare", waitsForApplies: false, directory: prepared).closing { _ in }
    let account = RealSizeAccount(shape)
    let answerer = RealSizeServer(account: account)
    let attributes = MemoryScribeWrites.attributes(account)
    let server = MemoryReplayServer(attributes: attributes) { query in await answerer.rows(answering: query) }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("real-size-sessions/e07-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let storeURL = directory.appendingPathComponent("cache.sqlite")
    try RealSizeFixture.copyStore(from: prepared.appendingPathComponent("cache.sqlite"), to: storeURL)

    var session: RealSizeSession?
    let launch = try await MemoryOnce.measure {
      session = try await RealSizeFixture.boot(
        shape: shape, account: account, storeURL: storeURL, directory: directory, removesDirectory: false, onFrame: nil,
        configure: { configuration in
          configuration.liveTransport = server.transport
          configuration.initialAttributes = Self.isPhoneCopy ? [] : attributes
          MemoryExerciseSession.configureAsScribe(&configuration)
        }
      )
    }
    guard let session else { return }
    let triples = await session.runtime.store.currentTripleCount()
    MemoryReport.print(
      "E07.launch.resident", launch, label: Self.label,
      extra: [("residentFacts", String(triples)), ("retainedPerFactB", MemoryReport.ratio(launch.netLiveBytes, triples))]
    )
    await session.close()
  }

  /// E08: uploads with the device's 4,264 file records on disk: a minute of WAV (5,760,044 bytes) and a six-second
  /// compressed segment (about 24 KB, ten a minute since build 120).
  @Test func e08Upload() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e08").closing { context in
      for (name, bytes, iterations) in [("chunk-wav", 5_760_044, 5), ("segment-m4a", 24_576, 20)] {
        let file = context.session.directory.appendingPathComponent("\(name).bin")
        try Data(repeating: 0x5a, count: bytes).write(to: file)
        let records = try await context.runtime.persistence.loadStoredFiles(appID: RealSizeAccount.appID).count
        let measurement = try await RealSizeMeter.measure("uploadFile.\(name)", label: Self.label, iterations: iterations, warmup: 1) { index in
          _ = try await context.runtime.uploadFile(
            from: file, name: "scribe/e08/\(name)/\(String(format: "%06d", index)).bin",
            contentType: name.hasSuffix("wav") ? "audio/wav" : "audio/mp4"
          )
        }
        MemoryReport.print(
          "E08.upload.\(name)", measurement, label: Self.label,
          extra: [
            ("fileKB", String(bytes / 1_024)), ("recordsOnDisk", String(records)),
            ("allocationsPerRecord", MemoryReport.ratio(measurement.allocations, max(1, records))),
          ]
        )
      }
    }
  }

  /// E09: what a write's diagnostics cost: the same write with no diagnostics sink, with Scribe's (the `.info` floor
  /// and five handlers), and with the exercises' (the `.debug` floor and one handler).
  ///
  /// The session's apply log is a handler as well, so the passes stop it first: until #1148 the "no sink" pass ran at the
  /// `.debug` floor with that handler, and each other pass had one handler more than its name says.
  @Test func e09DiagnosticsPerWrite() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e09", waitsForApplies: false).closing { context in
      let runtime = context.runtime
      let clock = context.session.clock
      let recordingID = RealSizeID.make(.write, 830_000)
      let diagnostics = InstantDiagnostics.shared
      defer { diagnostics.configure(.environment()) }
      context.session.applies.stop()

      for (name, level, handlers) in [("no-sink", InstantDiagnosticLevel.debug, 0), ("scribe-info-5-handlers", .info, 5), ("debug-1-handler", .debug, 1)] {
        diagnostics.configure(InstantDiagnosticsConfiguration(fileURL: nil, minimumLevel: level))
        try #require(!diagnostics.isEnabled, "E09 \(name): a sink this pass did not add is active.")
        let events = MemoryEventCounter()
        let tokens = (0..<handlers).map { _ in diagnostics.addHandler { _ in events.increment() } }
        // An interim of the line in progress, Scribe's most frequent write.
        let interims = (0..<210).map { index in
          MemoryScribeWrites.liveLine(recordingID: recordingID, line: 830_001, words: 3 + index % 9, at: clock.now())
        }
        let measurement = try await RealSizeMeter.measure("transact", label: Self.label, iterations: 100, warmup: 10) { index in
          try await runtime.transact(MemoryScribeWrites.transaction { MemoryScribeWrites.update(interims[index], at: clock.advance(), txID: $0) })
          try await MemoryExerciseSession.waitUntilAcknowledged(runtime)
        }
        for token in tokens { diagnostics.removeHandler(token) }
        MemoryReport.print(
          "E09.diagnostics.\(name)", measurement, label: Self.label,
          // The handlers saw the warm-up, timed and counted passes: 10 + 100 + 100 writes.
          extra: [("handlerCallsPerWrite", handlers == 0 ? "-" : MemoryReport.ratio(events.value, 210))]
        )
      }
    }
  }

  /// E10: what grows with the app's schema rather than the store: the same new line and its emission on a 64-line
  /// tail, and the same 64-line refresh, on a small store declaring the generated account's own attributes and on
  /// the same store declaring the phone's 2,283.
  @Test func e10SchemaSizedWork() async throws {
    var small = RealSizeShape.phone.scaled(0.01)
    small.attributes = RealSizeAccount.scribeAttributeCount
    var wide = small
    wide.attributes = RealSizeShape.phone.attributes
    for shape in [small, wide] {
      try await MemoryExerciseSession.open(shape, label: "e10").closing { context in
        let recordingID = RealSizeID.make(.recording, 0)
        let tail = try await MemoryTail.open(
          context, plan: MemoryExerciseSession.tailPlan(id: "e10-tail", recordingID: recordingID, rows: 64),
          expectedRows: min(64, shape.transcriptLines.first ?? 0)
        )
        let frames = await tail.frames(count: 3 + 2 * 20) { index in
          RealSizeAccount.segment(
            recordingID: recordingID, line: 50_000 + index, revision: 4, serial: 0, id: RealSizeID.make(.write, 840_000 + index)
          )
        }
        let recording = try #require(context.session.account.entities["recordings"]?.first { $0.id == recordingID })
        let energy = InstantEnergyMeter.snapshot()
        let newLines = (0..<43).map { index in
          RealSizeAccount.segment(recordingID: recordingID, line: 50_000 + index, revision: 4, serial: 0, id: frames[index].id)
        }
        let write = try await RealSizeMeter.measure("new-line", label: Self.label, iterations: 20, warmup: 3) { index in
          try await tail.writeAndShow(
            frames[index], MemoryScribeWrites.finalLine(newLines[index], recording: recording, liveLine: nil, at: context.session.clock.advance())
          )
        }
        MemoryReport.print(
          "E10.schema.window-new-line", write, label: "attributes\(shape.attributes)",
          extra: MemoryEnergy.operations(since: energy, iterations: 43)
        )
        await tail.close()

        let page = try await MemoryOpenPage.open(
          context, recordingID: RealSizeID.make(.write, 850_000), rows: 64, firstLine: 0, idBase: 3_000_000, id: "e10-page"
        )
        let pageFrames = await page.frames(count: 17)
        let refresh = try await RealSizeMeter.measure("refresh-64", label: Self.label, iterations: 8, warmup: 1) { index in
          await context.server.push(encoded: pageFrames[index].frame)
          try await context.waitApplies.wait(for: pageFrames[index].tx)
        }
        MemoryReport.print("E10.schema.page-refresh-64", refresh, label: "attributes\(shape.attributes)")
        await page.close()
      }
    }
  }

  /// E11: `storedFiles()` with the account's 9,455 files: a one-shot query of the whole `$files` list, its stored
  /// result and query cache row, each time it is called (Scribe's storage cleanup calls it once per launch).
  @Test func e11StoredFiles() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e11").closing { context in
      let files = await context.session.server.filesRows()
      await context.server.prepareAnswer(namespace: "$files", rows: files)
      var listed = 0
      let energy = InstantEnergyMeter.snapshot()
      let measurement = try await RealSizeMeter.measure("storedFiles", label: Self.label, iterations: 2, warmup: 1) { _ in
        listed = try await context.runtime.storedFiles().count
      }
      MemoryReport.print(
        "E11.files.storedFiles", measurement, label: Self.label,
        extra: [("files", String(files.count)), ("listed", String(listed))] + MemoryEnergy.operations(since: energy, iterations: 5)
      )
    }
  }

  /// E12: a live page's stored result written and read back: the 256-line page's refresh with nothing due to write,
  /// the write of its result (`flushPendingLiveQueryResults`, which the 30-second throttle and a background run do),
  /// and the refresh right after that write.
  @Test func e12ResultWriteAndReadBack() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e12").closing { context in
      let page = try await MemoryOpenPage.open(
        context, recordingID: RealSizeID.make(.write, 860_000), rows: 256, firstLine: 0, idBase: 4_000_000, id: "e12-page"
      )
      let iterations = 6
      let frames = await page.frames(count: 3 * (1 + 2 * iterations))
      var next = 0
      func refresh() async throws {
        let frame = frames[next]
        next += 1
        await context.server.push(encoded: frame.frame)
        try await context.waitApplies.wait(for: frame.tx)
      }
      let mid = try await RealSizeMeter.measure("refresh", label: Self.label, iterations: iterations, warmup: 1) { _ in
        try await refresh()
      }
      MemoryReport.print("E12.result.refresh-nothing-due", mid, label: Self.label)
      let flush = try await RealSizeMeter.measure("flush", label: Self.label, iterations: iterations, warmup: 1) { _ in
        try await refresh()
        try await context.runtime.flushPendingLiveQueryResults()
      }
      MemoryReport.print("E12.result.refresh-then-write", flush, label: Self.label)
      let after = try await RealSizeMeter.measure("refresh-after-write", label: Self.label, iterations: iterations, warmup: 1) { _ in
        try await context.runtime.flushPendingLiveQueryResults()
        try await refresh()
      }
      MemoryReport.print("E12.result.write-then-refresh", after, label: Self.label)
      await page.close()
    }
  }

  /// E13: a reconnect with Scribe's three recording-screen queries open (the live window, the lines in progress, the
  /// recordings list): what one costs, and what each leaves behind (about three in a two-hour recording).
  @Test func e13Reconnect() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e13").closing { context in
      let runtime = context.runtime
      let (recordingID, _) = Self.longestRecording
      var leases: [InstantQueryObservationLease] = []
      for plan in [
        MemoryExerciseSession.tailPlan(id: "e13-window", recordingID: recordingID, rows: 64),
        InstantQueryPlan(
          id: "e13-live-lines", namespace: "recordingSpeakers",
          filters: [.equals(field: "recordingID", value: .string(recordingID))], limit: 8
        ),
        MemoryExerciseSession.listPlan,
      ] {
        let lease = await runtime.observeQueryLease(plan)
        _ = try await MemoryStreams.first(lease.stream, "e13: \(plan.id)'s first emission") { _ in true }
        leases.append(lease)
      }
      try await MemoryExerciseSession.settle(runtime)
      let energy = InstantEnergyMeter.snapshot()
      let loads = await runtime.persistenceCacheResidencyMetricsForTesting()
      let copies = await runtime.store.fullCopyCountForTesting
      let measurement = try await RealSizeMeter.measure("reconnect", label: Self.label, iterations: 3, warmup: 1) { _ in
        let added = await context.server.addQueries
        _ = try await runtime.closeConnection()
        _ = try await runtime.connect()
        let deadline = ContinuousClock.now + .seconds(120)
        while await context.server.addQueries < added + leases.count {
          guard ContinuousClock.now < deadline else { throw MemoryStreams.Timeout(description: "e13: the queries were not added again") }
          try await Task.sleep(for: .milliseconds(1))
        }
        try await MemoryExerciseSession.settle(runtime)
      }
      let loadsAfter = await runtime.persistenceCacheResidencyMetricsForTesting()
      MemoryReport.print(
        "E13.reconnect.three-queries", measurement, label: Self.label,
        extra: [
          ("connections", String(await context.server.connections)),
          ("fullStoreLoads", String(loadsAfter.fullStoreSnapshotLoadCount - loads.fullStoreSnapshotLoadCount)),
          ("storeReplacements", String(loadsAfter.storeSnapshotReplacementCount - loads.storeSnapshotReplacementCount)),
          ("fullStoreCopies", String(await runtime.store.fullCopyCountForTesting - copies)),
        ] + MemoryEnergy.operations(since: energy, iterations: 7)
      )
      for lease in leases { await lease.cancel() }
    }
  }

  /// E14: the recording screen's history read: the longest recording's lines from this device's store in 256-line
  /// pages, newest first, each page a one-shot local read (Scribe reads every page when the screen opens).
  @Test func e14LocalHistoryPages() async throws {
    try await MemoryExerciseSession.open(Self.shape, label: "e14").closing { context in
      let (recordingID, lines) = Self.longestRecording
      let pages = max(1, (lines + 255) / 256)
      var rows = 0
      let measurement = try await RealSizeMeter.measure("queryLocally.page", label: Self.label, iterations: pages, warmup: 1) { index in
        let plan = InstantQueryPlan(
          id: "e14-history", namespace: "transcriptionSegments",
          filters: [.equals(field: "recordingID", value: .string(recordingID))],
          order: InstantQueryOrder("segmentIndex", .descending), offset: (index % pages) * 256, limit: 256,
          selectedFields: RealSizeAccount.segmentFields.filter { $0 != "id" }
        )
        rows = try await context.runtime.queryLocally(plan).values.count
      }
      MemoryReport.print(
        "E14.read.local-history-page", measurement, label: Self.label,
        extra: [("pages", String(pages)), ("lines", String(lines)), ("lastPageRows", String(rows))]
      )
      // #1150: a page cost 19.5 MB on the Mac mini while each read rebuilt the schema's attribute index from all 2,283
      // attributes (7.2 MB once it took the store's), and decoded its deferred values' computed JSON with JSONDecoder.
      #expect(
        measurement.allocatedBytes < 4 * 1_024 * 1_024,
        "E14 allocated \(measurement.allocatedBytes / 1_024) KB per 256-line page."
      )
    }
  }
}

/// A session over a copy of the generated store whose server is the memory audit's (`MemoryReplayServer`): text
/// frames through the production decoder, no frame history, every query answered from the generated account.
struct MemoryExerciseSession: Sendable {
  let session: RealSizeSession
  let server: MemoryReplayServer
  let applies: MemoryApplyWaiter?

  var runtime: InstantRuntime { session.runtime }

  /// The library as Scribe configures it, where that changes what an exercise measures: transcript text and words
  /// stay on disk until a selected page hydrates them (`ScribeInstantBootstrap.deferredValueResidency`), and a local
  /// read finds a recording's lines through one small index (`ScribeInstantBootstrap.localLookup`).
  static func configureAsScribe(_ configuration: inout InstantRuntimeConfiguration) {
    configuration.deferredValueResidency = InstantDeferredValueResidencyPolicy(
      attributeIDs: ["transcriptionSegments/text", "transcriptionSegments/wordsJSON"]
    )
    configuration.localLookup = InstantLocalLookupPolicy(attributeIDs: ["recordings/id", "transcriptionSegments/recordingID"])
  }

  /// A session over a fresh copy of `shape`'s store (`directory`, when given, keeps the copy after the session).
  ///
  /// The copy is first made to look like a phone's on one point: #1072's generator acknowledged writes with string
  /// transaction ids, which no refresh can cover, so its store keeps 783 confirmed writes the library can never prune
  /// (the phone's keeps 3). Their ids are set to 1 on the copy, and the session's first server apply (a throwaway query
  /// opened here) prunes them through the library's own watermark path, before any exercise measures.
  static func open(
    _ shape: RealSizeShape,
    label: String,
    waitsForApplies: Bool = true,
    directory: URL? = nil,
    storeSource: URL? = nil,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> Self {
    // One account per session: the fixture's server and this one share its storage.
    let account = RealSizeAccount(shape)
    let answerer = RealSizeServer(account: account)
    let attributes = MemoryScribeWrites.attributes(account)
    let server = MemoryReplayServer(attributes: attributes) { query in await answerer.rows(answering: query) }
    let removesDirectory = directory == nil
    let directory = directory ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("real-size-sessions", isDirectory: true)
      .appendingPathComponent("memory-\(label)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let storeURL = directory.appendingPathComponent("cache.sqlite")
    let source: URL
    if let storeSource { source = storeSource } else { source = try await RealSizeFixture.store(shape) }
    try RealSizeFixture.copyStore(from: source, to: storeURL)
    let stale = try MemoryStoreCopy.coverStaleConfirmedWrites(at: storeURL)
    let session = try await RealSizeFixture.boot(
      shape: shape, account: account, storeURL: storeURL, directory: directory, removesDirectory: removesDirectory,
      onFrame: nil,
      configure: { configuration in
        configuration.liveTransport = server.transport
        configuration.initialAttributes = MemoryExercises.isPhoneCopy ? [] : attributes
        configureAsScribe(&configuration)
        configure(&configuration)
      }
    )
    // The fixture's apply log keeps every apply it saw: growth that is the harness's, not the library's.
    session.applies.stop()
    let context = Self(session: session, server: server, applies: waitsForApplies ? MemoryApplyWaiter() : nil)
    let prune = await session.runtime.observeQueryLease(
      InstantQueryPlan(
        id: "memory-session-first-apply", namespace: "agentThreads",
        filters: [.equals(field: "recordingID", value: .string("memory-session-first-apply"))], limit: 1
      )
    )
    _ = try await MemoryStreams.first(prune.stream, "the session's first apply") { _ in true }
    try await settle(session.runtime)
    await prune.cancel()
    let counts = try RealSizeStoreCounts(storeURL)
    print(
      "MEMORY-SESSION \(label) shape=[\(shape)] staleConfirmedCovered=\(stale)"
        + " outbox=\(counts.outbox.keys.sorted().map { "\($0):\(counts.outbox[$0]!)" }.joined(separator: ","))"
    )
    return context
  }

  func close() async {
    applies?.stop()
    await session.close()
  }

  /// Runs `body`, then closes the session whether `body` threw or not: a close left to a detached task would run into
  /// the next exercise's counts.
  func closing<Result>(_ body: (Self) async throws -> Result) async throws -> Result {
    let result: Result
    do {
      result = try await body(self)
    } catch {
      await close()
      throw error
    }
    await close()
    return result
  }

  /// Waits until the server acknowledged every write: on the open session's apply waiter, which checks the outbox after
  /// each write outcome the runtime reports (#1147), or, in a session without one (E09 prices handlers, so it adds
  /// none), by checking every millisecond.
  static func waitUntilAcknowledged(_ runtime: InstantRuntime) async throws {
    if let waiter = MemoryApplyWaiter.current {
      try await waiter.waitUntilAcknowledged(runtime)
      return
    }
    let deadline = ContinuousClock.now + .seconds(60)
    while await runtime.pendingMutationCount() > 0 {
      guard ContinuousClock.now < deadline else { throw MemoryStreams.Timeout(description: "writes still pending after 60 s") }
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  /// Waits until no write is pending and the runtime is idle for a moment (answers in flight applied).
  static func settle(_ runtime: InstantRuntime) async throws {
    try await waitUntilAcknowledged(runtime)
    try await Task.sleep(for: .milliseconds(300))
  }

  /// Scribe's live transcript window: a recording's newest lines, newest first.
  static func tailPlan(id: String, recordingID: String, rows: Int) -> InstantQueryPlan {
    InstantQueryPlan(
      id: id, namespace: "transcriptionSegments",
      filters: [.equals(field: "recordingID", value: .string(recordingID))],
      order: InstantQueryOrder("segmentIndex", .descending), limit: rows,
      selectedFields: RealSizeAccount.segmentFields.filter { $0 != "id" }
    )
  }

  /// The recordings list: seven pages of twelve, newest first (Scribe's retained window).
  static let listPlan = InstantQueryPlan(
    id: "memory-recordings-list", namespace: "recordings", order: InstantQueryOrder("updatedAtMs", .descending), limit: 84,
    selectedFields: RealSizeAccount.recordingFields.filter { $0 != "id" }
  )
}

extension MemoryExerciseSession {
  /// The apply waiter of a session opened with `waitsForApplies` (the default).
  var waitApplies: MemoryApplyWaiter { applies! }
}

/// An open window of a recording's lines (a tail, newest first) and the server's answer for it: a new line is written,
/// acknowledged, then shown by the server's refresh of the window with it first, as the server does after each write.
struct MemoryTail: Sendable {
  let context: MemoryExerciseSession
  let lease: InstantQueryObservationLease
  let query: InstantLiveJSONValue
  let initialRows: [InstantLiveJSONValue]
  let rows: Int

  static func open(_ context: MemoryExerciseSession, plan: InstantQueryPlan, expectedRows: Int) async throws -> Self {
    let added = await context.server.addQueries
    let lease = await context.runtime.observeQueryLease(plan)
    let query = await context.server.nextAddQuery(after: added)
    _ = try await MemoryStreams.first(lease.stream, "\(plan.id): the window's answer") { $0.values.count >= expectedRows }
    let initialRows = await context.session.server.rows(answering: query)
    return Self(context: context, lease: lease, query: query, initialRows: initialRows, rows: plan.limit ?? initialRows.count)
  }

  /// `count` new lines (`line(index)`) and the server's refresh frame of the window after each, encoded now.
  func frames(count: Int, line: (Int) -> RealSizeEntity) async -> [(id: String, tx: String, frame: String)] {
    var window = initialRows
    var frames: [(id: String, tx: String, frame: String)] = []
    for index in 0..<count {
      let entity = line(index)
      window.insert(entity.joinRow(), at: 0)
      if window.count > rows { window.removeLast(window.count - rows) }
      let tx = await context.server.nextTransactionID()
      frames.append((entity.id, tx, MemoryReplayServer.encoded(MemoryReplayServer.refreshFrame(query, rows: window, tx: tx))))
    }
    return frames
  }

  /// Writes the new line, waits for the server's acknowledgment, sends the window's refresh with it first, and waits
  /// for the emission that shows it.
  func writeAndShow(_ frame: (id: String, tx: String, frame: String), _ write: InstantStoreTransaction) async throws {
    try await context.runtime.transact(write)
    try await MemoryExerciseSession.waitUntilAcknowledged(context.runtime)
    await context.server.push(encoded: frame.frame)
    let id = frame.id
    _ = try await MemoryStreams.first(lease.stream, "the window's emission of a new line") { $0.values.first?.id == id }
  }

  func close() async { await lease.cancel() }
}

/// A transcript page the runtime observes and the server refreshes: a recording's `rows` lines from `firstLine`, its
/// filter matching only them, as the server holds them. Line `n`'s id is `RealSizeID.make(.write, idBase + n)`.
struct MemoryOpenPage: Sendable {
  let context: MemoryExerciseSession
  let lease: InstantQueryObservationLease
  let query: InstantLiveJSONValue
  let recordingID: String
  let firstLine: Int
  let rows: Int
  let idBase: Int
  let reader: Task<Void, Never>

  static func open(
    _ context: MemoryExerciseSession, recordingID: String, rows: Int, firstLine: Int, idBase: Int, id: String
  ) async throws -> Self {
    let plan = InstantQueryPlan(
      id: id, namespace: "transcriptionSegments",
      filters: [
        .equals(field: "recordingID", value: .string(recordingID)),
        .greaterThanOrEqual(field: "segmentIndex", value: .number(Double(firstLine))),
      ],
      order: InstantQueryOrder("segmentIndex"), limit: 256,
      selectedFields: RealSizeAccount.segmentFields.filter { $0 != "id" }
    )
    let lines = (0..<rows).map { line(recordingID: recordingID, firstLine: firstLine, idBase: idBase, $0, revision: 4) }
    await context.server.prepareAnswer(namespace: "transcriptionSegments", rows: lines.map { $0.joinRow() })
    let added = await context.server.addQueries
    let lease = await context.runtime.observeQueryLease(plan)
    let query = await context.server.nextAddQuery(after: added)
    await context.server.forgetPreparedAnswer(namespace: "transcriptionSegments")
    _ = try await MemoryStreams.first(lease.stream, "\(id): the page's answer") { $0.values.count >= rows }
    // A screen reads every emission.
    let reader = Task { for await _ in lease.stream {} }
    return Self(
      context: context, lease: lease, query: query, recordingID: recordingID, firstLine: firstLine, rows: rows,
      idBase: idBase, reader: reader
    )
  }

  private static func line(recordingID: String, firstLine: Int, idBase: Int, _ index: Int, revision: Int) -> RealSizeEntity {
    RealSizeAccount.segment(
      recordingID: recordingID, line: firstLine + index, revision: revision, serial: 0,
      id: RealSizeID.make(.write, idBase + index)
    )
  }

  /// `count` refresh frames of the whole page, encoded now, one line changed in each, as a refresh after a write
  /// carries it.
  func frames(count: Int) async -> [(tx: String, frame: String)] {
    var lines = (0..<rows).map { Self.line(recordingID: recordingID, firstLine: firstLine, idBase: idBase, $0, revision: 4) }
    var frames: [(tx: String, frame: String)] = []
    for index in 0..<count {
      let slot = index % rows
      lines[slot] = Self.line(recordingID: recordingID, firstLine: firstLine, idBase: idBase, slot, revision: index % 5)
      let tx = await context.server.nextTransactionID()
      frames.append((tx, MemoryReplayServer.encoded(MemoryReplayServer.refreshFrame(query, rows: lines.map { $0.joinRow() }, tx: tx))))
    }
    return frames
  }

  func close() async {
    reader.cancel()
    await lease.cancel()
  }
}

/// Waits on a stream with a deadline that holds even when the stream stops emitting: a `for await` loop reads its
/// deadline only when an element arrives, so a page that never fills hangs the exercise instead of failing it.
enum MemoryStreams {
  struct Timeout: Error, CustomStringConvertible {
    var description: String
  }

  static func first<Element: Sendable>(
    _ stream: AsyncStream<Element>,
    within timeout: Duration = .seconds(120),
    _ what: String,
    where matches: @escaping @Sendable (Element) -> Bool
  ) async throws -> Element {
    try await withThrowingTaskGroup(of: Element?.self) { group in
      group.addTask {
        for await element in stream where matches(element) { return element }
        return nil
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw Timeout(description: "\(what): nothing within \(timeout)")
      }
      defer { group.cancelAll() }
      guard case .some(.some(let element)) = try await group.next() else {
        throw Timeout(description: "\(what): the stream finished first")
      }
      return element
    }
  }
}

/// One counted run of an operation that cannot be repeated on the same state (a launch, a first observation).
struct MemoryOnce: Sendable {
  var allocations = 0
  var allocatedBytes = 0
  var frees = 0
  var peakLiveBytes = 0
  var netLiveBytes = 0
  var footprintBefore: UInt64 = 0
  var footprintAfter: UInt64 = 0
  var footprintPeak: UInt64 = 0
  var wall: Duration = .zero

  static func measure(_ body: () async throws -> Void) async throws -> MemoryOnce {
    RealSizeProcess.resetFootprintPeak()
    let before = RealSizeProcess.usage().footprint
    let liveBefore = RealSizeProcess.zoneBytesInUse()
    let started = ContinuousClock.now
    RealSizeAllocations.start()
    do {
      try await body()
    } catch {
      _ = RealSizeAllocations.stop()
      throw error
    }
    let counts = RealSizeAllocations.stop()
    let wall = ContinuousClock.now - started
    let liveAfter = RealSizeProcess.zoneBytesInUse()
    let usage = RealSizeProcess.usage()
    return MemoryOnce(
      allocations: counts.allocations, allocatedBytes: counts.allocatedBytes, frees: counts.frees,
      peakLiveBytes: counts.peakLiveBytes, netLiveBytes: liveAfter - liveBefore, footprintBefore: before,
      footprintAfter: usage.footprint, footprintPeak: max(usage.footprintIntervalPeak, usage.footprint), wall: wall
    )
  }
}

enum MemoryReport {
  static func ratio(_ value: some BinaryInteger, _ divisor: some BinaryInteger) -> String {
    String(format: "%.1f", Double(value) / Double(max(1, divisor)))
  }

  static func milliseconds(_ duration: Duration) -> String {
    String(format: "%.2f", Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15)
  }

  /// A metered operation, per iteration (retained: the counted pass's net heap growth over its iterations).
  static func print(_ exercise: String, _ measurement: RealSizeMeasurement, label: String, extra: [(String, String)] = []) {
    let n = max(1, measurement.iterations)
    let fields: [(String, String)] = [
      ("n", String(measurement.iterations)),
      ("allocations", String(measurement.allocations)),
      ("allocatedKB", String(measurement.allocatedBytes / 1_024)),
      ("frees", String(measurement.frees)),
      ("retainedKB", String(format: "%.1f", Double(measurement.netLiveBytes) / Double(n) / 1_024)),
      ("peakLiveKB", String(measurement.peakLiveBytes / 1_024)),
      ("footprintPeakMB", String(measurement.footprintPeak / 1_048_576)),
      ("wallMs", milliseconds(measurement.medianWall)),
    ] + extra
    Swift.print("MEMORY \(exercise) \(label) " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " "))
  }

  /// A one-shot operation.
  static func print(_ exercise: String, _ once: MemoryOnce, label: String, extra: [(String, String)] = []) {
    let fields: [(String, String)] = [
      ("n", "1"),
      ("allocations", String(once.allocations)),
      ("allocatedKB", String(once.allocatedBytes / 1_024)),
      ("frees", String(once.frees)),
      ("retainedKB", String(format: "%.1f", Double(once.netLiveBytes) / 1_024)),
      ("peakLiveKB", String(once.peakLiveBytes / 1_024)),
      ("footprintPeakMB", String(once.footprintPeak / 1_048_576)),
      ("footprintGrowthMB", String(format: "%.1f", (Double(once.footprintAfter) - Double(once.footprintBefore)) / 1_048_576)),
      ("wallMs", milliseconds(once.wall)),
    ] + extra
    Swift.print("MEMORY \(exercise) \(label) " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " "))
  }
}

/// Which of the library's metered operations ran during a measurement, per iteration (`InstantEnergyMeter`), so a
/// cost names the work behind it: `op.serverApplyCommit=2.0` is two commits per iteration.
enum MemoryEnergy {
  /// Each operation that ran: `op.<name>` (times per iteration) and `opMs.<name>` (its wall milliseconds per
  /// iteration).
  static func operations(since earlier: InstantEnergySnapshot, iterations: Int) -> [(String, String)] {
    let delta = InstantEnergyMeter.snapshot().subtracting(earlier)
    return InstantEnergyOperation.allCases.flatMap { operation -> [(String, String)] in
      let measure = delta[operation]
      guard measure.count > 0 else { return [] }
      return [
        ("op." + operation.rawValue, MemoryReport.ratio(measure.count, iterations)),
        ("opMs." + operation.rawValue, String(format: "%.2f", Double(measure.wallNanoseconds) / 1e6 / Double(max(1, iterations)))),
      ]
    }
  }
}

/// Changes to a session's own copy of the generated store, before the runtime opens it (never to the cached store).
enum MemoryStoreCopy {
  /// Sets the server transaction id of every confirmed write whose id is not an integer to 1, so the first refresh
  /// covers it and the library prunes it as it would have on a phone (see `MemoryTransactionIDs`). Returns how many.
  static func coverStaleConfirmedWrites(at url: URL) throws -> Int {
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
      throw MemoryStreams.Timeout(description: "could not open the store copy at \(url.path)")
    }
    let sql = """
      UPDATE instant_outbox SET server_transaction_id = '1'
      WHERE status = 'confirmed' AND COALESCE(server_transaction_id, '') GLOB '*[^0-9]*'
      """
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw MemoryStreams.Timeout(description: "could not update the store copy: \(String(cString: sqlite3_errmsg(database)))")
    }
    return Int(sqlite3_changes(database))
  }
}

/// Writes shaped as Scribe makes them through the typed API (`InstantTypedAPI.swift`): `update` inserts the row's
/// primary key and every assigned value, `updateExisting` first requires the row, `delete` removes the row in its
/// namespace, and a line links to its recording through the reverse side of `recordings.segments`.
///
/// #1072's fixture writes rows as `.merge`s, which suits building a store; but a merge onto a row the store does not
/// hold changes nothing in memory (as upstream `mergeTriple`), so a new line written that way is never materialized
/// until the server echoes it, and the link set, the cascade preview and new index entries never run (the write-path
/// auditor's note). The exercises write what Scribe writes.
enum MemoryScribeWrites {
  /// A recording's lines, as Scribe's schema links them (`recordingSegments`): forward on the recording, has many.
  static let segmentsLink = InstantAttribute(
    id: "recordings/segments", namespace: "recordings", name: "segments", valueType: .ref, isRequired: false,
    cardinality: .many, isIndexed: true, forwardIdentity: "recordings/segments",
    reverseIdentity: "transcriptionSegments/recording", linkNamespace: "transcriptionSegments"
  )

  /// The generated account's schema and the link.
  static func attributes(_ account: RealSizeAccount) -> [InstantAttribute] { account.attributes + [segmentsLink] }

  /// `update(id:)`: the primary key, then each value of `entity` named in `fields` (every one when nil).
  static func update(
    _ entity: RealSizeEntity, fields: [String]? = nil, at time: InstantTimestamp, txID: String
  ) -> [InstantTripleOperation] {
    let names = fields ?? entity.values.keys.sorted().filter { $0 != "id" }
    let identity = InstantTriple(
      entityID: entity.id, attributeID: "\(entity.namespace)/id", value: .string(entity.id), txID: txID, txTime: time
    )
    return [.insert(identity)] + names.compactMap { name in
      entity.values[name].map { value in
        .insert(InstantTriple(entityID: entity.id, attributeID: "\(entity.namespace)/\(name)", value: value, txID: txID, txTime: time))
      }
    }
  }

  /// `updateExisting(id:)`: requires the row, then `update` of `fields`.
  static func updateExisting(
    _ entity: RealSizeEntity, fields: [String], at time: InstantTimestamp, txID: String
  ) -> [InstantTripleOperation] {
    [.requireEntityExists(entityID: entity.id, namespace: entity.namespace)] + update(entity, fields: fields, at: time, txID: txID)
  }

  /// `delete(id:)`.
  static func delete(id: String, namespace: String) -> InstantTripleOperation {
    .deleteEntityInNamespace(entityID: id, namespace: namespace)
  }

  /// A line's link to its recording, written from the line's side.
  static func link(lineID: String, recordingID: String, at time: InstantTimestamp, txID: String) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: lineID, attributeID: "transcriptionSegments/recording", value: .ref(recordingID), txID: txID, txTime: time
      )
    )
  }

  /// One transaction of `operations(txID)`.
  static func transaction(_ operations: (String) -> [InstantTripleOperation]) -> InstantStoreTransaction {
    let id = UUID().uuidString.lowercased()
    return InstantStoreTransaction(id: id, operations: operations(id))
  }

  /// A finished line, as Scribe's final writes it in one transaction: the recording's `updatedAtMs`, the line's
  /// values and its link, and the line in progress deleted.
  static func finalLine(
    _ line: RealSizeEntity, recording: RealSizeEntity, liveLine: (id: String, namespace: String)?, at time: InstantTimestamp
  ) -> InstantStoreTransaction {
    transaction { txID in
      var recording = recording
      recording.values["updatedAtMs"] = .number(Double(time.milliseconds))
      var operations = updateExisting(recording, fields: ["updatedAtMs"], at: time, txID: txID)
      operations += update(line, at: time, txID: txID)
      operations.append(link(lineID: line.id, recordingID: recording.id, at: time, txID: txID))
      if let liveLine { operations.append(delete(id: liveLine.id, namespace: liveLine.namespace)) }
      return operations
    }
  }

  /// The line in progress of `line` (Scribe's `liveLines` row, played by `recordingSpeakers`: sixteen values, its
  /// words growing with each interim).
  static func liveLine(recordingID: String, line: Int, words: Int, at time: InstantTimestamp) -> RealSizeEntity {
    let payload = "[" + (0..<words).map { "{\"w\":\"word\($0 % 37)\",\"s\":\(Double($0) * 0.31),\"c\":0.9}" }.joined(separator: ",") + "]"
    return row(
      MemoryReplayRecording.liveLinesNamespace, id: RealSizeID.make(.write, 3_000_000 + line), recordingID: recordingID,
      kind: "live", payload: payload, at: time
    )
  }

  /// A row of one of the account's other namespaces: its first `fieldCount` values (`RealSizeAccount.otherFields`,
  /// sixteen at most).
  static func row(
    _ namespace: String, id: String, recordingID: String, kind: String, payload: String, extra: String = "",
    fieldCount: Int = 16, at time: InstantTimestamp
  ) -> RealSizeEntity {
    var values: [String: InstantValue] = [:]
    for field in RealSizeAccount.otherFields.prefix(fieldCount) {
      switch field {
      case "id": values[field] = .string(id)
      case "recordingID": values[field] = .string(recordingID)
      case "ownerUserID": values[field] = .string(RealSizeAccount.userID)
      case "kind": values[field] = .string(kind)
      case "createdAtMs", "updatedAtMs": values[field] = .number(Double(time.milliseconds))
      case "payloadJSON": values[field] = .string(payload)
      default: values[field] = .string("\(field)-\(kind)\(extra)")
      }
    }
    return RealSizeEntity(namespace: namespace, id: id, values: values)
  }

  /// Links every line of the account's recording `recordingID` to it, as the phone's store holds them (its longest
  /// recording links 2,364): setup, before a measurement.
  static func seedLinks(_ context: MemoryExerciseSession, recordingID: String) async throws -> Int {
    let lines = (context.session.account.entities["transcriptionSegments"] ?? []).filter {
      $0.values["recordingID"] == .string(recordingID)
    }
    let time = context.session.clock.advance()
    // Two hundred links a transaction: a write may expand to at most 256 steps (the outbox's durable delivery limit).
    for chunk in stride(from: 0, to: lines.count, by: 200) {
      try await context.runtime.transact(transaction { txID in
        lines[chunk..<min(lines.count, chunk + 200)].map { link(lineID: $0.id, recordingID: recordingID, at: time, txID: txID) }
      })
    }
    try await MemoryExerciseSession.settle(context.runtime)
    return lines.count
  }
}

/// Counts diagnostics events without allocating per event.
final class MemoryEventCounter: @unchecked Sendable {
  // SAFETY: `lock` guards `count`.
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}
