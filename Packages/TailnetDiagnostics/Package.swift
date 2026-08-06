// swift-tools-version: 6.0

import PackageDescription

/// Extracted from Scribe for Instant recipe apps. Target names stay **unique**
/// across the dual-dev graph with Scribe (which also owns InstantDBLogger /
/// InstantToolsLogging targets). Product names match the historical Scribe
/// module names where practical for Recipes imports after rename.
let package = Package(
  name: "TailnetDiagnostics",
  platforms: [
    .iOS(.v16),
    .macOS(.v14),
    .tvOS(.v16),
    .watchOS(.v9),
  ],
  products: [
    .library(name: "TailnetInstantDBLogger", targets: ["TailnetInstantDBLogger"]),
    .library(name: "TailnetInstantToolsLogging", targets: ["TailnetInstantToolsLogging"]),
  ],
  dependencies: [
    .package(name: "instant-data-swift", path: "../.."),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "TailnetInstantToolsLogging",
      dependencies: [
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ],
      path: "Sources/InstantToolsLogging"
    ),
    .target(
      name: "TailnetInstantDBLogger",
      dependencies: [
        "TailnetInstantToolsLogging",
        .product(name: "InstantSwiftData", package: "instant-data-swift"),
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "DependenciesMacros", package: "swift-dependencies"),
      ],
      path: "Sources/InstantDBLogger"
    ),
    .testTarget(
      name: "TailnetInstantDBLoggerTests",
      dependencies: ["TailnetInstantDBLogger"],
      path: "Tests/InstantDBLoggerTests"
    ),
  ]
)
