# ADR 0021: Progressive Media Travels as Compressed Segments in `$files`, Listed by Rows, Played as HLS

- Status: Proposed (measurements below; the owner's ask, typed 2026-10-23 12:30: "It would be nice to have a library
  primitive for streaming progressive audio file over instant. Because right now, if I'm remote, I can't play back
  the audio. I'd like to be able to play it back. Is there a more compressed file format that would be useful there?")
- Date: 2026-10-23
- Issue: #1012 (part of #1005; related: #533, #651, #454, #807, #959, #082, #253)
- Scope: a new append-only media primitive: the segment spool and its uploader, the manifest rows, the reader that
  turns rows into an HLS media playlist, and (in a new `InstantSwiftDataMedia` target) the AVFoundation segmenter and
  player glue. Nothing in the entity sync path, the outbox, streams (ADR 0017) or `uploadFile` changes.

## Context

An always-on recorder keeps its audio as a 48 kHz, 16-bit, mono WAV: 5.76 MB a minute, 2.0 GB for a 5.8-hour day.
Today that audio reaches other devices three ways, and none of them lets a listener away from the recording device
play it while it records, or play a long recording without first downloading all of it:

- While recording, the app cuts 60 s WAV chunks 10 s behind the end of the file (system audio is mixed into the file
  up to 10 s late), uploads each with `uploadFile`, and links it from a chunk row. On cellular, on battery, a chunk
  waits for Wi-Fi. A desktop mirror assembles the chunks; measured on 2026-10-23, a chunk reached it 13-25 s after its
  last sample, with spikes of 98-165 s, so a listener following the chunks would be up to about 85 s behind, and no
  player follows them.
- At the end of a recording the whole WAV goes up as one `PUT`, which can fail for a long recording and restarts from
  byte 0.
- Another device opens a recording by downloading the whole WAV before it plays a sample.

The library's own pieces do not cover it:

- `uploadFile(from:name:contentType:)` is one `PUT {apiURI}/storage/upload` that waits for the server. Nothing queues
  it on disk, retries it, or resumes it after a relaunch.
- Streams (ADR 0017) carry UTF-8 text. Audio would travel as Base64 (a third larger), and every read of a stream
  returns everything written so far, so a reader of a growing hour of audio reads the hour again on every append.
- The frame types in `InstantMediaStreamFrames.swift` and the buffer in `InstantMediaStreamBuffer.swift` describe and
  bound media in memory; nothing sends them anywhere.
- ADR 0001 already says how media must behave: "Media bytes never sit on the entity synchronization critical path",
  each item persists enough state to retry after a relaunch, and a rejection is isolated to its item or stream.

### What upstream does

`upstream/instant/client/packages/core/src` (pinned e7101761):

- `StorageAPI.ts` `uploadFile`: one `PUT {apiURI}/storage/upload` with headers `app_id`, `path`, `authorization` and
  `content-type`, answered by `{ data: { id } }`, the `$files` row's id. A file is named by its `path`; uploading the
  same path again replaces the bytes. No queue, retry or progress.
- A file's URL is not stored. `server/src/instant/db/instaql.clj` `add-url-to-join-rows` mints it whenever a query
  reads `$files.url`: a presigned S3 `GET` valid for 7 days (`storage/s3.clj`, `Duration/ofDays 7`), signed at a time
  rounded to the UTC day, so the same file's URL is stable for about a day.
- `Stream.ts`: a text `WritableStream` buffered in memory; files appear only as the server's flushed 1 MB pieces of a
  stream's text. There is no media primitive upstream.

### What the formats measure

All figures come from `benchmarks/AudioCodecLab` (its README says how to rerun each), on two 5-minute excerpts of real
recordings (a phone-microphone conversation; an audiobook played from a speaker and mixed with system audio) and a
3-minute quiet stretch. Quality is wideband PESQ (ITU-T P.862.2, MOS-LQO, 4.64 at best) over 10 s windows of speech,
against a 16 kHz reference. The encoders are AudioToolbox's own; `libopus` (through ffmpeg) is the reference Opus
encoder, for quality only.

| Format (mono) | Bytes a minute | vs the WAV | PESQ, conversation | PESQ, audiobook | PESQ, quiet room |
| --- | ---: | ---: | ---: | ---: | ---: |
| WAV, 48 kHz 16-bit (today) | 5,760,000 | 1x | (reference) | (reference) | (reference) |
| AAC-LC, 48 kHz, 64 kbps | 487,800 | 11.8x smaller | 4.51 | 4.56 | 4.56 |
| AAC-LC, 48 kHz, 48 kbps | 366,400 | 15.7x | 4.39 | 4.46 | 4.45 |
| AAC-LC, 48 kHz, 32 kbps | 243,100 | 23.7x | 4.17 | 3.96 | 3.99 |
| **AAC-LC, 24 kHz, 32 kbps** | **242,800** | **23.7x** | **4.32** | **4.11** | **4.28** |
| AAC-LC, 24 kHz, 24 kbps | 182,400 | 31.6x | 4.08 | 3.65 | 3.86 |
| AAC-LC, 16 kHz, 24 kbps | 182,600 | 31.5x | 4.06 | 3.50 | 3.89 |
| HE-AAC, 48 kHz, 32 kbps | 243,900 | 23.6x | 4.16 | 3.89 | 4.06 |
| HE-AAC, 48 kHz, 24 kbps | 183,000 | 31.5x | 3.95 | 3.57 | 3.90 |
| Opus (AudioToolbox, 20 ms), 32 kbps | 242,000 | 23.8x | 4.37 | 4.13 | 4.02 |
| Opus (AudioToolbox, 20 ms), 24 kbps | 178,400 | 32.3x | 4.35 | 4.11 | 3.45 |
| Opus (AudioToolbox, 20 ms), 16 kbps | 117,100 | 49.2x | 4.32 | 4.06 | 3.47 |
| Opus (libopus through ffmpeg, voip), 24 kbps | (reference encoder) | | 4.39 | 4.21 | 3.54 |

Sizes are the conversation's; AAC's encoder holds its rate (243 KB a minute on all three inputs at 32 kbps), Opus's
varies a little with the content (113-120 KB at 16 kbps). PESQ's quiet-room column scores all 18 of its ten-second
windows with sound above -45 dBFS.

AudioToolbox's AAC-LC encoder takes 32 kbps and up at 48 kHz (`kAudioConverterApplicableEncodeBitRates`), so a lower
AAC rate means a lower sample rate. At 32 kbps the 24 kHz encoder spends its bits below 12 kHz, where speech is, and
scores higher than the 48 kHz encoder at the same size, on all three inputs. Opus is the better speech codec, as its
designers built it to be: at 16 kbps it matches AAC-LC at 32 kbps on close speech. On a quiet room, though, Apple's Opus
encoder drops to 3.45-3.47 (its variable rate spends little on low-level sound), where AAC-LC at 24 kHz keeps 4.28.
HE-AAC buys nothing for speech at these rates.

CPU, measured on this Mac (an M1 Max under heavy load from other builds, one run per format, so an upper bound): AAC-LC at 24 kHz and 32 kbps took 0.082 CPU seconds per minute of audio (0.14% of a core while recording), at 48 kHz 0.122; Opus at 24 kbps 0.715. AVAssetWriter's segmenter with AAC-LC at 48 kHz, whose encoder runs on its own threads, measured 0.18 CPU seconds a minute in all. The iPhone's figure, on its performance and efficiency cores, waits for the phone to be reachable by xcodebuild (`DeviceMatrixTests`); the budget is well under 1% of a core.

What plays them, measured:

- **AVFoundation segments AAC-LC into HLS fragmented MP4 directly.** `AVAssetWriter` with
  `outputFileTypeProfile = .mpeg4AppleHLS` and a 6 s `preferredOutputSegmentInterval` emits one initialization
  segment (612 bytes) and one self-contained 6 s media segment (about 25.7 KB at 32 kbps) at a time, through its
  delegate, with no file on disk. Init plus the segments in order is itself a valid MP4 that AVFoundation plays.
- **Opus through the same writer is not usable.** `AVAssetWriter` writes Opus in 2.5 ms packets (AudioToolbox's
  default; it exposes no packet-size setting), so a 24 kbps Opus stream measures 44.5 kbps in fMP4, at three times
  AAC-LC's CPU on the same machine.
- **AVPlayer follows a growing playlist** (macOS 26.5): an EVENT playlist of 6 s AAC-LC segments, each listed 10 s
  after its last sample is captured (the mix margin) plus 1.5 s (upload and manifest sync), played 37.5 s behind
  capture, steady, with 0 stalls over 150 s. 21 s of that is AVPlayer's own hold-back (three target durations).
- **AVPlayer fails a live playlist that lists nothing yet.** Given an EVENT playlist with no segment, it fails the item
  for good (CoreMedia -12888, "Playlist File unchanged for longer than 1.5 * target duration").
- **A pause in the uploads stalls a listener; a long one stops it.** With uploads paused for 30 s (the playlist
  unchanged), AVPlayer stalled once for about 7 s and played on, 48.7 s behind instead of 41.7. Paused for 2 minutes,
  it played out its buffer, set its rate to 0 without an error, and stayed paused after the playlist grew again.
- **AVPlayer plays a playlist an `AVAssetResourceLoader` serves from memory, and follows a redirect for each file**
  (Apple's AVARLDelegateDemo pattern: a custom URL scheme answered with the playlist's bytes, and each initialization
  or media segment answered with a 302 to its real URL). A finished playlist played after 1 s; a growing one played
  41.7 s behind capture, steady, with 0 stalls over 2 minutes (19 playlist reloads, 25 redirects). It does not treat a
  `file://` playlist as HLS: the item never became ready.
- **Chrome 155** (desktop, headless): AAC-LC fMP4 plays as native HLS (`canPlayType` of `application/vnd.apple.mpegurl`
  answers "maybe"), through Media Source Extensions, and as one joined file. Apple's Opus fMP4 fails in Media Source
  Extensions and as HLS, and plays only as one joined file.
- **watchOS** has `AVPlayer` and `AVAudioEngine` but neither `AVAssetResourceLoader` nor `AVAssetWriter` (Xcode 27
  SDK headers, `API_UNAVAILABLE(watchos)`).

## Options

1. **Keep WAV chunks and add a player for them.** 23.7 times the bytes of AAC-LC on every network, 60 s chunks put a
   listener a minute or more behind, and no browser or Apple player follows a series of WAV files.
2. **Audio in streams (ADR 0017).** Base64 text, a read that returns everything written so far, and server-side 1 MB
   flushes that decide when bytes become readable. Built for text; wrong for media.
3. **One growing file.** Storage objects are immutable: every append would upload the whole file again.
4. **Opus.** The best codec for speech, but on Apple's side only through our own muxer (AVAssetWriter's Opus is
   44.5 kbps for 24 kbps), and Chrome rejects Apple's Opus fMP4 in Media Source Extensions and HLS. Its 2x size
   advantage does not pay for a player that works in fewer places.
