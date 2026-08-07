# ADR 0014: Entity lifecycle status, Fetch observation, and open-segment writes

- Status: Proposed (revised 2026-08-06 — **draft does not skip outbox**)
- Date: 2026-08-06
- Scope: Instant Swift Data local materialization, optimistic outbox, `@Fetch*`
  observation, generated `Entity.Draft` write values, and status projection
- Related: ADR 0001 (application/sync boundary), ADR 0013 (protect pending
  optimistic from empty live-query retractions)
- Product driver: Scribe long-recording memory — stop dual in-app timelines and
  full-graph / `transcriptText` rewrites; keep **every** segment update
  local-first **and** outbox-synced; fix churn by **write shape**, not by
  withholding publication

## Context

### What SQLiteData and Sharing already teach

SQLiteData’s `@FetchAll` / `@FetchOne` / `@Fetch` are not bespoke observers per
screen. They are thin wrappers over Point-Free **Sharing** `SharedReader` keys.
The library owns the subscription keyed by query identity; any number of views
attach the same fetch and see the same projected result. Writes go through the
database; readers invalidate by observation — not by hand-pushing
`timelineUpdated → list.timeline = …`.

Instant already aspires to that shape for `@Fetch*` (ADR 0001). The missing
product pieces for Scribe are:

1. **Observation without dual TCA timelines** (list vs active).
2. **Lifecycle / sync status** on fetch results so UI (especially dev builds)
   can show draft → pending → confirmed without knowing outbox internals.
3. **Performant live speech writes**: interim updates must not re-project the
   entire recording or rewrite finalized history.

### Direction change (explicit)

An earlier draft of this ADR proposed `publication: .draft` that **skipped the
outbox** so interim speech stayed local-only. **That is withdrawn.**

- Interim (non-final) segments **are published** through the normal Instant
  path: local materialize + durable outbox + server when online.
- If rapid open-segment updates are expensive, **fix library/app write
  efficiency** (append / rewrite only the open segment). Do not paper over
  cost by refusing to sync.

`Entity.Draft` remains the **write ergonomics** shape (like SQLiteData
`Reminder.Draft` → insert/update), not a “hold off the server” mode.

### What Instant Draft is today

`@InstantEntity` generates `Entity.Draft: InstantEntityDraft` — a write-value
builder. `db.save(draft)` materializes locally and enters the outbox. That is
the intended path for **all** speech updates (interim and final).

### What Scribe is doing wrong today (app, not Instant)

1. **Active recording** holds a full in-memory `timeline`.
2. On every update, **RecordingList copies** that entire timeline into
   `recordings[i].timeline`.
3. A **snapshot save** re-projects the rich model, often rewriting **full
   `transcriptText`** and effectively re-diffing large graphs on every partial.

Churn was never “we published the open segment.” Churn was **full-graph /
full-text rewrite** and **dual in-memory timelines**.

## Decision

### 1. One entity graph; no second store

```text
Recording 1──* Transcription 1──* TranscriptionSegment 1──* TranscriptionWord
```

- Generated `TranscriptionSegment.Draft` / `TranscriptionWord.Draft` for writes.
- No app `LiveSegmentDraftStore`, no parallel draft namespace.

### 2. Always sync; fix write shape for the open segment

Live speech policy (application contract the library must make cheap):

| Event | Write |
|-------|--------|
| First words of a new interim section | **Create** segment (+ words) with stable id; `isFinal == false` |
| More interim updates for **same** section | **Update only that segment** (and its word set); same id |
| Section finalized | **Update** that segment to `isFinal == true` (and final words); then **never rewrite that segment** during the rest of the active recording |
| Next section starts | **Create** a new segment id (append); previous finals stay immutable |

Invariants:

- At most **one open (non-final) segment** per speech lane (e.g. mic vs system
  audio) at a time.
- Finalized segments are **append-only history** for the session: no bulk
  re-upsert of the whole timeline on each partial.
- **No** full joined `transcriptText` on the transcription row for the live
  path (Scribe product; join on read later if needed).

If memory/CPU still blows up under this policy, treat it as a **library or
projection bug** (e.g. materialize-all-observers, dual residency thrash), not as
a reason to skip outbox.

### 3. Lifecycle / sync status is a library projection (ADT)

Fetch results expose a **sync status** algebraic type with **payloads** (times,
errors), not a bare string. Exact cases are implementation detail; intent:

