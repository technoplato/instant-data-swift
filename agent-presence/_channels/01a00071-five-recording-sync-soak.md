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

- 2026-08-14T22:19:52-0400 plan-to-touch: `semantic_noop_insert_fix` owns only
  exact normalized-triple semantic no-op invalidation in `TripleIndexes.swift`
  plus focused scalar/ref regressions in `InstantStoreTests.swift` and, if it
  fits the existing fixture without widening scope, one Scribe-shaped repeated
  refresh regression in `InstantLiveQueryNestedLimitMemoryTests.swift`. An
  `.insert` whose normalized triple is already resident must return no changed
  entity or attribute IDs even when transaction identity differs; actual scalar
  value changes, ref relinks, and ref membership changes retain current
  invalidation. Query replacement/page-info, transaction lifecycle, persistence,
  live refresh translation, runtime, and public APIs are explicitly out of
  scope. This is a Swift shared-store adaptation, not upstream per-query-store
  parity. Historical claims are committed; `preapply_nested_limit` has declared
  its nested-limit file stable. No SwiftPM/build/commit/stage is claimed; parser
  and scoped diff checks only.

- 2026-08-14T22:25:30-0400 FILES STABLE `semantic_noop_insert_fix`:
  `TripleIndexes.apply(.insert)` now distinguishes semantic identity from the
  resident transaction stamp. It still applies every insert so transaction
  identity, server checkpoints, query replacement/page-info, and durability
  remain in their existing layers, but an already-resident normalized value
  returns no changed entity or ref endpoint IDs. Focused regressions cover a
  date-normalized scalar replay with a different transaction ID and zero
  observer rematerialization, exact ref replay versus relink and new membership,
  and a bounded Scribe-shaped refresh in which a full repeated page invalidates
  nothing while one changed segment index invalidates only that segment. This
  is explicitly the Swift shared-hot-store adaptation to upstream's per-query
  stores. Frontend parse and scoped `git diff --check` pass; no SwiftPM/build,
  stage, or commit ran. Exact root filter:
  `swift test --jobs 1 --no-parallel --filter 'exactNormalizedScalarInsertReplaySkipsObservationInvalidation|exactRefReplaySkipsEndpointsButRelinkAndMembershipChangesInvalidate|repeatedScribeShapedRefreshInvalidatesOnlyTheChangedSegment'`.
  Hashes: TripleIndexes
  `e69636e490373cdcb13014c903e6d8d3c11d393f7da52fec522dbd9a34709c96`,
  InstantStoreTests
  `244dcb400936be6d8ab13f87d5fbaad24b3665bf773390d7d3e9f474c44dd8d4`,
  nested-limit tests
  `936575c06fb672ee7338396d8189c1715d8fffefe363e1e1f451b784f2189d77`.
  Files are frozen for root's serialized verification.

- 2026-08-14T22:19:51-0400 plan-to-touch: `send_failure_reconnect_fix` owns only
  current-generation remove-query send-failure ownership in
  `InstantRuntimeLiveSession.swift` and one focused two-session regression in
  `InstantLiveTransportTests.swift`. Test-first contract: a failed remove-query
  send must terminate the exact receiver and let that receiver remain the sole
  failure/reconnect owner; its replacement socket must reinstall the surviving
  query and reach opened status, while explicit close/replacement generations
  continue suppressing stale reconnect and every exact task owner is idle after
  close. No direct Runtime failure callback from the send path, no public API,
  persistence, schema, Scribe, commit, stage, ledger, progress, audit, SwiftPM,
  build, install, or physical-device lane is claimed; parser and scoped diff
  checks only.

- 2026-08-14T22:29:56-0400 FILES STABLE: `send_failure_reconnect_fix`
  completed the send/receiver ownership slice without staging, committing, or
  running SwiftPM. An active current-generation send failure is retained by
  session identity and generation, then the wire is aborted; the exact receive
  loop consumes that error and remains the sole Runtime reconnect callback.
  Send timeout/caller abandonment no longer aborts ahead of actor-isolated
  failure publication. Opening/no-receiver sends keep caller-owned invalidation,
  while replacement and explicit close clear the handoff before stopping the
  prior receiver. The focused two-session regression holds reconnect long
  enough to assert the exact scripted error, then proves the surviving bounded
  query is reinstalled, status returns to opened, and close leaves every exact
  owner idle. A second regression closes during a suspended removal and proves
  no stale reconnect; the existing manual replacement regression remains in
  the exact filter. Frontend parse and scoped diff check pass. Exact filter:
  `currentRemovalFailureReconnectsAndReinstallsSurvivingQuery|explicitCloseSupersedesPendingRemovalFailureWithoutReconnect|supersededRemovalFailureCannotOverwriteHealthyReplacementStatus`.
  Hashes: live session
  `9a5e3be0f7b2141fa385db0e89dd054117dba5365273c6ba8f28f709ad703e12`,
  live transport tests
  `d3ebf3cb314e249837961beb82880701448d39d456e4475a8dcb9146394c10b4`.

- 2026-08-14T22:32:46-0400 FILES STABLE compile correction:
  `send_failure_reconnect_fix` added the required `try` to the focused test's
  temporary persistence URL and evaluated the two actor-isolated values before
  passing them to `expectNoDifference`. No behavior or production source
  changed. Frontend parse and scoped diff check pass; no SwiftPM command ran.
  The exact filter is unchanged:
  `currentRemovalFailureReconnectsAndReinstallsSurvivingQuery|explicitCloseSupersedesPendingRemovalFailureWithoutReconnect|supersededRemovalFailureCannotOverwriteHealthyReplacementStatus`.
  Hashes: live session
  `9a5e3be0f7b2141fa385db0e89dd054117dba5365273c6ba8f28f709ad703e12`,
  live transport tests
  `0fc6c559de2bcf2d12987e0317998000e4e03d3921e33866e0f8e237c73ed882`.

- 2026-08-14T22:37:16-0400 FILES STABLE expectation correction:
  `send_failure_reconnect_fix` changed only the focused reconnect test's active
  query-key expectation. It now derives the canonical registration key through
  `InstantLiveQueryEncoder.registrationKey(for:)` from the same encoded
  surviving query asserted on the replacement wire, matching Runtime's actual
  registration semantics. Frontend parse and scoped diff check pass; no
  SwiftPM command or production change ran. Exact filter remains
  `currentRemovalFailureReconnectsAndReinstallsSurvivingQuery|explicitCloseSupersedesPendingRemovalFailureWithoutReconnect|supersededRemovalFailureCannotOverwriteHealthyReplacementStatus`.
  Hashes: live session
  `9a5e3be0f7b2141fa385db0e89dd054117dba5365273c6ba8f28f709ad703e12`,
  live transport tests
  `7ada46b9ba49f31282a04babb746cb07fa4e2e54637ba030f80d89d69c8441a0`.

- 2026-08-14T22:50:17-0400 plan-to-touch expansion:
  `send_failure_reconnect_fix` additionally claims only Runtime.swift's
  connect/startReceiving slice around the existing live-transport inner open
  path. `semantic_noop_v2` explicitly confirmed its concurrent Runtime work is
  limited to authoritative server-apply calls around lines 2420 and 2620 and
  released this region; root authorized the expansion. The receiver-start seam
  must atomically consume a current session/generation failure captured after
  low-level open but before receiver installation, throw through the existing
  close/save-errored path, and prevent a false `.opened` return. The same slice
  also synthesizes an actionable network failure when a current-generation
  receiver unexpectedly returns `CancellationError`; explicit close/replacement
  remain inert because they increment generation first. No other Runtime,
  server-apply, Store, indexes, public API, schema, persistence, Scribe, commit,
  stage, ledger, build, install, or physical-device path is claimed; parser and
  scoped diff checks only.

- 2026-08-14T22:57:00-0400 FILES STABLE receiver-race follow-up:
  `send_failure_reconnect_fix` completed the coordinated three-file slice
  without staging, committing, or running SwiftPM. A current-generation
  receiver that returns cancellation without an explicit generation-changing
  close/replacement now produces an actionable network failure and invokes the
  sole receiver-owned reconnect callback. A send failure in the low-level-open
  / pre-receiver interval is retained by generation and session identity;
  throwing `startReceiving` atomically consumes and invalidates it inside
  Runtime's existing inner open do/catch after server-attribute installation
  but before `.opened` persistence. The existing catch closes the session,
  records `.errored`, and prevents a false opened return. Deterministic tests
  force receive to win while send remains suspended, pause the exact
  pre-receiver window, prove the exact pending error escapes connect, and
  reread `.closed` after a late send resolves. Upstream review classifies the
  reconnect outcome and stale-generation suppression as behaviorally aligned;
  synthesized Swift failure status and the atomic pre-receiver handoff are
  explicit Swift lifecycle adaptations because upstream installs callbacks
  before opening. Frontend parse and scoped diff check pass. Exact filter:
  `currentRemovalFailureReconnectsAndReinstallsSurvivingQuery|unexpectedCurrentReceiverCancellationReconnectsBeforeLateSendFailure|preReceiverRemovalFailureCannotReturnOpenedConnection|explicitCloseSupersedesPendingRemovalFailureWithoutReconnect|supersededRemovalFailureCannotOverwriteHealthyReplacementStatus`.
  Hashes: live session
  `2bbeb4a1552de587e595256618643d32f2debed06765d402c6b57ff325aab205`,
  shared Runtime (including the coordinated stable semantic-noop slices)
  `e9ba7bcb3920f343fe66a8dc396170c32d4c59eee0b78971a93f48855525ec1b`,
  live transport tests
  `c94df96e18a9708083d67e90be65d60669a25d7a3e7b2db2da12adb9555d0242`.

- 2026-08-14T23:05:23-0400 FILES STABLE pre-receiver linearization
  correction: the serialized gate passed ten of eleven tests and exposed one
  remaining real interleaving in
  `preReceiverRemovalFailureCannotReturnOpenedConnection`. Releasing the
  transport send and receiver-start checkpoint back-to-back allowed
  `startReceiving` to inspect pending failure before the resumed send reached
  its actor catch. `InstantRuntimeLiveSession` now counts in-flight sends by
  exact generation/session identity before their first suspension and finishes
  them only after success or failure disposition. Receiver installation waits
  for that current key to drain, rechecks session/generation ownership, then
  consumes pending failure or installs the task without another suspension.
  Multiple overlapping sends and sends that arrive after a waiter resumes are
  covered by the count/loop linearization; stale generations never block a
  replacement. No Runtime or test change was needed for this correction.
  Frontend parse and scoped diff check pass; no SwiftPM command ran. Exact
  filter remains
  `currentRemovalFailureReconnectsAndReinstallsSurvivingQuery|unexpectedCurrentReceiverCancellationReconnectsBeforeLateSendFailure|preReceiverRemovalFailureCannotReturnOpenedConnection|explicitCloseSupersedesPendingRemovalFailureWithoutReconnect|supersededRemovalFailureCannotOverwriteHealthyReplacementStatus`.
  Hashes: live session
  `bc4f060e5636640694eff79d011fbc745339035f9f37656e43c4fb80175e1a4e`,
  shared Runtime
  `e9ba7bcb3920f343fe66a8dc396170c32d4c59eee0b78971a93f48855525ec1b`,
  live transport tests
  `c94df96e18a9708083d67e90be65d60669a25d7a3e7b2db2da12adb9555d0242`.

- 2026-08-14T22:40:00-0400 reviewed plan-to-touch expansion:
  `semantic_noop_v2` owns the existing exact-insert slice plus the package-internal
  `InstantStore` page-info publication seam and its one server-apply call site.
  Independent review proved an exact value may still evict malformed siblings,
  replacing its resident stamp would diverge hot and durable state when observers
  are skipped, and page-info-only refreshes must remain observable per live-query
  key. The mower revision skips the insert only when the complete normalized slot
  is already identical, preserves its resident stamp, folds changed page info into
  the same store commit, and deduplicates unchanged metadata-only installs. Focused
  tests own the malformed cardinality-one slot, bounded stream emissions, Scribe-
  shaped identical replay, and page-info-only change/replay. No public API, schema,
  reconnect source/test, SwiftPM, build, stage, or commit is claimed.

