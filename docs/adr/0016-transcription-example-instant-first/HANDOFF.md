# Handoff — ADR 0016 Transcription app tree (interview)

**Written:** 2026-08-11 (America/New_York session)  
**Updated:** 2026-08-11 — **decisions locked**; plan + #193  
**Status:** Decisions locked — execute `plan.md` / issue #193  
**Repo:** `instant-data-swift`  
**Implementation:** allowed per plan steps. Claim #193, workLog each step.

---

## Start here (cold agent)

1. Read **this file**.
2. Read `plan.md` and `query-issue 193` (system of record for execution).
3. Read `qanda.md` only if a decision is unclear (Q01–Q26 decided).
4. Read `overviews/04-uri-tree.md` — system of record for the app tree.
5. Schema skill file (durable types):
   `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md`
6. Skills while implementing: `$instant-data` (+ modeling/dependencies/testing),
   `$change-log` with `--issue 193`, `$issue-tracker` for workLog.

```text
docs/adr/0016-transcription-example-instant-first/
  HANDOFF.md          ← you are here
  README.md
  plan.md             ← execute this
  qanda.md            ← decided log
  findings.md
  overviews/
    00-archetype.md
    01-schema.md / 01-schema-segments.md
    02-recording-activity-adt.md
    03-session-mode-floating-toolbar.md
    04-uri-tree.md    ← app tree SoR
    04b-message-graph-experiment.md  ← parked; may discard
```

Plus schema edits may live under the **skills** checkout (not this repo):

- `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md`
  (`process` bag removed; `preference` added)

**Warning:** External editor overwrite
(`sourceType: externalEditOnAgentFile`) once dropped Q20–Q22 back to
`createLinked`. Recovered from Grok session `rewind_points.jsonl`. **Commit
promptly** after each accepted leaf. Mode work is committed on `main` from
`f647abee` onward.

---

## What this ADR is building

Teachable multi-host **Transcription** example in `instant-data-swift`:
Instant-first, then TCA. Simulated speech (no real mic v1). Dual-client sync.
Hosts: CLI, TUI, Mac, iOS/iPad.

**Not:** Scribe product work, ADR 0015 library ergonomics (related, separate).

---

## Locked model (do not re-litigate without captain)

### App skeleton = two roots only

```text
transcription.app
├── screen                    # navigation (Swift Navigation–style)
│   ├── library.empty
│   ├── library.populated
│   ├── timeline(recordingId) # recording body — not plain transcription text
│   └── settings              # UI only; data is schema.preference
└── mode                      # nine flat Cartesian leaves
    ├── recordingIdlePlaybackIdle
    ├── recordingIdlePlaybackPlaying(playback)
    ├── recordingIdlePlaybackPaused(playback)
    ├── recordingActivePlaybackIdle(capture)
    ├── recordingActivePlaybackPlaying(capture, playback)
    ├── recordingActivePlaybackPaused(capture, playback)
    ├── recordingPausedPlaybackIdle(capture)
    ├── recordingPausedPlaybackPlaying(capture, playback)
    └── recordingPausedPlaybackPaused(capture, playback)
```

### Killed names (do not reintroduce)

| Dead | Replacement |
| --- | --- |
| `process` app root | deleted |
| `process.focus` | `screen.timeline(recordingId)` route param |
| `process.capture` / `playback` | associated values on mode leaves |
| prefs under process / prefs app root | **`schema.preference`** |
| `screen.detail.timeline` | `screen.timeline(recordingId)` |
| nested `mode.recordingX.playbackY` | flat `mode.recordingXPlaybackY` |
| `recordingAndTranscription.createLinked` | **`recording.create`** |
| `finishLinked` | explicit finish fields |
| `injectSimulatedSpeech` | **`speechRecognized`** (sim = dependency) |
| FAB | **floating toolbar** |

### Mode spelling (Q17)

- **Tree/URI:** nine flat camelCase siblings. No intermediate dots.
- **Code algebra (allowed):** two small ADTs  
  `recordingPhase: idle | active(capture) | paused(capture)`  
  `playbackPhase: idle | playing(playback) | paused(playback)`
- **True exclusive hierarchies still nest** (`library` → empty/populated).
- **Independent-axis products flatten.**

### Handles (not schema)

```text
capture
  recordingId
  transcriptionId

playback
  recordingId          # may equal capture (A+A legal)
  mediaPosition
```

Parentheses on leaf names are **associated values**, not URI path segments.

### Schema (durable)

```text
recording 1 ──* transcription 1 ──* segment
  segment.body = speech | event   (exclusive)
  segment ──* response
  times = wall + relative (always expand both clocks)

preference
  speechRate
  speechRateDefault
  debugPanel.presentation   # expanded | collapsed | hidden
```

### speechRecognized (kept)

```text
speechRecognized
  └── mutate
        ├── segment.upsertSpeech
        │     transcriptionId, words, isFinal
        │     times (wall + relative)
        └── when isFinal
              ├── segment finalize current
              └── segment.create next open speech
```

