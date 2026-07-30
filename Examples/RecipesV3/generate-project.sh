#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
package_root="${script_dir:h:h}"
temporary_parent="$(mktemp -d "${TMPDIR:-/tmp}/instant-xcodegen-alias.XXXXXX")"
stable_package_root="$temporary_parent/instant-data-swift"

cleanup() {
  unlink "$stable_package_root" 2>/dev/null || true
  rmdir "$temporary_parent" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# XcodeGen names a local package from its checkout directory. Generate through
# a stable alias so worktree names do not dirty the tracked project or its IDs.
ln -s "$package_root" "$stable_package_root"
xcodegen generate \
  --spec "$stable_package_root/Examples/RecipesV3/project.yml" \
  --project "$stable_package_root/Examples/RecipesV3"

cleanup
trap - EXIT INT TERM
