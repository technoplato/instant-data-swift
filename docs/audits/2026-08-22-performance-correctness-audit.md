# 2026-08-22 Memory, CPU, Throughput, and Synchronization Audit

## Scope

This audit covers Instant Swift Data, its pinned InstantDB TypeScript reference, and the Scribe realtime-transcription workload. It treats battery, memory growth, CPU wakeups, durable offline writes, reconnect behavior, and cross-SDK wire compatibility as correctness properties rather than optional tuning.

## Published-branch consolidation

The published branch inventory was compared with `main` before implementation.

- The ADR 0015, outbox-hydration, bounded-intent-outbox, local-write/server-refresh, live-query-ownership, and three autoresearch memory branches contain no commits ahead of current `main`; their substantive work is already consolidated.
- `codex/scribe-compatibility` and the pre-compatibility backup are historical snapshots with no commits ahead of `main`.
- `exercise-gem/instant-throughput-correctness` contains the useful unmerged cross-runtime correctness and throughput gym. Its harness must be ported onto current `main` rather than merging stale history wholesale.
- `desert` contains a broad alternate synchronization architecture. It is intentionally not merged as a performance patch: its behavior must graduate through the same wire-correctness, offline, memory, and release gates before any isolated component is adopted.

## Current architecture findings

### Correct invariants to preserve

1. `transact` and `save` complete after local materialization and durable outbox enqueue; they never silently wait for a server round trip.
2. Scribe rewrites only the current open segment, finalizes it, and then allocates a new segment identity.
3. Exact same-entity outbox-tail supersession is allowed only for complete, never-claimed, never-offered scalar assignments; barriers and partial patches are never crossed or merged.
4. Recording-list queries use bounded linked includes and never hydrate an entire transcript timeline merely to paint summary rows.
5. Entity synchronization and progressive media upload remain independently retryable and independently rejectable.
6. A release claim about synchronization requires live Swift-to-TypeScript and TypeScript-to-Swift evidence, not compilation or local fixtures alone.

### Performance risks addressed by the gate

- Whole-result recomputation after a narrow change.
- Retention of superseded observation snapshots or infinite-query pages.
- Reconnect loops that reset backoff before a successful `init-ok`, or retry while reachability says offline.
- Unbounded pending mutation bodies during high-frequency open-segment rewrites.
- Repeated decoding, sorting, or copying of unchanged linked graph branches.
- Audio progress writes that contend with or block transcript delivery.
- Benchmarks that describe a slow Swift result as an “optimization target” but still exit successfully.
- Version tags or releases created without reproducible correctness and performance evidence.

## Required benchmark matrix

Every release candidate must report, in release mode:

- transaction lowering and triple insert/update/retract;
- flat, nested, reverse-linked, bounded-per-parent, and infinite queries;
- observer fanout and observation replacement/cancellation;
- durable enqueue, relaunch restore, reconnect drain, rejection isolation, and exact-tail supersession;
- Scribe-shaped rapid open-segment rewriting and finalization;
- TypeScript writer → Swift reader and Swift writer → TypeScript reader;
- progressive audio metadata/chunk upload while transcript mutations continue;
- p50/p95/p99 latency, observed throughput, CPU time, wakeup/sample count where available, boot/peak/settled RSS, memory slope, SQLite/WAL/outbox bytes, and websocket frames/bytes;
- correctness hashes, monotonic sequence checks, duplicate/loss/reordering counts, and final server-ground-truth hashes.

## Hard acceptance policy

Unless a narrower documented platform exception is approved, release mode requires:

- Swift p50 and p95 latency no greater than the equivalent TypeScript lane;
- Swift sustained observed throughput no lower than TypeScript;
- Swift incremental peak and settled memory no greater than TypeScript;
- zero lost, duplicated, reordered, or post-finalization-regressed writes;
- matching final correctness hashes in both wire directions;
- bounded post-warmup memory slope;
- no unbounded linked include, infinite-page retention, outbox body growth, or media retry queue;
- every deterministic, protocol/mock, and credentialed live test green.

The comparison process exits nonzero for a missed target. Merely attaching an optimization explanation is not a passing result.

## Release policy

- Pull requests run deterministic correctness and release-mode local parity checks.
- Scheduled and manually dispatched workflows run the longer memory/CPU/throughput matrix.
- Version-tag workflows require the complete live matrix and upload immutable evidence.
- Release publication is a dependent job and therefore cannot execute when the gate fails.
- The version in `VERSION`, a `v<version>` tag, and any package/app metadata must agree.

## Evidence hierarchy

Reports keep these levels separate:

1. deterministic local tests;
2. local protocol/mock transport tests;
3. credentialed Swift/TypeScript live transport tests;
4. installed-device/app evidence.

No lower level is described as proof of a higher one.
