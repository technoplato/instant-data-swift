# Plan 2026-11-02-order-1648: a write's place in the outbox is decided when it enters the operation gate

- planId: 2026-11-02-order-1648
- agentId: claude-code/order-1648@halfjew22 (tools/agent-run, claude/halfjew22, opus)
- role: mower (the same writes in the order they were made; no new public surface)
- issues: #1648 (found by #1609's measurement), parent #1609
- branch: agent/claude/order-1648 (worktree ~/Sync/worktrees/order-1648), landed with ~/Scribe/tools/land

## Why (read from v1.9.64's source before any change)

Delivery is `ORDER BY created_at_ms, mutation_id` and a mutation id is a random UUID, so two writes with one
`created_at_ms` go out in coin-flip order; up to 50 are in flight and the server applies them as they arrive. The
runtime steps a new write's stamp past the outbox tail (`max(now, tail + 1)`, `performTransact`) only when the caller
passes no `createdAt`. Three entries read the clock before the operation gate and pass it explicitly, so they never
step: the typed `transact(_ mutations:)` (every typed write: `transact { }`, `save`, `transact(saving:)`, the array
form), `InstantRuntime.transact(operations:)` and `retryQuarantinedMutation(id:)`. The typed path also stamps every
fact with that time. Measured by #1609 on a phone: two revisions of one row written 0.5 ms apart got one stamp, the
newer went first, and a rule requiring a newer `updatedAtMs` refused the older. The same tie lets the immediate-tail
supersession keep the wrong write and hides a refused write's later covering write from
`failedMutationSupersessions()`.

Upstream Reactor.js `pushOps` gives each mutation `order = max(order) + 1` when it is made, and sorts by it
(`sortedMutationEntries`); the Swift outbox's `created_at_ms` plays that part.

## Steps

1. This plan and its claims (plan-only commit), landed on main.
2. Red (InstantSwiftDataTests, a frozen configuration clock): two typed writes of one row in one millisecond reach the
   outbox and the wire in the order they entered the gate, with strictly increasing `created_at_ms`, each fact
   stamped with its write's creation time; a typed write after the clock steps back still goes after the tail; a
   typed write replaces the unsent write of the same row made in the same millisecond (never the reverse); a refused
   typed write is superseded by the write made after it in the same millisecond; `transact(operations:)` keeps call
   order in one millisecond.
3. Green: without an explicit `createdAt`, the creation time is assigned inside the gate after the outbox tail, and a
   typed write's facts are restamped with it on every attempt (so the visible-write filter and the same-entity
   supersession compare the same order delivery uses). `transact(operations:)` and `retryQuarantinedMutation` stop
   passing `now()`. An explicit `createdAt` keeps its meaning (the caller's time, kept exactly, ties by id): the
   library's own tests rely on it (TypedAPITests' `serverCreatedAt` order, InstantFastDrainTests' and
   InstantLocalStampShadowsServerTests' device stamps, the supersession integration tests).
4. The focused suites around writes and delivery on the Mac mini through build.sh; land; CHANGELOG and ledger.
5. Release v1.9.65 (docs/releases, PROGRESS, ledger, tag), then bump Scribe's exact pin in a realtime-voice worktree
   cut from origin/main, build it through build.sh, push to main; coordinate on #1609.

## Touching

- `Sources/InstantSwiftData/InstantTypedAPI.swift` (the typed `transact(_ mutations:)` only)
- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (`transact`, `transact(operations:)`, `performTransact`'s
  creation stamp, `retryQuarantinedMutation` only)
- `Tests/InstantSwiftDataTests/InstantWriteCreationOrderTests.swift` (new)
- `Tests/InstantSwiftDataCoreTests/InstantSendAgainCreationOrderTests.swift` (new, amendment 1)
- `docs/FOOTGUNS.md` (a new F67 entry and its index row only, amendment 2)
- `Tests/InstantSwiftDataTests/TypedAPITests.swift` (two tests' expectations only, amendment 3)
- `CHANGELOG.md`, `PROGRESS.md`, `docs/releases/v1.9.65.md`, `docs/audits/commit-changelog.md` (release and ledger)

## Conflict check

`InstantRuntime.swift`'s last claims are #1491/#1493/#1494/#1498 (2026-10-31, all landed and released in v1.9.62-64);
`InstantTypedAPI.swift`'s last claim is library-79 (2026-10-04). No open lane names these functions.

## Amendment 1 (22:56)

Send Again (`retryQuarantinedMutation`) needs a quarantined row, which only the Core test target can seed
(`simulateUnexpectedConnectionCloseForTesting` is internal), so its same-millisecond red test is a new Core test file:
a write made now, then a quarantined mutation sent again in the same millisecond, goes after it.

## Amendment 2 (23:05)

docs/FOOTGUNS.md asks that a newly found trap be added with its rule and guard test in the same change: F67, "decide a
write's place in the outbox under the operation gate, never before it", guarded by the two creation-order suites.

## Amendment 3 (03:05)

The full run at the fix (build.sh job 1648-gate, mini, 02:27-02:40) failed two typed tests whose expectations encoded
the tie: with the clock frozen they expected pending writes in id order and every fact at the one frozen time
(`typedCreateIsStrictAndTypedUpdateUpserts`, `typedLookupMutationsResolveUniqueAttributesAndPreservePendingLookups`).
Their expectations become the order the writes were made and each write's own time. The run also showed the gate's
holder renamed to `transact(_:creation:source:)` (three gate tests); the runtime now enters the gate under
`transact(_:createdAt:source:)` for every local write, the name diagnostics and baselines key on. The other failures
are checked against main's sources in the next job.
