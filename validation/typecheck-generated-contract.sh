#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/validation/ts-runner"
GENERATED="${RUNNER}/.generated"

rm -rf "${GENERATED}"
mkdir -p "${GENERATED}"
trap 'rm -rf "${GENERATED}"' EXIT

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

pnpm --dir "${RUNNER}" exec tsc --noEmit --project tsconfig.json
