# Overview 04 — App tree (observe, send, goesTo, mutate)

**Status:** **work in progress** — needs more captain feedback  
**Last review:** captain through `mode.recordingIdle.*` (2026-08-10); pick up at
`mode.recordingActive.*`  
**Schema:** `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md`  
https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/transcription.md  
**This file (GitHub, when pushed):**  
https://github.com/technoplato/instant-data-swift/blob/main/docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md


## Related experiment

Message/command/schema-write graph experiment (may not keep):  
[`04b-message-graph-experiment.md`](./04b-message-graph-experiment.md)  
Started Monday 2026-08-10 ~5:46 PM America/New_York.

## WIP / handoff

- Shape of **screen** + exhaustive **mode** nesting is accepted in spirit.
- Leaves use nested `observe` / `send` / `goesTo` / `mutate` (no side arrows).
- Captain feedback incorporated through **`mode.recordingIdle`** children.
- **Not yet re-reviewed by captain:** `mode.recordingActive.*`,
  `mode.recordingPaused.*`, process leaves, navigation stack model.
- **Open:** how `goBack` resolves (nav stack / tree nav / deep link) — not
  hard-coded to `library.populated`.
- **Open:** field lists under observe may still grow or shrink.

Do not treat this file as locked for implementation until the full mode tree
is reviewed.

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
│   │           │         └── focus.recordingId      set
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
│   │   │   │   ├── playback.recordingId
│   │   │   │   └── playback.mediaPosition
│   │   │   └── send
│   │   │       ├── pausePlayback
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingIdle.playbackPaused
│   │   │       ├── stopPlayback
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingIdle.playbackIdle
│   │   │       ├── scrubPlayback
│   │   │       │   └── mutate
│   │   │       │         └── playback.mediaPosition   set
│   │   │       └── startRecording
│   │   │             ├── goesTo
│   │   │             │     └── mode.recordingActive.playbackPlaying
│   │   │             └── mutate
│   │   │                   └── recordingAndTranscription.createLinked
│   │   │
│   │   └── playbackPaused
│   │       ├── observe
│   │       │   ├── playback.recordingId
│   │       │   └── playback.mediaPosition
│   │       └── send
│   │           ├── resumePlayback
│   │           │   └── goesTo
│   │           │         └── mode.recordingIdle.playbackPlaying
│   │           ├── stopPlayback
│   │           │   └── goesTo
│   │           │         └── mode.recordingIdle.playbackIdle
│   │           ├── scrubPlayback
│   │           │   └── mutate
│   │           │         └── playback.mediaPosition   set
│   │           └── startRecording
│   │                 ├── goesTo
│   │                 │     └── mode.recordingActive.playbackPaused
│   │                 └── mutate
│   │                       └── recordingAndTranscription.createLinked
│   │
│   │   # ----- captain review stopped around here; continue below -----
│   │
│   ├── recordingActive
│   │   │
│   │   ├── playbackIdle
│   │   │   ├── observe
│   │   │   │   ├── capture.recordingId
│   │   │   │   ├── capture.transcriptionId
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
│   │   │   │   └── segment                        open speech tail if any
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
│   │   │       │   └── goesTo
│   │   │       │         └── mode.recordingActive.playbackPlaying
│   │   │       ├── openActiveTimeline
│   │   │       │   ├── goesTo
│   │   │       │   │     └── screen.detail.timeline
│   │   │       │   └── mutate
│   │   │       │         └── focus.recordingId        set capture id
│   │   │       └── injectSimulatedSpeech
│   │   │             └── mutate
│   │   │                   └── segment.upsertSpeech
│   │   │                         transcriptionId
│   │   │                         words
│   │   │                         isFinal
│   │   │                         times
│   │   │
│   │   ├── playbackPlaying
│   │   │   ├── observe
│   │   │   │   ├── capture.recordingId
│   │   │   │   ├── capture.transcriptionId
│   │   │   │   ├── recording                       fields as above
│   │   │   │   ├── transcription                   fields as above
│   │   │   │   ├── segment                         open speech tail if any
│   │   │   │   ├── playback.recordingId
│   │   │   │   └── playback.mediaPosition
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
│   │   │       │         └── playback.mediaPosition   set
│   │   │       ├── openActiveTimeline
│   │   │       │   ├── goesTo
│   │   │       │   │     └── screen.detail.timeline
│   │   │       │   └── mutate
│   │   │       │         └── focus.recordingId
│   │   │       └── injectSimulatedSpeech
│   │   │             └── mutate
│   │   │                   └── segment.upsertSpeech
│   │   │
│   │   └── playbackPaused
│   │       ├── observe
│   │       │   ├── capture.recordingId
│   │       │   ├── capture.transcriptionId
│   │       │   ├── recording
│   │       │   ├── transcription
│   │       │   ├── segment
│   │       │   ├── playback.recordingId
│   │       │   └── playback.mediaPosition
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
│   │           │         └── playback.mediaPosition   set
│   │           ├── openActiveTimeline
│   │           │   ├── goesTo
│   │           │   │     └── screen.detail.timeline
│   │           │   └── mutate
│   │           │         └── focus.recordingId
│   │           └── injectSimulatedSpeech
│   │                 └── mutate
│   │                       └── segment.upsertSpeech
│   │
│   └── recordingPaused
│       │
│       ├── playbackIdle
│       │   ├── observe
│       │   │   ├── capture.recordingId
│       │   │   ├── capture.transcriptionId
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
│       │       └── openActiveTimeline
│       │             ├── goesTo
│       │             │     └── screen.detail.timeline
│       │             └── mutate
│       │                   └── focus.recordingId
│       │
│       ├── playbackPlaying
│       │   ├── observe
│       │   │   ├── capture.recordingId
│       │   │   ├── capture.transcriptionId
│       │   │   ├── recording
│       │   │   ├── transcription
│       │   │   ├── playback.recordingId
│       │   │   └── playback.mediaPosition
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
│       │       │         └── playback.mediaPosition   set
│       │       └── openActiveTimeline
│       │             ├── goesTo
│       │             │     └── screen.detail.timeline
│       │             └── mutate
│       │                   └── focus.recordingId
│       │
│       └── playbackPaused
│           ├── observe
│           │   ├── capture.recordingId
│           │   ├── capture.transcriptionId
│           │   ├── recording
│           │   ├── transcription
│           │   ├── playback.recordingId
│           │   └── playback.mediaPosition
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
│               │         └── playback.mediaPosition   set
│               └── openActiveTimeline
│                     ├── goesTo
│                     │     └── screen.detail.timeline
│                     └── mutate
│                           └── focus.recordingId
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
