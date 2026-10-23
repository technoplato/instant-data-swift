#!/bin/bash
# Runs the codec matrix on a phone (#1012, ADR 0021): DeviceMatrixTests through xcodebuild, on the device's own cores.
#
#   run_on_phone.sh <speech.wav> <xcodebuild destination id> [<development team>]
#
# The excerpt is copied into the test bundle for this run only and removed afterwards; it never enters git. Each
# result is printed as one "CODEC-LAB {json}" line and kept in $OUT (default /tmp/audio-codec-lab-phone.jsonl).
# Xcode 27 drives an iOS 27 phone (Xcode 26's tools list it as offline), so DEVELOPER_DIR points at the beta. The phone
# must have its developer disk image mounted (plugged in and unlocked once), or xcodebuild finds no such destination.
# HEAVY_RUNNER, when set, is a job queue the command runs under (`$HEAVY_RUNNER <label> <command>`).
set -euo pipefail
WAV=$1
DESTINATION=$2
TEAM=${3:-${DEVELOPMENT_TEAM:-}}
OUT=${OUT:-/tmp/audio-codec-lab-phone.jsonl}
HERE=$(cd "$(dirname "$0")" && pwd)
PACKAGE=$(dirname "$HERE")
RESOURCE="$PACKAGE/Tests/AudioCodecLabTests/Resources/speech.wav"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}

cp "$WAV" "$RESOURCE"
trap 'rm -f "$RESOURCE"' EXIT
cd "$PACKAGE"
${HEAVY_RUNNER:+$HEAVY_RUNNER audio-codec-lab-phone} \
  xcodebuild test -scheme AudioCodecLab-Package -destination "id=$DESTINATION" \
  -only-testing:AudioCodecLabTests/DeviceMatrixTests -allowProvisioningUpdates ${TEAM:+DEVELOPMENT_TEAM=$TEAM} \
  -jobs 4 2>&1 | tee /tmp/audio-codec-lab-phone.log | sed -n 's/^.*CODEC-LAB //p' | tee "$OUT"
echo "results: $OUT (full log /tmp/audio-codec-lab-phone.log)"
