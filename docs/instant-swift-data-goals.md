# Instant Swift Data Goals

This document is the portable goal contract for continuing the work from this
repository.

## Product Goal

Build **Instant Swift Data**: a Swift package that lets an app describe durable
records, live signals, files, streams, auth, permissions, and sharing in Swift,
then keeps those values correct through InstantDB, offline SQLite persistence,
command-line tools, and TypeScript parity tests.

The system is successful only when complete Swift examples prove the library in
real applications. Small demos are useful during development, but half-ported
examples do not satisfy the goal.

## Source Material To Read First

- Instant TypeScript repository:
  `upstream/instant`
- Instant website examples:
  `upstream/instant/client/www/_examples`
- Instant website recipes:
  `upstream/instant/client/www/app/recipes` and
  `upstream/instant/client/www/app/docs`
- SQLiteData examples:
  `upstream/sqlite-data/Examples`
- Existing Swift Instant work:
  `upstream/sharing-instant` and `upstream/instant-ios-sdk`
- `upstream/README.md` for checked-out revisions and transfer notes, including
  the missing local-only `swift-sharing-instant-ship` checkout.
- Attached Instant LLM and patterns docs in this Codex thread.
- On the target machine, also research the latest Swift, Swift macro, Swift
  benchmarking, SwiftPM, SwiftData, Observation, and Xcode documentation through
  the configured Xcode docs tooling before implementing APIs that depend on
  current Swift behavior.

## Name And Shape

- Package name: **Instant Swift Data**.
- Swift module/product naming should center on `InstantSwiftData`.
- One repository owns all production targets.
- Do not maintain a separate core Swift SDK and a separate wrapper package.
- Internal targets are required and should be versioned together:
  - `InstantSwiftData`: public app API.
  - `InstantSwiftDataCore`: triple store, reactor, transport, cache, outbox,
    query engine, auth, storage, streams.
  - `InstantSwiftDataSchema`: Swift schema DSL, IR, TypeScript printer,
    permission printer, code generation.
  - `InstantSwiftDataMacros`: macros such as `@InstantEntity`.
  - `InstantSwiftDataTesting`: ephemeral apps, admin clients, fixtures,
    generated draft validation, platform adapter validation, real-run
    assertions.
  - `instant-swift-data`: command-line interface.
  - `InstantSwiftDataBenchmarks`: Swift benchmark targets.

## Required Example Ports

These examples are acceptance artifacts. They must be full working apps with
tests, not screenshots or partial sketches.

### Instant Website Examples

Port the examples from `client/www/_examples`:

- `todos`: basic schema, realtime todos, presence/viewer count, offline behavior.
- `chat`: guest/login flow, channels, messages, seed/reset tooling.
- `microblog`: `$users`, profiles, posts, likes, nested linked queries,
  cascade delete, auth integration.
- `mobile-chat`: mobile realtime chat shape and React Native parity concepts
  translated into Swift.
- `stroopwafel`: multiplayer game shape using the current upstream durable
  `$users`, rooms, games, and points schema, with host/member permission checks;
  presence/topics should be covered where upstream source actually declares and
  uses them.
- `app-builder`: schema, storage, platform/tooling concepts where applicable.

### Instant Recipes

Port the recipes from `client/www/pages/recipes`:

- todos.
- auth: `instant-swift-data examples auth send-code`, `verify-code`, `status`,
  `watch`, and `sign-out`.
- cursors via presence: `instant-swift-data examples cursors move`, `list`,
  `watch`, `clear`, and `leave`.
- custom cursors via presence: `instant-swift-data examples custom-cursors
  move`, `list`, `watch`, `clear`, and `leave`.
- reactions via topics: `instant-swift-data examples reactions tap`, `list`,
  and `watch`.
- typing indicator via presence: `instant-swift-data examples typing-indicator
  join`, `type`, `stop`, `list`, `watch`, and `leave`.
- avatar stack via presence: `instant-swift-data examples avatar-stack join`,
  `list`, `watch`, and `leave`.
- merge tile game using `merge` and multiplayer presence:
  `instant-swift-data examples merge-tile-game join`, `tap`, `board`, `watch`,
  `reset`, and `leave`.

### SQLiteData Examples

Port the examples from `pointfreeco/sqlite-data/Examples`:

- CaseStudies:
  animations, dynamic queries, transactions, SwiftUI, UIKit, observable model,
  and SwiftData-template comparison.
- Reminders:
  full reminders/lists/tags app, advanced search, stats, list detail,
  forms, many-to-many tags, sharing, and tests.
- SyncUps:
  faithful Scrumdinger/SyncUps port, meeting recording flow, speech/sound/open
  settings dependencies, persistence, sync, and tests.
- CloudKitDemo:
  port the synchronization and record-sharing concept to Instant. This does not
  mean using CloudKit; it means providing the Instant equivalent of shared
  records, participants, permissions, accept/share links, and visible sharing
  state.
  The local CloudKitDemo-style counter CLI remains available:
  `instant-swift-data examples counters add/list/increment/decrement/delete`
  and the `examples cloudkit-demo` alias. It proves local visible sharing
  metadata, current-user roles, member counts, reader rejection, and writer
  promotion for shared counter roots. `instant-swift-data validation
  cloudkit-demo --jsonl` promotes that proof to a terminal artifact covering
  owner create/share, invitee accept, reader rejection without local/outbox
  mutation, writer promotion/update, and relaunch persistence. This is
  local/mock-remote Instant evidence. The runnable `CloudKitDemoV3App` now
  completes the real boundary on a fresh Instant app using the settled sharing
  namespaces and public typed messages. Swift creates the shared graph,
  reader denial rolls optimistic state back, the owner replaces reader/writer
  roles and revokes access, both SDKs increment the same exact counter shape,
  and Swift relaunches with visible `@Shares` state. Reproducible evidence is
  produced by `validation/verify-cloudkit-demo-v3-app-live.sh`.

## Public API Goals

Start from a concrete Swift app:

```swift
@InstantEntity
struct Todo: Identifiable, Codable, Sendable {
  var id: InstantID<Todo>
  var text: String
  var isCompleted: Bool
  var createdAt: Date
}

@FetchAll(Todo.query.order(.serverCreatedAt, .descending))
var todos: [Todo]

try await db.transact {
  Todo.create(text: "Ship Instant Swift Data")
}

var draft = Todo.Draft(text: "Ship generated drafts", isCompleted: false)
try await db.save(draft)

var editDraft = Todo.Draft(existingTodo)
editDraft.text = "Ship generated draft edits"
try await db.save(editDraft)
```

The macro should infer the namespace from the type name:

- `Todo` -> `todos`
- `Profile` -> `profiles`
- `SyncUp` -> `syncUps` or the selected documented pluralization strategy
- Manual namespace override remains available for special cases:

