# Plan: cut pure CPU and disk waste from the write path, with nothing a person can see changing (#653, #669)

- **planId:** `2026-10-10-energy-98-write`
- **agentId:** `claude-opus-5.5-energy-98-write` (a helper of the energy-98 coordinator)
- **Role:** mower. The same durable, visible result for less CPU and fewer bytes written; no feature removed.
- **Branch:** `agent/claude/energy-98-write`, from `agent/claude/energy-98` at v1.9.8 (`61b9c226`).
- **Goal (the user, verbatim, 2026-10-10 23:09):** "We want all of our functionality but to reduce and eliminate any
  waste or spurious processor etc behavior" "Don’t remove any functionality, fix the underlying problems"
- **Issues:** #653 (the write path, measured on 1.9.8), #669 (the energy-98 umbrella)

## Steps (no code here), each a red test commit, then the fix, each measured before and after

1. SQLite: a bounded 2 MiB page cache instead of none, and memory released on a memory warning instead of after every
   save.
2. Prepared statements reused per connection (a bounded cache keyed by SQL text, reset after use, finalized on close).
3. A written value identical to the stored one changes no row and adds nothing to the rollback; the outbox body sent to
   the server is unchanged.
4. An observer is not handed a result equal to the last one it was handed (upstream `Reactor.js` `notifyOne`).
5. The server's echo of a result this device already holds is not processed again in full.

Touching `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`, `TripleIndexes.swift`, `InstantStore.swift`,
`InstantRuntime.swift`, `InstantLiveRefreshApplication.swift`, and new
`Tests/InstantSwiftDataCoreTests/InstantWritePathEnergyTests.swift`, added 2026-10-10 23:40 EDT.
