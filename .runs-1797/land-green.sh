#!/bin/bash
# perf-mem-1797's landing branch, green first (the reds ran in 1797-1500-perf-mem-focused, 2026-11-04 20:19):
#   1. #1165, #1145, #541 and #1500 over the 24 suites they touch, debug. Its exit line comes first, so the landing
#      need not wait for the measurement below.
#   2. #1145's criterion, the two-hour replay (MemoryLongRunReplay, release), at HEAD and at #1145's red sources, in
#      this one job (same-job A/B).
set -u
cd /Users/laptop/Sync/worktrees/perf-mem-1797
ulimit -n 10240 2>/dev/null || ulimit -n 4096
echo "open files: $(ulimit -n)"
git log -1 --oneline
HEAD_SHA=$(git rev-parse HEAD)
RED1145=213a7563
OUT=.runs-1797
FOCUSED='InstantSessionMapBoundsTests|InstantNonResidentWriteTests|InstantResidencySweepTests|InstantUnloadInPlaceTests|InstantLocalReadTests|DeferredValueResidencyTests|InstantStoredResultReloadTests|InstantObserverRegistrationGateTests|InstantPruneOffTheApplierTests|InstantPruneCostTests|InstantPruneResidencyCostTests|InstantPruneMaintenanceActivityTests|InstantPruneGateHoldTests|InstantHydrationRecheckHolderTests|InstantInactiveLiveQueryPruneMemoryTests|InstantStoredLiveQueryResultTests|InstantLiveQueryResultWriteTests|InstantLiveQueryCompactOwnershipTests|InstantLiveQueryNestedLimitMemoryTests|InstantOutboxHydrationTests|InstantFastDrainTests|InstantEntityWriteScopeTests|InstantStoreTests|CLITests'
swift test -j 6 --filter "$FOCUSED" > $OUT/land-green.log 2>&1
green=$?
echo "== green exit $green"
grep -E '✘|Test run with|recorded an issue|failed after|error:' $OUT/land-green.log | tail -80

replay_lines() { grep -hE 'MEMORY-REPLAY-SUMMARY|MEMORY-REPLAY phone minute=(5|30|60|90|120) |recorded an issue|Resident facts went|heap grew' "$1"* 2>/dev/null | cut -c1-420 | tail -14; }
echo "== 2a. the two-hour replay at HEAD ($HEAD_SHA): the sweep and unload in place"
scripts/memory-exercises/run-memory-exercises.sh --log $OUT/replay-green.log --suite replay > $OUT/replay-green.out 2>&1
echo "== replay green exit $?"
replay_lines $OUT/replay-green.log

echo "== 2b. the replay at #1145's red sources ($RED1145): no sweep, closed results copied"
git checkout "$RED1145" -- Sources Tests
# Files added after the red commit are not in its tree; remove them so it compiles as it was.
comm -13 <(git ls-tree -r --name-only "$RED1145" -- Sources Tests | sort) <(git ls-tree -r --name-only "$HEAD_SHA" -- Sources Tests | sort) | xargs -I{} rm -f {}
scripts/memory-exercises/run-memory-exercises.sh --log $OUT/replay-red.log --suite replay > $OUT/replay-red.out 2>&1
echo "== replay red exit $?"
replay_lines $OUT/replay-red.log
git checkout "$HEAD_SHA" -- Sources Tests
exit $green
