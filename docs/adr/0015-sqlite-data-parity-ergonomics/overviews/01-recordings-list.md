# Overview 01 — Recordings list (10-foot)

**Status:** accepted (2026-08-06)  
**Goal:** List many recordings with summary + activity ADT + bounded latest-segment
preview — never full transcripts, never app-side graph merge/diff.

## What the user sees (ASCII)

```text
┌─────────────────────────────────────────────────────────────┐
│ Recordings                                                  │
├─────────────────────────────────────────────────────────────┤
│ ● ACTIVE · this device                                      │
│   Recording 042 · 12:34 · 180 words · 📱                    │
│   “…and then we upsert only the open segment               │
│    and peers see it live.”                    ← 2 lines    │
│                                                             │
│ ◐ ACTIVE · other device                                     │
│   Recording 041 · 03:12 · 40 words · 💻                     │
│   “…peer is still speaking on the Mac and                  │
│    this phone is only following.”                           │
│                                                             │
│ ▶ PLAYBACK · this device                                    │
│   Recording 040 · 08:00 · 900 words                         │
│   “Finalized opening line of that session                   │
│    when we walked through the boundary.”                    │
│                                                             │
│   Recording 039 · 01:02 · 12 words          ← no idle badge │
│                                             ← no preview    │
└─────────────────────────────────────────────────────────────┘
```

### Activity ADT (product — not Instant delivery status)

**Decided (Q23):** Instant **client id** is the identity.

```text
RecordingActivity
  ├── active(clientId: InstantClientId)    // this ⇔ clientId == localClientId
  ├── playback(clientId: InstantClientId)
  └── (absent)                             // idle: no badge, no preview
```

Port/expose TS client id / local id into Swift if incomplete. This vs other is
only a comparison to `localClientId`.

### Tap behavior

| Row state | Tap |
| --- | --- |
| **Active · this device** | Open / continue recording here |
| **Active · other device** | Open as follow/observe (no silent mic steal) |
| **Playback · this device** | Open playback UI |
| **Default (no badge)** | Open detail / playback |

## Data per list row

**Summary fields:** id, title, duration, wordCount, deviceIcon, …

**Activity ADT:** as above.

**Latest segment preview:**

- At most **two lines** of text
- Shown only when activity is `active` or `playback`
- **Hidden** when idle / default
- Not the full segment list; not words graph; not full timeline

## Data flow (ASCII)

```text
  speech / stop / playback intents
              │
              │  ordinary row writes only
              │  (NO previous/current document diff)
              ▼
  update recording summary
  (duration, wordCount, activity ADT…)
  upsert open segment (write path elsewhere)
              │
              ▼
  library @Fetch* / InfiniteQuery
    · recording summary rows
    · latest segment text for preview (bounded)
              │
              ▼
         List UI
         (status · title · duration · 0–2 line preview)
```

## Explicitly rejected

- Full-document previous/current **diffing**
- Multi-subscribe merge for list paint
- Full timeline on list rows
- Showing an “idle” badge
- Preview on idle rows

## Latest segment preview (Q20 decided)

- **Relational:** list query includes the **two most recent segments** per
  recording (bounded), not denormalized full preview text on the recording.
- **Map:** library ergonomics map → list row; **truncate to two UI lines**
  (and char caps) even if a segment body is huge.
- Full syntax sketch: `overviews/03-list-query-syntax-sketch.md`

## Open (do not reopen this overview)

- Q28 — implement nested limit-per-parent / include ergonomics in library
