// History
// 2026-10-24  #1074  Created. The phone's gate reports showed a prune, a server apply, a compaction and an observer's
//                    registration each making writes and reads wait for seconds, but they name only waits past 250 ms,
//                    and no two runs had the same workload. These exercises run Scribe's recording workload, and each
//                    long holder alone, on #1072's real-size store, and print every caller's wait and every holder's
//                    hold, so each fix the concurrency audit names is measured against the same run before and after.
//                    Each write's acknowledgement is timed too: it queues in the frame applier, where no gate sees it.

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// The concurrency audit's exercises (#1074), on #1072's real-size store: `recording` (Scribe's recording load, with a
/// prune a quarter of the way in), `prune`, `prune-inline` (the cadence prune inside the frame applier),
/// `server-apply`, `observers` (registration over a slow socket), `compaction` and `launch`.
///
/// `INSTANT_CONTENTION=1` runs them, one real-size session each (a minute or less once the store is generated; build
/// in release to measure what a phone runs). `INSTANT_CONTENTION_ONLY=recording,prune` picks some,
/// `INSTANT_CONTENTION_SCALE=0.25` a smaller store, `INSTANT_CONTENTION_SECONDS=60` the recording's length. Every number
/// is one `CONTENTION` line (``ContentionReport``); `docs/audits/2026-10-24-concurrency-baseline.txt` holds the first
/// run's lines and `scripts/contention-exercises/run-contention-exercises.sh` runs them the same way again.
enum ContentionExercise {
  static var environment: [String: String] { ProcessInfo.processInfo.environment }

  static var isEnabled: Bool { environment["INSTANT_CONTENTION"] == "1" }

  static func wanted(_ name: String) -> Bool {
    guard let only = environment["INSTANT_CONTENTION_ONLY"], !only.isEmpty else { return true }
    return only.split(separator: ",").contains { $0 == name }
  }

  static var shape: RealSizeShape {
    let scale = environment["INSTANT_CONTENTION_SCALE"].flatMap(Double.init) ?? 1
    return scale == 1 ? .phone : .phone.scaled(scale)
  }

  static var recordingSeconds: Int { environment["INSTANT_CONTENTION_SECONDS"].flatMap(Int.init) ?? 60 }
}

/// What Scribe asks of the library while it records (#1074), at the rates its energy ledger measured on a phone
/// (2026-10-22/23, 5.5 h of recording, builds 113-114): one sequential writer at 90 transacts a minute while talking with
/// the live word preview on (an open line rewritten 3-5 times, then its final), the recording's duration every 5 s,
/// about 63 live observers, about eleven uploads a minute, the status probes; plus a user reading past transcripts, a
/// scenario the ledger did not measure. Each lane makes one call at a time on a fixed schedule; every exercise prints the
/// rates it ran.
struct ContentionWorkload: Sendable {
  /// The writer's slot: a transcript line's write (an open line's revision, then the next line), and every
  /// `heartbeatEvery`-th slot the recording's duration instead.
  var write: Duration = .milliseconds(667)
  var heartbeatEvery = 8
  /// The server's refresh of the open transcript page, as its answer to the device's own writes.
  var echo: Duration = .milliseconds(667)
  /// A past recording's transcript page read through the server (`queryOnce`), and another read locally.
  var read: Duration = .seconds(1)
  /// `pendingMutationCount()` and `connectionStatus()`: Scribe's sync-status probe every 5 s, its health beat, and
  /// its media scan's, together.
  var status: Duration = .milliseconds(2_500)
  /// A file upload (a 60 s audio chunk and ten 6 s compressed segments a minute).
  var upload: Duration? = .milliseconds(5_500)
  /// Live observers open besides the open transcript page.
  var otherObservers = 61

  static let recording = ContentionWorkload()

  /// The focused exercises' load: a write and a local read every 100 ms, the status probes every 250 ms.
  static let focused = ContentionWorkload(
    write: .milliseconds(100), heartbeatEvery: 10, echo: .seconds(3_600), read: .milliseconds(100),
    status: .milliseconds(250), upload: nil, otherObservers: 0
  )

  var fields: [(String, String)] {
    [
      ("write_ms", ContentionReport.milliseconds(write.contentionMilliseconds)),
      ("heartbeat_every", String(heartbeatEvery)),
      ("echo_ms", ContentionReport.milliseconds(echo.contentionMilliseconds)),
      ("read_ms", ContentionReport.milliseconds(read.contentionMilliseconds)),
      ("status_ms", ContentionReport.milliseconds(status.contentionMilliseconds)),
      ("upload_ms", upload.map { ContentionReport.milliseconds($0.contentionMilliseconds) } ?? "none"),
      ("other_observers", String(otherObservers)),
    ]
  }
}