5. **AAC-LC in fragmented MP4 segments, one `$files` file each, listed by rows, played as HLS** (chosen).

## Decision

### The format

AAC-LC, mono, 24 kHz, 32 kbps, in fragmented MP4: one initialization segment, then media segments of 6 s (the HLS
authoring guidance's target), each starting with its own `moof`, so any segment decodes after the initialization
segment alone (`EXT-X-INDEPENDENT-SEGMENTS`). 242.8 KB a minute (14.6 MB an hour), 23.7 times smaller than the WAV,
PESQ 4.32. The codecs string is `mp4a.40.2`. Every player measured plays it: AVPlayer on iOS, iPadOS and macOS,
Safari, Chrome (native HLS and MSE), and the joined file anywhere.

The full-quality WAV is unchanged and stays where it is recorded: transcription, voice prints and share clips keep
reading it. The compressed stream is a second, traveling copy, about 4% of the WAV's size.

### Storage: one `$files` file per segment, at a path that names it

```
<path prefix>/init.mp4
<path prefix>/000000.m4s, 000001.m4s, ...
```

The app chooses each stream's path prefix, so its storage rules can name it (a recording's media folder, say). Because
upstream names a file by its path, a retried upload replaces the same object; a crash between an upload and its row
costs one repeated `PUT`, never a duplicate.

