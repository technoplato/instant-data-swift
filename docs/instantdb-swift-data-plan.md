# Instant Swift Data Implementation Plan

This plan is reconciled with
`docs/instant-swift-data-goals.md`, which is the portable goal contract for the
project. When the two documents differ, the goals document wins and this plan
should be updated rather than treated as a competing source of truth.

## Goal

Build a single Swift package that feels like SQLiteData/SwiftData at the app
surface, but uses InstantDB as the backing system.

The important concrete pieces are:

- A local store: an in-memory and persisted copy of the facts the client knows.
- A query observer: code that turns a query into a live Swift value and updates it
  when the local store changes.
- A mutation outbox: a durable ordered list of writes that have been applied
  optimistically but not yet confirmed by InstantDB.
- A transport: WebSocket/SSE and HTTP calls that exchange queries, transaction
  steps, auth, files, rooms, presence, topics, and stream messages with Instant.
- Schema tooling: Swift declarations that can emit the TypeScript schema,
  permissions, generated Swift entity/query/mutation helpers, and validation
  fixtures.

The target package should not require maintaining a separate core Swift SDK and
a separate sharing wrapper. It can still have internal targets, but they should
live in one repository and version together.

Resolved decisions from the later goal pass:

- The package, module, and CLI naming centers on `InstantSwiftData` and
  `instant-swift-data`.
- Swift `Date` maps to Instant's `date` semantic value by default. Epoch
  milliseconds remain an explicit compatibility strategy.
- SQLite is the first durable Swift persistence backend unless benchmarks prove
  another backend is better.
- Macro support and benchmark support are first-class package targets.
- The CLI must be agent-interactable, non-captive, and backed by the same
  durable auth/cache/outbox state as app clients.
- Swift concurrency compliance is a first-class implementation constraint. The
  detailed contract lives in `docs/swift-concurrency-guidance.md`; the core
  package must stay clean under Swift 6 strict concurrency.

## Upstream Inventory

Fetched on 2026-06-12.

| Source | Local path | Revision inspected | What to mine |
| --- | --- | --- | --- |
| Instant TypeScript | `upstream/instant` | `e7101761` | Canonical client behavior, schema surface, query grammar, transaction grammar, streams, storage, presence, auth, offline cache, sync table |
| SQLiteData | `upstream/sqlite-data` | `0c79d7a` | SwiftData-like API shape, `@FetchAll`/`@FetchOne`/`@Fetch`, dependency bootstrap, migration docs, observation ergonomics, example ports |
| Swift sharing Instant | `upstream/sharing-instant` | `d78601a` | Prior Swift Instant behavior: reactor, triple store, offline tests, pending flush order, schema codegen, presence/topics/storage |
| Instant iOS SDK draft | `upstream/instant-ios-sdk` | `304677c` | Core Swift client, WebSocket, local storage, auth, storage, query manager, local-first manager, macros |

`upstream/README.md` is the submodule map. The transferred plan referenced a
local-only `swift-sharing-instant-ship` checkout and a Sigil bridge path; neither
is part of this moved repository, so they are historical research leads rather
than current local inputs.

## Feature Parity Target

Instant's TypeScript client is the contract. The Swift package should support
each surface below with Swift-native types and end-to-end validation against a
real Instant app.

### Connection And Runtime

- Configure `appId`, `apiURI`, `websocketURI`, transport type, logging, date
  decoding, validation toggles, cache limits, and custom persistence store.
- Report connection status: connecting, opened, authenticated, closed, errored.
- Authenticate transport sessions and resubscribe on reconnect.
- Support WebSocket first. Keep SSE as a target if Instant's public protocol
  remains available and useful for server-like Swift environments.

### Schema

- Entities with scalar attributes: string, number, boolean, date, json.
- Swift-only type safety for enums, discriminated unions, typed JSON fields,
  typed IDs, local IDs, and decode validation.
- Required/optional fields.
- Indexed fields and unique fields.
- Primary keys and lookup by unique attribute.
- Links with forward/reverse labels, one/many cardinality, required forward
  links, and cascade delete behavior.
- Rooms with typed presence and typed topics.
- Special namespaces: `$users` and `$files`.
- Swift schema declarations must derive TypeScript `instant.schema.ts`.
- Swift permissions declarations should derive `instant.perms.ts`; do not leave
  permissions as a manual TypeScript-only sidecar.
