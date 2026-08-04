# Instant Data Performance Benchmarks

This document records the desired benchmark state for Instant Swift Data. It is
intentionally separate from implementation plans: this file answers "how fast
should the library be, and how do we know?"

## Sources Checked

- Current repo docs:
  - `INSTANT_DATA_API_DESIGN_PREFERENCES.md`
  - `docs/instant-swift-data-goals.md`
  - `docs/instantdb-swift-data-plan.md`
- Local Swift benchmark surface:
  - `Sources/InstantSwiftDataBenchmarks/main.swift`
  - `Sources/InstantSwiftDataCore/InstantLocalTodoBenchmark.swift`
  - `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift`
- Local upstream TypeScript references:
  - `upstream/instant/client/packages/core/src/instaql.ts`
  - `upstream/instant/client/packages/core/src/store.ts`
  - `upstream/instant/client/packages/core/src/instaml.ts`
  - `upstream/instant/client/packages/core/src/instatx.ts`
  - `upstream/instant/client/packages/core/src/infiniteQuery.ts`
  - `upstream/instant/client/packages/core/__tests__/src/instaql.bench.ts`
- New local benchmark harness:
  - `benchmarks/upstream-instant/observe.ts`
  - `benchmarks/upstream-instant/write.ts`

## Current Recommendation

Instant Swift Data should treat upstream InstantDB TypeScript performance as the
first parity target for equivalent local graph work.

That means:

- Read and observe benchmarks run separately from write benchmarks.
- Benchmarks emit machine-readable JSON with p50 and p95 timings, correctness
  hashes, operation counts, result counts, fixture hashes, Node version, and
  upstream revision.
- Swift targets are stated as ratios against pinned upstream TypeScript numbers,
  not as free-floating millisecond wishes.
- Swift-only overhead, such as actor hops and SQLite persistence, gets explicit
  absolute budgets in addition to TypeScript-relative targets.
- Live transport benchmarks are added only after the local core path is stable,
  because websocket latency should not hide local store/query regressions.

Status: recommended benchmark target, not yet an acceptance gate.

## Observed Constraints

- The local upstream checkout is `upstream/instant` at revision `e7101761`.
- Upstream dependencies were installed locally with `corepack pnpm@10.2.0
install` from `upstream/instant/client`.
- The local run used Node `v24.13.0` on `darwin arm64`. Upstream's `www`
  workspace warns that it wants Node `22.x`, so CI gates should rerun under
  Node 22 before treating numbers as canonical.
- `@instantdb/version` had to be built locally because `infiniteQuery.ts`
  imports through core `index.ts`.
- The upstream TypeScript scripts import local source from the vendored checkout
  and do not edit upstream files.
- Memory deltas in the TypeScript harness are `process.memoryUsage().heapUsed`
  deltas and should be treated as directional until CI runs with explicit GC.
- The current Swift benchmark suite is local-cache oriented and already records
  actor-hop breakdowns. The new TypeScript suite supplies the missing upstream
  baseline.

## Runbook

Install and build the local upstream package:

```sh
cd upstream/instant/client
corepack pnpm@10.2.0 install
corepack pnpm@10.2.0 --filter @instantdb/version build
```

Run the existing upstream Vitest benchmark in Node only:

```sh
corepack pnpm@10.2.0 --filter @instantdb/core exec vitest bench --run --project node
```

Run the new observing benchmark:

```sh
corepack pnpm@10.2.0 exec tsx ../../../benchmarks/upstream-instant/observe.ts --iterations 10 --warmups 3
```

Run the new writing benchmark in a separate process:

```sh
corepack pnpm@10.2.0 exec tsx ../../../benchmarks/upstream-instant/write.ts --iterations 5 --warmups 2
```

Use `--jsonl` when appending results to validation evidence.

## Current Upstream Baseline

Recorded on 2026-06-30 using upstream revision `e7101761`.

Existing upstream Vitest bench:

| Metric      |     Mean |      p75 |      p99 | Samples |
| ----------- | -------: | -------: | -------: | ------: |
| `big query` | 2.920 ms | 3.179 ms | 8.832 ms |     172 |

Swift package-benchmark counterpart (same fixture + plan, recorded
2026-08-04 on `laptop.local`, Darwin 25.5.0 arm64, release build):

```sh
cd benchmarks && swift package benchmark --filter 'LocalRead.deepJoin.zeneca'
```

| Metric                        |    p50 |    p90 |   p99 | Samples |
| ----------------------------- | -----: | -----: | ----: | ------: |
| `LocalRead.deepJoin.zeneca` wall clock | 23 ms | 24 ms | 25 ms |     201 |
| throughput                    | 43 / s | 42 / s | 41 / s |     201 |

Versus the TypeScript observe suite below (`core.instaql.big-query.zeneca`
p50 4.707 ms), Swift is currently ~**4.9× slower** on this deep-join path.
That misses the target of p50 ≤ 1.00× TS; the port is complete and the gap
is now a measurable performance task rather than a missing workload.

New observing suite:

