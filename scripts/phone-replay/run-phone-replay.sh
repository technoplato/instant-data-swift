#!/usr/bin/env bash
# The phone-shaped replay gate (#296) against the library checkout this script lives in.
#
# Stages a copy of a pulled device store under /tmp, deletes its credential rows, builds the tests under the shared
# heavy-build lock, runs PhoneReplayGateTests, writes the REPLAY lines to --log in the format of the published replay
# logs, optionally compares them with a reference log, and deletes the /tmp copy on exit. See README.md here.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="${ROOT}/scripts/phone-replay"
LOCK_FILE="${PHONE_REPLAY_LOCK_FILE:-/tmp/scribe-heavy-build.lock}"
MINIMUM_FREE_GB="${PHONE_REPLAY_MINIMUM_FREE_GB:-25}"
FILTER='PhoneReplayGateTests/replayThePhonesDrainThroughItsVerdicts'

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/phone-replay/run-phone-replay.sh --store PATH --refusals PATH --log PATH [options]

  --store PATH       The pulled store: <appID>.sqlite, or the directory holding it (with -wal and -shm). Read only.
  --refusals PATH    The mutation ids the device saw refused (refused-mutation-ids.py output, a JSON array, or
                     one id per line). Every other write is accepted.
  --log PATH         Where the REPLAY lines go. The build log goes beside it as <log>.build.
  --frames MODE      list (default) or touched.
  --window N         Claims per window (default 50).
  --work DIR         Staging directory under /tmp (default: a new /tmp/phone-replay.XXXXXX). Deleted on exit.
  --reference PATH   A previous replay log to compare this run with (compare-replay-logs.py).
  --skip-build       Reuse the existing test build.
  --no-lock          Run the replay outside the heavy-build lock (the build still takes it). For runs that would
                     hold the lock longer than its 20-minute budget.
USAGE
  exit 64
}

STORE="" REFUSALS="" LOG="" FRAMES="list" WINDOW="50" WORK="" REFERENCE="" SKIP_BUILD=0 NO_LOCK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --store) STORE="${2:?}"; shift 2 ;;
    --refusals) REFUSALS="${2:?}"; shift 2 ;;
    --log) LOG="${2:?}"; shift 2 ;;
    --frames) FRAMES="${2:?}"; shift 2 ;;
    --window) WINDOW="${2:?}"; shift 2 ;;
    --work) WORK="${2:?}"; shift 2 ;;
    --reference) REFERENCE="${2:?}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --no-lock) NO_LOCK=1; shift ;;
    *) usage ;;
  esac
done
[[ -n "${STORE}" && -n "${REFUSALS}" && -n "${LOG}" ]] || usage
[[ "${FRAMES}" == "list" || "${FRAMES}" == "touched" ]] || usage
[[ "${WINDOW}" =~ ^[1-9][0-9]*$ ]] || usage
[[ -f "${REFUSALS}" ]] || { echo "No refusal file at ${REFUSALS}" >&2; exit 66; }
[[ -z "${REFERENCE}" || -f "${REFERENCE}" ]] || { echo "No reference log at ${REFERENCE}" >&2; exit 66; }
REFUSALS="$(cd "$(dirname "${REFUSALS}")" && pwd)/$(basename "${REFUSALS}")"

