#!/bin/bash
# The recording exercise at several library commits in one job on one machine, interleaved, each run alone and beside
# a synthetic CPU load (#1491).
#
# Why: the #1491 bisect ran one commit per job, and the jobs met different neighbours on the Mac mini: every run that
# shared the machine with another job measured a fast transact hold, every run alone a slow one, and between two of
# them every line moved together (read.local, which never takes the gate, 0.67 -> 3.34 ms). A day's commits cannot be
# told from the machine's state that way. Here every commit runs in every condition, in a rotated order, round after
# round, and each run records what else used the CPU while it ran.
#
# usage: ab-commits.sh [--commits "287f77d1 4accbf45 HEAD"] [--rounds 2] [--load 6] [--only recording]
#                      [--seconds 60] [--out-dir ab-out] [--jobs 8] [--bench-runs 0] [--test-filter <regex>]
# Each commit other than HEAD is exported (git archive) under .build/ab-trees/<sha> and built there once; HEAD builds
# in .build/contention-release. The load is <load> busy shell loops for the length of a run. Output: one file per run,
# <out-dir>/<commit>-<condition>-r<round>.txt, and <out-dir>/summary.txt. --bench-runs N then runs the cross-SDK runtime
# benchmark (one todo, 300 transacts back to back: the CPU stays busy, unlike the exercise's one write every 667 ms) N
# times per commit, alternating, into <out-dir>/bench-<commit>-r<run>.json and the summary. --test-filter runs the core
# bundle's matching tests at each commit first (<out-dir>/tests-<commit>.txt).
#
# History:
# - 2026-10-31: #1491: created.
set -uo pipefail

commits="287f77d1 4accbf45 HEAD"
rounds=2
load=6
only=recording
seconds=60
out_dir=ab-out
jobs=8
bench_runs=0
test_filter=""
while [ $# -gt 0 ]; do
  case "$1" in
    --commits) commits=$2; shift 2 ;;
    --rounds) rounds=$2; shift 2 ;;
    --load) load=$2; shift 2 ;;
    --only) only=$2; shift 2 ;;
    --seconds) seconds=$2; shift 2 ;;
    --out-dir) out_dir=$2; shift 2 ;;
    --jobs) jobs=$2; shift 2 ;;
    --bench-runs) bench_runs=$2; shift 2 ;;
    --test-filter) test_filter=$2; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
mkdir -p "$out_dir"
out_dir=$(cd "$out_dir" && pwd)
ulimit -n 4096 2>/dev/null || true
echo "ab-commits: $(sysctl -n hw.model), $(sysctl -n hw.ncpu) cores, perflevels: $(sysctl -n hw.perflevel0.logicalcpu 2>/dev/null)P+$(sysctl -n hw.perflevel1.logicalcpu 2>/dev/null)E; commits: $commits; rounds $rounds; load $load"

tree_for() {   # <commit>: the folder the commit builds and runs in
  if [ "$1" = HEAD ]; then echo "$root"; else echo "$root/.build/ab-trees/$1"; fi
}
name_for() {   # <commit>: the short sha the CONTENTION lines carry
  git rev-parse --short=8 "$1"
}

# Export and build every tree first, so no run overlaps a build of this job. The builds run side by side: a release
# build of the core module is one whole-module compile, one core each.
build_pids=()
for commit in $commits; do
  tree=$(tree_for "$commit")
  if [ "$commit" != HEAD ] && [ ! -f "$tree/Package.swift" ]; then
    rm -rf "$tree" && mkdir -p "$tree"
    git archive "$commit" | tar -x -C "$tree" || { echo "ab-commits: cannot export $commit" >&2; exit 1; }
  fi
  name=$(name_for "$commit")
  (
    started=$(date +%s)
    cd "$tree" && swift build -j "$jobs" -c release -Xswiftc -enable-testing --product InstantSwiftDataCoreTests \
      --scratch-path "$tree/.build/contention-release" > "$out_dir/build-$name.log" 2>&1
    status=$?
    echo "ab-commits: build $name exit $status in $(( $(date +%s) - started )) s"
    grep -E "error:" "$out_dir/build-$name.log" | head -5
  ) &
  build_pids+=($!)
done
wait "${build_pids[@]}"

# --test-filter: the core bundle's tests matching it, at each commit, from the release build (#expect judges there;
# CustomDump's expectNoDifference records nothing in a release build).
if [ -n "$test_filter" ]; then
  developer=$(xcode-select -p)
  platform="$developer/Platforms/MacOSX.platform/Developer"
  helper="$developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"
  for commit in $commits; do
    tree=$(tree_for "$commit")
    name=$(name_for "$commit")
    products="$tree/.build/contention-release/out/Products/Release"
    [ -d "$products" ] || products="$tree/.build/contention-release/arm64-apple-macosx/release"
    (cd "$tree" && DYLD_LIBRARY_PATH="$products:$platform/usr/lib" \
      DYLD_FRAMEWORK_PATH="$products/PackageFrameworks:$products:$platform/Library/Frameworks:$platform/Library/PrivateFrameworks" \
      "$helper" --test-bundle-path "$products/InstantSwiftDataCoreTests.xctest/Contents/MacOS/InstantSwiftDataCoreTests" \
      --testing-library swift-testing --filter "$test_filter" > "$out_dir/tests-$name.txt" 2>&1)
    echo "ab-commits: tests $name: $(grep -E "Test run with" "$out_dir/tests-$name.txt" | tail -1)"
    grep -E "recorded an issue|Expectation failed|􀄵" "$out_dir/tests-$name.txt" | grep -v "known issue" | head -6
  done
