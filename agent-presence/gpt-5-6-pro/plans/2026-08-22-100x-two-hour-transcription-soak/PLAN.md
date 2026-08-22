# Plan: 100× two-hour transcription evolution soak

- **planId:** `2026-08-22-100x-two-hour-transcription-soak`
- **agentId:** `gpt-5-6-pro`
- **role:** `grower` for the user-ordered benchmark surface; `mower` for every optimization needed to pass it
- **issues:** Instant #155 and #156
- **started:** 2026-08-22 10:20 EDT

## Outcome

Add a fail-closed, local-first benchmark that represents two hours of transcription evolving at one hundred times human speed, proves Swift↔TypeScript wire correctness in both directions, measures CPU and physical memory on Michael's Mac, and becomes mandatory for release publication.

## Fixed workload contract

- logical duration: **7,200 seconds**
- acceleration: **100×**
- target generation wall time: **72 seconds**, hard ceiling **90 seconds**
- reference human speech rate: **150 words/minute**
- exact logical word count: **18,000**
- words per finalized segment: **20**
- exact finalized segment count: **900**
- revisions per segment: **10**
- exact local mutation count: **9,000**
- target local mutation cadence: **125 revisions/second**
- each open segment owns a bounded words JSON array; no full-transcript blob or word entities
- a segment is immutable after finalization and the next segment receives a new identity

## Correctness gates

1. Run Swift local-first writer → TypeScript live reader and TypeScript local-first writer → Swift live reader.
2. Administrative APIs may provision and verify server ground truth but may not substitute for either client writer.
3. Require exactly 900 final segments, 18,000 words, contiguous segment indexes, monotonic per-segment revisions, and a matching deterministic final hash.
4. Fail on any lost or duplicate final segment, revision after finalization, order regression, hash mismatch, decode error, rejected mutation, or non-empty final outbox.
5. Exercise bounded latest-two linked queries while the recording evolves and prove released observers/pages do not retain the full history.
6. Preserve offline-first semantics: ordinary writes finish after local materialization plus durable outbox enqueue; server catch-up is a separate measured phase.

## Resource gates

### Cross-SDK CLI lanes

- incremental physical-footprint peak ≤ **64 MiB** per Swift process
- settled footprint growth ≤ **16 MiB** per process
- average process CPU ≤ **200%** of one core over the accelerated wall interval
- total CPU seconds / logical transcript second ≤ **0.02**
- post-generation server catch-up ≤ **30 seconds**

### Scribe product lane

- recording + transcription + synchronization physical footprint remains **<100 MiB** after startup/model-load exclusions already defined by the product budget
- settled growth from warm state ≤ **16 MiB**
- average process CPU ≤ **200%** during the 100× stress interval
- normalized CPU ≤ **0.02 CPU-seconds per logical second**
- exact product-side final word/segment totals and server hash match

Threshold changes require a separate review and may not be modified by an optimization commit whose purpose is to make the workload pass.

## Implementation sequence

1. Add deterministic contract/model tests before the live runner.
2. Add a bounded Swift writer/reader and equivalent TypeScript core writer/reader.
3. Add the ephemeral schema/perms and one-command benchmark script.
4. Integrate the benchmark into the strict performance/release gate.
5. Add `.home-runner/transcription-100x-2h.sh` and an Ubuntu dispatcher workflow that queues the exact SHA on `technoplato/home-runner`.
6. Run on Michael's Mac, inspect evidence, and optimize hot paths without weakening thresholds.
7. Merge and version only after all deterministic, bidirectional live, CPU, memory, and product gates are green.

## Touching

- `Sources/InstantSwiftDataCore/AcceleratedTranscriptionEvolutionBench.swift`
- `Sources/ScribeShaped20sWriteBench/main.swift`
- `Tests/InstantSwiftDataCoreTests/AcceleratedTranscriptionEvolutionBenchTests.swift`
- `validation/ts-runner/src/accelerated-transcription-evolution-bench.ts`
- `validation/run-accelerated-transcription-evolution-bench.sh`
- `validation/fixtures/accelerated-transcription-evolution.schema.ts`
- `validation/fixtures/accelerated-transcription-evolution.perms.ts`
- `validation/run-performance-gate.sh`
- `.home-runner/transcription-100x-2h.sh`
- `.github/workflows/transcription-100x-2h.yml`
- `docs/benchmarks/accelerated-transcription-100x-2h.md`
- `PROGRESS.md`
- `CHANGELOG.md`
- `docs/audits/commit-changelog.md`

## Conflict check

Before implementation, scan every corresponding `_touching/**/agents.txt` and the performance-hardening channel. Any overlapping owner is preserved and coordination is recorded before editing.

## Channel

`agent-presence/_channels/2026-08-22-100x-two-hour-transcription-soak.md`