```swift
@InstantEntity("people")
struct Person { ... }
```

Add a lint or macro diagnostic rule that warns when the override is exactly the
default plural. `@InstantEntity("todos") struct Todo` should be flagged as
redundant.

Queries should resemble InstantDB, but be strongly typed and Swift-native:

```swift
@FetchAll(
  Post.query
    .where(\.author.handle == selectedHandle)
    .include(\.author)
    .include(\.likes)
    .order(.serverCreatedAt, .descending)
)
var posts: [Post.With<(\.author, \.likes)>]
```

`serverCreatedAt` is reserved for order-only metadata and should not be emitted
as a schema attribute or decoded model field. Models that need their own visible
creation timestamp should use a domain field such as `createdAt`.
Queries without an explicit order should follow Instant's implicit
`serverCreatedAt` ascending order.
Typed field selection should use declared attribute paths, for example
`.select(Todo.text, Todo.isCompleted)`. Partial selections should be consumed as
snapshots unless a model's decoder explicitly supports the reduced shape.
Typed forward includes should use declared ref attributes, for example
`.include(Post.author, User.query.select(User.name))`; reverse includes should
be generated relation tokens rather than raw string names. A relation declared on
the source type may host the reverse token there, for example `Post.posts` for
`@InstantRelation(reverse: "posts") var author: InstantID<User>`, while the token
type still encodes the target/source relation for `User.query.include(...)`.
One-shot typed queries should use `queryOnceDecoded` when callers need decoded
values plus pagination `pageInfo`, and raw `queryOnce` when they need snapshots
or the full query emission.
Strict one-shot queries should validate selected fields, filters, order fields,
and include targets before materializing or caching invalid plans.

Dynamic queries are a first-class requirement:

```swift
@Observable
final class ReminderSearchModel {
  var text = ""
  var selectedList: ReminderList.ID?

  @ObservationIgnored
  @FetchAll var reminders: [Reminder] = []

  func refresh() async throws {
    try await $reminders.load(
      Reminder.query
        .where(\.title.localizedContains(text))
        .where(optional: selectedList) { \.list.id == $0 }
        .include(\.tags)
        .order(\.dueDate, .ascending)
    )
  }
}
```

The API should avoid SQL noise. Instant field projection may use `.select(...)`
with declared attribute paths because it maps to Instant field selection, but do
not expose `leftJoin` or SQL row-shape machinery unless there is no cleaner
Instant-shaped representation.

Client adapters should translate live/subscribable Instant objects into
platform-idiomatic Swift surfaces. The public app-facing layer should expose
property wrappers, projected bindings, observable model state, and
`AsyncSequence` streams rather than leaking raw subscription callbacks or
transport objects into feature code.

## Schema And Type Safety

- Swift schema is the source of truth.
- Generate `instant.schema.ts`, `instant.perms.ts`, Swift entity helpers, Swift
  mutation helpers, Swift query helpers, room/topic/presence types, and
  validation fixtures.
- Support Instant scalar types: string, number, boolean, date, json.
- `Date` defaults to Instant's date value, not an epoch-number convention.
  Epoch milliseconds remain an explicit compatibility strategy.
- Support typed enums and discriminated unions at the Swift layer.
- Encode enums/unions to an Instant-compatible wire representation.
- Decode validation must reject wrong server values with clear messages.
- Writes that are impossible for the declared Swift type must be rejected before
  network send.
- Support typed IDs and local IDs. Local IDs must persist by name, matching
  Instant's `getLocalId("name")` behavior.
- Generate `Entity.Draft` for primary-keyed `@InstantEntity` models. A draft's
  `id` must be optional, `Draft(existingEntity)` must copy persisted values for
  edit flows, and the memberwise initializer must support new drafts whose id is
  omitted so the client can allocate the Instant id at save time. Entities that
  declare the primary key as immutable `let id` must receive the same generated
  draft surface.
- Generated drafts should include only writable stored fields, should not emit
  the managed Instant id as a normal attribute assignment, and should not conform
  to `Identifiable` by default. UI examples may add their own stable local
  editing identity when needed. Writable Instant ref fields must be included
  with their generated relation metadata so linked edit/create forms can save
  and clear relation drafts. When `instantAttributes` is manual, relation draft
  fields must also have an explicit static `InstantAttributePath`; the macro
  should diagnose the missing path rather than silently omitting the draft
  assignment. Terminal validation should prove the summarized pending mutation
  shape for nil-id creates and `Draft(existing)` edits.

## Mutation Semantics

- Match Instant transaction builder behavior: `create` is a strict insert,
  `update` is the upsert-shaped write, `updateExisting`/no-upsert update must
  fail before cache/outbox writes when the entity is missing, and `merge` should
  deep-merge JSON values while rejecting relationship attributes in favor of
  `link`/`unlink`.
- Support lookup refs by unique attribute for entity writes and link targets.
  Pending mutations should preserve lookup-shaped operations for server
  lowering, while local optimistic application resolves them against the current
  AEV index in transaction order. Unresolved non-strict lookup writes may no-op
  locally and remain pending for the server, but strict lookup updates must fail
  before cache/outbox writes.
- Support SQLiteData-style draft saves as a first-class typed write path.
  Saving a draft with an id should update/upsert that entity through existing
  mutation semantics; saving a draft without an id should allocate a durable
  client-scoped Instant id, create the entity, return the created id, and leave
  strict `create`/`updateExisting` guarantees intact. Draft saves should also
  compose with related writes in one explicit transaction so create/edit forms
  can save the draft, use the allocated typed id, and write links or child rows
  with the same transaction id/time, matching SQLiteData form ergonomics.
- Preserve `ruleParams` operations in the pending outbox for transport lowering.
  Rule params affect server-side permission evaluation and should not mutate
  local materialized entities optimistically.
- Pending mutations should expose a deterministic Instant-shaped transport
  projection so agents can inspect `txSteps` before real WebSocket sync is
  available.
- Mutation transport should be an injectable Sendable client so local demos,
  tests, previews, and future live WebSocket transport share the same
  send/ack/failure application path.
- Live session transport should also be an injectable Sendable client with
  reusable `.local` and `.live` instances. Swift Dependencies should expose it
  through `DependencyValues.instantLiveTransport`, defaulting to nil so the
  local-cache runtime remains deterministic until apps explicitly opt into a
  WebSocket session.
- Local delete must remove the entity, forward refs, and reverse refs, and must
  honor `onDelete`/`onDeleteReverse` cascade metadata. Until Swift transactions
  carry namespace-specific delete steps, `deleteEntity(String)` is a
  namespace-less fallback and therefore applies cascades across every matching
  local incoming ref edge for that raw id.
- Local seed/demo helpers may use explicit upsert operations so terminal demos
  remain repeatable against durable state, but app-facing `create` must stay
  strict.

## Triple Store Fidelity

