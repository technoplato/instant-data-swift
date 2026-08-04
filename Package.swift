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
    .library(name: "AppBuilderV3App", targets: ["AppBuilderV3App"]),
    .library(name: "AuthV3App", targets: ["AuthV3App"]),
    .library(name: "CloudKitDemoV3App", targets: ["CloudKitDemoV3App"]),
    .library(name: "MobileChatV3App", targets: ["MobileChatV3App"]),
    .library(name: "PresenceRecipesV3App", targets: ["PresenceRecipesV3App"]),
    .library(name: "RecipesV3App", targets: ["RecipesV3App"]),
    .library(name: "RemindersV3App", targets: ["RemindersV3App"]),
    .library(name: "StroopwafelV3App", targets: ["StroopwafelV3App"]),
    .library(name: "SyncUpsV3App", targets: ["SyncUpsV3App"]),
    .library(name: "StreamsV3App", targets: ["StreamsV3App"]),
    .library(name: "TodosV3App", targets: ["TodosV3App"]),
    .library(name: "LinkedInfiniteV3App", targets: ["LinkedInfiniteV3App"]),
    .library(name: "VoiceTrailV3App", targets: ["VoiceTrailV3App"]),
    .executable(name: "instant-swift-data", targets: ["instant-swift-data"]),
    .executable(name: "app-builder-v3", targets: ["AppBuilderV3Executable"]),
    .executable(name: "auth-v3", targets: ["AuthV3Executable"]),
    .executable(name: "cloudkit-demo-v3", targets: ["CloudKitDemoV3Executable"]),
    .executable(name: "mobile-chat-v3", targets: ["MobileChatV3Executable"]),
    .executable(name: "presence-recipes-v3", targets: ["PresenceRecipesV3Executable"]),
    .executable(name: "recipes-v3", targets: ["RecipesV3Executable"]),
    .executable(name: "reminders-v3", targets: ["RemindersV3Executable"]),
    .executable(name: "reminders-v3-cli", targets: ["RemindersV3CLIExecutable"]),
    .executable(name: "stroopwafel-v3", targets: ["StroopwafelV3Executable"]),
    .executable(name: "syncups-v3", targets: ["SyncUpsV3Executable"]),
    .executable(name: "streams-v3", targets: ["StreamsV3Executable"]),
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
    // Accept the CasePaths 1.x line so TCA hosts can unify on their newer compatible release.
    .package(url: "https://github.com/pointfreeco/swift-case-paths", "1.0.0"..<"2.0.0"),
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
    .target(
      name: "InstantSwiftDataCore",
      dependencies: [
        .product(name: "IssueReporting", package: "xctest-dynamic-overlay")
      ],
      swiftSettings: strictConcurrencySettings
    ),
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
        "AppBuilderV3App",
        "AuthV3App",
        "CloudKitDemoV3App",
        "InstantSwiftData",
        "InstantSwiftDataCore",
        "MobileChatV3App",
        "PresenceRecipesV3App",
        "RemindersV3App",
        "StroopwafelV3App",
        "SyncUpsV3App",
        "TodosV3App",
        "VoiceTrailV3App",
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "AppBuilderV3App",
      dependencies: [
        "AuthV3App",
        "InstantSwiftData",
        "InstantSwiftDataSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "AuthV3App",
      dependencies: [
        "InstantSwiftData",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "CloudKitDemoV3App",
      dependencies: [
        "AuthV3App",
        "InstantSwiftData",
        "InstantSwiftDataSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "MobileChatV3App",
      dependencies: [
        "AuthV3App",
        "InstantSwiftData",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "PresenceRecipesV3App",
      dependencies: [
        "InstantSwiftData",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "RecipesV3App",
      dependencies: [
        "AuthV3App",
        "InstantSwiftData",
        "LinkedInfiniteV3App",
        "PresenceRecipesV3App",
        "TodosV3App",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "RemindersV3App",
      dependencies: [
        "AuthV3App",
        "InstantSwiftData",
        "InstantSwiftDataSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "StroopwafelV3App",
      dependencies: [
        "InstantSwiftData",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "SyncUpsV3App",
      dependencies: [
        "InstantSwiftData",
        "InstantSwiftDataSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
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
      name: "LinkedInfiniteV3App",
      dependencies: [
        "InstantSwiftData",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "VoiceTrailV3App",
      dependencies: [
        "AuthV3App",
        "InstantSwiftData",
        "InstantSwiftDataSchema",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .target(
      name: "StreamsV3App",
      dependencies: [
        "InstantSwiftData",
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
        "RemindersV3App",
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
      name: "AppBuilderV3Executable",
      dependencies: ["AppBuilderV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "AuthV3Executable",
      dependencies: ["AuthV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "CloudKitDemoV3Executable",
      dependencies: ["CloudKitDemoV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "MobileChatV3Executable",
      dependencies: ["MobileChatV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "PresenceRecipesV3Executable",
      dependencies: ["PresenceRecipesV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "RecipesV3Executable",
      dependencies: [
        "RecipesV3App",
        "LinkedInfiniteV3App",
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "RemindersV3Executable",
      dependencies: ["RemindersV3App", "InstantSwiftData"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "RemindersV3CLIExecutable",
      dependencies: [
        "RemindersV3App",
        "InstantSwiftData",
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "StroopwafelV3Executable",
      dependencies: ["StroopwafelV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "SyncUpsV3Executable",
      dependencies: ["SyncUpsV3App"],
      swiftSettings: strictConcurrencySettings
    ),
    .executableTarget(
      name: "StreamsV3Executable",
      dependencies: ["StreamsV3App"],
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
      name: "AppBuilderV3AppTests",
      dependencies: [
        "AppBuilderV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "AuthV3AppTests",
      dependencies: [
        "AuthV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "CloudKitDemoV3AppTests",
      dependencies: [
        "CloudKitDemoV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "StreamsV3AppTests",
      dependencies: [
        "StreamsV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "MobileChatV3AppTests",
      dependencies: [
        "MobileChatV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "PresenceRecipesV3AppTests",
      dependencies: [
        "PresenceRecipesV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "RecipesV3AppTests",
      dependencies: [
        "RecipesV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "RemindersV3AppTests",
      dependencies: [
        "RemindersV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "StroopwafelV3AppTests",
      dependencies: [
        "StroopwafelV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
      ],
      swiftSettings: strictConcurrencySettings
    ),
    .testTarget(
      name: "SyncUpsV3AppTests",
      dependencies: [
        "SyncUpsV3App",
        .product(name: "CustomDump", package: "swift-custom-dump"),
        .product(name: "DependenciesTestSupport", package: "swift-dependencies"),
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