- Schema tooling must support round trips:
  Swift schema -> TypeScript schema -> Swift IR, and TypeScript schema -> Swift
  generated helpers -> TypeScript schema.

### Querying

- Live subscriptions equivalent to `subscribeQuery`/React `useQuery`.
- One-shot strict queries equivalent to `queryOnce`, exposed through
  `InstantSwiftDataClient.queryOnce(_:)` for raw snapshots/emissions and typed
  `queryOnceDecoded(_:)` for decoded values plus pagination `pageInfo`.
- Top-level namespace queries and nested relation queries.
- Explicit linked-entity inclusion, including typed forward includes like
  `.include(Post.author, User.query.select(User.name))`. Raw core materialization
  also supports multi-linked entities and reverse links; typed reverse includes
  need generated reverse relation tokens.
- Field selection, including typed `.select(Todo.text, Todo.isCompleted)`.
  Partial selections should be read as raw snapshots unless the selected fields
  satisfy the entity decoder.
- `where` operators: equality, `$ne`, `$isNull`, `$gt`, `$lt`, `$gte`, `$lte`,
  `$in`, `$like`, `$ilike`, `and`, `or`, and nested field paths like
  `relation.field`.
- Local triple materialization currently supports one-hop raw nested field
  filters (`relation.field`) over declared forward and reverse links, including
  `relation.id`, null/not-equals matching for missing links, and validation that
  rejects deeper paths such as `relation.child.field` by returning no local
  results until full InstaQL path parity is implemented.
- Ordering on indexed fields and `serverCreatedAt`.
- Local triple materialization supports explicit `serverCreatedAt` ordering as
  an order-only reserved field backed by the entity id triple's `txTime`, with a
  namespace-triple fallback for low-level local rows without an id triple. Local
  no-order queries remain id-sorted until the broader default-order parity slice.
- The typed query surface exposes this reserved order as
  `.order(.serverCreatedAt, .descending)`.
- `serverCreatedAt` is not materialized into entity snapshots or decoded models,
  and schema attributes using that name are rejected at bootstrap. User data
  should use domain fields such as `createdAt`.
- Pagination on top-level namespaces: `limit`, `offset`, `first`, `after`,
  `last`, `before`, inclusive cursors, and page info.
- Infinite query subscriptions.
- Query validation that rejects unsupported operators and illegal nested
  pagination before the network call.
- Hashing/caching of queries so cached results can be restored consistently.

### Mutations

- Transaction builder parity with TypeScript `db.tx`.
- Strict `create`, upserting `update`, strict update with no upsert, `merge`,
  `delete`, `link`, `unlink`, and `ruleParams`. Repeatable local seed commands
  should use explicit upsert helpers rather than weakening app-facing `create`.
- Batch transactions with stable operation order.
- Lookup refs by unique attribute for writes and links. Preserve lookup-shaped
  pending mutations for transport lowering; resolve local optimistic effects
  sequentially against the AEV index, no-op unresolved non-strict lookups, and
  reject strict lookup updates before cache/outbox writes when missing.
- Preserve `ruleParams` operations for transport lowering. They should validate
  lookup refs but otherwise no-op local optimistic materialization because their
  effect is server-side permission evaluation.
- Delete locally removes entity triples plus forward/reverse refs and honors
  cascade metadata. Add namespace-specific delete steps later; until then the
  Swift `.deleteEntity(String)` fallback applies cascades for every matching
  local incoming ref edge for that raw id.
- Optimistic application before server confirmation.
- Rollback or visible failure state when the server rejects a mutation.
- Durable pending mutation persistence across process restart.
- In-flight mutation de-duplication.
- Stable flush ordering after reconnect, especially link-before-create hazards.
- High-bandwidth write path for repeated field updates and linked entities.

### Offline And Local First

- Persist schema attributes, triples, cached query results, pending mutations,
  processed tx id, auth session, and sync table state.
- Subscriptions can emit cached results while offline.
- `queryOnce` fails offline, but carries last-known cached result when available.
- Offline writes update observers immediately, stay in the outbox, and flush in
  deterministic order after reconnect.
