# V3 Syntax and End-to-End Port Plan

Status: active execution plan

This document turns the V3 SwiftUI sketches into a sequence of small,
test-gated implementation packets. It is subordinate to
`docs/instant-swift-data-goals.md`, which remains the product contract, and it
narrows `docs/instantdb-swift-data-plan.md` to the shortest path from the
current local-first implementation to real Swift/TypeScript synchronization.

## Current Baseline

As of 2026-07-18:

- The package already has a substantial local core: schema generation, typed
  queries and mutations, SQLite persistence, optimistic outbox behavior,
  property-wrapper adapters, auth seams, rooms, presence, topics, files,
  streams, sharing, CLI examples, validation fixtures, and benchmarks.
- The live WebSocket protocol can be exercised in opt-in validation commands,
  including one Swift-to-TypeScript and one TypeScript-to-Swift boundary proof.
- The normal runtime now owns an authenticated live session and a continuous
  server-event receiver. Commit `af88570` routes `refresh-ok` through the normal
  runtime, persists canonical join rows and the transaction checkpoint, and
  publishes the result to public query observers.
- The runtime does not yet install and remove active queries, send its durable
  outbox, correlate transaction acceptance or rejection, or reconnect and
  restore live state. Until active queries are installed, the new receiver can
  only apply refreshes the server sends without a runtime-managed query.
- The V3 API direction is documented in
  `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md` and `screens/v3/`.
- The prior screen syntax is preserved under `screens/v2/` in commit `d11b1cf`.
  The five V3 screen probes were committed in `5316f24` and `edce7da`.
- Packet 0 restored the deterministic validation baseline in commit `e0350ba`.
  The gate passed 811 Swift tests, 28 dedicated macro snapshot tests, generated
  schema and permissions verification, and the local Swift/TypeScript E2E
  orchestrator. Its evidence directory was
  `/tmp/instant-swift-data-packet0-20260718T1106`.
- The first normal-runtime receive slice passed the focused transport boundary
  tests and the full 812-test Swift package suite.
- The compact parity gate records 287 cases: 28 exact, 255 adapted, 2 not
  applicable, and 2 blocked. The only blocked ids are
  `instant.live-transport.swift-to-typescript` and
  `instant.live-transport.typescript-to-swift` until credentialed live evidence
  artifacts are supplied.
- No version tag should be created yet. The `v0.1.0-v3-syntax` compile and
  lifecycle gate remains pending.

## Authority Order

When sources disagree, use this order:

1. `docs/instant-swift-data-goals.md`: product requirements and definition of
   done.
2. This file: execution order, gates, and version targets.
3. `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md`: desired public API direction.
4. `screens/v3/*.md`: executable syntax probes for realistic app code.
5. `docs/instantdb-swift-data-plan.md`: full feature inventory and historical
   progress record.
6. `validation/README.md`: evidence format and harness operation.
7. Canonical upstream source pinned under `upstream/`: behavior and exact wire
   contract.

## Decisions Already Made

These decisions are sufficient to continue implementation:

- `@FetchAll` is the normal list surface.
- `@FetchOne` is for one value or scalar result.
- `@Fetch` and request objects are for one wrapper-owned composite value, not
  merely for dynamic input.
- Property wrappers own loading, observation, cancellation, stale-work
  replacement, and renderable status.
- SwiftUI button closures remain synchronous. They send typed messages; views
  do not create unstructured `Task` values for ordinary operations.
- Mutation and auth callbacks live at the call site and represent side effects
  of that specific action.
- Passive observation does not replay action-specific callbacks.
- Low-level query, subscription, transaction, auth, storage, room, and local-ID
  primitives remain public for non-SwiftUI code, tests, and advanced use.
- VoiceTrail-specific types and convenience wrappers stay outside the reusable
  Instant core.

## Decisions To Resolve Through Compiling Slices

Do not pause the whole port for these. Resolve each in the first compiling
slice that needs it, record the answer in the V3 design document, and add a
compile/runtime test:

- Dynamic wrapper attachment spelling: `.instantFetch($rows, query)` versus a
  projected-value lifecycle API.
