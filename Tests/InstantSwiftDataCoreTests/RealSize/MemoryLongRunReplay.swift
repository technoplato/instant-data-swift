import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1075 (2026-10-24): the long-run memory exercise. A two-hour recording's writes, reads and uploads, replayed back to
// back against the phone-shaped store (#1072's fixture), with the process's footprint reported at recording minutes 5,
// 60 and 120 and every five minutes between, so a fix's effect on growth over hours is measured the same way before
// and after.
//
// The workload is the phone's, measured over one 118.8-minute recording (the audit's workload map): per minute about
// ten finished lines (each an interim or two of the line in progress, then two writes), twelve duration heartbeats,
// three route updates, an audio chunk row, ten six-second compressed segments (an upload and a two-row write each), a
// minute of WAV uploaded every five minutes, the media scan, and the server's refresh of every open query each write
// touched: the live window (64 lines), the lines in progress (8) and the recordings list (84). The store's own 48
// open queries stay observed throughout, as Scribe's screens keep about 60 open, so their results stay resident.
// Namespaces the generated account lacks are played by ones it has (`MemoryReplayRecording`).
//
// "Minute" is recording time: each minute's work runs as fast as the runtime takes it, so two hours replay in minutes,
// and the session's clock moves sixty seconds a minute, so the library's time-based policies (a stored result written
// at most every 30 s) act as they do on the phone. Growth that depends on work done shows; growth that depends on wall
// time alone (a timer's own allocations) does not, and the audit says so where it matters.
//
// One `MEMORY-REPLAY` line per sample, one `MEMORY-REPLAY-SUMMARY` line at the end:
//
//     MEMORY-REPLAY <label> minute=60 footprintMB=… footprintPeakMB=… heapMB=… triples=… observers=… …
//
// `footprintMB` is `phys_footprint` (what jetsam and Xcode's memory gauge report), `footprintPeakMB` the highest it
// reached since the previous sample, `heapMB` the bytes every malloc zone holds. The harness's own memory is constant
// after minute 0 (the generated account, the window of lines the server answers with); growth is the library's.
//
// `INSTANT_MEMORY_REPLAY=1` runs it (release, alone); `INSTANT_MEMORY_REPLAY_MINUTES` (default 120),
// `INSTANT_MEMORY_REPLAY_SCALE` (the store's size against the phone's, default 1), `INSTANT_MEMORY_REPLAY_SAMPLE_EVERY`
// (minutes, default 5) and `INSTANT_MEMORY_REPLAY_LABEL` change it. Each sample also names the wall time each kind of
// step took since the previous one (`ms.<kind>`), so a cost that grows with the recording names its step. The smoke test below always runs, on a tiny store for three minutes, so the replay cannot rot.
//
// History:
// - 2026-10-24: #1075: the replay, its workload (the phone's two-hour recording) and its report.

@Suite(.serialized)
struct MemoryLongRunReplaySmokeTests {
  @Test func aTinyReplaySamplesEveryMinute() async throws {
    var workload = MemoryReplayWorkload.scribe
    workload.wavBytes = 4_096
    workload.segmentBytes = 1_024
    let samples = try await MemoryReplay.run(
      shape: .phone.scaled(0.01), minutes: 3, workload: workload, label: "smoke", sampleEvery: 1
    )
    #expect(samples.map(\.minute) == [0, 1, 2, 3])
    #expect(samples.allSatisfy { $0.footprint > 0 && $0.heapInUse > 0 })
    // The recording's first write, then three minutes of work.
    #expect(samples.last!.writes == 1 + (1...3).map(workload.writes(inMinute:)).reduce(0, +))
    #expect(samples.last!.uploads == (1...3).map(workload.uploads(inMinute:)).reduce(0, +))
    #expect(samples.last!.pending == 0)
    #expect(samples.last!.emissions > 0)
  }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["INSTANT_MEMORY_REPLAY"] != nil))
struct MemoryLongRunReplay {
  @Test func twoHourRecording() async throws {
    let environment = ProcessInfo.processInfo.environment
    let minutes = environment["INSTANT_MEMORY_REPLAY_MINUTES"].flatMap(Int.init) ?? 120
    let scale = environment["INSTANT_MEMORY_REPLAY_SCALE"].flatMap(Double.init) ?? 1
    let shape = scale == 1 ? RealSizeShape.phone : RealSizeShape.phone.scaled(scale)
    let label = environment["INSTANT_MEMORY_REPLAY_LABEL"] ?? (scale == 1 ? "phone" : "x\(scale)")
    let sampleEvery = environment["INSTANT_MEMORY_REPLAY_SAMPLE_EVERY"].flatMap(Int.init) ?? 5
    let samples = try await MemoryReplay.run(
      shape: shape, minutes: minutes, workload: .scribe, label: label, sampleEvery: sampleEvery
    )
    #expect(samples.last?.minute == minutes)
  }
}

