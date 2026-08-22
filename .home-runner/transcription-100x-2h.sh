#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
RESULTS="${ROOT}/.home-runner-results/transcription-100x-2h"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"

export INSTANT_ACCELERATED_TRANSCRIPTION_RESULTS_DIR="${RESULTS}"

bash "${ROOT}/validation/run-accelerated-transcription-evolution-bench.sh"

printf '\n=== 100x two-hour transcription summary ===\n'
cat "${RESULTS}/comparison.md"
printf '\n=== machine-readable status ===\n'
cat "${RESULTS}/status.json"
