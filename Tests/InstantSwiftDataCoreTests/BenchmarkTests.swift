import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

extension InstantStoreTests {
  @Test
  func localTodoBenchmarkProducesDeterministicMetrics() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSwiftDataBenchmarkTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: cacheURL) }

    let ids = LockedCounter(prefix: "benchmark-id")
    let timestamps = LockedTimestamp(milliseconds: 1_000)
    let clock = LockedNanosecondClock(step: 100)

    let result = try await InstantSwiftDataLocalBenchmarks.runLocalTodos(
      appID: "benchmark-test",
      iterations: 2,
      cacheDirectory: cacheURL,
      timestamp: { timestamps.next() },
      makeID: { ids.next() },
      clockNanoseconds: { clock.next() }
    )

    expectNoDifference(result.suite, "local-todos")
    expectNoDifference(result.appID, "benchmark-test")
    expectNoDifference(result.iterations, 2)
    expectNoDifference(result.ok, true)
    expectNoDifference(result.finalTodoCount, 0)
    expectNoDifference(result.pendingMutationCount, 3)
    expectNoDifference(
      result.metrics.map(\.name),
      [
        "bootstrap.local-sqlite",
        "triple-insert.seed",
        "query-materialization.todos",
        "pending-mutation-enqueue.update",
        "query-cache-read.todos",
        "triple-retract.reset",
        "offline-restore.relaunch",
      ]
    )
    expectNoDifference(result.metrics.map(\.samples.count), Array(repeating: 2, count: 7))
    expectNoDifference(
      result.metrics.flatMap { $0.samples.map(\.durationNanoseconds) },
      Array(repeating: 100, count: 14)
    )
    expectNoDifference(
      result.metrics.first { $0.name == "triple-insert.seed" }?.samples.map(\.operationCount),
      [12, 12]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "query-materialization.todos" }?.samples.map(\.resultCount),
      [3, 3]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "offline-restore.relaunch" }?.samples.map(\.pendingMutationCount),
      [3, 3]
    )

    let evidenceRows = result.evidenceRows
    expectNoDifference(evidenceRows.count, 8)
    expectNoDifference(evidenceRows.first?.caseID, "benchmark.local.todos")
    expectNoDifference(evidenceRows.first?.event, "summary")
    expectNoDifference(evidenceRows.first?.details.transport, "not-implemented-local-cache-only")
    expectNoDifference(evidenceRows.first?.details.iterations, 2)
    expectNoDifference(evidenceRows.first?.details.metric, nil)
    expectNoDifference(evidenceRows.dropFirst().map(\.details.transport), Array(repeating: result.transport, count: 7))
    expectNoDifference(
      evidenceRows.dropFirst().compactMap(\.details.metric?.name),
      result.metrics.map(\.name)
    )
  }
}

// SAFETY: tests call these closures from one task, and mutation is protected by `lock`.
private final class LockedCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  private let prefix: String

  init(prefix: String) {
    self.prefix = prefix
  }

  func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    defer { value += 1 }
    return "\(prefix)-\(value)"
  }
}

// SAFETY: tests call this closure from one task, and mutation is protected by `lock`.
private final class LockedTimestamp: @unchecked Sendable {
  private let lock = NSLock()
  private var milliseconds: Int64

  init(milliseconds: Int64) {
    self.milliseconds = milliseconds
  }

  func next() -> InstantTimestamp {
    lock.lock()
    defer { lock.unlock() }
    defer { milliseconds += 1 }
    return InstantTimestamp(milliseconds: milliseconds)
  }
}

// SAFETY: tests call this closure from one task, and mutation is protected by `lock`.
private final class LockedNanosecondClock: @unchecked Sendable {
  private let lock = NSLock()
  private var nanoseconds: UInt64 = 0
  private let step: UInt64

  init(step: UInt64) {
    self.step = step
  }

  func next() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    defer { nanoseconds += step }
    return nanoseconds
  }
}
