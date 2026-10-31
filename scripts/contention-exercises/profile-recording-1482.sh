#!/bin/bash
# M6 (#1482): the `recording` contention exercise alone, 150 s, release, under two profilers on the Mac mini:
#   sample (60 s, symbol-level CPU: where refreshObservers, the server apply, the claim, the encoder and SQLite's mutex
#   spend their time) and xctrace's Swift Concurrency template (50 s: tasks created and alive, actor and executor waits).
# Runs through build.sh on the mini; every output lands at the repo root so the job brings it back.
# Builds like scripts/contention-exercises/run-contention-exercises.sh (same scratch path, warm after M1b/M1c).
set -u
# The job runs with the repository checkout as its working directory (build.sh copies this script elsewhere).
[ -f Package.swift ] || { echo "not at the repository root: $PWD" >&2; exit 64; }
root=$(pwd)
scratch=".build/contention-release"
swift build -j 8 -c release -Xswiftc -enable-testing --product InstantSwiftDataCoreTests --scratch-path "$scratch" 2>&1 | grep -E "error:|Build complete" || true
# The products folder as this toolchain lays it out (Swift 6.4 on the mini: out/Products/Release).
products=$(swift build -c release -Xswiftc -enable-testing --product InstantSwiftDataCoreTests --scratch-path "$scratch" --show-bin-path 2>/dev/null | tail -1)
[ -d "$products" ] || products="$scratch/arm64-apple-macosx/release"
bundle="$products/InstantSwiftDataCoreTests.xctest"
echo "products=$products" 
developer=$(xcode-select -p)
platform="$developer/Platforms/MacOSX.platform/Developer"
helper="$developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
[ -x "$helper" ] || helper=$(dirname "$(xcrun --find swift)")/../libexec/swift/pm/swiftpm-testing-helper
log="$root/m6-recording.log"
: > "$log"
echo "M6 start $(date '+%Y-%m-%dT%H:%M:%S%z') machine=$(sysctl -n hw.model) load=$(sysctl -n vm.loadavg)" | tee -a "$log"
INSTANT_CONTENTION=1 INSTANT_CONTENTION_SCALE=1 INSTANT_CONTENTION_SECONDS=150 INSTANT_CONTENTION_ONLY=recording \
  DYLD_LIBRARY_PATH="$products:$platform/usr/lib" \
  DYLD_FRAMEWORK_PATH="$products/PackageFrameworks:$products:$platform/Library/Frameworks:$platform/Library/PrivateFrameworks" \
  "$helper" --test-bundle-path "$bundle/Contents/MacOS/InstantSwiftDataCoreTests" --testing-library swift-testing \
  --filter ContentionExercises/recording >> "$log" 2>&1 &
helper_pid=$!
echo "helper pid $helper_pid" | tee -a "$log"
# Wait for the recording window (the setup line), at most 15 min (the fixture may need generating).
for i in $(seq 1 900); do
  if grep -q "^CONTENTION recording setup" "$log"; then break; fi
  if ! kill -0 $helper_pid 2>/dev/null; then echo "helper ended before setup" | tee -a "$log"; exit 1; fi
  sleep 1
done
echo "setup seen at $(date '+%H:%M:%S'); sampling" | tee -a "$log"
sleep 5
if [ "${M6_SAMPLE:-1}" = 1 ]; then sample $helper_pid 60 -mayDie -file "$root/m6-sample-recording.txt" >> "$log" 2>&1; fi
echo "sample done $(date '+%H:%M:%S'); xctrace" | tee -a "$log"
rm -rf "$root/m6-swiftconc.trace"
xcrun xctrace record --template 'Swift Concurrency' --attach $helper_pid --time-limit 45s --output "$root/m6-swiftconc.trace" >> "$log" 2>&1
echo "xctrace done $(date '+%H:%M:%S')" | tee -a "$log"
xcrun xctrace export --input "$root/m6-swiftconc.trace" --toc > "$root/m6-swiftconc-toc.xml" 2>> "$log" || true
for schema in SwiftAliveTaskCountAll SwiftActorCount SwiftActorQueueSize SwiftActorLifetime SwiftConcurrecyTimeProfilerSamples; do
  xcrun xctrace export --input "$root/m6-swiftconc.trace" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$schema\"]" > "$root/m6-$schema.xml" 2>> "$log" || true
done
wait $helper_pid
echo "helper exit $? $(date '+%H:%M:%S')" | tee -a "$log"
grep -E "^CONTENTION" "$log" > "$root/m6-contention-lines.txt" || true
ls -la "$root"/m6-* | tee -a "$log"
# The trace folder (about 20 MB) comes back with the job; it is not deleted here.
du -sh "$root/m6-swiftconc.trace" | tee -a "$log"
exit 0
