#!/usr/bin/env bash
# Strict publication gate for Instant Swift Data.
#
# Usage:
#   validation/run-performance-gate.sh deterministic   # local evidence
#   validation/run-performance-gate.sh live            # adds Swift↔TypeScript wire lanes
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

# NOTE: DomainAEV 0.069 ms is the TypeScript InstaQL floor. Keep the bar.
# `--filter` still compiles every package test target, including gym apps.
# Score DomainAEV in InstantSwiftDataDomainAEVTests first, before gym
# products compile. If it fails, still run the remaining suite, then fail
# closed.
domain_aev_status=0
swift test --package-path "${ROOT}" -c release --no-parallel \
  --target InstantSwiftDataDomainAEVTests \
  >"${RESULTS_DIR}/swift-release-domain-aev.log" 2>&1 \
  || domain_aev_status=$?
printf '%s\n' "${domain_aev_status}" > "${RESULTS_DIR}/domain-aev-exit.txt"

# Nested `swift run` waits forever on the package `.build.lock` held by
# `swift test`. Build the CLI products before the remaining suite.
swift build --package-path "${ROOT}" -c release --product instant-swift-data \
  >"${RESULTS_DIR}/swift-release-cli-products.log" 2>&1
swift build --package-path "${ROOT}" -c release \
  --product instant-swift-data-validation-runner \
  >>"${RESULTS_DIR}/swift-release-cli-products.log" 2>&1

remaining_status=0
swift test --package-path "${ROOT}" -c release --no-parallel \
  --skip DomainAEVLookupBenchTests \
  >"${RESULTS_DIR}/swift-release-tests.log" 2>&1 \
  || remaining_status=$?
printf '%s\n' "${remaining_status}" > "${RESULTS_DIR}/swift-release-tests-exit.txt"

macro_status=0
INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS="${INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS:-1}" \
  bash "${ROOT}/validation/run-macro-tests.sh" \
  >"${RESULTS_DIR}/macro-tests.log" 2>&1 \
  || macro_status=$?
printf '%s\n' "${macro_status}" > "${RESULTS_DIR}/macro-tests-exit.txt"

INSTANT_SWIFT_DATA_SCRIBE_SOAK_RESULTS_DIR="${RESULTS_DIR}/scribe-memory" \
  bash "${ROOT}/validation/verify-scribe-shaped-memory-soak.sh" \
  >"${RESULTS_DIR}/scribe-memory.log" 2>&1

INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR="${RESULTS_DIR}/cross-sdk" \
INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-7}" \
INSTANT_SWIFT_DATA_PNPM_VERSION="${PNPM_VERSION}" \
  bash "${ROOT}/validation/run-cross-sdk-benchmark-comparison.sh" \
  >"${RESULTS_DIR}/cross-sdk.log" 2>&1

LIVE_SUMMARY=""
WIRE_CORRECTNESS=""
if [[ "${MODE}" == "live" || "${MODE}" == "all" ]]; then
  # Suite-provided credentials win. Otherwise the wire harness provisions an
  # isolated temporary app through getadb.com and removes local secret material.
  INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR="${RESULTS_DIR}/scribe-wire" \
    bash "${ROOT}/validation/run-scribe-shaped-20s-write-bench.sh" \
    >"${RESULTS_DIR}/scribe-wire.log" 2>&1
  LIVE_SUMMARY="${RESULTS_DIR}/scribe-wire/summary.json"
  WIRE_CORRECTNESS="${RESULTS_DIR}/scribe-wire/wire-correctness.json"
fi

GYM_REPORT=""
if [[ "${MODE}" == "all" ]]; then
  : "${INSTANT_APP_ID:?all mode exercise-gym requires an explicit isolated app ID}"
  : "${INSTANT_ADMIN_TOKEN:?all mode exercise-gym requires its admin token}"
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
LIVE_SUMMARY="${LIVE_SUMMARY}" WIRE_CORRECTNESS="${WIRE_CORRECTNESS}" \
GYM_REPORT="${GYM_REPORT}" \
node --input-type=module <<'NODE' | tee "${RESULTS_DIR}/evidence.json"
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const results = process.env.RESULTS_DIR;
const readJSON = (path) => JSON.parse(readFileSync(resolve(path), "utf8"));
const readExit = (name) =>
  readFileSync(resolve(results, name), "utf8").trim();
