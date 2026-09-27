# Plan: server-apply catch-up must not hold local writes behind the operation gate (#277, then #278)

Owner: claude-opus-5.5 triage agent L, 2026-09-27. Branch agent/claude-opus-5.5/triage-l-operation-gate-2026-09-27
from agent/claude-opus-5.5/triage-integration-2026-09-27.

Evidence: Scribe device pull 2026-09-27 13:53:47, `serial-gate.stalled`: holder "catch up server apply"
held the operation gate 5,632 ms while `transact` waited 5,057 ms; 439 pending mutations after 3 minutes
offline. The server-apply phases under the gate are not logged, so the slow phase is unknown.

1. Instrument: a phase label on the operation gate holder, one `server-apply.operation-gate-held`
   diagnostic per apply with phase durations, and `serial-gate.waited` when a waiter queues past 250 ms
   (who waited, how long, which holder and phase).
2. Reproduce: a phone-shaped test (large connected pending tail, base store, concurrent local transact)
   measuring the local transact's wait and each phase under the gate.
3. Fix the slow phase so local transacts complete within their normal budget, keeping rejection
   isolation, offline ordering, and the optimistic peel and replay (cite upstream Reactor.js).
4. #278: quarantine a row whose selected field fails to decode instead of failing the query, with a loud
   report; consider a one-time local repair for partial rows left by the pruning bug.

Touches: Sources/InstantSwiftDataCore/AsyncSerialGate.swift, InstantRuntime.swift (server apply),
SQLitePersistenceStore.swift (if the commit or row decode changes), new tests.
