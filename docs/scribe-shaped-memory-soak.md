# Scribe-shaped memory soak (publish gate)

**Issue:** https://issues.knophy.com/issues/150

## Why

Scribe production Instant data (admin sample **2026-08-05**) is not “20 tiny todos”:

| Namespace | Approx count |
|-----------|--------------|
| recordings | 239 |
| transcriptions | 214 |
| transcriptionWords | ≥2000 |
| transcriptionSegments | ≥2000 |
| recordingAttachments | 246 |
| screenStreamSessions | 23 |
| debugLogs | ≥2000 |

Local Scribe store also held **184 failed outbox** rows (mostly `Permission denied: not perms-pass?`).

The linked-infinite recipe previously seeded ~20 parents with only a `wordCount` number — no word entities, no transcript text, page size 3. Multi‑GB Jetsam and thrash were rediscovered on real shapes because the recipe never exercised them.

## Gate

```bash
validation/verify-scribe-shaped-memory-soak.sh
```

Runs `LinkedInfiniteScribeShapedMemorySoakTests` with
`LinkedInfiniteScribeShapedSoakProfile.publishGate`:

- 80 recordings × 120 word entities + transcript text
- Infinite list page size **50** (Scribe library)
- **Physical footprint** growth budget 256 MiB, ceiling 512 MiB

Also invoked from `validation/verify-v1-release.sh`.

## VSZ vs footprint

| Metric | Meaning |
|--------|---------|
| **VSZ / Virtual** | Address space reserved/mapped (dyld shared cache, stack guards, …). Often **hundreds of GB** on Apple Silicon Debug apps. **Not RAM.** |
| **Resident** | Pages currently in RAM. |
| **Physical footprint** | What Jetsam / Activity Monitor treat as process memory cost. |

If the panel shows **~415 GB virtual** with **~60–120 MB footprint/resident**, that is normal address-space accounting, not a 415 GB leak.

## Production sample command

```bash
set -a; source ~/.config/instant-tools/scribe-main.env; set +a
export INSTANT_ADMIN_TOKEN="$SCRIBE_MAIN_INSTANT_ADMIN_TOKEN"
npx instant-cli query -a "$SCRIBE_MAIN_INSTANT_APP_ID" --admin \
  '{"recordings":{"$":{"limit":500}}}'
```
