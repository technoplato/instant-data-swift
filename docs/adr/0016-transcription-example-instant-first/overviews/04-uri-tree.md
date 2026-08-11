# Overview 04 — App tree (observe, send, goesTo, mutate)

**Status:** **work in progress**  
**Last review:** through `mode.recordingActive.playbackPlaying` (2026-08-11)  
**Pick up next:** `mode.recordingActive.playbackPaused`  
**Schema:** `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md`  
https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/transcription.md  
**This file (GitHub, when pushed):**  
https://github.com/technoplato/instant-data-swift/blob/main/docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md

## Related experiment

Message/command/schema-write graph experiment (parked, keep):  
[`04b-message-graph-experiment.md`](./04b-message-graph-experiment.md)

## WIP / handoff

- Screen + exhaustive mode nesting accepted.
- Leaves: nested `observe` / `send` / `goesTo` / `mutate`.
- **Reviewed:** screens, `mode.recordingIdle.*`, `mode.recordingActive.playbackIdle`,
  `mode.recordingActive.playbackPlaying`.
- **Not yet reviewed:** `recordingActive.playbackPaused`, `recordingPaused.*`,
  process, nav stack.
- **Open:** `goBack` → `navigation.previous` (stack TBD).

Do not implement until the full mode tree is reviewed.

## Rules

- One tree. Roots, branches, leaves.
- Leaves carry `observe` and `send`.
- Under each message: optional `goesTo` (mode/screen change) and `mutate`
  (data change). Nested — not arrows in the margin.
- No `|` bars for exclusive cases.
- Mode: nine leaves by nesting playback under each recording phase.
- `idle` = track off, not “no DB row.”
- **Screen vs mode:** library/detail/settings are where you look. Start/stop
  record and play control lives primarily on **mode** (floating toolbar /
  app-wide). Screen messages are for navigation and list/detail editing.
- `recording.create` + `transcription.create` are one **linked** mutation with
  host defaults (no field shopping list on the message).

## Conventions

| Node | Meaning |
| --- | --- |
| observe | Schema / session slices this node needs |
| send | Message available here |
| goesTo | Transition of screen and/or mode |
| mutate | Durable or session data change |

### Session (not schema)

`session` is **process/app state**, not Instant durable schema. It only holds
pointers and UI handles while the process runs.

```text
session.capture.recordingId
session.capture.transcriptionId
session.playback.recordingId
session.playback.mediaPosition
session.focus.recordingId
```

| Path | Meaning |
| --- | --- |
| `session.capture.recordingId` | Which **recording** is being captured right now (mode.recording is active or paused). Empty when mode.recording is idle. |
| `session.capture.transcriptionId` | Which **transcription** under that recording is receiving speech/events. |
| `session.playback.recordingId` | Which **recording** audio is playing or paused. Empty when mode.playback is idle. |
| `session.playback.mediaPosition` | Playback cursor. |
| `session.focus.recordingId` | Which recording **detail.timeline** is showing. |

“Capture” = the in-progress capture session (ids only). The durable rows live
under schema `recording` / `transcription` / `segment`.

### Durable schema (refresh)

```text
recording
  id             UUID
  title          String
  createdAt      Time
  updatedAt      Time
  finishedAt     Optional Time
  duration       Duration

recording 1 ──* transcription
transcription
  id             UUID
  recordingId    UUID
  createdAt      Time
  updatedAt      Time
  finishedAt     Optional Time

transcription 1 ──* segment
segment
  id                 UUID
  transcriptionId    UUID
  index              Int32
  times
    wall
      start          Time
      end            Time
    relative
      start          Duration
      end            Duration
  body
    speech
      words          Array of word
      text           Derived String
      isFinal        Bool
    event
      clipboard | screenshot | photo | location | systemAudio

segment 1 ──* response
response
  id             UUID
  segmentId      UUID
  parent
    root
    reply
      responseId UUID
  text           String
  author
    kind         human | agent
    id           UUID
    name         String
  createdAt      Time
```

Speech input is modeled as a real recognition message (`speechRecognized`).
Simulated engines are a **dependency** behind that message, not a separate tree
action named “inject sim.”

---

## The tree

