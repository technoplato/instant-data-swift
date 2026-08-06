# ADR 0015 — Findings (audit inventory)

Last updated: 2026-08-06. Issue #155.

## Owner hard rules (from interview)

- **Diffing previous vs current full documents is an anti-pattern.** Instant
  writes are ordinary row upserts of what changed (open segment, summary
  fields). Do not build planners that re-diff the world.
- List may show a **bounded** latest-segment preview (two lines when
  active/playback; hidden when idle), not full transcripts.
- List rows carry **product activity ADT**: active(device id…) / playback; idle
  has no badge. Prefer Instant client/local id for “which device.”
- **No stored full `transcriptionText`.** Generate full transcript by format on
  demand (SRT, Markdown, JSON, …).

## What is broken architecturally

Scribe currently reinvents Instant runtime concerns in app code:

| App symbol | Approx | Problem |
| --- | ---: | --- |
| `ScribeInstantStore` | ~3.2k LOC | Shadow Instant runtime: bootstrap, entity decode, multi-subscribe merge, media, wait-for-delivery |
| `ScribeSharedRealtimeTranscriptionPlanner` (`liveChanges` / `finalChanges` / `shouldWriteEntities`) | large | Full previous+current `Recording` diff engine |
| `ScribeSharedRealtimeSyncPlanner` | ~435 LOC | Rehydrate domain `Recording` from multiple Instant streams |
| `SharedRecordingSnapshotMutationCoordinator` | actor | Serial queue + full `lastSaved` `Recording` cache |
| `SegmentSyncStatusTracker` | process singleton | Fake sync status (only “local”) |
| 300ms full `saveSnapshot` of timeline | list feature | Rebuilds full document for Instant planning |

**Owner judgment (2026-08-06):** these are not things to polish. Delete / replace
with library-shaped `@Fetch*` + row upserts. App-level Instant stores are an
anti-pattern.

## What recent Scribe commits did

`c03220d` family (open-segment live writes, drop live `transcriptText`, list
timeline thinning, DEBUG pills):

- Direction partially aligns with ADR 0014 / Scribe ADR 0006
- Almost no library API shipped for this path
- Package pin remains remote `instant-data-swift` **1.5.6**
- Still keeps previous/current full-document planning in the app

## What to delete (intent — not scheduled until Q&A accepts)

- `ScribeInstantStore` as a product façade (bootstrap may remain composition-root helpers only)
- `liveChanges` / `finalChanges` / previous-current planners as the live write path
- Full last-saved `Recording` mutation coordinator cache
- Process-local `SegmentSyncStatusTracker`
- Dual multi-subscribe merge for list/detail observation
- Per-word Instant entities for live speech (words become JSON on the segment)

## Library gaps that forced the app hacks

1. No enforced sparse open-segment write recipe + examples
2. No per-entity sync status on fetch (ADR 0014 proposed)
3. No same-entity outbox supersession for high-frequency updates
4. Composite observation still easy to “do wrong” with manual multi-subscribe
5. JSON attributes lack app-declared Codable type binding → decode/encode drift

## Typed JSON blobs (owner requirement)

Instant wire type for free-form structure is `json`. Instant does **not**
enforce app struct shape. Requirement:

- At **schema / model** level, app declares an `Encodable`/`Decodable` (or
  Codable) struct type for each JSON attribute (e.g. segment words array)
- Write and read paths are **strict**: encode/decode failures are loud
  (reportIssue / quarantine), not silent `try?`
- When generating TypeScript `instant.schema.ts`, carry generics / typed JSON
  helpers where Instant’s TS schema API allows so server-side types stay
  aligned

Exact API spelling is still open (see `qanda.md`).

## Write / await semantics (library today)

- `await db.transact { … }` → local optimistic SQLite + outbox; returns
  `InstantStoreMutationResult` with **`transactionID`** already.
- Does **not** wait for server (ADR 0010).
- Server wait is separate: `waitForAllPendingMutations` or
  `observeMutationLifecycle(id:)`.
- Polymorphic risk: some `InstantMessage.send` paths await server lifecycle;
  speech must not use those for interim upserts.

## SQLiteData comparison (target ergonomics)

App shape in SQLiteData:

- `@FetchAll` / `@FetchOne` / `@Fetch` for reads
- `database.write { insert/update/delete }` for writes
- No previous full document retained to invent deltas
- Sync engine is library-owned (CloudKit), not a feature store

Instant already has `@Fetch*`, `transact`, `Draft`, outbox. Scribe is not using
that shape for the live transcript graph.

## First library milestone (decided Q28/Q29/Q30)

1. **Nested limit-per-parent** on reverse includes (e.g. 2 latest segments).
2. **Request-time map** to flat list row (`RecordingListRow`); empty children `[]`.
3. **Projection ergonomics** toward SQLiteData `@Selection` / `Columns` (app
   row types, generated builders) — Instant should grow this, not forever zip
   by hand.
4. **Aggregations / grouping / sectioning**: counts, group-by shapes, sectioned
   results (ordered dictionary etc.) as first-class fetch maps — Point-Free
   prior art in pointfree-research + sqlite-data examples.
5. Architecture tests: unbounded list includes fail.
6. Then **delete ScribeInstantStore** entirely (Q17) — bootstrap only in
   composition root; no long-lived hollow store type. Commits on `main` only.
7. Parallel track: Instant client id for activity ADT.
8. Follow-on main commits: aggregations/grouping/Selection-shaped projections.

Why nested limit blocked today: `InstantEntityQuery.including` precondition —
include plan does not carry nested page bounds (implementation gap).

Point-Free research root: `/Users/laptop/Sync/tca/pointfree-research`
