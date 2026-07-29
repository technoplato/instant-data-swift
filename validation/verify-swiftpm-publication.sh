#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if [ -e "${ROOT}/.gitmodules" ]; then
  echo "error: published SwiftPM source must not require Git submodules" >&2
  exit 1
fi

if git -C "${ROOT}" ls-files --stage | awk '$1 == "160000" { found = 1 } END { exit !found }'
then
  echo "error: published SwiftPM source contains tracked Git submodules" >&2
  git -C "${ROOT}" ls-files --stage | awk '$1 == "160000" { print $4 }' >&2
  exit 1
fi

swift package --package-path "${ROOT}" dump-package >/dev/null
echo "SwiftPM publication surface is self-contained."