/// What a recording does to the library each minute: Scribe's, measured on the phone over a two-hour recording.
struct MemoryReplayWorkload: Sendable, CustomStringConvertible {
  /// Finished transcript lines a minute (9.5 measured).
  var linesPerMinute = 10
  /// Interim writes of each line in progress before it finishes, line by line in turn (14.2 a minute measured).
  var interimsPerLine = [1, 2]
  /// Duration heartbeats of the recording's row a minute (every 5 s).
  var heartbeatsPerMinute = 12
  /// Route updates a minute, each adding `routeSamplesPerUpdate` samples to the chunk, a new chunk at 128.
  var routeUpdatesPerMinute = 3
  var routeSamplesPerUpdate = 10
  /// A minute of WAV: its row each minute, and its upload (then the row again) every `wavUploadEveryMinutes`: held on
  /// cellular and battery, as in the measured recording (every minute on Wi-Fi).
  var wavUploadEveryMinutes = 5
  var wavBytes = 5_760_044
  /// Six-second compressed segments a minute (since build 120): an upload and a write of two rows each.
  var segmentsPerMinute = 10
  var segmentBytes = 24_576
  /// Other rows a minute (runtime events, sounds).
  var otherRowsPerMinute = 1
  /// The open queries' sizes: the live window, the lines in progress, the recordings list (seven pages of twelve).
  var windowRows = 64
  var liveLineRows = 8
  var listRows = 84
  /// `pendingMutationCount()` polls a minute (the sync status, every 5 s).
  var pendingPollsPerMinute = 12
  /// The media scan, once a minute: three pending counts, two local looks closed at their first answer, one server
  /// query of the recording's attachments.
  var mediaScansPerMinute = 1
  /// Reconnects: one every this many minutes (about three in two hours measured), or none.
  var reconnectEveryMinutes: Int? = 40
  /// The library's own prune of closed results, every this many server applies (its default).
  var pruneWriteInterval = 64

  static let scribe = MemoryReplayWorkload()

  func interims(ofLine line: Int) -> Int { interimsPerLine[line % interimsPerLine.count] }

  func uploadsWAV(inMinute minute: Int) -> Bool { minute % wavUploadEveryMinutes == 0 }

  /// The writes of recording minute `minute` (from 1).
  func writes(inMinute minute: Int) -> Int {
    let lineWrites = (0..<linesPerMinute).map { interims(ofLine: (minute - 1) * linesPerMinute + $0) + 2 }.reduce(0, +)
    return lineWrites + heartbeatsPerMinute + routeUpdatesPerMinute + 1 + (uploadsWAV(inMinute: minute) ? 1 : 0)
      + segmentsPerMinute + otherRowsPerMinute
  }

  func uploads(inMinute minute: Int) -> Int { segmentsPerMinute + (uploadsWAV(inMinute: minute) ? 1 : 0) }

  var description: String {
    "lines/min=\(linesPerMinute) interims=\(interimsPerLine.map(String.init).joined(separator: ","))"
      + " heartbeats/min=\(heartbeatsPerMinute) routes/min=\(routeUpdatesPerMinute) wavEvery=\(wavUploadEveryMinutes)min"
      + "x\(wavBytes)B segments/min=\(segmentsPerMinute)x\(segmentBytes)B others/min=\(otherRowsPerMinute)"
      + " window=\(windowRows) liveLines=\(liveLineRows) list=\(listRows) polls/min=\(pendingPollsPerMinute)"
      + " scans/min=\(mediaScansPerMinute) reconnectEvery=\(reconnectEveryMinutes.map { "\($0)min" } ?? "never")"
      + " pruneEvery=\(pruneWriteInterval)"
  }
}

/// One sample of the replay: the process's memory and the library's sizes after `minute` minutes of the recording.
struct MemoryReplaySample: Sendable {
  var minute: Int
  var footprint: UInt64
  var footprintPeak: UInt64
  var heapInUse: Int
  var triples: Int
  var observers: Int
  var pending: Int
  var writes: Int
  var uploads: Int
  var emissions: Int
  var framesToClient: Int
  var bytesToClient: Int
  var largestFrameToClient: Int
  var resultJSONWrites: Int
  var resultJSONBytes: Int
  var fullStoreLoads: Int
  var storeReplacements: Int
  var fullStoreCopies: Int
  var connections: Int
  var wallSeconds: Double
  /// Wall time each kind of step took since the previous sample, in milliseconds, by kind.
  var stepMilliseconds: [(String, Int)] = []