```swift
// Conceptual shape — not a frozen public API spelling
enum InstantEntitySyncStatus: Equatable, Sendable {
  case localMaterialized(at: InstantTimestamp)           // applied locally, not yet outbox head
  case pendingDelivery(enqueuedAt: InstantTimestamp, …) // in outbox
  case inFlight(sentAt: InstantTimestamp, …)
  case confirmed(ackedAt: InstantTimestamp, …)
  case rejected(at: InstantTimestamp, reason: …)
}
```

Notes:

- **Domain** `isFinal` (speech interim vs final) stays on the app segment model
  and is **orthogonal** to sync status.
- Status is **derived/stored by the materialization + outbox layer**, not
  reimplemented per feature.
- **Dev / debug builds** (Scribe) should surface this on transcript rows
  (compact badge or overlay): e.g. pending vs confirmed, timestamps.
- “Local only forever / never publish” is **not** a default speech mode. If a
  product needs never-publish rows later, that is a separate policy flag, not
  the interim-speech path.

### 4. `Entity.Draft` + `db.save` — always the normal mutation path

```swift
// Pseudocode for product intent — real Instant APIs use query builders /
// save(draft) as they exist today; this is not a frozen DSL.

// Interim: rewrite ONLY the open segment
try await db.save(
  TranscriptionSegment.Draft(
    id: openSegmentID,
    isFinal: false,
    /* text/times/words for this segment only */
  )
)

// Final: same id, mark final; then stop touching this id
try await db.save(
  TranscriptionSegment.Draft(
    id: openSegmentID,
    isFinal: true,
    /* final words */
  )
)

// Next partials use a NEW segment id (append)
```

There is **no** `publication: .draft` that skips outbox. That earlier sketch is
**invalid as product policy** and was only illustrative.

### 5. `@Fetch` is the multi-screen observation bus

```swift
// Active recording — segments for this recording (real query API TBD)
@FetchAll(/* segments where recordingID == … ordered by start */)
var segments: [TranscriptionSegment]
// each row: domain isFinal + library syncStatus ADT

// Sidebar — narrow projection only
@FetchAll(/* recordings: title, duration, wordCount — no segment include */)
var rows: [RecordingListRow]
```

Multiple screens may attach the **same** segment query key and share one
library observation (Sharing-shaped). **No** feature copies another feature’s
timeline array.

Optional filters (when status is queryable): confirmed-only for export UIs,
etc. Default active UI includes open non-final segments (they are real synced
rows).

### 6. Application boundary (ADR 0001)

| App owns | Library owns |
|----------|----------------|
| When speech is interim vs final; open segment id per lane | Materialization, outbox, reconnect, status projection |
| Declaring which Fetch queries to observe | Invalidating those queries after mutations |
| Dev overlay that **displays** syncStatus | Computing syncStatus |
| Not holding dual full timelines | Making open-segment upsert cheap enough to sync every update |

## Consequences

### Positive

- Multi-device / multi-surface can see live interim text (publish always).
- Churn addressed at the right layer: **open-segment-only** writes + no
  full-text denorm + no dual TCA timelines.
- Draft type ergonomics retained; sync status ADT for debug and product UI.
- If cost is still high, pressure stays on Instant performance work (correct).

### Negative / costs

- High partial rate still generates many outbox mutations **for one entity
  id** — library should coalesce / replace in-flight mutations for the same
  entity where safe (implementation follow-up; not “don’t sync”).
- Dev UI must not treat “many pending” as failure if open-segment updates are
  frequent by design.

### Explicitly withdrawn

- Skipping outbox for “draft” interim speech.
- Local-only interim as the default Scribe path.
- App-level draft stores that never go through Instant.

## Pseudocode disclaimer

Examples that look like:

```swift
.where { $0.recordingID == recordingID }
publication: .draft
```

are **product-intent sketches**, not claims that Instant already ships that
exact DSL. Real call sites use whatever typed query / `save(draft)` APIs exist
at implementation time.

## Alternatives considered

1. **Outbox-skip drafts for interim** — Rejected (this revision). Hides
   performance bugs; blocks multi-device live interim; user wants everything
   synced.
2. **Full recording snapshot on every partial** — Rejected. Root of churn.
3. **Dual TCA timelines** — Rejected. Use Fetch observation.

## References

- SQLiteData `FetchAll` → Sharing `SharedReader`
- Instant `InstantEntityDraft` / `db.save(draft)`
- ADR 0001 application/sync boundary
- Scribe ADR 0006 (app-side transcript observation and schema)
