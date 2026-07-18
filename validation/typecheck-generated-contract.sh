#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
GENERATED="$(mktemp -d "${RUNNER}/.generated-contract.XXXXXX")"
trap 'rm -rf "${GENERATED}"' EXIT

EXPECTED_UPSTREAM_REVISION="$(
  cd "${RUNNER}"
  node -p "require('./package.json').instantContract.upstreamRevision"
)"
UPSTREAM_REVISION="$(git -C "${ROOT}/upstream/instant" rev-parse HEAD)"
if [[ "${UPSTREAM_REVISION}" != "${EXPECTED_UPSTREAM_REVISION}" ]]; then
  echo "Pinned Instant revision mismatch: expected ${EXPECTED_UPSTREAM_REVISION}, found ${UPSTREAM_REVISION}." >&2
  exit 1
fi

for example in validation recording-action; do
  swift run --package-path "${ROOT}" instant-swift-data schema generate \
    --example "${example}" \
    --to "${GENERATED}/${example}.schema.ts" \
    --json >/dev/null
  swift run --package-path "${ROOT}" instant-swift-data perms generate \
    --example "${example}" \
    --to "${GENERATED}/${example}.perms.ts" \
    --json >/dev/null
done

cp \
  "${ROOT}/validation/fixtures/recording-action.server.schema.ts" \
  "${GENERATED}/recording-action.server.schema.ts"
cp \
  "${ROOT}/validation/fixtures/recording-action.server.perms.ts" \
  "${GENERATED}/recording-action.server.perms.ts"

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json

sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

CORE_VERSION="$(cd "${RUNNER}" && node -p "require('./package.json').dependencies['@instantdb/core']")"
ADMIN_VERSION="$(cd "${RUNNER}" && node -p "require('./package.json').dependencies['@instantdb/admin']")"
TYPESCRIPT_VERSION="$(cd "${RUNNER}" && node -p "require('./package.json').devDependencies.typescript")"

printf '{"case":"validation.typescript.generated-contract","event":"typecheck","ok":true,"details":{"upstreamRevision":"%s","coreVersion":"%s","adminVersion":"%s","typescriptVersion":"%s","compilerWarningCount":0,"artifacts":{"validationSchemaSHA256":"%s","validationPermissionsSHA256":"%s","recordingActionSchemaSHA256":"%s","recordingActionPermissionsSHA256":"%s","serverRecordingActionSchemaSHA256":"%s","serverRecordingActionPermissionsSHA256":"%s"}}}\n' \
  "${UPSTREAM_REVISION}" \
  "${CORE_VERSION}" \
  "${ADMIN_VERSION}" \
  "${TYPESCRIPT_VERSION}" \
  "$(sha256 "${GENERATED}/validation.schema.ts")" \
  "$(sha256 "${GENERATED}/validation.perms.ts")" \
  "$(sha256 "${GENERATED}/recording-action.schema.ts")" \
  "$(sha256 "${GENERATED}/recording-action.perms.ts")" \
  "$(sha256 "${GENERATED}/recording-action.server.schema.ts")" \
  "$(sha256 "${GENERATED}/recording-action.server.perms.ts")"
