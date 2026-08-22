#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="smoke"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:?missing value for --mode}"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: validation/run-performance-gate.sh [--mode smoke|full|release]

smoke    Deterministic Swift + TypeScript correctness and local release-mode parity.
full     Smoke plus live bidirectional Scribe and exercise-gym memory/CPU/throughput.
release  Same as full, with version/tag checks and no optional live credentials.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

case "${MODE}" in
  smoke|full|release) ;;
  *)
    echo "--mode must be smoke, full, or release" >&2
    exit 64
    ;;
esac

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RESULTS_ROOT="${INSTANT_PERFORMANCE_RESULTS_DIR:-${ROOT}/validation/results/performance-gate/${STAMP}}"
LOCAL_DIR="${RESULTS_ROOT}/local"
CROSS_DIR="${RESULTS_ROOT}/cross-sdk"
SCRIBE_DIR="${RESULTS_ROOT}/scribe-live"
GYM_DIR="${RESULTS_ROOT}/exercise-gym"
mkdir -p "${LOCAL_DIR}" "${CROSS_DIR}" "${SCRIBE_DIR}" "${GYM_DIR}"

exec > >(tee "${RESULTS_ROOT}/gate.stdout.log") \
  2> >(tee "${RESULTS_ROOT}/gate.stderr.log" >&2)

started_epoch="$(date +%s)"
echo "[gate] mode=${MODE} root=${ROOT} results=${RESULTS_ROOT}"
echo "[gate] swift=$(swift --version | head -1)"
echo "[gate] node=$(node --version)"
echo "[gate] os=$(uname -a)"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_command git
require_command node
require_command swift
require_command corepack

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Performance evidence requires a clean worktree." >&2
  git -C "${ROOT}" status --short >&2
  exit 1
fi

prepare_upstream() {
  local runner="${ROOT}/validation/ts-runner"
  local expected
  expected="$({
    cd "${runner}"
    node -p "require('./package.json').instantContract.upstreamRevision"
  })"

  if [[ -f "${ROOT}/.gitmodules" ]] && git -C "${ROOT}" config -f .gitmodules --get-regexp '^submodule\..*\.path$' \
      | awk '{print $2}' | grep -Fxq 'upstream/instant'; then
    echo "[gate] initializing pinned Instant submodule"
    git -C "${ROOT}" submodule update --init --recursive upstream/instant
  elif [[ ! -d "${ROOT}/upstream/instant/.git" ]]; then
    echo "[gate] cloning pinned Instant reference"
    git clone --filter=blob:none --no-checkout https://github.com/instantdb/instant.git \
      "${ROOT}/upstream/instant"
  fi

  git -C "${ROOT}/upstream/instant" fetch --depth 1 origin "${expected}"
  git -C "${ROOT}/upstream/instant" checkout --detach "${expected}"

  local actual
  actual="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "Pinned Instant revision mismatch: expected=${expected} actual=${actual}" >&2
    exit 1
  fi
  printf '%s\n' "${actual}" >"${LOCAL_DIR}/upstream-instant-revision.txt"
}

prepare_dependencies() {
  echo "[gate] installing pinned TypeScript validation dependencies"
  corepack pnpm --dir "${ROOT}/validation/ts-runner" install --frozen-lockfile \
    | tee "${LOCAL_DIR}/pnpm-install.log"
}

run_deterministic_correctness() {
  echo "[gate] Swift release tests"
  swift test --package-path "${ROOT}" -c release \
    | tee "${LOCAL_DIR}/swift-test-release.log"

  echo "[gate] TypeScript contract tests"
  corepack pnpm --dir "${ROOT}/validation/ts-runner" test \
    | tee "${LOCAL_DIR}/typescript-contract-tests.log"
}

run_cross_sdk_parity() {
  echo "[gate] cross-SDK deterministic performance parity"
  export INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_RESULTS_DIR="${CROSS_DIR}"
  export INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS="${INSTANT_SWIFT_DATA_BENCHMARK_COMPARISON_ITERATIONS:-7}"
  "${ROOT}/validation/run-cross-sdk-benchmark-comparison.sh" \
    | tee "${CROSS_DIR}/runner.log"
  test -f "${CROSS_DIR}/comparison.json"
}