Instant stores client data as entity-attribute-value-time facts and indexes
those facts for query resolution. The Swift core must respect that model.

Required structures:

- EAV index: entity -> attribute -> value -> triple.
- AEV index: attribute -> entity -> value -> triple.
- VAE index for refs: value/target -> attribute -> entity -> triple.
- Attribute store with forward identity, reverse identity, cardinality,
  value type, indexed/unique metadata, primary keys, and link metadata.
- Timestamp/tx metadata needed for ordering, reconciliation, sync-table
  behavior, and server-created ordering.

The Swift implementation should be faithful first, then optimized. It must be
possible to compare Swift triple-store behavior directly against TypeScript
fixtures.

## Local Persistence

Use SQLite as the first Swift local persistence backend unless benchmarking
proves a better choice.

SQLite should persist:

- schema attributes and link metadata.
- triples.
- query cache and query metadata.
- sync-table state.
- pending mutation outbox.
- processed transaction ids.
- auth/session state.
- local IDs.
- storage/file metadata.

The public API should feel like SQLiteData where useful, but the implementation
should be Instant-shaped, not SQL-shaped.

## SQLiteData Practices To Preserve

The SQLiteData checkout is valuable because it shows how to make persistence feel
small at the call site while keeping lifecycle, errors, migrations, sync, and
testing explicit. Instant Swift Data should preserve these practices, adapted to
Instant's triple store and network model:

- **Dependency bootstrap as the root lifecycle boundary.** SQLiteData provisions
  `defaultDatabase` and `defaultSyncEngine` through `prepareDependencies` and a
  single `bootstrapDatabase` entry point, including previews and tests. This is
  good because app code, previews, CLIs, and tests all receive the same durable
  dependencies without global singletons or parallel setup paths. Instant Swift
  Data should provide one bootstrap path for app id, auth/session persistence,
  local SQLite cache, transport runtime, outbox, and live-query observation.
- **Swift Dependencies for effectful seams.** Use Point-Free's
  `swift-dependencies` library for app-facing override points that must vary by
  live, preview, test, CLI, or local-demo context. Keys should conform to
  `TestDependencyKey`, extend `DependencyValues` for key-path access, and use
  computed `liveValue`, `testValue`, and `previewValue` properties. Concrete
  Sendable clients can expose reusable extension instances such as
  `extension InstantMagicCodeExchange { public static let local = Self(...) }`,
  but the runtime must receive them through bootstrap/configuration rather than
  reaching for globals. Magic-code exchange, transport/auth clients, clocks,
  UUIDs, file/storage clients, sync engines, and
  future network clients should follow this pattern.
  Current package policy follows this shape with the auth exchange/verifier
  clients and `InstantMutationTransportClient`: each is a Sendable value client,
  exposes `.local` as an extension static instance for terminal demos, registers
  a `DependencyValues` key, and is resolved by `bootstrapInstantSwiftData` into
  `InstantRuntimeConfiguration`. New app-facing effect seams should copy that
  shape instead of adding hidden mutable singletons or parallel setup paths.
- **Context-aware database configuration.** SQLiteData uses context-dependent
  default databases, debug-only query tracing, in-memory or temporary databases
  for tests/previews, and explicit migrations. This is good because local
  development is observable while production avoids leaking bound values, and
  tests do not fight over shared state. Instant Swift Data should keep separate
  live, preview, test, and CLI stores with explicit paths and logging policies.
- **Frozen migrations plus typed query models.** SQLiteData keeps table
  declarations typed with `@Table`, but writes deployed schema changes as named,
  frozen migrations using strict SQL, foreign keys, indexes, FTS tables, and
  triggers. This is good because runtime queries stay type checked while shipped
  storage history remains reviewable and reproducible. Instant Swift Data should
  treat its SQLite tables for triples, attributes, query cache, sync metadata,
  and outbox the same way: typed access above, explicit migrations below.
- **Property wrappers backed by observable readers.** `@FetchAll`, `@FetchOne`,
  and `@Fetch` expose loaded values, `load`, `isLoading`, `loadError`, animation,
  dynamic query replacement, and cancellable subscriptions. This is good because
  SwiftUI views and observable models can own live data without bespoke observer
  wiring. Instant Swift Data should provide the same ergonomic state surface over
  Instant query trees, cached local materialization, server subscriptions, and
  cancellation.
- **Dynamic queries execute in the data engine.** SQLiteData's search examples
  debounce input, cancel stale tasks, and reload the underlying fetch key instead
  of fetching everything and filtering in Swift. This is good because memory,
  sorting, search, and pagination work stay close to the store. Instant Swift
  Data dynamic queries must replan and resubscribe at the query layer rather than
  filtering materialized Swift arrays as a substitute for Instant query support.
- **Draft-based writes and explicit write boundaries.** SQLiteData examples use
  generated `Draft` values for forms and `database.write` blocks for mutations,
  with `withErrorReporting` around user actions. This is good because edit state
  stays separate from persisted state, writes have one obvious transaction
  boundary, and thrown errors are surfaced instead of becoming crashes. Instant
  Swift Data should mirror this with typed mutation drafts, explicit optimistic
  transaction blocks, and human-readable error reporting.
- **Business logic outside SwiftUI bodies.** The larger examples use
  `@Observable` models, `@ObservationIgnored` dependencies/fetchers, injected
  clients, and small view methods for user intents. This is good because query,
  navigation, persistence, permissions, and side effects can be tested without
  rendering views. Instant Swift Data examples should follow the same model-first
  shape rather than hiding core behavior in SwiftUI `body` code.
- **Sync and sharing invariants are tested as domain rules.** SQLiteData's
  CloudKit tests cover root-record share restrictions, shared/private scopes,
  permission rejections, metadata, conflict behavior, relaunch, and sync-engine
  lifecycle with mock cloud databases and snapshot evidence. This is good
  because sharing is proven as durable state and authorization behavior, not just
  as UI. Instant Swift Data must prove equivalent Instant-native sharing,
  membership, permission, accept/revoke, reconnect, and relaunch behavior with
  real Instant validation plus deterministic local tests.
- **Cancellation and ownership are API features.** SQLiteData returns fetch
  subscriptions that can be tied to SwiftUI task lifetime, and dependency clients
  use `AsyncSequence`-style streams with termination cleanup. This is good
  because live queries and device/service clients do not leak work after the UI
  or model stops observing. Instant Swift Data should make cancellation explicit
  for live queries, presence, topics, storage progress, streams, reconnect loops,
  and outbox drains.

## Network Errors And Human Messages

Every rejected network write must produce a clear, human-readable error. This
includes:

- permission rejection.
- schema mismatch.
- wrong value type.
- missing linked entity.
- link-before-create ordering failures.
- auth/session failures.
- storage failures.
- stream failures.
- offline timeout or reconnect exhaustion.

The error should name:

