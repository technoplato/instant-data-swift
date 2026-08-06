# Overview 01 — Recordings list (10-foot)

**Status:** revised 2026-08-06 — summary + 2 segment lines + **attachment thumbnails**  
**Goal:** One list query loads everything a row needs; no full transcript; no dual-timeline merge.

## What each row needs

| Data | Source | Bound |
| --- | --- | --- |
| Title, duration, word count, device icon, activity | **Recording** summary fields | 1 parent row |
| Two lines of transcript preview | **Segments** (latest) | **limit 2** |
| Thumbnail strip | **Attachments** (images, etc.) | real attachment entities (UI may show first N thumbs) |

Not on the list path: all segments, words graph, full media bytes (thumbs use `storageFileID` / local cache later).

## Screen (ASCII)

```text
┌──────────────────────────────────────────────────────────────────────┐
│ Recordings                                                           │
├──────────────────────────────────────────────────────────────────────┤
│ ● ACTIVE · this device                                               │
│   Recording 042 · 12:34 · 180 words · 📱                             │
│   “…and then we upsert only the open segment                        │
│    and peers see it live.”                              ← 2 lines   │
│   ┌────┐ ┌────┐ ┌────┐                                  ← thumbs    │
│   │img │ │img │ │img │                                              │
│   └────┘ └────┘ └────┘                                              │
│                                                                      │
│ ◐ ACTIVE · other device                                              │
│   Recording 041 · 03:12 · 40 words · 💻                              │
│   “…peer is still speaking on the Mac.”                             │
│   “…this phone is only following.”                                  │
│   ┌────┐                                                             │
│   │img │                                                             │
│   └────┘                                                             │
│                                                                      │
│ ▶ PLAYBACK · this device                                             │
│   Recording 040 · 08:00 · 900 words                                  │
│   “Finalized opening line…”                                         │
│   “when we walked through the boundary.”                            │
│   ┌────┐ ┌────┐                                                      │
│   │img │ │img │                                                      │
│   └────┘ └────┘                                                      │
│                                                                      │
│   Recording 039 · 01:02 · 12 words          ← idle: no badge         │
│                                             ← no segment preview     │
│   ┌────┐                                    ← thumbs still ok        │
│   │img │                                                             │
│   └────┘                                                             │
└──────────────────────────────────────────────────────────────────────┘
```

Idle policy (prior decision): no activity badge, **hide segment preview**.  
Thumbnails can still show if attachments exist (product choice: show always).

## Data flow (ASCII)

```text
                    Instant store (local + outbox)
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
         ▼                    ▼                    ▼
   recordings            segments             attachments
   (summary attrs)     (per recording)      (per recording)
         │                    │                    │
         │     include        │     include        │
         │   order+limit 2    │   (e.g. images)    │
         └─────────┬──────────┴─────────┬──────────┘
                   │                    │
                   ▼                    ▼
              request-time MAP
         (Recording, bags.segments, bags.attachments)
                   │
                   ▼
            [RecordingListRow]
              · summary
              · previewLines[≤2]
              · thumbnails[]  (id, storageFileID, contentType, …)
                   │
                   ▼
              List UI
         (AsyncImage / local file from storageFileID)
```

Two **sibling bags** on the parent — not nested under each other:

```text
Recording snapshot
  links["segments"]    = [ segNewest, segNext ]     // max 2
  links["attachments"] = [ att1, att2, att3, … ]    // real rows for thumbs
```

## Walkthrough code (target API — bags shape)

Names approximate Scribe entities (`ScribeInstantRealtimeRecording`,  
`ScribeInstantRealtimeSegment`, `ScribeInstantRecordingAttachment`).  
Relation tokens assumed for clarity; today some links may be free-string ids.

### 1) List row DTO (app schema / UI model — not Instant-generated)

