#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_SHARING_RESULTS_DIR:-/tmp/instant-data-swift-sharing-contract-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"
PULL_DIR="${RESULTS_DIR}/pull"

: "${INSTANT_APP_ID:?Source ephemeral Instant credentials before running this verifier.}"
: "${INSTANT_ADMIN_TOKEN:?Source ephemeral Instant credentials before running this verifier.}"

if [[ "${INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION:-0}" != "1" ]]; then
  echo "Refusing to replace schema/perms without INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION=1." >&2
  exit 64
fi

WORKTREE_DIRTY=false
if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  WORKTREE_DIRTY=true
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_DIRTY_CONTRACT_RUN:-0}" != "1" ]]; then
    echo "Live sharing verification requires a clean worktree so evidence names an exact revision." >&2
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
export INSTANT_CLI_AUTH_TOKEN="${INSTANT_ADMIN_TOKEN}"

mkdir -p "${PUSH_DIR}" "${PULL_DIR}"
trap 'rm -f "${PUSH_DIR}/node_modules" "${PULL_DIR}/node_modules"' EXIT
cp "${RUNNER}/package.json" "${PUSH_DIR}/package.json"
cp "${RUNNER}/package.json" "${PULL_DIR}/package.json"
ln -s "${RUNNER}/node_modules" "${PUSH_DIR}/node_modules"
ln -s "${RUNNER}/node_modules" "${PULL_DIR}/node_modules"

swift run --package-path "${ROOT}" instant-swift-data schema generate \
  --example sharing \
  --to "${PUSH_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example sharing \
  --to "${PUSH_DIR}/instant.perms.ts" \
  --json >"${RESULTS_DIR}/swift-perms-generate.json"

(
  cd "${PUSH_DIR}"
  "${CLI}" push schema --app "${INSTANT_APP_ID}" --yes
  "${CLI}" push perms --app "${INSTANT_APP_ID}" --yes
) | tee "${RESULTS_DIR}/instant-cli-push.log"

(
  cd "${PULL_DIR}"
  "${CLI}" pull schema --app "${INSTANT_APP_ID}" --yes
  "${CLI}" pull perms --app "${INSTANT_APP_ID}" --yes
) | tee "${RESULTS_DIR}/instant-cli-pull.log"

swift run --package-path "${ROOT}" instant-swift-data schema verify \
  --example sharing \
  --from "${PULL_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example sharing \
  --from "${PULL_DIR}/instant.perms.ts" \
  --json >"${RESULTS_DIR}/swift-server-perms-verify.json"

pnpm --dir "${RUNNER}" exec tsc \
  --noEmit \
  --strict \
  --target ES2022 \
  --module NodeNext \
  --moduleResolution NodeNext \
  "${PULL_DIR}/instant.schema.ts" \
  "${PULL_DIR}/instant.perms.ts"

pnpm --dir "${RUNNER}" exec tsx src/sharing-live-contract.ts \
  >"${RESULTS_DIR}/typescript-sharing-live-contract.json"

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
const schema = readJSON("swift-server-schema-verify.json");
const permissions = readJSON("swift-server-perms-verify.json");
const live = readJSON("typescript-sharing-live-contract.json");
const expectedWarnings = [
  { code: "system-entity", path: "$files" },
  { code: "system-entity", path: "$streams" },
  { code: "system-attribute", path: "$users.imageURL" },
  { code: "system-attribute", path: "$users.type" },
  { code: "system-link", path: "$streams$files" },
  { code: "system-link", path: "$usersLinkedPrimaryUser" },
];

assert.equal(schema.entityCount, 4);
assert.equal(schema.attributeCount, 16);
assert.equal(schema.linkCount, 7);
assert.deepStrictEqual(schema.warnings, expectedWarnings);
assert.equal(permissions.namespaceCount, 4);
assert.equal(permissions.allowRuleCount, 13);
assert.equal(permissions.rateLimitCount, 0);
assert.equal(live.ok, true);
assert.deepStrictEqual(live.details.visibility, {
  owner: 1,
  reader: 1,
  writer: 1,
  outsider: 0,
});
assert.equal(live.details.finalValue, 3);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepStrictEqual(live.details.warnings, []);
for (const key of ["readerUpdate", "readerDelete", "writerDelete"]) {
  assert.match(live.details.rejected[key], /Permission denied/);
}

const evidence = {
  case: "validation.sharing.live-contract",
  event: "summary",
  appID: process.env.APP_ID,
  ok: true,
  details: {
    swiftRevision: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(),
    worktreeDirty: process.env.WORKTREE_DIRTY === "true",
    upstreamRevision: process.env.UPSTREAM_REVISION,
    coreVersion: manifest.dependencies["@instantdb/core"],
    adminVersion: manifest.dependencies["@instantdb/admin"],
    instantCLIVersion: manifest.devDependencies["instant-cli"],
    typescriptVersion: manifest.devDependencies.typescript,
    compilerWarningCount: 0,
    schema,
    permissions,
    live: live.details,
    artifacts: {
      pushedSchemaSHA256: sha256("push/instant.schema.ts"),
      pushedPermissionsSHA256: sha256("push/instant.perms.ts"),
      pulledSchemaSHA256: sha256("pull/instant.schema.ts"),
      pulledPermissionsSHA256: sha256("pull/instant.perms.ts"),
    },
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);

function readJSON(path) {
  return JSON.parse(readFileSync(resolve(results, path), "utf8"));
}

function sha256(path) {
  return createHash("sha256")
    .update(readFileSync(resolve(results, path)))
    .digest("hex");
}
NODE

echo "Sharing contract evidence: ${RESULTS_DIR}/evidence.json"