@Suite(
  .serialized,
  .enabled(if: ContentionExercise.isEnabled, "Set INSTANT_CONTENTION=1 to run the concurrency audit's exercises (#1074).")
)
struct ContentionExercises {
  /// Scribe's recording, compressed: transcript lines written as an open segment, the recording's heartbeat, the
  /// server echoing the open transcript page, a past transcript read through the server and another read locally, the
  /// status probes, an upload every few seconds, and the recording screen's observers. A quarter of the way in, the
  /// prune unloads a closed `$files` result (75,640 facts at the phone's size), as the cadence prune did on build 121,
  /// where a 6 s prune made every transact wait 5.0 s.
  @Test func recording() async throws {
    guard ContentionExercise.wanted("recording") else { return }
    let exercise = "recording"
    let workload = ContentionWorkload.recording
    let seconds = ContentionExercise.recordingSeconds
    let harness = try await ContentionHarness.open(exercise)
    let runtime = harness.runtime
    let session = harness.session

    let recording = try await harness.startRecording()
    var leases = [recording.lease]
    for plan in harness.recordingScreenObservers(count: workload.otherObservers) {
      leases.append(try await harness.observeUntilAnswered(plan).lease)
    }
    let closed = try await harness.closeLargeResult()
    try await RealSizeGenerator.waitForSettledOutbox(runtime)
    let scratch = try harness.scratchUpload()

    harness.printSetup(exercise, workload.fields + [("seconds", String(seconds)), ("closed_result_facts", String(closed))])
    let probes = harness.startProbes()
    let observer = harness.measureObserverLag(recording)
    let start = ContentionGateTimeline.now()
    let deadline = ContinuousClock.now + .seconds(seconds)
    let lanes = harness.recordingLanes(workload, recording: recording, scratch: scratch, until: deadline)

    try await Task.sleep(for: .seconds(seconds) / 4)
    let pruneStart = ContentionGateTimeline.now()
    let pruned = try await harness.latencies.time("maintenance.prune") {
      try await runtime.pruneLiveQueryResults(
        policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now()
      )
    }
    let pruneEnd = ContentionGateTimeline.now()
    for lane in lanes { await lane.value }
    let end = ContentionGateTimeline.now()
    observer.cancel()
    await observer.value
    for probe in probes { probe.cancel() }

    harness.printFields(exercise, "prune", [
      ("removed_results", String(pruned.removedQueryKeys.count)),
      ("removed_orphaned_facts", String(pruned.removedOrphanedTripleCount)),
    ])
    harness.report("\(exercise).steady", window: start...pruneStart)
    harness.report("\(exercise).prune", window: pruneStart...pruneEnd)
    harness.report("\(exercise).after", window: pruneEnd...end)
    harness.report("\(exercise).all", window: start...end)
    harness.reportApplies(exercise, window: start...end)
    harness.reportPrunes(exercise, window: start...end)
    harness.reportErrors(exercise)
    for lease in leases { await lease.cancel() }
    await harness.close()

    #expect(!pruned.removedQueryKeys.isEmpty)
    #expect((harness.latencies.recorded["write.line"]?.count ?? 0) > 0)
  }

  /// The prune of one large closed result while a writer writes and a reader reads locally every 100 ms (#654: on
  /// build 121 a 6 s prune made every transact wait 5.0 s). A prune batch takes at least one whole result, so the
  /// `$files` list's 75,640 facts are one batch, one hold.
  @Test func prune() async throws {
    guard ContentionExercise.wanted("prune") else { return }
    let exercise = "prune"
    let harness = try await ContentionHarness.open(exercise)
    let runtime = harness.runtime
    let session = harness.session
    let recording = try await harness.startRecording()
    let closed = try await harness.closeLargeResult()
    try await RealSizeGenerator.waitForSettledOutbox(runtime)

    harness.printSetup(exercise, ContentionWorkload.focused.fields + [("closed_result_facts", String(closed))])
    let (start, holderStart, holderEnd, end) = try await harness.underFocusedLoad(recording) {
      let pruned = try await harness.latencies.time("maintenance.prune") {
        try await runtime.pruneLiveQueryResults(
          policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now()
        )
      }
      harness.printFields(exercise, "prune", [
        ("removed_results", String(pruned.removedQueryKeys.count)),
        ("removed_orphaned_facts", String(pruned.removedOrphanedTripleCount)),
      ])
      #expect(!pruned.removedQueryKeys.isEmpty)
    }
    harness.report("\(exercise).before", window: start...holderStart)
    harness.report("\(exercise).during", window: holderStart...holderEnd)
    harness.report("\(exercise).all", window: start...end)
    harness.reportPrunes(exercise, window: holderStart...holderEnd)
    harness.reportErrors(exercise)
    await recording.lease.cancel()
    await harness.close()
  }

  /// Large server answers applied while a writer writes and a reader reads locally every 100 ms: the `$files` list's
  /// first answer (9,455 files, 75,640 facts at the phone's size; Scribe's `storedFiles()` asks for all of it, #1072),
  /// then the open transcript page's refresh with 256 lines. On the phone a plan held the gate 13,029 ms and a catch-up
  /// 3,899 ms (build 118), and one catch-up 436 s (build 122).
  @Test func serverApply() async throws {
    guard ContentionExercise.wanted("server-apply") else { return }
    let exercise = "server-apply"
    let harness = try await ContentionHarness.open(exercise)
    let runtime = harness.runtime
    let session = harness.session
    let recording = try await harness.startRecording()
    try await RealSizeGenerator.waitForSettledOutbox(runtime)

    harness.printSetup(exercise, ContentionWorkload.focused.fields)
    var filesLease: InstantQueryObservationLease?
    let files = try await harness.underFocusedLoad(recording) {
      let observed = try await harness.latencies.time("observe.files.first-answer") {
        try await harness.observeUntilAnswered(InstantQueryPlan(id: "contention-files", namespace: "$files"))
      }
      filesLease = observed.lease
    }
    harness.report("\(exercise).files", window: files.holderStart...files.holderEnd)

    let lines = (0..<256).map { line in
      RealSizeAccount.segment(
        recordingID: recording.transcript.recordingID, line: line, revision: 4, serial: 0,
        id: RealSizeID.make(.write, 300_000 + line)
      )
    }
    let page = try await harness.underFocusedLoad(recording) {
      let tx = await session.server.refresh(recording.query, rows: lines.map { $0.joinRow() })
      _ = await harness.latencies.time("server.refresh-256.apply") { await harness.applies.wait(for: tx) }
    }
    harness.report("\(exercise).page-256", window: page.holderStart...page.holderEnd)
    harness.report("\(exercise).all", window: files.start...page.end)
    harness.reportApplies(exercise, window: files.start...page.end)
    harness.reportErrors(exercise)
    await filesLease?.cancel()
    await recording.lease.cancel()
    await harness.close()
  }

