# Plan: measure instant-data-swift against @instantdb/core on Scribe's workload, on a local Instant server (#306)

- planId: 2026-09-30-ts-parity
- agentId: claude-opus-5.5-ts-parity
- role: mower (measurement first; library changes stay proposals, per the coordinator, because the fast-drain agent owns the library)
- Issue: #306 (https://issues.knophy.com/issues/306); related #296, #303
- Branch: agent/claude-opus-5.5/ts-parity-experiments from ab33cb35 (build 75's library)

Outcome: a controlled, traced comparison of the Swift library and the TypeScript core on one Scribe-shaped dictation
workload against a self-hosted Instant server, with every place Swift does more work than TypeScript named and
measured. Evidence lives in /Users/laptop/Sync/audit/instant-ts-vs-swift-2026-09-30/.

Steps (no code here):

1. Experiment-only switches, off by default, so one build can measure each hypothesis at run time:
   - SQLite `synchronous` (FULL, the current default in WAL mode, vs NORMAL) and `cache_size` (0 vs SQLite's default);
   - the `@instantdb/core` version the init frame advertises (Swift sends none, so the server sends every refresh-ok
     with all attributes, even when no result changed).
   With no environment variable set, the code paths are the same as ab33cb35.
2. Run the harness (writer and reader per SDK, decoding proxies, server span log) with each switch, at -O and -Onone.
3. Turn each confirmed gap into a written proposal with numbers for the fast-drain agent; no change here ships.

Touching (experiment switches only):

- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (the pragma block in the store's open path)
- Sources/InstantSwiftDataCore/InstantRuntime.swift (the init frame's versions)
- CHANGELOG.md, docs/audits/commit-changelog.md

Conflict check: both Swift files carry the fast-drain agent's claims (plan 2026-09-30-fast-drain-3). The switches touch
neither the server-apply reduction nor the splice; see agent-presence/_channels/2026-09-30-ts-parity.md.
