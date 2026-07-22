#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCRATCH_PATH="${INSTANT_SWIFT_DATA_MACRO_TESTING_SCRATCH_PATH:-$ROOT/.build-macrotesting}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCODE_MACOS_DEV="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer"
XCODE_MACOS_FRAMEWORKS="$XCODE_MACOS_DEV/Library/Frameworks"
XCODE_MACOS_PRIVATE_FRAMEWORKS="$XCODE_MACOS_DEV/Library/PrivateFrameworks"
JOBS="${INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS:-1}"
TARGET_TRIPLE="${INSTANT_SWIFT_DATA_MACRO_TESTING_TRIPLE:-$(uname -m)-apple-macosx14.0}"

export DEVELOPER_DIR

swift package resolve --scratch-path "$SCRATCH_PATH"

swift build \
  --scratch-path "$SCRATCH_PATH" \
  --triple "$TARGET_TRIPLE" \
  -Xswiftc -target \
  -Xswiftc "$TARGET_TRIPLE" \
  --disable-index-store \
  -j "$JOBS" \
  --target InstantSwiftDataMacros

xcode_flags=(
  -Xswiftc -target -Xswiftc "$TARGET_TRIPLE"
  -Xcc -F -Xcc "$XCODE_MACOS_FRAMEWORKS"
  -Xswiftc -I -Xswiftc "$XCODE_MACOS_DEV/usr/lib"
  -Xswiftc -F -Xswiftc "$XCODE_MACOS_FRAMEWORKS"
  -Xlinker -F -Xlinker "$XCODE_MACOS_FRAMEWORKS"
  -Xlinker -rpath -Xlinker "$XCODE_MACOS_FRAMEWORKS"
  -Xlinker -F -Xlinker "$XCODE_MACOS_PRIVATE_FRAMEWORKS"
  -Xlinker -rpath -Xlinker "$XCODE_MACOS_PRIVATE_FRAMEWORKS"
)

swift test \
  --scratch-path "$SCRATCH_PATH" \
  --triple "$TARGET_TRIPLE" \
  --disable-swift-testing \
  --enable-xctest \
  --disable-index-store \
  -j "$JOBS" \
  --filter InstantSwiftDataMacrosTests.InstantEntityMacroTests \
  "${xcode_flags[@]}" \
  "$@"
