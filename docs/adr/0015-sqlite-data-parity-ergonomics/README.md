# ADR 0015 — SQLiteData-parity ergonomics (library + Scribe)

- **Status:** Decisions locked; **plan cut** — execute via `plan.md` + #155
- **Date opened:** 2026-08-06
- **Instant issue:** [#155](https://issues.knophy.com/issues/155)
- **Related:** ADR 0001 (app/sync boundary), ADR 0014 (entity lifecycle + open-segment), Scribe ADR 0006, issues #044 (memory), #092 (streams)
- **Artifacts:** `qanda.md` · `findings.md` · `overviews/` · **`plan.md`** · **`HANDOFF.md`** · **`open-segment-write-recipe.md`**
- **Cold resume:** `query-issue 155` → read **`HANDOFF.md`** → `plan.md` → first unsatisfied criterion
- **Consumer app:** `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` (Scribe)

## One-line goal

Make Instant Swift Data as easy to use as SQLiteData (or better), with good
memory and performance, so Scribe can be a thin domain app — not a second
sync engine.

## Fundamentals (gate all other work)

Before any more product features in Scribe or Instant:

1. **Memory** — process footprint under live speech and idle must meet budgets
2. **Performance** — no dual-timeline thrash, no multi-subscribe merge storms
3. **Ergonomics** — `@Fetch*` + ordinary row writes; no app-level Instant stores

## Interview + plan process

Use personal skill `$adr-decision-qanda`:

1. Interview → `qanda.md` / overviews / findings  
2. When decisions lock → **Phase B:** write `plan.md` and map every step to
   Instant issue `successCriteria` + `workLog` (survives agent context death)  
3. When ADR accepted → materialize `screens/` for designed surfaces  

## Upstream references (canonical — one path each)

| Concern | Path |
| --- | --- |
| Instant TypeScript core | `/Users/laptop/Sync/instant-data-swift/upstream/instant/client/packages/core/src` (esp. `Reactor.js`) |
| SQLiteData | `/Users/laptop/Sync/instant-data-swift/upstream/sqlite-data` |
| Instant Swift library | `/Users/laptop/Sync/instant-data-swift` |
| Scribe | `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` |

When implementing Instant behavior, cite TypeScript Reactor and SQLiteData
patterns from the **vendored** Instant tree first so citations stay with the
library repo.
