#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"

xcodegen generate \
  --spec "$script_dir/project.yml" \
  --project "$script_dir"
