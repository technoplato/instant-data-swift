# InstantDB Swift Data Plan

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

## Upstream Inventory

Fetched on 2026-06-12.

| Source | Local path | Revision inspected | What to mine |
| --- | --- | --- | --- |
| Instant TypeScript | `/Users/michael.lustig/Sync/tca/tools-local/instant` | `origin/main e7101761` | Canonical client behavior, schema surface, query grammar, transaction grammar, streams, storage, presence, auth, offline cache, sync table |
| SQLiteData | `/Users/michael.lustig/Sync/tca/tools-local/sqlite-data` | `origin/main 0c79d7a` | SwiftData-like API shape, `@FetchAll`/`@FetchOne`/`@Fetch`, dependency bootstrap, migration docs, observation ergonomics |
| Swift sharing Instant, ship branch | `/Users/michael.lustig/Sync/tca/upstream-swift/swift-sharing-instant-ship` | `8286964` | Best current Swift Instant behavior: reactor, triple store, offline tests, pending flush order, schema codegen, presence/topics/storage |
| Swift sharing Instant, older branch | `/Users/michael.lustig/Sync/tca/swift-sharing-instant` | `d78601a` | Auto-research artifacts, ported tests, in-memory database sketches, parity scripts |
| Instant iOS SDK draft | `/Users/michael.lustig/Sync/tca/tools-local/instant-ios-sdk` | `3e41b59` | Core Swift client, WebSocket, local storage, auth, storage, query manager, local-first manager, macros |
| Sigil bridge | `/Users/michael.lustig/Sync/Sigil/Sources/USSInstantBridge` | local files | App-level bridge patterns and persistence integration |

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
- One-shot strict queries equivalent to `queryOnce`.
- Top-level namespace queries and nested relation queries.
- Explicit linked-entity inclusion, including multi-linked entities and reverse
  links.
- Field selection.
- `where` operators: equality, `$ne`, `$isNull`, `$gt`, `$lt`, `$gte`, `$lte`,
  `$in`, `$like`, `$ilike`, `and`, `or`, and nested field paths like
  `relation.field`.
- Ordering on indexed fields and `serverCreatedAt`.
- Pagination on top-level namespaces: `limit`, `offset`, `first`, `after`,
  `last`, `before`, inclusive cursors, and page info.
- Infinite query subscriptions.
- Query validation that rejects unsupported operators and illegal nested
  pagination before the network call.
- Hashing/caching of queries so cached results can be restored consistently.

### Mutations

- Transaction builder parity with TypeScript `db.tx`.
- `create`, `update`, strict update with no upsert, `merge`, `delete`, `link`,
  `unlink`, and `ruleParams`.
- Batch transactions with stable operation order.
- Lookup refs by unique attribute.
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
- CLI commands for schema generation, migration planning, push, get, and
  validation.
- Dev logging hooks should be optional and removable from production targets.

## Proposed Package Architecture

One repository, multiple targets:

- `InstantData`: public SwiftData-like API. Property wrappers, dependency
  bootstrap, query/mutation surface, errors, and docs.
- `InstantDataCore`: internal client engine. Reactor, transport, local store,
  outbox, query processor, persistence, auth, storage, presence, streams.
- `InstantDataSchema`: Swift schema declaration DSL, IR, TypeScript printer,
  Swift code generator, permissions printer.
- `instant-data`: CLI executable for schema generation, validation, fixture
  app creation, and parity scripts.
- `InstantDataTesting`: ephemeral app helpers and end-to-end assertion tools.

The public API should start with concrete Swift app code:

```swift
@main
struct AppMain: App {
  init() {
    prepareDependencies {
      try $0.bootstrapInstantData(appId: "...", schema: AppSchema.self)
    }
  }
}

@InstantEntity("todos")
struct Todo: Identifiable, Codable, Sendable {
  var id: UUID
  var title: String
  var done: Bool
  var createdAt: Date
}

@FetchAll(Todo.where(\.done == false).order(by: \.createdAt.desc()))
var openTodos: [Todo]

try await instantData.write {
  Todo.create(id: id, title: "Ship it", done: false)
}
```

`@FetchAll` should look familiar to SQLiteData users, but the engine underneath
is not SQL. A query becomes an Instant query tree, the server returns triples,
and the local store materializes Swift values from those triples.

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
- Permissions: generated permissions reject an unauthorized write in both
  Swift and TypeScript paths.

### Performance Gates

Record numbers as JSON, not prose:

- Subscription initial load latency.
- Swift -> TypeScript write observation latency.
- TypeScript -> Swift write observation latency.
- Offline outbox enqueue latency.
- Reconnect flush throughput and p95 time-to-visible.
- High-bandwidth update throughput for scalar and linked writes.
- Memory growth during 1k, 10k, and 50k triple workloads.

Initial budgets can be loose until the implementation exists, but the suite
must emit the same metrics on day one so regressions become visible.

## Implementation Packets

1. Repository scaffold: package targets, dependencies, docs, and validation
   directories.
2. Schema IR: import the best pieces from `InstantSchemaCodegen` and
   `InstantDBMacros`; make Swift -> TypeScript generation the primary path.
3. Core local store: port triple store, attrs store, query materialization,
   observer invalidation, and reverse-link cleanup into `InstantDataCore`.
4. Transport and auth: merge `InstantClient`, connection messages, auth manager,
   and session persistence into the core target.
5. Mutation outbox: transaction builder, optimistic apply, durable pending
   mutations, confirmation cleanup, rollback/error surfacing, and ordered flush.
6. Query surface: `@FetchAll`, `@FetchOne`, `@Fetch`, `queryOnce`, pagination,
   and infinite query.
7. Realtime linked entities: nested queries, multi-link resolution, field
   filters, different `with` clauses, and reverse observer propagation.
8. Offline: cached subscription emission, strict offline `queryOnce`, restart
   restore, reconnect flush.
9. Storage, auth public API, presence, topics, and streams.
10. Performance pass: batch write path, query recomputation profiling, local
    persistence hot path, memory pressure.

## Non-Goals For The First Cut

- Do not preserve `@Shared(.instantSync(...))` as the primary public API.
  A compatibility adapter can come later.
- Do not maintain `instant-ios-sdk` as a separate repository dependency.
- Do not treat mock-only unit tests as acceptance proof.
- Do not manually edit generated TypeScript schema/perms except to debug the
  generator.

## Open Questions

- Should the public package name be `InstantData`, `InstantSwiftData`, or
  `InstantDBData`?
- Should Swift `Date` default to Instant `date` values or epoch milliseconds?
  The prior examples recommend epoch milliseconds for TypeScript parity, but a
  SwiftData-like surface will expect `Date`.
- Should the first storage backend be SQLite through GRDB/StructuredQueries, or
  should we keep the current custom `LocalStorage` tables and only adopt
  SQLiteData-style observation APIs?
- How much of Instant streams is stable public API versus internal support for
  React Native/resumable stream packages?

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

