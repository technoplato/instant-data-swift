# 019fe994 memory root

- owner: `codex-desktop/019fe994-1250-7b42-825e-9b75836d9173/root`
- plan: `2026-08-09-bounded-intent-outbox-memory`
- mode: mower
- scope: row-addressed outbox lifecycle, bounded delivery hydration, receive-loop independence
- worker: `codex-desktop/019fe994-1250-7b42-825e-9b75836d9173/root/instant_bounded_outbox`
- split: worker owns bounded durable delivery selection in `SQLitePersistenceStore.swift`, `InstantRuntime.swift`, new `BoundedOutboxDelivery.swift`, and new focused tests; worker does not touch `OutboxSameEntitySupersession.swift` or its untracked claim
- scope-addition: root authorized the worker to update `Sources/InstantSwiftData/InstantSwiftData.swift` and focused `MutationDeliveryTests.swift` so wait-all reads a durable body-free summary instead of the bounded resident claim actor
- conflict: prior `2026-08-09-outbox-wire-hydration` claims are preserved; that agent is not live in the current agent tree
