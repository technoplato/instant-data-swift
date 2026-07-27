# ADR 0006: Preserve Opaque Live Query Cursors

- Status: Accepted
- Date: 2026-07-27
- Scope: Reactor page info, pagination cursors, and live query encoding

## Context

Instant's server returns pagination cursors as opaque four-element tuples.
`InstantQueryCursor` previously retained only the decoded entity ID, sort value,
and inclusivity flag. The live query encoder therefore rejected every `after`
or `before` cursor because reconstructing the server tuple from those public
fields is not safe.

The live refresh path also discarded server page info. A one-shot limited query
could locally recompute values, but it lost the authoritative `hasNextPage`
answer and could not issue the next live query. This blocks bounded infinite
queries and causes the current implementation to subscribe to an unbounded
namespace before slicing pages locally.

## Decision

A cursor decoded from live Reactor page info privately retains the exact server
tuple alongside its public typed fields. The tuple survives `Codable`, hashing,
query-result state, and cached emission persistence. Live query encoding replays
that tuple verbatim and emits `afterInclusive` or `beforeInclusive` only when
the public cursor requests inclusivity.

Before:

```swift
let next = InstantQueryPlan(
  id: "todos.next",
  namespace: "todos",
  after: page.endCursor
)
// Live encoding failed because the opaque tuple had already been discarded.
```

After:

```swift
let page = try await db.queryOnce(firstPage)
let next = InstantQueryPlan(
  id: "todos.next",
  namespace: "todos",
  after: page.pageInfo?.endCursor
)
// The next live query replays the exact cursor supplied by the server.
```

Hand-constructed cursors still support local pagination. They continue to fail
live encoding with the existing actionable error because the library will not
guess an opaque server tuple.

## Consequences

- One-shot live queries preserve authoritative server page info and typed sort
  values while retaining exact wire fidelity.
- Inclusive forward and reverse cursor queries can mirror Reactor's chunk
  coordinator without exposing the tuple as public API.
- Leading optimistic values remain locally materializable for ordinary limited
  queries; returning server page info no longer requires bounding the values to
  its start and end cursors.
- The tuple is an implementation detail and may change with the canonical
  Instant protocol without adding a second public cursor vocabulary.
- Continuous page-info observation and bounded infinite-query chunk ownership
  remain separate follow-up work.

## Verification

Focused live transport tests decode canonical server page info, preserve date
coercion, replay the exact tuple, round-trip cursors through `Codable`, and encode
both inclusive directions. Existing cursor-mismatch and remote-window tests
remain green.
