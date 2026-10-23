import CustomDump
import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #932 (2026-10-23): what one server apply costs with a Scribe-shaped backlog, frame by frame. On the iPhone (build 114,
// library 1.9.12) a server apply held the operation gate 4.3-7.4 s every ~30 s with ~2,560 pending writes (commit
// 3.3-6.4 s, patch 0.8-1.3 s), 1.1-1.8 s with none, and iOS counted 17 GB of writes in 11.5 h under
// `stageServerApplyBodyPage`. Every transact, query, observe and connection-status call waits behind that gate.
//
// `measureServerApplyCost` prints one `COST` line per frame: wall time, the gate hold and its phases (from the
// runtime's own `server-apply.operation-gate-held` event), the longest wait of a read that queued behind it, process
// CPU, instructions and logical bytes written, and the energy meter's plan and commit sections. It is skipped unless
// `INSTANT_SERVER_APPLY_COST` is set, and scales with:
//   INSTANT_SERVER_APPLY_COST_PENDING_SEGMENTS  pending segments, six writes each (default 430: 2,580 writes)
//   INSTANT_SERVER_APPLY_COST_SERVER_SEGMENTS   segments the server already holds (default 550)
//   INSTANT_SERVER_APPLY_COST_FRAMES            drain frames after the reconnect frames (default 6)
//   INSTANT_SERVER_APPLY_COST_LIVE_LINES=1      interims write a live row the final deletes (ADR 0069), and the device
//                                               keeps the live-lines query, as Scribe records today
//   INSTANT_FAST_DRAIN_FULL_REBASE=1            every frame peels and replays its whole component, as the phone's do

/// Process-wide counters: the runtime's work runs on actor executors and the cooperative pool, not the test's thread.
struct ServerApplyProcessUsage {
  var cpuNanoseconds: UInt64
  var instructions: UInt64
  var logicalWriteBytes: UInt64

  static func now() -> Self {
    var info = rusage_info_v4()
    _ = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
      }
    }
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    let ticks = info.ri_user_time + info.ri_system_time
    return Self(
      cpuNanoseconds: ticks * UInt64(timebase.numer) / UInt64(timebase.denom),
      instructions: info.ri_instructions,
      logicalWriteBytes: info.ri_logical_writes
    )
  }
}

/// The runtime's `server-apply.operation-gate-held` events, newest last.
final class ServerApplyGateEvents: @unchecked Sendable {
  // SAFETY: `lock` guards `events` and `exclusiveFallbacks` for every read and write.
  private let lock = NSLock()
  private var events: [[String: String]] = []
  private var exclusiveFallbacks = 0
  private var token: UUID?

  func start() {
    token = InstantDiagnostics.shared.addHandler { [weak self] entry in
      guard let self else { return }
      switch entry.event {
      case "server-apply.operation-gate-held":
        // The processed transaction id, so a test can keep only its own applies: other suites run in this process.
        var metadata = entry.metadata
        metadata["correlationID"] = entry.correlationID
        self.lock.withLock { self.events.append(metadata) }
      case "server-apply.exclusive-fallback":
        self.lock.withLock { self.exclusiveFallbacks += 1 }
      default:
        break
      }
    }
  }

  func stop() {
    if let token { InstantDiagnostics.shared.removeHandler(token) }
    token = nil
  }

  var count: Int { lock.withLock { events.count } }
  var fallbackCount: Int { lock.withLock { exclusiveFallbacks } }

  func events(since index: Int) -> [[String: String]] {
    lock.withLock { Array(events.dropFirst(index)) }
  }

  /// The events of the applies whose processed transaction id is `id`.
  func events(processedTransactionID id: String) -> [[String: String]] {
    lock.withLock { events.filter { $0["correlationID"] == id } }
  }
}

/// Calls `connectionStatus()`, which waits for the operation gate like every observe and query, back to back while a
/// frame applies, and keeps the longest wait: how long a read queued behind the apply.
final class ServerApplyReadProbe: @unchecked Sendable {
  // SAFETY: `lock` guards `longest` and `reads` for every read and write.
  private let lock = NSLock()
  private var longest: Duration = .zero
  private var reads = 0
  private var task: Task<Void, Never>?

