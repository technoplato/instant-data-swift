# Plan 2026-08-11-suite-green-and-latency

Owner: grok-build-wrap-perf
Mode: mower
Issues: #044, #150, #155

## Outcome
Full package test suite green on dirty freeze stack without weakening production timeouts; then commit coherent freezes; then execute Swift→TS-admin latency validation; iterate toward physical KEEP.

## Steps
1. Diagnose suite red (mixedCorruptWindow, SIGBUS, integration races).
2. Fix tests/source with minimal correct changes; keep 5s budgets.
3. Run focused then full `swift test --jobs 1 --no-parallel`.
4. Commit freeze slices + ledger.
5. Execute validate-swift-admin-latency.
6. Soak + device path as remaining KEEP.

## Touching
- InstantBoundedOutboxDeliveryTests, InstantMessageServerAcceptanceTests
- InstantRuntime, SQLitePersistenceStore as needed for fixture truth
