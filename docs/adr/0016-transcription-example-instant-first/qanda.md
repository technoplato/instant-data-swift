# ADR 0016 — Q&A log

Single file for the whole interview. Newest questions go at the bottom as
`open`. Chat presents **one** `asking` / overview item at a time.

Process skill: `$adr-decision-qanda`.

---

## Q01 — Where the Transcription example lives

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Recommendation (amended):** Monorepo placement yes; **no `V3` suffix**. Name
  is **Transcription**. Shared **core** + multiple hosts.
- **Question:** Should Transcription be a new Instant monorepo example (new
  product/targets), or should we repurpose VoiceTrail / SyncUps instead?

### Context

User asked for a standalone example ("we'll just call it an example …
transcription") and to not delete existing work. Monorepo already has the SPM
and dual-app patterns. Separate repo would split Instant consumption from the
library under active iteration.

VoiceTrail = existing Instant monorepo demo of capture/list/playback + auth
(`Sources/VoiceTrailV3App/`). Closest prior screen set; **not** the product name
and **not** rewritten in place.

### Answer

**New monorepo targets. Name: Transcription (not TranscriptionV3).**

Shared domain core consumed by multiple hosts:

| Target (intent) | Role |
| --- | --- |
| `Transcription` (core) | Schema, entities, queries, mutations, simulated speech, domain logic |
| CLI host | Terminal control / inspection |
| TUI host | Terminal UI (user said "2e" — interpreted as **TUI**; correct if e2e) |
| Mac app | Multi-window dual-client proof surface |
| iOS / iPad app | Phone/tablet host |

Do **not** replace VoiceTrail or SyncUps. Do **not** use a separate repository
for the first cut. Interview also uses **DomainAsTree / PIS** (mode trees,
URIs, messages) inside this ADR so the domain graph is honest before hosts.

Meta: feedback on domain history during this Q&A also informs adapting
`$domain-as-tree` into ADR-bound design (skill + process), not only product code.

### Follow-ups spawned

- Q02 — archetype one-liner (DomainAsTree step 1)
- Packaging spellings inside Package.swift (core product name, executable names)
- Host matrix order (Instant-first Mac dual-window before TCA)

---

## Q02 — Archetype one-liner (DomainAsTree)

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Recommendation:** Local-first voice memos + simulated speech + multi-client
  observe (amended with rate control + segment/words shape).
- **Question:** What is Transcription in one archetype sentence (no marketing)?

### Context

DomainAsTree requires an archetype one-liner before root screens and mode
trees. Toolshed proxy mapping: favorite stopwatch ↔ active recording; FAB ↔
create; non-favorite running ↔ playback.

Diagnostic frame (user): this example exists partly to stress-test whether the
current Instant + Scribe modeling is **doomed** or merely under-documented —
honest domain graph first, then hosts.

Simulated speech for now — real transcription engine is being extracted in
another chat. Rate of token updates is a **user-controlled slider**.

### Answer

**Archetype:**

> Local-first voice memos: simulated speech becomes attributed words on the
> active recording’s **transcription segments**; list / detail / playback stay
> in sync across Instant clients; no real microphone.

**Speech source (v1):** Simulated only. Slider increases/decreases update rate.
Real engine plugs in later without changing segment/words storage shape.

**Dev diagnostics (v1):** Reuse Recipes debug panel (memory, logs, commits,
build time, outbox). **Always on and expanded in all DEV builds** — no feature
flags to enable it. Release may omit or collapse (not decided yet).

### Follow-ups spawned

- Q03 — transcription segment + words storage
- Extract shared debug panel from Recipes into something hosts can depend on
  (implementation later)

---

## Q03 — Transcription segment + words storage

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Recommendation:** Align with ADR 0015 / Scribe: words as **strict Codable
  JSON array on the segment**, not Instant word entities; segment text/times
  derived from words.
- **Question:** How are live transcript pieces stored?

### Context

Scribe + open-segment recipe already use `wordsJSON` + segment `text` /
`isFinal`. User wants the same teachable shape, strongly typed in Swift.

### Answer

**Entity: transcription segment** (name spelling TBD: `TranscriptionSegment`
vs Scribe `recordingSegment`).

| Field | Rule |
| --- | --- |
| `words` | Strongly typed Swift `[Word]`; wire as JSON blob on the Instant attribute |
| `Word` | `start`, `end`, `text` (engines generally give word timing — use it) |
| `text` | **Derived** from words (joined / app rule), not a free-form second truth |
| `start` / `end` | **Derived** from first word start / last word end (or empty if no words) |

No per-word Instant rows. No denormalized full-transcript attribute as primary
storage. Live write path follows open-segment recipe (upsert current segment
only; always local + outbox).

### Follow-ups spawned

- Q04 — Recording parent + lifecycle (active / paused / stopped)
- Exact Instant attribute names + namespaces
- Whether derived fields are **persisted** on every write or computed only on read

---

## Q04 — Recording parent entity + lifecycle

- **Status:** decided (with pushback refinements; one concurrency follow-up)
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Recommendation:** Recording parent + nested ADT; **stop is a message**, not
  a state; name stays **Recording** for now (not Media).
- **Question:** Is the list row a **Recording** that owns many segments, and
  what exclusive states does a recording have?

### Context

Earlier product ask: recordings list, row, recording screen, playback. Segment
words alone cannot be the list identity. Toolshed: favorite = active lane;
creating while idle starts a new favorite.

User: double-nested enum; stop finishes the recording; playback has play/pause;
list “recording an edit” as future; agent must push back on incomplete answers.

### Answer

**Parent:** List rows are **Recording**s. Each owns many **TranscriptionSegment**s.
Stick with name **Recording** (not Media) for now.

**Stop is not a state.** `stop` is a **message/command** that finishes the
recording (transitions out of the recording branch).

**Nested ADT (refined — agent pushback applied):**

```text
Recording.activity                    // exclusive per recording row
├── recording(RecordingPhase)
│   ├── active              // receiving simulated / STT tokens
│   ├── paused              // same open recording; not receiving tokens
│   └── editingExisting     // LISTED ONLY — not v1 (append/edit lane later)
├── finished                // post-stop; not recording; not playing
└── playback(PlaybackPhase)
    ├── playing
    └── paused
```

**Messages (not states):**

| Message | From → to (sketch) |
| --- | --- |
| `createAndStart` (FAB) | — → new Recording `recording(.active)` |
| `pauseRecording` | `recording(.active)` → `recording(.paused)` |
| `resumeRecording` | `recording(.paused)` → `recording(.active)` |
| `stop` | `recording(_)` → `finished` |
| `startPlayback` | `finished` → `playback(.playing)` |
| `pausePlayback` | `playback(.playing)` → `playback(.paused)` |
| `resumePlayback` | `playback(.paused)` → `playback(.playing)` |
| `stopPlayback` | `playback(_)` → `finished` |

### Agent pushback (why the flat `active|paused|stopped` was wrong)

1. **`stopped` as a state mixed event with mode.** Stop finishes; the resting
   mode is **`finished`**, not “stopped.”
2. **`recording new` is not a phase of an existing row.** Creating is
   `createAndStart` → new entity already in `recording(.active)`. Keeping
   “recording new” as a status on the row is incomplete/nonsensical.
3. **Playback needs its own branch** with `playing | paused` (you corrected this).
4. **Missing leaf:** a completed recording that is **not** playing must be
   representable — that is **`finished`**. Without it, every idle past recording
   has nowhere to live in the ADT.
5. **`editingExisting`:** listed for honesty; **out of scope for v1** (no
   support required).

### Still incomplete until Q05 (do not paper over)

Can **this client** be `recording(.active)` on recording A while
`playback(.playing)` on recording B (toolshed favorite + non-favorite)? That is
**process-level** dual-lane, not a single-row ADT. Needs an explicit answer.

### Follow-ups spawned

- Q05 — dual-lane concurrency (record A + play B)
- Persist `activity` on Instant vs derive from local session + activity ADT
  (Scribe-style `activityKind` + `activityClientID`)
- Debug panel extraction to SPM module (packaging)

---

## Q04b — Debug panel packaging (decided alongside)

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10

### Answer

Extract **Recipes floating debug panel** into its own **SPM module** (name TBD,
e.g. `InstantDevDebug` / `ProcessDebugPanel`) so Transcription and other hosts
depend on it cleanly — not on `RecipesV3App`. DEV hosts: always on + expanded.

---

## Q05 — Dual-lane concurrency (record + play) + schema/session split

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Question:** Can this client record one recording and play another at the
  same time? How is that modeled?

### Answer

**Yes — dual-lane**, toolshed SyncUps FAB model (session mode, not schema):

| Session.mode | Meaning |
| --- | --- |
| Idle | neither lane |
| Recording | recording lane only (phase Active \| Paused) |
| Playback | playback lane only (phase Playing \| Paused) |
| Both | both lanes (ids may be **same or different**) |

Playing B does not stop recording A. Starting playback of C pauses B.

**Same id on both lanes is legal** (captain correction): pause the current
transcription and play that recording’s audio. Not an illegal state. Behavior
differs from two-id Both (no forced jump), but ADT allows it.

**Critical disambiguation:**

1. **Schema** = durable domain types (storage-agnostic) under `transcription.*`.
2. **Session mode** = this client’s FAB / dual-lane feature state.
3. Rejected: smuggling dual-lane as `Recording.activity` field notation.

**Floating toolbar:** Reuse SyncUps floating controls mode table — see
`overviews/03-session-mode-floating-toolbar.md`.

### Follow-ups spawned

- Q06 — accept nested schema draft (no compound names)

---

## Q06 — Accept schema catalog (recording → transcription → segment + event)

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Recommendation:** Accept skill transcription schema as drafted.
- **Question:** Accept cardinality and timeline model?

### Answer

**Accepted.**

```text
recording 1 ──* transcription
transcription 1 ──* segment
transcription 1 ──* event
```

- Segment uses `transcriptionId` (not `recordingId`).
- Events opt-in on transcription (clipboard, screenshot, photo, location, systemAudio).
- `times.wall` = `Time`; `times.relative` = `Duration`.
- Canonical: skill `references/schemas/transcription.md` (+ GitHub link in ADR README).

### Follow-ups spawned

- Q07 — segment responses / agent comments

---

## Q07 — Segment responses (threaded comments / agents)

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Recommendation:** `transcription.response` on a segment; recursive via
  `parentId`; text + author + createdAt. Author kind human | agent.
- **Question:** How do remote agents / humans comment on a segment?

### Answer

**Accepted.** Use case: remote agents listen to the conversation and respond
inline (Scribe already has related code); humans may comment too.

```text
transcription.segment 1 ──* transcription.response
transcription.response 1 ──* transcription.response   # parentId nest
```

Superseded field shape: see Q08 (`parent.root` | `parent.reply`).

Schema updated in skill `transcription.md`.

---

## Q08 — Homogeneous segments + response parent ADT + floating toolbar name

- **Status:** decided
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10

### Answer

1. **`*` means zero-or-many** in cardinality trees (not “required”).

2. **Homogeneous segments.** Timeline is only `transcription.segment` in order.
   No peer `event` list. Body ADT:

   ```text
   segment.body
     speech   (words[])
     event    (clipboard | screenshot | photo | location | systemAudio)
   ```

   Render by mapping segments. Any segment may have responses.

3. **`parent` is not Optional parentId.** ADT:

   ```text
   response.parent
     root
     reply
       responseId    UUID
   ```

   Optional nulls hide root vs reply. Explicit cases forbid a meaningless missing id.

4. **UI name:** **floating toolbar** — do not say FAB / acronym.

Schema: skill `references/schemas/transcription.md` updated.

---

## Q09 — One app tree (exhaustive mode + observe/send on leaves)

- **Status:** decided (shape); observe/send draft on leaves for review
- **Asked:** 2026-08-10
- **Decided:** 2026-08-10
- **Recommendation:** Nested exhaustive mode; leaves hold observe + send.
- **Question:** Accept tree shape?

### Answer

**Accepted shape.**

```text
screen.library.empty | populated | detail.timeline | settings
mode.recording{Idle,Active,Paused}.playback{Idle,Playing,Paused}
process.speechRate | debugPanel
```

Drawn nested only (no bars). Mode is nine leaves by nesting playback under
recording phase. Observe + send hang under each leaf in
`overviews/04-uri-tree.md` (same tree, not a second document structure).

Still fine-tune individual messages/observe slices if needed; shape is locked.


### Handoff (2026-08-10)

Tree file rewritten as WIP with observe/send/goesTo/mutate nested on leaves.
Captain feedback applied through `mode.recordingIdle.*`. Pick up at
`mode.recordingActive.*`. Navigation stack for `goBack` still open.

---

## Q10 — Dual-track same recording id

- **Status:** decided
- **Decided:** 2026-08-11

Capture and playback may target **different** or the **same** recording id
(A+A or A+B).

---

## Q11 — Nested observe; speechRecognized; when isFinal

- **Status:** decided
- **Decided:** 2026-08-11

Observe: `recording →* transcription →* segment`. Message: `speechRecognized`.
Mutate uses `when isFinal` → finalize current + create next open speech.

---

## Q12 — Dual-track leaf messages (active)

- **Status:** decided
- **Decided:** 2026-08-11

stopRecording uses explicit finish fields. Dual timeline openers. File first,
chat second. Early `process` bag superseded by Q14.

---

## Q13 — recordingPausedPlaybackIdle

- **Status:** decided
- **Decided:** 2026-08-11

**Accepted.** resume / stop / play / openCapture timeline.

---

## Q14 — Kill process; flatten timeline; prefs in schema

- **Status:** decided
- **Decided:** 2026-08-11

**Accepted.** No process root. `screen.timeline(recordingId)` (not detail).
Prefs = `schema.preference`. App roots: screen + mode only.

---

## Q15 — recordingPausedPlaybackPlaying

- **Status:** decided
- **Decided:** 2026-08-11

**Accepted.** No speechRecognized while capture paused. Dual openers.

---

## Q16 — nested name (superseded)

- **Status:** superseded by Q17 flat spelling; content re-asked as Q18

---

## Q17 — Flat Cartesian mode leaves

- **Status:** decided
- **Decided:** 2026-08-11

**Accepted.** Nine flat siblings: `recordingActivePlaybackPlaying`, not
`recordingActive.playbackPlaying`. Handle args in parentheses. True exclusive
hierarchies still nest. Independent-axis products flatten. Code may use two
phase ADTs; tree spelling is flat compounds.

---

## Q18 — recordingPausedPlaybackPaused

- **Status:** decided
- **Decided:** 2026-08-11

**Accepted.** Timeline observes derived `modeRelation` (capture/playback vs
route id). stopPlayback while paused still clears to idle.

---

## Q19 — recordingActivePlaybackIdle

- **Status:** decided
- **Decided:** 2026-08-11

**Accepted.** Full segment `times` (wall + relative). Skeleton restores handle
args.

---

## Q20 — recordingActivePlaybackPlaying

- **Status:** decided
- **Decided:** 2026-08-11

### Answer

**Accepted** (full tree — no truncated send block).

Dual capture + playback; both timeline openers; speechRecognized + when isFinal;
pause/stop recording; pause/stop/scrub playback.

Next: Q21 `recordingActivePlaybackPaused`.

---

## Q21 — mode.recordingActivePlaybackPaused

- **Status:** decided
- **Asked:** 2026-08-11
- **Decided:** 2026-08-11

### Answer

**Accepted.** Same dual-track shape as siblings; nothing special to call out.
resumePlayback (not pausePlayback); speechRecognized still on (capture active).

Next: remaining `recordingIdlePlayback*` leaves (no capture handle).

---

## Q22 — mode.recordingIdlePlaybackIdle + startRecording wording

- **Status:** decided
- **Asked:** 2026-08-11
- **Decided:** 2026-08-11
- **Recommendation:** Accept leaf with `recording.create` only.

### Pushback (captain)

- Not `recordingAndTranscription.createLinked`. Public mutate is
  **`recording.create`**. That a transcription (and empty open segment) is
  also written is **implementation**, not a second named mutation.
- Drop jargon: “host defaults; mode gets capture handle on arrival.”

### Plain meaning of startRecording

1. **mutate** `recording.create` — new recording row.
2. **goesTo** `mode.recordingActivePlaybackIdle(capture)` — capture ids are
   those of the recording you just created (the destination mode case always
   carries `capture`; no separate “handle arrival” story).

### Leaf (accepted)

```text
mode.recordingIdlePlaybackIdle
├── observe
│   └── (no capture; no playback)
└── send
    └── startRecording
          ├── goesTo
          │     └── mode.recordingActivePlaybackIdle(capture)
          └── mutate
                └── recording.create
```

### Answer

**Accepted** (captain: “good”).

Public mutate name is **`recording.create` only**. Same wording applies to
`startRecording` on the other idle-recording leaves when reviewed.

Next: `mode.recordingIdlePlaybackPlaying(playback)`.

---

## Q23 — mode.recordingIdlePlaybackPlaying

- **Status:** decided
- **Asked:** 2026-08-11
- **Decided:** 2026-08-11
- **Recommendation:** Accept leaf. Keep `recording.create` on startRecording.
  Prefer handle args on goesTo destinations that need them (match Q22).

### Context

Recording phase is idle; playback is playing. Toolbar can pause/stop/scrub
playback or start a **new** capture while playback continues (dual track:
active + playing).

### Leaf (accepted)

```text
mode.recordingIdlePlaybackPlaying(playback)
├── observe
│   └── playback
│         recordingId
│         mediaPosition
└── send
    ├── pausePlayback
    │   └── goesTo
    │         └── mode.recordingIdlePlaybackPaused(playback)
    ├── stopPlayback
    │   └── goesTo
    │         └── mode.recordingIdlePlaybackIdle
    ├── scrubPlayback
    │   └── mutate
    │         └── (mode) playback.mediaPosition   set
    └── startRecording
          ├── goesTo
          │     └── mode.recordingActivePlaybackPlaying(capture, playback)
          └── mutate
                └── recording.create
```

### Answer

**Accepted** as part of captain blanket apply for remaining idle mode
variants (Q23 + Q24 together).

---

## Q24 — mode.recordingIdlePlaybackPaused + blanket mode polish

- **Status:** decided
- **Asked:** 2026-08-11
- **Decided:** 2026-08-11
- **Recommendation:** Accept leaf. Same `recording.create`. Apply handle args
  on **all** mode goesTo destinations that need them (not only idle leaves).

### Captain

Blanket apply the same few differences across remaining mode leaves (idle
Playing / Paused). Do not re-interview each sibling one by one.

### Leaf (accepted)

```text
mode.recordingIdlePlaybackPaused(playback)
├── observe
│   └── playback
│         recordingId
│         mediaPosition
└── send
    ├── resumePlayback
    │   └── goesTo
    │         └── mode.recordingIdlePlaybackPlaying(playback)
    ├── stopPlayback
    │   └── goesTo
    │         └── mode.recordingIdlePlaybackIdle
    ├── scrubPlayback
    │   └── mutate
    │         └── (mode) playback.mediaPosition   set
    └── startRecording
          ├── goesTo
          │     └── mode.recordingActivePlaybackPaused(capture, playback)
          └── mutate
                └── recording.create
```

### Blanket polish (tree-wide, same turn)

On every mode goesTo that lands on a leaf which carries handles, write the
handles in parentheses (match Q22 style):

| Destination leaf kind | goesTo args |
| --- | --- |
| `recordingIdlePlaybackIdle` | none |
| `*PlaybackPlaying` / `*PlaybackPaused` (idle recording) | `(playback)` |
| `recordingActivePlaybackIdle` / `recordingPausedPlaybackIdle` | `(capture)` |
| dual-track leaves | `(capture, playback)` |

`startRecording` public mutate stays **`recording.create`** on all three idle
recording leaves.

### Answer

**Accepted.** All nine flat mode leaves are now reviewed (Q13–Q15, Q18–Q24).

Still open product questions (not mode leaf content):

- `goBack` / `navigation.previous` (stack vs tree vs deep link)
- Optional screen-leaf re-pass post-Q14 renames
- Instant parent issue # for ADR (README TBD)
- plan.md only after captain says decisions locked for implementation

---

## Q25 — goBack / navigation.previous

- **Status:** decided
- **Asked:** 2026-08-11
- **Decided:** 2026-08-11
- **Recommendation:** **Program navigation stack** (Swift Navigation style).  
  `goBack` → `goesTo navigation.previous` means “pop one screen frame.”  
  Do **not** hard-code `library.populated`.

### Question

How does `goBack` resolve the next screen?

### Options

| Option | Meaning |
| --- | --- |
| **A. Program stack (recommended)** | Real push/pop history in the **program** (Swift Navigation style). `navigation.previous` = previous frame. Not tree-parent-only. |
| **B. Tree parent** | Parent node in the screen tree only (no history). timeline → always library. |
| **C. Explicit edges** | Each screen names its own back target in the tree. |

### Why A

- Matches multi-host reality (CLI path, iOS stack, Mac windows).
- Library empty vs populated is data-driven, not a fixed back target.
- Deep link into `timeline(id)` can still define a default prior (library) without
  baking it into every leaf.

### Answer

**Accepted: A — program stack, Swift Navigation style.**

Captain: done from the **program itself**, not tree-parent-only and not a
fixed `library.populated` edge.

```text
goBack
  └── goesTo
        └── navigation.previous
```

Meaning:

1. The program holds a **screen stack** (path / frames).
2. Opening a screen **pushes** (or replaces per host policy for roots).
3. `goBack` **pops** one frame → that is `navigation.previous`.
4. Hosts (CLI, TUI, iOS, Mac) present the stack; they do not invent a second
   back model.
5. Deep link may seed a synthetic stack (for example library under timeline).

Still optional after this: screen-leaf re-pass post-Q14; Instant issue #;
plan.md when captain locks for implementation.
