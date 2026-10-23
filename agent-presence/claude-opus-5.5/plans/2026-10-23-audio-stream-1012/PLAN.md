# Plan: progressive media over Instant: compressed segments in `$files`, a manifest in rows (#1012)

- **planId:** `2026-10-23-audio-stream-1012`
- **agentId:** `claude-code/audio-stream-1012b@ld`
- **Role:** grower, ordered by the owner for #1012 (part of #1005): "a library primitive for streaming progressive audio
  file over instant" (typed 2026-10-23 12:30). Priority: after #1007, #1006, #1011 and #959 (typed 12:36); research,
  measurement and the ADR first.
- **Branch:** `agent/claude/audio-stream-1012`, from `main`; each green step lands on `main`.
- **Outcome:** an append-only media primitive: a writer appends self-contained compressed segments (one `$files` file
  each, deterministic paths, so a retry overwrites instead of duplicating), a manifest of rows written once per segment
  through `transact`, a durable on-disk spool so segments written offline upload later, and a reader that turns the
  manifest into an HLS media playlist (EVENT while live, VOD once finished) that AVPlayer and browsers play, following
  the live edge or from the start. The codec and container are chosen by measurement (ADR 0021).

## Steps (no code here)

1. Measure (benchmarks/AudioCodecLab): size a minute, CPU a minute, wideband PESQ, what AVAssetWriter can segment, what
   AVPlayer and Chrome can play, and the live edge of an EVENT playlist, on the Mac now and on the phone when it is
   reachable.
2. ADR 0021: the decision, with the measurements and the upstream comparison (Stream.ts, `$files`, s3.clj).
3. Red: the writer (spool, upload order, retry and backoff, manifest rows), the playlist builder, and the reader's
   ordering, as focused tests with an injected storage transport and clock.
4. Green: the smallest implementation in new files; the AVFoundation segmenter and player item in a new target.
5. Scribe adopts it (its own plan, ADR and worktree): live recordings, and the remote playback of finished ones.

## Touching

- `docs/adr/0021-progressive-media-over-instant.md` (new)
- `benchmarks/AudioCodecLab/` (new package; no dependency on the library)
- `Sources/InstantSwiftData/InstantProgressiveMedia*.swift` (new), `Sources/InstantSwiftDataMedia/` (new target)
- `Tests/InstantSwiftDataTests/InstantProgressiveMedia*Tests.swift` (new)
- `Package.swift`: one new target and product, only after #959 and #1011 land

## Conflict check

- #959 (storage-959) changes the stored-file functions so an upload keeps no copy; this plan only calls the public
  `uploadFile` and adds no stored-file code. The segment spool is plain files, so no SQLite migration and no edit to
  `SQLitePersistenceStore.swift`.
- #1007 (InstantStore publication, server apply), #1006 (prune and gate), #1011 (meter lines): no shared files.

## Update 2026-10-23 16:04 (resumed as `claude-code/audio-stream-1012b@strangelearning`)

The first measurements (benchmarks/AudioCodecLab, on the Mac) chose AAC-LC in fragmented MP4 over Opus: Apple's Opus
fMP4 is 44.5 kbps for a 24 kbps setting and Chrome 155 rejects it in MSE and native HLS, while AAC-LC plays in AVPlayer,
Chrome (native HLS, MSE, whole file) and Safari. The core splits into files, all new:

- `Sources/InstantSwiftData/InstantProgressiveMediaRows.swift`: the stream and segment rows (`progressiveMediaStreams`,
  `progressiveMediaSegments`), the format value and the deterministic ids and paths.
- `Sources/InstantSwiftData/InstantProgressiveMediaPlaylist.swift`: rows to an HLS media playlist (pure).
- `Sources/InstantSwiftData/InstantProgressiveMediaSpool.swift`: the on-disk spool of segments not yet stored.
- `Sources/InstantSwiftData/InstantProgressiveMediaWriter.swift`: append, finish, and the ordered uploader.
- `Sources/InstantSwiftData/InstantProgressiveMediaReader.swift`: history pages, the live tail, lazy URLs.
- `Sources/InstantSwiftDataCore/InstantNetworkPathWaiting.swift`: a public wait for the network path (#669's monitor),
  so the uploader skips attempts while the device is offline, as the socket does.
- Tests: `InstantProgressiveMediaPlaylistTests.swift`, `InstantProgressiveMediaWriterTests.swift`,
  `InstantProgressiveMediaReaderTests.swift` (InstantSwiftDataTests), and `Tests/InstantSwiftDataMediaTests/`.
- Bookkeeping: `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md` (append-only entries).

#1007 and #1011 merged, #959 landed (VerificationNeeded); #1006 is still open but shares no file with this plan.
