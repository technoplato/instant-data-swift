# Phone-shaped replay gate (#296)

Replays a pulled device store's outbox through the verdicts the device really got, on this checkout's library, and
compares the result with a model of Instant's server. No transport, no credentials, no production access. It is the
"phone-shaped replay" gate of `FAST-DRAIN.md` 15.5, rebuilt as a committed tool: the original probe was a temporary
test whose source was not kept.

## What it does

`Tests/InstantSwiftDataCoreTests/PhoneReplayGateTests.swift` (skipped unless `INSTANT_PHONE_REPLAY_STORE` is set):

- Opens a scratch copy of the store with Scribe's deferred attributes, credential rows deleted.
- Claims the outbox in windows of 50, in creation order, through the library's own claim path. The writes the device
  saw refused fail as `perms-pass?` refusals; every other write is accepted.
- The model server applies every write in creation order, including the refused writes' first offers, stores links
  in forward form, and keeps a cardinality-one slot's first-set time when its value changes, as Instant's
  `triple.clj` `ea-conflict-update-set` does.
- After each window, one server frame:
  - `list` (the gate): the touched recordings, their two preview segments, and the touched attachments, with only
    the attributes the store's stored list and attachment results select.
  - `touched`: every fact of the entities the window touched, as with the transcript open.
- At the end, one frame restates every entity the drain touched, as opening every screen would.
- Prints `REPLAY` lines (ids, attribute names, counts, stamps; values only for a short list of numeric and boolean
  fields) and fails if writes are left pending, a write is claimed twice, a listed refusal is not refused, or the
  model server meets an operation it does not model.

Frames and comparisons run in a fixed order, so reruns print the same lines apart from times. The original probe
iterated sets and dictionaries, so which attribute its first-frame `changesShadowedFact` decline named varied from
run to run (`recordingID` on `23a80571`, `transcriptionID` on `d487ee09` and `6a81039a`) with identical counts.

## Running it

```sh
# From the library checkout to gate. Builds the tests under the shared heavy-build lock, stages the store under
# /tmp, runs the replay, compares with the reference log, and deletes the /tmp copy.
scripts/phone-replay/run-phone-replay.sh \
  --store ~/scribe-device-pulls/2026-09-30-pre-71-backup/raw/database \
  --refusals /Users/laptop/Sync/audit/library-78-2026-10-01/phone-replay/build73-refusals.json \
  --log /tmp/phone-replay-$(git rev-parse --short HEAD)-list.log \
  --reference /Users/laptop/Sync/audit/library-78-2026-10-01/phone-replay/956fce52-list.log
```

- `--no-lock` runs the replay outside the lock when it would exceed a lock hold (about 20 minutes); the build still
  takes the lock. `--skip-build` reuses a build. `--frames touched` and `--window N` change the shape.
- `compare-replay-logs.py REFERENCE CANDIDATE` exits 0 when the candidate matches or improves on the reference, 1
  when it is worse (more rebased frames or bodies, a changed verdict count, writes left pending, or a gap the
  reference lacks after the drain or after the full restatement), and 2 when the inputs differ.
- The refusal file comes from a diagnostics journal: `refused-mutation-ids.py --journal JOURNAL --session ID
  --until TIME`. The journal keeps growing while the session runs, so keep the extracted file rather than
  re-extracting it.

Wall time is a Debug build: 530-1,350 s on the Mac at host load 130-1,000 for the pre-71 store, plus 5-7 minutes for
a fresh test build.

## The pre-71 store and its 103 refusals

- Store: the iPhone store copied before build 71 (2,487 pending, 116 failed).
- Refusals: the 103 writes the Mac collector shows refused on build 73 (session `7ded00b0`, logged 17:38:02-20:26:09
  on 2026-09-30), all pending in that store. The same journal now also holds 27 later `replay` refusals of that
  session (22:05:54-22:08:30); they are not part of this input.

List frames. The published runs used the original probe on `23a80571`, `d487ee09`, and `6a81039a`, which gave the same
counts. This tool on `956fce52` (library-77's build) reproduces every count; its log is the reference above.

| | Published | This tool on `956fce52` |
|---|---|---|
| Start | 2,487 pending, 116 failed, 103 of 103 refusals pending, window 50 | the same |
| Drain | 2,487 -> 0 pending, 119 frames, 17 with a component rebase, 26,288 bodies; accepted 2,384, refused 103; failed rows 116 -> 219 | the same, and all 28 printed windows equal |
| Reductions | 119, all reduced; 1 receipt patch; 1 refused overlay removed by the reduction | the same |
| Declines | `failedOverlay` 16; `changesShadowedFact` 1 on a transcription segment's `transcriptionID` (`recordingID` on `23a80571`) | the same; the fixed order names the segment's `id` |
| After the drain | 4 segments missing, 20 segments without `ownerUserID` (Pattern B), one route chunk missing 6 fields and another with 2 behind, `clipboardEntries` | the same 34 example lines |
| After a full restatement | only `recordings/clipboardEntries` differs (the phone's older copy of its own write) | the same |
| Wall (Debug) | 900-1,341 s | 900 s and 528 s drains in two runs whose lines are identical apart from times; host load 126-1,003 |