require_live_credentials() {
  local missing=0
  for variable in INSTANT_CLI_AUTH_TOKEN; do
    if [[ -z "${!variable:-}" ]]; then
      echo "Missing required live-gate secret: ${variable}" >&2
      missing=1
    fi
  done
  [[ "${missing}" -eq 0 ]] || exit 1
}

run_scribe_live_matrix() {
  echo "[gate] Scribe-shaped bidirectional live matrix"
  export INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR="${SCRIBE_DIR}"
  export INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS="${INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS:-30}"
  export INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT="${INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT:-16}"
  "${ROOT}/validation/run-scribe-shaped-20s-write-bench.sh" \
    | tee "${SCRIBE_DIR}/runner.log"
  test -f "${SCRIBE_DIR}/summary.json"
}

run_exercise_gym() {
  local gym="${ROOT}/validation/exercise-gym"
  if [[ ! -f "${gym}/package.json" ]]; then
    echo "The consolidated exercise gym is required for mode=${MODE}." >&2
    exit 1
  fi

  echo "[gate] installing exercise-gym dependencies"
  corepack pnpm --dir "${gym}" install --frozen-lockfile=false \
    | tee "${GYM_DIR}/pnpm-install.log"

  echo "[gate] exercise-gym linked graph, throughput, memory, bandwidth, and CPU lanes"
  export EXERCISE_GYM_DURATION_SECONDS="${EXERCISE_GYM_DURATION_SECONDS:-30}"
  export EXERCISE_GYM_MAX_APP_RSS_MIB="${EXERCISE_GYM_MAX_APP_RSS_MIB:-150}"
  (
    cd "${gym}"
    corepack pnpm exec tsx src/run.ts --suite all --out "${GYM_DIR}"
  ) | tee "${GYM_DIR}/runner.log"
  test -f "${GYM_DIR}/report.json"
}

verify_release_version() {
  [[ "${MODE}" == "release" ]] || return 0
  local version_file="${ROOT}/VERSION"
  [[ -f "${version_file}" ]] || {
    echo "Release mode requires VERSION." >&2
    exit 1
  }
  local version tag
  version="$(tr -d '[:space:]' <"${version_file}")"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    echo "Invalid VERSION: ${version}" >&2
    exit 1
  }
  tag="${GITHUB_REF_NAME:-}"
  if [[ -n "${tag}" && "${tag}" != "v${version}" ]]; then
    echo "Tag/version mismatch: tag=${tag} VERSION=${version}" >&2
    exit 1
  fi
  printf '%s\n' "${version}" >"${RESULTS_ROOT}/verified-version.txt"
}

assess() {
  local arguments=(
    --mode "${MODE}"
    --comparison "${CROSS_DIR}/comparison.json"
    --output "${RESULTS_ROOT}/assessment.json"
  )
  if [[ "${MODE}" != "smoke" ]]; then
    arguments+=(
      --scribe "${SCRIBE_DIR}/summary.json"
      --exercise "${GYM_DIR}/report.json"
    )
  fi
  node "${ROOT}/validation/assert-performance-gate.mjs" "${arguments[@]}" \
    | tee "${RESULTS_ROOT}/assessment.stdout.json"
}

prepare_upstream
prepare_dependencies
run_deterministic_correctness
run_cross_sdk_parity

if [[ "${MODE}" != "smoke" ]]; then
  require_live_credentials
  run_scribe_live_matrix
  run_exercise_gym
fi

verify_release_version
assess

finished_epoch="$(date +%s)"
elapsed="$((finished_epoch - started_epoch))"
cat >"${RESULTS_ROOT}/SUMMARY.md" <<EOF
# Instant performance and correctness gate

- Mode: \`${MODE}\`
- Result: **PASS**
- Duration: ${elapsed} seconds
- Swift revision: \`$(git -C "${ROOT}" rev-parse HEAD)\`
- Instant TypeScript revision: \`$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)\`
- Evidence: \`${RESULTS_ROOT}\`
EOF

echo "[gate] PASS mode=${MODE} duration=${elapsed}s evidence=${RESULTS_ROOT}"