- Server confirmations clean up pending mutations without erasing newer local
  state.
- Process restart while offline restores pending local state before network
  reconnect.

### Realtime Sync

- Initial query load.
- Incremental triple updates.
- Query invalidation/recomputation across all active subscribers when pending
  mutations change.
- Multiple simultaneous queries with different `with` clauses.
- Reverse-link observer propagation.
- Deletions that remove forward and reverse links without ghost entities.
- Sync-table path for high-volume ordered result sets.

### Auth

- Magic code send/verify/sign-in.
- Token sign-in and session restore.
- Guest sign-in.
- OAuth / id-token sign-in surfaces where supported by Instant.
- Sign out with token invalidation option.
- Auth state subscription.
- Auth session persistence and refresh token handling.

### Presence, Rooms, Topics

- Join and leave rooms.
- Publish presence and subscribe to presence slices.
- Get current presence.
- Publish topics and subscribe to topic events.
- Typed room schema generation from Swift schema declarations.
- Rejoin rooms after reconnect.

### Storage And Files

- Upload files, delete files, and query `$files`.
- Storage operation state: idle/loading/success/error plus progress where
  available.
- File permissions generation for `$files`.
- Storage references that can be embedded in app entities.

### Streams

- Support Instant's stream abstractions exposed through the TypeScript core:
  readable streams, writable streams, stream ids, resumable stream package, and
  React Native stream shims.
- Validate Swift writes observed by a TypeScript stream reader and TypeScript
  stream writes observed by Swift.
- Define backpressure and cancellation behavior explicitly before implementation.

### Admin And Tooling

- Ephemeral app creation for tests.
- Schema and permission push/pull.
- Admin query and transact helpers for ground-truth verification.
- CLI commands for schema generation, migration planning, push, get,
  validation, example business commands, cache inspection, outbox inspection,
  auth, and benchmarks.
- Dev logging hooks should be optional and removable from production targets.

### Sharing

- Instant-native sharing that reproduces SQLiteData/CloudKit-style shared record
  user experience without depending on CloudKit.
- Share/root entities, memberships, roles/capabilities, share links or tokens,
  accept/revoke flows, visible sharing metadata, and generated permissions using
  `auth.ref` and `data.ref` where applicable.
- The Reminders port must prove list sharing with two users.

## Proposed Package Architecture

One repository, multiple targets:

- `InstantSwiftData`: public SwiftData-like API. Property wrappers, dependency
  bootstrap, query/mutation surface, errors, and docs.
- `InstantSwiftDataCore`: internal client engine. Reactor, transport, local store,
  outbox, query processor, persistence, auth, storage, presence, streams.
- `InstantSwiftDataSchema`: Swift schema declaration DSL, IR, TypeScript printer,
  Swift code generator, permissions printer.
- `InstantSwiftDataMacros`: macro implementations such as `@InstantEntity` plus
  diagnostics for redundant namespace overrides.
- `instant-swift-data`: agent-interactable CLI executable for schema generation,
  validation, auth, example commands, cache/outbox inspection, fixture app
  creation, parity scripts, and benchmarks.
- `InstantSwiftDataTesting`: ephemeral app helpers and end-to-end assertion
  tools.
- `InstantSwiftDataBenchmarks`: benchmark executable for Swift/TypeScript
  parity measurements.

The public API should start with concrete Swift app code:

```swift
@main
struct AppMain: App {
  init() {
    prepareDependencies {
      try $0.bootstrapInstantSwiftData(appId: "...", schema: AppSchema.self)
    }
  }
}

@InstantEntity
struct Todo: Identifiable, Codable, Sendable {
  var id: InstantID<Todo>
  var title: String
  var done: Bool
  var createdAt: Date
}

@FetchAll(Todo.query.where(Todo.done == false).order(.serverCreatedAt, .descending))
var openTodos: [Todo]

try await db.transact {
  Todo.create(title: "Ship it", done: false)
}
```

`@InstantEntity` defaults to the documented plural namespace (`Todo` ->
`todos`). A manual override remains available, but the macro should diagnose an
override that exactly matches the default plural. `@FetchAll` should look
familiar to SQLiteData users, but the engine underneath is not SQL. A query
becomes an Instant query tree, the server returns triples, and the local store
materializes Swift values from those triples.

