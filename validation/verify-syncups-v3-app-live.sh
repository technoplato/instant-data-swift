#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS="${INSTANT_SWIFT_DATA_SYNCUPS_RESULTS_DIR:-/tmp/instant-data-swift-syncups-v3-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH="${RESULTS}/push"
PULL="${RESULTS}/pull"
GETADB_CREDENTIALS_FILE="${INSTANT_GETADB_CREDENTIALS_FILE:-}"
REMOVE_GETADB_CREDENTIALS=0
EXPECTED_SQLITE_DATA_REVISION="0c79d7a5748fc6d9ce7a1ba2b50f31b175305049"
EXPECTED_INSTANT_REVISION="$(
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
)"
SQLITE_DATA_REVISION="$(git -C "${ROOT}/upstream/sqlite-data" rev-parse HEAD)"
INSTANT_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "SyncUps V3 verification requires a clean worktree." >&2
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
  --example syncups --to "${PUSH}/instant.schema.ts" --json \
  >"${RESULTS}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example syncups --to "${PUSH}/instant.perms.ts" --json \
  >"${RESULTS}/swift-perms-generate.json"

printf 'Provisioned SyncUps V3 app through getadb.com (%s).\n' \
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
  --example syncups --from "${PULL}/instant.schema.ts" --json \
  >"${RESULTS}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example syncups --from "${PULL}/instant.perms.ts" --json \
  >"${RESULTS}/swift-server-perms-verify.json"
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --strict --target ES2022 \
  --module NodeNext --moduleResolution NodeNext \
  "${PULL}/instant.schema.ts" "${PULL}/instant.perms.ts"

INSTANT_SWIFT_DATA_SYNCUPS_SCHEMA_PATH="${PUSH}/instant.schema.ts" \
  corepack pnpm --dir "${RUNNER}" exec tsx src/syncups-v3-live-contract.ts \
  >"${RESULTS}/syncups-v3.json"

ROOT="${ROOT}" RUNNER="${RUNNER}" RESULTS="${RESULTS}" \
SQLITE_DATA_REVISION="${SQLITE_DATA_REVISION}" \
INSTANT_REVISION="${INSTANT_REVISION}" node --input-type=module <<'NODE' \
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
const live = read("syncups-v3.json");
const manifest = JSON.parse(readFileSync(resolve(process.env.RUNNER, "package.json"), "utf8"));
const serializedLive = JSON.stringify(live);
const syncUpID = "00000000-0000-4000-8000-000000000501";
const swiftAttendeeID = "00000000-0000-4000-8000-000000000502";
const swiftMeetingID = "00000000-0000-4000-8000-000000000503";
const typeScriptAttendeeID = "00000000-0000-4000-8000-000000000504";
const typeScriptMeetingID = "00000000-0000-4000-8000-000000000505";

assert.equal(live.ok, true);
assert.equal(serializedLive.includes("refresh_token"), false);
assert.equal(serializedLive.includes("INSTANT_ADMIN_TOKEN"), false);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepEqual(live.details.warnings, []);

const swiftGraph = live.details.typeScriptObservedSwiftGraph;
assert.equal(swiftGraph.id, syncUpID);
assert.equal(swiftGraph.title, "Design");
assert.equal(swiftGraph.seconds, 300);
assert.equal(swiftGraph.theme, "appOrange");
assert.deepEqual(swiftGraph.attendees, [
  { id: swiftAttendeeID, name: "Blob" },
]);
assert.deepEqual(swiftGraph.meetings, [
  {
    id: swiftMeetingID,
    date: "2026-07-19T13:20:00.000Z",
    transcript: "Reviewed launch risks.",
  },
]);

const finalGraph = live.details.typeScriptObservedFinalGraph;
assert.equal(finalGraph.id, syncUpID);
assert.equal(finalGraph.title, "Design updated by TypeScript");
assert.equal(finalGraph.seconds, 300);
assert.equal(finalGraph.theme, "appOrange");
assert.deepEqual(
  [...finalGraph.attendees].sort((lhs, rhs) => lhs.id.localeCompare(rhs.id)),
  [
    { id: swiftAttendeeID, name: "Blob" },
    { id: typeScriptAttendeeID, name: "Blob Jr" },
  ],
);
assert.deepEqual(
  [...finalGraph.meetings].sort((lhs, rhs) => lhs.id.localeCompare(rhs.id)),
  [
    {
      id: swiftMeetingID,
      date: "2026-07-19T13:20:00.000Z",
      transcript: "Reviewed launch risks.",
    },
    {
      id: typeScriptMeetingID,
      date: "2026-07-19T13:20:01.000Z",
      transcript: "TypeScript follow-up notes.",
    },
  ],
);

assert.equal(live.details.swift.syncUpID, syncUpID);
assert.equal(live.details.swift.title, "Design updated by TypeScript");
assert.equal(live.details.swift.seconds, 300);
assert.equal(live.details.swift.theme, "appOrange");
assert.equal(live.details.swift.connectionState, "authenticated");
assert.equal(live.details.swift.pendingMutationCount, 0);
assert.deepEqual(live.details.swift.attendeeIDs, [swiftAttendeeID, typeScriptAttendeeID]);
assert.deepEqual(live.details.swift.attendeeNames, ["Blob", "Blob Jr"]);
assert.deepEqual(
  [...live.details.swift.meetings].sort((lhs, rhs) => lhs.id.localeCompare(rhs.id)),
  [
    {
      id: swiftMeetingID,
      dateMilliseconds: 1_784_467_200_000,
      transcript: "Reviewed launch risks.",
    },
    {
      id: typeScriptMeetingID,
      dateMilliseconds: 1_784_467_201_000,
      transcript: "TypeScript follow-up notes.",
    },
  ],
);

assert.equal(schema.entityCount, 3);
assert.equal(schema.attributeCount, 9);
assert.equal(schema.linkCount, 2);
assert.deepEqual(schema.warnings, [
  { code: "system-entity", path: "$files" },
  { code: "system-entity", path: "$streams" },
  { code: "system-entity", path: "$users" },
  { code: "system-link", path: "$streams$files" },
  { code: "system-link", path: "$usersLinkedPrimaryUser" },
]);
assert.equal(permissions.namespaceCount, 3);
assert.equal(permissions.allowRuleCount, 12);
assert.equal(permissions.rateLimitCount, 0);
assert.deepEqual(permissions.warnings, []);

const evidence = {
  case: "validation.syncups-v3-app.live-contract",
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
    sqliteDataRevision: process.env.SQLITE_DATA_REVISION,
    instantRevision: process.env.INSTANT_REVISION,
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
      warnings: permissions.warnings,
      sha256: createHash("sha256")
        .update(readFileSync(resolve(results, "pull/instant.perms.ts")))
        .digest("hex"),
    },
    syncUps: live.details,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "SyncUps V3 evidence: ${RESULTS}/evidence.json"