  /// Twelve observers opened one after another while a writer writes and a reader reads locally every 100 ms, over a
  /// socket whose every send takes 150 ms: each observer sends its query while it holds the operation gate. Every
  /// launch on builds 121-126 held the gate 5.3-5.5 s in "observe standard live query" with about 11 callers queued.
  @Test func observerRegistration() async throws {
    guard ContentionExercise.wanted("observers") else { return }
    let exercise = "observers"
    let sendLatency = Duration.milliseconds(150)
    let harness = try await ContentionHarness.open(exercise) { configuration in
      configuration.liveTransport = configuration.liveTransport?.contentionDelayingSends(by: sendLatency)
    }
    let recording = try await harness.startRecording()
    try await RealSizeGenerator.waitForSettledOutbox(harness.runtime)

    harness.printSetup(exercise, ContentionWorkload.focused.fields + [("send_latency_ms", "150.00"), ("observers", "12")])
    var leases: [InstantQueryObservationLease] = []
    let opened = try await harness.underFocusedLoad(recording) {
      for plan in harness.recordingScreenObservers(count: 12) {
        let observed = try await harness.latencies.time("observe.first-answer") {
          try await harness.observeUntilAnswered(plan)
        }
        leases.append(observed.lease)
      }
    }
    harness.report("\(exercise).before", window: opened.start...opened.holderStart)
    harness.report("\(exercise).opening", window: opened.holderStart...opened.holderEnd)
    harness.report("\(exercise).all", window: opened.start...opened.end)
    harness.reportErrors(exercise)
    for lease in leases { await lease.cancel() }
    await recording.lease.cancel()
    await harness.close()
  }

  /// A `VACUUM` of the real-size store, started at background priority as Scribe starts it (10 s after a recording
  /// stops, while the app may be in use), while a writer writes and a reader reads locally every 100 ms. On the phone
  /// the vacuum phase held the gate 7,596 ms.
  @Test func compaction() async throws {
    guard ContentionExercise.wanted("compaction") else { return }
    let exercise = "compaction"
    let harness = try await ContentionHarness.open(exercise)
    let runtime = harness.runtime
    let session = harness.session
    let recording = try await harness.startRecording()
    // Free pages for the VACUUM to give back: the prune of a large closed result.
    _ = try await harness.closeLargeResult()
    _ = try await runtime.pruneLiveQueryResults(policy: session.configuration.liveQueryResultPruningPolicy, now: session.clock.now())
    try await RealSizeGenerator.waitForSettledOutbox(runtime)
    let before = try await runtime.persistence.localCacheFile()

    harness.printSetup(exercise, ContentionWorkload.focused.fields + [
      ("file_mb", ContentionReport.milliseconds(Double(before.pageCount * before.pageSize) / 1_048_576)),
      ("free_mb", ContentionReport.milliseconds(Double(before.freeByteCount) / 1_048_576)),
    ])
    let compacted = try await harness.underFocusedLoad(recording) {
      let compaction = try await harness.latencies.time("maintenance.compaction") {
        try await Task(priority: .background) {
          try await runtime.compactLocalCache(
            policy: InstantLocalCacheCompactionPolicy(minimumFreeFraction: 0, minimumFreeBytes: 0),
            holdingWhile: { nil }
          )
        }.value
      }
      harness.printFields(exercise, "vacuum", [
        ("outcome", String(describing: compaction.outcome)),
        ("vacuum_ms", ContentionReport.milliseconds(compaction.vacuumDuration?.contentionMilliseconds ?? 0)),
      ])
    }
    harness.report("\(exercise).before", window: compacted.start...compacted.holderStart)
    harness.report("\(exercise).during", window: compacted.holderStart...compacted.holderEnd)
    harness.report("\(exercise).all", window: compacted.start...compacted.end)
    harness.reportErrors(exercise)
    await recording.lease.cancel()
    await harness.close()
  }

  /// The cadence prune as production runs it: inside the frame applier, while it holds the server-apply gate, after a
  /// refresh (every 64th; every one here). A refresh that triggers the prune of a large closed result is followed at
  /// once by a second refresh, which waits behind the first one's prune before it applies: every frame behind it
  /// (acknowledgements included) waits for background maintenance.
  @Test func pruneInline() async throws {
    guard ContentionExercise.wanted("prune-inline") else { return }
    let exercise = "prune-inline"
    let harness = try await ContentionHarness.open(exercise) { configuration in
      configuration.liveQueryResultPruningWriteInterval = 1
    }
    let session = harness.session
    let recording = try await harness.startRecording()
    // The `$files` list stays open until the window: closed earlier, any apply in between (the cadence runs on every
    // one here) would unload it before the measured refreshes.
    let files = try await harness.observeUntilAnswered(InstantQueryPlan(id: "contention-closed-files", namespace: "$files"))
    try await RealSizeGenerator.waitForSettledOutbox(harness.runtime)

    harness.printSetup(exercise, ContentionWorkload.focused.fields + [
      ("closed_result_facts", String(session.shape.accountFiles * RealSizeAccount.fileFields.count))
    ])
    let lines = (0..<64).map { line in
      RealSizeAccount.segment(
        recordingID: recording.transcript.recordingID, line: line, revision: 4, serial: 0,
        id: RealSizeID.make(.write, 400_000 + line)
      )
    }
    let applied = try await harness.underFocusedLoad(recording) {
      // Both refreshes are queued at once; the applier takes them in order, and the first one's inline prune runs
      // while it still holds the server-apply gate, so the second refresh and every acknowledgement queued behind it
      // wait for that prune. Each is timed from the send; the window stays open until the prune has finished.
      await files.lease.cancel()
      let sentAt = ContentionGateTimeline.now()
      let sent = ContinuousClock.now
      let first = await session.server.refresh(recording.query, rows: lines.map { $0.joinRow() })
      let second = await session.server.refresh(recording.query, rows: lines.map { $0.joinRow() })
      await harness.applies.wait(for: first)
      harness.latencies.record("server.refresh.first.applied", startedAt: sentAt, sent.duration(to: .now))
      await harness.applies.wait(for: second)
      harness.latencies.record("server.refresh.second.applied", startedAt: sentAt, sent.duration(to: .now))
      await harness.timeline.waitUntilSettled("pruneLiveQueryResults(policy:now:)", requestedAfter: sentAt)
      harness.latencies.record("server.refreshes.prune-settled", startedAt: sentAt, sent.duration(to: .now))
    }
    harness.report("\(exercise).during", window: applied.holderStart...applied.holderEnd)
    harness.report("\(exercise).all", window: applied.start...applied.end)
    harness.reportApplies(exercise, window: applied.start...applied.end)
    harness.reportPrunes(exercise, window: applied.holderStart...applied.holderEnd)
    harness.reportErrors(exercise)
    await recording.lease.cancel()
    await harness.close()
  }

