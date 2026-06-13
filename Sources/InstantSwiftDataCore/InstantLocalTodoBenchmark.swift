import Foundation

public struct InstantBenchmarkSample: Codable, Equatable, Sendable {
  public var iteration: Int
  public var durationNanoseconds: UInt64
  public var operationCount: Int?
  public var resultCount: Int?
  public var pendingMutationCount: Int?
  public var cachePath: String?

  public init(
    iteration: Int,
    durationNanoseconds: UInt64,
    operationCount: Int? = nil,
    resultCount: Int? = nil,
    pendingMutationCount: Int? = nil,
    cachePath: String? = nil
  ) {
    self.iteration = iteration
    self.durationNanoseconds = durationNanoseconds
    self.operationCount = operationCount
    self.resultCount = resultCount
    self.pendingMutationCount = pendingMutationCount
    self.cachePath = cachePath
  }
}

public struct InstantBenchmarkMetric: Codable, Equatable, Sendable {
  public var name: String
  public var unit: String
  public var samples: [InstantBenchmarkSample]
  public var minNanoseconds: UInt64
  public var p50Nanoseconds: UInt64
  public var p95Nanoseconds: UInt64
  public var maxNanoseconds: UInt64
  public var averageNanoseconds: Double

  public init(name: String, samples: [InstantBenchmarkSample]) {
    let durations = samples.map(\.durationNanoseconds).sorted()
    self.name = name
    self.unit = "nanoseconds"
    self.samples = samples
    self.minNanoseconds = durations.first ?? 0
    self.p50Nanoseconds = Self.percentile(durations, fraction: 0.50)
    self.p95Nanoseconds = Self.percentile(durations, fraction: 0.95)
    self.maxNanoseconds = durations.last ?? 0
    self.averageNanoseconds =
      durations.isEmpty
      ? 0
      : Double(durations.reduce(0, +)) / Double(durations.count)
  }

  private static func percentile(_ sortedDurations: [UInt64], fraction: Double) -> UInt64 {
    guard !sortedDurations.isEmpty else { return 0 }
    let index = Int((Double(sortedDurations.count - 1) * fraction).rounded(.up))
    return sortedDurations[min(index, sortedDurations.count - 1)]
  }
}

public struct InstantLocalTodoBenchmarkResult: Codable, Equatable, Sendable {
  public var suite: String
  public var appID: String
  public var cachePath: String
  public var transport: String
  public var iterations: Int
  public var timestampMs: Int64
  public var ok: Bool
  public var metrics: [InstantBenchmarkMetric]
  public var finalTodoCount: Int
  public var pendingMutationCount: Int

  public init(
    suite: String,
    appID: String,
    cachePath: String,
    transport: String,
    iterations: Int,
    timestampMs: Int64,
    ok: Bool,
    metrics: [InstantBenchmarkMetric],
    finalTodoCount: Int,
    pendingMutationCount: Int
  ) {
    self.suite = suite
    self.appID = appID
    self.cachePath = cachePath
    self.transport = transport
    self.iterations = iterations
    self.timestampMs = timestampMs
    self.ok = ok
    self.metrics = metrics
    self.finalTodoCount = finalTodoCount
    self.pendingMutationCount = pendingMutationCount
  }
}

public struct InstantBenchmarkEvidenceDetails: Codable, Equatable, Sendable {
  public var suite: String
  public var cachePath: String
  public var transport: String
  public var iterations: Int
  public var finalTodoCount: Int
  public var pendingMutationCount: Int
  public var metric: InstantBenchmarkMetric?

  public init(
    suite: String,
    cachePath: String,
    transport: String,
    iterations: Int,
    finalTodoCount: Int,
    pendingMutationCount: Int,
    metric: InstantBenchmarkMetric? = nil
  ) {
    self.suite = suite
    self.cachePath = cachePath
    self.transport = transport
    self.iterations = iterations
    self.finalTodoCount = finalTodoCount
    self.pendingMutationCount = pendingMutationCount
    self.metric = metric
  }
}

