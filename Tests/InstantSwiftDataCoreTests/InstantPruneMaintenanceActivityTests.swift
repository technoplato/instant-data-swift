// History:
// - 2026-10-28: the live-query prune runs inside a maintenance activity and stops between batches when the system is
//   about to suspend the process (#1319).

import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #1319: a phone's prune batch held the operation gate from 3 s after Scribe left the front until it ran again 37
/// minutes later: iOS suspended the app in the middle of the batch. The prune now works inside an activity that keeps
/// the process running, and when the system is about to suspend the process it stops before its next batch, so it
/// holds no gate across the suspension and the batches left wait for the next prune.
@Suite(.serialized)
struct InstantPruneMaintenanceActivityTests {
  final class Activity: @unchecked Sendable {
    // SAFETY: `lock` guards every stored property below it.
    private let lock = NSLock()
    private var tokens: [InstantMaintenanceActivityToken] = []
    private let startsExpired: Bool

    init(startsExpired: Bool = false) { self.startsExpired = startsExpired }

    var maintenanceActivity: InstantMaintenanceActivity {
      InstantMaintenanceActivity { [self] _ in
        let token = InstantMaintenanceActivityToken(isExpired: startsExpired)
        lock.withLock { tokens.append(token) }
        return token
      }
    }

    var begun: [InstantMaintenanceActivityToken] { lock.withLock { tokens } }

    func expireAll() { for token in begun { token.expire() } }
  }

  final class Batches: @unchecked Sendable {
    // SAFETY: `lock` guards `count`.
    private let lock = NSLock()
    private var count = 0

    func record() -> Int { lock.withLock { count += 1; return count } }

    var recorded: Int { lock.withLock { count } }
  }

  struct Outcome {
    var batches: Int
    var pruned: InstantLiveQueryResultPruningResult
    var gateHolderAfter: String?
    var serverApplyHolderAfter: String?
    var tokens: [InstantMaintenanceActivityToken]

    var allTokensEnded: Bool { tokens.allSatisfy { $0.isEnded } }
  }

  static func prune(
    activity: Activity,
    expiringAfterBatch: Int? = nil,
    expiringWhenTheFirstBatchHoldsTheGates: Bool = false
  ) async throws -> Outcome {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    try await InstantPruneGateHoldTests.seed(at: url)
    let batches = Batches()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-maintenance-activity",
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveQueryResultPruneBatchTripleCount = 1_000
    configuration.maintenanceActivity = activity.maintenanceActivity
    configuration.onLiveQueryResultPruneBatchFinishedForTesting = { _ in
      if batches.record() == expiringAfterBatch { activity.expireAll() }
    }
    if expiringWhenTheFirstBatchHoldsTheGates {
      configuration.onLiveQueryResultPruneBatchHoldsOperationGateForTesting = { activity.expireAll() }
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(TodoExample.query)
    let pruned = try await runtime.pruneLiveQueryResults(
      policy: configuration.liveQueryResultPruningPolicy,
      now: configuration.now()
    )
    let holder = runtime.operationGateSnapshot().holder
    let serverApplyHolder = runtime.serverApplyGateHolderForTesting()
    await observation.cancel()
    _ = try? await runtime.closeConnection()
    return Outcome(
      batches: batches.recorded,
      pruned: pruned,
      gateHolderAfter: holder,
      serverApplyHolderAfter: serverApplyHolder,
      tokens: activity.begun
    )
  }

  @Test
  func aPruneWhoseActivityExpiresStopsBeforeItsNextBatchAndHoldsNoGate() async throws {
    let outcome = try await Self.prune(activity: Activity(), expiringAfterBatch: 1)

    expectNoDifference(outcome.batches, 1, "the system's notice came after the first batch")
    #expect(outcome.pruned.removedQueryKeys.count < InstantPruneGateHoldTests.resultCount)
    expectNoDifference(outcome.gateHolderAfter, nil)
    expectNoDifference(outcome.tokens.count, 1)
    #expect(outcome.allTokensEnded, "the prune ends its activity when it stops")
  }

  /// #1319: on a device a batch then held the server-apply gate 86 minutes, 20:26:51 to 21:53:00, across a 2,637 s
  /// suspension. The system's notice can come while a batch waits for its gates, the server-apply gate first and then
  /// the operation gate; the batch then gives both back without working.
  @Test
  func aBatchWhoseActivityExpiresWhileItTakesTheGatesGivesThemBackUnworked() async throws {
    let outcome = try await Self.prune(activity: Activity(), expiringWhenTheFirstBatchHoldsTheGates: true)

    expectNoDifference(outcome.batches, 0)
    expectNoDifference(outcome.pruned.removedQueryKeys.count, 0)
    expectNoDifference(outcome.gateHolderAfter, nil)
    expectNoDifference(outcome.serverApplyHolderAfter, nil)
    #expect(outcome.allTokensEnded)
  }

  @Test
  func aPruneRefusedAnActivityRunsNoBatch() async throws {
    let outcome = try await Self.prune(activity: Activity(startsExpired: true))

    expectNoDifference(outcome.batches, 0)
    expectNoDifference(outcome.pruned.removedQueryKeys.count, 0)
    expectNoDifference(outcome.gateHolderAfter, nil)
    #expect(outcome.allTokensEnded)
  }

  @Test
  func aPruneThatFinishesInsideItsActivityEndsIt() async throws {
    let outcome = try await Self.prune(activity: Activity())

    expectNoDifference(outcome.pruned.removedQueryKeys.count, InstantPruneGateHoldTests.resultCount)
    expectNoDifference(outcome.tokens.count, 1)
    #expect(outcome.allTokensEnded)
  }
}