  func line(_ label: String) -> String {
    func mb(_ bytes: some BinaryInteger) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }
    let fields: [(String, String)] = [
      ("minute", String(minute)),
      ("footprintMB", mb(footprint)),
      ("footprintPeakMB", mb(footprintPeak)),
      ("heapMB", mb(heapInUse)),
      ("triples", String(triples)),
      ("observers", String(observers)),
      ("pending", String(pending)),
      ("writes", String(writes)),
      ("uploads", String(uploads)),
      ("emissions", String(emissions)),
      ("framesIn", String(framesToClient)),
      ("bytesInMB", mb(bytesToClient)),
      ("largestFrameKB", String(largestFrameToClient / 1_024)),
      ("resultWrites", String(resultJSONWrites)),
      ("resultWrittenMB", mb(resultJSONBytes)),
      ("fullStoreLoads", String(fullStoreLoads)),
      ("storeReplacements", String(storeReplacements)),
      ("fullStoreCopies", String(fullStoreCopies)),
      ("connections", String(connections)),
      ("wallS", String(format: "%.1f", wallSeconds)),
    ] + stepMilliseconds.map { ("ms." + $0.0, String($0.1)) }
    return "MEMORY-REPLAY \(label) " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
  }
}

enum MemoryReplay {
  /// The queries #1072's generator left open in the store (`RealSizeGenerator`, step 3), the same plans: a transcript
  /// page of the longest recording, every recording, and the other namespaces' newest 200 by kind.
  static func openQueryPlans(shape: RealSizeShape) -> [InstantQueryPlan] {
    var plans: [InstantQueryPlan] = [
      InstantQueryPlan(
        id: "real-size-transcript-\(RealSizeID.make(.recording, 0))-0", namespace: "transcriptionSegments",
        filters: [
          .equals(field: "recordingID", value: .string(RealSizeID.make(.recording, 0))),
          .greaterThanOrEqual(field: "segmentIndex", value: .number(0)),
        ],
        order: InstantQueryOrder("segmentIndex"), limit: 256
      ),
      InstantQueryPlan(
        id: "real-size-recordings", namespace: "recordings", order: InstantQueryOrder("updatedAtMs", .descending),
        selectedFields: RealSizeAccount.recordingFields.filter { $0 != "id" }
      ),
    ]
    var index = 0
    while plans.count < shape.openQueries {
      plans.append(
        InstantQueryPlan(
          id: "real-size-open-\(index)", namespace: RealSizeAccount.otherNamespaces[index % RealSizeAccount.otherNamespaces.count],
          filters: [.equals(field: "kind", value: .string("kind-\(index % 7)"))], order: InstantQueryOrder("updatedAtMs", .descending),
          limit: 200
        )
      )
      index += 1
    }
    return plans
  }

  /// Replays `minutes` minutes of a recording and returns a sample at minute 0 and every `sampleEvery` minutes (and
  /// at the last minute), printing each one's line.
  static func run(
    shape: RealSizeShape,
    minutes: Int,
    workload: MemoryReplayWorkload,
    label: String,
    sampleEvery: Int = 5
  ) async throws -> [MemoryReplaySample] {
    let context = try await MemoryExerciseSession.open(shape, label: "replay-\(label)") { configuration in
      configuration.liveQueryResultPruningWriteInterval = workload.pruneWriteInterval
    }
    return try await context.closing { context in
      try await replay(context, shape: shape, minutes: minutes, workload: workload, label: label, sampleEvery: sampleEvery)
    }
  }

