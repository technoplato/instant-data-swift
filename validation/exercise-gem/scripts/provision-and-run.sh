#!/usr/bin/env bash
# Provision ephemeral Instant app for exercise-gem, push schema/perms, run suites.
# Issue #156 expansion.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANT_ROOT="$(cd "${ROOT}/../.." && pwd)"
RUNNER="${INSTANT_ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
TSX="${ROOT}/node_modules/.bin/tsx"
SUITE="${1:-all}"
DURATION="${EXERCISE_GEM_DURATION_SECONDS:-15}"
RESULTS_DIR="${EXERCISE_GEM_OUT:-${ROOT}/artifacts/$(date -u +%Y%m%dT%H%M%SZ)}"
WORK_DIR="${RESULTS_DIR}/app"

mkdir -p "${WORK_DIR}" "${RESULTS_DIR}"

if [[ ! -x "${CLI}" ]]; then
  echo "Missing Instant CLI. Run: pnpm --dir ${RUNNER} install --frozen-lockfile" >&2
  exit 1
fi

# Ensure local gem deps (tsx, ws). Prefer existing node_modules link.
if [[ ! -x "${TSX}" ]]; then
  if [[ -x "${RUNNER}/node_modules/.bin/tsx" ]]; then
    TSX="${RUNNER}/node_modules/.bin/tsx"
  else
    echo "Installing exercise-gem deps…"
    (cd "${ROOT}" && npm install --no-fund --no-audit)
    TSX="${ROOT}/node_modules/.bin/tsx"
  fi
fi

cp "${ROOT}/instant.schema.ts" "${WORK_DIR}/instant.schema.ts"
cp "${ROOT}/instant.perms.ts" "${WORK_DIR}/instant.perms.ts"
printf '{"private":true,"type":"module","dependencies":{"@instantdb/core":"1.0.49","@instantdb/admin":"1.0.49"}}\n' \
  >"${WORK_DIR}/package.json"
ln -sfn "${RUNNER}/node_modules" "${WORK_DIR}/node_modules"

echo "[exercise-gem] provisioning ephemeral Instant app…"
(
  cd "${WORK_DIR}"
  "${CLI}" init \
    --temp \
    --title "instant-exercise-gem" \
    --yes \
    --env .instant.env
) | tee "${RESULTS_DIR}/instant-cli-init.log"

set -a
# shellcheck disable=SC1090
source "${WORK_DIR}/.instant.env"
set +a

APP_ID="${INSTANT_APP_ID:?missing INSTANT_APP_ID}"
ADMIN_TOKEN="${INSTANT_APP_ADMIN_TOKEN:?missing INSTANT_APP_ADMIN_TOKEN}"
export INSTANT_APP_ID="${APP_ID}"
export INSTANT_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_APP_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_CLI_AUTH_TOKEN="${ADMIN_TOKEN}"
export EXERCISE_GEM_DURATION_SECONDS="${DURATION}"

# `instant-cli init --temp` already applied schema + perms from the copied files.
# A second push is optional and often just re-spams the attribute spinner; skip
# unless EXERCISE_GEM_FORCE_PUSH=1.
if [[ "${EXERCISE_GEM_FORCE_PUSH:-0}" == "1" ]]; then
  echo "[exercise-gem] force push schema + perms → ${APP_ID}"
  (
    cd "${WORK_DIR}"
    "${CLI}" push schema --yes
    "${CLI}" push perms --yes
  ) | tee "${RESULTS_DIR}/instant-cli-push.log"
else
  echo "[exercise-gem] schema/perms already applied by init → ${APP_ID}"
fi

# Save non-secret app id for artifacts
printf '{"appId":"%s"}\n' "${APP_ID}" >"${RESULTS_DIR}/app-meta.json"

echo "[exercise-gem] run suite=${SUITE} duration=${DURATION}s"
(
  cd "${ROOT}"
  "${TSX}" src/run.ts \
    --suite "${SUITE}" \
    --duration "${DURATION}" \
    --out "${RESULTS_DIR}/run" \
    ${EXERCISE_GEM_SKIP_SWIFT:+--skip-swift}
) | tee "${RESULTS_DIR}/run.log"

echo "[exercise-gem] done → ${RESULTS_DIR}"
echo "${RESULTS_DIR}"