extension InstantLocalTodoBenchmarkResult {
  public var evidenceRows: [ValidationEvidenceRow<InstantBenchmarkEvidenceDetails>] {
    let summary = ValidationEvidenceRow(
      caseID: "benchmark.local.todos",
      side: "swift",
      event: "summary",
      appID: appID,
      timestampMs: timestampMs,
      ok: ok,
      details: evidenceDetails()
    )
    return [summary]
      + metrics.map { metric in
        ValidationEvidenceRow(
          caseID: "benchmark.local.todos",
          side: "swift",
          event: metric.name,
          appID: appID,
          timestampMs: timestampMs,
          ok: ok,
          details: evidenceDetails(metric: metric)
        )
      }
  }

  private func evidenceDetails(metric: InstantBenchmarkMetric? = nil) -> InstantBenchmarkEvidenceDetails {
    InstantBenchmarkEvidenceDetails(
      suite: suite,
      cachePath: cachePath,
      transport: transport,
      iterations: iterations,
      finalTodoCount: finalTodoCount,
      pendingMutationCount: pendingMutationCount,
      metric: metric
    )
  }
}

public enum InstantSwiftDataLocalBenchmarks {
  public static let localTodosSuite = "local-todos"
  private static let highBandwidthScalarUpdateCount = 50
  private static let highBandwidthLinkedWriteCount = 20

