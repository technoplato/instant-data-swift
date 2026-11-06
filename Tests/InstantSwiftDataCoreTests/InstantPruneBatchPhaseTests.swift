// History:
// - 2026-11-05: restated for #1500's unload in place: the batches unload the closed results, and the memory they release
//   is a phase of its own (#1129).
// - 2026-11-05: a prune batch names each phase it holds its gates for and times it; a batch that held them 1 s or more
//   logs one notice with each phase's milliseconds (#1129).

import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #1129: on 2026-11-04 a Mac's cadence prune held the server-apply gate 4.5-13.1 s per batch, every live refresh
/// waiting behind it, and a phone's held a recording's first write 1.25 s, while a batch still releases at most 1,000
/// facts. Some phase stopped following the batch's size, and no report named it: the gate reports said only "prune live
/// query results". A batch now names each phase in both gates' holder phase and times it.
@Suite(.serialized)
struct InstantPruneBatchPhaseTests {
  final class Timings: @unchecked Sendable {
    // SAFETY: `lock` guards `recorded`.
    private let lock = NSLock()
    private var recorded: [InstantPruneBatchTiming] = []

    func record(_ timing: InstantPruneBatchTiming) { lock.withLock { recorded.append(timing) } }

    var all: [InstantPruneBatchTiming] { lock.withLock { recorded } }
  }

  /// The slow-batch notices one app logged, by their metadata.
  final class Notices: @unchecked Sendable {
    // SAFETY: `lock` guards `entries` and `token`.
    private let lock = NSLock()
    private var entries: [[String: String]] = []
    private var token: UUID?
    let appID: String

    init(appID: String) { self.appID = appID }

    func start() {
      let token = InstantDiagnostics.shared.addHandler { [weak self] entry in
        guard let self, entry.event == "live-query-results.prune-batch-slow",
          entry.metadata["appID"] == self.appID
        else { return }
        var metadata = entry.metadata
        metadata["level"] = entry.level.rawValue
        self.lock.withLock { self.entries.append(metadata) }
      }
      lock.withLock { self.token = token }
    }

    func stop() {
      if let token = lock.withLock({ token }) { InstantDiagnostics.shared.removeHandler(token) }
    }

    var all: [[String: String]] { lock.withLock { entries } }
  }

  /// The phase each holder of the operation gate named last when it left it.
  final class GateReleases: @unchecked Sendable {
    // SAFETY: `lock` guards `released`.
    private let lock = NSLock()
    private var released: [(operation: String, phase: String?)] = []

    var record: @Sendable (AsyncSerialGate.TimelineEvent) -> Void {
      { [weak self] event in
        guard event.kind == .released, let self else { return }
        self.lock.withLock { self.released.append((event.operation, event.phase)) }
      }
    }

    func phases(of operation: String) -> [String?] {
      lock.withLock { released.filter { $0.operation == operation }.map(\.phase) }
    }
  }

  struct Outcome {
    var timings: [InstantPruneBatchTiming]
    var notices: [[String: String]]
    var pruneGatePhases: [String?]
    var pruned: InstantLiveQueryResultPruningResult
  }

  /// The phases a prune batch can name.
  static let phaseNames: Set<String> = [
    "find released row", "active keys", "choose", "residency", "apply", "retract", "release memory", "unload",
  ]

  /// The 24 closed results `InstantPruneGateHoldTests` seeds, all loaded, with its open query, which shows none of their
  /// todos, pruned in batches of 1,000 facts. Since #1500 a batch unloads closed results where they are.
  static func prune(appID: String, slowBatchMilliseconds: Int) async throws -> Outcome {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let timings = Timings()
    let notices = Notices(appID: appID)
    let releases = GateReleases()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveQueryResultPruneBatchTripleCount = 1_000
    // #1107: every seeded result stays loaded at the launch, as in `InstantPruneGateHoldTests`.
    configuration.preloadedLiveQueryResultCount = .max
    configuration.liveQueryResultPruneSlowBatchMilliseconds = slowBatchMilliseconds
    configuration.onLiveQueryResultPruneBatchTimedForTesting = { timings.record($0) }
    configuration.operationGateTimeline = releases.record
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(InstantPruneGateHoldTests.openQuery)
    notices.start()
    let pruned: InstantLiveQueryResultPruningResult
    do {
      pruned = try await runtime.pruneLiveQueryResults(
        policy: configuration.liveQueryResultPruningPolicy,
        now: configuration.now()
      )
    } catch {
      notices.stop()
      throw error
    }
    notices.stop()
    await observation.cancel()
    _ = try? await runtime.closeConnection()
    return Outcome(
      timings: timings.all,
      notices: notices.all,
      pruneGatePhases: releases.phases(of: "pruneLiveQueryResults(policy:now:)"),
      pruned: pruned
    )
  }

