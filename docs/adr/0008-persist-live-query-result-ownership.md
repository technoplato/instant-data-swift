# ADR 0008: Persist Live Query Result Ownership

- Status: Accepted
- Date: 2026-07-27
- Scope: Reactor query results, authoritative replacement, and offline cache ownership

## Context

Instant's Reactor stores each subscribed query result independently in the
persisted `querySubs` object. Unsubscribing unloads that result from memory but
does not immediately erase its durable cache. A later refresh can therefore
replace the query's previous result after a relaunch.

The Swift runtime instead merged every live result into one durable triple
store and kept query ownership only in an in-memory dictionary. After a
relaunch, an authoritative empty result no longer knew which cached triples
belonged to that query, so the old rows survived forever. The in-memory map
also could not distinguish a triple shared by two durable query results.

## Decision

Persist each canonical live registration's authoritative result beside the
global store. SQLite uses a compact result row plus a normalized ownership
index:

```sql
instant_live_query_results(query_key, triple_count, updated_at_ms, json)
instant_live_query_triples(query_key, entity_id, attribute_id, value_json)
```

The JSON row retains the exact triples and optional server page information.
The normalized rows answer whether another persisted query still owns a triple
without loading every cached result into memory.

Before this decision, replacement state disappeared with the process:

```swift
let retractions = await inMemoryQueryResults.replacementRetractions(for: replacements)
try await persistence.saveStoreSnapshot(updatedStore)
```

After this decision, persisted ownership is canonical and is committed in the
same revision-checked SQLite transaction as the store, outbox, and processed
transaction checkpoint:

```swift
let retractions = try await persistence.liveQueryReplacementRetractions(
  for: replacements
)
var appliedTransaction = transaction
appliedTransaction.operations.insert(contentsOf: retractions, at: 0)
let prepared = try await store.prepare(
  appliedTransaction,
  applyingTo: durableStore
)
try await persistence.saveLiveRefresh(
  InstantPersistenceSnapshot(store: prepared.snapshot, outbox: outbox),
  queryResults: replacements.map {
    InstantPersistedLiveQueryResult(replacement: $0, updatedAt: receivedAt)
  },
  storeChanged: true,
  outboxChanged: outboxChanged,
  metadataKey: processedTransactionIDMetadataKey,
  metadataValue: processedTransactionID,
  metadataUpdatedAt: receivedAt,
  expectedStoreRevision: revision,
  expectedOutboxRevision: outboxRevision
)
```

A query-owned triple is retracted only when it is absent from the query's
replacement and no other replacement or persisted query owns the same
entity/attribute/value identity.

Persisting a result advances the store revision even when only page information
changed. That revision couples ownership to the global snapshot so another
runtime cannot commit a replacement calculated against stale ownership.
Persisted page information is loaded lazily by a relaunched live observation;
the runtime does not preload the full retained query corpus.

## Consequences

- Authoritative empty or narrowed results retract their previous cached rows
  after process relaunch.
- Overlapping query results retain a shared triple until its final durable
  owner removes it.
- Query ownership, global triples, outbox reconciliation, and the processed
  server checkpoint cannot be partially committed by a crash.
- Canonical query keys remain opaque storage keys; result triples are
  identity-normalized and encoded deterministically.
- The normalized ownership index is a prerequisite for safe orphan collection.
  Entry/age/triple-count retention, final-observer unloading, and optimistic
  write protection are the next bounded R-A8 slice rather than being implied
  by this decision.

## Verification

Focused live-transport tests seed an authoritative result, relaunch the
runtime, replace that query with an empty result, and prove both the generated
retractions and the empty durable store. A second test persists the same row
under two distinct canonical queries, relaunches, proves the first replacement
does not retract shared data, and proves the final replacement does. The full
57-test live-transport suite passes.
