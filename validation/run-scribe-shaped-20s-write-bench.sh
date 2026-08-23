#!/usr/bin/env bash
# #156 — Scribe open-segment 20s network write/observe matrix (Net-A + Net-B).
#
# Net-A: TS @instantdb/admin writer  →  Swift InstantRuntime observer
# Net-B: Swift InstantRuntime writer →  TS admin query observer
#
# Validity: the opposite SDK must observe progress and converge to the exact
# final sequence and word count confirmed by server ground truth.
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
umask 077
trap 'rm -f "${WORK_DIR}/.instant.env" "${WORK_DIR}/getadb-response.env" "${WORK_DIR}/node_modules"' EXIT

if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI. Run: pnpm --dir validation/ts-runner install --frozen-lockfile" >&2
  exit 1
fi

cp "${ROOT}/validation/fixtures/scribe-open-segment-bench.schema.ts" "${WORK_DIR}/instant.schema.ts"
cp "${ROOT}/validation/fixtures/scribe-open-segment-bench.perms.ts" "${WORK_DIR}/instant.perms.ts"
printf '{"private":true,"type":"module","dependencies":{"@instantdb/core":"1.0.49","@instantdb/admin":"1.0.49"}}\n' \
  >"${WORK_DIR}/package.json"
ln -sfn "${RUNNER}/node_modules" "${WORK_DIR}/node_modules"

provided_app_id="${INSTANT_APP_ID:-${VITE_INSTANT_APP_ID:-${NEXT_PUBLIC_INSTANT_APP_ID:-}}}"
provided_admin_token="${INSTANT_ADMIN_TOKEN:-${INSTANT_APP_ADMIN_TOKEN:-}}"
if [[ -n "${provided_app_id}" && -z "${provided_admin_token}" ]] \
  || [[ -z "${provided_app_id}" && -n "${provided_admin_token}" ]]
then
  echo "Provide both INSTANT_APP_ID and INSTANT_ADMIN_TOKEN, or neither." >&2
  exit 64
fi

credential_source="provided"
if [[ -z "${provided_app_id}" ]]; then
  credential_source="getadb-temporary"
  provision_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  echo "[bench #156] no suite credentials supplied; provisioning a temporary Instant app through getadb.com"
  curl --fail --silent --show-error --location --retry 3 \
    "https://www.getadb.com/provision/${provision_id}" \
    --output "${WORK_DIR}/getadb-response.env"
  chmod 600 "${WORK_DIR}/getadb-response.env"
  provided_app_id="$(
    sed -n -e 's/^INSTANT_APP_ID=//p' -e 's/^VITE_INSTANT_APP_ID=//p' \
      "${WORK_DIR}/getadb-response.env" | head -1
  )"
  provided_admin_token="$(
    sed -n -e 's/^INSTANT_ADMIN_TOKEN=//p' -e 's/^INSTANT_APP_ADMIN_TOKEN=//p' \
      "${WORK_DIR}/getadb-response.env" | head -1
  )"
fi

if [[ ! "${provided_app_id}" =~ ^[0-9a-fA-F-]{36}$ ]] \
  || [[ ! "${provided_admin_token}" =~ ^[A-Za-z0-9._-]+$ ]]
then
  echo "Instant test-app credentials are malformed." >&2
  exit 1
fi

export INSTANT_APP_ID="${provided_app_id}"
export INSTANT_ADMIN_TOKEN="${provided_admin_token}"
export INSTANT_APP_ADMIN_TOKEN="${provided_admin_token}"
export INSTANT_CLI_AUTH_TOKEN="${provided_admin_token}"

node --input-type=module - "${RESULTS_DIR}/provisioning.json" "${credential_source}" "${INSTANT_APP_ID}" <<'NODE'
import { writeFileSync } from "node:fs";
const [path, source, appID] = process.argv.slice(2);
writeFileSync(path, `${JSON.stringify({
  protocol: "instant-test-app-provisioning-v1",
  source,
  appID,
  temporary: source === "getadb-temporary",
  secretMaterialPersisted: false,
}, null, 2)}\n`);
NODE

if [[ "${INSTANT_SWIFT_DATA_TEST_APP_SKIP_SCHEMA_PUSH:-0}" != "1" ]]; then
  echo "[bench #156] pushing fixture schema + permissions to ${INSTANT_APP_ID} (${credential_source})"
  (
    cd "${WORK_DIR}"
    "${CLI}" push schema --yes
    "${CLI}" push perms --yes
  ) | tee "${RESULTS_DIR}/instant-cli-push.log"
else
  echo "[bench #156] schema push skipped by INSTANT_SWIFT_DATA_TEST_APP_SKIP_SCHEMA_PUSH=1"
fi

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

node "${ROOT}/validation/assert-bidirectional-wire-correctness.mjs" \
  "${RESULTS_DIR}/summary.json" \
  "${RESULTS_DIR}/wire-correctness.json" \
  | tee "${RESULTS_DIR}/wire-correctness.log"

echo "[bench #156] done. Results: ${RESULTS_DIR}/summary.json"
node -e '
  const s = require(process.argv[1]);
  const c = s.compare || {};
  console.log("compare.valid_writes_per_s netA=", c.netA_adminToSwift, "netB=", c.netB_swiftToAdmin, "ratio B/A=", c.ratio_netB_over_netA);
' "${RESULTS_DIR}/summary.json"
