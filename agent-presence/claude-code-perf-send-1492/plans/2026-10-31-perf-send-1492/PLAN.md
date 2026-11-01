# Plan 2026-10-31-perf-send-1492: the send path pays per connection, not per send

- planId: 2026-10-31-perf-send-1492
- agentId: claude-code/perf-send-1492@ld (tools/agent-run, claude/ld, opus)
- role: mower (the same frames, in the same order, for less CPU and fewer tasks; no new surface)
- issues: #1492 (first), #1497 (second), #1496 (third); from the #1482 audit, findings F1, F6, F5
- branch: agent/claude/perf-send-1492 (worktree ~/Sync/worktrees/perf-send-1492), landed with ~/Scribe/tools/land

## Why (measured before any change, by the #1482 audit)

Mac mini M4, release, the `recording` contention exercise sampled for 60 s at 1 ms (M6): `AttributeIDResolver.init` plus
`resolveAttributeIDs` 102-114 ms a minute for about 90 sends (about 1.2 ms a send); `optimisticEffectReceiptFingerprint`
119 ms a minute for about 90 acknowledgements (about 1.3 ms each); `instantLiveWithTimeout` 441 ms a minute inclusive.
Phone energy ledger: mutationEncode 0.28-0.43% of a core, acknowledgement 0.35-0.69%.

Checked before planning: the library's `init` advertises `@instantdb/core` v0.22.75, so the server's `skip-attrs` is
on and a `refresh-ok` carries attrs only when they changed (`session.clj` `handle-refresh!`, #303). One resolver per
`serverAttributes` value is therefore one build per connection or schema change.

## Steps

1. This plan and its claims (plan-only commit), landed on main.
2. Measurement: the `recording` exercise prints each library operation's count and CPU from the energy meter over its
   window (one CONTENTION line), so every before and after here is the same exercise on the same machine.
3. #1492 red: 100 sends on one connection with 2,283 generated attributes build the resolver once (a counter on the
   live session). Green: the resolver is kept on the session, dropped when `serverAttributes` changes, built on the
   next send. Same bytes on the wire. Mini, release: mutationEncode CPU per send before and after.
4. #1497: read the acknowledgement's three checks and every writer of the outbox body and its receipt column; pin
   what the digest proves; red: 0 receipt encodes per acknowledgement on the stored path; green at the source.
   `InstantServerTransactionLoopbackValidation` unchanged. Mini: acknowledgement CPU per acknowledgement.
5. #1496 red: task creations per send (today 3: the send's task and the timeout's work and deadline tasks). Green: one
   writer task per socket writes its frames in the order the session made them, and one deadline watcher per socket
   bounds the write in progress at 5 s; a send creates no task and arms no timer. `instantLiveWithTimeout` keeps its
   suite unchanged and its once-per-connection callers.
6. After each green: land, ledger with land --prepend, "READY FOR BUILD" on #1482. No build cut, tagged or installed.

Write contract unchanged: transact/save is local materialize and durable outbox only. Nothing is batched, delayed,
throttled, sampled, dropped or limited; every frame goes out as soon as it did, in the session's order.

## Touching

- Sources/InstantSwiftDataCore/InstantLiveMutation.swift (#1492: the resolver)
- Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift (#1492: `serverAttributes` and `sendMutations`' resolve;
  #1496: `send(_:through:)` and the socket's writer). Not `startReceiving`, `record`'s frame bookkeeping or
  `canDeliverReceiverEvent` (perf-observe-1493's #1494).
- Sources/InstantSwiftDataCore/InstantLiveTransport.swift (#1496: the writer beside `instantLiveWithTimeout`)
- Sources/InstantSwiftDataCore/InstantLiveSocketWriter.swift (new, #1496)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (#1497: `acceptOutboxMutation` and the receipt digest only)
- Sources/InstantSwiftDataCore/InstantModels.swift (#1497: `optimisticEffectReceiptFingerprint` only)
- Tests/InstantSwiftDataCoreTests/InstantLiveSendPathTests.swift (new)
- Tests/InstantSwiftDataCoreTests/InstantAcknowledgementDigestTests.swift (new)
- Tests/InstantSwiftDataCoreTests/RealSize/ContentionExercises.swift (the recording exercise's energy line only)
- CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

Main at 5d772e41: no open claim on these regions. Shares InstantRuntimeLiveSession.swift with perf-observe-1493 (#1494,
the applier's hops) and SQLitePersistenceStore.swift with perf-gate-1491 (#1491, the transact path) and perf-read-1498
(#1498, the query cache): disjoint regions; channel 2026-10-31-perf-send-1492. Rebase onto each landing before a land.

## Amendment 1 (#1497)

The audit's interim fix cannot be byte-equal to today's digest: the receipt fingerprint is SHA-256 over a sorted-keys
encoding of a payload (id, createdAt, transaction, rollback, overlay state, receipt version), not over the stored body.
The fix at the source: the store keeps, for each body it writes, the receipt it computed from it, keyed by the SHA-256
of the stored text. The claim and the acknowledgement reuse it when the stored bytes still hash the same, and compute
it as before when they do not (a body written by an earlier process or changed since). Touching adds
Tests/InstantSwiftDataCoreTests/InstantWritePathEnergyTests.swift (`eachStepOfALiveWriteFingerprintsItsEffectOnce`'s
pin only).

## Amendment 2 (#1497, #1496)

#1497: the kept fingerprint is keyed by a hash of its six inputs (id, createdAt, transaction, rollback, overlay state,
receipt version), not by the stored body's SHA-256: two receipt checks pass an in-memory write, not one decoded from
the row, and the inputs key is exact for every caller with no assumption that a body decodes back to the inputs it was
encoded from (ca5c830e after a55a0912).

#1496: `instantLiveWithTimeout` stays as it is for its once-per-connection callers: a two-child task group awaits its
children, and `liveTimeoutDoesNotAwaitCancellationInsensitiveWork` requires the timeout to return without the work.
The send path's pin lives in InstantLiveSendPathTests, since InstantFastDrainTests never sends on a socket.
