# Plan: one actor turn per step on transact, relaunch, and outbox drain (#403)

- **planId:** `2026-10-02-library-79-hops`
- **agentId:** `claude-opus-5.5-library-79` (issue workLog agentId `claude-code/claude-opus-5.5/library-79`)
- **Role:** mower. Fewer actor calls and SQLite transactions for the same durable result; no new public surface.
- **Branch:** `agent/claude-opus-5.5/library-79-hops`, from library-78's head `d95c9625` (the v1.9.0 candidate).
  Main's release plan (2026-10-02) and Michael's authorization ("Publish the library once it's checked fast. Yes.")
  extended it: merge v1.9.0, run the release-gate hold, and publish v1.9.1 from main, with
  `docs/releases/v1.9.1.md` (new, claimed 2026-10-02 15:43 EDT).
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
- `Sources/InstantSwiftDataCore/Outbox.swift` (a one-turn batch replace) and
  `Sources/InstantSwiftDataCore/OutboxSameEntitySupersession.swift` (a transaction-level eligibility check), added
  2026-10-02 09:38 EDT
- `Tests/InstantSwiftDataCoreTests/AsyncSerialGateTests.swift` (the held-snapshot test), added 2026-10-02 10:20 EDT
- The shared transport-date formatter, at main's request (2026-10-02 about 09:50 EDT), as its own commit:
  `Sources/InstantSwiftDataCore/InstantTransportMutation.swift`, new
  `Tests/InstantSwiftDataCoreTests/InstantTransportDateFormatterTests.swift`, new
  `validation/fixtures/transport-date-encoding.json` and `validation/ts-runner/src/transport-date-encoding-fixture.ts`
- A prepared-statement cache on the persistence actor, at main's request (2026-10-02 about 12:05 EDT), as its own
  commit: `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (already claimed) and new
  `Tests/InstantSwiftDataCoreTests/SQLiteStatementCacheTests.swift`, added 2026-10-02 12:08 EDT
- The three next cuts main approved (2026-10-02 13:21 EDT, "do them after v1.9.1 ships, one commit and one ABBA arm
  each"), prepared on the local branch `agent/claude-opus-5.5/library-79-next` and measured by heavy job 4; they land
  here after v1.9.1 ships: `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` and `InstantRuntime.swift`
  (already claimed), `Sources/InstantSwiftDataCore/InstantModels.swift` and `BoundedOutboxDelivery.swift` (one
  encoding per save), and new `Tests/InstantSwiftDataCoreTests/SQLiteTurnTransactionTests.swift`,
  `SQLiteBootstrapMigrationTests.swift`, and `InstantEncodedOutboxMutationTests.swift`, added 2026-10-02 14:32 EDT
- `Tests/InstantSwiftDataCoreTests/InstantCrossSDKRuntimeBenchmarkTests.swift`
- `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift` and `CLITests.swift` (hop pins only; CLITests added
  2026-10-02 11:38 EDT)
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

## #431 (P0, main, 2026-10-03 about 01:00 EDT)

A device that once wrote a single-value attribute never saw another device's later value of it: server facts carry the
triple's created_at, and the store resolved single-value facts last-write-wins by stamp. Fix: the server's facts are
authoritative and only surviving pending writes overlay them, as in Reactor.js; stores 1.9.1 persisted heal on the
first refresh that restates a shadowed slot. Published as v1.9.2 under the same authorization. Touching
`Sources/InstantSwiftDataCore/TripleIndexes.swift` and `InstantRuntime.swift` (already claimed),
`Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift`, new `InstantLocalStampShadowsServerTests.swift`, and
new `docs/releases/v1.9.2.md`, added 2026-10-03 01:11 EDT. The speed cuts on
`agent/claude-opus-5.5/library-79-next3` wait and will be measured on the fixed code.

Main, 01:12 EDT: cover slots the server cleared too ("Match Reactor.js here: on a full refresh, a local fact that
isn't pending and that the server doesn't return goes away."), next to the overwritten one, and check the fix against
the pulled iPad store. A cleared slot loses a value no other stored result owns, and only a pending write of a slot (or
of the entity, for a link) protects a retraction, never a write pruned in the same apply. Touching
`Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` for #431 and new
`Tests/InstantSwiftDataCoreTests/InstantLocalStampShadowsDeviceStoreTests.swift` (skipped unless
`INSTANT_431_DEVICE_STORE` names a pulled store), added 2026-10-03 01:40 EDT.

Round 2 (02:08 EDT) showed slot-level protection for every retraction rebasing four fast-drain cases, so a cleared slot
alone gets it; and main's rule covers slots no result ever held, so a query's `fields` decide which slots a refreshed
result vouches for. New `Tests/InstantSwiftDataCoreTests/InstantLiveQuerySelectedAttributesTests.swift` pins that
reading of the query key, added 2026-10-03 02:15 EDT.
