#!/usr/bin/env bash
# Publish gate: Scribe-shaped linked-infinite memory soak (#150).
#
# Fails if the library cannot seed a production-shaped
# recordings → transcriptions → words graph, page an infinite list+include,
# and stay within the documented physical-footprint budget.
#
# Do not interpret macOS VSZ (~hundreds of GB) as RAM — the soak gates on
# physical footprint / resident size only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${INSTANT_SWIFT_DATA_SCRIBE_SOAK_RESULTS_DIR:-/tmp/instant-data-swift-scribe-soak-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${RESULTS_DIR}"

echo "Scribe-shaped memory soak (#150) → ${RESULTS_DIR}"
echo "repo=$(git -C "${ROOT}" rev-parse HEAD)" | tee "${RESULTS_DIR}/revision.txt"

set +e
swift test --package-path "${ROOT}" \
  --filter LinkedInfiniteScribeShapedMemorySoakTests \
  >"${RESULTS_DIR}/swift-test.log" 2>&1
STATUS=$?
set -e

if [[ "${STATUS}" -ne 0 ]]; then
  echo "Scribe-shaped memory soak FAILED (exit ${STATUS})." >&2
  tail -n 80 "${RESULTS_DIR}/swift-test.log" >&2 || true
  exit "${STATUS}"
fi

if ! rg -q 'Test run with .* passed' "${RESULTS_DIR}/swift-test.log"; then
  # Swift Testing may print "passed after" per test without the suite summary on some versions.
  if ! rg -q 'scribeShapedInfiniteListStayWithinFootprintBudget\\(\\) passed' \
    "${RESULTS_DIR}/swift-test.log"
  then
    echo "Scribe-shaped memory soak did not report a passing test." >&2
    tail -n 80 "${RESULTS_DIR}/swift-test.log" >&2 || true
    exit 1
  fi
fi

cat >"${RESULTS_DIR}/evidence.json" <<EOF
{
  "case": "validation.scribe-shaped-memory-soak",
  "issue": "https://issues.knophy.com/issues/150",
  "revision": "$(git -C "${ROOT}" rev-parse HEAD)",
  "status": "passed",
  "filter": "LinkedInfiniteScribeShapedMemorySoakTests",
  "profile": "LinkedInfiniteScribeShapedSoakProfile.publishGate",
  "notes": "Gates physical footprint growth, not virtual address size (VSZ)."
}
EOF

echo "Scribe-shaped memory soak passed. Evidence: ${RESULTS_DIR}/evidence.json"
