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
#                      [--seconds 60] [--out-dir ab-out] [--jobs 8]
# Each commit other than HEAD is exported (git archive) under .build/ab-trees/<sha> and built there once; HEAD builds
# in .build/contention-release. The load is <load> busy shell loops for the length of a run. Output: one file per run,
# <out-dir>/<commit>-<condition>-r<round>.txt, and <out-dir>/summary.txt.
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
while [ $# -gt 0 ]; do
  case "$1" in
    --commits) commits=$2; shift 2 ;;
    --rounds) rounds=$2; shift 2 ;;
    --load) load=$2; shift 2 ;;
    --only) only=$2; shift 2 ;;
    --seconds) seconds=$2; shift 2 ;;
    --out-dir) out_dir=$2; shift 2 ;;
    --jobs) jobs=$2; shift 2 ;;
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

# Export and build every tree first, so no run overlaps a build of this job.
for commit in $commits; do
  tree=$(tree_for "$commit")
  if [ "$commit" != HEAD ] && [ ! -f "$tree/Package.swift" ]; then
    rm -rf "$tree" && mkdir -p "$tree"
    git archive "$commit" | tar -x -C "$tree" || { echo "ab-commits: cannot export $commit" >&2; exit 1; }
  fi
  started=$(date +%s)
  (cd "$tree" && swift build -j "$jobs" -c release -Xswiftc -enable-testing --product InstantSwiftDataCoreTests \
    --scratch-path "$tree/.build/contention-release" 2>&1 | grep -E "error:|Build complete")
  status=${PIPESTATUS[0]}
  echo "ab-commits: build $(name_for "$commit") exit $status in $(( $(date +%s) - started )) s"
done

spin_pids=()
start_load() {
  for _ in $(seq 1 "$1"); do (while :; do :; done) & spin_pids+=($!); done
}
stop_load() {
  for pid in "${spin_pids[@]}"; do kill "$pid" 2>/dev/null; done
  wait "${spin_pids[@]}" 2>/dev/null
  spin_pids=()
}
trap stop_load EXIT

neighbours() {   # the processes using the most CPU now, outside this job's own loops
  ps -Ao pcpu=,comm= -r | grep -v -E "ps$|bash$" | head -6 | awk '{ printf "%s%s:%s", (NR > 1 ? ", " : ""), $2, $1 }'
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
for round in $(seq 1 "$rounds"); do
  for condition in alone load; do
    # Rotate the order each round and condition, so no commit always runs first or last.
    offset=0
    [ "$condition" = load ] && offset=1
    shift_by=$(( (round - 1 + offset) % count ))
    ordered=$(echo $commits | awk -v s="$shift_by" '{ for (i = 0; i < NF; i++) printf "%s ", $(((i + s) % NF) + 1) }')
    for commit in $ordered; do run_one "$commit" "$condition" "$round"; done
  done
done

{
  echo "== summary (recording.steady): commit condition round | transact hold p50 | write.line p50 | read.local p50 | claim hold p50"
  for file in "$out_dir"/*-r*.txt; do
    label=$(basename "$file" .txt)
    pick() { grep -E "^CONTENTION $only\.steady $1" "$file" | head -1 | sed -E 's/.* p50_ms=([0-9.]+).*/\1/'; }
    echo "$label | $(pick 'gate.hold holder=transact') | $(pick 'call caller=write.line') | $(pick 'call caller=read.local') | $(pick 'gate.hold holder="claim')"
  done
} | tee "$out_dir/summary.txt"