  public static func runLocalTodos(
    appID: String = "local-benchmark",
    iterations: Int = 3,
    cacheDirectory: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    clockNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
  ) async throws -> InstantLocalTodoBenchmarkResult {
    guard iterations > 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "run local todo benchmark",
        message: "Iterations must be greater than zero.",
        recovery: "Pass '--iterations 1' or a larger value."
      )
    }

    let rootCacheDirectory =
      cacheDirectory
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataBenchmarks-\(makeID())", isDirectory: true)
    let cacheDirectory = rootCacheDirectory
      .appendingPathComponent("run-\(makeID())", isDirectory: true)
    try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

    var samplesByMetric: [String: [InstantBenchmarkSample]] = [:]
    var finalTodoCount = 0
    var pendingMutationCount = 0

    func record(_ metricName: String, _ sample: InstantBenchmarkSample) {
      samplesByMetric[metricName, default: []].append(sample)
    }

    for iteration in 0..<iterations {
      let cacheURL = cacheDirectory
        .appendingPathComponent("local-todos-\(iteration).sqlite")
      let (runtime, bootstrapDuration) = try await measured(clockNanoseconds) {
        try await InstantRuntime.bootstrap(
          configuration: InstantRuntimeConfiguration(
            appID: appID,
            persistenceURL: cacheURL,
            initialAttributes: TodoProjectExample.attributes,
            now: timestamp,
            makeID: makeID
          )
        )
      }
      record(
        "bootstrap.local-sqlite",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: bootstrapDuration,
          cachePath: cacheURL.path
        )
      )

      let seedTransactionID = makeID()
      let seededAt = timestamp()
      var seedRecords: [(id: String, seed: TodoSeedRecord)] = []
      for seed in TodoExample.seedRecords {
        seedRecords.append((try await runtime.localID(named: seed.localIDName), seed))
      }
      let seedOperations = TodoExample.seedOperations(
        records: seedRecords,
        baseCreatedAt: seededAt,
        transactionID: seedTransactionID
      )
      let (_, seedDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: seedTransactionID, operations: seedOperations),
          createdAt: seededAt,
          source: "benchmark.local.todos.seed"
        )
      }
      record(
        "triple-insert.seed",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: seedDuration,
          operationCount: seedOperations.count,
          pendingMutationCount: await runtime.pendingMutations().count
        )
      )

      let (seededTodos, queryDuration) = try await measured(clockNanoseconds) {
        try await TodoExample.decode(runtime.query(TodoExample.query))
      }
      record(
        "query-materialization.todos",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: queryDuration,
          resultCount: seededTodos.count
        )
      )

      let terminalID = try await runtime.localID(named: "examples.todos.seed.terminal")
      let updateTransactionID = makeID()
      let updatedAt = timestamp()
      let updatedTerminalText = "Run the benchmarked terminal workflow"
      let updateOperations = TodoExample.updateTextOperations(
        id: terminalID,
        text: updatedTerminalText,
        updatedAt: updatedAt,
        transactionID: updateTransactionID
      )
      let (_, updateDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: updateTransactionID, operations: updateOperations),
          createdAt: updatedAt,
          source: "benchmark.local.todos.update"
        )
      }
      record(
        "pending-mutation-enqueue.update",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: updateDuration,
          operationCount: updateOperations.count,
          pendingMutationCount: await runtime.pendingMutations().count
        )
      )

      var scalarOperationCount = 0
      let (_, scalarDuration) = try await measured(clockNanoseconds) {
        for updateIndex in 0..<highBandwidthScalarUpdateCount {
          let scalarTransactionID = makeID()
          let scalarUpdatedAt = timestamp()
          let scalarOperations = TodoExample.updateTextOperations(
            id: terminalID,
            text: "High-bandwidth scalar update \(updateIndex)",
            updatedAt: scalarUpdatedAt,
            transactionID: scalarTransactionID
          )
          scalarOperationCount += scalarOperations.count
          try await runtime.transact(
            InstantStoreTransaction(
              id: scalarTransactionID,
              operations: scalarOperations
            ),
            createdAt: scalarUpdatedAt,
            source: "benchmark.local.todos.scalar-update"
          )
        }
      }
      record(
        "high-bandwidth.scalar-updates",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: scalarDuration,
          operationCount: scalarOperationCount,
          pendingMutationCount: await runtime.pendingMutations().count
        )
      )

      let finalScalarText = "High-bandwidth scalar update \(highBandwidthScalarUpdateCount - 1)"
      let scalarTodos = try await TodoExample.decode(runtime.query(TodoExample.query))
      guard scalarTodos.contains(where: { $0.id == terminalID && $0.text == finalScalarText }) else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected high-bandwidth scalar updates to converge on the final value.",
          recovery: "Inspect repeated update transaction application before trusting benchmark timings."
        )
      }

      let linkedProjectID = try await runtime.localID(named: "examples.benchmark.linked.project")
      let linkedTransactionID = makeID()
      let linkedAt = timestamp()
      var linkedOperations = TodoProjectExample.createProjectOperations(
        id: linkedProjectID,
        title: "Benchmark linked writes",
        createdAt: linkedAt,
        transactionID: linkedTransactionID
      )
      var linkedTodoIDs: [String] = []
      for linkedIndex in 0..<highBandwidthLinkedWriteCount {
        let todoID = try await runtime.localID(named: "examples.benchmark.linked.todo.\(linkedIndex)")
        linkedTodoIDs.append(todoID)
        let todoCreatedAt = InstantTimestamp(milliseconds: linkedAt.milliseconds + Int64(linkedIndex + 1))
        linkedOperations += TodoExample.createOperations(
          id: todoID,
          text: "Linked benchmark todo \(linkedIndex)",
          createdAt: todoCreatedAt,
          transactionID: linkedTransactionID
        )
        linkedOperations += TodoProjectExample.linkOperations(
          todoID: todoID,
          projectID: linkedProjectID,
          updatedAt: todoCreatedAt,
          transactionID: linkedTransactionID
        )
      }
      let (_, linkedDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: linkedTransactionID, operations: linkedOperations),
          createdAt: linkedAt,
          source: "benchmark.local.todos.linked-writes"
        )
      }
      let linkedTodos = try await TodoProjectExample.decodeLinkedTodos(
        runtime.query(TodoProjectExample.todosQuery)
      )
      let materializedLinkedTodoIDs = linkedTodos
        .filter { $0.projectID == linkedProjectID }
        .map(\.id)
      let projectsWithTodos = try await runtime.query(TodoProjectExample.projectsWithTodosQuery)
      let includedLinkedTodoIDs =
        projectsWithTodos.first { $0.id == linkedProjectID }?.links?["todos"]?.map(\.id) ?? []
      guard materializedLinkedTodoIDs == linkedTodoIDs,
        includedLinkedTodoIDs == linkedTodoIDs
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected high-bandwidth linked writes to materialize every linked todo.",
          recovery: "Inspect linked transaction application and include materialization before trusting benchmark timings."
        )
      }
      record(
        "high-bandwidth.linked-writes",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: linkedDuration,
          operationCount: linkedOperations.count,
          resultCount: includedLinkedTodoIDs.count,
          pendingMutationCount: await runtime.pendingMutations().count
        )
      )

      let refreshedTodos = try await TodoExample.decode(runtime.query(TodoExample.query))
      guard refreshedTodos.contains(where: { $0.id == terminalID && $0.text == finalScalarText }) else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected query materialization to include the final scalar update.",
          recovery: "Inspect local triple materialization before trusting benchmark timings."
        )
      }

      let (cachedTodos, cacheDuration) = try await measured(clockNanoseconds) {
        try TodoExample.decode((try await runtime.cachedQuery(TodoExample.query))?.emission.values ?? [])
      }
      guard cachedTodos.contains(where: { $0.id == terminalID && $0.text == finalScalarText }) else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected the query cache to contain the final scalar update.",
          recovery: "Inspect local query cache persistence and materialization before trusting cache timings."
        )
      }
      record(
        "query-cache-read.todos",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: cacheDuration,
          resultCount: cachedTodos.count
        )
      )

      let currentTodos = try await TodoExample.decode(runtime.query(TodoExample.query))
      let resetTransactionID = makeID()
      let resetAt = timestamp()
      let resetOperations = TodoExample.resetOperations(ids: currentTodos.map(\.id))
      let (_, resetDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: resetTransactionID, operations: resetOperations),
          createdAt: resetAt,
          source: "benchmark.local.todos.reset"
        )
      }
      record(
        "triple-retract.reset",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: resetDuration,
          operationCount: resetOperations.count,
          pendingMutationCount: await runtime.pendingMutations().count
        )
      )

      let (relaunchedTodosAndPending, relaunchDuration) = try await measured(clockNanoseconds) {
        let relaunchedRuntime = try await InstantRuntime.bootstrap(
          configuration: InstantRuntimeConfiguration(
            appID: appID,
            persistenceURL: cacheURL,
            initialAttributes: TodoProjectExample.attributes,
            now: timestamp,
            makeID: makeID
          )
        )
        return (
          try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query)),
          await relaunchedRuntime.pendingMutations()
        )
      }
      finalTodoCount = relaunchedTodosAndPending.0.count
      pendingMutationCount = relaunchedTodosAndPending.1.count
      record(
        "offline-restore.relaunch",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: relaunchDuration,
          resultCount: finalTodoCount,
          pendingMutationCount: pendingMutationCount,
          cachePath: cacheURL.path
        )
      )
    }

    let metricOrder = [
      "bootstrap.local-sqlite",
      "triple-insert.seed",
      "query-materialization.todos",
      "pending-mutation-enqueue.update",
      "high-bandwidth.scalar-updates",
      "high-bandwidth.linked-writes",
      "query-cache-read.todos",
      "triple-retract.reset",
      "offline-restore.relaunch",
    ]
    let metrics = metricOrder.compactMap { metricName in
      samplesByMetric[metricName].map { InstantBenchmarkMetric(name: metricName, samples: $0) }
    }

    return InstantLocalTodoBenchmarkResult(
      suite: localTodosSuite,
      appID: appID,
      cachePath: cacheDirectory.path,
      transport: "not-implemented-local-cache-only",
      iterations: iterations,
      timestampMs: timestamp().milliseconds,
      ok: true,
      metrics: metrics,
      finalTodoCount: finalTodoCount,
      pendingMutationCount: pendingMutationCount
    )
  }

  private static func measured<Value>(
    _ clockNanoseconds: @Sendable () -> UInt64,
    operation: () async throws -> Value
  ) async throws -> (Value, UInt64) {
    let startedAt = clockNanoseconds()
    let value = try await operation()
    let endedAt = clockNanoseconds()
    return (value, endedAt >= startedAt ? endedAt - startedAt : 0)
  }
}