```swift
struct RecordingListRow: Equatable, Identifiable, Sendable {
  var id: InstantID<ScribeInstantRealtimeRecording>
  var title: String
  var durationSeconds: Double
  var wordCount: Double
  var deviceIcon: ScribeDeviceIcon?
  var activity: RecordingActivity?   // active(clientId) / playback / nil

  /// ≤ 2 UI lines from the two latest segments (empty when idle if product hides).
  var previewLines: [String]

  /// Real attachments for thumbnail strip (not a count).
  var thumbnails: [AttachmentThumbnail]
}

struct AttachmentThumbnail: Equatable, Identifiable, Sendable {
  var id: InstantID<ScribeInstantRecordingAttachment>
  var storageFileID: String?
  var contentType: String?
  var kind: String?   // image vs audio — UI may skip non-images
}
```

### 2) Query + map (request time — not the view)

```swift
// Target multi-bag API (Shape 1 from design discussion).
// L2 today only has single `children:`; multi-bag is the intended next step.

let listQuery =
  ScribeInstantRealtimeRecording.query
    .order(ScribeInstantRealtimeRecording.updatedAtMs, .descending)
    .limit(50)
    // Bag 1: two newest segments for preview text
    .include(
      ScribeInstantRealtimeRecording.segments,
      ScribeInstantRealtimeSegment.query
        .order(ScribeInstantRealtimeSegment.startTimeSeconds, .descending)
        .limit(2)
    )
    // Bag 2: attachments as real entities for thumbnails
    .include(
      ScribeInstantRealtimeRecording.attachments,
      ScribeInstantRecordingAttachment.query
        // optional: filter to images only if schema allows
        // .where(Attachment.kind == "image")
    )

let request = InstantFetchRequest(
  listQuery,
  map: { recording, bags in
    // bags.segments: 0...2 Segment
    // bags.attachments: 0...N Attachment (full rows for thumbs)
    let lines = makeTwoPreviewLines(from: bags.segments.map(\.text))
    let thumbs = bags.attachments.compactMap { att -> AttachmentThumbnail? in
      // Show images; skip pure audio if desired
      guard att.kind != "audio" else { return nil }
      return AttachmentThumbnail(
        id: att.id,
        storageFileID: att.storageFileID,
        contentType: att.contentType,
        kind: att.kind
      )
    }
    return RecordingListRow(
      id: recording.id,
      title: recording.title,
      durationSeconds: recording.durationSeconds,
      wordCount: recording.wordCount,
      deviceIcon: recording.deviceIcon,
      activity: recording.activity,
      previewLines: shouldShowSegmentPreview(activity: recording.activity) ? lines : [],
      thumbnails: thumbs
    )
  }
)
```

### 3) View only paints (no Instant graph)

```swift
List(rows) { row in
  VStack(alignment: .leading, spacing: 6) {
    activityBadge(row.activity)
    HStack {
      Text(row.title).font(.headline)
      Spacer()
      Text(formatDuration(row.durationSeconds))
    }
    ForEach(row.previewLines, id: \.self) { line in
      Text(line).font(.subheadline).foregroundStyle(.secondary)
        .lineLimit(1)
    }
    // Thumbnails — load image from Instant storage / local cache via storageFileID
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(row.thumbnails) { thumb in
          AttachmentThumbnailView(thumb)  // 44×44, etc.
        }
      }
    }
  }
}
```

### 4) Why two includes (not one)

```text
segments  → text for preview lines (must bound with limit 2)
attachments → actual image rows for thumbnails (bound by “what’s on the recording”,
              not by “limit 2 segments”)
```

If we only had single `children:`, we could map segments **or** attachments, not both cleanly — that’s why multi-bag / labeled bags is the robust API for this screen.

## Idle vs active (unchanged product rules)

```text
activity == nil (idle)
  → no badge
  → previewLines = []     (hide segment text)
  → thumbnails still shown if present

activity == active / playback
  → badge
  → previewLines from 2 segments
  → thumbnails
```

## Explicitly rejected

- Loading **all** segments for list paint  
- Denorm full `transcriptText` / preview string as the primary design  
- Multi-subscribe merge of recordings + segments + attachments in app code  
- Attachment **count only** when product wants **thumbnails of real rows**

## Open implementation (library)

- Multi-bag `map: { root, bags in }` (or labeled args) beyond single `children:`
- Relation tokens for `segments` / `attachments` if schema still uses free-string FKs
- Thumbnail image loading via Instant storage is separate from query ergonomics
