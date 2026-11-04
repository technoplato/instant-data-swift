# Plan 2026-11-04-newest-1748: the store's newest transaction time is kept, never walked

- planId: 2026-11-04-newest-1748
- agentId: claude-code/b1104-1748@halfjew22 (tools/agent-run, claude/halfjew22, opus)
- role: mower (the same stamps, read without walking the store; no new public surface, no behavior change)
- issue: #1748 (Scribe crashed on the iPad during Recording 364, 2026-11-04 02:46, build 245, library 1.9.64)
- branch: main, in ~/Sync/instant-data-swift (fast-forwarded to origin/main 0064aac2; Michael, Recording 349 #152:
  "Don't spin off different work trees"); rebase on origin/main before every push

## Why (measured)

iOS's CPU Monitor killed Scribe on the iPad: `Scribe Shared.cpu_resource_fatal-2026-11-04-024609.ips`, "48 seconds
cpu time over 60 seconds (81% cpu average), exceeding limit of 80% cpu over 60 seconds", "Non-Frontmost App" (Notes
was frontmost in Split View), "Action taken: Process killed". Symbolicated with build 245's dSYM: 6 of 6 samples in
`InstantRuntime.applyLiveRefresh` -> `performApplyServerTransaction` (InstantRuntime.swift:3734), 5 of 6 in
`TripleIndexes.newestTransactionTimeMilliseconds` (TripleIndexes.swift:1653). The non-fatal CPU reports of the same
night show the same getter on top: 10 of 32 samples at 01:57, 13 of 22 at 02:55 after the relaunch. Reports and
symbolicated text: ~/Sync/audit/crashes-2026-11-04-ipad-1748/.

The getter walks every entity x attribute x value. The full-rebase server apply calls it once for each pending write it
replays (forward pass and durable tail, InstantRuntime.swift:3734 and :3901), as do the refused-write successor
replays (:16738, :16881) and `localWriteStampedToWin` (:2964). A frame that replays P pending writes over a store of N
facts walks P x N: the iPad's unsent backlog made each frame slower, which grew the backlog, until the CPU Monitor
killed the app; after the relaunch the backlog drained at about 1 minute of audio per hour.

Upstream never reads the store for this: `store.ts` `getCreatedAt` stamps an optimistic triple `Date.now() * 10 +
_seed++`. Swift stamps newest + 1 to keep stamps in milliseconds; this keeps that meaning exactly and drops the walk.
`tripleCount` had the same shape and was fixed the same way (InstantStoreWriteScalingTests, 2026-08-04).

## Steps

1. This plan and its claims (plan-only commit) on main.
2. Red (InstantSwiftDataCoreTests, InstantStoreWriteScalingTests): reading the newest transaction time costs the same
   on a store 32x larger (a ratio, like the suite's other scaling tests); and the kept value equals a fresh walk after
   every kind of write: insert, a many-cardinality value, re-insert, a cardinality-one replacement, merge, retract of
   the newest fact, delete entity (with incoming refs), removal of marked deferred values, the derived-index rebuild,
   and a Codable round trip.
3. Green: TripleIndexes keeps how many facts carry each transaction time (a sharded dictionary, so a prepared copy
   copies one shard) and the newest of them; the newest is found again from the kept times (not the facts) only when
   the newest fact leaves, at the next read or write. Every writer of a stamp keeps it: insertNewCardinalityOne,
   insert, replaceCardinalityOneSlot, removeNormalized, removeEntityAttributes; the bulk rebuilds (decode,
   rebuildDerivedIndexes) recount. Not part of equality or hashing (derived from eav).
4. The focused suites around stores and server applies on the Mac mini through build.sh; measure a Scribe-shaped
   full-rebase drain before and after with InstantServerApplyCostTests (INSTANT_SERVER_APPLY_COST=1,
   INSTANT_FAST_DRAIN_FULL_REBASE=1).
5. Release the next free version (v1.9.65 is claimed by #1648's plan): docs/releases, CHANGELOG, PROGRESS, ledger,
   tag; then bump Scribe's exact pin on realtime-voice main, cut a build and install it, iPhone first, then the iPad.

## Touching

- `Sources/InstantSwiftDataCore/TripleIndexes.swift` (newestTransactionTimeMilliseconds, the stamp writers named in
  step 3, a private kept-times type, the decode init; not TxIDInterner, not the query paths)
- `Tests/InstantSwiftDataCoreTests/InstantStoreWriteScalingTests.swift` (new tests only)
- `CHANGELOG.md`, `PROGRESS.md`, `docs/releases/v1.9.66.md` (or the next free version), `docs/audits/commit-changelog.md`
  (release and ledger)

## Conflict check

TripleIndexes.swift's newest claim is gate-1319 (#1319, 2026-10-28, landed). No branch on origin holds an unlanded
change to it (checked 2026-11-04 10:40). #1648 (order-1648, resumed 10:12) touches InstantTypedAPI.swift and
InstantRuntime.swift's transact paths only, and claims v1.9.65; this plan does not touch InstantRuntime.swift.
