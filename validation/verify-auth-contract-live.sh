#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
RESULTS_DIR="${INSTANT_SWIFT_DATA_AUTH_RESULTS_DIR:-/tmp/instant-data-swift-auth-contract-$(date -u +%Y%m%dT%H%M%SZ)}"

: "${INSTANT_APP_ID:?Source ephemeral Instant credentials before running this verifier.}"
: "${INSTANT_ADMIN_TOKEN:?Source ephemeral Instant credentials before running this verifier.}"

WORKTREE_DIRTY=false
if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  WORKTREE_DIRTY=true
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_DIRTY_CONTRACT_RUN:-0}" != "1" ]]; then
    echo "Live auth verification requires a clean worktree so evidence names an exact revision." >&2
    exit 1
  fi
fi
export WORKTREE_DIRTY

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
mkdir -p "${RESULTS_DIR}"

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
pnpm --dir "${RUNNER}" exec tsx src/auth-live-contract.ts \
  >"${RESULTS_DIR}/typescript-auth-live-contract.json"

ROOT="${ROOT}" \
RUNNER="${RUNNER}" \
RESULTS_DIR="${RESULTS_DIR}" \
APP_ID="${INSTANT_APP_ID}" \
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
  readFileSync(resolve(results, "typescript-auth-live-contract.json"), "utf8"),
);

assert.equal(live.ok, true);
assert.equal(live.details.swift.serverVerifiedSignIn, true);
assert.equal(live.details.swift.durableRelaunch, true);
assert.equal(live.details.swift.localSessionCleared, true);
assert.equal(live.details.swift.invalidatedTokenRejected, true);
assert.equal(live.details.swift.rejectionCode, "authFailed");
assert.equal(live.details.typescriptInvalidatedTokenRejected, true);
assert.match(live.details.typescriptRejection, /record not found|app-user|400|auth/i);

const evidence = {
  case: "validation.auth.live-contract",
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
    live: live.details,
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Auth contract evidence: ${RESULTS_DIR}/evidence.json"
