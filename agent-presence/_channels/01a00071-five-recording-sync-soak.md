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

- 2026-08-14T17:28:55-0400 plan-to-touch: `ack_deadline_fix` owns the shared
  mutation acknowledgement-deadline policy, `InstantRuntimeLiveSession.swift`,
  acknowledgement-deadline assignment in `SQLitePersistenceStore.swift`, and
  focused regressions in `InstantBoundedOutboxDeliveryTests.swift`. The mower
  slice ports Reactor's roughly six-seconds-times-in-flight-ordinal deadline,
  and treats a genuine timeout as acknowledgement-unknown for the current live
  generation so the same client event cannot replay on the same socket. The
  durable outbox remains retryable after a replacement generation. No
  `InstantRuntime.swift`, permissions, schema, public API, Scribe source,
  commit, stage, ledger, progress, audit, build, install, or physical lane is
  claimed. The parent explicitly owns integration and serialized handoff.

- 2026-08-14T17:53:45-0400 FILES STABLE: `ack_deadline_fix` completed the
  acknowledgement-deadline/generation-barrier slice without committing or
  staging. The red regression pair proved all eight automatic claims used the
  old `now + 5_000` deadline, duplicated every client event after the early
  wake, and never opened the required replacement generation. The shared policy
  now mirrors Reactor's six-second-times-in-flight-ordinal formula in both
  SQLite claims and live reservations. A reclaimed current-generation offer is
  acknowledgement-unknown: the live generation is invalidated, even an empty
  timeout selection forces reconnect before another claim pass, and a response
  already decoded on the old receiver is generation-gated before durable
  handling. Successfully handled responses remove their offered-ID proof, so
  resident tracking stays bounded. The durable row remains retryable on the
  replacement socket. Final serialized command `swift test --jobs 1
  --no-parallel --filter
  'InstantBoundedOutboxDeliveryTests|InstantReactorParityTests'` passed 78/78 in
  23.750 seconds with 12 expected known issues. The focused pair plus exact-close
  receiver regression passed 3/3 in 0.111 seconds with one expected timeout
  issue. `swiftc -frontend -parse` on the four owned Swift files and scoped
  `git diff --check` passed; `.build/reproducible-build.json` is restored absent.
  No `InstantRuntime.swift`, permission, schema, public API, Scribe source,
  commit, stage, ledger, progress, audit, install, or physical-device lane was
  touched. The four owned source/test files and coordination markers are stable
  for the parent Scribe link/run.

- 2026-08-14T20:57:46-0400 plan-to-touch: `terminal_component_bounded_disposition`
  owns only terminal-rejection component-limit disposition in
  `SQLitePersistenceStore.swift` and `InstantRuntime.swift`, plus focused
  regressions in `InstantTerminalFailureComponentTests.swift` and
  `InstantLiveTransportTests.swift`. Test-first scope: a permission rejection
  with one claimed target and 50 connected successors durably fails only the
  exact token-owned target, retains its optimistic overlay until an
  authoritative refresh, keeps every successor deliverable, decodes only the
  target body, ignores a duplicate rejection, and keeps the current live
  connection. Production must generalize `failOutboxMutationsForDelivery`; a
  component-limit result removes the exact target from the hot outbox and
  publishes lifecycle without reconnecting. Preserve all existing bounded
  component, visible-write, acknowledgement-deadline, query, transport, and
  persistence work. No Scribe, public API, schema, ledger, `PROGRESS.md`, commit,
  stage, or SwiftPM run; parser and scoped diff checks only until root explicitly
  releases the serialized build lane.