| Metric                                          |       p50 |       p95 |          Result | Swift Target                     |
| ----------------------------------------------- | --------: | --------: | --------------: | -------------------------------- |
| `core.instaql.big-query.zeneca`                 |  4.707 ms |  5.500 ms |         4 users | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `query.linked-include.generated-1k`             |  1.193 ms |  1.610 ms |        67 todos | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `query.linked-include.generated-10k`            |  6.325 ms |  7.053 ms |       400 todos | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `query.nested-where-order-fields.generated-10k` |  2.705 ms |  3.186 ms |       150 todos | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `query.reverse-linked.generated-10k`            | 10.135 ms | 10.414 ms |       779 todos | p50 <= 1.00x TS, p95 <= 1.15x TS |
| `observe.subscription-fanout.synthetic-1k`      |  0.096 ms |  0.114 ms | 1,000 observers | p95 <= 1.25x TS                  |
| `observe.infinite-query-control.5-pages`        |  0.070 ms |  0.079 ms |         13 subs | p95 <= 1.25x TS                  |

New writing suite:

| Metric                                         |        p50 |        p95 | Operations | Swift Target                     |
| ---------------------------------------------- | ---------: | ---------: | ---------: | -------------------------------- |
| `write.transaction-builder.mixed-1k`           |   3.818 ms |   4.798 ms |      9,000 | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `write.instaml-transform.mixed-1k`             |   6.042 ms |   7.355 ms |      9,000 | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `write.store-transact.create-link-1k`          |  21.269 ms |  22.631 ms |     11,000 | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `write.store-triple-insert.generated-1k`       |   1.606 ms |   1.875 ms |      1,002 | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `write.store-triple-insert.generated-10k`      |  19.718 ms |  24.339 ms |     10,010 | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `write.store-triple-insert.generated-50k`      | 114.941 ms | 218.250 ms |     50,010 | p50 <= 1.00x TS, p95 <= 1.25x TS |
| `write.store-merge.metadata-500`               |   5.942 ms |   7.357 ms |        500 | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `write.store-retract-links.projects-todos-500` |   7.086 ms |   8.863 ms |        500 | p50 <= 1.00x TS, p95 <= 1.10x TS |
| `write.store-delete.todos-500`                 |  19.162 ms |  28.207 ms |        500 | p50 <= 1.00x TS, p95 <= 1.15x TS |

## Desired Benchmark Suite

### Observing

The observing script should prove:

- Recursive linked InstaQL queries stay fast on real upstream fixtures.
- Forward includes materialize without duplicate linked entities.
- Reverse links resolve at the same order of magnitude as forward links.
- Nested `where`, `order`, and `fields` do not regress when composed.
- Infinite query bookkeeping is cheap relative to query execution.
- Observer fanout is linear and does not recompute identical query results.

### Writing

The writing script should prove:

- The public transaction builder can create large mixed batches cheaply.
- Transaction lowering covers `create`, `update`, `merge`, `delete`, `link`,
  and `unlink`.
- Local store application scales across 1k, 10k, and 50k triple tiers.
- Linked writes produce all expected EAV, AEV, and VAE indexes.
- Deep merge scales with changed object size, not total store size.
- Retract and delete clean forward and reverse indexes.

### Future Live Coverage

These should become separate suites after local parity is stable:

- `auth.magic-code.round-trip`
- `presence.room-publish-observe`
- `topic.broadcast-fanout`
- `storage.upload-metadata-query`
- `streams.append-read-ordering`
- `outbox.offline-restore`
- `outbox.reconnect-drain`
- `sync-table.initial-load`

## Goal Tree

Final state:

Swift local query, observation, write, and persistence behavior is both
semantically compatible with InstantDB and at least as fast as the pinned
upstream TypeScript baseline for equivalent local work.

Goals:

1. Establish reproducible upstream TypeScript baselines.
2. Mirror each upstream case in Swift with equivalent fixtures and correctness
   hashes.
3. Fail comparison rows when Swift exceeds the target ratio.
4. Track Swift-only actor-hop and SQLite overhead separately.
5. Promote live transport, presence, topics, storage, and stream suites only
   after local parity is green.

## Recording Format

Each run emits:

```json
{
  "suite": "upstream-instant-observe",
  "side": "typescript",
  "upstreamRevision": "e7101761",
  "nodeVersion": "v24.13.0",
  "iterations": 10,
  "warmups": 3,
  "metrics": []
}
```

Each metric includes:

- `name`
- `description`
- `fixture`
- `fixtureHash`
- `source`
- `operationCount`
- `resultCount`
- `correctnessHash`
- `samples`
- `minNanoseconds`
- `p50Nanoseconds`
- `p95Nanoseconds`
- `maxNanoseconds`
- `averageNanoseconds`

Swift comparison rows should add:

- `typescriptMetricName`
- `swiftMetricName`
- `targetRatio`
- `actualRatio`
- `gapRatio`
- `actorHopCount`
- `actorHopBreakdown`
- `optimizationTarget`

## Decision Log

### 2026-06-30: Initial Benchmark Baseline

Status: upstream dependencies installed locally, upstream version package built,
existing Vitest benchmark run, and new observing/writing scripts added.

Observed:

- The upstream TypeScript local core path is very fast for direct query and
  store workloads.
- Reverse linked queries are the most expensive read case in the new suite.
- 50k store insertion has visible p95 noise in a short local run, so CI should
  use more iterations and a pinned Node 22 runtime before hard-gating it.
- The Swift suite already has useful local metrics, but it needs direct
  TypeScript comparison rows before performance parity can be enforced.

Pending:

- Add Swift mirrors for every new TypeScript metric.
- Add JSONL comparison output.
- Decide whether the acceptance gate is `1.00x`, `1.10x`, or `1.25x` per case
  after Node 22 CI baselines are collected.
