// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ExerciseGym",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(name: "ExerciseGym", targets: ["ExerciseGym"]),
  ],
  dependencies: [
    .package(name: "instant-data-swift", path: "../../.."),
  ],
  targets: [
    .executableTarget(
      name: "ExerciseGym",
      dependencies: [
        .product(name: "InstantSwiftDataCore", package: "instant-data-swift"),
      ],
      path: "Sources/ExerciseGym"
    ),
  ]
)
