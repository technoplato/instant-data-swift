# Plan 2026-11-04-perf-send-1797: one write costs one write

- planId: 2026-11-04-perf-send-1797
- agentId: claude-code/perf-send-1797@pp (tools/agent-run, claude/pp, opus)
- role: mower (the same writes, delivery order, durability and refusals, from fewer encodes, tasks and pages per
  write; no new public surface)
- issues: #653 (primary), #1517, #1523, #1142, #1254, #1463, #1464, #1320, #1434, #1241/#1426 (the library half of
  disk writes), #1648 (taken over: its worktree ended before its release), #1655; epic #1797 (trace audit
  2026-11-04), #1783
- branch: agent/claude/perf-send-1797, worktree ~/Sync/worktrees/perf-send-1797 (measurement jobs from a pinned
  worktree ~/Sync/worktrees/perf-send-1797-measure); every green lands on main, rebased first

## Why (measured)

The phone (builds 248-249, ledger 2026-11-04 15:58-17:57, 118.6 recording minutes): 55.5 MB/min of disk writes, 20.2%
of a core while recording. refresh-cost.py, build 248, 16:02-17:30: 4,288 transactions in 88 min (49 a minute), the
send side 39 CPU-s (9.2 ms of library CPU a write). The 15:55 trace (build 247): `InstantSwiftDataClient.transact` 7.4%
of Scribe's CPU, the delivery pump's claim 3.1%, the acceptance 1.6%, and the same write encoded and decoded several
times (`InstantStoreTransaction.encode` 1.4%, `PendingMutation.init(from:)` 1.4%, `decodeOutboxBody` 1.3%, #1517).
Pages per write on the phone's 10-31 log (#1510): a save 24.4, a claim 2, an acceptance 5 (the watermark index 1.98,
the outbox row, its delivery index, `instant_sync_metadata`), a server confirm 35.5; checkpoints 7 MB each.

## Target, written before the first fix

A live write's total log pages (save + claim + acknowledgement + echo) and CPU on the harness
(`StorageIOExercises.aLiveWritesStepsByBTree`, `eachStepOfALiveWrite`, the recording exercise's energy lines and a
60 s sample), and the phone's SQLite bytes an hour while recording, before (job 1648-gate-1797-base, at af35bc58) and
after each green.

## Steps

1. #1648: land order-1648's ten commits (merged onto main cleanly, af35bc58) with its gate: the creation-order suites
   three times and the transact-path suites at the head, red with main's sources; release.
2. #1517, #1523: one encode and one fingerprint per write. The claim, the receipt check and the wire body derive from
   the bytes the save encoded (or a digest column the save writes); the acknowledgement re-hashes nothing it holds;
   `InstantAcknowledgementDigestTests` reads the compressed body (failing on main since 1.9.64). Red: a write's
   encodes and hashes counted from save to acknowledgement.
3. #1142: no per-write task churn or polling in delivery: the pump's passes, the send and the acknowledgement deadline
   run on tasks that live as long as the socket; `waitForAllPendingMutations` waits on the lifecycle, not a 50 ms poll.
   Red: tasks created per write on a connected runtime.
4. #653 item 4: the acknowledgement and the claim write only the accepted row's pages (an index keyed on a column they
   change, a revision only another reader needs). Red: StorageIO pages per acknowledgement and claim.
5. #1254: no per-write rewrite of `instant_sync_metadata`'s revision page, with revisions monotonic across launches
   (the stored query cache keys answers by store revision).
6. #1320: the WAL checkpoint runs outside the operation gate and off the commit that crosses 4,000 frames, with
   #1118's cadence and durability kept.
7. #1464, #1463, #1434: measured designs first (what #1510 left of overflow; effect entities and key rows as one
   b-tree pair; ownership rows keyed without the whole value twice, ADR 0020), built in this order if the evidence
   holds.
8. #1655: the typed transact hands a writer the stamp assigned under the gate.
9. Release each green as a library version, pin it in Scribe, cut and install; after an hour on the phone compare
   `device-lab.py ledger` writes MB/min and refresh-cost.py's send CPU, written on #1797.

## Touching

- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift` (saveLocalMutation's body, fingerprint and key columns,
  claimAutomaticOutboxDeliveryWindow, acceptOutboxMutation, the metadata revisions, the writer's checkpoint; not
  serverApplyPlanningReads, the retraction diff or the result saves (perf-recv-1797), not deferred loads, the prune or
  reload (perf-mem-1797))
- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (transact and performTransact, the delivery pump,
  acceptMutationIfPresent; not applyLiveRefresh's planning (perf-recv-1797), not the deferred loads (perf-mem-1797))
- `Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift`, `InstantModels.swift` (the write's fingerprints),
  `InstantOutboxStoredBody.swift`, `Outbox.swift`, `InstantSQLiteWriteRecorder.swift` (checkpoint attribution),
  `InstantMutationAcknowledgementDeadlinePolicy.swift`, `InstantLiveTransport.swift` and
  `InstantRuntimeLiveSession.swift` (the send path only: sendMutations, send(_:through:)),
  `Sources/InstantSwiftData/InstantSwiftData.swift` (waitForAllPendingMutations), `InstantTypedAPI.swift` (#1648, #1655)
- Tests: `InstantAcknowledgementDigestTests.swift`, `SQLiteCheckpointCadenceTests.swift`,
  `RealSize/StorageIOExercises.swift`, `InstantServerRefreshWritesTests.swift` (the b-tree exercise), new
  `InstantWritePathCostTests.swift`
- `docs/FOOTGUNS.md`, `docs/audits/2026-11-04-write-path-1797.md` (new), `CHANGELOG.md`, `PROGRESS.md`,
  `docs/releases/v1.9.*.md`, `docs/audits/commit-changelog.md`

## Conflict check

- perf-recv-1797 (#1109): the server apply's planning reads, the retraction diff, the result saves, the publication;
  I touch the echo only where it deletes confirmed outbox rows, keys and effect entities, and #1434's ownership value
  text only after a word on its channel.
- perf-mem-1797 (#1500): the deferred-value loads before a local write prepares are theirs; I leave
  `deferredValuesForPreparing` alone. #1434 touches the ownership rows' value encoding #1251/#1505 also rewrites: a
  channel line before either edits it.
- perf-sync-1796 (#1796): reconnect and the applier; my pump and send changes keep their ordering and the bounded
  window (#1007, #1108), and I write on its channel before touching the receive loop (I don't plan to).
- order-1648 (#1648): its worktree ended; I land its branch as is and keep its claims' scope.
- Channel: agent-presence/_channels/2026-11-04-perf-send-1797.md