- the operation.
- the entity or namespace.
- the field/link/path when applicable.
- the local id and server event id when available.
- whether the optimistic local state was kept, rolled back, or marked failed.
- the likely fix.

## CLI Requirement

The core library must work without SwiftUI. The command line is not a demo; it
is an acceptance surface.

The CLI must be **agent-interactable** and **non-captive**. An LLM or shell
script should be able to use the same core business logic as the GUI examples
without launching a heavy SwiftUI application or simulator. Commands must be
small, composable, deterministic, and readable from stdout/stderr.

CLI argument parsing must use Point-Free `swift-parsing`/parser-printer
combinators for the typed grammar. Preserve today's global `--json`/`--jsonl`
semantics while migrating command leaves gradually behind parser-level tests;
manual `popFirstArgument` parsing is allowed only as a temporary legacy bridge.
Current progress: top-level command/output token parsing and `examples todos`,
auth recipe, app-builder, chat, microblog, mobile-chat, todo-links,
CloudKitDemo/counters, reactions, typing-indicator, avatar-stack, cursors,
custom-cursors, merge-tile-game, Stroopwafel, SyncUps, and Reminders dispatch
are combinator-backed, and the executable consumes those typed leaves produced
by the parser instead of reparsing those branches.

The CLI must maintain durable state across sessions using the same persistence
work as the core library:

- authenticated user/session.
- selected app/environment.
- local SQLite cache.
- local IDs.
- pending mutation outbox.
- last observed query cache.
- sync metadata needed to refresh before and after commands.

For example, the todo example should be usable like this:

```bash
instant-swift-data examples todos add "do the dishes"
instant-swift-data examples todos list
instant-swift-data examples todos complete <todo-id>
instant-swift-data examples todos refresh
```

If an agent runs `instant-swift-data examples todos add "do the dishes"`, the
command should:

1. load persisted CLI auth and local cache.
2. refresh the relevant todo query when network is available.
3. add the todo through the same typed core mutation path used by the app.
4. apply the write optimistically to the local cache.
5. enqueue or send the mutation depending on connectivity.
6. print the refreshed todo list or a JSON result.
7. persist the resulting cache/outbox/session state so the next CLI invocation
   resumes from the same world.

The next command invocation must observe the prior command's state. If the user
adds a todo in one shell session and lists todos in another, the second command
must show the locally cached todo immediately and then reconcile with InstantDB.

CLI auth is required and must consume `InstantSwiftDataCore`, not a parallel
implementation. Required auth flows:

- guest sign-in.
- id-token sign-in backed by an injectable `InstantIDTokenExchange` dependency
  for native OAuth providers such as Apple, Google, Clerk, and Firebase.
- OAuth authorization-code sign-in backed by an injectable `InstantOAuthExchange`
  dependency for web/provider callback flows.
- magic-code sign-in backed by an injectable `InstantMagicCodeExchange`
  dependency, with `.local` for the durable terminal demo and a live exchange
  replacing it when real Instant auth transport lands. App and test code should
  override `DependencyValues.instantMagicCodeExchange` before
  `bootstrapInstantSwiftData`; the CLI may use the same `.local` instance for
  non-captive proof until transport-backed auth is implemented. The app-facing
  dependency client should also expose
  `signInWithMagicCodeResult(email:code:extraFields:)` so `$users` extra fields
  can be persisted locally with Instant's `created` flag semantics while the
  legacy session-returning API remains source compatible.
- app-facing auth should be available directly on the `InstantSwiftDataClient`
  dependency, not by reaching through to private runtime internals. This
  includes `observeAuthSession` for auth-state subscriptions and
  `signInWithIDToken(clientName:idToken:nonce:)` for native OAuth token flows
  plus `signInWithOAuth(code:codeVerifier:)` for authorization-code flows.
- OAuth authorization URL and issuer helpers should mirror Instant's
  `apiURI`/`appID` URL shape and be available through both the runtime and the
  app-facing dependency client.
- sign-out token invalidation should be backed by an injectable
  `InstantAuthTokenInvalidator` dependency with a reusable `.local` no-op for
  terminal demos and tests.
- token/session restore.
- refresh-token sign-in/session restore should be backed by an injectable
  `InstantRefreshTokenVerifier` dependency with `.local` for deterministic CLI
  and test runs.
- sign-out.
- show current auth state.
- watch current auth state through a finite non-captive CLI command such as
  `instant-swift-data auth watch --events 1 --jsonl`.

Agent-oriented output modes are required:

- human-readable default output for local use.
- `--json` for single JSON documents.
- `--jsonl` for event streams and validation evidence.
- stable non-zero exit codes for auth failure, validation failure, network
  failure, permission rejection, decode/type rejection, and implementation
  errors.

`instant-swift-data` should support:

- initialize package scaffolding.
- generate schema and permissions from Swift with structured local evidence, for
  example `instant-swift-data schema generate --example todos --to instant.schema.ts --json`
  and `instant-swift-data perms generate --example todos --to instant.perms.ts --jsonl`,
  plus the validation fixture pair with `--example validation`.
- push/pull schema and permissions.
- create ephemeral test app.
- run admin query.
- run admin transact.
- seed examples.
- reset examples.
- run local Swift validation evidence, including
  `instant-swift-data validation local-todos --jsonl` and
  `instant-swift-data validation local-integrations --jsonl`, plus Reminders,
  CloudKitDemo-style sharing, live session protocol smoke, server transaction
  loopback, typed draft, platform adapter, and SyncUps recording evidence via
  `instant-swift-data validation reminders --jsonl`,
  `instant-swift-data validation cloudkit-demo --jsonl`,
  `instant-swift-data validation live-session --jsonl`,
  `instant-swift-data validation live-transaction --jsonl`,
  `instant-swift-data validation server-transaction-loopback --jsonl`,
  `instant-swift-data validation typed-drafts --jsonl`,
  `instant-swift-data validation platform-adapters --jsonl`, and
  `instant-swift-data validation syncups-recording --jsonl`; detailed parity
  provenance is available through
  `instant-swift-data validation parity-report --jsonl`, while
  `instant-swift-data validation coverage --jsonl` emits a compact summary gate.
  When `INSTANT_SWIFT_DATA_COVERAGE_ARTIFACTS_DIR` or
  `INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR` points at credentialed
  `typescript-swift-boundary.jsonl` and `swift-typescript-boundary.jsonl`
  artifacts, that gate should promote the two real live-transport records from
  blocked to adapted. The e2e harness should archive that post-boundary gate as
  `swift-coverage-final.jsonl`. Swift runtime code should apply live
  `refresh-ok` payloads through `InstantRuntime.applyLiveRefresh(_:)`, mapping
  server attribute ids onto declared local schema identities, publishing query
  observers, advancing the processed transaction checkpoint, and confirming a
  matching optimistic outbox mutation only after the server refresh has been
  committed locally, while replaying remaining local outbox writes so newer
  optimistic edits stay visible.
  The TypeScript-to-Swift live observe validation must go past raw WebSocket
  receipt: when the target `refresh-ok` arrives, it should apply the payload to
  a Swift runtime cache and emit cached entity/text evidence in the JSONL row.
  The TypeScript runner should keep validating Swift-authored transport evidence,
  including `--swift-transport-contract`,
  `--swift-local-integrations-contract`, `--swift-live-session-contract`, and
  `--swift-live-transaction-contract`, so local protocol and room-contract drift
  is visible before remote push/pull is complete.
  The platform adapter stream covers binding plus `@FetchAll` dynamic reload,
  nil-query, cached-prior-error, cancellation-cleanup, optional `@FetchOne`
  dynamic and nil-query reloads, `@Fetch` request dynamic reload, nil request
  reset, cancellation cleanup, live wrapper dynamic replacement/cancellation,
  topic/file/stream/share wrapper cancellation cleanup, `@ConnectionStatus`
  streaming state changes, and `@FetchAll`/`@Fetch` filtered reload behavior.
