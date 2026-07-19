#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_PREFERENCES_RESULTS_DIR:-/tmp/instant-data-swift-preferences-contract-$(date -u +%Y%m%dT%H%M%SZ)}"
APP_DIR="${RESULTS_DIR}/app"

WORKTREE_DIRTY=false
if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  WORKTREE_DIRTY=true
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_DIRTY_CONTRACT_RUN:-0}" != "1" ]]; then
    echo "Live preferences verification requires a clean worktree so evidence names an exact revision." >&2
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
mkdir -p "${APP_DIR}"
trap 'unlink "${APP_DIR}/.instant.env" 2>/dev/null || true; unlink "${APP_DIR}/node_modules" 2>/dev/null || true' EXIT
cp "${RUNNER}/package.json" "${APP_DIR}/package.json"
ln -s "${RUNNER}/node_modules" "${APP_DIR}/node_modules"

(
  cd "${APP_DIR}"
  "${CLI}" init \
    --temp \
    --title "instant-data-swift-preferences" \
    --yes \
    --env .instant.env
) | tee "${RESULTS_DIR}/instant-cli-init.log"

set -a
# shellcheck disable=SC1090
source "${APP_DIR}/.instant.env"
set +a

APP_ID="${INSTANT_APP_ID:?Instant CLI did not write INSTANT_APP_ID}"
ADMIN_TOKEN="${INSTANT_APP_ADMIN_TOKEN:?Instant CLI did not write INSTANT_APP_ADMIN_TOKEN}"
export INSTANT_APP_ID="${APP_ID}"
export INSTANT_ADMIN_TOKEN="${ADMIN_TOKEN}"

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
pnpm --dir "${RUNNER}" exec tsx src/preferences-live-contract.ts \
  >"${RESULTS_DIR}/typescript-preferences-live-contract.json"

ROOT="${ROOT}" \
RUNNER="${RUNNER}" \
RESULTS_DIR="${RESULTS_DIR}" \
APP_ID="${APP_ID}" \
UPSTREAM_REVISION="${UPSTREAM_REVISION}" \
node --input-type=module <<'NODE' | tee "${RESULTS_DIR}/evidence.json"
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = process.env.ROOT;
const runner = process.env.RUNNER;
const results = process.env.RESULTS_DIR;
const manifest = JSON.parse(readFileSync(resolve(runner, "package.json"), "utf8"));
const live = JSON.parse(
  readFileSync(resolve(results, "typescript-preferences-live-contract.json"), "utf8"),
);

assert.equal(live.ok, true);
assert.equal(live.details.swift.connectionState, "authenticated");
assert.deepStrictEqual(live.details.swift.phaseSequence, ["connected", "authenticated"]);
assert.ok(live.details.swift.localCacheSize > 0);
assert.equal(live.details.swift.streamCacheSize, 12);
assert.equal(live.details.swift.downloadedFileSizeBeforeClear, 7);
assert.equal(live.details.swift.downloadedFileCountBeforeClear, 2);
assert.equal(live.details.swift.clearedFileCount, 1);
assert.equal(live.details.swift.clearedBytes, 4);
assert.equal(live.details.swift.downloadedFileSizeAfterClear, 3);
assert.equal(live.details.swift.downloadedFileCountAfterClear, 1);
assert.deepStrictEqual(live.details.swift.remainingFileNames, ["transcript.txt"]);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepStrictEqual(live.details.warnings, []);

const evidence = {
  case: "validation.preferences.live-contract",
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
    live: live.details,
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Preferences contract evidence: ${RESULTS_DIR}/evidence.json"
