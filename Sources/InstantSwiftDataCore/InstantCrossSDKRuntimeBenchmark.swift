import Foundation

public enum InstantCrossSDKRuntimeBenchmarkContract {
  public static let version = 1
  public static let mutationCount = 1
  public static let metricNames = [
    "pending-mutation-enqueue.update",
    "offline-restore.relaunch",
    "reconnect-outbox-drain",
  ]
}

public enum InstantSwiftDataCrossSDKRuntimeBenchmarks {
  public static let suite = "cross-sdk-runtime"

  public static func run(
    appID: String = "cross-sdk-runtime-benchmark",
    iterations: Int = 5,
    cacheDirectory: URL? = nil,
    clockNanoseconds: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) async throws -> InstantLocalTodoBenchmarkResult {
    guard iterations > 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "run cross-SDK runtime benchmark",
        message: "Iterations must be greater than zero.",
        recovery: "Pass '--iterations 1' or a larger value."
      )
    }

    let rootCacheDirectory =
      cacheDirectory
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantCrossSDKRuntimeBenchmarks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: rootCacheDirectory,
      withIntermediateDirectories: true
    )

    var samples: [String: [InstantBenchmarkSample]] = [:]
    var finalTodoCount = 0
    var finalPendingMutationCount = 0

    for iteration in 0..<iterations {
      let cacheURL = rootCacheDirectory
        .appendingPathComponent("runtime-\(iteration).sqlite")
      let recorder = InstantActorHopRecorder()
      var configuration = InstantRuntimeConfiguration(
        appID: "\(appID)-\(iteration)",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
      configuration.actorHopRecorder = recorder
      let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

      let todoID = "runtime-todo-\(iteration)"
      let transactionID = "runtime-transaction-\(iteration)"
      let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(iteration))
      let operations = TodoExample.createOperations(
        id: todoID,
        text: "Cross-SDK runtime todo \(iteration)",
        createdAt: createdAt,
        transactionID: transactionID
      )
      let enqueueBaseline = recorder.baseline()
      let (_, enqueueDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: operations),
          createdAt: createdAt,
          source: "benchmark.cross-sdk.runtime.enqueue"
        )
      }
      let enqueueHops = recorder.summary(since: enqueueBaseline)
      let enqueued = await runtime.pendingMutations()
      try require(
        enqueued.count == InstantCrossSDKRuntimeBenchmarkContract.mutationCount,
        operation: "validate cross-SDK runtime enqueue benchmark"
      )
      record(
        "pending-mutation-enqueue.update",
        sample: InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: enqueueDuration,
          operationCount: operations.count,
          pendingMutationCount: enqueued.count,
          actorHopCount: enqueueHops.count,
          actorHopBreakdown: enqueueHops.breakdown,
          cachePath: cacheURL.path
        ),
        into: &samples
      )

      let restoreRecorder = InstantActorHopRecorder()
      var restoreConfiguration = configuration
      restoreConfiguration.actorHopRecorder = restoreRecorder
      let restoreBaseline = restoreRecorder.baseline()
      let (restored, restoreDuration) = try await measured(clockNanoseconds) {
        let relaunched = try await InstantRuntime.bootstrap(configuration: restoreConfiguration)
        return (
          runtime: relaunched,
          todos: try await TodoExample.decode(relaunched.query(TodoExample.query)),
          pending: await relaunched.pendingMutations()
        )
      }
      let restoreHops = restoreRecorder.summary(since: restoreBaseline)
      try require(
        restored.todos.count == 1
          && restored.todos.first?.id == todoID
          && restored.pending.count == InstantCrossSDKRuntimeBenchmarkContract.mutationCount,
        operation: "validate cross-SDK runtime restore benchmark"
      )
      record(
        "offline-restore.relaunch",
        sample: InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: restoreDuration,
          resultCount: restored.todos.count,
          pendingMutationCount: restored.pending.count,
          actorHopCount: restoreHops.count,
          actorHopBreakdown: restoreHops.breakdown,
          cachePath: cacheURL.path
        ),
        into: &samples
      )

      _ = try await restored.runtime.closeConnection()
      let drainBaseline = restoreRecorder.baseline()
      let (drain, drainDuration) = try await measured(clockNanoseconds) {
        _ = try await restored.runtime.connect()
        return try await restored.runtime.flushPendingMutations()
      }
      let drainHops = restoreRecorder.summary(since: drainBaseline)
      try require(
        drain.confirmed.count == InstantCrossSDKRuntimeBenchmarkContract.mutationCount
          && drain.pendingMutationCount == 0,
        operation: "validate cross-SDK runtime reconnect-drain benchmark"
      )
      record(
        "reconnect-outbox-drain",
        sample: InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: drainDuration,
          operationCount: drain.request.mutations.count,
          resultCount: drain.confirmed.count,
          pendingMutationCount: drain.pendingMutationCount,
          actorHopCount: drainHops.count,
          actorHopBreakdown: drainHops.breakdown,
          cachePath: cacheURL.path
        ),
        into: &samples
      )

      finalTodoCount = restored.todos.count
      finalPendingMutationCount = drain.pendingMutationCount
    }

    let metrics = InstantCrossSDKRuntimeBenchmarkContract.metricNames.map {
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
      finalTodoCount: finalTodoCount,
      pendingMutationCount: finalPendingMutationCount
    )
  }

  private static func record(
    _ name: String,
    sample: InstantBenchmarkSample,
    into samples: inout [String: [InstantBenchmarkSample]]
  ) {
    samples[name, default: []].append(sample)
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