  private static func replay(
    _ context: MemoryExerciseSession,
    shape: RealSizeShape,
    minutes: Int,
    workload: MemoryReplayWorkload,
    label: String,
    sampleEvery: Int
  ) async throws -> [MemoryReplaySample] {
    let session = context.session
    let runtime = context.runtime
    let server = context.server
    let applies = context.waitApplies
    let replay = MemoryReplayRecording(session: session, workload: workload)
    // The account's newest recordings, for the list's answer: computed once, so the harness does not grow.
    let listQueryJSON = InstantLiveJSONValue.object([
      "recordings": .object(["$": .object(["order": .object(["updatedAtMs": .string("desc")]), "limit": .number(Double(workload.listRows))])])
    ])
    replay.setAccountListRows(await session.server.rows(answering: listQueryJSON))
    await server.setAnswer { [replay, account = session.server] query in
      if let rows = replay.rows(answering: query) { return rows }
      return await account.rows(answering: query)
    }
    let wav = session.directory.appendingPathComponent("chunk.wav")
    try Data(repeating: 0x5a, count: workload.wavBytes).write(to: wav)
    let segment = session.directory.appendingPathComponent("segment.m4a")
    try Data(repeating: 0x5b, count: workload.segmentBytes).write(to: segment)

    print("MEMORY-REPLAY-START \(label) shape=[\(shape)] workload=[\(workload)] minutes=\(minutes)")
    let started = ContinuousClock.now
    var samples: [MemoryReplaySample] = []
    var uploads = 0
    var stepTime: [String: Duration] = [:]
    var energy = InstantEnergyMeter.snapshot()

    // The recording starts: its row, then the screen's queries.
    try await runtime.transact(replay.recordingWrite())
    let emissions = MemoryReplayEmissionCounter()
    var leases: [InstantQueryObservationLease] = []
    var queries: [InstantLiveJSONValue] = []
    var readers: [Task<Void, Never>] = []
    for plan in [replay.windowPlan, replay.liveLinesPlan, MemoryExerciseSession.listPlan] {
      let added = await server.addQueries
      let lease = await runtime.observeQueryLease(plan)
      queries.append(await server.nextAddQuery(after: added))
      _ = try await MemoryStreams.first(lease.stream, "replay: \(plan.id)'s first emission") { _ in true }
      leases.append(lease)
      readers.append(emissions.read(lease))
    }
    let (windowQuery, liveLinesQuery, listQuery) = (queries[0], queries[1], queries[2])
    // The rest of what Scribe keeps open while it records (62-64 observers on the phone): the store's own open queries,
    // so their results stay resident as on the phone (47k facts at minute 5) instead of going with the first prune.
    for plan in MemoryReplay.openQueryPlans(shape: shape) {
      let lease = await runtime.observeQueryLease(plan)
      _ = try await MemoryStreams.first(lease.stream, "replay: \(plan.id)'s first emission") { _ in true }
      leases.append(lease)
      readers.append(emissions.read(lease))
    }

    func refresh(window: Bool = false, liveLines: Bool = false, list: Bool = false) async throws {
      try await MemoryExerciseSession.waitUntilAcknowledged(runtime)
      var results: [(query: InstantLiveJSONValue, rows: [InstantLiveJSONValue])] = []
      if window { results.append((windowQuery, replay.windowRows())) }
      if liveLines { results.append((liveLinesQuery, replay.liveLineRows())) }
      if list { results.append((listQuery, replay.listRows())) }
      try await applies.wait(for: await server.refresh(results))
    }

    func sample(_ minute: Int) async throws {
      try await MemoryExerciseSession.settle(runtime)
      let usage = RealSizeProcess.usage()
      let metrics = await runtime.persistenceCacheResidencyMetricsForTesting()
      let written = await runtime.liveQueryResultJSONWriteStatsForTesting()
      let now = ContinuousClock.now - started
      let sample = MemoryReplaySample(
        minute: minute,
        footprint: usage.footprint,
        footprintPeak: max(usage.footprintIntervalPeak, usage.footprint),
        heapInUse: RealSizeProcess.zoneBytesInUse(),
        triples: await runtime.store.currentTripleCount(),
        observers: await runtime.store.activeObservationCount(),
        pending: await runtime.pendingMutationCount(),
        writes: replay.writes,
        uploads: uploads,
        emissions: emissions.count,
        framesToClient: await server.framesToClient,
        bytesToClient: await server.bytesToClient,
        largestFrameToClient: await server.largestFrameToClient,
        resultJSONWrites: written.writes,
        resultJSONBytes: written.bytes,
        fullStoreLoads: metrics.fullStoreSnapshotLoadCount,
        storeReplacements: metrics.storeSnapshotReplacementCount,
        fullStoreCopies: await runtime.store.fullCopyCountForTesting,
        connections: await server.connections,
        wallSeconds: Double(now.components.seconds) + Double(now.components.attoseconds) / 1e18,
        stepMilliseconds: stepTime.keys.sorted().map { key in
          let time = stepTime[key]!
          return (key, Int(time.components.seconds * 1_000 + time.components.attoseconds / 1_000_000_000_000_000))
        } + {
          // The library's own metered operations over the same minutes (`InstantEnergyMeter`), by wall time.
          let delta = InstantEnergyMeter.snapshot().subtracting(energy)
          return InstantEnergyOperation.allCases.compactMap { operation in
            let milliseconds = Int(delta[operation].wallNanoseconds / 1_000_000)
            return milliseconds == 0 ? nil : ("op." + operation.rawValue, milliseconds)
          }
        }()
      )
      stepTime.removeAll(keepingCapacity: true)
      energy = InstantEnergyMeter.snapshot()
      samples.append(sample)
      print(sample.line(label))
      RealSizeProcess.resetFootprintPeak()
    }

    try await sample(0)
    for minute in 1...minutes {
      if let every = workload.reconnectEveryMinutes, minute % every == every / 2 {
        let reconnectStarted = ContinuousClock.now
        defer { stepTime["reconnect", default: .zero] += ContinuousClock.now - reconnectStarted }
        let added = await server.addQueries
        _ = try await runtime.closeConnection()
        _ = try await runtime.connect()
        let deadline = ContinuousClock.now + .seconds(120)
        while await server.addQueries < added + leases.count {
          guard ContinuousClock.now < deadline else { throw MemoryStreams.Timeout(description: "replay: queries not added again") }
          try await Task.sleep(for: .milliseconds(1))
        }
        try await MemoryExerciseSession.settle(runtime)
      }
      for step in replay.steps(inMinute: minute) {
        replay.moveClock(toMinute: minute, millisecond: step.millisecond)
        let stepStarted = ContinuousClock.now
        defer { stepTime[step.kind.name, default: .zero] += ContinuousClock.now - stepStarted }
        switch step.kind {
        case .interim(let line, let part):
          try await runtime.transact(replay.interimWrite(line: line, part: part))
          try await refresh(liveLines: true)
        case .finalLine(let line):
          try await runtime.transact(replay.finalWrite(line: line))
          try await refresh(window: true, liveLines: true, list: true)
        case .speakers(let line):
          try await runtime.transact(replay.speakersWrite(line: line))
          try await refresh(list: true)
        case .heartbeat:
          try await runtime.transact(replay.heartbeatWrite(minute: minute))
          try await refresh(list: true)
        case .route:
          try await runtime.transact(replay.routeWrite())
        case .chunkRow(let uploaded):
          try await runtime.transact(replay.chunkWrite(minute: minute, uploaded: uploaded))
        case .chunkUpload:
          _ = try await runtime.uploadFile(
            from: wav, name: "scribe/\(replay.recordingID)/audio-chunks/\(String(format: "%06d", minute)).wav",
            contentType: "audio/wav"
          )
          uploads += 1
        case .segment(let index):
          _ = try await runtime.uploadFile(
            from: segment, name: "scribe/\(replay.recordingID)/audio-stream/\(String(format: "%06d", index)).m4a",
            contentType: "audio/mp4"
          )
          uploads += 1
          try await runtime.transact(replay.segmentRowsWrite(index: index))
        case .otherRow(let index):
          try await runtime.transact(replay.otherRowWrite(index: index))
        case .pendingPoll:
          _ = await runtime.pendingMutationCount()
        case .mediaScan:
          for _ in 0..<3 { _ = await runtime.pendingMutationCount() }
          for plan in replay.mediaScanPlans {
            let lease = await runtime.observeQueryLease(plan)
            _ = try await MemoryStreams.first(lease.stream, "replay: the media scan's \(plan.id)") { _ in true }
            await lease.cancel()
          }
          _ = try await runtime.queryOnce(replay.mediaScanServerPlan)
        }
      }
      if minute % sampleEvery == 0 || minute == minutes { try await sample(minute) }
    }

    let first = samples.first { $0.minute == 5 } ?? samples[0]
    let middle = samples.first { $0.minute == 60 } ?? samples[samples.count / 2]
    let last = samples[samples.count - 1]
    func mb(_ bytes: Int64) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }
    let hours = max(Double(last.minute - first.minute) / 60, 1.0 / 60)
    print(
      "MEMORY-REPLAY-SUMMARY \(label) minutes=\(minutes)"
        + " footprint0MB=\(mb(Int64(samples[0].footprint))) footprint5MB=\(mb(Int64(first.footprint)))"
        + " footprint60MB=\(mb(Int64(middle.footprint))) footprint120MB=\(mb(Int64(last.footprint)))"
        + " growth5to60MB=\(mb(Int64(middle.footprint) - Int64(first.footprint)))"
        + " growth60to120MB=\(mb(Int64(last.footprint) - Int64(middle.footprint)))"
        + " footprintPerHourMB=\(String(format: "%.1f", (Double(last.footprint) - Double(first.footprint)) / 1_048_576 / hours))"
        + " heapPerHourMB=\(String(format: "%.1f", Double(last.heapInUse - first.heapInUse) / 1_048_576 / hours))"
        + " peakMB=\(mb(Int64(samples.map(\.footprintPeak).max() ?? 0)))"
        + " triples5=\(first.triples) triples60=\(middle.triples) triples120=\(last.triples)"
        + " wallS=\(String(format: "%.0f", last.wallSeconds))"
    )

