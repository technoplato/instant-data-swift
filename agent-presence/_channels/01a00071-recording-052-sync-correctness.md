# Recording 052 sync correctness

- Owner: `codex-desktop/01a00071-f1c1-7193-adcd-3bc9f30b5f95/root`
- Plan: `2026-08-15-local-write-server-refresh`
- Instant issue: `#008`

- 2026-08-15T23:58:00-0400 plan-to-touch — root owns only the long
  server-apply preparation versus short local-write commit boundary in
  `InstantRuntime.swift` and one deterministic revision-race contract in
  `InstantBoundedServerApplyRebaseTests.swift`. Historical owners are inactive
  and their frozen sections remain unchanged. The test must prove a local
  transaction reaches durable SQLite while server apply is paused, then prove
  server apply retries and preserves both authoritative and optimistic state.
  No timeout increase, dropped refresh, weakened receipt check, Scribe data
  reset, or unrelated Runtime edit is authorized.

- 2026-08-16T00:20:00-0400 plan-to-touch expansion — the one-write regression
  passed but the continuous-write regression exhausted all five complete
  server-apply retries. Root additionally owns only the bounded SQLite
  server-apply plan extension needed to capture exact newly appended Runtime
  mutations, replay them over the prepared server result, and commit them
  atomically. Existing rows, receipts, claims, wire intent, and revision races
  must remain fail-closed. No retry-count increase or long operation-gate hold
  is authorized.

- 2026-08-16T01:31:47-0400 verification — the complete
  `InstantBoundedServerApplyRebaseTests` suite passes 24/24 after a current-source
  rebuild. The complete `InstantOutboxSupersessionIntegrationTests` suite passes
  22/22 with only its three declared quarantine known issues. The final design
  gives server refresh its own gate, catches up append-only local writes without
  holding ordinary local writes for the long plan, persists rebased peer writes
  before hot publication, preserves closure/claim/acceptance checks, bounds peer
  catch-up, and lets explicit close finish under sustained peer writes.
