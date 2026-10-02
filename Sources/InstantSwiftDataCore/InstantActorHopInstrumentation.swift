import Foundation

/// Where the runtime crosses into another isolation domain, as counted by ``InstantActorHopRecorder``.
///
/// Call sites record a boundary just before they await it, so a count is only as complete as its call sites. The three
/// cross-SDK runtime workloads (transact, relaunch, reconnect drain) record every actor call and every unstructured
/// task they start; their counts are pinned in `InstantCrossSDKRuntimeBenchmarkTests` (#403).
package enum InstantActorHopBoundary: String, CaseIterable, Sendable {
  case operationGate = "operation-gate"
  case mutationFlushGate = "mutation-flush-gate"
  case connectionGate = "connection-gate"
  case persistence
  case store
  case outbox
  case mutationTransport = "mutation-transport"
  case liveSession = "live-session"
  /// A publish to an observer registry actor (connection status, mutation lifecycle).
  case observers
  case reconnectController = "reconnect-controller"
  case deliveryPump = "delivery-pump"
  /// An unstructured `Task` the operation starts; each one is a job the cooperative pool has to schedule.
  case task
}

package struct InstantActorHopBaseline: Sendable {
  var counts: [InstantActorHopBoundary: Int]
}

package struct InstantActorHopSummary: Equatable, Sendable {
  package var count: Int
  package var breakdown: [String: Int]
}

// SAFETY: mutable counter state is protected by `lock`.
package final class InstantActorHopRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [InstantActorHopBoundary: Int] = [:]

  package init() {}

  package func record(_ boundary: InstantActorHopBoundary) {
    lock.lock()
    counts[boundary, default: 0] += 1
    lock.unlock()
  }

  package func baseline() -> InstantActorHopBaseline {
    lock.lock()
    defer { lock.unlock() }
    return InstantActorHopBaseline(counts: counts)
  }

  package func summary(since baseline: InstantActorHopBaseline) -> InstantActorHopSummary {
    lock.lock()
    let current = counts
    lock.unlock()

    var breakdown: [String: Int] = [:]
    for boundary in InstantActorHopBoundary.allCases {
      let delta = (current[boundary] ?? 0) - (baseline.counts[boundary] ?? 0)
      if delta > 0 {
        breakdown[boundary.rawValue] = delta
      }
    }

    return InstantActorHopSummary(
      count: breakdown.values.reduce(0, +),
      breakdown: breakdown
    )
  }
}
