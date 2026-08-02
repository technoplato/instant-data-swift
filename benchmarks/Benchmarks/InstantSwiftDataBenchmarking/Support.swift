import Foundation
import InstantSwiftDataCore

let benchmarkNamespace = "todos"

let benchmarkPlan = InstantQueryPlan(id: "benchmark.todos", namespace: benchmarkNamespace)

func benchmarkTimestamp(_ index: Int) -> InstantTimestamp {
  InstantTimestamp(milliseconds: 1_700_000_000_000 + Int64(index))
}

func benchmarkPersistenceURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantSwiftDataBenchmarks-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

func benchmarkRuntime(persistenceURL: URL? = nil) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "instant-swift-data-benchmarks",
      persistenceURL: try persistenceURL ?? benchmarkPersistenceURL(),
      initialAttributes: TodoExample.attributes
    )
  )
}

func benchmarkTransaction(index: Int) -> InstantStoreTransaction {
  let transactionID = "benchmark-tx-\(index)"
  return InstantStoreTransaction(
    id: transactionID,
    operations: TodoExample.createOperations(
      id: "benchmark-todo-\(index)",
      text: "benchmark row \(index)",
      createdAt: benchmarkTimestamp(index),
      transactionID: transactionID
    )
  )
}
