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
9. Add an explicit local deferred-value residency policy keyed by stable attribute id. Keep eligible cardinality-one, non-ref, non-indexed payloads in SQLite instead of hot triple indexes; hydrate only selected paged values while preserving exact optimistic update, restart, and rejection behavior.
10. Keep local infinite-query ordering observation payload-free, slice the visible page before deferred hydration, hydrate only newly exposed page identities when the raw sequence is unchanged, and emit one typed persistence failure snapshot if hydration cannot complete.
11. Couple deferred hydration to the exact hot-store sequence under the operation gate, dropping stale emissions instead of combining identity metadata with payload bytes from another revision; make pre-bootstrap live paging expand payload-free identity/order rows and hydrate only newly visible IDs.
12. Add a reusable infinite-query retention policy that defaults to accumulated pages and can retain a bounded contiguous cursor window. Support exact next/previous navigation, evict live chunks and cancel their subscriptions, and prune hydrated snapshots/cache entries to the retained page window under page growth and local reorder/prepend.
13. Replace server transaction apply/rebase queue hydration with compact indexed component planning and streamed 50-body / 8-MiB pages. Preserve Reactor's authoritative-server-then-local-overlay order, prove exact store/row/closure revisions before each targeted commit, and cover disjoint 10,000-row work, connected components above both page ceilings, retractions/global/ref/lookup/deferred effects, watermarks, failed-active roots, confirmation-proven rows, empty operations, and race restarts.
14. Replace storage upload whole-file `Data` construction and `URLRequest.httpBody` retention with a file-backed request source. Preserve canonical PUT headers, response/error behavior, cancellation, and local persistence, and prove a large file reaches the transport as a URL plus exact byte count without a file-sized in-memory request payload.
15. Split persistence validity into reusable store, attribute, outbox, and query-result revision domains. Routine outbox lifecycle, automatic retry, query-result persistence, and server refresh metadata must adopt the still-valid materialized store without a full SQLite snapshot load, store reconstruction, or runtime `replaceSnapshot`; a true external store mutation must still reload exactly once.
16. Make custom live connection creation itself a cold, per-call, immediately abortable attempt. Acquire and validate the exact abort operation before awaiting connector work; hard-bound runtime and validation connection creation to five seconds; abort late-returning sessions; preserve attempt/session identity through decorators; retain the legacy constructor only as an explicit pre-work rejection path.

## Acceptance

- One WebSocket acknowledgement decodes and writes one durable outbox row, independent of failed/pending backlog size.
- Delivery hydration is bounded before JSON decode and never exceeds the admitted window plus a documented small lookahead.
- Duplicate acknowledgements and terminal errors do not reconnect, kill the receive loop, or resubscribe queries.
- No global gate performs O(all outbox bodies) work on the normal acknowledgement path.
- Fifty eligible offline same-entity upserts compact to one without losing local materialization or final/delete/media barriers.
- Exact TypeScript/self-host materialization parity and all local durability/rejection tests pass.
- A same-scenario physical trial shows the predicted decode/reclaim/head-of-line counters collapse and host physical footprint improves; otherwise the hypothesis is not verified.
- A route-free query decodes no configured deferred payload bytes, selecting one page hydrates only that page, and local optimistic update/restart/rejection remains exact.
- Local infinite queries preserve out-of-window reorder semantics without decoding deferred values outside the visible window, and deferred hydration failure is observable as one typed failed snapshot rather than a silent stream end.
- Deferred query snapshots never mix a hot-store identity/order revision with deferred payload from another revision, and three stalled-live-bootstrap pages of two decode exactly six selected deferred values rather than repeatedly hydrating the cumulative window.
- A two-page infinite-query window stays at two pages after one hundred forward loads, reports exact next/previous identifiers and capabilities, cancels evicted live page subscriptions, remains capped after local reorder/prepend, and retains no deferred decoded/cache/snapshot values outside the contiguous window.
- `uploadFile(from:)` never constructs a whole-file `Data` or assigns a file-sized `URLRequest.httpBody`; the live transport uses a file-backed URLSession upload and focused tests preserve headers, success/error decoding, cancellation, and local save cleanup behavior.
- After bootstrap, thousands of scalar outbox/query-only events produce zero full store snapshot loads, reconstructions, or replacements; a second runtime's real triple-store mutation invalidates the store revision and forces only the necessary safe reload.
- A cancellation-insensitive custom connector cannot retain runtime or validation work: every supported connection attempt exposes its exact synchronous abort before async work, times out or cancels within five seconds, aborts a session returned after abandonment, and remains independent from overlapping attempts created by the same client.