- run Swift/TypeScript parity suites.
- run credential-free Swift/TypeScript transport-contract validation in both
  local directions: Swift outbox payloads consumed by TypeScript, and
  TypeScript-authored server transaction operation tuples consumed by
  `instant-swift-data validation server-transaction-loopback --jsonl` via
  `INSTANT_SWIFT_DATA_TYPESCRIPT_SERVER_TRANSACTION_CONTRACT`.
- run benchmarks.
- inspect local SQLite cache, including namespace summaries, attributes, and
  triples with commands such as `instant-swift-data cache inspect`,
  `instant-swift-data cache attributes todos --json`, and
  `instant-swift-data cache triples todos --jsonl`.
- inspect durable local IDs with commands such as
  `instant-swift-data local-id get todos.viewer --json` and
  `instant-swift-data local-id list --json`.
- inspect local runtime connection status with
  `instant-swift-data connection status --json`.
- exercise local connection lifecycle output with
  `instant-swift-data connection close --json` and
  `instant-swift-data connection connect --json`.
- inspect pending mutation outbox.
- replay or drain pending mutations, including fixed transaction-id admin writes
  that de-duplicate exact pending replays and reject mismatched operations.
- print decoded query results.
- produce JSONL evidence for CI.
- persist local room presence and topic messages after sign-in or with
  explicit `--user-id` commands such as:
  `instant-swift-data rooms presence set chat lobby --value '{"name":"Ada"}'`
  and
  `instant-swift-data rooms topics publish chat lobby sendEmoji --value '{"emoji":"wave"}'`;
  finite local snapshot watches such as
  `instant-swift-data rooms presence watch chat lobby --events 1 --jsonl` and
  `instant-swift-data rooms topics watch chat lobby sendEmoji --events 1 --jsonl`
  must stay non-captive until transport-backed subscriptions arrive.
- persist local file metadata and copied content after sign-in with commands
  such as `instant-swift-data files upload ./photo.jpg --content-type image/jpeg`
  `instant-swift-data files list --json`, and
  `instant-swift-data files read <file-id> --json`; prove local upload progress with
  `instant-swift-data files upload-progress ./photo.jpg --content-type image/jpeg --jsonl`
  and local metadata observation with
  `instant-swift-data files watch --events 1 --jsonl`.
- persist ordered local stream chunks after sign-in with commands such as
  `instant-swift-data streams append chat/lobby --value '{"text":"hello"}'`
  and `instant-swift-data streams read chat/lobby --after-index 0 --json`;
  prove local chunk observation with
  `instant-swift-data streams watch chat/lobby --after-index 0 --events 1 --jsonl`.
  Treat `after-index` as a local JSON-chunk cursor.
- persist local byte-offset stream metadata and UTF-8 content after sign-in with
  commands such as `instant-swift-data streams create chat-session`,
  `instant-swift-data streams append-content <stream-id> --content 'Hi ' --offset 0`,
  `instant-swift-data streams read-content --client-id chat-session --byte-offset 3`,
  and `instant-swift-data streams close <stream-id> --abort-reason done`.
  This proves local `$streams`-style `clientID`, `done`, `size`, and
  `abortReason` metadata plus offset validation; live Instant stream transport,
  reconnect, and transport backpressure remain a dedicated follow-up slice.
- persist local share metadata, memberships, accept, and revoke flows after
  sign-in with commands such as
  `instant-swift-data shares create remindersLists list-1`,
  `instant-swift-data shares accept <token>`, and
  `instant-swift-data shares revoke <share-id>`.
- reject reader and non-member writes to active local shared roots before local
  cache/outbox persistence, and reject reader attempts to mint a second owner
  share for the same active root. The local guard must cover direct root writes,
  same-transaction-id replays, namespace-less deletes, declared relationship
  targets, unresolved source lookups with shared ref targets, unresolved
  primary-key lookup ref targets, cascade-expanded delete targets, and
  undeclared namespace-prefixed attributes, for example
  after sharing a todo root, accepting as a reader, and running
  `instant-swift-data examples todos update <todo-id> "reader edit"`.
- promote and demote accepted non-owner share members between reader and writer
  roles with owner-only commands such as
  `instant-swift-data shares role <share-id> <user-id> writer`; writers must be
  able to mutate active shared roots, while demoted readers are rejected before
  local cache/outbox persistence and share ownership/duplicate-share creation
  remains owner-only.
- run the first local Reminders port slice with commands such as
  `instant-swift-data examples reminders add-list "Family"`,
  `instant-swift-data examples reminders add <list-id> "Pack lunch"`, and
  `instant-swift-data examples reminders list --refresh --jsonl`; reminder child
  mutations carry their list ref so the local shared-list guard can reject
  readers before cache/outbox persistence until containment-aware permissions land.
- tag and search Reminders locally with commands such as
  `instant-swift-data examples reminders add-tag <reminder-id> family`,
  `instant-swift-data examples reminders search "Pack" --tag family --json`,
  and `instant-swift-data examples reminders tags --jsonl`; this is a durable
  Instant-shaped many-ref tag/search slice. The runnable SwiftUI app now exposes
  live substring and exact-tag search, while exact SQLite FTS ranking/snippet
  presentation remains a documented reference difference.
- delete Reminders locally with commands such as
  `instant-swift-data examples reminders delete <reminder-id>`,
  `instant-swift-data examples reminders delete-completed --list-id <list-id>`,
  and `instant-swift-data examples reminders delete-list <list-id>`; reminder
  deletes reassert list membership for shared-list permission checks, and list
  deletes prove local cascade cleanup through the triple store.
