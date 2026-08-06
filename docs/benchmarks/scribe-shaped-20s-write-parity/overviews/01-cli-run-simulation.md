# Overview 01 — CLI run simulation (revised after Q01)

**Decided:** network-vs-network primary; local-vs-local optional separate matrix; never mix.  
**Write shape:** one recording, open segment always, words JSON on segment (no word entities).

## Validity rule

```text
  Writer process                    Instant cloud                 Observer process
  ─────────────                    ─────────────                 ────────────────
  build segment upsert  ──tx──►    apply + fanout   ──refresh──►  see new wordsJSON
       │                                                              │
       │                                                              ▼
       │                                                         COUNT +1 valid write
       ▼
  local await alone does NOT count
```

A write only increments the scoreboard when the **other process** has observed it.

## Process layout (v1 network matrix)

```text
  ┌──────────────────────────────────────────────────────────────┐
  │  orchestrator (library validation CLI)                        │
  │  run-scribe-shaped-20s-write-bench --duration 20 --matrix net │
  └───────────────┬───────────────────────────────┬──────────────┘
                  │                               │
     Scenario Net-A                               Scenario Net-B
     ─────────────                                ─────────────
     Writer:  TS @instantdb/admin                 Writer:  Swift InstantRuntime
     Observer: Swift InstantRuntime (live)        Observer: TS admin/query (live)
     both sample RSS/CPU                          both sample RSS/CPU
```

Optional later:

```text
  Scenario Local-A / Local-B  — same machine, no Instant cloud
  compared only to each other, never to Net-*
```

## Simulated terminal — network matrix (what we actually want)

```text
$ cd /Users/laptop/Sync/instant-data-swift
$ validation/run-scribe-shaped-20s-write-bench.sh \
    --duration 20 \
    --matrix network \
    --profile open-segment-words-json

[bench] #156 fixture=scribe-open-segment-json schemaHash=…
[bench] speech=very-fast  wordsPerUpsert≈12  single open segment id
[bench] Net-A  writer=ts-admin   observer=swift-runtime
[bench] Net-B  writer=swift      observer=ts-admin-query

── Net-A  admin writes → Swift observes (20.0s) ───────────────
  valid_writes_observed      1_840     # observer-acked only
  writer.rss_peak_mb            92
  writer.cpu_user_s            3.1
  observer.footprint_peak_mb   188
  observer.cpu_user_s         12.4
  invalid_local_only_acks        0     # must stay 0 by definition of score

── Net-B  Swift writes → TS observes (20.0s) ──────────────────
  valid_writes_observed        620
  writer.footprint_peak_mb     240
  writer.cpu_user_s           16.8
  observer.rss_peak_mb          88
  observer.cpu_user_s          2.4

── compare (network vs network ONLY) ──────────────────────────
  metric                    Net-A(admin→swift)  Net-B(swift→ts)  ratio B/A
  valid_writes_per_s               92.0               31.0          0.34×
  writer_peak_mem_mb               92                240          2.61×
  observer_peak_mem_mb            188                 88          0.47×

  → .perf-runs/scribe-20s-write/<ts>/network-summary.json
  BASELINE_ESTABLISHED
```

## Simulated terminal — forbidden comparison (we will not print)

```text
── BAD compare ────────────────────────────────────────────────
  ts-core local writes/s 2409   vs  swift network writes/s 31
  # mixes 0 RTT store with full network observe — invalid
```

## Write unit (product shape)

```text
  recordings/{recId}
       │
       └── transcriptionSegments/{openSegId}
              text: "…"
              wordsJSON: [{start,end,text}, …]   ← grows every upsert
              updatedAtMs: …

  each loop tick (fast speech):
    append ~N words into wordsJSON
    upsert SAME openSegId only
    wait until observer query sees updatedAtMs / word count
```

No `transcriptionWords` entities in this bench.
