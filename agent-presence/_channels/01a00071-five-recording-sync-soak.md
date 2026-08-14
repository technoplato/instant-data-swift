# Five-recording sync soak

- 2026-08-14T13:25:20-0400 plan-to-touch: `root` owns required-foundation
  preservation in `InstantVisibleWriteFilter.swift`, the SQLite/in-memory
  visible-write snapshots, and focused bounded-delivery tests. Physical Scribe
  evidence proved one full persisted segment body could be delivered later as
  relation-without-required-text after a newer scalar revision materialized.
  The fix must substitute only the newest materialized required scalar when no
  active successor protects it; active successors keep original ordered bodies.
  No Runtime, transport, query, schema, public API, or Scribe path is claimed.

- 2026-08-14T13:39:00-0400 handoff: implemented the required-foundation slice
  without committing or staging. The durable visible-write snapshot now excludes
  active, unconfirmed outbox overlays (including legacy NULL confirmation proof),
  hydrates only the value of an otherwise-stale required non-reference scalar,
  preserves the older mutation's operation and transaction metadata, retains
  ordered predecessor/successor bodies, and continues filtering stale optional
  fields. The hot in-memory snapshot remains conservative because it lacks outbox
  provenance. `swiftc -parse` and `git diff --check` passed for all four owned
  source/test files. `swift test --jobs 1 --no-parallel --filter
  'InstantBoundedOutboxDeliveryTests'` passed all 44 tests in 24.212 seconds with
  12 pre-existing expected known issues. Remaining boundary: required reference
  attributes are not hydrated by this scalar-only slice; the Scribe recording
  reference is optional, so that does not reopen the observed missing-text case.
- 2026-08-14T13:42:26-0400 plan-to-touch expansion: independent review proved
  required-value substitution can enlarge the final transport mutation after
  durable-body admission. `root` additionally claims
  `Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift` to keep the existing
  8 MiB body/window ceiling authoritative after filtering and hydration. The
  focused delivery test must use a tiny persisted value plus an over-limit
  authoritative value and prove no oversized wire body is emitted. No Runtime,
  transport client, schema, public API, query, or Scribe path is added.

- 2026-08-14T13:53:52-0400 scope agreement: the complete bounded slice includes
  metadata-first authoritative scalar lengths, exact sorted-key projected-body
  admission inside the atomic SQLite claim, and one nullable claim-scoped
  projected-byte column. Legacy active claims with no projected count block
  refill until disposition. The returned window retains hydrated values only
  for the admitted 8 MiB prefix. Runtime, transport, and public APIs remain out
  of scope; the focused tests own individual failure and aggregate deferral.

- 2026-08-14T14:12:30-0400 handoff: the atomic projected-byte slice is
  implemented without committing or staging. Migration
  `0019_projected_outbox_claim_bytes` adds nullable claim-scoped projected body
  bytes; claim admission measures exact sorted-key `PendingMutation` bytes from
  authoritative value-length metadata before decoding values, visibly fails an
  individually oversized row, releases an aggregate-overflow suffix unoffered,
  and counts already-active claims. Legacy active NULL reservations block
  refill. ACK, release, expiry, failure, retry/isolation, and quarantine clear
  the reservation. `swiftc -parse` and `git diff --check` passed. The two
  red-first projected-envelope tests passed 2/2 in 0.641 seconds; claim
  lifecycle tests passed 3/3 in 0.063 seconds; the full serialized
  `InstantBoundedOutboxDeliveryTests` suite passed 48/48 in 21.161 seconds with
  12 expected known issues; `InstantTerminalFailureComponentTests` passed 14/14
  in 2.416 seconds. The five owned source/test files are stable for review.

- 2026-08-14T17:25:12-0400 plan-to-touch/handoff: `root` claims only
  `docs/audits/commit-changelog.md` plus this coordination line to record Scribe
  implementation `0da0651942e329064bdc2a8a7c63bd1f60e14dc1`. That commit keeps the
  process-wide footprint baseline and rearms the one-second >150 MiB abort for
  every sequential recording; its exact pair passes 2/2 and watchdog suite
  passes 6/6. This is audit bookkeeping only: no Instant source, tests, package,
  changelog, progress, runtime, transport, or public API is claimed.
