// swift-tools-version: 6.0

import PackageDescription

// Progressive media end to end over a live Instant app (#1012, ADR 0021): one client records through the library's
// segmenter and writer, a second plays through AVPlayer and the library's resource loader, and the gap between them is
// measured. Not part of the library's package: it depends on the checkout above it, so that checkout's folder must be
// named instant-data-swift (a local package's identity is its folder's name).
let package = Package(
  name: "ProgressiveMediaLive",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(path: "../.."),
  ],
  targets: [
    .executableTarget(
      name: "progressive-media-live",
      dependencies: [
        .product(name: "InstantSwiftData", package: "instant-data-swift"),
        .product(name: "InstantSwiftDataMedia", package: "instant-data-swift"),
      ]
    ),
  ]
)
