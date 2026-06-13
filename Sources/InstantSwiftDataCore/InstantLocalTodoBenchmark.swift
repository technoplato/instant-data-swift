import Foundation

#if canImport(Darwin)
import Darwin
#endif

public struct InstantBenchmarkSample: Codable, Equatable, Sendable {
  public var iteration: Int
  public var durationNanoseconds: UInt64
  public var operationCount: Int?
  public var resultCount: Int?
  public var pendingMutationCount: Int?
  public var memoryBeforeBytes: UInt64?
  public var memoryAfterBytes: UInt64?
  public var memoryDeltaBytes: UInt64?
  public var memoryBudgetBytes: UInt64?
  public var actorHopCount: Int?
  public var actorHopBreakdown: [String: Int]?
  public var cachePath: String?

  public init(
    iteration: Int,
    durationNanoseconds: UInt64,
    operationCount: Int? = nil,
    resultCount: Int? = nil,
    pendingMutationCount: Int? = nil,
    memoryBeforeBytes: UInt64? = nil,
    memoryAfterBytes: UInt64? = nil,
    memoryDeltaBytes: UInt64? = nil,
    memoryBudgetBytes: UInt64? = nil,
    actorHopCount: Int? = nil,
    actorHopBreakdown: [String: Int]? = nil,
    cachePath: String? = nil
  ) {
    self.iteration = iteration
    self.durationNanoseconds = durationNanoseconds
    self.operationCount = operationCount
    self.resultCount = resultCount
    self.pendingMutationCount = pendingMutationCount
    self.memoryBeforeBytes = memoryBeforeBytes
    self.memoryAfterBytes = memoryAfterBytes
    self.memoryDeltaBytes = memoryDeltaBytes
    self.memoryBudgetBytes = memoryBudgetBytes
    self.actorHopCount = actorHopCount
    self.actorHopBreakdown = actorHopBreakdown
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
  private static let highBandwidthMemoryBudgetBytes: UInt64 = 64 * 1024 * 1024
  private static let tripleMemoryTiers: [(metricName: String, tripleCount: Int, budgetBytes: UInt64)] = [
    ("memory-growth.triples.1k", 1_000, 64 * 1024 * 1024),
    ("memory-growth.triples.10k", 10_000, 256 * 1024 * 1024),
    ("memory-growth.triples.50k", 50_000, 1_024 * 1024 * 1024),
  ]
  private static let tripleMemoryTodoOperationCount = 4
  private static let storageMetadataFileCount = 5
  private static let streamChunkCount = 25

  private struct SnapshotObservationResult: Sendable {
    var emissionCount: Int
    var initialCount: Int
  }

  public static func runLocalTodos(
    appID: String = "local-benchmark",
    iterations: Int = 3,
    cacheDirectory: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    clockNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
    memoryBytes: (@Sendable () -> UInt64?)? = nil
  ) async throws -> InstantLocalTodoBenchmarkResult {
    guard iterations > 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "run local todo benchmark",
        message: "Iterations must be greater than zero.",
        recovery: "Pass '--iterations 1' or a larger value."
      )
    }

    let measureMemoryBytes = memoryBytes ?? residentMemoryBytes
    let actorHopRecorder = InstantActorHopRecorder()
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

