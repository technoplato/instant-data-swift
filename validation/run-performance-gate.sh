#!/usr/bin/env bash
# Strict publication gate for Instant Swift Data.
#
# Usage:
#   validation/run-performance-gate.sh deterministic   # default; PR/release-safe local evidence
#   validation/run-performance-gate.sh live            # adds Swift↔TypeScript network lanes
#   validation/run-performance-gate.sh all             # deterministic + live + exercise gym
#
# The gate fails closed. A diagnostic explanation never turns a failed metric green.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-${INSTANT_SWIFT_DATA_PERFORMANCE_MODE:-deterministic}}"
RESULTS_DIR="${INSTANT_SWIFT_DATA_PERFORMANCE_RESULTS_DIR:-${ROOT}/validation/results/performance-gate-$(date -u +%Y%m%dT%H%M%SZ)}"
RUNNER="${ROOT}/validation/ts-runner"
GYM="${ROOT}/validation/exercise-gym"
PNPM_VERSION="${INSTANT_SWIFT_DATA_PNPM_VERSION:-9.15.0}"

case "${MODE}" in
  deterministic|live|all) ;;
  *) echo "mode must be deterministic, live, or all" >&2; exit 64 ;;
esac

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Performance gate requires a clean worktree." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

mkdir -p "${RESULTS_DIR}"
export CI=1
export NO_COLOR=1

echo "[gate] mode=${MODE} results=${RESULTS_DIR} pnpm=${PNPM_VERSION}"
git -C "${ROOT}" rev-parse HEAD | tee "${RESULTS_DIR}/swift-revision.txt"

git -C "${ROOT}" submodule sync -- upstream/instant
git -C "${ROOT}" submodule update --init --recursive upstream/instant
EXPECTED_UPSTREAM="$({
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
})"
ACTUAL_UPSTREAM="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
printf '%s\n' "${ACTUAL_UPSTREAM}" | tee "${RESULTS_DIR}/upstream-revision.txt"
if [[ "${ACTUAL_UPSTREAM}" != "${EXPECTED_UPSTREAM}" ]]; then
  echo "Pinned upstream revision mismatch: expected ${EXPECTED_UPSTREAM}, got ${ACTUAL_UPSTREAM}" >&2
  exit 1
fi

corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" install --frozen-lockfile \
  >"${RESULTS_DIR}/typescript-install.log" 2>&1
corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" test \
  >"${RESULTS_DIR}/typescript-contracts.log" 2>&1

swift test --package-path "${ROOT}" -c release \
  >"${RESULTS_DIR}/swift-release-tests.log" 2>&1
INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS="${INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS:-1}" \
  "${ROOT}/validation/run-macro-tests.sh" \
  >"${RESULTS_DIR}/macro-tests.log" 2>&1

INSTANT_SWIFT_DATA_SCRIBE_SOAK_RESULTS_DIR="${RESULTS_DIR}/scribe-memory" \
  "${ROOT}/validation/verify-scribe-shaped-memory-soak.sh" \
  >"${RESULTS_DIR}/scribe-memory.log" 2>&1

INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR="${RESULTS_DIR}/cross-sdk" \
INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-7}" \
INSTANT_SWIFT_DATA_PNPM_VERSION="${PNPM_VERSION}" \
  "${ROOT}/validation/run-cross-sdk-benchmark-comparison.sh" \
  >"${RESULTS_DIR}/cross-sdk.log" 2>&1

LIVE_SUMMARY=""
if [[ "${MODE}" == "live" || "${MODE}" == "all" ]]; then
  : "${INSTANT_CLI_AUTH_TOKEN:?live mode requires INSTANT_CLI_AUTH_TOKEN}"
  INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR="${RESULTS_DIR}/scribe-wire" \
    "${ROOT}/validation/run-scribe-shaped-20s-write-bench.sh" \
    >"${RESULTS_DIR}/scribe-wire.log" 2>&1
  LIVE_SUMMARY="${RESULTS_DIR}/scribe-wire/summary.json"
fi