- Whether `@InstantFetchBuilder` is handwritten, generated, or both.
- How much of a mutation change envelope is macro-generated.
- Whether room presence uses a wrapper, a modifier, or both.
- Whether auth-provider catalogs are generated from app configuration.

The first item is the only immediate recordings-list syntax decision. The
others can wait for their vertical slice.

## Commit and Version Discipline

Every commit must be one reviewable packet. A packet should normally touch one
behavioral seam plus its tests, fixture, and documentation. Avoid mixing
transport, public syntax, app work, and unrelated cleanup.

Before a packet commit:

1. Run the narrow tests for the changed seam.
2. Run `swift test` with no accepted failures.
3. Run `validation/run-macro-tests.sh` when macros or generated API change.
4. Run the local Swift/TypeScript contract harness.
5. Run the relevant real Instant boundary case when the packet touches live
   transport, schema, permissions, sharing, auth, files, rooms, or streams.
6. Inspect generated schema, permissions, JSONL evidence, and warnings as
   committed review artifacts or reproducible outputs.

Do not weaken assertions merely to make a packet green. First determine whether
the implementation changed intentionally, the evidence list is nondeterministic,
or the expectation is stale.

Create annotated Git tags only after the milestone gate passes from a clean
checkout. The tag message must name the validation artifact directory and the
canonical TypeScript dependency revisions. There are currently no repository
tags; the targets below establish the first version line.

## Version Targets

| Version | State | Next proof required |
| --- | --- | --- |
| `v0.1.0-v3-syntax` | Pending | Five V3 screens compile against public APIs |
| `v0.2.0-live-sync` | Pending | Normal runtime passes two-way live boundary |
| `v0.3.0-schema-auth-sharing` | Pending | Deployed schema/perms and two-user proof |
| `v0.4.0-apps-e2e` | Pending | Required apps run through live public APIs |
| `v1.0.0` | Pending | Full goals definition of done |

### `v0.1.0-v3-syntax`

Target: the V3 public API is executable, not only sketched.

Gate:

- Full Swift suite passes.
- V3 screen fixtures type-check under Swift 6 strict concurrency.
- Recordings list, auth login, recording, playback, and preferences compile
  against public package APIs with product-only placeholders isolated in a
  VoiceTrail fixture module.
- Wrapper lifecycle and action callback semantics have deterministic tests.
- The V3 docs contain no syntax that the fixtures cannot compile.

### `v0.2.0-live-sync`

Target: the normal runtime performs bidirectional live synchronization.

Gate:

- Swift writes through its normal client; the canonical TypeScript SDK observes
  the exact entity and linked data.
- TypeScript writes; the normal Swift subscription observes and decodes it.
- Reconnect resubscribes and resumes from the processed transaction checkpoint.
- The durable outbox drains in order after reconnect.
- `transact-ok`, refreshes, server rejection, retryable network errors, and
  permanent failures update cache/outbox/status correctly.
- No special validation-only transport path is required by the app runtime.

### `v0.3.0-schema-auth-sharing`

Target: generated contracts and protected multi-user data work on real Instant.

Gate:

- Swift-generated `instant.schema.ts` and `instant.perms.ts` type-check against
  pinned canonical Instant packages.
- An ephemeral validation app installs the generated schema and permissions.
- Auth session creation/restoration/invalidation works through real transport.
- Owner, reader, and writer sharing flows work across two users.
- Unauthorized reads and writes are rejected without corrupting optimistic
  local state or leaving a stuck outbox row.
- `$users`, `$files`, forward/reverse links, required/optional values, and share
  metadata match canonical TypeScript shapes.

### `v0.4.0-apps-e2e`

Target: required example apps run end to end through the public V3 API.

Gate:

- VoiceTrail V3 screen flows run against live synced data.
- Required Instant examples and recipes have working Swift app surfaces, not
  only CLI or model proofs.
- SQLiteData CaseStudies, Reminders, SyncUps, and the Instant equivalent of
  CloudKitDemo meet the goals document acceptance cases.
- Auth, offline/reconnect, sharing, permissions, presence, topics, storage, and
  streams are exercised through app-facing adapters.

### `v1.0.0`