    for lease in leases { await lease.cancel() }
    for reader in readers { reader.cancel() }
    return samples
  }
}

/// The recording being replayed: its rows as the device writes them and as the server answers with them. Only what
/// the open queries need is kept (the newest window of lines, the line in progress), so the harness does not grow.
///
/// Namespaces Scribe writes that the generated account lacks are played by ones it has, with the same sixteen-value
/// rows: the lines in progress (`liveLines`) by `recordingSpeakers`, route chunks by `agentFenceposts`, the compressed
/// segments' rows (`progressiveMediaSegments`, nine values) by `recordingSounds`. Every write has Scribe's shape (`MemoryScribeWrites`): rows inserted, the
/// recording updated where it exists, each finished line linked to the recording, the line in progress deleted.
final class MemoryReplayRecording: @unchecked Sendable {
  enum StepKind: Sendable {
    case interim(line: Int, part: Int)
    case finalLine(Int)
    case speakers(Int)
    case heartbeat
    case route
    case chunkRow(uploaded: Bool)
    case chunkUpload
    case segment(Int)
    case otherRow(Int)
    case pendingPoll
    case mediaScan

    /// The step's name in a sample's timings.
    var name: String {
      switch self {
      case .interim: "interim"
      case .finalLine: "final"
      case .speakers: "speakers"
      case .heartbeat: "heartbeat"
      case .route: "route"
      case .chunkRow: "chunkRow"
      case .chunkUpload: "wavUpload"
      case .segment: "segment"
      case .otherRow: "other"
      case .pendingPoll: "poll"
      case .mediaScan: "scan"
      }
    }
  }

