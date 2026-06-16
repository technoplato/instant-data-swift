#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR:-${ROOT}/validation/results/$(date -u +%Y%m%dT%H%M%SZ)}"
if [[ "${RESULTS_DIR}" != /* ]]; then
  RESULTS_DIR="${PWD}/${RESULTS_DIR}"
fi
VALIDATION_APP_ID="local-validation"
REMOTE_VALIDATION_APP_ID="${INSTANT_SWIFT_DATA_REMOTE_APP_ID:-${INSTANT_APP_ID:-local-validation}}"
BENCHMARK_ITERATIONS="${INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS:-1}"
REQUIRE_REMOTE_PREFLIGHT="${INSTANT_SWIFT_DATA_REQUIRE_REMOTE_PREFLIGHT:-0}"
RUN_LIVE_BOUNDARY="${INSTANT_SWIFT_DATA_RUN_LIVE_BOUNDARY:-0}"
RUN_TYPESCRIPT_LIVE_BOUNDARY="${INSTANT_SWIFT_DATA_RUN_TYPESCRIPT_LIVE_BOUNDARY:-0}"

mkdir -p "${RESULTS_DIR}"
rm -f \
  "${RESULTS_DIR}/swift-local.jsonl" \
  "${RESULTS_DIR}/swift-local-integrations.jsonl" \
  "${RESULTS_DIR}/swift-server-transaction-loopback.jsonl" \
  "${RESULTS_DIR}/swift-cloudkit-demo.jsonl" \
  "${RESULTS_DIR}/swift-live-session.jsonl" \
  "${RESULTS_DIR}/swift-live-transaction.jsonl" \
  "${RESULTS_DIR}/swift-live-observe.jsonl" \
  "${RESULTS_DIR}/swift-reminders.jsonl" \
  "${RESULTS_DIR}/swift-typed-drafts.jsonl" \
  "${RESULTS_DIR}/swift-platform-adapters.jsonl" \
  "${RESULTS_DIR}/swift-syncups-recording.jsonl" \
  "${RESULTS_DIR}/swift-parity-report.jsonl" \
  "${RESULTS_DIR}/swift-coverage.jsonl" \
  "${RESULTS_DIR}/swift-transport-contract-transact.json" \
  "${RESULTS_DIR}/swift-transport-contract.json" \
  "${RESULTS_DIR}/swift-schema-generate.json" \
  "${RESULTS_DIR}/swift-perms-generate.json" \
  "${RESULTS_DIR}/swift-schema-verify.json" \
  "${RESULTS_DIR}/swift-perms-verify.json" \
  "${RESULTS_DIR}/swift-generated-schema-verify.json" \
  "${RESULTS_DIR}/swift-generated-perms-verify.json" \
  "${RESULTS_DIR}/swift-macro-tests.log" \
  "${RESULTS_DIR}/swift-benchmark.jsonl" \
  "${RESULTS_DIR}/typescript-fixtures.jsonl" \
  "${RESULTS_DIR}/typescript-transport-contract.jsonl" \
  "${RESULTS_DIR}/typescript-local-integrations-contract.jsonl" \
  "${RESULTS_DIR}/typescript-live-session-contract.jsonl" \
  "${RESULTS_DIR}/typescript-live-transaction-contract.jsonl" \
  "${RESULTS_DIR}/typescript-server-transaction-contract.json" \
  "${RESULTS_DIR}/typescript-server-transaction-contract.jsonl" \
  "${RESULTS_DIR}/swift-typescript-server-transaction-contract.jsonl" \
  "${RESULTS_DIR}/typescript-boundary.jsonl" \
  "${RESULTS_DIR}/typescript-swift-boundary.jsonl" \
  "${RESULTS_DIR}/swift-typescript-boundary.jsonl" \
  "${RESULTS_DIR}/generated.instant.schema.ts" \
  "${RESULTS_DIR}/generated.instant.perms.ts"
rm -rf "${RESULTS_DIR}/transport-contract-home"
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

resolve_node() {
  if [[ -n "${INSTANT_SWIFT_DATA_NODE:-}" ]]; then
    if [[ -x "${INSTANT_SWIFT_DATA_NODE}" ]]; then
      printf '%s\n' "${INSTANT_SWIFT_DATA_NODE}"
      return 0
    fi
    return 2
  fi

  if command -v node >/dev/null 2>&1; then
    command -v node
    return 0
  fi

  if [[ -n "${HOME:-}" ]]; then
    local bundled_node="${HOME}/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
    if [[ -x "${bundled_node}" ]]; then
      printf '%s\n' "${bundled_node}"
      return 0
    fi
  fi

  return 1
}

log_json "start" true "$(json_object "resultsDir" "${RESULTS_DIR}")"

missing_required_file=false
for required_file in \
  "${ROOT}/validation/fixtures/schema.swift" \
  "${ROOT}/validation/fixtures/instant.schema.ts" \
  "${ROOT}/validation/fixtures/instant.perms.ts" \
  "${ROOT}/validation/ts-runner/package.json" \
  "${ROOT}/validation/run-macro-tests.sh" \
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

log_json "swift-schema-fixtures-start" true
if (
  cd "${ROOT}"
  swift run instant-swift-data schema generate \
    --example validation \
    --to "${RESULTS_DIR}/generated.instant.schema.ts" \
    --json
) | tee "${RESULTS_DIR}/swift-schema-generate.json"; then
  log_json "swift-schema-generate-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-schema-generate.json")"
else
  status=$?
  log_json \
    "swift-schema-generate-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-schema-generate.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-schema-generate","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

if (
  cd "${ROOT}"
  swift run instant-swift-data perms generate \
    --example validation \
    --to "${RESULTS_DIR}/generated.instant.perms.ts" \
    --json
) | tee "${RESULTS_DIR}/swift-perms-generate.json"; then
  log_json "swift-perms-generate-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-perms-generate.json")"
else
  status=$?
  log_json \
    "swift-perms-generate-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-perms-generate.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-perms-generate","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

if (
  cd "${ROOT}"
  swift run instant-swift-data schema verify \
    --example validation \
    --from validation/fixtures/instant.schema.ts \
    --json
) | tee "${RESULTS_DIR}/swift-schema-verify.json"; then
  log_json "swift-schema-verify-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-schema-verify.json")"
else
  status=$?
  log_json \
    "swift-schema-verify-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-schema-verify.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-schema-verify","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

if (
  cd "${ROOT}"
  swift run instant-swift-data perms verify \
    --example validation \
    --from validation/fixtures/instant.perms.ts \
    --json
) | tee "${RESULTS_DIR}/swift-perms-verify.json"; then
  log_json "swift-perms-verify-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-perms-verify.json")"
else
  status=$?
  log_json \
    "swift-perms-verify-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-perms-verify.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-perms-verify","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

if (
  cd "${ROOT}"
  swift run instant-swift-data schema verify \
    --example validation \
    --from "${RESULTS_DIR}/generated.instant.schema.ts" \
    --json
) | tee "${RESULTS_DIR}/swift-generated-schema-verify.json"; then
  log_json "swift-generated-schema-verify-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-generated-schema-verify.json")"
else
  status=$?
  log_json \
    "swift-generated-schema-verify-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-generated-schema-verify.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-generated-schema-verify","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

if (
  cd "${ROOT}"
  swift run instant-swift-data perms verify \
    --example validation \
    --from "${RESULTS_DIR}/generated.instant.perms.ts" \
    --json
) | tee "${RESULTS_DIR}/swift-generated-perms-verify.json"; then
  log_json "swift-generated-perms-verify-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-generated-perms-verify.json")"
else
  status=$?
  log_json \
    "swift-generated-perms-verify-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-generated-perms-verify.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-generated-perms-verify","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi
log_json "swift-schema-fixtures-complete" true "$(json_object "resultsDir" "${RESULTS_DIR}")"

log_json "swift-macro-tests-start" true
if (
  cd "${ROOT}"
  validation/run-macro-tests.sh
) 2>&1 | tee "${RESULTS_DIR}/swift-macro-tests.log"; then
  log_json "swift-macro-tests-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-macro-tests.log")"
else
  status=$?
  log_json \
    "swift-macro-tests-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-macro-tests.log" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-macro-tests","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
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

log_json "swift-server-transaction-loopback-start" true
if (
  cd "${ROOT}"
  swift run instant-swift-data-validation-runner --server-transaction-loopback
) | tee "${RESULTS_DIR}/swift-server-transaction-loopback.jsonl"; then
  log_json "swift-server-transaction-loopback-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-server-transaction-loopback.jsonl")"
else
  status=$?
  log_json \
    "swift-server-transaction-loopback-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-server-transaction-loopback.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-server-transaction-loopback","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-cloudkit-demo-start" true
if (
  cd "${ROOT}"
  swift run instant-swift-data-validation-runner --cloudkit-demo
) | tee "${RESULTS_DIR}/swift-cloudkit-demo.jsonl"; then
  log_json "swift-cloudkit-demo-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-cloudkit-demo.jsonl")"
else
  status=$?
  log_json \
    "swift-cloudkit-demo-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-cloudkit-demo.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-cloudkit-demo","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-live-session-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${REMOTE_VALIDATION_APP_ID}" swift run instant-swift-data validation live-session --jsonl
) | tee "${RESULTS_DIR}/swift-live-session.jsonl"; then
  log_json "swift-live-session-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-live-session.jsonl")"
else
  status=$?
  log_json \
    "swift-live-session-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-live-session.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-live-session","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-live-transaction-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${REMOTE_VALIDATION_APP_ID}" swift run instant-swift-data validation live-transaction --jsonl
) | tee "${RESULTS_DIR}/swift-live-transaction.jsonl"; then
  log_json "swift-live-transaction-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-live-transaction.jsonl")"
else
  status=$?
  log_json \
    "swift-live-transaction-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-live-transaction.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-live-transaction","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-live-observe-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${REMOTE_VALIDATION_APP_ID}" swift run instant-swift-data validation live-observe --jsonl
) | tee "${RESULTS_DIR}/swift-live-observe.jsonl"; then
  log_json "swift-live-observe-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-live-observe.jsonl")"
else
  status=$?
  log_json \
    "swift-live-observe-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-live-observe.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-live-observe","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

log_json "swift-reminders-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" swift run instant-swift-data validation reminders --jsonl
) | tee "${RESULTS_DIR}/swift-reminders.jsonl"; then
  log_json "swift-reminders-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-reminders.jsonl")"
else
  status=$?
  log_json \
    "swift-reminders-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-reminders.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-reminders","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
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

log_json "swift-coverage-start" true
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" swift run instant-swift-data validation coverage --jsonl
) | tee "${RESULTS_DIR}/swift-coverage.jsonl"; then
  log_json "swift-coverage-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-coverage.jsonl")"
else
  status=$?
  log_json \
    "swift-coverage-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-coverage.jsonl" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-coverage","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
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

TRANSPORT_CONTRACT_HOME="${RESULTS_DIR}/transport-contract-home"
log_json "swift-transport-contract-start" true "$(json_object "home" "${TRANSPORT_CONTRACT_HOME}")"
if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" \
    INSTANT_SWIFT_DATA_HOME="${TRANSPORT_CONTRACT_HOME}" \
    swift run instant-swift-data admin transact validationTransport contract-note \
      --merge '{"done":false,"title":"Swift transport contract"}' \
      --transaction-id validation-transport-contract \
      --json
) | tee "${RESULTS_DIR}/swift-transport-contract-transact.json"; then
  log_json "swift-transport-contract-transact-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-transport-contract-transact.json")"
else
  status=$?
  log_json \
    "swift-transport-contract-transact-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-transport-contract-transact.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-transport-contract-transact","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

if (
  cd "${ROOT}"
  INSTANT_APP_ID="${VALIDATION_APP_ID}" \
    INSTANT_SWIFT_DATA_HOME="${TRANSPORT_CONTRACT_HOME}" \
    swift run instant-swift-data outbox transport --json
) | tee "${RESULTS_DIR}/swift-transport-contract.json"; then
  log_json "swift-transport-contract-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-transport-contract.json")"
else
  status=$?
  log_json \
    "swift-transport-contract-failed" \
    false \
    "$(json_failure_details "${RESULTS_DIR}/swift-transport-contract.json" "${status}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"swift-transport-contract","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
  exit "${status}"
fi

NODE_EXECUTABLE=""
if NODE_EXECUTABLE="$(resolve_node)"; then
  log_json "typescript-fixtures-start" true "$(json_object "node" "${NODE_EXECUTABLE}")"
  if (
    cd "${ROOT}"
    VALIDATION_APP_ID="${VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts --fixtures --app-id "${VALIDATION_APP_ID}"
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

  log_json "typescript-transport-contract-start" true "$(json_object "path" "${RESULTS_DIR}/swift-transport-contract.json")"
  if (
    cd "${ROOT}"
    VALIDATION_APP_ID="${VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts \
      --swift-transport-contract "${RESULTS_DIR}/swift-transport-contract.json" \
      --app-id "${VALIDATION_APP_ID}"
  ) | tee "${RESULTS_DIR}/typescript-transport-contract.jsonl"; then
    log_json "typescript-transport-contract-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-transport-contract.jsonl")"
  else
    status=$?
    log_json \
      "typescript-transport-contract-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/typescript-transport-contract.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"typescript-transport-contract","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi

  log_json "typescript-local-integrations-contract-start" true "$(json_object "path" "${RESULTS_DIR}/swift-local-integrations.jsonl")"
  if (
    cd "${ROOT}"
    VALIDATION_APP_ID="${VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts \
      --swift-local-integrations-contract "${RESULTS_DIR}/swift-local-integrations.jsonl" \
      --app-id "${VALIDATION_APP_ID}"
  ) | tee "${RESULTS_DIR}/typescript-local-integrations-contract.jsonl"; then
    log_json "typescript-local-integrations-contract-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-local-integrations-contract.jsonl")"
  else
    status=$?
    log_json \
      "typescript-local-integrations-contract-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/typescript-local-integrations-contract.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"typescript-local-integrations-contract","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi

  log_json "typescript-live-session-contract-start" true "$(json_object "path" "${RESULTS_DIR}/swift-live-session.jsonl")"
  if (
    cd "${ROOT}"
    VALIDATION_APP_ID="${REMOTE_VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts \
      --swift-live-session-contract "${RESULTS_DIR}/swift-live-session.jsonl" \
      --app-id "${REMOTE_VALIDATION_APP_ID}"
  ) | tee "${RESULTS_DIR}/typescript-live-session-contract.jsonl"; then
    log_json "typescript-live-session-contract-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-live-session-contract.jsonl")"
  else
    status=$?
    log_json \
      "typescript-live-session-contract-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/typescript-live-session-contract.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"typescript-live-session-contract","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi

  log_json "typescript-live-transaction-contract-start" true "$(json_object "path" "${RESULTS_DIR}/swift-live-transaction.jsonl")"
  if (
    cd "${ROOT}"
    VALIDATION_APP_ID="${REMOTE_VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts \
      --swift-live-transaction-contract "${RESULTS_DIR}/swift-live-transaction.jsonl" \
      --app-id "${REMOTE_VALIDATION_APP_ID}"
  ) | tee "${RESULTS_DIR}/typescript-live-transaction-contract.jsonl"; then
    log_json "typescript-live-transaction-contract-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-live-transaction-contract.jsonl")"
  else
    status=$?
    log_json \
      "typescript-live-transaction-contract-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/typescript-live-transaction-contract.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"typescript-live-transaction-contract","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi

  log_json "typescript-server-transaction-contract-start" true "$(json_object "path" "${RESULTS_DIR}/typescript-server-transaction-contract.json")"
  if (
    cd "${ROOT}"
    VALIDATION_APP_ID="${VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts \
      --typescript-server-transaction-contract "${RESULTS_DIR}/typescript-server-transaction-contract.json" \
      --app-id "${VALIDATION_APP_ID}"
  ) | tee "${RESULTS_DIR}/typescript-server-transaction-contract.jsonl"; then
    log_json "typescript-server-transaction-contract-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-server-transaction-contract.jsonl")"
  else
    status=$?
    log_json \
      "typescript-server-transaction-contract-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/typescript-server-transaction-contract.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"typescript-server-transaction-contract","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi

  log_json "swift-typescript-server-transaction-contract-start" true "$(json_object "path" "${RESULTS_DIR}/typescript-server-transaction-contract.json")"
  if (
    cd "${ROOT}"
    INSTANT_APP_ID="${VALIDATION_APP_ID}" \
      INSTANT_SWIFT_DATA_TYPESCRIPT_SERVER_TRANSACTION_CONTRACT="${RESULTS_DIR}/typescript-server-transaction-contract.json" \
      swift run instant-swift-data validation server-transaction-loopback --jsonl
  ) | tee "${RESULTS_DIR}/swift-typescript-server-transaction-contract.jsonl"; then
    log_json "swift-typescript-server-transaction-contract-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-typescript-server-transaction-contract.jsonl")"
  else
    status=$?
    log_json \
      "swift-typescript-server-transaction-contract-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/swift-typescript-server-transaction-contract.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"swift-typescript-server-transaction-contract","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi

  boundary_mode=--boundary-preflight
  if [[ "${REQUIRE_REMOTE_PREFLIGHT}" == "1" ]]; then
    boundary_mode=--boundary-admin-smoke
  fi
  boundary_args=("${boundary_mode}" --app-id "${REMOTE_VALIDATION_APP_ID}")
  if [[ "${REQUIRE_REMOTE_PREFLIGHT}" == "1" ]]; then
    boundary_args+=(--require-boundary)
  fi
  required_remote_preflight_json=false
  if [[ "${REQUIRE_REMOTE_PREFLIGHT}" == "1" ]]; then
    required_remote_preflight_json=true
  fi
  log_json \
    "typescript-boundary-preflight-start" \
    true \
    "$(printf '{"remoteAppID":%s,"required":%s,"mode":%s}' "$(json_string "${REMOTE_VALIDATION_APP_ID}")" "${required_remote_preflight_json}" "$(json_string "${boundary_mode}")")"
  if (
    cd "${ROOT}"
    INSTANT_APP_ID="${REMOTE_VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts "${boundary_args[@]}"
  ) | tee "${RESULTS_DIR}/typescript-boundary.jsonl"; then
    log_json "typescript-boundary-preflight-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-boundary.jsonl")"
  else
    status=$?
    log_json \
      "typescript-boundary-preflight-failed" \
      false \
      "$(json_failure_details "${RESULTS_DIR}/typescript-boundary.jsonl" "${status}")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"typescript-boundary-preflight","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
    exit "${status}"
  fi

  if [[ "${RUN_LIVE_BOUNDARY}" == "1" ]]; then
    log_json \
      "typescript-swift-boundary-start" \
      true \
      "$(json_object "remoteAppID" "${REMOTE_VALIDATION_APP_ID}")"
    if (
      cd "${ROOT}"
      INSTANT_APP_ID="${REMOTE_VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts \
        --boundary-swift-live-observe \
        --app-id "${REMOTE_VALIDATION_APP_ID}" \
        --require-boundary
    ) | tee "${RESULTS_DIR}/typescript-swift-boundary.jsonl"; then
      log_json "typescript-swift-boundary-complete" true "$(json_object "path" "${RESULTS_DIR}/typescript-swift-boundary.jsonl")"
    else
      status=$?
      log_json \
        "typescript-swift-boundary-failed" \
        false \
        "$(json_failure_details "${RESULTS_DIR}/typescript-swift-boundary.jsonl" "${status}")"
      log_json \
        "complete" \
        false \
        "$(printf '{"resultsDir":%s,"failed":"typescript-swift-boundary","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
      exit "${status}"
    fi
  fi

  if [[ "${RUN_TYPESCRIPT_LIVE_BOUNDARY}" == "1" ]]; then
    log_json \
      "swift-typescript-boundary-start" \
      true \
      "$(json_object "remoteAppID" "${REMOTE_VALIDATION_APP_ID}")"
    if (
      cd "${ROOT}"
      INSTANT_APP_ID="${REMOTE_VALIDATION_APP_ID}" "${NODE_EXECUTABLE}" validation/ts-runner/src/main.ts \
        --boundary-typescript-live-observe \
        --app-id "${REMOTE_VALIDATION_APP_ID}" \
        --require-boundary
    ) | tee "${RESULTS_DIR}/swift-typescript-boundary.jsonl"; then
      log_json "swift-typescript-boundary-complete" true "$(json_object "path" "${RESULTS_DIR}/swift-typescript-boundary.jsonl")"
    else
      status=$?
      log_json \
        "swift-typescript-boundary-failed" \
        false \
        "$(json_failure_details "${RESULTS_DIR}/swift-typescript-boundary.jsonl" "${status}")"
      log_json \
        "complete" \
        false \
        "$(printf '{"resultsDir":%s,"failed":"swift-typescript-boundary","exitCode":%s}' "$(json_string "${RESULTS_DIR}")" "${status}")"
      exit "${status}"
    fi
  fi
elif [[ -n "${INSTANT_SWIFT_DATA_NODE:-}" ]]; then
  log_json "missing-node" false "$(json_object "path" "${INSTANT_SWIFT_DATA_NODE}")"
  log_json \
    "complete" \
    false \
    "$(printf '{"resultsDir":%s,"failed":"missing-node"}' "$(json_string "${RESULTS_DIR}")")"
  echo "INSTANT_SWIFT_DATA_NODE must point to an executable Node.js binary." >&2
  exit 1
else
  if [[ "${RUN_LIVE_BOUNDARY}" == "1" || "${RUN_TYPESCRIPT_LIVE_BOUNDARY}" == "1" ]]; then
    log_json "missing-node" false "$(json_object "reason" "Requested live TypeScript boundary validation requires Node.js")"
    log_json \
      "complete" \
      false \
      "$(printf '{"resultsDir":%s,"failed":"missing-node"}' "$(json_string "${RESULTS_DIR}")")"
    echo "Live TypeScript boundary validation requires Node.js; set INSTANT_SWIFT_DATA_NODE or add node to PATH." >&2
    exit 1
  fi
  log_json "typescript-boundary-skipped" true "$(json_object "reason" "node is not available; set INSTANT_SWIFT_DATA_NODE to run TypeScript fixture validation")"
fi

log_json "complete" true "$(json_object "resultsDir" "${RESULTS_DIR}")"
