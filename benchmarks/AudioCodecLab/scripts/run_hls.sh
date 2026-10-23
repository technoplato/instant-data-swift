#!/bin/bash
# Fragmented MP4 HLS segments through AVAssetWriter for each candidate (#1012, ADR 0021): size, CPU (the fastest of
# three runs) and whether AVFoundation plays the joined file, then each segment set's decoded quality is not scored
# here (run_matrix.sh scores the codecs); this measures the segmenter and the container.
#
#   run_hls.sh <lab-binary> <out-dir> <input.wav>
set -euo pipefail
LAB=$1; OUT=$2; INPUT=$3
mkdir -p "$OUT"
RESULTS="$OUT/hls.jsonl"
: > "$RESULTS"
CONFIGS=(
  "aac-lc 48000 32000 6" "aac-lc 48000 32000 10" "aac-lc 48000 32000 2" "aac-lc 48000 64000 6"
  "aac-lc 24000 24000 6" "he-aac 48000 32000 6" "he-aac 48000 24000 6" "opus 48000 24000 6" "opus 48000 32000 6"
)
for c in "${CONFIGS[@]}"; do
  set -- $c
  for rep in 1 2 3; do
    ${TASKPOLICY:-} "$LAB" hls --input "$INPUT" --codec "$1" --rate "$2" --bitrate "$3" --segment "$4" \
      --out-dir "$OUT" --name "$1-$2-$3-${4}s" | sed "s/^{/{\"rep\":$rep,/" >> "$RESULTS" || true
  done
  "$LAB" check --file "$OUT/$1-$2-$3-${4}s/whole.mp4" >> "$RESULTS" || true
done
echo "results: $RESULTS"
