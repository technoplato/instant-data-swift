# Instant Swift Data Goals

This document is the portable goal contract for continuing the work on another
machine.

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
  `/Users/michael.lustig/Sync/tca/tools-local/instant`
- Instant website examples:
  `/Users/michael.lustig/Sync/tca/tools-local/instant/client/www/_examples`
- Instant website recipes:
  `/Users/michael.lustig/Sync/tca/tools-local/instant/client/www/pages/recipes`
- SQLiteData examples:
  `/Users/michael.lustig/Sync/tca/tools-local/sqlite-data/Examples`
- Existing Swift Instant work:
  `/Users/michael.lustig/Sync/tca/upstream-swift/swift-sharing-instant-ship`
  and `/Users/michael.lustig/Sync/tca/tools-local/instant-ios-sdk`
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

@FetchAll(Todo.query.order(\.createdAt, .descending))
var todos: [Todo]

try await db.transact {
  Todo.create(text: "Ship Instant Swift Data")
}
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

The API should avoid SQL noise. Do not expose `select`, `leftJoin`, or row-shape
machinery unless there is no cleaner Instant-shaped representation.

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
- magic-code sign-in.
- token/session restore.
- sign-out.
- show current auth state.

Agent-oriented output modes are required:

- human-readable default output for local use.
- `--json` for single JSON documents.
- `--jsonl` for event streams and validation evidence.
- stable non-zero exit codes for auth failure, validation failure, network
  failure, permission rejection, decode/type rejection, and implementation
  errors.

`instant-swift-data` should support:

- initialize package scaffolding.
- generate schema and permissions from Swift.
- push/pull schema and permissions.
- create ephemeral test app.
- run admin query.
- run admin transact.
- seed examples.
- reset examples.
- run Swift/TypeScript parity suites.
- run benchmarks.
- inspect local SQLite cache.
- inspect pending mutation outbox.
- replay or drain pending mutations.
- print decoded query results.
- produce JSONL evidence for CI.
- run example business commands directly, such as todo/reminder/sync-up/chat
  create, list, update, delete, share, accept, upload, and stream operations.

Example command shapes:

```bash
instant-swift-data schema generate --from Sources/AppSchema --to instant.schema.ts
instant-swift-data app ephemeral --title reminders-port
instant-swift-data query '{ reminders: { tags: {} } }' --admin
instant-swift-data validate --suite reminders --evidence .evidence/reminders.jsonl
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
- Swift offline writes update local observers immediately, do not appear on the
  TypeScript side before reconnect, then flush in order after reconnect.
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
