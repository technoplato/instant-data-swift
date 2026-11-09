#!/bin/bash
# perf-mem-1797's one gate (2026-11-05 00:25; final: main v1.9.70 8af1ecd7), Mac mini. The tree that lands is
# M2 f504ed51: main (v1.9.70, #1523; v1.9.69 #653 #1517 #1142 #1648) + #1165 #1145 #541 #1500 (merge cfd74320) + #1104 #1105 (merge
# f504ed51). The worktree is at #1149's launch-read green (518b7418: on top of #1107's green 83446b22, on top of M2), so
# every commit below ships with the job (01:30: the launch read folded in; only HEAD's ancestry reaches the mini).
#   1. The whole InstantSwiftDataCoreTests bundle at M2, debug, against Tests/known-failing.txt: the landing's gate.
#      Its exit lines come first; a bundle that does not build stops the job.
#   2. The whole bundle at 518b7418 (#1107's green and #1149's launch read, which land with M2 when it passes); then
#      #1104 red (277a9203), #1105 red (dfe16998), #1107 red (9da1fbf5) and #1149's launch-read red (44fc0c03), debug,
#      at their own commits.
#   3. Release: at M2 the two-hour replay (#1145's criterion), S05's large-allocation sites (#1512) and E07's launch
#      (#1149's before); E07 at 518b7418 (after); the replay at #1145's red sources (213a7563), the same job's A/B.
# Explicit commits, not HEAD: on the mini HEAD is build.sh's snapshot commit.
set -u
cd /Users/laptop/Sync/worktrees/perf-mem-1797
ulimit -n 10240 2>/dev/null || ulimit -n 4096
echo "open files: $(ulimit -n)"
git log -1 --oneline
SNAP=$(git rev-parse HEAD)
M2=f504ed51
LAUNCH=518b7418
RED1104=277a9203
RED1105=dfe16998
RED1107=9da1fbf5
RED1149=44fc0c03
RED1145=213a7563
OUT=.runs-1797
summary() { grep -E '✘|Test run with|recorded an issue|failed after|error:' "$1" | tail -${2:-60}; }
# A commit's Sources and Tests exactly (no-overlay: files the commit lacks are removed).
at() { git restore --source="$1" --staged --worktree -- Sources Tests && echo "-- at $(git rev-parse --short "$1")"; }
bundle() { # <out-dir> <label>
  nice -n 10 scripts/known-failing-tests.sh run "$1" --jobs 6 > "$1-run.log" 2>&1
  echo "== $2 bundle run exit $?"
  tail -5 "$1-run.log"
  if [ ! -f "$1/summary.json" ]; then
    grep -hE 'error:' "$1/build.log" 2>/dev/null | sort -u | head -40
    echo "== $2 bundle did not build"
    return 2
  fi
  scripts/known-failing-tests.sh compare "$1" > "$1-compare.log" 2>&1
  local status=$?
  echo "== $2 bundle compare exit $status"
  tail -40 "$1-compare.log"
  return $status
}

echo "== 1. the whole bundle at $M2"
at "$M2"
bundle "$OUT/bundle" "M2"
gate=$?
if [ "$gate" = 2 ]; then git restore --source="$SNAP" --staged --worktree -- Sources Tests; exit 2; fi

echo "== 2. the whole bundle at #1107's green and #1149's launch read $LAUNCH"
at "$LAUNCH"
bundle "$OUT/bundle-launch" "LAUNCH"
echo "== launch gate $?"

echo "== 2a. #1104 red at $RED1104"
at "$RED1104"
swift test -j 6 --filter 'InstantStoredFileEvictionTests' > $OUT/1104-red.log 2>&1
echo "== 1104 red exit $?"
summary $OUT/1104-red.log 30
echo "== 2b. #1105 red at $RED1105"
at "$RED1105"
swift test -j 6 --filter 'InstantStoredFileEvictionTests' > $OUT/1105-red.log 2>&1
echo "== 1105 red exit $?"
summary $OUT/1105-red.log 30
echo "== 2c. #1107 red at $RED1107"
at "$RED1107"
swift test -j 6 --filter 'InstantLaunchResidencyTests' > $OUT/1107-red.log 2>&1
echo "== 1107 red exit $?"
summary $OUT/1107-red.log 30
echo "== 2d. #1149's launch-read red at $RED1149"
at "$RED1149"
swift test -j 6 --filter 'InstantLaunchResidencyTests' > $OUT/1149-red.log 2>&1
echo "== 1149 red exit $?"
summary $OUT/1149-red.log 30

replay_lines() { grep -hE 'MEMORY-REPLAY-SUMMARY|MEMORY-REPLAY phone minute=(5|30|60|90|120) |recorded an issue|Resident facts went|heap grew' "$1"* 2>/dev/null | cut -c1-420 | tail -14; }
memory_lines() { grep -hE "$2|recorded an issue" "$1"* 2>/dev/null | cut -c1-400 | head -${3:-70}; }
# The green side is the tree that ships (M2: it carries v1.9.68's splice, which changes no resident fact).
echo "== 3a. the two-hour replay at $M2: the sweep and unload in place"
at "$M2"
scripts/memory-exercises/run-memory-exercises.sh --log $OUT/replay-green.log --suite replay > $OUT/replay-green.out 2>&1
echo "== replay green exit $?"
replay_lines $OUT/replay-green.log
echo "== 3a'. S05's large-allocation sites at $M2"
INSTANT_MEMORY_SITES=1 scripts/memory-exercises/run-memory-exercises.sh --skip-build --log $OUT/s05.log --suite 's05LargeAllocationSites' > $OUT/s05.out 2>&1
echo "== s05 exit $?"
memory_lines $OUT/s05.log 'S05'
echo "== 3a''. E07's launch at $M2 (#1149 before)"
scripts/memory-exercises/run-memory-exercises.sh --skip-build --log $OUT/e07-m2.log --suite 'e07LaunchResident' > $OUT/e07-m2.out 2>&1
echo "== e07 m2 exit $?"
memory_lines $OUT/e07-m2.log 'E07' 20
echo "== 3b. E07's launch at $LAUNCH (#1107 + #1149's launch read: after)"
at "$LAUNCH"
scripts/memory-exercises/run-memory-exercises.sh --log $OUT/e07-launch.log --suite 'e07LaunchResident' > $OUT/e07-launch.out 2>&1
echo "== e07 launch exit $?"
memory_lines $OUT/e07-launch.log 'E07' 20
echo "== 3c. the replay at #1145's red sources ($RED1145): no sweep, closed results copied"
at "$RED1145"
scripts/memory-exercises/run-memory-exercises.sh --log $OUT/replay-red.log --suite replay > $OUT/replay-red.out 2>&1
echo "== replay red exit $?"
replay_lines $OUT/replay-red.log
git restore --source="$SNAP" --staged --worktree -- Sources Tests
echo "== gate: M2 bundle compare exit $gate"
exit $gate
