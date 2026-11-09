#!/bin/bash
# #1648's release gate, one job so the mini's queue is waited once:
#   1. every test target at the branch head (the fix and every creation-order test);
#   2. the creation-order suites five more times at the head (they drive a live transport and wait on it);
#   3. red: the head's tests against main's sources (Sources at the red commit 5535f452, main plus the first red tests),
#      creation-order suites only: every one must fail, including the concurrent case added in ba690a53;
#   4. base: every test target with Sources and Tests at 5535f452, so each failure in 1 is named new or already on main.
set -u
ulimit -n 4096
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
BASE=5535f4528d4eb1fd1e5c07d9eb728b0bb9d8cb1f
SUMMARY='^✘ Test .* failed after|^✔ Test run with|^✘ Test run with|Test run with .* (passed|failed)|error:'

echo "== head: every test target at $(git rev-parse --short HEAD)"
swift test --filter Tests > order-1648-head-all.log 2>&1
echo "head swift test exit $?"
grep -E "$SUMMARY" order-1648-head-all.log | tail -80

for round in 1 2 3 4 5; do
  echo "== head: creation-order suites, round $round"
  swift test --filter InstantWriteCreationOrderTests > "order-1648-head-order-$round.log" 2>&1
  echo "round $round exit $?"
  grep -E "$SUMMARY" "order-1648-head-order-$round.log" | tail -20
done

echo "== red: the head's tests with Sources at ${BASE:0:8}, creation-order suites only"
git checkout "$BASE" -- Sources
swift test --filter InstantWriteCreationOrderTests > order-1648-red.log 2>&1
echo "red swift test exit $?"
grep -E "$SUMMARY" order-1648-red.log | tail -40

echo "== base: every test target with Sources and Tests at ${BASE:0:8}"
git checkout "$BASE" -- Sources Tests
swift test --filter Tests > order-1648-base-all.log 2>&1
echo "base swift test exit $?"
git checkout HEAD -- Sources Tests
grep -E "$SUMMARY" order-1648-base-all.log | tail -80
git status --short Sources Tests
