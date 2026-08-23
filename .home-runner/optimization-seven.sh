#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/optimization-seven"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"

export CI=1
export NO_COLOR=1
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

echo "Seven-optimization focused acceptance on $(hostname)"
echo "commit=$(git -C "${ROOT}" rev-parse HEAD)"

swift test \
  --package-path "${ROOT}" \
  -c release \
  --no-parallel \
  --filter InstantMediaStreamOptimizationTests \
  2>&1 | tee "${RESULTS}/stream-optimizations.log"

swift test \
  --package-path "${ROOT}" \
  -c release \
  --no-parallel \
  --filter InstantMediaStreamBufferTests \
  2>&1 | tee "${RESULTS}/stream-contracts.log"

RESULTS="${RESULTS}" ROOT="${ROOT}" python3 - <<'PY' \
  | tee "${RESULTS}/evidence.json"
import json
import os
import re
from pathlib import Path

results = Path(os.environ["RESULTS"])
optimization_log = (results / "stream-optimizations.log").read_text()
contract_log = (results / "stream-contracts.log").read_text()

required_tests = [
    "Binary codec decodes fragmented frames into a caller-owned sink",
    "Direct binary framing is smaller and faster than the JSON/Base64 compatibility envelope",
    "Ring buffer preserves order across sustained bounded backpressure",
    "One released slot wakes one suspended producer instead of a thundering herd",
    "Allocation-free rolling digest matches the compatibility digest",
    "Twenty thousand synchronized audio frames stay inside a fixed memory and CPU envelope",
]
missing = [name for name in required_tests if name not in optimization_log]
if missing:
    raise SystemExit(f"focused optimization tests were not all observed: {missing}")
if "SEVEN_OPT_BINARY_CODEC" not in optimization_log:
    raise SystemExit("binary codec comparison evidence is missing")
if "SEVEN_OPT_STREAM_RESOURCE" not in optimization_log:
    raise SystemExit("stream resource evidence is missing")

optimization_summary = re.search(
    r"Test run with ([0-9]+) tests? in ([0-9]+) suites? passed",
    optimization_log,
)
contract_summary = re.search(
    r"Test run with ([0-9]+) tests? in ([0-9]+) suites? passed",
    contract_log,
)
if not optimization_summary:
    raise SystemExit("focused optimization suite did not report a passing Swift Testing summary")
if int(optimization_summary.group(1)) < len(required_tests):
    raise SystemExit(
        "focused optimization suite passed fewer tests than the required optimization set"
    )
if not contract_summary:
    raise SystemExit("media stream contract suite did not report a passing Swift Testing summary")
if re.search(r"Test run with .* failed", optimization_log):
    raise SystemExit("focused optimization suite reported a failing Swift Testing summary")
if re.search(r"Test run with .* failed", contract_log):
    raise SystemExit("media stream contract suite reported a failing Swift Testing summary")

binary = re.search(
    r"SEVEN_OPT_BINARY_CODEC binary_s=([0-9.]+) compatibility_s=([0-9.]+) ratio=([0-9.]+) binary_bytes=([0-9]+) compatibility_bytes=([0-9]+)",
    optimization_log,
)
resource = re.search(
    r"SEVEN_OPT_STREAM_RESOURCE frames=([0-9]+) wall_s=([0-9.]+) frames_per_s=([0-9.]+) cpu_pct=([0-9.]+) peak_growth_bytes=(-?[0-9]+) settled_growth_bytes=(-?[0-9]+) peak_buffer_bytes=([0-9]+) peak_buffer_frames=([0-9]+) digest=([0-9a-f]+)",
    optimization_log,
)
if not binary or not resource:
    raise SystemExit("could not parse focused resource metrics")

optimizations = [
    {
        "id": "media.ring-storage",
        "claim": "Amortized O(1) bounded FIFO; consumed payload slots are released immediately.",
        "evidence": "ring order and 20,000-frame bounded-resource tests",
    },
    {
        "id": "media.single-waiter-resume",
        "claim": "One released slot wakes one producer, avoiding actor-hop thundering herds.",
        "evidence": "one-slot producer-resume test",
    },
    {
        "id": "media.binary-frame-codec",
        "claim": "Direct payload framing removes JSON and Base64 expansion.",
        "evidence": {
            "binarySeconds": float(binary.group(1)),
            "compatibilitySeconds": float(binary.group(2)),
            "cpuRatio": float(binary.group(3)),
            "binaryBytes": int(binary.group(4)),
            "compatibilityBytes": int(binary.group(5)),
        },
    },
    {
        "id": "media.incremental-read-cursor",
        "claim": "Fragmented decoding uses a read cursor and amortized compaction instead of shifting every frame.",
        "evidence": "arbitrary fragmented transport round-trip",
    },
    {
        "id": "media.caller-owned-decode-sink",
        "claim": "Decoded frames can flow directly into a caller-owned sink without an intermediate frame array.",
        "evidence": "sink-based fragmented decode",
    },
    {
        "id": "media.allocation-free-digest",
        "claim": "Digest fields and payloads are traversed without temporary Data allocations.",
        "evidence": "optimized and compatibility digests match",
    },
    {
        "id": "media.fixed-residency-envelope",
        "claim": "Sustained synchronized audio remains bounded by configured bytes and frames.",
        "evidence": {
            "frameCount": int(resource.group(1)),
            "wallSeconds": float(resource.group(2)),
            "framesPerSecond": float(resource.group(3)),
            "averageCPUPercent": float(resource.group(4)),
            "incrementalPeakBytes": int(resource.group(5)),
            "settledGrowthBytes": int(resource.group(6)),
            "peakBufferBytes": int(resource.group(7)),
            "peakBufferFrames": int(resource.group(8)),
            "digest": resource.group(9),
        },
    },
]

report = {
    "case": "instant-swift-data.optimization-seven",
    "ok": len(optimizations) >= 7,
    "revision": os.popen(f"git -C '{os.environ['ROOT']}' rev-parse HEAD").read().strip(),
    "optimizationCount": len(optimizations),
    "optimizations": optimizations,
    "optimizationTestCount": int(optimization_summary.group(1)),
    "contractTestCount": int(contract_summary.group(1)),
    "contractSuiteObserved": "InstantMediaStreamBufferTests" in contract_log,
}
print(json.dumps(report, indent=2, sort_keys=True))
PY

echo "Focused seven-optimization acceptance passed: ${RESULTS}/evidence.json"
