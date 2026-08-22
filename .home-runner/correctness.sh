#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/correctness"
RUNNER="${ROOT}/validation/ts-runner"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"
export CI=1
export NO_COLOR=1

echo "Instant Swift Data correctness on $(hostname)"
echo "commit=$(git -C "${ROOT}" rev-parse HEAD)"

git -C "${ROOT}" submodule sync -- upstream/instant
git -C "${ROOT}" submodule update --init --recursive upstream/instant
corepack enable

node --test "${ROOT}/validation/tests/benchmark-policy.test.mjs" \
  2>&1 | tee "${RESULTS}/benchmark-policy.log"
corepack pnpm --dir "${RUNNER}" install --frozen-lockfile \
  2>&1 | tee "${RESULTS}/typescript-install.log"
swift test --package-path "${ROOT}" -c release \
  2>&1 | tee "${RESULTS}/swift-release-tests.log"
INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS=1 \
  "${ROOT}/validation/run-macro-tests.sh" \
  2>&1 | tee "${RESULTS}/macro-tests.log"
corepack pnpm --dir "${RUNNER}" test \
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
