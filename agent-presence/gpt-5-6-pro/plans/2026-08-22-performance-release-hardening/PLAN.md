# Performance and release hardening plan

- **Agent:** `gpt-5-6-pro`
- **Role:** mower/grower — preserve semantics while shrinking hot-path cost; add only the release infrastructure explicitly requested by the user.
- **Started:** 2026-08-22 08:31 EDT
- **Primary issues:** #155, #156; Scribe performance budget and cross-SDK synchronization correctness.

## Outcome

Land a current-main consolidation of all still-relevant published work, make the TypeScript Instant source a pinned reference, and introduce a single strict performance/correctness gate that blocks library publication unless Swift meets the configured latency, throughput, memory, and bidirectional wire-correctness requirements.

## Audit conclusions to preserve

1. Existing memory, reconnect, outbox, live-query, and Scribe compatibility experiment branches are already contained in `main`; do not replay stale histories.
2. `exercise-gem/instant-throughput-correctness` contains six unique commits and the strongest reusable cross-runtime harness. Transplant its `validation/exercise-gym` tree onto current `main` rather than merging its 152-commit-old base.
3. `desert` is a separate synchronization architecture and is not an automatic performance consolidation candidate.
4. Existing comparison scripts currently describe slower Swift rows as optimization targets but still return success. Release mode must fail closed.
5. The vendored TypeScript reference is 95 commits behind current upstream and is currently an ignored optional checkout. Pin a reviewed upstream revision and make the reference reproducible.

## Implementation sequence

1. Add deterministic branch-inventory evidence and copy the exercise gym onto current `main`.
2. Add a pinned upstream Instant gitlink/reference and verify its revision in every benchmark run.
3. Add one entry point, `validation/run-performance-gate.sh`, which runs release-mode Swift tests/benchmarks, TypeScript reference benchmarks, memory ceilings, open-segment rewrite/finalization scenarios, bounded linked/infinite-query scenarios, stream/audio metadata scenarios, offline restore/reconnect drain, and both Swift→TypeScript and TypeScript→Swift live lanes when credentials are present.
4. Change comparison/report scripts to fail nonzero on correctness mismatches or configured p50/p95, throughput, RSS/physical-footprint, retained-result, outbox, or wire-order regressions. No explanatory text may turn a failed metric green.
5. Add GitHub Actions for deterministic CI, scheduled/manual performance runs, and a release workflow whose publication job depends on all required gates.
6. Prepare `v1.5.7` release notes and version validation, but do not create the release tag unless the final gate is green.
7. Record audit, verification, limitations, and exact commands in `PROGRESS.md`, `CHANGELOG.md`, and the cross-repository audit ledger.

## Planned touch set

- `.gitignore`
- `.gitmodules`
- `upstream/README.md`
- `upstream/instant` (gitlink)
- `validation/exercise-gym/**`
- `validation/run-performance-gate.sh`
- `validation/run-cross-sdk-benchmark-comparison.sh`
- `validation/compare-cross-sdk-benchmarks.mjs`
- `validation/compare-cross-sdk-runtime-benchmarks.mjs`
- `validation/combine-cross-sdk-benchmark-comparisons.mjs`
- `.github/workflows/correctness.yml`
- `.github/workflows/performance.yml`
- `.github/workflows/release-gate.yml`
- `scripts/validate-release-version.sh`
- `docs/audits/2026-08-22-performance-release-hardening.md`
- `docs/releases/v1.5.7.md`
- `PROGRESS.md`
- `CHANGELOG.md`
- `docs/audits/commit-changelog.md`

## Conflict check

Before implementation, read every existing `_touching` marker for the paths above and append this agent rather than replacing another claim. Coordinate through `agent-presence/_channels/2026-08-22-performance-release-hardening.md` if a live conflict exists.

## Verification layers

- Deterministic Swift unit and architecture tests.
- Release-mode local core/runtime benchmarks with correctness hashes.
- Self-hosted cross-SDK wire tests.
- Credentialed Instant Cloud lanes when secrets are available.
- Scribe device/physical-footprint evidence remains a separate product gate; CI must not claim device thermal proof from a macOS process benchmark.
