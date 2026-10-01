# Plan: build 78's library: server errors keep the socket, failed live queries recover and say so, duplicate writes are not refused, and the build 78 robustness queue (#376 #360 #303 #317 #329)

- planId: 2026-10-01-library-78
- agentId: claude-opus-5.5-library-78 (issue tracker: claude-code/claude-opus-5.5/library-78)
- role: mower (removes reconnect churn, silent query loss, refused duplicates, gate stalls, and whole-stream re-reads;
  the only new public surface is the live-query error a subscriber receives)
- Branch: agent/claude-opus-5.5/library-78 from library-77 956fce52 (build 77's library)
- Goal (Michael, verbatim): "fix this please so it works efficiently as as well as the typescript core library"
- On refused writes (Michael, 2026-10-01, verbatim): "I want to know why rights are refused in the first place? I don't
  think they really should be"
- On reconnects (Michael, verbatim): "I don't really understand why it would do that, reconnecting song and dance or why
  what was causing the problem. Why couldn't it just reconnect? Yeah, why are the reconnects there in the first place?"

Steps (no code here; a red test first in each, upstream `Reactor.js` / `Stream.ts` at e7101761 as the reference):

1. #376: a retryable server error on a write (500 operation-timed-out and the other transient statuses) keeps the
   socket. The write stays pending and is offered again on the same socket after a backoff that grows across its
   consecutive failures, with jitter. Only a dead socket (close, missed pings) reconnects. Test: a scripted socket that
   answers one transact with 500 several times; one connection, growing gaps, the write lands.
2. #360: an add-query answered with a server error reaches the query's subscribers (upstream `notifyQueryError`), and
   the query is sent again on the same socket with a growing backoff. Tests: subscribe() and the infinite query keep
   their stream, see the error, and refresh after the window without a reconnect.
3. Refused writes that are only duplicates: a pending write whose every attribute a newer accepted write of the same
   entity already covers is not offered again; a replay refusal whose effect is already in place resolves as
   superseded, not failed. Test: a lost acknowledgment followed by a newer accepted write; the large-store drop shape.
4. Merge the exclusive server-apply fallback (agent/claude-opus-5.5/library-78-apply-fallback, a8030bbe).
5. acceptMutation's 5-attempt exhaustion ("The local outbox changed repeatedly while updating mutation"): name what
   moves the outbox revision while the gate is held, and fix it. Test reproduces the exhaustion.
6. pruneLiveQueryResults holds the operation gate 5-13 s while transacts wait: bound the hold. Test: a transact is not
   delayed behind a large prune.
7. A local-first queryOnce: rows already on the device answer without waiting on the socket (#317). Test: queryOnce
   with a stalled socket returns the stored rows.
8. Streams: incremental snapshots (keep materializeMedia's cumulative contract); a finished stream's reader
   unregisters; an unrouted stream-reader error does not reconnect; #329 streams written offline reach the server, with
   the client id versus server id decision written up (ADR 0017).
8a. P0 from the list-crash agent (Scribe #388, added 2026-10-01 18:20): a windowed live infinite query's snapshot can
   list one entity twice (Scribe's list traps on it), and the window shows no rows for about 0.6 s at a kickstart.
   Their failing test goes in first (InstantInfiniteQueryDuplicateRowsTests), then the fix in pushSnapshot.
8b. A caller that cancels while its message is being sent no longer ends the socket (found while checking the #388
   property tests: a cancelled chunk's add-query send aborted the session).
9. Gates on the final head: differential and connection survival, the ten suites, the 211 infinite-query tests, the
   library-77 and new tests, the phone-shaped replay, the Recording 023-shape backlog, the large-store drop A/B against
   956fce52 (2+ interleaved pairs), a 30-minute calibrated-car soak on Scribe main, the companion fault scenarios
   (burst, transact-burst, burst-then-reconnect), and the replay benchmark.

Touching:

- Sources/InstantSwiftDataCore/InstantRuntime.swift, InstantRuntimeLiveSession.swift, InstantLiveTransport.swift,
  SQLitePersistenceStore.swift, InstantSnapshotObservers.swift, InstantModels.swift, InstantInfiniteQuery.swift,
  BoundedOutboxDelivery.swift, and new InstantServerErrorRetryPolicy.swift and InstantLiveQueryErrors.swift (added
  2026-10-01 13:10)
- Sources/InstantSwiftData/InstantSwiftData.swift and InstantTypedAPI.swift (added 2026-10-01 13:36: the typed infinite
  snapshot keeps its rows with a live-query error), and Tests/InstantSwiftDataTests: new
  InstantLiveQueryErrorSubscriptionTests.swift (added 2026-10-01 13:10)
- Tests/InstantSwiftDataCoreTests/InstantInfiniteQueryDuplicateRowsTests.swift (new) and
  InstantInfiniteQueryLeadingRowsTests.swift (the model server's forward-answer hold only), added 2026-10-01 18:55 (#388)
- Tests/InstantSwiftDataCoreTests: new InstantTransientMutationRetryTests.swift, InstantLiveQueryErrorRecoveryTests.swift,
  InstantSupersededReplayTests.swift, InstantOutboxRevisionGateTests.swift, InstantPruneGateHoldTests.swift,
  InstantLocalFirstQueryOnceTests.swift, InstantStreamRobustnessTests.swift; existing InstantLiveTransportTests.swift,
  InstantReactorParityTests.swift, InstantBoundedServerApplyRebaseTests.swift (the apply-fallback merge)
- docs/adr/0017-streams-written-offline.md
- CHANGELOG.md, docs/audits/commit-changelog.md, PROGRESS.md

Conflict check (2026-10-01 12:55 EDT): the latest claims on these paths are library-77 (finished, this branch's base),
the apply fallback (finished, merged here in step 4), and ts-parity-experiments (closed at 9fe19555, not merged). The
account-linking plan shares only CHANGELOG.md, PROGRESS.md, and docs/audits/commit-changelog.md, which every branch
prepends; merges resolve them in timestamp order.
