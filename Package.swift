// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "instant-data",
  platforms: [
    .iOS(.v15),
    .macOS(.v14),
    .macCatalyst(.v15),
    .tvOS(.v15),
    .watchOS(.v8),
  ],
  products: [
    .library(name: "InstantData", targets: ["InstantData"]),
    .library(name: "InstantDataCore", targets: ["InstantDataCore"]),
    .library(name: "InstantDataSchema", targets: ["InstantDataSchema"]),
    .library(name: "InstantDataTesting", targets: ["InstantDataTesting"]),
    .executable(name: "instant-data", targets: ["instant-data"]),
    .executable(
      name: "instantdata-validation-swift-runner",
      targets: ["InstantDataValidationRunner"]
    ),
  ],
  targets: [
    .target(
      name: "InstantData",
      dependencies: ["InstantDataCore", "InstantDataSchema"]
    ),
    .target(name: "InstantDataCore"),
    .target(name: "InstantDataSchema"),
    .target(
      name: "InstantDataTesting",
      dependencies: ["InstantData", "InstantDataCore", "InstantDataSchema"]
    ),
    .executableTarget(
      name: "instant-data",
      dependencies: ["InstantDataSchema"]
    ),
    .executableTarget(
      name: "InstantDataValidationRunner",
      dependencies: ["InstantDataTesting"]
    ),
  ],
  swiftLanguageModes: [.v6]
)

