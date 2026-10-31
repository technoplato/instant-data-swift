# Plan 2026-10-31-perf-gate-1491: what a local write's gate hold measures, and a write that encodes its body once

- planId: 2026-10-31-perf-gate-1491
- agentId: claude-code/perf-gate-1491@ld (tools/agent-run, claude/ld, opus)
- role: mower (the same writes, the same durable rows and the same errors, for less CPU per write; no new surface)
- issues: #1491 (F0 of the #1482 audit), reported on #1482
- branch: agent/claude/perf-gate-1491 (worktree ~/Sync/worktrees/perf-gate-1491), landed with ~/Scribe/tools/land

## Why (read from the #1482 bisect's own lines before any change)

The #1482 audit names a 4.6x regression of the recording exercise's steady transact hold (1.58 ms at 287f77d1, 7.22 ms
at 0ddbaa62) and a day bisect (10-25 1.38, 10-26 5.01, 10-27 6.38, 10-28 6.61). Its own lines say the comparison mixed
machine states: none of 10-26's code changes runs in the exercise (its server pushes messages in memory, so #1117's
frame-decode meter never runs; its transport's path is `.alwaysSatisfied`, so #1237's route watcher never starts;
#1227 is the files folder), every line moved together between d1025 and d1026 (read.local, which never takes the gate,
0.67 -> 3.34 ms; the claim 1.04 -> 4.45; the plan 0.54 -> 2.29), and the mini's journal puts every fast run beside
another job and every slow run alone. Mini jobs run under `taskpolicy -c utility` and `nice 10` on 4P+6E cores.

The write's own CPU is real either way: the M6 sample puts about 3 ms of CPU in each transact on the M4, and about
0.9 ms of it is three sorted-key JSON encodes of the same mutation (the admission's size check, the stored body, the
receipt fingerprint).

## Steps

1. This plan and its claims (plan-only commit), landed on main.
2. Measure first: `scripts/contention-exercises/ab-commits.sh` runs the recording exercise at 287f77d1, 4accbf45 and
   main in one job on the mini, each alone and beside six busy loops, two rounds in a rotated order, each run recording
   what else used the CPU. Its lines decide whether any commit moved the hold; they go on #1491 and #1482, and the
   audit's F0 is corrected to what they show. If a commit did move it, bisect with the same runner and condition and
   fix that commit's cost at its source.
3. Red: a new local write encodes its mutation to JSON exactly as many times as its durable rows need (a counter
   beside `optimisticEffectFingerprintCountForTesting`): today the admission's size check encodes the whole mutation
   once more only to count its bytes. Green: the size bound is checked on the body bytes the save already encodes, in
   the same SQLite transaction, before the row is written; same error, same code, same message, nothing committed
   (`newOversizedBodyMutationFailsBeforeLocalCommitAndNextWriteDelivers` unchanged).
4. Any further cost the A/B or a sample names inside the transact's own turns (its reads, prepare, save, status read,
   diagnostics), one red/green each, measured with ab-commits.sh (this branch against main, same job, both
   conditions).
5. Amendment 1 (measured at 12:44: 287f77d1 alone holds 5.02 ms, so F0 is mostly machine state): the two digests a
   save writes format their 32 bytes with `String(format:)` each, about 0.11 ms a write on the M4 (M6 sample); red pins
   the digest of a known input, green writes the same lowercase hex from a byte table.
6. Amendment 2: in `saveOutboxMutationWithoutTransaction`, the wire-intent fingerprints (the candidate's sorted-key
   encode and SHA-256, the stored body's decode and its own) decide only a row that already holds a server acceptance
   or was offered to delivery; a new write computes them and reads neither. Red pins the count of wire fingerprints a
   new write computes (0); green computes them only for such a row; same checks, same errors.
7. After each green: land, ledger with land --prepend, "READY FOR BUILD" on #1482. No build cut, tagged or installed.

Write contract unchanged: transact/save is local materialize and durable outbox only. Nothing is batched, delayed,
throttled, sampled, dropped or limited.

## Touching

- scripts/contention-exercises/ab-commits.sh (new)
- Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift (`InstantAutomaticOutboxAdmission.validateNewMutation`)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (`saveLocalMutation`, and in
  `saveOutboxMutationWithoutTransaction` the admission's byte bound beside `encodeOutboxBody` and, amendment 2, its
  wire-intent fingerprints; not
  `acceptOutboxMutation` or the receipt digest, which perf-send-1492 owns, nor the query cache or the server apply)
- Sources/InstantSwiftDataCore/InstantRuntime.swift (`transact`, `performTransact`, `loadLocalWriteReads`,
  `saveLocalMutationReadingConnectionStatus` only)
- Sources/InstantSwiftDataCore/InstantModels.swift (amendment 1: `instantSHA256HexDigest` only; not
  `optimisticEffectReceiptFingerprint`, which perf-send-1492 owns)
- Tests/InstantSwiftDataCoreTests/InstantLocalWriteEncodeTests.swift (new)
- docs/audits/2026-10-31-transact-hold-1491.md (new: the A/B's lines and what they mean)
- CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

Main at d2392508: no claim on the transact path. Shares SQLitePersistenceStore.swift with perf-send-1492 (#1497, the
acknowledgement and the receipt digest), perf-read-1498 (#1498, the query cache) and perf-observe-1493 (#1494, the
server apply's planning reads): disjoint functions. `saveOutboxMutationWithoutTransaction` is the one function next to
#1497's digest: my change there is the byte bound only; channel 2026-10-31-perf-gate-1491. Rebase onto each landing
before a land.
