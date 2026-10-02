import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantCrossSDKRuntimeBenchmarkTests {
  @Test
  func runtimeComparisonProducesEveryPinnedDurableWorkload() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantCrossSDKRuntimeBenchmarkTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheURL) }
    let clock = RuntimeBenchmarkNanosecondClock(step: 100)

    let result = try await InstantSwiftDataCrossSDKRuntimeBenchmarks.run(
      appID: "cross-sdk-runtime-test",
      iterations: 2,
      cacheDirectory: cacheURL,
      clockNanoseconds: { clock.next() }
    )

    expectNoDifference(result.suite, "cross-sdk-runtime")
    expectNoDifference(result.transport, "sqlite-local-runtime")
    expectNoDifference(result.iterations, 2)
    expectNoDifference(result.ok, true)
    expectNoDifference(result.finalTodoCount, 1)
    expectNoDifference(result.pendingMutationCount, 0)
    expectNoDifference(
      result.metrics.map { $0.name },
      InstantCrossSDKRuntimeBenchmarkContract.metricNames
    )
    expectNoDifference(
      result.metrics.flatMap { metric in metric.samples.map { $0.durationNanoseconds } },
      Array(repeating: 100, count: 6)
    )
    #expect(result.metrics.flatMap { $0.samples }.allSatisfy { ($0.actorHopCount ?? 0) > 0 })
    expectNoDifference(
      result.metrics.first { $0.name == "pending-mutation-enqueue.update" }?
        .samples.map { $0.pendingMutationCount },
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "offline-restore.relaunch" }?
        .samples.map { $0.pendingMutationCount },
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "reconnect-outbox-drain" }?
        .samples.map { $0.pendingMutationCount },
      [0, 0]
    )
  }

  /// Every actor call and unstructured task on the three workloads, pinned (#403). An added await on any of these
  /// paths changes a count here; ADR 0018 maps each hop to the line that makes it and what it protects.
  @Test
  func runtimeWorkloadsPinEveryActorHop() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantCrossSDKRuntimeBenchmarkHopTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let result = try await InstantSwiftDataCrossSDKRuntimeBenchmarks.run(
      appID: "cross-sdk-runtime-hop-test",
      iterations: 2,
      cacheDirectory: cacheURL
    )

    let enqueue: [String: Int] = [
      "operation-gate": 2,
      "persistence": 12,
      "server-apply-gate": 1,
      "store": 2,
      "live-session": 1,
      "observers": 1,
    ]
    let relaunch: [String: Int] = [
      "operation-gate": 4,
      "persistence": 9,
      "store": 2,
      "task": 1,
    ]
    let drain: [String: Int] = [
      "connection-gate": 2,
      "live-session": 3,
      "mutation-flush-gate": 2,
      "mutation-transport": 1,
      "observers": 2,
      "operation-gate": 6,
      "outbox": 2,
      "persistence": 26,
      "reconnect-controller": 1,
      "task": 5,
    ]
    expectNoDifference(
      result.metrics.map { metric in metric.samples.map(\.actorHopBreakdown) },
      [[enqueue, enqueue], [relaunch, relaunch], [drain, drain]]
    )
    expectNoDifference(
      result.metrics.map { metric in metric.samples.map(\.actorHopCount) },
      [[19, 19], [16, 16], [50, 50]]
    )
  }

  @Test
  func contractPinsEquivalentRuntimeOperationCounts() {
    expectNoDifference(InstantCrossSDKRuntimeBenchmarkContract.version, 1)
    expectNoDifference(InstantCrossSDKRuntimeBenchmarkContract.mutationCount, 1)
  }
}

// SAFETY: mutation is protected by `lock`.
private final class RuntimeBenchmarkNanosecondClock: @unchecked Sendable {
  private let lock = NSLock()
  private let step: UInt64
  private var nanoseconds: UInt64 = 0

  init(step: UInt64) {
    self.step = step
  }

  func next() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    nanoseconds += step
    return nanoseconds
  }
}