### The manifest: rows, written after the bytes are stored

Two namespaces the app declares in its schema (the library writes them; the app owns the schema and the rules, ADR
0001), each with an `ownerUserID` for the app's rules:

- `progressiveMediaStreams`, one row per stream: `codecs`, `sampleRate`, `channelCount`, `bitRate`, `segmentSeconds`,
  `initializationPath`, `state` (`recording` or `finished`), `segmentCount`, `durationSeconds`, `createdAtMs`,
  `updatedAtMs`. Its id is a UUID derived (SHA-256) from a key the app chooses, such as a recording's generation, so
  every device names the stream the same way without a lookup.
- `progressiveMediaSegments`, one row per segment: `streamID` (indexed), `index` (indexed, ordered), `startSeconds`,
  `durationSeconds`, `byteCount`, `path`, `createdAtMs`. Its id is derived from the stream's id and the index, so a
  replayed write lands on the same row.

A segment's row and its stream's row are written in one `transact` after the segment's file is stored, so a row on the
server means its bytes are there, and the stream row's `segmentCount` and the segment rows always agree. Rows travel
through the ordinary outbox; media bytes never do.

### The writer: a durable spool, drained in order (`InstantProgressiveMediaWriter`)

- `append` writes the segment to a spool directory on this device and returns. It never waits for the server, the
  same contract as `transact` (ADR 0010): offline appends succeed.
