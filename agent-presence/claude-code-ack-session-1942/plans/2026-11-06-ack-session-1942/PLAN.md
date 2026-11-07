# Plan 2026-11-06-ack-session-1942: one late write does not tear down a session that still delivers frames

- planId: 2026-11-06-ack-session-1942
- agentId: claude-code/ack-session-1942@pp (tools/agent-run, claude/pp, opus)
- role: mower (a fix at the cause, in the acknowledgement deadline's expiry; no new public API)
- issues: #1942 (P1, this), #1916 (the long recordings it fails on the Mac), #296 and #1383 (why the deadline is
  deferred behind a frame being applied, and how long), #1270 (lost acknowledgements make full rebases)
- branch: agent/claude/ack-session-1942 (worktree ~/Sync/worktrees/ack-session-1942), released per AGENTS.md

## Why (measured, before any change)

On the Mac (one app build, library 1.9.78, 2026-11-06 12:27-12:41, laptop load 105-300) one durable write that missed
its 6 s acknowledgement deadline expired its claim, and `releaseMutationReservations(_:timedOut:)` replaced the live
session (`generation += 1`, `session.abort()`): 16 `outbox.mutation.ack-timeout-batch` lines, each expiring exactly one
write, each followed by `connection.mutation-delivery-failed` and a reconnect, and every one-shot read in flight failed
(71 `query-once.failed` in the 12:00 hour; 2 in each of the two hours before, 0-3 in each hour after). One write missed at 6.3 s and was accepted 1.6 s
later on the next session: the old session was slow, not dead. One-shot reads that failed at the 12:40:39 replacement
had kept waiting through four 5 s stall windows, each of which needs a frame received, taken or being applied, so the
session was still delivering up to its deadline. From 13:00 to 20:00 (builds 286-293; the laptop's load then not
measured) the Mac logged no ack-timeout batch at all.

Upstream `Reactor.js` (`_sendMutation`) times a transact out after `max(6 s, in-flight x 6 s)` and fails that one
transaction; it never closes a socket for it. Swift keeps the write (a durable outbox) and replaces the session before
offering the same client event id again (the acknowledgement-unknown barrier); that barrier stays for a session that
went quiet.

## Steps

1. This plan and its claims (plan-only commit).
2. Red (`InstantBoundedOutboxDeliveryTests`, controlled clock and sleeps): a write whose answer is late while the session
   keeps delivering frames keeps its claim and its session, is sent once and accepted on the first connection; a late
   write is kept only up to the deferral limit (120 s) and then expires as today; a session that delivers nothing past
   the deadline is still replaced (guard).
3. Green: a delivery pass asks whether the session's applier took a frame within one acknowledgement interval (6 s);
   when it did, the claim admission keeps this claimant's claims that passed their deadline (moved one interval later,
   tokens kept) inside the same SQLite transaction that would reclaim them, so a wait for the operation gate cannot race
   it. The head kept past the deferral limit is given up as today. A frame being applied keeps its own deferral (#296,
   #1383) unchanged. Diagnostics: `outbox.mutation.ack-late-kept`, `outbox.mutation.ack-late-wait-exhausted`.
4. Release (docs/releases, tag), CHANGELOG, PROGRESS, commit ledger; pin in Scribe the way the 1.9.78 pin did (ten pin
   files); a build cut stays the commander's call.

## Touching

- Sources/InstantSwiftDataCore/InstantRuntime.swift: `InstantRuntimeAcknowledgementDeferral`,
  `deferAcknowledgementDeadlinesWhileAFrameIsApplied`, `runAutomaticMutationPumpPass`,
  `automaticOutboxTransportMutationsForDelivery`, one test hook
- Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift: a delivered-frame reading beside `receiveProgress()`
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift: `claimAutomaticOutboxDeliveryWindow` keeps late claims;
  `deferAutomaticOutboxClaimDeadlines` shares its shift
- Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift: one request field, one window field
- Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift (three new tests)
- docs/releases/, CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md

## Conflict check

The last claims on these paths are the 11-04 perf lanes (landed in 1.9.7x) and #1383 (1.9.52); the newest source change
on main is #696 (1.9.79, held writes; no overlap with claim expiry). No other agent has a library branch past
origin/main on these files.

## Amendment 1 (2026-11-06 21:15)

FOOTGUNS F65 gains its fourth piece (#1942, 1.9.80): a missed acknowledgement on a session that still delivers frames is
late, not lost; a deadline asks whether the session went quiet. Touching: docs/FOOTGUNS.md (F65's list entry and body
only). No other agent's claim on it since 2026-11-04.
