---
name: instant-data
description: Route and govern work in the Instant Swift Data repository. Use for every task in this repository, including API design, Swift implementation, examples, documentation, reviews, debugging, validation, and performance work; then load the focused instant-data-modeling, instant-data-dependencies, or instant-data-testing companion when applicable.
---

# Instant Data

Use this family as the Point-Free-style Instant Data (`pfw-instant-data`)
guidance for the repository.

Start with the Point-Free `pfw` skill, then use the applicable Point-Free and
`instant-data-*` companions.

## Read the contract

Read these sources before changing public behavior:

1. `docs/adr/0001-application-sync-boundary.md`
2. `docs/instant-swift-data-goals.md`
3. `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md` for V3 app-facing syntax
4. `docs/instantdb-swift-data-plan.md` for inventory and acceptance gates

Treat the ADR as canonical when older sketches drift. Treat current symbols in
`Sources/` and compiling fixtures in `Tests/` as authoritative for syntax that
can be used today. The V3 design document and `screens/v3/` are design targets,
not a complete inventory of implemented symbols. Search the implementation
before recommending a projection or fetch builder: names such as
`@InstantProjectionBuilder`, `@InstantFetchBuilder`, `InstantFetchPlan`,
`Project`, `Query`, and `Count` may still be sketches.

## Preserve the boundary

Keep these responsibilities in applications:

- schema, projections, permissions, and typed models;
- query shape, observation lifetime, and dynamic inputs;
- mutations and user intent;
- auth, sharing, rooms, presence, topics, and files;
- explicit user-visible operations and diagnostics.

Keep these responsibilities in the library:

- cache and local materialization;
- optimistic observation;
- persistent outbox, reconnection, and delivery;
- acknowledgement, rollback, retry, and rejection isolation;
- observation replacement and cancellation.

Reject a public `queryLocal`. Inject a local-only client at the dependency
boundary and use ordinary query, observation, and mutation APIs.

A statically configured `@FetchAll`, `@FetchOne`, or `@Fetch` starts observing
automatically. Use a replacement task/modifier only when identity, search, or
scope actually changes during the feature's lifetime, and declare that dynamic
wrapper with an explicit `nil` key so it does not start a broad observation.

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