Target: the complete definition of done in
`docs/instant-swift-data-goals.md` passes from a clean checkout with reproducible
Swift/TypeScript evidence and benchmark artifacts.

## Execution Packets

### Packet 0: Restore a trustworthy green baseline — complete

Purpose: remove uncertainty before changing the public API or transport.

- Diagnose the five failing tests listed above.
- Add the required `SAFETY:` ownership comment for the unchecked WebSocket
  wrapper only after confirming the actual serialization guarantee.
- Determine why the platform-adapter runner emits four new cancellation rows
  while its public test still expects 25 rows.
- Fix the local-integration regression where the CLI reports one room member
  while the test requires two.
- Reconcile cancellation evidence counts and benchmark actor-hop expectations
  with the implementation that produced them.
- Fix real regressions; update expectations only for verified intentional
  behavior.
- Run the full local suite and local E2E harness.
- Keep this separate from V3 syntax changes.

Commit target: `Restore deterministic validation baseline`.

### Packet 1: Freeze and compile the direct fetch lifecycle

Purpose: turn the recordings-list sketch into the first executable V3 slice.

- Add a small VoiceTrail fixture target or compile-test fixture.
- Implement the chosen dynamic attachment spelling for `@FetchAll`.
- Make the wrapper own subscription task creation, replacement, cancellation,
  cached initial emission, and error state.
- Prove search/scope changes cancel stale observation and install the new query.
- Keep `@Fetch` reserved for the rows-plus-counts composite variant.
- Update the V3 decision log and recordings-list sketch to exactly match the
  compiling fixture.

Commit target: `Compile V3 recordings list fetch lifecycle`.

### Packet 2: Add typed message sends and change envelopes

Purpose: make V3 mutations compile and preserve optimistic/server semantics.

- Add `db.send(message, onOptimisticCommit:onServerAccepted:onFailure:)` over
  the existing transaction/outbox core.
- Generate or explicitly define the smallest typed change envelope needed by
  the recordings-list rename flow.
- Guarantee callbacks run once for their corresponding action phase.
- Keep passive remote refreshes from invoking local action callbacks.
- Prove optimistic state, server acceptance, server rejection, relaunch, and
  retry behavior.

Commit target: `Add V3 typed message mutation lifecycle`.

### Packet 3: Promote live validation transport into the runtime

Purpose: reach real bidirectional sync as quickly as possible.

- Give the runtime one owned live-session state machine.
- Send `init`, authenticate, install queries, receive refreshes, apply canonical
  join rows, and advance the transaction checkpoint.
- Send outbox transactions and correlate `transact-ok`/refresh/rejection with
  durable pending mutations.
- Reconnect with bounded backoff, resubscribe active queries, rejoin rooms, and
  resume outbox drain.
- Route normal public clients and wrappers through this session; eliminate the
  validation-only architectural fork.

Commit targets, split if needed:

1. `Own authenticated live session in runtime` — implemented in `1c627e8`.
2. `Apply live refreshes through public subscriptions` — receiver and refresh
   application implemented in `af88570`; active query add/remove lifecycle is
   the remaining half.
3. `Drain durable outbox through live session`
4. `Reconnect and restore live runtime state`

Each commit must have its own boundary case and pass the existing local suite.

### Packet 4: Pin and enforce the canonical TypeScript contract

Purpose: make “exact shape” reproducible.

- Replace `latest` TypeScript dependencies with exact versions or workspace
  references tied to the pinned `upstream/instant` revision.
- Commit the lockfile used by validation.
- Add `typecheck` and `test` scripts; do not rely on `tsx` execution alone.
- Record the Swift package revision, TypeScript package versions, upstream
  commit, app id, and schema hash in every boundary evidence run.
- Compare normalized values for strings, booleans, integers/doubles, dates,
  JSON, enums, optional absent/null values, IDs, lookup refs, one/many links,
  `$users`, `$files`, and transaction metadata.
- Treat unknown fields, lossy number/date conversion, missing required fields,
  and enum decode failures as explicit warnings or errors with stable codes.

Commit target: `Pin canonical TypeScript shape contract`.

### Packet 5: Make schema and permissions deployable acceptance inputs

Purpose: prove generation against the server, not only fixture text.

