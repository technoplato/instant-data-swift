#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/wire-correctness"
RUNNER="${ROOT}/validation/ts-runner"
PNPM_VERSION="${INSTANT_SWIFT_DATA_PNPM_VERSION:-9.15.0}"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"

export CI=1
export NO_COLOR=1
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"
export INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR="${RESULTS}"
export INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS="${INSTANT_SWIFT_DATA_WIRE_CORRECTNESS_SECONDS:-5}"
export INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT="${INSTANT_SWIFT_DATA_WIRE_CORRECTNESS_WORDS_PER_UPSERT:-4}"
export INSTANT_SWIFT_DATA_BENCH_DRAIN_TIMEOUT_SECONDS="${INSTANT_SWIFT_DATA_WIRE_DRAIN_TIMEOUT_SECONDS:-30}"

corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" install --frozen-lockfile \
  2>&1 | tee "${RESULTS}/typescript-install.log"

bash "${ROOT}/validation/run-scribe-shaped-20s-write-bench.sh" \
  2>&1 | tee "${RESULTS}/home-runner.log"

node --input-type=module - "${RESULTS}/wire-correctness.json" <<'NODE'
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const evidence = JSON.parse(readFileSync(process.argv[2], "utf8"));
assert.equal(evidence.ok, true);
assert.equal(evidence.evidence.length, 2);
for (const lane of evidence.evidence) {
  assert.equal(lane.checks.oppositeSDKReachedFinalSequence, true);
  assert.equal(lane.checks.oppositeSDKReachedFinalWordCount, true);
}
NODE

echo "Bidirectional Swift↔TypeScript correctness passed: ${RESULTS}/wire-correctness.json"