- 2026-08-14T23:05:00-0400 FILES STABLE `semantic_noop_v2`:
  Exact insert replay suppression is now an internal policy whose default keeps
  the ordinary replace-and-invalidate behavior. Only Runtime's authoritative
  server transaction apply opts into preserving a normalized resident fact, and
  only when the complete visible slot is already identical. Cardinality-one
  slots with siblings still run the existing insert, report their changed entity,
  and persist the sibling removal. Local exact-value writes retain a nonempty
  rollback; a SQLite-backed Runtime regression peels, authoritatively refreshes,
  and reapplies that pending overlay without throwing. Page-info replacement is
  independently keyed per live observer: store mutations install changed metadata
  inside the same commit/materialization pass, while metadata-only installs dedupe
  exact replay and return the same emissions yielded to streams. The Scribe-shaped
  Runtime regression observes the bounded root/two-child query and proves one full
  identical refresh has zero changed IDs, emissions, rematerializations, and
  materialized snapshots; one changed segment emits; page-info-only change emits;
  exact page-info replay does not; persisted replacement and processed transaction
  assertions remain. Frontend parse and scoped `git diff --check` pass. No SwiftPM,
  build, stage, or commit ran. Exact filter:
  `swift test --jobs 1 --no-parallel --filter 'exactNormalizedScalarInsertReplaySkipsObservationInvalidation|exactRefReplaySkipsEndpointsButRelinkAndMembershipChangesInvalidate|authoritativeExactCardinalityOneReplayEvictsMalformedSiblingsForPersistence|localExactValueMutationRetainsRollbackAcrossAuthoritativeReplay|metadataOnlyPageInfoInstallPublishesOnlyKeyedChanges|repeatedScribeShapedRefreshInvalidatesOnlyTheChangedSegment'`.
  Hashes: TripleIndexes
  `fabed7c368925d7895a5353b91953b34582e4fec8cb59c2fcd30d427bc11fd17`,
  InstantStore
  `a4612ef6b15129df5a83cbc4d69662197e2a58c4cd3efbbe7f6e8d8eaa2b368c`,
  Runtime server-apply/page-info shape
  `760ded51da3925dc6f797bd6ff44ecb055cbacc816d9176a13143e5f9d78d1e8`,
  InstantStoreTests
  `ca52594c3ee546b2993680cf5698dc7306564c99808fa90a56d21eab9ce03f84`,
  nested-limit tests
  `127eb41296bd55c9212d515fe29301e72bf92efe68d2d10dc3239b090a940da5`.

- 2026-08-15T02:10:00-0400 CLAIM — known no-materialized effect + provenance:
  `semantic_noop_v2` owns only optimistic rollback/state installation and
  invalidation consumers in `InstantRuntime.swift`, the initial overlay receipt
  in `InstantModels.swift`, and focused `InstantStoreTests.swift` regressions.
  Public construction stays unknown until Runtime completes a prepare; every
  completed prepare installs explicit `.applied` plus its optional inverse.
  Existing durable explicit-applied rows remain compatible. The serialized lane
  confirmed both focused tests red with `Active optimistic mutation ... has no
  durable rollback.` No SwiftPM/build by this worker.

- 2026-08-15T02:35:00-0400 CLAIM EXPANSION — explicit replayable-no-effect receipt:
  `semantic_noop_v2` additionally owns only active-state serialization/claim
  predicates in `SQLitePersistenceStore.swift` and new-mutation admission in
  `BoundedOutboxDelivery.swift`. The new durable state distinguishes a Runtime-
  proven replayable no-diff body from ambiguous historical `.applied + nil`.
  Unknown/unprepared public values must not enter automatic or explicit wire
  claims. Existing integer active indexes continue to include the new state.

- 2026-08-15T02:52:00-0400 CLAIM EXPANSION — receipt-aware effect metadata:
  `semantic_noop_v2` additionally owns only receipt validation/versioning in
  `InstantOptimisticEffectFootprint.swift`. Unknown receipts produce no normalized
  footprint. Quarantine clears derived effect metadata/entities so failed-unknown
  isolation can make unrelated server apply continue safely.

- 2026-08-15T01:57:48-0400 CLAIM — known no-materialized optimistic effect:
  `semantic_noop_v2` owns only the optimistic rollback/state installation and
  invalidation consumers in `InstantRuntime.swift`, plus focused regressions in
  `InstantStoreTests.swift`. An applied row with a completed prepare and no
  inverse remains replayable/deliverable but has no current materialized layer;
  legacy `state=nil` remains unknown and fail-closed. The regression target is
  effective local delete -> authoritative equivalent delete -> no-op pending
  replay -> later refresh/rejection without reconnect, plus an unresolved lookup
  that becomes effective after later authoritative data. No SwiftPM/build until
  source and tests are parser-clean and files are declared stable.
  Runtime's connect/startReceiving region remains released to
  `send_failure_reconnect_fix`; this slice did not edit it.

- 2026-08-14T23:17:05-0400 FILES STABLE schema-index follow-up:
  Independent final review found the prior exact-slot predicate could skip the
  insert that first reconciles derived indexes after server attributes are learned
  or change shape. The new red-by-construction regression seeds one exact value
  while its attribute is unknown, learns the same attribute as cardinality-one and
  indexed, reapplies the exact fact, and requires the changed persistence payload
  plus a successful indexed query. Against the prior source it returns no changed
  ID and no query row because EAV count alone passed while the slot stayed `.many`
  and namespace/value indexes stayed empty. No SwiftPM run was permitted, so this
  is static red evidence rather than an executed red result. `TripleIndexes` now
  records a compact derived-index schema shape, rebuilds VAE, indexed-value,
  indexed-entity, and namespace maps once when that shape changes or decoded
  indexes lack provenance, and only suppresses the authoritative insert when the
  normalized slot representation plus current derived entries are all valid.
  Deferred hydration, merge, insert, and retract paths share the same schema-shape
  reconciliation. Frontend parse and scoped `git diff --check` pass; no SwiftPM,
  build, stage, or commit ran. Updated exact filter:
  `swift test --jobs 1 --no-parallel --filter 'exactNormalizedScalarInsertReplaySkipsObservationInvalidation|exactRefReplaySkipsEndpointsButRelinkAndMembershipChangesInvalidate|authoritativeExactCardinalityOneReplayEvictsMalformedSiblingsForPersistence|authoritativeExactSchemaLearnReconcilesIndexedOneSlot|localExactValueMutationRetainsRollbackAcrossAuthoritativeReplay|metadataOnlyPageInfoInstallPublishesOnlyKeyedChanges|repeatedScribeShapedRefreshInvalidatesOnlyTheChangedSegment'`.
  Updated hashes: TripleIndexes
  `a595b01cd49a837cbf9e45a5c8dc8791da1ed9e2a398a7c22841cf5b03b87ac5`,
  InstantStoreTests
  `0fa83ee7e2cf11d4f836a1f940af597837566848b403f437de8d92138bac557e`.
  InstantStore and nested-limit hashes remain unchanged. Shared Runtime hash is
  now `e9ba7bcb3920f343fe66a8dc396170c32d4c59eee0b78971a93f48855525ec1b`
  because it also contains the coordinated reconnect worker's disjoint receiver
  install; this semantic follow-up did not alter Runtime.

- 2026-08-14T23:31:15-0400 plan-to-touch reconnect ownership follow-up:
  `send_failure_reconnect_fix` additionally claims only the package-internal
  receiver-owned send-failure marker, Runtime's live infinite-query unregister
  failure catch around line 3650 for a deterministic test checkpoint, and the
  corresponding marker guard in `recordConnectionError` around line 5107. A
  failure already retained by the exact current session/receiver must still fail
  the unregister operation, but its delayed caller may not persist `.errored`
  after explicit close or a healthy replacement has won. `semantic_noop_v2` has
  released these regions and remains stable around Runtime lines 2420/2620; all
  shared changes are preserved. No other Runtime, server-apply, Store, indexes,
  public API, schema, Scribe, SwiftPM, build, stage, or commit path is claimed;
  parser and scoped diff checks only.

- 2026-08-14T23:38:30-0400 plan-to-touch clarification:
  The deterministic checkpoint above belongs in the standard live-query
  unregister catch around line 3460, which is the independently reviewed stale
  caller path; it does not modify the analogous infinite-query catch. The
  regression therefore cancels a public standard observation, pauses after the
  receiver-owned unregister failure has reached its caller, waits for the exact
  receiver error status, closes, then releases the stale caller and requires
  `.closed` to remain authoritative.

- 2026-08-14T23:35:50-0400 timestamp correction: the immediately preceding
  clarification was appended at 23:35 EDT; its 23:38 label is a typographical
  error. Its ownership and scope statements are unchanged.

- 2026-08-14T23:35:50-0400 FILES STABLE reconnect ownership follow-up:
  `send_failure_reconnect_fix` completed the narrow late-caller correction
  without SwiftPM, build, stage, or commit. When a current session retains a
  send failure for its exact receiver/start boundary, the originating operation
  now throws a package-internal receiver-owned marker whose description remains
  the original error. Runtime ignores that marker only for connection-status
  persistence; the exact receiver still consumes the original transport error,
  saves `.errored`, and owns reconnect. The new standard-observation regression
  pauses its unregister catch after the receiver has persisted the scripted
  error, explicitly closes to `.closed`, releases the stale caller, then proves
  status and last-error metadata remain closed/clear, no replacement session was
  opened, and every exact close owner is idle. This also suppresses the same
  delayed marker after a healthy replacement, while true non-session-owned
  failures retain ordinary caller persistence. Frontend parse and scoped
  `git diff --check` pass. Exact filter:
  `currentRemovalFailureReconnectsAndReinstallsSurvivingQuery|unexpectedCurrentReceiverCancellationReconnectsBeforeLateSendFailure|preReceiverRemovalFailureCannotReturnOpenedConnection|explicitCloseSupersedesPendingRemovalFailureWithoutReconnect|receiverOwnedRemovalFailureCannotOverwriteExplicitClose|supersededRemovalFailureCannotOverwriteHealthyReplacementStatus`.
  Hashes: live session
  `1d11f4ec47e08a367737ddc881be4c383b30ee34866b8d01a9ed7bcdbff6dc30`,
  shared Runtime (including preserved semantic server-apply/page-info slices)
  `214adf67b7a91ac11bb87196a9436d508cea6dcca1e1904e9b4f43db6c95d2db`,
  live transport tests
  `a3d09fe1c4f1c73b89bad408c3997dcf0eefe9860a8ba09002e15b5b2164790e`.

- 2026-08-14T23:34:55-0400 semantic schema-reconciliation expansion:
  `semantic_noop_v2` retains its existing TripleIndexes/InstantStore/test ownership
  for the final derived-index blocker. Attribute merging now reconciles every
  changed derived-index shape before any rollback, authoritative operation,
  delete, require, or unrelated operation runs. Focused tests cover an empty
  transaction learning an indexed ref and then using its namespace/equality/VAE
  maps for reverse-reference deletion; an unknown indexed date-many value is
  normalized once and remains an exact replay; and a malformed many-to-one slot
  evicts a newer-stamped sibling through the authoritative repair path. Ordinary
  local last-write behavior remains unchanged. No Runtime reconnect slice,
  SwiftPM, build, stage, or commit is claimed.

- 2026-08-14T23:35:51-0400 FILES STABLE semantic schema reconciliation:
  Attribute merges reconcile changed derived-index shapes before hydration,
  rollback, delete, require, or any unrelated server operation. The merge-only
  regression learns an indexed ref from an unknown resident triple, proves the
  namespace/equality lookup, and then proves the rebuilt reverse-ref map removes
  that triple when its target is deleted. A second regression proves an unknown
  numeric date-many value normalizes once, remains an exact authoritative replay,
  and materializes through its indexed date filter. The malformed cardinality-one
  regression now gives the sibling a newer stamp; only the authoritative exact
  repair bypasses the ordinary LWW guard and evicts it. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact filter:
  `swift test --jobs 1 --no-parallel --filter 'exactNormalizedScalarInsertReplaySkipsObservationInvalidation|exactRefReplaySkipsEndpointsButRelinkAndMembershipChangesInvalidate|authoritativeExactCardinalityOneReplayEvictsMalformedSiblingsForPersistence|authoritativeExactSchemaLearnReconcilesIndexedOneSlot|schemaMergeWithoutMatchingOperationReconcilesIndexesAndReverseDelete|schemaMergeNormalizesUnknownIndexedDateManyBeforeExactReplay|localExactValueMutationRetainsRollbackAcrossAuthoritativeReplay|metadataOnlyPageInfoInstallPublishesOnlyKeyedChanges|repeatedScribeShapedRefreshInvalidatesOnlyTheChangedSegment'`.
  Hashes: TripleIndexes
  `cadf83094669036182d1831c105f700f71e54d62e1e237162ddfe0427d3369de`,
  InstantStore
  `7f2e0f1589d309f1a0e8f1067e93c9329a664a89d92973168804e2cdf801fb7e`,
  InstantStoreTests
  `79dfc86b59944b796a4c93aec7e77612b0f2f35ce74e391db3ea85f2a483e569`,
  nested-limit tests
  `127eb41296bd55c9212d515fe29301e72bf92efe68d2d10dc3239b090a940da5`.
  Shared Runtime was parser-clean at
  `214adf67b7a91ac11bb87196a9436d508cea6dcca1e1904e9b4f43db6c95d2db`
  and contains coordinated disjoint reconnect work; the semantic Runtime regions
  remain unchanged.

