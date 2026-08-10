# Plan 2026-08-09-bounded-intent-outbox-memory

Owner: `codex-desktop/019fe994-1250-7b42-825e-9b75836d9173/root`
Mode: mower
Issues: #044, #155

## Outcome

Make normal Instant acknowledgement and delivery work proportional to the affected mutation or admitted send window, not the complete durable outbox. Keep the WebSocket reader able to read later acknowledgements while ordered persistence work runs. Preserve exact optimistic/offline semantics and five-second failure visibility.

## Evidence being tested

Each `transact-ok` currently reconstructs all pending, confirmed, and failed mutation bodies before updating one row. Delivery decodes and sorts every pending/confirmed body before sending at most 50 mutations / 256 transaction steps. Server refresh and terminal rejection likewise peel/rebase all durable successors under the global operation gate. In the physical run, this co-traveled with 212 acknowledgement-timeout reclaims, 58 head-of-line waits, a 4.37-second `failMutation` gate hold, and rapidly increasing backlog.

## Steps

1. Add decode-count and lifecycle tests at a ten-thousand-row outbox shape. The tests must show that accepting one mutation decodes/updates one row, duplicate acceptance/error is idempotent, and delivery decodes only a bounded candidate window.
2. Add revision-checked SQLite primitives for mutation-ID load/update/delete and pending counts. Update the compact resident outbox shell by ID. Do not rebuild or diff the full array for `transact-ok`.
3. Select the oldest delivery window in SQL before JSON decoding. Enforce both mutation and step budgets without hydrating the entire queue; keep visible-write correctness and ordering explicit.
4. Wire durable same-entity supersession only for proven eligible pending upserts. Preserve in-flight, failed/poison, delete, link, media, and barrier/multi-entity semantics. Test 50 offline open-segment-shaped writes leave at most one eligible row per key.
5. Make duplicate terminal server errors idempotent, keep the socket alive, and remove the current registered-query remove/add refresh after a mutation error. Add wire-frame assertions.
6. Move terminal-failure overlay recomputation outside the short operation-gate compare-and-swap section and restrict rebase work to successors that overlap affected visible-write/entity keys.
7. Record raw receive, reservation clear, handler start/end, durable acceptance, and next-read timestamps by mutation ID. Keep this diagnostic discrete and bounded.
8. Measure each slice independently in a process harness, then in the identical physical Scribe/ReplayKit scenario. If server refresh still scales with total pending overlay count, implement the separate authoritative-server store plus indexed optimistic overlay as the next isolated hypothesis.

## Acceptance

- One WebSocket acknowledgement decodes and writes one durable outbox row, independent of failed/pending backlog size.
- Delivery hydration is bounded before JSON decode and never exceeds the admitted window plus a documented small lookahead.
- Duplicate acknowledgements and terminal errors do not reconnect, kill the receive loop, or resubscribe queries.
- No global gate performs O(all outbox bodies) work on the normal acknowledgement path.
- Fifty eligible offline same-entity upserts compact to one without losing local materialization or final/delete/media barriers.
- Exact TypeScript/self-host materialization parity and all local durability/rejection tests pass.
- A same-scenario physical trial shows the predicted decode/reclaim/head-of-line counters collapse and host physical footprint improves; otherwise the hypothesis is not verified.
