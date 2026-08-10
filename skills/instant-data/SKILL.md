---
name: instant-data
description: >
  Route and govern work in Instant Swift Data and dual library+app development
  (especially Scribe). Use for every task in this repository and whenever a
  consumer app is co-evolving Instant behavior: API design, Swift
  implementation, ergonomics, memory/performance, examples, docs, reviews,
  debugging, validation. Then load instant-data-modeling,
  instant-data-dependencies, or instant-data-testing as needed. ACTIVE
  ITERATION with the user — update this skill when dual-dev guidance changes.
---

# Instant Data

**Status: in active iteration with the user** while Instant Swift Data and
Scribe are co-developed. Prefer editing this skill over leaving dual-dev rules
only in chat. Pair large decisions with `$adr-decision-qanda` and the open
ADR 0015 interview folder.

Use this family as the Point-Free-style Instant Data (`pfw-instant-data`)
guidance for the repository.

Start with the Point-Free `pfw` skill, then use the applicable Point-Free and
`instant-data-*` companions.

## Fundamentals first (before features)

The library works, but **memory, performance, and ergonomics are not done**.
Until ADR 0015 / issue #155 say otherwise:

1. Prefer library fixes over app workarounds.
2. Do not grow consumer-app Instant stores, multi-subscribe merge actors,
   previous/current full-document planners, or process-local fake sync status.
3. Target shape is SQLiteData parity: `@Fetch*` observes; writes touch the
   rows that changed; library owns outbox and delivery.

Interview + decisions:

- `docs/adr/0015-sqlite-data-parity-ergonomics/` (`qanda.md`, `findings.md`,
  `overviews/`)
- `docs/adr/0014-entity-lifecycle-status-and-draft-visibility-in-fetch.md`
- `docs/adr/0001-application-sync-boundary.md`
- Instant issue https://issues.knophy.com/issues/155

Primary consumer stress case: `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant`
(Scribe). Symlink: that repo’s `Packages/instant-data-swift`.

## Read the contract

Read these sources before changing public behavior:

1. `docs/adr/0001-application-sync-boundary.md`
2. `docs/adr/0015-sqlite-data-parity-ergonomics/` (active ergonomics program)
3. `docs/instant-swift-data-goals.md`
4. `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md` for V3 app-facing syntax
5. `docs/instantdb-swift-data-plan.md` for inventory and acceptance gates

Treat the ADR as canonical when older sketches drift. Treat current symbols in
`Sources/` and compiling fixtures in `Tests/` as authoritative for syntax that
can be used today. The V3 design document and `screens/v3/` are design targets,
not a complete inventory of implemented symbols. Search the implementation
before recommending a projection or fetch builder: names such as
`@InstantProjectionBuilder`, `@InstantFetchBuilder`, `InstantFetchPlan`,
`Project`, `Query`, and `Count` may still be sketches.

## Upstream citations (one tree)

When implementing Instant behavior, cite from **this repo’s** vendored trees:

- Instant TypeScript: `upstream/instant/client/packages/core/src` (esp. `Reactor.js`)
- SQLiteData: `upstream/sqlite-data`

Do not require a second SQLiteData checkout for guidance. If another path
exists on the machine, the vendored tree still wins for library work.

## Preserve the boundary

Keep these responsibilities in applications:

- schema, projections, permissions, and typed models;
- query shape, observation lifetime, and dynamic inputs;
- mutations and user intent;
- auth, sharing, rooms, presence, topics, and files;
- explicit user-visible operations and diagnostics;
- domain-only mapping (e.g. speech “open segment id”), **not** sync engines.

Keep these responsibilities in the library:

- cache and local materialization;
- optimistic observation;
- persistent outbox, reconnection, and delivery;
- acknowledgement, rollback, retry, and rejection isolation;
- observation replacement and cancellation;
- entity sync status on fetch (ADR 0014/0015);
- exact immediate-tail assignment supersession for high-frequency updates;

**Anti-pattern:** app-level Instant “store” types that multi-subscribe, merge
streams, rehydrate full domain graphs, wait on delivery, or cache last-saved
full documents for diff planning. Bootstrap belongs in the composition root;
features use `@Fetch*` + `transact` / `save` / `send`.

Reject a public `queryLocal`. Inject a local-only client at the dependency
boundary and use ordinary query, observation, and mutation APIs.

A statically configured `@FetchAll`, `@FetchOne`, or `@Fetch` starts observing
automatically. Use a replacement task/modifier only when identity, search, or
scope actually changes during the feature's lifetime, and declare that dynamic
wrapper with an explicit `nil` key so it does not start a broad observation.

### Write contract (every app — library boundary)

- **`transact` / `save` never await the server.** Success = local materialize +
  durable outbox. Offline must work.
- `async` = local runtime/SQLite finished (SQLiteData-shaped), not network.
- Return/`InstantStoreMutationResult.transactionID` is the delivery handle
  (already exists — document and use it; do not invent a second id type).
- Observe delivery via public `observeTransaction(id:)` (wrap lifecycle) or
  entity **sync status on fetch**. Explicit `wait…` APIs only for CLI/tools.