## SQLiteData Audit Notes

Audit source: `upstream/sqlite-data`, especially the Reminders, SyncUps,
CaseStudies, CloudKitDemo, `Fetch*`, `SyncEngine`, and CloudKit test suites.
These practices should inform the Instant Swift Data design without turning the
public API into SQL:

- **One bootstrap path.** SQLiteData's `bootstrapDatabase` and
  `prepareDependencies` pattern is good because previews, tests, app launches,
  and model code all consume the same injected database/sync dependencies. The
  Instant plan should expose `bootstrapInstantSwiftData` as the only production
  setup path, with explicit configuration for app id, auth/session store, local
  SQLite path, transport runtime, outbox, query cache, and preview/test stores.
- **Swift Dependencies for overridable effects.** App-facing clients that vary
  across live, preview, test, CLI, and local terminal contexts should be modeled
  as Point-Free `swift-dependencies` values. Define a Sendable interface in the
  appropriate module, expose reusable concrete instances in extensions such as
  `extension InstantMagicCodeExchange { public static let local = Self(...) }`,
  register `TestDependencyKey` and `DependencyKey` values with computed
  `testValue`, `previewValue`, and `liveValue`, and thread the resolved dependency into
  `bootstrapInstantSwiftData`/`InstantRuntimeConfiguration`. This applies first
  to magic-code exchange and should later apply to transport/auth, sync, file
  storage, and network clients.
- **Typed models above explicit migrations.** SQLiteData combines `@Table`,
  `Draft`, `@Selection`, typed expressions, and generated update helpers with
  named migrations that use strict SQL, foreign keys, indexes, FTS tables, and
  triggers. This is good because application queries are type checked while
  persisted schema history stays frozen and auditable. Instant Swift Data should
  keep typed access to triples, attributes, outbox rows, query cache rows, and
  sync metadata while requiring named migrations for every persisted shape.
- **Observable fetch wrappers as the app-facing contract.** SQLiteData's
  `@FetchAll`, `@FetchOne`, and `@Fetch` expose values plus loading, errors,
  animation, dynamic `load`, and cancellable `FetchSubscription` state. This is
  good because views and `@Observable` models can subscribe without hand-rolled
  observer lifetimes. Instant fetch wrappers should do the same over Instant
  query trees, cached materialized results, server subscriptions, and explicit
  cancellation.
- **Dynamic query work belongs in the engine.** SQLiteData's search examples
  debounce user input, cancel stale tasks, and reload the query key so filtering,
  sorting, FTS, and limits execute in SQLite. This is good because it avoids
  loading everything and doing repeated Swift collection work. Instant dynamic
  queries should replan local materialization and server subscriptions rather
  than treating post-filtered arrays as feature parity.
- **Writes have drafts, transactions, and reportable errors.** SQLiteData uses
  `Draft` values for forms, `database.write` for mutation boundaries, and
  `withErrorReporting` around user actions. This is good because edit state,
  persisted state, transaction scope, and error surfacing stay separate. Instant
  mutations should use typed drafts or builders, an explicit optimistic
  transaction boundary, durable outbox writes, rollback/failure state, and
  actionable error values.
- **Examples are architecture tests.** Reminders and SyncUps keep side effects in
  `@Observable` models with `@ObservationIgnored` dependencies, preview seeds,
  injected clients, and tested model behavior. This is good because real app
  workflows exercise persistence, navigation, search, sharing, media/speech, and
  sync without burying the behavior in SwiftUI `body`. Instant example ports
  should preserve that model-first structure and include CLI access to the same
  core behavior.
- **Sync and sharing are proved with stateful tests.** SQLiteData's CloudKit
  tests use mock private/shared databases, snapshots, relaunch scenarios,
  permission rejection tests, metadata checks, root-record restrictions, and
  sync-engine lifecycle assertions. This is good because collaboration bugs live
  in durable state transitions, not in view code. Instant Swift Data should add
  both deterministic local tests and real Instant validation for memberships,
  roles, share links/tokens, accept/revoke, permissions, reconnect, and relaunch.
- **Cancellable async ownership is part of the API.** SQLiteData fetch
  subscriptions and dependency clients clean up observations and streams on task
  cancellation. This is good because live data, speech/audio, sync, and storage
  work cannot leak past the feature that started it. Instant runtime tasks need
  clear owners and cancellation handles for live queries, presence, topics,
  storage progress, streams, transport reconnect loops, and outbox drains.

