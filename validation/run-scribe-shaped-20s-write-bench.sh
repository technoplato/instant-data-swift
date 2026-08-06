#!/usr/bin/env bash
# #156 — Scribe open-segment 20s network write/observe matrix (Net-A + Net-B).
#
# Net-A: TS @instantdb/admin writer  →  Swift InstantRuntime observer
# Net-B: Swift InstantRuntime writer →  TS admin query observer
#
# Validity: observer process counts monotonic `seq` advances over the network.
# Compare network-vs-network only (never local vs network).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
DURATION="${INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS:-20}"
WORDS="${INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT:-12}"
RESULTS_DIR="${INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR:-${ROOT}/.perf-runs/scribe-20s-write/$(date -u +%Y%m%dT%H%M%SZ)}"
WORK_DIR="${RESULTS_DIR}/app"
export INSTANT_SWIFT_DATA_BENCH_RESULTS_DIR="${RESULTS_DIR}"
export INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS="${DURATION}"
export INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT="${WORDS}"

mkdir -p "${WORK_DIR}" "${RESULTS_DIR}"
trap 'rm -f "${WORK_DIR}/.instant.env" "${WORK_DIR}/node_modules"' EXIT

if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI. Run: pnpm --dir validation/ts-runner install --frozen-lockfile" >&2
  exit 1
fi

cp "${ROOT}/validation/fixtures/scribe-open-segment-bench.schema.ts" "${WORK_DIR}/instant.schema.ts"
cp "${ROOT}/validation/fixtures/scribe-open-segment-bench.perms.ts" "${WORK_DIR}/instant.perms.ts"
printf '{"private":true,"type":"module","dependencies":{"@instantdb/core":"1.0.49","@instantdb/admin":"1.0.49"}}\n' \
  >"${WORK_DIR}/package.json"
ln -sfn "${RUNNER}/node_modules" "${WORK_DIR}/node_modules"

echo "[bench #156] provisioning ephemeral Instant app…"
(
  cd "${WORK_DIR}"
  "${CLI}" init \
    --temp \
    --title "instant-data-swift-scribe-open-segment-20s" \
    --yes \
    --env .instant.env
) | tee "${RESULTS_DIR}/instant-cli-init.log"

set -a
# shellcheck disable=SC1090
source "${WORK_DIR}/.instant.env"
set +a

APP_ID="${INSTANT_APP_ID:?Instant CLI did not write INSTANT_APP_ID}"
ADMIN_TOKEN="${INSTANT_APP_ADMIN_TOKEN:?Instant CLI did not write INSTANT_APP_ADMIN_TOKEN}"
export INSTANT_APP_ID="${APP_ID}"
export INSTANT_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_APP_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_CLI_AUTH_TOKEN="${ADMIN_TOKEN}"

echo "[bench #156] pushing schema + perms to ${APP_ID}"
(
  cd "${WORK_DIR}"
  "${CLI}" push schema --yes
  "${CLI}" push perms --yes
) | tee "${RESULTS_DIR}/instant-cli-push.log"

echo "[bench #156] building Swift CLI (first run may take a while)…"
swift build --package-path "${ROOT}" --product scribe-shaped-20s-write-bench \
  | tee "${RESULTS_DIR}/swift-build.log"

echo "[bench #156] running Net-A + Net-B for ${DURATION}s (words/upsert=${WORDS})…"
TSX="${RUNNER}/node_modules/.bin/tsx"
if [[ ! -x "${TSX}" ]]; then
  echo "Missing tsx at ${TSX}. Run: pnpm --dir validation/ts-runner install --frozen-lockfile" >&2
  exit 1
fi
(
  cd "${RUNNER}"
  "${TSX}" src/scribe-shaped-20s-write-bench.ts \
    --role coordinate \
    --duration "${DURATION}" \
    --words-per-upsert "${WORDS}"
) | tee "${RESULTS_DIR}/coordinate.stdout.json"

echo "[bench #156] done. Results: ${RESULTS_DIR}/summary.json"
if [[ -f "${RESULTS_DIR}/summary.json" ]]; then
  node -e '
    const s = require(process.argv[1]);
    const c = s.compare || {};
    console.log("compare.valid_writes_per_s netA=", c.netA_adminToSwift, "netB=", c.netB_swiftToAdmin, "ratio B/A=", c.ratio_netB_over_netA);
  ' "${RESULTS_DIR}/summary.json"
fi
