#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/performance-live"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"

# Only a test-suite-specific environment file may override ephemeral getadb
# provisioning. Never inherit Scribe or general-purpose production app secrets.
TEST_ENV_FILE="${INSTANT_SWIFT_DATA_TEST_ENV_FILE:-${HOME}/.config/instant-tools/instant-data-swift-test.env}"
if [[ -f "${TEST_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${TEST_ENV_FILE}"
  set +a
fi

export INSTANT_SWIFT_DATA_PERFORMANCE_RESULTS_DIR="${RESULTS}"
export INSTANT_SWIFT_DATA_MAX_P50_RATIO="${INSTANT_SWIFT_DATA_MAX_P50_RATIO:-1}"
export INSTANT_SWIFT_DATA_MAX_P95_RATIO="${INSTANT_SWIFT_DATA_MAX_P95_RATIO:-1}"
export INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-7}"

echo "Instant Swift Data strict live synchronization gate on $(hostname)"
bash "${ROOT}/validation/run-performance-gate.sh" live \
  2>&1 | tee "${RESULTS}/home-runner.log"
