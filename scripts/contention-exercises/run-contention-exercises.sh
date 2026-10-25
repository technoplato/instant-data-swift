#!/bin/bash
# The concurrency audit's exercises (#1074): build the core test bundle in release with testing enabled, run
# ContentionExercises on the real-size store, and keep the CONTENTION lines.
#
# Every number the audit names is one CONTENTION line, so a fix is measured by running this again on the same machine
# and comparing the same lines (docs/audits/2026-10-24-concurrency-baseline.txt holds the first run's).
#
# usage: run-contention-exercises.sh [--scale 1] [--seconds 60]
#        [--only recording,recording-deferred,prune,prune-inline,server-apply,observers,compaction,compaction-main-hop,launch]
#        [--out contention.txt] [--scratch .build/contention-release] [--jobs 4]
# On a shared Mac, run it through the machine's heavy-job queue; it builds, then runs one test process alone.
#
# History:
# - 2026-10-24: #1074: created with the exercises.
set -euo pipefail

scale=1
seconds=60
only=""
out=""
scratch=".build/contention-release"
jobs=4
while [ $# -gt 0 ]; do
  case "$1" in
    --scale) scale=$2; shift 2 ;;
    --seconds) seconds=$2; shift 2 ;;
    --only) only=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --scratch) scratch=$2; shift 2 ;;
    --jobs) jobs=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
log=$(mktemp -t contention-exercises)

# Release, as a phone runs the library; -enable-testing for the exercises' @testable import.
swift build -j "$jobs" -c release -Xswiftc -enable-testing --product InstantSwiftDataCoreTests --scratch-path "$scratch" \
  2>&1 | grep -E "error:|Build complete" || true

products="$scratch/out/Products/Release"
[ -d "$products" ] || products="$scratch/arm64-apple-macosx/release"
bundle="$products/InstantSwiftDataCoreTests.xctest"
developer=$(xcode-select -p)
platform="$developer/Platforms/MacOSX.platform/Developer"
helper="$developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
[ -x "$helper" ] || helper=$(dirname "$(xcrun --find swift)")/../libexec/swift/pm/swiftpm-testing-helper

{
  # A copy without .git (synced to another Mac) names its commit with CONTENTION_COMMIT.
  commit=${CONTENTION_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}
  echo "CONTENTION run machine=$(sysctl -n hw.model) cores=$(sysctl -n hw.ncpu) load=\"$(sysctl -n vm.loadavg)\" commit=$commit date=$(date '+%Y-%m-%dT%H:%M:%S%z') scale=$scale seconds=$seconds"
  INSTANT_CONTENTION=1 INSTANT_CONTENTION_SCALE="$scale" INSTANT_CONTENTION_SECONDS="$seconds" INSTANT_CONTENTION_ONLY="$only" \
    DYLD_LIBRARY_PATH="$products:$platform/usr/lib" \
    DYLD_FRAMEWORK_PATH="$products/PackageFrameworks:$products:$platform/Library/Frameworks:$platform/Library/PrivateFrameworks" \
    "$helper" --test-bundle-path "$bundle/Contents/MacOS/InstantSwiftDataCoreTests" --testing-library swift-testing \
    --filter ContentionExercises 2>&1
} > "$log" || true

grep -E "^CONTENTION|^REALSIZE-FIXTURE" "$log" > "${out:-/dev/stdout}" || true
if grep -qE "✘|error:" "$log"; then
  grep -E "✘|error:" "$log" >&2
  echo "full log: $log" >&2
  exit 1
fi
rm -f "$log"
