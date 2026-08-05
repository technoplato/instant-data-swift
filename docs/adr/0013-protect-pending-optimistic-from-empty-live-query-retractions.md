# ADR 0013: Protect Pending Optimistic Entities from Empty Live-Query Retractions

- Status: Accepted
- Date: 2026-08-04
- Scope: Live refresh application, outbox optimistic materialization, join-shaped observations

## Context

Upstream Instant keeps an authoritative **server query store** separate from
local mutations and re-applies pending mutations as an overlay when materializing
`dataForQuery`. Swift persists **one** materialized store and records the inverse
of each optimistic layer for rollback.

ADR 0008 made each live registration’s authoritative result a durable owner of
its triples. An empty or narrowed server replacement therefore generates
retractions for triples that left the result. That is correct for pure server
data.

Scribe (2026-08-04, iPad blank recording detail) showed a mixed case:

1. A recording root and transcription child were materialised (list word counts
   and live sections worked).
2. Mutations remained **pending** in the outbox (server had zero rows; delivery
   had not accepted them).
3. An empty live-query replacement for the joined observation retracted the
   child triples.
4. Playback still had audio (attachment entity survived) but the detail join
   returned `transcriptionCount=0` / empty timeline — a blank surface.

Optimistic rows were durable in the outbox’s view of the world, but not in the
store after the empty replacement. Application-level workarounds (preserve list
timeline in the UI) hide the symptom; the library owns optimistic observation.

## Decision

When applying live-query result replacements, **do not retract triples whose
entity IDs are still covered by a non-failed pending mutation** whose optimistic
overlay has not been explicitly removed.

Concretely, after `liveQueryReplacementRetractions(for:)`:

- collect entity IDs (and ref targets) from pending outbox mutations with
  `optimisticOverlayState != .removed` and `status != .failed`;
- drop `.retract` operations for those entity IDs before preparing the store
  transaction.

Lookup-based mutations cannot name a concrete entity without applying the
lookup; they rely on the existing rebase path rather than broad protection.

Server-only rows with **no** pending optimistic coverage still retract when the
authoritative result becomes empty (existing tests such as
`liveQueryReplacementRetractsPersistedRowsAfterRelaunch` remain the contract).

## Consequences

- Empty live refreshes can no longer blank a join-shaped detail while delivery
  is still pending.
- Rejected/failed mutations (`optimisticOverlayState == .removed`) remain
  retractable by authoritative empty results after isolation.
- Application recipes (Linked Infinite) and Scribe still must not paper over a
  missing child with fake data; they observe a store that keeps pending children.
- Focused tests:
  - `emptyLiveQueryReplacementPreservesPendingOptimisticChildRows`
  - `emptyLiveQueryReplacementPreservesOptimisticTranscriptionJoin`

## Verification

- Core suite: empty replacement with pending optimistic update keeps the child
  text/wordCount and outbox entry.
- Linked Infinite example: recording + transcription join survives empty live
  replacement with pending wordCount update.
- Pure server empty replacement still retracts unowned rows after relaunch.