- Keep Swift declarations as the source for schema and permissions fixtures.
- Type-check generated TypeScript against the pinned SDK.
- Create/reset an ephemeral validation app and install the generated contract.
- Read the server schema back and compare normalized entities, attributes,
  links, rooms, and permissions.
- Fail on generated drift or manual fixture edits.

Commit targets:

1. `Type-check generated Instant schema and permissions`
2. `Install and verify generated contract on ephemeral app`

### Packet 6: Auth and two-user sharing

Purpose: make permissions meaningful end to end.

- Implement the V3 `@InstantAuth` state machine over real transport.
- Prove session restoration and sign-out invalidation.
- Create owner/reader/writer identities and a share link.
- Prove allowed and rejected reads/writes from both SDKs.
- Reconcile rejected optimistic writes and expose actionable recovery text.

Commit targets:

1. `Run V3 auth through live Instant transport`
2. `Prove two-user sharing and permission rejection`

### Packet 7: Complete remaining V3 wrappers

Implement in independently gated commits:

- `@InstantSyncStatus`
- queryable `$files` and upload/delete progress
- `@Room`, `@Presence`, and `@Topic`
- `@LocalID`
- composite `@Fetch` and `@InstantFetchBuilder`
- recording/playback-specific message flows

Every wrapper must have local lifecycle tests and a canonical TypeScript
boundary case when it represents remote data.

### Packet 8: Run apps through the real public surface

Purpose: replace CLI/model-only confidence with working app acceptance.

- Start with the five VoiceTrail V3 fixture screens as a coherent app.
- Port required examples in the order that expands surface coverage fastest:
  todos, auth, chat/mobile-chat, presence/topic recipes, Reminders sharing,
  SyncUps, storage/app-builder, streams, and CloudKitDemo-equivalent sharing.
- Keep app business logic in testable models and public wrappers.
- Remove fixture-only adapters as their public equivalents become available.

## End-to-End Shape Matrix

The release harness must prove each applicable row in both directions:

| Surface | Swift to TS | TS to Swift | Failure proof |
| --- | --- | --- | --- |
| Scalars/optionals | exact value/absence | exact decode | required/type mismatch |
| Dates/numbers | canonical wire value | no lossy decode | overflow/invalid date |
| JSON and enums | exact nested shape | typed decode | unknown enum/case shape |
| One/many links | nested canonical query | typed includes/reverse links | invalid link/lookup |
| Optimistic writes | observed after accept | remote refresh observed | rollback/reconcile |
| Offline/reconnect | queued then visible | server changes restored | bounded retry |
| Auth | session accepted | session refresh observed | invalid/expired token |
| Sharing/permissions | owner/writer succeeds | role changes observed | reader/outsider denied |
| Presence/topics | Swift event observed | TS event observed | disconnect cleanup |
| Files | metadata/content visible | metadata/content decoded | permission/upload failure |
| Streams | ordered chunks visible | ordered chunks decoded | cancellation/backpressure |

## Required Gates

### Packet gate

- Focused tests for the changed seam.
- Full `swift test` green.
- Swift 6 strict-concurrency build green.
- Generated artifacts unchanged unless the packet intentionally changes them.

### Contract gate

- TypeScript install uses the committed lockfile.
- TypeScript type-check and fixture tests pass.
- Swift local validation and TypeScript contract consumption pass.
- No unexpected Swift or TypeScript warnings.

### Live milestone gate

- A fresh or reset Instant validation app uses the generated schema and perms.
- Swift-to-TypeScript and TypeScript-to-Swift live cases pass.
- The relevant permission rejection case passes.
- Evidence JSONL contains revisions, schema hash, stable case ids, exact
  expected/actual data, warnings, latency, and success status.
- The milestone is rerun from a clean checkout before its annotated tag.

## Immediate Next Step

Finish Packet 3's public subscription slice: encode `InstantQueryPlan` into the
canonical Instant query object, install and reference-count active queries on
the owned live session, send `remove-query` on cancellation, and prove a
TypeScript-originated write reaches a normal Swift observer. Then implement
Packet 1 as the first compiling V3 API slice over that real subscription path.
