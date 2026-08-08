// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ExerciseGymMac",
  platforms: [
    .macOS(.v14),
  ],
  products: [
    .executable(name: "ExerciseGymMac", targets: ["ExerciseGymMac"]),
  ],
  dependencies: [
    .package(name: "instant-data-swift", path: "../../.."),
  ],
  targets: [
    .executableTarget(
      name: "ExerciseGymMac",
      dependencies: [
        .product(name: "InstantSwiftDataCore", package: "instant-data-swift"),
      ],
      path: "Sources/ExerciseGymMac"
    ),
  ]
)
