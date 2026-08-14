# Five-recording sync soak

- 2026-08-14T13:25:20-0400 plan-to-touch: `root` owns required-foundation
  preservation in `InstantVisibleWriteFilter.swift`, the SQLite/in-memory
  visible-write snapshots, and focused bounded-delivery tests. Physical Scribe
  evidence proved one full persisted segment body could be delivered later as
  relation-without-required-text after a newer scalar revision materialized.
  The fix must substitute only the newest materialized required scalar when no
  active successor protects it; active successors keep original ordered bodies.
  No Runtime, transport, query, schema, public API, or Scribe path is claimed.