- create and filter richer Reminders fields locally with commands such as
  `instant-swift-data examples reminders add <list-id> "Pack lunch" --due-date "$(date -u +%F)" --priority high --flagged`,
  `instant-swift-data examples reminders list --scheduled --json`,
  `instant-swift-data examples reminders list --today --json`, and
  `instant-swift-data examples reminders list --flagged --priority high --json`;
  due dates use Instant date values, priority uses the upstream integer rank in
  Instant triples while the CLI keeps stable `low`/`medium`/`high` names, and
  filtered views default to incomplete reminders like the upstream Reminders
  predicates.
- inspect upstream-style Reminders smart-list stats with
  `instant-swift-data examples reminders stats --json`; the local counts expose
  all incomplete, completed, flagged, scheduled, and today reminders, and
  flagged/scheduled/today follow the upstream incomplete-only predicates.
- exercise the local Reminders form model through core tests and
  `instant-swift-data validation reminders --jsonl`; the model supports nil-id
  create drafts, `Draft(existing)`-style edit flows, due-date toggling,
  duplicate-safe selected tags, and full tag-link replacement for edit/create
  flows.
- exercise runtime-backed Reminders search and detail models through core tests;
  `SearchRemindersModel` ports upstream basics/show-completed/delete-completed,
  tag suggestions, tag-token search, tab-created near tokens, and aged completed
  deletion, plus loading/error state that preserves previous rows on load
  failure,
  and `RemindersDetailModel` ports list detail rows, due-date/priority/title
  ordering, show-completed toggling, move-to-manual position persistence, and
  upstream smart-list/tag detail filters with the same load-state contract.
- run the first local SyncUps port slice with commands such as
  `instant-swift-data examples sync-ups add "Design" --seconds 900 --theme appOrange --attendee Blob`,
  `instant-swift-data examples sync-ups edit <sync-up-id> --title "Design Review" --attendee Blob`,
  `instant-swift-data examples sync-ups delete-attendee <attendee-id>`,
  `instant-swift-data examples sync-ups add-attendee <sync-up-id> "Blob Jr"`,
  `instant-swift-data examples sync-ups record <sync-up-id> --transcript "Reviewed launch risks."`,
  `instant-swift-data examples sync-ups record-demo <sync-up-id>`,
  and `instant-swift-data examples sync-ups delete-meeting <meeting-id>`;
  sync-up attendee and meeting records are linked children with cascade delete
  and shared-root role checks; deleting the final attendee creates a blank
  replacement attendee, matching the upstream form model. The local
  `record-demo` path must use Sendable speech, sound, and open-settings
  dependency clients with reusable `.local` instances so the terminal demo
  proves the same effect seams that the eventual SwiftUI recording flow uses.
- run the local Instant auth recipe port with
  `instant-swift-data examples auth status`,
  `instant-swift-data examples auth send-code user@example.com`,
  `instant-swift-data examples auth verify-code user@example.com <code>`,
  `instant-swift-data examples auth watch --events 1 --jsonl`, and
  `instant-swift-data examples auth sign-out`; the port uses the same
  `InstantMagicCodeExchange` Swift Dependencies seam as app auth, preserves the
  upstream signed-out login/code-entry versus signed-in dashboard state, and
  preserves Instant's standard authenticated-user identity fields, including
  `user.email`, in the durable `InstantAuthSession`.
  The terminal `send-code` output represents the transient code-entry step that
  the React recipe keeps in component state.
- run the local app-builder port with
  `instant-swift-data examples app-builder generate "Build a Tic Tac Toe game"`,
  `instant-swift-data examples app-builder list`,
  `instant-swift-data examples app-builder show <build-id>`,
  `instant-swift-data examples app-builder append <build-id> --code <text> --reasoning <text>`,
  `instant-swift-data examples app-builder finish <build-id>`, and
  `instant-swift-data examples app-builder reset`; generation requires the
  email-backed magic-code auth session from `examples auth`, creates a local
  platform app through the reusable `InstantPlatformAppClient.local` Swift
  Dependencies seam at `DependencyValues.instantPlatformAppClient`, streams
  local reasoning/code through `AppBuilderCodeGeneratorClient.local` via
  `DependencyValues.appBuilderCodeGenerator`, uploads the generated `App.tsx`
  into local `$files` storage, links it from the build, preserves the upstream
  owner-linked `builds` schema plus schema-visible `$files`, keeps list queries
  owner-filtered, and keeps `show` as an id-only route query.
- run the local Instant website-style chat port with
  `instant-swift-data examples chat seed`,
  `instant-swift-data examples chat channels`,
  `instant-swift-data examples chat post <channel-id> "hello"`,
  `instant-swift-data examples chat messages <channel-id> --jsonl`, and
  `instant-swift-data examples chat reset`; messages are linked to channels,
  signed-out posts auto-create a local guest session, and posts after
  `instant-swift-data auth token <refresh-token> --user-id <user-id>` preserve
  logged-in author attribution across CLI launches.
- run the local Instant website-style microblog port with
  `instant-swift-data examples microblog seed`,
  `instant-swift-data examples microblog feed --jsonl`,
  `instant-swift-data examples microblog setup-profile "Display Name" <handle>`,
  `instant-swift-data examples microblog post "hello"`,
  `instant-swift-data examples microblog like <post-id>`,
  `instant-swift-data examples microblog unlike <post-id>`,
  `instant-swift-data examples microblog delete-post <post-id>`, and
  `instant-swift-data examples microblog reset`; `$users`, profiles, posts, and
  likes are linked with the upstream cascade shape, and profile/post/like
  mutations require an auth session from
  `instant-swift-data auth token <refresh-token> --user-id <user-id>`.
- run the local Instant mobile chat port with
  `instant-swift-data examples mobile-chat seed`,
  `instant-swift-data examples mobile-chat channels`,
  `instant-swift-data examples mobile-chat setup-profile "Display Name"`,
  `instant-swift-data examples mobile-chat send <channel-id> "hello"`,
  `instant-swift-data examples mobile-chat messages <channel-id> --jsonl`,
  `instant-swift-data examples mobile-chat join <channel-id>`,
  `instant-swift-data examples mobile-chat presence <channel-id>`,
  `instant-swift-data examples mobile-chat leave <channel-id>`, and
  `instant-swift-data examples mobile-chat reset`; `$users`, `$files`,
  profile-linked messages, channel-filtered message queries with nested
  author/user includes, optional author links, and `chat` room presence preserve
  the React Native example shape, while seed/profile/reset are explicit local
  terminal conveniences because upstream ships no app-data bootstrap. Reset
  clears mobile chat channels, profiles, messages, and presence while preserving
  shared auth and `$users` system state.