- Ban polymorphic writes where `await` sometimes means network. Name server
  waits in the API.

### Live speech write shape (Scribe product, library must make cheap)

- **Recipe:** `docs/adr/0015-sqlite-data-parity-ergonomics/open-segment-write-recipe.md`
  + `OpenSegmentWriteRecipe` (Core) / `OpenSegmentWriteRecipeEntities` (typed).
- Always outbox for open-segment updates (never skip outbox for interim text).
- Upsert **only the current recording segment**; on finalize, mark final and
  move to a new id. App tracks `recordingSegmentID` (not a full-document diff).
- Words are **not** Instant entities: strict Codable JSON array on the segment
  (`start`, `end`, `text`). Fail loud on encode/decode drift
  (`OpenSegmentWriteRecipe.encodeWordsJSON` / `decodeWordsJSON`).
- **Same-entity outbox supersession** (high-churn speech): durable enqueue may
  replace only the one exact never-claimed, never-offered tail when predecessor
  and newcomer are complete assignments of the same schema-known
  cardinality-one scalar attribute set. Never scan/group the queue, cross a
  barrier, merge partial patches, or choose by a payload revision. See
  `docs/adr/0015-sqlite-data-parity-ergonomics/follow-on-outbox-same-entity-supersession.md`.
  Always outbox today. Full mutation bodies are bounded for an eligible chain;
  old transaction-ID aliases are append-only, so total durable metadata is not.
- **No stored full joined transcript text.** Generate/export by format on demand
  from segments + words JSON.
- Prefer schema-level typed JSON + TypeScript schema generation generics where
  Instant allows (ADR 0015 qanda Q03/Q04).
- **No full-document previous/current diffing** in app or library product APIs.
  That pattern is an anti-pattern for this program.

### Recordings list (Scribe product, library must make cheap)

- List is summary + **product activity ADT** (`active(clientId)` /
  `playback(clientId)` / absent idle) + **bounded latest segments** (query
  limit two most recent) then **map/truncate** to two UI lines — not full
  timelines, not denormalized full preview text as the primary design.
- **This vs other device** = compare activity `clientId` to Instant **local
  client id** via `try await client.clientID()` (TS `getLocalId` /
  `Reactor.getLocalId`; reserved name `InstantClientID.name`). Offline-safe.
  Helper: `InstantClientID.isThisClient(activityClientID:localClientID:)`.
  Not websocket `session-id` (reconnect-scoped presence peer).
- Prefer library-owned include + limit + map helpers (ADR 0015 overview 03);
  never multi-subscribe merge of the whole transcript graph for list paint.
- **Correctness over convenience** — fix query ergonomics rather than denorm
  workarounds.
- **First #155 milestone:** nested limit-per-parent include + request-time
  **map** to list rows; grow toward `@Selection`/Columns-style projections;
  aggregations / grouping / sectioned results (SQLiteData parity). Prior art:
  `upstream/sqlite-data`, `/Users/laptop/Sync/tca/pointfree-research` (ep328,
  ep374). Then delete app Instant stores/planners.

## Route the work

- Use `instant-data-modeling` for entities, schema, queries, projections,
  `@FetchAll`, `@FetchOne`, `@Fetch`, drafts, and mutations.
- Use `instant-data-dependencies` for bootstrap, `@Dependency`, live/local-only
  selection, previews, tests, or effect clients.
- Use `instant-data-testing` for tests, offline behavior, outbox/reconnect,
  rejection, live Swift/TypeScript validation, architecture checks, or media
  isolation.

Use more than one companion when the task crosses those concerns.

For recording work, additionally inspect the current application-owned models
and screens in `Sources/VoiceTrailV3App/` and the focused fixtures in:

- `Tests/InstantSwiftDataTests/V3RecordingFixtureTests.swift`
- `Tests/InstantSwiftDataTests/V3RecordingActionFixtureTests.swift`
- `Tests/InstantSwiftDataTests/V3RecordingsListFixtureTests.swift`
- `Tests/VoiceTrailV3AppTests/`

An Instant entity in these examples is an application-modeled
`InstantEntityModel` (for example `VoiceTrailRecording` or
`VoiceTrailTranscription`), not a generic built-in library `Entity`. A word
entity and other transcript records are likewise application-modeled schema
decisions, not built-in Instant Swift Data entities.

## Work test-first

Inspect the real implementation, persisted artifacts, and current tests before
guessing. Add or tighten the smallest focused test first, make the smallest
implementation change, and run the narrow test before broader validation.

Do not equate compilation or unit tests with live Instant acceptance. Report
local deterministic evidence and credentialed cross-SDK evidence separately.

## Protect feature code

Do not add outbox, reconnect, transport, cache-materializer, or manual flush
coordination to normal app features. Allow explicit delivery details only in
CLI, diagnostics, tests, bootstrap/live adapters, or a user-visible operation.

Keep entity delivery independent from media transfer. Prefer a bounded LIFO
media cache and isolate rejection per item or stream.
