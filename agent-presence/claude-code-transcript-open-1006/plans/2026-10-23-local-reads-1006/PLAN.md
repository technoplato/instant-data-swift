# Plan 2026-10-23-local-reads-1006

- **planId:** 2026-10-23-local-reads-1006
- **agentId:** claude-code/transcript-open-1006@halfjew22
- **role:** grower (user-ordered fix, issue #1006), kept small: no new public read API; the existing local reader
  client answers from the whole device store.
- **branch:** agent/claude/local-reads-1006 (worktree ~/Sync/worktrees/instant-data-swift-transcript-open-1006), pushed
  to main after each green step, then released.

## Outcome (#1006)

A read through `InstantSwiftDataClient.localReader()` answers from this device's store without waiting for the server,
a server apply, or the operation gate:

1. A one-shot local read finds every entity the device stores, also those on disk but not in memory, when its filters
   include `attribute == value` for an attribute the app names in a new lookup policy. After a relaunch the in-memory
   store holds only what stored results own and what unsent writes touch; the rest of the device's data was unreachable.
2. A local read takes no operation gate and writes no query-cache row. A read that hydrated deferred values without the
   gate waits for it only when its holder may be writing the entities it read (a holder may name them; unnamed is
   treated as everything, as today).
3. Local reads read SQLite on their own read-only WAL connection, so a server apply's commit on the persistence actor
   does not hold them up.

## Steps

1. Red tests (InstantLocalReadTests): a relaunched store's local read finds the device's on-disk rows; a local read and
   a local observation's hydration answer while a server apply holds the gate before its commit; deferred values come
   from the read connection.
2. Green: InstantLocalLookupPolicy and a partial index on instant_triples(attribute_id, value_json) ensured at open;
   SQLiteReadConnection; the local reader's one-shot read over memory and disk; AsyncSerialGate write annotation and
   its use in hydration; the server apply names its changed entities before its commit (agreed on #932).
3. Full core suite on the mini against main's baseline; measurements; CHANGELOG, PROGRESS, audit ledger; release.

## Touching

Sources/InstantSwiftDataCore/InstantRuntime.swift (local reads, hydration's gate check, configuration, one line in the
server apply), Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (ensure the lookup index at open),
Sources/InstantSwiftDataCore/AsyncSerialGate.swift, Sources/InstantSwiftDataCore/InstantStore.swift (one read-only
helper), Sources/InstantSwiftDataCore/InstantLocalLookupPolicy.swift (new),
Sources/InstantSwiftDataCore/SQLiteReadConnection.swift (new), Sources/InstantSwiftData/InstantSwiftData.swift (the
policy's parameter), Tests/InstantSwiftDataCoreTests/InstantLocalReadTests.swift (new), CHANGELOG.md, PROGRESS.md,
docs/audits/commit-changelog.md, docs/releases/ (the release document).

## Conflict check

#932 (server-apply-932) edits performApplyServerTransaction's attempt loop, the resident patch, the gate timeline and
SQLitePersistenceStore's server-apply functions: this plan adds one line before its "commit plan" phase, asked on #932,
and touches none of those functions otherwise. #1007 (hotpath-1007) edits InstantStore's publication path and
TripleIndexes' include skip: this plan only reads TripleIndexes and adds a read-only InstantStore helper.
