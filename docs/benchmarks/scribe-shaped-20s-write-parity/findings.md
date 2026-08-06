# Findings — Scribe-shaped 20s write/memory CLI (#156)

**Date:** 2026-08-06

## What already exists (reuse, do not reinvent)

### Swift

| Surface | Path | Metrics | Notes |
|---------|------|---------|-------|
| package-benchmark | `benchmarks/Benchmarks/InstantSwiftDataBenchmarking/` | wallClock, cpuTotal, mallocCountTotal, peakMemoryResident, throughput; **maxDuration 20s** | Local persistence only; simple `LocalWrite.transact.100` + Zeneca deep join — **not** Scribe-linked graph race |
| InstantSwiftDataBenchmarks CLI | `Sources/InstantSwiftDataBenchmarks/main.swift` | p50/p95 ns suites | Suites: `local-todos`, `cross-sdk-core`, `cross-sdk-runtime` |
| Cold-start profiler | `benchmarks/Profiler/` | phase durations | SQLite reopen, not write race |
| ScribeProductionShapedSchema | `Sources/InstantSwiftDataCore/ScribeProductionShapedSchema.swift` | n/a | Production namespaces: recordings, transcriptions, transcriptionWords, transcriptionSegments, recordingAttachments, debugLogs |
| #150 soak | `validation/verify-scribe-shaped-memory-soak.sh` + core tests | physical footprint budgets | **Settle/idle growth**, not “max writes in 20s” |

### TypeScript

| Surface | Path | Metrics | Notes |
|---------|------|---------|-------|
| upstream write harness | `benchmarks/upstream-instant/write.ts` | p50/p95 ns, heapUsed delta | Fixed-N batches (1k/10k/50k); todos/projects graph — not Scribe namespaces |
| upstream observe harness | `benchmarks/upstream-instant/observe.ts` | same | Read path |
| shared harness | `benchmarks/upstream-instant/shared.ts` | `process.memoryUsage().heapUsed` | Directional only until GC control |
| cross-sdk compare | `validation/compare-cross-sdk-benchmarks.mjs` | Swift/TS p50 ratios | Fixed-N core workloads; no 20s race; no admin |

### Product budget language

- Scribe: `docs/performance-budget.md` — fail >400 MB footprint, target ≤250 MB  
- Gate rule: **physical footprint / RSS only — never VSZ**

## Gap

There is **no** single CLI that:

1. Runs **matching** Scribe-shaped linked write loops on **both** TypeScript Instant and Swift Instant Data  
2. For a **fixed wall-clock window (~20s)**  
3. Reports **write throughput + CPU + process memory** for both sides  
4. Diffs them into a **baseline artifact** for regression comparison  

Existing tools cover either fixed-N microbench (TS+Swift core) **or** long soak memory (#150) **or** generic package-benchmark writes — not the dual-runtime 20s Scribe-shaped race.

## Ambiguity (interview targets)

### A. What is the TypeScript “admin node” side?

| Option | Meaning | Fair vs Swift local? | Network noise? |
|--------|---------|----------------------|----------------|
| **A1** `@instantdb/admin` live `transact` against a real app | Matches “admin node” literally | No — server RTT + server store | Yes |
| **A2** Vendored `@instantdb/core` in-process store (existing write.ts shape) | Canonical upstream local path | Yes vs Swift local store/runtime | No |
| **A3** Both lanes: `local-core` + optional `admin-live` | Full matrix | Local fair; live labeled separately | Live only |

### B. What is the Swift “application” side?

| Option | Meaning |
|--------|---------|
| **B1** InstantRuntime local (SQLite outbox materialize) — library CLI | Closest to app write cost without UI |
| **B2** Pure in-memory InstantStore (like Zeneca bench) | Fairer to TS core; understates SQLite |
| **B3** Full Scribe app process driven by agent-control | Highest product fidelity; worst hermeticity |

### C. Write shape

| Option | Shape |
|--------|-------|
| **C1** Legacy heavy link: create word **entities** + links (ScribeProductionShapedSchema soak style) | Stresses triple indexes hard |
| **C2** Product ADR 0015 shape: upsert **current segment only**, words as **JSON array** on segment | Matches intended product write; fewer entities |
| **C3** Both profiles labeled | Compare cost classes |

### D. Memory metric

| Side | Prefer |
|------|--------|
| Swift/macOS | physical footprint / peak resident (as package-benchmark + #150) |
| Node | `process.memoryUsage().rss` primary; heapUsed secondary (with optional `--expose-gc`) |

## Recommended skeleton (pending Q&A)

```text
instant-scribe-write-bench run \
  --duration-seconds 20 \
  --profile linked-words \   # or open-segment-json
  --sides swift-local,ts-core \
  [--sides admin-live] \
  --json > run.json

instant-scribe-write-bench compare \
  --baseline baselines/…json \
  --candidate run.json
```

Orchestrator: thin shell/node that spawns **separate processes** per side (so RSS is real), reuses fixtures from `ScribeProductionShapedSchema` and upstream harness patterns.