- 2026-08-14T23:51:14-0400 semantic many-to-one reconciliation follow-up:
  `semantic_noop_v2` retains its existing `TripleIndexes.swift`,
  `InstantStore.swift`, and focused `InstantStoreTests.swift` ownership for the
  final merge-only cardinality blocker. Learning cardinality-one over a resident
  many-valued slot must choose the normal deterministic last-write-wins fact,
  remove every losing sibling from materialization and derived indexes, and
  return the affected entity IDs so observers and SQLite persistence receive the
  canonical store. The regression owns hot materialization, indexed ordering,
  reverse-reference delete, and SQLite reload equality for two resident values;
  one-to-many behavior remains unchanged. Runtime reconnect and direct mutation
  reconnect catches remain owned by `send_failure_reconnect_fix`. No Runtime,
  SwiftPM, build, stage, or commit is claimed; parser and scoped diff checks only.

- 2026-08-14T23:54:00-0400 semantic Runtime coordination correction:
  Root confirmed `semantic_noop_v2` additionally owns only the server-apply
  accumulator initialization around `InstantRuntime.swift:2430`. A merge-only
  reconciliation result cannot reach observer invalidation or
  `changedEntityTriples` persistence while that accumulator starts empty. It will
  instead start from the merge-base prepared result. Reconnect ownership and its
  direct mutation-delivery catches around lines 5879/5937 remain exclusively
  `send_failure_reconnect_fix`; no other Runtime region is claimed.

- 2026-08-14T23:53:33-0400 automatic mutation reconnect ownership follow-up:
  `send_failure_reconnect_fix` is touching only the direct automatic mutation
  delivery failure catches around `InstantRuntime.swift:5879/5937`, their
  shared receiver-owned/superseded failure classifier and a package-only
  reconnect-controller idle test seam, plus one deterministic mutation fixture
  and regression in `InstantLiveTransportTests.swift`. The test holds the exact
  receiver pending after the originating mutation send fails, proves the sender
  leaves reconnect ownership idle, then releases the receiver and proves one
  reconnect reoffers the durable mutation. Semantic Runtime regions around
  2430/2480/2620 remain untouched. Parser and scoped diff checks only; no
  SwiftPM, build, stage, or commit.

- 2026-08-14T23:58:16-0400 FILES STABLE — automatic mutation sender ownership:
  `send_failure_reconnect_fix` completed the direct mutation-delivery correction.
  `InstantRuntime.callerOwnsLiveSessionFailure` now gives both automatic
  delivery catches and delayed connection-status recording one shared rule:
  superseded and receiver-owned send markers still fail their originating
  operation, but never persist status or schedule reconnect from that caller.
  A deterministic transact fixture holds the current receive loop pending after
  the send abort, proves the mutation pump finishes while the reconnect
  controller remains idle and status stays opened, then releases that exact
  receiver and proves one reconnect reoffers the durable transaction, returns
  opened, and closes with exact owners idle. Frontend parsing and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact filter:
  `swift test --jobs 1 --no-parallel --filter 'automaticMutationSendFailureLeavesReconnectToExactReceiver'`.
  Hashes: Runtime
  `ba31a3a306e1425a8b9af5cdb698aa2d46b68d11fd08e9ad5a02eec6172b6ec4`,
  LiveSession
  `1d11f4ec47e08a367737ddc881be4c383b30ee34866b8d01a9ed7bcdbff6dc30`,
  LiveTransport tests
  `8ce4ae08604005e4035ab4a14b51c2da1e020d632f803325d5774b3ea6a51735`.

- 2026-08-15T00:01:20-0400 FILES STABLE — semantic exact replay and schema reconciliation:
  Merge-only many-to-one schema learning now deterministically retains the
  newest resident stamp, removes siblings, rebuilds namespace/index/reverse-ref
  maps, and carries the affected source IDs through server-apply invalidation and
  SQLite persistence. Exact authoritative replay remains a zero-ID no-op only
  after the normalized slot and every derived index are already exact; local
  writes keep ordinary rollback-producing behavior. Page-info invalidation stays
  keyed and atomic with commit/publish. Frontend parsing and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact filters are the nine test
  names reported in the semantic handoff. Hashes: TripleIndexes
  `4a0d078c7ca37ab6f87205cda49de2c6f2002990a5e325e97ff4b9c1945ef03f`,
  InstantStore
  `9fb1af39cd6c9937013a54b2acbb564125732aa85b92e8197c80ad16d5740024`,
  Runtime
  `ba31a3a306e1425a8b9af5cdb698aa2d46b68d11fd08e9ad5a02eec6172b6ec4`,
  InstantStoreTests
  `15982ae29c3981a935401cb7f9fd68f886cf0bf892d1b7114799d4d2d3c31d4c`,
  nested-limit tests
  `127eb41296bd55c9212d515fe29301e72bf92efe68d2d10dc3239b090a940da5`.

- 2026-08-15T00:10:28-0400 same-generation retained-failure send gate:
  Focused execution showed the receiver-delayed mutation fixture sent the same
  transact twice on session zero before receiver release. `send_failure_reconnect_fix`
  is retouching only `InstantRuntimeLiveSession.swift` and the existing focused
  regression. Once a failure is retained for the current receiver generation
  and session identity, later sends through that exact session will fail
  locally with the receiver-owned marker before transport I/O, without
  consuming the retained exact error or giving the caller reconnect ownership.
  The test will assert session zero has exactly one transact before releasing
  its receiver and session one has exactly one reoffer after reconnect. Parser
  and scoped diff checks only; no SwiftPM, build, stage, or commit.

- 2026-08-15T00:12:03-0400 FILES STABLE — retained receiver failure blocks wire retries:
  `InstantRuntimeLiveSession.send` now checks the current opened generation,
  session identity, and retained receiver failure before diagnostics,
  in-flight accounting, timeout setup, or transport I/O. A same-generation
  retry throws the receiver-owned marker while the exact original failure
  remains stored for `startReceiving`/the installed receiver to consume and
  own status plus reconnect. The focused automatic mutation regression asserts
  session zero contains only `init, transact` before receiver release, repeats
  that assertion after reconnect, and asserts session one contains exactly one
  `init, transact` reoffer. Independent read-only review found no actor,
  Sendable, continuation, or ownership blocker. Frontend parsing and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact filter:
  `swift test --jobs 1 --no-parallel --filter 'automaticMutationSendFailureLeavesReconnectToExactReceiver'`.
  Hashes: Runtime
  `ba31a3a306e1425a8b9af5cdb698aa2d46b68d11fd08e9ad5a02eec6172b6ec4`,
  LiveSession
  `8bb2e7cab6da47757c5deb26b4f2566e4c847601c958e695660ba98eb2c874c3`,
  LiveTransport tests
  `f325a8c01f3f33fe775d2ddcc3e80bf602bbe7585f38528c41ea9edeeaeade65`.

- 2026-08-15T00:28:41-0400 FILES STABLE — peeled-base schema canonicalization:
  Schema-changing server apply now plans every active optimistic overlay, peels
  bounded reverse pages under the resident schema, merges/canonicalizes the
  authoritative base once, then applies the server transaction and replays
  pending mutations under the new schema. This prevents a newest pending value
  from evicting confirmed many-value siblings before its inverse runs. The new
  SQLite-backed regression proves confirmed A/B plus pending C becomes pending C
  with a rebuilt rollback-to-B, rejection restores B, and the hot, raw SQLite,
  and relaunched snapshots agree. Independent blocker review is clean. Frontend
  parsing and scoped `git diff --check` pass; no SwiftPM/build ran. Exact filter:
  `schemaManyToOnePeelsPendingValueBeforeCanonicalizationAndRejection`. Hashes:
  TripleIndexes
  `4a0d078c7ca37ab6f87205cda49de2c6f2002990a5e325e97ff4b9c1945ef03f`,
  InstantStore
  `91256644a74fcec5f676a10f225f7a31aeddd007b78a0c60e20b6f5d279fbd1b`,
  Runtime
  `41eb19a61bb304049d30d11292e3f7f304fd669c875e73c220a107a1ecafad7f`,
  InstantStoreTests
  `c83ddfe19b52f5ffa40b7b27f6efcf0914607401d4ac3b0b1f1aeaba61d0d053`,
  nested-limit tests
  `127eb41296bd55c9212d515fe29301e72bf92efe68d2d10dc3239b090a940da5`.

- 2026-08-15T02:30:00-0400 CLAIM — optimistic receipt test-fixture
  compatibility: `rollback_invariant_source` owns only direct-persistence
  fixture receipt installation in `InstantBoundedOutboxDeliveryTests.swift`,
  `InstantTerminalFailureComponentTests.swift`, and
  `InstantPersistenceCacheResidencyTests.swift`, plus focused automatic and
  explicit unknown-receipt claim coverage if it is not already covered by the
  root-owned `InstantStoreTests.swift`. Materialized fixtures receive a real
  nonempty inverse; intentionally unmaterialized persistence fixtures receive
  `.replayableWithoutMaterializedEffect` with nil rollback. Historical owners
  are not live and root assigned this disjoint mower slice. No production,
  other tests, stage, commit, ledger, SwiftPM, build, install, or device lane is
  claimed; frontend parse and scoped diff checks only until root releases the
  serialized test lane.

- 2026-08-15T02:35:08-0400 FILES STABLE — optimistic receipt fixture
  compatibility: Direct-persistence delivery fixtures in
  `InstantBoundedOutboxDeliveryTests.swift` and
  `InstantPersistenceCacheResidencyTests.swift` now explicitly prove an
  intentional unmaterialized/replayable effect; fixtures that model a current
  cache layer in all three owned files now pair `.applied` with a real nonempty
  inverse. Require-only, lookup, and global rule fixtures use
  `.replayableWithoutMaterializedEffect` with nil rollback instead of an empty
  inverse. The new explicit selector regression proves an unknown head is
  quarantined byte-for-byte while its prepared successor is claimed in the
  same pass. Automatic selector plus successor progress remains covered by
  `knownNoMaterializedOptimisticEffectUnpreparedPublicSaveCannotEnterDeliveryClaim`
  in the root-owned `InstantStoreTests.swift`, so it was not duplicated. Scoped
  `git diff --check` and `swiftc -frontend -parse` pass for all three files; no
  SwiftPM/build ran. Exact suite filters after lane release:
  `InstantBoundedOutboxDeliveryTests`,
  `InstantTerminalFailureComponentTests`, and
  `InstantPersistenceCacheResidencyTests`; focused new filter:
  `explicitClaimQuarantinesUnknownHeadAndClaimsPreparedSuccessor`. Hashes:
  Bounded Outbox `fba2b366e1df4e402d05387b731a619348835b3ccf73738bcab4d6a87deebfe0`,
  Terminal Component
  `907a2210ae930c4e3d973f16c7bab111589cb7b43fbefda6ce6f74d649842038`,
  Cache Residency
  `244afcee858e94f09a73946db9189eba0fd3933d56dd9ace8cc98704042fa402`.

- 2026-08-15T02:51:05-0400 FILES STABLE UPDATE — store-local receipt
  provenance in explicit claim fixture: The intentional unknown head is first
  persisted through the public boundary. The prepared successor is then added
  through the internal runtime-authority outbox diff with exact revisions, so
  the unchanged head remains untrusted while only the successor receives a
  fingerprint in the target SQLite store. Frontend parsing and scoped
  `git diff --check` pass; no SwiftPM/build ran. Focused filter remains
  `explicitClaimQuarantinesUnknownHeadAndClaimsPreparedSuccessor`. Updated
  Bounded Outbox hash
  `f732a6207e75cee91c7194d8d3fcddbaaa3a1d6a8fcd3e0e7518860b462ba881`;
  Terminal Component and Cache Residency hashes are unchanged.

