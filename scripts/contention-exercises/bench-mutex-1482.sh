#!/bin/bash
# M4 (#1482): the cross-SDK runtime benchmark (transact, relaunch, drain; one todo; the same workload ADR 0018 timed),
# release on the mini, 300 iterations, as an A/B for a one-line change shipped uncommitted in the worktree (the job
# commits the worktree's state). Label names the arm. Output at the repo root.
set -u
label=${1:?label}
# The job runs with the repository checkout as its working directory (build.sh copies this script elsewhere).
[ -f Package.swift ] || { echo "not at the repository root: $PWD" >&2; exit 64; }
root=$(pwd)
scratch=".build/contention-release"
swift build -j 8 -c release -Xswiftc -enable-testing --product instant-swift-data-benchmarks --scratch-path "$scratch" 2>&1 | grep -E "error:|Build complete" || true
products=$(swift build -c release -Xswiftc -enable-testing --product instant-swift-data-benchmarks --scratch-path "$scratch" --show-bin-path 2>/dev/null | tail -1)
[ -d "$products" ] || products="$scratch/arm64-apple-macosx/release"
bin="$products/instant-swift-data-benchmarks"
echo "bin=$bin" 
out="$root/m4-$label.json"
echo "M4 $label start $(date '+%Y-%m-%dT%H:%M:%S%z') load=$(sysctl -n vm.loadavg) commit=$(git rev-parse --short HEAD 2>/dev/null)" > "$root/m4-$label.log"
grep -n "SQLITE_OPEN_FULLMUTEX\|SQLITE_OPEN_NOMUTEX" Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift Sources/InstantSwiftDataCore/SQLiteReadConnection.swift >> "$root/m4-$label.log"
for arm in 1 2 3; do
  "$bin" --suite cross-sdk-runtime --iterations 300 --app-id "m4-$label-$arm" > "$root/m4-$label-$arm.json" 2>> "$root/m4-$label.log"
  echo "arm $arm exit $? $(date '+%H:%M:%S')" >> "$root/m4-$label.log"
done
python3 - "$root" "$label" <<'PY' >> "$root/m4-$label.log" 2>&1
import json, sys, statistics, glob
root, label = sys.argv[1], sys.argv[2]
for p in sorted(glob.glob(f"{root}/m4-{label}-*.json")):
    r = json.load(open(p))
    for m in r.get("metrics", []):
        d = sorted(s["durationNanoseconds"] for s in m["samples"])
        p50 = d[len(d)//2] / 1e6; p95 = d[int(len(d)*0.95)-1] / 1e6
        print(f"{p.split('/')[-1]} {m['name']} n={len(d)} p50={p50:.3f}ms p95={p95:.3f}ms")
PY
cat "$root/m4-$label.log"
exit 0
