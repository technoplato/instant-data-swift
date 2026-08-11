# Overview 04 — App tree (observe, send, goesTo, mutate)

**Status:** **work in progress** — needs more captain feedback  
**Last review:** Q23–Q24 accepted (2026-08-11):
  All nine flat mode leaves reviewed. Blanket: `recording.create` + handle
  args on goesTo destinations that need them.  
**Schema:** `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md`  
https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/transcription.md  
**This file (GitHub, when pushed):**  
https://github.com/technoplato/instant-data-swift/blob/main/docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md


## Related experiment

Message/command/schema-write graph experiment (may not keep):  
[`04b-message-graph-experiment.md`](./04b-message-graph-experiment.md)  
Started Monday 2026-08-10 ~5:46 PM America/New_York.

## WIP / handoff

**Full agent handoff:** [`../HANDOFF.md`](../HANDOFF.md) (2026-08-11).

- **App roots:** `screen` + `mode` only. No `process`. Prefs = **schema**.
- **Mode:** nine **flat** siblings (Cartesian product spelling). Handles as
  associated values in parentheses — not URI path segments.
- **Screen:** `timeline(recordingId)` = recording body (speech + events +
  responses). Observes derived `modeRelation` vs route id.
- Leaves: nested `observe` / `send` / `goesTo` / `mutate`. Full expansion —
  no truncated send arrows in review leaves.
- **Reviewed:** all nine mode leaves (Q13–Q15, Q18–Q24).
  Rule: `startRecording` → `recording.create`; goesTo carries needed handles.
- **Open:** `goBack` resolution (stack / tree / deep link).
- Capture and playback may target the **same** recording id (A + A).

## Rules

- One tree. Roots, branches, leaves.
- App roots: **`screen`** + **`mode`**.
- No `|` bars for exclusive cases.
- **Cartesian products** (independent axes): **flat sibling leaves**, camelCase
  compounds, no intermediate dots (`recordingActivePlaybackPlaying`).
- **True exclusive hierarchies** still nest (`library` → `empty` / `populated`).
- Capture / playback handles hang on mode leaves that need them.
- Conditionals under mutate use nested **`when`**.
- Durable observe nests: `recording →* transcription →* segment`.
- Segment `times` always expand: wall + relative (start/end each).
- Timeline openers: pure `goesTo screen.timeline(recordingId)`.

## Conventions

| Node | Meaning |
| --- | --- |
| observe | Schema slices + mode handles this node needs |
| send | Message available here |
| goesTo | Transition of screen and/or mode |
| mutate | Schema change |
| when | Conditional branch under a mutate |

---

## Mode: algebra vs tree spelling

```text
recordingPhase: idle | active(capture) | paused(capture)
playbackPhase:  idle | playing(playback) | paused(playback)
```

Tree spelling — nine exclusive siblings:

```text
mode
  recordingIdlePlaybackIdle
  recordingIdlePlaybackPlaying(playback)
  recordingIdlePlaybackPaused(playback)
  recordingActivePlaybackIdle(capture)
  recordingActivePlaybackPlaying(capture, playback)
  recordingActivePlaybackPaused(capture, playback)
  recordingPausedPlaybackIdle(capture)
  recordingPausedPlaybackPlaying(capture, playback)
  recordingPausedPlaybackPaused(capture, playback)
```

Hosts may implement two phase enums in Swift; **URI/tree name is the flat compound**.

### Mode handles (not schema)

```text
capture
  recordingId          recording.id
  transcriptionId      transcription.id

playback
  recordingId          recording.id
  mediaPosition        Duration
```

### Schema (not app roots)

```text
recording
└──* transcription
    └──* segment
          body
            speech | event
          └──* response

preference
  speechRate
  speechRateDefault
  debugPanel.presentation
```

### `speechRecognized` (kept)

