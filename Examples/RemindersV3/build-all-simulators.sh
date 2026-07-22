#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
package_root="${script_dir:h:h}"
derived_data="${REMINDERS_V3_DERIVED_DATA:-/tmp/reminders-v3-simulators}"
host_build="${REMINDERS_V3_HOST_BUILD:-/tmp/reminders-v3-host-macro}"

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
  xcodebuild \
    -project "$script_dir/RemindersV3.xcodeproj" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    ARCHS=arm64 \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    build
}

build RemindersV3iOS "${REMINDERS_V3_IOS_DESTINATION:-generic/platform=iOS Simulator}"
build RemindersV3tvOS "${REMINDERS_V3_TVOS_DESTINATION:-generic/platform=tvOS Simulator}"
build RemindersV3watchOS "${REMINDERS_V3_WATCHOS_DESTINATION:-generic/platform=watchOS Simulator}"

print "Built iOS, tvOS, and watchOS apps under $derived_data/Build/Products"