- run the local Instant Stroopwafel port with
  `instant-swift-data examples stroopwafel setup-profile <handle>`,
  `instant-swift-data examples stroopwafel create-room [code]`,
  `instant-swift-data examples stroopwafel join <code>`,
  `instant-swift-data examples stroopwafel ready <code>`,
  `instant-swift-data examples stroopwafel start <code>`,
  `instant-swift-data examples stroopwafel tap <game-id> <color>`,
  `instant-swift-data examples stroopwafel games --jsonl`, and
  `instant-swift-data examples stroopwafel reset`; `$users`, rooms, games, and
  points follow jsventures/stroopwafel at
  `7f5e2379464d932c0e4681655cbf022f8d9c2614`, profile/room/game mutations
  require an auth session, host-only kick/start behavior is checked locally, and
  reset clears room/game/point state while preserving shared auth and `$users`.
- run the local Instant reactions recipe port with
  `instant-swift-data examples reactions tap <fire|wave|confetti|heart> --direction <degrees> --rotation <degrees>`,
  `instant-swift-data examples reactions list`, and
  `instant-swift-data examples reactions watch --events 1 --jsonl`; the port uses
  the upstream `topics-example/123` room, `emoji` topic, and
  `{name, directionAngle, rotationAngle}` payload while decoding only the four
  upstream reaction names and leaving durable local topic history available for
  terminal evidence.
- run the local Instant typing indicator recipe port with
  `instant-swift-data examples typing-indicator join <user-id>`,
  `instant-swift-data examples typing-indicator type <user-id>`,
  `instant-swift-data examples typing-indicator stop <user-id>`,
  `instant-swift-data examples typing-indicator list [--viewer-user-id <user-id>]`,
  `instant-swift-data examples typing-indicator watch --events 1 --jsonl [--viewer-user-id <user-id>]`, and
  `instant-swift-data examples typing-indicator leave <user-id>`; the port uses
  the upstream `typing-indicator-example/1234` room, `id` presence field, and
  `chat-input` activity field while deriving active typers only from peers whose
  `chat-input` value is `true` when a viewer id is supplied.
- run the local Instant avatar stack recipe port with
  `instant-swift-data examples avatar-stack join <user-id> [--name <name>]`,
  `instant-swift-data examples avatar-stack list [--viewer-user-id <user-id>]`,
  `instant-swift-data examples avatar-stack watch --events 1 --jsonl [--viewer-user-id <user-id>]`, and
  `instant-swift-data examples avatar-stack leave <user-id>`; the port uses the
  upstream `avatars-example/avatars-example-1234` room and `name` presence field,
  derives omitted names from the first six user-id characters, and exposes the
  upstream current-user plus peers view when a viewer id is supplied.
- run the local Instant cursors recipe ports with
  `instant-swift-data examples cursors move <user-id> --x <n> --y <n> --x-percent <n> --y-percent <n> [--color <color>]`,
  `instant-swift-data examples cursors list [--viewer-user-id <user-id>]`,
  `instant-swift-data examples cursors watch --events 1 --jsonl [--viewer-user-id <user-id>]`,
  `instant-swift-data examples cursors clear <user-id>`,
  `instant-swift-data examples cursors leave <user-id>`, and the same
  `custom-cursors` commands with optional `--name <name>` on `move`; the ports
  use the upstream `cursors-example/123` and `cursors-example/124` rooms, the
  default `<Cursors>` space key, `{x, y, xPercent, yPercent, color}` cursor
  payloads, and the custom cursor `name` presence field while exposing the
  upstream peer-only cursor view when a viewer id is supplied.
- run the local Instant merge tile game recipe port with
  `instant-swift-data examples merge-tile-game board`,
  `instant-swift-data examples merge-tile-game join <user-id> [--color <color>]`,
  `instant-swift-data examples merge-tile-game tap <user-id> <row> <column>`,
  `instant-swift-data examples merge-tile-game watch --events 1 --jsonl [--viewer-user-id <user-id>]`,
  `instant-swift-data examples merge-tile-game reset`, and
  `instant-swift-data examples merge-tile-game leave <user-id>`; the port uses
  the upstream fixed board id `83c059e2-ed47-42e5-bdd9-6de88d26c521`, a 4x4
  JSON `state` object, the `tile-game-example/_defaultRoomId` presence room,
  and the six-color palette, while `tap` deep-merges a single cell and `reset`
  replaces the full board state. Omitting `--color` deterministically chooses
  the first available palette color for terminal evidence instead of the
  browser recipe's random available-color choice.
- run local admin write/query helpers such as
  `instant-swift-data admin transact notes note-1 --merge '{"title":"admin note"}' --transaction-id tx-admin-note-1`
  and `instant-swift-data admin query notes --json` for durable terminal
  ground-truth checks; required remote validation additionally runs the
  dependency-free TypeScript admin smoke against Instant's admin query,
  transact, and SSE subscribe endpoints when credentials are supplied, while
  `--boundary-swift-live-observe` proves Swift's live WebSocket transaction is
  visible to TypeScript's admin SSE subscription on an existing app and
  `--boundary-typescript-live-observe` proves a TypeScript admin HTTP write is
  visible to Swift's live WebSocket observer and applied into the Swift cache.
  The coverage gate should only clear the two live-transport blockers after
  those concrete JSONL artifacts are present for a non-local app id.
- run example business commands directly, such as todo/reminder/sync-up/chat/mobile-chat/microblog/reactions/stroopwafel
  create, list, update, delete, share, accept, upload, and stream operations.

Example command shapes:

```bash
instant-swift-data schema generate --from Sources/AppSchema --to instant.schema.ts
instant-swift-data app ephemeral --title reminders-port
instant-swift-data admin transact reminders reminder-1 --merge '{"title":"call Ada"}'
instant-swift-data admin query reminders --json
# Future validation harness:
# instant-swift-data validate --suite reminders --evidence .evidence/reminders.jsonl
instant-swift-data benchmark --suite typeScript-parity --compare ../instant
instant-swift-data auth guest
instant-swift-data examples todos add "do the dishes" --json
instant-swift-data examples reminders list --refresh --jsonl
```

## Sharing Requirement

SQLiteData demonstrates CloudKit sharing with `CKShare`, shared records,
participants, accept metadata, and visible "shared with..." state. Instant
Swift Data must provide the Instant equivalent.

Research and implement an Instant sharing model using some combination of:

- share/root entities.
- membership/participant entities.
- roles/capabilities.
- generated permissions using `data.ref` and `auth.ref`.
- share-link entities or tokens.
- accept/revoke flows.
- visible sharing metadata in app queries.

The Reminders port must include real list sharing. A user must be able to share
a reminders list, another user must accept it, permissions must govern writes,
and both clients must observe the shared state through Instant.
The CloudKitDemo concept must include shared counter-style records with visible
share state. The local CLI slice proves this shape through `instant-swift-data
examples counters`, `examples cloudkit-demo`, and `instant-swift-data
validation cloudkit-demo --jsonl`. The runnable V3 app and
`validation/verify-cloudkit-demo-v3-app-live.sh` satisfy the real
Instant-backed Swift/TypeScript acceptance bar with exact cross-SDK values,
reader/writer permissions, role replacement, revocation, and relaunch.

