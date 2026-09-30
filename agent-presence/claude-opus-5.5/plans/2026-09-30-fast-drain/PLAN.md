# Plan: a large outbox drains without a whole-component rebase per server frame (#296 open item 2)

- planId: 2026-09-30-fast-drain
- agentId: claude-opus-5.5-fast-drain
- role: mower (removes repeated work from the server-apply path; no new public surface)
- Issue: #296 (Recording 023), open item 2 of `/Users/laptop/Sync/audit/recording-023-fixes/STALE-WRITES.md`
- Branch: agent/claude-opus-5.5/fast-drain from agent/claude-opus-5.5/stale-writes (80db4271)

Evidence: the phone (iPhone 17 Pro, iOS 27) holds 2,487 pending writes. Every server frame that touches them
peels and replays the whole connected component (1,864 and 616 writes); two finished rebases took 22.5 s and
24.9 s with one core pegged. With 4e281ddd the outbox drains, but about 33 writes per 55 s.

Steps (no code here):

1. A Scribe-shaped drain harness in the test target: thousands of pending writes linked to one recording,
   a consistent fake server that accepts them in order and answers with query results. Measure frames,
   rebase count, bodies peeled and replayed, wall time, and CPU on the current code (baseline).
2. Before planning a server apply, classify each server fact against the materialized store and the durable
   optimistic receipts. A fact that cannot change the authoritative base under the pending writes is
   dropped. When nothing that remains touches an entity with an active overlay, and the watermark prunes
   only a prefix of the outbox, the plan is body-free: no peel and no replay. Anything else keeps today's
   full rebase. Upstream Reactor.js keeps server results per query and reapplies pending mutations on top;
   this computes the same answer without replaying writes the frame cannot affect.
3. Tests first: focused Swift Testing cases, seen failing before the change, and a differential test that
   runs the optimized path and the full rebase side by side over randomized interleavings of server frames,
   acceptances, refusals, and new local writes, comparing every read.
4. Keep 4e281ddd's deadline deferral and 120 s cap, #259's whole-entity rules, and 8ed26be3's rule.
5. Measure after; run the library's broad suites against the stale-writes baseline (682 pass, 21 known).
6. Secondary: reproduce Pattern B (segments losing ownerUserID) with a test; fix only if on the same path.

Touching:

- Sources/InstantSwiftDataCore/InstantRuntime.swift (server apply)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (server-apply plan and classification queries)
- Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift (new)
- CHANGELOG.md, docs/audits/commit-changelog.md

Conflict check: the stale-writes agent's claims on InstantRuntime.swift and SQLitePersistenceStore.swift are its
own finished, pushed work, which this branch builds on. No other open claim on these paths since 2026-09-29.
