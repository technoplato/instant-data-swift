#!/bin/bash
# perf-mem-1797 (2026-11-05): the 13 suites the fix commits changed, debug, on the laptop with Xcode beta, to catch type
# errors and read the compact ownership digest's new value before the mini's whole-bundle run. Full log kept.
set -u
cd /Users/laptop/Sync/worktrees/perf-mem-1797
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
git log -1 --oneline
F='InstantPruneGateHoldTests|InstantPruneOffTheApplierTests|InstantPruneMaintenanceActivityTests|InstantPruneResidencyCostTests|InstantPruneCostTests|InstantObserverRegistrationGateTests|InstantStoredResultReloadTests|InstantInactiveLiveQueryPruneMemoryTests|StorageIOExercises|InstantStoredFileLookupTests|InstantBoundedServerApplyRebaseTests|InstantLiveQueryCompactOwnershipTests|InstantLaunchResidencyTests'
nice -n 10 swift test --scratch-path .build-beta -j 4 --filter "$F" > .runs-1797/laptop-check.log 2>&1
echo "== laptop check exit $?"
grep -E "error:|recorded an issue|failed after|Test run with|over [0-9]+ answers" .runs-1797/laptop-check.log | cut -c1-300 | head -80