## Swift Concurrency Contract

The implementation must follow `docs/swift-concurrency-guidance.md`. Concurrency
correctness is part of the acceptance contract, not cleanup work after features
exist.

Build and toolchain requirements:

- Keep Swift 6 language mode enabled.
- Keep complete strict concurrency enabled in CI.
- Enable upcoming concurrency checks as the supported toolchain allows:
  strict concurrency, region-based isolation, dynamic actor isolation,
  `nonisolated(nonsending)` by default, Sendable inference from captures, and
  isolated conformance inference.
- Do not add `@preconcurrency`, `@unchecked Sendable`, or global actor
  annotations merely to silence diagnostics. Each use needs a local explanation
  of the invariant that makes it correct.

Actor ownership rules:

- Use coarse actors for state ownership: store/triple indexes, outbox,
  persistence, transport/runtime, and delivery/observation where needed.
- Do not make every entity, query, or pending mutation an actor.
- Every mutable variable belongs to exactly one actor. Mutable state that can be
  written from two actors, or from actor-isolated and nonisolated code, is a
  design error.
- Actor methods must not suspend while invariants are partially updated. Split
  mutation, snapshot creation, persistence, and network I/O into explicit phases.
- Cross actor boundaries with immutable snapshots, never with references into
  another actor's mutable state.

Sendable and isolation rules:

- All values crossing actor boundaries must be `Sendable`: query plans,
  transaction steps, IDs, schema IR, errors, cache rows, outbox rows, transport
  messages, storage metadata, room/presence/topic messages, stream chunks, and
  query emissions.
- Prefer immutable structs and enums for boundary values.
- `nonisolated` is for pure, cheap helpers and protocol requirements that do not
  touch actor-owned state.
- `nonisolated(nonsending)` must be deliberate. It can keep lightweight async
  helper work caller-bound, but it must not be used when the intent is to move
  CPU-heavy work off the caller's actor.
- CPU-heavy work must use an explicit concurrent boundary, detached task, custom
  executor, or nonisolated async design that is verified not to inherit main
  actor execution.

Runtime and performance rules:

- Keep `@MainActor` out of `InstantSwiftDataCore`, `InstantSwiftDataSchema`, and
  the CLI. Main actor isolation belongs in UI adapters and examples only.
- Every long-lived task must have an owner and deterministic cancellation path.
  No fire-and-forget task may outlive the call stack without being stored and
  cancelled by its owning runtime or actor.
- Live queries, presence, topics, storage progress, and stream APIs should use
  `AsyncSequence`-shaped surfaces or equivalent observation wrappers with
  bounded buffering and explicit cancellation.
- Hot paths must batch actor crossings. Do not insert or recompute one triple at
  a time across actor boundaries.
- Synchronous SQLite or file I/O must be isolated to a persistence actor or
  custom serial executor and must not block actors responsible for query
  observation or transport responsiveness.

## Validation Suite

The validation rule is: a unit test can explain a helper, but it cannot prove
the library. Every feature must have at least one real script that moves data
through InstantDB and crosses the Swift/TypeScript boundary.

### Harness Shape

Create `validation/` with:

- `fixtures/schema.swift`: Swift source of truth for entities, links, rooms,
  topics, files, and permissions.
- `fixtures/instant.schema.ts`: generated TypeScript schema committed for diff
  review.
- `fixtures/instant.perms.ts`: generated TypeScript permissions committed for
  diff review.
- `swift-runner/`: Swift executable that can subscribe, transact, go offline,
  reconnect, upload files, publish presence/topics, and stream.
- `ts-runner/`: TypeScript executable using `@instantdb/core` and
  `@instantdb/admin`.
- `run-e2e.sh`: orchestrates a fresh ephemeral app, pushes schema/perms, runs
  both runners, collects JSONL evidence, and exits non-zero on mismatch.
- `results/`: ignored output containing per-run logs, timings, and server ids.

### End-To-End Cases

- Swift writes scalar entity; TypeScript admin observes exact fields.
- TypeScript writes scalar entity; Swift subscription observes exact fields.
- Swift creates linked graph; TypeScript nested query observes forward and
  reverse links.
