#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
package_root="${script_dir:h:h}"
derived_data="${VOICE_TRAIL_V3_DERIVED_DATA:-/tmp/voicetrail-v3-watch}"
host_build="${VOICE_TRAIL_V3_HOST_BUILD:-/tmp/voicetrail-v3-host-macro}"

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

plugin_destination="$derived_data/Build/Products/Debug-watchsimulator/InstantSwiftDataMacros"

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
  -project "$script_dir/VoiceTrailV3.xcodeproj" \
  -scheme VoiceTrailV3watchOS \
  -destination "${VOICE_TRAIL_V3_WATCHOS_DESTINATION:-generic/platform=watchOS Simulator}" \
  -derivedDataPath "$derived_data" \
  ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=YES \
  WATCHOS_DEPLOYMENT_TARGET=10.0 \
  build

print "Built VoiceTrailV3watchOS under $derived_data/Build/Products"
