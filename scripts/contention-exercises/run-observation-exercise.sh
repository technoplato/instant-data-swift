#!/bin/bash
# The observation exercise (#1493): build InstantObservationExercise in release and run it alone (48 live FetchAll
# observers, one write at a time to a row all 48 show), and keep its OBSERVATION lines: the library tasks the open
# observations keep, and the wall time from the store's publication to each wrapper's value. An executable, because
# the wrapper test bundle does not link in release on the macOS 27 SDK (two SwiftUI fixture tests' View.task(id:)).
#
# usage: run-observation-exercise.sh [--writes 200] [--idle 0] [--trace <dir>] [--out observation.txt]
#        [--scratch .build/observation-release] [--jobs 6]
# --trace records xctrace's Swift Concurrency template over the idle window (pass --idle too) and exports the TOC and
# every table whose schema names tasks into <dir>. Run it through the machine's build queue (build.sh, mini first): it
# builds, then runs one test process alone. Before and after are the same command at two commits on the same machine.
#
# History:
# - 2026-10-31: #1493: created with the exercise; the exercise moved to an executable target.
set -euo pipefail

writes=200
idle=0
trace=""
out=""
scratch=".build/observation-release"
jobs=6
while [ $# -gt 0 ]; do
  case "$1" in
    --writes) writes=$2; shift 2 ;;
    --idle) idle=$2; shift 2 ;;
    --trace) trace=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --scratch) scratch=$2; shift 2 ;;
    --jobs) jobs=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
log=$(mktemp -t observation-exercise)

# Release, as a phone runs the library.
set +e
swift build -j "$jobs" -c release --product InstantObservationExercise --scratch-path "$scratch" > "$log.build" 2>&1
build_status=$?
set -e
grep -E "error:|Build complete" "$log.build" || true
if [ $build_status -ne 0 ]; then
  echo "build exit $build_status; full log: $log.build" >&2
  exit 1
fi

products="$scratch/out/Products/Release"
[ -d "$products" ] || products="$scratch/arm64-apple-macosx/release"
exercise="$products/InstantObservationExercise"
# A store opens several read connections (#1131).
ulimit -n 4096 || true

commit=${OBSERVATION_COMMIT:-$(git rev-parse --short HEAD 2>/dev/null || echo unknown)}
echo "OBSERVATION run machine=$(sysctl -n hw.model) cores=$(sysctl -n hw.ncpu) load=\"$(sysctl -n vm.loadavg)\" commit=$commit date=$(date '+%Y-%m-%dT%H:%M:%S%z') writes=$writes idle=$idle" > "$log"
INSTANT_OBSERVATION_WRITES="$writes" INSTANT_OBSERVATION_IDLE_SECONDS="$idle" "$exercise" >> "$log" 2>&1 &
helper_pid=$!

if [ -n "$trace" ] && [ "$idle" -gt 2 ]; then
  mkdir -p "$trace"
  for _ in $(seq 1 300); do
    grep -q "^OBSERVATION idle" "$log" && break
    kill -0 $helper_pid 2>/dev/null || break
    sleep 1
  done
  if grep -q "^OBSERVATION idle" "$log"; then
    rm -rf "$trace/observation.trace"
    xcrun xctrace record --template 'Swift Concurrency' --attach $helper_pid --time-limit "$((idle - 2))s" \
      --output "$trace/observation.trace" >> "$log.trace" 2>&1 || true
    xcrun xctrace export --input "$trace/observation.trace" --toc > "$trace/toc.xml" 2>> "$log.trace" || true
    for schema in $(grep -oE 'schema="[^"]*"' "$trace/toc.xml" | sed 's/schema="//; s/"$//' | sort -u | grep -iE "task|actor"); do
      xcrun xctrace export --input "$trace/observation.trace" \
        --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$schema\"]" > "$trace/$schema.xml" 2>> "$log.trace" || true
    done
  fi
fi

set +e
wait $helper_pid
helper_status=$?
set -e
grep -E "^OBSERVATION" "$log" > "${out:-/dev/stdout}" || true
if [ $helper_status -ne 0 ]; then
  cat "$log" >&2
  echo "exercise exit $helper_status; full log: $log" >&2
  exit 1
fi
rm -f "$log" "$log.build"
