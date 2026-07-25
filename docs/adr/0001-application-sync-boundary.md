# ADR 0001: Application and Synchronization Boundary

- Status: Accepted
- Date: 2026-07-25
- Scope: Instant Swift Data clients, examples, and integrating applications

The upstream semantics were rechecked on 2026-07-25 against Instant
`origin/main` at `a57ca801` (2026-07-24) and SQLiteData `origin/main` at
`63a2ff6` (2026-07-24). The vendored checkouts provide the local source pointers
below; the relevant upstream behavior is unchanged at those current revisions.

## Context

Instant Swift Data is local-first, but local-first is a runtime guarantee rather
than a second application API. Earlier sketches exposed enough cache, outbox,
subscription, and flush mechanics that a normal feature could accidentally
become a synchronization coordinator. That creates two sources of lifecycle
truth: the feature and the library.

SQLiteData demonstrates the desired application shape. A feature declares a
result with `@FetchAll`, `@FetchOne`, or `@Fetch`; the reader owns observation.
Dynamic input replaces the reader's key. A request object is used when one
reader must vend one composite value, not whenever a query has inputs.

Instant's TypeScript client establishes an important distinction:

- `subscribeQuery` immediately emits a previous cached result when available,
  then registers the callback and starts the server subscription
  (`upstream/instant/client/packages/core/src/Reactor.js`, `subscribeQuery`).
- optimistic query materialization applies persisted pending mutations over the
  server-backed store (`Reactor.js`, `dataForQuery`).
- pending mutations are persisted, ordered, and resent after authentication or
  reconnection (`Reactor.js`, `pushOps`, `_sendMutation`, and
  `_flushPendingMessages`).
- `queryOnce` is a strict one-shot operation for a live client. The public
  documentation says it can use local data while connected, but it
  intentionally fails when offline or when no active client connection exists
  so stale data is not presented as fresh. An explicitly configured local-only
  client is the exception: it serves the same API from its local runtime by
  design (`upstream/instant/client/packages/core/src/index.ts`, `queryOnce`,
  and `Reactor.js`, `queryOnce`).

The Swift API must preserve that distinction without adding a public
`queryLocal` escape hatch.

## Decision

### Applications own domain intent

An application knows and declares:

- its schema, entities, links, projections, and permissions;
- which query a feature observes and the lifetime of that observation;
- dynamic query inputs such as search text, scope, pagination, and identity;
- mutations and the user intent that initiated them;
- auth, sharing, rooms, presence, topics, files, and other product capabilities;
- explicit user-visible operations such as retry, refresh, or diagnostics.

A normal feature does not know whether a value came from SQLite, memory, a
server refresh, an optimistic write, an outbox replay, or a reconnect.

### The library owns synchronization mechanics

Instant Swift Data owns:

- the local cache and private materialization engine;
- immediate optimistic observer updates;
- durable, ordered outbox persistence;
- connection recovery and query resubscription;
- mutation delivery, acknowledgement, rollback, and retry;
- server refresh reconciliation without erasing newer optimistic state;
- cancellation and replacement of stale observations;
- isolation of a rejected query, mutation, stream, or media operation from
  unrelated observations and delivery lanes.

These responsibilities remain behind ordinary query and mutation APIs. They are
not reimplemented in app reducers, models, views, or feature clients.

### Fetch declarations observe local-first automatically

A static declaration starts local-first observation without a view task, manual
`load`, explicit subscribe call, or merge loop:

```swift
@FetchAll(
  Todo.query.order(.serverCreatedAt, .descending)
)
private var todos: [Todo]

@FetchOne(Todo.query.where(Todo.isCompleted == false).order(.serverCreatedAt))
private var firstIncomplete: Todo?

@Fetch(DashboardSummary())
private var summary = DashboardSummary.Value()
```

Each wrapper may emit cached and optimistic state immediately, then reconcile
as live results arrive. Its projected value exposes status and dynamic
replacement when the feature actually needs those capabilities.

The wrapper also tolerates an asynchronous composition-root bootstrap. If it is
initialized before the default client is ready, the first value read retries
automatic observation against the now-current dependency. Features still do
not add a task or a load call. Bootstrap hydrates the in-memory store from
SQLite once; declaring more queries does not reread the full database.

Dynamic input replaces the wrapper's query key and therefore its owned
observation:

```swift
@FetchAll(nil) private var rows: [RecordingListRow]

var body: some View {
  List(rows) { row in
    RecordingRow(row: row)
  }
  .instantFetch($rows, rowsQuery)
}
```

The explicit `nil` key disables initial broad observation. The feature supplies
the dynamic inputs, and the wrapper begins only when the replacement query is
non-nil. It cancels stale work, retains the applicable local-first value, and
owns the replacement subscription; replacing the query with `nil` cancels and
resets it.

`@Fetch` represents one composite observed value. Its request declaration may
contain multiple queries, but the feature must not manually fetch, subscribe,
merge, or coordinate those parts. The library owns the combination and emits
only after each source has emitted. The result is not an atomic cross-query
snapshot.

### Ordinary mutations do not flush

Application-owned entities use the injected ordinary client and typed
transaction builder:

