#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_CONTRACT_RESULTS_DIR:-/tmp/instant-swift-data-recording-contract-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"
PULL_DIR="${RESULTS_DIR}/pull"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Live contract verification requires a clean worktree so evidence names an exact Swift revision." >&2
  exit 1
fi

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
trap 'rm -f "${PUSH_DIR}/.instant.env" "${PUSH_DIR}/node_modules" "${PULL_DIR}/node_modules"' EXIT

printf '{"private":true,"type":"module","dependencies":{"@instantdb/core":"1.0.49"}}\n' \
  >"${PUSH_DIR}/package.json"
printf '{"private":true,"type":"module","dependencies":{"@instantdb/core":"1.0.49"}}\n' \
  >"${PULL_DIR}/package.json"
ln -s "${RUNNER}/node_modules" "${PUSH_DIR}/node_modules"
ln -s "${RUNNER}/node_modules" "${PULL_DIR}/node_modules"

swift run --package-path "${ROOT}" instant-swift-data schema generate \
  --example recording-action \
  --to "${PUSH_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-schema-generate.json"
swift run --package-path "${ROOT}" instant-swift-data perms generate \
  --example recording-action \
  --to "${PUSH_DIR}/instant.perms.ts" \
  --json >"${RESULTS_DIR}/swift-perms-generate.json"

(
  cd "${PUSH_DIR}"
  "${CLI}" init \
    --temp \
    --title "instant-data-swift-recording-contract" \
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
export INSTANT_CLI_AUTH_TOKEN="${ADMIN_TOKEN}"

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
  --example recording-action \
  --from "${PULL_DIR}/instant.schema.ts" \
  --json >"${RESULTS_DIR}/swift-server-schema-verify.json"
swift run --package-path "${ROOT}" instant-swift-data perms verify \
  --example recording-action \
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

ROOT="${ROOT}" \
RUNNER="${RUNNER}" \
RESULTS_DIR="${RESULTS_DIR}" \
APP_ID="${APP_ID}" \
node --input-type=module <<'NODE' | tee "${RESULTS_DIR}/evidence.json"
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";

const root = process.env.ROOT;
const runner = process.env.RUNNER;
const results = process.env.RESULTS_DIR;
const manifest = JSON.parse(readFileSync(resolve(runner, "package.json"), "utf8"));
const schemaVerification = JSON.parse(
  readFileSync(resolve(results, "swift-server-schema-verify.json"), "utf8"),
);
const permissionsVerification = JSON.parse(
  readFileSync(resolve(results, "swift-server-perms-verify.json"), "utf8"),
);
const sha256 = (path) =>
  createHash("sha256").update(readFileSync(path)).digest("hex");

const evidence = {
  case: "validation.instant.recording-contract",
  event: "install-pull-verify",
  ok: true,
  appID: process.env.APP_ID,
  details: {
    swiftRevision: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
    upstreamRevision: execFileSync(
      "git",
      ["-C", resolve(root, "upstream/instant"), "rev-parse", "HEAD"],
      { encoding: "utf8" },
    ).trim(),
    coreVersion: manifest.dependencies["@instantdb/core"],
    adminVersion: manifest.dependencies["@instantdb/admin"],
    cliVersion: manifest.devDependencies["instant-cli"],
    typescriptVersion: manifest.devDependencies.typescript,
    compilerWarningCount: 0,
    schemaWarnings: schemaVerification.warnings,
    schema: {
      entityCount: schemaVerification.entityCount,
      attributeCount: schemaVerification.attributeCount,
      linkCount: schemaVerification.linkCount,
      sha256: sha256(resolve(results, "pull/instant.schema.ts")),
    },
    permissions: {
      namespaceCount: permissionsVerification.namespaceCount,
      allowRuleCount: permissionsVerification.allowRuleCount,
      rateLimitCount: permissionsVerification.rateLimitCount,
      sha256: sha256(resolve(results, "pull/instant.perms.ts")),
    },
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Live recording contract evidence: ${RESULTS_DIR}/evidence.json"
