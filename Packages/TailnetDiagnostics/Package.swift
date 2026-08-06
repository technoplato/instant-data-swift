// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "TailnetDiagnostics",
  platforms: [
    .iOS(.v16),
    .macOS(.v14),
    .tvOS(.v16),
    .watchOS(.v9),
  ],
  products: [
    .library(name: "InstantDBLogger", targets: ["InstantDBLogger"]),
    .library(name: "InstantToolsLogging", targets: ["InstantToolsLogging"]),
  ],
  dependencies: [
    .package(name: "instant-data-swift", path: "../.."),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "InstantToolsLogging",
      dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .target(
      name: "InstantDBLogger",
      dependencies: [
        "InstantToolsLogging",
        .product(name: "InstantSwiftData", package: "instant-data-swift"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ]
    ),
    .testTarget(
      name: "InstantDBLoggerTests",
      dependencies: ["InstantDBLogger"]
    ),
  ]
)
