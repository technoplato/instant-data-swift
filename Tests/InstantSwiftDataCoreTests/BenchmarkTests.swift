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
    let memory = LockedMemoryMeter(start: 1_000, step: 100)

    let result = try await InstantSwiftDataLocalBenchmarks.runLocalTodos(
      appID: "benchmark-test",
      iterations: 2,
      cacheDirectory: cacheURL,
      timestamp: { timestamps.next() },
      makeID: { ids.next() },
      clockNanoseconds: { clock.next() },
      memoryBytes: { memory.next() }
    )

    expectNoDifference(result.suite, "local-todos")
    expectNoDifference(result.appID, "benchmark-test")
    expectNoDifference(result.iterations, 2)
    expectNoDifference(result.ok, true)
    expectNoDifference(result.finalTodoCount, 0)
    expectNoDifference(result.pendingMutationCount, 0)
    expectNoDifference(
      result.metrics.map(\.name),
      [
        "bootstrap.local-sqlite",
        "triple-insert.seed",
        "query-materialization.todos",
        "pending-mutation-enqueue.update",
        "high-bandwidth.scalar-updates",
        "high-bandwidth.linked-writes",
        "memory-growth.triples.1k",
        "memory-growth.triples.10k",
        "memory-growth.triples.50k",
        "storage-metadata.query",
        "stream-write.chunks",
        "stream-read.chunks",
        "subscription-cancel.live-query",
        "query-cache-read.todos",
        "triple-retract.reset",
        "offline-restore.relaunch",
        "outbox-flush.local-transport",
      ]
    )
    expectNoDifference(result.metrics.map(\.samples.count), Array(repeating: 2, count: 17))
    expectNoDifference(
      result.metrics.flatMap { $0.samples.map(\.durationNanoseconds) },
      Array(repeating: 100, count: 34)
    )
    expectNoDifference(
      result.metrics.first { $0.name == "triple-insert.seed" }?.samples.map(\.operationCount),
      [21, 21]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "triple-insert.seed" }?.samples.map(\.actorHopCount),
      [7, 7]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "triple-insert.seed" }?.samples.map(\.actorHopBreakdown),
      [
        ["operation-gate": 2, "outbox": 1, "persistence": 2, "store": 2],
        ["operation-gate": 2, "outbox": 1, "persistence": 2, "store": 2],
      ]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "query-materialization.todos" }?.samples.map(\.resultCount),
      [3, 3]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "query-materialization.todos" }?.samples.map(\.actorHopCount),
      [7, 7]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "query-materialization.todos" }?.samples.map(\.actorHopBreakdown),
      [
        ["operation-gate": 2, "persistence": 3, "store": 2],
        ["operation-gate": 2, "persistence": 3, "store": 2],
      ]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.scalar-updates" }?.samples.map(\.operationCount),
      [150, 150]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.scalar-updates" }?.samples.map(\.actorHopCount),
      [350, 350]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.scalar-updates" }?.samples.map(\.actorHopBreakdown),
      [
        ["operation-gate": 100, "outbox": 50, "persistence": 100, "store": 100],
        ["operation-gate": 100, "outbox": 50, "persistence": 100, "store": 100],
      ]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.scalar-updates" }?.samples.map(\.memoryDeltaBytes),
      [100, 100]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.scalar-updates" }?.samples.map(\.memoryBudgetBytes),
      [67_108_864, 67_108_864]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.linked-writes" }?.samples.map(\.operationCount),
      [123, 123]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.linked-writes" }?.samples.map(\.resultCount),
      [20, 20]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.linked-writes" }?.samples.map(\.actorHopCount),
      [7, 7]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.linked-writes" }?.samples.map(\.memoryDeltaBytes),
      [100, 100]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "high-bandwidth.linked-writes" }?.samples.map(\.memoryBudgetBytes),
      [67_108_864, 67_108_864]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.1k" }?.samples.map(\.operationCount),
      [1_000, 1_000]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.1k" }?.samples.map(\.resultCount),
      [250, 250]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.1k" }?.samples.map(\.pendingMutationCount),
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.1k" }?.samples.map(\.memoryDeltaBytes),
      [100, 100]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.1k" }?.samples.map(\.memoryBudgetBytes),
      [67_108_864, 67_108_864]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.1k" }?.samples.map(\.actorHopCount),
      [7, 7]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.10k" }?.samples.map(\.operationCount),
      [10_000, 10_000]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.10k" }?.samples.map(\.resultCount),
      [2_500, 2_500]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.10k" }?.samples.map(\.pendingMutationCount),
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.10k" }?.samples.map(\.memoryDeltaBytes),
      [100, 100]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.10k" }?.samples.map(\.memoryBudgetBytes),
      [268_435_456, 268_435_456]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.10k" }?.samples.map(\.actorHopCount),
      [7, 7]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.50k" }?.samples.map(\.operationCount),
      [50_000, 50_000]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.50k" }?.samples.map(\.resultCount),
      [12_500, 12_500]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.50k" }?.samples.map(\.pendingMutationCount),
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.50k" }?.samples.map(\.memoryDeltaBytes),
      [100, 100]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.50k" }?.samples.map(\.memoryBudgetBytes),
      [1_073_741_824, 1_073_741_824]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "memory-growth.triples.50k" }?.samples.map(\.actorHopCount),
      [7, 7]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "storage-metadata.query" }?.samples.map(\.resultCount),
      [5, 5]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "stream-write.chunks" }?.samples.map(\.operationCount),
      [25, 25]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "stream-read.chunks" }?.samples.map(\.resultCount),
      [25, 25]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "subscription-cancel.live-query" }?.samples.map(\.operationCount),
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "subscription-cancel.live-query" }?.samples.map(\.resultCount),
      [1, 1]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "offline-restore.relaunch" }?.samples.map(\.pendingMutationCount),
      [54, 54]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "offline-restore.relaunch" }?.samples.map(\.actorHopCount),
      [12, 12]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "offline-restore.relaunch" }?.samples.map(\.actorHopBreakdown),
      [
        ["operation-gate": 2, "outbox": 1, "persistence": 6, "store": 3],
        ["operation-gate": 2, "outbox": 1, "persistence": 6, "store": 3],
      ]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.operationCount),
      [54, 54]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.resultCount),
      [54, 54]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.pendingMutationCount),
      [0, 0]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.actorHopCount),
      [15, 15]
    )
    expectNoDifference(
      result.metrics.first { $0.name == "outbox-flush.local-transport" }?.samples.map(\.actorHopBreakdown),
      [
        [
          "mutation-flush-gate": 2,
          "mutation-transport": 1,
          "operation-gate": 4,
          "outbox": 1,
          "persistence": 7,
        ],
        [
          "mutation-flush-gate": 2,
          "mutation-transport": 1,
          "operation-gate": 4,
          "outbox": 1,
          "persistence": 7,
        ],
      ]
    )

    let evidenceRows = result.evidenceRows
    expectNoDifference(evidenceRows.count, 18)
    expectNoDifference(evidenceRows.first?.caseID, "benchmark.local.todos")
    expectNoDifference(evidenceRows.first?.event, "summary")
    expectNoDifference(evidenceRows.first?.details.transport, "not-implemented-local-cache-only")
    expectNoDifference(evidenceRows.first?.details.iterations, 2)
    expectNoDifference(evidenceRows.first?.details.metric, nil)
    expectNoDifference(evidenceRows.dropFirst().map(\.details.transport), Array(repeating: result.transport, count: 17))
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

// SAFETY: tests call this closure from one task, and mutation is protected by `lock`.
private final class LockedMemoryMeter: @unchecked Sendable {
  private let lock = NSLock()
  private var bytes: UInt64
  private let step: UInt64

  init(start: UInt64, step: UInt64) {
    self.bytes = start
    self.step = step
  }

  func next() -> UInt64? {
    lock.lock()
    defer { lock.unlock() }
    defer { bytes += step }
    return bytes
  }
}
