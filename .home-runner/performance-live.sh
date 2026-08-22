#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/performance-live"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"

for env_file in \
  "${HOME}/.config/instant-tools/instant.env" \
  "${HOME}/.config/instant-tools/scribe-main.env"
do
  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi
done

export INSTANT_CLI_AUTH_TOKEN="${INSTANT_CLI_AUTH_TOKEN:-${INSTANT_AUTH_TOKEN:-}}"
: "${INSTANT_CLI_AUTH_TOKEN:?Missing Instant CLI auth token in the runner environment/config}"
export INSTANT_SWIFT_DATA_PERFORMANCE_RESULTS_DIR="${RESULTS}"
export INSTANT_SWIFT_DATA_MAX_P50_RATIO="${INSTANT_SWIFT_DATA_MAX_P50_RATIO:-1}"
export INSTANT_SWIFT_DATA_MAX_P95_RATIO="${INSTANT_SWIFT_DATA_MAX_P95_RATIO:-1}"
export INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-7}"

echo "Instant Swift Data strict live synchronization gate on $(hostname)"
"${ROOT}/validation/run-performance-gate.sh" live \
  2>&1 | tee "${RESULTS}/home-runner.log"
