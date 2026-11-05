# Plan 2026-11-04-perf-sync-1796: a follower applies the newest result next, and a busy socket is not a failed one

- planId: 2026-11-04-perf-sync-1796
- agentId: claude-code/perf-sync-1796@pp (tools/agent-run, claude/pp, opus)
- role: mower (the same final store from less work: a refresh a newer buffered frame restates is not applied; no new
  public surface)
- issues: #1796 (primary), #998, #1127, #1768, #1734; epic #1783, ledger #1797
- branch: agent/claude/perf-sync-1796, worktree ~/Sync/worktrees/perf-sync-1796 cut from origin/main da175eb7; every
  green lands on main, rebased first

## Why (measured)

Mac diagnostics collector, 2026-11-04, iPhone builds 248-249 recording, iPad build 248 (library 1.9.66) following:

- The writer is not the cause: the iPhone's outbox held 0-3 pending writes from 16:00 to 18:00 (session.health).
- The follower is. The iPad held 8,240-11,035 of its own pending writes (left from its overnight recording) and drained
  25-35 a minute. With that queue each server frame cost about 1-2 s to apply. One minute (17:09:42-17:10:42): 29
  `refresh-ok` of the recordings list (144 KB each) and 31 `transact-ok`; 22 server applies; serverApplyPlan 41% and
  serverApplyStage 30% of a core; "Instant sync 75% of one core", 101% in all, heat serious, 2.5 W.
- Every frame waits in one buffer (128 frames) for one applier, in arrival order. A `refresh-ok` restates each of its
  queries' whole results, so a buffered refresh that a newer buffered refresh restates is applied for nothing, and
  each `transact-ok` behind it waits for that apply.
- After the 17:33 relaunch the live recording's first transcript page took 47.4 s to arrive
  (`recording.query.detail.pages-complete`), and every one-shot read ($files, progressiveMediaStreams,
  recordingAttachments) failed at the fixed 5 s acknowledgement wait as "Network or live transport failed" while the
  socket was open and frames were applying. The playback screen showed that text (`playback.audio.load-error`); it is
  the message he read aloud at 17:34.

Upstream: the server drops a queued refresh a newer one supersedes (`session.clj`, `combine [:refresh :refresh]`
returns the second event); `Reactor.js` replaces a query's whole stored result on each `refresh-ok`
(`querySubs[hash].result = ...`), so applying only the newest restatement of a query leaves the same state;
`queryOnce` waits 30 s (`QUERY_ONCE_TIMEOUT`).

## Steps

1. This plan and its claims (plan-only commit) on main.
2. Red (`InstantFollowerLatencyTests`, scripted sockets as in `InstantLiveConnectionSurvivalTests`):
   - refreshes buffered behind a long apply: the applier applies only the newest restatement of a query, ends where
     applying every frame ends, and the acknowledgements buffered among them apply without a refresh apply between;
   - a follower under a replayed recording load (the writer's lines at the phone's measured rate, the follower's own
     outbox deep): the newest line is applied within two applies of its arrival however deep the buffer was;
   - a one-shot read whose answer waits behind frames that keep applying for more than 5 s is answered; on a socket
     that delivers nothing it still fails 5 s after the last progress.
3. Green: `InstantLiveReceivedFrames` drops, on buffering a `refresh-ok`, the computations it restates from older
   buffered `refresh-ok` frames (never from a frame carrying `attrs`, never across a lower processed-tx-id), and
   removes a frame left with none; `queryOnceThroughLive` waits for its acknowledgement until 5 s pass without the
   connection delivering a frame or the applier finishing one, within upstream's 30 s.
4. A receive summary once a minute (frames taken, refreshes skipped, computations dropped, deepest buffer, the
   longest and median wait from the reader to the applier), at notice when a frame waited 1 s or more.
5. FOOTGUNS entry; the focused suites and the whole bundle on the Mac mini through build.sh; release v1.9.68 (or the
   next free version); pin it in Scribe, cut and install on the iPhone and the iPad; measure the follower on the iPad
   (receive summary, applies per refresh received, one-shot timeouts) before/after on #1796 and #1797.
6. Scribe side (short-lived branch of realtime-voice): a one-shot read that timed out is not a dead end on the playback
   screen; the follower's line latency (createdAt on the writer to shown on the follower) logged as p50/p95/max a
   minute, if no such metric exists.

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` (InstantLiveReceivedFrames, the receiver loop's take
  bookkeeping, the receive summary; not sendMutations/send/serverAttributes (#1492), not query registration (#1131))
- `Sources/InstantSwiftDataCore/InstantRuntime.swift` (queryOnceThroughLive's acknowledgement wait only; not
  applyLiveRefresh or performApplyServerTransaction (perf-recv-1797), not transact (#1648, perf-send-1797))
- `Tests/InstantSwiftDataCoreTests/InstantFollowerLatencyTests.swift` (new)
- `docs/FOOTGUNS.md`, `CHANGELOG.md`, `PROGRESS.md`, `docs/releases/v1.9.68.md`, `docs/audits/commit-changelog.md`

## Conflict check

- perf-recv-1797 (#1109, #1127 step 7, #590): they make each apply cheaper inside applyLiveRefresh and its planning;
  I make the applier skip applies a newer frame supersedes and stop one-shot reads failing behind it. Their step 7
  (acknowledgements and one-shot answers on arrival) is this plan's steps 2-3; I write on their channel.
- perf-mem-1797 (#1165, #1145, #1500): no shared code.
- perf-send-1797 (#653): the send path stays theirs.
- Channel: agent-presence/_channels/2026-11-04-perf-sync-1796.md

## Amendment 1 (2026-11-05 04:00 EST, claude-code/perf-sync-1796@pp)

Scope the branch already holds, recorded here before it lands, and one measurement slice for #1129.

- `Sources/InstantSwiftDataCore/InstantRuntime.swift`: a standard query's and an infinite query page's registration
  name their query's namespace in the operation gate's phase (`reload <ns>`, `answer <ns>`; red fac02655, green
  d7502832). Why: at a tablet's launch one registration held the gate 4,583 ms with its connect and 7 callers behind
  it, unnamed (#1131, #1137). Phase marks only; the registration's work and order are unchanged.
- `Tests/InstantSwiftDataCoreTests/InstantWriterFollowerLatencyTests.swift` (new: a writer and a follower runtime under
  the tablet's measured load) and `InstantObserverRegistrationGateTests.swift` (one test and its helper).
- `docs/releases/v1.9.71.md` (the release record; v1.9.68-v1.9.70 went to other lanes).
- #1129 (measurement only): `pruneLiveQueryResults`, `pruneLiveQueryResultsBatch` and
  `pruneReleasedLiveQueryResultChunk` name each phase in both gates' phases (choose, residency, apply, retract) and
  time it; a batch that held the gates 1 s or more logs one notice with each phase's milliseconds and the batch's
  counts. Why: on 2026-11-04 the Mac's prune held the server-apply gate 4.5-13.1 s per batch (refreshes waited behind
  each) and the phone's held a recording's first write 1.25 s, with batches still capped at 1,000 facts, so a phase
  that does not follow the batch size is unnamed. What a batch removes, and when, is unchanged. New test file
  `Tests/InstantSwiftDataCoreTests/InstantPruneBatchPhaseTests.swift`. perf-mem-1797's later #1500 prune work keeps the
  prune's decisions; this only times them (told on their channel).
