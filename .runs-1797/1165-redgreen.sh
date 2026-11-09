#!/bin/bash
# #1165 and #1145 in one build job (one mini run for both):
#   1. #1165 red: InstantNonResidentWriteTests on main's sources (20b88d9a), debug.
#   2. #1145 red: the two-hour replay (MemoryLongRunReplay, phone size, release) without the sweep (6ab10a4b).
#   3. #1145 green: the same replay with the sweep (HEAD).
#   4. green focused suites, debug: the sweep's, #1165's, and the residency neighbours.
#   5. the whole InstantSwiftDataCoreTests bundle against Tests/known-failing.txt.
set -u
cd "$(dirname "$0")/.."
# The mini's sessions get 256 open files; the suites open many SQLite stores at once.
ulimit -n 10240 2>/dev/null || ulimit -n 4096
echo "open files: $(ulimit -n)"
GREEN=$(git rev-parse HEAD)
RED1165=117e37eb
RED1145=df4fcb7a
OUT=.runs-1797
git log -1 --oneline
summary() { grep -E '✘|✔|Test run with|recorded an issue|failed after|passed after' "$1" | tail -${2:-40}; }
green_only() { rm -f Sources/InstantSwiftDataCore/InstantResidencySweep.swift Tests/InstantSwiftDataCoreTests/InstantResidencySweepTests.swift; }

echo "== 1. #1165 red: sources and tests at $RED1165"
git checkout "$RED1165" -- Sources Tests; green_only
swift test -j 6 --filter 'InstantNonResidentWriteTests' > $OUT/1165-red.log 2>&1
echo "== 1165 red exit $?"
summary $OUT/1165-red.log

echo "== 2. #1145 red: the two-hour replay at $RED1145 (no sweep)"
git checkout "$RED1145" -- Sources Tests; green_only
scripts/memory-exercises/run-memory-exercises.sh --log $OUT/1145-red-replay.log --suite replay > $OUT/1145-red-replay.out 2>&1
echo "== 1145 red replay exit $?"
grep -hE 'MEMORY-REPLAY-SUMMARY|MEMORY-REPLAY phone minute=(5|60|120) |recorded an issue|Resident facts went|heap grew' $OUT/1145-red-replay.log* | cut -c1-400 | tail -12

echo "== 3. #1145 green: the replay at $GREEN"
git checkout "$GREEN" -- Sources Tests
git status --short -- Sources Tests | head
scripts/memory-exercises/run-memory-exercises.sh --log $OUT/1145-green-replay.log --suite replay > $OUT/1145-green-replay.out 2>&1
echo "== 1145 green replay exit $?"
grep -hE 'MEMORY-REPLAY-SUMMARY|MEMORY-REPLAY phone minute=(5|60|120) |recorded an issue|Resident facts went|heap grew' $OUT/1145-green-replay.log* | cut -c1-400 | tail -12

echo "== 3b. #1512: allocations of 32 KB and more by site (release build of step 3)"
INSTANT_MEMORY_SITES=1 scripts/memory-exercises/run-memory-exercises.sh --log $OUT/1512-sites.log --suite 'MemorySiteExercises/s05LargeAllocationSites' --skip-build > $OUT/1512-sites.out 2>&1
echo "== 1512 sites exit $?"
grep -hE '^MEMORY-SITES|^MEMORY-SITE-BYTES' $OUT/1512-sites.log.*.out | cut -c1-300 | head -40

echo "== 4. green focused suites"
swift test -j 6 --filter 'InstantResidencySweepTests|InstantNonResidentWriteTests|InstantLocalReadTests|InstantStoredResultReloadTests|InstantObserverRegistrationGateTests|InstantPruneOffTheApplierTests|DeferredValueResidencyTests|InstantFastDrainTests' > $OUT/1145-focused.log 2>&1
echo "== focused exit $?"
summary $OUT/1145-focused.log 60

echo "== 5. bundle: InstantSwiftDataCoreTests against Tests/known-failing.txt"
rm -rf $OUT/bundle
scripts/known-failing-tests.sh run $OUT/bundle > $OUT/bundle-run.log 2>&1
echo "== bundle run exit $?"
tail -15 $OUT/bundle-run.log
scripts/known-failing-tests.sh compare $OUT/bundle > $OUT/bundle-compare.log 2>&1
compare=$?
echo "== bundle compare exit $compare"
tail -40 $OUT/bundle-compare.log
exit $compare
