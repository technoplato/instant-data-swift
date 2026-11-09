#!/bin/bash
# #1796 in one build job (the queue waits hours): each red test on its red commit's sources, the two-client test on
# red1's sources (it must fail there), the newest green with the suites beside the changed code (falling back to an
# older green when the newest does not build), then the whole InstantSwiftDataCoreTests bundle on the green that ran,
# against Tests/known-failing.txt. Baseline on main after 1.9.67 (mini, 17:45): 3 off the list (2
# InstantAcknowledgementDigestTests since 1.9.64, InstantLiveFrameDecodeTests' load-sensitive ratio).
# The mini copies this script into its job folder: cd to the worktree's laptop path, which it rewrites to the slot.
set -u
cd /Users/laptop/Sync/worktrees/perf-sync-1796
ulimit -n 10240 2>/dev/null || ulimit -n 4096
echo "open files: $(ulimit -n)"
git log -8 --oneline
commit() { git log --format=%H -1 --grep "^$1" HEAD; }
RED1=$(commit 'red(#1796): a follower applies every buffered refresh')
GREEN1=$(commit 'green(#1796): a waiting refresh loses what a newer one restates')
RED2=$(commit 'red(#1796): a one-shot read sent on a socket that just died')
GREEN2=$(commit 'green(#1796): a one-shot read whose add-query met a dead socket')
RED3=$(commit 'red(#1796): nothing measures how old')
GREEN3=$(commit 'green(#1796): the receive summary measures how old')
TEST4=$(commit "test(#1796): a writer's lines reach a slow follower")
MERGE=$(commit 'merge(#1796): main (v1.9.68)')
MERGE69=$(commit 'merge(#1796): main (v1.9.69)')
RED5=$(commit "red(#1796): an observer's registration holds the gate without naming")
GREEN5=$(commit "green(#1796): an observer's registration names its query")
TWO_CLIENT=Tests/InstantSwiftDataCoreTests/InstantWriterFollowerLatencyTests.swift
HEAD_SHA=$(git rev-parse HEAD)
echo "red1=$RED1 green1=$GREEN1 red2=${RED2:-none} green2=${GREEN2:-none} red3=${RED3:-none} green3=${GREEN3:-none} test4=${TEST4:-none} merge=${MERGE:-none} red5=${RED5:-none} green5=${GREEN5:-none} head=$HEAD_SHA"
NEIGHBOURS='InstantFollowerLatencyTests|InstantWriterFollowerLatencyTests|InstantLiveConnectionSurvivalTests|InstantReactorParityTests|InstantPruneOffTheApplierTests|InstantInfiniteQueryLeadingRowsTests|InstantObserverRegistrationGateTests|InstantConnectionStateTruthTests|InstantQueryCacheAnswerWriteTests|InstantReconnectBackoffParityTests|InstantCancelledSendTests'

# Sources and Tests as `sha` has them: a pathspec checkout leaves the files HEAD added after it, so remove those; `keep`
# comes back as HEAD has it (an earlier step removed it).
tree_at() { # sha [keep]
  git checkout "$1" -- Sources Tests
  comm -13 <(git ls-tree -r --name-only "$1" -- Sources Tests | sort) \
    <(git ls-tree -r --name-only HEAD -- Sources Tests | sort) | while read -r added; do
    rm -f "$added"
  done
  if [ -n "${2:-}" ]; then git checkout HEAD -- "$2"; fi
}
run() { # name sha filter [keep]
  echo "== $1: sources at $2"
  tree_at "$2" "${4:-}"
  swift test -j 6 --filter "$3" > ".runs-1796/$1.log" 2>&1
  local code=$?
  echo "== $1 exit $code"
  grep -E '✘|Test run with|Executed [0-9]+ test|recorded an issue|failed after|error:|lines: median' ".runs-1796/$1.log" | tail -60
  return $code
}
ran() { grep -q -E 'Test run with|Executed [0-9]+ test' ".runs-1796/$1.log"; }

run red1 "$RED1" 'InstantFollowerLatencyTests'
[ -n "$RED2" ] && run red2 "$RED2" 'aOneShotReadSentOnASocketThatJustDied'
[ -n "$RED3" ] && run red3 "$RED3" 'theBufferMeasuresHowOld|theReceiveSummaryReportsHowOld'
# The two-client test on the sources before the fix, the test file from its own commit: it must fail.
[ -n "$TEST4" ] && run red4 "$RED1" 'InstantWriterFollowerLatencyTests' "$TWO_CLIENT"
[ -n "$RED5" ] && run red5 "$RED5" 'aRegistrationsHoldNamesItsQuerysNamespace'

run green "$HEAD_SHA" "$NEIGHBOURS"
green=$?
BUNDLE=$HEAD_SHA
if ! ran green; then
  echo "== the newest green did not build: falling back"
  BUNDLE=
  for fallback in "${MERGE69:-}" "${GREEN5:-}" "${MERGE:-}" "${GREEN3:-}" "$GREEN2" "$GREEN1"; do
    [ -n "$fallback" ] || continue
    run "green-${fallback:0:8}" "$fallback" "$NEIGHBOURS"
    green=$?
    if ran "green-${fallback:0:8}"; then BUNDLE=$fallback; break; fi
  done
fi
echo "== green exit $green at ${BUNDLE:-nothing that builds}"

if [ -n "$BUNDLE" ]; then
  echo "== bundle: InstantSwiftDataCoreTests at $BUNDLE against Tests/known-failing.txt"
  tree_at "$BUNDLE"
  rm -rf .runs-1796/bundle
  scripts/known-failing-tests.sh run .runs-1796/bundle > .runs-1796/bundle-run.log 2>&1
  echo "== bundle run exit $?"
  tail -15 .runs-1796/bundle-run.log
  scripts/known-failing-tests.sh compare .runs-1796/bundle > .runs-1796/bundle-compare.log 2>&1
  echo "== bundle compare exit $?"
  tail -40 .runs-1796/bundle-compare.log
fi
git checkout HEAD -- Sources Tests
[ "$green" = 0 ]
