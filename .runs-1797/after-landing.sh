#!/bin/bash
# perf-mem-1797's post-landing check (2026-11-05), Mac mini, debug:
#   1. InstantLiveFrameDecodeTests alone, 5 times, at the landed tree (d7dcf707) and at M2 (f504ed51): the gate read its
#      timing ratio 0.366-0.374 on the launch trees against 0.323-0.325 elsewhere, inside the parallel bundle.
#   2. Main's new suites from v1.9.71 (#1796) and the registration gate suite on the landed tree, which no whole bundle
#      ran: InstantFollowerLatencyTests, InstantWriterFollowerLatencyTests, InstantObserverRegistrationGateTests.
set -u
cd /Users/laptop/Sync/worktrees/perf-mem-1797
ulimit -n 10240 2>/dev/null || ulimit -n 4096
SNAP=$(git rev-parse HEAD)
OUT=.runs-1797
at() { git restore --source="$1" --staged --worktree -- Sources Tests && echo "-- at $(git rev-parse --short "$1")"; }
ratios() { grep -h "decoded at .* times JSONDecoder" "$1" | sed 's/.*decoded at \([0-9.]*\).*/\1/' | tr '\n' ' '; }
for tree in d7dcf707 f504ed51; do
  at "$tree"
  : > "$OUT/decode-$tree.log"
  for i in 1 2 3 4 5; do
    swift test -j 6 --filter 'InstantLiveFrameDecodeTests/aServerResultDecodesAtAFractionOfJSONDecodersCost' >> "$OUT/decode-$tree.log" 2>&1
  done
  echo "== decode alone at $tree: ratios $(ratios "$OUT/decode-$tree.log")"
done
at d7dcf707
swift test -j 6 --filter 'InstantFollowerLatencyTests|InstantWriterFollowerLatencyTests|InstantObserverRegistrationGateTests' > "$OUT/after-suites.log" 2>&1
echo "== main's new suites exit $?"
grep -E "recorded an issue|failed after|Test run with" "$OUT/after-suites.log" | cut -c1-300 | tail -30
git restore --source="$SNAP" --staged --worktree -- Sources Tests
