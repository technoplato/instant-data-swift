# AudioCodecLab

The measurements behind ADR 0021 (`docs/adr/0021-progressive-media-over-instant.md`): which compressed format a
recording's audio travels in, what it costs to encode, and what plays it. A separate package with no dependency on the
library, so it builds in seconds and runs the same code on a Mac (the `audio-codec-lab` command) and on a phone (the
test target, run on the device by `xcodebuild`).

No audio is committed. Each run takes a mono 16-bit WAV of real speech (the lab's 2026-10-23 inputs were 5-minute
excerpts of a phone-microphone conversation and of an audiobook mixed with system audio, and a 3-minute quiet room),
and a 16 kHz reference beside it for quality scoring:

```sh
sox -G input.wav -r 16000 input.ref-16k.wav
```

## Commands

```sh
swift build -c release                      # through the machine's heavy-job queue where there is one
LAB=.build/arm64-apple-macosx/release/audio-codec-lab

$LAB probe                                  # encoders, decoders, playable MIME types, AVAssetWriter HLS support
$LAB encode --input in.wav --codec aac-lc --rate 24000 --bitrate 32000 --out-dir out --name aac-24k-32k
$LAB hls --input in.wav --codec aac-lc --rate 48000 --bitrate 32000 --segment 6 --out-dir out
$LAB play --url http://127.0.0.1:18767/live.m3u8 --seconds 150 --capture-start <epoch s> [--loader redirect]
```

- `scripts/run_matrix.sh <lab> <out> <python with pesq> <input.wav>...`: every candidate codec, rate and bit rate,
  then wideband PESQ (ITU-T P.862.2) of each decoded file (`scripts/score_pesq.py`). `CONFIG_SET=core REPS=1` runs only
  the candidates once; the phone measures CPU.
- `scripts/run_hls.sh`: AVAssetWriter's fragmented MP4 HLS segments for each candidate.
- `scripts/live_hls_server.py <segments> --port 18767 --elapsed 40 [--pause 70:100]`: serves a segment folder as a live
  EVENT playlist that grows in real time, listing each segment 10 s after its last sample plus 1.5 s; `--pause` stops
  the listing for a while, as a phone that goes offline does. Pick a free port: another process may hold a familiar one.
- `scripts/run_on_phone.sh <speech.wav> <device id> <team>`: `DeviceMatrixTests` on a phone, at the default and the
  background QoS (performance and efficiency cores).
- `scripts/browser_check.html`: what a browser plays (MSE and `<audio>`), driven headless.

## Results

`results/` holds the 2026-10-23 runs as JSON lines, without paths: `2026-10-23-mac-codecs.jsonl` (sizes and PESQ),
`2026-10-23-mac-playback.jsonl` (AVPlayer following a live playlist, with and without a pause in the uploads). ADR 0021
tabulates them.
