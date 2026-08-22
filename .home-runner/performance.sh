#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/performance"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"

export INSTANT_SWIFT_DATA_PERFORMANCE_RESULTS_DIR="${RESULTS}"
export INSTANT_SWIFT_DATA_MAX_P50_RATIO="${INSTANT_SWIFT_DATA_MAX_P50_RATIO:-1}"
export INSTANT_SWIFT_DATA_MAX_P95_RATIO="${INSTANT_SWIFT_DATA_MAX_P95_RATIO:-1}"
export INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-7}"

echo "Instant Swift Data strict deterministic performance gate on $(hostname)"
"${ROOT}/validation/run-performance-gate.sh" deterministic \
  2>&1 | tee "${RESULTS}/home-runner.log"
