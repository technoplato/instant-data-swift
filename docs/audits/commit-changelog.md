## 2026-08-08 10:28:18 EDT

- **repo:** instant-data-swift
- **sha:** ac99ea88ea56a1cbbf9ff8bfd2e1f72081f15a9d
- **branch:** exercise-gem/instant-throughput-correctness
- **reason:** Instant Exercise Gem — TS/Swift correctness + throughput matrix (#156); clientId/descriptor message analysis; Electron + Mac UI shells.


## 2026-08-07 00:46:54 EDT
- **repo:** realtime-voice-sqlite-instant
- **sha:** 45c0022409b580f0b78378a6687a597d2eddd193
- **reason:** #167 agent-addressable ScribePressPadSanity CLI (reduce/self-test/events) + Rec 018 mailbox; Core/Client already on main
## August 07, 2026 at 00:45:33 EDT

- **repository:** instant-data-swift
- **commit:** fdbef6d76506b286717ca0db42359b5be2b8e896
- **reason:** Link multi-agent coordination protocol in AGENTS; land proposed ADR 0014 (entity lifecycle/status on fetch, open-segment writes still outbox).

## August 07, 2026 at 00:45:33 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** faccdf133506bbcf50ab22d77be44007a3d5e819
- **reason:** Document agent-control BigInt command-ID hazard; mailbox SSH self-loop and iPad remote-control probes.

## 2026-08-07 00:44:17 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** c5e2b5f (Core), 38c754b (Client), b21a6b8 (wire), 2a37393 (plan merge)
- **reason:** #167 pure SPM press-pad core + Dependency client + sanity CLI (no Xcode host)

## 2026-08-07 00:08:32 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** `383c73b8e539e082fefb82c9a481118afb91c4c7`
- **reason:** Complete core agent axioms 1–8 (plan/touch/mower-grower + Instant issues + Genesis + no browser spam) at AGENTS.md top; presence operational-only.

## 2026-08-06 23:32:15 EDT — realtime-voice-sqlite-instant be56ed1de0535a37ca13710c4a705425897f542d

- **Repo:** realtime-voice-sqlite-instant
- **SHA:** be56ed1de0535a37ca13710c4a705425897f542d
- **Reason:** #163 minuscule attachment image titles (watched-folder Screen Shot names); docs for #164 feature mini-apps and #165 Mow/Grow.


## 2026-08-06 21:33:10 EDT

- **repo:** realtime-voice-sqlite-instant
- **sha:** 29f39f7025af24c8d44226d70d428c00d995c245
- **reason:** Ship recording activity badges + OpenSegment CLI sanity harness (#155)

## 2026-08-06 19:39:03 EDT

- **repo:** instant-data-swift
- **commit:** 549f740c9a8001ff1ccfd0e9ee15a9a850f304db
- **reason:** Expose Instant clientID() for activity ADT this vs other device (ADR 0015 Q23 / #155 P1)

## 2026-08-06 18:14:49 EDT

- **repo:** instant-data-swift
- **commit:** de1fa08e242f632dac05c4f3414698e4ba58c4e2
- **reason:** InstantFetchRequest(snapshotsOf:) for multi-bag aggregate list values (ADR 0015 / #155)

## August 6, 2026 at 4:52:26 PM EDT — instant-data-swift `421f735343f59cc9903affe38d3c3a7d2dff907c`

**Return from transact after local commit, not wire send**

Optimistic `transact` no longer awaits websocket outbox delivery (counter lag root cause). Delete-all restored to offline-capable fire-and-forget `send`. #151.

## August 6, 2026 at 4:31:26 PM EDT — instant-data-swift `289c148fbddccff3b85fbfe6e7424e4caf3b5d03`

**Harden todos delete-all to await server acceptance**

Todos delete-all awaits Instant server acceptance within 5s and fails loud. Live tests cover single-client accept and two-client peer propagation for #151.

## August 6, 2026 at 4:12:59 PM EDT — instant-data-swift `b97ad44752e37615c5d1b8efdc71626fe06523ee`

**Allow swipe-down keyboard dismiss on todos composer**

Todos composer keeps focus after send, but swipe/scroll down can dismiss the keyboard without server callbacks reclaiming focus. Interactive scrollDismissesKeyboard on the list.

## 2026-08-06 15:49:19 EDT

- **Repository:** instant-data-swift
- **Commit:** `22a973c204926c7133f91b02aff6d23456f79c7b`
- **High-level reason:** Add Scribe open-segment 20s network write/observe benchmark CLI (#156) — Net-A admin→Swift, Net-B Swift→admin, wordsJSON on open segment, observer-validated seq + process memory/CPU.

## 2026-08-05 23:35:07 EDT

## 2026-08-06 13:55:22 EDT

- **Repository:** instant-data-swift
- **Commit:** `c3fadbac66a743d4d1fec598e3c5ef8b91cfbfd5`
- **High-level reason:** Fix iOS Instant Recipes install (wipe path + iOS 17 availability)

## 2026-08-06 13:55:22 EDT

- **Repository:** instant-data-swift
- **Commit:** `24520678695b530f1dc2ca5462094e93228830be`
- **High-level reason:** Auth recipe page public + account counters reacting to login/logout (#152)


## 2026-08-06 13:49:55 EDT

- **Repository:** instant-data-swift
- **Commit:** `24520678695b530f1dc2ca5462094e93228830be`
- **High-level reason:** Put public + account counters on Auth recipe page so they react to login/logout (#152)


- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `44cd5f9ff0005907f53eb748d94b26dd46c71bd2`
- **Reason:** Memory soak dependency fixtures + debounced timeline saves for long-recording footprint (#044).

## 2026-08-05 22:20:42 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `6390d50ba2899ad65008c9652f854bbbdc15f5ea`
- **Reason:** Denser greppable process metrics (5s, CPU peak, thermal) and discrete TCA dual-write over diagnostics WebSocket for #044 long-recording thrash diagnosis.

# Commit changelog

## 2026-08-05 20:19:02 EDT

- **instant-data-swift** tag `v1.5.6` @ `29495b966108b5a90de0ab09a61a8a93f8ed87ed` — Production Scribe namespace soak + dual Instant thrash + demotion guest auth (#150).
- **realtime-voice-sqlite-instant** `39ebb186136d` — Pin Package.swift exact 1.5.6.
- **realtime-voice-sqlite-instant** `204e6582af9efb66410c6e39703de6b25c37e5f2` — Instant-lane library chatter filter.


## 2026-08-05 20:03:36 EDT

- **instant-data-swift** `60df101efae42243b139eb4d5b2260934e1b1a99` — Production Scribe namespaces + dual Instant debugLogs thrash soak (#150).
- **realtime-voice-sqlite-instant** `204e6582af9efb66410c6e39703de6b25c37e5f2` — Instant-lane filter for library chatter re-entering debugLogs thrash (#150).

## 2026-08-05 13:12:29 EDT

## 2026-08-05 17:37:25 EDT — realtime-voice-sqlite-instant dual-write feedback fix

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `a3d415fdd4500c3b6edb1232d74eaa1473bc36ef`
- **Reason:** App-side bridge filter + smaller debug log batches to stop Instant dual-write memory thrash on idle iPad.


## 2026-08-05 17:37:14 EDT — instant-data-swift diagnostic dual-write thrash fix

- **Repository:** instant-data-swift
- **Commit:** `759c899a8a4f76ccaa2d473e5f15c33fe86946fc`
- **Reason:** Break InstantDiagnostics dual-write feedback that drove multi-GB idle memory via continuous debug-log-batch mutations.


## 2026-08-05 13:31:35 EDT — realtime-voice-sqlite-instant performance plan pointer

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `af82b476348d2ece9d976b9740dd99f9986eb4ba`
- **Reason:** Point Scribe agents at Instant production performance readiness plan after iPad 880MB+ thrash evidence.

## 2026-08-05 13:31:18 EDT — realtime-voice-sqlite-instant plan handoff (instant-data-swift)

- **Repository:** instant-data-swift
- **Commit:** `c5f9a0cef24161e92b0f51bc252faf50cb87fccc`
- **Reason:** Document production performance readiness plan from research quorum and live iPad thrash evidence (880MB+ idle, gate holds, receive-loop isolation gaps).

- **Repository:** instant-data-swift
- **Commit:** `8fbfa0c8ef1d95457929a9b4462c65f85923c9f2`
- **Reason:** Recipes outbox panel, wipe/clear, delete todos, sharing counters (#152)

## 2026-08-05 12:58:28 EDT

- **Repository:** instant-data-swift
- **Commit:** `551bb333839dcd050fb7ad4acf312124ee87d046`
- **Reason:** Scribe-shaped linked-infinite memory soak publish gate (#150)

## 2026-08-05 12:48:03 EDT

- **Repository:** instant-data-swift
- **Commit:** `ca483b549791175854c0f21faf25eae72a016cc2`
- **Reason:** Isolate failed legacy unknown-overlay mutations so live server apply continues (fixes receive-loop thrash on poison outbox rows; #134)

## 2026-08-05 12:41:23 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** 4320fc235fa953d5c7116f91541ce6d8fc92e22a
- **Reason:** Require mid-work Instant workLog progress so future agents can resume from query-issue.

- **Repository:** skills
- **Commit:** 39496e6099b66461242534302e926690c94f208a
- **Reason:** issue-tracker mandatory progress workLog section for future-agent handoff.

## 2026-08-05 12:29:20 EDT

- **repo:** instant-data-swift
- **commit:** `1a7303ac92ff0d689b34a4c12e541b86337edd29`
- **reason:** Recipes-v3 floating debug panel (memory/logs) after idle 5GB linked-infinite process; relaunch front and center.

## 2026-08-05 12:27:16 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** d77d69ed48930836bac97ef1786cbda90db67cc8
- **Reason:** Expand Instant issue-triage policy to feature requests, ideas, and capability gaps.

- **Repository:** skills
- **Commit:** 77b39de584456e7e47bd09d7ef44b2d87e218c83
- **Reason:** issue-triage skill covers features/ideas; claim only when executing.


## 2026-08-05 12:27:03 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `35afbcc9f144180f16bb889e584c56f950b47eba`
- **Reason:** Remove 640pt readable-column cap so recording transcript uses full width on iPad/Mac.
## 2026-08-05 12:24:10 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** c9fe3386fbcf961f93cb73a6f258234883704f89
- **Reason:** Require Instant issue triage on user-reported defects; Instant-only tracker, never GitHub Issues.

- **Repository:** skills
- **Commit:** da08e4ed703c4e1e4a69ad5c9a93cecd9d1cab7c
- **Reason:** Add issue-triage skill (search Instant catalog, claim or create, hand mutations to issue-tracker).

## 2026-08-05 12:10:52 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** ee7da38254ec72db838c954794c93a1993273b78
- **Reason:** Build debug overlay process-memory series (5s samples) + sparkline graph.

## 2026-08-05 09:51:26 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** `16b7e9e82146305d03f68065334c9b30aeda67e1`
- **reason:** Add Scribe Diagnostics suite with audio route probe and Device Hub silent-mic warning

## 2026-08-05 09:36:23 EDT

- **repo:** instant-data-swift
- **commit:** `adeea919009c` (tag v1.5.2 / `7dc2fe28`)
- **reason:** Instrument live infinite-query page-info and auth for host dual-write diagnostics.

- **repo:** realtime-voice-sqlite-instant
- **commit:** `5f0c98429013e198ecc31df62eac22ec649fe59b`
- **reason:** Bridge InstantDiagnostics to Tailnet dual-write logger; pin 1.5.2; list owner fingerprints.

## 2026-08-05 09:44:30 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `68f1a8faa44f14cfee7452f028b61327c808c43a`
- **Reason:** Multi-lane deep links/OAuth/companion pairing + localDev agent evidence defaults from bundle-id audit.

## 2026-08-05 09:09:23 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** d8ae5cd489883d22200b8eaa58e9297253b6e972
- **Reason:** Floating build debug overlay with Shared file-backed presentation modes (hidden/collapsed/expanded), opacity, and build provenance copy panel.

## 2026-08-05 09:22:15 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `bb22fd3507dc4dc48c68536febd2989aba3e5060`
- **Reason:** Typed ScribeBuildCatalog multi-lane identity + \$scribe-install skill (localDev default; TestFlight upload-only for production host).

## 2026-08-05 08:51:00 EDT

- **repo:** instant-data-swift
- **commit:** `cdd1ba421f27269b4307ff6056e2bd908096e926` (tag v1.5.1 / `43e3385c2e0aa2318aafcd63c0171192ce8e55ef`)
- **reason:** Fix live infinite short-page canLoadNextPage thrash that Jetsam-killed Scribe on iPad during recording.

- **repo:** realtime-voice-sqlite-instant
- **commit:** `39722d4e9a2bd75e79d5da9477b692b61659b2a0`
- **reason:** Pin instant-data-swift 1.5.1 and stop list/constellation loadNextPage thrash that OOM-killed iPad recordings.

## 2026-08-05 08:32:30 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** 
- **reason:** Land TestFlight App Store validation fixes, versioning docs, and app/vakyume/0.1+3 tag metadata for the first VALID Vakyume upload (build 3).

## 2026-08-05 00:19:30 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `51eb3a58ecf08047c55baeb31b7ef3702da55322`
- **Reason:** Make Stream Companion Settings agent-controllable without QR

## 2026-08-04 23:27:17 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** `b63973acac674e1fd9a51c2f3629c57af3d8f073`
- **reason:** Stamp and show auto-detected device icons on recordings (list UI, settings auto-detect, device-local preference).


## 2026-08-04 22:42:05 EDT

- **repository:** instant-data-swift
- **commit/tag:** v1.5.0 (0a91a121) / a3b63e73
- **reason:** Empty live-query replacements preserve pending optimistic children; Linked Infinite blank-detail recipe + tests; ADR 0013.

- **repository:** realtime-voice-sqlite-instant
- **commit:** c3423e09e31460c85072962dbc196c04a644b310
- **reason:** Pin instant-data-swift exact 1.5.0 for blank-detail library fix.
## 2026-08-04 22:38:35 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** 9e21a429821bf10b5d3bfd7dfd2d94d0b3317861
- **reason:** Stream Companion Instant owner perms + TS auth daemon skeleton


## 2026-08-04 22:30:42 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** 5f1cdfa7380fa9efd67745cfb5dfc9dd89ede1ed
- **reason:** Preserve playback timeline when Instant detail join is empty; full transcription upserts and empty-detail diagnostics.

- **repository:** instant-data-swift
- **commit:** a3b63e73af0f32921506132a5c40e71621064962
- **reason:** Do not retract pending-optimistic entity triples on empty live-query replacements (Scribe blank-detail).
## 2026-08-04 22:11:33 EDT

- **repo:** realtime-voice-sqlite-instant
- **commit:** ff7835d2642875a9b83ad1ed6b8f8781efa1606d
- **reason:** Tuple-inspired Stream Companion: scribe-stream-agent connect (Grok/Claude/Codex) + design/prompt docs
## 2026-08-04 17:31:40 EDT

- **repo**: realtime-voice-sqlite-instant
- **commit**: `2aa994a60468841c73640ce9b8651e3444f6fd1e`
- **reason**: Stream Interactor multi-message segment replies, AgentThread navigation, fenceposts

## 2026-08-04 17:31:25 EDT

- **repo**: realtime-voice-sqlite-instant
- **commit**: `144d0f6d875effa5ac320a145ed1ffa3381cafb8`
- **reason**: Stream Interactor multi-message segment replies, AgentThread navigation, fenceposts

## 2026-08-04 17:12:23 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `0156b980d46f9912f6ad38acf666269f25bb1691`
- **Reason:** Rename the Mac app to Scribe and embed the real AppIcon so Spotlight no longer shows a generic "Scribe Shared" Application tile.

## 2026-08-04 16:15:34 EDT

- **repository:** realtime-voice-sqlite-instant
- **commit:** 1f1c3637a7eca44cc918f2406bbac4a217beada6
- **reason:** Join-shaped recording list: single infinite + transcription include; dual-write graph ref

## 2026-08-04 16:15:34 EDT

- **repository:** instant-data-swift
- **commit:** d862dc083d8d0614bff0dd126557687fd8ac3a4b
- **reason:** Linked infinite paging recipe with includes, InfiniteQueryPhase/pageSize, CLI seed/list/page, README

## 2026-08-04 15:59:36 EDT

- **Repository:** instant-data-swift
- **Commit:** 43015b16fec14a49157915fb88c51a323a813618
- **Reason:** Detailed handoff for typed Instant permissions result builder + custom bindings.

## 2026-08-04 15:55:21 EDT

- **Repository:** instant-data-swift
- **Commit:** 0ac518d51c716dc05c94fc46e14d2177bc8ce411
- **Reason:** ADR 0012 — typed Swift Instant permissions as source of truth (ADT + TS parse/print).

## 2026-08-04 15:44:40 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** 1112c4f045934212bf5a1d3a1ff393bada86dfb8
- **Reason:** Add private Instant segment-range shares for partial transcript access.

## 2026-08-04 15:32:18 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** be0d24be3d4f07b54405f49844a692dec0a8cdda
- **Reason:** Restrict recording/transcription Instant access to owner, linked guest, and share members (schema, perms, write-path ownership, reader/writer share helpers).

# Cross-Repository Commit Changelog

Newest entries go at the top. Timestamps include seconds and use Eastern Time
(`America/New_York`). Each substantive commit records the repository, full
commit SHA, and high-level reason. Changelog-only bookkeeping commits are
visible in Git history but are not self-recorded because a commit cannot
contain its own final SHA.

## 2026-08-04 14:50:12 EDT

- **Repository:** realtime-voice-sqlite-instant
- **Commit:** `8d192863b280887cd6bbe69ed7cfe364d91626e1`
- **Reason:** Wire installed Mac `ScribeSharedApp` Settings to `ScribeMacSettingsView` so Manage account / Instant sign-in is available on Mac (Option A; uses `apple-mac` provider config).

## August 4, 2026 at 12:55:02 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f1f74bb6915c`
- Reason: Pin published `instant-data-swift` **1.4.0** (API-convergence inventories)
  in Package.swift, Package.resolved, and installer required dependencies.

## August 4, 2026 at 12:53:10 PM EDT

- Repository: `instant-data-swift`
- Commit: `c8c8011f5846a66fa29da4f1ca809b62dc418c09`
- Reason: Full suite green for 1.4.0 (1351 tests / 115 suites, known issues
  only). Parity-count pins, outbox-revision and mutationCount expectations,
  reactor message counts, SAFETY comment, and `docs/releases/v1.4.0.md`.

## August 4, 2026 at 12:13:51 PM EDT

- Repository: `instant-data-swift`
- Commit: `3e625416e2db9376606bcecaff97043de4073c94`
- Reason: Same inventory/port procedure as Instant TypeScript, applied to
  Point-Free SQLiteData: 261 runtime tests enumerated at vendored `0c79d7a`
  (dual-method + subagent), gap analysis with CloudKit/SQL human boundaries,
  ergonomics ports for date roundtrip and assertQuery-style dumps, full parity
  registry coverage, and reconciliation tests that fail on drift.

## August 4, 2026 at 11:34:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `c4badb4bf6b0deb1d44e0fc98fd1f9a827c0f86e`
- Reason: Port upstream's only core benchmark (`instaql.bench.ts` `big query`)
  to Swift: correctness pin, package-benchmark `LocalRead.deepJoin.zeneca`,
  parity record, and reconciliation coverage for `*.bench.ts`. Measured
  release arm64 p50 23 ms vs TypeScript 4.707 ms (~4.9× slower) — the port is
  complete and the gap is now a performance task with numbers in
  `INSTANT_DATA_PERFORMANCE_BENCHMARKS.md`.

## August 4, 2026 at 11:28:18 AM EDT

- Repository: `instant-data-swift`
- Commit: `5d28f49070efbecc49fc32ab02a66b730af881f5`
- Reason: Finish the inventory re-baseline against the package's own vendored
  InstantDB checkout (`e7101761`, 19 files / 186 declarations / 225 runtime
  cases) and close the loop that made parity checkable. Fixed stale Swift test
  names and paraphrased `sourceTestName`s in `InstantParityCoverage`, and added
  `InstantUpstreamParityReconciliationTests` so renames, invented upstream
  names, missing records, and a moved vendored commit fail the suite. The only
  remaining open porting item from the gap analysis is the
  `instaql.bench.ts` deep-join benchmark.

## August 4, 2026 at 11:04:13 AM EDT

- Repository: `instant-data-swift`
- Commit: `a4c445ad97b4b8ca17ad1a0b56e284957cd6fba2`
- Reason: Make "we have parity with upstream" a measurement instead of an
  assertion. Added `docs/porting/upstream-typescript-test-inventory.md` (every
  one of the 175 declarations / 211 runtime cases in `@instantdb/core`, with
  file, line and greppable name, plus the single benchmark) and
  `docs/porting/swift-port-gap-analysis.md` (that inventory reconciled against
  `InstantParityCoverage.swift` and the 1338 Swift tests). Counts converged
  across three independent methods run twice consecutively. All 175 upstream
  declarations resolve to a parity record; date coercion and the `Where OR`
  table were verified case-by-case rather than by record count and are
  complete. Real gaps found: a stale Swift test name cited by four records,
  ~20 records storing paraphrases where upstream's literal test name belongs,
  and no Swift equivalent for upstream's `instaql.bench.ts` deep-join
  benchmark.

## August 4, 2026 at 10:19:57 AM EDT

- Repository: `instant-data-swift`
- Commit: `900050e68ee08714f09422182b14a3322b06ab2b`
- Tag: `v1.3.1` moved here — **still local, NOT pushed**
- Reason: Stop counting every triple on every prepare. Third instance of the
  same shape as `04f1b668`, and the one that dominated once the outbox resend
  loop was gone: `TripleIndexes.tripleCount` walked every entity × attribute ×
  value, and `InstantStore.prepare` reads it on every applied transaction and
  every terminal-failure removal. Sampled on a Mac holding ~400% CPU against an
  883,388-triple store, that single getter was 2,400 of 5,301 samples, reached
  through `failMutation → prepareTerminalFailureRemoval → prepare`. Now
  maintained by `insert` and `removeNormalized`, which already read the slot
  they are about to write, so the delta is exact for the cases that are easy to
  get wrong — identical re-insert, cardinality-one eviction, retracting an
  absent triple. `Codable` is now explicit so only eav/aev/vae are encoded and
  the count is recomputed on decode: adding a derived field to the wire format
  would have stopped persisted caches from decoding, which is precisely the
  migration failure behind `3ebc6704`. Measured on a copy of the real store,
  one transaction through `prepare`: 0.0744 s → 0.0119 s. **Relevant to the
  Scribe repository:** with all three fixes the Mac converged to 7–26% CPU
  after ~150 s and its outbox drained (pending 256 → 110) for the first time,
  where before it held 200–400% indefinitely against an unchanging store.

## August 4, 2026 at 9:59:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `3ebc6704973ce470a356457de8a4b5236d5641e8`
- Tag: `v1.3.1` — **created locally, NOT pushed**
- Reason: Stop re-sending mutations the server already accepted. This is the
  root cause of the Mac holding ~200% CPU indefinitely while its store stayed
  byte-for-byte unchanged: it was re-sending 7,125 already-accepted mutations
  in a loop. `confirmationSource` was added to `PendingMutation` after
  `serverTransactionID`, so every mutation accepted by an earlier build carries
  a server-assigned ID and a nil source; six call sites asked "has the server
  accepted this?" by consulting `confirmationSource` alone and answered "no"
  for all 6,887 such rows, permanently. A single
  `PendingMutation.provesServerAcceptance` predicate now also honours a non-nil
  `serverTransactionID`, which `Outbox.accepting` alone writes and only from a
  server `transact-ok` — so delivery finally agrees with `pruningConfirmed`,
  which already treated it as the authority. Measured on a copy of the real
  645 MB store: 7,125 → 256 mutations offered per server event, and 1.05 s →
  0.047 s to build one batch. The count is the bug; the time is why it never
  recovered, because a rebuild took longer than the gap between inbound events.
  **Relevant to the Scribe repository:** this is why the Mac "went quiet" and
  never claimed a screen-stream session — its Instant event loop never
  returned. Tracked as issue 146.

## August 4, 2026 at 9:59:35 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `bb2c26b437d5d1070af8cc2df6adffaf11b916aa`
- Reason: Consume `instant-data-swift` 1.3.1 so the outbox stops re-sending
  accepted work. **This commit does not build anywhere but the authoring
  machine until `git push origin v1.3.1` is run in the library repository** —
  the tag was created locally so the fix could be verified against a real
  device before publishing, and publishing was deliberately left to the
  repository owner. Push the tag or revert this commit before sharing the
  branch. A local SwiftPM mirror (`.swiftpm/configuration/mirrors.json`) points
  the dependency at the sibling checkout, because `swift package edit` silently
  fails to take effect here: the committed `Packages/instant-data-swift`
  symlink already occupies the directory SwiftPM manages for edited packages,
  so `show-dependencies` kept reporting the remote 1.3.0 and two full app
  builds were measured against the unfixed library before this was caught.

## August 4, 2026 at 7:07:52 AM EDT

- Repository: `instant-data-swift`
- Commit: `04f1b6682bf23c17103da501174d50e27fb38bd5`
- Reason: Stop the write path from scaling with the size of the schema. A Mac
  Scribe process sat at 99.5% CPU across three cooperative-pool threads for 136
  minutes, applying server transactions against the diagnostics store (343
  attributes, 883,388 triples, 7,928-deep outbox) and never returning to its
  event loop. `AttributeStore.namespaces` rebuilt a `Set` from the whole
  attribute table on every read while `validateWriteValue` reads it twice per
  triple, so each write was O(attributes); it is now maintained beside the other
  derived lookup indexes. `newestWriteTime` materialised an array per write key
  to take a maximum, and `visibleWriteFilter` asks for it once per key across the
  entire outbox on every inbound server event; it is now `lazy`. Measured at
  2,000 writes with attribute count varied: 800 attributes went 1.825 s → 0.025 s,
  and the growth from 100 → 800 attributes went 7.1× → flat. **Relevant to the
  Scribe repository:** the app looked disconnected — a screen-stream session
  stayed `requested` and was never claimed — when it was actually saturated, so
  "the Mac went quiet" was a CPU-starvation symptom, not a transport failure.
  Evidence is linked to issue 125, which owns the complementary half (why the
  diagnostics store grew that large). Still unfixed and named there:
  `sendOutstandingMutationsToLiveSession` rescans the entire outbox on every
  inbound server event, which remains O(outbox) per event.

## August 4, 2026 at 7:41:18 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `f991e9b8675203d1c9c60b1f0dae68ceb0c79d1e`
- Reason: Make the unlaunchable macOS build loud, and offer a reproducible way
  past it. The macOS app has been unlaunchable since 2026-08-02 (issue #141):
  it declares `com.apple.developer.applesignin`, macOS honours that restricted
  entitlement only when an embedded provisioning profile grants it, and the
  installer embeds no profile — so launchd refuses to spawn the process before
  any application code runs, leaving the app's own logs empty while the
  installer reports success. The default path now warns with the unauthorized
  entitlement, the missing profile path, and the exact error about to appear;
  `--strip-unprofiled-entitlements` opts into a launchable local build and says
  plainly that Sign in with Apple is absent from it. Issue #141 records that the
  choice among its three fixes is a product decision about signing identity, so
  this deliberately leaves that decision open and only removes the silence.
  Previously the only working macOS build was a hand-re-signed artifact that no
  repository change could reproduce.

## August 4, 2026 at 7:07:52 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commits: `65076f1cdb5fbbd0abd7fb748f0a85a26e5f6b63`,
  `6f035076d6e76366549ec3922a54e09149631f12` (WIP checkpoint)
- Reason: Make five seconds the timeout everywhere in `AGENTS.md`. Written down
  after the wedged Mac above went undiagnosed while a probe sat on a 60-second
  watch and reported nothing: a long timeout does not make a stall less likely,
  it only delays discovery and turns a loud failure into a hang that reads as
  "still working". Work that legitimately needs longer is a progress-reporting
  problem, not a timeout problem. The second commit checkpoints another agent's
  untracked `docs/core-module-extraction-audit.md` unmodified, because the macOS
  installer refuses to build from a dirty checkout and `AGENTS.md` names a WIP
  checkpoint as the way to preserve another agent's in-flight work rather than
  stashing it.

## August 4, 2026 at 5:10:00 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commits: `8b51efd191d84a0b2e47815be4fd718f168c90cc`,
  `276ec1f4017e9b4bbb34cc27eeb3a8b59eb724ee`,
  `5fdddd7` (docs/ADR)
- Reason: Open the running TCA store to an agent over the diagnostics WebSocket.
  A physical device has no terminal touch path (`devicectl` exposes no input
  command), so the reducer that was meant to be terminal-drivable was reachable
  only by a finger. `.agentRemoteControl` sits at the root beside `_printChanges`
  and accepts `listActions`, `readState`, `sendAction` through the same reducer
  the UI uses. The catalog is generated by a `@RemoteControl` macro from each
  `Action` enum instead of being hand-maintained; nesting composes, so the iPad
  build exposes 181 actions with no list in the source. **Relevant to this
  repository:** driving the store from a terminal immediately exposed a lost
  reservation acknowledgement — the recording-title counter advanced 184 → 185
  server-side while the client sat in `isRecordingTitleReservationInFlight` with
  no timeout, which is delivery/acknowledgement behaviour the library owns.

## August 4, 2026 at 1:56:30 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `325af15aedb4a4a53e0f9a2ba14b6e1b0f4a4b3c` (see `git log` for the full SHA)
- Reason: HACK — tolerate an empty pre-sync emission for the recording-title
  counter so the record button can start a recording. On a fresh iPad install the
  live observation emitted an empty materialization for `recordingTitleSequences`
  16 seconds before that namespace synced; the client read it as data, threw
  "received 0", ended the observation, and discarded the authoritative high water
  of 183. **Owed to this repository:** load state on `InstantQueryEmission`,
  mirroring upstream InstantDB `isLoading`, so consumers can distinguish a cold
  cache from a server-confirmed empty set. Landing that flag removes the hack.

## August 4, 2026 at 1:15:49 AM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `7cd5c6d2d2826c6cce1dfeea5d81569184cda05a`
- Reason: Write diagnostics to the tailnet WebSocket collector and the InstantDB
  `debugLogs` app at the same time, and instrument the record-button gate in the
  reducer. An iPad on `dfbe377` produced no diagnostic events for a dead-looking
  record button, and its InstantDB lane had been dark for two days while the app
  kept running, so a lane built on the Instant client could not report its own
  outage. Also preserves `InstantError` detail that the `NSError` cast had
  collapsed to domain plus code 1.

## August 3, 2026 at 11:39:21 PM EDT

- Repository: `instant-data-swift`
- Commit: `a52ab0911d4e78e1b7b33f610240fe55c74f069b`
- High-level reason: Fix the library-side blocker behind the Mac livestream (#003) and, more broadly, behind every stale device. Instant stores attributes as data, so a client can only materialize namespaces whose attributes it holds, and query observation refuses to subscribe to a namespace it cannot validate. The client decoded the attribute set the server sends in every `init-ok` but kept it in memory; attributes only became durable as a side effect of a query result for a namespace it already knew. That deadlocks for every namespace it did not: no attributes means no subscription, no subscription means no result, no result means the attributes never arrive — silently, with a healthy-looking connection. Upstream applies the set on every `init-ok` (`Reactor.js:640`); this now does the same on the connect path, merging rather than replacing so a namespace/name pair the device already holds keeps the local attribute id its triples and pending mutations reference. Proven against the real server from a cache holding no attributes: 0 → 361 attributes across 37 namespaces after one connect, and unchanged with the call removed. Decision recorded in ADR 0011. CORRECTED 2026-08-04: this entry originally said the defect was why the Mac never saw a stream request (#003), citing a cache frozen at 133 attributes over 16 namespaces. That file (`~/Library/Application Support/InstantDB/`) is stale and unopened; the app uses `~/.instant-swift-data/apps/`, which holds 466 attributes over 38 namespaces including 16 locally-seeded `screenStreamSessions` attributes. The causal claim is withdrawn — an app that seeds `initialAttributes` from its schema cannot hit this deadlock — while the defect and fix stand on the clean-cache evidence.

## August 3, 2026 at 6:42:32 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `46e20a2c80611e4b832e7e386ba819ba9029ee1b`
- High-level reason: Isolate the Mac-side claim failure for the livestream (#003) with a terminal-driven probe rather than UI guesswork. `scripts/screen-stream/probe-mac-claim.mjs` writes a fresh unexpired `screenStreamSessions` request in exactly the shape the phone produces and polls for 60 s; the running Mac never claimed it. Ruled out the false negatives first: permissions grant `view: "true"`, the Mac process was alive with two established TLS connections, and every session since 2026-07-29 is likewise unclaimed. Narrows the cause to the Mac Instant store never installing as default (where an `AsyncSerialGate` stall would present, and the deployed build pins published 1.2.2 without the fix) or `observeAll` never emitting — and notes that the remote log lane, dead since 2026-07-30, is installed by that same bootstrap, so both symptoms may be one defect.

## August 3, 2026 at 6:42:32 PM EDT (build blockers)

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commits: `082dd0f8b5253e5f02ccc9fae122020c39a0cc95`, `0ee348982516d680508d7aef2dc168ed45f5f8c8`, `749e06d21ff3c97b9ebf0f1fa418865d0a82c3a7`
- High-level reason: Clear three blockers that prevented any provenance-checked device install. `.claude/settings.local.json` was ignored only by the user-level global gitignore, which the SwiftPM plugin sandbox cannot read, so every reproducible build failed "requires a clean worktree" while the tree looked clean outside the sandbox. Two genuine bugs in the checkpointed code stored JavaScript's `MAX_SAFE_INTEGER` in an untyped `Int`, which overflows on watchOS `arm64_32`; `SharedModels` then failed to emit for the watch leg and took the whole embedded iOS scheme down, which was the root of all 150 device-build failures and is invisible to the 64-bit macOS test suite.

## August 3, 2026 at 7:19:04 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commits: `5919c9e672b922e659615542a4002a44bbb1ce68`, `f5c4dc3` (see Git history for the full SHA)
- High-level reason: Fix the Mac half of the livestream (#003) and narrow what remains. The Instant store was started by a SwiftUI view's `.task` and cancelled by its `.onDisappear` with a per-view `@StateObject`, so on a macOS app that deliberately outlives its windows, closing one cancelled the shared bootstrap — taking down both the screen-stream claim loop and the real remote logger at once, which is why both went silent on 2026-07-30 with no error reported. The store is now process-wide and started from `applicationDidFinishLaunching`; on-device logs confirm the claim loop starts for the first time. Separately, `observeScreenStreamSessions` swallowed every subscription error into an empty catch and then finished the stream, leaving the Mac in a silent one-second retry loop; failures are now loud through `reportIssue` and a structured event. What remains is precise and library-side per ADR 0001: the `screenStreamSessions` subscription stays alive and never delivers a first batch, with the `AsyncSerialGate` stall (absent from the pinned published 1.2.2) as the leading hypothesis.

## August 3, 2026 at 5:06:55 PM EDT

- Repository: `instant-data-swift`
- Commit: `4b596d4ec9b42ba8c62dada1aa52cf22442c82ae`
- High-level reason: Honor cancellation in `AsyncSerialGate` and name the holder when it stalls. The old 23-line gate parked cancelled waiters forever (non-throwing continuation, no cancellation handler), so Scribe's cancel-in-flight session-request retries each made the stall permanently worse; `transact` now enters the operation gate cancellation-aware (honored only before acquisition so a started critical section still completes), the four runtime gates are labelled, and a watchdog reports the holding function, longest waiter, and queue depth through `InstantDiagnostics` and `reportIssue` instead of stalling silently. Verified against upstream: `Reactor.js` has no equivalent primitive because the JS reactor is a single event loop, making this a documented Swift-side adaptation. Continues an earlier agent's uncompiled work; it built and all 8 gate tests plus the full suite passed unmodified.

## August 3, 2026 at 5:05:10 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8e79caa0201c12684609df2de0e39c4a8f2b498e`
- High-level reason: Link the live screen publisher into the iPhone app and record the decision. The phone linked only `ScribeSharedAppCore`, whose closure deliberately contains no LiveKit, so no publisher could ever have run on device regardless of reducer wiring; `project.yml` now links `ScreenStreamFeature` (mirroring the Mac target), the host app registers the live client with `prepareDependencies` so the linker cannot dead-strip the conformance, and the #066 linkage test pins the new product list while the appex allowlist stays `SystemAudioBroadcastHandoff` only. Decision recorded as Scribe ADR 0001.

## August 3, 2026 at 5:03:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `55c08113995164d82c6045a8794800adb8dda3be`
- High-level reason: Wire the `Recording` reducer to start, feed, and stop the screen publisher (#003). Start on ReplayKit broadcast activity with a ready saved configuration, forward every JPEG frame with no second throttle so `videoSampleInterval` stays the only rate control, stop on broadcast end and every teardown path, log loud named failures with the exact fix, and exclude the Mac by data (`automatesScreenStreamPublisher`) because it holds a subscriber-only grant in the same App Group slot. Seven TestStore tests pin the behavior.

## August 3, 2026 at 5:01:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c0fc4ac0da5ba1b785f7ea817c269b397e4c46f2`
- High-level reason: Build the missing host-side bridge from broadcast JPEG frames to the LiveKit publisher (#003). `captureVideo` had zero callers; this adds the `ScreenStreamPublisherClient` seam, the JPEG→BGRA `CMSampleBuffer` converter, a strictly increasing host-side publish timeline that refuses to inherit the #143 clock reset, and a live bridge session reporting `framesReceived` vs `framesPublished` on every event so frame loss can never be silent again.

## August 3, 2026 at 4:18:52 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1b5321e068d6a44bdb280c83006e8601fddab2dd`
- High-level reason: Correct the livestream diagnosis and reorder the work behind it. `ScreenStreamClientLive.captureVideo` and `captureAppAudio` have zero callers anywhere in the repository, so the LiveKit publisher is fed by nothing at all — the broadcast extension's JPEG frames terminate in the recording transcript instead — which means the prior framing of "the carrier is too slow to reach video rate" was wrong and fixing the session-request stall alone would have connected a room and published an empty track, presenting as a LiveKit or token defect. Records the revised order (bridge the existing frames into the publisher first to prove room connect, token, publish and render end to end, then fix the stall, then replace the file carrier with LiveKit's Unix-domain-socket path), the developer's requirement that publish cadence respect the existing `videoSampleInterval` setting rather than a second throttle that would silently multiply it, the per-frame performance measurement points the bridge must leave behind given the device already leads energy use at ~25% of one core and 40.3 °C, and the state of three subagents terminated mid-task by an account usage limit — including uncommitted and never-compiled `AsyncSerialGate` cancellation work in this repository, and a proven-compiling WebRTC-free 16-file broadcast closure whose host-side symbol collisions argue for forking `client-sdk-swift` rather than vendoring it.

## August 3, 2026 at 2:41:06 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c7a236377030000fc23be3b8596e25c42499c52c`
- High-level reason: Record that Scribe and `instant-data-swift` are co-developed through a symlink so a Scribe symptom is as likely to originate in the library (and a reinstall does not rule it out, because the cache and outbox persist on disk); add `docs/performance-budget.md` as the release gate, written against the measured 2026-08-03 sysdiagnose baseline with a measurement command beside every threshold; symlink `CLAUDE.md` to `AGENTS.md` so the canonical instructions cannot drift.

## August 3, 2026 at 2:39:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6430fd0d6b725c3e7bfdf9b5ceb74fea56822465`
- High-level reason: Point the diagnostics status probe at the port the collector actually listens on, because the Foldkit portal squatting the old port answers `/health` with a 404 rather than refusing and so disguised a healthy collector as a broken one; document the tailnet TLS prerequisite whose absence kept the shipping diagnostics lane dark, along with its device-visible `NSURLError -1004` / POSIX 61 signature and the fact that `tailscale cert` writes a private key into the working directory.

## August 3, 2026 at 2:37:05 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3dbc3a4ff6d1384cce2ab99d6fdc109ce2a7e103`
- High-level reason: Restore supervision of the shipping diagnostics collector by binding it to a free port instead of evicting an unrelated project that has held 8765 since 2026-07-26, and scope the installer's dirty-tree guard to the files launchd actually executes so unrelated in-flight work on shared `main` can no longer block a clean install — the repository-wide check could only be satisfied by committing another agent's uncommitted changes.

## August 3, 2026 at 2:32:51 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1b586060af1d024085ae9c50b1e27dc220607c8a`
- High-level reason: Teach the Instant schema drift gate the pulled `rooms` root key so its comparison runs again instead of failing closed on every invocation; record and enforce the decision not to compare rooms (they are client-side declarations the pull echoes, never server state), and report an unrecognized root key as a named unsupported-feature failure. (#144)

## August 3, 2026 at 12:49:11 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9fdadc081e81e9e688c0c117d94eebcf6697e986`
- High-level reason: End the ReplayKit broadcast when the recording stops, via a Darwin notification the extension honours, because only the extension can call finishBroadcastWithError. (#066, #120)

## August 3, 2026 at 12:23:16 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `66b30f5e57bdc2e94615fa678a2d34212c384eda`
- High-level reason: Remove a DragGesture(minimumDistance: 0) that claimed every touch in the recording timeline so rows opened on swipes, and make the system-video frame interval configurable end to end. (#140)

## August 3, 2026 at 10:23:20 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `39bd55cd7d2edc4ebc3d6f104f22cc7abc90c23c`
- High-level reason: Make the broadcast panel's video toggle and picker work: the toggle guarded on !isRecording while its panel only renders during recording, and the picker searched only RPSystemBroadcastPickerView's direct subviews for a button that is nested deeper. (#140)

## August 3, 2026 at 8:38:14 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7f7e1ddad4a6b995854c86379d5eebe162cd1dd7`
- High-level reason: Unlink ScreenStreamClientLive from the broadcast upload extension, which had pulled LiveKitWebRTC and RustLiveKitUniFFI into an appex with no Frameworks directory on its runpath, so dyld killed the extension at launch every time. Root cause of system audio being dead since c409dec on 2026-07-28; verified on the physical iPhone. (#066)

## August 3, 2026 at 6:24:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `fedeae5301c87f1424a1df13905b85e01b2bcff1`
- High-level reason: Guard a Mac-only Process/Pipe call site so ScribeSharedSupport compiles for iOS, watchOS, tvOS and visionOS again; the entire iOS app had been unbuildable since bdf0173. (#138)

## August 3, 2026 at 6:09:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5b18ed77e4cc5a043db2bc4f744654301c733f93`
- High-level reason: Give the broadcast upload extension a diagnostic lane that is not the channel under suspicion: a heartbeat written by whole-file replacement, mirrored into the shared UserDefaults suite and readable after the extension exits. (#066)

## August 3, 2026 at 3:24:09 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `823d547e669f6545224cc9b76bc3e581a64b2b0f`
- High-level reason: Align the E2E latency gate to the 200 ms target #089 actually states; the previous 100 ms sat below this location's measured network floor to api.instantdb.com, so it failed on something no client change could reach.

## August 3, 2026 at 3:24:00 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `654e07549bad14da4ab51dcd02981aac8d954aed`
- High-level reason: Pin with a focused test that one unrelated terminal outbox row no longer silences the InstantDB diagnostics lane, giving #135 criterion 3 the evidence d829490 shipped without.

## August 3, 2026 at 3:23:50 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5a4f552774bca07f3253cc4a3128da29b07e2ea4`
- High-level reason: Give the stream listener per-segment isolation so one unanswerable segment stops losing the developer's speech, and stop a failed remote write leaving presence claiming a listener is both observing and stopped. Five focused tests verified to fail against the pre-fix source. (#137)

## August 2, 2026 at 7:21:33 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b7db0813ec8282a906d3287a80a016723180143`
- High-level reason: Isolate the generic real-Instant Swift E2E writer in a
  fresh per-report HOME/Application Support/database tree so the test cannot
  open the production CLI cache or inherit legacy outbox mutations. The
  platform/local-root contract passes 25/25, and credentialed diagnostics
  delivered 5/5 and 25/25 rows while correctly retaining the strict latency
  failure (25-row p95 214.2 ms against the 100 ms target).

## August 2, 2026 at 8:06:12 PM EDT

- Repository: `instant-data-swift`
- Commit: `1ac73a1bce165920deb83f06c7d7070c652cacf2`
- High-level reason: Stop one unretryable legacy outbox row from taking down
  the whole live connection. Rows written before durable optimistic-overlay
  metadata carry the deploy-fixable "could not resolve" message, so the
  connect-time retry sweep selected them and threw `retainedUnknown`; the
  live-connect catch then closed the socket, stored an `errored` connection
  state and rethrew, repeating on every reconnect. That silenced queries, all
  later mutations, and the separate diagnostic-log client, presenting on the
  physical iPhone and iPad as an indefinite "Loading recordings…" with no
  error. The row is now retained and reported while the sweep continues.
  Tracked as issue #134 (P0).

## August 2, 2026 at 7:06:28 PM EDT

- Repository: `instant-data-swift`
- Commit: `460b7ca01e049dd45338a0a1766c90195655d33d`
- High-level reason: Restore the declared `.watchOS(.v8)` platform. The
  browser-OAuth and Apple ID authorizer guards relied on `canImport(UIKit)`,
  which is true on watchOS even though the platform has no
  `ASPresentationAnchor`, `UIApplication.connectedScenes`, or
  presentation-context protocols, so the module failed to compile with 13
  unavailability errors. Adding `!os(watchOS)` routes watchOS to the existing
  unsupported-platform branch. Found while building Scribe for the physical
  iPhone, whose iOS app embeds the `ScribeSharedWatch` companion. Published as
  tag `v1.2.1`; tag `v1.2.0` at `01ac62bd` does not compile for watchOS.

## August 2, 2026 at 6:39:23 PM EDT

- Repository: `instant-data-swift`
- Commit: `71ccbcf132508376adb0281fd100821e1ff6c12f`
- High-level reason: Match upstream exact-value retract semantics by
  reconciling a retained server-accepted write only when the prepared
  authoritative transition proves the exact EAV existed before and its
  cardinality-one key is absent afterward; base-absent and unrelated retracts
  remain fail-closed, with the complete 139-test gate green.

## August 2, 2026 at 6:29:55 PM EDT

- Repository: `instant-data-swift`
- Commit: `8d02a7a8d6b7000dea42be0b534e96761e3b1daf`
- High-level reason: Require explicit WebSocket or server-transport
  acknowledgement before resolving mutation delivery, atomically remove known
  optimistic effects on terminal rejection while rebuilding successors, and
  fail closed when authoritative refresh does not cover every materialized
  effect; the coupled 136-test gate and independent P0/P1/P2 review are green.

## August 2, 2026 at 6:11:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d15c3aa6b290bfc83955063fabf47c611032431b`
- High-level reason: Preserve the user's 17%-usage cutoff boundary with the
  exact three hash-anchored #117 acknowledgement P1 findings, protected typed
  log identity, ownership and re-review gate, plus #043's current read-only
  production title evidence (`178` to planned `179`) and continuation order.

## August 2, 2026 at 5:55:23 PM EDT

- Repository: `instant-data-swift`
- Commit: `95cc1f03cf533696ac3fb1ac86e7977c1f130f17`
- High-level reason: Preserve issue #043's exact 39/39 acknowledgement and
  rollback evidence while explicitly recording the four independent-review
  no-ship blockers, expanded ownership, and regression-to-ledger continuation
  boundary required before stabilizing the editable ABI for Scribe #059.

## August 2, 2026 at 5:44:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `fe43d27475b47664a6ae893bbd65a731fa903e76`
- High-level reason: Preserve a cutoff-safe cross-repository boundary naming
  the immutable Recipes presence commits and protected evidence for #127–#130,
  while recording #059's zero-completed-test SIGSEGV as unverified mixed-ABI
  evidence with the exact fresh-scratch continuation gate.

## August 2, 2026 at 5:41:40 PM EDT

- Repository: `instant-data-swift`
- Commit: `671e370509294195992f6482aced9b7b169c4bc1`
- High-level reason: Preserve topic event identity so repeated equal-payload
  Recipes reactions animate across devices, expose touch-device custom cursor
  feedback, and project Avatar Stack presence once per logical user, with 25/25
  focused wrapper and app regressions green for issues #127–#129.

## August 2, 2026 at 5:34:02 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `653fb7d02ce39c82ca7cadfb1e436e5ae6faa015`
- High-level reason: Integrate the proven shared AuthV3 account surface into
  iPhone/iPad Settings and Mac General Settings through one TCA route, with
  platform-owned Apple client names, shared Google/callback configuration,
  guest/canonical session projection, loud failure state, and 4/4 focused tests
  for issues #113 and #131.

## August 2, 2026 at 5:30:25 PM EDT

- Repository: `instant-data-swift`
- Commit: `5d506d7a393c0e340445190677c5f151b53b0791`
- High-level reason: Preserve a cutoff-safe, newest-first checkpoint for issue
  #043's explicit server-acceptance RED contract and issues #127–#130's
  upstream-backed topic, cursor, presence, and Merge Tiles diagnoses, including
  exact ownership, dirty-file boundaries, test evidence, and unfinished device
  acceptance.

## August 2, 2026 at 5:29:29 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `61dc6668920c611128e5acd3aed892e66c823252`
- High-level reason: Preserve a cutoff-safe recovery boundary with exact
  subagent ownership, physical Recipes Apple acceptance evidence, typed issue
  references, acknowledgement NO-SHIP findings, title/list/auth test state,
  concurrent dirty-file boundaries, and the clean landing/device order for
  issues #043, #059, #113, and #127–#131.

## August 2, 2026 at 4:29:34 PM EDT

- Repository: `instant-data-swift`
- Commit: `6408c8ec1982bda51442a6e517c4d900c7818734`
- High-level reason: Route app-owned Apple and Google provider metadata into
  the runnable Recipes auth surface, register its OAuth callback, enable the
  signed Apple capability on iOS and macOS, and protect the packaging contract
  with focused tests for issue #113.

## August 2, 2026 at 4:26:07 PM EDT

- Repository: `instant-data-swift`
- Commit: `ff736a0ae8c01b251d75507e8e9cbba5162d6fc1`
- High-level reason: Require canonical upstream Instant TypeScript behavior as
  the starting point for tricky synchronization, optimistic-state, rejection,
  reconnect, query, auth, and persistence edge cases; preserve its transition
  and test shape and document necessary Swift adaptations for issue #043.

## August 2, 2026 at 4:24:56 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `67e4c27fea7a5541ef21e7569bc96d84a5fa0091`
- High-level reason: Make canonical upstream Instant the required starting
  point for tricky synchronization, optimistic-state, rejection, reconnect,
  query, auth, and persistence behavior; preserve the upstream transition and
  document any necessary Swift/Scribe adaptation for issue #043.

## August 2, 2026 at 2:22:59 PM EDT

- Repository: `instant-data-swift`
- Commit: `f13ee441dabbcdf3144a0cd42dfa9f00c1ebdf37`
- High-level reason: Add callback-safe native Apple auth, state/PKCE browser
  OAuth for Google and other providers, and atomic exact-guest-token promotion
  with injectable client seams, truthful linked-existing-user outcomes, a
  polished sample surface, independent review, and 62 passing auth tests for
  Scribe issue #113.

## August 2, 2026 at 2:18:49 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3636f17c8954549e2762d8382186c25b68f2d7a6`
- High-level reason: Preserve physical-iPad proof that the Home Screen widget
  routes into recording but the enabled built-in microphone returns an exact
  all-zero WAV, while the local row/media survive behind 901 pending Instant
  mutations and disappear from the UI after relaunch despite zero remote rows
  for #023 and #026.

## August 2, 2026 at 1:59:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `adf30204cb36e0b73c60cf7b215994257bcc6fd0`
- High-level reason: Preserve physical-iPhone #044 evidence that audio had
  stopped before a stale pre-WebSocket Scribe process was normally terminated,
  record its continued Instant/diagnostics activity, and correctly rule the
  visible 27-hour Apple Clock stopwatch out of the Scribe thermal incident.

## August 2, 2026 at 1:47:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `03d95f864a74e959e8ef914e259dd9449dfa8556`
- High-level reason: Enable the signed Sign in with Apple capability across the
  iPhone/iPad host and both Mac packaging paths, with a focused regression that
  keeps the entitlement present while physical provisioning and account
  completion remain explicit unverified acceptance lanes for #113.

## August 2, 2026 at 1:14:58 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9b22efe8ac1ff33b909a47bc137aa32c1c1184f8`
- High-level reason: Record the returned-device recovery boundary with immutable E2E and system-surface SHAs, exact auth-worker ownership, verified guest-promotion semantics, the Mac inline-response contract, the iPhone thermal lane, and the safe continuation order for #035, #044, #089, #099, #113, and #116.

## August 2, 2026 at 1:11:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `cd272b3ba21ffc3d88f8291cd190d56600eee1af`
- High-level reason: Keep iPhone/iPad widgets, Live Activities, deep links, and app-icon quick actions aligned with canonical recording state; coalesce rapid transcript reloads across both widget kinds; preserve paused state; and remove Start Recording while capture or playback is already active for #013, #105, #116, and #126.

## August 2, 2026 at 1:05:58 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `20e664c9f15073c59c348fbe05185ccc604b8a8f`
- High-level reason: Add a repository-owned bounded E2E JSONL observer skill, make Scribe-specific guidance qualify evidence while the generic typed tracker owns lifecycle mutations, and teach the two-commit ledger to link canonical issues #041 and #089 with focused tests.

## August 2, 2026 at 1:03:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6fe4be91321e5598471932ac5b1387b9a3c196fb`
- High-level reason: Harden the simulator-only real-audio Instant matrix so nine independent Mac/iPhone/iPad writer-observer lanes require exact fixture PCM, deterministic transcript projection, materialized storage bytes, guest identity separation, publication-anchored latency, private issue-tagged local JSONL, bounded artifacts, and clean participant shutdown for #089 and #116.

## August 2, 2026 at 12:43:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6b11ab6194560c5d1b61dbce47a4d3e965a7201d`
- High-level reason: Replace the synthetic Instant matrix with independent guest writer/observer participants that drive the shipping recorder from a checked-in real 48 kHz WAV, mock only transcription, require exact PCM and remote materialization, anchor latency to successful publication events, and emit dependency-injected bounded private device logs for #089 and #116.

## August 2, 2026 at 12:28:13 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1e3297dda65698f52e08a1c791cc1b256510fa9f`
- High-level reason: Add a disposable 128 KiB startup recording projection that renders cached and valid-empty libraries before canonical bootstrap, reconciles only paired fresh pages, isolates cache paths by database/persistence/account/E2E participant identity, and strictly bounds corrupt quarantine while retaining physical under-200 ms acceptance as an explicit open lane for #059.

## August 2, 2026 at 12:17:53 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `252af0be307c47734f702f72ef161d9b24ce853a`
- High-level reason: Preserve the connected physical iPhone's inspected widget and Live Activity screenshots as immutable before evidence for typed issues #013, #105, and #116, proving the observed active-recording versus idle-widget state mismatch without overstating tap-routing acceptance.

## August 2, 2026 at 11:45:25 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3e4d78a01e873f4001582a409adfa196b911bdd6`
- High-level reason: Preserve the green generic simulator build without overstating acceptance, record every independently reviewed E2E false-pass blocker, lock the physical-iPhone no-contact boundary, and select the bounded read-only launch-projection design and exact restart order before further implementation.

## August 2, 2026 at 11:28:59 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4b2d08f29e3a1a41123f5a652e2e203d66a19a38`
- High-level reason: Persist immutable diagnostics and cold-load commits, exact test and performance evidence, memory and physical-acceptance boundaries, the disconnected-iPhone prohibition, remaining simulator E2E ownership, and the safe ordered continuation so limited premium-model access cannot strand the recovery state.

## August 2, 2026 at 11:27:29 AM EDT

- Repository: `instant-data-swift`
- Commit: `0f78572e02a17189409fc918b912188e9d50680a`
- High-level reason: Reduce eager SQLite state-load time with bounded 1 MiB/1,024-row JSON arrays and two decode slots, preserve exact ordering and outbox semantics, add loud row-range/path failures and per-collection tracing, and retain a release profiler plus explicit memory and physical-acceptance boundaries.

## August 2, 2026 at 11:26:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `de0ee7df1b6052e072ee208e76507dac6f3661ea`
- High-level reason: Replace the startup-blocking diagnostics Instant database with bounded crash-recoverable device JSONL, one process-long tailnet WebSocket, durable collector acknowledgements, protected-evidence retention, opt-out lifecycle enforcement, and a loopback-only launchd-supervised collector.

## August 2, 2026 at 10:59:06 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a3cb9f652865d18636bf7c2180e77e6226a91cb9`
- High-level reason: Persist the user's explicit no-access boundary for the disconnected iPhone, the simulator and physical-iPad continuation lanes, the committed audio-recovery evidence, and collision-free worker ownership so a restart cannot violate the device boundary or lose progress.

## August 2, 2026 at 10:57:23 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `38a822c3b81cc92f32f98a63bf31c9e9ae33f6fa`
- High-level reason: Recover the active microphone capture graph after input-hardware changes without changing recording identity, serialize teardown against recovery, and keep automatic audio-session reclaim alive in bounded retry windows when iOS omits the interruption-ended notification.

## August 2, 2026 at 10:34:43 AM EDT

- Repository: `instant-data-swift`
- Commit: `b92d5f0976e99bea2712973b5e1f5cfce48c9429`
- High-level reason: Standardize immutable, restartable progress checkpoints across the active library and Scribe repositories because ChatGPT and Sol Ultra access is limited.

## August 2, 2026 at 10:33:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e5fd42b51712990b2c7faa08e22961e53db401b1`
- High-level reason: Preserve a restartable physical-recovery checkpoint with immutable commits, device evidence, worker ownership, simulator real-audio E2E acceptance criteria, and exact continuation steps because premium-model access is limited.

## August 2, 2026 at 10:26:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `e87765b8cd8c5c2830494ee05c9686f7edb9f4d4`
- High-level reason: Prevent deep persisted outboxes from starving live queries by sending query registrations first, bounding unacknowledged transaction work by count and low-level step weight, and refilling only after acknowledgements with reentrancy-safe reservation cleanup.

## August 2, 2026 at 10:06:27 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `aa5229f13d6a2e2a7a985cc15c848cfb9e6e6c5a`
- High-level reason: Add typed, bounded Instant issue-file evidence handling with validation before upload, SHA-256 over the exact streamed bytes, atomic issue linking, orphan cleanup, relation materialization, and overwrite-safe downloads.

## August 1, 2026 at 11:54:55 PM EDT

- Repository: `instant-data-swift`
- Commit: `be978ea30743b1aa05f03dd2ceae4fdf1bf77bbd`
- High-level reason: Enforce UUID validation on INSTANT_APP_ID environment variable in AuthV3AppConfiguration to prevent non-UUID strings (like 'auth-v3-local') from reaching InstantDB server OAuth endpoints.

## August 1, 2026 at 11:45:40 PM EDT

- Repository: `instant-data-swift`
- Commit: `f8bf1938bfe43818e90632b719ee18e11a2f6460`
- High-level reason: Update default InstantDB app ID in AuthV3AppConfiguration from 'auth-v3-local' placeholder string to canonical UUID ('28c98cc4-e65b-41be-a5bc-204827f5d364').

## August 1, 2026 at 11:40:40 PM EDT

- Repository: `instant-data-swift`
- Commit: `4a5f309e088d22384a86acdf2cfecfef2ef3ecfa`
- High-level reason: Implement ASWebAuthenticationSession browser OAuth authorizer with automatic fallback for Apple Sign-In when running in development/un-entitled binary builds.

## August 1, 2026 at 11:18:00 PM EDT

- Repository: `instant-data-swift`
- Commit: `4048c2058d85ffd5214f1c456a1d727524065828`
- High-level reason: Implement native Apple Sign-In authorizer using AuthenticationServices ASAuthorizationController and update AuthV3App UI to display logged-in credentials and logout functionality.

## August 1, 2026 at 10:15:24 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b4c2d04ec3e8c99db222249c871010a8d45a5d9a`
- High-level reason: Keep the recording audio session alive through system alerts and hardware-muted microphones — adds setPrefersNoInterruptionsFromSystemAlerts and .overrideMutedMicrophoneInterruption, retries setCategory without resilience options instead of failing the recording, and downgrades three previously fatal optional preferences to reported issues. Ledger entry added by the session that owned this repository, since the authoring agent was scoped out of it.

## August 1, 2026 at 10:07:28 PM EDT

- Repository: `instant-data-swift`
- Commit: `3f4e8926c6b7845ecb3f46a0ab7316328ba2a0e8`
- High-level reason: Add a package-benchmark suite (the tool TCA2 uses) measuring wall clock, CPU, malloc, peak resident memory, and throughput for local write, read, and cold store reopen — first run: write p50 28ms, query p50 41ms, reopen p50 117ms.

## August 1, 2026 at 10:07:28 PM EDT

- Repository: `instant-data-swift`
- Commit: `4fbc07fb6421b7591e3dea61bc409ad20b2aa299`
- High-level reason: Recover mutations quarantined by schema or permission drift by retrying deploy-fixable failures on a fresh session, so the 463 and 1 stranded field mutations can deliver once the deployment lands.

## August 1, 2026 at 9:38:07 PM EDT

- Repository: `instant-data-swift`
- Commit: `0d0fbc3d5acb3308fe6c652fe57904a6d080aa50`
- High-level reason: Stop a schema-drifted mutation from stalling the whole outbox — bounded flush batches, in-flight acknowledgement timeout, IssueReporting visibility for quarantines/deep backlog, and keeping a healthy connection open when recording a quarantine fails. Reconstructed from a Scribe device outbox holding 691 pending mutations.

## August 1, 2026 at 5:02:23 PM EDT

- Repository: `instant-data-swift`
- Commit: `5ae2f6b7d6f5c2904918544f7e1a578798163626`
- High-level reason: Add newest-first PROGRESS.md tracking library-side work driven by the Scribe production-readiness plan (seam defects under diagnosis, planned RecipesV3 latency/large-list validation recipes, dedicated E2E test database with Instant-room semaphore).

## August 1, 2026 at 5:02:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3bf8a8b915514937c812ea14244433baf6887d38`
- High-level reason: Author production-readiness master plan (docs/production-readiness-plan.md), newest-first PROGRESS.md, and getadb test-database provisioning documentation (.env.example placeholders, .gitignore coverage for .env.test).

## August 1, 2026 at 10:12:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ca1bb950b7f30440699d6d3385e7e51b811efb63`
- High-level reason: Quote node labels and link titles in README.md Mermaid diagram to prevent syntax rendering errors.

## August 1, 2026 at 10:02:20 AM EDT

- Repository: `instant-data-swift`
- Commit: `d86fe4a6c0b70c11c8b8573205c35ada954be8c3`
- High-level reason: Add root MIT LICENSE file.

## August 1, 2026 at 9:56:50 AM EDT

- Repository: `instant-data-swift`
- Commit: `2a50ed044f10d026e9374585d273ae1414cb6127`
- High-level reason: Update README with InstantDB open-source platform-agnostic sync details across TypeScript, React, React Native, Vue, Svelte, and Swift.

## August 1, 2026 at 9:54:30 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5c982a7c30ef891bba44f8896b59d403cad5774c`
- High-level reason: Audit repository secrets, extract environment variables template to .env.example, and author comprehensive README.

## August 1, 2026 at 9:52:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `6ec3cb6ac70f135e9d8c68ceac7985795607b70d`
- High-level reason: Create Point-Free style README with comprehensive feature list,
  quick start guide, code comparisons, and pre-release disclaimer.


## August 1, 2026 at 1:14:47 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `68d5aad21486aa49fdde1c30f88e6d260b0268b2`
- High-level reason: Preserve sanitized physical-iPad evidence for Recordings
  175 and 176 with exact persisted counts, PCM duration and signal facts, build
  provenance, and hashes while explicitly leaving screenshot causation unproven.

## August 1, 2026 at 1:13:20 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f3f8f33e5516ce1e00ac55067f35e11d7ea47fa0`
- High-level reason: Add a dependency-controlled TCA health snapshot pipeline
  that reads Voice Memos and local Instant Swift Data metadata without mutation,
  establishes a start-now watermark, and persists only salted memo identities
  plus aggregate Scribe counts and deltas in a private host-local SQLite store.

## August 1, 2026 at 1:10:54 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9185d36968a03af6f4e708787a6f4fedc78252bd`
- High-level reason: Add a serialized regression gate with a deterministic
  recording corpus, exact focused Instant Swift Data tests, stale-binary
  fingerprinting, strict sub-minute acceptance, and honest separation of
  credentialed, simulator, resource, and physical evidence lanes.

## August 1, 2026 at 1:10:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `64b845fab3685d26f0bf2481333701e9db12ee94`
- High-level reason: Preserve the latest persisted transcription word count in
  cold recording-list projections until real timeline sections hydrate, while
  keeping hydrated timeline words authoritative.

## July 31, 2026 at 3:37:08 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c109f7a369df5fffe75d76c1f8c3ffb202d06a53`
- High-level reason: Defer the restricted user-assigned device-name entitlement
  until Apple grants it for the iOS bundle, retain the exact restoration patch
  in an immutable named stash, and add a root index explaining the blocker,
  fallback behavior, and post-approval recovery steps.

## July 31, 2026 at 11:26:16 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `bb43a6bf833983e5cf14bc6baac21863aa74e443`
- High-level reason: Move recording-list loading, retry, cancellation, and
  pagination into a reducer-owned dependency lifecycle; preserve complete and
  pending local history across partial pages; expose typed failures; and keep
  one observation alive across shared multi-window presentation.

## July 31, 2026 at 11:06:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2f340d1e23e34d89984cb84205fc594f8f5f01d1`
- High-level reason: Make remote-diagnostics opt-out invalidate queued events
  across blocked preparation and transient disable/reenable transitions, make
  disabled flush return without waiting for setup, and replace global
  quiescence waits with call-time enqueue completion fences.

## July 31, 2026 at 10:29:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e31a56a7a20502c264db1ada0ef8ad8d5876f0ab`
- High-level reason: Make explicitly requested physical-device deployment fail
  closed when the target is absent or unready, add exact CoreDevice ID and name
  selection without fallback, and bind plan and result evidence to that same
  device identity.

## July 31, 2026 at 10:20:24 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ecbfe82e268be472669f5103bc95b808372245e3`
- High-level reason: Remove dedicated diagnostics-store preparation from the
  startup critical path, bound and preserve queued evidence, stop active-recording
  system-surface churn, keep system-audio transcription provider-neutral, and
  add ReplayKit source diagnostics that distinguish missing callbacks,
  conversion failures, and all-zero PCM.

## July 30, 2026 at 6:25:00 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6fd3ad7cd7b0d78efc78669d18524854b72ace04`
- High-level reason: Use one automatic Apple Development signing identity for
  the iOS host, App Clip, widgets, broadcast extension, and Watch app so Xcode
  embedded-binary validation and physical-device deployment resolve the same
  certificate and team throughout the bundle.

## July 30, 2026 at 5:41:53 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `240019f98d9c62da359da9de6c1847238dea4458`
- High-level reason: Restore iPhone, watchOS, and unsupported-platform builds
  after the screen-recording permission dependency became required, while
  retaining macOS as the only live permission-request implementation.

## July 30, 2026 at 3:07:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `66a0f0926fd5607388c5d1b206846f86a51ae0c6`
- High-level reason: Bind Screen Recording recovery to Scribe's stable Apple
  Development identity, isolate ad-hoc QA builds, promote only verified signed
  bundles, and prevent stale ScreenCaptureKit failures from stopping a
  replacement capture session.

## July 30, 2026 at 3:02:21 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `77d93672443fabf32e1a8b01974e509a60ac8f4a`
- High-level reason: Restore the portable issue success-evidence vocabulary as
  the same explicit closed enum in Swift and TypeScript, rejecting arbitrary
  wire labels instead of silently accepting schema drift.

## July 30, 2026 at 1:56:32 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3ca298562069787aba201baffca5e3f5db36e58b`
- High-level reason: Bind the verified public clip duration into the exact
  publication approval fingerprint so duration drift always requires fresh
  approval.

## July 30, 2026 at 1:55:05 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0d08577e7957ac517bc8e24c60eb30bc6cb3de2f`
- High-level reason: Publish only trusted recording-time word ranges behind
  random 256-bit capabilities, immutable atomic handoffs, non-enumerating
  recording-bound routes, and fail-closed X create/delete intent recovery.

## July 30, 2026 at 1:51:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `97e8309a0babab64c0a791a664c3eb20692f4047`
- High-level reason: Give Scribe a canonical Mac window, native tabbed
  Settings, shared command-aware state, and Recording, Search, Sidebar, and
  editing menu commands while moving build provenance out of the main chrome.

## July 30, 2026 at 1:49:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a60dc7aad79f4b89626c2b4b0559941454b833a1`
- High-level reason: Productionize recording interaction with one control bar,
  a live dependency-controlled full-screen clock, deterministic scroll follow,
  complete corpus copy, readable Mac sidebar, and fail-closed ReplayKit image
  provenance.

## July 30, 2026 at 1:48:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `920d11257e707bb43364affb6bb0f598d8ed5e59`
- High-level reason: Add a private, disabled-by-default image-analysis domain,
  Apple Foundation Models adapter, byte- and profile-bound idempotency, portable
  capture provenance, and fail-closed Instant schema permissions.

## July 30, 2026 at 1:46:31 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1a780aea3f172ff0cbac274d4f9e5a7595d7d9c4`
- High-level reason: Give playback and export one ordered mixed-corpus document
  that preserves full clipboard text and every media/context entry for native
  selection plus explicit all-platform copy.

## July 30, 2026 at 1:36:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3656460c82936d7a666b873695801b5e94357907`
- High-level reason: Preserve a privacy-reviewed, hash-addressed #044 evidence
  package for the observed Scribe process CPU and memory incident while
  excluding raw transcripts, logs, environments, heaps, and databases.

## July 30, 2026 at 1:29:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8ac599eb20648cce53a0b0efba557dc890283d3c`
- High-level reason: Bound remote diagnostic delivery to one 256-event drain,
  preserve error, critical, and issue-linked evidence under pressure, and stop
  producing Instant mutations when the remote outbox is already saturated.

## July 30, 2026 at 1:26:26 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `adb538ddb20f4404f9d30946c0ed78b10391a9c7`
- High-level reason: Make Mac ScreenStream grant refresh, local LiveKit host
  ownership, relay teardown, and app-group handoff generation-safe across
  expiry and cancellation, with typed errors, credential redaction, focused
  reducer coverage, and a real local publisher/subscriber room join.

## July 30, 2026 at 1:12:24 PM EDT

- Repository: `instant-data-swift`
- Commit: `ac6ee60fb2b0435578138a22e8fbc798224a2d9a`
- High-level reason: Materialize deterministic large store snapshots by walking
  the existing entity and attribute index order instead of flattening and
  globally stable-sorting every triple, with a 50,000-entity sparse regression
  test shaped like Scribe diagnostics.

## July 30, 2026 at 12:43:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b7b30d033ed46f1900161e8360100d743761baae`
- High-level reason: Make Swift Issue success-evidence decoding preserve
  unfamiliar non-empty wire labels while retaining the current known values,
  so independent client schema evolution cannot make the entire issue catalog
  unreadable.

## July 30, 2026 at 12:10:27 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `427c2862827e0069e4b0cf743331d0c8cc7bb759`
- High-level reason: Keep the Swift Issue evidence wire values aligned with
  live Instant and Foldkit by adding Research and CodeReview, and preserve the
  user-supplied public IssueTrackerError screenshot as hashed issue evidence.

## July 30, 2026 at 11:48:54 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6f4c3a02c4da184c0564eb0ba74dda2d97482f07`
- High-level reason: Make the protected typed append-log command the explicit
  repository agent boundary and align its documentation and tracker skill with
  the committed required, optional, and success fields.

## July 30, 2026 at 11:45:18 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f512057408573691526b57458069ee41e392cecc`
- High-level reason: Preserve a privacy-reviewed installed-app baseline of 12
  screenshots, their 12 direct ASCII renderings, and three safe accessibility
  trees before the canonical Mac and cross-platform visual refactor.

## July 30, 2026 at 11:42:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `152b0e75c1b1360cd5f25fc8c2b1624361e9b224`
- High-level reason: Document the committed typed append-log JSON contract and
  clarify that scribe-issue-tracker owns lifecycle while
  instantdb-log-observer owns structured evidence emission and observation.

## July 30, 2026 at 11:34:25 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `03aad74a1e319f86a2437594861a57cfc851219e`
- High-level reason: Add a committed typed CLI for atomic issue-tagged log
  emission, with Swift-compatible payloads, canonical `logID` lookup support,
  ergonomic diagnostic path relationships, and shared RFC UUID-v5 link IDs.

## July 30, 2026 at 11:24:26 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `16bba15c9ad0ed926750dbc67e3e809e82453d40`
- High-level reason: Replace invalid composite Instant issue-link entity IDs
  with cross-language RFC 4122 UUID-v5 identities derived from the URL
  namespace and canonical log namespace, log ID, and issue ID path.

## July 30, 2026 at 8:19:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b02035d5b9d3f347ef3eb18d98fc4b354c7f334`
- High-level reason: Add a fail-closed standalone YouTube comment plugin with
  exact microphone grammar, explicit final confirmation, bounded unique
  transcript/audio provenance matching, scoped Google OAuth identity
  verification, and durable exactly-once publication receipts and audit.

## July 30, 2026 at 7:45:33 AM EDT

- Repository: `foldkit`
- Commit: `aa2417af07b6da5ec921cb3115b0569b2fc8e053`
- High-level reason: Correct Foldkit skill drift around Disclosure and scoped
  Effect Layers, and add a focused regression proving one Program can run as
  isolated simultaneous runtimes with independent state, evidence, Ports,
  resources, and shutdown.

## July 30, 2026 at 7:44:40 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ae4f941823a8e78a0d8ab8643458a1b42035dc81`
- High-level reason: Add default-on Apple performance diagnostics using
  MetricKit on macOS and iOS/iPadOS, with a bounded process-memory fallback on
  watchOS and privacy-filtered remote summaries.

## July 30, 2026 at 7:39:11 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `cfd923ad28421b623fc27160201f8d3a8fe7f280`
- High-level reason: Add discoverable Codex interface metadata for the typed
  realtime Scribe issue-tracker skill, validated by the official skill checker
  and a strict zero-finding skill audit.

## July 30, 2026 at 7:34:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7c354c67d75845780adc53c3b4600c1e40cc3de9`
- High-level reason: Prevent the generated Instant Issue `status` attribute
  path from being shadowed by a loop binding, eliminating the reproducible
  arm64 SIGBUS in filtered issue queries while preserving bounded server filters.

## July 30, 2026 at 7:34:02 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f9d93a6751f9522f19c2b51ca8f4281781e5be15`
- High-level reason: Add participant-attributed SharePlay transcription with
  mandatory confirmed alphanumeric display names, Apple message-source identity
  binding, bounded reliable replay, spoof-resistant contribution IDs, validated
  party timelines, and persistence through Scribe's existing recording path.

## July 30, 2026 at 7:29:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d70af8e8a56ac08c438fd48aec163c8392867fe3`
- High-level reason: Keep Apple speech and on-device language-model work on
  Scribe's standard local-first Instant room path so transcript and agent turns
  remain visible without internet while auth, sync, and enabled diagnostics
  continue retrying and catch up when connectivity returns.

## July 30, 2026 at 7:28:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `dd251fb15bdd588f9df862117523828a2bba52a2`
- High-level reason: Complete the typed realtime Instant issue cutover after
  exact reconciliation of all 45 legacy source documents, remove the Markdown
  catalog/import target, and route agent guidance, feedback intake, persistent
  corrections/preferences, log tagging, and source-path hypotheses through the CLI.

## July 30, 2026 at 7:25:32 AM EDT

- Repository: `foldkit`
- Commit: `5108dd1453fa99a446a3c9ef712b7528f6ec05db`
- High-level reason: Align Foldkit's portable issue and logging domains with the
  typed Instant tracker, infer issue tags at append time, persist server-queryable
  evidence links and path relationships, and render the selected issue's latest
  evidence through the same Program across the web runtime.

## July 30, 2026 at 7:21:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `54a0aa9613004a4141c850a2d20761ab504fc233`
- High-level reason: Add a typed YouTube comment plugin tool target and
  room-scoped stable tool identifiers while preserving global identifiers and
  shared recording-tool defaults, with focused contract tests.

## July 30, 2026 at 7:16:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d5cb4fd1321c4305551f5f4c6b78b72e4f884863`
- High-level reason: Add the guarded 2:17 a.m. macOS nightly bonsai runner,
  five-million-token goal, recent recording/log-aware bounded issue ranking,
  independent QA and Mac screenshot requirements, and brief measured-usage
  reporting.

## July 30, 2026 at 7:05:52 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `61c54fc52f6a558c476cdfbba0ced72f24375a09`
- High-level reason: Preserve a first-class `Planned` workflow state across the
  Swift issue model and typed Node CLI so structured library feature intake is
  not flattened during realtime Instant upsert.

## July 30, 2026 at 7:02:23 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4707a45f7be4559a2f050966a78998fa8798b154`
- High-level reason: Add the typed realtime Instant issue/guidance schema and
  structured JSON CLI with deterministic Swift/Node identities, merge-safe
  updates, evidence queries, public-read/admin-write permissions, and no
  Markdown parsing path.

## July 30, 2026 at 7:01:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `572373b8c54913322bd6dd0334eab206793d6889`
- High-level reason: Make structured logs tag issue mentions immediately,
  retain suspected/contributing/ruled-out source paths, and persist direct
  evidence links to the lightweight Instant issue viewer with legacy-read
  compatibility.

## July 30, 2026 at 6:59:48 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `55556b7045b4b278c044ca20ef3d316e63bf0827`
- High-level reason: Build recording-scoped Instant listener rooms, a
  standalone Mac stream-agent CLI, hidden passive responses, allow-listed TCA
  actions, explicit Apple system TTS, and a fully local Apple SpeechAnalyzer
  and Foundation Models intelligence mode.

## July 30, 2026 at 6:13:15 AM EDT

- Repository: `foldkit`
- Commit: `80c1969ade21ff69dc15fde3e43988f4c9f63ee1`
- High-level reason: Add and package a Foldkit-native companion skill family
  for composable architecture, Schema modeling, Effect dependencies, shared
  state, navigation, testing, views, and portable client hosts without
  importing the separate ts-pfw runtime contract.

## July 30, 2026 at 2:36:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3a2790751a38044636d79d0566b31ea0b0616cc5`
- High-level reason: Verify issue 001 with immutable before-and-after
  transcriber-selection evidence, independent QA, and a synchronized active
  issue queue.

## July 30, 2026 at 2:28:47 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f1064d4d27eeaa4e968b7f626fd12e464cd38e96`
- High-level reason: Freeze the selected transcriber identity at recording
  start so an unavailable Apple session cannot be mislabeled as Deepgram.

## July 30, 2026 at 2:15:55 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4f4b9070c790d86eebd5813394ed6428628f8263`
- High-level reason: Restore the iPhone and iPad transcriber Settings gear by
  moving it into the recording sidebar's rendered navigation toolbar while
  preserving root ownership of selection and the Settings sheet.

## July 30, 2026 at 2:05:07 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c01d263bdadacc457494bc115a8493aa1362d895`
- High-level reason: Claim issue 001 for current provider-selector verification,
  adopt the canonical success-criteria heading, and repair its malformed link
  to the original selector implementation commit.

## July 30, 2026 at 1:22:59 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c3300c2cd44d54ae5d891aca62d3042dda5d1725`
- High-level reason: Install the supplied Scribe artwork as the shared app icon
  for iPhone, iPad, App Clip, Mac, Apple Watch, Apple Vision Pro, and Apple TV,
  with platform-specific asset catalog variants validated by Apple's compiler.

## July 30, 2026 at 1:21:52 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b051d215230f8ba57ef8ade745e89f754af6955`
- High-level reason: Add portable and Markdown workflow states that distinguish
  partial implementation, missing verification, concrete feedback requests,
  fixes, and regressions; migrate issue 040 to `verification-needed` without
  discarding its completed implementation and passing criteria.

## July 30, 2026 at 12:15:20 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d2221439ef8220aa8c62acd96c239742bf7c99ca`
- High-level reason: Record the independent issue-040 QA verdict and return the
  P0 to open and unclaimed until non-manual literal press-and-hold evidence and
  fresh physical-iPad evidence exist for both new-window entry points.

## July 30, 2026 at 12:14:08 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d3ecabf26014e404196ca67f94f48f03d6b5f597`
- High-level reason: Add an accessible recording-window action and preserve
  Computer Use iPad simulator evidence proving route hydration and three
  concurrent Scribe scenes, while recording the literal long-press gesture and
  fresh physical-iPad verification as still outstanding.

## July 30, 2026 at 12:02:05 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c2d1c2737f9e65a71044deb6162d37f91e54f3f5`
- High-level reason: Add typed issue success criteria to the dependency-light
  Swift schema, align their encoded shape and legacy default with Foldkit, and
  prove lossless Instant payload persistence with focused tests.

## July 30, 2026 at 12:01:59 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1f1351782e247059a82f5e10a1148ad4dfe107ca`
- High-level reason: Limit default-on process-memory sampling to the requested
  initial iOS, iPadOS, and macOS platform set so shared Watch and visionOS hosts
  do not start performance instrumentation.

## July 29, 2026 at 11:58:01 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d08edbf96b717fa6350d28972f55908539de249c`
- High-level reason: Make process-memory diagnostics default-on with a one-time
  settings migration, then move collection and dedicated-store logging into a
  once-per-minute background single-flight path with focused self-overhead,
  main-thread, persistence, and collection-cost tests.

## July 29, 2026 at 11:50:27 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `caaee133d7a340f6a9327d78e78e41a5fa08bc29`
- High-level reason: Make Scribe complaint intake explicitly event-driven,
  require measurable success criteria and independent before/after QA, and
  return issue 042 to the open queue when physical behavior proof remains
  inconclusive.

## July 29, 2026 at 11:36:32 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `171661d329da41681112b57ca7ac4398c902460d`
- High-level reason: Add a default-off, device-local process-memory diagnostics
  setting, a dependency-controlled Darwin sampler, privacy-filtered active-scene
  logging, and focused settings and sampling tests so long-recording performance
  reports can be correlated with stable memory evidence.

## July 29, 2026 at 11:20:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f2509f88f2fdf6fdb7854384aaa82c0039c2b6d2`
- High-level reason: Enable the iOS multi-scene capability required for the
  existing identity-keyed SwiftUI recording-chat window actions to create real
  iPadOS windows, with a focused manifest regression test.

## July 29, 2026 at 11:18:05 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `eb075a69189184d7c6da037ff7b8468274f177ef`
- High-level reason: Preserve current-commit portrait and landscape,
  normal and full-screen visual evidence that the one-line transcript now
  starts at the top reading position, while retaining the physical iPhone
  interaction gap in the active issue.

## July 29, 2026 at 11:15:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `013238b344e54bec831b056986a4dc501ed8bfed`
- High-level reason: Preserve current clean physical deployment evidence for
  the active transcript-offset issue and attach a hashed iPad reproduction of
  repeated `Recording 001` titles without claiming unverified physical layout
  behavior or closing the recording-identity defect.

## July 29, 2026 at 11:14:35 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5b46d0bdeb4dc2f1847af5dd0cf84569a9c47b3a`
- High-level reason: Replace the lossy Mac bootstrap notification race with a
  latched default-store installation rendezvous so the resident screen-stream
  listener starts whether InstantDB becomes ready before or after AppKit launch.

## July 29, 2026 at 11:02:46 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8ee3ed92ccebbea1b07c4f194c8ec5bcc3569024`
- High-level reason: Extract the portable Swift issue and attachment wire
  contract into a dependency-light SPM leaf module, keep issue behavior and
  InstantDB transport in separate dependent targets, align the TypeScript
  Effect schema, and make complaint screenshots durable issue attachments.

## July 29, 2026 at 11:02:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3c3d07b99ac040b737a6d534dba90017d8ccd999`
- High-level reason: Give normal and full-screen short transcripts one shared
  top-leading layout policy so the first transcript row no longer sits near
  the bottom of an otherwise empty viewport.

## July 29, 2026 at 10:51:15 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `acf7d780016f85dc1e149d6a7d88422498ab1c02`
- High-level reason: Keep the Mac InstantDB screen-stream listener alive after
  its windows close, start LiveKit with the Mac's Tailscale address advertised
  to WebRTC peers, deliver room-scoped credentials without manual entry, and
  make an already-open receiver react to newly prepared sessions.

## July 29, 2026 at 8:39:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0763612e9eeede65118f0d52c2cc81b8c535dd7b`
- High-level reason: Add transport-independent Swift logging and issue domains,
  TCA dependency control, separate Instant adapters, lossless Markdown import,
  recurrence-based priority escalation, and explicit intake for the remaining
  transcript-offset, recording-title, and Settings requests.

## July 29, 2026 at 8:38:15 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `80f36d99bed857b83cef1e8fb9b9c82d4e6032c1`
- High-level reason: Keep portrait and landscape full-screen transcripts
  visible and wrapping beside a full local millisecond timestamp gutter, and
  close the thumbnail file-arrival lost-wakeup window that could defer a
  screenshot until later transcript activity.

## July 29, 2026 at 7:02:13 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `315e1a25b8570d19af87a003628f4193336e6568`
- High-level reason: Replace the forgotten-password custom build keychain with
  one-time command-line signing permissions on the existing login-keychain
  Apple Development keys, without storing a second password.

## July 29, 2026 at 6:45:59 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8b7f8a29e0887b011dbbf752383608283204f791`
- High-level reason: Make physical-device signing repeatable without Xcode by
  securely bootstrapping the isolated ScribeBuild keychain once, unlocking it
  from an encrypted login-Keychain credential, and selecting it explicitly for
  every deployment build.

## July 29, 2026 at 6:34:02 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3d8f9ad18965c5e8fe28c0e96417da4d14fc7756`
- High-level reason: Keep the shared passive-watcher controls buildable on
  watchOS with typed Picker bindings while preserving the existing Menu and
  rounded text-field presentation on supported platforms.

## July 29, 2026 at 6:30:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `37400396e68d6222e5b5fa241275a7662bef489d`
- High-level reason: Add accessible recording-bar and historical-chat actions
  that open recording-identity-keyed windows on iPadOS, macOS, and visionOS,
  backed by shared TCA state and focused platform-routing tests.

## July 29, 2026 at 6:15:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `df9e06ed78e5fdb0aa2d049cc5d95d839a086f6b`
- High-level reason: Enable installed Scribe builds to send privacy-filtered
  diagnostics to the dedicated Instant app by default, with a durable
  device-local Settings opt-out and live delivery gating. The shared-index
  commit also links the concurrent issue 035 watcher work.

## July 29, 2026 at 6:13:56 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a9ce1d8b6148c592c78028312fc879e9b1a5fb91`
- High-level reason: Add the smallest recording-scoped passive watcher with
  visible agent presence, persisted GPT target settings, stable transcript
  threads, terse offline responses, lifecycle controls, and focused tests.

## July 29, 2026 at 6:11:57 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `458e5154be773c1d411f60c88f219642b3274d58`
- High-level reason: Create and immediately claim issue 040 as P0 before
  implementation, with an identity-keyed recording-chat multiwindow contract
  for iPadOS, macOS, and visionOS.

## July 29, 2026 at 6:10:43 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5d4a9b36e63d47b19b7013b4c85973ec7f0f8037`
- High-level reason: Correct the public-sharing LaunchAgent to the installed
  Node path proven by a live loopback and Cloudflare-hosted health check.

## July 29, 2026 at 6:10:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5d38fbddb474e75960352a2e483c8134618e2097`
- High-level reason: Consolidate build provenance and speech-provider controls
  into Settings and adapt the recording surface for wide iPad layouts with
  focused presentation and layout tests.

## July 29, 2026 at 6:08:52 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e1c086c350dcb58a88728c449fc219ed81a9bc46`
- High-level reason: Add a local-first public segment and X publishing
  prototype with bounded audio export, explicit approval gates, PKCE Keychain
  authorization, unenumerable serving, recoverable revocation, and focused
  dry-run and duplicate-suppression tests.

## July 29, 2026 at 6:03:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `65b4a43e2575529df1ee1dc8dd47c897b0150b6a`
- High-level reason: Require canonical agent claimants in issue metadata,
  append-only claim history, and atomic claim-before-implementation workflow.

## July 29, 2026 at 6:02:57 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a205bd1f54f9e76098256a05c2173b3d32d63c70`
- High-level reason: Capture the reproduced incremental-copy failure and a
  bounded ChatGPT audio-handoff investigation, specify the full local
  millisecond gutter contract, and make foreground-independent hands-free
  watching explicit without displacing higher-priority capture work.

## July 29, 2026 at 5:56:45 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ffb4153c0f09bcfbddcf9937c600e2d18f0ed66c`
- High-level reason: Clarify immediate screenshot visibility, scroll-to-bottom,
  full-screen iPhone text overflow, and SyncUps branch-discovery requirements;
  prove that the installed physical-iPad app generated local logs while its
  environment-gated remote destination remained unconfigured; and track that
  observability defect as a P1 prerequisite.

## July 29, 2026 at 5:54:36 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `59a33eada1012e6cd3dd779b30b1e8a91b6e6c90`
- High-level reason: Correct the screenshot symptom to measurable
  capture-to-chat visibility latency, preserve Settings and iPad layout as
  active requests, and separate the first passive room/thread watcher
  prototype from deferred public audio-segment publishing.

## July 29, 2026 at 5:50:55 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `35a70e904af6116eed562f14849103e4efe29131`
- High-level reason: Fetch and inspect the physical-iPad feedback screenshots;
  preserve the stale remote-log boundary; split screenshot latency, in-app
  ReplayKit access, Settings consolidation, and SyncUps toolbar reuse into
  prioritized backlog items; and update recurring layout issues without
  displacing capture, continuity, and identity priorities.

## July 29, 2026 at 5:50:21 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `598ad5f4a55fe364a023472b45f33d38f95425dc`
- High-level reason: Record clean physical-iPad build, install, launch, process,
  provider, transcript, and plugged-in microphone evidence; preserve
  interaction-dependent acceptance gaps; and track the newly observed unused
  iPad display area without assuming its windowing cause.

## July 29, 2026 at 5:41:07 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `028b55c651dd102d01fc5bf260b6077f41ba8d4d`
- High-level reason: Tie prioritized local issues to their immutable
  addressing commits, update exact status timestamps and evidence-backed
  acceptance, and preserve the remaining physical-device and speech-reconnect
  boundaries.

## July 29, 2026 at 5:39:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `00cb4a3a7422f5978d106fbc29aa2b4c5692e199`
- High-level reason: Catch up active recording duration from wall time after
  scheduler suspension, preserve hidden active-recording routing through
  compact navigation, and cover the surrounding timer and health behavior
  without claiming speech transport reconnection.

## July 29, 2026 at 5:39:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4ea4e28c832f95aa64c73ae33fab83b8f713bd0e`
- High-level reason: Expose privacy-safe account, device, and authoritative
  recording identity on iPhone and iPad while keeping raw identifiers, email,
  recording titles, and tokens out of diagnostic metadata.

## July 29, 2026 at 5:23:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2bfdf7603881be0ff630372082162992331e2fe7`
- High-level reason: Bound automatic physical-device-to-Mac screen-stream
  requests, Mac claims, and LiveKit preparation with typed recovery, stale
  attempt cleanup, sanitized diagnostics, 21 focused tests, and a real
  Mac-local publisher/subscriber token join.

## July 29, 2026 at 5:23:20 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b36c8b8fee2ec3362363561065ce66615ac0f34d`
- High-level reason: Expose the next or active recording provider on iPhone and
  iPad, permit device-local selection before recording, explain active-session
  locking, and keep the compact picker explicit and accessible.

## July 29, 2026 at 5:19:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d33e1c00d0a9afe66743317eb7ceea4ba3be9aa2`
- High-level reason: Detect two seconds of exact-zero physical-device
  microphone PCM before any real signal, preserve active route evidence, stop
  the false live pipeline, and present an actionable retry with focused
  teardown and diagnostic coverage.

## July 29, 2026 at 5:19:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9ceb673ca9e933affc9c21a6a94709a81a0edfd5`
- High-level reason: Version the reusable Scribe feedback-intake skill with
  physical-device recording/media retrieval, non-overwrite defaults, fresh-log
  chronology, parser tests, prioritized issue intake, and immutable
  addressing/fixing commit links.

## July 29, 2026 at 5:19:30 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `dab216bbf646355db4fea33d8e3f0a11c80aaa97`
- High-level reason: Rank the physical-device backlog, add exact issue
  timestamps and P0-P4 priorities, preserve the all-zero iPad evidence and
  lower-priority map direction, and require commit-linked work logs.

## July 29, 2026 at 4:55:56 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a37c740ee45d9067b64dbddbec0a798a216d2db3`
- High-level reason: Separate 25 physical-device feedback items into
  independently actionable local issues with transcript evidence, acceptance
  criteria, cross-links, an indexed lifecycle, and confirmed-working
  observations preserved as constraints.

## July 29, 2026 at 2:43:34 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b333e6d37d071ad5f9ff0d37d5e26e648f456cab`
- High-level reason: Generate destination-aware iOS, Watch, and Apple TV
  schemes from the tracked XcodeGen source of truth, match the App Clip to its
  iPhone-and-iPad container, and make stable deployment regenerate the ignored
  Xcode project before building.

## July 29, 2026 at 2:13:57 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `54a596c0e3177985f35bbdd69367c41793d341b5`
- High-level reason: Restore repository-owned, destination-aware shared Xcode
  schemes for the iOS, Watch, and Apple TV products and return the stable
  installer to scheme builds with isolated derived data and regression
  coverage for each scheme's target identity.

## July 29, 2026 at 2:01:41 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0945c66a7d841bcc3f8d29ae438e6a6be661d0cc`
- High-level reason: Keep direct iOS and Watch target builds isolated with
  target-compatible product and intermediate roots while retaining
  derived-data isolation for the Apple TV shared scheme.

## July 29, 2026 at 1:56:40 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a1ffc654b500a2fe2253401deaa8ebbfdcf13ee2`
- High-level reason: Build the iOS and Watch deployment products through their
  concrete Xcode targets while retaining the verified shared scheme for Apple
  TV, with regression coverage for the target-versus-scheme contract.

## July 29, 2026 at 1:42:48 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `02677bb3328cc7813c28bec07bd875b932f847d5`
- High-level reason: Pin stable Scribe builds to exact published
  `instant-data-swift` and Point-Free `swift-sharing` releases, preserve a
  no-worktree editable-package workflow, and embed and verify dependency
  revisions alongside the Scribe commit.

## July 29, 2026 at 1:30:07 PM EDT

- Repository: `instant-data-swift`
- Commit: `2b2517e256351f7e82286424aa83b4055b7e174c`
- High-level reason: Make the published SwiftPM package self-contained by
  removing reference-only Git submodules, preserving their optional local
  checkout pins in documentation, and adding a publication-surface check.

## July 29, 2026 at 1:20:15 PM EDT

- Repository: `instant-data-swift`
- Commit: `0584ffb6c1488461e5d52081f5c88412e4cb82d5`
- High-level reason: Reconcile every current Instant and cross-repository SHA
  reference with the verified technoplato identity-rewrite maps while
  preserving external revisions and non-reference content.

## July 29, 2026 at 1:19:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5709f8b367d6496a69c35bab67b68165e1e82db8`
- High-level reason: Reconcile every current Scribe SHA reference with the
  verified technoplato identity-rewrite map while preserving external hashes
  and non-reference content.

## July 29, 2026 at 10:39:55 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3d4d539ac3f684f3f0a44881e426eb3a2232572f`
- High-level reason: Clean SwiftPM outputs before generating Mac build
  provenance so the installed app compiles the current clean commit and build
  timestamp instead of reusing a stale generated build-info object.

## July 29, 2026 at 10:36:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `32d79ef6c36ae62c2717ef919048e44f1839ebff`
- High-level reason: Apply the bundle-relative framework runtime path to the
  installed Mac executable rather than the already-copied SwiftPM build
  product, with a focused installer-wiring regression check.

## July 29, 2026 at 10:35:32 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `52e9c3735efae986eb72c18a942c16540d95de0f`
- High-level reason: Add the bundle-relative framework runtime search path to
  the installed macOS executable so dyld can load the packaged LiveKit
  frameworks before Scribe startup.

## July 29, 2026 at 10:33:08 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `01adc38e97710b592b4b49108abf1cdf7600d151`
- High-level reason: Package top-level SwiftPM runtime frameworks in the
  installed macOS wrapper so the LiveKit-enabled Scribe host can launch instead
  of aborting in dyld before startup.

## July 29, 2026 at 10:08:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2b43cce1457381385ec0d4f184b63eb70f8f7418`
- High-level reason: Make selective clean deployment reliable for unblocked
  targets, recognize provenance in Xcode Debug dylibs, and restore the shared
  recording and screen-stream settings views to a successful tvOS build.

## July 29, 2026 at 9:47:46 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c5616c4fab6c94cea8c9b9976b0029161f7d9673`
- High-level reason: Build, verify, install, and launch one clean Scribe commit
  across the Mac and every discoverable iPhone, Apple Watch, iPad, and Apple TV,
  with explicit simulator fallbacks and per-target deployment results.

## July 28, 2026 at 10:27:21 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1a5b6aa5305e204bfb11938b1a3ef6022cf59448`
- High-level reason: Run the InstantDB screen-stream watcher and automatic
  LiveKit receiver window in the stable signed Finder-installed Mac app while
  preserving its existing bundle identity and Keychain continuity.

## July 28, 2026 at 10:24:00 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8fa185553320b4f184ce3add50d320e29cf513ae`
- High-level reason: Automate phone-requested screen streams through an
  InstantDB control plane, Mac-hosted LiveKit room-scoped credentials, and a
  guarded OBS-to-unlisted-YouTube relay with automatic receiver setup.

## July 28, 2026 at 9:23:31 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2e81885ca2959f96f72a10edda057a9e37e28c38`
- High-level reason: Keep live-screen stream configuration reachable from the
  active recording menu so the publisher endpoint and token can be set before
  starting the ReplayKit broadcast.

## July 28, 2026 at 9:11:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `c409dec45ced0cc878120e7dc2b496132d76c31c`
- High-level reason: Stream ReplayKit screen video and app audio from iPhone
  through LiveKit WebRTC to a dedicated Mac receiver while preserving the
  existing transcription and periodic screen-image handoff paths.

## July 28, 2026 at 8:28:02 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `01b725112d94f44f2ddc60d7a185e6b46f73e796`
- High-level reason: Keep the live bottom margin proportional in extremely
  short landscape transcript viewports instead of allowing its minimum clamp
  to push all current text off screen.

## July 28, 2026 at 8:24:11 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7449acde8cd8f51ab3985654483d1940740e68bd`
- High-level reason: Re-anchor a following live transcript after viewport-size
  changes so rotation and window resizing keep the newest line on its lower
  reading line.

## July 28, 2026 at 8:13:24 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `fd761a5d44418089fe9f4b31ea85e947cc697055`
- High-level reason: Give short live transcripts a viewport-aware minimum
  content height so the newest line reaches the same lower-screen reading
  position as long scrolling transcripts.

## July 28, 2026 at 8:10:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7257748cb1d57a6bf44f24e00de9c7217ab0073b`
- High-level reason: Show a satellite uplink icon on the recording page's
  native ReplayKit broadcast launcher while keeping periodic screen-frame
  attachments as a separate opt-in control.

## July 28, 2026 at 8:00:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `beef03a956d52b659510323ed1e24c05cc051f75`
- High-level reason: Add bounded transcript voice commands and a bottom-pinned
  full-screen reader, disable all automatic heart-rate workout consumption,
  document the guest App Clip path, and expose the supported CarPlay surfaces.

## July 27, 2026 at 8:49:00 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8459e4953799876dd978c41bdf32a929ee54e058`
- High-level reason: Add a minimal recording App Clip that creates or reuses an
  Instant guest session, uploads a finalized M4A, waits for server
  acknowledgement before showing Saved, and preserves failed drafts for retry.

## July 27, 2026 at 7:20:14 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ff00831ceb314e58d48aa7652ec3295bbb334807`
- High-level reason: Remove the redundant speech-provider icon from the Home
  recording control and constrain the live transcript to a vertical,
  viewport-width scroll surface so horizontal swipes cannot shift the text.

## July 27, 2026 at 6:24:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9fd2a6373354ff252b1bea19fce35b2bf1b7f19f`
- High-level reason: Add runtime-selectable Apple Speech Analyzer transcription
  with on-device model preparation, time-indexed progressive results, explicit
  finalization, visible device-local provider controls, and an immutable
  Deepgram-or-Apple choice for each active microphone and system-audio session.

## July 27, 2026 at 4:20:15 PM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `2fea96e53b5981071dc9761ed10b7d0a8a9497f5`
- High-level reason: Keep live Watch heart-rate samples associated with the
  requesting iPhone recording, bound the relay, replace indefinite waiting
  with an actionable timeout, and expose the full recovery message.

## July 27, 2026 at 4:06:21 PM EDT

- Repository: `instant-data-swift`
- Commit: `598ec0b2459e83aef66d13ad3480410f51c29f52`
- High-level reason: Remove repeated full-snapshot sorting from optimistic
  live-data rebases after physical iPhone and Apple Watch CPU reports
  identified it as the shared recording-freeze hot path.

## July 27, 2026 at 2:14:01 PM EDT

- Repository: `instant-data-swift`
- Commit: `4f077bc71c4e81a73850cb866f5b17619b430c90`
- High-level reason: Preserve the repeated clean current-head signing result,
  ready Watch state, and protected-log freshness boundary without presenting
  compilation as installation or runtime acceptance.

## July 27, 2026 at 2:00:16 PM EDT

- Repository: `instant-data-swift`
- Commit: `10ad6819c0d8cf321c80e8289f32ed27f9111ef0`
- High-level reason: Reconcile the cross-repository audit with the final
  server-acknowledged delivery fix, full suites, clean six-lane performance
  evidence, and the exact unsigned-versus-signed physical Watch boundary.

## July 27, 2026 at 1:55:54 PM EDT

- Repository: `instant-data-swift`
- Commit: `981427972ac338838f08706ed161eb855ac8016d`
- High-level reason: Availability-gate the Duration-based live delivery waiter
  so InstantSwiftData continues compiling for its iOS 15 and watchOS 8 package
  deployment targets while newer Scribe targets use the explicit server-ack
  boundary.

## July 27, 2026 at 1:43:44 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `864f541483087f65af50a45d27c9872f49ec4a9a`
- High-level reason: Make explicit logger and replay durability boundaries wait
  for actual Instant server acknowledgement instead of invoking a local
  mutation transport that could remove outbox work before remote observation.

## July 27, 2026 at 1:42:48 PM EDT

- Repository: `instant-data-swift`
- Commit: `27b65349097e233b434100654693ccb543d34e93`
- High-level reason: Wait for actual live server acknowledgement without
  locally confirming the durable outbox, and preserve causally required older
  scalar writes during ordered replay while continuing to filter isolated
  stale retries.

## July 27, 2026 at 1:20:59 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `db7f808e143623b7407bec20ed7682104b2b5f4f`
- High-level reason: Carry Deepgram finalization acknowledgements through the
  transcript stream and hold stop persistence behind a reducer-owned,
  five-second-bounded provider acknowledgement so the final transcript cannot
  be discarded by the former fixed 500 ms delay.

## July 27, 2026 at 1:05:33 PM EDT

- Repository: `instant-data-swift`
- Commit: `36e871c147e4040f105de408e66c6a2e81baea95`
- High-level reason: Reject stale live-refresh writes atomically, preserve
  migration and relaunch ownership boundaries, normalize duplicate canonical
  query computations with final-result-wins semantics, and serialize live
  registration with durable pruning.

## July 27, 2026 at 1:02:29 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `94cfd243650ed34c27104e0c5f97ad9c7ee91a92`
- High-level reason: Keep the live Apple Watch BPM and exact failure reason
  visible outside the compressed iPhone recording toolbar, and let the active
  recording retry the dependency-controlled heart-rate session without showing
  a stale sample.

## July 27, 2026 at 12:55:33 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `634240a53a142283069899f24cffa4fad1d2cb4c`
- High-level reason: Bound diagnostic action-key extraction to known TCA enum
  wrappers so payload cases cannot replace the real leaf action or trigger an
  unbounded CustomDump traversal; refresh the committed heart-rate snapshot and
  restore the 466-test Scribe suite.

## July 27, 2026 at 12:39:15 PM EDT

- Repository: `instant-data-swift`
- Commit: `6386abc892aa0ef8516b9dd283efb59c57200a26`
- High-level reason: Apply Reactor-aligned age, entry, and owned-triple bounds
  to durable live query results; preserve active and optimistic owners; and
  transactionally collect only global triples whose final semantic owner is
  gone.

## July 27, 2026 at 12:28:17 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8c397aa1d8b34f1d1aa8880b48b2d579e82390c4`
- High-level reason: Model simulator heart-rate streams behind the Point-Free
  dependency boundary with controlled clocks and dates while preserving the
  live HealthKit and WatchConnectivity dependency on physical devices.

## July 27, 2026 at 12:27:31 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8ba9e9b5d45f16c0b51cbe78482c202b4541ab05`
- High-level reason: Make iPhone and Watch transcript sections seekable, keep
  Watch playback following the active section, configure spoken-audio output,
  expose the active route, and peak-normalize unusually quiet PCM for playback.

## July 27, 2026 at 12:26:49 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b993378751a6b51d7ef4deb437729826bbfe1723`
- High-level reason: Make the Watch converge on a late-arriving paired-iPhone
  account session, automatically page the full recording library, expose its
  exact total, and remove the Watch-only eight-recording display cap.

## July 27, 2026 at 12:10:19 PM EDT

- Repository: `instant-data-swift`
- Commit: `cb1b7217f4d366fd548651e416c31b8cbea91b8f`
- High-level reason: Persist canonical live-query triples and page information
  atomically with server refreshes, restore ownership across relaunch, and
  retract only rows no longer owned by any durable query.

## July 27, 2026 at 12:08:06 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `52bab8e7605a67501d349ab67ae45199e1096097`
- High-level reason: Add strict live Apple Watch heart-rate measurement to
  active recordings using an acknowledged WatchConnectivity control channel,
  a HealthKit workout session, fresh-sample enforcement, and recording UI on
  both the Watch and paired iPhone.

## July 27, 2026 at 12:01:58 PM EDT

- Repository: `instant-data-swift`
- Commit: `c5667b402dffd792622b24b21955dbf50a74eaaa`
- High-level reason: Replace the unbounded live infinite-query subscription
  with limited starter, forward, and reverse cursor chunks; atomically apply
  authoritative page windows; freeze loaded intervals; preserve local-first
  starter rows; and cancel every replaced or final Reactor registration.

## July 27, 2026 at 11:51:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `96eaa15643c6d1c09f84eff7e71099b421533acc`
- High-level reason: Select direct Deepgram for physical-Watch production
  transcription so transient paired-phone reachability cannot terminate live
  PCM delivery, while preserving WatchConnectivity only for asynchronous
  companion responsibilities such as Instant identity bootstrap.

## July 27, 2026 at 11:35:59 AM EDT

- Repository: `instant-data-swift`
- Commit: `0b3183e1f45ccf870f44d35a31bde3714696da69`
- High-level reason: Record the accepted private opaque-cursor design, exact
  before/after pagination flow, local-cursor safety boundary, and remaining
  continuous page-info and bounded infinite-query ownership follow-up.

## July 27, 2026 at 11:34:56 AM EDT

- Repository: `instant-data-swift`
- Commit: `2c2117ae0ca1e84eab8b422b51629919815bf259`
- High-level reason: Preserve canonical live query page information and opaque
  Reactor cursors through decoding, persistence, one-shot materialization, and
  exact after/before re-encoding so bounded remote pagination can use server
  frontiers without reconstructing lossy client cursors.

## July 27, 2026 at 11:21:38 AM EDT

- Repository: `instant-data-swift`
- Commit: `c429e815bb0be013b76db96228a503bec7ac37bd`
- High-level reason: Expose the library-owned composite fetch request directly
  to actors and TCA effects, preserving the same transformed load,
  `combineLatest` observation, error, and cancellation behavior used by
  `@Fetch` without requiring wrapper state.

## July 27, 2026 at 11:12:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `cdd1f3e2fafed31e86a10f8cb3e7fe25116a1c19`
- High-level reason: Preserve the clean signed production Watch build,
  successful physical installation and launch, settled passive UI evidence,
  runtime-only Deepgram override handling, and the remaining spoken-production
  acceptance boundary in the durable Watch transcription guide.

## July 27, 2026 at 11:08:30 AM EDT

- Repository: `instant-data-swift`
- Commit: `931d4f39d5a252e636252e981433e70869401c3f`
- High-level reason: Record that the clean production `ScribeSharedWatch`
  generic build now compiles and signs for arm64/arm64_32 with strict code-sign
  verification, while preserving install and live production acceptance as
  separate remaining device work.

## July 27, 2026 at 11:02:29 AM EDT

- Repository: `instant-data-swift`
- Commit: `9ce8dccda4c67b17a7d0e3d6c7ceabe85730d431`
- High-level reason: Reconcile the durable audit with the complete physical
  Watch PCM/WAV/Deepgram/final-transcript proof, the production audio-policy
  port and watchOS build, the 447-test Scribe suite, and the remaining signed
  deployment, persistence, reliability-soak, and ReplayKit boundaries.

## July 27, 2026 at 10:58:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ac50d0d2603e4c45f7964e55ebfd74f801d6cde3`
- High-level reason: Carry the recording-compatible Watch audio-session policy
  proven by the physical Deepgram probe into the production transcription
  path, preserve TCA ordering invariants, and document the evidence and
  operational acceptance procedure.

## July 27, 2026 at 10:45:54 AM EDT

- Repository: `instant-data-swift`
- Commit: `f742678c8c0f51884e78eb9061a15c91c79615f1`
- High-level reason: Record the Watch auto-run readiness fix and the final
  clean Scribe package verification of 446 tests across 47 suites.

## July 27, 2026 at 10:44:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7cabc1aad2beddd3f2f1c0f81f3572711e7dd21f`
- High-level reason: Preserve proof that blocked remote diagnostics do not
  block local credential persistence while replacing scheduler-yield sampling
  with a bounded monotonic evidence window under parallel-suite load.

## July 27, 2026 at 10:43:16 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1c5500a51b78c7c4b87ad71dd93e72648e75dcfc`
- High-level reason: Start the Watch probe's eight-second auto-run window only
  after capture, WAV append, and Deepgram streaming report active, so physical
  startup latency cannot consume the diagnostic recording window.

## July 27, 2026 at 10:40:47 AM EDT

- Repository: `instant-data-swift`
- Commit: `d8f5c2219f3751993a517e708ebeff4bf1992be7`
- High-level reason: Reconcile the final audit with the Watch probe's
  recording-compatible asynchronous activation policy and the authoritative
  Scribe package, performance-safety, and artifact-sanitization evidence.

## July 27, 2026 at 10:40:18 AM EDT

- Repository: `instant-data-swift`
- Commit: `0e2dc17922dc276630601e4e27fa88d77c2d53ab`
- High-level reason: Preserve exact final suite totals and distinguish the
  physical Watch build/install/launch/prepared evidence from the remaining
  human recording and ReplayKit broadcast acceptance interactions.

## July 27, 2026 at 10:33:55 AM EDT

- Repository: `instant-data-swift`
- Commit: `10f685d52705c14d01266c36df9b64feaab19c31`
- High-level reason: Give nonblocking utility-priority startup cookie sync a
  five-second wall-clock evidence window under parallel-suite load while
  preserving its exact request and retention assertions.

## July 27, 2026 at 10:31:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `18d54937308fcf140192f1d4ec0ccd89284d5acb`
- High-level reason: Keep the physical Apple Watch microphone session on the
  recording-compatible default route policy while retaining asynchronous
  activation required before opening its Deepgram WebSocket.

## July 27, 2026 at 10:30:34 AM EDT

- Repository: `instant-data-swift`
- Commit: `ef9eebdb2b96444b8db4ba61c797f33ac935f687`
- High-level reason: Wait for all automatic composite-fetch observations with
  a bounded condition before asserting recorder totals, preserving exact
  observation coverage without sampling asynchronous task registration.

## July 27, 2026 at 10:29:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f14b1049365dc91195c136c00a0c33109a0eb18b`
- High-level reason: Show the reproducible-build timestamp prominently on the
  Apple Watch audio probe so the installed diagnostic binary can be identified
  directly from its screen.

## July 27, 2026 at 10:26:14 AM EDT

- Repository: `instant-data-swift`
- Commit: `c238c4e7ae29154f46f923e4c7bd1eb3a01bbc65`
- High-level reason: Remove a race-prone assertion about the transient state of
  intentional live-transport auto-connect while retaining explicit WebSocket,
  connect-opened, and close-closed behavior checks.

## July 27, 2026 at 10:23:13 AM EDT

- Repository: `instant-data-swift`
- Commit: `83939c376899f6fe2b30e5c6789f2482b3f034e2`
- High-level reason: Make composite fetch fixtures independent of concurrent
  task order and prevent a load-only assertion from racing an empty automatic
  observation during the full parallel suite.

## July 27, 2026 at 10:18:42 AM EDT

- Repository: `instant-data-swift`
- Commit: `1657fba57650f1fdf4c84343ee93ef48f19120f0`
- High-level reason: Keep synthetic relaunch and migration fixtures inside the
  production cache-retention window and document the lock protecting the
  pruning cadence's unchecked `Sendable` state.

## July 27, 2026 at 10:14:50 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ee8a81d542ac62dce6268862a3d1dd013fa6b874`
- High-level reason: Reuse the already bootstrapped live Instant runtime for
  Scribe's read-only local projections, eliminating the second SQLite runtime
  while retaining live freshness semantics for ordinary one-shot queries.

## July 27, 2026 at 10:14:43 AM EDT

- Repository: `instant-data-swift`
- Commit: `0a1129fa639a416a57ce262e3be7b0a18a0f4935`
- High-level reason: Correct the deterministic offline-relaunch benchmark to
  the measured 11-hop contract after bootstrap pruning was integrated into the
  existing persistence actor call rather than adding a new hop.

## July 27, 2026 at 10:13:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `b7fc41134b068cb6fdaa19fd0db70091a72d353c`
- High-level reason: Authorize the physical Apple Watch recording session for
  long-form audio streaming and configure its Deepgram WebSocket to surface
  connection failures immediately on constrained or expensive networks.

## July 27, 2026 at 10:13:01 AM EDT

- Repository: `instant-data-swift`
- Commit: `d1066e817f5048abfd8eb5746eddf41b7edf3538`
- High-level reason: Prune persisted query cache rows at bootstrap and then
  every 64 successful cache writes, preserving active observations without
  adding retention work to every one-shot query.

## July 27, 2026 at 10:05:15 AM EDT

- Repository: `instant-data-swift`
- Commit: `96cc06864fe7928a3609ac3388a63451aa4a2cb1`
- High-level reason: Derive an injectable read-only local client facet from an
  existing runtime so composition roots can use ordinary query APIs over local
  state without a second SQLite bootstrap or a public `queryLocal` method.

## July 27, 2026 at 10:03:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `94cd84a7c2beae28070539c3c1bd458d4eddd736`
- High-level reason: Route Scribe's explicitly local projection loaders through
  an injected local-only Instant client sharing the live client's SQLite file,
  avoiding server acknowledgement waits without exposing `queryLocal`.

## July 27, 2026 at 9:59:16 AM EDT

- Repository: `instant-data-swift`
- Commit: `b812a2c3a1b13d0d3e90b927a1b4232afd80be7e`
- High-level reason: Avoid re-materializing flat query observers in namespaces
  untouched by a commit while preserving conservative invalidation for
  relationship paths, includes, schema changes, and unresolved entities.

## July 27, 2026 at 9:56:00 AM EDT

- Repository: `instant-data-swift`
- Commit: `a488b43452ceaf2c620775737b99a9cca0d08468`
- High-level reason: Invoke the Reactor-compatible query-cache retention policy
  after production one-shot writes, preserving active observation keys while
  bounding unloaded rows by age, count, and encoded size.

## July 27, 2026 at 9:48:11 AM EDT

- Repository: `instant-data-swift`
- Commit: `870a4083e2eb895c776bc2634e0f69a4b3de6cb6`
- High-level reason: Decode cardinality-one entity snapshot fields through
  schema-owned typed attribute paths, with centralized wire semantics and
  explicit namespace mismatch validation.

## July 27, 2026 at 9:45:23 AM EDT

- Repository: `instant-data-swift`
- Commit: `e965771ebe8b9bdb69a4fe4d96014ab0114e98dd`
- High-level reason: Add a dependency-controlled zero-argument typed ID
  initializer with canonical lowercase formatting, while preserving raw-value
  identity and keeping the core module independent of Dependencies.

## July 27, 2026 at 9:43:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `09e1c4c4afdc2dc679a307e300fb542ca0c6227c`
- High-level reason: Preserve the bootstrapped Instant diagnostic logger across
  the iPhone WatchConnectivity speech relay so Watch audio, Deepgram send, and
  transcript timing checkpoints reach the canonical remote log.

## July 27, 2026 at 9:42:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `84c41625ccf2494839ebecedaf7b4e205c003e00`
- High-level reason: Serialize live recording snapshot saves and deletes through
  a bounded tail-task coordinator so overlapping reducer effects cannot finish
  persistence mutations out of submission order.

## July 27, 2026 at 9:38:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a43a126035c07eaaa4437c54c76ec9b462302f60`
- High-level reason: Keep cumulative transcript text out of live persistence
  transactions while retaining normalized segment and word delivery, then
  explicitly write the complete fallback string during finalization.

## July 27, 2026 at 9:32:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2a6a44c1146ec35023322b54961b4488204deb0a`
- High-level reason: Structurally redact benchmark credentials before
  performance reports reach disk and provide an atomic sanitizer with hash
  provenance for existing ignored artifacts.

## July 27, 2026 at 9:29:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4a30f633912945d5cf01110370c0aa163494f996`
- High-level reason: Correlate transcript source attribution with the audio
  frames actually sent under each context and use the exact `System Audio`
  fallback whenever reliable application metadata is unavailable.

## July 27, 2026 at 9:29:36 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5e3d1c13f278c856688bfeef91dd936802e8d6ce`
- High-level reason: Load generator-produced, Git-ignored provenance into the
  SwiftPM build plugin and reject stale commits, mismatched source roots, or
  dirty worktrees before compiling reproducible build metadata.

## July 27, 2026 at 9:27:54 AM EDT

- Repository: `instant-data-swift`
- Commit: `657a74a16e5347c729d94fcc68ceaad60875e4ba`
- High-level reason: Persist only an unencodable mutation as failed, keep the
  shared live connection open, and continue sending healthy mutations behind
  it instead of poisoning every delivery attempt.

## July 27, 2026 at 9:22:10 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `02f8a08109e321e86e3b4f4e894b1bd98459f7e2`
- High-level reason: Embed clean-build commit, branch, dirty state, timestamps,
  host, source root, artifact location, configuration, platform, and
  architecture in the standalone Watch audio probe's structured startup log.

## July 27, 2026 at 9:21:59 AM EDT

- Repository: `instant-data-swift`
- Commit: `43b65eeffafff3b6a54ea8caf8943a329901ab95`
- High-level reason: Assign monotonic implicit outbox timestamps so mutations
  created in the same millisecond retain insertion order across persistence and
  relaunch without changing deliberately supplied domain timestamps.

## July 27, 2026 at 9:18:04 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d4beb51ad6f3c9c59bea3df0ea319f7a238c7cdf`
- High-level reason: Wait for the asynchronously enqueued WebSocket timeout
  diagnostic before asserting it, removing a scheduler-dependent suite flake.

## July 27, 2026 at 9:17:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0d107b482fa1eb003c34d757e8d29b3c3f9d9aac`
- High-level reason: Retain only the newest 4,096 Watch relay chunk timings in a
  circular buffer and avoid false latency attribution after older timings are
  evicted.

## July 27, 2026 at 9:16:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3a04ad40185a8590e8777c0dd2a691d3ab8dad2a`
- High-level reason: Require explicit process opt-in before structured
  diagnostics can use the dedicated remote Instant app, while preserving local
  diagnostics by default.

## July 27, 2026 at 9:14:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4f6c9a9eb463eb8fe94195c55260715aab3972b8`
- High-level reason: Restore a saved Watch credential through the phone relay,
  persist validated replacements on the phone, inject relay credential sources
  explicitly, and keep remote diagnostics off the credential critical path.

## July 27, 2026 at 9:14:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7ec2bddb6c2971d0315858c58f5bc836a1b73461`
- High-level reason: Attach build provenance to structured diagnostics, record
  startup milestones locally, and preserve a privacy-safe local checkpoint when
  a remote diagnostic write fails.

## July 27, 2026 at 9:12:06 AM EDT

- Repository: `instant-data-swift`
- Commit: `fdd4c1e399f02e7e30ae967aa8b18d8fffdfc0e2`
- High-level reason: Reference-count shared live-room registrations so one
  observer leaving cannot tear down the server room while another observer is
  still consuming it.

## July 27, 2026 at 9:07:41 AM EDT

- Repository: `instant-data-swift`
- Commit: `d2b1e5c0f27a2b161f7d3346a9bdb7ae4058992a`
- High-level reason: Make automatic fetch observation generation-aware so a
  canceled or stale observer cannot supersede a newer explicit projected-value
  task and surface a spurious `CancellationError`.

## July 27, 2026 at 9:04:28 AM EDT

- Repository: `instant-data-swift`
- Commit: `62eb6067d032271c2f805dc8543543eba8b3dede`
- High-level reason: Make ordering parity fixtures use genuinely later edit
  timestamps and prove the complete local order before validating the
  infinite-query window.

## July 27, 2026 at 9:04:08 AM EDT

- Repository: `instant-data-swift`
- Commit: `8f43f3f5258da82f5d788abe854914a49450fba1`
- High-level reason: Rebase remaining optimistic mutations above the current
  server snapshot so later local writes stay visible after an earlier server
  confirmation, matching upstream Reactor overlay semantics.

## July 27, 2026 at 8:56:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `bfa8bc07aa607b0e6a33e6f02cb57420bbd0c1d8`
- High-level reason: Adopt the intent-ledger workflow and install reusable
  change-recording and reproducible-build provenance helpers in Scribe.

## July 27, 2026 at 8:55:43 AM EDT

- Repository: `instant-data-swift`
- Commit: `3a0c2c53cf28296ea56617d6d868dfa6a73f0383`
- High-level reason: Preserve live-error `original-event` correlation, reject
  only the affected query without reconnecting the shared socket, fail
  one-shot queries promptly, and prevent stale automatic mutation delivery
  when the runtime is configured for manual connection.

## July 27, 2026 at 8:55:21 AM EDT

- Repository: `instant-data-swift`
- Commit: `e2dba6ba9ce08a5ec107bade582bc86cfd6e4f8e`
- High-level reason: Adopt the intent-ledger workflow and install reusable
  change-recording and reproducible-build provenance helpers in Instant.

## July 27, 2026 at 8:39:12 AM EDT

- Repository: `instant-data-swift`
- Commit: `ceb22e40503aa854adb18a8c9050c59e3fc2e65d`
- High-level reason: Refresh deterministic performance evidence for the
  optimized offline-restore hop count and ensure the Reminders move fixture
  writes later than its seeded triples.

## July 27, 2026 at 8:34:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `95c4b3174957e2cb4c792082b8eeb9907e93f7f5`
- High-level reason: Bound the live microphone PCM stream to its 256 newest
  buffers, record dropped-buffer diagnostics, and warn once when a speech
  consumer falls behind without interrupting local capture.

## July 27, 2026 at 8:28:05 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `386a9b41c8a913039497e7e0b57475f4c47e4d2d`
- High-level reason: Close the remaining pasteboard crash path by making the
  clipboard read dependency async and isolating every live read to MainActor.

## July 27, 2026 at 8:22:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `46ec7179ec1d5062eb1aef39162fb425124947b9`
- High-level reason: Establish shared commit discipline in Scribe so parallel
  work is staged deliberately, journaled centrally, and handed off cleanly.

## July 27, 2026 at 8:22:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3ed949b13c3e5bec795081c9ae5489536f103547`
- High-level reason: Preserve the existing parallel Watch companion auth,
  speech relay, wire-format, test, and session-record work before auditing it.

## July 27, 2026 at 8:21:39 AM EDT

- Repository: `instant-data-swift`
- Commit: `099858f93f76de6dfa2ce9e41cb50386b3848176`
- High-level reason: Establish the cross-repository commit journal and require
  small verified commits plus clean parallel-agent handoffs.

## July 27, 2026 at 8:20:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `7593790839f66620b4d4cf8789d20f4530c58ab3`
- High-level reason: Preserve the unedited comprehensive audit journal before
  reading or changing the audited working tree.

## July 26, 2026 at 4:41:41 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9d65fbb201b22816a2b355675ce932e4c3480d62`
- High-level reason: Establish the Scribe baseline with the Watch companion
  speech relay and privacy-safe diagnostics checkpointed.

## July 26, 2026 at 4:41:39 PM EDT

- Repository: `instant-data-swift`
- Commit: `a9abe9d27301ac205ea6ff1e445eec9051a18913`
- High-level reason: Establish the Instant Swift baseline with startup tracing
  and hardened storage runtime behavior.