- 2026-08-15T02:55:34-0400 CLAIM UPDATE — optimistic receipt fixture
  compatibility: `rollback_invariant_source` additionally owns only truthful
  receipt state and target-store Runtime-authority seeding in
  `InstantBoundedServerApplyRebaseTests.swift` and
  `InstantFailedMutationRetryWindowTests.swift`. Intentional corrupt and legacy
  unknown rows remain untrusted. Preserve every concurrent production and test
  edit; no production, other tests, stage, commit, ledger, SwiftPM, build,
  install, or device lane is claimed. Frontend parse and scoped diff checks only.

- 2026-08-15T02:56:56-0400 FILES STABLE — bounded server-apply and failed-retry
  receipt fixtures: `boundedServerApplyMutation` now pairs its materialized
  `.applied` state with the existing real nonempty rollback, and the shared
  runtime fixture seeds the store first before atomically admitting its outbox
  through target-store Runtime authority. Failed-retry fixtures now use the
  same target-store authority helper; the explicit `overlayState: nil` legacy
  row still receives no fingerprint, and the separately corrupted row remains
  corrupted only after trusted seeding. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact suite filters after lane
  release: `InstantBoundedServerApplyRebaseTests` and
  `InstantFailedMutationRetryWindowTests`. Hashes: Bounded Server Apply
  `e3f836771743bda45791237e528ccb7d29d07fc07ef19d7361113883820fbf3a`;
  Failed Retry Window
  `7620f9f641f4460144250c2fee30dafb6bd7a9c2835260ca499da9261da83068`.

- 2026-08-15T02:57:23-0400 CLAIM UPDATE — final disjoint optimistic receipt
  fixture batch: `rollback_invariant_source` additionally owns only the
  oversized terminal-component receipt/trusted seed in
  `InstantLiveTransportTests.swift`, the four inventoried persisted-tail
  provenance fixtures in `InstantOutboxSupersessionIntegrationTests.swift`, and
  the legacy-accepted plus target-store prepared pending-tail fixture in
  `InstantServerAcceptanceProofTests.swift`. Intentional legacy, oversized, and
  corrupt evidence remains untrusted. Preserve all unrelated transport,
  supersession, production, and test edits; no SwiftPM, build, stage, commit,
  ledger, install, or device lane is claimed. Frontend parse and scoped diff
  checks only.

- 2026-08-15T02:59:48-0400 FILES STABLE — transport, supersession, and
  acceptance-proof receipt fixtures: The oversized terminal-component chain now
  carries `.applied` plus its existing real inverse and is admitted through
  target-store Runtime authority after its materialized store seed. The three
  valid supersession tails now carry `.applied` plus their existing inverses and
  are target-store trusted before fault injection; the oversized legacy tail
  remains a public untrusted body. The acceptance proof now publicly persists
  only the historical accepted row, keeps its missing rollback/fingerprint
  unknown, and appends a materialized pending row with a real inverse through
  target-store Runtime authority; explicit fingerprint assertions prove that
  split. Frontend parse and scoped `git diff --check` pass; no SwiftPM/build ran.
  Exact filters after lane release:
  `runtimeLiveOversizedTerminalComponentFailsOnlyClaimedTargetWithoutReconnect`,
  `claimAfterInvalidTailReadPreventsQuarantineAndPreservesRawEvidence`,
  `oversizedNormalizedTailIsNeverDecodedByTenThousandLaterEnqueues`,
  `staleSmallByteMetadataCannotMaterializeAnOversizedImmediateTail`,
  `corruptImmediateTailIsDecodedAndQuarantinedOnceBeforeTenThousandLaterEnqueues`,
  and `acceptedLegacyMutationsAreNotOfferedToTheTransport`. Hashes: Live
  Transport `d73ef9576c3e89e4c89e44d1385f2f9185197918e58c993fdae9a0ca6e1972eb`;
  Supersession `755c2ad722dcfdaa008985fda8c54cd826b7416ec3b953daa47e6a742639f71e`;
  Acceptance Proof `e535667377220d19a81d649715885b9f6cee11f92c73279e47dcea361dbc0a0f`.

- 2026-08-15T03:06:31-0400 FILES STABLE UPDATE — coherent pre-0020 bounded
  outbox migration fixture: `restorePreBoundedDeliveryOutboxSchema` now removes
  migration 0020 from the ledger when it recreates `instant_outbox` without the
  optimistic-effect receipt fingerprint column. Reopening therefore reruns the
  migration that restores the removed column instead of leaving the database
  falsely marked current. Frontend parsing and scoped `git diff --check` pass;
  no SwiftPM/build ran. Exact filter:
  `migrationTreatsLegacyRowsAsOfferedAndNewRowsAsNeverOffered`. Updated Bounded
  Outbox hash
  `2728debe911e57be6af1292fa99063db47bd2efdd04931050643f5cdf9331323`.

- 2026-08-15T03:08:14-0400 FILES STABLE UPDATE — terminal-component fixture
  provenance: The shared `terminalPersistence` helper now admits its canonical
  prepared mutations through the target SQLite store's internal Runtime
  authority using exact store/outbox revisions. The later status-only public
  rewrite remains public and therefore continues to cover preservation of an
  unchanged database-owned fingerprint. Frontend parsing and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact filter:
  `InstantTerminalFailureComponentTests`. Updated Terminal Component hash
  `1f1975ab3a4d7b0a848832a500402c3111feded993f58c708c5409f486e7a08b`.

- 2026-08-15T03:10:18-0400 CLAIM UPDATE — retained-unknown receipt wording:
  `rollback_invariant_source` additionally owns only the stale fail-closed error
  assertion in `InstantFailedMutationDiscardTests.swift`. The substantive
  retry/discard refusal and `.retainedUnknown` disposition assertions remain
  unchanged. No production, other tests, SwiftPM, build, stage, or commit lane
  is claimed; frontend parsing and scoped diff checks only.

- 2026-08-15T03:10:42-0400 FILES STABLE — retained-unknown receipt wording:
  The shared unknown-state assertion now matches the durable provenance error's
  `matching SQLite-owned Runtime preparation receipt` contract while preserving
  the exact local id and `.retainedUnknown` disposition checks for both retry
  and discard. Frontend parsing and scoped `git diff --check` pass; no
  SwiftPM/build ran. Exact filters: the legacy-unknown retry/discard cases in
  `InstantFailedMutationDiscardTests`. Hash
  `97ff3b5332f19be4a7167e99f250b1d96448f080ffa50184d3b0e82cb167be7f`.

- 2026-08-15T03:12:44-0400 CLAIM UPDATE — public-tail supersession
  provenance: `rollback_invariant_source` expands its existing
  `InstantOutboxSupersessionIntegrationTests.swift` ownership by exactly one
  focused regression for a well-formed public-persisted immediate tail whose
  canonical-looking body has no SQLite-owned Runtime fingerprint. The test will
  require raw quarantine preservation, no supersession lifecycle/alias, and a
  target-store Runtime-prepared newcomer that remains able to progress. No
  production, other tests, SwiftPM, build, stage, or commit lane is claimed.

- 2026-08-15T03:14:00-0400 FILES STABLE UPDATE — public-tail supersession
  provenance: `wellFormedPublicTailIsQuarantinedWithoutSupersessionAndNewcomerProgresses`
  now proves that a well-formed public-saved `.applied` body with a real inverse
  still has no SQLite-owned Runtime fingerprint, is quarantined byte-for-byte,
  and creates neither lifecycle nor alias metadata. A same-entity newcomer
  prepared by the target-store Runtime remains pending with a nonempty inverse
  and a nonnil fingerprint while its optimistic value materializes. Frontend
  parsing and scoped `git diff --check` pass; no SwiftPM/build ran. Exact filter:
  `wellFormedPublicTailIsQuarantinedWithoutSupersessionAndNewcomerProgresses`.
  Updated Supersession hash
  `ce82661de39dc04550afcc2c26761bf084280b06746379b0b3103bd4a7d771a8`.

- 2026-08-15T03:21:14-0400 CLAIM UPDATE — remaining bounded/cache receipt
  fixtures: `rollback_invariant_source` expands its existing ownership of
  `InstantPersistenceCacheResidencyTests.swift` to the automatic-retry and
  terminal-attribute-race fixtures, and its existing ownership of
  `InstantBoundedOutboxDeliveryTests.swift` to the canonical delivery seed
  family, explicit forward-wire rebase acknowledgement contract, and
  historically plausible pre-0012 ordering fixture. Materialized rows will get
  coherent store effects plus target-store Runtime authority; intentionally
  public/legacy unknown rows remain untrusted. No production, other tests,
  SwiftPM, build, stage, commit, ledger, install, or device lane is claimed.

- 2026-08-15T08:41:45-0400 CLAIM UPDATE — exact claim-token acknowledgement
  authority: `bounded_claim_token_tests` shares the already-claimed
  `InstantBoundedOutboxDeliveryTests.swift` test path and owns only exact
  claim-token call-site repairs plus focused stale-acknowledgement and accepted
  same-id changed-wire rewrite regressions. It will preserve all unrelated test
  and production edits, use the current production API, and run only frontend
  parse and scoped diff checks; no SwiftPM, build, stage, commit, ledger,
  install, or device lane is claimed.

- 2026-08-15T08:44:28-0400 FILES STABLE — exact claim-token
  acknowledgement authority: all three pre-existing direct SQLite ACK call
  sites in `InstantBoundedOutboxDeliveryTests.swift` now pass the token that
  created their exact claim. The focused stale-ACK regression proves claim A,
  a Runtime-prepared changed-wire same-id rewrite, claim B, rejection of late
  token A without a revision or claim change, and successful acceptance by
  token B. A second regression proves that both public persistence and
  Runtime-prepared changed-wire rewrites of an accepted id throw while the
  accepted body and external acceptance fingerprint remain unchanged. Frontend
  parse and scoped `git diff --check` pass; no SwiftPM/build ran. Exact filters:
  `automaticClaimExcludesForeignRuntimeSuccessorUntilHeadIsAccepted`,
  `legacyClaimWithoutProjectedBytesBlocksRefillUntilReleased`,
  `explicitFlushCannotLeapfrogAnAutomaticallyClaimedHead`,
  `staleAcknowledgementCannotAcceptARewrittenAndReclaimedPayload`, and
  `acceptedMutationRejectsPublicAndRuntimePreparedChangedWireRewrites`. Hash:
  `e96a6c53b3efe399b2a49c03db33e83470b5d5fd9376b5e81f092706586c15d7`.

- 2026-08-15T08:45:47-0400 FILES STABLE UPDATE — stale-ACK revision
  assertion: the post-ACK actor read is now hoisted out of
  `expectNoDifference`'s synchronous autoclosure. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact filter:
  `staleAcknowledgementCannotAcceptARewrittenAndReclaimedPayload`. Updated hash:
  `d4bb5a60371ea76848f7e4e0b38550be2359244eaa64b714665c42d77273cc5c`.

- 2026-08-15T08:48:10-0400 CLAIM UPDATE — row-addressed hydration
  acceptance authority: `bounded_claim_token_tests` additionally owns only the
  four `acceptMutationIfPresent` fixtures in
  `InstantOutboxHydrationTests.swift`. The 10,000-row test will preserve its
  one-addressed-body decode and bounded-state contract while admitting the
  target through target-store Runtime authority and claiming it with the exact
  owning Runtime/token. Duplicate acceptance may omit a token only after the
  SQLite acceptance marker exists; missing-row acceptance may omit it. No
  production, other tests, SwiftPM, build, stage, commit, ledger, install, or
  device lane is claimed.

- 2026-08-15T08:50:20-0400 FILES STABLE — row-addressed hydration
  acceptance authority: the 10,000-row fixture now publicly seeds 9,998 inert
  rows and uses the target Runtime's `transact` path for the target plus the
  locally confirmed receipt, preserving exactly 10,000 durable rows. Their
  earlier creation positions let separate one-row automatic claims owned by
  that Runtime select them without decoding the later malformed public head.
  Both first server acceptances pass their exact claim tokens; the duplicate
  passes nil only after SQLite-bound acceptance exists, and the missing-row
  probe passes nil. Separate counters preserve the one-body claim and one-body
  row-addressed ACK contracts. Frontend parse and scoped `git diff --check`
  pass; no SwiftPM/build ran. Exact filter:
  `serverAcceptanceDecodesOnlyAddressedRowInTenThousandRowOutbox`. Hash:
  `d04ba9c515253c1685dbeb69487538e7708a3da2b8cd9bdb88c07757d21346ad`.

