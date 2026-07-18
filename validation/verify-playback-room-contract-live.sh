#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
RESULTS_DIR="${INSTANT_SWIFT_DATA_PLAYBACK_ROOM_RESULTS_DIR:-/tmp/instant-data-swift-playback-room-contract-$(date -u +%Y%m%dT%H%M%SZ)}"
GENERATED_DIR="${RESULTS_DIR}/generated"

: "${INSTANT_APP_ID:?Source ephemeral Instant credentials before running this verifier.}"
: "${INSTANT_ADMIN_TOKEN:?Source ephemeral Instant credentials before running this verifier.}"

WORKTREE_DIRTY=false
if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  WORKTREE_DIRTY=true
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_DIRTY_CONTRACT_RUN:-0}" != "1" ]]; then
    echo "Live playback room verification requires a clean worktree so evidence names an exact revision." >&2
    exit 1
  fi
fi
export WORKTREE_DIRTY

if [[ ! -d "${RUNNER}/node_modules" ]]; then
  echo "Missing pinned TypeScript dependencies. Run: pnpm --dir validation/ts-runner install --frozen-lockfile" >&2
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
mkdir -p "${GENERATED_DIR}"

swift run --package-path "${ROOT}" instant-swift-data schema generate \
  --example recording-action \
  --to "${GENERATED_DIR}/recording-action.schema.ts" \
  --json >"${RESULTS_DIR}/swift-schema-generate.json"

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json

INSTANT_SWIFT_DATA_RECORDING_SCHEMA_PATH="${GENERATED_DIR}/recording-action.schema.ts" \
  pnpm --dir "${RUNNER}" exec tsx src/playback-room-live-contract.ts \
  >"${RESULTS_DIR}/typescript-playback-room-live-contract.json"

ROOT="${ROOT}" \
RUNNER="${RUNNER}" \
RESULTS_DIR="${RESULTS_DIR}" \
APP_ID="${INSTANT_APP_ID}" \
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
      .update(readFileSync(resolve(results, "generated/recording-action.schema.ts")))
      .digest("hex"),
    live: live.details,
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Playback room contract evidence: ${RESULTS_DIR}/evidence.json"
