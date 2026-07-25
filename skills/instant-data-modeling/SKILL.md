---
name: instant-data-modeling
description: Model Instant Swift Data schemas, entities, links, projections, typed mutations, drafts, and local-first fetch declarations. Use when adding or changing @InstantEntity models, query builders, @FetchAll, @FetchOne, @Fetch, dynamic query inputs, composite requests, includes, pagination, permissions, or V3 screen data ergonomics.
---

# Instant Data Modeling

Use `instant-data` and the Point-Free `pfw`, `pfw-sqlite-data`, and
`pfw-structured-queries` skills first.

## Inspect prior art

Read the relevant public implementation and compiling tests first, then
compare the design targets:

- `Sources/InstantSwiftData/InstantSwiftData.swift`
- `Sources/InstantSwiftData/InstantTypedAPI.swift`
- the nearest compiling fixture under `Tests/`
- `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md`
- `upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/Fetching.md`
- `upstream/sqlite-data/Sources/SQLiteData/Documentation.docc/Articles/DynamicQueries.md`
- `upstream/sqlite-data/Sources/SQLiteData/FetchKeyRequest.swift`
- the corresponding Instant TypeScript query or transaction source.

Adapt SQLiteData ergonomics to Instant semantics; do not expose SQL vocabulary
for an Instant query. Current `Sources/` and compiling fixtures win when a V3
sketch differs. Do not assume projection/fetch-builder names such as
`@InstantProjectionBuilder`, `@InstantFetchBuilder`, `InstantFetchPlan`,
`Project`, `Query`, or `Count` exist until source search proves they do.

## Model the domain

- Use typed entities, IDs, attributes, and relation tokens.
- Keep Swift schema as the source of truth for generated TypeScript schema and
  permissions.
- Model view-specific joined shapes as projections, not partial entities.
- Keep writable form state in generated drafts and preserve strict create,
  upsert, and update-existing semantics.
- Validate fields, filters, includes, order, pagination, links, and mutation
  shape before cache or outbox mutation.

## Choose a fetch by result shape

- Use `@FetchAll` for a collection.
- Use `@FetchOne` for an optional or single entity value.
- Use `@Fetch` for an aggregate or when one wrapper must vend one composite
  value.

A static declaration observes local-first automatically:

```swift
@FetchAll(Todo.query.order(.serverCreatedAt, .descending))
var todos: [Todo]
```

Do not add a task, `load`, subscribe call, or refresh method to start a static
fetch.

For dynamic input, derive one query/request value from feature state and use a
currently implemented replacement API. Do not require `Hashable` of
`InstantFetchKeyRequest`; its current public requirement is `Sendable`. Require
`Hashable` only when a specific identity API, such as SwiftUI `.task(id:)`,
actually requires it. Let the wrapper cancel the stale observation and retain
applicable cached state. Declare a dynamic entity wrapper as `@FetchAll(nil)` or
`@FetchOne(nil)`: the explicit nil key prevents a broad default query before the
real input exists, and a later nil replacement cancels and resets observation.

Do not make a request object merely because a query has search or filter input.
Use a request when rows and aggregates must form one library-owned combined
observed value. Its `combineLatest` observation emits only after every source
has emitted; it is not an atomic cross-query snapshot. Never make the feature
manually fetch, subscribe to, and merge request parts.

The current composite surface is `InstantFetchKeyRequest` plus
`InstantFetchRequest<Value>`:

```swift
struct TodoFacts: Equatable, Sendable {
  var todos: [Todo] = []
  var count = 0
}

struct TodoFactsRequest: InstantFetchKeyRequest {
  var rowsQuery: InstantEntityQuery<Todo>
  var countQuery: InstantEntityQuery<Todo>

  var fetchRequest: InstantFetchRequest<TodoFacts> {
    InstantFetchRequest(rowsQuery, countQuery) { todos, countedTodos in
      TodoFacts(todos: todos, count: countedTodos.count)
    }
  }
}

@Fetch(
  TodoFactsRequest(rowsQuery: Todo.query, countQuery: Todo.query)
)
var facts = TodoFacts()
```

A static composite detail fetch can capture an ID in `init`; that request is
fixed for the view/model lifetime and observes automatically:

```swift
struct RecordingDetail: Sendable, Equatable {
  var recording: VoiceTrailRecording?
  var transcriptions: [VoiceTrailTranscription] = []
}

struct RecordingDetailRequest: InstantFetchKeyRequest {
  var recordingID: InstantID<VoiceTrailRecording>

  var fetchRequest: InstantFetchRequest<RecordingDetail> {
    InstantFetchRequest(
      VoiceTrailRecording.query.where(
        VoiceTrailRecording.identifier == recordingID.rawValue
      ),
      VoiceTrailTranscription.query.where(
        VoiceTrailTranscription.recording == recordingID
      )
    ) { recordings, transcriptions in
      RecordingDetail(
        recording: recordings.first,
        transcriptions: transcriptions
      )
    }
  }
}

@Fetch private var detail: RecordingDetail

init(recordingID: InstantID<VoiceTrailRecording>) {
  _detail = Fetch(
    wrappedValue: RecordingDetail(),
    RecordingDetailRequest(recordingID: recordingID)
  )
}
```

If the identity must change without creating a new view/model identity, use a
replacement API that exists in the current source. Do not invent a composite
`.instantFetch` modifier or builder syntax from a design sketch.

## Preserve query semantics

Use wrappers/subscriptions for local-first cached and optimistic state.
Use `queryOnce`/`queryOnceDecoded` only for freshness-sensitive one-shot work
with an active connection, except that an explicitly injected local-only client
serves them from its local runtime by design. Do not add `queryLocal`; inject a
local-only client when the whole environment is local-only.

## Keep mutations ordinary

Send typed mutations/messages through the injected client. Let the runtime
apply optimistic state, persist the outbox, reconnect, deliver, and reconcile.
Keep call-site callbacks for the one user action; do not replay them during
passive refresh or outbox retry.

The ordinary transaction surface is enough for direct typed writes:

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

Do not call `flushPendingMutations` after the transaction. The runtime owns
outbox persistence, reconnect, and delivery; flushing is reserved for CLI,
diagnostic, test, or explicit user-visible operations.

## Verify

Test static initial observation, dynamic replacement, stale cancellation,
projection decoding, composite combination timing, optimistic updates,
rejection, and callback cardinality through the public surface.
