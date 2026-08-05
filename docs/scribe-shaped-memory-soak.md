# Scribe-shaped memory soak (publish gate)

**Issue:** https://issues.knophy.com/issues/150

## Why

Scribe production Instant data is not “20 tiny todos”:

| Namespace | Approx count |
|-----------|--------------|
| recordings | 239 |
| transcriptions | 214 |
| transcriptionWords | ≥2000 |
| transcriptionSegments | ≥2000 |
| recordingAttachments | 246 |
| debugLogs | ≥2000 (dual-write thrash amplifier) |

Field 2026-08-05: **idle multi‑GB** on iPad from InstantDiagnostics dual-written into Instant `debugLogs` as oversized batches — not only infinite-page thrash.

## Gate

```bash
validation/verify-scribe-shaped-memory-soak.sh
```

Runs:

1. `LinkedInfiniteScribeShapedMemorySoakTests` — `publishGate` (80×120 words, page 50, thrash expand + idle settle growth)
2. `ScribeShapedAuthenticatedIdleMemorySoakTests` — **guest auth** + `publishGateAbsoluteIdle` (**absolute settle ≤400 MiB**, idle growth ≤64 MiB)
3. `InstantDiagnosticFeedbackLoopTests` — dual-write demotion regression

### Budgets (physical footprint only; never VSZ)

| Profile | Absolute settle | Idle growth | Expand thrash |
|---------|-----------------|-------------|---------------|
| `publishGate` | ≤1.5 GiB hard multi‑GB | ≤128 MiB | page-expand ≤64 MiB; seed growth ≤768 MiB |
| `publishGateAbsoluteIdle` | **≤400 MiB** (product fail) | ≤64 MiB | seed growth ≤400 MiB |

### Auth

- **Always:** `signInAsGuest()` with `InstantGuestAuthenticator.local` (Scribe guest path shape).
- **Live (optional):** `INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1` + `SCRIBE_MAIN_INSTANT_APP_ID` uses `.live` guest auth against the real Instant app. Misconfigured live requirement fails the gate.

Also invoked from `validation/verify-v1-release.sh`.

## VSZ vs footprint

Gate on **physical footprint** / resident size. VSZ is not RAM.
