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

## Status 2026-10-14 (agent 2 of #669, Claude Code session d417e89e)

Verified by running the same 59-suite filter at v1.9.8 (`61b9c226`), at this branch's tip (`c086d927`), and at the tip
without step 3, then every failure again one test at a time. The user's rule for this work, typed 2026-10-14 15:45:
"We want to make sure that we're not changing any functionality, but improving performance."

1. Kept (`bad65eaf`): the memory bound; no CPU or disk change measured.
2. Kept (`8a1f4068`): the refresh echo 3-5% fewer instructions, the whole replay 0.8%.
3. Reverted: nine `InstantFastDrainTests` that pass at v1.9.8 failed with it (a server frame that only restates or
   confirms what the device shows rebased the pending writes again: an unchanged result peeled all 120), and four
   store tests that pin a writer's stamp on an identical value. A slower drain is the opposite of this plan's goal.
   Redo only together with the drain planner, which reads a writer's stamp to tell its own writes from the server's.
4. Kept (`8d912a74`). Three tests waited for, or counted, an emission equal to the last one handed; they are brought
   in line, each with the reason. Its own test's "equal" write flipped `hasNextPage`, which a reader sees.
5. Not started. #654's page refresh (`c086d927`, plan `2026-10-11-energy-99-pages`) cuts another part of the echo's
   cost: the refresh of pages the echo cannot reach.

Touching also `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift` (the two tests of step 4), added 2026-10-14.