- TypeScript creates multi-linked graph; Swift nested query observes all linked
  entities without duplicates.
- Swift deletes an entity; TypeScript observes removed forward and reverse links.
- TypeScript deletes an entity; Swift observers drop ghost reverse links.
- Swift writes while offline; Swift observer updates immediately; TypeScript
  sees nothing until reconnect; after reconnect TypeScript sees ordered result.
- TypeScript writes while Swift is offline; Swift emits cached result; after
  reconnect Swift observes server update.
- Restart Swift while offline with pending mutations; pending local state
  restores before reconnect and flushes once online.
- `queryOnce` succeeds online and fails offline with last-known data when cached.
- High-bandwidth scalar update stream: Swift performs repeated updates,
  TypeScript observes monotonic final state and timing budget.
- High-bandwidth linked writes: Swift writes create/link batches, TypeScript
  observes no link-before-create failures.
- TypeScript high-bandwidth writes; Swift observes without dropping final state.
- Presence: Swift joins room and publishes presence; TypeScript observes.
- Presence: TypeScript joins room and publishes presence; Swift observes.
- Topics: Swift publishes topic; TypeScript receives exactly once.
- Topics: TypeScript publishes topic; Swift receives exactly once.
- Storage: Swift uploads and links file; TypeScript queries `$files` and linked
  entity.
- Storage: TypeScript uploads or creates file record; Swift observes.
- Streams: Swift writes stream chunks; TypeScript reads in order.
- Streams: TypeScript writes stream chunks; Swift reads in order.
- Sharing: two Swift users share and accept a Reminders list; TypeScript verifies
  memberships, permissions, and visible sharing metadata.
- CLI: `instant-swift-data examples todos add "do the dishes"` persists auth,
  local IDs, cache, and outbox state for a later CLI invocation.
- Permissions: generated permissions reject an unauthorized write in both
  Swift and TypeScript paths.
- Concurrency: concurrent Swift `transact` calls preserve deterministic outbox
  order and deterministic final store state.
- Concurrency: transport updates racing with local optimistic writes produce the
  same materialized query results across repeated runs.
- Concurrency: cancelling live query, presence, topic, stream, and storage
  subscriptions unregisters observers and releases continuations.
- Concurrency: no core API requires `@MainActor`; UI examples may adapt core
  emissions onto the main actor.

### Performance Gates

Record numbers as JSON, not prose:

- Subscription initial load latency.
- Swift -> TypeScript write observation latency.
- TypeScript -> Swift write observation latency.
- Offline outbox enqueue latency.
- Reconnect flush throughput and p95 time-to-visible.
- High-bandwidth update throughput for scalar and linked writes.
- Memory growth during 1k, 10k, and 50k triple workloads.
- Swift/TypeScript benchmark comparison result and quantified gap when Swift is
  slower.
- Actor-hop counts or equivalent instrumentation for triple insert,
  materialization, reconnect drain, and outbox flush hot paths.
- Cancellation latency for live query, presence/topic, storage progress, and
  stream subscriptions.

Initial budgets can be loose until the implementation exists, but the suite
must emit the same metrics on day one so regressions become visible.

## Implementation Packets

1. Repository scaffold: `InstantSwiftData` package targets, macro and benchmark
   placeholders, docs, validation directories, and Swift 6 strict concurrency
   settings.
2. Schema IR and macros: import the best pieces from `InstantSchemaCodegen` and
   `InstantDBMacros`; make Swift -> TypeScript generation the primary path; add
   Point-Free MacroTesting coverage for generated code and diagnostics.
3. Concurrency foundation: apply `docs/swift-concurrency-guidance.md`; define
   actor ownership for store, outbox, persistence, transport/runtime, and
   observation; define Sendable boundary types; add strict-concurrency CI.
4. Bootstrap and persistence foundation: implement `bootstrapInstantSwiftData`
   through `prepareDependencies`; provision context-aware live, preview, test,
   and CLI stores; register Swift Dependencies values for magic-code exchange
   and future auth/transport seams; create named SQLite migrations for
   attributes, triples, query cache, sync metadata, local IDs, auth/session, and
   outbox tables.
