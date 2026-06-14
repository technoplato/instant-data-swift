#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR:-${ROOT}/validation/results/$(date -u +%Y%m%dT%H%M%SZ)}"
VALIDATION_APP_ID="local-validation"
BENCHMARK_ITERATIONS="${INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS:-1}"

mkdir -p "${RESULTS_DIR}"
rm -f \
  "${RESULTS_DIR}/swift-local.jsonl" \
  "${RESULTS_DIR}/swift-local-integrations.jsonl" \
  "${RESULTS_DIR}/swift-typed-drafts.jsonl" \
  "${RESULTS_DIR}/swift-platform-adapters.jsonl" \
  "${RESULTS_DIR}/swift-syncups-recording.jsonl" \
  "${RESULTS_DIR}/swift-parity-report.jsonl" \
  "${RESULTS_DIR}/swift-benchmark.jsonl" \
  "${RESULTS_DIR}/typescript-fixtures.jsonl"
: > "${RESULTS_DIR}/orchestrator.jsonl"

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
  local details="${3:-}"
  if [[ -z "${details}" ]]; then
    details="{}"
  fi
  if command -v python3 >/dev/null 2>&1; then
    EVENT="${event}" \
      OK="${ok}" \
      APP_ID="${VALIDATION_APP_ID}" \
      TIMESTAMP_MS="$(timestamp_ms)" \
      DETAILS="${details}" \
      python3 - <<'PY' | tee -a "${RESULTS_DIR}/orchestrator.jsonl" >/dev/null
import json
import os

print(json.dumps({
  "case": "harness",
  "side": "orchestrator",
  "event": os.environ["EVENT"],
  "appID": os.environ["APP_ID"],
  "timestampMs": int(os.environ["TIMESTAMP_MS"]),
  "ok": os.environ["OK"] == "true",
  "details": json.loads(os.environ["DETAILS"]),
}, separators=(",", ":")))
PY
  else
    printf '{"case":"harness","side":"orchestrator","event":"%s","appID":"%s","timestampMs":%s,"ok":%s,"details":%s}\n' \
      "${event}" \
      "${VALIDATION_APP_ID}" \
      "$(timestamp_ms)" \
      "${ok}" \
      "${details}" | tee -a "${RESULTS_DIR}/orchestrator.jsonl" >/dev/null
  fi
}

json_string() {
  if command -v python3 >/dev/null 2>&1; then
    VALUE="$1" python3 - <<'PY'
import json
import os
print(json.dumps(os.environ["VALUE"]))
PY
  else
    printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  fi
}

json_object() {
  local key="$1"
  local value="$2"
  printf '{"%s":%s}' "${key}" "$(json_string "${value}")"
}

json_failure_details() {
  local path="$1"
  local exit_code="$2"
  printf '{"path":%s,"exitCode":%s}' "$(json_string "${path}")" "${exit_code}"
}

require_file() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    log_json "missing-required-file" false "$(json_object "path" "${path}")"
    echo "Missing required validation component: ${path}" >&2
    return 1
  fi
}

log_json "start" true "$(json_object "resultsDir" "${RESULTS_DIR}")"

missing_required_file=false
for required_file in \
  "${ROOT}/validation/fixtures/schema.swift" \
  "${ROOT}/validation/fixtures/instant.schema.ts" \
  "${ROOT}/validation/fixtures/instant.perms.ts" \
  "${ROOT}/validation/ts-runner/package.json" \
  "${ROOT}/Package.swift" \
  "${ROOT}/Sources/instant-swift-data/main.swift" \
  "${ROOT}/Sources/InstantSwiftDataValidationRunner/main.swift" \
  "${ROOT}/Sources/InstantSwiftDataBenchmarks/main.swift"
do
  if ! require_file "${required_file}"; then
    missing_required_file=true
  fi
