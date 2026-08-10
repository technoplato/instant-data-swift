# Overview 02 — Recording activity ADT

**Status:** SUPERSEDED — conflated schema with session mode (`Recording.activity`
notation was wrong). See `01-schema.md` + `03-session-mode-floating-toolbar.md`.

**Historical only (Q04 early draft)**

## Per-recording exclusive mode tree

```text
Recording.activity
├── recording(RecordingPhase)
│   ├── active
│   ├── paused
│   └── editingExisting     # deferred v1
├── finished
└── playback(PlaybackPhase)
    ├── playing
    └── paused
```

## Stop is a message

```text
  recording(.active | .paused)
         │  message: stop
         ▼
      finished
```

Not: `activity = stopped`.

## Create is a message

```text
  FAB / createAndStart
         │
         ▼
  new Recording { activity: recording(.active) }
```

Not: phase `recordingNew` on an existing id.

## Process-level lanes (Q05)

```text
  ThisClientSession (parallel to per-row activity)
  ├── recordingLane: Recording.ID?    // at most one
  └── playbackLane:  Recording.ID?    // at most one
```

If Q05 = yes, row A can be `recording(.active)` while row B is
`playback(.playing)` on the same client.

## Name

**Recording** for now — not Media.
