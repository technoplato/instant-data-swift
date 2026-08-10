# Overview 04b — Message graph experiment (may not keep)

**Experiment started:** Monday, 2026-08-10, 5:46 PM (America/New_York)  
**Status:** exploratory — duplicate of the URI tree idea with a **static graph**  
of schema · messages · mutations · commands · send-sites. We might throw this
away. Do not implement runtime enforcement until the interview keeps it.

**Parent tree (source of truth for structure):**  
[`04-uri-tree.md`](./04-uri-tree.md)

**Schema:**  
`/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md`

---

## Why

Instant’s triple store keeps the same fact under multiple indexes (EAV / AEV /
VAE-style lookups). We want something similar for the **domain graph**:

| Index | Answers |
| --- | --- |
| **message → writes** | Which schema paths may this message change? |
| **schema path → messages** | Which messages are *allowed* to change this path? |
| **node → send** | Which messages may this screen/mode leaf send? |
| **message → commands** | Which side-effect commands fire (Foldkit-style)? |
| **message → goesTo** | Which app-tree transitions result? |

Later: static analysis or runtime checks that a mutate of `recording.finishedAt`
only happens under a message that declared that write.

**No source code** in this file — declaration only.

---

## Nomenclature (best guess)

| Term | Role | Foldkit-ish | TCA-ish |
| --- | --- | --- | --- |
| **message** | Present-tense UI/system fact the app accepts | Message | Action / intent |
| **command** | Side-effect intent (I/O, audio, outbox flush, timers) | Command | Effect / `store` task |
| **mutation** | Declared durable or session **schema/session write** | Model update | State write in reducer |
| **goesTo** | App-tree transition (screen/mode product) | navigation | state enum change |
| **observe** | Schema/session slices a node is allowed to read | subscriptions | `@Fetch*` / store state |

Only **messages** listed in the catalog exist. Nodes may only `send` catalog ids.
Mutations may only target schema (or named session) paths. Commands never write
schema directly — they cause effects; results return as **later messages**.

---

## Session paths (not durable schema)

```text
session.focus.recordingId
session.capture.recordingId
session.capture.transcriptionId
session.playback.recordingId
session.playback.mediaPosition
session.navigation.stack
process.speechRate
process.speechRateDefault
process.debugPanel.presentation
```

---

## 1. Message catalog

Each message: `payload`, `writes` (schema/session paths), `commands`, `goesTo`
(from → to, parametric).

### msg.openSettings

```text
payload
  (none)

writes
  (none)

commands
  (none)

goesTo
  *.screen.*  →  screen.settings
```

### msg.goBack

```text
payload
  (none)

writes
  session.navigation.stack     pop

commands
  (none)

goesTo
  *  →  navigation.previous
```

### msg.openRecording

```text
payload
  recordingId                  recording.id

writes
  session.focus.recordingId    set payload.recordingId

commands
  (none)

goesTo
  *.screen.*  →  screen.detail.timeline
```

### msg.deleteRecording

```text
payload
  recordingId                  recording.id

writes
  recording.*                  delete entity payload.recordingId
  transcription.*              delete where recordingId = payload
  segment.*                    delete owned
  response.*                   delete owned

commands
  cmd.outboxEnqueueDelete      optional host
  cmd.mediaDelete              optional host

goesTo
  (stay)
```

### msg.startRecording

```text
payload
  (none)                       host defaults

writes
  recording.*                  create (defaults)
  transcription.*              create linked to new recording
  session.capture.recordingId  set new recording.id
  session.capture.transcriptionId  set new transcription.id

commands
  cmd.beginAudioCapture        host / sim
  cmd.scheduleSimSpeech        DEV when sim

goesTo
  mode.recordingIdle.playbackIdle
    → mode.recordingActive.playbackIdle
  mode.recordingIdle.playbackPlaying
    → mode.recordingActive.playbackPlaying
  mode.recordingIdle.playbackPaused
    → mode.recordingActive.playbackPaused
```

### msg.pauseRecording

