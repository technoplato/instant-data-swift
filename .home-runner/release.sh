#!/usr/bin/env bash
# The only supported publisher for Instant Swift Data tags.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${HOME_RUNNER_RESULTS_DIR:-${ROOT}/.home-runner-results}/release"
rm -rf "${RESULTS}"
mkdir -p "${RESULTS}"

CURRENT="$(git -C "${ROOT}" rev-parse HEAD)"
MAIN="$(git -C "${ROOT}" ls-remote origin refs/heads/main | awk '{print $1}')"
if [[ -z "${MAIN}" || "${CURRENT}" != "${MAIN}" ]]; then
  echo "Release jobs must target the exact current main commit." >&2
  echo "current=${CURRENT} main=${MAIN:-missing}" >&2
  exit 1
fi

VERSION="$({
  find "${ROOT}/docs/releases" -maxdepth 1 -name 'v*.md' -print \
    | sed -E 's#^.*/v([^/]+)\.md$#\1#' \
    | sort -V \
    | tail -n 1
})"
: "${VERSION:?No release document found}"

git -C "${ROOT}" fetch --tags --force
"${ROOT}/scripts/validate-release-version.sh" "${VERSION}" \
  2>&1 | tee "${RESULTS}/version.log"

# Publication is downstream of the full deterministic + credentialed live gate.
"${ROOT}/.home-runner/performance-live.sh"
cp -R "${HOME_RUNNER_RESULTS_DIR}/performance-live" "${RESULTS}/performance-live"

gh auth status
gh auth setup-git
git -C "${ROOT}" config user.name "technoplato"
git -C "${ROOT}" config user.email "6922904+technoplato@users.noreply.github.com"
git -C "${ROOT}" tag -a "v${VERSION}" -m "Instant Swift Data v${VERSION}"
git -C "${ROOT}" push origin "v${VERSION}"

gh release create "v${VERSION}" \
  --repo "${HOME_RUNNER_REPO:-technoplato/instant-data-swift}" \
  --verify-tag \
  --title "v${VERSION}" \
  --notes-file "${ROOT}/docs/releases/v${VERSION}.md"

cat >"${RESULTS}/published.json" <<EOF
{
  "case": "instant-swift-data.home-runner.release",
  "ok": true,
  "version": "${VERSION}",
  "tag": "v${VERSION}",
  "commit": "${CURRENT}",
  "performanceEvidence": "performance-live/evidence.json"
}
EOF

echo "Published Instant Swift Data v${VERSION} from ${CURRENT}."
