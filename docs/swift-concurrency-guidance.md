# Swift Concurrency Guidance

This document is the concurrency contract for Instant Swift Data. It exists to
keep the core implementation correct under Swift 6 strict concurrency while
remaining performant under high-volume sync, offline replay, query observation,
and CLI use.

Official references:

- Swift strict concurrency: https://developer.apple.com/documentation/Swift/AdoptingSwift6
- Swift `Sendable`: https://developer.apple.com/documentation/Swift/Sendable
- Swift actors: https://developer.apple.com/documentation/Swift/Actor
- Swift global actors: https://developer.apple.com/documentation/Swift/GlobalActor
- Swift `SerialExecutor`: https://developer.apple.com/documentation/Swift/SerialExecutor
- Swift `AsyncStream`: https://developer.apple.com/documentation/Swift/AsyncStream
- Swift `AsyncThrowingStream`: https://developer.apple.com/documentation/Swift/AsyncThrowingStream
- Swift task cancellation: https://developer.apple.com/documentation/Swift/AsyncIteratorProtocol#Cancellation
- Xcode build settings for strict concurrency, region-based isolation, dynamic
  actor isolation, approachable concurrency, and `nonisolated(nonsending)`:
  https://developer.apple.com/documentation/Xcode/build-settings-reference

## Baseline Rule

Treat Swift concurrency as an architectural constraint, not as warnings to quiet
later. The package already uses Swift 6 language mode. New targets and CI should
keep complete strict concurrency enabled and should enable upcoming concurrency
features as soon as the supported toolchain allows them.

Prefer package or target settings equivalent to:

```swift
swiftSettings: [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("RegionBasedIsolation"),
    .enableUpcomingFeature("DynamicActorIsolation"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
```

The exact spelling can vary by Swift tools version. The requirement is that the
core package must compile cleanly under Swift 6 strict concurrency and should not
rely on relaxed checking.

## Ownership Model

Use actors for state ownership, not as decoration. Do not make every entity,
query, or outbox record an actor. Use a few coarse actors with clear ownership:

```swift
actor InstantStore {
    private var triples: TripleIndexes
    private var observers: [QueryID: QueryObserver]

    func apply(_ tx: StoreTransaction) -> [QueryEmission] {
        // Mutate EAV/AEV/VAE indexes and compute affected observer emissions.
    }

    func snapshot(for query: QueryPlan) -> MaterializedResult {
        // Read under store isolation.
    }
}

actor Outbox {
    private var pending: [PendingMutation]

    func enqueue(_ mutation: PendingMutation) async throws { ... }
    func nextBatch() -> [PendingMutation] { ... }
    func markConfirmed(_ ids: [MutationID]) { ... }
}

actor PersistenceStore {
    // Owns the SQLite connection and all SQLite state.
}

actor Transport {
    // Owns websocket/session/auth transport state.
}
```

The invariant is simple: every mutable variable belongs to exactly one actor. If
a mutable value can be written from two actors, or from an actor and nonisolated
code, the design is wrong.

## Sendable Boundaries

All values that cross actor boundaries must be `Sendable`. This includes query
plans, transaction steps, IDs, schema IR, errors, cache records, outbox records,
transport messages, storage metadata, room/presence/topic messages, and emitted
query results.

Good boundary types are immutable value types:

```swift
public struct InstantID<Entity>: Hashable, Codable, Sendable {
    public let rawValue: String
}

struct Triple: Hashable, Codable, Sendable {
    var entity: EntityID
    var attribute: AttributeID
    var value: InstantValue
    var txTime: InstantTimestamp
}

enum InstantValue: Hashable, Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case json(JSONValue)
    case ref(EntityID)
}
```

Avoid `@unchecked Sendable`. It is allowed only at narrow boundaries where a
non-Sendable implementation detail is protected by a specific actor, lock, or
custom executor. Every `@unchecked Sendable` conformance must include a comment
naming the protection mechanism that makes it correct.

## Swift Dependencies Boundaries

Use Point-Free `swift-dependencies` for effectful app seams, but keep dependency
values themselves `Sendable` and immutable. A dependency may be a value client
with `@Sendable` closures, or a handle to an actor that owns mutable state. It
must not be a hidden mutable singleton.

Concrete local/demo implementations can be exposed as extension static instances,
for example:

- `extension InstantMagicCodeExchange { public static let local = Self(...) }`
- `extension InstantAuthTokenInvalidator { public static let local = Self(...) }`

App-facing override points should still be registered through
`TestDependencyKey`/`DependencyKey` with computed `static var` dependency
values, resolved in `bootstrapInstantSwiftData`, then passed into
`InstantRuntimeConfiguration`. This keeps live, preview, test, CLI, and
non-captive terminal runs on the same concurrency path while allowing auth,
transport, sync, and storage behavior to vary by context.
Long-lived streams such as query observation and auth-session observation should
be dependency-client operations that delegate to runtime/actor owners; do not
hide mutable stream registries behind global dependency values.

## Isolation Rules

Use `nonisolated` only for pure, cheap helpers and protocol requirements that do
not touch actor-owned mutable state:

```swift
nonisolated func namespaceName(for typeName: String) -> String { ... }
```

Be explicit about `nonisolated(nonsending)`. With newer concurrency behavior,
nonisolated async functions may run on the caller's actor by default unless the
function is explicitly concurrent. That is useful for lightweight helpers that
should not force Sendable transfer, but it is not a way to move heavy work off
the main actor.