- 2026-08-15T08:42:48-0400 CLAIM UPDATE — lifecycle SQLite authority: `root`
  owns only focused additions to `InstantMutationLifecycleTests.swift` proving
  that caller-shaped acceptance cannot mint a lifecycle event, untrusted failed
  bodies expose an unknown local effect, and a genuinely SQLite-authorized
  acceptance survives relaunch. Production source remains in the existing root
  ownership; no staging, commit, install, or device lane is claimed yet.

- 2026-08-15T09:14:12-0400 CLAIM UPDATE — final receipt migration and
  public-authority boundary: `root` takes over the now-idle
  `semantic_noop_v2` production ownership in
  `SQLitePersistenceStore.swift` and shares the already-stable
  `InstantBoundedOutboxDeliveryTests.swift` only for an exact 0020 migration
  matrix and pending prepared-row public rewrite regression. Scope is bounded
  to released receipt-shape compatibility, bounded primary-key migration,
  malformed pre-0017 handling, and refusal to create an ownerless prepared
  overlay. Concurrent Runtime/live-session review remains read-only. No stage,
  commit, ledger, install, or device lane is claimed yet.

- 2026-08-15T09:18:04-0400 CLAIM UPDATE — exact live claim ownership:
  `final_acceptance_review`, delegated by `root`, owns only atomic response
  claim-token capture in `InstantRuntimeLiveSession.swift`, reclaimed live
  reservation retirement in the narrow explicit-flush/receive call sites of
  `InstantRuntime.swift`, and focused regressions in
  `InstantLiveTransportTests.swift`. It will preserve every concurrent edit,
  write tests first, and run parser/scoped-diff checks only. It does not own
  SQLite persistence, migrations, other tests, SwiftPM, build, stage, commit,
  ledger, progress, install, or device lanes.

- 2026-08-15T09:24:34-0400 FILES STABLE — exact live claim ownership:
  Response recording now captures the offered claim token before removing the
  in-flight anti-reoffer reservation and carries that actor-local token through
  the Runtime handler; its testing checkpoint deterministically allows a
  same-generation reoffer after capture and proves the stale ACK cannot adopt
  the replacement token. The explicit flush now consumes every reclaimed id
  through timed-out live-reservation release while holding the operation gate,
  aborting an acknowledgement-unknown generation before same-id reoffer.
  Frontend parsing and scoped `git diff --check` pass; no SwiftPM/build ran.

- 2026-08-15T09:51:02-0400 CLAIM UPDATE — legacy-head authority contract:
  `legacy_head_contract_tests`, delegated by `root`, shares the already-claimed
  `InstantBoundedOutboxDeliveryTests.swift` path and owns only the broad-suite
  legacy-head regression. The existing public accepted-looking rows plus the
  corrupt active sentinel will become an explicit manual-recovery connection
  barrier with zero transport sends and a still-pending tail. A separate
  positive test will preserve authorized-head non-starvation using exact
  SQLite Runtime receipt and claim/acknowledgement authority without an unknown
  corrupt row. No production, other tests, SwiftPM, build, stage, commit,
  ledger, install, or device lane is claimed.
  Exact filters: `explicitFlushReclaimRetiresTheOfferedLiveGeneration` and
  `staleAcknowledgementCannotAdoptAClaimTokenReofferedDuringResponseRecording`.
  Hashes: Runtime Live Session
  `40589602bb75582dfcd427b049316ba5bb51208c296d30492be99d91389dd82e`;
  Runtime
  `edf6822b7d3e73962e312dbdf31972c8ab94f7a9d2475a1646050e03c6f74762`;
  Live Transport Tests
  `3b6b31d13d942aaf3d791b86e6dd20589fff05b531225154e0eff2a9c74cfb77`.

- 2026-08-15T09:31:20-0400 DELEGATED CLAIM — terminal lifecycle migration
  authority: `terminal_lifecycle_authority_tests`, delegated by `root`, shares
  only `InstantMutationLifecycleTests.swift` to add focused pre-0021 terminal
  lifecycle relaunch fixtures. The tests will require caller-shaped terminal
  acceptance to remain waiting and caller-shaped failed rollback data to be
  sanitized without SQLite-owned authority, while preserving a valid
  SQLite-authorized terminal case when the existing fixture permits. No
  production, SwiftPM, build, stage, commit, ledger, install, or device lane is
  claimed; frontend parse and scoped diff checks only.

- 2026-08-15T09:35:44-0400 FILES STABLE — terminal lifecycle migration
  authority: two fixtures now bootstrap the current database, seed only the
  pre-0021 lifecycle columns, remove migration 0021, and relaunch with no
  physical outbox row. A terminal body that claims server acceptance resolves
  to waiting because the migrated acceptance marker is null; a failed terminal
  body that claims an applied rollback remains failed but exposes neither
  overlay state nor rollback and reports an unknown local effect. The existing
  genuine SQLite-authorized relaunch acceptance remains as the positive
  control. Frontend parse and scoped `git diff --check` pass; no SwiftPM/build,
  stage, or commit ran. Exact filters:
  `preReceiptAuthorityTerminalAcceptanceRemainsWaitingAfterRelaunch`,
  `preReceiptAuthorityTerminalFailureReportsUnknownLocalEffectAfterRelaunch`,
  and positive control `SQLiteAuthorizedAcceptanceSurvivesRelaunch`. Test-file
  hash: `a29463b2ad1511188b8877e5fb1c2c76baf62398a75bd22966bef090506214cd`.

- 2026-08-15T09:37:04-0400 FILES STABLE UPDATE — terminal lifecycle SQLite
  error conversion: the focused build found that passing
  `String.init(cString:)` directly to `Optional.map` did not match the mutable
  C-pointer type. The helper now uses the explicit closure form. No fixture or
  assertion behavior changed. Frontend parse and scoped `git diff --check`
  pass; no SwiftPM command ran. Exact filters are unchanged. Updated test-file
  hash: `4d3348474c6114c838442ca48c99ab1ee35a1e6d2983b0b91e39dadc8165ae79`.

- 2026-08-15T09:53:46-0400 FILES STABLE — legacy-head authority contract:
  the old mixed legacy-head regression is now a bounded fail-closed fixture.
  Two post-0020 public accepted-looking rows have no Runtime receipt or SQLite
  server-acceptance fingerprint; the first remains an active raw malformed
  sentinel, so connection preflight reports retained-unknown manual recovery,
  performs zero body decodes and zero transport sends, preserves raw evidence
  without manufacturing quarantine evidence, and leaves the prepared tail
  pending and unclaimed. The separate positive control creates two heads with
  Runtime preparation receipts, exact claim ownership, and SQLite acceptance
  fingerprints, then proves the prepared tail is the only transact send. The
  accepted changed-wire regression already expects `persist accepted outbox
  mutation`; no edit was needed there. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build ran. Exact filters:
  `untrustedAcceptedHeadsAndCorruptSentinelBlockConnectionBeforePendingTail`,
  `SQLiteAuthorizedAcceptedHeadsDoNotStarvePendingTail`, and unchanged
  `acceptedMutationRejectsPublicAndRuntimePreparedChangedWireRewrites`.
  Test-file hash:
  `98f257bbce79ccf35e7a9fe7994ab48ff2af634c0825d57206bda36785813e36`.

- 2026-08-15T09:54:56-0400 CLAIM UPDATE — attainable claimed-tail
  corruption order: `legacy_head_contract_tests`, delegated by `root`, owns
  only `claimAfterInvalidTailReadPreventsQuarantineAndPreservesRawEvidence` and
  its now-single-use race helper in
  `InstantOutboxSupersessionIntegrationTests.swift`. The impossible attempt to
  claim after direct body corruption will be replaced with an exact receipt-
  validated claim acquired before fault injection; the later supersession must
  respect that durable ownership and retain raw evidence. No production, other
  tests, SwiftPM, build, stage, commit, ledger, install, or device lane is
  claimed; frontend parse and scoped diff checks only.

- 2026-08-15T09:55:45-0400 FILES STABLE — attainable claimed-tail
  corruption order: the impossible hook that attempted to mint a claim after
  direct body corruption is gone. The renamed
  `claimAcquiredBeforeTailCorruptionPreventsQuarantineAndPreservesRawEvidence`
  first proves a nonnil SQLite preparation receipt, acquires the exact durable
  claim, and only then injects raw corruption. A concurrent Runtime transaction
  respects that existing ownership: the claim stays live, no quarantine row is
  manufactured, the raw bytes are unchanged, the newcomer appends, and its
  optimistic value becomes current. The obsolete single-use hook helper was
  removed. Frontend parse and scoped `git diff --check` pass; no SwiftPM/build
  ran. Exact filter:
  `claimAcquiredBeforeTailCorruptionPreventsQuarantineAndPreservesRawEvidence`.
  Test-file hash:
  `6aa6350c67d67443506bd882d37dd4fad6077e2baeeca0bd6e81bfc9ea5191a6`.

- 2026-08-15T09:58:25-0400 CLAIM UPDATE — typed synchronization
  blocker: `legacy_head_contract_tests`, delegated by `root`, owns only the
  public blocker/status model additions in `InstantModels.swift`, their shared
  package error factory, local-blocker presentation in `InstantSyncStatus.swift`,
  and focused Codable/error plus SwiftUI-state tests in
  `MutationDeliveryTests.swift` and `V3PreferencesFixtureTests.swift`.
  Existing optimistic receipt edits in `InstantModels.swift` remain preserved;
  SQLite persistence and Runtime are explicitly outside this slice. No other
  tests, SwiftPM, build, stage, commit, ledger, install, or device lane is
  claimed; frontend parse and scoped diff checks only.

- 2026-08-15T10:00:30-0400 FILES STABLE — typed synchronization
  blocker: `InstantSynchronizationBlocker` now publicly carries the closed
  `.unknownOptimisticEffectReceipt` reason, first durable mutation id, and
  blocked count. Its package error factory preserves the exact
  `.persistenceFailed` / `.retainedUnknown` authority boundary and says that
  reconnect is paused and synchronization remains blocked until explicit
  destructive reset or operator repair; it explicitly disclaims guaranteed
  lossless recovery. `InstantConnectionStatus` has an optional defaulted
  blocker field whose missing-key legacy JSON decodes to nil. SwiftUI sync
  state exposes the blocker, summarizes it exactly as `Local sync recovery
  required`, disables flush even in an authenticated phase, and clears rather
  than synthesizes a network error. Focused tests cover Codable round-trip and
  missing-key compatibility, canonical error fields, blocker presentation,
  and return to normal pending status. All four files pass frontend parse and
  scoped `git diff --check`; no SwiftPM/build ran. Exact filters:
  `synchronizationBlockerRoundTripsAndLegacyConnectionStatusDecodesWithoutIt`,
  `unknownReceiptSynchronizationBlockerBuildsCanonicalManualRecoveryError`,
  and
  `localSynchronizationBlockerRequiresRecoveryWithoutBecomingANetworkError`.
  Hashes: InstantModels
  `c10132c980f6bd887e544faf486b09f63204d1eb38659c499c2977334eef7d57`;
  InstantSyncStatus
  `44acbcd6749e92a257cf940b28010115809125b6f4a8bb25093b49f5e686f29c`;
  MutationDeliveryTests
  `817f7572bd573e39627855201fe0d2f4979ee756c70de9efe972235b76f0d327`;
  V3PreferencesFixtureTests
  `8f59e80bdc9b92aa7c36d9b7fe3652aab85f5b89ec53a3a9140973c5a62095dc`.

- 2026-08-15T10:02:36-0400 CLAIM UPDATE — atomic blocker claim
  contracts: `legacy_head_contract_tests`, delegated by `root`, owns only the
  stale explicit and automatic unknown-head claim tests in
  `InstantBoundedOutboxDeliveryTests.swift` and `InstantStoreTests.swift`, plus
  one focused blocked-local-write/relaunch test if it remains small. Both claim
  paths must now throw the canonical typed blocker before body decode,
  quarantine, or claim while preserving the unknown row and prepared
  successor. The existing server-apply fail-closed regression remains intact.
  Current concurrent SQLite/Runtime implementation edits are read-only and
  explicitly outside this slice. No other tests, SwiftPM, build, stage, commit,
  ledger, install, or device lane is claimed; frontend parse and scoped diff
  checks only.