  struct Step: Sendable {
    var millisecond: Int
    var kind: StepKind
  }

  static let liveLinesNamespace = "recordingSpeakers"
  static let routeNamespace = "agentFenceposts"
  static let segmentNamespace = "recordingSounds"
  static let chunkNamespace = "recordingAudioChunks"
  static let otherNamespace = "recordingRuntimeEvents"

  // SAFETY: `lock` guards every stored `var`; the replay drives it from one task, the server's answer reads it.
  private let lock = NSLock()
  let recordingID: String
  private let session: RealSizeSession
  private let workload: MemoryReplayWorkload
  private var recording: RealSizeEntity
  /// The newest lines, newest first, at most `workload.windowRows`.
  private var window: [RealSizeEntity] = []
  private var liveLine: RealSizeEntity?
  private var route: RealSizeEntity?
  private var routeSamples = 0
  private var routeChunk = 0
  private var accountListRows: [InstantLiveJSONValue] = []
  private var writeCount = 0

  /// Transactions written so far.
  var writes: Int { lock.withLock { writeCount } }

  init(session: RealSizeSession, workload: MemoryReplayWorkload) {
    self.session = session
    self.workload = workload
    let index = 900_000
    recordingID = RealSizeID.make(.write, index)
    recording = RealSizeAccount.recording(id: recordingID, index: index)
  }

  // MARK: - The minute's schedule

  /// Recording minute `minute`'s steps, in time order: each at its millisecond into the minute.
  func steps(inMinute minute: Int) -> [Step] {
    var steps: [Step] = []
    let lineSpacing = 60_000 / max(1, workload.linesPerMinute)
    for slot in 0..<workload.linesPerMinute {
      let line = (minute - 1) * workload.linesPerMinute + slot
      let base = slot * lineSpacing
      let interims = workload.interims(ofLine: line)
      for part in 0..<interims {
        steps.append(Step(millisecond: base + (part + 1) * lineSpacing / (interims + 2), kind: .interim(line: line, part: part)))
      }
      steps.append(Step(millisecond: base + lineSpacing - 900, kind: .finalLine(line)))
      steps.append(Step(millisecond: base + lineSpacing - 800, kind: .speakers(line)))
    }
    let segmentSpacing = 60_000 / max(1, workload.segmentsPerMinute)
    for slot in 0..<workload.segmentsPerMinute {
      steps.append(Step(millisecond: slot * segmentSpacing + segmentSpacing - 100, kind: .segment((minute - 1) * workload.segmentsPerMinute + slot)))
    }
    let heartbeatSpacing = 60_000 / max(1, workload.heartbeatsPerMinute)
    for slot in 0..<workload.heartbeatsPerMinute {
      steps.append(Step(millisecond: slot * heartbeatSpacing + heartbeatSpacing / 2, kind: .heartbeat))
    }
    let routeSpacing = 60_000 / max(1, workload.routeUpdatesPerMinute)
    for slot in 0..<workload.routeUpdatesPerMinute {
      steps.append(Step(millisecond: slot * routeSpacing + routeSpacing / 2, kind: .route))
    }
    let pollSpacing = 60_000 / max(1, workload.pendingPollsPerMinute)
    for slot in 0..<workload.pendingPollsPerMinute {
      steps.append(Step(millisecond: slot * pollSpacing + 100, kind: .pendingPoll))
    }
    steps.append(Step(millisecond: 500, kind: .chunkRow(uploaded: false)))
    if workload.uploadsWAV(inMinute: minute) {
      steps.append(Step(millisecond: 30_000, kind: .chunkUpload))
      steps.append(Step(millisecond: 30_100, kind: .chunkRow(uploaded: true)))
    }
    for slot in 0..<workload.otherRowsPerMinute {
      steps.append(Step(millisecond: 45_000 + slot * 100, kind: .otherRow((minute - 1) * workload.otherRowsPerMinute + slot)))
    }
    for slot in 0..<workload.mediaScansPerMinute {
      steps.append(Step(millisecond: 50_000 + slot * 100, kind: .mediaScan))
    }
    return steps.sorted { $0.millisecond < $1.millisecond }
  }

  /// Moves the session's clock to `millisecond` into recording minute `minute` (never back).
  func moveClock(toMinute minute: Int, millisecond: Int) {
    let target = RealSizeAccount.epoch.milliseconds + Int64((minute - 1) * 60_000 + millisecond)
    let now = session.clock.now().milliseconds
    if target > now { _ = session.clock.advance(by: target - now) }
  }

  // MARK: - Queries

  /// The live window: the recording's newest lines, newest first.
  var windowPlan: InstantQueryPlan {
    MemoryExerciseSession.tailPlan(id: "replay-window", recordingID: recordingID, rows: workload.windowRows)
  }

