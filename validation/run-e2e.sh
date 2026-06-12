#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${ROOT}/validation/results/$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "${RESULTS_DIR}"

log_json() {
  local event="$1"
  local ok="$2"
  local details="${3:-{}}"
  printf '{"case":"harness","side":"orchestrator","event":"%s","timestampMs":%s,"ok":%s,"details":%s}\n' \
    "${event}" \
    "$(node -e 'console.log(Date.now())')" \
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

if ! command -v node >/dev/null 2>&1; then
  log_json "missing-node" false
  echo "node is required for the TypeScript runner." >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  log_json "missing-swift" false
  echo "swift is required for the Swift runner." >&2
  exit 1
fi

log_json "blocked-not-implemented" false "{\"reason\":\"Swift and TypeScript runners are not implemented yet\"}"
echo "Validation scaffold is present, but runners are not implemented yet." >&2
exit 2
