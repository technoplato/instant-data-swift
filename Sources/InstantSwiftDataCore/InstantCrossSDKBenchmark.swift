import Foundation

public enum InstantCrossSDKBenchmarkContract {
  public static let version = 1
  public static let entityCount = 1_000
  public static let projectCount = 100
  public static let todosPerProject = 10
  public static let scalarUpdateCount = 10_000
  public static let storageMetadataCount = 100
  public static let streamChunkCount = 1_000

  public static let metricNames = [
    "transaction-transform.scalar",
    "triple-insert.todos",
    "triple-update.todos",
    "triple-retract.todos",
    "query-materialization.flat",
    "query-materialization.nested",
    "query-materialization.reverse",
    "high-bandwidth.scalar-updates",
    "high-bandwidth.linked-writes",
    "storage-metadata.query",
    "stream-write.chunks",
    "stream-read.chunks",
  ]
}

public enum InstantSwiftDataCrossSDKBenchmarks {
  public static let suite = "cross-sdk-core"

  public static func run(
    appID: String = "cross-sdk-core-benchmark",
    iterations: Int = 5,
    clockNanoseconds: @escaping @Sendable () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) async throws -> InstantLocalTodoBenchmarkResult {
    guard iterations > 0 else {
      throw InstantError(
        code: .validationFailed,
        operation: "run cross-SDK benchmark",
        message: "Iterations must be greater than zero.",
        recovery: "Pass '--iterations 1' or a larger value."
      )
    }

    var samples: [String: [InstantBenchmarkSample]] = [:]
    for iteration in 0..<iterations {
      func record(
        _ name: String,
        duration: UInt64,
        operations: Int? = nil,
        results: Int? = nil
      ) {
        samples[name, default: []].append(
          InstantBenchmarkSample(
            iteration: iteration,
            durationNanoseconds: duration,
            operationCount: operations,
            resultCount: results
          )
        )
      }

      let (_, transformDuration) = measured(clockNanoseconds) {
        var operationCount = 0
        for index in 0..<InstantCrossSDKBenchmarkContract.entityCount {
          operationCount +=
            InstantInstamlTransform.updateOperations(
              namespace: TodoExample.namespace,
              entityID: todoID(index),
              fields: [
                "id": .string("ignored"),
                "text": .string("Todo \(index)"),
                "isCompleted": .bool(false),
                "createdAt": .date(fixedDate(index)),
              ],
              txID: "transform",
              txTime: fixedTimestamp(index)
            ).count
        }
        return operationCount
      }
      record(
        "transaction-transform.scalar",
        duration: transformDuration,
        operations: InstantCrossSDKBenchmarkContract.entityCount
      )

      let insertStore = InstantStore(
        snapshot: InstantStoreSnapshot(attributes: TodoProjectExample.attributes)
      )
      let insertOperations = todoOperations(transactionID: "insert")
      let (insertResult, insertDuration) = try await measured(clockNanoseconds) {
        try await insertStore.prepare(
          InstantStoreTransaction(id: "insert", operations: insertOperations)
        ).result
      }
      try require(
        insertResult.tripleCount == InstantCrossSDKBenchmarkContract.entityCount * 4,
        operation: "validate cross-SDK insert benchmark"
      )
      record(
        "triple-insert.todos",
        duration: insertDuration,
        operations: insertOperations.count,
        results: insertResult.tripleCount
      )

      let updateOperations = (0..<InstantCrossSDKBenchmarkContract.entityCount).flatMap { index in
        TodoExample.updateTextOperations(
          id: todoID(index),
          text: "Updated \(index)",
          updatedAt: fixedTimestamp(index + InstantCrossSDKBenchmarkContract.entityCount),
          transactionID: "update"
        )
      }
      let (_, updateDuration) = try await measured(clockNanoseconds) {
        try await insertStore.prepare(
          InstantStoreTransaction(id: "update", operations: updateOperations)
        )
      }
      let updated = try TodoExample.decode(await insertStore.materialize(TodoExample.query))
      try require(
        updated.count == InstantCrossSDKBenchmarkContract.entityCount
          && updated.first?.text == "Updated 0",
        operation: "validate cross-SDK update benchmark"
      )
      record(
        "triple-update.todos",
        duration: updateDuration,
        operations: updateOperations.count,
        results: updated.count
      )

      let retractOperations = (0..<InstantCrossSDKBenchmarkContract.entityCount).flatMap { index in
        TodoExample.deleteOperations(id: todoID(index))
      }
      let (_, retractDuration) = try await measured(clockNanoseconds) {
        try await insertStore.prepare(
          InstantStoreTransaction(id: "retract", operations: retractOperations)
        )
      }
      let retracted = await insertStore.materialize(TodoExample.query)
      try require(retracted.isEmpty, operation: "validate cross-SDK retract benchmark")
      record(
        "triple-retract.todos",
        duration: retractDuration,
        operations: retractOperations.count,
        results: retracted.count
      )

      let queryStore = try await seededTodoStore()
      let (flat, flatDuration) = await measured(clockNanoseconds) {
        await queryStore.materialize(TodoExample.query)
      }
      try require(
        flat.count == InstantCrossSDKBenchmarkContract.entityCount,
        operation: "validate cross-SDK flat query benchmark"
      )
      record(
        "query-materialization.flat",
        duration: flatDuration,
        results: flat.count
      )

      let linkedStore = try await seededLinkedStore()
      let (nested, nestedDuration) = await measured(clockNanoseconds) {
        await linkedStore.materialize(TodoProjectExample.todosWithProjectQuery)
      }
      try require(
        nested.count == InstantCrossSDKBenchmarkContract.entityCount
          && nested.allSatisfy { $0.links?["project"]?.count == 1 },
        operation: "validate cross-SDK nested query benchmark"
      )
      record(
        "query-materialization.nested",
        duration: nestedDuration,
        results: nested.count
      )

      let (reverse, reverseDuration) = await measured(clockNanoseconds) {
        await linkedStore.materialize(TodoProjectExample.projectsWithTodosQuery)
      }
      try require(
        reverse.count == InstantCrossSDKBenchmarkContract.projectCount
          && reverse.allSatisfy {
            $0.links?["todos"]?.count == InstantCrossSDKBenchmarkContract.todosPerProject
          },
        operation: "validate cross-SDK reverse query benchmark"
      )
      record(
        "query-materialization.reverse",
        duration: reverseDuration,
        results: reverse.count
      )

      let scalarStore = try await seededSingleTodoStore()
      let (_, scalarDuration) = try await measured(clockNanoseconds) {
        for index in 0..<InstantCrossSDKBenchmarkContract.scalarUpdateCount {
          _ = try await scalarStore.prepare(
            InstantStoreTransaction(
              id: "scalar-\(index)",
              operations: TodoExample.updateTextOperations(
                id: todoID(0),
                text: "Scalar \(index)",
                updatedAt: fixedTimestamp(index + 10_000),
                transactionID: "scalar-\(index)"
              )
            )
          )
        }
      }
      let scalar = try TodoExample.decode(await scalarStore.materialize(TodoExample.query))
      try require(
        scalar.first?.text
          == "Scalar \(InstantCrossSDKBenchmarkContract.scalarUpdateCount - 1)",
        operation: "validate cross-SDK scalar benchmark"
      )
      record(
        "high-bandwidth.scalar-updates",
        duration: scalarDuration,
        operations: InstantCrossSDKBenchmarkContract.scalarUpdateCount,
        results: scalar.count
      )

      let unlinkedStore = try await seededLinkedStore(includeLinks: false)
      let linkOperations = (0..<InstantCrossSDKBenchmarkContract.entityCount).flatMap { index in
        TodoProjectExample.linkOperations(
          todoID: todoID(index),
          projectID: projectID(index / InstantCrossSDKBenchmarkContract.todosPerProject),
          updatedAt: fixedTimestamp(index + 20_000),
          transactionID: "links"
        )
      }
      let (_, linkDuration) = try await measured(clockNanoseconds) {
        try await unlinkedStore.prepare(
          InstantStoreTransaction(id: "links", operations: linkOperations)
        )
      }
      let linked = await unlinkedStore.materialize(TodoProjectExample.projectsWithTodosQuery)
      try require(
        linked.reduce(0) { $0 + ($1.links?["todos"]?.count ?? 0) }
          == InstantCrossSDKBenchmarkContract.entityCount,
        operation: "validate cross-SDK linked-write benchmark"
      )
      record(
        "high-bandwidth.linked-writes",
        duration: linkDuration,
        operations: linkOperations.count,
        results: linked.count
      )

      let storageStore = try await seededStorageStore()
      let (files, storageDuration) = await measured(clockNanoseconds) {
        await storageStore.materialize(storageQuery)
      }
      try require(
        files.count == InstantCrossSDKBenchmarkContract.storageMetadataCount,
        operation: "validate cross-SDK storage query benchmark"
      )
      record(
        "storage-metadata.query",
        duration: storageDuration,
        results: files.count
      )

      let streamStore = InstantStore(
        snapshot: InstantStoreSnapshot(attributes: streamAttributes)
      )
      let streamOperations = streamChunkOperations()
      let (_, streamWriteDuration) = try await measured(clockNanoseconds) {
        try await streamStore.prepare(
          InstantStoreTransaction(id: "stream-write", operations: streamOperations)
        )
      }
      record(
        "stream-write.chunks",
        duration: streamWriteDuration,
        operations: streamOperations.count,
        results: InstantCrossSDKBenchmarkContract.streamChunkCount
      )
      let (chunks, streamReadDuration) = await measured(clockNanoseconds) {
        await streamStore.materialize(streamQuery)
      }
      try require(
        chunks.count == InstantCrossSDKBenchmarkContract.streamChunkCount,
        operation: "validate cross-SDK stream read benchmark"
      )
      record(
        "stream-read.chunks",
        duration: streamReadDuration,
        results: chunks.count
      )
    }

    let metrics = InstantCrossSDKBenchmarkContract.metricNames.compactMap { name in
      samples[name].map { InstantBenchmarkMetric(name: name, samples: $0) }
    }
    return InstantLocalTodoBenchmarkResult(
      suite: suite,
      appID: appID,
      cachePath: "in-memory",
      transport: "in-memory-core",
      iterations: iterations,
      timestampMs: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
      ok: metrics.count == InstantCrossSDKBenchmarkContract.metricNames.count,
      metrics: metrics,
      finalTodoCount: InstantCrossSDKBenchmarkContract.entityCount,
      pendingMutationCount: 0
    )
  }

