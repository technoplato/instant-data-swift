# Outbox wire hydration plan

- planId: `2026-08-09-outbox-wire-hydration`
- agentId: `codex-desktop/019fe75c-e769-71b1-a62f-14478e917459/root`
- role: `mower`
- issues: Instant #117; Scribe #044
- outcome: Preserve the memory-thinned in-process outbox while reconstructing the exact durable transaction operations at the delivery boundary, so automatic delivery and explicit flush cannot emit empty `tx-steps`. Prove parity against vendored upstream Instant and the self-hosted server before using the library in the physical-iPhone memory experiment.

## Steps

1. Add focused Swift tests that reproduce the same-process empty-`tx-steps` failure for automatic delivery and explicit flush, and record the corresponding upstream Reactor transaction path.
2. Add a selective SQLite persistence read for the queued mutations needed at the delivery boundary; do not invalidate the full cache or reload the full triple corpus.
3. Hydrate selected outbox rows before visible-write filtering and transport lowering, preserving ordering, lifecycle status, rollback metadata, failure isolation, and the thin resident cache.
4. Run focused and coupled outbox/reconnect suites, then run reproducible self-hosted Swift/TypeScript wire and server-materialization comparison.
5. Record kept/discarded evidence in the canonical autoresearch run, `PROGRESS.md`, both change ledgers, and Instant issues #117 and #044.

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntime.swift`
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`
- `Tests/InstantSwiftDataCoreTests/InstantOutboxHydrationTests.swift`
- `autoresearch/2026-08-09-iphone-replaykit-memory`
- `PROGRESS.md`
- `CHANGELOG.md`
- `docs/audits/commit-changelog.md`

## Conflict check

No existing canonical `_touching` claim or channel names these paths. The untracked legacy `agent-presence/grok-build` claim concerns only `OutboxSameEntitySupersession.swift`; this plan does not touch that file or integrate supersession.

## Channel

No shared-path channel is required at plan time. If another identifier appears in a claimed path, open an append-only channel before implementation.
