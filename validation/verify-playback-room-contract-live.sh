#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_PLAYBACK_ROOM_RESULTS_DIR:-/tmp/instant-data-swift-playback-room-contract-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"

WORKTREE_DIRTY=false
if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  WORKTREE_DIRTY=true
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_DIRTY_CONTRACT_RUN:-0}" != "1" ]]; then
    echo "Live playback room verification requires a clean worktree so evidence names an exact revision." >&2
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
mkdir -p "${PUSH_DIR}"
trap 'unlink "${PUSH_DIR}/.instant.env" 2>/dev/null || true; unlink "${PUSH_DIR}/node_modules" 2>/dev/null || true' EXIT
cp "${RUNNER}/package.json" "${PUSH_DIR}/package.json"
ln -s "${RUNNER}/node_modules" "${PUSH_DIR}/node_modules"

swift run --package-path "${ROOT}" instant-swift-data schema generate \
  --example recording-action \
  --to "${PUSH_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-schema-generate.json"

(
  cd "${PUSH_DIR}"
  "${CLI}" init \
    --temp \
    --title "instant-data-swift-playback-room" \
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

(
  cd "${PUSH_DIR}"
  "${CLI}" push schema --yes
) | tee "${RESULTS_DIR}/instant-cli-push.log"

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json

INSTANT_SWIFT_DATA_RECORDING_SCHEMA_PATH="${PUSH_DIR}/instant.schema.ts" \
  pnpm --dir "${RUNNER}" exec tsx src/playback-room-live-contract.ts \
  >"${RESULTS_DIR}/typescript-playback-room-live-contract.json"

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
const manifest = JSON.parse(readFileSync(resolve(runner, "package.json"), "utf8"));
const live = JSON.parse(
  readFileSync(resolve(results, "typescript-playback-room-live-contract.json"), "utf8"),
);

const swiftPresence = {
  userID: live.details.swiftUserID,
  displayName: "Swift Listener",
  isPlaying: true,
  offsetSeconds: 12.5,
  focusedSegmentID: "segment-swift",
};
const typeScriptPresence = {
  userID: live.details.typeScriptUserID,
  displayName: "TypeScript Listener",
  isPlaying: false,
  offsetSeconds: 4.25,
  focusedSegmentID: "segment-typescript",
};
const swiftTopics = {
  reaction: { emoji: "swift-wave", offsetSeconds: 12.5 },
  commentDraft: { text: "Swift draft", offsetSeconds: 12.5 },
  commentCommitted: { commentID: "comment-swift" },
};
const typeScriptTopics = {
  reaction: { emoji: "typescript-wave", offsetSeconds: 4.25 },
  commentDraft: { text: "TypeScript draft", offsetSeconds: 4.25 },
  commentCommitted: { commentID: "comment-typescript" },
};
const reconnectedSwiftPresence = {
  userID: live.details.swiftUserID,
  displayName: "Swift Listener Rejoined",
  isPlaying: false,
  offsetSeconds: 18.75,
  focusedSegmentID: "segment-swift-rejoined",
};
const reconnectedTypeScriptPresence = {
  userID: live.details.typeScriptUserID,
  displayName: "TypeScript Listener Rejoined",
  isPlaying: true,
  offsetSeconds: 9.5,
  focusedSegmentID: "segment-typescript-rejoined",
};
const reconnectedSwiftTopics = {
  reaction: { emoji: "swift-rejoined", offsetSeconds: 18.75 },
  commentDraft: { text: "Swift draft after reconnect", offsetSeconds: 18.75 },
  commentCommitted: { commentID: "comment-swift-rejoined" },
};
const reconnectedTypeScriptTopics = {
  reaction: { emoji: "typescript-rejoined", offsetSeconds: 9.5 },
  commentDraft: { text: "TypeScript draft after reconnect", offsetSeconds: 9.5 },
  commentCommitted: { commentID: "comment-typescript-rejoined" },
};

assert.equal(live.ok, true);
assert.equal(live.details.roomType, "recording.playback");
assert.deepStrictEqual(live.details.observedSwiftPresence, swiftPresence);
assert.deepStrictEqual(live.details.observedSwiftTopics, swiftTopics);
assert.deepStrictEqual(live.details.publishedTypeScriptPresence, typeScriptPresence);
assert.deepStrictEqual(live.details.publishedTypeScriptTopics, typeScriptTopics);
assert.deepStrictEqual(live.details.swift.publishedPresence, swiftPresence);
assert.deepStrictEqual(live.details.swift.receivedPresence, typeScriptPresence);
assert.deepStrictEqual(live.details.swift.publishedTopics, swiftTopics);
assert.deepStrictEqual(live.details.swift.receivedTopics, typeScriptTopics);
assert.equal(live.details.swift.connectionState, "authenticated");
assert.deepStrictEqual(
  live.details.observedReconnectedSwiftPresence,
  reconnectedSwiftPresence,
);
assert.deepStrictEqual(
  live.details.observedReconnectedSwiftTopics,
  reconnectedSwiftTopics,
);
assert.deepStrictEqual(
  live.details.publishedReconnectedTypeScriptPresence,
  reconnectedTypeScriptPresence,
);
assert.deepStrictEqual(
  live.details.publishedReconnectedTypeScriptTopics,
  reconnectedTypeScriptTopics,
);
assert.equal(live.details.swift.reconnect.connectionCount, 2);
assert.equal(live.details.swift.reconnect.connectionState, "authenticated");
assert.deepStrictEqual(
  live.details.swift.reconnect.publishedPresence,
  reconnectedSwiftPresence,
);
assert.deepStrictEqual(
  live.details.swift.reconnect.receivedPresence,
  reconnectedTypeScriptPresence,
);
assert.deepStrictEqual(
  live.details.swift.reconnect.publishedTopics,
  reconnectedSwiftTopics,
);
assert.deepStrictEqual(
  live.details.swift.reconnect.receivedTopics,
  reconnectedTypeScriptTopics,
);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepStrictEqual(live.details.warnings, []);

const evidence = {
  case: "validation.playback-room.live-contract",
  event: "summary",
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
    typescriptVersion: manifest.devDependencies.typescript,
    compilerWarningCount: 0,
    schemaSHA256: createHash("sha256")
      .update(readFileSync(resolve(results, "push/instant.schema.ts")))
      .digest("hex"),
    live: live.details,
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Playback room contract evidence: ${RESULTS_DIR}/evidence.json"
