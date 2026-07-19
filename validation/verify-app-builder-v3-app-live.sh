#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS="${INSTANT_SWIFT_DATA_APP_BUILDER_RESULTS_DIR:-/tmp/instant-data-swift-app-builder-v3-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH="${RESULTS}/push"
PULL="${RESULTS}/pull"
GETADB_CREDENTIALS_FILE="${INSTANT_GETADB_CREDENTIALS_FILE:-}"
REMOVE_GETADB_CREDENTIALS=0
EXPECTED_SQLITE_DATA_REVISION="0c79d7a5748fc6d9ce7a1ba2b50f31b175305049"
EXPECTED_INSTANT_REVISION="$(cd "${RUNNER}" && node -p "require('./package.json').instantContract.upstreamRevision")"
SQLITE_DATA_REVISION="$(git -C "${ROOT}/upstream/sqlite-data" rev-parse HEAD)"
INSTANT_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "App Builder V3 verification requires a clean worktree." >&2
  exit 1
fi
if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI." >&2
  exit 1
fi
if [[ "${SQLITE_DATA_REVISION}" != "${EXPECTED_SQLITE_DATA_REVISION}" ]]; then
  echo "Pinned SQLiteData revision mismatch." >&2
  exit 1
fi
if [[ "${INSTANT_REVISION}" != "${EXPECTED_INSTANT_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch." >&2
  exit 1
fi

export CI=1
export NO_COLOR=1
mkdir -p "${PUSH}" "${PULL}"
if [[ -z "${GETADB_CREDENTIALS_FILE}" ]]; then
  GETADB_PROVISION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  GETADB_CREDENTIALS_FILE="${RESULTS}/getadb-${GETADB_PROVISION_ID}.txt"
  curl -fsSL "https://www.getadb.com/provision/${GETADB_PROVISION_ID}" >"${GETADB_CREDENTIALS_FILE}"
  chmod 600 "${GETADB_CREDENTIALS_FILE}"
  REMOVE_GETADB_CREDENTIALS=1
else
  GETADB_PROVISION_ID="provided"
fi
trap 'if [[ "${REMOVE_GETADB_CREDENTIALS}" == 1 ]]; then rm -f "${GETADB_CREDENTIALS_FILE}"; fi; unlink "${PUSH}/node_modules" 2>/dev/null || true; unlink "${PULL}/node_modules" 2>/dev/null || true' EXIT

export INSTANT_APP_ID="$(sed -n 's/^VITE_INSTANT_APP_ID=//p' "${GETADB_CREDENTIALS_FILE}" | head -1)"
export INSTANT_ADMIN_TOKEN="$(sed -n 's/^INSTANT_ADMIN_TOKEN=//p' "${GETADB_CREDENTIALS_FILE}" | head -1)"
: "${INSTANT_APP_ID:?getadb response did not contain VITE_INSTANT_APP_ID}"
: "${INSTANT_ADMIN_TOKEN:?getadb response did not contain INSTANT_ADMIN_TOKEN}"
export INSTANT_APP_ADMIN_TOKEN="${INSTANT_ADMIN_TOKEN}"
export INSTANT_CLI_AUTH_TOKEN="${INSTANT_ADMIN_TOKEN}"

cp "${RUNNER}/package.json" "${PUSH}/package.json"
cp "${RUNNER}/package.json" "${PULL}/package.json"
ln -s "${RUNNER}/node_modules" "${PUSH}/node_modules"
ln -s "${RUNNER}/node_modules" "${PULL}/node_modules"

swift run --package-path "${ROOT}" instant-swift-data schema generate --example app-builder --to "${PUSH}/instant.schema.ts" --json >"${RESULTS}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate --example app-builder --to "${PUSH}/instant.perms.ts" --json >"${RESULTS}/swift-perms-generate.json"
printf 'Provisioned App Builder V3 app through getadb.com (%s).\n' "${GETADB_PROVISION_ID}" | tee "${RESULTS}/getadb-provision.log"

(cd "${PUSH}" && "${CLI}" push schema --yes && "${CLI}" push perms --yes) | tee "${RESULTS}/instant-cli-push.log"
(cd "${PUSH}" && "${CLI}" push schema --yes && "${CLI}" push perms --yes) | tee "${RESULTS}/instant-cli-push-no-drift.log"
(cd "${PULL}" && "${CLI}" pull schema --yes && "${CLI}" pull perms --yes) | tee "${RESULTS}/instant-cli-pull.log"

swift run --package-path "${ROOT}" instant-swift-data schema verify --example app-builder --from "${PULL}/instant.schema.ts" --json >"${RESULTS}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify --example app-builder --from "${PULL}/instant.perms.ts" --json >"${RESULTS}/swift-server-perms-verify.json"
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --strict --target ES2022 --module NodeNext --moduleResolution NodeNext "${PULL}/instant.schema.ts" "${PULL}/instant.perms.ts"

INSTANT_SWIFT_DATA_APP_BUILDER_SCHEMA_PATH="${PUSH}/instant.schema.ts" corepack pnpm --dir "${RUNNER}" exec tsx src/app-builder-v3-live-contract.ts >"${RESULTS}/app-builder-v3.json"

export INSTANT_SWIFT_DATA_EVIDENCE_ROOT="${ROOT}"
export INSTANT_SWIFT_DATA_EVIDENCE_RESULTS="${RESULTS}"
export INSTANT_SWIFT_DATA_EVIDENCE_SQLITE_REVISION="${SQLITE_DATA_REVISION}"
export INSTANT_SWIFT_DATA_EVIDENCE_INSTANT_REVISION="${INSTANT_REVISION}"
corepack pnpm --dir "${RUNNER}" exec tsx src/app-builder-v3-evidence.ts | tee "${RESULTS}/evidence.json"

echo "App Builder V3 evidence: ${RESULTS}/evidence.json"