  /// The lines in progress.
  var liveLinesPlan: InstantQueryPlan {
    InstantQueryPlan(
      id: "replay-live-lines", namespace: Self.liveLinesNamespace,
      filters: [.equals(field: "recordingID", value: .string(recordingID))], limit: workload.liveLineRows
    )
  }

  /// The media scan's local looks: the recording's attachments and its newest audio chunks.
  var mediaScanPlans: [InstantQueryPlan] {
    [
      InstantQueryPlan(
        id: "replay-scan-attachments", namespace: "recordingAttachments",
        filters: [.equals(field: "recordingID", value: .string(recordingID))], limit: 100
      ),
      InstantQueryPlan(
        id: "replay-scan-chunks", namespace: Self.chunkNamespace,
        filters: [.equals(field: "recordingID", value: .string(recordingID))],
        order: InstantQueryOrder("createdAtMs", .descending), limit: 16
      ),
    ]
  }

  /// The media scan's server query of the recording's attachments.
  var mediaScanServerPlan: InstantQueryPlan {
    InstantQueryPlan(
      id: "replay-scan-attachments-server", namespace: "recordingAttachments",
      filters: [.equals(field: "recordingID", value: .string(recordingID))], limit: 100
    )
  }

  func setAccountListRows(_ rows: [InstantLiveJSONValue]) {
    lock.withLock { accountListRows = Array(rows.prefix(max(0, workload.listRows - 1))) }
  }

  func windowRows() -> [InstantLiveJSONValue] { lock.withLock { window.map { $0.joinRow() } } }
  func liveLineRows() -> [InstantLiveJSONValue] { lock.withLock { liveLine.map { [$0.joinRow()] } ?? [] } }
  func listRows() -> [InstantLiveJSONValue] {
    lock.withLock { [recording.joinRow(fields: RealSizeAccount.recordingFields)] + accountListRows }
  }

  /// The server's answer to a query of this recording's lines, lines in progress or the list, or nil for any other.
  func rows(answering query: InstantLiveJSONValue) -> [InstantLiveJSONValue]? {
    guard case .object(let root) = query, let entry = root.first else { return nil }
    let (namespace, top) = (entry.key, entry.value)
    if namespace == "recordings" {
      // Only the list (its limit); the store's own query of every recording is the account's.
      guard case .object(let options)? = top.objectValue?["$"], options["limit"] == .number(Double(workload.listRows)) else {
        return nil
      }
      return listRows()
    }
    guard case .object(let options)? = top.objectValue?["$"], case .object(let clause)? = options["where"],
      Self.mentions(clause, recordingID)
    else { return nil }
    switch namespace {
    case "transcriptionSegments": return windowRows()
    case Self.liveLinesNamespace: return liveLineRows()
    default: return nil
    }
  }

  private static func mentions(_ clause: [String: InstantLiveJSONValue], _ id: String) -> Bool {
    for (field, condition) in clause {
      if field == "recordingID", condition == .string(id) { return true }
      if field == "and" || field == "or", let parts = condition.arrayValue {
        for case .object(let part) in parts where mentions(part, id) { return true }
      }
    }
    return false
  }

  // MARK: - Writes (Scribe's shapes: `MemoryScribeWrites`)

  private func transaction(_ operations: (String) -> [InstantTripleOperation]) -> InstantStoreTransaction {
    writeCount += 1
    return MemoryScribeWrites.transaction(operations)
  }

