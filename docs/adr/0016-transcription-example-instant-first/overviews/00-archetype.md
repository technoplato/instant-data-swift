# Overview 00 — Archetype (DomainAsTree)

**Status:** accepted (Q02, 2026-08-10)

## One-liner

```text
Local-first voice memos: simulated speech becomes attributed words on the
active recording's transcription segments; list / detail / playback stay in
sync across Instant clients; no real microphone.
```

## v1 speech + debug

- Speech: **simulated** (engine extracted elsewhere); **rate slider** in UI.
- Debug: **RecipesDebugPanel** reused — **DEV builds always on + expanded**,
  no enable flags (`Sources/RecipesV3App/RecipesDebugPanel.swift` + Support).

## Proxy mapping (toolshed)

```text
Favorite stopwatch     ->  Active recording (transcription lane)
Non-favorite running   ->  Playback of a past recording
FAB (idle)             ->  Create + start new recording
Floating controls      ->  Global record / pause / stop / jump
```

## What this is not

- Not Scribe product (no media pipeline, no real STT, no widgets first)
- Not stock SyncUps meetings
- Not VoiceTrail rename

## Screens prior art (API-first)

`screens/v3/` (recordings-list, recording, playback, …) was designed around the
desired Instant API surface — inventory only until Transcription mode trees land.