done
if [[ "${missing_required_file}" == "true" ]]; then
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"missing-required-file"}' "$(json_string "${RESULTS_DIR}")")"
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  log_json "missing-swift" false
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"missing-swift"}' "$(json_string "${RESULTS_DIR}")")"
  echo "swift is required for the Swift runner." >&2
  exit 1
fi

log_json "swift-local-start" true
if (
  cd "${ROOT}"
  swift run instant-swift-data-validation-runner --local-todos
) | tee "${RESULTS_DIR}/swift-local.jsonl"; then
  log_json "swift-local-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-local.jsonl")"
else
  status=$?
  log_json \
    "swift-local-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-local.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-local","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-local-integrations-start" true
if (
  cd "${ROOT}"
  swift run instant-swift-data-validation-runner --local-integrations
) | tee "${RESULTS_DIR}/swift-local-integrations.jsonl"; then
  log_json "swift-local-integrations-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-local-integrations.jsonl")"
else
  status=$?
  log_json \
    "swift-local-integrations-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-local-integrations.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-local-integrations","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-typed-drafts-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" swift run instant-swift-data validation typed-drafts --jsonl
) | tee "${RESULTS_DIR}/swift-typed-drafts.jsonl"; then
  log_json "swift-typed-drafts-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-typed-drafts.jsonl")"
else
  status=$?
  log_json \
    "swift-typed-drafts-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-typed-drafts.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-typed-drafts","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-platform-adapters-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" swift run instant-swift-data validation platform-adapters --jsonl
) | tee "${RESULTS_DIR}/swift-platform-adapters.jsonl"; then
  log_json "swift-platform-adapters-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-platform-adapters.jsonl")"
else
  status=$?
  log_json \
    "swift-platform-adapters-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-platform-adapters.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-platform-adapters","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-syncups-recording-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" swift run instant-swift-data validation syncups-recording --jsonl
) | tee "${RESULTS_DIR}/swift-syncups-recording.jsonl"; then
  log_json "swift-syncups-recording-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-syncups-recording.jsonl")"
else
  status=$?
  log_json \
    "swift-syncups-recording-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-syncups-recording.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-syncups-recording","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-parity-report-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" swift run instant-swift-data validation parity-report --jsonl
) | tee "${RESULTS_DIR}/swift-parity-report.jsonl"; then
  log_json "swift-parity-report-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-parity-report.jsonl")"
else
  status=$?
  log_json \
    "swift-parity-report-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-parity-report.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-parity-report","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-benchmark-start" true
if (
  cd "${ROOT}"
  swift run instant-swift-data-benchmarks \
    --suite local-todos \
    --iterations "${BENCHMARK_ITERATIONS}" \
    --app-id "${VALIDATION_APP_ID}" \
    --jsonl
) | tee "${RESULTS_DIR}/swift-benchmark.jsonl"; then
  log_json "swift-benchmark-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-benchmark.jsonl")"
else
  status=$?
  log_json \
    "swift-benchmark-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-benchmark.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-benchmark","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

if command -v node >/dev/null 2>&1; then
  log_json "typescript-fixtures-start" true
  if (
    cd "${ROOT}"
    VALIDATION_APP_ID="${VALIDATION_APP_ID}" node validation/ts-runner/src/main.ts --fixtures --app-id "${VALIDATION_APP_ID}"
  ) | tee "${RESULTS_DIR}/typescript-fixtures.jsonl"; then
    log_json "typescript-fixtures-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-fixtures.jsonl")"
  else
    status=$?
    log_json \
      "typescript-fixtures-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/typescript-fixtures.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"typescript-fixtures","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi
  log_json "typescript-boundary-pending" true "$(json_object "reason" "Real Instant app creation, schema push, and admin query/transact remain pending")"
else
  log_json "typescript-boundary-skipped" true "$(json_object "reason" "node is not available and Swift local validations and benchmark completed")"
fi

log_json "complete" true "$(json_object "resultsDir" "${RESULTS_DIR}")"