- `deliver` drains the spool oldest first: store the file, write its rows, remove it from the spool. The spool (plain
  files, one directory per stream) is the writer's only state, so `resumable(in:storage:)` finds what a previous launch
  left and delivers it, and appends after a relaunch continue the numbering and the timeline.
- A failed upload is tried again after a delay that doubles from 1 s to 60 s and resets only after a success, and no
  attempt is made while the network path is down (the socket's reconnect follows the same two rules, `Reactor.js`
  `_scheduleReconnect`, #669). Nothing after a failed segment moves first. A refused upload (`permissionRejected`) ends
  that stream's delivery and keeps its spool; other streams continue (ADR 0001's isolation).
- `finish` marks the stream finished; the last segment's rows carry `state: finished`.

### The reader: the playlist is built from rows (`InstantProgressiveMediaReader`)

- `refresh()` reads the stream's row, then only the segment rows it has not read yet (a page of up to 500 at a time),
  so following a six-hour stream costs one row and the new segments' rows per refresh, never the whole list again. A
  player's playlist reload (once a target duration) drives the refresh. Segments are listed contiguously from index 0:
  a row that has not arrived ends the listing until it does, so a player never skips audio.
- URLs are read lazily, a page of the following segments at a time (`$files` where `path` in the page, reading `url`;
  upstream signs each such read for 7 days from the start of its UTC day), and kept for a day.
- The playlist is a pure function of the listed segments (`InstantProgressiveMediaPlaylist`): `EXT-X-PLAYLIST-TYPE:EVENT`
  while the stream records, `VOD` with `EXT-X-ENDLIST` once every segment is listed; `EXT-X-TARGETDURATION` is the
  longest segment rounded to the nearest second (RFC 8216 4.3.3.1).
- A live player is handed the playlist only once it lists a segment, and its owner calls `play()` again when a player
  that ran out of audio at the live edge (rate 0 after a long pause in the uploads) sees the stream grow.

### Players

- iOS, iPadOS, macOS, visionOS, tvOS: AVPlayer over `InstantProgressiveMediaResourceLoader`, an
  `AVAssetResourceLoader` delegate that answers `instant-progressive-media://<stream id>/playlist.m3u8` with the
  playlist built from the rows, and each `init.mp4` and `<index>.m4s` with a 302 to the file's storage URL, read when
  the player asks for it. A URL is signed only for a file the player plays, and a reload costs the reader's refresh.
- watchOS has no `AVAssetResourceLoader`, and AVPlayer does not play a `file://` playlist, so a Watch needs the
  playlist from an http(s) endpoint or decodes the segments itself (`AVAudioConverter` and `AVAudioEngine`, which
  watchOS has); left for the Watch app's adoption.
- Browsers: the same rows; Safari and Chrome play the playlist as native HLS, other browsers through Media Source
  Extensions.

### Where Swift differs from upstream, and why

Upstream has no media primitive. The storage calls (`PUT /storage/upload` by path, URLs read from `$files.url`) are
upstream's own; the spool, the ordered uploader and the rows are the library's, because upstream's client keeps
nothing across a reload and an always-on recorder must.

## Consequences

- A remote listener follows a recording about 35-40 s behind its capture, and plays a finished recording without
  downloading its WAV.
- Uploads are small enough for cellular: 14.6 MB an hour.
- Storage keeps the compressed copy, about 4% of the WAV's size.
- A new library target, `InstantSwiftDataMedia`, links AVFoundation; the core targets do not.

## Verification

- Formats, quality, segmenting and playback: `benchmarks/AudioCodecLab` (results in its `results/`).
- Library: `InstantProgressiveMediaPlaylistTests`, `InstantProgressiveMediaWriterTests` and
  `InstantProgressiveMediaReaderTests` (InstantSwiftDataTests); `InstantProgressiveMediaSegmenterTests` and
  `InstantProgressiveMediaResourceTests` (InstantSwiftDataMediaTests).
- Pending: the iPhone's encoding CPU, and a live recording heard on another device through Instant's storage.

## References

- `benchmarks/AudioCodecLab` (measurements and their scripts)
- RFC 8216 (HTTP Live Streaming); RFC 6716 (Opus); ITU-T P.862.2 (wideband PESQ)
- ADR 0001 (media isolation), ADR 0010 (writes never wait for the server), ADR 0017 (streams)
