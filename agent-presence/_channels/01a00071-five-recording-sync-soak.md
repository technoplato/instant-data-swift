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