- 2026-08-15T10:04:44-0400 FILES STABLE — atomic blocker claim
  contracts: explicit and automatic claim tests now require the canonical
  typed blocker before any durable body decode, quarantine, or claim. Both
  assert `.persistenceFailed`, `.retainedUnknown`, the exact claim operation,
  first mutation id, blocked count one, zero decoded bodies, nil quarantine,
  retained pending unknown state, and a receipt-backed prepared successor that
  stays ready and unoffered. The obsolete bounded claim probe was removed. A
  focused Runtime test proves `transact` still materializes and durably receipts
  a new local write behind the blocker, keeps it ready/unsent, and reconstructs
  the same value, receipt, blocker, and two pending rows across relaunch with
  zero transport attempts. The separate server-apply fail-closed test is
  unchanged. Both files pass frontend parse and scoped `git diff --check`; no
  SwiftPM/build ran. Exact filters:
  `explicitClaimThrowsSynchronizationBlockerBeforeUnknownHeadDecodeOrSuccessorClaim`,
  `automaticClaimThrowsSynchronizationBlockerBeforeUnpreparedPublicHeadDecodeOrSuccessorClaim`,
  `runtimeTransactWhileSynchronizationBlockedPersistsReceiptAndRemainsUnsentAcrossRelaunch`,
  plus unchanged
  `knownNoMaterializedOptimisticEffectServerApplyBlocksPendingUnknownBeforeClaim`.
  Hashes: Bounded Outbox
  `0651f50f44dc5d9144fcfceb646538b40bc036c7cfd57e4d9c78380f918f5d0e`;
  Store
  `1628b43709f4fb0eb33535f9a531f418ce4ec879128baebd7372b64df3160902`.

- 2026-08-15T10:10:00-0400 ROOT PLAN UPDATE — structured blocker
  integration: root retains the previously recorded Runtime/SQLite ownership
  and is correcting three review-confirmed authority gaps before broad tests:
  suspend/skip auto-connect at bootstrap and suspend on live blocker failure;
  durably demote a decoded body/receipt mismatch to the canonical nil-receipt
  blocker before throwing; and add/use a receipt-keyed blocker index. The
  bounded claim tests are released and receive only the two compile-only
  throwing-expression hoists found by the serialized build. No stage, commit,
  app build, install, or device action until focused and broad tests are green.
- 2026-08-15T10:11:39-0400 — /root/legacy_head_contract_tests claims InstantStoreTests.swift for typed-blocker bootstrap and receipt/body refresh regressions; test-only, no production or SwiftPM.

- 2026-08-15T10:14:25-0400 DELEGATED CLAIM — synchronization blocker
  index regression: `blocker_index_test`, delegated by `root`, shares only
  `InstantBoundedOutboxDeliveryTests.swift` and owns one focused test plus
  test-local SQLite query-plan helpers. It will seed a mixed durable outbox,
  require `instant_outbox_synchronization_blocker_idx` with no temporary
  order-by B-tree, and assert the exact first blocked id/count. If the existing
  reconstructed-table fixture makes it straightforward, it will also prove the
  index survives that migration path. No production, other tests, SwiftPM,
  build, stage, commit, ledger, install, or device lane is claimed; frontend
  parse and scoped diff checks only.

- 2026-08-15T10:16:46-0400 FILES STABLE — synchronization blocker index
  regression: one focused test seeds 1,000 receipt-backed mutations, changes
  three active rows into blockers and two earlier rows into inactive controls,
  and requires exact first id `tx-blocker-index-00307` with blocked count three.
  Raw SQLite `EXPLAIN QUERY PLAN` requires the covering
  `instant_outbox_synchronization_blocker_idx` for both the ordered first-row
  selector and count, with no temporary order-by B-tree. The same test rebuilds
  `instant_outbox` while deliberately retaining migration 0022, then relaunches
  and proves the unconditional repair restores the same covering ordered plan
  without duplicating the migration ledger row. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build, stage, or commit ran. Exact filter:
  `synchronizationBlockerUsesCoveringIndexAndRepairsReconstructedTable`. Test
  file hash:
  `5ab016a707fd24500c1fa01e684d42b1ea001f9bad382b1950de49ac7e742e39`.

- 2026-08-15T10:17:54-0400 FILES STABLE — typed blocker bootstrap and
  receipt/body refresh regressions: `InstantStoreTests.swift` now proves an
  automatic launch over a nil-receipt active row makes no transport or
  reconnect-sleep attempt, leaves the reconnect controller idle, and suspends
  the mutation delivery pump before and after a later receipt-backed local
  transaction and relaunch. A separate scripted live-refresh test rewrites one
  valid prepared body behind its nonnil SQLite receipt, proves init is harmless,
  then requires the refresh to retain the body/store/checkpoint atomically,
  demote the receipt to nil, publish the exact structured blocker, suspend the
  pump, and make no reconnect or sleep. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build, stage, or commit ran. Exact filters:
  `runtimeTransactWhileSynchronizationBlockedPersistsReceiptAndRemainsUnsentAcrossRelaunch`
  and
  `preparedActiveReceiptBodyMismatchBlocksLiveRefreshAtomicallyWithoutReconnect`.
  File hash:
  `6df0430f5e0cef34cfc3a88e4da0c9c41aabe9c59674b418d8ad13535752e851`.

- 2026-08-15T10:23:21-0400 DELEGATED CLAIM — compact blocker assertion
  correction: `blocker_index_test`, delegated by `root`, again shares only
  `InstantBoundedOutboxDeliveryTests.swift` to correct the focused explicit
  blocker test's expectation that `loadCompactState()` contains durable outbox
  bodies. It will preserve the fixture and assert retained pending rows through
  the bounded revision-qualified durable loader after the existing zero-decode
  proof. No production, other tests, SwiftPM, build, stage, or commit is
  claimed; frontend parse and scoped diff checks only.

- 2026-08-15T10:24:05-0400 FILES STABLE — compact blocker assertion
  correction: the explicit blocker fixture was correct; `loadCompactState()`
  intentionally omits all queue-depth-proportional outbox shells. After the
  existing zero-body-decode assertion, the test now uses the bounded,
  revision-qualified durable loader for exactly the unknown head and prepared
  successor, and retains the pending-status assertions. This proves SQLite
  durability without weakening compact-cache containment or turning the claim
  path's no-decode proof into a queue-wide read. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build, stage, or commit ran. Exact filter:
  `explicitClaimThrowsSynchronizationBlockerBeforeUnknownHeadDecodeOrSuccessorClaim`.
  Test file hash:
  `b8ab53350441d7fb6b43c144fdb45015318df2096ca892905f56df51a9c24441`.

- 2026-08-15T10:23:15-0400 — /root/legacy_head_contract_tests reclaims
  `InstantStoreTests.swift` only to repair deterministic choreography in the two
  newly focused typed-blocker regressions after parent-run failure evidence;
  no production edits or SwiftPM.

- 2026-08-15T10:27:30-0400 ROOT CLAIM — claimed-tail corruption regression:
  root reclaims only
  `Tests/InstantSwiftDataCoreTests/InstantOutboxSupersessionIntegrationTests.swift`
  after the prior owner reported FILES STABLE. The focused failure reads a
  memory-thinned compact persistence snapshot, which is not the contract for
  the newly materialized local value; root will switch that assertion to the
  live runtime store snapshot without changing production behavior. No other
  supersession test or production source is claimed.

- 2026-08-15T10:32:10-0400 ROOT CLAIM — final focused test corrections:
  after delegated FILES STABLE, root reclaims only
  `InstantStoreTests.swift` and `InstantLiveTransportTests.swift`. The blocked
  local-write test will inspect the local store directly instead of invoking a
  live query that correctly refuses connection preflight, and the explicit
  reclaim test will scope its single deterministic timeout `reportIssue`
  without relying on toolchain-specific Issue rendering. No production source
  or other test is claimed.

- 2026-08-15T10:36:00-0400 ROOT CLAIM — broad persistence regression
  corrections: root reclaims
  `InstantBoundedOutboxDeliveryTests.swift` and
  `InstantFailedMutationRetryWindowTests.swift` after their prior owners
  reported FILES STABLE. First, both pre-0020 schema helpers will drop the new
  receipt-keyed covering index before dropping its receipt column. Root is also
  auditing the old quarantine-and-continue expectations against the new
  fail-closed active-owner blocker before changing those contracts. Production
  claim behavior remains under read-only independent review until that verdict.

- 2026-08-15T10:42:00-0400 ROOT CLAIM — strict receipt fixture alignment:
  root additionally claims only `InstantOutboxHydrationTests.swift`. The
  10,000-row row-addressed acceptance fixture will represent its 9,998 empty
  bodies as target-store Runtime-prepared replayable/no-current-effect rows,
  rather than public unprepared active rows that correctly trigger the global
  blocker. The failed-retry legacy-row case will likewise assert body-free
  blocking before decode instead of obsolete isolation-and-progress behavior.
  No production implementation is changed in this slice.

- 2026-08-15T10:28:20-0400 FILES STABLE — focused Store blocker failure
  choreography: the bootstrap regression now proves the seeded structured
  blocker before launch and scopes only the exact intermittent automatic
  connection-preflight report as known while retaining hard zero-I/O,
  zero-sleep, idle-reconnect, and suspended-pump assertions. The live-refresh
  regression now creates a genuine server-accepted active prepared row through
  an exact claim/ACK before rewriting its body, so automatic delivery cannot
  quarantine it ahead of refresh; it additionally requires zero transact sends
  before refresh and no quarantine afterward. Frontend parse and scoped
  `git diff --check` pass; no SwiftPM/build, stage, or commit ran. Exact filters:
  `runtimeTransactWhileSynchronizationBlockedPersistsReceiptAndRemainsUnsentAcrossRelaunch`
  and
  `preparedActiveReceiptBodyMismatchBlocksLiveRefreshAtomicallyWithoutReconnect`.
  File hash:
  `6fae441e4dd7e56426cd45a29f43eebaac79b3ebd281ac6f505dcd3473d69145`.

- 2026-08-15T10:40:57-0400 DELEGATED CLAIM — atomic quarantine blocker
  claim stop: `blocker_index_test`, delegated by `root`, shares
  `BoundedOutboxDelivery.swift`, `SQLitePersistenceStore.swift`, and
  `InstantBoundedOutboxDeliveryTests.swift` for the accepted release blocker.
  It owns only the claim result seam that commits a newly created active
  nil-receipt quarantine, restores every claim newly acquired under the current
  request token, returns no transport rows, and throws the canonical structured
  blocker after commit, plus the focused corrupt/oversized/step contracts and
  stale recovery text. Existing foreign/older claims remain untouched. No
  SwiftPM/build, stage, commit, ledger, install, or device lane is claimed;
  frontend parse and scoped diff checks only.

- 2026-08-15T10:48:16-0400 ROOT CLAIM — downgrade-safe no-effect receipt
  encoding: root reclaims `Sources/InstantSwiftDataCore/InstantModels.swift`
  from the errored/stable semantic worker and claims a new focused Codable
  compatibility test only. The new known-no-materialized-effect proof will be
  represented by an additive optional receipt version while retaining the
  historical serialized overlay state `applied`, so v1.5.6 decoders ignore the
  new key instead of failing on a new enum raw value. SQLite's external receipt
  fingerprint remains the sole Runtime authority. Runtime and SQLite call-site
  edits will wait for the two active delegated P1 slices to report FILES STABLE.
  No SwiftPM/build, stage, commit, ledger, install, or device lane is claimed.

- 2026-08-15T10:51:48-0400 ROOT RECLAIM — after
  `blocker_index_test` reported FILES STABLE, root reclaims
  `SQLitePersistenceStore.swift` and `InstantBoundedOutboxDeliveryTests.swift`
  only for the downgrade-safe receipt-version integration described above.
  The stable atomic quarantine/claim-release implementation and tests are
  preserved unchanged. `BoundedOutboxDelivery.swift` remains stable/read-only.

