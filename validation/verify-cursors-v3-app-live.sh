#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS="${INSTANT_SWIFT_DATA_CURSORS_RESULTS_DIR:-/tmp/instant-data-swift-cursors-v3-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH="${RESULTS}/push"
PULL="${RESULTS}/pull"
GETADB_CREDENTIALS_FILE="${INSTANT_GETADB_CREDENTIALS_FILE:-}"
REMOVE_GETADB_CREDENTIALS=0

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Cursors V3 verification requires a clean worktree." >&2
  exit 1
fi
if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI." >&2
  exit 1
fi

EXPECTED_REVISION="$(cd "${RUNNER}" && node -p "require('./package.json').instantContract.upstreamRevision")"
UPSTREAM_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
if [[ "${UPSTREAM_REVISION}" != "${EXPECTED_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch." >&2
  exit 1
fi

export CI=1
export NO_COLOR=1
mkdir -p "${PUSH}" "${PULL}"
if [[ -z "${GETADB_CREDENTIALS_FILE}" ]]; then
  GETADB_PROVISION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  GETADB_CREDENTIALS_FILE="${RESULTS}/getadb-${GETADB_PROVISION_ID}.txt"
  curl -fsSL "https://www.getadb.com/provision/${GETADB_PROVISION_ID}" \
    >"${GETADB_CREDENTIALS_FILE}"
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

swift run --package-path "${ROOT}" instant-swift-data schema generate \
  --example cursors --to "${PUSH}/instant.schema.ts" --json \
  >"${RESULTS}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example cursors --to "${PUSH}/instant.perms.ts" --json \
  >"${RESULTS}/swift-perms-generate.json"

printf 'Provisioned Cursors V3 app through getadb.com (%s).\n' \
  "${GETADB_PROVISION_ID}" | tee "${RESULTS}/getadb-provision.log"

(
  cd "${PUSH}"
  "${CLI}" push schema --yes
  "${CLI}" push perms --yes
) | tee "${RESULTS}/instant-cli-push.log"
(
  cd "${PUSH}"
  "${CLI}" push schema --yes
  "${CLI}" push perms --yes
) | tee "${RESULTS}/instant-cli-push-no-drift.log"
(
  cd "${PULL}"
  "${CLI}" pull schema --yes
  "${CLI}" pull perms --yes
) | tee "${RESULTS}/instant-cli-pull.log"

swift run --package-path "${ROOT}" instant-swift-data schema verify \
  --example cursors --from "${PULL}/instant.schema.ts" --json \
  >"${RESULTS}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example cursors --from "${PULL}/instant.perms.ts" --json \
  >"${RESULTS}/swift-server-perms-verify.json"
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --strict --target ES2022 \
  --module NodeNext --moduleResolution NodeNext \
  "${PULL}/instant.schema.ts" "${PULL}/instant.perms.ts"

INSTANT_SWIFT_DATA_CURSORS_SCHEMA_PATH="${PUSH}/instant.schema.ts" \
  corepack pnpm --dir "${RUNNER}" exec tsx src/cursors-v3-live-contract.ts \
  >"${RESULTS}/cursors-v3.json"

ROOT="${ROOT}" RUNNER="${RUNNER}" RESULTS="${RESULTS}" \
UPSTREAM_REVISION="${UPSTREAM_REVISION}" node --input-type=module <<'NODE' \
  | tee "${RESULTS}/evidence.json"
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const results = process.env.RESULTS;
const read = (name) => JSON.parse(readFileSync(resolve(results, name), "utf8"));
const schema = read("swift-server-schema-verify.json");
const permissions = read("swift-server-perms-verify.json");
const live = read("cursors-v3.json");
const manifest = JSON.parse(readFileSync(resolve(process.env.RUNNER, "package.json"), "utf8"));
const serializedLive = JSON.stringify(live);
assert.equal(live.ok, true);
assert.equal(serializedLive.includes("refresh_token"), false);
assert.equal(serializedLive.includes("INSTANT_ADMIN_TOKEN"), false);
assert.deepEqual(live.details.swift.publishedCursor, {
  x: 150,
  y: 90,
  xPercent: 25,
  yPercent: 40,
  color: "#123456",
});
assert.deepEqual(live.details.swift.observedCursor, {
  x: 300,
  y: 200,
  xPercent: 75,
  yPercent: 60,
  color: "#654321",
});
assert.equal(live.details.swift.remoteCursorCount, 1);
assert.equal(live.details.swift.remoteCursorCountAfterClear, 0);
assert.equal(live.details.swift.remotePeerCountAfterDisconnect, 0);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepEqual(live.details.warnings, []);
assert.equal(schema.entityCount, 0);
assert.equal(schema.linkCount, 0);
assert.equal(permissions.namespaceCount, 0);
assert.equal(permissions.allowRuleCount, 0);
assert.equal(permissions.rateLimitCount, 0);

const evidence = {
  case: "validation.cursors-v3-app.live-contract",
  event: "bidirectional-sdk-summary",
  appID: process.env.INSTANT_APP_ID,
  ok: true,
  details: {
    swiftRevision: execFileSync(
      "git",
      ["-C", process.env.ROOT, "rev-parse", "HEAD"],
      { encoding: "utf8" },
    ).trim(),
    worktreeDirty: false,
    upstreamRevision: process.env.UPSTREAM_REVISION,
    coreVersion: manifest.dependencies["@instantdb/core"],
    adminVersion: manifest.dependencies["@instantdb/admin"],
    cliVersion: manifest.devDependencies["instant-cli"],
    typescriptVersion: manifest.devDependencies.typescript,
    compilerWarningCount: 0,
    schema: {
      entityCount: schema.entityCount,
      linkCount: schema.linkCount,
      warnings: schema.warnings,
      sha256: createHash("sha256")
        .update(readFileSync(resolve(results, "pull/instant.schema.ts")))
        .digest("hex"),
    },
    permissions: {
      namespaceCount: permissions.namespaceCount,
      allowRuleCount: permissions.allowRuleCount,
      rateLimitCount: permissions.rateLimitCount,
      sha256: createHash("sha256")
        .update(readFileSync(resolve(results, "pull/instant.perms.ts")))
        .digest("hex"),
    },
    cursors: live.details,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Cursors V3 evidence: ${RESULTS}/evidence.json"
