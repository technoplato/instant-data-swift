#!/usr/bin/env bash
# Type-checks the package's self-contained Darwin helpers for every Darwin target the package declares, the Apple
# Watch's arm64_32 first (#1019).
#
# Why: arm64_32 is ILP32, and Darwin declares some C parameters differently there (getattrlist's options are
# `unsigned int` on LP64 and `unsigned long` on ILP32, so Swift sees UInt32 on a Mac and UInt on a Watch). The macOS
# test suite never compiles watchOS, so a call that fails only there reached four tags (1.9.14-1.9.17) unseen and broke
# every app build that embeds a Watch app.
#
# Each entry below names a file and a top-level declaration that imports nothing beyond Foundation; the script cuts
# that declaration out of the file (from its first line to the first `}` at column 0) and type-checks it alone, so it
# needs no dependency builds and runs in seconds. A whole-package watchOS build is the fuller check (#1019).
#
# Usage: scripts/check-watchos-arm64_32.sh   (DEVELOPER_DIR selects an Xcode with the watchOS, iOS and macOS SDKs)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKS=(
  "Sources/InstantSwiftDataCore/InstantFileModels.swift|enum InstantFileBlocks"
)
# The narrowest pointer width first, then each platform at the package's minimum version (Package.swift).
TARGETS=(
  "arm64_32-apple-watchos9.0 watchos"
  "arm64-apple-watchos9.0 watchos"
  "arm64-apple-ios16.0 iphoneos"
  "arm64-apple-macosx14.0 macosx"
)

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
failures=0
for check in "${CHECKS[@]}"; do
  file="${check%%|*}"
  declaration="${check#*|}"
  source="${work}/$(basename "${file}" .swift)-$(echo "${declaration}" | tr -c 'A-Za-z0-9' '_').swift"
  # #sourceLocation keeps each diagnostic on the file's own path and line.
  { echo "import Foundation"; awk -v head="${declaration}" -v path="${file}" '
      index($0, head) == 1 { inside = 1; printf "#sourceLocation(file: \"%s\", line: %d)\n", path, NR }
      inside { print }
      inside && $0 == "}" { exit }
    ' "${ROOT}/${file}"; } > "${source}"
  if [[ "$(wc -l < "${source}")" -lt 3 ]]; then
    echo "FAIL ${file}: no top-level '${declaration}' to check" >&2
    failures=$((failures + 1))
    continue
  fi
  for target in "${TARGETS[@]}"; do
    triple="${target% *}"
    sdk="${target#* }"
    if output="$(xcrun --sdk "${sdk}" swiftc -target "${triple}" -parse-as-library -typecheck "${source}" 2>&1)"; then
      echo "ok   ${triple} ${file} (${declaration})"
    else
      echo "FAIL ${triple} ${file} (${declaration})" >&2
      echo "${output}" | grep -E 'error:' >&2
      failures=$((failures + 1))
    fi
  done
done
[[ "${failures}" -eq 0 ]]
