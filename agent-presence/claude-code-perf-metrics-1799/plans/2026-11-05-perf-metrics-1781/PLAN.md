# Plan 2026-11-05-perf-metrics-1781: each query's time to its first answer, and that answer's rows

- planId: 2026-11-05-perf-metrics-1781
- agentId: claude-code/perf-metrics-1799@pp (tools/agent-run, claude/pp, opus)
- role: grower (one new measure on the existing wire meter; issue #1781 asks for it: a per-query record of shape,
  time to first result, rows, bytes and CPU, charted per build)
- issues: #1781 (criterion 1), epic #1783, ledger #1797
- branch: agent/claude/perf-metrics-1781, worktree ~/Sync/worktrees/perf-metrics-1781-instant; the green lands on main
  and rides the next free v1.9.x

## Why (measured)

The host app's energy ledger already carries, each minute, every query shape's answers and bytes (`receivedByQuery`,
#1117) and the library's CPU by operation (`InstantEnergyMeter`). What no line carries is how long a query waits for
its first answer: the library's only first-answer timings are the local observer's (`startup.query.*`), and a launch's
first lines reached the screen 12.1 s after start on 2026-11-04 (#1309) with no way to tell which query waited. CPU per
shape is derived off the device from the ledger's measured receive CPU and each shape's bytes (rule: a diagnostic adds
no per-event work where a derivation will do), so this plan adds only what cannot be derived.

## Design (per subscription, never per refresh)

1. `InstantURLSessionLiveWebSocket.send`: for an `add-query` frame, note its `client-event-id` with the query's shape
   (`InstantWireMeter.queryShape(of:)`) and the uptime clock, before the frame is handed to URLSession (the actor is
   reentrant: an answer can arrive before `send` resumes); a failed send drops the note. At most 256 notes wait.
2. `receive`: an `add-query-ok` or `add-query-exists` echoes the asking frame's `client-event-id` (upstream
   `instant/reactive/session.clj` `handle-add-query!`); its note gives the wait, and the answer's rows are its
   `join-rows` triples (once per subscription; `add-query-exists` carries none). An `error` with that id drops the note.
3. `InstantWireSnapshot.firstAnswersByQuery`: per shape, answers, total wait, answers that waited 5 s or more (the
   codebase's bound for any wait), and rows; subtracts like the other counts, bounded at 48 shapes like
   `receivedByQuery`; `network.wire-summary` names the three longest waits.
4. The host app reads it once a minute at its ledger's own call (its `net.instant.queries` reader), never per frame.

## Tests (red first, on the mini)

`InstantWireMeterTests`: a first answer through the loopback socket is timed under its shape with its rows; an
`add-query-exists` and an `error` close the note; a send that fails leaves none; notes are bounded; the minute's
subtraction and summary; a slow (5 s or more) answer is counted apart.

## Touching

- `Sources/InstantSwiftDataCore/InstantWireMeter.swift` (the snapshot's first answers, the storage's record call, the
  notes type)
- `Sources/InstantSwiftDataCore/InstantLiveTransport.swift` (only `InstantURLSessionLiveWebSocket`: its stored notes,
  `send(_:)` and `receive()`; not the delivery pump, `sendMutations` or `send(_:through:)` (perf-send-1797), not the
  receive buffer or the receiver loop (perf-sync-1796))
- `Tests/InstantSwiftDataCoreTests/InstantWireMeterTests.swift`
- `CHANGELOG.md`, `docs/audits/commit-changelog.md` (entries only)

## Conflict check

- perf-send-1797 (#653): its claim on InstantLiveTransport.swift covers the send path (`sendMutations`,
  `send(_:through:)`); I touch only the URLSession socket's own `send(_:)`/`receive()` bodies, three lines each.
- perf-sync-1796 (#1796): the receive buffer and the receiver loop in InstantRuntimeLiveSession.swift stay theirs; the
  socket's `receive()` gains one lookup after its decode.
- perf-recv-1797 (#1109): the refresh path is untouched (no per-refresh work added).
- Channel: agent-presence/_channels/2026-11-05-perf-metrics-1781.md