```text
payload
  (none)

writes
  (none durable)               capture stays open

commands
  cmd.pauseAudioCapture

goesTo
  mode.recordingActive.playbackIdle
    → mode.recordingPaused.playbackIdle
  mode.recordingActive.playbackPlaying
    → mode.recordingPaused.playbackPlaying
  mode.recordingActive.playbackPaused
    → mode.recordingPaused.playbackPaused
```

### msg.resumeRecording

```text
payload
  (none)

writes
  (none durable)

commands
  cmd.resumeAudioCapture

goesTo
  mode.recordingPaused.playbackIdle
    → mode.recordingActive.playbackIdle
  mode.recordingPaused.playbackPlaying
    → mode.recordingActive.playbackPlaying
  mode.recordingPaused.playbackPaused
    → mode.recordingActive.playbackPaused
```

### msg.stopRecording

```text
payload
  (none)

writes
  recording.finishedAt         set
  recording.duration           set
  recording.updatedAt          set
  transcription.finishedAt     set
  transcription.updatedAt      set
  session.capture.recordingId  clear
  session.capture.transcriptionId  clear

commands
  cmd.stopAudioCapture
  cmd.finalizeOpenSegment

goesTo
  mode.recordingActive.playbackIdle
    → mode.recordingIdle.playbackIdle
  mode.recordingActive.playbackPlaying
    → mode.recordingIdle.playbackPlaying
  mode.recordingActive.playbackPaused
    → mode.recordingIdle.playbackPaused
  mode.recordingPaused.playbackIdle
    → mode.recordingIdle.playbackIdle
  mode.recordingPaused.playbackPlaying
    → mode.recordingIdle.playbackPlaying
  mode.recordingPaused.playbackPaused
    → mode.recordingIdle.playbackPaused
```

### msg.playRecording

```text
payload
  recordingId                  recording.id

writes
  session.playback.recordingId set payload.recordingId
  session.playback.mediaPosition  set zero or resume

commands
  cmd.startMediaPlayback

goesTo
  mode.recordingIdle.playbackIdle
    → mode.recordingIdle.playbackPlaying
  mode.recordingActive.playbackIdle
    → mode.recordingActive.playbackPlaying
  mode.recordingPaused.playbackIdle
    → mode.recordingPaused.playbackPlaying
  # if already playing another id: replace playback target (same leaf)
```

### msg.pausePlayback

```text
payload
  (none)

writes
  (none)                       position retained in session

commands
  cmd.pauseMediaPlayback

goesTo
  mode.recordingIdle.playbackPlaying
    → mode.recordingIdle.playbackPaused
  mode.recordingActive.playbackPlaying
    → mode.recordingActive.playbackPaused
  mode.recordingPaused.playbackPlaying
    → mode.recordingPaused.playbackPaused
```

### msg.resumePlayback

```text
payload
  (none)

writes
  (none)

commands
  cmd.resumeMediaPlayback

goesTo
  mode.recordingIdle.playbackPaused
    → mode.recordingIdle.playbackPlaying
  mode.recordingActive.playbackPaused
    → mode.recordingActive.playbackPlaying
  mode.recordingPaused.playbackPaused
    → mode.recordingPaused.playbackPlaying
```

### msg.stopPlayback

```text
payload
  (none)

writes
  session.playback.recordingId clear
  session.playback.mediaPosition clear

commands
  cmd.stopMediaPlayback

goesTo
  mode.recordingIdle.playbackPlaying
    → mode.recordingIdle.playbackIdle
  mode.recordingIdle.playbackPaused
    → mode.recordingIdle.playbackIdle
  mode.recordingActive.playbackPlaying
    → mode.recordingActive.playbackIdle
  mode.recordingActive.playbackPaused
    → mode.recordingActive.playbackIdle
  mode.recordingPaused.playbackPlaying
    → mode.recordingPaused.playbackIdle
  mode.recordingPaused.playbackPaused
    → mode.recordingPaused.playbackIdle
```

### msg.scrubPlayback

```text
payload
  mediaPosition                Duration

writes
  session.playback.mediaPosition  set payload

commands
  cmd.seekMediaPlayback

goesTo
  (stay)
```

