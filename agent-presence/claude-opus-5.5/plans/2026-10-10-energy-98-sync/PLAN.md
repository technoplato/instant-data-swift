# Plan: a reconnect loop with upstream's backoff and network gating, an energy meter, and the outage's outbox (#669)

- **planId:** `2026-10-10-energy-98-sync`
- **agentId:** `claude-opus-5.5-energy-98-sync` (a helper of the energy-98 coordinator)
- **Role:** mower for the reconnect loop (fewer attempts for the same reconnects) and the outbox analysis; grower for
  the energy meter (user-ordered through #669: per-operation counters and signposts for the app's energy ledger).
- **Branch:** `agent/claude/energy-98-sync`, from `agent/claude/energy-98` at v1.9.8 (`61b9c226`). Added after the
  two red-test commits: the coordinator asked for no merge to main, so the plan rides on this branch.
- **Goal (the user, verbatim, 2026-10-10 23:09):** "We want all of our functionality but to reduce and eliminate any
  waste or spurious processor etc behavior" "Don’t remove any functionality, fix the underlying problems"
- **Issues:** #669 (the energy-98 umbrella), #653 (the write path; this plan only adds one-line meter hooks there)

## Steps (no code here), each a red test commit, then the change, measured before and after

1. Reconnect parity with `Reactor.js` `_scheduleReconnect`: the delay lives on the controller, grows 1 s per scheduled
   attempt to 10 s, resets only at `init-ok` (and a user change); no attempt while the transport's network path is
   missing (`NWPathMonitor` for the live transport), one as soon as it returns. The 5 s open deadline stays.
2. `InstantEnergyMeter.snapshot()`: per-operation count, thread CPU and wall time, plus transactions, outbox rows
   written and superseded, and reconnect attempts; os_signpost intervals for the same sections.
3. The outage's outbox: replay the recording's write timing with Scribe's write shapes, explain the depth, and measure
   any coalescing that changes nothing anyone can see (else a proposal with numbers).
4. Lowest priority: a store observer leak check for the observe-first-emission-cancel pattern and re-registration.

Touching `Sources/InstantSwiftDataCore/InstantRuntime.swift`, `InstantLiveTransport.swift`, new
`InstantNetworkPath.swift`, `InstantRuntimeReconnectController.swift`, `InstantEnergyMeter.swift`; one-line meter hooks
at the first line of functions in `SQLitePersistenceStore.swift`, `InstantStore.swift`,
`InstantLiveRefreshApplication.swift`, `InstantLiveMutation.swift` (the write helper owns those bodies); new tests
`InstantReconnectBackoffParityTests.swift`, `InstantEnergyMeterTests.swift`, `InstantObservationLifecycleEnergyTests.swift`;
and `CHANGELOG.md`. Added 2026-10-11 00:16 EDT.