- 2026-08-14T21:05:11-0400 FILES STABLE:
  `terminal_component_bounded_disposition` completed the bounded terminal
  disposition slice without staging, committing, or running SwiftPM. One
  red-first live regression seeds a 51-body same-entity component, offers the
  first 50 rows, holds the last successor behind a competing exact claim, and
  requires a permission rejection to decode and fail only the target while its
  overlay remains applied. It also requires the hot target shell to disappear,
  all successors to remain pending and deliverable, the duplicate rejection to
  change no revision or decode count, one open socket with one init, and a later
  authoritative server transaction to remove only the failed overlay while
  replaying every successor. Production generalizes
  `failOutboxMutationsForDelivery` with an optional schema revision and metadata
  entries; `componentLimitExceeded` uses that exact token-owned one-body path,
  publishes lifecycle/status, removes the hot target, and returns without a
  reconnect. Frontend parse across the two source files and focused test plus
  scoped `git diff --check` pass. Exact focused filter:
  `runtimeLiveOversizedTerminalComponentFailsOnlyClaimedTargetWithoutReconnect`;
  broader filters: `InstantLiveTransportTests|InstantTerminalFailureComponentTests`.
  Hashes: Runtime
  `fc917dc284be6de769a14913a2c672c99c408db9680a451c4a4d2ed3e1d2619a`,
  persistence
  `af4f3fc42c54871c3282114ca3dbd5052e0177bad6fc9045bf55f5da4205f098`,
  live test
  `91accda016b6d1ce1a9bcb4735911381a39a8cafa5b7f6efd80ca6c57893a238`.
  Files are frozen pending root's serialized SwiftPM lane release.

- 2026-08-14T21:12:28-0400 FILES STABLE test-fixture correction: the broader
  filter exposed that `staleLiveMutationErrorCannotFailAClaimReclaimedByAnotherRuntime`
  still expected an expired acknowledgement-unknown claim to be reclaimed and
  reoffered in one selector pass. The current durable generation barrier
  correctly returns that first pass with no mutations and the target in
  `reclaimedMutationIDs`. The test now asserts that barrier, then installs the
  intended exact foreign claim through the existing no-hydration testing seam
  before injecting the stale socket error. No production code changed and no
  SwiftPM command ran. Frontend parse and scoped diff check pass; live-test hash
  is `1a3830610fdbf9336eddef77eea0b7b7693ba9b3d9269bc63805a49b3c0efce5`.
  Files are frozen for root's identical serialized filter rerun.

- 2026-08-14T21:28:45-0400 FILES STABLE lifecycle follow-up: independent
  review found that the generalized exact-row failure helper retained local
  confirmation metadata that the ordinary terminal-component path clears. The
  helper now clears `serverTransactionID` and `confirmationSource` before
  saving every token-owned failed row. The 51-body regression seeds its target
  as locally confirmed through `.localTransport`, proves it is still eligible
  for live delivery, and requires both confirmation fields to be nil after the
  bounded permission rejection. No other production or test behavior changed
  and no SwiftPM command ran. Frontend parse and scoped diff check pass. Exact
  focused filter:
  `runtimeLiveOversizedTerminalComponentFailsOnlyClaimedTargetWithoutReconnect`.
  Hashes: Runtime
  `fc917dc284be6de769a14913a2c672c99c408db9680a451c4a4d2ed3e1d2619a`,
  persistence
  `09ca73cc61f53ebac0b396351866f9cf8e25153f8fffb85c78fa8f3fc5a3b22e`,
  live test
  `430007cacf434259075b1335e1519c69b3f04abe0f01ee09a8bae5725c8d13fc`.
  Files are frozen for root's serialized rerun.

- 2026-08-14T21:00:32-0400 plan-to-touch: `preapply_nested_limit` owns only
  pre-authoritative nested-limit containment in `InstantLiveRefreshApplication.swift`,
  directly related provenance-comment correction in `InstantLiveQueryNestedLimit.swift`, and
  focused regressions in `InstantLiveQueryNestedLimitMemoryTests.swift`. The translator must use
  one bounded insert-triple set for both authoritative operations and live-query replacement while
  preserving non-inserts and unbounded/non-query computations. This is a Swift-specific hot-store
  containment, not claimed upstream parity or true server pushdown. The historical claims on the
  translator/test are committed and their agents are not live. No Runtime, SQLite persistence,
  outbox, terminal-disposition, Scribe, public API, schema, commit, stage, or SwiftPM run is claimed;
  parser and scoped diff checks only until root explicitly releases the serialized build lane.