  func start(_ runtime: InstantRuntime) {
    task = Task { [weak self] in
      while !Task.isCancelled {
        let started = ContinuousClock.now
        _ = try? await runtime.connectionStatus()
        let waited = ContinuousClock.now - started
        guard let self else { return }
        self.lock.withLock {
          self.reads += 1
          self.longest = max(self.longest, waited)
        }
        try? await Task.sleep(for: .milliseconds(5))
      }
    }
  }

  func stop() async -> (longest: Duration, reads: Int) {
    task?.cancel()
    await task?.value
    return lock.withLock { (longest, reads) }
  }
}

struct ServerApplyFrameCost: CustomStringConvertible {
  var label: String
  var wall: Duration
  var gate: [String: String]?
  var longestRead: Duration
  var cpuMilliseconds: Double
  var instructionsMillions: Double
  var logicalWriteKilobytes: Double
  var planCPUMilliseconds: Double
  var commitCPUMilliseconds: Double
  var storePrepareCPUMilliseconds: Double
  var plannedBodies: Int

  static func milliseconds(_ duration: Duration) -> Int {
    Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
  }

  var heldMilliseconds: Int { gate.flatMap { $0["heldMilliseconds"] }.flatMap(Int.init) ?? 0 }

  var description: String {
    let phases = ["catchUp", "commit", "publish", "patch", "finish"].map { phase in
      "\(phase) \(gate?["\(phase)Milliseconds"] ?? "-")"
    }.joined(separator: " ")
    return String(
      format:
        "COST %@: wall %d ms, gate held %d ms (%@), longest read %d ms, cpu %.0f ms, instr %.0f M, writes %.0f KB, plan cpu %.0f ms, commit cpu %.0f ms, storePrepare cpu %.0f ms, bodies %d, pending %@, changed %@",
      label,
      Self.milliseconds(wall),
      heldMilliseconds,
      phases,
      Self.milliseconds(longestRead),
      cpuMilliseconds,
      instructionsMillions,
      logicalWriteKilobytes,
      planCPUMilliseconds,
      commitCPUMilliseconds,
      storePrepareCPUMilliseconds,
      plannedBodies,
      gate?["pendingMutationCount"] ?? "-",
      gate?["changedEntityCount"] ?? "-"
    )
  }
}

extension ServerApplyFrameCost {
  /// Applies `frame` while a read probe waits on `runtime`'s operation gate, and measures it.
  static func measure(
    _ label: String,
    runtime: InstantRuntime,
    events: ServerApplyGateEvents,
    _ frame: () async throws -> FastDrainFrameMeasurement
  ) async throws -> Self {
    let eventIndex = events.count
    let probe = ServerApplyReadProbe()
    let energyBefore = InstantEnergyMeter.snapshot()
    let usageBefore = ServerApplyProcessUsage.now()
    probe.start(runtime)
    let started = ContinuousClock.now
    let applied = try await frame()
    let wall = ContinuousClock.now - started
    let read = await probe.stop()
    let usageAfter = ServerApplyProcessUsage.now()
    let energy = InstantEnergyMeter.snapshot().subtracting(energyBefore)
    return Self(
      label: label,
      wall: wall,
      gate: events.events(since: eventIndex).last,
      longestRead: read.longest,
      cpuMilliseconds: Double(usageAfter.cpuNanoseconds - usageBefore.cpuNanoseconds) / 1e6,
      instructionsMillions: Double(usageAfter.instructions - usageBefore.instructions) / 1e6,
      logicalWriteKilobytes: Double(usageAfter.logicalWriteBytes - usageBefore.logicalWriteBytes) / 1024,
      planCPUMilliseconds: Double(energy[.serverApplyPlan].cpuNanoseconds) / 1e6,
      commitCPUMilliseconds: Double(energy[.serverApplyCommit].cpuNanoseconds) / 1e6,
      storePrepareCPUMilliseconds: Double(energy[.storePrepare].cpuNanoseconds) / 1e6,
      plannedBodies: applied.plannedBodyCount
    )
  }
}

