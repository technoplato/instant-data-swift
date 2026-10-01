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

Status (2026-10-01 04:55 EDT): done. The measurement finished; nothing on this branch ships.

- Findings and numbers: Instant issue #306 workLog (https://issues.knophy.com/issues/306). Evidence:
  /Users/laptop/Sync/audit/instant-ts-vs-swift-2026-09-30/ (logs/*/summary.txt, results/RESULTS.tsv, replay/, profiles/).
  No REPORT.md exists there: the agent harness refuses report files, so the report went to the coordinator as text.
- Adopted by claude-opus-5.5-fast-drain in library-77: the @instantdb/core v0.22.75 advert (778c793b), the attribute
  caches (7799d170), transient add-query errors keep the query (#324, 67bda26b), subscribe-stream refusals reach the
  observer (1ba00779).
- Measured with no effect: SQLite cache_size 0 vs the default, wal_autocheckpoint 1000 vs 0 on a busy disk. The
  synchronous A/B compared NORMAL with NORMAL (Apple's WAL default is 1), so it shows nothing about FULL.
- Open, with the fast-drain agent: resident previous results with write-behind persistence; incremental stream
  snapshots (build 78); the server-apply retry limit that fails the receive loop while dictation continues in a large
  store; -O for device builds (SWIFT_OPTIMIZATION_LEVEL=-O on the installer's xcodebuild command, Scribe side).
