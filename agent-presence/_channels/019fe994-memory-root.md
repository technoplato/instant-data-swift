# 019fe994 memory root

- owner: `codex-desktop/019fe994-1250-7b42-825e-9b75836d9173/root`
- plan: `2026-08-09-bounded-intent-outbox-memory`
- mode: mower
- scope: row-addressed outbox lifecycle, bounded delivery hydration, receive-loop independence
- worker: `codex-desktop/019fe994-1250-7b42-825e-9b75836d9173/root/instant_bounded_outbox`
- split: worker owns bounded durable delivery selection in `SQLitePersistenceStore.swift`, `InstantRuntime.swift`, new `BoundedOutboxDelivery.swift`, and new focused tests; worker does not touch `OutboxSameEntitySupersession.swift` or its untracked claim
- scope-addition: root authorized the worker to update `Sources/InstantSwiftData/InstantSwiftData.swift` and focused `MutationDeliveryTests.swift` so wait-all reads a durable body-free summary instead of the bounded resident claim actor
- conflict: prior `2026-08-09-outbox-wire-hydration` claims are preserved; that agent is not live in the current agent tree
- supersession-slice: root reassigned this worker to conservative immediate durable-tail same-entity supersession. Worker now owns `OutboxSameEntitySupersession.swift`, the existing `SQLitePersistenceStore.swift` / `InstantRuntime.swift` claims, and new focused `InstantOutboxSupersessionIntegrationTests.swift`; the legacy untracked `grok-build` supersession marker is preserved and its agent is not live.
- supersession-finish: root reassigned the incomplete uncommitted slice from `instant_bounded_outbox` to `instant_supersession_finish`; the finisher owns those same paths, preserves the prior worker's edits, and will freeze the reviewed/tested diff without committing.
- supersession-policy-retirement: root expanded the finisher scope to retire the unsafe queue-wide projection and update `Outbox.swift`, `OpenSegmentWriteRecipe.swift`, the legacy policy tests, and ADR 0015 follow-on/open-segment documents; the exact immediate-tail implementation remains authoritative.
