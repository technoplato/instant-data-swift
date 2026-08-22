# 2026-08-22 Instant Swift Data and Scribe Performance Audit

## Executive finding

Recent published memory, outbox, reconnect, live-query, and Scribe-compatibility branches were compared with `main`. The substantive ADR 0015, bounded outbox, local-write/server-refresh, live-query ownership, and autoresearch memory work is already contained by `main`. The only valuable branch still ahead is the cross-runtime exercise gym; its measurement intent is consolidated onto current `main` without importing stale branch history or the unrelated Electron presentation shell. The divergent `desert` branch is an alternate synchronization architecture, not a safe performance patch, and remains quarantined behind the same correctness gates.

The remaining risk is not a lack of isolated fixes. It is the absence of a single enforceable contract tying local-first correctness, bidirectional wire compatibility, CPU/memory bounds, and version publication together.

## Invariants

- Ordinary writes complete after local materialization and durable outbox enqueue, never after an implicit server round trip.
- Offline writes, relaunch restoration, ordered reconnect drain, rollback/rejection isolation, and newer-optimistic-state preservation remain mandatory.
- Scribe rewrites only its current open segment with complete assignments, finalizes it, and then creates a new identity.
- Exact-tail supersession never crosses a claimed/offered mutation, barrier, entity, or partial-patch boundary.
- Recording lists use bounded per-parent linked includes; infinite queries retain only their configured page window.
- Transcript entity delivery and progressive audio transfer are independently retryable and independently rejectable.
- A synchronization claim requires live TypeScript writer → Swift reader and Swift writer → TypeScript reader evidence.

## Hot-path audit

The gate measures and attributes these known pressure points:

1. transaction lowering and field ordering;
2. incremental triple insert/update/retract and link-index maintenance;
3. flat, nested, reverse-linked, bounded-per-parent, and infinite-query materialization;
4. observer fanout, replacement, cancellation, no-op suppression, and snapshot retention;
5. SQLite transaction/WAL/outbox growth and relaunch decoding;
6. reachability-gated reconnect with persistent exponential backoff and jitter;
7. high-frequency open-segment assignment supersession;
8. progressive audio metadata/chunk upload under simultaneous transcript writes;
9. websocket frames, bytes, acknowledgements, duplicate/loss/reordering, and final hashes;
10. process boot, peak, settled, and post-warmup memory slope plus CPU/resource usage.

## State-of-the-art optimization policy

- Prefer incremental view maintenance and query-key invalidation over whole-result recomputation.
- Preserve structural sharing and copy only changed graph branches.
- Pre-index forward and reverse relation lookups; never scan the full store for a linked include.
- Bound every cache, page window, pending body, diagnostic buffer, and retry queue by item and byte count.
- Coalesce only semantically supersedable tail assignments; retain idempotency and transaction aliases.
- Batch SQLite work in explicit transactions, reuse prepared statements, and checkpoint WAL by measured policy rather than every write.
- Keep actor ownership coarse enough to preserve correctness but avoid repeated hop/copy/decode cycles in one logical mutation.
- Gate reconnect attempts on reachability and reset backoff only after successful protocol initialization.
- Stream media from bounded buffers with backpressure; do not load complete recordings or block entity delivery.
- Treat p50, tail latency, sustained throughput, settled memory, and memory slope as separate release dimensions.

## Branch consolidation result

- Already in `main`: ADR 0015 branches, bounded-intent outbox, outbox wire hydration, local-write/server-refresh, live-query ownership, Scribe list memory, ReplayKit memory, live-put observation memory, and Scribe compatibility.
- Consolidated as current-main measurement infrastructure: `exercise-gem/instant-throughput-correctness`.
- Excluded pending independent graduation: `desert` alternate coordinator/transport architecture.
- Historical only: pre-compatibility backup and branches with zero commits ahead of `main`.

## Acceptance policy

Pull requests run deterministic correctness and release-mode measurements. They may merge only when every correctness check passes and no benchmark regresses beyond the checked-in baseline tolerance.

A version may be tagged only when the exact candidate also satisfies all of the following:

- Swift p50 and p95 cost/latency are no greater than TypeScript for equivalent work;
- Swift sustained observed throughput is no lower than TypeScript;
- Swift incremental peak and settled memory are no greater than TypeScript;
- post-warmup memory growth is at or below 0.5 MiB/min unless a stricter workload budget applies;
- zero loss, duplication, reordering, sequence violation, hash mismatch, or post-finalization regression;
- deterministic local, protocol/mock, credentialed live, and app-build evidence are all green;
- `VERSION`, requested release version, tag, and app/package metadata agree.

The release workflow tests first and creates the tag last. This ordering prevents an unverified SwiftPM version from becoming consumable.