- 2026-08-15T10:52:35-0400 ROOT RECLAIM — after
  `legacy_head_contract_tests` reported FILES STABLE, root reclaims
  `InstantRuntime.swift`, `InstantStoreTests.swift`, and
  `InstantLiveTransportTests.swift` for the downgrade-safe receipt-version
  integration and combined focused validation. The stable close-arbitration and
  same-ID receipt-validation fixes/tests are preserved unchanged.

- 2026-08-15T10:45:30-0400 DELEGATED CLAIM — Runtime P1 release blockers:
  `legacy_head_contract_tests`, delegated by `root`, owns only manual blocker
  persistence ordering/cancellation and same-ID pending replay receipt
  validation in `InstantRuntime.swift`, plus focused regressions in
  `InstantStoreTests.swift` and `InstantLiveTransportTests.swift`. Manual
  blocker persistence must enter the connection gate before the operation gate,
  preserve explicit `.closed`, and suspend delivery without letting a canceled
  pump overwrite close. An idempotent same-ID replay must revision-validate the
  exact SQLite-owned Runtime receipt before returning success; an unknown
  receipt throws the canonical blocker without materialization or claim. The
  downgrade/P2 receipt representation, SQLite, bounded delivery, other tests,
  SwiftPM/build, stage, commit, ledger, install, and device lanes remain out of
  scope; frontend parse and scoped diff checks only.

- 2026-08-15T10:52:03-0400 FILES STABLE — Runtime P1 release blockers:
  same-ID pending `transact` replay now validates the exact caller-visible body
  against SQLite's Runtime-owned preparation receipt under the loaded outbox
  revision before returning idempotent success. A public body without that
  receipt throws the canonical retained-unknown blocker and changes no store,
  revision, durable body, or delivery claim. Manual blocker persistence now
  acquires the cancellation-aware connection gate before the operation gate,
  rechecks durable `.closed`, publishes only while it still owns connection
  state, releases both gates on every path, and suspends delivery afterward. A
  noncooperative checkpoint regression proves explicit close persists and
  returns `.closed` with no stale error, reconnect sleep, or mutation send while
  the delayed blocker task is canceled and joined. Frontend parse of all three
  owned Swift files and scoped `git diff --check` pass; no SwiftPM/build, stage,
  or commit ran. Exact filters:
  `sameIDPendingTransactRejectsPublicBodyWithoutSQLitePreparationReceipt` and
  `manualSynchronizationBlockerCannotOverwriteExplicitClose`. Hashes: Runtime
  `a834c95366a0c70f7ee5eacf0f667ed716cbe14c37e69f15cb143c9efe5c01a7`,
  Store tests
  `1219be7d3b9f5eb39e4bc8b49608b647207bf4bb4f2164c4d6eed389749334f5`,
  LiveTransport tests
  `862d0cef0baa08a11d0dbdf12f9afc4bac3c8520a62c2158030f5fab856abbc6`.

- 2026-08-15T10:51:02-0400 FILES STABLE — atomic quarantine blocker claim
  stop: `blocker_index_test` completed the delegated
  `BoundedOutboxDelivery.swift`, `SQLitePersistenceStore.swift`, and
  `InstantBoundedOutboxDeliveryTests.swift` slice. A corrupt, oversized, or
  over-step active row now stops the candidate walk, atomically restores every
  claim acquired under this request token to its exact preclaim
  `delivery_started` value, commits quarantine/revision/raw evidence, returns no
  transport rows, and throws the canonical structured blocker after the
  transaction commits. A pre-existing same-runtime claim under another token
  is proven untouched; later rows remain unclaimed and undecoded. Recovery text
  now states that automatic synchronization, retry, and discard remain blocked
  until app-owned reset/rebuild. Frontend parse and scoped `git diff --check`
  pass; no SwiftPM/build, stage, commit, ledger, install, or device lane ran.
  Exact focused filters:
  `InstantBoundedOutboxDeliveryTests.corruptActiveOverlayInsideWindowCommitsBlockerAndReleasesOnlyNewClaims`,
  `InstantBoundedOutboxDeliveryTests.overLimitStepHeadCommitsBlockerWithoutClaimingTail`,
  `InstantBoundedOutboxDeliveryTests.oversizedHeadCommitsBlockerWithoutDecodingOrClaimingTail`,
  `InstantBoundedOutboxDeliveryTests.corruptHeadWindowStopsAtFirstBlockerWithoutDecodingTail`,
  and
  `InstantBoundedOutboxDeliveryTests.malformedLifecycleWithOversizedFailedBodyBlocksConnectAndRetainsTail`.
  Current file hashes respectively:
  `1cb8e7b20e54901ee40c5030c82ae47c06836b6b39397931025122725a44c35d`,
  `2f0deb74f9fde62e2a6b24aa1f7f9ba615f81809a0c2ef8003473a73f0fa1391`,
  `2225761b39bf2a1d8bd02774adf6695deef5306c431fad1611decdd05a1837c2`.

- 2026-08-15T11:06:11-0400 plan-to-touch — root owns only the stale synthetic
  pre-0012 fixture normalization in
  `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift`.
  The broad serialized run showed that the helper strips the SQLite receipt
  columns but leaves the new additive receipt-version JSON field, a shape that
  no pre-0012 database could contain. Root will remove that field while
  reconstructing the legacy table, rerun the exact failing contract, then
  resume broad validation. No production ownership expansion.

- 2026-08-15T11:08:05-0400 FILES STABLE — root's synthetic pre-0012 fixture
  correction is complete. Table reconstruction now removes the additive
  `optimisticEffectReceiptVersion` JSON field along with the SQLite authority
  columns, matching a body shape that could actually predate receipt authority.
  `legacyConfirmedUnprovenRowsRemainOrderedAheadOfPendingTail` is green;
  frontend parse and scoped diff-check pass. No production edit. Current test
  file SHA-256:
  `db364852c6169626935c7cdf1db1a64244de7e5b98f9288f96192803043a7509`.

- 2026-08-15T11:21:49-0400 plan-to-touch — root owns the narrow
  Runtime-owned local-snapshot migration boundary in
  `Sources/InstantSwiftDataCore/InstantRuntime.swift` and the matching forward
  plus rollback priority conversion in
  `Sources/InstantSwiftDataCore/ReminderExample.swift`. The broad CLI
  regression proves a deployed-shape pending optimistic row: public snapshot
  persistence correctly refuses to rewrite its store/body. Root will validate
  every current outbox body against the exact SQLite receipt/revision before a
  changed migration, commit through the Runtime-prepared CAS, and migrate the
  inverse alongside the forward transaction. No public-guard weakening.

- 2026-08-15T11:31:41-0400 test expansion — root additionally owns one focused
  `InstantStoreTests.swift` unit contract proving the Reminders priority
  migration converts the materialized store, forward mutation, and inverse
  rollback together while preserving transaction identities. This is disjoint
  from the now-stable attribute-cache fixture hunk; no helper or broader test
  ownership expansion.

- 2026-08-15T11:34:54-0400 plan-to-touch — root owns only the three stale
  unknown-failed contracts in
  `Tests/InstantSwiftDataCoreTests/InstantOutboxDeliveryStallTests.swift`.
  They predate the now-explicit SQLite receipt authority and still require
  unrelated delivery/server apply to continue. Root will retain their field
  fixtures but assert the canonical manual-recovery blocker, zero wire/server
  progress, durable row/store preservation, suspended delivery, and idle
  reconnect. No production change.

- 2026-08-15T11:11:09-0400 DELEGATED CLAIM — strict retry-window receipt
  fixtures: `blocker_index_test`, delegated by `root`, owns only
  `InstantFailedMutationRetryWindowTests.swift`. It will repair broad-suite
  fixtures that model Runtime-prepared rows so they carry same-store SQLite
  authority and coherent material receipts, while preserving the intentionally
  legacy unknown row as the first synchronization blocker. Production, other
  tests, build, stage, commit, ledger, install, and device lanes remain out of
  scope. Root currently owns the serialized SwiftPM lane, so this slice will
  run frontend parse and scoped diff checks only.

- 2026-08-15T11:11:09-0400 plan-to-touch — `blocker_index_test` will make
  the smallest fixture-only correction in
  `InstantFailedMutationRetryWindowTests.swift`: Runtime-prepared active rows
  receive the current receipt version before the same-store authorized save;
  the explicit `overlayState: nil` legacy row remains versionless and cannot
  acquire SQLite receipt authority. No production or other test path is in
  scope.

- 2026-08-15T11:12:09-0400 FILES STABLE — strict retry-window receipt
  fixtures: every applied-overlay retry fixture now carries the current receipt
  version alongside its coherent inverse rollback before the existing
  same-store Runtime-authorized SQLite save. The deliberately legacy unknown
  row still has a nil overlay and nil version, so it remains the first blocker
  and prevents decoding the earlier corrupt body or later candidates. Frontend
  parse and scoped `git diff --check` pass. Root owns the serialized SwiftPM
  lane, so no SwiftPM/build, stage, commit, ledger, install, or device command
  ran. Exact deferred filter:
  `swift test --jobs 1 --no-parallel --filter InstantFailedMutationRetryWindowTests`.
  Test file SHA-256:
  `3bdf124d2696d4614f516001cd538b57b7156225e7a8a307f9978e5f05688bc6`.

- 2026-08-15T11:21:34-0400 plan-to-touch — `legacy_head_contract_tests`,
  delegated by `root`, owns only three diagnosed test-only corrections:
  deterministic actor-hop counters in
  `Tests/InstantSwiftDataCoreTests/BenchmarkTests.swift`; the matching benchmark
  mirrors only in `Tests/InstantSwiftDataCoreTests/CLITests.swift` (the legacy
  Reminder priority migration test is explicitly excluded); and the one
  attribute-only cross-runtime writer call in
  `Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift`, switched to the
  existing Runtime-prepared package seam. Production sources, other test hunks,
  SwiftPM/build, stage, commit, ledger, install, and device lanes remain owned by
  root or their existing agents. This slice will run frontend parse and scoped
  diff checks, then return exact deferred filters and file hashes.

- 2026-08-15T11:23:05-0400 FILES STABLE — `legacy_head_contract_tests`
  completed the three delegated test-only corrections. The deterministic local
  benchmark now counts the indexed synchronization-blocker persistence boundary
  after each successful transact, plus the two current live-session reservation
  release boundaries across the bounded flush passes; the CLI benchmark mirrors
  match those counters. The attribute-only cross-runtime cache fixture now uses
  the existing `saveRuntimePreparedStoreSnapshot` package seam and still tests
  attribute-revision cache invalidation. The legacy Reminder priority migration
  test and all production sources remain untouched. All three test files pass
  `xcrun swiftc -frontend -parse`; scoped `git diff --check` passes. Root owns
  SwiftPM, so no build/test, stage, commit, ledger, install, or device command
  ran. Exact deferred filters:
  `InstantStoreTests.localTodoBenchmarkProducesDeterministicMetrics`,
  `InstantStoreTests.cliBenchmarkLocalTodosEmitsJSONAndEvidence`, and
  `InstantStoreTests.closedQueryDoesNotReturnStaleCacheAfterAttributeOnlyCrossRuntimeChange`.
  SHA-256 hashes: `BenchmarkTests.swift`
  `dd4a239ed524e8e0b003e7662ecd3659953d615a6ad98a3e788b0e047657d6da`;
  `CLITests.swift`
  `869a1169f5ad600b5f89b446cd93b68f6736da3306dc628da8bea4b6244817e5`;
  `InstantStoreTests.swift`
  `f36976f44394605caae63f9b62852df8ca423c758af3a05373211a97e735bb45`.

- 2026-08-15T11:58:43-0400 plan-to-touch — `migration_architecture_fix`,
  delegated by `root`, owns only the application migration descriptor and
  pre-runtime bootstrap seam in `InstantRuntime.swift`; the atomic durable
  migration and offered-wire guard in `SQLitePersistenceStore.swift`; the
  Reminder priority descriptor; CLI registration/removal of the post-bootstrap
  migration; and focused priority migration regressions in `CLITests.swift`,
  `InstantStoreTests.swift`, and `InstantBoundedOutboxDeliveryTests.swift`.
  Existing dirty edits and stable hunks are preserved. No SwiftPM/build, stage,
  commit, ledger, install, or device lane is claimed; frontend parse, scoped
  diff checks, and file hashes only before returning stable files to root.

