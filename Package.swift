// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "instant-swift-data",
  platforms: [
    .iOS(.v15),
    .macOS(.v14),
    .macCatalyst(.v15),
    .tvOS(.v15),
    .watchOS(.v8),
  ],
  products: [
    .library(name: "InstantSwiftData", targets: ["InstantSwiftData"]),
    .library(name: "InstantSwiftDataCore", targets: ["InstantSwiftDataCore"]),
    .library(name: "InstantSwiftDataSchema", targets: ["InstantSwiftDataSchema"]),
    .library(name: "InstantSwiftDataMacros", targets: ["InstantSwiftDataMacros"]),
    .library(name: "InstantSwiftDataTesting", targets: ["InstantSwiftDataTesting"]),
    .executable(name: "instant-swift-data", targets: ["instant-swift-data"]),
    .executable(
      name: "instant-swift-data-validation-runner",
      targets: ["InstantSwiftDataValidationRunner"]
    ),
    .executable(
      name: "instant-swift-data-benchmarks",
      targets: ["InstantSwiftDataBenchmarks"]
    ),
  ],
  targets: [
    .target(
      name: "InstantSwiftData",
      dependencies: [
        "InstantSwiftDataCore",
        "InstantSwiftDataMacros",
        "InstantSwiftDataSchema",
      ]
    ),
    .target(name: "InstantSwiftDataCore"),
    .target(name: "InstantSwiftDataSchema"),
    .target(name: "InstantSwiftDataMacros"),
    .target(
      name: "InstantSwiftDataTesting",
      dependencies: [
        "InstantSwiftData",
        "InstantSwiftDataCore",
        "InstantSwiftDataSchema",
      ]
    ),
    .executableTarget(
      name: "instant-swift-data",
      dependencies: ["InstantSwiftDataCore", "InstantSwiftDataSchema"]
    ),
    .executableTarget(
      name: "InstantSwiftDataValidationRunner",
      dependencies: ["InstantSwiftDataTesting"]
    ),
    .executableTarget(
      name: "InstantSwiftDataBenchmarks",
      dependencies: ["InstantSwiftDataCore"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
