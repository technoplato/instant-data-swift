# Instant Cross-Runtime Exercise Gym

This directory is the current-main consolidation of the useful intent from the published `exercise-gem/instant-throughput-correctness` branch. It deliberately omits the stale branch's Electron and sample-app presentation layers and keeps the part needed for a release decision: one normalized report over the deterministic Swift/TypeScript benchmarks and the Scribe-shaped live wire matrix.

The gym is not a substitute for the underlying workloads. `validation/run-performance-gate.sh` first runs those workloads, then invokes this reporter to produce the combined `report.json` and `report.md` used by the hard gate.

## Covered behavior

- transaction lowering and triple insert/update/retract;
- flat, nested, reverse-linked, storage, stream, and high-frequency linked workloads;
- durable enqueue, relaunch restore, and reconnect drain;
- rapid open-segment rewriting and finalization;
- TypeScript writer → Swift reader;
- Swift writer → TypeScript reader;
- release-mode latency/cost, throughput, memory evidence when the underlying report exposes it;
- zero-tolerance loss, duplication, reordering, hash mismatch, sequence violation, or post-finalization regression.

## Run

Use the repository-level command rather than invoking this package directly:

```sh
./validation/run-performance-gate.sh --mode smoke
./validation/run-performance-gate.sh --mode full
./validation/run-performance-gate.sh --mode release
```

The combined reporter treats every remaining Swift-slower-than-TypeScript row as a failure. The older behavior of attaching an optimization explanation while returning success is intentionally rejected.