  /// The recording's row, created.
  func recordingWrite() -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      return transaction { MemoryScribeWrites.update(recording, at: time, txID: $0) }
    }
  }

  /// The line in progress, written again with more words (`liveLines.update`).
  func interimWrite(line: Int, part: Int) -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      let entity = MemoryScribeWrites.liveLine(recordingID: recordingID, line: line, words: 3 + part * 3, at: time)
      liveLine = entity
      return transaction { MemoryScribeWrites.update(entity, at: time, txID: $0) }
    }
  }

  /// The line finished: the recording's `updatedAtMs`, the line's sixteen values and its link, and the line in
  /// progress deleted, in one transaction.
  func finalWrite(line: Int) -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      let segment = RealSizeAccount.segment(
        recordingID: recordingID, line: line, revision: 4, serial: 0, id: RealSizeID.make(.write, 1_000_000 + line)
      )
      window.insert(segment, at: 0)
      if window.count > workload.windowRows { window.removeLast(window.count - workload.windowRows) }
      recording.values["updatedAtMs"] = .number(Double(time.milliseconds))
      let live = liveLine.map { ($0.id, $0.namespace) }
      liveLine = nil
      writeCount += 1
      return MemoryScribeWrites.finalLine(segment, recording: recording, liveLine: live, at: time)
    }
  }

  /// The line's second write: the recording's speakers (about 330 bytes of JSON).
  func speakersWrite(line: Int) -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      recording.values["speakers"] = .string(
        "[" + (0..<3).map { "{\"speaker\":\($0),\"name\":\"Speaker \($0)\",\"lines\":\(line + $0),\"seconds\":\(line * 4)}" }.joined(separator: ",") + "]"
      )
      recording.values["updatedAtMs"] = .number(Double(time.milliseconds))
      let recording = recording
      return transaction { MemoryScribeWrites.updateExisting(recording, fields: ["speakers", "updatedAtMs"], at: time, txID: $0) }
    }
  }

  /// The duration heartbeat.
  func heartbeatWrite(minute: Int) -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      recording.values["durationSeconds"] = .number(Double(time.milliseconds - RealSizeAccount.epoch.milliseconds) / 1_000)
      recording.values["updatedAtMs"] = .number(Double(time.milliseconds))
      let recording = recording
      return transaction { MemoryScribeWrites.updateExisting(recording, fields: ["durationSeconds", "updatedAtMs"], at: time, txID: $0) }
    }
  }

  /// The route chunk, its samples JSON growing to 128 samples (about 32 KiB), then a new chunk: created whole, then
  /// updated (`updateExisting`).
  func routeWrite() -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      if route == nil || routeSamples >= 128 {
        routeChunk += 1
        routeSamples = 0
      }
      routeSamples = min(128, routeSamples + workload.routeSamplesPerUpdate)
      let sample = "{\"lat\":40.7128000,\"lon\":-74.0060000,\"alt\":12.5,\"acc\":4.8,\"speed\":1.25,\"course\":182.5,\"t\":1792800000000,\"floor\":null,\"src\":\"gps\",\"pad\":\"" + String(repeating: "x", count: 64) + "\"}"
      let entity = MemoryScribeWrites.row(
        Self.routeNamespace, id: RealSizeID.make(.write, 4_000_000 + routeChunk), recordingID: recordingID, kind: "route",
        payload: "[" + Array(repeating: sample, count: routeSamples).joined(separator: ",") + "]", at: time
      )
      let fresh = route?.id != entity.id
      route = entity
      return transaction { txID in
        fresh
          ? MemoryScribeWrites.update(entity, at: time, txID: txID)
          : MemoryScribeWrites.updateExisting(entity, fields: ["payloadJSON", "updatedAtMs"], at: time, txID: txID)
      }
    }
  }

  /// The minute's audio chunk row, and the row again once its file is uploaded.
  func chunkWrite(minute: Int, uploaded: Bool) -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      let entity = MemoryScribeWrites.row(
        Self.chunkNamespace, id: RealSizeID.make(.write, 5_000_000 + minute), recordingID: recordingID,
        kind: uploaded ? "uploaded" : "recorded", payload: "{\"minute\":\(minute),\"bytes\":\(workload.wavBytes)}",
        extra: uploaded ? "-stored" : "", at: time
      )
      return transaction { MemoryScribeWrites.update(entity, at: time, txID: $0) }
    }
  }

  /// A compressed segment's write: its new row (nine values, as `progressiveMediaSegments`) and the stream's playlist
  /// row updated.
  func segmentRowsWrite(index: Int) -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      let segment = MemoryScribeWrites.row(
        Self.segmentNamespace, id: RealSizeID.make(.write, 6_000_000 + index), recordingID: recordingID, kind: "segment",
        payload: "{\"index\":\(index),\"bytes\":\(workload.segmentBytes),\"seconds\":6}", fieldCount: 9, at: time
      )
      let playlist = MemoryScribeWrites.row(
        Self.segmentNamespace, id: RealSizeID.make(.write, 5_900_000), recordingID: recordingID, kind: "playlist",
        payload: "{\"segments\":\(index + 1)}", fieldCount: 9, at: time
      )
      let fresh = index == 0
      return transaction { txID in
        MemoryScribeWrites.update(segment, at: time, txID: txID)
          + (fresh
            ? MemoryScribeWrites.update(playlist, at: time, txID: txID)
            : MemoryScribeWrites.updateExisting(playlist, fields: ["payloadJSON", "updatedAtMs"], at: time, txID: txID))
      }
    }
  }

  /// One other row: a runtime event.
  func otherRowWrite(index: Int) -> InstantStoreTransaction {
    lock.withLock {
      let time = session.clock.now()
      let entity = MemoryScribeWrites.row(
        Self.otherNamespace, id: RealSizeID.make(.write, 7_000_000 + index), recordingID: recordingID, kind: "event",
        payload: "{\"event\":\(index)}", fieldCount: 10, at: time
      )
      return transaction { MemoryScribeWrites.update(entity, at: time, txID: $0) }
    }
  }
}

/// Reads every emission of the replay's observers, as a screen does, and counts them.
final class MemoryReplayEmissionCounter: @unchecked Sendable {
  // SAFETY: `lock` guards `total`.
  private let lock = NSLock()
  private var total = 0

  var count: Int { lock.withLock { total } }

  func read(_ lease: InstantQueryObservationLease) -> Task<Void, Never> {
    Task { [self] in
      for await _ in lease.stream {
        lock.withLock { total += 1 }
      }
    }
  }
}
