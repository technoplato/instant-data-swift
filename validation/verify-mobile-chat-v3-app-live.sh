#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_MOBILE_CHAT_V3_RESULTS_DIR:-/tmp/instant-data-swift-mobile-chat-v3-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"
PULL_DIR="${RESULTS_DIR}/pull"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Mobile Chat V3 app verification requires a clean worktree." >&2
  exit 1
fi
if [[ "${INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION:-}" != "1" ]]; then
  echo "Set INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION=1 for the disposable getadb app." >&2
  exit 1
fi
if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI. Run pnpm install in validation/ts-runner." >&2
  exit 1
fi

APP_ID="${INSTANT_APP_ID:?Missing getadb INSTANT_APP_ID}"
ADMIN_TOKEN="${INSTANT_ADMIN_TOKEN:?Missing getadb INSTANT_ADMIN_TOKEN}"
EXPECTED_UPSTREAM_REVISION="$(
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
)"
UPSTREAM_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
if [[ "${UPSTREAM_REVISION}" != "${EXPECTED_UPSTREAM_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch." >&2
  exit 1
fi

export CI=1
export NO_COLOR=1
export INSTANT_APP_ID="${APP_ID}"
export INSTANT_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_APP_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_CLI_AUTH_TOKEN="${ADMIN_TOKEN}"
export INSTANT_SWIFT_DATA_REMOTE_APP_ID="${APP_ID}"

mkdir -p "${PUSH_DIR}" "${PULL_DIR}"
trap 'unlink "${PUSH_DIR}/.instant.env" 2>/dev/null || true; unlink "${PUSH_DIR}/node_modules" 2>/dev/null || true; unlink "${PULL_DIR}/node_modules" 2>/dev/null || true' EXIT
cp "${RUNNER}/package.json" "${PUSH_DIR}/package.json"
cp "${RUNNER}/package.json" "${PULL_DIR}/package.json"
ln -s "${RUNNER}/node_modules" "${PUSH_DIR}/node_modules"
ln -s "${RUNNER}/node_modules" "${PULL_DIR}/node_modules"
install -m 600 /dev/null "${PUSH_DIR}/.instant.env"
printf 'INSTANT_APP_ID=%s\nINSTANT_APP_ADMIN_TOKEN=%s\n' \
  "${APP_ID}" "${ADMIN_TOKEN}" >"${PUSH_DIR}/.instant.env"

swift run --package-path "${ROOT}" instant-swift-data schema generate \
  --example mobile-chat \
  --to "${PUSH_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example mobile-chat \
  --to "${PUSH_DIR}/instant.perms.ts" \
  --json >"${RESULTS_DIR}/swift-perms-generate.json"

(
  cd "${PUSH_DIR}"
  "${CLI}" push schema --yes
  "${CLI}" push perms --yes
) | tee "${RESULTS_DIR}/instant-cli-push.log"

(
  cd "${PUSH_DIR}"
  "${CLI}" push schema --yes
  "${CLI}" push perms --yes
) | tee "${RESULTS_DIR}/instant-cli-push-no-drift.log"

(
  cd "${PULL_DIR}"
  "${CLI}" pull schema --yes
  "${CLI}" pull perms --yes
) | tee "${RESULTS_DIR}/instant-cli-pull.log"

swift run --package-path "${ROOT}" instant-swift-data schema verify \
  --example mobile-chat \
  --from "${PULL_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example mobile-chat \
  --from "${PULL_DIR}/instant.perms.ts" \
  --json >"${RESULTS_DIR}/swift-server-perms-verify.json"

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
pnpm --dir "${RUNNER}" exec tsc \
  --noEmit \
  --strict \
  --target ES2022 \
  --module NodeNext \
  --moduleResolution NodeNext \
  "${PULL_DIR}/instant.schema.ts" \
  "${PULL_DIR}/instant.perms.ts"

INSTANT_SWIFT_DATA_MOBILE_CHAT_SCHEMA_PATH="${PUSH_DIR}/instant.schema.ts" \
  pnpm --dir "${RUNNER}" exec tsx src/mobile-chat-v3-live-contract.ts \
  >"${RESULTS_DIR}/mobile-chat-v3.json"

ROOT="${ROOT}" \
RUNNER="${RUNNER}" \
RESULTS_DIR="${RESULTS_DIR}" \
APP_ID="${APP_ID}" \
UPSTREAM_REVISION="${UPSTREAM_REVISION}" \
node --input-type=module <<'NODE' | tee "${RESULTS_DIR}/evidence.json"
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = process.env.ROOT;
const runner = process.env.RUNNER;
const results = process.env.RESULTS_DIR;
const readJSON = (name) => JSON.parse(readFileSync(resolve(results, name), "utf8"));
const manifest = JSON.parse(readFileSync(resolve(runner, "package.json"), "utf8"));
const schema = readJSON("swift-server-schema-verify.json");
const permissions = readJSON("swift-server-perms-verify.json");
const live = readJSON("mobile-chat-v3.json");
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

assert.equal(live.ok, true);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepStrictEqual(live.details.warnings, []);
assert.match(live.details.swift.profileID, uuid);
assert.match(live.details.swift.channelID, uuid);
assert.match(live.details.swift.messageID, uuid);
assert.deepStrictEqual(live.details.typeScriptObserved, {
  userID: live.details.swift.userID,
  profileID: live.details.swift.profileID,
  displayName: "Swift Chatter",
  channelID: live.details.swift.channelID,
  channelName: "Swift Channel",
  messageID: live.details.swift.messageID,
  messageChannelID: live.details.swift.channelID,
  authorProfileID: live.details.swift.profileID,
  content: "Swift live message",
  timestampMilliseconds: 1_700_000_010_000,
});
assert.deepStrictEqual(live.details.swiftObserved, {
  direction: "typescript-to-swift",
  ...live.details.typeScriptCreated,
  connectionState: "authenticated",
  pendingMutationCount: 0,
});
assert.deepStrictEqual(live.details.room, {
  observedSwiftPresence: {
    profileId: live.details.swift.profileID,
    displayName: "Swift Chatter",
  },
  observedSwiftTyping: { isTyping: true },
  observedSwiftReaction: { name: "wave", directionAngle: 90, rotationAngle: 180 },
  roomType: "chat",
  roomID: live.details.swift.channelID,
  peerCount: 2,
  presence: {
    profileId: live.details.swift.profileID,
    displayName: "Swift Chatter",
  },
  typing: { isTyping: true },
  emoji: { name: "wave", directionAngle: 90, rotationAngle: 180 },
  peerCountAfterDisconnect: 1,
  receivedPresence: {
    profileId: live.details.typeScriptCreated.profileID,
    displayName: "TypeScript Chatter",
  },
  receivedTyping: { isTyping: false },
  receivedEmoji: { name: "heart", directionAngle: 45, rotationAngle: 270 },
});
assert.equal(live.details.permissions.anonymousCreateRejected, true);
assert.match(live.details.permissions.rejection, /permission|denied|record|auth|400/i);
assert.equal(schema.entityCount, 5);
assert.equal(schema.attributeCount, 14);
assert.equal(schema.linkCount, 4);
assert.deepStrictEqual(schema.warnings, []);
assert.equal(permissions.namespaceCount, 5);
assert.equal(permissions.allowRuleCount, 17);
assert.equal(permissions.rateLimitCount, 0);

const evidence = {
  case: "validation.mobile-chat-v3-app.live-contract",
  event: "bidirectional-sdk-summary",
  appID: process.env.APP_ID,
  ok: true,
  details: {
    swiftRevision: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
    worktreeDirty: false,
    upstreamRevision: process.env.UPSTREAM_REVISION,
    sourceApplications: live.details.upstream,
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
      anonymousCreateRejected: live.details.permissions.anonymousCreateRejected,
    },
    mobileChat: live.details,
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Mobile Chat V3 evidence: ${RESULTS_DIR}/evidence.json"