Use `nonisolated(nonsending)` for async helpers that are logically caller-bound:

```swift
nonisolated(nonsending)
func validate(_ plan: QueryPlan) async throws -> ValidatedQuery { ... }
```

For CPU-heavy work that must not inherit caller isolation, use an explicit
concurrent boundary, detached task, or custom executor path. Do not assume that
`async` means "off actor".

## Actor Suspension

Do not suspend an actor while its invariants are partially updated. Split work
into isolated mutation phases and nonisolated or separate-actor I/O phases.

Prefer:

```swift
actor InstantStore {
    func preparePersistenceBatch(after tx: StoreTransaction) -> PersistenceBatch {
        self.apply(tx)
        return PersistenceBatch(/* immutable snapshot */)
    }
}

actor PersistenceStore {
    func write(_ batch: PersistenceBatch) async throws {
        // SQLite write confined here.
    }
}
```

Avoid:

```swift
actor InstantStore {
    func applyAndPersist(_ tx: ServerTx) async throws {
        apply(tx)
        try await sqlite.write(...)
    }
}
```

The second shape suspends the store actor after mutation and before persistence
has completed. That can be correct only with very careful invariant design; use
it rarely and document why it is safe.

## Snapshot Before Crossing Actors

Never export actor-owned mutable state. Cross actor boundaries with immutable
snapshots:

```swift
actor InstantStore {
    func changesForPersistence(after tx: StoreTransaction) -> PersistenceBatch {
        self.apply(tx)
        return PersistenceBatch(/* value snapshot */)
    }
}
```

A method like `persist(indexes: TripleIndexes)` is suspicious if `TripleIndexes`
is reference-backed or mutable. The receiving actor should get a stable value,
not a handle into another actor's state.

## Query Observation

Expose live queries through `AsyncSequence`-shaped APIs or observation wrappers,
while keeping registration and invalidation isolated to the store actor.

Use bounded buffering for high-frequency streams:

```swift
AsyncThrowingStream<QueryEmission, Error>(bufferingPolicy: .bufferingNewest(1)) {
    continuation in
    // Register continuation under InstantStore isolation.
}
```

Unbounded streams are not acceptable for sync feeds, query invalidation,
presence, topics, or storage progress. They can turn reconnect, bulk import, or
high-bandwidth writes into memory growth bugs.

Observer cancellation must unregister from the owning actor. Every live query,
room subscription, topic subscription, stream reader, and storage progress
subscription needs a deterministic cancellation path.

## MainActor Boundary

Keep `@MainActor` out of `InstantSwiftDataCore`, `InstantSwiftDataSchema`, and
`instant-swift-data`. The core must work in apps, CLI commands, validation
runners, benchmarks, and server-like environments.

Use `@MainActor` only in UI adapters and examples:

```swift
@MainActor
@Observable
final class TodoListModel {
    private let db: InstantDatabase
    var todos: [Todo] = []

    func start() {
        Task {
            for try await emission in db.observe(Todo.query) {
                self.todos = emission.values
            }
        }
    }
}
```

Core engine APIs must not require SwiftUI and must not assume main actor
isolation.

## Task Ownership

Every long-lived task needs an owner and cancellation path. Store tasks inside
the actor or runtime object that owns the work:

```swift
public final class InstantDatabase: Sendable {
    private let runtime: RuntimeActor

    public func connect() async throws {
        try await runtime.connect()
    }

    public func close() async {
        await runtime.close()
    }
}

actor RuntimeActor {
    private var transportTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?

    func close() {
        transportTask?.cancel()
        flushTask?.cancel()
        transportTask = nil
        flushTask = nil
    }
}
```

Avoid fire-and-forget `Task {}`. If a task survives past the current call stack,
it must be stored, cancellable, and included in teardown.

## Performance Rules

Avoid actor-hop-per-triple designs. Batch across actor boundaries:

```swift
let emissions = await store.apply(serverTransaction)
await delivery.emit(emissions)
```

Do not do this in hot paths:

```swift
for triple in triples {
    await store.insert(triple)
    await observers.recompute()
}
```

Actor hops are not free. Store mutation, query invalidation, persistence batch
creation, and outbox draining should operate on batches wherever possible.

If SQLite or file I/O blocks synchronously, isolate that blocking work to a
persistence actor or a custom serial executor. Do not block the main actor, and
do not put long blocking I/O on actors that need to remain responsive for query
observation or transport.

## Validation Requirements

Concurrency compliance is part of acceptance. Add tests and validation scripts
that prove:

- The package builds under Swift 6 strict concurrency with no warnings treated as
  acceptable debt.
- No core API requires `@MainActor`.
- Concurrent `transact` calls preserve deterministic outbox order.
- Transport updates and local optimistic writes racing produce deterministic
  store state.
- Observer cancellation removes registrations and releases continuations.
- Offline restart restores pending mutations before reconnect.
- Reconnect drain batches mutations without actor-hop-per-mutation behavior.
- High-bandwidth scalar and linked writes stay within memory-growth budgets.

The review rule is: every mutable variable has one actor owner, every cross-actor
value is `Sendable`, every suspension point preserves actor invariants, every
long-lived task is cancellable by its owner, and every high-volume path batches
actor crossings.
