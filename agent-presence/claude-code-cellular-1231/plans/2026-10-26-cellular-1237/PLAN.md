# Plan 2026-10-26-cellular-1237: the live socket and storage requests prefer a network that is not expensive, and the socket moves back to one

- planId: 2026-10-26-cellular-1237
- agentId: claude-code/cellular-1231@strangelearning
- role: grower (a fix ordered on #1237 and #1231; the consuming app's brief: "every upload that is allowed on cellular
  today stays allowed")
- issues: #1237 (primary), #1231, #1214

## Why

On one device (#1231, #1237) the live socket failed with POSIX 57 ("Socket is not connected") while the device's Wi-Fi
had trouble, reopened 4 s later over cellular, and stayed there for the rest of the session (57 minutes) while Wi-Fi was
associated again and carried other apps' traffic; the app's storage uploads stayed on cellular too: 368.2 MB, 341.2 mWh
of the battery by the device's own accounting. Nothing in the library reopens an open socket when a better path returns
(`InstantRuntimeReconnectController`: "no listener runs while the connection is up"), and URLSession keeps reusing a
pooled storage connection that steady requests never let idle.

Measured on a Mac (loopback, this SDK): URLSession keys a pooled connection by the request's network policy, so a
request with `allowsExpensiveNetworkAccess = false` never reuses one opened for a request that allowed expensive
networks; `URLSession.flush` did not force a new connection; a task's own delegate receives `URLSessionTaskMetrics` for a
completion-handler upload task.

Upstream `Reactor.js`: its `NetworkListener` calls `_startSocket()` on every change to online, and `_startSocket` closes
an open previous transport ("to be safe right now we always create a new socket"). Apple ("Reducing networking and
Bluetooth power usage"): "To prevent network tasks from using an expensive network, set allowsExpensiveNetworkAccess to
false. Postpone nonessential tasks until a nonexpensive network, such as Wi-Fi, becomes available", and back off retries
exponentially "to prevent energy-draining retry loops".

## Design

1. The system path monitor keeps the path's cost (satisfied, expensive, constrained, interface kind) and a generation
   that changes with it, and logs `network.path-changed` at notice when they change (no line today says when the path
   changed).
2. A route preference, one per path (`InstantNetworkPath`): new connections ask for a route that is not expensive while
   the path is satisfied and not expensive, unless such an attempt was refused under the same path within its backoff
   (1 minute, doubling to 32); a success resets it. Pure state, tested by table.
3. The socket: `InstantLiveSessionRequest.allowsExpensiveNetworkAccess` (default `true`, so custom transports and the
   upstream shape are unchanged); the runtime sets it per attempt from the preference; the live transport opens its task
   from a `URLRequest` that carries it. A not-expensive attempt that fails to open counts as refused, so the next attempt
   may use any network: the socket never stays down because only cellular works.
4. The move: a session that opened allowing expensive networks is replaced, through the reconnect controller, on the
   first path change to satisfied and not expensive after it opened, or when a not-expensive storage request succeeds
   after a refusal; at most once a minute; `network.path-reconnect` at notice with the path at open and now. No error is
   recorded: the outbox, queries, rooms and streams resume as on any reconnect (upstream `_startSocket`).
5. Storage: the live HTTP client asks for a route that is not expensive when the preference says so and the caller's
   request allowed expensive networks, and sends the caller's own request at once when the system refuses that
   (`URLError.networkUnavailableReason == .expensive`); a caller's refusal is never widened. Each response carries the
   route its transfer used (`InstantStorageHTTPResponse.route`, from the task's `URLSessionTaskMetrics`).
6. `InstantNetworkRouteMeter.snapshot()`: the open socket's access, its moves and refused attempts, for an app's energy
   ledger.

## Steps

1. This plan and its claims (plan-only commit on main).
2. Red: `InstantNetworkRouteTests` (the path's generation, the preference table, the runtime's attempts and move over a
   scripted transport and path, the outbox delivered after the move, one move a minute, a socket opened on a route that
   is not expensive stays), `InstantStorageRouteTests` (prefer, fall back on refusal, never widen, the route of a real
   loopback upload).
3. Green; the focused suites; the whole `InstantSwiftDataCoreTests` bundle with `scripts/known-failing-tests.sh`.
4. Release 1.9.44: docs/releases/v1.9.44.md, CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md; the app pins it.

## Touching

Sources/InstantSwiftDataCore/InstantNetworkPath.swift, Sources/InstantSwiftDataCore/InstantNetworkPathWaiting.swift,
Sources/InstantSwiftDataCore/InstantLiveTransport.swift (the session request's access, the live socket's request),
Sources/InstantSwiftDataCore/InstantRuntime.swift (the attempt's access, the move's scheduling and watcher only),
Sources/InstantSwiftDataCore/InstantRuntimeReconnectController.swift, Sources/InstantSwiftDataCore/InstantStorageTransport.swift
(the live HTTP client's preference, fallback and route), Sources/InstantSwiftDataCore/InstantNetworkRouteMeter.swift
(new), Tests/InstantSwiftDataCoreTests/InstantNetworkRouteTests.swift (new),
Tests/InstantSwiftDataCoreTests/InstantStorageRouteTests.swift (new), docs/releases/v1.9.44.md (new), CHANGELOG.md,
PROGRESS.md, docs/audits/commit-changelog.md.

## Conflict check

The last claims on these files (energy-98, hotpath-1007, fix-storage-1076, fix-memory-1075, server-apply-932) are
released in 1.9.42 or earlier; main has no source commit since 1.9.43 (13dbc935). Channel
agent-presence/_channels/2026-10-26-cellular-1237.md.

## Amendment A (2026-10-26 22:45): Wi-Fi Assist, not a path change

The device's unified log (sysdiagnose 17:31, `log show`) shows the path never changed: configd and symptomsd kept en0
primary all hour, and wifid shows the same access point with no drop or roam until 15:59:28. The Wi-Fi's internet link
failed about 15:03:40-15:04:24; Wi-Fi Assist (symptomsd "rnf", fallback "preferred" from 15:03:58) opened the socket's
reconnect over pdp_ip0 after its en0 SYNs went unanswered, and the storage connection (QUIC/HTTP3) migrated to pdp_ip0
"because PTO count is > 3" and marked en0 unreachable for good; 618 later tasks reused it. "Better alternate path
available" reached the socket at 15:03:50 with no handler. So a path-change trigger alone would never have fired: the
socket's attempts ask for a route that is not expensive whenever the path has one (falling back once), and a socket on
any network moves on a path change, on a storage request's recovery after a refusal, or on a probe after the backoff.
Storage requests fall back on a timeout only for small uploads, so a storage stall (#1233) never sends a large body
twice. The watcher is its own value type and never holds the runtime while it waits.
