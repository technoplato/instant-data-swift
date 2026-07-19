// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let strictConcurrencySettings: [SwiftSetting] = [
  .enableUpcomingFeature("StrictConcurrency"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
]

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
    .library(name: "InstantSwiftDataTesting", targets: ["InstantSwiftDataTesting"]),
    .library(name: "TodosV3App", targets: ["TodosV3App"]),
    .library(name: "VoiceTrailV3App", targets: ["VoiceTrailV3App"]),
    .executable(name: "instant-swift-data", targets: ["instant-swift-data"]),
    .executable(name: "voicetrail-v3", targets: ["VoiceTrailV3Executable"]),
    .executable(name: "todos-v3", targets: ["TodosV3Executable"]),
    .executable(
      name: "instant-swift-data-validation-runner",
      targets: ["InstantSwiftDataValidationRunner"]
    ),
    .executable(
      name: "instant-swift-data-benchmarks",
      targets: ["InstantSwiftDataBenchmarks"]
    ),
  ],
  dependencies: [
    // Keep swift-parsing on the non-macro CasePaths release compatible with SwiftSyntax 602.
    .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.1.0"),
    // Keep MacroTesting on the SnapshotTesting line compatible with the Xcode Swift Testing framework.
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.18.9"),
    .package(url: "https://github.com/pointfreeco/swift-parsing", from: "0.14.1"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
  ],
  targets: [
    .target(
      name: "InstantSwiftData",
      dependencies: [
        "InstantSwiftDataCore",
        "InstantSwiftDataMacros",
        "InstantSwiftDataSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(name: "InstantSwiftDataCore", swiftSettings: strictConcurrencySettings),
    .target(
      name: "InstantSwiftDataSchema",
      dependencies: ["InstantSwiftDataCore"],
      swiftSettings: strictConcurrencySettings
    ),
    .macro(
      name: "InstantSwiftDataMacros",
      dependencies: [
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "InstantSwiftDataTesting",
      dependencies: [
        "InstantSwiftData",
        "InstantSwiftDataCore",
        "VoiceTrailV3App",
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "TodosV3App",
      dependencies: [
        "InstantSwiftData",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "VoiceTrailV3App",
      dependencies: [
        "InstantSwiftData",
        "InstantSwiftDataSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "InstantSwiftDataCLIParsing",
      dependencies: [
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Parsing", package: "swift-parsing"),
      ],
      path: "Sources/InstantSwiftDataCLI",
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "instant-swift-data",
      dependencies: [
        "InstantSwiftDataCLIParsing",
        "InstantSwiftData",
        "InstantSwiftDataCore",
        "InstantSwiftDataSchema",
        "InstantSwiftDataTesting",
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "InstantSwiftDataValidationRunner",
      dependencies: [
        "InstantSwiftDataCLIParsing",
        "InstantSwiftDataCore",
        "InstantSwiftDataTesting",
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "InstantSwiftDataBenchmarks",
      dependencies: [
        "InstantSwiftDataCLIParsing",
        "InstantSwiftDataCore",
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "TodosV3Executable",
      dependencies: ["TodosV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "VoiceTrailV3Executable",
      dependencies: ["VoiceTrailV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "InstantSwiftDataCoreTests",
      dependencies: [
        "InstantSwiftDataCore",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "InstantSwiftDataTests",
      dependencies: [
        "InstantSwiftData",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "InstantSwiftDataSchemaTests",
      dependencies: [
        "InstantSwiftDataSchema",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "InstantSwiftDataTestingTests",
      dependencies: [
        "InstantSwiftDataCLIParsing",
        "InstantSwiftDataTesting",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "InstantSwiftDataCLIParsingTests",
      dependencies: [
        "InstantSwiftDataCLIParsing",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      path: "Tests/InstantSwiftDataCLITests",
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "InstantSwiftDataMacrosTests",
      dependencies: [
        "InstantSwiftDataMacros",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
        // Keep the root SnapshotTesting pin visible to SwiftPM.
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        // Importing the macro module in tests requires its plugin dependencies to be visible.
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "TodosV3AppTests",
      dependencies: [
        "TodosV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "VoiceTrailV3AppTests",
      dependencies: [
        "VoiceTrailV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
  ],
  swiftLanguageModes: [.v6]
)
