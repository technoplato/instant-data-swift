import CustomDump
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantCrossSDKBenchmarkTests {
  @Test
  func coreComparisonProducesEveryPinnedWorkload() async throws {
    let result = try await InstantSwiftDataCrossSDKBenchmarks.run(iterations: 1)

    expectNoDifference(result.suite, "cross-sdk-core")
    expectNoDifference(result.transport, "in-memory-core")
    expectNoDifference(result.iterations, 1)
    expectNoDifference(result.ok, true)
    expectNoDifference(
      result.metrics.map(\.name),
      InstantCrossSDKBenchmarkContract.metricNames
    )
    expectNoDifference(
      result.metrics.flatMap(\.samples).map(\.iteration),
      Array(repeating: 0, count: InstantCrossSDKBenchmarkContract.metricNames.count)
    )
    #expect(result.metrics.allSatisfy { $0.p50Nanoseconds > 0 })
  }

  @Test
  func contractPinsEquivalentOperationCounts() {
    expectNoDifference(InstantCrossSDKBenchmarkContract.version, 1)
    expectNoDifference(InstantCrossSDKBenchmarkContract.entityCount, 1_000)
    expectNoDifference(InstantCrossSDKBenchmarkContract.projectCount, 100)
    expectNoDifference(InstantCrossSDKBenchmarkContract.todosPerProject, 10)
    expectNoDifference(InstantCrossSDKBenchmarkContract.scalarUpdateCount, 10_000)
    expectNoDifference(InstantCrossSDKBenchmarkContract.storageMetadataCount, 100)
    expectNoDifference(InstantCrossSDKBenchmarkContract.streamChunkCount, 1_000)
  }
}
