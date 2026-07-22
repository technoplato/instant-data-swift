#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
package_root="${script_dir:h:h}"
derived_data="${REMINDERS_V3_DERIVED_DATA:-/tmp/reminders-v3-ios}"
host_build="${REMINDERS_V3_HOST_BUILD:-/tmp/reminders-v3-host-macro}"
destination="${REMINDERS_V3_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"

# Xcode 26.6 currently emits both host and simulator copies of a local SwiftPM
# macro executable, but may ask the host compiler to launch the simulator copy.
# Keep the correct host tool in that product slot while xcodebuild is running.
# The workaround is confined to DerivedData and can be removed when Xcode fixes
# the local-package macro product selection.
swift build \
  --package-path "$package_root" \
  --scratch-path "$host_build" \
  --target InstantSwiftData >/dev/null
host_plugin="$host_build/arm64-apple-macosx/debug/InstantSwiftDataMacros-tool"
plugin_destination="$derived_data/Build/Products/Debug-iphonesimulator/InstantSwiftDataMacros"

if [[ ! -x "$host_plugin" ]]; then
  print -u2 "Missing host macro executable at $host_plugin"
  exit 1
fi

(
  while true; do
    if [[ -f "$plugin_destination" ]] && ! cmp -s "$host_plugin" "$plugin_destination"; then
      install -m 755 "$host_plugin" "$plugin_destination"
    fi
    sleep 0.05
  done
) &
watcher_pid=$!

cleanup() {
  kill "$watcher_pid" 2>/dev/null || true
  wait "$watcher_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

xcodebuild \
  -project "$script_dir/RemindersV3.xcodeproj" \
  -scheme RemindersV3iOS \
  -sdk iphonesimulator \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

print "Built $derived_data/Build/Products/Debug-iphonesimulator/Reminders V3.app"
