# Overview 02 — Active transcription (10-foot)

**Status:** accepted (2026-08-06)  
**Goal:** Live speech publishes only the current **recording segment**; UI
observes segments for this recording. No full-document diffing. No stored full
transcript text.

## What the user sees (ASCII)

```text
┌─────────────────────────────────────────────────────────────┐
│ ● Recording 042 · this device · 12:34                       │
│   [Stop]  [Pause]                                           │
├─────────────────────────────────────────────────────────────┤
│  (older finalized segments — scrollable)                    │
│                                                             │
│  Speaker 1                                                  │
│  We decided the list only shows a two-line                  │
│  preview and never a full timeline.                         │
│  [sync: ok]                                                 │
│                                                             │
│  Speaker 1                         ← current recording seg  │
│  And the open segment keeps updating as I                   │
│  talk… words live as JSON on this row.                      │
│  [sync: pending]                                            │
│                                                             │
│                         ▽ live follow                       │
└─────────────────────────────────────────────────────────────┘
```

`[sync: …]` = library **entity sync status** on the segment row (optional in
prod UI). Orthogonal to speech `isFinal` and list **activity ADT**.

## Naming

- **Recording segment id** — the segment currently being written for this speech
  lane (was “open segment id” in drafts). App tracks this id only for write
  targeting.

## Library recipe

Canonical Instant write steps, write contract, wordsJSON, and non-goals:
[`../open-segment-write-recipe.md`](../open-segment-write-recipe.md).

## Write loop (ASCII)

```text
  speech token arrives
         │
         ▼
  app: recordingSegmentID known?
    no  → create new segment id, isFinal=false
    yes → keep same id
         │
         ▼
  upsert THAT segment only
    · text
    · words JSON [{start, end, text}, …]  (strict Codable)
    · isFinal = false
    · always local + outbox
         │
         ▼
  section final from speech?
    yes → upsert same id, isFinal=true
          clear recordingSegmentID (current product scope)
          next speech → new id
    no  → wait for more tokens
```

No previous full `Recording`. No `liveChanges` planner. No lastSaved full graph.
No `transcriptionText` / joined full transcript attribute.

## Observation (ASCII)

```text
  @FetchAll / observe
    segments where recordingID == current
    ordered by start / index
         │
         ▼
  each row: domain fields + library syncStatus
         │
         ▼
  Transcript UI
```

## Full transcript / export

Not stored. **Generate on demand** into the requested format (SRT, DTT,
Markdown, JSON, plain, …) from segments + words JSON — same idea as
copy-as-format.

## Who owns what

| Layer | Responsibility |
| --- | --- |
| App | recordingSegmentID; speech isFinal; schema; words Codable JSON; export generators |
| Library | materialize, outbox, coalesce same-segment supersedes, syncStatus on fetch |
| App must not | previous/current document diff; stored full transcript text; fake sync maps |

## Rejected

- Full-document previous/current diff planners (`liveChanges` / `finalChanges`)
- Word Instant entities
- Stored joined `transcriptionText` for convenience
- Silent `try?` on save
- Skipping outbox for interim text
