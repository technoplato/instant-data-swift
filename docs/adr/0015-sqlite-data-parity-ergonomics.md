# ADR 0015: SQLiteData-parity ergonomics (library + consumer apps)

- Status: **In interview** (body incomplete until `qanda.md` closes)
- Date: 2026-08-06
- Scope: Instant Swift Data public write/observe ergonomics; Scribe as primary
  consumer stress case
- Issue: [#155](https://issues.knophy.com/issues/155)
- Interview folder: [`0015-sqlite-data-parity-ergonomics/`](./0015-sqlite-data-parity-ergonomics/)

## Context

Instant Swift Data already provides `@Fetch*`, `transact` / `Draft`, and a
library-owned outbox (ADR 0001). Scribe nevertheless grew app-level planners,
stores, multi-subscribe merge, and full-document previous/current diffs. That
harms memory, performance, and ergonomics. ADR 0014 covers open-segment write
shape and sync status; this ADR covers the **ergonomics parity program** and
the **deletion of app shadow runtimes**, driven by recorded Q&A.

## Decision (provisional — see qanda)

1. Fundamentals first: memory, performance, ergonomics before new features.
2. No app-level Instant stores; composition root bootstrap only.
3. Live speech: upsert open segment only; words as strict-typed JSON on segment.
4. Always outbox for open segments.
5. Library projects entity sync status on fetch.
6. Prefer deleting Scribe planners/coordinators over polishing them.
7. Typed JSON attributes: schema-bound Codable + strict decode; TS schema gen
   carries types where Instant allows.

Full decided answers: [`0015-sqlite-data-parity-ergonomics/qanda.md`](./0015-sqlite-data-parity-ergonomics/qanda.md).

## Consequences

- Library work before Scribe feature work.
- Scribe `ScribeInstantStore` and related planners are deletion candidates after
  migration plan (Q17).
- Agents and the `instant-data` skill must treat dual-repo development as
  active iteration with the user.

## Notes

Do not treat this stub as Accepted. Interview status is authoritative.
