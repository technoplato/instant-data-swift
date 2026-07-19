#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
RESULTS_DIR="${INSTANT_SWIFT_DATA_V1_RESULTS_DIR:-/tmp/instant-data-swift-v1-release-$(date -u +%Y%m%dT%H%M%SZ)}"
BENCHMARK_RESULTS="${RESULTS_DIR}/benchmark"
CLOUDKIT_RESULTS="${RESULTS_DIR}/cloudkit-demo"
TODOS_RESULTS="${RESULTS_DIR}/todos"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "V1 release verification requires a clean worktree." >&2
  exit 1
fi
if [[ ! -d "${RUNNER}/node_modules/@instantdb/core" ]]; then
  echo "Missing pinned TypeScript dependencies. Run pnpm install in validation/ts-runner." >&2
  exit 1
fi

export CI=1
export NO_COLOR=1
mkdir -p "${RESULTS_DIR}"

git -C "${ROOT}" rev-parse HEAD >"${RESULTS_DIR}/swift-revision.txt"
git -C "${ROOT}/upstream/instant" rev-parse HEAD >"${RESULTS_DIR}/upstream-revision.txt"

swift test --package-path "${ROOT}" >"${RESULTS_DIR}/swift-test.log" 2>&1
INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS="${INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS:-1}" \
  "${ROOT}/validation/run-macro-tests.sh" >"${RESULTS_DIR}/macro-tests.log" 2>&1

products=(
  instant-swift-data
  instant-swift-data-validation-runner
  instant-swift-data-benchmarks
  app-builder-v3
  auth-v3
  cloudkit-demo-v3
  mobile-chat-v3
  presence-recipes-v3
  reminders-v3
  stroopwafel-v3
  streams-v3
  syncups-v3
  todos-v3
  voicetrail-v3
)
: >"${RESULTS_DIR}/product-builds.log"
for product in "${products[@]}"; do
  swift build --package-path "${ROOT}" --product "${product}" \
    >>"${RESULTS_DIR}/product-builds.log" 2>&1
done
printf '%s\n' "${products[@]}" >"${RESULTS_DIR}/products.txt"

corepack pnpm --dir "${RUNNER}" test >"${RESULTS_DIR}/typescript-matrix.log" 2>&1

INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR="${BENCHMARK_RESULTS}" \
  "${ROOT}/validation/run-cross-sdk-benchmark-comparison.sh" \
  >"${RESULTS_DIR}/benchmark.log" 2>&1

INSTANT_SWIFT_DATA_CLOUDKIT_DEMO_V3_RESULTS_DIR="${CLOUDKIT_RESULTS}" \
  "${ROOT}/validation/verify-cloudkit-demo-v3-app-live.sh" \
  >"${RESULTS_DIR}/cloudkit-demo.log" 2>&1

INSTANT_SWIFT_DATA_TODOS_V3_RESULTS_DIR="${TODOS_RESULTS}" \
  "${ROOT}/validation/verify-todos-v3-app-live.sh" \
  >"${RESULTS_DIR}/todos.log" 2>&1

if rg -n '(^|[[:space:]])warning:' \
  "${RESULTS_DIR}/swift-test.log" \
  "${RESULTS_DIR}/macro-tests.log" \
  "${RESULTS_DIR}/product-builds.log" \
  "${RESULTS_DIR}/typescript-matrix.log" \
  >"${RESULTS_DIR}/warnings.log"
then
  echo "V1 release verification found compiler/runtime warnings." >&2
  cat "${RESULTS_DIR}/warnings.log" >&2
  exit 1
fi

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "V1 release verification changed the worktree." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

ROOT="${ROOT}" RESULTS_DIR="${RESULTS_DIR}" PRODUCTS="${products[*]}" \
node --input-type=module <<'NODE' | tee "${RESULTS_DIR}/evidence.json"
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = process.env.ROOT;
const results = process.env.RESULTS_DIR;
const read = (path) => readFileSync(resolve(results, path), "utf8");
const json = (path) => JSON.parse(read(path));
const revision = read("swift-revision.txt").trim();
const upstreamRevision = read("upstream-revision.txt").trim();
const swiftLog = read("swift-test.log");
const macroLog = read("macro-tests.log");
const benchmark = json("benchmark/comparison.json");
const cloudKit = json("cloudkit-demo/evidence.json");
const todos = json("todos/evidence.json");
const checkedBaseline = JSON.parse(
  readFileSync(
    resolve(root, "validation/benchmarks/v1-cross-sdk-performance-2026-07-19.json"),
    "utf8",
  ),
);

const swiftMatch = swiftLog.match(/Test run with (\d+) tests in (\d+) suites passed/);
assert.ok(swiftMatch, "Full Swift test log did not contain a passing Swift Testing summary.");
const macroMatches = [...macroLog.matchAll(/Executed (\d+) tests, with 0 failures/g)];
assert.ok(macroMatches.length > 0, "Macro log did not contain a passing XCTest summary.");
const macroCount = Number(macroMatches.at(-1)[1]);
assert.equal(macroCount, 28);
assert.equal(benchmark.ok, true);
assert.equal(benchmark.details.swiftRevision, revision);
assert.equal(benchmark.details.upstreamRevision, upstreamRevision);
assert.equal(benchmark.details.summary.workloadCount, 15);
assert.equal(benchmark.details.summary.actorHopInstrumentedWorkloadCount, 3);
assert.equal(cloudKit.ok, true);
assert.equal(cloudKit.details.swiftRevision, revision);
assert.equal(cloudKit.details.coverage.coverageComplete, true);
assert.equal(cloudKit.details.coverage.blockedCount, 0);
assert.deepStrictEqual(cloudKit.details.coverage.blockedIDs, []);
assert.equal(todos.ok, true);
assert.equal(todos.details.swiftRevision, revision);
assert.equal(todos.details.compilerWarningCount, 0);
assert.equal(todos.details.todos.compilerWarningCount, 0);
assert.deepStrictEqual(todos.details.todos.warnings, []);
assert.equal(checkedBaseline.ok, true);
assert.equal(checkedBaseline.details.benchmarkEvidence.summary.workloadCount, 15);
for (const measurement of Object.values(todos.details.todos.performance)) {
  assert.ok(measurement.durationNanoseconds > 0);
  assert.ok(measurement.actorHopCount > 0);
}

const evidence = {
  case: "validation.v1.release",
  event: "clean-checkout-summary",
  ok: true,
  details: {
    swiftRevision: revision,
    upstreamRevision,
    worktreeDirty: false,
    compilerWarningCount: 0,
    swift: {
      testCount: Number(swiftMatch[1]),
      suiteCount: Number(swiftMatch[2]),
      macroTestCount: macroCount,
      products: process.env.PRODUCTS.split(" "),
    },
    typeScript: {
      completeMatrix: true,
    },
    parity: cloudKit.details.coverage,
    benchmark: benchmark.details.summary,
    liveActorHops: todos.details.todos.performance,
    appBoundaries: {
      cloudKitDemo: cloudKit.case,
      todos: todos.case,
    },
    checkedPerformanceBaseline:
      "validation/benchmarks/v1-cross-sdk-performance-2026-07-19.json",
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "V1 release evidence: ${RESULTS_DIR}/evidence.json"
