# Plan 2026-10-24-audit-concurrency-1074

- **planId:** 2026-10-24-audit-concurrency-1074
- **agentId:** claude-code/audit-concurrency-1074@ld
- **role:** grower for the exercises and the one instrument they need (ordered on #1074: "write real exercises of the
  poor hot paths"); mower for nothing yet: no library fix in this plan unless it is one line with a passing exercise
  (an amendment names it first). The lab dispatches the fixes from the issues this audit files.
- **branch:** agent/claude/audit-concurrency-1074 (worktree ~/Sync/worktrees/instant-audit-concurrency-1074), rebased
  on main and pushed when the audit and its exercises are green.

## Outcome (#1074)

An audit of the library's concurrency: every actor, serial gate, lock and unstructured task; what runs under the
operation gate and for how long; actor hops per operation; work on the main actor; head-of-line blocking (a long prune,
apply or compaction making writes and reads wait); priority inversion (a caller someone waits on queued behind utility
work); cancellation that never reaches long loops; tasks that outlive their owner. Each anti-pattern has a file and
line, how often it runs while a recording runs, its cost now (measured, or "not measured yet"), a design, and its saving
written as a hypothesis with how it is measured. Committed exercises drive writers, readers, a live observer, a prune
and a server apply together on #1072's real-size store and print each caller kind's wait (median, p99, worst) and each
holder's hold in stable lines, so the same exercise measures each fix later; today's baseline is recorded from them.

## Steps

1. Read the library's actors, gates, locks and tasks (parallel read-only readers), map Scribe's recording workload,
   and read the phone's own gate-wait lines (device pulls, never committed).
2. The instrument: `AsyncSerialGate` reports every request, acquisition (with its wait) and release (with its hold) to
   an optional timeline closure, nil by default, so production pays one nil check; `InstantRuntimeConfiguration` gets
   one property that hands it to the operation gate. Test first (`AsyncSerialGateTimelineTests`).
3. Exercises under `Tests/InstantSwiftDataCoreTests/RealSize/Contention*.swift` on #1072's `RealSizeFixture`
   (measurement-only, `.measurement` trait): the contention exercise (writers, readers, a live observer, a prune and a
   server apply together; per caller kind wait median, p99, worst; per holder hold median, p99, worst; latency probes
   on the persistence actor, the store actor and the main actor), plus one focused exercise per poor hot path the
   audit names. Each prints `CONTENTION <exercise> key=value ...` lines.
4. Baseline runs (the Mac mini, idle; heavy.sh on the laptop when the mini is busy); a real-size check on a local copy
   of the phone's store (never committed, never copied into the repo). Baseline in
   `docs/audits/2026-10-24-concurrency-baseline.txt`.
5. One issue per fix (linked to #1074 and #1072), worst first by measured cost, each naming its exercise and baseline.
6. The audit (`docs/audits/2026-10-24-concurrency-audit.md`); CHANGELOG, PROGRESS, the audit ledger; push to main.

## Touching

New: `Tests/InstantSwiftDataCoreTests/RealSize/ContentionExercises.swift`,
`Tests/InstantSwiftDataCoreTests/RealSize/ContentionInstruments.swift`,
`Tests/InstantSwiftDataCoreTests/AsyncSerialGateTimelineTests.swift`,
`docs/audits/2026-10-24-concurrency-audit.md`, `docs/audits/2026-10-24-concurrency-baseline.txt`,
`scripts/contention-exercises/run-contention-exercises.sh`.
Changed: `Sources/InstantSwiftDataCore/AsyncSerialGate.swift` (the timeline hook only),
`Sources/InstantSwiftDataCore/InstantRuntime.swift` (one `InstantRuntimeConfiguration` property, its default, and the
line that builds the operation gate; agreed with #1072 by message 2026-10-24 16:10 EDT: #1072 keeps the stored-file
calls and does not touch `AsyncSerialGate` or that line).
Appended: `CHANGELOG.md`, `PROGRESS.md`, `docs/audits/commit-changelog.md`.
Read only: #1072's `RealSizeFixture.swift` and `RealSizeMeter.swift` (requests through
`agent-presence/_channels/2026-10-24-lib-audit-1072.md`).

## Conflict check

`AsyncSerialGate.swift`'s earlier claims (#277, #403, #473, #482, #1006) have all landed. `InstantRuntime.swift` is
claimed by #1072 for `storedFiles()` and `observeStoredFiles()`; this plan edits only the configuration struct and the
operation gate's construction, far from those functions. #1075 and #1076 claim no library source. `RealSize/` is
#1072's directory; this plan adds `Contention*` files beside theirs and edits none of theirs.
