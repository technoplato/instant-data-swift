# 2026-08-12 live revision cardinality

- owner: `grok-4.6-live-revision`
- plan: Instant `2026-08-12-live-revision-cardinality`
- mode: mower
- issues: #044, #155
- split: Instant-library characterization only. Does not steal `codex-desktop/019fe994` InstantStore/Runtime claims or Scribe recording sources.
- intent: Replicate the 4 GB recording balloon as 10,000 same-entity puts whose domain cardinality stays 1 while unbounded namespace observation rematerializes every sibling. User invariant: do not debounce or drop live sync revisions; prune the operation journal after ack; observe live current state plus bounded finalized pages.
- 2026-08-12T12:36:00-0400 user-explicit-allow steal: `grok-4.6-live-revision` may steal InstantStore/Runtime ownership for the live-put rematerialize memory slice only. Steal is allowed only because the user explicitly allowed it at this timestamp. Prior `codex-desktop/019fe994` ids remain. Scope: Swift-only memory-byte tests first, then skip rematerialize of observers whose result does not include the changed entity. Do not edit outbox, deferred values, or bounded-query candidate enumeration. InstantRuntime claimed; no Runtime edit unless InstantStore publish contract requires it.
- 2026-08-12T13:07:02-0400 splice + include skip: `shouldRefresh` intersects plan+include namespaces; `splicedEmission` replaces lastValues in place when membership and order keys are unchanged. Diagnostics: skippedObserverCount, splicedObserverCount, rematerializedObserverCount, materializedSnapshotCount. Autoresearch `2026-08-12-live-put-observation-memory`. InstantRuntime still unedited.
