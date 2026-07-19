#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_REACTIONS_V3_RESULTS_DIR:-/tmp/instant-data-swift-reactions-v3-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"
PULL_DIR="${RESULTS_DIR}/pull"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Reactions V3 verification requires a clean worktree." >&2
  exit 1
fi
if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI. Run pnpm install in validation/ts-runner." >&2
  exit 1
fi

APP_ID="${INSTANT_APP_ID:-}"
ADMIN_TOKEN="${INSTANT_ADMIN_TOKEN:-${INSTANT_APP_ADMIN_TOKEN:-}}"
if [[ -n "${APP_ID}" || -n "${ADMIN_TOKEN}" ]]; then
  if [[ -z "${APP_ID}" || -z "${ADMIN_TOKEN}" ]]; then
    echo "Configured-app mode requires both INSTANT_APP_ID and an admin token." >&2
    exit 1
  fi
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION:-}" != "1" ]]; then
    echo "Set INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION=1 for configured-app mutation." >&2
    exit 1
  fi
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
  --example reactions --to "${PUSH_DIR}/instant.schema.ts" --json \
  >"${RESULTS_DIR}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example reactions --to "${PUSH_DIR}/instant.perms.ts" --json \
  >"${RESULTS_DIR}/swift-perms-generate.json"

if [[ -z "${APP_ID}" ]]; then
  (
    cd "${PUSH_DIR}"
    "${CLI}" init --temp --title "instant-data-swift-reactions-v3" --yes --env .instant.env
  ) | tee "${RESULTS_DIR}/instant-cli-init.log"
  set -a
  # shellcheck disable=SC1090
  source "${PUSH_DIR}/.instant.env"
  set +a
  APP_ID="${INSTANT_APP_ID:?Instant CLI did not write INSTANT_APP_ID}"
  ADMIN_TOKEN="${INSTANT_APP_ADMIN_TOKEN:?Instant CLI did not write INSTANT_APP_ADMIN_TOKEN}"
else
  install -m 600 /dev/null "${PUSH_DIR}/.instant.env"
  printf 'INSTANT_APP_ID=%s\nINSTANT_APP_ADMIN_TOKEN=%s\n' \
    "${APP_ID}" "${ADMIN_TOKEN}" >"${PUSH_DIR}/.instant.env"
fi

export INSTANT_APP_ID="${APP_ID}"
export INSTANT_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_APP_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_CLI_AUTH_TOKEN="${ADMIN_TOKEN}"

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
  --example reactions --from "${PULL_DIR}/instant.schema.ts" --json \
  >"${RESULTS_DIR}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example reactions --from "${PULL_DIR}/instant.perms.ts" --json \
  >"${RESULTS_DIR}/swift-server-perms-verify.json"

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
pnpm --dir "${RUNNER}" exec tsc --noEmit --strict --target ES2022 \
  --module NodeNext --moduleResolution NodeNext \
  "${PULL_DIR}/instant.schema.ts" "${PULL_DIR}/instant.perms.ts"

INSTANT_SWIFT_DATA_REACTIONS_SCHEMA_PATH="${PUSH_DIR}/instant.schema.ts" \
  pnpm --dir "${RUNNER}" exec tsx src/reactions-v3-live-contract.ts \
  >"${RESULTS_DIR}/reactions-v3.json"

ROOT="${ROOT}" RUNNER="${RUNNER}" RESULTS_DIR="${RESULTS_DIR}" \
APP_ID="${APP_ID}" UPSTREAM_REVISION="${UPSTREAM_REVISION}" \
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
const live = readJSON("reactions-v3.json");
const swiftPayload = { name: "heart", directionAngle: 45, rotationAngle: 270 };
const typeScriptPayload = { name: "wave", directionAngle: 90, rotationAngle: 180 };

assert.equal(live.ok, true);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepStrictEqual(live.details.warnings, []);
assert.deepStrictEqual(live.details.swift.publishedPayload, swiftPayload);
assert.deepStrictEqual(live.details.swift.observedPayload, typeScriptPayload);
assert.equal(live.details.swift.ignoredInvalidName, "sparkle");
assert.deepStrictEqual(live.details.typeScriptPublishedPayload, typeScriptPayload);
assert.deepStrictEqual(live.details.typeScriptObservedSwiftPayload, swiftPayload);
assert.deepStrictEqual(live.details.subscriptionCleanup, {
  cleanupProbePayload: { name: "fire", directionAngle: 225, rotationAngle: 135 },
  witnessObserved: true,
  callbackCountBeforeProbe: 1,
  callbackCountAfterProbe: 1,
});
assert.equal(schema.entityCount, 0);
assert.equal(schema.attributeCount, 0);
assert.equal(schema.linkCount, 0);
assert.deepStrictEqual(schema.warnings, [
  { code: "system-entity", path: "$files" },
  { code: "system-entity", path: "$streams" },
  { code: "system-entity", path: "$users" },
  { code: "system-link", path: "$streams$files" },
  { code: "system-link", path: "$usersLinkedPrimaryUser" },
]);
assert.equal(permissions.namespaceCount, 0);
assert.equal(permissions.allowRuleCount, 0);
assert.equal(permissions.rateLimitCount, 0);

const evidence = {
  case: "validation.reactions-v3-app.live-contract",
  event: "bidirectional-sdk-summary",
  appID: process.env.APP_ID,
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
    reactions: live.details,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Reactions V3 evidence: ${RESULTS_DIR}/evidence.json"