  /// A launch, as the app makes one: the store is open and the socket is not, and the app registers its observers (62
  /// queries, 7 auth-session streams, 5 connection-status streams) while the socket connects. On builds 121-126 every
  /// launch held the operation gate 5.3-5.5 s in "observe standard live query" with about 11 callers queued, and
  /// "connect live session" held the connection gate 5.5-6.8 s.
  @Test func launch() async throws {
    guard ContentionExercise.wanted("launch") else { return }
    let exercise = "launch"
    let harness = try await ContentionHarness.open(exercise)
    let runtime = harness.runtime
    let latencies = harness.latencies
    // The fixture connects as it opens; close the socket so the observers register before it opens, as at launch.
    _ = try await runtime.closeConnection()
    let plans = [harness.session.transcriptPage(recordingID: RealSizeID.make(.recording, 0))]
      + harness.recordingScreenObservers(count: 61)
    harness.printSetup(exercise, [("observers", String(plans.count)), ("auth_streams", "7"), ("status_streams", "5")])

    let probes = harness.startProbes()
    let start = ContentionGateTimeline.now()
    let leases = ContentionLeaseBag()
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        _ = try await latencies.time("launch.connect") { try await runtime.connect() }
      }
      for plan in plans {
        group.addTask {
          await latencies.time("launch.observe.first-emission") {
            let lease = await runtime.observeQueryLease(plan)
            leases.add(lease)
            for await emission in lease.stream where emission.pageInfo != nil || !emission.values.isEmpty { break }
          }
        }
      }
      for _ in 0..<7 {
        group.addTask {
          try await latencies.time("launch.observeAuthSession.first-value") {
            for await _ in try await runtime.observeAuthSession() { break }
          }
        }
      }
      for _ in 0..<5 {
        group.addTask {
          try await latencies.time("launch.observeConnectionStatus.first-value") {
            for await _ in try await runtime.observeConnectionStatus() { break }
          }
        }
      }
      try await group.waitForAll()
    }
    let end = ContentionGateTimeline.now()
    for probe in probes { probe.cancel() }
    harness.report(exercise, window: start...end)
    harness.reportApplies(exercise, window: start...end)
    harness.reportErrors(exercise)
    for lease in leases.all { await lease.cancel() }
    await harness.close()
  }
}

// MARK: - The harness

/// One exercise's real-size session and its instruments (#1074): the gate's timeline, probes on the persistence actor,
/// the store actor and the main actor, every caller's wall time, every server apply's own record, and each lane's
/// errors.
final class ContentionHarness: Sendable {
  let session: RealSizeSession
  let timeline: ContentionGateTimeline
  let latencies = ContentionLatencies()
  let acceptances: ContentionAcceptances
  let prunes = ContentionEvents("live-query-results.pruned")
  let applies: ContentionApplies
  let errors = ContentionErrors()
  let probes = [ContentionProbe("persistence"), ContentionProbe("store"), ContentionProbe("main")]

  var runtime: InstantRuntime { session.runtime }

  private init(session: RealSizeSession, timeline: ContentionGateTimeline, applies: ContentionApplies) {
    self.session = session
    self.timeline = timeline
    self.applies = applies
    self.acceptances = ContentionAcceptances(latencies: latencies)
  }

