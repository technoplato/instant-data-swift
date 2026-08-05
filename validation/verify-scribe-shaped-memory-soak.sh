#!/usr/bin/env bash
# Publish gate: Scribe-shaped memory soak + authenticated idle absolute budget (#150).
#
# 1) LinkedInfiniteScribeShapedMemorySoakTests — thrash expand + idle settle growth
# 2) ScribeShapedAuthenticatedIdleMemorySoakTests — guest auth + absolute ≤400 MiB idle
# 3) InstantDiagnosticFeedbackLoopTests — dual-write demotion regression
#
# Gates on **physical footprint** only (never VSZ).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${INSTANT_SWIFT_DATA_SCRIBE_SOAK_RESULTS_DIR:-${ROOT}/validation/results/scribe-soak-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${RESULTS_DIR}"

echo "Scribe-shaped memory soak (#150) → ${RESULTS_DIR}"
echo "repo=$(git -C "${ROOT}" rev-parse HEAD)" | tee "${RESULTS_DIR}/revision.txt"

FILTER='LinkedInfiniteScribeShapedMemorySoakTests|ScribeShapedAuthenticatedIdleMemorySoakTests|InstantDiagnosticFeedbackLoopTests'

set +e
swift test --package-path "${ROOT}" \
  --filter "${FILTER}" \
  >"${RESULTS_DIR}/swift-test.log" 2>&1
STATUS=$?
set -e

if [[ "${STATUS}" -ne 0 ]]; then
  echo "Scribe-shaped memory soak FAILED (exit ${STATUS})." >&2
  tail -n 120 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit "${STATUS}"
fi

# Swift Testing prints display names, e.g. Test "guest-auth …" passed after …
if ! rg -q 'guest-auth Scribe-shaped idle stays under absolute footprint budget".*passed|guestAuthScribeShapedIdleUnderAbsoluteBudget\(\) passed' \
  "${RESULTS_DIR}/swift-test.log"
then
  echo "Authenticated absolute idle soak did not report a passing test." >&2
  tail -n 120 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit 1
fi

if ! rg -q 'routine outbox and query diagnostics stay below info.*passed|scribeShapedInfiniteListStayWithinFootprintBudget\(\) passed' \
  "${RESULTS_DIR}/swift-test.log"
then
  echo "Required soak/feedback tests did not all pass." >&2
  tail -n 120 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit 1
fi

# Fail loud if live auth soak was requested but skipped/misconfigured.
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
  "filter": "${FILTER}",
  "profiles": [
    "LinkedInfiniteScribeShapedSoakProfile.publishGate",
    "LinkedInfiniteScribeShapedSoakProfile.publishGateAbsoluteIdle"
  ],
  "absoluteIdleCeilingMiB": 400,
  "notes": "Gates physical footprint (never VSZ). Guest auth always; live guest when INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1."
}
EOF

echo "Scribe-shaped memory soak passed. Evidence: ${RESULTS_DIR}/evidence.json"
