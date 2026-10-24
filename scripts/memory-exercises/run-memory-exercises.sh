#!/usr/bin/env bash
# The memory audit's exercises (#1075) against the library checkout this script lives in.
#
# Builds the core tests in release with testing enabled (under the shared heavy-build lock, or through a heavy-job
# wrapper named by MEMORY_EXERCISES_HEAVY), runs the chosen suites one at a time and alone (their allocation counts are
# process-wide), and writes every MEMORY, MEMORY-REPLAY and REALSIZE-FIXTURE line to --log. The audit and its baseline:
# docs/audits/2026-10-24-memory-audit.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_FILE="${MEMORY_EXERCISES_LOCK_FILE:-/tmp/scribe-heavy-build.lock}"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/memory-exercises/run-memory-exercises.sh --log PATH [options]

  --log PATH          Where the MEMORY lines go. The build log and each suite's full output go beside it.
  --suite NAME        exercises (MemoryExercises, the default), replay (MemoryLongRunReplay, two hours of recording),
                      or a test filter of your own. Repeat to run several, one process each.
  --minutes N         The replay's recording minutes (default 120).
  --scale X           The generated store's size against the phone's (default 1).
  --store PATH        A copy of a phone's store to stand in for the generated one (never commit it).
  --scratch DIR       The build directory (default .build/memory-exercises in the checkout, ignored by git).
  --skip-build        Reuse the existing test build.
USAGE
  exit 64
}

LOG="" SUITES=() MINUTES="120" SCALE="1" STORE="" SCRATCH="${ROOT}/.build/memory-exercises" SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log) LOG="${2:?}"; shift 2 ;;
    --suite) SUITES+=("${2:?}"); shift 2 ;;
    --minutes) MINUTES="${2:?}"; shift 2 ;;
    --scale) SCALE="${2:?}"; shift 2 ;;
    --store) STORE="${2:?}"; shift 2 ;;
    --scratch) SCRATCH="${2:?}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    *) usage ;;
  esac
done
[[ -n "${LOG}" ]] || usage
[[ ${#SUITES[@]} -gt 0 ]] || SUITES=(exercises)
[[ -z "${STORE}" || -f "${STORE}" ]] || { echo "No store at ${STORE}" >&2; exit 66; }
mkdir -p "$(dirname "${LOG}")"
: > "${LOG}"

heavy() {
  if [[ -n "${MEMORY_EXERCISES_HEAVY:-}" ]]; then
    "${MEMORY_EXERCISES_HEAVY}" memory-exercises "$@"
  elif [[ -x /usr/bin/lockf ]]; then
    /usr/bin/lockf -k "${LOCK_FILE}" "$@"
  else
    "$@"
  fi
}

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
  echo "building release tests into ${SCRATCH} (log ${LOG}.build)" >&2
  (cd "${ROOT}" && heavy swift build -j "${MEMORY_EXERCISES_JOBS:-4}" -c release -Xswiftc -enable-testing \
    --product InstantSwiftDataCoreTests --scratch-path "${SCRATCH}") > "${LOG}.build" 2>&1
fi

# The test bundle and the toolchain's testing helper: `swift test` would build again in debug.
PRODUCTS="${SCRATCH}/out/Products/Release"
[[ -d "${PRODUCTS}" ]] || PRODUCTS="${SCRATCH}/arm64-apple-macosx/release"
BUNDLE="$(ls -d "${PRODUCTS}"/InstantSwiftDataCoreTests.xctest 2>/dev/null || ls -d "${PRODUCTS}"/*PackageTests.xctest | head -1)"
NAME="$(basename "${BUNDLE}" .xctest)"
DEVELOPER="$(xcode-select -p)"
PLATFORM="${DEVELOPER}/Platforms/MacOSX.platform/Developer"
HELPER="${DEVELOPER}/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper"

for suite in "${SUITES[@]}"; do
  case "${suite}" in
    exercises) filter="MemoryExercises"; envs=(INSTANT_MEMORY_EXERCISES=1 "INSTANT_MEMORY_EXERCISES_SCALE=${SCALE}") ;;
    replay) filter="MemoryLongRunReplay/"; envs=(INSTANT_MEMORY_REPLAY=1 "INSTANT_MEMORY_REPLAY_MINUTES=${MINUTES}" "INSTANT_MEMORY_REPLAY_SCALE=${SCALE}") ;;
    *) filter="${suite}"; envs=(INSTANT_MEMORY_EXERCISES=1 INSTANT_MEMORY_REPLAY=1 "INSTANT_MEMORY_REPLAY_MINUTES=${MINUTES}") ;;
  esac
  [[ -z "${STORE}" ]] || envs+=("INSTANT_REAL_SIZE_STORE=${STORE}")
  out="${LOG}.$(echo "${suite}" | tr -c 'A-Za-z0-9' '_').out"
  echo "running ${filter} (${envs[*]}) -> ${out}" >&2
  set +e
  (cd "${ROOT}" && env "${envs[@]}" \
    DYLD_LIBRARY_PATH="${PRODUCTS}:${PLATFORM}/usr/lib" \
    DYLD_FRAMEWORK_PATH="${PRODUCTS}/PackageFrameworks:${PRODUCTS}:${PLATFORM}/Library/Frameworks:${PLATFORM}/Library/PrivateFrameworks" \
    "${HELPER}" --test-bundle-path "${BUNDLE}/Contents/MacOS/${NAME}" --testing-library swift-testing --filter "${filter}") \
    > "${out}" 2>&1
  status=$?
  set -e
  grep -E '^(MEMORY|MEMORY-REPLAY|MEMORY-REPLAY-START|MEMORY-REPLAY-SUMMARY|REALSIZE-FIXTURE) ' "${out}" >> "${LOG}" || true
  echo "${filter} exit=${status}" >&2
done