```swift
@Dependency(\.defaultInstantSwiftData) private var db

func rename(
  _ recordingID: InstantID<VoiceTrailRecording>,
  to title: String
) async throws {
  try await db.transact {
    VoiceTrailRecording.update(
      id: recordingID,
      VoiceTrailRecording.title.set(title)
    )
  }
}
```

The feature does not call `flushPendingMutations` afterward. The transaction
enters library-owned optimistic state and the persistent outbox; the library
owns reconnect and delivery.

### One-shot queries remain freshness-sensitive

`queryOnce` and `queryOnceDecoded` are for callers that request a one-shot
result with an active connection. They may reuse applicable local state while
connected, but a live client fails offline rather than silently returning stale
data. An explicitly injected local-only client serves the one-shot API from its
local runtime. A live-client error may carry last-known cached context for
recovery or rendering.

Local-first UI and model behavior uses fetch wrappers or the ordinary
subscription API. It does not use one-shot queries as a polling loop.

### There is no public `queryLocal`

A local-only app, preview, test, or CLI injects a local-only
`InstantSwiftDataClient` and uses the same ordinary query, observation, and
mutation APIs as a live client:

```swift
try await withDependencies {
  try await $0.bootstrapLocalInstantSwiftData(
    appID: "local-preview",
    context: .test,
    initialAttributes: Todo.instantAttributes
  )
  let localOnlyClient = $0.localInstantSwiftData
  $0.defaultInstantSwiftData = localOnlyClient
} operation: {
  // Use @FetchAll, subscribe, transact, and typed messages normally.
}
```

The local-only choice is made at the dependency/bootstrap boundary. It is not a
different feature-level query vocabulary. Any direct local materializer remains
private to the runtime, or internal test support when exact core behavior must
be verified. `bootstrapLocalInstantSwiftData` populates the explicit
`localInstantSwiftData` dependency; fetch wrappers read
`defaultInstantSwiftData`, so local bootstrap does not silently redirect them.

### Flush and synchronization status are exceptional surfaces

Outbox flush, delivery status, connection details, and cache inspection are
public only where the operation itself is the product:

- CLI commands;
- diagnostics and support tools;
- tests and validation harnesses;
- explicit user-visible operations such as a Preferences "Sync now" button or
  a pending-upload indicator.

Normal features do not flush after mutations, await delivery before observing
their own optimistic changes, display internal outbox state, or decide when to
reconnect.

### Entity synchronization and media transfer are independent

Durable entity and relationship changes must continue to project, observe, and
deliver when media upload or download is slow, offline, or rejected. Media
bytes never sit on the entity synchronization critical path.

The media-cache direction is bounded LIFO:

- retain and attempt the newest eligible media first;
- cap the cache by explicit item and byte budgets;
- evict the oldest eligible cached media when a bound is exceeded;
- persist enough per-item state to retry after relaunch;
- isolate rejection and retry state per media item or stream so one bad item
  cannot stall entity delivery or unrelated media.

Metadata needed to render the recording remains an ordinary synced entity even
when its media is not currently available.

### Application targets enforce the boundary statically

Integrating repositories should add an architecture test over app and normal
feature targets. Importing `InstantSwiftData` is allowed and expected for
schema, `@Fetch*`, ordinary mutations, auth, and sharing. The check should
reject direct imports or references to:

- Instant runtime/store/materializer implementation types;
- `queryLocal` or equivalent cache-only reads;
- outbox drain/flush/confirm/fail/retry mechanics;
- transport, reconnect, and transport-level subscription
  registration/resubscription mechanics;
- manual fetch/subscribe/merge coordination for a composite value;
- synchronization coordinators injected into ordinary reducers or views.

Allow these references in live adapter targets, bootstrap/composition roots,
CLI and diagnostics targets, validation/test support, and an explicitly named
user-visible synchronization screen. Prefer symbol/import checks over banning
the bare word `sync`, which has legitimate UI and domain meanings.

## Consequences

- Feature code becomes smaller and remains valid across local-only, preview,
  test, offline, and live clients.
- Cache and transport implementations can change without feature rewrites.
- Static fetch declarations are concise; dynamic declarations expose only the
  input/lifetime decision the feature owns.
- Composite fetches cannot expose partially merged feature state.
- Strict one-shot freshness and local-first observation have different,
  documented semantics.
- Diagnostics remain possible, but their API surface does not become the
  default architecture.
- Media failures degrade media availability rather than the entire data graph.

## Rejected alternatives

- **Public `queryLocal`:** rejected because it lets normal features couple to a
  cache implementation and creates a second query semantic.
- **Feature-managed fetch plus subscribe plus merge:** rejected because the
  feature would own runtime lifecycle and could render partially updated
  composite state.
- **Manual flush after each mutation:** rejected because it defeats persistent
  outbox/reconnect ownership and makes offline behavior action-specific.
- **Media upload in the entity delivery transaction:** rejected because large
  or rejected media would block unrelated entity projection and observation.

## Verification

Library tests should prove cached initial emission, optimistic observation,
dynamic key replacement, library-owned composite combination, persisted outbox replay,
reconnect, per-operation rejection isolation, local-only dependency parity, and
media/entity independence. Integrating applications should enforce the static
target boundary described above.

The concrete Scribe adoption contract is
`docs/scribe-feature-sync-boundary.md`; its executable architecture test remains
owned by the Scribe repository.
