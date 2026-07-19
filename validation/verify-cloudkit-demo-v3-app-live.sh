#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_CLOUDKIT_DEMO_V3_RESULTS_DIR:-/tmp/instant-data-swift-cloudkit-demo-v3-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"
PULL_DIR="${RESULTS_DIR}/pull"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "CloudKitDemo V3 verification requires a clean worktree." >&2
  exit 1
fi
if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI. Run pnpm install in validation/ts-runner." >&2
  exit 1
fi

EXPECTED_UPSTREAM_REVISION="$({
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
})"
UPSTREAM_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
if [[ "${UPSTREAM_REVISION}" != "${EXPECTED_UPSTREAM_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch." >&2
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
  --example sharing --to "${PUSH_DIR}/instant.schema.ts" --json \
  >"${RESULTS_DIR}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example sharing --to "${PUSH_DIR}/instant.perms.ts" --json \
  >"${RESULTS_DIR}/swift-perms-generate.json"

(
  cd "${PUSH_DIR}"
  "${CLI}" init --temp --title "instant-data-swift-cloudkit-demo-v3" --yes --env .instant.env
) | tee "${RESULTS_DIR}/instant-cli-init.log"
set -a
# shellcheck disable=SC1090
source "${PUSH_DIR}/.instant.env"
set +a

export INSTANT_APP_ID="${INSTANT_APP_ID:?Instant CLI did not write INSTANT_APP_ID}"
export INSTANT_ADMIN_TOKEN="${INSTANT_APP_ADMIN_TOKEN:?Instant CLI did not write INSTANT_APP_ADMIN_TOKEN}"
export INSTANT_CLI_AUTH_TOKEN="${INSTANT_ADMIN_TOKEN}"

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
  --example sharing --from "${PULL_DIR}/instant.schema.ts" --json \
  >"${RESULTS_DIR}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example sharing --from "${PULL_DIR}/instant.perms.ts" --json \
  >"${RESULTS_DIR}/swift-server-perms-verify.json"

corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
corepack pnpm --dir "${RUNNER}" exec tsc --noEmit --strict --target ES2022 \
  --module NodeNext --moduleResolution NodeNext \
  "${PULL_DIR}/instant.schema.ts" "${PULL_DIR}/instant.perms.ts"

corepack pnpm --dir "${RUNNER}" exec tsx src/cloudkit-demo-v3-live-contract.ts \
  >"${RESULTS_DIR}/cloudkit-demo-v3.json"

ROOT="${ROOT}" RUNNER="${RUNNER}" RESULTS_DIR="${RESULTS_DIR}" \
UPSTREAM_REVISION="${UPSTREAM_REVISION}" node --input-type=module <<'NODE' \
  | tee "${RESULTS_DIR}/evidence.json"
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
const live = readJSON("cloudkit-demo-v3.json");
const expectedWarnings = [
  { code: "system-entity", path: "$files" },
  { code: "system-entity", path: "$streams" },
  { code: "system-attribute", path: "$users.imageURL" },
  { code: "system-attribute", path: "$users.type" },
  { code: "system-link", path: "$streams$files" },
  { code: "system-link", path: "$usersLinkedPrimaryUser" },
];

assert.equal(live.ok, true);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepStrictEqual(live.details.warnings, []);
assert.equal(live.details.final.owner.value, 2);
assert.equal(live.details.final.reader.count, 0);
assert.equal(live.details.final.writer.value, 2);
assert.equal(live.details.final.outsider.count, 0);
assert.deepStrictEqual(live.details.swift.ownerObservedValues, [0, 1, 2]);
assert.deepStrictEqual(live.details.swift.readerObservedValues, [0, 1, 0, 1, 2, 3, 2]);
assert.deepStrictEqual(live.details.swift.relaunchedRoles, ["owner", "writer"]);
assert.deepStrictEqual(live.details.swift.relaunchedPublicShareRoles, ["owner", "writer"]);
assert.equal(live.details.swift.pendingMutationCount, 0);
assert.equal(live.details.swift.failedMutationCount, 0);
assert.equal(schema.entityCount, 4);
assert.equal(schema.attributeCount, 16);
assert.equal(schema.linkCount, 7);
assert.deepStrictEqual(schema.warnings, expectedWarnings);
assert.equal(permissions.namespaceCount, 4);
assert.equal(permissions.allowRuleCount, 13);
assert.equal(permissions.rateLimitCount, 0);

const evidence = {
  case: "validation.cloudkit-demo-v3-app.live-contract",
  event: "cross-sdk-shared-counter-summary",
  appID: process.env.INSTANT_APP_ID,
  ok: true,
  details: {
    swiftRevision: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
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
    sharing: live.details,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "CloudKitDemo V3 evidence: ${RESULTS_DIR}/evidence.json"
