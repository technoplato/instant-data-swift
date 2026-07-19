#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
CLI="${RUNNER}/node_modules/.bin/instant-cli"
RESULTS_DIR="${INSTANT_SWIFT_DATA_AUTH_V3_RESULTS_DIR:-/tmp/instant-data-swift-auth-v3-app-$(date -u +%Y%m%dT%H%M%SZ)}"
APP_DIR="${RESULTS_DIR}/app"

if [[ -n "$(git -C "${ROOT}" status --porcelain)" ]]; then
  echo "Auth V3 app verification requires a clean worktree." >&2
  exit 1
fi
if [[ ! -x "${CLI}" ]]; then
  echo "Missing pinned Instant CLI. Run pnpm install in validation/ts-runner." >&2
  exit 1
fi

EXPECTED_UPSTREAM_REVISION="$(
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
)"
UPSTREAM_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
if [[ "${UPSTREAM_REVISION}" != "${EXPECTED_UPSTREAM_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch." >&2
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
  "${CLI}" init --temp --title "instant-data-swift-auth-v3-app" --yes --env .instant.env
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
swift build --package-path "${ROOT}" --product auth-v3
pnpm --dir "${RUNNER}" exec tsx src/auth-v3-app-live-contract.ts \
  >"${RESULTS_DIR}/auth-v3-app.json"

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
const live = JSON.parse(readFileSync(resolve(results, "auth-v3-app.json"), "utf8"));

assert.equal(live.ok, true);
assert.deepStrictEqual(live.details.swift.providerIDs, [
  "magic-code", "apple", "google", "github", "enterprise-oidc",
]);
assert.equal(live.details.swift.userNamespace, "$users");
assert.equal(live.details.swift.signedInStatus, "signedIn");
assert.equal(live.details.swift.relaunchedStatus, "signedIn");
assert.equal(live.details.swift.signedOutStatus, "signedOut");
assert.equal(live.details.swift.auth.serverVerifiedSignIn, true);
assert.equal(live.details.swift.auth.durableRelaunch, true);
assert.equal(live.details.swift.auth.localSessionCleared, true);
assert.equal(live.details.swift.auth.invalidatedTokenRejected, true);
assert.equal(live.details.swift.auth.rejectionCode, "authFailed");
assert.match(live.details.typeScriptRejection, /record not found|app-user|400|auth/i);
assert.equal(live.details.compilerWarningCount, 0);
assert.deepStrictEqual(live.details.warnings, []);

const evidence = {
  case: "validation.auth-v3-app.live-contract",
  event: "app-owned-auth-summary",
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
    auth: live.details,
  },
};

process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

echo "Auth V3 app evidence: ${RESULTS_DIR}/evidence.json"