- 2026-08-15T12:00:27-0400 root checkpoint — the previously hanging
  `byteStreamContentObservationsBufferEveryUpdate` regression was stale against
  the bounded `bufferingNewest(1)` stream contract. Root renamed it to
  `byteStreamContentObservationsCoalesceQueuedCumulativeUpdates`, consumes the
  first append before intentionally queuing the second append plus close, and
  requires the latest cumulative terminal snapshot (`AB`, done, size 2). The
  exact renamed test passes in isolation; frontend parse and scoped diff check
  pass.

- 2026-08-15T12:00:27-0400 root checkpoint — SQLite now treats
  `delivery_started` as irreversible proof that a mutation ID's forward wire
  intent escaped to delivery. Runtime-prepared changed-wire replacement throws
  `persist offered outbox mutation`; the old claim and JSON remain authoritative;
  same-wire stamp/rollback rebase remains permitted. Focused automatic and
  explicit-claim contracts were rewritten to pin these invariants. This hunk is
  under independent read-only review while the application migration worker
  owns the disjoint pre-runtime migration implementation.

- 2026-08-15T12:12:26-0400 plan-to-touch — `offered_server_apply_tests`,
  delegated by `root`, owns only two deterministic additions to
  `Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift`:
  an already-offered changed-wire server-apply rejection preserving durable
  store/outbox/plan authority/revisions, and a stale-plan race where a second
  SQLite actor claims then releases the row before staging/commit. Production
  sources and every existing test hunk remain untouched. No SwiftPM/build,
  stage, commit, ledger, install, or device command will run; frontend parse,
  scoped diff check, hashes, and exact deferred filters only.

- 2026-08-15T12:16:36-0400 FILES STABLE — `offered_server_apply_tests`
  added both delegated server-apply invariants. A plan created after an offer
  now proves changed lowered wire intent fails with
  `persist offered outbox mutation`; the failed staging transaction preserves
  the original plan body, durable store/outbox body, claim authority, row
  revision, and all four revision domains. A plan created while the row is
  unoffered now becomes stale when a second SQLite actor claims and releases
  it: stale paging is surfaced, retained changed-wire staging fails, commit
  returns no result, and a fresh third actor verifies no body/store/revision or
  metadata corruption while `delivery_started` remains irreversible. Existing
  test hunks and all production files remain untouched. Frontend parse and
  scoped `git diff --check` pass; no SwiftPM/build, stage, commit, ledger,
  install, or device command ran. Exact deferred filters:
  `InstantBoundedServerApplyRebaseTests.offeredRowRejectsChangedWireStagingWithoutChangingDurableAuthority`
  and
  `InstantBoundedServerApplyRebaseTests.claimAndReleaseMakesAnUnofferedServerApplyPlanStale`.
  Test file SHA-256:
  `37452c693a0b1b08592b7f80498c8f5ca8027e33d6794bd2c63b34415421bb98`.

- 2026-08-15T12:21:14-0400 FILES STABLE — `migration_architecture_fix`
  implemented the application value-migration descriptor, storage-owned
  `BEGIN IMMEDIATE` ledgered executor, Reminder legacy-priority descriptor,
  pre-runtime CLI registration, immutable offered/accepted wire enforcement,
  and focused migration/authority tests. The executor keyset-scans only declared
  attribute IDs; bounds original and transformed canonical, live-result, and
  outbox rows; fails closed on collisions, unknown values, unknown optimistic
  owners, receipt/scalar incoherence, offered/accepted rows, and identity or
  lifecycle changes; rebuilds receipt/effect/write-key/live ownership metadata;
  invalidates query caches; and advances all relevant revisions atomically.
  The already-stable server-apply test file was preserved. Frontend parse and
  scoped `git diff --check` pass. No SwiftPM/build, stage, commit, ledger,
  install, or device command ran. Exact deferred test filters:
  `InstantStoreTests.reminderPriorityMigrationRewritesStoreForwardIntentAndRollbackTogether`,
  `InstantStoreTests.reminderPriorityDurableMigrationCoversNonresidentAndLiveQueryRowsAtomically`,
  `InstantStoreTests.liveResultOnlyPriorityMigrationInvalidatesCrossActorMaterializationCache`,
  `InstantStoreTests.reminderPriorityDurableMigrationRejectsOfferedAndAcceptedRowsWithoutPartialWrites`,
  `InstantStoreTests.reminderPriorityDurableMigrationRejectsUnchangedUnknownOptimisticOwner`,
  `InstantStoreTests.reminderPriorityDurableMigrationRejectsUnknownLegacyRankAtomically`,
  `InstantBoundedOutboxDeliveryTests.offeredMutationRejectsRuntimePreparedChangedWireAndPreservesOriginalClaim`,
  `InstantBoundedOutboxDeliveryTests.explicitConfirmationRejectsChangedWireAndPreservesSameWireRebase`,
  and `CLITests.cliRemindersMigratesLegacyStringPriorityRanks`.
  SHA-256 hashes: `InstantRuntime.swift`
  `f51dc9d67014affd1a0570d365f9ad48376bb69f3766ab157ed4b728911c06e9`;
  `SQLitePersistenceStore.swift`
  `95ac87454fe50a61d3b4ef2b56e09793fa142d1c075a090d34a05cfb678d49bc`;
  `ReminderExample.swift`
  `d2ef04d79ecddc821b90600569133c78978d694d5e4a4c859f7a3a208c997641`;
  `main.swift`
  `65e72ca9b9e1885c9068c573ad70b583107ebd92a1ab97e71745a4c632ed6bea`;
  `InstantStoreTests.swift`
  `0909d8a91b8a3a2b14dc6b8ea3aa01444571b47b7c789207d8486d0d487d694e`;
  `InstantBoundedOutboxDeliveryTests.swift`
  `67477747336c5746c6011047c01df1e87bebcb5a1e8c7553e3d25a2594a32b45`;
  `CLITests.swift`
  `869a1169f5ad600b5f89b446cd93b68f6736da3306dc628da8bea4b6244817e5`.

- 2026-08-15T12:49:22-0400 FILES STABLE — `migration_architecture_fix`
  corrected only three migration-test compact-residency expectations while
  preserving root's inserted resident, full-state, and delete-entity fixture
  corrections. The live-result-only fixture now expects entity-scoped residency
  to retain the canonical row even when the persisted ownership value is legacy;
  the two atomic-failure fixtures compare all four revision domains separately
  while raw attributes/triples/outbox continue to prove exact rollback. Frontend
  parse and scoped `git diff --check` pass; no SwiftPM/build ran. Exact filters:
  `InstantStoreTests.liveResultOnlyPriorityMigrationInvalidatesCrossActorMaterializationCache`,
  `InstantStoreTests.reminderPriorityDurableMigrationRejectsUnchangedUnknownOptimisticOwner`,
  and `InstantStoreTests.reminderPriorityDurableMigrationRejectsUnknownLegacyRankAtomically`.
  `InstantStoreTests.swift` SHA-256:
  `d264aeb70595810f53f50bca5f1e57cd762afbd2e91efe1997885d804ca7e74b`.

- 2026-08-15T12:23:30-0400 root plan-to-touch — rename the superseded
  residency-thinned package snapshot rewrite to the explicit test-fixture seam
  `rewriteResidentPersistenceSnapshotForTesting` and update its six existing
  FailedDiscard, OutboxStall, and OutboxHydration test call sites. This keeps the
  new storage-owned application migration as the only production-sounding
  durable migration path. Root owns frontend parse, scoped diff check, and the
  serialized SwiftPM lane; no agent overlaps these exact seams.

- 2026-08-15T12:26:30-0400 root build checkpoint — the first SwiftPM build
  compiled production and exposed only test-macro isolation errors that frontend
  parsing cannot detect. Root hoisted four throwing raw-SQL helper results before
  `#require` and one awaited actor read before `expectNoDifference`; both files
  now pass frontend parse and the full worktree passes `git diff --check`.

- 2026-08-15T13:31:42-0400 plan-to-touch — root delegates
  `file_upload_cancel_triage` only the upload-progress section of
  `InstantRuntime.swift` and
  `fileUploadProgressCancellationBeforeSaveDoesNotPersistFile` in
  `InstantStoreTests.swift`. The mower slice restores public stream-termination
  cancellation through the existing exact managed lease and replaces the old
  fixed-delay choreography with deterministic explicit cancel/join evidence.
  Existing dirty hunks remain untouched; frontend parse and scoped diff checks
  only, with no SwiftPM/build, stage, commit, ledger, install, or device command.

- 2026-08-15T13:35:19-0400 FILES STABLE — `file_upload_cancel_triage`
  restored the public upload-progress termination edge lost in `8b7c384e`.
  The producer now captures only the continuation, while stream cancellation
  synchronously requests the existing managed lease cancellation; that lease
  cancels and exactly joins the producer. The focused Store regression replaces
  its obsolete 50-millisecond race window with a package-only loading checkpoint
  whose lock-backed continuation records actual producer cancellation before
  asserting that no file persisted. This is a production cancellation regression
  plus stale test choreography, not a license to weaken the no-persist contract.
  Both Swift files pass `xcrun swiftc -frontend -parse`; the five owned source,
  test, touch, and channel paths pass scoped `git diff --check`. No SwiftPM/build,
  test, stage, commit, ledger, install, or device command ran. Exact deferred
  filter:
  `InstantStoreTests.fileUploadProgressCancellationBeforeSaveDoesNotPersistFile`.
  SHA-256: `InstantRuntime.swift`
  `3877415ad7207437882c93a5d0306db02ce8023c195b91b5f2444a32bcad29c0`;
  `InstantStoreTests.swift`
  `8ea0ff77f6a8d964a50945a75660d659b188df5fb69a6ac40317899fcb79ca4d`.

- 2026-08-15T13:39:24-0400 FILES STABLE — post-build upload-progress
  cancellation correction: the prior deterministic checkpoint still let the
  consumer task finish normally after one buffered value, which did not create
  the public stream-cancellation event under test. The focused regression now
  keeps that consumer alive on its second `next()`, explicitly cancels and joins
  it, then waits for cancellation to reach the producer's pre-save checkpoint
  before asserting empty storage. The Runtime termination-to-managed-lease edge
  is unchanged. Both owned Swift files pass frontend parse and all five scoped
  source/test/touch/channel paths pass `git diff --check`; no SwiftPM/build/test,
  stage, commit, ledger, install, or device command ran. Exact deferred filter:
  `InstantStoreTests.fileUploadProgressCancellationBeforeSaveDoesNotPersistFile`.
  SHA-256: `InstantRuntime.swift`
  `3877415ad7207437882c93a5d0306db02ce8023c195b91b5f2444a32bcad29c0`;
  `InstantStoreTests.swift`
  `c14a7fb08d1577550f1898ccc6da4cb0b5dab5f9fe264929c424c2db28151b60`.

- 2026-08-15T13:55:03-0400 root final package gate — a current-source rebuild
  passes the exact upload-cancellation, injected-local-live-transport, and
  unchecked-Sendable documentation regressions 3/3. The widened
  `BootstrapTests|InstantLiveTransportTests|InstantStoreTests/fileUpload` run
  passes 196/196 with two deliberate known issues. The final package-wide
  serialized run passes 1,729 tests across 146 suites in 578.263 seconds with
  exactly 27 deliberate known issues and no unexpected failures; full output is
  `/tmp/instant-data-swift-full-final-20260815.log`. All 33 changed Swift files
  pass `swiftc -frontend -parse`, and the complete 55-file worktree passes
  `git diff --check`. Root owns staging, implementation/ledger commits, and the
  clean physical Scribe handoff.

- 2026-08-15T14:14:51-0400 root portability release gate — the independent
  staged-boundary audit found that receipt SHA-256 authority imported Apple-only
  `CryptoKit` directly despite the repository's Linux-clean source contract.
  Root added the official `swift-crypto` 4.x `Crypto` product only to
  `InstantSwiftDataCore`, preserving the exact `v1:` and `wire-v1:` digest
  formats, and pinned 4.5.1 plus its swift-asn1 1.7.1 dependency. The native
  package rebuilt successfully and all three pending-mutation compatibility
  tests pass, including the fixed SHA-256 `abc` vector. An isolated Swift 6.3.3
  Linux container compiled the full `Crypto` product, then reached the existing
  repository-wide `import SQLite3` Linux module-map limitation; no new crypto
  portability failure occurred. Package, resolution, digest source, test, touch,
  and channel paths are root-owned for the implementation commit.