  static func open(
    _ label: String,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> ContentionHarness {
    let timeline = ContentionGateTimeline()
    let applies = ContentionApplies()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("contention-sessions", isDirectory: true)
      .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
    let session = try await RealSizeFixture.open(
      ContentionExercise.shape, in: directory, removesDirectory: true,
      configure: { configuration in
        configuration.operationGateTimeline = timeline.record
        configure(&configuration)
      }
    )
    return ContentionHarness(session: session, timeline: timeline, applies: applies)
  }

  func close() async {
    applies.stop()
    acceptances.stop()
    prunes.stop()
    await session.close()
  }

  // MARK: Setup

  /// The recording Scribe has open: its row written, its transcript page observed and answered by the server.
  struct Recording: Sendable {
    var transcript: ContentionTranscript
    var lease: InstantQueryObservationLease
    /// The page's query as the server holds it, for its refreshes.
    var query: InstantLiveJSONValue
  }

  func startRecording() async throws -> Recording {
    let recording = session.newRecording(90_000)
    try await runtime.transact(recording.write)
    let observed = try await observeUntilAnswered(session.transcriptPage(recordingID: recording.id))
    return Recording(
      transcript: ContentionTranscript(recordingID: recording.id, lineBase: 100_000),
      lease: observed.lease,
      query: observed.query
    )
  }

  /// Observes `plan` until the server's answer has been applied (or two minutes pass), and returns the lease and the
  /// query as the server received it.
  ///
  /// The answer's own apply, not the first emission: a store that already holds the rows emits them before the answer
  /// arrives, and an answer applied later (75,640 facts for the `$files` list) would land inside the next measured
  /// window, with the inline prune it may trigger.
  func observeUntilAnswered(_ plan: InstantQueryPlan) async throws -> (lease: InstantQueryObservationLease, query: InstantLiveJSONValue) {
    let added = await session.server.addQueries
    let lease = await runtime.observeQueryLease(plan)
    let query = try await session.server.nextAddQuery(after: added)
    if let answer = await session.server.answerTransaction(for: query) {
      _ = await applies.wait(for: answer, timeout: .seconds(120))
    }
    return (lease, query)
  }

  /// A closed result for the prune to unload: the `$files` list observed until answered, then closed. Returns its
  /// fact count.
  func closeLargeResult() async throws -> Int {
    let observed = try await observeUntilAnswered(InstantQueryPlan(id: "contention-closed-files", namespace: "$files"))
    await observed.lease.cancel()
    return session.shape.accountFiles * RealSizeAccount.fileFields.count
  }

  /// The recording screen's other observers, each query distinct (an identical query shares the first one's
  /// subscription and sends nothing): the recordings list's first pages, then small bounded queries of past
  /// recordings' rows across the namespaces Scribe observes (transcript pages, audio chunks, runtime events, speakers,
  /// agent threads and responses). Scribe's own mix also holds about twenty `$users` access queries with nested
  /// includes, which the generated account does not have.
  func recordingScreenObservers(count: Int) -> [InstantQueryPlan] {
    var plans: [InstantQueryPlan] = (0..<3).map { page in
      InstantQueryPlan(
        id: "contention-recordings-\(page)",
        namespace: "recordings",
        order: InstantQueryOrder("updatedAtMs", .descending),
        offset: page * 12,
        limit: 12
      )
    }
    let namespaces = [
      "transcriptionSegments", "recordingAudioChunks", "recordingRuntimeEvents", "recordingSpeakers", "agentThreads",
      "agentResponses",
    ]
    var index = 0
    while plans.count < count {
      let namespace = namespaces[index % namespaces.count]
      let past = RealSizeID.make(.recording, (index / namespaces.count) % max(1, session.shape.recordings))
      if namespace == "transcriptionSegments" {
        var page = session.transcriptPage(recordingID: past)
        page.id = "contention-transcript-\(index)"
        page.limit = 64
        plans.append(page)
      } else {
        plans.append(
          InstantQueryPlan(
            id: "contention-\(namespace)-\(index)", namespace: namespace,
            filters: [.equals(field: "recordingID", value: .string(past))], limit: 64
          )
        )
      }
      index += 1
    }
    return Array(plans.prefix(count))
  }

  /// A 16 KB file to upload.
  func scratchUpload() throws -> URL {
    let url = session.directory.appendingPathComponent("contention-upload.wav")
    try Data(repeating: 1, count: 16_384).write(to: url)
    return url
  }

  // MARK: Load

  /// Starts the probes; cancel the returned tasks to stop them.
  func startProbes() -> [Task<Void, Never>] {
    let runtime = runtime
    return [
      probes[0].start { _ = await runtime.persistence.run { _ in 0 } },
      probes[1].start { _ = await runtime.store.currentSequence() },
      probes[2].start { await MainActor.run {} },
    ]
  }

  /// Runs `body` on a fixed schedule (every `interval` from the start, skipping the slots a slow call overran) until
  /// `deadline`, one call at a time, as each of Scribe's lanes does. A failed call is counted under `name`.
  func lane(
    _ name: String,
    every interval: Duration,
    until deadline: ContinuousClock.Instant,
    priority: TaskPriority = .userInitiated,
    _ body: @escaping @Sendable (Int) async throws -> Void
  ) -> Task<Void, Never> {
    let errors = errors
    return Task(priority: priority) {
      let start = ContinuousClock.now
      var slot = 0
      var index = 0
      while ContinuousClock.now < deadline, !Task.isCancelled {
        do { try await body(index) } catch { errors.record(name, error) }
        index += 1
        slot = max(slot + 1, Int(((ContinuousClock.now - start) / interval).rounded(.up)))
        try? await Task.sleep(until: start + interval * slot)
      }
    }
  }

  /// The recording's lanes: lines, heartbeat, echo, reads, status probes and uploads.
  func recordingLanes(
    _ workload: ContentionWorkload,
    recording: Recording,
    scratch: URL?,
    until deadline: ContinuousClock.Instant
  ) -> [Task<Void, Never>] {
    let runtime = runtime
    let session = session
    let latencies = latencies
    let acceptances = acceptances
    let applies = applies
    let transcript = recording.transcript
    let pastPage = session.transcriptPage(recordingID: RealSizeID.make(.recording, 1))
    let localPage = session.transcriptPage(recordingID: RealSizeID.make(.recording, 2))
    var lanes = [
      // One sequential writer, as Scribe's recording lane is: lines, and every `heartbeatEvery`-th slot the duration.
      lane("write", every: workload.write, until: deadline) { index in
        if index % workload.heartbeatEvery == workload.heartbeatEvery - 1 {
          var entity = RealSizeAccount.recording(id: transcript.recordingID, index: 90_000)
          entity.values["durationSeconds"] = .number(Double(index))
          let write = InstantStoreTransaction(
            id: UUID().uuidString.lowercased(), operations: entity.mergeOperations(at: session.clock.advance())
          )
          acceptances.expect(write.id, startedAt: ContentionGateTimeline.now())
          try await latencies.time("write.heartbeat") { try await runtime.transact(write) }
        } else {
          let write = transcript.write(index, session: session)
          acceptances.expect(write.id, startedAt: ContentionGateTimeline.now())
          try await latencies.time("write.line") { try await runtime.transact(write) }
        }
      },
      lane("read.queryOnce", every: workload.read, until: deadline) { _ in
        _ = try await latencies.time("read.queryOnce") { try await runtime.queryOnce(pastPage) }
      },
      lane("read.local", every: workload.read, until: deadline) { _ in
        _ = try await latencies.time("read.local") { try await runtime.queryLocally(localPage) }
      },
      lane("status", every: workload.status, until: deadline) { _ in
        _ = await latencies.time("status.pendingMutationCount") { await runtime.pendingMutationCount() }
        _ = try await latencies.time("status.connectionStatus") { try await runtime.connectionStatus() }
      },
      lane("server.echo", every: workload.echo, until: deadline, priority: .medium) { _ in
        let rows = transcript.rows()
        guard !rows.isEmpty else { return }
        let tx = await session.server.refresh(recording.query, rows: rows)
        _ = await latencies.time("server.echo.apply") { await applies.wait(for: tx) }
      },
    ]
    if let upload = workload.upload, let scratch {
      lanes.append(
        lane("upload", every: upload, until: deadline, priority: .utility) { index in
          _ = try await latencies.time("upload.file") {
            try await runtime.uploadFile(from: scratch, name: "scribe/contention/chunk-\(index).wav", contentType: "audio/wav")
          }
        }
      )
    }
    return lanes
  }

  /// Runs the focused load (a line write and a local read every 100 ms, the status probes every 250 ms, the probes)
  /// for a second, then `holder` with the load still running, then a second more; returns the windows on the gate's
  /// clock.
  func underFocusedLoad(
    _ recording: Recording,
    _ holder: () async throws -> Void
  ) async throws -> (start: UInt64, holderStart: UInt64, holderEnd: UInt64, end: UInt64) {
    let workload = ContentionWorkload.focused
    let probeTasks = startProbes()
    let observer = measureObserverLag(recording)
    let stop = ContentionStop()
    let deadline = ContinuousClock.now + .seconds(3_600)
    let runtime = runtime
    let latencies = latencies
    let acceptances = acceptances
    let transcript = recording.transcript
    let session = session
    let localPage = session.transcriptPage(recordingID: RealSizeID.make(.recording, 2))
    let lanes = [
      lane("write.line", every: workload.write, until: deadline) { index in
        guard !stop.isStopped else { throw CancellationError() }
        let write = transcript.write(index, session: session)
        acceptances.expect(write.id, startedAt: ContentionGateTimeline.now())
        try await latencies.time("write.line") { try await runtime.transact(write) }
      },
      lane("read.local", every: workload.read, until: deadline) { _ in
        guard !stop.isStopped else { throw CancellationError() }
        _ = try await latencies.time("read.local") { try await runtime.queryLocally(localPage) }
      },
      lane("status", every: workload.status, until: deadline) { _ in
        guard !stop.isStopped else { throw CancellationError() }
        _ = try await latencies.time("status.connectionStatus") { try await runtime.connectionStatus() }
      },
    ]
    let start = ContentionGateTimeline.now()
    try await Task.sleep(for: .seconds(1))
    let holderStart = ContentionGateTimeline.now()
    try await holder()
    let holderEnd = ContentionGateTimeline.now()
    try await Task.sleep(for: .seconds(1))
    stop.stop()
    for lane in lanes { lane.cancel() }
    for lane in lanes { await lane.value }
    let end = ContentionGateTimeline.now()
    // One iterator at a time on the page's stream: the next window's observer starts after this one has stopped.
    observer.cancel()
    await observer.value
    for probe in probeTasks { probe.cancel() }
    for probe in probeTasks { await probe.value }
    return (start, holderStart, holderEnd, end)
  }

  /// Times, for each line write, how long until the open transcript page's observer emits it: what the recording
  /// screen waits to show a line.
  func measureObserverLag(_ recording: Recording) -> Task<Void, Never> {
    let latencies = latencies
    let transcript = recording.transcript
    let stream = recording.lease.stream
    return Task(priority: .userInitiated) {
      for await emission in stream {
        let now = ContentionGateTimeline.now()
        for startedAt in transcript.satisfied(by: emission) {
          latencies.record("observer.lag", startedAt: startedAt, .nanoseconds(Int64(now &- startedAt)))
        }
        if Task.isCancelled { break }
      }
    }
  }

  // MARK: Report

  func printSetup(_ exercise: String, _ fields: [(String, String)]) {
    printFields(exercise, "setup", [("shape", session.shape.description)] + fields)
  }

  func printFields(_ exercise: String, _ metric: String, _ fields: [(String, String)]) {
    print(ContentionReport.line(exercise, metric, fields))
  }

  @discardableResult
  func report(_ exercise: String, window: ClosedRange<UInt64>) -> [String] {
    ContentionReport.print(
      exercise: exercise,
      gate: ContentionGateAnalysis(timeline.recorded, window: window),
      probes: probes,
      latencies: latencies,
      window: window
    )
  }

  /// Each server apply's own record (the runtime's `server-apply.operation-gate-held`), by path: how long it held the
  /// operation gate, and the planning part of it.
  func reportApplies(_ exercise: String, window: ClosedRange<UInt64>) {
    var byPath: [String: [[String: String]]] = [:]
    for apply in applies.finished(in: window) { byPath[apply["path"] ?? "-", default: []].append(apply) }
    for (path, records) in byPath.sorted(by: { $0.key < $1.key }) {
      func stats(_ key: String) -> ContentionStats { ContentionStats(records.compactMap { $0[key].flatMap(Double.init) }) }
      let held = stats("heldMilliseconds")
      let planning = stats("planningHeldMilliseconds")
      let retried = records.filter { (Int($0["attempt"] ?? "") ?? 1) > 1 }.count
      printFields(exercise, "server.apply", [
        ("path", path), ("n", String(held.count)), ("held_p50_ms", ContentionReport.milliseconds(held.median)),
        ("held_p99_ms", ContentionReport.milliseconds(held.p99)), ("held_worst_ms", ContentionReport.milliseconds(held.worst)),
        ("planning_worst_ms", ContentionReport.milliseconds(planning.worst)), ("retried", String(retried)),
      ])
    }
  }

  /// What the prune batches that finished inside `window` removed, from the runtime's own `live-query-results.pruned`
  /// records: a run whose prune removed nothing did not measure a prune.
  func reportPrunes(_ exercise: String, window: ClosedRange<UInt64>) {
    let batches = prunes.recorded(in: window)
    func sum(_ key: String) -> Int { batches.reduce(0) { $0 + (Int($1[key] ?? "") ?? 0) } }
    printFields(exercise, "prune.batches", [
      ("n", String(batches.count)), ("removed_results", String(sum("removedCount"))),
      ("removed_facts", String(sum("removedOrphanedTripleCount"))),
    ])
  }

  func reportErrors(_ exercise: String) {
    for (lane, (count, first)) in errors.recorded.sorted(by: { $0.key < $1.key }) {
      printFields(exercise, "errors", [("lane", lane), ("n", String(count)), ("first", first)])
    }
    let accepted = latencies.recorded["write.accepted"]?.count ?? 0
    printFields(exercise, "writes", [
      ("accepted", String(accepted)), ("unaccepted_at_close", String(acceptances.unaccepted(since: 0))),
    ])
  }
}

// MARK: - The open transcript

/// The open recording's transcript as the device wrote it (#1074): each write's line and revision, the newest revision
/// of each line for the server's echo, and the writes no observer emission has shown yet.
final class ContentionTranscript: @unchecked Sendable {
  let recordingID: String
  private let lineBase: Int
  // SAFETY: `lock` protects `lines` and `pending`.
  private let lock = NSLock()
  private var lines: [Int: RealSizeEntity] = [:]
  /// A write's line id, its `updatedAtMs` (unique to its line and revision) and when it started, on the gate's clock.
  private var pending: [String: [(updatedAtMs: Double, startedAt: UInt64)]] = [:]

