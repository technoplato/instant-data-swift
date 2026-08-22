# Accelerated transcription evolution benchmark

This gate answers a deliberately hostile product question:

> Can the local-first Swift client accept, retain, synchronize, and settle two
> logical hours of rapidly evolving transcription at **at least 100× human
> speed** without losing correctness or exceeding its CPU and memory budgets?

## Fixed corpus

The corpus is deterministic and shared with Scribe and the TypeScript runner.
It is not inferred from wall-clock sleeps.

| Dimension | Contract |
| --- | ---: |
| Logical duration | 7,200 seconds |
| Human speech reference | 150 words/minute |
| Final words | 18,000 |
| Segment duration | 8 logical seconds |
| Final segments | 900 |
| Complete-assignment revisions/segment | 10 |
| Total revisions | 9,000 |
| Maximum total wall time | 72 seconds |
| Minimum revision throughput | 125 revisions/second |
| Maximum open-segment payload | 16 KiB |

Every revision reuses one open-segment identity. Revision ten finalizes that
segment before the next identity is allocated. Finalized segments are
immutable. The fixture itself retains only the requested open segment; it does
not retain a second transcript graph or diff a growing two-hour document.

## What the gate measures

- Exact final segment and word counts.
- A canonical ordered final-content hash shared by Swift and TypeScript.
- Local-first revision throughput and total accelerated wall time.
- Durable outbox peak and final drain state.
- Baseline, peak, and settled process memory.
- User and system CPU time, normalized per revision.
- Swift/TypeScript memory, CPU, and wall-time ratios on the same Mac.
- Scribe product-process physical footprint, RSS, CPU, local SQLite/outbox
  progress, and cloud observation in its paired repository gate.

Missing measurements are failures. A surviving `optimization-target` is not a
publishable result.

## Run it

```bash
bash validation/run-accelerated-transcription-evolution-bench.sh
```

Through Michael's repo-scoped Mac runner:

```bash
home-run run technoplato/instant-data-swift transcription-100x-2h \
  --ref <exact-commit>
```

The target-repository workflow queues and watches that private control-repo
job. Ubuntu only dispatches; Swift and TypeScript execute on the self-hosted
`laptop` Mac.

## Current hard ceilings

| Metric | Ceiling |
| --- | ---: |
| Swift incremental peak physical footprint | 64 MiB |
| Swift settled physical-footprint growth | 16 MiB |
| TypeScript incremental/settled resident growth | 64 MiB / 16 MiB |
| Swift peak pending mutations | 1,800 |
| Swift average CPU | 200% of one core |
| Swift CPU/revision | no greater than TypeScript |
| Swift wall time | no greater than TypeScript |
| Swift incremental process memory | no greater than TypeScript |

The Scribe product lane additionally retains the existing absolute
**<100 MiB physical-footprint** transcription-and-sync budget. Platform-specific
framework baseline is reported separately; it is never hidden by VSZ.

## Correctness before performance

The burst path preserves the ordinary write contract: local materialization and
durable outbox admission complete the write. It does not wait for a server
round trip for every interim word. Remote convergence and final outbox drain are
observed after the burst. This prevents the benchmark from confusing network
latency with local-first throughput while still failing incomplete sync.
