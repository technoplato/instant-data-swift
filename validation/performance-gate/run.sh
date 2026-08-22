#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="smoke"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:?missing --mode value}"; shift 2 ;;
    -h|--help)
      echo 'Usage: validation/run-performance-gate.sh --mode smoke|full|release'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done
[[ "${MODE}" =~ ^(smoke|full|release)$ ]] || { echo "Invalid mode: ${MODE}" >&2; exit 64; }

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RESULTS="${INSTANT_PERFORMANCE_RESULTS_DIR:-${ROOT}/validation/results/performance-gate/${STAMP}}"
LOCAL="${RESULTS}/local"
CROSS="${RESULTS}/cross-sdk"
SCRIBE="${RESULTS}/scribe-live"
EXERCISE="${RESULTS}/exercise-gym"
mkdir -p "${LOCAL}" "${CROSS}" "${SCRIBE}" "${EXERCISE}"
exec > >(tee "${RESULTS}/stdout.log") 2> >(tee "${RESULTS}/stderr.log" >&2)
STARTED="$(date +%s)"

echo "[gate] mode=${MODE} revision=$(git -C "${ROOT}" rev-parse HEAD)"
echo "[gate] swift=$(swift --version | head -1) node=$(node --version)"

for command in git node swift corepack; do
  command -v "${command}" >/dev/null || { echo "Missing ${command}" >&2; exit 1; }
done

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Performance evidence requires a clean checkout." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

RUNNER="${ROOT}/validation/ts-runner"
EXPECTED_UPSTREAM="$({ cd "${RUNNER}"; node -p "require('./package.json').instantContract.upstreamRevision"; })"
if [[ ! -d "${ROOT}/upstream/instant/.git" ]]; then
  rm -rf "${ROOT}/upstream/instant"
  git clone --filter=blob:none --no-checkout https://github.com/instantdb/instant.git "${ROOT}/upstream/instant"
fi
git -C "${ROOT}/upstream/instant" fetch --depth 1 origin "${EXPECTED_UPSTREAM}"
git -C "${ROOT}/upstream/instant" checkout --detach "${EXPECTED_UPSTREAM}"
test "$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)" = "${EXPECTED_UPSTREAM}"
printf '%s\n' "${EXPECTED_UPSTREAM}" >"${LOCAL}/upstream-revision.txt"

corepack pnpm --dir "${RUNNER}" install --frozen-lockfile \
  | tee "${LOCAL}/pnpm-install.log"

swift test --package-path "${ROOT}" -c release \
  | tee "${LOCAL}/swift-test-release.log"
corepack pnpm --dir "${RUNNER}" run typecheck \
  | tee "${LOCAL}/typescript-typecheck.log"
corepack pnpm --dir "${RUNNER}" run test:cross-sdk-core-benchmark \
  | tee "${LOCAL}/typescript-core-benchmark-tests.log"
corepack pnpm --dir "${RUNNER}" run test:cross-sdk-runtime-benchmark \
  | tee "${LOCAL}/typescript-runtime-benchmark-tests.log"

if [[ "${MODE}" != "smoke" ]]; then
  corepack pnpm --dir "${RUNNER}" test \
    | tee "${LOCAL}/typescript-contract-suite.log"
fi

export INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR="${CROSS}"
export INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-7}"
"${ROOT}/validation/run-cross-sdk-benchmark-comparison.sh" \
  | tee "${CROSS}/runner.log"
test -f "${CROSS}/comparison.json"

if [[ "${MODE}" != "smoke" ]]; then
  missing=0
  for variable in INSTANT_CLI_AUTH_TOKEN INSTANT_APP_ID INSTANT_ADMIN_TOKEN; do
    if [[ -z "${!variable:-}" ]]; then echo "Missing live secret ${variable}" >&2; missing=1; fi
  done
  [[ "${missing}" -eq 0 ]] || exit 1

  export INSTANT_APP_ADMIN_TOKEN="${INSTANT_APP_ADMIN_TOKEN:-${INSTANT_ADMIN_TOKEN}}"
  export INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR="${SCRIBE}"
  export INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS="${INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS:-30}"
  export INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT="${INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT:-16}"
  "${ROOT}/validation/run-scribe-shaped-20s-write-bench.sh" \
    | tee "${SCRIBE}/runner.log"
  test -f "${SCRIBE}/summary.json"

  GYM="${ROOT}/validation/exercise-gym"
  corepack pnpm --dir "${GYM}" install --frozen-lockfile \
    | tee "${EXERCISE}/pnpm-install.log"
  (
    cd "${GYM}"
    corepack pnpm exec tsx src/report.ts \
      --comparison "${CROSS}/comparison.json" \
      --scribe "${SCRIBE}/summary.json" \
      --out "${EXERCISE}/report.json"
  ) | tee "${EXERCISE}/runner.log"
  test -f "${EXERCISE}/report.json"
fi

if [[ "${MODE}" == "release" ]]; then
  test -f "${ROOT}/VERSION"
  VERSION="$(tr -d '[:space:]' <"${ROOT}/VERSION")"
  [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]
  if [[ -n "${RELEASE_VERSION:-}" ]]; then
    test "${VERSION}" = "${RELEASE_VERSION}"
  fi
  printf '%s\n' "${VERSION}" >"${RESULTS}/verified-version.txt"
fi

ASSERT_ARGS=(
  --mode "${MODE}"
  --comparison "${CROSS}/comparison.json"
  --baseline "${ROOT}/validation/benchmarks/v1-cross-sdk-performance-2026-07-19.json"
  --output "${RESULTS}/assessment.json"
)
if [[ "${MODE}" != "smoke" ]]; then
  ASSERT_ARGS+=(--scribe "${SCRIBE}/summary.json" --exercise "${EXERCISE}/report.json")
fi
node "${ROOT}/validation/performance-gate/assert.mjs" "${ASSERT_ARGS[@]}" \
  | tee "${RESULTS}/assessment.stdout.json"

ELAPSED="$(($(date +%s) - STARTED))"
cat >"${RESULTS}/SUMMARY.md" <<EOF
# Instant performance and correctness gate

- Result: **PASS**
- Mode: \`${MODE}\`
- Duration: ${ELAPSED} seconds
- Swift revision: \`$(git -C "${ROOT}" rev-parse HEAD)\`
- Instant TypeScript revision: \`${EXPECTED_UPSTREAM}\`
EOF

echo "[gate] PASS mode=${MODE} elapsed=${ELAPSED}s evidence=${RESULTS}"