if [[ -d "${STORE}" ]]; then
  shopt -s nullglob
  stores=("${STORE}"/*.sqlite)
  shopt -u nullglob
  [[ ${#stores[@]} -eq 1 ]] || { echo "Expected one .sqlite store in ${STORE}, found ${#stores[@]}" >&2; exit 66; }
  STORE_FILE="${stores[0]}"
else
  STORE_FILE="${STORE}"
fi
[[ -f "${STORE_FILE}" ]] || { echo "No store at ${STORE_FILE}" >&2; exit 66; }

if [[ -z "${WORK}" ]]; then
  WORK="$(mktemp -d /tmp/phone-replay.XXXXXX)"
else
  case "${WORK}" in /tmp/*|/private/tmp/*) ;; *) echo "--work must be under /tmp" >&2; exit 64 ;; esac
  [[ ! -e "${WORK}" ]] || { echo "${WORK} already exists; choose a new directory" >&2; exit 64; }
  mkdir -p "${WORK}"
fi
chmod 700 "${WORK}"
trap 'rm -rf "${WORK}"' EXIT

locked() {
  if [[ -x /usr/bin/lockf ]]; then /usr/bin/lockf -k "${LOCK_FILE}" "$@"; else "$@"; fi
}
load() {
  uptime | sed 's/.*load averages*: //'
}

# A credential-free copy: the session's refresh token, magic-code challenges, and share tokens are deleted.
NAME="$(basename "${STORE_FILE}")"
mkdir -p "${WORK}/store"
for suffix in "" -wal -shm; do
  if [[ -f "${STORE_FILE}${suffix}" ]]; then cp -p "${STORE_FILE}${suffix}" "${WORK}/store/${NAME}${suffix}"; fi
done
chmod 600 "${WORK}/store/"*
COPY="${WORK}/store/${NAME}"
for table in instant_auth_sessions instant_magic_code_challenges instant_shares; do
  exists="$(sqlite3 -cmd ".timeout 10000" "${COPY}" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = '${table}';")"
  if [[ "${exists}" == "1" ]]; then sqlite3 -cmd ".timeout 10000" "${COPY}" "DELETE FROM ${table};"; fi
done
[[ "$(sqlite3 "${COPY}" "PRAGMA quick_check;")" == "ok" ]] || { echo "The staged copy fails quick_check" >&2; exit 65; }
[[ "$(sqlite3 "${COPY}" "SELECT COUNT(*) FROM instant_auth_sessions;")" == "0" ]] || { echo "Auth rows remain" >&2; exit 65; }
echo "staged ${NAME} in ${WORK}/store; $(sqlite3 "${COPY}" "SELECT group_concat(status || ' ' || n, ', ') FROM (SELECT status, COUNT(*) AS n FROM instant_outbox GROUP BY status);")" >&2

if [[ "${SKIP_BUILD}" == 0 ]]; then
  free_kb="$(df -Pk "${ROOT}" | awk 'NR == 2 {print $4}')"
  if (( free_kb / 1024 / 1024 < MINIMUM_FREE_GB )); then
    echo "Only $(( free_kb / 1024 / 1024 )) GB free; the build needs ${MINIMUM_FREE_GB} GB (PHONE_REPLAY_MINIMUM_FREE_GB)" >&2
    exit 75
  fi
  echo "building tests at $(git -C "${ROOT}" rev-parse --short HEAD), $(date '+%H:%M:%S'), load $(load)" >&2
  if ! locked swift build --build-tests --package-path "${ROOT}" > "${LOG}.build" 2>&1; then
    grep -E "error:" "${LOG}.build" | grep -v maintenance.lock | head -20 >&2
    echo "The test build failed; see ${LOG}.build" >&2
    exit 1
  fi
fi

HEAD_LABEL="$(git -C "${ROOT}" rev-parse --short HEAD)"
[[ -z "$(git -C "${ROOT}" status --porcelain --untracked-files=no)" ]] || HEAD_LABEL="${HEAD_LABEL} (dirty)"
replay() {
  if [[ "${NO_LOCK}" == 1 ]]; then "$@"; else locked "$@"; fi
}
echo "replaying, $(date '+%H:%M:%S'); REPLAY lines go to ${LOG}" >&2
# One lock hold covers the whole measured block, so LOAD-BEFORE and LOAD-AFTER bracket the replay, not the wait.
MEASURED='
  echo "LOAD-BEFORE $(uptime | sed "s/.*load averages*: //") $(date "+%H:%M:%S") head $0"
  "$@" 2>&1 | grep --line-buffered -E "REPLAY|passed after|failed after|recorded an issue|error:|Fatal" \
    | grep --line-buffered -v maintenance.lock | cut -c1-600
  status=${PIPESTATUS[0]}
  echo "LOAD-AFTER $(uptime | sed "s/.*load averages*: //") $(date "+%H:%M:%S")"
  exit "${status}"
'
set +e
replay /bin/bash -c "${MEASURED}" "${HEAD_LABEL}" env \
  INSTANT_PHONE_REPLAY_STORE="${COPY}" \
  INSTANT_PHONE_REPLAY_REFUSALS="${REFUSALS}" \
  INSTANT_PHONE_REPLAY_FRAMES="${FRAMES}" \
  INSTANT_PHONE_REPLAY_WINDOW="${WINDOW}" \
  INSTANT_PHONE_REPLAY_SCRATCH="${WORK}" \
  swift test --package-path "${ROOT}" --skip-build --filter "${FILTER}" > "${LOG}"
status=$?
set -e
grep -E "^REPLAY (start|drain|declines)|Test run with" "${LOG}" >&2 || true
if [[ "${status}" != 0 ]]; then
  echo "The replay test failed (exit ${status}); see ${LOG}" >&2
fi
if [[ -n "${REFERENCE}" ]]; then
  set +e
  python3 "${HERE}/compare-replay-logs.py" "${REFERENCE}" "${LOG}"
  compared=$?
  set -e
  [[ "${status}" == 0 ]] || exit "${status}"
  exit "${compared}"
fi
exit "${status}"
