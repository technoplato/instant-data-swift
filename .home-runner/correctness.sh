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
#
# NOTE: DomainAEV 0.069 ms is the TypeScript InstaQL floor. Keep the bar.
# `--filter` still compiles every package test target, including gym apps.
# Score DomainAEV in InstantSwiftDataDomainAEVTests first, before gym
# products compile. If it fails, still run the remaining suite, then fail
# closed.
domain_aev_status=0
swift test --package-path "${ROOT}" -c release --no-parallel \
  --target InstantSwiftDataDomainAEVTests \
  2>&1 | tee "${RESULTS}/swift-release-domain-aev.log" \
  || domain_aev_status=$?
printf '%s\n' "${domain_aev_status}" > "${RESULTS}/domain-aev-exit.txt"

swift build --package-path "${ROOT}" -c release --product instant-swift-data \
  2>&1 | tee "${RESULTS}/swift-release-cli-products.log"
swift build --package-path "${ROOT}" -c release \
  --product instant-swift-data-validation-runner \
  2>&1 | tee -a "${RESULTS}/swift-release-cli-products.log"

remaining_status=0
swift test --package-path "${ROOT}" -c release --no-parallel \
  --skip DomainAEVLookupBenchTests \
  2>&1 | tee "${RESULTS}/swift-release-tests.log" \
  || remaining_status=$?
printf '%s\n' "${remaining_status}" > "${RESULTS}/swift-release-tests-exit.txt"

macro_status=0
INSTANT_SWIFT_DATA_MACRO_TESTING_JOBS=1 \
  "${ROOT}/validation/run-macro-tests.sh" \
  2>&1 | tee "${RESULTS}/macro-tests.log" \
  || macro_status=$?
printf '%s\n' "${macro_status}" > "${RESULTS}/macro-tests-exit.txt"

ts_status=0
corepack "pnpm@${PNPM_VERSION}" --dir "${RUNNER}" test \
  2>&1 | tee "${RESULTS}/typescript-contracts.log" \
  || ts_status=$?
printf '%s\n' "${ts_status}" > "${RESULTS}/typescript-contracts-exit.txt"

# Fail closed on Instant library compiler warnings. Gym source-compat
# deprecation tests, unused test locals, and third-party linker notes are
# not Instant product warnings.
python3 - "${RESULTS}" <<'PY'
from pathlib import Path
import re
import sys

results = Path(sys.argv[1])
logs = [
    results / "swift-release-cli-products.log",
    results / "swift-release-domain-aev.log",
    results / "swift-release-tests.log",
    results / "macro-tests.log",
]
pattern = re.compile(
    r"/Sources/(InstantSwiftData[^/]*|instant-swift-data)/[^:]+\.swift:\d+:\d+: warning:"
)
hits = []
for log in logs:
    if not log.exists():
        continue
    text = log.read_text()
    for line in text.splitlines():
        if pattern.search(line):
            hits.append(f"{log.name}: {line}")
out = results / "warnings.log"
out.write_text("\n".join(hits) + ("\n" if hits else ""))
if hits:
    print("Correctness job found Instant library compiler warnings.", file=sys.stderr)
    print("\n".join(hits), file=sys.stderr)
    raise SystemExit(1)
PY

ROOT="${ROOT}" RESULTS="${RESULTS}" node --input-type=module <<'NODE' \
  | tee "${RESULTS}/evidence.json"
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const results = process.env.RESULTS;
for (const file of [
  "benchmark-policy.log",
  "swift-release-cli-products.log",
  "swift-release-domain-aev.log",
  "swift-release-tests.log",
  "macro-tests.log",
  "typescript-contracts.log",
]) {
  const value = readFileSync(resolve(results, file), "utf8");
  assert.ok(value.length > 0, `${file} was empty`);
}
const readExit = (name) =>
  readFileSync(resolve(results, name), "utf8").trim();
assert.equal(readExit("domain-aev-exit.txt"), "0", "DomainAEV dedicated target failed");
assert.equal(
  readExit("swift-release-tests-exit.txt"),
  "0",
  "remaining Swift release tests failed",
);
assert.equal(readExit("macro-tests-exit.txt"), "0", "macro tests failed");
assert.equal(readExit("typescript-contracts-exit.txt"), "0", "TypeScript contracts failed");
const domainAev = readFileSync(
  resolve(results, "swift-release-domain-aev.log"),
  "utf8",
);
const remaining = readFileSync(
  resolve(results, "swift-release-tests.log"),
  "utf8",
);
assert.match(domainAev, /STORE_ONLY_BENCH/);
assert.match(domainAev, /Test run with .* passed/);
assert.match(remaining, /Test run with .* passed/);
const evidence = {
  case: "instant-swift-data.home-runner.correctness",
  ok: true,
  revision: readFileSync(resolve(process.env.ROOT, ".git/HEAD"), "utf8").trim(),
  commit: process.env.HOME_RUNNER_REF || "default",
  machine: process.env.RUNNER_NAME || "laptop",
  checks: {
    failClosedPolicy: true,
    domainAevIsolated: true,
    domainAevDedicatedTarget: true,
    swiftReleaseTests: true,
    macroTests: true,
    typeScriptContracts: true,
    libraryCompilerWarnings: 0,
  },
};
process.stdout.write(`${JSON.stringify(evidence, null, 2)}\n`);
NODE

test -z "$(git -C "${ROOT}" status --porcelain --untracked-files=no)"
echo "Instant Swift Data correctness passed."
