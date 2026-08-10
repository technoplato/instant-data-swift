# Immediate-tail outbox supersession

**Status:** Implemented for exact scalar assignments at durable enqueue
**Program:** ADR 0015 / Instant issue
[#155](https://issues.knophy.com/issues/155)  
**Parent write shape:**
[`open-segment-write-recipe.md`](./open-segment-write-recipe.md)
**Implementation:**
`InstantRuntime.performTransact`, `SQLitePersistenceStore`, and
`OutboxSameEntitySupersession.canReplaceImmediateTail`
**Integration tests:**
`InstantOutboxSupersessionIntegrationTests`

## Outcome

High-frequency writes to one open segment may replace only the **one exact
durable queue tail immediately before the newcomer**. Instant never searches
backward, groups a queue by entity, or chooses a winner using a domain payload
revision. An intervening row is a causal barrier even when an older row behind
it targets the same entity.

The ordinary write contract is unchanged:

```text
await transact = local materialization + durable outbox
```

It never means server acknowledgement. Offline writes continue to succeed.

## Why the older queue-wide policy was retired

The former `OutboxSupersessionCandidate` projection omitted facts required for
safe replacement:

- exact physical queue adjacency;
- complete normalized operations and schema cardinality;
- the predecessor rollback;
- whether a row was claimed or offered;
- lookup, precondition, link, delete, and multi-entity barriers;
- the baseline needed if the survivor later fails.

Grouping all projected rows by `(namespace, entityID)` could therefore cross a
barrier and delete causal evidence. `payloadRevisionMs` was a product field,
not durable queue order. The public projection remains for source compatibility,
but `decide`, `applying`, and `coalescing` are deprecated conservative no-ops.
They never authorize persistence changes.

## Exact eligibility

Both the predecessor and newcomer must satisfy every condition below.

### Durable tail state

The predecessor is:

- the exact last row by `(created_at_ms, mutation_id)`;
- pending;
- still carrying its optimistic overlay and rollback;
- normalized with current delivery metadata;
- `needsDelivery`;
- `ready`, never claimed, and never offered (`delivery_started = 0`);
- no larger than the fixed 8 MiB automatic-body limit.

Claim and offered state are rechecked inside the same SQLite write transaction
that replaces the row. Claim transitions do not need to bump the outbox
revision for this race to remain safe.

### Complete assignment shape

Each transaction must be a nonempty, complete assignment with:

- only concrete `.insert` operations;
- one entity ID and one namespace;
- schema-known cardinality-one, non-reference attributes;
- no duplicate attribute ID;
- the exact same attribute-ID set on predecessor and newcomer;
- the namespace primary-key attribute present exactly once, with its string
  value equal to the entity ID;
- newcomer write timestamps greater than or equal to predecessor timestamps for
  every assigned attribute;
- distinct mutation IDs in strict durable `(createdAt, id)` creation order.

This is assignment supersession, not partial-patch merging. If the predecessor
assigns fields `{id, text, wordsJSON, updatedAt}` and the newcomer omits
`wordsJSON`, they do not supersede.

## Barriers

Any failed, confirmed, claimed, offered, oversized, lookup, precondition,
retract, merge, delete, link/reference, cardinality-many, multi-entity,
different-attribute-shape, different-entity, or unrelated immediate tail is a
barrier. Instant appends the newcomer without scanning behind that row.

Malformed normalized tails are different from ordinary barriers while they
remain ready and never offered. A body within the fixed byte limit is decoded
once, durably converted to a visible failed quarantine row with the exact raw
JSON in `quarantine_json`, and the outbox revision is bumped. The enqueue then
reloads and retries. If a claimant wins after that read, quarantine aborts and
the claimed row remains an ordering barrier. Later writes do not decode or
report a quarantined body again.

## Atomic replacement and rollback

```text
read exact tail under store/outbox revisions
        |
        v
validate full assignment pair
        |
        v
peel predecessor rollback from the hot local store
        |
        v
apply newcomer and build rollback directly to pre-predecessor baseline
        |
        v
BEGIN IMMEDIATE
  recheck revisions + exact tail + pending/active/ready/never-offered
  delete predecessor body
  save newcomer body and direct rollback
  update lifecycle lineage
  bump store + outbox revisions
COMMIT
```

If any recheck loses a race, the transaction changes nothing. The runtime
reloads; a claimed tail becomes a barrier and both rows remain ordered.

The survivor rollback is direct, not a concatenated chain. Failure restores
the authoritative value or entity absence in work proportional to the current
assignment shape.

## Transaction lifecycle aliases

Every `transact` returns a transaction ID, including IDs whose physical body is
later replaced. A supersession chain therefore keeps:

- one lifecycle row naming the current survivor;
- one alias row for **every returned transaction ID** in that chain;
- one compact terminal lifecycle after acceptance or failure.

Aliases intentionally survive restart, survivor pruning, and terminal apply so
every old ID can observe the survivor's terminal result. Publication is stricter
than observation: a terminal event wakes the shared lifecycle only when its
mutation ID equals `current_mutation_id`; a delayed predecessor event is ignored.

Ordinary non-superseded mutations create no lifecycle or alias history rows.

Alias retention is append-only under the current contract. The 10,000-write
test therefore expects one durable mutation body, one lifecycle row, and 10,000
small alias rows. This bounds retained **mutation bodies and rollback graphs**,
not total durable metadata bytes. Do not claim total durable storage is bounded.
Deleting or expiring aliases would weaken old-ID observation and requires a
separate explicit retention/API decision.

## Upstream relationship

Instant TypeScript `Reactor.js` `pushTx` / `pushOps` appends each event to
`pendingMutations`; `_rewriteMutations` rewrites schema attribute IDs, not
same-entity intent. Swift deliberately diverges because its offline outbox is
durable and open-segment workloads otherwise retain many full mutation and
rollback bodies. The divergence is limited to the exact never-offered tail;
all ambiguous cases preserve upstream-style append order.

## Verification

```bash
cd /Users/laptop/Sync/instant-data-swift
swift test --filter InstantOutboxSupersessionIntegrationTests
swift test --filter OutboxSameEntitySupersessionTests
```

The integration suite covers:

- 10,000 exact offline assignments retaining one mutation body across restart;
- latest local value and survivor-only delivery;
- authoritative-baseline and entity-absence rollback;
- old-ID acceptance/failure across restart and pruning;
- append-only alias counts;
- stale predecessor publication rejection;
- failed/offered/unrelated/shape/operation/reference barriers;
- deterministic claim races at replacement and invalid-tail quarantine;
- oversized tails with zero body decode;
- corrupt normalized tails with one decode and one durable quarantine;
- ordinary mutations creating no alias history.

The legacy policy suite proves the deprecated queue-wide API is a no-op. It is
not eligibility evidence.