```text
transcription.app
│
├── screen
│   │
│   ├── library
│   │   │
│   │   ├── empty
│   │   │   ├── observe
│   │   │   │   └── recording[]
│   │   │   │         count                          0
│   │   │   └── send
│   │   │       └── openSettings
│   │   │             └── goesTo
│   │   │                   └── screen.settings
│   │   │
│   │   │   # Note: startRecording is not owned here.
│   │   │   # Primary home is mode.recordingIdle.* (toolbar / app-wide).
│   │   │
│   │   └── populated
│   │       ├── observe
│   │       │   └── recording[]
│   │       │         id
│   │       │         title
│   │       │         duration
│   │       │         finishedAt
│   │       │         previewThumbs[]                aggregate
│   │       │         responseCount                  aggregate
│   │       │         activityBadge                  optional
│   │       └── send
│   │           ├── openRecording
│   │           │   ├── goesTo
│   │           │   │     └── screen.detail.timeline
│   │           │   └── mutate
│   │           │         └── session.focus.recordingId      set
│   │           ├── deleteRecording
│   │           │   └── mutate
│   │           │         └── recording.deleteLinked
│   │           │               # recording + its transcriptions/segments/…
│   │           └── openSettings
│   │                 └── goesTo
│   │                       └── screen.settings
│   │
│   ├── detail
│   │   └── timeline
│   │       ├── observe
│   │       │   ├── focus.recordingId
│   │       │   ├── recording
│   │       │   │     id
│   │       │   │     title
│   │       │   │     createdAt
│   │       │   │     updatedAt
│   │       │   │     finishedAt
│   │       │   │     duration
│   │       │   ├── transcription
│   │       │   │     id
│   │       │   │     recordingId
│   │       │   │     createdAt
│   │       │   │     updatedAt
│   │       │   │     finishedAt
│   │       │   ├── segment[]
│   │       │   │     id
│   │       │   │     transcriptionId
│   │       │   │     index
│   │       │   │     times
│   │       │   │       wall
│   │       │   │         start
│   │       │   │         end
│   │       │   │       relative
│   │       │   │         start
│   │       │   │         end
│   │       │   │     body
│   │       │   │       speech
│   │       │   │         words[]
│   │       │   │         text
│   │       │   │         isFinal
│   │       │   │       event
│   │       │   │         kind
│   │       │   │         …
│   │       │   └── response[]                     trees on segments
│   │       │         id
│   │       │         segmentId
│   │       │         parent
│   │       │           root
│   │       │           reply
│   │       │             responseId
│   │       │         text
│   │       │         author
│   │       │         createdAt
│   │       └── send
│   │           ├── goBack
│   │           │   └── goesTo
│   │           │         └── navigation.previous
│   │           │               # WIP: stack / tree / deep link — not hard-coded
│   │           │               # to library.populated
│   │           ├── postResponse
│   │           │   └── mutate
│   │           │         └── response.create
│   │           │               segmentId
│   │           │               parent.root
│   │           │               text
│   │           │               author
│   │           │               createdAt
│   │           └── replyToResponse
│   │                 └── mutate
│   │                       └── response.create
│   │                             segmentId
│   │                             parent.reply.responseId
│   │                             text
│   │                             author
│   │                             createdAt
│   │           # Two messages keep parent algebraic (root vs reply), not Optional
│   │
│   └── settings
│       ├── observe
│       │   ├── speechRateDefault
│       │   └── debugPanel
│       │         presentation
│       └── send
│           ├── setSpeechRateDefault
│           │   └── mutate
│           │         └── process.speechRateDefault    set
│           ├── setDebugPanelPresentation
│           │   └── mutate
│           │         └── process.debugPanel.presentation  set
│           └── goBack
│                 └── goesTo
│                       └── navigation.previous
│
├── mode
│   │
│   │   # Mode = app-wide capture/play combination (nine leaves).
│   │   # Floating toolbar is one surface; mode is not limited to it.
│   │   # Start/stop record and play primarily live here, not on library.
│   │
│   ├── recordingIdle
│   │   │
│   │   ├── playbackIdle
│   │   │   ├── observe
│   │   │   │   └── (no open capture; no playback id)
│   │   │   └── send
│   │   │       └── startRecording
│   │   │             ├── goesTo
│   │   │             │     └── mode.recordingActive.playbackIdle
│   │   │             └── mutate
│   │   │                   └── recordingAndTranscription.createLinked
│   │   │                         # one linked mutation; host defaults for
│   │   │                         # title, times, empty duration, etc.
│   │   │   # Cannot start playback from this leaf alone — pick a recording
│   │   │   # on screen (library/detail), then playRecording there or via
│   │   │   # toolbar once a target id is known.
│   │   │
│   │   ├── playbackPlaying
│   │   │   ├── observe
│   │   │   │   ├── session.playback.recordingId
│   │   │   │   └── session.playback.mediaPosition
│   │   │   └── send
│   │   │       ├── pausePlayback
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingIdle.playbackPaused
│   │   │       ├── stopPlayback
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingIdle.playbackIdle
│   │   │       ├── scrubPlayback
│   │   │       │   └── mutate
│   │   │       │         └── session.playback.mediaPosition   set
│   │   │       └── startRecording
│   │   │             ├── goesTo
│   │   │             │     └── mode.recordingActive.playbackPlaying
│   │   │             └── mutate
│   │   │                   └── recordingAndTranscription.createLinked
│   │   │
│   │   └── playbackPaused
│   │       ├── observe
│   │       │   ├── session.playback.recordingId
│   │       │   └── session.playback.mediaPosition
│   │       └── send
│   │           ├── resumePlayback
│   │           │   └── goesTo
│   │           │         └── mode.recordingIdle.playbackPlaying
│   │           ├── stopPlayback
│   │           │   └── goesTo
│   │           │         └── mode.recordingIdle.playbackIdle
│   │           ├── scrubPlayback
│   │           │   └── mutate
│   │           │         └── session.playback.mediaPosition   set
│   │           └── startRecording
│   │                 ├── goesTo
│   │                 │     └── mode.recordingActive.playbackPaused
│   │                 └── mutate
│   │                       └── recordingAndTranscription.createLinked
│   │
│   │   # ----- review stopped after recordingActive.playbackIdle; continue below -----
│   │
│   ├── recordingActive
│   │   │
│   │   ├── playbackIdle                           # REVIEWED 2026-08-11
│   │   │   ├── observe
│   │   │   │   ├── session.capture.recordingId
│   │   │   │   ├── session.capture.transcriptionId
│   │   │   │   ├── recording
│   │   │   │   │     id
│   │   │   │   │     title
│   │   │   │   │     createdAt
│   │   │   │   │     updatedAt
│   │   │   │   │     finishedAt
│   │   │   │   │     duration
│   │   │   │   ├── transcription
│   │   │   │   │     id
│   │   │   │   │     recordingId
│   │   │   │   │     createdAt
│   │   │   │   │     updatedAt
│   │   │   │   │     finishedAt
│   │   │   │   └── segment[]                      open speech tail if any
│   │   │   │         (via transcription; body.speech)
│   │   │   └── send
│   │   │       ├── pauseRecording
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingPaused.playbackIdle
│   │   │       ├── stopRecording
│   │   │       │   ├── goesTo
│   │   │       │   │     └── mode.recordingIdle.playbackIdle
│   │   │       │   └── mutate
│   │   │       │         └── recordingAndTranscription.finishLinked
│   │   │       ├── playRecording
│   │   │       │   │  e.g. long-press a segment while still capturing
│   │   │       │   │  payload: recordingId (often capture id or another)
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingActive.playbackPlaying
│   │   │       ├── openCaptureRecordingTimeline
│   │   │       │   ├── goesTo
│   │   │       │   │     └── screen.detail.timeline
│   │   │       │   └── mutate
│   │   │       │         └── session.focus.recordingId
│   │   │       │               set session.capture.recordingId
│   │   │       └── speechRecognized
│   │   │             │  STT / engine result (sim is a dependency)
│   │   │             └── mutate
│   │   │                   └── segment.upsertSpeech
│   │   │                         transcriptionId
│   │   │                         words
│   │   │                         isFinal
│   │   │                         times
│   │   │
│   │   ├── playbackPlaying                        # REVIEWED 2026-08-11
│   │   │   ├── observe
│   │   │   │   ├── session.capture.recordingId
│   │   │   │   ├── session.capture.transcriptionId
│   │   │   │   ├── session.playback.recordingId
│   │   │   │   ├── session.playback.mediaPosition
│   │   │   │   ├── recording
│   │   │   │   │     id
│   │   │   │   │     title
│   │   │   │   │     createdAt
│   │   │   │   │     updatedAt
│   │   │   │   │     finishedAt
│   │   │   │   │     duration
│   │   │   │   ├── transcription
│   │   │   │   │     id
│   │   │   │   │     recordingId
│   │   │   │   │     createdAt
│   │   │   │   │     updatedAt
│   │   │   │   │     finishedAt
│   │   │   │   └── segment[]
│   │   │   │         id
│   │   │   │         transcriptionId
│   │   │   │         index
│   │   │   │         times
│   │   │   │         body
│   │   │   │   # live tail: include current non-final speech segment if any
│   │   │   └── send
│   │   │       ├── pauseRecording
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingPaused.playbackPlaying
│   │   │       ├── stopRecording
│   │   │       │   ├── goesTo
│   │   │       │   │     └── mode.recordingIdle.playbackPlaying
│   │   │       │   └── mutate
│   │   │       │         └── recordingAndTranscription.finishLinked
│   │   │       ├── pausePlayback
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingActive.playbackPaused
│   │   │       ├── stopPlayback
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingActive.playbackIdle
│   │   │       ├── scrubPlayback
│   │   │       │   └── mutate
│   │   │       │         └── session.playback.mediaPosition   set
│   │   │       ├── openCaptureRecordingTimeline
│   │   │       │   ├── goesTo
│   │   │       │   │     └── screen.detail.timeline
│   │   │       │   └── mutate
│   │   │       │         └── session.focus.recordingId
│   │   │       │               set session.capture.recordingId
│   │   │       ├── openPlaybackRecordingTimeline
│   │   │       │   ├── goesTo
│   │   │       │   │     └── screen.detail.timeline
│   │   │       │   └── mutate
│   │   │       │         └── session.focus.recordingId
│   │   │       │               set session.playback.recordingId
│   │   │       └── speechRecognized
│   │   │             └── mutate
│   │   │                   └── segment.upsertSpeech
│   │   │
│   │   └── playbackPaused
│   │       ├── observe
│   │       │   ├── session.capture.recordingId
│   │       │   ├── session.capture.transcriptionId
│   │       │   ├── session.playback.recordingId
│   │       │   ├── session.playback.mediaPosition
│   │       │   ├── recording
│   │       │   │     id
│   │       │   │     title
│   │       │   │     createdAt
│   │       │   │     updatedAt
│   │       │   │     finishedAt
│   │       │   │     duration
│   │       │   ├── transcription
│   │       │   │     id
│   │       │   │     recordingId
│   │       │   │     createdAt
│   │       │   │     updatedAt
│   │       │   │     finishedAt
│   │       │   └── segment[]
│   │       │         id
│   │       │         transcriptionId
│   │       │         index
│   │       │         times
│   │       │         body
│   │       └── send
│   │           ├── pauseRecording
│   │           │   └── goesTo
│   │           │         └── mode.recordingPaused.playbackPaused
│   │           ├── stopRecording
│   │           │   ├── goesTo
│   │           │   │     └── mode.recordingIdle.playbackPaused
│   │           │   └── mutate
│   │           │         └── recordingAndTranscription.finishLinked
│   │           ├── resumePlayback
│   │           │   └── goesTo
│   │           │         └── mode.recordingActive.playbackPlaying
│   │           ├── stopPlayback
│   │           │   └── goesTo
│   │           │         └── mode.recordingActive.playbackIdle
│   │           ├── scrubPlayback
│   │           │   └── mutate
│   │           │         └── session.playback.mediaPosition   set
│   │           ├── openCaptureRecordingTimeline
│   │           │   ├── goesTo
│   │           │   │     └── screen.detail.timeline
│   │           │   └── mutate
│   │           │         └── session.focus.recordingId
│   │           │               set session.capture.recordingId
│   │           ├── openPlaybackRecordingTimeline
│   │           │   ├── goesTo
│   │           │   │     └── screen.detail.timeline
│   │           │   └── mutate
│   │           │         └── session.focus.recordingId
│   │           │               set session.playback.recordingId
│   │           └── speechRecognized
│   │                 └── mutate
│   │                       └── segment.upsertSpeech
│   │
│   └── recordingPaused
│       │
│       ├── playbackIdle
│       │   ├── observe
│       │   │   ├── session.capture.recordingId
│       │   │   ├── session.capture.transcriptionId
│       │   │   ├── recording
│       │   │   └── transcription
│       │   └── send
│       │       ├── resumeRecording
│       │       │   └── goesTo
│       │       │         └── mode.recordingActive.playbackIdle
│       │       ├── stopRecording
│       │       │   ├── goesTo
│       │       │   │     └── mode.recordingIdle.playbackIdle
│       │       │   └── mutate
│       │       │         └── recordingAndTranscription.finishLinked
│       │       ├── playRecording
│       │       │   └── goesTo
│       │       │         └── mode.recordingPaused.playbackPlaying
│       │       └── openCaptureRecordingTimeline
│       │             ├── goesTo
│       │             │     └── screen.detail.timeline
│       │             └── mutate
│       │                   └── session.focus.recordingId
│       │                         set session.capture.recordingId
│       │
│       ├── playbackPlaying
│       │   ├── observe
│       │   │   ├── session.capture.recordingId
│       │   │   ├── session.capture.transcriptionId
│       │   │   ├── session.playback.recordingId
│       │   │   ├── session.playback.mediaPosition
│       │   │   ├── recording
│       │   │   │     id
│       │   │   │     title
│       │   │   │     createdAt
│       │   │   │     updatedAt
│       │   │   │     finishedAt
│       │   │   │     duration
│       │   │   └── transcription
│       │   │         id
│       │   │         recordingId
│       │   │         createdAt
│       │   │         updatedAt
│       │   │         finishedAt
│       │   └── send
│       │       ├── resumeRecording
│       │       │   └── goesTo
│       │       │         └── mode.recordingActive.playbackPlaying
│       │       ├── stopRecording
│       │       │   ├── goesTo
│       │       │   │     └── mode.recordingIdle.playbackPlaying
│       │       │   └── mutate
│       │       │         └── recordingAndTranscription.finishLinked
│       │       ├── pausePlayback
│       │       │   └── goesTo
│       │       │         └── mode.recordingPaused.playbackPaused
│       │       ├── stopPlayback
│       │       │   └── goesTo
│       │       │         └── mode.recordingPaused.playbackIdle
│       │       ├── scrubPlayback
│       │       │   └── mutate
│       │       │         └── session.playback.mediaPosition   set
│       │       ├── openCaptureRecordingTimeline
│       │       │   ├── goesTo
│       │       │   │     └── screen.detail.timeline
│       │       │   └── mutate
│       │       │         └── session.focus.recordingId
│       │       │               set session.capture.recordingId
│       │       └── openPlaybackRecordingTimeline
│       │             ├── goesTo
│       │             │     └── screen.detail.timeline
│       │             └── mutate
│       │                   └── session.focus.recordingId
│       │                         set session.playback.recordingId
│       │
│       └── playbackPaused
│           ├── observe
│           │   ├── session.capture.recordingId
│           │   ├── session.capture.transcriptionId
│           │   ├── session.playback.recordingId
│           │   ├── session.playback.mediaPosition
│           │   ├── recording
│           │   │     id
│           │   │     title
│           │   │     createdAt
│           │   │     updatedAt
│           │   │     finishedAt
│           │   │     duration
│           │   └── transcription
│           │         id
│           │         recordingId
│           │         createdAt
│           │         updatedAt
│           │         finishedAt
│           └── send
│               ├── resumeRecording
│               │   └── goesTo
│               │         └── mode.recordingActive.playbackPaused
│               ├── stopRecording
│               │   ├── goesTo
│               │   │     └── mode.recordingIdle.playbackPaused
│               │   └── mutate
│               │         └── recordingAndTranscription.finishLinked
│               ├── resumePlayback
│               │   └── goesTo
│               │         └── mode.recordingPaused.playbackPlaying
│               ├── stopPlayback
│               │   └── goesTo
│               │         └── mode.recordingPaused.playbackIdle
│               ├── scrubPlayback
│               │   └── mutate
│               │         └── session.playback.mediaPosition   set
│               ├── openCaptureRecordingTimeline
│               │   ├── goesTo
│               │   │     └── screen.detail.timeline
│               │   └── mutate
│               │         └── session.focus.recordingId
│               │               set session.capture.recordingId
│               └── openPlaybackRecordingTimeline
│                     ├── goesTo
│                     │     └── screen.detail.timeline
│                     └── mutate
│                           └── session.focus.recordingId
│                                 set session.playback.recordingId
│
└── process
    ├── speechRate
    │   ├── observe
    │   │   └── rate
    │   └── send
    │       └── setSpeechRate
    │             └── mutate
    │                   └── process.speechRate         set
    └── debugPanel
        ├── observe
        │   ├── memory
        │   ├── logs
        │   ├── buildProvenance
        │   └── presentation
        └── send
            └── setPresentation
                  └── mutate
                        └── process.debugPanel.presentation  set
                  # DEV always expanded by default; presentation still mutable
```

---

## Linked mutations (shorthand)

| Name | Meaning |
| --- | --- |
| `recordingAndTranscription.createLinked` | Create recording + transcription in one mutation; defaults for title/times |
| `recordingAndTranscription.finishLinked` | Set finishedAt / duration on open capture |
| `recording.deleteLinked` | Delete recording and owned transcription graph |
| `segment.upsertSpeech` | Open-segment style upsert of speech body + words |
| `response.create` | New thread (`parent.root`) or reply (`parent.reply`) |

---

## Navigation (WIP)

`goesTo.navigation.previous` stands for “pop / resolve back.” Contributors:

- stack navigation
- tree navigation
- deep links

Not specified yet. Do not assume back always lands on `library.populated`.

---

## Schema pointer

```text
recording
└──* transcription
    └──* segment
          ├── body
          │     ├── speech
          │     └── event
          └──* response
```
