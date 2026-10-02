import Foundation

/// The warm-connection counterpart of ``InstantCrossSDKRuntimeBenchmarkContract`` (#403).
///
/// The cold suite times each operation on a runtime it has just opened, so per-connection work (statements an app
/// prepares once, the first reads after opening) lands in every sample. An app opens one runtime and runs every
/// operation on it. This suite does that: one runtime, a few untimed warm-up operations, then one write and one
/// acknowledged delivery per iteration, each timed. The TypeScript side runs the same operations on one long-lived
/// `Reactor` (`validation/ts-runner/src/cross-sdk-runtime-warm-benchmark.ts`).
public enum InstantCrossSDKWarmRuntimeBenchmarkContract {
  public static let version = 1
  /// Operations each side runs before it starts timing.
  public static let warmUpOperationCount = 3
  public static let metricNames = [
    "warm.pending-mutation-enqueue.update",
    "warm.reconnect-outbox-drain",
  ]
}

public enum InstantSwiftDataCrossSDKWarmRuntimeBenchmarks {
  public static let suite = "cross-sdk-runtime-warm"

  /// Runs `iterations` timed write-then-deliver rounds on one runtime, after
  /// ``InstantCrossSDKWarmRuntimeBenchmarkContract/warmUpOperationCount`` untimed rounds.
  ///
  /// Each round writes one todo with `transact` (timed: local materialize plus the durable outbox row), checks that
  /// one write is pending, then delivers it with `flushPendingMutations()` through the local transport (timed: the
  /// claim, the transport, the confirmation, and the settlement). The runtime connects once, before the warm-up.
  public static func run(
    appID: String = "cross-sdk-runtime-warm-benchmark",
    iterations: Int = 20,
    cacheDirectory: URL? = nil,
    clockNanoseconds: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) async throws -> InstantLocalTodoBenchmarkResult {
    guard iterations > 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "run warm cross-SDK runtime benchmark",
        message: "Iterations must be greater than zero.",
        recovery: "Pass '--iterations 1' or a larger value."
      )
    }

    let rootCacheDirectory =
      cacheDirectory
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantCrossSDKWarmRuntimeBenchmarks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: rootCacheDirectory,
      withIntermediateDirectories: true
    )
    let cacheURL = rootCacheDirectory.appendingPathComponent("runtime.sqlite")
    let recorder = InstantActorHopRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.actorHopRecorder = recorder
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()

    var samples: [String: [InstantBenchmarkSample]] = [:]
    let warmUp = InstantCrossSDKWarmRuntimeBenchmarkContract.warmUpOperationCount
    for round in 0..<(warmUp + iterations) {
      let todoID = "warm-runtime-todo-\(round)"
      let transactionID = "warm-runtime-transaction-\(round)"
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(round))
      let operations = TodoExample.createOperations(
        id: todoID,
        text: "Warm cross-SDK runtime todo \(round)",
        createdAt: createdAt,
        transactionID: transactionID
      )
      let enqueueBaseline = recorder.baseline()
      let (_, enqueueDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: operations),
          createdAt: createdAt,
          source: "benchmark.cross-sdk.runtime-warm.enqueue"
        )
      }
      let enqueueHops = recorder.summary(since: enqueueBaseline)
      let pendingCount = await runtime.pendingMutations().count
      try require(pendingCount == 1, operation: "validate warm cross-SDK runtime enqueue benchmark")

      let drainBaseline = recorder.baseline()
      let (drain, drainDuration) = try await measured(clockNanoseconds) {
        try await runtime.flushPendingMutations()
      }
      let drainHops = recorder.summary(since: drainBaseline)
      try require(
        drain.confirmed.count == 1 && drain.pendingMutationCount == 0,
        operation: "validate warm cross-SDK runtime drain benchmark"
      )

      let iteration = round - warmUp
      guard iteration >= 0 else { continue }
      samples["warm.pending-mutation-enqueue.update", default: []].append(
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: enqueueDuration,
          operationCount: operations.count,
          pendingMutationCount: pendingCount,
          actorHopCount: enqueueHops.count,
          actorHopBreakdown: enqueueHops.breakdown,
          cachePath: cacheURL.path
        )
      )
      samples["warm.reconnect-outbox-drain", default: []].append(
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: drainDuration,
          operationCount: drain.request.mutations.count,
          resultCount: drain.confirmed.count,
          pendingMutationCount: drain.pendingMutationCount,
          actorHopCount: drainHops.count,
          actorHopBreakdown: drainHops.breakdown,
          cachePath: cacheURL.path
        )
      )
    }
    _ = try await runtime.closeConnection()

    let metrics = InstantCrossSDKWarmRuntimeBenchmarkContract.metricNames.map {
      InstantBenchmarkMetric(name: $0, samples: samples[$0] ?? [])
    }
    return InstantLocalTodoBenchmarkResult(
      suite: suite,
      appID: appID,
      cachePath: rootCacheDirectory.path,
      transport: "sqlite-local-runtime",
      iterations: iterations,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: metrics.allSatisfy { $0.samples.count == iterations },
      metrics: metrics,
      finalTodoCount: warmUp + iterations,
      pendingMutationCount: 0
    )
  }

  private static func require(
    _ condition: @autoclosure () -> Bool,
    operation: String
  ) throws {
    guard condition() else {
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        message: "The benchmark workload produced an unexpected result.",
        recovery: "Fix workload parity before comparing performance."
      )
    }
  }

  private static func measured<Value: Sendable>(
    _ clock: @Sendable () -> UInt64,
    operation: () async throws -> Value
  ) async rethrows -> (Value, UInt64) {
    let start = clock()
    let value = try await operation()
    return (value, clock() - start)
  }
}
