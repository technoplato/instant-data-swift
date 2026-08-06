#!/usr/bin/env bash
# Publish gate: Scribe-shaped memory soak + authenticated idle absolute budget (#150).
#
# 1) LinkedInfiniteScribeShapedMemorySoakTests — production namespaces thrash expand + idle
# 2) ScribeShapedAuthenticatedIdleMemorySoakTests — guest auth + absolute ≤400 MiB idle
#    + real second Instant debugLogs thrash driver
# 3) InstantDiagnosticFeedbackLoopTests — dual-write demotion regression
#
# Gates on **physical footprint** only (never VSZ).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${INSTANT_SWIFT_DATA_SCRIBE_SOAK_RESULTS_DIR:-${ROOT}/validation/results/scribe-soak-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${RESULTS_DIR}"

echo "Scribe-shaped memory soak (#150) → ${RESULTS_DIR}"
echo "repo=$(git -C "${ROOT}" rev-parse HEAD)" | tee "${RESULTS_DIR}/revision.txt"

# Live guest auth: auto-enable when credentials exist unless explicitly disabled.
if [[ -z "${INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK:-}" ]]; then
  if [[ -n "${SCRIBE_MAIN_INSTANT_APP_ID:-}" || -n "${INSTANT_APP_ID:-}" ]]; then
    export INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1
    echo "Live auth soak auto-enabled (SCRIBE_MAIN_INSTANT_APP_ID/INSTANT_APP_ID present)."
  elif [[ -f "${HOME}/.config/instant-tools/scribe-main.env" ]]; then
    # shellcheck disable=SC1091
    set -a
    # Source without printing secrets.
    source "${HOME}/.config/instant-tools/scribe-main.env"
    set +a
    if [[ -n "${SCRIBE_MAIN_INSTANT_APP_ID:-}" || -n "${INSTANT_APP_ID:-}" ]]; then
      export INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1
      echo "Live auth soak auto-enabled from ~/.config/instant-tools/scribe-main.env"
    fi
  fi
fi

# Run suites sequentially. Process-wide InstantProcessMemory samples are
# polluted when LinkedInfinite's large seed and the absolute-idle suite overlap
# (Swift Testing runs suites in parallel by default). Live guest hydrate then
# falsely exceeds the 400 MiB product ceiling.
FILTERS=(
  'InstantDiagnosticFeedbackLoopTests'
  'LinkedInfiniteScribeShapedMemorySoakTests'
  'ScribeShapedAuthenticatedIdleMemorySoakTests'
)

: >"${RESULTS_DIR}/swift-test.log"
STATUS=0
for FILTER in "${FILTERS[@]}"; do
  echo "=== ${FILTER} ===" | tee -a "${RESULTS_DIR}/swift-test.log"
  set +e
  swift test --package-path "${ROOT}" \
    --filter "${FILTER}" \
    >>"${RESULTS_DIR}/swift-test.log" 2>&1
  STEP_STATUS=$?
  set -e
  if [[ "${STEP_STATUS}" -ne 0 ]]; then
    STATUS="${STEP_STATUS}"
    echo "Filter ${FILTER} failed (exit ${STEP_STATUS})." | tee -a "${RESULTS_DIR}/swift-test.log" >&2
    break
  fi
done

if [[ "${STATUS}" -ne 0 ]]; then
  echo "Scribe-shaped memory soak FAILED (exit ${STATUS})." >&2
  tail -n 160 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit "${STATUS}"
fi

# Swift Testing prints display names, e.g. Test "guest-auth …" passed after …
if ! rg -q 'guest-auth Scribe-shaped idle stays under absolute footprint budget".*passed|guestAuthScribeShapedIdleUnderAbsoluteBudget\(\) passed' \
  "${RESULTS_DIR}/swift-test.log"
then
  echo "Authenticated absolute idle soak did not report a passing test." >&2
  tail -n 160 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit 1
fi

if ! rg -q 'forced dual Instant debugLogs thrash stays finite|forcedDualInstantDebugLogsThrashStaysFiniteAndBudgeted\(\) passed|forced info dual-write' \
  "${RESULTS_DIR}/swift-test.log"
then
  echo "Forced dual Instant debugLogs thrash test did not report a pass." >&2
  tail -n 160 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit 1
fi

if ! rg -q 'routine outbox and query diagnostics stay below info.*passed|scribeShapedInfiniteListStayWithinFootprintBudget\(\) passed' \
  "${RESULTS_DIR}/swift-test.log"
then
  echo "Required soak/feedback tests did not all pass." >&2
  tail -n 160 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit 1
fi

# Fail loud if live auth soak was required but skipped/misconfigured.
if [[ "${INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK:-}" == "1" ]]; then
  if rg -q 'Live guest auth failed|requires SCRIBE_MAIN_INSTANT_APP_ID' \
    "${RESULTS_DIR}/swift-test.log"
  then
    echo "Live auth soak was required (INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1) but failed." >&2
    exit 1
  fi
fi

cat >"${RESULTS_DIR}/evidence.json" <<EOF
{
  "case": "validation.scribe-shaped-memory-soak",
  "issue": "https://issues.knophy.com/issues/150",
  "revision": "$(git -C "${ROOT}" rev-parse HEAD)",
  "status": "passed",
  "filters": [
    "InstantDiagnosticFeedbackLoopTests",
    "LinkedInfiniteScribeShapedMemorySoakTests",
    "ScribeShapedAuthenticatedIdleMemorySoakTests"
  ],
  "namespaces": [
    "recordings",
    "transcriptions",
    "transcriptionWords",
    "transcriptionSegments",
    "recordingAttachments",
    "debugLogs"
  ],
  "profiles": [
    "LinkedInfiniteScribeShapedSoakProfile.publishGate",
    "LinkedInfiniteScribeShapedSoakProfile.publishGateAbsoluteIdle"
  ],
  "absoluteIdleCeilingMiB": 400,
  "liveAuthSoak": "${INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK:-0}",
  "notes": "Production Scribe namespaces + real second Instant debugLogs thrash. Physical footprint only (never VSZ). Guest auth always; live guest when credentials present or INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1."
}
EOF

echo "Scribe-shaped memory soak passed. Evidence: ${RESULTS_DIR}/evidence.json"
