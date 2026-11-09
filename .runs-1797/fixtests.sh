#!/bin/bash
# perf-mem-1797's landing gate, second run (2026-11-05), Mac mini: the whole InstantSwiftDataCoreTests bundle, debug,
# against Tests/known-failing.txt, at the worktree as build.sh shipped it (agent/claude/perf-mem-1797-fixtests: 518b7418
# plus the 22 tests the first run found still expecting #1500's removed copy, and a bounded batch's unloading).
# Its exit is the compare's: 0 lands the tip.
set -u
cd /Users/laptop/Sync/worktrees/perf-mem-1797
ulimit -n 10240 2>/dev/null || ulimit -n 4096
echo "open files: $(ulimit -n)"
git log -1 --oneline
# Queued before the fixes were done, to hold a place in line (2026-11-05 03:15): it runs only on the tree READY names
# ("<Sources tree> <Tests tree>", written once the fixes are committed), never on a half-edited worktree.
read -r want_sources want_tests < .runs-1797/READY 2>/dev/null || { echo "== not ready: no .runs-1797/READY"; exit 3; }
have_sources=$(git rev-parse HEAD:Sources); have_tests=$(git rev-parse HEAD:Tests)
if [ "$have_sources $have_tests" != "$want_sources $want_tests" ]; then
  echo "== not ready: trees $have_sources $have_tests, READY names $want_sources $want_tests"
  exit 3
fi
echo "== ready: Sources $have_sources Tests $have_tests"
OUT=.runs-1797/bundle-fix
rm -rf "$OUT"
nice -n 10 scripts/known-failing-tests.sh run "$OUT" --jobs 6 > "$OUT-run.log" 2>&1
echo "== fix bundle run exit $?"
tail -5 "$OUT-run.log"
if [ ! -f "$OUT/summary.json" ]; then
  grep -hE 'error:' "$OUT/build.log" 2>/dev/null | sort -u | head -40
  echo "== fix bundle did not build"
  exit 2
fi
scripts/known-failing-tests.sh compare "$OUT" > "$OUT-compare.log" 2>&1
status=$?
echo "== fix bundle compare exit $status"
tail -60 "$OUT-compare.log"
exit $status
