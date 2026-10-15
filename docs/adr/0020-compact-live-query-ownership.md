# ADR 0020: Live-Query Ownership Rows Carry a Compact Query ID, Not the Query's Whole Key

- Status: Accepted; ships in v1.9.11 (maintainer authorization, typed 2026-10-15: "Do 704")
- Date: 2026-10-15
- Issue: #704 (related: #654, #441, #445, #436)
- Amends: ADR 0008's table shape. Ownership itself (what it records, when it changes, what reads it) is unchanged.
- Scope: `instant_live_query_results`, `instant_live_query_triples`, the statements in `SQLitePersistenceStore` that
  read or write them, and a one-time conversion of existing stores at `bootstrap()`

## Context

ADR 0008 stores each live query's result once in `instant_live_query_results` and indexes its facts in
`instant_live_query_triples`, so a relaunched runtime knows which query still owns which fact. Migration 0011 created
the ownership table keyed by the result's `query_key`:

```sql
CREATE TABLE instant_live_query_triples (
  query_key TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  attribute_id TEXT NOT NULL,
  value_json TEXT NOT NULL,
  PRIMARY KEY (query_key, entity_id, attribute_id, value_json),
  FOREIGN KEY (query_key) REFERENCES instant_live_query_results (query_key) ON DELETE CASCADE
);
CREATE INDEX instant_live_query_triples_identity_idx
ON instant_live_query_triples (entity_id, attribute_id, value_json, query_key);
```

`query_key` is the canonical JSON of the whole InstaQL query. For a list screen it names every selected field, the
page cursor and the includes, so it is long, and every ownership row repeats it. A store copied from a device the day
this was found (SQLite `dbstat`, 4 KB pages):

| | |
|---|---|
| ownership rows | 32,555, for 40 stored results (161 results in all) |
| their values (`value_json`) | 3.7 MB |
| `query_key` per row | 1,671 bytes on average, 4,306 at most; 54.4 MB of key text in the table |
| `instant_live_query_triples` | 71.9 MB |
| its primary-key index (`sqlite_autoindex_…_1`) | 127.8 MB |
| `instant_live_query_triples_identity_idx` | 129.2 MB |
| all three | 328.9 MB |

The table is a rowid table, so its primary key is a second b-tree holding all four columns again. Both indexes
contain the key, and an index cell keeps at most about 1 KB on a 4 KB page, so most index entries spilled to an
overflow page of their own: 26,596 overflow pages in each index (for 32,555 entries), 108.9 MB each, 64.6 MB of each
unused. The store had
grown from 197 MB to 547 MB within minutes of its first connection after an upgrade, when these results were stored.

Upstream keeps the query once per entry too: `Reactor.js` keys `querySubs` by `weakHash(q)`, a 64-bit hash of the
query, and stores `q` inside the entry (`_startQuerySub`, Reactor.js, pinned `e7101761`).

## Decision

### The layout

Each stored result gets an integer id, and ownership rows carry the id instead of the key:

```sql
CREATE TABLE instant_live_query_results (
  query_id INTEGER PRIMARY KEY,
  query_key TEXT NOT NULL UNIQUE,
  triple_count INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  json TEXT NOT NULL
);
CREATE TABLE instant_live_query_triples (
  query_id INTEGER NOT NULL,
  entity_id TEXT NOT NULL,
  attribute_id TEXT NOT NULL,
  value_json TEXT NOT NULL,
  PRIMARY KEY (query_id, entity_id, attribute_id, value_json),
  FOREIGN KEY (query_id) REFERENCES instant_live_query_results (query_id) ON DELETE CASCADE
) WITHOUT ROWID;
CREATE INDEX instant_live_query_triples_identity_idx
ON instant_live_query_triples (entity_id, attribute_id, value_json, query_id);
```

- `query_id` is the result row's rowid alias. It is assigned when a key is first stored and stays with that row; an
  upsert of the same key (`ON CONFLICT(query_key) DO UPDATE`) keeps it. When a result row is deleted its ownership
  rows go with it (the cascade, as before), so an id that SQLite later reuses never points at another query's rows.
- `WITHOUT ROWID` makes the table its own primary-key b-tree, so the second copy (the autoindex) is gone. Two b-trees
  remain, one per lookup direction: by query (the primary key) and by fact (the identity index), as before.
- `query_key UNIQUE` keeps the lookup by key and the upsert's conflict target, as the old primary key did.

### What each statement does now

Every statement keeps its meaning; only how it names the result changes.

