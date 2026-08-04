# ADR 0011: Persist the Server Attribute Set on Every Connect

- Status: Accepted
- Date: 2026-08-03
- Corrected: 2026-08-04 (see "Correction" below — the decision stands, one
  motivating measurement was wrong)
- Scope: local cache convergence, query observability, schema evolution

## Context

Instant models attributes as data. An attribute — a namespace/name pair with a
value type and an id — is a record stored alongside the triples, not a static
compile-time schema. A client can only materialize a namespace whose attributes
it holds, and `InstantRuntime.observe` refuses to register a live query for a
namespace missing from its attribute set.

The server sends the whole attribute set in `init-ok`, on every connection. This
client decoded that payload into `InstantRuntimeLiveSession.serverAttributes`
and used it for two things: rewriting outbound mutation attribute ids, and
supplying `attrs` to `applyLiveRefresh` when a `refresh-ok` or `add-query-ok`
arrived without its own. It never wrote the set to the local cache.

Attributes therefore only became durable as a side effect of a query result
arriving for a namespace the device already knew — which produced a deadlock for
every namespace it did not:

1. A namespace is added to the schema and deployed.
2. A device that synced before that has no attributes for it.
3. Observation fails schema validation and returns an empty stream without
   sending `add-query`.
4. No subscription exists, so no result arrives, so the attributes never land.
5. Return to 2, for the lifetime of the install.

Nothing errors. The device reports a healthy connection, open subscriptions, and
zero failures while serving permanently stale data.

Measured against the deployed Scribe app `e7c49961` from a cache with no prior
attributes: after one connect the client persisted zero attributes; with this
change it persisted 361 across 37 namespaces. A client that never writes them
can only ever know the namespaces its host application seeded locally.

**Who this actually bites.** An application that passes its full schema as
`initialAttributes` seeds every namespace it cares about at bootstrap, so it
never reaches the deadlock — its validation always passes and its subscriptions
always open. The exposure is real for any client that seeds nothing, seeds a
subset, or is schemaless, and for any namespace a device learns about only from
the server. See the Correction below: the motivating incident was not, in fact,
an instance of this.

## Decision

Apply the server's attribute set to the local cache immediately after the live
session opens, before anything reads the cache — matching upstream, which calls
`this._setAttrs(msg.attrs)` in its `init-ok` branch
(`upstream/instant/client/packages/core/src/Reactor.js:640`).

`InstantRuntime.applyServerAttributesWithGateHeld` runs under the operation gate
on the `connect` path, reads the server payload from the live session, and
persists through the same compare-and-swap loop the bootstrap attribute merge
uses.

**It merges; it does not replace.** Upstream replaces its whole in-memory attr
store and keeps locally minted attributes separately in `optimisticAttrs()`.
This client persists a single durable attribute set, so replacing it would
orphan every local triple and every pending mutation that references a local
attribute id. The reconciliation is the one `refresh-ok` already performs
(`InstantLiveRefreshAttributeContext`): a namespace/name pair the device already
holds keeps its local attribute id and the server's copy is discarded; only
pairs the device has never seen are added. The server's `id` attribute is
skipped because the store derives a namespace's primary key itself.

A second, smaller decision: schema validation failure in `observe` now calls
`reportIssue` in addition to recording a diagnostic. An observation that stays
empty forever is indistinguishable from a namespace with no rows, and that
silence is why this defect survived weeks of use.

## Consequences

- A device converges with the deployed schema on every connect, so a namespace
  added after its last sync becomes queryable without a reinstall.
- The attribute write is one bounded compare-and-swap on connect, and a no-op
  once converged: `attributesToMerge` is empty, so nothing is written.
- Rejected alternative — replay the `init-ok` payload through `applyLiveRefresh`
  with no computations. It reuses more code but writes a synthetic
  `processed-tx-id` into sync metadata and runs the outbox through
  `InstantOutbox.pruningConfirmed` against a transaction id the server never
  issued.
- Rejected alternative — drop the validation gate in `observe` and always
  subscribe, which is what upstream does. That is a larger behavioral change to
  a deliberate local guard; the attributes are now present before observation on
  the connect path, so the gate stops firing for this cause.

## Ownership

The application owns schema, query lifetime, and mutations; the library owns
cache and materialization
([ADR 0001](0001-application-sync-boundary.md)). A device holding the wrong
attribute set is a cache-convergence defect, so the fix belongs here and not in
any application that compensates for it.

## Tests

`Tests/InstantSwiftDataCoreTests/InstantInitialAttributeSyncTests.swift`

- The store-level statement, with no socket: applying an `init-ok` attribute set
  makes a never-seen namespace materializable, adds only unseen namespace/name
  pairs, and leaves the already-synced namespace's local attribute ids alone.
- Over a scripted socket: opening a connection persists the set durably, and a
  namespace learned from `init-ok` actually sends `add-query` instead of
  returning an empty stream.

Both socket tests fail without the call on the connect path.

## Correction (2026-08-04)

This ADR was first written claiming the defect was the cause of a specific
incident — a Mac that never claimed an iPad's screen-stream request (Scribe
issue #003). **That causal claim was wrong and is withdrawn.** The decision,
the mechanism, and the fix are unaffected.

The error was in the evidence, not the reasoning. The Mac's cache was read at
`~/Library/Application Support/InstantDB/instant_<app>.sqlite`, which held 133
attributes over 16 namespaces last written 2026-07-03 and none for
`screenStreamSessions`. That file is stale and nothing opens it. The running
application uses `~/.instant-swift-data/apps/<app>.sqlite`, which holds 466
attributes over 38 namespaces including 16 locally-seeded
`screenStreamSessions/*` attributes and 110 triples in that namespace. The
namespace was never missing, validation never failed for it, and the
subscription was never gated. After installing this version the Mac still did
not claim a probe request.

Two lessons worth keeping. First, confirm a database is the one the process has
open — `lsof -p <pid>` — before drawing conclusions from its contents; a
plausible file at a plausible path is not evidence. Second, an application that
seeds `initialAttributes` from its own schema is structurally immune to this
deadlock, so any incident in such an application should have been ruled out
against that fact immediately.

The independent evidence for the defect stands and is what justifies the
change: a clean cache connected against production persisted zero attributes
before, 361 after, and zero again with the call removed.
