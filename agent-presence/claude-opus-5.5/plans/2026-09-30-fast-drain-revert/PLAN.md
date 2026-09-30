# Plan: revert the fast-drain reduction for Scribe build 72 (#296)

- planId: 2026-09-30-fast-drain-revert
- agentId: claude-opus-5.5-fast-drain
- role: mower (removes one commit; no new surface)
- Issue: #296 (Recording 023), open item 2
- Branch: agent/claude-opus-5.5/fast-drain-revert from agent/claude-opus-5.5/fast-drain (bb88af72)

Evidence: on an iPhone simulator against the throwaway app bd40c50a, running the same perf soak, bb88af72 (build 71)
fell behind a live recording. Pending writes reached 20 in the first minute and about 830 after 11 minutes, while
accepts fell from 51 to 4-15 per 30 s. Every older library kept up: 1.7.0 (252bb6cd), c9f25d45, 8ed26be3, and
4e281ddd. 4e281ddd's library sources are identical to 80db4271's, and bb88af72's sources equal 80db4271's plus only
8bee78eb. So 8bee78eb (the server-apply reduction and the tail-write stamp guard) is the regression.

Steps (no code here):

1. Revert 8bee78eb alone. This removes its sources and its test suite (InstantFastDrainTests.swift), keeps ce40ebe3's
   test-only busy timeout, and leaves library sources byte-identical to 80db4271.
2. Change log and audit ledger entries.
3. Run the Recording 023-shape test on the head: about 2,500 pending writes, a fresh connection, then ack timeouts,
   reconnects, and drain time over 5-10 minutes.
4. A corrected reduction becomes a later build, gated on the live soak.

Touching:

- Sources/InstantSwiftDataCore/InstantRuntime.swift
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift
- Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift (deleted by the revert)
- CHANGELOG.md, docs/audits/commit-changelog.md

Conflict check: these paths' latest claims are this agent's own fast-drain plan (e8331558) and the stale-writes
agent's finished, pushed work that this branch builds on. main carries no newer claim on them.
