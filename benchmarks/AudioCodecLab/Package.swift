// swift-tools-version: 6.0

import PackageDescription

// The codec measurements behind ADR 0021 (#1012): which compressed format a recording's audio travels in.
// A separate package with no dependency on the library, so it builds in seconds and runs the same code on a Mac
// (`audio-codec-lab`) and on a phone (the test target, run on the device by xcodebuild).
let package = Package(
  name: "AudioCodecLab",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "AudioCodecLab", targets: ["AudioCodecLab"]),
    .executable(name: "audio-codec-lab", targets: ["audio-codec-lab"]),
  ],
  targets: [
    .target(name: "AudioCodecLab"),
    .executableTarget(name: "audio-codec-lab", dependencies: ["AudioCodecLab"]),
    // Resources/speech.wav is copied in by scripts/run_on_phone.sh for a run and never committed (.gitignore).
    .testTarget(name: "AudioCodecLabTests", dependencies: ["AudioCodecLab"], resources: [.copy("Resources")]),
  ],
  swiftLanguageModes: [.v5]
)
