// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ExerciseGemMac",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(name: "ExerciseGemMac", targets: ["ExerciseGemMac"]),
  ],
  dependencies: [
    .package(name: "instant-data-swift", path: "../../.."),
  ],
  targets: [
    .executableTarget(
      name: "ExerciseGemMac",
      dependencies: [
        .product(name: "InstantSwiftDataCore", package: "instant-data-swift"),
      ],
      path: "Sources/ExerciseGemMac"
    ),
  ]
)