### msg.openActiveTimeline

```text
payload
  (none)                       uses session.capture.recordingId

writes
  session.focus.recordingId    set session.capture.recordingId

commands
  (none)

goesTo
  *.screen.*  →  screen.detail.timeline
```

### msg.injectSimulatedSpeech

```text
payload
  words[]                      transcription.word
  isFinal                      Bool

writes
  segment.*                    upsert open speech segment
  segment.body.speech.words
  segment.body.speech.text     derived
  segment.body.speech.isFinal
  segment.times.*              derived
  transcription.updatedAt
  recording.updatedAt
  recording.duration           optional live bump

commands
  cmd.outboxEnqueueSegment     durable outbox when live Instant

goesTo
  (stay on current mode leaf under recordingActive.*)
```

### msg.postResponse

```text
payload
  segmentId                    segment.id
  text                         String
  author                       transcription.author

writes
  response.*                   create
  response.parent              root
  response.segmentId
  response.text
  response.author
  response.createdAt

commands
  cmd.outboxEnqueueResponse

goesTo
  (stay)
```

### msg.replyToResponse

```text
payload
  segmentId                    segment.id
  parentResponseId             response.id
  text                         String
  author                       transcription.author

writes
  response.*                   create
  response.parent              reply(parentResponseId)
  response.segmentId
  response.text
  response.author
  response.createdAt

commands
  cmd.outboxEnqueueResponse

goesTo
  (stay)
```

### msg.setSpeechRateDefault

```text
payload
  rate                         Float64

writes
  process.speechRateDefault    set

commands
  (none)

goesTo
  (stay)
```

### msg.setSpeechRate

```text
payload
  rate                         Float64

writes
  process.speechRate           set

commands
  (none)

goesTo
  (stay)
```

### msg.setDebugPanelPresentation

```text
payload
  presentation                 expanded | collapsed | hidden

writes
  process.debugPanel.presentation  set

commands
  (none)

goesTo
  (stay)
```

---

## 2. Command catalog (side effects only)

```text
cmd.beginAudioCapture
cmd.pauseAudioCapture
cmd.resumeAudioCapture
cmd.stopAudioCapture
cmd.scheduleSimSpeech
cmd.startMediaPlayback
cmd.pauseMediaPlayback
cmd.resumeMediaPlayback
cmd.stopMediaPlayback
cmd.seekMediaPlayback
cmd.finalizeOpenSegment
cmd.outboxEnqueueSegment
cmd.outboxEnqueueResponse
cmd.outboxEnqueueDelete
cmd.mediaDelete
```

Commands do not list schema writes. Completions re-enter as messages later
(e.g. sim speech timer → `msg.injectSimulatedSpeech`).

---

## 3. Schema path → messages allowed to write (AEV-style index)

Only **declared** writers. Anything else is illegal for static check.

```text
recording.id
  msg.startRecording

recording.title
  msg.startRecording                 default
  # title edit not in tree yet

recording.createdAt
  msg.startRecording

recording.updatedAt
  msg.startRecording
  msg.stopRecording
  msg.injectSimulatedSpeech

recording.finishedAt
  msg.stopRecording

recording.duration
  msg.startRecording                 zero
  msg.stopRecording
  msg.injectSimulatedSpeech          optional live

recording (delete)
  msg.deleteRecording

transcription.id
  msg.startRecording

transcription.recordingId
  msg.startRecording

transcription.createdAt
  msg.startRecording

transcription.updatedAt
  msg.startRecording
  msg.stopRecording
  msg.injectSimulatedSpeech

transcription.finishedAt
  msg.stopRecording

transcription (delete)
  msg.deleteRecording

segment.*
  msg.injectSimulatedSpeech
  msg.deleteRecording                cascade

segment.body.speech.words
  msg.injectSimulatedSpeech

segment.body.speech.text
  msg.injectSimulatedSpeech          derived

segment.body.speech.isFinal
  msg.injectSimulatedSpeech

segment.times.*
  msg.injectSimulatedSpeech          derived

response.*
  msg.postResponse
  msg.replyToResponse
  msg.deleteRecording                cascade

session.focus.recordingId
  msg.openRecording
  msg.openActiveTimeline

session.capture.recordingId
  msg.startRecording
  msg.stopRecording

session.capture.transcriptionId
  msg.startRecording
  msg.stopRecording

session.playback.recordingId
  msg.playRecording
  msg.stopPlayback

session.playback.mediaPosition
  msg.playRecording
  msg.scrubPlayback
  msg.stopPlayback

session.navigation.stack
  msg.goBack
  # push not fully declared — WIP

process.speechRateDefault
  msg.setSpeechRateDefault

process.speechRate
  msg.setSpeechRate

process.debugPanel.presentation
  msg.setDebugPanelPresentation
```