assert.equal(readExit("domain-aev-exit.txt"), "0", "DomainAEV dedicated target failed");
assert.equal(
  readExit("swift-release-tests-exit.txt"),
  "0",
  "remaining Swift release tests failed",
);
assert.equal(readExit("macro-tests-exit.txt"), "0", "macro tests failed");
const domainAev = readFileSync(
  resolve(results, "swift-release-domain-aev.log"),
  "utf8",
);
const remaining = readFileSync(
  resolve(results, "swift-release-tests.log"),
  "utf8",
);
assert.match(domainAev, /STORE_ONLY_BENCH/);
assert.match(domainAev, /Test run with .* passed/);
assert.match(remaining, /Test run with .* passed/);
const comparison = readJSON(resolve(results, "cross-sdk/comparison.json"));
const memory = readJSON(resolve(results, "scribe-memory/evidence.json"));
assert.equal(comparison.ok, true, "cross-SDK comparison failed");
assert.equal(comparison.details.summary.failureCount, 0, "cross-SDK failures remain");
assert.equal(memory.status, "passed", "Scribe-shaped memory gate failed");

let live = null;
let wireCorrectness = null;
if (process.env.LIVE_SUMMARY) {
  assert.ok(existsSync(process.env.LIVE_SUMMARY), "live summary is missing");
  assert.ok(existsSync(process.env.WIRE_CORRECTNESS), "wire correctness is missing");
  live = readJSON(process.env.LIVE_SUMMARY);
  wireCorrectness = readJSON(process.env.WIRE_CORRECTNESS);
  assert.equal(wireCorrectness.ok, true, "bidirectional wire correctness failed");
  assert.equal(wireCorrectness.evidence.length, 2, "both wire directions are required");
}

let gym = null;
if (process.env.GYM_REPORT) {
  assert.ok(existsSync(process.env.GYM_REPORT), "exercise-gym report is missing");
  gym = readJSON(process.env.GYM_REPORT);
  assert.equal(gym.ok ?? true, true, "exercise gym failed");
}

const evidence = {
  case: "validation.performance-publication-gate",
  contractVersion: 2,
  ok: true,
  mode: process.env.MODE,
  swiftRevision: readFileSync(resolve(results, "swift-revision.txt"), "utf8").trim(),
  upstreamRevision: readFileSync(resolve(results, "upstream-revision.txt"), "utf8").trim(),
  crossSDK: comparison.details.summary,
  memory,
  live,
  wireCorrectness,
  exerciseGym: gym,
  policy: {
    failClosed: true,
    domainAevIsolated: true,
    domainAevDedicatedTarget: true,
    defaultP50Ratio: 1,
    defaultP95Ratio: 1,
    typeScriptWriterObservedBySwift: true,
    swiftWriterObservedByTypeScript: true,
    exactFinalSequenceAndWordCountConvergence: true,
    ephemeralAppWhenSuiteCredentialsAreAbsent: true,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

# Fail closed on Instant library compiler warnings. Gym source-compat
# deprecation tests, unused test locals, and third-party linker notes are
# not Instant product warnings.
python3 - "${RESULTS_DIR}" <<'PY'
from pathlib import Path
import re
import sys

results = Path(sys.argv[1])
logs = [
    results / "swift-release-cli-products.log",
    results / "swift-release-domain-aev.log",
    results / "swift-release-tests.log",
    results / "macro-tests.log",
]
pattern = re.compile(
    r"/Sources/(InstantSwiftData[^/]*|instant-swift-data)/[^:]+\.swift:\d+:\d+: warning:"
)
hits = []
for log in logs:
    if not log.exists():
        continue
    text = log.read_text()
    for line in text.splitlines():
        if pattern.search(line):
            hits.append(f"{log.name}: {line}")
out = results / "warnings.log"
out.write_text("\n".join(hits) + ("\n" if hits else ""))
if hits:
    print("Performance gate found Instant library compiler warnings.", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    raise SystemExit(1)
PY

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Performance gate changed the worktree." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

echo "Performance publication gate passed: ${RESULTS_DIR}/evidence.json"
