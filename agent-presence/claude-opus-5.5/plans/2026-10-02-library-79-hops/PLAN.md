# Plan: one actor turn per step on transact, relaunch, and outbox drain (#403)

- **planId:** `2026-10-02-library-79-hops`
- **agentId:** `claude-opus-5.5-library-79` (issue workLog agentId `claude-code/claude-opus-5.5/library-79`)
- **Role:** mower. Fewer actor calls and SQLite transactions for the same durable result; no new public surface.
- **Branch:** `agent/claude-opus-5.5/library-79-hops`, from library-78's head `d95c9625` (the v1.9.0 candidate).
  Not merged to main and not published by this plan.
- **Goal (Michael, verbatim, 2026-10-01):** "fix this please so it works efficiently as as well as the typescript
  core library"
- **Issue:** https://issues.knophy.com/issues/403 (related: #402, #155, #303)

## Outcome

The three cross-SDK runtime workloads make far fewer actor calls, each counted, with tests that pin the counts:
one transact runs its persistence work in two actor turns instead of about twelve. The write contract is unchanged:
`await transact` means local materialize plus a durable outbox row, offline writes succeed, and nothing assumes one
server answer per transaction (Instant's `combine-transact` merges same-shape queued writes).

## Steps (no code here)

1. Measure first: record every actor call on the three benchmark paths, so before and after are both measured.
2. Add a `run` entry point on `SQLitePersistenceStore` (Point-Free ep362@12:16): several synchronous calls in one
   actor turn, with no other persistence work interleaved between them.
3. Connection status: its six persistence reads in one turn, everywhere it is published.
4. transact: the reads before the save in one turn; the save and the status reads in a second.
5. The server-apply gate's held flag without a hop; no live-session hop when no live transport is configured.
6. Relaunch and drain: batch the persistence calls that sit next to each other.
7. Tests pin the hop counts; ABBA p50 against v1.8.0 and against the base, through `heavy.sh`.
8. Library ADR 0018 (design note and decisions), CHANGELOG and ledger entries, PROGRESS, #403 work log.

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntime.swift`
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`
- `Sources/InstantSwiftDataCore/AsyncSerialGate.swift`
- `Sources/InstantSwiftDataCore/InstantActorHopInstrumentation.swift`
- `Tests/InstantSwiftDataCoreTests/InstantCrossSDKRuntimeBenchmarkTests.swift`
- `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` (hop pins only)
- `docs/adr/0018-one-actor-turn-per-step.md` (new)
- `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md` (prepend only)

## Conflict check

- `claude-opus-5.5-library-78` claims `InstantRuntime.swift`, `SQLitePersistenceStore.swift`, and the three logs on
  `agent/claude-opus-5.5/library-78`, which is still running its final gates. This branch starts from its final head
  `d95c9625` and never pushes to it; when library-78 merges to main, this branch merges main and resolves there.
  Noted in `agent-presence/_channels/2026-10-02-library-79-hops.md`.
- `AsyncSerialGate.swift`'s last claim is triage-l's finished plan `2026-09-27-triage-l-operation-gate`.
- Library ADR 0017 is the highest number on every remote branch on 2026-10-02 at 09:05 EDT; Scribe's ADR 0018 is a
  different repository.