  /// A batch that unloads closed results holds its gates for these phases, in this order: it looks for a released row to
  /// check first, reads the active queries, chooses its results, reads the hot store's facts of their entities, marks
  /// the results unloaded in SQLite, releases from memory the entities no loaded result owns (#1500), and unloads the
  /// results' live state. A batch that removes facts retracts them from the hot store after `apply`.
  @Test
  func aPruneBatchTimesEachPhaseItHoldsTheGatesFor() async throws {
    let outcome = try await Self.prune(appID: "prune-batch-phases", slowBatchMilliseconds: .max)

    expectNoDifference(outcome.pruned.unloadedQueryKeys.count, InstantPruneGateHoldTests.resultCount)
    expectNoDifference(outcome.pruned.removedQueryKeys, [])
    let first = try #require(outcome.timings.first, "#1129: no prune batch reported its phases")
    expectNoDifference(
      first.phases.map(\.name),
      ["find released row", "active keys", "choose", "residency", "apply", "release memory", "unload"]
    )
    #expect(outcome.timings.count > 1, "24 results of about 450 facts take several batches of 1,000")
    for timing in outcome.timings {
      #expect(timing.phases.allSatisfy { $0.milliseconds <= timing.heldMilliseconds })
    }
  }

  /// A stall or wait report names the operation gate's holder and the phase it named last: each batch's release names
  /// the phase it ended in, where it said only "pruneLiveQueryResults(policy:now:)".
  @Test
  func aPruneBatchNamesItsPhaseInTheOperationGate() async throws {
    let outcome = try await Self.prune(appID: "prune-batch-gate-phase", slowBatchMilliseconds: .max)

    #expect(!outcome.pruneGatePhases.isEmpty)
    expectNoDifference(
      outcome.pruneGatePhases.filter { $0 == nil || !Self.phaseNames.contains($0!) },
      [],
      "#1129: a prune batch left the operation gate without naming its phase"
    )
  }

  /// A batch that held its gates at least the threshold logs one notice with each phase's milliseconds and its counts.
  @Test
  func aSlowPruneBatchLogsANoticeWithEachPhasesTime() async throws {
    let outcome = try await Self.prune(appID: "prune-batch-slow-notice", slowBatchMilliseconds: 0)

    expectNoDifference(outcome.notices.count, outcome.timings.count)
    let notice = try #require(outcome.notices.first, "#1129: no notice for a batch at the threshold")
    expectNoDifference(notice["level"], InstantDiagnosticLevel.notice.rawValue)
    #expect(notice["phases"]?.hasPrefix("find released row ") == true)
    #expect(notice["heldMilliseconds"] != nil)
    #expect(notice["slowestPhase"] != nil)
    expectNoDifference(notice["kind"], "results")
    #expect(Int(notice["unloadedResultCount"] ?? "") ?? 0 > 0)
  }

  /// A batch under the threshold logs nothing at notice: a device prunes on its write cadence.
  @Test
  func aQuickPruneBatchLogsNoNotice() async throws {
    let outcome = try await Self.prune(appID: "prune-batch-quick", slowBatchMilliseconds: .max)

    #expect(!outcome.timings.isEmpty)
    expectNoDifference(outcome.notices.count, 0)
  }

  /// Guard: a phase entered again adds up under its first place, and the hold runs from the first phase to the end.
  @Test
  func phasesEnteredAgainAddUp() {
    final class ManualClock: @unchecked Sendable {
      // SAFETY: `lock` guards `offset`.
      private let lock = NSLock()
      private let base = ContinuousClock.now
      private var offset = Duration.zero
      func advance(_ duration: Duration) { lock.withLock { offset += duration } }
      var now: ContinuousClock.Instant { lock.withLock { base + offset } }
    }
    let clock = ManualClock()
    let phases = InstantPruneBatchPhases(gates: [], now: { clock.now })

    phases.begin("choose")
    clock.advance(.milliseconds(10))
    phases.begin("apply")
    clock.advance(.milliseconds(20))
    phases.begin("choose")
    clock.advance(.milliseconds(5))
    let timing = phases.finish()

    expectNoDifference(
      timing,
      InstantPruneBatchTiming(
        heldMilliseconds: 35,
        phases: [.init(name: "choose", milliseconds: 15), .init(name: "apply", milliseconds: 20)]
      )
    )
    expectNoDifference(timing.slowestPhase?.name, "apply")
    expectNoDifference(timing.phasesDescription, "choose 15 ms, apply 20 ms")
  }
}
