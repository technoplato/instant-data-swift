#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS_RUNNER="${ROOT}/validation/ts-runner"
RESULTS_DIR="${INSTANT_ACCELERATED_TRANSCRIPTION_RESULTS_DIR:-${ROOT}/validation/results/accelerated-transcription-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${RESULTS_DIR}"

export CI=1
export NO_COLOR=1
export INSTANT_ACCELERATED_TRANSCRIPTION_FULL=1
export INSTANT_ACCELERATED_TRANSCRIPTION_RESULTS_DIR="${RESULTS_DIR}"

{
  echo "revision=$(git -C "${ROOT}" rev-parse HEAD)"
  echo "startedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "machine=$(uname -a)"
  sysctl -n machdep.cpu.brand_string 2>/dev/null | sed 's/^/cpu=/' || true
  sysctl -n hw.memsize 2>/dev/null | sed 's/^/memoryBytes=/' || true
} >"${RESULTS_DIR}/environment.txt"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Accelerated transcription gate requires a clean checkout." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

if [[ -f "${ROOT}/.gitmodules" ]]; then
  git -C "${ROOT}" submodule update --init --recursive
fi

if [[ ! -d "${TS_RUNNER}/node_modules" ]]; then
  corepack enable
  corepack pnpm --dir "${TS_RUNNER}" install --frozen-lockfile
fi

set +e
(
  cd "${TS_RUNNER}"
  corepack pnpm exec node --expose-gc --import tsx \
    src/accelerated-transcription-evolution-bench.ts \
    --out "${RESULTS_DIR}/typescript.json"
) >"${RESULTS_DIR}/typescript.log" 2>&1
TYPESCRIPT_STATUS=$?

INSTANT_ACCELERATED_TRANSCRIPTION_FULL=1 \
INSTANT_ACCELERATED_TRANSCRIPTION_RESULTS_DIR="${RESULTS_DIR}" \
  swift test --package-path "${ROOT}" -c release \
    --filter AcceleratedTranscriptionEvolutionBenchTests \
    >"${RESULTS_DIR}/swift.log" 2>&1
SWIFT_STATUS=$?

ASSESS_STATUS=1
if [[ -f "${RESULTS_DIR}/swift.json" && -f "${RESULTS_DIR}/typescript.json" ]]; then
  node "${ROOT}/validation/assess-accelerated-transcription-evolution.mjs" \
    "${RESULTS_DIR}/swift.json" \
    "${RESULTS_DIR}/typescript.json" \
    "${RESULTS_DIR}/comparison.json" \
    >"${RESULTS_DIR}/assessment.log" 2>&1
  ASSESS_STATUS=$?
else
  {
    echo "Evidence missing."
    echo "swift.json=$([[ -f "${RESULTS_DIR}/swift.json" ]] && echo present || echo missing)"
    echo "typescript.json=$([[ -f "${RESULTS_DIR}/typescript.json" ]] && echo present || echo missing)"
  } >"${RESULTS_DIR}/assessment.log"
fi
set -e

cat >"${RESULTS_DIR}/status.json" <<EOF
{
  "revision": "$(git -C "${ROOT}" rev-parse HEAD)",
  "typescriptExitCode": ${TYPESCRIPT_STATUS},
  "swiftExitCode": ${SWIFT_STATUS},
  "assessmentExitCode": ${ASSESS_STATUS},
  "ok": $([[ "${TYPESCRIPT_STATUS}" -eq 0 && "${SWIFT_STATUS}" -eq 0 && "${ASSESS_STATUS}" -eq 0 ]] && echo true || echo false)
}
EOF

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Accelerated transcription gate changed the checkout." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

if [[ "${TYPESCRIPT_STATUS}" -ne 0 || "${SWIFT_STATUS}" -ne 0 || "${ASSESS_STATUS}" -ne 0 ]]; then
  echo "100× two-hour transcription gate FAILED." >&2
  echo "Results: ${RESULTS_DIR}" >&2
  tail -n 120 "${RESULTS_DIR}/typescript.log" >&2 || true
  tail -n 160 "${RESULTS_DIR}/swift.log" >&2 || true
  cat "${RESULTS_DIR}/assessment.log" >&2 || true
  exit 1
fi

echo "100× two-hour transcription gate passed."
echo "Results: ${RESULTS_DIR}"
