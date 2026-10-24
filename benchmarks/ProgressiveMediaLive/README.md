# ProgressiveMediaLive

Progressive media end to end over a live Instant app (#1012, ADR 0021). One client plays the part of the recording
device: a WAV is played out in real time, and every 5 s heartbeat the audio that is final (all but its last 10 s, the
margin a recorder keeps for late mixing) goes through `InstantAudioSegmenter` and `InstantProgressiveMediaWriter`, which
stores each 6 s segment in `$files` and lists it in rows. A second client, signed in as the same user with its own
store, plays the part of another device: it waits for the first listed segment (or `--join` seconds), then plays the
stream through AVPlayer and `InstantProgressiveMediaResourceLoader`. Every 2 s it prints how far the player is behind
the recording's live edge. At Stop the rest is stored, the stream finishes, and the finished playlist plays from its
start and from its middle. The rows and files are deleted at the end.

## Run

On a Mac (macOS 15), against a throwaway app only (the tool refuses the consuming app's production ids). It signs in as
a guest, so it needs no admin token, and it uploads the audio, so use speech nobody minds being uploaded:

```sh
say -o speech.aiff -f some-public-domain-text.txt
afconvert -f WAVE -d LEI16@48000 -c 1 speech.aiff speech.wav
swift build -c debug
INSTANT_APP_ID=<throwaway app id> .build/debug/progressive-media-live speech.wav --seconds 180 --margin 10 [--join 90]
```

The package depends on the checkout above it by path, so that checkout's folder must be named `instant-data-swift`
(a local package's identity is its folder's name). The files go under `library/<user>/progressive-media-live/`, the
one place the throwaway app's storage rules let a user write.

## Results

`results/live-instant.jsonl`, one summary line a run (Mac mini M4, macOS 26, Xcode 27 beta, the throwaway app,
2026-10-23; 216 s of synthesized speech from the opening of Alice's Adventures in Wonderland):

- **First segment listed on the other client:** 22.0-22.8 s after the recording started: the 10 s margin, up to 5 s
  until the next heartbeat, the 6 s segment, its upload and its rows.
- **Behind the live edge while it records:** opened at the first listed segment, the player starts at the stream's
  start and stays 29.2 s (60 s run) and 29.5 s (180 s run, 89 samples, every one) behind, with no stall. Opened 90 s
  in (`--join 90`), AVPlayer starts about three segments behind the newest and stays 37.0 s behind (60 samples, every
  one), with no stall: the gap another device sees when it opens a recording that is under way, close to the Mac's
  local measurement in ADR 0021 (37.5-41.7 s). Both are under the 60 s #1012 asks for.
- **Stop:** the other client lists the stream whole within 0.1 s of its next look, and the finished playlist (31
  segments, 180.1 s) plays from its start and from its middle.
- **Clean up:** every run deleted what it wrote (12, 32 and 32 rows and files).
