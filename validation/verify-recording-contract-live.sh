#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_CONTRACT_RESULTS_DIR:-/tmp/instant-swift-data-recording-contract-$(date -u +%Y%m%dT%H%M%SZ)}"
PUSH_DIR="${RESULTS_DIR}/push"
PULL_DIR="${RESULTS_DIR}/pull"

WORKTREE_DIRTY=false
if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  WORKTREE_DIRTY=true
  if [[ "${INSTANT_SWIFT_DATA_ALLOW_DIRTY_CONTRACT_RUN:-0}" != "1" ]]; then
    echo "Live contract verification requires a clean worktree so evidence names an exact Swift revision." >&2
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

export INSTANT_ADMIN_TOKEN="${ADMIN_TOKEN}"
export INSTANT_SWIFT_DATA_REMOTE_APP_ID="${APP_ID}"
export INSTANT_SWIFT_DATA_LIVE_BOUNDARY_SWIFT_TIMEOUT_MS="${INSTANT_SWIFT_DATA_LIVE_BOUNDARY_SWIFT_TIMEOUT_MS:-90000}"
pnpm --dir "${RUNNER}" exec tsx src/main.ts \
  --boundary-recording-sdk-e2e \
  --app-id "${APP_ID}" \
  | tee "${RESULTS_DIR}/typescript-recording-sdk-e2e.jsonl"

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
const recordingSDKRows = readFileSync(
  resolve(results, "typescript-recording-sdk-e2e.jsonl"),
  "utf8",
)
  .split("\n")
  .filter(Boolean)
  .map((line) => JSON.parse(line));
const ownerRow = recordingSDKRows.find(
  (row) => row.event === "canonical-sdk-owner-created",
);
const swiftRow = recordingSDKRows.find(
  (row) => row.event === "swift-recording-transaction",
);
const queryRow = recordingSDKRows.find(
  (row) => row.event === "canonical-sdk-query",
);
const recordingBoundaryOK =
  ownerRow?.ok === true
  && swiftRow?.ok === true
  && queryRow?.ok === true;
const sha256 = (path) =>
  createHash("sha256").update(readFileSync(path)).digest("hex");

const evidence = {
  case: "validation.instant.recording-contract",
  event: "install-pull-verify-swift-write",
  ok: recordingBoundaryOK,
  appID: process.env.APP_ID,
  details: {
    swiftRevision: execFileSync("git", ["-C", root, "rev-parse", "HEAD"], {
      encoding: "utf8",
    }).trim(),
    swiftWorktreeDirty: process.env.WORKTREE_DIRTY === "true",
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
    swiftToTypeScript: {
      ownerID: ownerRow?.details.ownerID ?? null,
      swiftEvents: swiftRow?.details.swiftEvents ?? [],
      queryAttemptCount: queryRow?.details.queryAttemptCount ?? null,
      exactShape: queryRow?.details.exactShape ?? false,
      actual: queryRow?.details.actual ?? null,
      expected: queryRow?.details.expected ?? null,
      warnings: queryRow?.details.warnings ?? [],
    },
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Live recording contract evidence: ${RESULTS_DIR}/evidence.json"
