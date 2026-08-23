#!/usr/bin/env bash
# Queue an exact target commit on technoplato/home-runner and block until it exits.
set -euo pipefail

JOB="${1:?job name}"
REF="${2:?target branch, tag, or commit}"
REPO="${3:-${GITHUB_REPOSITORY:-technoplato/instant-data-swift}}"
CONTROL_REPO="${HOME_RUNNER_CONTROL_REPO:-technoplato/home-runner}"
WORKFLOW="${HOME_RUNNER_WORKFLOW:-run-job.yml}"

: "${GH_TOKEN:?GH_TOKEN must be HOME_RUNNER_TOKEN with Actions read/write access to ${CONTROL_REPO}}"
if [[ ! "${JOB}" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "invalid home-runner job: ${JOB}" >&2
  exit 64
fi

TITLE="${REPO}:${JOB}@${REF}"
QUEUED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Queueing ${TITLE}"
gh workflow run "${WORKFLOW}" \
  --repo "${CONTROL_REPO}" \
  -f repo="${REPO}" \
  -f job="${JOB}" \
  -f ref="${REF}"

RUN_ID=""
for _ in {1..60}; do
  RUN_ID="$({
    gh run list \
      --repo "${CONTROL_REPO}" \
      --workflow "${WORKFLOW}" \
      --event workflow_dispatch \
      --limit 50 \
      --json databaseId,displayTitle,createdAt
  } | jq -r \
      --arg title "${TITLE}" \
      --arg queued "${QUEUED_AT}" \
      '.[] | select(.displayTitle == $title and .createdAt >= $queued) | .databaseId' \
      | head -n 1)"
  [[ -n "${RUN_ID}" ]] && break
  sleep 2
done

if [[ -z "${RUN_ID}" ]]; then
  echo "Could not locate dispatched run ${TITLE}" >&2
  exit 1
fi

echo "Watching ${CONTROL_REPO} run ${RUN_ID}: ${TITLE}"
gh run watch "${RUN_ID}" --repo "${CONTROL_REPO}" --exit-status
echo "Home runner passed: https://github.com/${CONTROL_REPO}/actions/runs/${RUN_ID}"
