# Overview 03 — Session mode + floating toolbar (not schema)

**Status:** draft from toolshed SyncUps proxy + Q05 direction  
**Source:** toolshed floating stopwatch controls (proxy domain plan)  
**Name:** **floating toolbar** — do not use the acronym FAB.

## Disambiguation

| Concept | Layer |
| --- | --- |
| Recording finished vs open | Schema (`finishedAt` etc.) |
| This client recording A and/or playing B | **Session mode** (feature tree) |
| List row badge “active on other device” | Optional Instant projection later |

## Session mode ADT (floating toolbar driver)

Derived from “which recording is the active transcription lane” + “which is the
playback lane” — same as SyncUps favorite + non-favorite running. **Not stored
as a free-floating third DB**; computed from session pointers + schema facts
(or held as explicit session state).

```text
Session.mode
├── Idle
│   no recording lane, no playback lane
│   floating toolbar: create + start new Recording
├── Recording
│   recording lane set; no playback lane
│   controls: pause/resume recording, stop (→ finish), time, jump to detail
│   └── phase
│       ├── Active
│       └── Paused
├── Playback
│   playback lane set; no recording lane
│   controls: scrub, play/pause, create new recording
│   └── phase
│       ├── Playing
│       └── Paused
└── Both
    recording lane + playback lane (same or different Recording ids)
    controls: playback scrub + play/pause; jump to active recording;
              recording stop/pause as designed
    ├── recording: phase Active | Paused
    └── playback: phase Playing | Paused
```

### Valid combinations (exhaustive)

| Recording lane | Playback lane | Mode |
| --- | --- | --- |
| none | none | Idle |
| A | none | Recording(A, phase) |
| none | B | Playback(B, phase) |
| A | B (A ≠ B) | Both(A, B, phases) |
| A | A | **Both(A, A, phases)** — **legal** |

Captain correction (2026-08-10): same id on both lanes is **allowed**. Example:
pause the current transcription and play that recording’s audio. Behavior
differs (no forced “jump elsewhere”), but it is **not** illegal.

Constraints:

1. At most one recording lane.
2. At most one playback lane.
3. Playing C while B was playing → pause B (single playback).
4. Recording phase and playback phase are independent (including same id).
5. Do not invent “same id illegal” without captain confirmation.

## Floating toolbar behavior (from SyncUps floating controls — use this)

| Mode | Floating toolbar shows |
| --- | --- |
| Idle | Create new recording (start) |
| Recording | Pause/resume, stop, elapsed, open active detail |
| Playback | Scrub + play/pause + **create new recording** |
| Both | Scrub + play/pause for playback + **jump to active** recording |

Creating new recording from Playback: pause playback, create+start recording,
navigate to detail (toolshed rule).

## Mapping stopwatch → Transcription

| Stopwatch | Transcription |
| --- | --- |
| favoriteStopwatchID | recording lane id |
| non-favorite isRunning | playback lane id |
| Mode.idle | Session.Idle |
| Mode.activeTranscription | Session.Recording |
| Mode.playbackOnly | Session.Playback |
| Mode.both | Session.Both |

## Per-row schema vs session

A past recording with `finishedAt != nil` is **Finished in schema** even when
session is Idle. “Idle past recording” = finished row sitting in the library
with no session lane pointing at it.