Keyword **`when`** for conditionals under mutate. Prior art: Scribe open-segment
write path.

### screen.timeline

- Route param = which recording body is shown.
- Observes derived **`modeRelation`** vs that id (capture on/off, playback
  off/playing/paused) — not a fourth store; derived from mode handles.
- Richer than “transcription”: speech + events + responses.
- Future export/share: nest **under** timeline, not under empty `detail`.

### startRecording (Q22 — **decided**)

```text
startRecording
  ├── goesTo mode.recordingActivePlaybackIdle(capture)
  └── mutate recording.create
```

Creating transcription / empty open segment under the new recording is
**implementation**, not a second public mutation name. Do not write
“host defaults; mode gets capture handle on arrival.”

### stopRecording

Explicit fields only:

```text
recording.finishedAt / duration / updatedAt set
transcription.finishedAt / updatedAt set
```

Then goesTo appropriate idle recording phase (playback phase preserved).

### Process / interview discipline

- **File first, chat second** — write `04-uri-tree.md` / `qanda.md` before
  dumping large trees only in chat.
- One question at a time; hard chat separator before next question.
- Show **full** leaf trees in chat (no truncated send blocks like
  `pauseRecording → foo`).
- Captain may dictate while testing Scribe; ignore app-test noise unless
  addressed to the ADR.

---

## Leaf review status

| Mode leaf | Status | Q |
| --- | --- | --- |
| recordingIdlePlaybackIdle | **Accepted** (`recording.create`) | Q22 |
| recordingIdlePlaybackPlaying | **Accepted** | Q23 |
| recordingIdlePlaybackPaused | **Accepted** | Q24 |
| recordingActivePlaybackIdle | **Accepted** | Q19 |
| recordingActivePlaybackPlaying | **Accepted** | Q20 |
| recordingActivePlaybackPaused | **Accepted** | Q21 |
| recordingPausedPlaybackIdle | **Accepted** | Q13 |
| recordingPausedPlaybackPlaying | **Accepted** | Q15 |
| recordingPausedPlaybackPaused | **Accepted** | Q18 |

Screen leaves (`library`, `timeline`, `settings`) exist in tree; not all
re-passed after Q14 renames. Timeline `modeRelation` locked in spirit (Q18).

---

## Exact next steps for the next agent

### Immediate (execute plan)

1. ~~Interview~~ **locked** (Q26, captain “lock”).
2. ~~plan.md + #193~~ **done**.
3. **Next code step:** T0 schema entities (`issue-193-T0-schema`).
4. Claim #193 while executing; append workLog with full commit SHAs.

### Commit hygiene

- Stage only ADR-owned paths (+ skills schema if you own that checkout).
- Prefer small commits: e.g. “ADR 0016: flat mode leaves + kill process bag”.
- Follow repo `$change-log` skill after substantive commits.

### Dual-repo note

Scribe (`../tools/realtime-voice-sqlite-instant`) is stress prior art for
speech/open-segment, not the product under design. Prefer Scribe for
`speechRecognized` / open-segment shape when unclear.

---

## Captain voice (recent corrections)

Verbatim themes from this session:

- `process.focus` is **navigation**, not a third process track.
- Prefs are **schema**, not app skeleton.
- No empty `detail` wrapper — `timeline(recordingId)`.
- Flat mode names: `recordingActivePlaybackPlaying`, not nested dots.
- Timeline must know capture vs playback vs both for route id.
- Show full trees; don’t truncate send.
- Not `createLinked` — **`recording.create`**. Implementation may also write
  transcription; don’t expose that as the public name.
- Don’t invent jargon about “host defaults” / “handle on arrival.”
- Blanket apply sibling mode variants when only a few fields differ.
- goBack is **program** stack (Swift Navigation style), not host-only glue
  and not tree-parent-only.

---

## Open questions (deferred / non-blocking)

| Topic | Notes |
| --- | --- |
| Screen leaf re-pass | Deferred at lock; tree already matches |
| 04b message graph | Parked; may discard |

---

## Skills / protocol

| Skill | Use |
| --- | --- |
| `$adr-decision-qanda` | Interview loop, then plan + Instant issues |
| `$domain-as-tree` | PISS trees, schema catalog, no bars |
| `$instant-data` | When implementing library/example later |
| `$change-log` | Commits |
| Agent coordination | `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/docs/agent-coordination-protocol.md` if multi-agent on main |

---

## Resume recipe (copy-paste)

```text
cd /Users/laptop/Sync/tools/realtime-voice-sqlite-instant
scripts/with-instant-tools-credentials node scripts/instant-tools.mjs query-issue 193
# First unsatisfied issue-193-T*
cd /Users/laptop/Sync/instant-data-swift
read docs/adr/0016-transcription-example-instant-first/plan.md
read docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md
# Implement step on main; workLog + change-log --issue 193
```