  private static func seededTodoStore() async throws -> InstantStore {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: TodoProjectExample.attributes)
    )
    _ = try await store.prepare(
      InstantStoreTransaction(id: "seed", operations: todoOperations(transactionID: "seed"))
    )
    return store
  }

  private static func seededSingleTodoStore() async throws -> InstantStore {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: TodoProjectExample.attributes)
    )
    _ = try await store.prepare(
      InstantStoreTransaction(
        id: "seed-single",
        operations: TodoExample.upsertOperations(
          id: todoID(0),
          text: "Todo 0",
          createdAt: fixedTimestamp(0),
          transactionID: "seed-single"
        )
      )
    )
    return store
  }

  private static func seededLinkedStore(includeLinks: Bool = true) async throws -> InstantStore {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: TodoProjectExample.attributes)
    )
    var operations: [InstantTripleOperation] = []
    for index in 0..<InstantCrossSDKBenchmarkContract.projectCount {
      operations += TodoProjectExample.upsertProjectOperations(
        id: projectID(index),
        title: "Project \(index)",
        createdAt: fixedTimestamp(index),
        transactionID: "linked-seed"
      )
    }
    operations += todoOperations(transactionID: "linked-seed")
    if includeLinks {
      for index in 0..<InstantCrossSDKBenchmarkContract.entityCount {
        operations += TodoProjectExample.linkOperations(
          todoID: todoID(index),
          projectID: projectID(index / InstantCrossSDKBenchmarkContract.todosPerProject),
          updatedAt: fixedTimestamp(index),
          transactionID: "linked-seed"
        )
      }
    }
    _ = try await store.prepare(
      InstantStoreTransaction(id: "linked-seed", operations: operations)
    )
    return store
  }

  private static func todoOperations(transactionID: String) -> [InstantTripleOperation] {
    (0..<InstantCrossSDKBenchmarkContract.entityCount).flatMap { index in
      TodoExample.upsertOperations(
        id: todoID(index),
        text: "Todo \(index)",
        createdAt: fixedTimestamp(index),
        transactionID: transactionID
      )
    }
  }

  private static func seededStorageStore() async throws -> InstantStore {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: storageAttributes))
    let timestamp = fixedTimestamp(0)
    let operations = (0..<InstantCrossSDKBenchmarkContract.storageMetadataCount).flatMap { index in
      let id = "file-\(index)"
      return [
        InstantTripleOperation.insert(
          InstantTriple(
            entityID: id,
            attributeID: InstantAttribute.primaryKeyID(namespace: "$files"),
            value: .string(id),
            txID: "storage",
            txTime: timestamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "$files/path",
            value: .string("bench/file-\(index).txt"),
            txID: "storage",
            txTime: timestamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "$files/size",
            value: .number(Double(index + 1)),
            txID: "storage",
            txTime: timestamp
          )
        ),
      ]
    }
    _ = try await store.prepare(
      InstantStoreTransaction(id: "storage", operations: operations)
    )
    return store
  }

  private static func streamChunkOperations() -> [InstantTripleOperation] {
    let timestamp = fixedTimestamp(0)
    return (0..<InstantCrossSDKBenchmarkContract.streamChunkCount).flatMap { index in
      let id = "chunk-\(index)"
      return [
        InstantTripleOperation.insert(
          InstantTriple(
            entityID: id,
            attributeID: InstantAttribute.primaryKeyID(namespace: "benchmark_stream_chunks"),
            value: .string(id),
            txID: "stream-write",
            txTime: timestamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "benchmark_stream_chunks/index",
            value: .number(Double(index)),
            txID: "stream-write",
            txTime: timestamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "benchmark_stream_chunks/payload",
            value: .json(.object(["index": .number(Double(index))])),
            txID: "stream-write",
            txTime: timestamp
          )
        ),
      ]
    }
  }

  private static let storageAttributes = [
    InstantAttribute.primaryKey(namespace: "$files"),
    InstantAttribute(
      id: "$files/path",
      namespace: "$files",
      name: "path",
      valueType: .string,
      isIndexed: true
    ),
    InstantAttribute(
      id: "$files/size",
      namespace: "$files",
      name: "size",
      valueType: .number,
      isIndexed: true
    ),
  ]

  private static let storageQuery = InstantQueryPlan(
    id: "benchmark.cross-sdk.storage",
    namespace: "$files",
    order: InstantQueryOrder("path", .ascending)
  )

  private static let streamAttributes = [
    InstantAttribute.primaryKey(namespace: "benchmark_stream_chunks"),
    InstantAttribute(
      id: "benchmark_stream_chunks/index",
      namespace: "benchmark_stream_chunks",
      name: "index",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "benchmark_stream_chunks/payload",
      namespace: "benchmark_stream_chunks",
      name: "payload",
      valueType: .json
    ),
  ]

  private static let streamQuery = InstantQueryPlan(
    id: "benchmark.cross-sdk.stream",
    namespace: "benchmark_stream_chunks",
    order: InstantQueryOrder("index", .ascending)
  )

  private static func todoID(_ index: Int) -> String { "todo-\(index)" }
  private static func projectID(_ index: Int) -> String { "project-\(index)" }
  private static func fixedTimestamp(_ index: Int) -> InstantTimestamp {
    InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
  }
  private static func fixedDate(_ index: Int) -> Date {
    Date(timeIntervalSince1970: Double(fixedTimestamp(index).milliseconds) / 1_000)
  }

  private static func require(_ condition: @autoclosure () -> Bool, operation: String) throws {
    guard condition() else {
      throw InstantError(
        code: .validationFailed,
        operation: operation,
        message: "The benchmark workload produced an unexpected result.",
        recovery: "Fix workload parity before comparing performance."
      )
    }
  }

  private static func measured<Value>(
    _ clock: @Sendable () -> UInt64,
    operation: () throws -> Value
  ) rethrows -> (Value, UInt64) {
    let start = clock()
    let value = try operation()
    return (value, clock() - start)
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
