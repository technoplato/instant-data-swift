#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
package_root="${script_dir:h:h}"
derived_data="${INSTANT_RECIPES_DERIVED_DATA:-/tmp/instant-recipes-v3-platforms}"
host_build="${INSTANT_RECIPES_HOST_BUILD:-/tmp/instant-recipes-v3-host-macro}"

"$script_dir/generate-project.sh"

swift build \
  --package-path "$package_root" \
  --scratch-path "$host_build" \
  --target InstantSwiftData >/dev/null
host_plugin="$host_build/arm64-apple-macosx/debug/InstantSwiftDataMacros-tool"

if [[ ! -x "$host_plugin" ]]; then
  print -u2 "Missing host macro executable at $host_plugin"
  exit 1
fi

plugin_destinations=(
  "$derived_data/Build/Products/Debug-iphonesimulator/InstantSwiftDataMacros"
  "$derived_data/Build/Products/Debug-appletvsimulator/InstantSwiftDataMacros"
  "$derived_data/Build/Products/Debug-watchsimulator/InstantSwiftDataMacros"
)

(
  while true; do
    for plugin_destination in "${plugin_destinations[@]}"; do
      if [[ -f "$plugin_destination" ]] && ! cmp -s "$host_plugin" "$plugin_destination"; then
        install -m 755 "$host_plugin" "$plugin_destination"
      fi
    done
    sleep 0.05
  done
) &
watcher_pid=$!

cleanup() {
  kill "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

build() {
  local scheme="$1"
  local destination="$2"
  local deployment_setting="$3"
  xcodebuild \
    -project "$script_dir/InstantRecipesV3.xcodeproj" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    "$deployment_setting" \
    build
}

build InstantRecipesV3macOS \
  "${INSTANT_RECIPES_MACOS_DESTINATION:-generic/platform=macOS}" \
  "MACOSX_DEPLOYMENT_TARGET=14.0"
build InstantRecipesV3iOS \
  "${INSTANT_RECIPES_IOS_DESTINATION:-generic/platform=iOS Simulator}" \
  "IPHONEOS_DEPLOYMENT_TARGET=17.0"
build InstantRecipesV3tvOS \
  "${INSTANT_RECIPES_TVOS_DESTINATION:-generic/platform=tvOS Simulator}" \
  "TVOS_DEPLOYMENT_TARGET=17.0"
build InstantRecipesV3watchOS \
  "${INSTANT_RECIPES_WATCHOS_DESTINATION:-generic/platform=watchOS Simulator}" \
  "WATCHOS_DEPLOYMENT_TARGET=10.0"

print "Built macOS, iOS, tvOS, and watchOS apps under $derived_data/Build/Products"
