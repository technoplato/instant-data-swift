# Plan 2026-11-07-sync-diagnostics-2037: the connection status says why changes are not reaching Instant

- planId: 2026-11-07-sync-diagnostics-2037
- agentId: claude-code/sync-diagnostics-2037@ld (tools/agent-run, claude/ld, opus)
- role: grower (ordered on #2037: a typed cause in place of a plain error string), compressed where it can be
- issues: #2037 (this), #2028 (replays refused after a dropped socket: a separate fix in the outbox), #2027 and #1834
  (Instant's rate limits and the traffic an app needs), #669 and #1237 (the network path the reconnect loop already reads)
- branch: agent/claude/sync-diagnostics-2037 (worktree ~/Sync/worktrees/sync-diagnostics-2037-lib)

## Why (read in the code and upstream before any change)

- `InstantConnectionStatus` says `.errored` with `lastErrorMessage = String(describing: error)`: an app cannot tell a
  weak signal from no network, a server that does not answer, a rate limit or a refused sign-in. Every socket-level
  failure passes through `saveErroredConnectionMetadataWithGateHeld(message:)`, where the error is turned into text.
- Being offline reads as the five-second open timeout ("Timed out after 5000ms waiting for Instant live transport."):
  the socket's URLSession waits for connectivity, so only the network path (`InstantNetworkPathMonitor`, already read by
  the reconnect loop) tells "no network" from "a network that does not carry the connection in time".
- A dropped socket saves `.errored` in `scheduleReconnect` but publishes nothing, so an observer learns of it only at
  the next unrelated publish; failed reconnect attempts publish nothing either.
- Rate limits: upstream sends a rate-limited operation over the socket as an `error` frame with `status` 400 and
  `type` "rate-limited" (session.clj, exception.clj), and the socket stays open; over HTTP it is a 429. The retry time
  is only in the hint (`retry-at`, ISO 8601; `retry-after`, whole seconds); no `Retry-After` header is set anywhere.
  Today the library reads 429 as transient but a 400 as a refusal: a rate-limited write would fail for good and a
  rate-limited live query would be retired until relaunch. An `error` frame during `init` also loses its status, type
  and hint.

## Steps, red then green

1. Red, pure: `InstantSyncInterruption` and its classifier. A transport failure on a satisfied path is a weak network,
   on a missing path no network; a refused or unresolvable host, a TLS failure or a 5xx is the server not reachable; a
   `rate-limited` type (any status) or a 429 is a rate limit with the hint's retry time; a refused sign-in is
   authentication; a synchronization blocker is a local repair; anything else is other. Each says whether queued changes
   are kept (always: the outbox is durable) and whether it ends on its own.
2. Red, runtime (the scripted transports): a dropped socket publishes `.errored` with its interruption at once; a
   five-second open timeout on a missing path says no network, on a satisfied cellular path a weak network; the next
   open clears it; a rate-limited write stays pending and is offered again no sooner than the server's retry time, and
   the status says rate limited until the server answers again; a rate-limited live query is sent again, not retired;
   an `init` error keeps its status, type and hint.
3. Green: `InstantSyncInterruption.swift` (new); `InstantConnectionStatus.interruption`; the errored funnel takes the
   error and stores its interruption beside the last error (one persistence turn, as #403), the path read when the
   status is made; `scheduleReconnect` and a failed attempt publish when the interruption changed; the rate-limit frame
   is transient for writes, queries and `InstantWriteFailureKind`, and its retry time sets the earliest next offer.
4. Diagnostics: the connection failure events carry the interruption's cause and the path, so a device's log says why.
5. Release (docs/releases, tag), CHANGELOG, PROGRESS, the commit ledger; the consuming app pins it.

## Touching

- Sources/InstantSwiftDataCore/InstantSyncInterruption.swift (new)
- Sources/InstantSwiftDataCore/InstantModels.swift: `InstantConnectionStatus` only
- Sources/InstantSwiftDataCore/InstantRuntime.swift: the connection metadata funnel and status inputs,
  `scheduleReconnect`'s publish, the error-frame routing predicates (`isRetryableMutationError`,
  `addQueryRejectionRepeats`) and the rate limit's earliest next offer
- Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift: the `init` error's server fields only
- Sources/InstantSwiftDataCore/InstantWriteFailureKind.swift: `serverFailureKind` only
- Sources/InstantSwiftDataCore/InstantServerErrorRetryPolicy.swift: a server retry time as the earliest next attempt
- Tests/InstantSwiftDataCoreTests/InstantSyncInterruptionTests.swift (new),
  Tests/InstantSwiftDataCoreTests/InstantConnectionInterruptionTests.swift (new)
- docs/releases/, CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md, skills/instant-data/SKILL.md (the status)

Conflict check: replay-2028 (#2028, not yet on main) changes InstantRuntime.swift's refusal coverage and
InstantServerErrorRetryPolicy.swift's one-at-a-time probe; this plan touches neither function and rebases on it.
perf-sync-1796, ack-session-1942 and perf-send-1797's claims name other functions.

## Not this plan

The outbox's replay refusals (#2028). The traffic itself (#2027 cut the admin callers; #1834 holds what a fork would
change). Reconnect timing: it already matches upstream (1 s steps to 10 s, at once when the path returns).
