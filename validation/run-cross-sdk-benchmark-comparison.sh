#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-5}"
RESULTS_DIR="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR:-/tmp/instant-data-swift-benchmark-comparison-$(date -u +%Y%m%dT%H%M%SZ)}"
PNPM_VERSION="${INSTANT_SWIFT_DATA_PNPM_VERSION:-9.15.0}"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Cross-SDK benchmark comparison requires a clean worktree." >&2
  exit 1
fi
if [[ ! "${ITERATIONS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Benchmark iterations must be a positive integer." >&2
  exit 64
fi
if [[ ! -d "${RUNNER}/node_modules/@instantdb/core" ]]; then
  echo "Missing pinned TypeScript dependencies. Run pnpm install in validation/ts-runner." >&2
  exit 1
fi

EXPECTED_UPSTREAM_REVISION="$({
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
})"
UPSTREAM_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
if [[ "${UPSTREAM_REVISION}" != "${EXPECTED_UPSTREAM_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch." >&2
  exit 1
fi

mkdir -p "${RESULTS_DIR}"
swift run --package-path "${ROOT}" -c release instant-swift-data-benchmarks \
  --suite cross-sdk-core \
  --iterations "${ITERATIONS}" \
  --app-id cross-sdk-core-benchmark \
  --json >"${RESULTS_DIR}/swift-core.json"

corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" exec tsx src/cross-sdk-core-benchmark.ts \
  --iterations "${ITERATIONS}" >"${RESULTS_DIR}/typescript-core.json"

(
  cd "${ROOT}"
  node validation/compare-cross-sdk-benchmarks.mjs \
    "${RESULTS_DIR}/swift-core.json" \
    "${RESULTS_DIR}/typescript-core.json"
) >"${RESULTS_DIR}/core-comparison.json"

swift run --package-path "${ROOT}" -c release instant-swift-data-benchmarks \
  --suite cross-sdk-runtime \
  --iterations "${ITERATIONS}" \
  --app-id cross-sdk-runtime-benchmark \
  --json >"${RESULTS_DIR}/swift-runtime.json"

corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" exec tsx src/cross-sdk-runtime-benchmark.ts \
  --iterations "${ITERATIONS}" >"${RESULTS_DIR}/typescript-runtime.json"

(
  cd "${ROOT}"
  node validation/compare-cross-sdk-runtime-benchmarks.mjs \
    "${RESULTS_DIR}/swift-runtime.json" \
    "${RESULTS_DIR}/typescript-runtime.json"
) >"${RESULTS_DIR}/runtime-comparison.json"

(
  cd "${ROOT}"
  node validation/combine-cross-sdk-benchmark-comparisons.mjs \
    "${RESULTS_DIR}/core-comparison.json" \
    "${RESULTS_DIR}/runtime-comparison.json"
) | tee "${RESULTS_DIR}/comparison.json"

echo "Cross-SDK benchmark evidence: ${RESULTS_DIR}/comparison.json"