  init(recordingID: String, lineBase: Int) {
    self.recordingID = recordingID
    self.lineBase = lineBase
  }

  /// Write `index` of the transcript: five revisions of line `index / 5`, merged whole, as Scribe writes a line.
  func write(_ index: Int, session: RealSizeSession) -> InstantStoreTransaction {
    let line = index / 5
    let revision = index % 5
    let id = RealSizeID.make(.write, lineBase + line)
    let entity = RealSizeAccount.segment(recordingID: recordingID, line: line, revision: revision, serial: 0, id: id)
    let updatedAtMs: Double = if case .number(let value)? = entity.values["updatedAtMs"] { value } else { 0 }
    let startedAt = ContentionGateTimeline.now()
    lock.withLock {
      lines[line] = entity
      pending[id, default: []].append((updatedAtMs, startedAt))
    }
    return InstantStoreTransaction(
      id: UUID().uuidString.lowercased(), operations: entity.mergeOperations(at: session.clock.advance())
    )
  }

  /// The server's rows of the page: every line at its newest revision.
  func rows() -> [InstantLiveJSONValue] {
    lock.withLock { lines.keys.sorted().compactMap { lines[$0]?.joinRow() } }
  }

  /// The start times of the writes `emission` shows for the first time: a line at that revision or a newer one.
  func satisfied(by emission: InstantQueryEmission) -> [UInt64] {
    var shown: [String: Double] = [:]
    for value in emission.values {
      if case .number(let updatedAtMs)? = value.values["updatedAtMs"]?.first { shown[value.id] = updatedAtMs }
    }
    return lock.withLock {
      var started: [UInt64] = []
      for (id, updatedAtMs) in shown {
        guard let writes = pending[id] else { continue }
        let (done, waiting) = (writes.filter { $0.updatedAtMs <= updatedAtMs }, writes.filter { $0.updatedAtMs > updatedAtMs })
        started += done.map(\.startedAt)
        pending[id] = waiting.isEmpty ? nil : waiting
      }
      return started
    }
  }
}

// MARK: - Server applies, errors, stopping

/// Every server apply the runtime finished in this process, by its processed transaction id, from the runtime's own
/// `server-apply.operation-gate-held` record (#1074), so an exercise waits for an apply without polling and reports
/// how each one held the gate.
final class ContentionApplies: @unchecked Sendable {
  // SAFETY: `lock` protects every stored property below it.
  private let lock = NSLock()
  private var finished: [String: (at: UInt64, metadata: [String: String])] = [:]
  private var waiters: [String: [UUID: CheckedContinuation<[String: String]?, Never>]] = [:]
  private var cancelled: Set<UUID> = []
  private var token: UUID?