```text
speechRecognized
  └── mutate
        ├── segment.upsertSpeech (transcriptionId, words, isFinal, times wall+relative)
        └── when isFinal
              ├── segment finalize current
              └── segment.create next open speech
```

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
│   │           │   └── goesTo
│   │           │         └── screen.timeline(row.recordingId)
│   │           ├── deleteRecording
│   │           │   └── mutate
│   │           │         └── recording.delete
│   │           └── openSettings
│   │                 └── goesTo
│   │                       └── screen.settings
│   │
│   ├── timeline(recordingId)
│   │   ├── observe
│   │   │   ├── modeRelation
│   │   │   │     capture
│   │   │   │       off
│   │   │   │       on
│   │   │   │     playback
│   │   │   │       off
│   │   │   │       playing
│   │   │   │       paused
│   │   │   ├── playback.mediaPosition
│   │   │   └── recording
│   │   │         id
│   │   │         title
│   │   │         createdAt
│   │   │         updatedAt
│   │   │         finishedAt
│   │   │         duration
│   │   │         └──* transcription
│   │   │               id
│   │   │               recordingId
│   │   │               createdAt
│   │   │               updatedAt
│   │   │               finishedAt
│   │   │               └──* segment
│   │   │                     id
│   │   │                     transcriptionId
│   │   │                     index
│   │   │                     times
│   │   │                       wall
│   │   │                         start
│   │   │                         end
│   │   │                       relative
│   │   │                         start
│   │   │                         end
│   │   │                     body
│   │   │                       speech
│   │   │                         words[]
│   │   │                         text
│   │   │                         isFinal
│   │   │                       event
│   │   │                         kind
│   │   │                         …
│   │   │                     └──* response
│   │   │                           id
│   │   │                           segmentId
│   │   │                           parent
│   │   │                             root
│   │   │                             reply
│   │   │                               responseId
│   │   │                           text
│   │   │                           author
│   │   │                           createdAt
│   │   └── send
│   │       ├── goBack
│   │       │   └── goesTo
│   │       │         └── navigation.previous
│   │       ├── postResponse
│   │       │   └── mutate
│   │       │         └── response.create
│   │       │               segmentId
│   │       │               parent.root
│   │       │               text
│   │       │               author
│   │       │               createdAt
│   │       └── replyToResponse
│   │             └── mutate
│   │                   └── response.create
│   │                         segmentId
│   │                         parent.reply.responseId
│   │                         text
│   │                         author
│   │                         createdAt
│   │
│   └── settings
│       ├── observe
│       │   └── preference
│       │         speechRateDefault
│       │         debugPanel
│       │           presentation
│       └── send
│           ├── setSpeechRateDefault
│           │   └── mutate
│           │         └── preference.speechRateDefault    set
│           ├── setDebugPanelPresentation
│           │   └── mutate
│           │         └── preference.debugPanel.presentation  set
│           └── goBack
│                 └── goesTo
│                       └── navigation.previous
│
├── mode
│   │
│   ├── recordingIdlePlaybackIdle                      # REVIEWED Q22
│   │   ├── observe
│   │   │   └── (no capture; no playback)
│   │   └── send
│   │       └── startRecording
│   │             ├── goesTo
│   │             │     └── mode.recordingActivePlaybackIdle(capture)
│   │             └── mutate
│   │                   └── recording.create
│   │
│   ├── recordingIdlePlaybackPlaying(playback)            # REVIEWED Q23
│   │   ├── observe
│   │   │   └── playback
│   │   │         recordingId
│   │   │         mediaPosition
│   │   └── send
│   │       ├── pausePlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingIdlePlaybackPaused(playback)
│   │       ├── stopPlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingIdlePlaybackIdle
│   │       ├── scrubPlayback
│   │       │   └── mutate
│   │       │         └── (mode) playback.mediaPosition   set
│   │       └── startRecording
│   │             ├── goesTo
│   │             │     └── mode.recordingActivePlaybackPlaying(capture, playback)
│   │             └── mutate
│   │                   └── recording.create
│   │
│   ├── recordingIdlePlaybackPaused(playback)             # REVIEWED Q24
│   │   ├── observe
│   │   │   └── playback
│   │   │         recordingId
│   │   │         mediaPosition
│   │   └── send
│   │       ├── resumePlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingIdlePlaybackPlaying(playback)
│   │       ├── stopPlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingIdlePlaybackIdle
│   │       ├── scrubPlayback
│   │       │   └── mutate
│   │       │         └── (mode) playback.mediaPosition   set
│   │       └── startRecording
│   │             ├── goesTo
│   │             │     └── mode.recordingActivePlaybackPaused(capture, playback)
│   │             └── mutate
│   │                   └── recording.create
│   │
│   ├── recordingActivePlaybackIdle(capture)           # REVIEWED Q19
│   │   ├── observe
│   │   │   ├── capture
│   │   │   │     recordingId
│   │   │   │     transcriptionId
│   │   │   └── recording
│   │   │         id
│   │   │         title
│   │   │         createdAt
│   │   │         updatedAt
│   │   │         finishedAt
│   │   │         duration
│   │   │         └──* transcription
│   │   │               id
│   │   │               recordingId
│   │   │               createdAt
│   │   │               updatedAt
│   │   │               finishedAt
│   │   │               └──* segment
│   │   │                     id
│   │   │                     transcriptionId
│   │   │                     index
│   │   │                     times
│   │   │                       wall
│   │   │                         start
│   │   │                         end
│   │   │                       relative
│   │   │                         start
│   │   │                         end
│   │   │                     body
│   │   │                       speech
│   │   │                         words[]
│   │   │                         text
│   │   │                         isFinal
│   │   │                       event
│   │   │                         kind
│   │   │                         …
│   │   └── send
│   │       ├── pauseRecording
│   │       │   └── goesTo
│   │       │         └── mode.recordingPausedPlaybackIdle(capture)
│   │       ├── stopRecording
│   │       │   ├── goesTo
│   │       │   │     └── mode.recordingIdlePlaybackIdle
│   │       │   └── mutate
│   │       │         ├── recording.finishedAt         set
│   │       │         ├── recording.duration           set
│   │       │         ├── recording.updatedAt          set
│   │       │         ├── transcription.finishedAt     set
│   │       │         └── transcription.updatedAt      set
│   │       ├── playRecording
│   │       │   └── goesTo
│   │       │         └── mode.recordingActivePlaybackPlaying(capture, playback)
│   │       ├── openCaptureRecordingTimeline
│   │       │   └── goesTo
│   │       │         └── screen.timeline(capture.recordingId)
│   │       └── speechRecognized
│   │             └── mutate
│   │                   ├── segment.upsertSpeech
│   │                   │     transcriptionId
│   │                   │     words
│   │                   │     isFinal
│   │                   │     times
│   │                   │       wall
│   │                   │         start
│   │                   │         end
│   │                   │       relative
│   │                   │         start
│   │                   │         end
│   │                   └── when isFinal
│   │                         ├── segment finalize current
│   │                         └── segment.create next open speech
│   │
│   ├── recordingActivePlaybackPlaying(capture, playback)  # REVIEWED Q20
│   │   ├── observe
│   │   │   ├── capture
│   │   │   │     recordingId
│   │   │   │     transcriptionId
│   │   │   ├── playback
│   │   │   │     recordingId
│   │   │   │     mediaPosition
│   │   │   └── recording
│   │   │         id
│   │   │         title
│   │   │         createdAt
│   │   │         updatedAt
│   │   │         finishedAt
│   │   │         duration
│   │   │         └──* transcription
│   │   │               id
│   │   │               recordingId
│   │   │               createdAt
│   │   │               updatedAt
│   │   │               finishedAt
│   │   │               └──* segment
│   │   │                     id
│   │   │                     transcriptionId
│   │   │                     index
│   │   │                     times
│   │   │                       wall
│   │   │                         start
│   │   │                         end
│   │   │                       relative
│   │   │                         start
│   │   │                         end
│   │   │                     body
│   │   │                       speech
│   │   │                         words[]
│   │   │                         text
│   │   │                         isFinal
│   │   │                       event
│   │   │                         kind
│   │   │                         …
│   │   └── send
│   │       ├── pauseRecording
│   │       │   └── goesTo
│   │       │         └── mode.recordingPausedPlaybackPlaying(capture, playback)
│   │       ├── stopRecording
│   │       │   ├── goesTo
│   │       │   │     └── mode.recordingIdlePlaybackPlaying(playback)
│   │       │   └── mutate
│   │       │         ├── recording.finishedAt         set
│   │       │         ├── recording.duration           set
│   │       │         ├── recording.updatedAt          set
│   │       │         ├── transcription.finishedAt     set
│   │       │         └── transcription.updatedAt      set
│   │       ├── pausePlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingActivePlaybackPaused(capture, playback)
│   │       ├── stopPlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingActivePlaybackIdle(capture)
│   │       ├── scrubPlayback
│   │       │   └── mutate
│   │       │         └── (mode) playback.mediaPosition   set
│   │       ├── openCaptureRecordingTimeline
│   │       │   └── goesTo
│   │       │         └── screen.timeline(capture.recordingId)
│   │       ├── openPlaybackRecordingTimeline
│   │       │   └── goesTo
│   │       │         └── screen.timeline(playback.recordingId)
│   │       └── speechRecognized
│   │             └── mutate
│   │                   ├── segment.upsertSpeech
│   │                   │     transcriptionId
│   │                   │     words
│   │                   │     isFinal
│   │                   │     times
│   │                   │       wall
│   │                   │         start
│   │                   │         end
│   │                   │       relative
│   │                   │         start
│   │                   │         end
│   │                   └── when isFinal
│   │                         ├── segment finalize current
│   │                         └── segment.create next open speech
│   │
│   ├── recordingActivePlaybackPaused(capture, playback)   # REVIEWED Q21
│   │   ├── observe
│   │   │   ├── capture
│   │   │   │     recordingId
│   │   │   │     transcriptionId
│   │   │   ├── playback
│   │   │   │     recordingId
│   │   │   │     mediaPosition
│   │   │   └── recording
│   │   │         id
│   │   │         title
│   │   │         createdAt
│   │   │         updatedAt
│   │   │         finishedAt
│   │   │         duration
│   │   │         └──* transcription
│   │   │               id
│   │   │               recordingId
│   │   │               createdAt
│   │   │               updatedAt
│   │   │               finishedAt
│   │   │               └──* segment
│   │   │                     id
│   │   │                     transcriptionId
│   │   │                     index
│   │   │                     times
│   │   │                       wall
│   │   │                         start
│   │   │                         end
│   │   │                       relative
│   │   │                         start
│   │   │                         end
│   │   │                     body
│   │   │                       speech
│   │   │                         words[]
│   │   │                         text
│   │   │                         isFinal
│   │   │                       event
│   │   │                         kind
│   │   │                         …
│   │   └── send
│   │       ├── pauseRecording
│   │       │   └── goesTo
│   │       │         └── mode.recordingPausedPlaybackPaused(capture, playback)
│   │       ├── stopRecording
│   │       │   ├── goesTo
│   │       │   │     └── mode.recordingIdlePlaybackPaused(playback)
│   │       │   └── mutate
│   │       │         ├── recording.finishedAt         set
│   │       │         ├── recording.duration           set
│   │       │         ├── recording.updatedAt          set
│   │       │         ├── transcription.finishedAt     set
│   │       │         └── transcription.updatedAt      set
│   │       ├── resumePlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingActivePlaybackPlaying(capture, playback)
│   │       ├── stopPlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingActivePlaybackIdle(capture)
│   │       ├── scrubPlayback
│   │       │   └── mutate
│   │       │         └── (mode) playback.mediaPosition   set
│   │       ├── openCaptureRecordingTimeline
│   │       │   └── goesTo
│   │       │         └── screen.timeline(capture.recordingId)
│   │       ├── openPlaybackRecordingTimeline
│   │       │   └── goesTo
│   │       │         └── screen.timeline(playback.recordingId)
│   │       └── speechRecognized
│   │             └── mutate
│   │                   ├── segment.upsertSpeech
│   │                   │     transcriptionId
│   │                   │     words
│   │                   │     isFinal
│   │                   │     times
│   │                   │       wall
│   │                   │         start
│   │                   │         end
│   │                   │       relative
│   │                   │         start
│   │                   │         end
│   │                   └── when isFinal
│   │                         ├── segment finalize current
│   │                         └── segment.create next open speech
│   │
│   ├── recordingPausedPlaybackIdle(capture)               # REVIEWED Q13
│   │   ├── observe
│   │   │   ├── capture
│   │   │   │     recordingId
│   │   │   │     transcriptionId
│   │   │   └── recording
│   │   │         id
│   │   │         title
│   │   │         createdAt
│   │   │         updatedAt
│   │   │         finishedAt
│   │   │         duration
│   │   │         └──* transcription
│   │   │               id
│   │   │               recordingId
│   │   │               createdAt
│   │   │               updatedAt
│   │   │               finishedAt
│   │   │               └──* segment
│   │   │                     id
│   │   │                     transcriptionId
│   │   │                     index
│   │   │                     times
│   │   │                       wall
│   │   │                         start
│   │   │                         end
│   │   │                       relative
│   │   │                         start
│   │   │                         end
│   │   │                     body
│   │   │                       speech
│   │   │                         words[]
│   │   │                         text
│   │   │                         isFinal
│   │   │                       event
│   │   │                         kind
│   │   │                         …
│   │   └── send
│   │       ├── resumeRecording
│   │       │   └── goesTo
│   │       │         └── mode.recordingActivePlaybackIdle(capture)
│   │       ├── stopRecording
│   │       │   ├── goesTo
│   │       │   │     └── mode.recordingIdlePlaybackIdle
│   │       │   └── mutate
│   │       │         ├── recording.finishedAt         set
│   │       │         ├── recording.duration           set
│   │       │         ├── recording.updatedAt          set
│   │       │         ├── transcription.finishedAt     set
│   │       │         └── transcription.updatedAt      set
│   │       ├── playRecording
│   │       │   └── goesTo
│   │       │         └── mode.recordingPausedPlaybackPlaying(capture, playback)
│   │       └── openCaptureRecordingTimeline
│   │             └── goesTo
│   │                   └── screen.timeline(capture.recordingId)
│   │
│   ├── recordingPausedPlaybackPlaying(capture, playback)  # REVIEWED Q15
│   │   ├── observe
│   │   │   ├── capture
│   │   │   │     recordingId
│   │   │   │     transcriptionId
│   │   │   ├── playback
│   │   │   │     recordingId
│   │   │   │     mediaPosition
│   │   │   └── recording
│   │   │         id
│   │   │         title
│   │   │         createdAt
│   │   │         updatedAt
│   │   │         finishedAt
│   │   │         duration
│   │   │         └──* transcription
│   │   │               id
│   │   │               recordingId
│   │   │               createdAt
│   │   │               updatedAt
│   │   │               finishedAt
│   │   │               └──* segment
│   │   │                     id
│   │   │                     transcriptionId
│   │   │                     index
│   │   │                     times
│   │   │                       wall
│   │   │                         start
│   │   │                         end
│   │   │                       relative
│   │   │                         start
│   │   │                         end
│   │   │                     body
│   │   │                       speech
│   │   │                         words[]
│   │   │                         text
│   │   │                         isFinal
│   │   │                       event
│   │   │                         kind
│   │   │                         …
│   │   └── send
│   │       ├── resumeRecording
│   │       │   └── goesTo
│   │       │         └── mode.recordingActivePlaybackPlaying(capture, playback)
│   │       ├── stopRecording
│   │       │   ├── goesTo
│   │       │   │     └── mode.recordingIdlePlaybackPlaying(playback)
│   │       │   └── mutate
│   │       │         ├── recording.finishedAt         set
│   │       │         ├── recording.duration           set
│   │       │         ├── recording.updatedAt          set
│   │       │         ├── transcription.finishedAt     set
│   │       │         └── transcription.updatedAt      set
│   │       ├── pausePlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingPausedPlaybackPaused(capture, playback)
│   │       ├── stopPlayback
│   │       │   └── goesTo
│   │       │         └── mode.recordingPausedPlaybackIdle(capture)
│   │       ├── scrubPlayback
│   │       │   └── mutate
│   │       │         └── (mode) playback.mediaPosition   set
│   │       ├── openCaptureRecordingTimeline
│   │       │   └── goesTo
│   │       │         └── screen.timeline(capture.recordingId)
│   │       ├── openPlaybackRecordingTimeline
│   │       │   └── goesTo
│   │       │         └── screen.timeline(playback.recordingId)
│   │       └── (no speechRecognized — capture paused)
│   │
│   └── recordingPausedPlaybackPaused(capture, playback)   # REVIEWED Q18
│       ├── observe
│       │   ├── capture
│       │   │     recordingId
│       │   │     transcriptionId
│       │   ├── playback
│       │   │     recordingId
│       │   │     mediaPosition
│       │   └── recording
│       │         id
│       │         title
│       │         createdAt
│       │         updatedAt
│       │         finishedAt
│       │         duration
│       │         └──* transcription
│       │               id
│       │               recordingId
│       │               createdAt
│       │               updatedAt
│       │               finishedAt
│       │               └──* segment
│       │                     id
│       │                     transcriptionId
│       │                     index
│       │                     times
│       │                       wall
│       │                         start
│       │                         end
│       │                       relative
│       │                         start
│       │                         end
│       │                     body
│       │                       speech
│       │                         words[]
│       │                         text
│       │                         isFinal
│       │                       event
│       │                         kind
│       │                         …
│       └── send
│           ├── resumeRecording
│           │   └── goesTo
│           │         └── mode.recordingActivePlaybackPaused(capture, playback)
│           ├── stopRecording
│           │   ├── goesTo
│           │   │     └── mode.recordingIdlePlaybackPaused(playback)
│           │   └── mutate
│           │         ├── recording.finishedAt         set
│           │         ├── recording.duration           set
│           │         ├── recording.updatedAt          set
│           │         ├── transcription.finishedAt     set
│           │         └── transcription.updatedAt      set
│           ├── resumePlayback
│           │   └── goesTo
│           │         └── mode.recordingPausedPlaybackPlaying(capture, playback)
│           ├── stopPlayback
│           │   └── goesTo
│           │         └── mode.recordingPausedPlaybackIdle(capture)
│           ├── scrubPlayback
│           │   └── mutate
│           │         └── (mode) playback.mediaPosition   set
│           ├── openCaptureRecordingTimeline
│           │   └── goesTo
│           │         └── screen.timeline(capture.recordingId)
│           └── openPlaybackRecordingTimeline
│                 └── goesTo
│                       └── screen.timeline(playback.recordingId)
```

---

## Mutations (shorthand)

| Name | Meaning |
| --- | --- |
| `recording.create` | Start a new recording row. Creating the owned transcription (and empty open speech segment, if any) is **implementation** of start-record — not a second public mutate name. |
| `recording.delete` | Delete that recording; cascade of owned graph is implementation. |
| `segment.upsertSpeech` | Open-segment upsert of speech body + words |
| `response.create` | Thread (`parent.root`) or reply (`parent.reply`) |

Finish capture: explicit `finishedAt` / `duration` / `updatedAt` fields on
recording and transcription — not a `finishLinked` name.

---

## Navigation (WIP)

`goesTo.navigation.previous` — stack / tree / deep link. Not hard-coded to
`library.populated`.

---

## Killed names

| Dead | Replacement |
| --- | --- |
| `process` app root | deleted |
| `process.focus` | `screen.timeline(recordingId)` |
| `process.capture` / `playback` | mode leaf handles |
| prefs under process | `schema.preference` |
| `screen.detail.timeline` | `screen.timeline(recordingId)` |
| `mode.recordingX.playbackY` nested | `mode.recordingXPlaybackY` flat |
| `injectSimulatedSpeech` | `speechRecognized` |
| `recordingAndTranscription.createLinked` | `recording.create` |
| `recording.deleteLinked` / `finishLinked` | `recording.delete` / explicit finish fields |