## Testing And Validation

Unit tests are useful but are not the source of truth.

The acceptance proof is real execution against Instant:

- Swift writes, TypeScript observes.
- TypeScript writes, Swift observes.
- Swift offline writes update local observers immediately, remain queued while
  the connection is closed, do not appear on the TypeScript side before
  reconnect, then flush in order after reconnect.
- TypeScript writes while Swift is offline are observed by Swift after reconnect.
- All linked-entity cases cross the Swift/TypeScript boundary.
- All sharing cases cross the Swift/TypeScript boundary with two users.
- All storage/file cases cross the boundary.
- All streams cases cross the boundary.
- Presence and topic cases run with at least two clients.
- Permission failures are verified from both Swift and TypeScript paths.

Port TypeScript Instant tests into Swift through the core client and adapter
layers. Required categories include:

- store/triple indexes.
- InstaQL query resolution.
- InstaML transaction transform.
- transaction validation.
- query validation.
- schema serialization/parsing.
- pagination and cursors.
- linked/reverse/nested queries.
- cascade delete.
- date conversion.
- pending mutations.
- offline cache.
- sync table.
- auth state.
- storage.
- presence/topics.
- streams.

Port upstream Instant core tests faithfully, and add analogous tests for every
Swift client adapter. Adapter parity must be proven through the idiomatic Swift
surface that users touch: `@FetchAll`, `@InfiniteQuery`, `@FetchOne`, `@Fetch`,
projected bindings, observable models, `@LocalID`, `@AuthSession`,
`@RoomPresence`, `@RoomTopicMessages`, `@StoredFiles`, `@StreamChunks`,
`@Shares`, `AsyncSequence` subscriptions, auth/status observers,
room/presence/topic streams, storage/stream/share observers, and
paged/infinite-query helpers. Tests
should verify loading/error state, dynamic nil queries, resubscription,
cached-prior results, cleanup on cancellation, independent subscription
lifetime, dynamic infinite-query subscription/load replacement, dynamic
live-wrapper replacement, resource-wrapper task cancellation, and task
cancellation without reaching around to raw callbacks unless the test is
explicitly about the core runtime.

Port SQLiteData core and example tests faithfully for the InstantDB version.
This includes `FetchAll`, `FetchOne`, `Fetch`, `FetchSubscription`, observable
model examples, Reminders search/stats/detail/delete flows, SyncUps form
save/update behavior, CloudKitDemo sharing concepts translated to Instant
sharing, and generated `Draft` macro/write behavior. Each port should be exact
when possible and explicitly adapted when SQLite-specific behavior maps to an
Instant query, mutation, or sharing concept.

Every ported TypeScript test should record:

- original TypeScript test file.
- original test name.
- Swift test file.
- parity status: exact, adapted, blocked, or not applicable.
- reason for any adaptation.

## Macro Testing

All Swift macros must use Point-Free MacroTesting.

Rules:

- Macro tests live in their own test targets.
- Macro tests are wrapped in `#if os(macOS)`.
- Macro test targets import only the macro plugin and `MacroTesting` plus test
  framework support.
- Do not hand-write inline expansion snapshots. Let the test run generate them.
- Delete stale inline snapshots when changing assertions.

Macro acceptance includes:

- default plural namespace generation.
- redundant namespace diagnostic.
- manual namespace override.
- generated schema attributes.
- generated mutation helpers.
- generated query helpers.
- enum/discriminated-union wire validation.
- clear diagnostics for unsupported Swift shapes.

## Benchmarks

Use the current Swift benchmarking guidance on the implementation machine.
Benchmark Swift against the TypeScript client on equivalent workloads.

Required benchmark suites:

- triple insert/retract/update.
- query materialization from triples.
- nested linked query.
- reverse linked query.
- transaction transform.
- pending mutation enqueue.
- offline restore from SQLite.
- reconnect outbox drain.
- high-bandwidth scalar updates.
- high-bandwidth linked writes.
- storage metadata query.
- stream read/write throughput.

Current local progress: `instant-swift-data benchmark --suite local-todos`
records JSON/JSONL metrics for local bootstrap, triple insert/retract, todo
query materialization, pending mutation enqueue, query-cache reads, offline
SQLite restore, high-bandwidth scalar update streams, and high-bandwidth linked
write batches, storage metadata queries, stream read/write throughput, and
live-query, presence, topic, storage, and stream cancellation latency.
High-bandwidth scalar and linked samples also carry resident-memory high-water
growth and budget fields, 1k/10k/50k triple workload samples carry explicit
memory budgets, and local transact/query/cache/relaunch/outbox-flush samples
carry actor-hop breakdowns. The release-mode
`cross-sdk-core` and `cross-sdk-runtime` suites now compare 15 equivalent
logical workloads against pinned canonical TypeScript 1.0.49. The checked
baseline quantifies every current Swift gap and names a tracked optimization
target for each slower workload. The runtime suite records actor-hop breakdowns
for durable enqueue, offline restore, and reconnect drain; the fresh Todos live
gate separately records authenticated connect, accepted live mutations,
offline enqueue, and real WebSocket reconnect/drain hops. Reproduce the combined
comparison with `validation/run-cross-sdk-benchmark-comparison.sh`; inspect
`validation/benchmarks/v1-cross-sdk-performance-2026-07-19.json` for the pinned
result.

Success criterion: Swift matches or exceeds TypeScript for equivalent workloads.
If Swift is slower, the benchmark must name the reason, quantify the gap, and
create a tracked optimization target.

V1 acceptance record: `validation/verify-v1-release.sh` passed from the clean
`95bd966` revision and is bound to annotated tag `v1.0.0`. The archiveable
evidence is
`/tmp/instant-data-swift-v1-release-20260719T103430Z/evidence.json`.

## Definition Of Done

The project is done when:

- The package builds from a clean checkout.
- The CLI works from a terminal without SwiftUI.
- Swift schema generation emits TypeScript schema and permissions.
- Macro tests pass with generated snapshots.
- The Instant example ports are complete.
- The SQLiteData example ports are complete.
- Reminders sharing works through Instant.
- SyncUps works through Instant.
- CloudKitDemo's sync/share concepts have real Instant equivalents; local
  counter/share CLI proof is useful progress but not the final acceptance bar.
- TypeScript Instant tests are ported or explicitly classified.
- Swift/TypeScript real-run validation passes.
- Offline, optimistic, and reconnect behavior is proven.
- Storage, files, streams, auth, presence, rooms, and topics are proven.
- Benchmarks are checked in with reproducible commands and JSON output.
- Network rejection errors are human-readable and actionable.
- No success claim depends only on unit tests or mocks.
