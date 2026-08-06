# Scribe-shaped memory soak (publish gate)

**Issue:** https://issues.knophy.com/issues/150

## Why

Scribe production Instant data is not “20 tiny todos” and not `linked_infinite_*`
toy namespaces. The soak uses **production namespace names**:

| Namespace | Approx count (admin sample) | Role |
|-----------|------------------------------|------|
| `recordings` | 239 | library list parents |
| `transcriptions` | 214 | include metrics + transcript text |
| `transcriptionWords` | ≥2000 | per-word materialization |
| `transcriptionSegments` | ≥2000 | segment materialization |
| `recordingAttachments` | 246 | attachment materialization |
| `debugLogs` | ≥2000 | **second Instant store** dual-write thrash |

Field 2026-08-05: **idle multi‑GB** on iPad (home screen, **not** recording)
from InstantDiagnostics dual-written into a second Instant `debugLogs` client as
oversized `debug-log-batch-*` mutations (HOL at 256 steps, pending ~80+). Physical
footprint climbed hundreds of MB/minute while VSZ stayed ~475 GB address space.

Schema fixture: `ScribeProductionShapedSchema` in InstantSwiftDataCore.

## Gate

```bash
validation/verify-scribe-shaped-memory-soak.sh
```

Runs suites **sequentially** (process-wide footprint samples must not overlap):

1. `InstantDiagnosticFeedbackLoopTests` — dual-write demotion regression
2. `LinkedInfiniteScribeShapedMemorySoakTests` — production namespaces, `publishGate` (80×120 words, page 50)
3. `ScribeShapedAuthenticatedIdleMemorySoakTests` — guest auth + absolute idle + **real second Instant debugLogs thrash driver**

### Budgets (physical footprint only; never VSZ)

| Profile | Absolute settle | Idle growth | Expand thrash |
|---------|-----------------|-------------|---------------|
| `publishGate` | ≤1.5 GiB hard multi‑GB | ≤128 MiB | page-expand ≤64 MiB; seed growth ≤768 MiB |
| `publishGateAbsoluteIdle` | **≤400 MiB** (product fail) | ≤64 MiB | seed growth ≤400 MiB |

### Auth

- **Always:** `signInAsGuest()` with `InstantGuestAuthenticator.local`.
- **Live (auto when credentials present):** sources `SCRIBE_MAIN_INSTANT_APP_ID` /
  `~/.config/instant-tools/scribe-main.env` and runs `.live` guest auth unless
  `INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0`. Explicit `=1` fails the gate if misconfigured.

Also invoked from `validation/verify-v1-release.sh`.

## Dual Instant thrash driver

The authenticated suite boots **two** `InstantRuntime`s: main Scribe graph +
`debugLogs` attrs. Forced thrash writes 16×8 multi-attr debugLogs entities
(~22 ops/row, InstantDBLogger batch shape). Demotion regression that re-enables
info+ high-frequency dual-write actually enqueues into the second store.

## VSZ vs footprint

Gate on **physical footprint** / resident size. VSZ is not RAM.