GYM_REPORT=""
if [[ "${MODE}" == "all" ]]; then
  : "${INSTANT_APP_ID:?all mode requires INSTANT_APP_ID}"
  : "${INSTANT_ADMIN_TOKEN:?all mode requires INSTANT_ADMIN_TOKEN}"
  corepack "pnpm@${PNPM_VERSION}" --dir "${GYM}" install --no-frozen-lockfile \
    >"${RESULTS_DIR}/gym-install.log" 2>&1
  corepack "pnpm@${PNPM_VERSION}" --dir "${GYM}" run typecheck \
    >"${RESULTS_DIR}/gym-typecheck.log" 2>&1
  corepack "pnpm@${PNPM_VERSION}" --dir "${GYM}" exec tsx src/full-compare.ts \
    --simple "${INSTANT_EXERCISE_GYM_SIMPLE_WRITES:-100}" \
    --complex "${INSTANT_EXERCISE_GYM_COMPLEX_WRITES:-20}" \
    --out "${RESULTS_DIR}/exercise-gym" \
    >"${RESULTS_DIR}/exercise-gym.log" 2>&1
  GYM_REPORT="${RESULTS_DIR}/exercise-gym/COMPARISON.json"
fi

ROOT="${ROOT}" RESULTS_DIR="${RESULTS_DIR}" MODE="${MODE}" \
LIVE_SUMMARY="${LIVE_SUMMARY}" GYM_REPORT="${GYM_REPORT}" \
node --input-type=module <<'NODE' | tee "${RESULTS_DIR}/evidence.json"
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const results = process.env.RESULTS_DIR;
const readJSON = (path) => JSON.parse(readFileSync(resolve(path), "utf8"));
const comparison = readJSON(resolve(results, "cross-sdk/comparison.json"));
const memory = readJSON(resolve(results, "scribe-memory/evidence.json"));
assert.equal(comparison.ok, true, "cross-SDK comparison failed");
assert.equal(comparison.details.summary.failureCount, 0, "cross-SDK failures remain");
assert.equal(memory.status, "passed", "Scribe-shaped memory gate failed");

let live = null;
if (process.env.LIVE_SUMMARY) {
  assert.ok(existsSync(process.env.LIVE_SUMMARY), "live summary is missing");
  live = readJSON(process.env.LIVE_SUMMARY);
  assert.equal(live.ok ?? true, true, "bidirectional live synchronization failed");
  for (const lane of [live.netA, live.netB].filter(Boolean)) {
    assert.equal(lane.lost ?? 0, 0, "live lane lost writes");
    assert.equal(lane.duplicates ?? 0, 0, "live lane duplicated writes");
    assert.equal(lane.reordered ?? 0, 0, "live lane reordered writes");
  }
}

let gym = null;
if (process.env.GYM_REPORT) {
  assert.ok(existsSync(process.env.GYM_REPORT), "exercise-gym report is missing");
  gym = readJSON(process.env.GYM_REPORT);
  assert.equal(gym.ok ?? true, true, "exercise gym failed");
}

const evidence = {
  case: "validation.performance-publication-gate",
  contractVersion: 1,
  ok: true,
  mode: process.env.MODE,
  swiftRevision: readFileSync(resolve(results, "swift-revision.txt"), "utf8").trim(),
  upstreamRevision: readFileSync(resolve(results, "upstream-revision.txt"), "utf8").trim(),
  crossSDK: comparison.details.summary,
  memory,
  live,
  exerciseGym: gym,
  policy: {
    failClosed: true,
    defaultP50Ratio: 1,
    defaultP95Ratio: 1,
    noLostDuplicateOrReorderedWireUpdates: true,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

if rg -n '(^|[[:space:]])warning:' \
  "${RESULTS_DIR}/swift-release-tests.log" \
  "${RESULTS_DIR}/macro-tests.log" \
  "${RESULTS_DIR}/typescript-contracts.log" \
  >"${RESULTS_DIR}/warnings.log"
then
  echo "Performance gate found compiler/runtime warnings." >&2
  cat "${RESULTS_DIR}/warnings.log" >&2
  exit 1
fi

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Performance gate changed the worktree." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

echo "Performance publication gate passed: ${RESULTS_DIR}/evidence.json"