| Statement (`SQLitePersistenceStore`) | Before | After |
|---|---|---|
| a result's ownership (`liveQueryOwnershipWithoutTransaction`) | `WHERE query_key = ?` | `WHERE query_id = (SELECT query_id … WHERE query_key = ?)` |
| a save's removed and added rows (`saveLiveQueryResultWithoutTransaction`) | the key bound on every row | the id, read once after the result row is written |
| a reconciled result's rows (`replaceReconciledLiveQueryResultWithoutTransaction`) | delete and insert by key | by id |
| dropping a result (`dropLiveQueryResultWithoutTransaction`) | delete rows by key, then the result | the same, by the result's id |
| is a fact still owned (`liveQueryTripleHasOwnerWithoutTransaction`) | `query_key NOT IN (keys)` | `query_id NOT IN (SELECT query_id … WHERE query_key IN (keys))` |
| #441 when a result last showed a fact | `JOIN … ON result.query_key = owned.query_key` | `ON result.query_id = owned.query_id` |
| #445 the newest result's values for a slot | picks `owned.query_key`, ordered by time then key | picks the id, ordered by time then `result.query_key` |
| application-migration scan | `owned.query_key = result.query_key` | `owned.query_id = result.query_id` |
| bootstrap's retained entities, the id-fact repair, prune | entity columns, or delete the result row | unchanged (prune's cascade follows the id) |

A key that has no stored result has no ownership rows, before and after, so each `NOT IN` and each subquery returns
the same rows as the statement it replaces.

### The conversion

`bootstrap()` checks the ownership table's columns after the ledger migrations. When it still has `query_key` (0011's
layout), one `BEGIN IMMEDIATE` transaction:

1. creates the new results table and copies every result row into it, in key order (`query_id` 1, 2, …);
2. creates the new ownership table and copies every ownership row into it, joined to its result by key;
3. drops the old ownership table (with both of its indexes), then the old results table, renames the new tables to
   the old names (SQLite rewrites the new table's foreign key to the renamed parent), and creates the identity index;
4. records `0026_live_query_compact_ownership` in `instant_schema_migrations`, and logs what it did
   (`sqlite.live-query-ownership.compacted`: rows, results, rows without a result, milliseconds).

Properties:

- **Once, in place.** The check is one read of the table's columns; a converted store is not rewritten again. The
  check, not the ledger row, decides, because test fixtures and restores can recreate 0011's tables after the ledger
  recorded the conversion (the existing "remove the 0011 tables" migration test does).
- **Resumable.** All of it is one transaction. A process killed during it leaves the old tables as they were (SQLite
  ignores the uncommitted part of the WAL), and the next open converts again from the start.
- **No row lost.** Every result row and every ownership row whose result exists is copied as it was. An ownership row
  whose result is missing (the foreign key forbids one; none existed on the device copies checked) has no result to
  name and is not copied; the log counts such rows.
- **Nothing else changes.** The outbox, the triples, the metadata and the query cache are not touched; no revision is
  bumped, because what each read returns is the same.
- **A new store** gets 0011's tables and converts them while they are empty, in the same step.

### What is not part of this change

- **Shrinking the file.** The old tables' pages go to the store's free list and later writes reuse them; the file
  keeps its size, because these stores use no auto-vacuum. A `VACUUM` after the conversion took 2.8 s on a Mac on the
  device copy and left a 219 MB file instead of 561 MB; it rewrites the whole store at launch, so it is a separate
  decision.
- **Keys of superseded page cursors (#654).** Keys embed page cursors, so a long session can store results for cursors
  it no longer shows until prune removes them. This change makes each such row cost about 200 bytes instead of about
  10 KB; whether prune keeps up is still open.

## Alternatives

- **A 32-byte SHA-256 of the key, as a BLOB.** No rebuild of the results table, but every statement would hash the key
  in Swift, each row would hold 32 bytes instead of one to three, and the foreign key would need a new unique column
  on the results table anyway.
- **Keep the key, drop one index.** The key would still repeat on every row (54 MB of text here) and still overflow.
- **Empty the cache at the upgrade.** Its results are refetchable, but ownership is what lets a relaunched runtime
  retract what a query no longer shows (ADR 0008), and refetching costs the network and the CPU at launch. Translating
  keeps every row.

## Consequences

- Ownership costs about 200 bytes a row in two b-trees instead of about 10 KB. A SQL prototype of this conversion on a
  copy of the device store: 13.8 MB for the same 32,555 rows instead of 328.9 MB, every row and every result row
  identical before and after, 1.5 s on a Mac in one transaction.
- An existing store pays that conversion once, at its first open on v1.9.11.
- Statements that bound a 1.7 KB key once per row bind an integer.

## Verification

Filled in with the release (`docs/releases/v1.9.11.md` has the full list).