fi

spin_pids=()
start_load() {
  for (( spin = 0; spin < $1; spin++ )); do (while :; do :; done) & spin_pids+=($!); done
}
stop_load() {
  # macOS's bash 3.2 calls an empty array unbound under `set -u`.
  [ "${#spin_pids[@]}" -gt 0 ] || return 0
  for pid in "${spin_pids[@]}"; do kill "$pid" 2>/dev/null; done
  wait "${spin_pids[@]}" 2>/dev/null
  spin_pids=()
}
trap stop_load EXIT

neighbours() {   # the processes using the most CPU now, outside this job's own loops
  ps -Ao pcpu=,comm= -r | grep -v -E "ps$|bash$" | head -6 \
    | awk '{ n = split($2, path, "/"); printf "%s%s:%s", (NR > 1 ? ", " : ""), path[n], $1 }'
}

run_one() {   # <commit> <condition> <round>
  local commit=$1 condition=$2 round=$3 tree name file
  tree=$(tree_for "$commit")
  name=$(name_for "$commit")
  file="$out_dir/$name-$condition-r$round.txt"
  [ "$condition" = load ] && start_load "$load"
  sleep 2
  local before after
  before=$(neighbours)
  (cd "$tree" && CONTENTION_COMMIT=$name bash scripts/contention-exercises/run-contention-exercises.sh \
    --only "$only" --seconds "$seconds" --jobs "$jobs" --scratch "$tree/.build/contention-release" --out "$file")
  local status=$?
  after=$(neighbours)
  stop_load
  {
    echo "AB run commit=$name condition=$condition round=$round exit=$status load=\"$(sysctl -n vm.loadavg)\""
    echo "AB neighbours before: $before"
    echo "AB neighbours after: $after"
  } >> "$file"
  echo "ab-commits: $name $condition r$round exit $status; neighbours before: $before"
}

set -- $commits
count=$#
for (( round = 1; round <= rounds; round++ )); do
  for condition in alone load; do
    # Rotate the order each round and condition, so no commit always runs first or last.
    offset=0
    [ "$condition" = load ] && offset=1
    shift_by=$(( (round - 1 + offset) % count ))
    ordered=$(echo $commits | awk -v s="$shift_by" '{ for (i = 0; i < NF; i++) printf "%s ", $(((i + s) % NF) + 1) }')
    for commit in $ordered; do run_one "$commit" "$condition" "$round"; done
  done
done

if [ "$bench_runs" -gt 0 ]; then
  for commit in $commits; do
    tree=$(tree_for "$commit")
    (cd "$tree" && swift build -j "$jobs" -c release -Xswiftc -enable-testing --product instant-swift-data-benchmarks \
      --scratch-path "$tree/.build/contention-release" 2>&1 | grep -E "error:|Build complete")
  done
  for (( run = 1; run <= bench_runs; run++ )); do
    for commit in $commits; do
      tree=$(tree_for "$commit")
      name=$(name_for "$commit")
      bin=$(cd "$tree" && swift build -c release -Xswiftc -enable-testing --product instant-swift-data-benchmarks \
        --scratch-path "$tree/.build/contention-release" --show-bin-path 2>/dev/null | tail -1)/instant-swift-data-benchmarks
      "$bin" --suite cross-sdk-runtime --iterations 300 --app-id "ab-$name-$run" > "$out_dir/bench-$name-r$run.json" \
        2>> "$out_dir/bench.log"
      echo "ab-commits: bench $name r$run exit $?"
    done
  done
fi

{
  echo "== summary (recording.steady): commit condition round | transact hold p50 | write.line p50 | read.local p50 | claim hold p50"
  for file in "$out_dir"/*-r*.txt; do
    [ -f "$file" ] || continue
    label=$(basename "$file" .txt)
    pick() { grep -E "^CONTENTION $only\.steady $1" "$file" | head -1 | sed -E 's/.* p50_ms=([0-9.]+).*/\1/'; }
    echo "$label | $(pick 'gate.hold holder=transact') | $(pick 'call caller=write.line') | $(pick 'call caller=read.local') | $(pick 'gate.hold holder="claim')"
  done
  if [ "$bench_runs" -gt 0 ]; then
    echo "== summary (cross-sdk-runtime, 300 iterations): file | metric p50 ms"
    python3 - "$out_dir" <<'PY'
import glob, json, sys
for path in sorted(glob.glob(f"{sys.argv[1]}/bench-*.json")):
    try:
        metrics = json.load(open(path)).get("metrics", [])
    except ValueError:
        print(f"{path.split('/')[-1]} | unreadable")
        continue
    for metric in metrics:
        samples = sorted(sample["durationNanoseconds"] for sample in metric["samples"])
        print(f"{path.split('/')[-1]} | {metric['name']} {samples[len(samples) // 2] / 1e6:.3f}")
PY
  fi
} | tee "$out_dir/summary.txt"