@Suite(.serialized)
struct InstantServerApplyCostTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_SERVER_APPLY_COST"] != nil))
  func measureServerApplyCost() async throws {
    let environment = ProcessInfo.processInfo.environment
    let pendingSegments = environment["INSTANT_SERVER_APPLY_COST_PENDING_SEGMENTS"].flatMap(Int.init) ?? 430
    let serverSegments = environment["INSTANT_SERVER_APPLY_COST_SERVER_SEGMENTS"].flatMap(Int.init) ?? 550
    let drainFrames = environment["INSTANT_SERVER_APPLY_COST_FRAMES"].flatMap(Int.init) ?? 6
    let reduces = environment["INSTANT_FAST_DRAIN_FULL_REBASE"] != "1"
    let liveLines = environment["INSTANT_SERVER_APPLY_COST_LIVE_LINES"] == "1"
    let setupStarted = ContinuousClock.now
    var fixture = try await FastDrainFixture.make(
      suffix: "cost",
      serverSegmentCount: serverSegments,
      pendingSegmentCount: pendingSegments,
      reducesServerApply: reduces,
      scribeLinks: true,
      defersSegmentText: true,
      liveLines: liveLines
    )
    let setup = ContinuousClock.now - setupStarted
    let pendingAtStart = try await fixture.pendingCount()
    print(
      "COST setup: \(pendingAtStart) pending, \(serverSegments) server segments, \(reduces ? "reduced" : "full rebase")\(liveLines ? ", live lines" : ""), \(ServerApplyFrameCost.milliseconds(setup)) ms"
    )

    let events = ServerApplyGateEvents()
    events.start()
    defer { events.stop() }
    let declines = FastDrainDeclineCounter()
    let declineToken = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "server-apply.reduction-declined" else { return }
      declines.record(
        [entry.metadata["reason"], entry.metadata["attributeID"]].compactMap { $0 }.joined(separator: " ")
      )
    }
    defer { InstantDiagnostics.shared.removeHandler(declineToken) }
    var costs: [ServerApplyFrameCost] = []
    for query in fixture.server.registeredQueries {
      let cost = try await ServerApplyFrameCost.measure(
        "reconnect \(query.rawValue)", runtime: fixture.runtime, events: events
      ) {
        try await fixture.refresh(queries: [query])
      }
      print(cost)
      costs.append(cost)
    }
    var window = try await fixture.claimWindow()
    var delivered = 0
    for index in 0..<drainFrames {
      if delivered == window.mutations.count {
        window = try await fixture.claimWindow()
        delivered = 0
      }
      guard delivered < window.mutations.count else { break }
      let mutation = window.mutations[delivered]
      delivered += 1
      let token = window.token
      let cost = try await ServerApplyFrameCost.measure(
        "drain \(index + 1)", runtime: fixture.runtime, events: events
      ) {
        try await fixture.acceptAndRefresh(mutation, claimToken: token)
      }
      print(cost)
      costs.append(cost)
    }
    let pendingAfter = try await fixture.pendingCount()
    let held = costs.map(\.heldMilliseconds).sorted()
    let walls = costs.map { ServerApplyFrameCost.milliseconds($0.wall) }.sorted()
    let reads = costs.map { ServerApplyFrameCost.milliseconds($0.longestRead) }.sorted()
    print(
      """
      COST summary: \(costs.count) frames, pending \(pendingAtStart) -> \(pendingAfter), exclusive fallbacks \(events.fallbackCount); \
      gate held median \(held[held.count / 2]) max \(held.last ?? 0) ms; wall median \(walls[walls.count / 2]) max \(walls.last ?? 0) ms; \
      longest read median \(reads[reads.count / 2]) max \(reads.last ?? 0) ms; \
      cpu \(Int(costs.map(\.cpuMilliseconds).reduce(0, +))) ms, instr \(Int(costs.map(\.instructionsMillions).reduce(0, +))) M, \
      writes \(Int(costs.map(\.logicalWriteKilobytes).reduce(0, +))) KB; declined reductions \(declines.snapshot())
      """
    )
    #expect(pendingAfter <= pendingAtStart)
  }

  /// What a server apply costs with nothing to rebase, against a copy of a real store: each frame restates the largest
  /// stored live-query results unchanged, as the server's refresh after a write elsewhere does, 10 s apart, so a
  /// result's JSON write (one per 30 s, #566) comes due every third frame. The phone held the gate 1.1-3.9 s for such
  /// applies (0 pending, 0 changed entities), and the Mac 1.75 s (build 115, 2026-10-23 14:27). Skipped unless
  /// `INSTANT_SERVER_APPLY_STORE` names a store (`<appID>.sqlite` or its directory); the copy loses its credential rows.
  ///   INSTANT_SERVER_APPLY_STORE_QUERIES  results restated per frame, largest first (default 3)
  ///   INSTANT_SERVER_APPLY_STORE_FRAMES   frames (default 9)
  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_SERVER_APPLY_STORE"] != nil))
  func measureServerApplyCostOnAStoreCopy() async throws {
    let environment = ProcessInfo.processInfo.environment
    let store = try PhoneReplayGateTests.storeFile(at: try #require(environment["INSTANT_SERVER_APPLY_STORE"]))
    let queryCount = environment["INSTANT_SERVER_APPLY_STORE_QUERIES"].flatMap(Int.init) ?? 3
    let frameCount = environment["INSTANT_SERVER_APPLY_STORE_FRAMES"].flatMap(Int.init) ?? 9
    let url = try PhoneReplayGateTests.scratchCopy(of: store, in: FileManager.default.temporaryDirectory)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let runtime = try await PhoneReplayGateTests.runtime(
      url,
      appID: store.deletingPathExtension().lastPathComponent,
      deferred: InstantDeferredValueResidencyPolicy(attributeIDs: PhoneReplayGateTests.scribeDeferredAttributeIDs)
    )
    let results = Array(try PhoneReplayGateTests.storedResults(url).prefix(queryCount))
    let pending = try await runtime.persistence.countOutboxMutations(status: .pending)
    print(
      "COST store: \(pending) pending; restating \(results.map { "\($0.triples.count) facts" }.joined(separator: ", ")) per frame"
    )
    let events = ServerApplyGateEvents()
    events.start()
    defer { events.stop() }
    let newest = results.flatMap(\.triples).map(\.txTime.milliseconds).max() ?? 1_790_000_000_000
    var costs: [ServerApplyFrameCost] = []
    for frame in 0..<frameCount {
      let id = "store-cost-\(frame)"
      let receivedAt = InstantTimestamp(milliseconds: newest + 60_000 + Int64(frame) * 10_000)
      let cost = try await ServerApplyFrameCost.measure("restate \(frame + 1)", runtime: runtime, events: events) {
        _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
          InstantStoreTransaction(id: id, operations: results.flatMap(\.triples).map(InstantTripleOperation.insert)),
          attributesToMerge: [],
          liveQueryResultReplacements: results.map {
            InstantLiveQueryResultReplacement(key: $0.key, triples: $0.triples, pageInfo: $0.pageInfo)
          },
          receivedAt: receivedAt
        )
        return FastDrainFrameMeasurement(duration: .zero, plannedBodyCount: 0, decodedBodyCount: 0)
      }
      let event = events.events(processedTransactionID: id).last ?? [:]
      print("\(cost); \(event["path"] ?? "-"); commit inside \(event["commitInsideMilliseconds"] ?? "-") ms (validate \(event["commitValidateMilliseconds"] ?? "-"), facts \(event["commitFactsMilliseconds"] ?? "-"), outbox \(event["commitOutboxMilliseconds"] ?? "-"), results \(event["commitResultsMilliseconds"] ?? "-"), bookkeeping \(event["commitBookkeepingMilliseconds"] ?? "-"), SQLite commit \(event["commitSQLiteCommitMilliseconds"] ?? "-")), result JSON \(event["commitResultJSONBytes"] ?? "-") bytes")
      costs.append(cost)
    }
    let held = costs.map(\.heldMilliseconds).sorted()
    print(
      """
      COST store summary: \(costs.count) frames; gate held median \(held[held.count / 2]) max \(held.last ?? 0) ms; \
      cpu \(Int(costs.map(\.cpuMilliseconds).reduce(0, +))) ms, instr \(Int(costs.map(\.instructionsMillions).reduce(0, +))) M, \
      writes \(Int(costs.map(\.logicalWriteKilobytes).reduce(0, +))) KB
      """
    )
  }
}