    func runtimeConfiguration(persistenceURL: URL) -> InstantRuntimeConfiguration {
      var configuration = InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: persistenceURL,
        initialAttributes: TodoProjectExample.attributes,
        now: timestamp,
        makeID: makeID
      )
      configuration.actorHopRecorder = actorHopRecorder
      return configuration
    }

    for iteration in 0..<iterations {
      let cacheURL = cacheDirectory
        .appendingPathComponent("local-todos-\(iteration).sqlite")
      let (runtime, bootstrapDuration) = try await measured(clockNanoseconds) {
        try await InstantRuntime.bootstrap(
          configuration: runtimeConfiguration(persistenceURL: cacheURL)
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

      _ = try await runtime.signInWithRefreshToken(
        "benchmark-refresh-token-\(iteration)",
        userID: "benchmark-user"
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
      let seedActorHopBaseline = actorHopRecorder.baseline()
      let (_, seedDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: seedTransactionID, operations: seedOperations),
          createdAt: seededAt,
          source: "benchmark.local.todos.seed"
        )
      }
      let seedActorHops = actorHopRecorder.summary(since: seedActorHopBaseline)
      record(
        "triple-insert.seed",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: seedDuration,
          operationCount: seedOperations.count,
          pendingMutationCount: await runtime.pendingMutations().count,
          actorHopCount: seedActorHops.count,
          actorHopBreakdown: seedActorHops.breakdown
        )
      )

      let queryActorHopBaseline = actorHopRecorder.baseline()
      let (seededTodos, queryDuration) = try await measured(clockNanoseconds) {
        try await TodoExample.decode(runtime.query(TodoExample.query))
      }
      let queryActorHops = actorHopRecorder.summary(since: queryActorHopBaseline)
      record(
        "query-materialization.todos",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: queryDuration,
          resultCount: seededTodos.count,
          actorHopCount: queryActorHops.count,
          actorHopBreakdown: queryActorHops.breakdown
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
      let updateActorHopBaseline = actorHopRecorder.baseline()
      let (_, updateDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: updateTransactionID, operations: updateOperations),
          createdAt: updatedAt,
          source: "benchmark.local.todos.update"
        )
      }
      let updateActorHops = actorHopRecorder.summary(since: updateActorHopBaseline)
      record(
        "pending-mutation-enqueue.update",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: updateDuration,
          operationCount: updateOperations.count,
          pendingMutationCount: await runtime.pendingMutations().count,
          actorHopCount: updateActorHops.count,
          actorHopBreakdown: updateActorHops.breakdown
        )
      )

      var scalarOperationCount = 0
      let scalarMemoryBefore = measureMemoryBytes()
      let scalarActorHopBaseline = actorHopRecorder.baseline()
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
      let scalarActorHops = actorHopRecorder.summary(since: scalarActorHopBaseline)
      let scalarMemoryAfter = measureMemoryBytes()
      let scalarMemoryDelta = try validatedMemoryDelta(
        before: scalarMemoryBefore,
        after: scalarMemoryAfter,
        budget: highBandwidthMemoryBudgetBytes,
        operation: "high-bandwidth scalar updates"
      )
      record(
        "high-bandwidth.scalar-updates",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: scalarDuration,
          operationCount: scalarOperationCount,
          pendingMutationCount: await runtime.pendingMutations().count,
          memoryBeforeBytes: scalarMemoryBefore,
          memoryAfterBytes: scalarMemoryAfter,
          memoryDeltaBytes: scalarMemoryDelta,
          memoryBudgetBytes: highBandwidthMemoryBudgetBytes,
          actorHopCount: scalarActorHops.count,
          actorHopBreakdown: scalarActorHops.breakdown
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
      let linkedMemoryBefore = measureMemoryBytes()
      let linkedActorHopBaseline = actorHopRecorder.baseline()
      let (_, linkedDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: linkedTransactionID, operations: linkedOperations),
          createdAt: linkedAt,
          source: "benchmark.local.todos.linked-writes"
        )
      }
      let linkedActorHops = actorHopRecorder.summary(since: linkedActorHopBaseline)
      let linkedMemoryAfter = measureMemoryBytes()
      let linkedMemoryDelta = try validatedMemoryDelta(
        before: linkedMemoryBefore,
        after: linkedMemoryAfter,
        budget: highBandwidthMemoryBudgetBytes,
        operation: "high-bandwidth linked writes"
      )
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
          pendingMutationCount: await runtime.pendingMutations().count,
          memoryBeforeBytes: linkedMemoryBefore,
          memoryAfterBytes: linkedMemoryAfter,
          memoryDeltaBytes: linkedMemoryDelta,
          memoryBudgetBytes: highBandwidthMemoryBudgetBytes,
          actorHopCount: linkedActorHops.count,
          actorHopBreakdown: linkedActorHops.breakdown
        )
      )

      for tier in tripleMemoryTiers {
        let memoryCacheURL = cacheDirectory
          .appendingPathComponent("\(tier.metricName)-\(iteration).sqlite")
        let memoryRuntime = try await InstantRuntime.bootstrap(
          configuration: runtimeConfiguration(persistenceURL: memoryCacheURL)
        )
        let memoryBefore = measureMemoryBytes()
        let memoryTransactionID = makeID()
        let memoryCreatedAt = timestamp()
        let memoryOperations = tripleMemoryOperations(
          iteration: iteration,
          tripleCount: tier.tripleCount,
          transactionID: memoryTransactionID,
          createdAt: memoryCreatedAt
        )
        let memoryActorHopBaseline = actorHopRecorder.baseline()
        let (_, memoryDuration) = try await measured(clockNanoseconds) {
          try await memoryRuntime.transact(
            InstantStoreTransaction(id: memoryTransactionID, operations: memoryOperations),
            createdAt: memoryCreatedAt,
            source: "benchmark.local.todos.\(tier.metricName)"
          )
        }
        let memoryActorHops = actorHopRecorder.summary(since: memoryActorHopBaseline)
        let memoryAfter = measureMemoryBytes()
        let memoryDelta = try validatedMemoryDelta(
          before: memoryBefore,
          after: memoryAfter,
          budget: tier.budgetBytes,
          operation: "\(tier.tripleCount) triple memory workload"
        )
        let memoryTodos = try await TodoExample.decode(memoryRuntime.query(TodoExample.query))
        guard memoryTodos.count == tier.tripleCount / tripleMemoryTodoOperationCount else {
          throw InstantError(
            code: .validationFailed,
            operation: "run local todo benchmark",
            message: "Expected \(tier.tripleCount) triple memory workload to materialize every todo.",
            recovery: "Inspect bulk triple transaction application before trusting memory timings."
          )
        }
        record(
          tier.metricName,
          InstantBenchmarkSample(
            iteration: iteration,
            durationNanoseconds: memoryDuration,
            operationCount: memoryOperations.count,
            resultCount: memoryTodos.count,
            pendingMutationCount: await memoryRuntime.pendingMutations().count,
            memoryBeforeBytes: memoryBefore,
            memoryAfterBytes: memoryAfter,
            memoryDeltaBytes: memoryDelta,
            memoryBudgetBytes: tier.budgetBytes,
            actorHopCount: memoryActorHops.count,
            actorHopBreakdown: memoryActorHops.breakdown
          )
        )
      }

      let benchmarkRoom = InstantRoomHandle(type: "chat", id: "benchmark-local-todos")
      _ = try await runtime.setPresence(
        room: benchmarkRoom,
        values: [
          "name": .string("Benchmark user"),
          "status": .string("online"),
        ]
      )
      let presenceObservationTask = try await snapshotObservationTask(
        stream: try await runtime.observeRoomPresence(room: benchmarkRoom),
        expectedInitialCount: 1,
        operation: "room presence"
      )
      let (presenceObservation, presenceCancellationDuration) = try await measured(clockNanoseconds) {
        presenceObservationTask.cancel()
        let observation = await presenceObservationTask.value
        try await waitForLocalSubscriptionCancellation(operation: "room presence") {
          try await runtime.activeRoomPresenceObservationCount(room: benchmarkRoom)
        }
        return observation
      }
      record(
        "subscription-cancel.presence",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: presenceCancellationDuration,
          operationCount: 1,
          resultCount: presenceObservation.emissionCount
        )
      )

      _ = try await runtime.publishTopicMessage(
        room: benchmarkRoom,
        topic: "sendEmoji",
        payload: .object(["emoji": .string("wave")])
      )
      let topicObservationTask = try await snapshotObservationTask(
        stream: try await runtime.observeRoomTopicMessages(
          room: benchmarkRoom,
          topic: "sendEmoji"
        ),
        expectedInitialCount: 1,
        operation: "room topic"
      )
      let (topicObservation, topicCancellationDuration) = try await measured(clockNanoseconds) {
        topicObservationTask.cancel()
        let observation = await topicObservationTask.value
        try await waitForLocalSubscriptionCancellation(operation: "room topic") {
          try await runtime.activeRoomTopicObservationCount(
            room: benchmarkRoom,
            topic: "sendEmoji"
          )
        }
        return observation
      }
      record(
        "subscription-cancel.topic",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: topicCancellationDuration,
          operationCount: 1,
          resultCount: topicObservation.emissionCount
        )
      )

      var expectedFileByteCounts: [String: Int64] = [:]
      for fileIndex in 0..<storageMetadataFileCount {
        let fileName = "storage-source-\(fileIndex).txt"
        let contents = Data("benchmark file \(iteration)-\(fileIndex)\n".utf8)
        let sourceURL = cacheDirectory
          .appendingPathComponent("storage-source-\(iteration)-\(fileIndex).txt")
        try contents.write(to: sourceURL)
        expectedFileByteCounts[fileName] = Int64(contents.count)
        _ = try await runtime.uploadFile(
          from: sourceURL,
          name: fileName,
          contentType: "text/plain"
        )
      }
      let (storedFiles, storageDuration) = try await measured(clockNanoseconds) {
        try await runtime.storedFiles()
      }
      let storedFileByteCounts = Dictionary(
        uniqueKeysWithValues: storedFiles.map { ($0.name, $0.byteCount) }
      )
      guard storedFileByteCounts == expectedFileByteCounts,
        storedFiles.allSatisfy({ $0.ownerUserID == "benchmark-user" }),
        storedFiles.allSatisfy({ $0.contentType == "text/plain" }),
        storedFiles.allSatisfy({ FileManager.default.fileExists(atPath: $0.localPath) })
      else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected storage metadata query to return every uploaded benchmark file.",
          recovery: "Inspect local file metadata persistence before trusting benchmark timings."
        )
      }
      record(
        "storage-metadata.query",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: storageDuration,
          operationCount: storageMetadataFileCount,
          resultCount: storedFiles.count
        )
      )

      let storageObservationTask = try await snapshotObservationTask(
        stream: try await runtime.observeStoredFiles(),
        expectedInitialCount: storageMetadataFileCount,
        operation: "stored files"
      )
      let (storageObservation, storageCancellationDuration) = try await measured(clockNanoseconds) {
        storageObservationTask.cancel()
        let observation = await storageObservationTask.value
        try await waitForLocalSubscriptionCancellation(operation: "stored files") {
          await runtime.activeStoredFilesObservationCount()
        }
        return observation
      }
      record(
        "subscription-cancel.storage",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: storageCancellationDuration,
          operationCount: 1,
          resultCount: storageObservation.emissionCount
        )
      )

      let streamID = "benchmark/local-todos"
      var appendedStreamChunks: [InstantStreamChunk] = []
      let (_, streamWriteDuration) = try await measured(clockNanoseconds) {
        for chunkIndex in 0..<streamChunkCount {
          let chunk = try await runtime.appendStreamChunk(
            streamID: streamID,
            payload: .object([
              "iteration": .number(Double(iteration)),
              "index": .number(Double(chunkIndex)),
            ])
          )
          appendedStreamChunks.append(chunk)
        }
      }
      guard appendedStreamChunks.map(\.index) == (0..<streamChunkCount).map(Int64.init) else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected stream writes to receive contiguous local indexes.",
          recovery: "Inspect local stream append ordering before trusting benchmark timings."
        )
      }
      record(
        "stream-write.chunks",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: streamWriteDuration,
          operationCount: streamChunkCount,
          resultCount: appendedStreamChunks.count
        )
      )

      let (readStreamChunks, streamReadDuration) = try await measured(clockNanoseconds) {
        try await runtime.streamChunks(streamID: streamID)
      }
      guard readStreamChunks == appendedStreamChunks else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected stream reads to return the written chunks in order.",
          recovery: "Inspect local stream read ordering before trusting benchmark timings."
        )
      }
      record(
        "stream-read.chunks",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: streamReadDuration,
          resultCount: readStreamChunks.count
        )
      )

      let streamObservationTask = try await snapshotObservationTask(
        stream: try await runtime.observeStreamChunks(streamID: streamID),
        expectedInitialCount: streamChunkCount,
        operation: "stream chunks"
      )
      let (streamObservation, streamCancellationDuration) = try await measured(clockNanoseconds) {
        streamObservationTask.cancel()
        let observation = await streamObservationTask.value
        try await waitForLocalSubscriptionCancellation(operation: "stream chunks") {
          try await runtime.activeStreamChunksObservationCount(streamID: streamID)
        }
        return observation
      }
      record(
        "subscription-cancel.stream",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: streamCancellationDuration,
          operationCount: 1,
          resultCount: streamObservation.emissionCount
        )
      )

      let observationTask = try await liveQueryObservationTask(runtime: runtime)
      let (observedEmissionCount, cancellationDuration) = try await measured(clockNanoseconds) {
        observationTask.cancel()
        let observedEmissionCount = await observationTask.value
        try await waitForLiveQueryObserverCancellation(runtime: runtime)
        return observedEmissionCount
      }
      guard observedEmissionCount == 1 else {
        throw InstantError(
          code: .validationFailed,
          operation: "run local todo benchmark",
          message: "Expected live query cancellation to finish after the initial emission.",
          recovery: "Inspect observation cancellation before trusting benchmark timings."
        )
      }
      record(
        "subscription-cancel.live-query",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: cancellationDuration,
          operationCount: 1,
          resultCount: observedEmissionCount
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

      let cacheActorHopBaseline = actorHopRecorder.baseline()
      let (cachedTodos, cacheDuration) = try await measured(clockNanoseconds) {
        try TodoExample.decode((try await runtime.cachedQuery(TodoExample.query))?.emission.values ?? [])
      }
      let cacheActorHops = actorHopRecorder.summary(since: cacheActorHopBaseline)
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
          resultCount: cachedTodos.count,
          actorHopCount: cacheActorHops.count,
          actorHopBreakdown: cacheActorHops.breakdown
        )
      )

      let currentTodos = try await TodoExample.decode(runtime.query(TodoExample.query))
      let resetTransactionID = makeID()
      let resetAt = timestamp()
      let resetOperations = TodoExample.resetOperations(ids: currentTodos.map(\.id))
      let resetActorHopBaseline = actorHopRecorder.baseline()
      let (_, resetDuration) = try await measured(clockNanoseconds) {
        try await runtime.transact(
          InstantStoreTransaction(id: resetTransactionID, operations: resetOperations),
          createdAt: resetAt,
          source: "benchmark.local.todos.reset"
        )
      }
      let resetActorHops = actorHopRecorder.summary(since: resetActorHopBaseline)
      record(
        "triple-retract.reset",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: resetDuration,
          operationCount: resetOperations.count,
          pendingMutationCount: await runtime.pendingMutations().count,
          actorHopCount: resetActorHops.count,
          actorHopBreakdown: resetActorHops.breakdown
        )
      )

      let relaunchActorHopBaseline = actorHopRecorder.baseline()
      let (relaunchedState, relaunchDuration) = try await measured(clockNanoseconds) {
        let relaunchedRuntime = try await InstantRuntime.bootstrap(
          configuration: runtimeConfiguration(persistenceURL: cacheURL)
        )
        return (
          todos: try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query)),
          pending: await relaunchedRuntime.pendingMutations(),
          runtime: relaunchedRuntime
        )
      }
      let relaunchActorHops = actorHopRecorder.summary(since: relaunchActorHopBaseline)
      finalTodoCount = relaunchedState.todos.count
      pendingMutationCount = relaunchedState.pending.count
      record(
        "offline-restore.relaunch",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: relaunchDuration,
          resultCount: finalTodoCount,
          pendingMutationCount: pendingMutationCount,
          actorHopCount: relaunchActorHops.count,
          actorHopBreakdown: relaunchActorHops.breakdown,
          cachePath: cacheURL.path
        )
      )

      let flushActorHopBaseline = actorHopRecorder.baseline()
      let (flushResult, flushDuration) = try await measured(clockNanoseconds) {
        try await relaunchedState.runtime.flushPendingMutations()
      }
      let flushActorHops = actorHopRecorder.summary(since: flushActorHopBaseline)
      pendingMutationCount = flushResult.pendingMutationCount
      record(
        "outbox-flush.local-transport",
        InstantBenchmarkSample(
          iteration: iteration,
          durationNanoseconds: flushDuration,
          operationCount: flushResult.request.mutations.count,
          resultCount: flushResult.confirmed.count,
          pendingMutationCount: pendingMutationCount,
          actorHopCount: flushActorHops.count,
          actorHopBreakdown: flushActorHops.breakdown
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
      "memory-growth.triples.1k",
      "memory-growth.triples.10k",
      "memory-growth.triples.50k",
      "storage-metadata.query",
      "stream-write.chunks",
      "stream-read.chunks",
      "subscription-cancel.live-query",
      "subscription-cancel.presence",
      "subscription-cancel.topic",
      "subscription-cancel.storage",
      "subscription-cancel.stream",
      "query-cache-read.todos",
      "triple-retract.reset",
      "offline-restore.relaunch",
      "outbox-flush.local-transport",
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

  private static func tripleMemoryOperations(
    iteration: Int,
    tripleCount: Int,
    transactionID: String,
    createdAt: InstantTimestamp
  ) -> [InstantTripleOperation] {
    let recordCount = tripleCount / tripleMemoryTodoOperationCount
    var operations: [InstantTripleOperation] = []
    operations.reserveCapacity(recordCount * tripleMemoryTodoOperationCount)

    for recordIndex in 0..<recordCount {
      let recordCreatedAt = InstantTimestamp(
        milliseconds: createdAt.milliseconds + Int64(recordIndex)
      )
      operations += TodoExample.upsertOperations(
        id: "benchmark.memory.\(tripleCount).\(iteration).\(recordIndex)",
        text: "Memory benchmark \(tripleCount) triple todo \(recordIndex)",
        createdAt: recordCreatedAt,
        transactionID: transactionID
      )
    }

    return operations
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

  private static func liveQueryObservationTask(
    runtime: InstantRuntime
  ) async throws -> Task<Int, Never> {
    let stream = await runtime.observe(TodoExample.query)
    let firstEmission = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let observationTask = Task<Int, Never> {
      var iterator = stream.makeAsyncIterator()
      var emissionCount = 0
      while await iterator.next() != nil {
        emissionCount += 1
        if emissionCount == 1 {
          firstEmission.continuation.yield()
          firstEmission.continuation.finish()
        }
      }
      return emissionCount
    }

    var firstEmissionIterator = firstEmission.stream.makeAsyncIterator()
    guard await firstEmissionIterator.next() != nil else {
      observationTask.cancel()
      throw InstantError(
        code: .validationFailed,
        operation: "run local todo benchmark",
        message: "Expected live query observation to emit before cancellation.",
        recovery: "Inspect observation registration before trusting benchmark timings."
      )
    }
    return observationTask
  }

  private static func snapshotObservationTask<Value: Sendable>(
    stream: AsyncStream<[Value]>,
    expectedInitialCount: Int,
    operation: String
  ) async throws -> Task<SnapshotObservationResult, Never> {
    let firstEmission = AsyncStream<Int>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let observationTask = Task<SnapshotObservationResult, Never> {
      var iterator = stream.makeAsyncIterator()
      var emissionCount = 0
      var initialCount = 0
      while let values = await iterator.next() {
        emissionCount += 1
        if emissionCount == 1 {
          initialCount = values.count
          firstEmission.continuation.yield(initialCount)
          firstEmission.continuation.finish()
        }
      }
      return SnapshotObservationResult(
        emissionCount: emissionCount,
        initialCount: initialCount
      )
    }

    var firstEmissionIterator = firstEmission.stream.makeAsyncIterator()
    guard let initialCount = await firstEmissionIterator.next() else {
      observationTask.cancel()
      throw InstantError(
        code: .validationFailed,
        operation: "run local todo benchmark",
        message: "Expected \(operation) observation to emit before cancellation.",
        recovery: "Inspect local snapshot observation registration before trusting cancellation timings."
      )
    }
    guard initialCount == expectedInitialCount else {
      observationTask.cancel()
      throw InstantError(
        code: .validationFailed,
        operation: "run local todo benchmark",
        message: "Expected \(operation) observation to emit \(expectedInitialCount) values.",
        recovery: "Inspect local snapshot persistence before trusting cancellation timings."
      )
    }
    return observationTask
  }

  private static func waitForLocalSubscriptionCancellation(
    operation: String,
    activeCount: () async throws -> Int
  ) async throws {
    for _ in 0..<100 {
      if try await activeCount() == 0 {
        return
      }
      await Task.yield()
    }
    throw InstantError(
      code: .validationFailed,
      operation: "run local todo benchmark",
      message: "Expected \(operation) cancellation to remove its local snapshot observer.",
      recovery: "Inspect AsyncStream termination and local observer cleanup before trusting cancellation timings."
    )
  }

  private static func waitForLiveQueryObserverCancellation(
    runtime: InstantRuntime
  ) async throws {
    for _ in 0..<100 {
      if await runtime.store.activeObservationCount() == 0 {
        return
      }
      await Task.yield()
    }
    throw InstantError(
      code: .validationFailed,
      operation: "run local todo benchmark",
      message: "Expected live query cancellation to remove its store observer.",
      recovery: "Inspect AsyncStream termination and observer cleanup before trusting benchmark timings."
    )
  }

  private static func validatedMemoryDelta(
    before: UInt64?,
    after: UInt64?,
    budget: UInt64,
    operation: String
  ) throws -> UInt64? {
    guard let before, let after else { return nil }
    let delta = after >= before ? after - before : 0
    guard delta <= budget else {
      throw InstantError(
        code: .validationFailed,
        operation: "run local todo benchmark",
        message: "Expected \(operation) resident high-water growth to stay within \(budget) bytes.",
        recovery: "Inspect batching and retained benchmark state before trusting high-bandwidth timings."
      )
    }
    return delta
  }

  private static func residentMemoryBytes() -> UInt64? {
    #if canImport(Darwin)
      var usage = rusage()
      guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
      return UInt64(max(usage.ru_maxrss, 0))
    #else
      return nil
    #endif
  }
}
