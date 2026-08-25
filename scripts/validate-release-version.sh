#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Usage: scripts/validate-release-version.sh <semver-without-v>" >&2
  exit 64
fi

RELEASE_DOC="${ROOT}/docs/releases/v${VERSION}.md"
if [[ ! -f "${RELEASE_DOC}" ]]; then
  echo "Missing release document: docs/releases/v${VERSION}.md" >&2
  exit 1
fi

LATEST_DOCUMENTED="$({
  find "${ROOT}/docs/releases" -maxdepth 1 -name 'v*.md' -print \
    | sed -E 's#^.*/v([^/]+)\.md$#\1#' \
    | sort -V \
    | tail -n 1
})"
if [[ "${VERSION}" != "${LATEST_DOCUMENTED}" ]]; then
  echo "Requested version ${VERSION} is not the latest documented version ${LATEST_DOCUMENTED}." >&2
  exit 1
fi

if git -C "${ROOT}" rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null; then
  echo "Tag v${VERSION} already exists." >&2
  exit 1
fi

for required in \
  'validation/run-performance-gate.sh' \
  'Swift→TypeScript' \
  'TypeScript→Swift' \
  'memory' \
  'throughput'
do
  if ! rg -q --fixed-strings "${required}" "${RELEASE_DOC}"; then
    echo "Release document must contain: ${required}" >&2
    exit 1
  fi
done

echo "Release version v${VERSION} is structurally valid; publication still requires green workflow gates."
