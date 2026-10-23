#!/bin/bash
# The codec matrix behind ADR 0021 (#1012): every candidate codec, rate and bit rate on each input, three runs
# each (the CPU figure is the fastest of the three), then wideband PESQ of each decoded file.
#
#   run_matrix.sh <lab-binary> <out-dir> <python-with-pesq> <input.wav> [<input.wav> ...]
#
# Each input needs a 16 kHz reference beside it named <input>.ref-16k.wav (sox -G <input>.wav -r 16000 ...).
# Set TASKPOLICY="taskpolicy -c background" to measure on efficiency cores only. REPS (default 3) sets the runs per
# config; CONFIG_SET=core runs only the candidates (sizes and quality; the phone measures CPU, DeviceMatrixTests).
set -euo pipefail
LAB=$1; OUT=$2; PY=$3; shift 3
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
RESULTS="$OUT/results.jsonl"
: > "$RESULTS"
# codec rate bitrate [quality|-] [frames-per-packet]. AAC-LC takes 32 kbps and up at 48 kHz (AudioToolbox's
# ApplicableEncodeBitRates), so its lower rates run at 24 or 16 kHz. Opus runs in 20 ms packets unless a frame count
# is given; 120 frames (2.5 ms) is AudioToolbox's own default, kept for the record.
CONFIGS=(
  "aac-lc 48000 32000" "aac-lc 48000 48000" "aac-lc 48000 64000"
  "aac-lc 24000 24000" "aac-lc 24000 32000" "aac-lc 16000 24000"
  "he-aac 48000 24000" "he-aac 48000 32000" "he-aac 24000 24000"
  "opus 48000 16000" "opus 48000 24000" "opus 48000 32000" "opus 48000 48000"
  "opus 16000 16000" "opus 16000 24000" "opus 24000 24000"
  "opus 48000 24000 - 120"
  "aac-lc 48000 32000 min" "aac-lc 48000 32000 medium" "aac-lc 48000 32000 high" "aac-lc 48000 32000 max"
  "opus 48000 24000 min" "opus 48000 24000 medium" "opus 48000 24000 max"
)
if [ "${CONFIG_SET:-full}" = core ]; then
  CONFIGS=(
    "aac-lc 48000 32000" "aac-lc 48000 48000" "aac-lc 48000 64000" "aac-lc 24000 24000" "aac-lc 24000 32000"
    "aac-lc 16000 24000" "he-aac 48000 24000" "he-aac 48000 32000"
    "opus 48000 16000" "opus 48000 24000" "opus 48000 32000" "opus 16000 16000"
  )
fi
REPS=${REPS:-3}
for input in "$@"; do
  base=$(basename "$input" .wav)
  dir="$OUT/$base"
  mkdir -p "$dir"
  run() { # codec rate bitrate [quality|-] [frames-per-packet]
    local quality=${4:-}; [ "$quality" = "-" ] && quality=""
    local fpp=${5:-}
    local name="$1-$2-$3${quality:+-$quality}${fpp:+-fpp$fpp}"
    for rep in $(seq 1 "$REPS"); do
      local extra=()
      [ "$rep" = 1 ] && extra=(--out-dir "$dir" --name "$name")
      ${TASKPOLICY:-} "$LAB" encode --input "$input" --codec "$1" --rate "$2" --bitrate "$3" \
        ${quality:+--quality $quality} ${fpp:+--frames-per-packet $fpp} ${extra[@]+"${extra[@]}"} \
        | sed "s/^{/{\"input\":\"$base\",\"name\":\"$name\",\"rep\":$rep,/" >> "$RESULTS" || true
    done
  }
  for c in "${CONFIGS[@]}"; do run $c; done
  # The reference Opus encoder (libopus through ffmpeg), for quality only: its CPU is not measured here.
  if command -v ffmpeg >/dev/null; then
    for kbps in 16 24 32; do
      ffmpeg -loglevel error -y -i "$input" -c:a libopus -b:a ${kbps}k -application voip -frame_duration 20 \
        "$dir/libopus-$kbps.opus"
      ffmpeg -loglevel error -y -i "$dir/libopus-$kbps.opus" -ar 16000 -ac 1 "$dir/libopus-48000-${kbps}000.decoded-16k.wav"
    done
  fi
  "$PY" "$HERE/score_pesq.py" "${input%.wav}.ref-16k.wav" "$dir"/*.decoded-16k.wav \
    | sed "s/^{/{\"input\":\"$base\",/" >> "$RESULTS"
done
echo "results: $RESULTS"
