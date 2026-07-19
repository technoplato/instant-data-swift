#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS="${INSTANT_SWIFT_DATA_STROOPWAFEL_RESULTS_DIR:-/tmp/instant-data-swift-stroopwafel-v3-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH="${RESULTS}/push"
PULL="${RESULTS}/pull"
GETADB_CREDENTIALS_FILE="${INSTANT_GETADB_CREDENTIALS_FILE:-}"
REMOVE_GETADB_CREDENTIALS=0
UPSTREAM_REVISION="7f5e2379464d932c0e4681655cbf022f8d9c2614"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Stroopwafel V3 verification requires a clean worktree." >&2
  exit 1
fi
if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI." >&2
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
  --example stroopwafel --to "${PUSH}/instant.schema.ts" --json \
  >"${RESULTS}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example stroopwafel --to "${PUSH}/instant.perms.ts" --json \
  >"${RESULTS}/swift-perms-generate.json"

printf 'Provisioned Stroopwafel V3 app through getadb.com (%s).\n' \
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
  --example stroopwafel --from "${PULL}/instant.schema.ts" --json \
  >"${RESULTS}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example stroopwafel --from "${PULL}/instant.perms.ts" --json \
  >"${RESULTS}/swift-server-perms-verify.json"
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --strict --target ES2022 \
  --module NodeNext --moduleResolution NodeNext \
  "${PULL}/instant.schema.ts" "${PULL}/instant.perms.ts"

INSTANT_SWIFT_DATA_STROOPWAFEL_SCHEMA_PATH="${PUSH}/instant.schema.ts" \
  corepack pnpm --dir "${RUNNER}" exec tsx src/stroopwafel-v3-live-contract.ts \
  >"${RESULTS}/stroopwafel-v3.json"

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
const live = read("stroopwafel-v3.json");
const manifest = JSON.parse(readFileSync(resolve(process.env.RUNNER, "package.json"), "utf8"));
const serializedLive = JSON.stringify(live);

assert.equal(live.ok, true);
assert.equal(serializedLive.includes("refresh_token"), false);
assert.equal(serializedLive.includes("INSTANT_ADMIN_TOKEN"), false);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepEqual(live.details.warnings, []);
assert.equal(live.details.typeScriptObservedSwiftGame.colors.length, 14);
assert.equal(live.details.typeScriptObservedCompletedGame.status, "GAME_COMPLETED");
assert.equal(
  live.details.typeScriptObservedCompletedGame.points.find(
    (point) => point.userId === live.details.users.swift.id,
  ).val,
  13,
);
assert.equal(
  live.details.typeScriptObservedCompletedGame.points.find(
    (point) => point.userId === live.details.users.typeScript.id,
  ).val,
  1,
);
assert.equal(
  live.details.typeScriptObservedCompletedGame.rooms[0].currentGameId,
  undefined,
);
assert.equal(live.details.swift.typeScriptPointObservedBySwift.value, 1);
assert.equal(live.details.swift.winningPointValue, 13);
assert.equal(live.details.swift.currentGameIDAfterCompletion, undefined);
assert.equal(live.details.swift.connectionState, "authenticated");
assert.equal(schema.entityCount, 4);
assert.equal(schema.attributeCount, 21);
assert.equal(schema.linkCount, 4);
for (const path of ["rooms.readyIds", "rooms.kickedIds", "games.playerIds", "games.colors"]) {
  assert.ok(
    schema.warnings.some((warning) => (
      warning.code === "server-json-as-any" && warning.path === path
    )),
    `Expected server JSON projection warning for ${path}.`,
  );
}
assert.ok(schema.warnings.every((warning) => (
  warning.code === "server-json-as-any"
  || warning.code === "server-system-string-as-any"
  || warning.code === "system-entity"
  || warning.code === "system-attribute"
  || warning.code === "system-link"
  || warning.code === "canonical-link-name"
)));
assert.equal(permissions.namespaceCount, 4);
assert.equal(permissions.allowRuleCount, 17);
assert.equal(permissions.rateLimitCount, 0);

const evidence = {
  case: "validation.stroopwafel-v3-app.live-contract",
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
      attributeCount: schema.attributeCount,
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
    stroopwafel: live.details,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Stroopwafel V3 evidence: ${RESULTS}/evidence.json"