---

## 4. App tree (send = message ids only)

Same shape as `04-uri-tree.md`. Leaves list **observe** + **send** catalog ids.
No inline mutate bodies — those live in §1.

```text
transcription.app
│
├── screen
│   │
│   ├── library
│   │   │
│   │   ├── empty
│   │   │   ├── observe
│   │   │   │   └── recording[]                    empty
│   │   │   └── send
│   │   │       └── msg.openSettings
│   │   │
│   │   └── populated
│   │       ├── observe
│   │       │   └── recording[]
│   │       │         id
│   │       │         title
│   │       │         duration
│   │       │         finishedAt
│   │       │         previewThumbs[]
│   │       │         responseCount
│   │       │         activityBadge
│   │       └── send
│   │           ├── msg.openRecording
│   │           ├── msg.deleteRecording
│   │           ├── msg.playRecording
│   │           └── msg.openSettings
│   │
│   ├── detail
│   │   └── timeline
│   │       ├── observe
│   │       │   ├── session.focus.recordingId
│   │       │   ├── recording
│   │       │   │     id title createdAt updatedAt finishedAt duration
│   │       │   ├── transcription
│   │       │   │     id recordingId createdAt updatedAt finishedAt
│   │       │   ├── segment[]
│   │       │   │     id index times body
│   │       │   └── response[]
│   │       └── send
│   │           ├── msg.goBack
│   │           ├── msg.postResponse
│   │           ├── msg.replyToResponse
│   │           └── msg.playRecording
│   │
│   └── settings
│       ├── observe
│       │   ├── process.speechRateDefault
│       │   └── process.debugPanel.presentation
│       └── send
│           ├── msg.setSpeechRateDefault
│           ├── msg.setDebugPanelPresentation
│           └── msg.goBack
│
├── mode
│   │
│   ├── recordingIdle
│   │   ├── playbackIdle
│   │   │   ├── observe
│   │   │   │   └── (no capture; no playback)
│   │   │   └── send
│   │   │       └── msg.startRecording
│   │   │
│   │   ├── playbackPlaying
│   │   │   ├── observe
│   │   │   │   ├── session.playback.recordingId
│   │   │   │   └── session.playback.mediaPosition
│   │   │   └── send
│   │   │       ├── msg.pausePlayback
│   │   │       ├── msg.stopPlayback
│   │   │       ├── msg.scrubPlayback
│   │   │       └── msg.startRecording
│   │   │
│   │   └── playbackPaused
│   │       ├── observe
│   │       │   ├── session.playback.recordingId
│   │       │   └── session.playback.mediaPosition
│   │       └── send
│   │           ├── msg.resumePlayback
│   │           ├── msg.stopPlayback
│   │           ├── msg.scrubPlayback
│   │           └── msg.startRecording
│   │
│   ├── recordingActive
│   │   ├── playbackIdle
│   │   │   ├── observe
│   │   │   │   ├── session.capture.recordingId
│   │   │   │   ├── session.capture.transcriptionId
│   │   │   │   ├── recording                        fields
│   │   │   │   ├── transcription                    fields
│   │   │   │   └── segment                          speech tail
│   │   │   └── send
│   │   │       ├── msg.pauseRecording
│   │   │       ├── msg.stopRecording
│   │   │       ├── msg.playRecording
│   │   │       ├── msg.openActiveTimeline
│   │   │       └── msg.injectSimulatedSpeech
│   │   │
│   │   ├── playbackPlaying
│   │   │   ├── observe
│   │   │   │   ├── session.capture.*
│   │   │   │   ├── session.playback.*
│   │   │   │   ├── recording
│   │   │   │   ├── transcription
│   │   │   │   └── segment
│   │   │   └── send
│   │   │       ├── msg.pauseRecording
│   │   │       ├── msg.stopRecording
│   │   │       ├── msg.pausePlayback
│   │   │       ├── msg.stopPlayback
│   │   │       ├── msg.scrubPlayback
│   │   │       ├── msg.openActiveTimeline
│   │   │       └── msg.injectSimulatedSpeech
│   │   │
│   │   └── playbackPaused
│   │       ├── observe
│   │       │   ├── session.capture.*
│   │       │   ├── session.playback.*
│   │       │   ├── recording
│   │       │   ├── transcription
│   │       │   └── segment
│   │       └── send
│   │           ├── msg.pauseRecording
│   │           ├── msg.stopRecording
│   │           ├── msg.resumePlayback
│   │           ├── msg.stopPlayback
│   │           ├── msg.scrubPlayback
│   │           ├── msg.openActiveTimeline
│   │           └── msg.injectSimulatedSpeech
│   │
│   └── recordingPaused
│       ├── playbackIdle
│       │   ├── observe
│       │   │   ├── session.capture.*
│       │   │   ├── recording
│       │   │   └── transcription
│       │   └── send
│       │       ├── msg.resumeRecording
│       │       ├── msg.stopRecording
│       │       ├── msg.playRecording
│       │       └── msg.openActiveTimeline
│       │
│       ├── playbackPlaying
│       │   ├── observe
│       │   │   ├── session.capture.*
│       │   │   ├── session.playback.*
│       │   │   ├── recording
│       │   │   └── transcription
│       │   └── send
│       │       ├── msg.resumeRecording
│       │       ├── msg.stopRecording
│       │       ├── msg.pausePlayback
│       │       ├── msg.stopPlayback
│       │       ├── msg.scrubPlayback
│       │       └── msg.openActiveTimeline
│       │
│       └── playbackPaused
│           ├── observe
│           │   ├── session.capture.*
│           │   ├── session.playback.*
│           │   ├── recording
│           │   └── transcription
│           └── send
│               ├── msg.resumeRecording
│               ├── msg.stopRecording
│               ├── msg.resumePlayback
│               ├── msg.stopPlayback
│               ├── msg.scrubPlayback
│               └── msg.openActiveTimeline
│
└── process
    ├── speechRate
    │   ├── observe
    │   │   └── process.speechRate
    │   └── send
    │       └── msg.setSpeechRate
    └── debugPanel
        ├── observe
        │   ├── memory
        │   ├── logs
        │   ├── buildProvenance
        │   └── process.debugPanel.presentation
        └── send
            └── msg.setDebugPanelPresentation
```

---

## 5. Enforcement sketch (future, not built)

```text
For every runtime mutate of path P under handling of message M:
  require P ∈ catalog[M].writes

For every send of M from node N:
  require M ∈ tree[N].send

For every command C fired under M:
  require C ∈ catalog[M].commands
```

Foldkit: message → commands → later messages.  
TCA: message ≈ action; commands ≈ effects/tasks.  
Instant outbox: `cmd.outboxEnqueue*` is a command; durable row writes stay in
`writes`.

---

## 6. Relation to Instant indexes (analogy only)

| Instant | This experiment |
| --- | --- |
| EAV (entity, attr, value) | session/schema fact |
| AEV (attr → entities) | schema path → messages that may write it (§3) |
| VAE | less relevant here |
| Triple fact once | message catalog once; tree only references ids |

---

## Keep or kill

- **Keep if:** static graph stays readable and matches how we want Foldkit/TCA
  hosts enforced.
- **Kill if:** dual maintenance with `04-uri-tree.md` is worse than one tree.

Parent tree remains the structural WIP captain was reviewing. This file is the
Monday 5:46 PM graph experiment.
