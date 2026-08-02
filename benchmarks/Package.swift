// swift-tools-version: 6.0

import PackageDescription

// A separate package, following the Point-Free convention, so the benchmark
// tool's dependencies stay out of the library's own dependency graph.
let package = Package(
  name: "Benchmarks",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: ".."),
    .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.36.0"),
  ],
  targets: [
    .executableTarget(
      name: "InstantColdStartProfiler",
      dependencies: [
        .product(name: "InstantSwiftDataCore", package: "instant-data-swift")
      ],
      path: "Profiler"
    ),
    .executableTarget(
      name: "InstantSwiftDataBenchmarking",
      dependencies: [
        .product(name: "InstantSwiftDataCore", package: "instant-data-swift"),
        .product(name: "Benchmark", package: "package-benchmark"),
        .product(name: "BenchmarkPlugin", package: "package-benchmark"),
      ],
      path: "Benchmarks/InstantSwiftDataBenchmarking"
    ),
  ],
  swiftLanguageModes: [.v6]
)