  init() {
    let token = InstantDiagnostics.shared.addHandler { [weak self] entry in
      guard let self, entry.event == "server-apply.operation-gate-held", let id = entry.correlationID else { return }
      let at = ContentionGateTimeline.now()
      let resumed = self.lock.withLock { () -> [CheckedContinuation<[String: String]?, Never>] in
        self.finished[id] = (at, entry.metadata)
        return Array((self.waiters.removeValue(forKey: id) ?? [:]).values)
      }
      for waiter in resumed { waiter.resume(returning: entry.metadata) }
    }
    lock.withLock { self.token = token }
  }

  /// Stops listening, and lets every waiter go.
  func stop() {
    let (token, waiting) = lock.withLock { () -> (UUID?, [CheckedContinuation<[String: String]?, Never>]) in
      defer { self.token = nil; self.waiters = [:] }
      return (self.token, self.waiters.values.flatMap(\.values))
    }
    if let token { InstantDiagnostics.shared.removeHandler(token) }
    for waiter in waiting { waiter.resume(returning: nil) }
  }

  /// The record of `transactionID`'s apply once it finished; nil when the waiting task is cancelled first.
  @discardableResult
  func wait(for transactionID: String) async -> [String: String]? {
    let key = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<[String: String]?, Never>) in
        let now: [String: String]?? = lock.withLock {
          if cancelled.remove(key) != nil { return .some(nil) }
          if let done = finished[transactionID] { return .some(done.metadata) }
          waiters[transactionID, default: [:]][key] = continuation
          return .none
        }
        if let now { continuation.resume(returning: now) }
      }
    } onCancel: {
      let waiter = lock.withLock { () -> CheckedContinuation<[String: String]?, Never>? in
        if let waiter = waiters[transactionID]?.removeValue(forKey: key) { return waiter }
        cancelled.insert(key)
        return nil
      }
      waiter?.resume(returning: nil)
    }
  }

  /// The record of `transactionID`'s apply, or nil when `timeout` passes first.
  func wait(for transactionID: String, timeout: Duration) async -> [String: String]? {
    await withTaskGroup(of: [String: String]?.self) { group in
      group.addTask { await self.wait(for: transactionID) }
      group.addTask {
        try? await Task.sleep(for: timeout)
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  /// The records of the applies that finished inside `window`.
  func finished(in window: ClosedRange<UInt64>) -> [[String: String]] {
    lock.withLock { finished.values.filter { window.contains($0.at) }.map(\.metadata) }
  }
}

/// The runtime's own records of one diagnostic event, with when each arrived on the gate's clock (#1074).
final class ContentionEvents: @unchecked Sendable {
  // SAFETY: `lock` protects `events` and `token`; the handler runs on the runtime's tasks.
  private let lock = NSLock()
  private var events: [(at: UInt64, metadata: [String: String])] = []
  private var token: UUID?

  init(_ event: String) {
    let token = InstantDiagnostics.shared.addHandler { [weak self] entry in
      guard let self, entry.event == event else { return }
      let at = ContentionGateTimeline.now()
      self.lock.withLock { self.events.append((at, entry.metadata)) }
    }
    lock.withLock { self.token = token }
  }

  func recorded(in window: ClosedRange<UInt64>) -> [[String: String]] {
    lock.withLock { events.filter { window.contains($0.at) }.map(\.metadata) }
  }

  func stop() {
    let token = lock.withLock { () -> UUID? in
      defer { self.token = nil }
      return self.token
    }
    if let token { InstantDiagnostics.shared.removeHandler(token) }
  }
}

/// Each lane's failed calls: how many, and the first one's error.
final class ContentionErrors: @unchecked Sendable {
  // SAFETY: `lock` protects `errors`.
  private let lock = NSLock()
  private var errors: [String: (count: Int, first: String)] = [:]

  func record(_ lane: String, _ error: any Error) {
    guard !(error is CancellationError) else { return }
    lock.withLock {
      let first = errors[lane]?.first ?? String(String(describing: error).prefix(160))
      errors[lane] = ((errors[lane]?.count ?? 0) + 1, first)
    }
  }

  var recorded: [String: (count: Int, first: String)] { lock.withLock { errors } }
}

/// A flag the focused lanes check before each call, so the load ends right after the holder's window.
final class ContentionStop: @unchecked Sendable {
  // SAFETY: `lock` protects `stopped`.
  private let lock = NSLock()
  private var stopped = false
  var isStopped: Bool { lock.withLock { stopped } }
  func stop() { lock.withLock { stopped = true } }
}

/// The leases a launch's concurrent observers opened, to cancel when it ends.
final class ContentionLeaseBag: @unchecked Sendable {
  // SAFETY: `lock` protects `leases`.
  private let lock = NSLock()
  private var leases: [InstantQueryObservationLease] = []
  func add(_ lease: InstantQueryObservationLease) { lock.withLock { leases.append(lease) } }
  var all: [InstantQueryObservationLease] { lock.withLock { leases } }
}

// MARK: - A slow socket

extension InstantLiveTransportClient {
  /// The same transport with every frame the runtime sends delayed by `latency`, as a slow network's socket send is
  /// (#1074): work done while a send is awaited is work that waits on the network.
  func contentionDelayingSends(by latency: Duration) -> InstantLiveTransportClient {
    let inner = self
    var delayed = InstantLiveTransportClient.connectionAttempts { request in
      let attempt = try inner.makeConnectionAttempt(request)
      return InstantLiveConnectionAttempt(
        connect: {
          let session = try await attempt.connect()
          return InstantLiveWebSocketSession(
            send: { message in
              try await Task.sleep(for: latency)
              try await session.send(message)
            },
            receive: { try await session.receive() },
            close: { await session.close() },
            abort: { session.abort() }
          )
        },
        abort: { attempt.abort() }
      )
    }
    delayed.networkPath = inner.networkPath
    return delayed
  }
}

// MARK: - The instruments' own tests

/// The gate timeline's arithmetic (#1074), on a hand-made timeline: waits, holds, and whom each wait was spent behind.
@Suite("Contention instruments")
struct ContentionInstrumentsTests {
  @Test("a wait is split exactly among the holds it spans, and a window keeps holds that began before it")
  func waitsSplitAmongHolds() {
    func event(_ kind: AsyncSerialGate.TimelineEvent.Kind, _ ticket: UInt64, _ operation: String, _ at: UInt64)
      -> AsyncSerialGate.TimelineEvent
    {
      .init(kind: kind, gate: "operation", ticket: ticket, operation: operation, priority: .interactive, uptimeNanoseconds: at)
    }
    let ms: UInt64 = 1_000_000
    let events = [
      event(.requested, 1, "prune", 0), event(.acquired, 1, "prune", 0),
      event(.requested, 2, "transact", 10 * ms),
      event(.released, 1, "prune", 50 * ms), event(.requested, 3, "apply", 50 * ms), event(.acquired, 3, "apply", 50 * ms),
      event(.released, 3, "apply", 80 * ms), event(.acquired, 2, "transact", 80 * ms),
      event(.released, 2, "transact", 85 * ms),
    ]
    let analysis = ContentionGateAnalysis(events, window: (5 * ms)...(100 * ms))

    #expect(analysis.waits()["transact|interactive"] == [70])
    #expect(analysis.holds()["transact"] == [5])
    #expect(analysis.holds()["prune"] == nil)
    #expect(analysis.behind()[.init(waiter: "transact", holder: "prune")] == [40])
    #expect(analysis.behind()[.init(waiter: "transact", holder: "apply")] == [30])
  }

  @Test("percentiles are nearest-rank")
  func nearestRank() {
    let stats = ContentionStats((1...100).map(Double.init))
    #expect(stats.median == 50)
    #expect(stats.p99 == 99)
    #expect(stats.worst == 100)
    #expect(ContentionStats([]).count == 0)
  }
}
