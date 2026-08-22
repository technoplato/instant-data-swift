#!/usr/bin/env bash
# Provision ephemeral Instant app for exercise-gym, push schema/perms, run suites.
# Issue #156 expansion (exercise gym).
#
# Self-host (Docker Instant):
#   bash scripts/docker-up.sh
#   EXERCISE_GYM_SELF_HOST=1 bash scripts/provision-and-run.sh all
#
# Cloud (default):
#   bash scripts/provision-and-run.sh all
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANT_ROOT="$(cd "${ROOT}/../.." && pwd)"
RUNNER="${INSTANT_ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
TSX="${ROOT}/node_modules/.bin/tsx"
SUITE="${1:-all}"
DURATION="${EXERCISE_GYM_DURATION_SECONDS:-15}"
RESULTS_DIR="${EXERCISE_GYM_OUT:-${ROOT}/artifacts/$(date -u +%Y%m%dT%H%M%SZ)}"
WORK_DIR="${RESULTS_DIR}/app"

mkdir -p "${WORK_DIR}" "${RESULTS_DIR}"

if [[ ! -x "${CLI}" ]]; then
  echo "Missing Instant CLI. Run: pnpm --dir ${RUNNER} install --frozen-lockfile" >&2
  exit 1
fi

if [[ ! -x "${TSX}" ]]; then
  if [[ -x "${RUNNER}/node_modules/.bin/tsx" ]]; then
    TSX="${RUNNER}/node_modules/.bin/tsx"
  else
    echo "Installing exercise-gym deps…"
    (cd "${ROOT}" && npm install --no-fund --no-audit)
    TSX="${ROOT}/node_modules/.bin/tsx"
  fi
fi

# Self-host API endpoints
if [[ "${EXERCISE_GYM_SELF_HOST:-0}" == "1" ]]; then
  export INSTANT_API_URI="${INSTANT_API_URI:-http://localhost:8888}"
  export INSTANT_WEBSOCKET_URI="${INSTANT_WEBSOCKET_URI:-ws://localhost:8888/runtime/session}"
  export INSTANT_CLI_API_URI="${INSTANT_CLI_API_URI:-http://localhost:8888}"
  export INSTANT_TEST_API_ORIGIN="${INSTANT_TEST_API_ORIGIN:-http://localhost:8888}"
  # Ensure Docker is healthy
  if ! curl -fsS "${INSTANT_API_URI}/health/system" >/dev/null; then
    echo "[exercise-gym] self-host not healthy at ${INSTANT_API_URI}; run scripts/docker-up.sh" >&2
    exit 1
  fi
  echo "[exercise-gym] self-host mode → ${INSTANT_API_URI}"
fi

cp "${ROOT}/instant.schema.ts" "${WORK_DIR}/instant.schema.ts"
cp "${ROOT}/instant.perms.ts" "${WORK_DIR}/instant.perms.ts"
printf '{"private":true,"type":"module","dependencies":{"@instantdb/core":"1.0.49","@instantdb/admin":"1.0.49"}}\n' \
  >"${WORK_DIR}/package.json"
ln -sfn "${RUNNER}/node_modules" "${WORK_DIR}/node_modules"

# Point instant-cli at self-host when configured
if [[ -n "${INSTANT_CLI_API_URI:-}" ]]; then
  cat >"${WORK_DIR}/instant.config.ts" <<EOF
export default {
  apiURI: "${INSTANT_CLI_API_URI}",
};
EOF
fi

echo "[exercise-gym] provisioning ephemeral Instant app…"
set +e
(
  cd "${WORK_DIR}"
  env \
    ${INSTANT_CLI_API_URI:+INSTANT_CLI_API_URI="${INSTANT_CLI_API_URI}"} \
    "${CLI}" init \
      --temp \
      --title "instant-exercise-gym" \
      --yes \
      --env .instant.env
) | tee "${RESULTS_DIR}/instant-cli-init.log"
init_status=${PIPESTATUS[0]}
set -e
if [[ ! -f "${WORK_DIR}/.instant.env" ]]; then
  echo "[exercise-gym] instant-cli init failed (status=${init_status}) and wrote no .instant.env" >&2
  exit 1
fi
if [[ "${init_status}" -ne 0 ]]; then
  echo "[exercise-gym] warning: instant-cli init exit ${init_status}, but .instant.env exists — continuing"
fi

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
export EXERCISE_GYM_DURATION_SECONDS="${DURATION}"

if [[ "${EXERCISE_GYM_FORCE_PUSH:-0}" == "1" ]]; then
  echo "[exercise-gym] force push schema + perms → ${APP_ID}"
  (
    cd "${WORK_DIR}"
    env ${INSTANT_CLI_API_URI:+INSTANT_CLI_API_URI="${INSTANT_CLI_API_URI}"} \
      "${CLI}" push schema --yes
    env ${INSTANT_CLI_API_URI:+INSTANT_CLI_API_URI="${INSTANT_CLI_API_URI}"} \
      "${CLI}" push perms --yes
  ) | tee "${RESULTS_DIR}/instant-cli-push.log"
else
  echo "[exercise-gym] schema/perms already applied by init → ${APP_ID}"
fi

printf '{"appId":"%s","apiURI":"%s","websocketURI":"%s","selfHost":%s}\n' \
  "${APP_ID}" \
  "${INSTANT_API_URI:-https://api.instantdb.com}" \
  "${INSTANT_WEBSOCKET_URI:-wss://api.instantdb.com/runtime/session}" \
  "$( [[ "${EXERCISE_GYM_SELF_HOST:-0}" == "1" ]] && echo true || echo false )" \
  >"${RESULTS_DIR}/app-meta.json"

echo "[exercise-gym] run suite=${SUITE} duration=${DURATION}s"
(
  cd "${ROOT}"
  # shellcheck disable=SC2086
  "${TSX}" src/run.ts \
    --suite "${SUITE}" \
    --duration "${DURATION}" \
    --out "${RESULTS_DIR}/run" \
    ${EXERCISE_GYM_SKIP_SWIFT:+--skip-swift} \
    ${EXERCISE_GYM_SWIFT_ONLY:+--swift-only}
) | tee "${RESULTS_DIR}/run.log"

# Export docker server artifacts when self-hosting
if [[ "${EXERCISE_GYM_SELF_HOST:-0}" == "1" ]]; then
  bash "${ROOT}/scripts/export-server-artifacts.sh" "${RESULTS_DIR}/server" || true
fi

echo "[exercise-gym] done → ${RESULTS_DIR}"
echo "${RESULTS_DIR}"
