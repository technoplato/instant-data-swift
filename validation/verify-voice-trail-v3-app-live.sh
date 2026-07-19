#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_VOICE_TRAIL_V3_APP_RESULTS_DIR:-/tmp/instant-data-swift-voice-trail-v3-app-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"
PULL_DIR="${RESULTS_DIR}/pull"

WORKTREE_DIRTY=false
if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  WORKTREE_DIRTY=true
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_DIRTY_CONTRACT_RUN:-0}" != "1" ]]; then
    echo "VoiceTrail V3 app verification requires a clean worktree." >&2
    exit 1
  fi
fi
export WORKTREE_DIRTY

if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI. Run: pnpm --dir validation/ts-runner install --frozen-lockfile" >&2
  exit 1
fi

EXPECTED_UPSTREAM_REVISION="$(
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
)"
UPSTREAM_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
if [[ "${UPSTREAM_REVISION}" != "${EXPECTED_UPSTREAM_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch: expected ${EXPECTED_UPSTREAM_REVISION}, found ${UPSTREAM_REVISION}." >&2
  exit 1
fi

export CI=1
export NO_COLOR=1
mkdir -p "${PUSH_DIR}" "${PULL_DIR}"
trap 'unlink "${PUSH_DIR}/.instant.env" 2>/dev/null || true; unlink "${PUSH_DIR}/node_modules" 2>/dev/null || true; unlink "${PULL_DIR}/node_modules" 2>/dev/null || true' EXIT
cp "${RUNNER}/package.json" "${PUSH_DIR}/package.json"
cp "${RUNNER}/package.json" "${PULL_DIR}/package.json"
ln -s "${RUNNER}/node_modules" "${PUSH_DIR}/node_modules"
ln -s "${RUNNER}/node_modules" "${PULL_DIR}/node_modules"

swift run --package-path "${ROOT}" instant-swift-data schema generate \
  --example voice-trail \
  --to "${PUSH_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example voice-trail \
  --to "${PUSH_DIR}/instant.perms.ts" \
  --json >"${RESULTS_DIR}/swift-perms-generate.json"

(
  cd "${PUSH_DIR}"
  "${CLI}" init \
    --temp \
    --title "instant-data-swift-voicetrail-v3-app" \
    --yes \
    --env .instant.env
) | tee "${RESULTS_DIR}/instant-cli-init.log"

set -a
# shellcheck disable=SC1090
source "${PUSH_DIR}/.instant.env"
set +a

APP_ID="${INSTANT_APP_ID:?Instant CLI did not write INSTANT_APP_ID}"
ADMIN_TOKEN="${INSTANT_APP_ADMIN_TOKEN:?Instant CLI did not write INSTANT_APP_ADMIN_TOKEN}"
export INSTANT_APP_ID="${APP_ID}"
export INSTANT_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_CLI_AUTH_TOKEN="${ADMIN_TOKEN}"
export INSTANT_SWIFT_DATA_REMOTE_APP_ID="${APP_ID}"
export INSTANT_SWIFT_DATA_LIVE_BOUNDARY_SWIFT_TIMEOUT_MS="${INSTANT_SWIFT_DATA_LIVE_BOUNDARY_SWIFT_TIMEOUT_MS:-90000}"

(
  cd "${PUSH_DIR}"
  "${CLI}" push schema --yes
  "${CLI}" push perms --yes
) | tee "${RESULTS_DIR}/instant-cli-push.log"

(
  cd "${PULL_DIR}"
  "${CLI}" pull schema --yes
  "${CLI}" pull perms --yes
) | tee "${RESULTS_DIR}/instant-cli-pull.log"

swift run --package-path "${ROOT}" instant-swift-data schema verify \
  --example voice-trail \
  --from "${PULL_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example voice-trail \
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

pnpm --dir "${RUNNER}" exec tsx src/voice-trail-v3-capture-live-contract.ts \
  >"${RESULTS_DIR}/app-capture.json"
pnpm --dir "${RUNNER}" exec tsx src/voice-trail-recordings-list-live-contract.ts \
  >"${RESULTS_DIR}/recordings-list.json"
INSTANT_SWIFT_DATA_RECORDING_SCHEMA_PATH="${PUSH_DIR}/instant.schema.ts" \
  pnpm --dir "${RUNNER}" exec tsx src/playback-room-live-contract.ts \
  >"${RESULTS_DIR}/playback.json"
pnpm --dir "${RUNNER}" exec tsx src/preferences-live-contract.ts \
  >"${RESULTS_DIR}/preferences.json"
pnpm --dir "${RUNNER}" exec tsx src/auth-live-contract.ts \
  >"${RESULTS_DIR}/auth.json"

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
const appCapture = readJSON("app-capture.json");
const recordings = readJSON("recordings-list.json");
const playback = readJSON("playback.json");
const preferences = readJSON("preferences.json");
const auth = readJSON("auth.json");

assert.equal(recordings.ok, true);
assert.equal(appCapture.ok, true);
assert.equal(appCapture.details.swift.direction, "swift-to-typescript");
assert.equal(appCapture.details.swift.connectionState, "authenticated");
assert.equal(appCapture.details.swift.pendingMutationCount, 0);
assert.deepStrictEqual(appCapture.details.typescript, {
  recordingID: appCapture.details.swift.recordingID,
  transcriptionID: appCapture.details.swift.transcriptionID,
  attachmentID: appCapture.details.swift.attachmentID,
  title: appCapture.details.swift.title,
  ownerUserID: appCapture.details.swift.userID,
  deviceID: appCapture.details.swift.deviceID,
  recordingState: "finished",
  durationMilliseconds: 12_750,
  transcriptionState: "ready",
  attachmentKind: "screenshot",
  attachmentContents: "capture.png",
  attachmentOffsetMilliseconds: 2_500,
});
assert.equal(appCapture.details.compilerWarningCount, 0);
assert.deepStrictEqual(appCapture.details.warnings, []);
assert.deepStrictEqual(recordings.details.ownerStages, ["owner", "cancelled"]);
assert.deepStrictEqual(
  recordings.details.memberStages,
  ["reader", "writer", "revoked", "cancelled"],
);
assert.match(recordings.details.readerUpdateRejection, /permission|recording|update/i);
assert.equal(recordings.details.compilerWarningCount, 0);
assert.deepStrictEqual(recordings.details.warnings, []);
assert.equal(playback.ok, true);
assert.equal(playback.details.swift.reconnect.connectionCount, 2);
assert.equal(playback.details.swift.reconnect.connectionState, "authenticated");
assert.equal(playback.details.compilerWarningCount, 0);
assert.deepStrictEqual(playback.details.warnings, []);
assert.equal(preferences.ok, true);
assert.deepStrictEqual(preferences.details.swift.phaseSequence, ["connected", "authenticated"]);
assert.equal(preferences.details.swift.streamCacheSize, 12);
assert.equal(preferences.details.swift.downloadedFileSizeBeforeClear, 7);
assert.equal(preferences.details.swift.clearedBytes, 4);
assert.deepStrictEqual(preferences.details.swift.remainingFileNames, ["transcript.txt"]);
assert.equal(preferences.details.compilerWarningCount, 0);
assert.deepStrictEqual(preferences.details.warnings, []);
assert.equal(auth.ok, true);
assert.equal(auth.details.swift.serverVerifiedSignIn, true);
assert.equal(auth.details.swift.durableRelaunch, true);
assert.equal(auth.details.swift.invalidatedTokenRejected, true);
assert.equal(auth.details.compilerWarningCount, 0);
assert.deepStrictEqual(auth.details.warnings, []);

const evidence = {
  case: "validation.voice-trail-v3-app.live-contract",
  event: "five-screen-bidirectional-summary",
  appID: process.env.APP_ID,
  ok: true,
  details: {
    swiftRevision: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
    worktreeDirty: process.env.WORKTREE_DIRTY === "true",
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
      warnings: permissions.warnings,
      sha256: createHash("sha256")
        .update(readFileSync(resolve(results, "pull/instant.perms.ts")))
        .digest("hex"),
    },
    appCapture: appCapture.details,
    recordings: recordings.details,
    playback: playback.details,
    preferences: preferences.details,
    auth: auth.details,
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "VoiceTrail V3 app evidence: ${RESULTS_DIR}/evidence.json"
