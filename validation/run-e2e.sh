#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT}/validation/results/$(date -u +%Y%m%dT%H%M%SZ)"
VALIDATION_APP_ID="local-validation"

mkdir -p "${RESULTS_DIR}"

timestamp_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
  else
    printf '%s000\n' "$(date -u +%s)"
  fi
}

log_json() {
  local event="$1"
  local ok="$2"
  local details="${3:-{}}"
  printf '{"case":"harness","side":"orchestrator","event":"%s","appID":"%s","timestampMs":%s,"ok":%s,"details":%s}\n' \
    "${event}" \
    "${VALIDATION_APP_ID}" \
    "$(timestamp_ms)" \
    "${ok}" \
    "${details}" | tee -a "${RESULTS_DIR}/orchestrator.jsonl" >/dev/null
}

require_file() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    log_json "missing-required-file" false "{\"path\":\"${path}\"}"
    echo "Missing required validation component: ${path}" >&2
    return 1
  fi
}

log_json "start" true "{\"resultsDir\":\"${RESULTS_DIR}\"}"

require_file "${ROOT}/validation/fixtures/schema.swift"
require_file "${ROOT}/validation/fixtures/instant.schema.ts"
require_file "${ROOT}/validation/fixtures/instant.perms.ts"
require_file "${ROOT}/validation/ts-runner/package.json"
require_file "${ROOT}/Package.swift"
require_file "${ROOT}/Sources/InstantSwiftDataValidationRunner/main.swift"

if ! command -v swift >/dev/null 2>&1; then
  log_json "missing-swift" false
  echo "swift is required for the Swift runner." >&2
  exit 1
fi

log_json "swift-local-start" true
if (
  cd "${ROOT}"
  swift run instant-swift-data-validation-runner --local-todos
) | tee "${RESULTS_DIR}/swift-local.jsonl"; then
  log_json "swift-local-complete" true "{\"path\":\"${RESULTS_DIR}/swift-local.jsonl\"}"
else
  status=$?
  log_json \
    "swift-local-failed" \
    false \
    "{\"path\":\"${RESULTS_DIR}/swift-local.jsonl\",\"exitCode\":${status}}"
  log_json \
    "complete" \
    false \
    "{\"resultsDir\":\"${RESULTS_DIR}\",\"failed\":\"swift-local\",\"exitCode\":${status}}"
  exit "${status}"
fi

if command -v node >/dev/null 2>&1; then
  log_json "typescript-boundary-pending" true "{\"reason\":\"TypeScript runner remains scaffolded until real Instant transport lands\"}"
else
  log_json "typescript-boundary-skipped" true "{\"reason\":\"node is not available and Swift local validation completed\"}"
fi

log_json "complete" true "{\"resultsDir\":\"${RESULTS_DIR}\"}"
