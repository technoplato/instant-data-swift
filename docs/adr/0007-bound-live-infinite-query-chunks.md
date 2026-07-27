# ADR 0007: Bound Live Infinite Queries with Cursor Chunks

- Status: Accepted
- Date: 2026-07-27
- Scope: Infinite queries, Reactor subscriptions, and authoritative page windows

## Context

`subscribeInfiniteQuery` previously observed a query with its limit and cursors
removed, then sliced the entire namespace in memory. That preserved local test
semantics but registered one unbounded Reactor query in production. A growing
namespace therefore increased remote result size, local materialization work,
and retained query state even when the application had loaded only one page.

ADR 0006 made the canonical server cursor tuple and page info available to the
Swift runtime. That closes the prerequisite for porting Instant's bounded
infinite-query coordinator from
`upstream/instant/client/packages/core/src/infiniteQuery.ts`.

## Decision

Live infinite queries use a dedicated actor-isolated coordinator. Local-only
runtimes retain the existing in-memory window coordinator. A live coordinator:

1. registers one limited starter query;
2. waits for the starter's authoritative server start cursor before splitting;
3. registers a limited inclusive forward chunk and a limited reverse chunk;
4. freezes a loaded chunk to an inclusive `after`/`before` interval; and
5. replaces it with the frozen interval plus the next limited chunk.

Reverse chunks use the inverted sort order and advance automatically when the
server reports another page. The application API does not change:

```swift
let pages = await db.subscribeInfiniteQuery(
  Item.query.order(Item.value).limit(20)
)
pages.loadNextPage()
```

Before, that declaration registered the equivalent of an unbounded live query:

```swift
Item.query.order(Item.value)
```

After, its live registrations remain limited or cursor-bounded:

```swift
var inclusiveStart = start
inclusiveStart.inclusive = true
var inclusiveEnd = end
inclusiveEnd.inclusive = true

Item.query.order(Item.value).limit(20) // starter
Item.query.order(Item.value).after(inclusiveStart).limit(20)
Item.query.order(Item.value).after(inclusiveStart)
  .before(inclusiveEnd) // frozen chunk
Item.query.order(Item.value).after(end).limit(20) // next chunk
```

Each chunk observer is associated with its canonical live registration key.
When a refresh is committed, the store installs that query's authoritative
page info before publishing the matching observer emission. This prevents a
bounded query from accidentally materializing unrelated rows already present
in the shared local triple store.

The limited starter may still emit locally persisted and optimistic rows before
the server responds. A locally synthesized cursor never starts live cursor
chunks because only a cursor carrying the opaque server tuple can be encoded.

## Consequences

- Live infinite-query traffic and materialization scale with loaded pages
  instead of the full namespace.
- Forward paging and leading-row capture match the upstream inclusive/exclusive
  boundaries, including duplicate sort values.
- Replacing or cancelling a chunk unregisters its exact Reactor query; final
  cancellation unregisters the starter and every active chunk.
- Page-info installation is atomic with server-backed observer publication in
  both mutation and metadata-only refresh paths.
- Local-only infinite-query behavior remains unchanged, and live starters stay
  local-first while awaiting a server cursor.
- Durable query-result ownership and triple reachability remain the separate
  R-A8 retention decision; this ADR does not choose an offline eviction policy.

## Verification

Protocol tests prove the exact starter, forward, reverse, frozen, and next-page
query shapes; reject every unbounded registration; verify automatic reverse
advancement; and compare all registered queries with their eventual removals.
The local starter regression proves an offline live configuration emits cached
rows before remote page info. The complete infinite-query, live-transport, and
Reactor parity suites pass, as does the existing store remote-page-window test.
