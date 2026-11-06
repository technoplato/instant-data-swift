# Plan 2026-11-06-mac-longplay-1916: a progressive media stream lists in a few reads, whatever its length

- planId: 2026-11-06-mac-longplay-1916
- agentId: claude-code/mac-longplay-1916@al (tools/agent-run, claude, opus)
- role: fixer (P0 defect #1916, in the consuming app: long streams never start playing)
- issue: #1916 (related #1012, #1796, #1808, #1809, #632)

## Why

`InstantProgressiveMediaReader.refresh()` reads every segment row of a stream, 500 a page, one one-shot query after
another, before the resource loader can answer the playlist. Measured 2026-11-06 against a live app: 811 rows (81 min)
is 2 pages, 4,203 rows (7 h) is 9, 7,695 rows (12.8 h) is 16. A cold first page took 1.1 s (164 rows), 2.2 s (811) and
5.2 s (4,203) on the server alone; on the consuming app each page also waits behind its store's apply gate. While a
large transcript loaded, the walk never finished: AVFoundation gave up on the playlist request after 20 s with
"resource unavailable", on every retry. Time to first sound grows with the stream's length.

What the rows hold makes the walk unnecessary. The writer sets each segment's `startSeconds` to the sum of the durations
before it, its `path` to `stream.segmentPath(index)`, and writes the stream row's `segmentCount` in the same
transaction as each segment row, after its file. AVAssetWriter cuts a take every `segmentSeconds` from where the take
starts. A census of a live app's 221 streams (every row read): 218 whole and contiguous, 212 with every segment within
0.25 s of `index * segmentSeconds`, 8 shifted 1.4-5.4 s, and in all 8 the break is in the last two segments (a take
finished early and an encoder restarted). Server query shapes measured: `$in` on `index` costs 7.6 s for 17 rows and
12.4 s for 29; `$gte` with `$lte` in one clause keeps only the lower bound. Single-row equality reads and
`$gte`-ordered pages are the shapes to use.

## Steps (no code here)

1. This plan and its claims, landed on main.
2. Red: `InstantProgressiveMediaReaderTests`: a stream of 811, 1,768 and 7,695 segments on its grid lists every segment
   (index, start, duration, derived path) from at most two segment reads; a stream with breaks (a short segment near
   the end, one in the middle, several) lists every segment exactly at each break and within the tolerance elsewhere,
   from reads that grow with its breaks, not its length; a growing stream still reads only its new rows after the first
   listing; a missing or out-of-place row falls back to reading that stretch's rows; URLs still come a page at a time.
3. Green: the first listing of a stream reads its last row, lists a stretch whose two ends sit on the grid from the
   rows' arithmetic, splits a stretch that does not (reading the rows at its split points concurrently), and reads the
   rows of a short broken stretch as one page. A new source read, one segment row by index (equality), with a default
   built from the page read so existing sources keep compiling. Later refreshes keep reading only rows after the listing.
4. ADR 0021 amendment: the listing, its tolerance and the measured server query shapes.
5. Release v1.9.77 (release record, PROGRESS.md, CHANGELOG two-commit entry, cross-repository ledger), tagged on main.

## Touching

Sources/InstantSwiftData/InstantProgressiveMediaReader.swift, Tests/InstantSwiftDataTests/InstantProgressiveMediaReaderTests.swift,
docs/adr/0021-progressive-media-over-instant.md, docs/releases/v1.9.77.md (new), PROGRESS.md, CHANGELOG.md,
docs/audits/commit-changelog.md.

## Conflict check

The reader and its tests carry only the first author's claim (#1012, 2026-10-23); no open plan touches progressive media.
No storage change, no row change, no schema change. Channel: agent-presence/_channels/2026-11-06-mac-longplay-1916.md.
