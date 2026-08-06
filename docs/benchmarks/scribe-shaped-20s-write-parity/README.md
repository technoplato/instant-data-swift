# Scribe-shaped 20s write / memory parity CLI

**Status:** In interview  
**Issue:** [#156](https://issues.knophy.com/issues/156)  
**Related:** #150 (soak gate), #044 (memory instrumentation), #155 (ergonomics),  
`INSTANT_DATA_PERFORMANCE_BENCHMARKS.md`

## Goal

One pure command-line utility (in **instant-data-swift**, not Scribe UI) that:

1. Exercises **TypeScript `@instantdb/admin` Node** and **Instant Swift Data runtime** against a **real Instant app**
2. Uses the **product write shape**: one recording, **open segment always**, **words as JSON on the segment** (no word entities)
3. Runs a fixed **~20 second** race: “how many writes were **observed by another process**?”
4. Reports **valid writes, wall time, CPU, process memory** on **both writer and observer** (physical footprint / RSS — never VSZ as gate)
5. Compares **network vs network** (and optionally **local vs local** later) — **never** local vs network
6. Emits a machine-readable baseline for regression comparison

## Design records

| File | Role |
|------|------|
| `findings.md` | What already exists; gap; smells |
| `qanda.md` | One decision log for the interview |
| `overviews/` | ASCII flows / simulated terminal contracts |

## How to run

```sh
cd /Users/laptop/Sync/instant-data-swift
# Default 20s, 12 words per open-segment upsert. Needs network + Instant CLI.
validation/run-scribe-shaped-20s-write-bench.sh

# Shorter smoke:
INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS=5 \
INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT=8 \
  validation/run-scribe-shaped-20s-write-bench.sh
```

Artifacts land in `.perf-runs/scribe-20s-write/<timestamp>/summary.json`.

### Lanes

| Scenario | Writer | Observer |
|----------|--------|----------|
| **Net-A** | TS `@instantdb/admin` | Swift InstantRuntime |
| **Net-B** | Swift InstantRuntime (awaits server acceptance) | TS admin query |

Score: observer counts monotonic `seq` advances on the open segment (`wordsJSON` blob, no word entities).  
Compare **network vs network only**.

### Implementation map

| Piece | Path |
|-------|------|
| Orchestrator | `validation/run-scribe-shaped-20s-write-bench.sh` |
| TS coordinate / admin lanes | `validation/ts-runner/src/scribe-shaped-20s-write-bench.ts` |
| Schema / perms fixtures | `validation/fixtures/scribe-open-segment-bench.{schema,perms}.ts` |
| Swift core | `Sources/InstantSwiftDataCore/ScribeOpenSegmentNetworkBench.swift` |
| Swift CLI product | `scribe-shaped-20s-write-bench` |

## Non-goals

- Replacing the #150 multi-minute soak publish gate
- Device UI / Instruments GUI (CLI first; Instruments optional later)
- Optimizing library performance in the same change as the harness
- Local-vs-network ratios