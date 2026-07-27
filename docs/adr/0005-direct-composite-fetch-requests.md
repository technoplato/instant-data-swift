# ADR 0005: Direct Composite Fetch Request Execution

- Status: Accepted
- Date: 2026-07-27
- Scope: `InstantFetchRequest` actor and effect consumption

## Context

`InstantFetchRequest` already owns the load and `combineLatest` observation of
one composite value. `@Fetch` uses those operations internally, which gives
SwiftUI views and observable models automatic local-first observation.

An actor, TCA effect, or other non-property-wrapper consumer could not execute
the same request directly. Its only options were to construct an otherwise
unneeded `Fetch` wrapper or to subscribe to every child query and reimplement
the merge and cancellation lifecycle. The latter violates ADR 0001 by moving
library-owned composite observation into feature code.

## Decision

`InstantFetchRequest` exposes `load()` and `subscribe()` operations, with
overloads that accept an explicit `InstantSwiftDataClient`. The operations use
the exact load, transformation, `combineLatest`, error, and cancellation
machinery already used by `@Fetch`.

Before:

```swift
let fetch = Fetch(
  wrappedValue: RecordingFacts(),
  RecordingFactsRequest(recordingID: id)
)
let subscription = try await fetch.subscribe(using: db)
```

After:

```swift
let request = RecordingFactsRequest(recordingID: id).fetchRequest
let facts = try await request.load(using: db)
let subscription = try await request.subscribe(using: db)
```

The default overloads resolve `defaultInstantSwiftData` through Dependencies,
while the explicit overloads remain available for actors, tests, previews, and
composition roots.

## Consequences

- TCA effects and actors can consume the same composite request as `@Fetch`
  without manufacturing wrapper state.
- Child-query combination and cancellation remain library-owned.
- `InstantFetchKeyRequest` stays `Sendable`; this change does not impose a
  global `Hashable` requirement for SwiftUI task identity.
- Composite observation still emits only after every child source has emitted
  and does not claim an atomic cross-query snapshot.

## Verification

Focused public-surface tests load and subscribe to a two-query request without
a property wrapper, verify the transformed value, and exercise the existing
combined subscription lifecycle.
