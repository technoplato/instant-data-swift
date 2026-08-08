// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ExerciseGem",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(name: "ExerciseGem", targets: ["ExerciseGem"]),
  ],
  dependencies: [
    .package(name: "instant-data-swift", path: "../../.."),
  ],
  targets: [
    .executableTarget(
      name: "ExerciseGem",
      dependencies: [
        .product(name: "InstantSwiftDataCore", package: "instant-data-swift"),
      ],
      path: "Sources/ExerciseGem"
    ),
  ]
)
