import Benchmark
import Foundation
import InstantSwiftDataCore

// Throughput and memory for the paths a live recording runs through: writing
// mutations into the local store and reading them back. A device that cannot
// keep up here drops transcript segments, so a regression should fail a release
// rather than be discovered on a phone.
//
// These run against local persistence only — no network — so the numbers are
// stable enough to compare across runs.
let benchmarks = { @Sendable in
  Benchmark.defaultConfiguration = .init(
    metrics: [
      .wallClock,
      .cpuTotal,
      .mallocCountTotal,
      .peakMemoryResident,
      .throughput,
    ],
    warmupIterations: 1,
    maxDuration: .seconds(20)
  )

  Benchmark("LocalWrite.transact.100") { benchmark in
    let runtime = try await benchmarkRuntime()
    benchmark.startMeasurement()
    for index in 0..<100 {
      try await runtime.transact(
        benchmarkTransaction(index: index),
        createdAt: benchmarkTimestamp(index)
      )
    }
    benchmark.stopMeasurement()
    blackHole(runtime)
  }

  Benchmark("LocalRead.queryOnce.after1kWrites") { benchmark in
    let runtime = try await benchmarkRuntime()
    for index in 0..<1_000 {
      try await runtime.transact(
        benchmarkTransaction(index: index),
        createdAt: benchmarkTimestamp(index)
      )
    }
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      blackHole(try await runtime.queryOnce(benchmarkPlan))
    }
    benchmark.stopMeasurement()
  }

  Benchmark("LocalStore.reopen.with1kEntities") { benchmark in
    let url = try benchmarkPersistenceURL()
    let seeded = try await benchmarkRuntime(persistenceURL: url)
    for index in 0..<1_000 {
      try await seeded.transact(
        benchmarkTransaction(index: index),
        createdAt: benchmarkTimestamp(index)
      )
    }
    benchmark.startMeasurement()
    // Reopening is the cold-start path: the app pays this before it can show
    // a recording list.
    let reopened = try await benchmarkRuntime(persistenceURL: url)
    blackHole(try await reopened.queryOnce(benchmarkPlan))
    benchmark.stopMeasurement()
  }

  // Ports upstream's only core benchmark (`instaql.bench.ts` `big query`):
  // a four-level cyclic join over the fixed Zeneca fixture, no network, no I/O.
  // Correctness is pinned by
  // `upstreamInstaQLBigQueryDeepJoinMaterializes` in the unit suite; this
  // workload exists so Swift-vs-TypeScript join cost can be compared on the
  // same plan (TS: `core.instaql.big-query.zeneca` in observe.ts).
  Benchmark("LocalRead.deepJoin.zeneca") { benchmark in
    let store = try loadZenecaStore()
    // Load cost is setup, not the join path under measurement.
    blackHole(await store.materialize(zenecaBigQueryPlan))
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations {
      blackHole(await store.materialize(zenecaBigQueryPlan))
    }
    benchmark.stopMeasurement()
  }
}
