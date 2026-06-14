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
    real-run assertions.
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
- `stroopwafel`: multiplayer game shape using presence/topics/permissions.
- `app-builder`: schema, storage, platform/tooling concepts where applicable.

### Instant Recipes

Port the recipes from `client/www/pages/recipes`:

- todos.
- auth.
- cursors.
- custom cursors.
- reactions via topics.
- typing indicator via presence.
- avatar stack via presence slices.
- merge tile game using `merge` and multiplayer presence.

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
  omitted so the client can allocate the Instant id at save time.
- Generated drafts should include only writable stored fields, should not emit
  the managed Instant id as a normal attribute assignment, and should not conform
  to `Identifiable` by default. UI examples may add their own stable local
  editing identity when needed.

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
  strict `create`/`updateExisting` guarantees intact.
- Preserve `ruleParams` operations in the pending outbox for transport lowering.
  Rule params affect server-side permission evaluation and should not mutate
  local materialized entities optimistically.
- Pending mutations should expose a deterministic Instant-shaped transport
  projection so agents can inspect `txSteps` before real WebSocket sync is
  available.
- Mutation transport should be an injectable Sendable client so local demos,
  tests, previews, and future live WebSocket transport share the same
  send/ack/failure application path.
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
  non-captive proof until transport-backed auth is implemented.
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
  and `instant-swift-data perms generate --example todos --to instant.perms.ts --jsonl`.
- push/pull schema and permissions.
- create ephemeral test app.
- run admin query.
- run admin transact.
- seed examples.
- reset examples.
- run local Swift validation evidence, including
  `instant-swift-data validation local-todos --jsonl` and
  `instant-swift-data validation local-integrations --jsonl`, plus typed
  draft, platform adapter, and SyncUps recording evidence via
  `instant-swift-data validation typed-drafts --jsonl`,
  `instant-swift-data validation platform-adapters --jsonl`, and
  `instant-swift-data validation syncups-recording --jsonl`.
- run Swift/TypeScript parity suites.
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
  and `instant-swift-data streams read chat/lobby --json`; prove local chunk
  observation with `instant-swift-data streams watch chat/lobby --events 1 --jsonl`.
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
  Instant-shaped many-ref tag/search slice, not the full upstream FTS/highlight
  search UI yet.
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
  due dates use Instant date values, priority is a local Swift enum encoded as a
  string for now, and filtered views default to incomplete reminders like the
  upstream Reminders predicates.
- inspect upstream-style Reminders smart-list stats with
  `instant-swift-data examples reminders stats --json`; the local counts expose
  all incomplete, completed, flagged, scheduled, and today reminders, and
  flagged/scheduled/today follow the upstream incomplete-only predicates.
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
- run local admin write/query helpers such as
  `instant-swift-data admin transact notes note-1 --merge '{"title":"admin note"}' --transaction-id tx-admin-note-1`
  and `instant-swift-data admin query notes --json` for durable terminal
  ground-truth checks until real Instant admin transport is available.
- run example business commands directly, such as todo/reminder/sync-up/chat
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
surface that users touch: `@FetchAll`, `@FetchOne`, `@Fetch`, projected
bindings, observable models, `@LocalID`, `@AuthSession`, `@RoomPresence`,
`@RoomTopicMessages`, `@StoredFiles`, `@StreamChunks`, `@Shares`,
`AsyncSequence` subscriptions, auth/status observers, room/presence/topic
streams, storage/stream/share observers, and paged/infinite-query helpers. Tests
should verify loading/error state, dynamic nil queries, resubscription,
cached-prior results, cleanup on cancellation, independent subscription
lifetime, and task cancellation without reaching around to raw callbacks unless
the test is explicitly about the core runtime.

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
carry actor-hop breakdowns. Swift/TypeScript comparison and live transport
actor-hop counts remain future benchmark work.

Success criterion: Swift matches or exceeds TypeScript for equivalent workloads.
If Swift is slower, the benchmark must name the reason, quantify the gap, and
create a tracked optimization target.

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
- CloudKitDemo's sync/share concepts have real Instant equivalents.
- TypeScript Instant tests are ported or explicitly classified.
- Swift/TypeScript real-run validation passes.
- Offline, optimistic, and reconnect behavior is proven.
- Storage, files, streams, auth, presence, rooms, and topics are proven.
- Benchmarks are checked in with reproducible commands and JSON output.
- Network rejection errors are human-readable and actionable.
- No success claim depends only on unit tests or mocks.
