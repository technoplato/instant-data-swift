#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${INSTANT_SWIFT_DATA_V03_RESULTS_DIR:-/tmp/instant-data-swift-v0.3-contract-$(date -u +%Y%m%dT%H%M%SZ)}"
SHARING_DIR="${RESULTS_DIR}/sharing"
AUTH_DIR="${RESULTS_DIR}/auth"

: "${INSTANT_APP_ID:?Source ephemeral Instant credentials before running this verifier.}"
: "${INSTANT_ADMIN_TOKEN:?Source ephemeral Instant credentials before running this verifier.}"
: "${INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION:?Set to 1 for the disposable validation app.}"

mkdir -p "${SHARING_DIR}" "${AUTH_DIR}"

INSTANT_SWIFT_DATA_SHARING_RESULTS_DIR="${SHARING_DIR}" \
  "${ROOT}/validation/verify-sharing-contract-live.sh"
INSTANT_SWIFT_DATA_AUTH_RESULTS_DIR="${AUTH_DIR}" \
  "${ROOT}/validation/verify-auth-contract-live.sh"

ROOT="${ROOT}" \
RESULTS_DIR="${RESULTS_DIR}" \
APP_ID="${INSTANT_APP_ID}" \
node --input-type=module <<'NODE' | tee "${RESULTS_DIR}/evidence.json"
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = process.env.ROOT;
const results = process.env.RESULTS_DIR;
const revision = execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
  encoding: "utf8",
}).trim();
const sharing = readJSON("sharing/evidence.json");
const auth = readJSON("auth/evidence.json");

assert.equal(sharing.ok, true);
assert.equal(auth.ok, true);
assert.equal(sharing.details.swiftRevision, revision);
assert.equal(auth.details.swiftRevision, revision);
assert.equal(sharing.details.worktreeDirty, false);
assert.equal(auth.details.worktreeDirty, false);
assert.equal(sharing.details.schema.entityCount, 4);
assert.equal(sharing.details.schema.attributeCount, 16);
assert.equal(sharing.details.schema.linkCount, 7);
assert.equal(sharing.details.permissions.namespaceCount, 4);
assert.equal(sharing.details.permissions.allowRuleCount, 13);
assert.equal(sharing.details.live.compilerWarningCount, 0);
assert.deepStrictEqual(sharing.details.live.swiftReaderRejection.observedValues, [1, 2, 1]);
assert.equal(sharing.details.live.swiftReaderRejection.pendingMutationCount, 0);
assert.equal(sharing.details.live.swiftReaderRejection.failedMutationCount, 1);
assert.deepStrictEqual(sharing.details.live.swiftWriterAcceptance.observedValues, [1, 3]);
assert.equal(sharing.details.live.swiftWriterAcceptance.pendingMutationCount, 0);
assert.equal(sharing.details.live.swiftWriterAcceptance.failedMutationCount, 0);
assert.equal(sharing.details.live.finalValue, 3);
assert.equal(auth.details.compilerWarningCount, 0);
assert.equal(auth.details.live.swift.serverVerifiedSignIn, true);
assert.equal(auth.details.live.swift.durableRelaunch, true);
assert.equal(auth.details.live.swift.localSessionCleared, true);
assert.equal(auth.details.live.swift.invalidatedTokenRejected, true);
assert.equal(auth.details.live.swift.rejectionCode, "authFailed");

const evidence = {
  case: "validation.version.v0.3.0-schema-auth-sharing",
  event: "summary",
  appID: process.env.APP_ID,
  ok: true,
  details: {
    revision,
    tagTarget: "v0.3.0-schema-auth-sharing",
    sharing: sharing.details,
    auth: auth.details,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);

function readJSON(path) {
  return JSON.parse(readFileSync(resolve(results, path), "utf8"));
}
NODE

echo "v0.3.0 gate evidence: ${RESULTS_DIR}/evidence.json"
