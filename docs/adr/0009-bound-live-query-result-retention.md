# ADR 0009: Bound Live Query Result Retention

- Status: Accepted
- Date: 2026-07-27
- Scope: Reactor `querySubs` garbage collection and global triple reachability

## Context

ADR 0008 made each canonical live query result a durable owner of its triples.
That restored authoritative replacement after relaunch, but retained ownership
rows and their globally materialized triples indefinitely.

Instant's TypeScript Reactor configures its persisted `querySubs` with three
bounds in `upstream/instant/client/packages/core/src/Reactor.js`:

```js
gc: {
  maxAgeMs: 1000 * 60 * 60 * 24 * 7 * 52,
  maxEntries: 1000,
  maxSize: 1_000_000,
}
```

For live query results, `maxSize` is the sum of each retained result store's
triple count. Reactor unloads a key when its final subscriber leaves, while the
durable value remains eligible for later oldest-first collection.

## Decision

Apply the same age, entry, and owned-triple bounds to
`instant_live_query_results`. The Swift defaults are 52 weeks, 1,000 results,
and 1,000,000 ownership edges. Pruning runs at bootstrap and every 64 successful
live-result writes.

Retention follows these rules:

1. Every currently registered live query key is protected.
2. Reference-counted query cancellation unloads in-memory page information
   only after the final observer leaves; the durable result remains cached.
3. A query result containing an entity touched by a pending optimistic
   mutation is protected as a whole so partial update operations do not lose
   their server baseline. Direct reference targets are protected too. A
   lookup-based mutation conservatively protects all live results because its
   entity cannot be identified without applying the lookup.
4. Age uses a strict `updated_at_ms < cutoff` comparison. Entry and triple
   overflow remove the oldest unprotected rows first.
5. Removing a result deletes its ownership edges transactionally. A global
   triple is deleted only when no retained query owns its
   entity/attribute/value identity. Transaction metadata does not create a
   distinct semantic fact at that identity.
6. Ownership removal and orphan deletion advance the store revision in one
   SQLite transaction, so another runtime cannot commit against stale
   reachability state.

Active-query and pending-mutation protection keep current optimistic or server
materializations reachable. Once the final protected ownership edge is gone,
the current global materialization at that semantic identity is collectible
even when its transaction metadata is newer than the removed result.

## Consequences

- Cycling through unbounded query shapes no longer grows the durable ownership
  set without limit.
- Overlapping results count separately toward Reactor's owned-triple budget,
  but a shared global triple remains until the final ownership edge is gone.
- Active observations cannot be evicted, even when their count alone exceeds a
  configured bound.
- Pending mutations keep the complete cached query baseline needed for local
  optimistic projection; lookup-based writes prefer temporary retention over
  unsafe collection.
- Collection normally reads only ownership metadata. Full result JSON is
  decoded only for rows selected for removal, and the cached store snapshot is
  reused when its revisions match.
- Attributes are not collected by this policy. They are schema metadata rather
  than query-result ownership and remain under the existing schema lifecycle.

## Verification

Focused tests persist 1,001 unloaded keys and prove the oldest is removed at
the upstream 1,000-entry limit; prove shared ownership counts toward the
triple budget without prematurely deleting the shared global triple; pin the
strict age boundary; preserve explicitly active results; preserve a complete
baseline beneath a pending strict update; and prove final observer
unsubscription makes the durable result and its four newly orphaned triples
collectable. They also prove bootstrap and write-cadence collection, plus final
semantic-identity collection when the current materialization has newer
transaction metadata than the removed result. The store, live-transport, and
parity suites cover the surrounding persistence and lifecycle behavior.
