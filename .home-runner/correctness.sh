#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/correctness"
RUNNER="${ROOT}/validation/ts-runner"
PNPM_VERSION="${INSTANT_SWIFT_DATA_PNPM_VERSION:-9.15.0}"
SQLITE_DATA_REVISION="97987458b49f0311717ecfbf7e8ac4c406afbf55"
SQLITE_DATA_CHECKOUT="${ROOT}/upstream/sqlite-data"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"
export CI=1
export NO_COLOR=1
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.0}"

echo "Instant Swift Data correctness on $(hostname)"
echo "commit=$(git -C "${ROOT}" rev-parse HEAD)"
echo "pnpm=${PNPM_VERSION}"
echo "macOS deployment target=${MACOSX_DEPLOYMENT_TARGET}"

git -C "${ROOT}" submodule sync -- upstream/instant
git -C "${ROOT}" submodule update --init --recursive upstream/instant
if [[ ! -d "${SQLITE_DATA_CHECKOUT}/.git" ]]; then
  rm -rf "${SQLITE_DATA_CHECKOUT}"
  git clone --filter=blob:none --no-checkout \
    https://github.com/pointfreeco/sqlite-data.git \
    "${SQLITE_DATA_CHECKOUT}"
fi
git -C "${SQLITE_DATA_CHECKOUT}" fetch --force --depth 1 origin "${SQLITE_DATA_REVISION}"
git -C "${SQLITE_DATA_CHECKOUT}" checkout --force --detach FETCH_HEAD
export SQLITE_DATA_UPSTREAM_CHECKOUT="${SQLITE_DATA_CHECKOUT}"
corepack enable

node --test "${ROOT}/validation/tests/benchmark-policy.test.mjs" \
  2>&1 | tee "${RESULTS}/benchmark-policy.log"
corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" install --frozen-lockfile \
  2>&1 | tee "${RESULTS}/typescript-install.log"
# Swift Testing is parallel by default. Correctness, cancellation, SQLite, and
# timing tests share process resources, so the publication gate executes them
# serially and leaves comparative performance to the isolated benchmark lanes.
#
# Process-level CLI and validation-runner tests must invoke already-built
# products. Nested `swift run` waits forever on the package `.build.lock`
# held by `swift test`.
swift build --package-path "${ROOT}" -c release --product instant-swift-data \
  2>&1 | tee "${RESULTS}/swift-release-cli-products.log"
swift build --package-path "${ROOT}" -c release \
  --product instant-swift-data-validation-runner \
  2>&1 | tee -a "${RESULTS}/swift-release-cli-products.log"
swift test --package-path "${ROOT}" -c release --no-parallel \
  2>&1 | tee "${RESULTS}/swift-release-tests.log"
INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS=1 \
  "${ROOT}/validation/run-macro-tests.sh" \
  2>&1 | tee "${RESULTS}/macro-tests.log"
corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" test \
  2>&1 | tee "${RESULTS}/typescript-contracts.log"

if rg -n '(^|[[:space:]])warning:' \
  "${RESULTS}/swift-release-tests.log" \
  "${RESULTS}/macro-tests.log" \
  "${RESULTS}/typescript-contracts.log" \
  >"${RESULTS}/warnings.log"
then
  echo "Correctness job found warnings." >&2
  cat "${RESULTS}/warnings.log" >&2
  exit 1
fi

ROOT="${ROOT}" RESULTS="${RESULTS}" node --input-type=module <<'NODE' \
  | tee "${RESULTS}/evidence.json"
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const results = process.env.RESULTS;
for (const file of [
  "benchmark-policy.log",
  "swift-release-cli-products.log",
  "swift-release-tests.log",
  "macro-tests.log",
  "typescript-contracts.log",
]) {
  const value = readFileSync(resolve(results, file), "utf8");
  assert.ok(value.length > 0, `${file} was empty`);
}
const evidence = {
  case: "instant-swift-data.home-runner.correctness",
  ok: true,
  revision: readFileSync(resolve(process.env.ROOT, ".git/HEAD"), "utf8").trim(),
  commit: process.env.HOME_RUNNER_REF || "default",
  machine: process.env.RUNNER_NAME || "laptop",
  checks: {
    failClosedPolicy: true,
    swiftReleaseTests: true,
    macroTests: true,
    typeScriptContracts: true,
    warnings: 0,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

test -z "$(git -C "${ROOT}" status --porcelain --untracked-files=no)"
echo "Instant Swift Data correctness passed."
