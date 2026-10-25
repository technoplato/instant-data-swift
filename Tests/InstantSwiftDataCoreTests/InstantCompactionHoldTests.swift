// History
// 2026-10-25  #1136  Created. Compaction asked the app's hold closure a second time under the operation gate, so the
//                    gate was held while the closure ran (the consuming app's hops to the main actor) as well as during
//                    the VACUUM; on a phone the vacuum phase held the gate 7,596 ms (build 118).

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// The app's hold is asked once, before the operation gate (#1136). Under the gate, compaction re-checks only what it can
/// read at once (cancellation, the device's heat and power, the volume's room), so the gate's hold is the VACUUM's own.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantCompactionHoldTests {
  @Test
  func theAppsHoldIsAskedOnceBeforeTheGate() async throws {
    let url = try InstantLocalCacheCompactionTests.cacheURL("hold-before-gate")
    try await InstantLocalCacheCompactionTests.fill(url, written: 4_000, kept: 400)
    let runtime = try await InstantLocalCacheCompactionTests.runtime(on: url)
    let asks = CompactionHoldAsks()

    let compaction = try await runtime.compactLocalCache(policy: InstantLocalCacheCompactionTests.policy) {
      asks.record(gateHeld: runtime.operationGateSnapshot().holder != nil)
      return nil
    }

    #expect(compaction.outcome == .compacted)
    #expect(
      asks.value == [false],
      "#1136: the app's hold was asked \(asks.value.count) times, \(asks.value.filter { $0 }.count) under the gate"
    )
  }

  /// A reason the app gives still holds the compaction, before the gate is taken.
  @Test
  func aReasonTheAppGivesStillHoldsTheCompaction() async throws {
    let url = try InstantLocalCacheCompactionTests.cacheURL("hold-reason")
    try await InstantLocalCacheCompactionTests.fill(url, written: 4_000, kept: 400)
    let runtime = try await InstantLocalCacheCompactionTests.runtime(on: url)

    let compaction = try await runtime.compactLocalCache(policy: InstantLocalCacheCompactionTests.policy) {
      "recording"
    }

    #expect(compaction.outcome == .held(.application("recording")))
    #expect(compaction.vacuumDuration == nil)
  }
}

/// Whether the operation gate was held at each ask of the app's hold.
private final class CompactionHoldAsks: @unchecked Sendable {
  // SAFETY: `lock` guards `asks`.
  private let lock = NSLock()
  private var asks: [Bool] = []

  var value: [Bool] { lock.withLock { asks } }

  func record(gateHeld: Bool) {
    lock.withLock { asks.append(gateHeld) }
  }
}
