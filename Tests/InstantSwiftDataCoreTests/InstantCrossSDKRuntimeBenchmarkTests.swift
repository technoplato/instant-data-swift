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