5. Core local store: port triple store, attrs store, query materialization,
   observer invalidation, and reverse-link cleanup into `InstantSwiftDataCore`;
   persist through SQLite first; batch store mutation and query emissions across
   actor boundaries.
6. Transport and auth: merge `InstantClient`, connection messages, auth manager,
   and session persistence into the core target behind Sendable Swift
   Dependencies clients whose local/test implementations remain usable without
   real Instant credentials.
7. Agent CLI foundation: auth, selected app, SQLite cache, local IDs, query cache,
   sync metadata, and pending outbox persisted across invocations.
8. Mutation outbox: draft/builder write APIs, explicit optimistic transaction
   boundary, durable pending mutations, confirmation cleanup, rollback/error
   surfacing, and ordered flush.
9. Query surface: `@FetchAll`, `@FetchOne`, `@Fetch`, `queryOnce`, pagination,
   infinite query, nested linked queries, dynamic query changes, loading/error
   state, animation hooks, and cancellable subscription handles.
10. Realtime linked entities: multi-link resolution, field filters, different
    `with` clauses, and reverse observer propagation.
11. Offline: cached subscription emission, strict offline `queryOnce`, restart
    restore, reconnect flush.
12. Storage, auth public API, presence, topics, rooms, and streams with explicit
    async ownership and cancellation handles.
13. Sharing model: Instant-native share entities, memberships, permissions,
    accept/revoke flows, visible sharing metadata, read-only rejection behavior,
    relaunch/reconnect proof, Reminders list sharing proof, and CloudKitDemo
    concept port.
14. Example ports: Instant website examples, Instant recipes, SQLiteData
    CaseStudies, Reminders, SyncUps, and CloudKitDemo concepts; keep business
    logic in observable models with injected dependencies and preview/test seeds.
15. TypeScript test parity: port or classify Instant TypeScript tests with exact
    source-file/test-name provenance.
16. SQLiteData-style local test suite: add deterministic in-memory tests for
    dynamic fetches, migrations, write errors, sharing rules, relaunch, and
    cancellation alongside real Instant validation.
17. Performance pass: benchmark target, Swift/TypeScript comparison scripts,
    batch write path, query recomputation profiling, local persistence hot path,
    memory pressure, actor-hop counts, and cancellation latency.

## Non-Goals For The First Cut

- Do not preserve `@Shared(.instantSync(...))` as the primary public API.
  A compatibility adapter can come later.
- Do not maintain `instant-ios-sdk` as a separate repository dependency.
- Do not treat mock-only unit tests as acceptance proof.
- Do not manually edit generated TypeScript schema/perms except to debug the
  generator.

## Remaining Open Questions

- How much of Instant streams is stable public API versus internal support for
  React Native/resumable stream packages?
- Which Swift SQLite layer should own persistence first: GRDB,
  StructuredQueries/SQLiteData pieces, or a narrower SQLite adapter inside
  `InstantSwiftDataCore`?

## First Acceptance Contract

- WHEN a schema is declared in Swift, THE CLI SHALL generate
  `instant.schema.ts`, `instant.perms.ts`, Swift entity helpers, and a validation
  fixture app without manual edits.
- WHEN Swift writes an entity, THE TypeScript runner SHALL observe the entity
  through InstantDB and verify fields from a server read.
- WHEN TypeScript writes an entity, THE Swift runner SHALL observe the entity
  through InstantDB and verify fields from a live subscription.
- WHEN Swift writes offline, THE Swift observer SHALL update immediately, THE
  TypeScript runner SHALL not observe the write before reconnect, and THE
  TypeScript runner SHALL observe it after reconnect.
- WHEN high-bandwidth writes run, THE suite SHALL record throughput, p95
  latency, dropped-update count, final-state correctness, and memory use.
- WHEN the CLI runs `instant-swift-data examples todos add "do the dishes"`,
  THE next CLI invocation SHALL observe the same durable auth/cache/outbox world.
- WHEN the package builds in CI, THE core targets SHALL compile under Swift 6
  strict concurrency with no accepted concurrency-warning debt.
- WHEN concurrent Swift writes, transport updates, observer cancellation, and
  reconnect drains run, THE suite SHALL prove deterministic state, deterministic
  outbox order, bounded buffering, and cancellable task ownership.
