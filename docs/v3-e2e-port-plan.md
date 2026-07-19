# V3 Syntax and End-to-End Port Plan

Status: V1 port complete; performance optimization follow-up active

This document turns the V3 SwiftUI sketches into a sequence of small,
test-gated implementation packets. It is subordinate to
`docs/instant-swift-data-goals.md`, which remains the product contract, and it
narrows `docs/instantdb-swift-data-plan.md` to the shortest path from the
current local-first implementation to real Swift/TypeScript synchronization.

## Current Baseline

As of 2026-07-19:

- The package already has a substantial local core: schema generation, typed
  queries and mutations, SQLite persistence, optimistic outbox behavior,
  property-wrapper adapters, auth seams, rooms, presence, topics, files,
  streams, sharing, CLI examples, validation fixtures, and benchmarks.
- The live WebSocket protocol can be exercised in opt-in validation commands,
  including one Swift-to-TypeScript and one TypeScript-to-Swift boundary proof.
- The normal runtime now owns an authenticated live session and a continuous
  server-event receiver. Commit `af88570` routes `refresh-ok` through the normal
  runtime, persists canonical join rows and the transaction checkpoint, and
  publishes the result to public query observers.
- Commit `ecf2145` encodes canonical Instant query objects, installs and
  reference-counts active queries, applies initial `add-query-ok` results, sends
  `remove-query` on cancellation, and restores active queries when a session is
  opened again.
- Commit `378b76f` drains the durable outbox through the owned live session,
  rewrites local attribute identities to the server UUIDs from `init-ok`,
  correlates `transact-ok` and server errors, persists retryable failures, and
  resumes pending sends after relaunch.
- Commit `abe63c5` reconnects established live sessions automatically with the
  canonical immediate-then-bounded backoff progression, publishes transient
  drops as closed rather than terminal errors, reinstalls active queries,
  resends only unacknowledged durable mutations, and cancels reconnect work on
  explicit close.
- Commits `4138549` and `44c11b1` encode the canonical room wire messages,
  idempotently join active rooms, queue presence and topic data until
  `join-room-ok`, rejoin with current presence after reconnect, flush newer
  queued data once, and send `leave-room` on cleanup. Commits `a98fe60` and
  `1ab3b99` apply and record incoming `refresh-presence`, `patch-presence`, and
  `server-broadcast` events through public ephemeral observers.
- Commit `ef00fc8` encodes canonical stream subscribe/unsubscribe and reader
  resume state. Commits `121cf3d` and `dd59d2f` register public stream-content
  observers with the owned live session, restore them after reconnect, and
  unsubscribe with the active subscription event id.
- Commits `f362b38` and `02ad087` reconnect on retryable `stream-append`
  failures without publishing failed content. Commits `029a3db` and `677398e`
  materialize inline appends with UTF-8 byte overlap, persist and publish the
  resulting snapshot, and advance reconnect state only after persistence.
  Canonical file-backed append fetching remains a separate stream packet.
- The V3 API direction is documented in
  `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md` and `screens/v3/`.
- The prior screen syntax is preserved under `screens/v2/` in commit `d11b1cf`.
  The five V3 screen probes were committed in `5316f24` and `edce7da`.
- Packet 0 restored the deterministic validation baseline in commit `e0350ba`.
  The gate passed 811 Swift tests, 28 dedicated macro snapshot tests, generated
  schema and permissions verification, and the local Swift/TypeScript E2E
  orchestrator. Its evidence directory was
  `/tmp/instant-swift-data-packet0-20260718T1106`.
- The current runtime and V3 recordings-list, auth-login, recording, and
  playback room fixtures passed 886 Swift Testing tests across 30 suites; the
  prior syntax gate also passed 28 dedicated macro tests.
  The auth slice includes wrapper-owned magic-code, guest, and provider
  actions; exact call-site callbacks; typed authenticated-user identity;
  stale-action cancellation; failure/retry; and durable session restoration
  after runtime relaunch. The recording slice now proves concrete-ID timeline
  query identity plus one-shot, view-invalidating `@LocalID` resolution in a
  hosted SwiftUI view. The recording action fixture now proves product
  preparation replacement; canonical owner/member/recording/transcription
  refs; start, finish, and attachment mutations; typed optimistic and accepted
  callbacks; rejection recovery without callback replay; exact transport
  mutation/precondition shapes; and durable relaunch state. Commit `33028f6`
  adds the same five-entity, five-link contract as a Swift-owned schema and
  permissions example with CLI generation and verification. Commits `8ebc352`
  and `9c8a338` pin the TypeScript SDK/compiler/lockfile and type-check generated
  and server-readback artifacts with hashes. Commits `c0a70d1` and `e27c446`
  verify server-normalized schema and permissions while reporting Instant's
  six known system-schema additions as stable warnings. Commits `b711a7b`,
  `baaaf39`, `e7bde06`, and `8b88488` define the exact 18-step Swift recording
  graph, route it through the live-transaction validator, and type-check/test
  the matching nested query and projection against the canonical TypeScript
  SDK. The core reconnect packet's earlier explicit E2E evidence is
  `/tmp/instant-swift-data-reconnect-20260718T161703Z`.
- Credentialed remote preflight and both real Swift/TypeScript boundary
  directions passed from the typed-message milestone. The
  evidence directory is
  `/tmp/instant-swift-data-v3-message-e2e-20260718T180003Z`. That run recorded
  295 cases, 28 exact, 265 adapted, 2 not applicable, and 0 blocked, including
  generated schema/permissions verification and both Swift-to-TypeScript and
  TypeScript-to-Swift live boundaries.
- The auth-enabled head was revalidated in
  `/tmp/instant-swift-data-v3-auth-e2e-20260718T181947Z`. The full local,
  generated-contract, macro, and Swift-to-TypeScript gates passed. The first
  TypeScript-to-Swift child process exhausted the harness's 30-second cold
  build timeout; its documented 90-second rerun passed, and the regenerated
  final coverage reports 295 records, 28 exact, 265 adapted, 2 not applicable,
  and 0 blocked. This verifies that head's cross-SDK transport baseline. Real
  refresh-token verification, durable restoration, sign-out invalidation, and
  rejection by both Swift and the canonical TypeScript SDK are now covered by
  the later Packet 6 acceptance gate.
- Commit `eb35a31` makes the recording contract install reproducible from a
  clean checkout using the pinned Instant CLI. The clean-head run at `b711a7b`
  created ephemeral app `a5dfcd81-6392-4f81-afda-6f2b59756a56`, pushed the
  Swift-generated schema and permissions, pulled both back, verified their
  normalized Swift shapes, and type-checked the pulled files. Non-secret
  evidence is in
  `/tmp/instant-data-swift-recording-contract-live-20260718T1557/evidence.json`;
  the temporary app expires automatically and its admin token was removed from
  the retained artifacts.
- Commits `0144185` through `771ed4c` close the recording-action data-plane
  acceptance case in both directions. The clean-head run at `771ed4c` created
  an ephemeral app, installed and read back the generated schema and
  permissions, wrote the exact linked graph through Swift and queried it with
  the pinned TypeScript SDK, then wrote and finished the graph through
  TypeScript while the normal Swift live observer decoded the exact refresh.
  Both comparisons passed with zero compiler or runtime warnings. Non-secret
  evidence is in
  `/private/tmp/instant-data-swift-recording-bidirectional-clean-771ed4c-20260718/evidence.json`.
- Commits `a7c1ad3`, `9fe9c25`, and `031e4fe` compile the playback room seam.
  Typed room identity, join/leave, dynamic replacement, hosted SwiftUI
  invalidation, exact Codable presence publication and decoding, typed topic
  publication callbacks and observation, cancellation cleanup, and room-schema
  topic constraints passed 885 Swift tests across 30 suites. Presence is
  resolved as wrapper-owned state plus explicit dynamic room/publication input
  from `.presence(_:in:publishing:)`.
- Commit `8b979c0` adds the typed `recording.playback` presence and topic
  declaration to the Swift-owned recording schema and strictly compiles valid
  plus deliberately invalid `joinRoom`, presence, and topic calls against the
  pinned canonical TypeScript SDK. The canonical schema migration does not
  persist room declarations and a fresh pull returns `rooms: {}`, so server
  readback verifies entities, links, and permissions while the generated local
  schema remains the room type authority. The clean existing recording-data
  contract rerun passed in both directions at
  `/private/tmp/instant-data-swift-playback-schema-clean-8b979c0-20260718/evidence.json`.
  That run revalidates the shared data plane; it does not replace the live
  presence/topic boundary.
- Commit `2390aa0` proves that live presence/topic boundary in both directions.
  Authenticated Swift and canonical TypeScript 1.0.49 peers join the same typed
  `recording.playback` room and observe exact presence plus `reaction`,
  `commentDraft`, and `commentCommitted` payloads with zero compiler/runtime
  warnings. Clean evidence is in
  `/tmp/instant-data-swift-playback-room-clean-2390aa0-20260718/evidence.json`.
- Commits `45daf84` through `ece3022` extend that boundary through an injected
  transport loss and automatic room rejoin. The source port first proves the
  pinned Reactor room loop accepts fresh peer presence and broadcasts after
  rejoin. The live gate then creates a fresh getadb app, pushes the
  Swift-generated recording schema, forces the normal Swift WebSocket session
  to fail, and proves a second authenticated session republishes and receives
  exact presence plus all three topic payloads without call-site reconnect
  management. The shared TypeScript contract type-checks under the pinned SDK,
  compiler/runtime warnings are zero, and all 907 Swift tests in 35 suites plus
  the complete TypeScript contract/fixture suite pass. Clean evidence for
  revision `ece3022` is in
  `/tmp/instant-data-swift-playback-room-reconnect-clean-ece3022-20260718T1957Z/evidence.json`.
- Commits `4ddf46b` through `02e06cf` compile and live-prove the preferences
  sync and storage source contracts. `@InstantSyncStatus` renders cached, connecting,
  connected, authenticated, reconnecting, offline, and failed phases from the
  canonical connection observer and exposes explicit manual-flush callbacks.
  `@InstantStorageStatus` reads actual SQLite, stream-content, and downloaded
  file byte counts, while typed file matching clears only the selected
  downloads and reports one explicit completion callback. The fresh getadb
  gate proves connected-to-authenticated state plus exact 12-byte stream cache,
  7-byte downloaded cache, and selective 4-byte audio deletion. Clean evidence
  for revision `1e81ab1` is in
  `/tmp/instant-data-swift-preferences-contract-20260719T001942Z/evidence.json`.
- Commit `1e81ab1` adds the runnable `voicetrail-v3` executable and a shared app
  target containing auth, recordings, capture, playback, and preferences. The
  focused app tests compile every settled screen, prove recording-to-playback
  routing, and verify local/live bootstrap selection. Full verification is
  green at 917 Swift tests in 39 suites plus the complete TypeScript contract
  and fixture suite.
- Commits `6e649b0` through `636c922` move capture start, attachment, and finish
  into the shared app target and add the first clean aggregate app gate. A
  fresh app at revision `636c922` verified generated schema and permissions,
  the actual app-model recording/transcription/attachment flow observed through
  the canonical TypeScript SDK with its exact finished state, bidirectional
  recording graph compatibility,
  owner/reader/writer/revocation plus reader-write denial, playback room
  reconnect, preferences storage cleanup, and auth invalidation with zero
  compiler/runtime warnings. Evidence is in
  `/tmp/instant-data-swift-voice-trail-v3-app-20260719T004933Z/evidence.json`.
- Commits `7cad7ee` and `1dcee4b` make the VoiceTrail app the authority for the
  playback room type and all presence/reaction/comment payloads, removing the
  validator's parallel payload models. The clean aggregate rerun at `1dcee4b`
  proves those exact app-owned payloads in both directions before and after a
  forced reconnect, with zero warnings. Evidence is in
  `/tmp/instant-data-swift-voice-trail-v3-app-20260719T005834Z/evidence.json`.
- Commits `f1b4d30` and `58b7496` add the first non-VoiceTrail Packet 8 app:
  a runnable `todos-v3` SwiftUI executable and shared `TodosV3App` target. It
  uses the desired `@InstantEntity`, `@FetchAll`, typed-message, call-site
  callback, room, and presence syntax. Focused model tests and the full package
  gate pass at 922 Swift tests in 42 suites.
- The Todos live boundary is complete through `122d4e0`. A clean fresh-app run
  installs and reads back the generated schema and permissions, proves the
  exact Swift-to-TypeScript and TypeScript-to-typed-Swift rows, observes one
  canonical TypeScript room peer, queues exactly one Swift mutation while
  disconnected, and observes that exact row in TypeScript after reconnect and
  server acceptance. Compiler/runtime warnings are zero. Evidence is in
  `/tmp/instant-data-swift-todos-v3-20260719T012426Z/evidence.json`.
- The standalone Auth app boundary is complete through `08df094`, `319aa3c`,
  `236b6aa`, `a9783c9`, and `9c0b683`. `auth-v3` compiles the settled
  `@InstantAuth` call-site callback syntax with the exact five-provider
  catalog. VoiceTrail now consumes those app-owned user, provider, and login
  screen types instead of maintaining parallel definitions. The clean
  fresh-app gate proves server-verified sign-in, app-owned `signedIn` state,
  durable relaunch, app-owned `signedOut`, local session clearing, and remote
  token rejection through canonical TypeScript with zero warnings. Evidence
  is in
  `/tmp/instant-data-swift-auth-v3-app-20260719T013823Z/evidence.json`.
- The canonical Mobile Chat boundary is complete through `5f3276a`.
  `MobileChatV3App` and the `mobile-chat-v3` executable own the exact upstream
  `$users`, `profiles`, `channels`, and `messages` graph; authenticated profile,
  channel, and message mutations; `chat` presence; and `typing`/`emoji` topics.
  The clean getadb gate pushed the Swift-generated schema and permissions twice
  with no drift, pulled and verified the server-normalized contract, type-checked
  the generated and pulled TypeScript, proved both SDK graph directions, proved
  both room payload directions plus disconnect cleanup, and rejected a
  cross-user message edit with zero compiler/runtime warnings. Evidence is in
  `/tmp/instant-data-swift-mobile-chat-v3-20260719T021910Z/evidence.json`.
- The canonical Typing Indicator recipe boundary is complete through `2c36ab7`.
  `PresenceRecipesV3App` and the `presence-recipes-v3` executable own the
  source-pinned room/presence surface for `typing-indicator-example/1234`.
  The fresh-app gate proves the exact initial-absence, active `true`, inactive
  `false`, and cleared `null` frames in both Swift/TypeScript directions, active
  peer filtering, TypeScript disconnect cleanup to zero remote peers, generated
  room schema and empty permissions round trips, strict TypeScript compilation,
  and five pinned server system-schema warnings. Evidence is in
  `/tmp/instant-data-swift-typing-indicator-v3-20260719T025123Z/evidence.json`.
- The canonical Reactions recipe boundary is complete through `e84679b`, with
  the final clean live gate recorded at `e1f100a` before the executable-only
  recipe navigation commit.
  Source-first app, schema, CLI, TypeScript, live-support, and Swift-evidence
  tests pin `topics-example/123`, the `emoji` topic, the exact
  `{name, directionAngle, rotationAngle}` payload, and the four canonical
  reaction names. The clean fresh-app gate proves Swift `heart` publication is
  observed by TypeScript, TypeScript `wave` publication is observed by Swift,
  unknown `sparkle` is ignored by the app model, and topic unsubscribe cleanup
  prevents a later `fire` probe from invoking the removed callback. Generated
  room schema and empty permissions push twice with no drift, pull back and
  strict-typecheck, with five pinned server system-schema warnings and zero
  compiler/runtime warnings. Evidence is in
  `/tmp/instant-data-swift-reactions-v3-20260719T032236Z/evidence.json`.
- The canonical Avatar Stack recipe boundary is complete through `22980dc`.
  Source-first app, generated-schema, CLI, TypeScript, Swift-evidence,
  remote-peer-count, and credential-redaction tests pin
  `avatars-example/avatars-example-1234`, exact name-only app presence,
  first-six-character fallback names, wrapper-owned peer metadata, local-plus-
  peers online count, and disconnect cleanup. The clean getadb gate provisions
  a fresh app directly through `getadb.com`, pushes schema and permissions
  twice with no drift, pulls and strict-typechecks them, and proves exact
  `{name}` presence in both Swift/TypeScript directions. Final evidence is in
  `/tmp/instant-data-swift-avatar-stack-v3-20260719T034215Z/evidence.json` and
  contains no refresh or admin credentials.
- The canonical Cursors recipe boundary is complete through `fb946c0`, with
  its clean fresh-app proof recorded at `e09d871`. Source-first Swift and
  TypeScript contracts pin `cursors-example/123`, the dynamic
  `cursors-space-default--cursors-example-123` presence key, exact
  `{x, y, xPercent, yPercent, color}` cursor payload, viewport normalization,
  dark lowercase hex colors, peer-only projection, and credential-redacted
  evidence. The gate provisions a fresh getadb app, pushes schema and empty
  permissions twice without drift, pulls and strict-typechecks them, proves
  both SDK directions, observes cursor clear separately from peer disconnect,
  and asserts the exact five server system-schema warnings with zero compiler
  or runtime warnings. Evidence is in
  `/tmp/instant-data-swift-cursors-v3-20260719T040045Z/evidence.json`.
- The canonical Custom Cursors recipe boundary is complete through `8f3e9e2`.
  Source-first Swift, generated-schema, CLI, TypeScript, live-support, and
  Swift-evidence contracts pin `cursors-example/124`, the dynamic
  `cursors-space-default--cursors-example-124` key, required top-level `name`,
  exact `{x, y, xPercent, yPercent, color}` cursor data, and the canonical
  encoded 40-point avatar URL. The clean fresh-app gate proves both SDK
  directions, keeps the named peer after cursor clear, removes the peer after
  disconnect, pushes and reads back empty app schema and permissions without
  drift, and records the five exact server system-schema warnings with zero
  compiler or runtime warnings. Evidence is in
  `/tmp/instant-data-swift-custom-cursors-v3-20260719T042442Z/evidence.json`.
- The canonical Merge Tile Game boundary is complete through `59a5e2d`, with
  its clean fresh-app proof recorded at the same revision. The app-owned `boards` entity,
  `@FetchOne`, typed initialize/merge/reset messages, and
  `tile-game-example/_defaultRoomId` color presence preserve the fixed 4x4
  board, six-color palette, and single-cell JSON deep merge. The live gate
  proves Swift and TypeScript publish distinct cells without clobbering,
  observes exact color presence in both directions, resets all 16 cells, and
  removes the remote peer on disconnect. Server readback preserves the Swift
  JSON contract through the explicit `server-json-as-any` warning. Evidence is
  in `/tmp/instant-data-swift-merge-tile-game-v3-20260719T045650Z/evidence.json`.
- The canonical Stroopwafel boundary is complete through `3584c15`. The
  source-first Swift and TypeScript contracts pin
  `jsventures/stroopwafel@7f5e2379464d932c0e4681655cbf022f8d9c2614`, its
  four-entity/four-link durable graph, 17 allow rules, wrapper-owned
  `@FetchOne`/`@FetchAll` screens, typed messages, and exact multiplayer score
  lifecycle. The fresh getadb gate pushes schema and permissions twice without
  drift, pulls and strict-typechecks both artifacts, then proves Swift room and
  game creation, TypeScript join/readiness and owned point update, Swift
  observation and completion at 13, and cleared `currentGameId`. The gate also
  caught and fixed a core transport ambiguity by keeping lookup references
  distinct from ordinary two-element JSON arrays. Evidence is in
  `/tmp/instant-data-swift-stroopwafel-v3-20260719T054351Z/evidence.json` with
  zero compiler/runtime warnings.
- The canonical Reminders boundary is complete through `e72c99a`. The
  source-first Swift app, generated schema and permissions, canonical
  TypeScript contract, and fresh-app verifier preserve the six-namespace,
  nine-link sharing graph; UUID tag identity with human titles; `Date`
  semantics; and owner, reader, writer, and outsider boundaries. The live gate
  proves Swift graph creation observed by TypeScript, reader visibility with a
  rejected write, Swift promotion to writer, TypeScript mutation and reminder
  creation observed by Swift, Swift state observed back in TypeScript, zero
  pending mutations, outsider invisibility, and zero compiler/runtime warnings.
  Evidence is in
  `/tmp/instant-data-swift-reminders-v3-20260719T070753Z/evidence.json`. The
  post-port aggregate passes 1,049 Swift Testing cases across 76 suites plus
  the complete TypeScript typecheck, contract, live-support, and fixture matrix.
- The canonical SyncUps boundary is complete through `b689469`. The app owns
  the three upstream entities, all 16 themes, two required cascading parent
  links, list/detail/form/recording screens, speech authorization and
  recognition, sound, settings, clock behavior, generated schema and
  permissions, and the runnable `syncups-v3` executable. The fresh-app gate
  pushes the Swift-owned contract twice with no drift, pulls and verifies the
  server-normalized artifacts, strictly type-checks them, and proves the exact
  nested graph in both Swift-to-TypeScript and TypeScript-to-Swift directions.
  It records three entities, nine attributes, two links, twelve allow rules,
  canonical `Date` objects, authenticated Swift state, zero pending mutations,
  and zero compiler/runtime warnings at
  `/tmp/instant-data-swift-syncups-v3-20260719T073704Z/evidence.json`. The
  post-port aggregate at `194ef4d` passes 1,067 Swift Testing cases across 83
  suites, the `syncups-v3` build, and the complete TypeScript typecheck,
  contract, live-support, and fixture matrix.
- The canonical App Builder and Storage boundary is complete through
  `7f9acc5`. `AppBuilderV3App` owns the authenticated owner list, build detail,
  generation model, streaming reasoning/code updates, platform-app creation,
  uploaded `App.tsx`, linked `$files` record, failure cleanup, runnable host,
  generated schema, and source-pinned permissions. Swift file uploads now use
  the canonical Storage PUT/DELETE requests, retain downloaded bytes in the
  local cache under the server-issued file id, and expose the same linked file
  graph as TypeScript. The clean fresh-app gate pushes schema and permissions
  twice with no drift, pulls and strictly verifies them, and proves both SDK
  directions plus exact downloaded file contents and canonical server-owned
  file metadata. It records three entities, thirteen authored attributes, two
  links, five allow rules, eight exact normalization warnings, authenticated
  Swift state, zero pending mutations, and zero compiler/runtime warnings at
  `/tmp/instant-data-swift-app-builder-v3-20260719T082431Z/evidence.json`. The
  post-port aggregate passes 1,083 Swift Testing cases across 90 suites, 28
  macro tests, the `app-builder-v3` build, and the complete TypeScript
  typecheck, contract, live-support, and fixture matrix.
- Commits `1d77c27`, `a3238fe`, `f0daf86`, and `217c4a7` close the remaining
  local live-reader stream packet. The runtime now fetches canonical signed
  `stream-append` files in order while prefetching the next response, discards
  overlap in bytes across file and inline segments, preserves split UTF-8
  scalars, cancels active response bodies, advances reconnect state by fetched
  bytes only after persistence, and stops after the upstream ten-retry budget.
  Client-id and stream-id readers can start from an empty cache; the first
  canonical append persists its server-resolved metadata and publishes
  identical snapshots to both selector forms.
- Commits `3499955`, `806780a`, `468637d`, and `972e12a` add the canonical
  writer half: exact `start-stream`/`append-stream` shapes, correlated
  server-issued ids, unflushed UTF-8 buffering, reconnect with the original
  token, resend after the server-confirmed byte offset, and terminal
  `stream-flushed` acknowledgement before socket teardown. Commit `dc2e3da`
  adds the runnable `streams-v3` app and its app-owned async reader/writer
  model. Commits `ebc0994` through `2ec8a17` add the fresh-app contract gate.
  The clean run proves exact 24-byte content in both Swift-to-TypeScript and
  TypeScript-to-Swift directions, distinct server-issued stream ids,
  authenticated Swift state, two `$streams` allow rules, five expected system
  schema warnings, and zero compiler/runtime warnings at
  `/tmp/instant-data-swift-streams-v3-20260719T092305Z/evidence.json`. The
  post-port aggregate passes 1,096 Swift Testing cases across 92 suites plus 28
  macro tests, the `streams-v3` build, and the complete TypeScript typecheck.
- The CloudKitDemo-equivalent boundary is complete through `f3ee07c`.
  `CloudKitDemoV3App` owns the runnable shared-counter UI, typed create,
  increment, participant grant, role-replacement, and revocation messages, and
  the existing `v3_shared_lists`/`v3_shares`/`v3_share_memberships` wire model.
  The clean fresh-app gate proves Swift graph creation observed by TypeScript;
  reader rejection and authoritative rollback; reader-to-writer-to-reader role
  replacement; Swift increment `0 -> 1`; TypeScript increment `1 -> 2`;
  participant revocation; writer and outsider permissions; visible `@Shares`
  state; and owner relaunch with zero pending or failed mutations. Evidence is
  in
  `/tmp/instant-data-swift-cloudkit-demo-v3-20260719T093505Z/evidence.json`.
  The post-port aggregate passes 1,100 Swift Testing cases across 94 suites,
  28 isolated macro tests, the `cloudkit-demo-v3` build, and the complete
  TypeScript typecheck, contract, live-support, and fixture matrix.
- The current static parity gate records 295 cases: 28 exact, 263 adapted, 2 not
  applicable, and 2 blocked when no credentialed artifacts are supplied. The
  only blocked ids are
  `instant.live-transport.swift-to-typescript` and
  `instant.live-transport.typescript-to-swift`; valid credentialed artifacts
  promote those two records instead of changing the static source ledger.
- The required app matrix and its final CloudKitDemo boundary are green, so
  `v0.4.0-apps-e2e` is ready to bind to this clean evidence record. The next
  execution phase is a `v1.0.0` goals audit, not another V3 syntax-design
  phase.

## Authority Order

When sources disagree, use this order:

1. `docs/instant-swift-data-goals.md`: product requirements and definition of
   done.
2. This file: execution order, gates, and version targets.
3. `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md`: desired public API direction.
4. `screens/v3/*.md`: executable syntax probes for realistic app code.
5. `docs/instantdb-swift-data-plan.md`: full feature inventory and historical
   progress record.
6. `validation/README.md`: evidence format and harness operation.
7. Canonical upstream source pinned under `upstream/`: behavior and exact wire
   contract.

## Important Working References

| Need | Reference |
| --- | --- |
| Current execution state, packet order, gates, and tag targets | `docs/v3-e2e-port-plan.md` |
| Product contract and full definition of done | `docs/instant-swift-data-goals.md` |
| Desired V3 API rules and decision log | `INSTANT_DATA_API_DESIGN_PREFERENCES_V3.md` |
| Next execution target | Profile the largest checked performance gaps, beginning with nested and reverse linked query materialization, without changing V1 semantics |
| V1 clean release gate | `validation/verify-v1-release.sh` and `/tmp/instant-data-swift-v1-release-20260719T103430Z/evidence.json` |
| Checked V1 performance baseline | `validation/benchmarks/v1-cross-sdk-performance-2026-07-19.json` |
| Reproducible cross-SDK performance gate | `validation/run-cross-sdk-benchmark-comparison.sh`, `InstantCrossSDKBenchmark.swift`, `InstantCrossSDKRuntimeBenchmark.swift`, and their pinned TypeScript peers |
| Live transport actor-hop proof | `validation/verify-todos-v3-app-live.sh` and `InstantTodosV3LiveValidation.swift` |
| Completed CloudKitDemo live gate | `validation/verify-cloudkit-demo-v3-app-live.sh`, `Sources/InstantSwiftDataTesting/InstantCloudKitDemoV3LiveValidation.swift`, and `validation/ts-runner/src/cloudkit-demo-v3-live-contract.ts` |
| Completed Streams live gate | `validation/verify-streams-v3-app-live.sh`, `Sources/InstantSwiftDataTesting/InstantStreamsV3LiveValidation.swift`, and `validation/ts-runner/src/streams-v3-live-contract.ts` |
| Completed SyncUps live gate | `validation/verify-syncups-v3-app-live.sh`, `Sources/InstantSwiftDataTesting/InstantSyncUpsV3LiveValidation.swift`, and `validation/ts-runner/src/syncups-v3-*.ts` |
| Completed App Builder and Storage live gate | `validation/verify-app-builder-v3-app-live.sh`, `Sources/InstantSwiftDataTesting/InstantAppBuilderV3LiveValidation.swift`, `Sources/InstantSwiftDataCore/InstantStorageTransport.swift`, and `validation/ts-runner/src/app-builder-v3-*.ts` |
| Current generated recording contract | `InstantSchemaExamples.recordingActionDocument`, `recordingActionValidationPermissions`, and `--example recording-action` |
| TypeScript contract pin/type-check gate | `validation/ts-runner/package.json`, its committed `pnpm-lock.yaml`, and `validation/typecheck-generated-contract.sh` |
| Reproducible live schema/perms install and readback | `validation/verify-recording-contract-live.sh` and `validation/fixtures/recording-action.server.*.ts` |
| Completed recording data-plane contract | `InstantRecordingActionLiveContract` in `Sources/InstantSwiftDataTesting/` and `validation/verify-recording-contract-live.sh` |
| All five desired VoiceTrail screen probes | `screens/v3/README.md` and sibling Markdown files |
| Existing public wrapper implementation | `Sources/InstantSwiftData/InstantSwiftData.swift` |
| Owned live runtime and persistence integration | `Sources/InstantSwiftDataCore/InstantRuntime.swift` |
| Canonical stream lifecycle | `upstream/instant/client/packages/core/src/Stream.ts` and `upstream/instant/client/packages/python/src/instantdb/_async/streams/reader.py` |
| Canonical stream state tests | `upstream/instant/client/packages/python/tests/test_streams_state.py` |
| Source-to-Swift parity ledger | `Sources/InstantSwiftDataCore/InstantParityCoverage.swift` |
| Reproducible Swift/TypeScript harness | `validation/run-e2e.sh` and `validation/README.md` |
| Aggregate VoiceTrail app gate | `validation/verify-voice-trail-v3-app-live.sh` and its `app-capture.json`/`evidence.json` artifacts |
| Runnable Todos app | `Sources/TodosV3App/`, `Sources/TodosV3Executable/`, and `Tests/TodosV3AppTests/` |
| Aggregate Todos app gate | `validation/verify-todos-v3-app-live.sh`, `validation/ts-runner/src/todos-v3-live-contract.ts`, and its `evidence.json` artifact |
| Standalone Auth app and live gate | `Sources/AuthV3App/`, `Sources/AuthV3Executable/`, `validation/verify-auth-v3-app-live.sh`, and `validation/ts-runner/src/auth-v3-app-live-contract.ts` |
| Mobile Chat app-owned syntax and behavior | `Sources/MobileChatV3App/`, `Sources/MobileChatV3Executable/`, and `Tests/MobileChatV3AppTests/` |
| Mobile Chat source-first schema/live contracts | `Tests/InstantSwiftDataSchemaTests/MobileChatContractTests.swift`, `Tests/InstantSwiftDataTestingTests/InstantMobileChatV3LiveValidationTests.swift`, and `validation/ts-runner/src/mobile-chat-v3-app-contract.test.ts` |
| Mobile Chat reproducible cross-SDK gate | `validation/verify-mobile-chat-v3-app-live.sh` and `validation/ts-runner/src/mobile-chat-v3-live-contract.ts` |
| Typing Indicator app-owned syntax and behavior | `Sources/PresenceRecipesV3App/`, `Sources/PresenceRecipesV3Executable/`, and `Tests/PresenceRecipesV3AppTests/` |
| Typing Indicator source/schema/live contracts | `Tests/InstantSwiftDataSchemaTests/TypingIndicatorContractTests.swift`, `Tests/InstantSwiftDataTestingTests/InstantTypingIndicatorV3LiveValidationTests.swift`, and `validation/ts-runner/src/typing-indicator-v3-*.ts` |
| Typing Indicator reproducible cross-SDK gate | `validation/verify-typing-indicator-v3-app-live.sh` and its `evidence.json` artifact |
| Cursors app-owned syntax and exact dynamic presence | `Sources/PresenceRecipesV3App/CursorsV3Screen.swift`, `Tests/PresenceRecipesV3AppTests/CursorsV3Tests.swift`, and `Tests/InstantSwiftDataSchemaTests/CursorsContractTests.swift` |
| Cursors reproducible cross-SDK gate | `validation/verify-cursors-v3-app-live.sh`, `validation/ts-runner/src/cursors-v3-live-contract.ts`, and its `evidence.json` artifact |
| Custom Cursors app-owned syntax and exact dynamic presence | `Sources/PresenceRecipesV3App/CustomCursorsV3Screen.swift`, `Tests/PresenceRecipesV3AppTests/CustomCursorsV3Tests.swift`, and `Tests/InstantSwiftDataSchemaTests/CustomCursorsContractTests.swift` |
| Custom Cursors reproducible cross-SDK gate | `validation/verify-custom-cursors-v3-app-live.sh`, `validation/ts-runner/src/custom-cursors-v3-live-contract.ts`, and `/tmp/instant-data-swift-custom-cursors-v3-20260719T042442Z/evidence.json` |
| Merge Tile Game app-owned syntax and typed board messages | `Sources/PresenceRecipesV3App/MergeTileGameV3Screen.swift`, `Tests/PresenceRecipesV3AppTests/MergeTileGameV3Tests.swift`, and `Tests/InstantSwiftDataSchemaTests/MergeTileGameContractTests.swift` |
| Merge Tile Game reproducible cross-SDK gate | `validation/verify-merge-tile-game-v3-app-live.sh`, `validation/ts-runner/src/merge-tile-game-v3-live-contract.ts`, and `/tmp/instant-data-swift-merge-tile-game-v3-20260719T045650Z/evidence.json` |
| Stroopwafel app-owned syntax and typed lifecycle | `Sources/StroopwafelV3App/`, `Sources/StroopwafelV3Executable/`, `Tests/StroopwafelV3AppTests/`, and `Tests/InstantSwiftDataSchemaTests/StroopwafelContractTests.swift` |
| Stroopwafel source/live contracts | `Tests/InstantSwiftDataTestingTests/InstantStroopwafelV3LiveValidationTests.swift` and `validation/ts-runner/src/stroopwafel-v3-*.ts` |
| Stroopwafel reproducible cross-SDK gate | `validation/verify-stroopwafel-v3-app-live.sh` and `/tmp/instant-data-swift-stroopwafel-v3-20260719T054351Z/evidence.json` |
| Reactions app-owned syntax and behavior | `Sources/PresenceRecipesV3App/ReactionsV3Screen.swift`, `Sources/PresenceRecipesV3App/PresenceRecipesV3App.swift`, and `Tests/PresenceRecipesV3AppTests/ReactionsV3Tests.swift` |
| Reactions source/schema/live contracts | `Tests/InstantSwiftDataSchemaTests/ReactionsContractTests.swift`, `Tests/InstantSwiftDataTestingTests/InstantReactionsV3LiveValidationTests.swift`, and `validation/ts-runner/src/reactions-v3-*.ts` |
| Reactions reproducible cross-SDK gate | `validation/verify-reactions-v3-app-live.sh` and `/tmp/instant-data-swift-reactions-v3-20260719T032236Z/evidence.json` |
| Avatar Stack app-owned syntax and behavior | `Sources/PresenceRecipesV3App/AvatarStackV3Screen.swift`, `Sources/PresenceRecipesV3App/PresenceRecipesV3App.swift`, and `Tests/PresenceRecipesV3AppTests/AvatarStackV3Tests.swift` |
| Avatar Stack source/schema/live contracts | `Tests/InstantSwiftDataSchemaTests/AvatarStackContractTests.swift`, `Tests/InstantSwiftDataTestingTests/InstantAvatarStackV3LiveValidationTests.swift`, and `validation/ts-runner/src/avatar-stack-v3-*.ts` |
| Avatar Stack reproducible cross-SDK gate | `validation/verify-avatar-stack-v3-app-live.sh` and `/tmp/instant-data-swift-avatar-stack-v3-20260719T034215Z/evidence.json` |

## Decisions Already Made

These decisions are sufficient to continue implementation:

- `@FetchAll` is the normal list surface.
- `@FetchOne` is for one value or scalar result.
- `@Fetch` and request objects are for one wrapper-owned composite value, not
  merely for dynamic input.
- Direct SwiftUI wrappers attach with `.instantFetch($rows, query)`; query
  identity drives SwiftUI task replacement and the wrapper owns the underlying
  subscription lifecycle.
- Property wrappers own loading, observation, cancellation, stale-work
  replacement, and renderable status.
- SwiftUI button closures remain synchronous. They send typed messages; views
  do not create unstructured `Task` values for ordinary operations.
- Mutation and auth callbacks live at the call site and represent side effects
  of that specific action.
- Passive observation does not replay action-specific callbacks.
- Low-level query, subscription, transaction, auth, storage, room, and local-ID
  primitives remain public for non-SwiftUI code, tests, and advanced use.
- VoiceTrail-specific types and convenience wrappers stay outside the reusable
  Instant core.
- Auth-provider catalogs are handwritten app configuration for V3. Credential
  acquisition is an injected platform seam; the reusable auth wrapper owns
  exchange, session state, cancellation, and action callbacks. Catalog
  generation can be added later without changing the public catalog protocol.

## Decisions To Resolve Through Compiling Slices

Do not pause the whole port for these. Resolve each in the first compiling
slice that needs it, record the answer in the V3 design document, and add a
compile/runtime test:

- Whether `@InstantFetchBuilder` is handwritten, generated, or both.
- How much of a mutation change envelope is macro-generated.

The recordings-list attachment, auth-provider catalog, local-ID, recording
action, and room-presence ownership decisions are resolved. The remaining
items can wait for their vertical slice; no separate design phase is required
before continuing the port.

## Commit and Version Discipline

Every commit must be one reviewable packet. A packet should normally touch one
behavioral seam plus its tests, fixture, and documentation. Avoid mixing
transport, public syntax, app work, and unrelated cleanup.

Before a packet commit:

1. Run the narrow tests for the changed seam.
2. Run `swift test` with no accepted failures.
3. Run `validation/run-macro-tests.sh` when macros or generated API change.
4. Run the local Swift/TypeScript contract harness.
5. Run the relevant real Instant boundary case when the packet touches live
   transport, schema, permissions, sharing, auth, files, rooms, or streams.
6. Inspect generated schema, permissions, JSONL evidence, and warnings as
   committed review artifacts or reproducible outputs.

Do not weaken assertions merely to make a packet green. First determine whether
the implementation changed intentionally, the evidence list is nondeterministic,
or the expectation is stale.

Create annotated Git tags only after the milestone gate passes from a clean
checkout. The tag message must name the validation artifact directory and the
canonical TypeScript dependency revisions. The repository currently has the
annotated `v0.3.0-schema-auth-sharing` milestone; the targets below govern the
remaining version line.

## Version Targets

| Version | State | Next proof required |
| --- | --- | --- |
| `v0.1.0-v3-syntax` | Complete, subsumed | Preserve the compiling screen and wrapper fixtures in the `v0.4.0` aggregate |
| `v0.2.0-live-sync` | Complete, subsumed | Preserve the bidirectional runtime, reconnect, and rejection gates in the `v0.4.0` aggregate |
| `v0.3.0-schema-auth-sharing` | Complete | Preserve the clean aggregate evidence named by the annotated tag |
| `v0.4.0-apps-e2e` | Complete | Preserve the clean CloudKitDemo and aggregate evidence named by the annotated tag |
| `v1.0.0` | Complete | Preserve the clean release evidence named by the annotated tag |

### `v0.1.0-v3-syntax`

Target: the V3 public API is executable, not only sketched.

Gate:

- Full Swift suite passes.
- V3 screen fixtures type-check under Swift 6 strict concurrency.
- Recordings list, auth login, recording, playback, and preferences compile
  against public package APIs with product-only placeholders isolated in a
  VoiceTrail fixture module.
- Wrapper lifecycle and action callback semantics have deterministic tests.
- The V3 docs contain no syntax that the fixtures cannot compile.

### `v0.2.0-live-sync`

Target: the normal runtime performs bidirectional live synchronization.

Gate:

- Swift writes through its normal client; the canonical TypeScript SDK observes
  the exact entity and linked data.
- TypeScript writes; the normal Swift subscription observes and decodes it.
- Reconnect resubscribes and resumes from the processed transaction checkpoint.
- The durable outbox drains in order after reconnect.
- `transact-ok`, refreshes, server rejection, retryable network errors, and
  permanent failures update cache/outbox/status correctly.
- No special validation-only transport path is required by the app runtime.

### `v0.3.0-schema-auth-sharing`

Target: generated contracts and protected multi-user data work on real Instant.

Gate:

- Swift-generated `instant.schema.ts` and `instant.perms.ts` type-check against
  pinned canonical Instant packages.
- An ephemeral validation app installs the generated schema and permissions.
- Auth session creation/restoration/invalidation works through real transport.
- Owner, reader, and writer sharing flows work across two users.
- Unauthorized reads and writes are rejected without corrupting optimistic
  local state or leaving a stuck outbox row.
- `$users`, `$files`, forward/reverse links, required/optional values, and share
  metadata match canonical TypeScript shapes.

Current evidence: commits `81890b2`, `952255c`, `7e68005`, `875ca2d`,
`1bf2914`, and `c4c9a26` port the SQLiteData sharing tests first, define the
Swift-owned sharing schema and permissions, round-trip and type-check the
generated TypeScript, and prove real owner/reader/writer/outsider behavior on
an ephemeral Instant app. Commits `cd6c066` through `072fd05` then prove the
remaining runtime boundary: rejected Swift reader optimism reconciles through
`[1, 2, 1]` with no pending mutation, the Swift writer observes `[1, 3]` with
no failure, and real auth survives relaunch before Swift sign-out invalidates
the token for both SDKs. The clean aggregate gate at `072fd05` passed with zero
compiler warnings; evidence is in
`/tmp/instant-data-swift-v0.3-clean-worktree-072fd05-final-20260718/evidence.json`.
The milestone is complete once the same clean gate is bound to this updated
record by the annotated `v0.3.0-schema-auth-sharing` tag.

### `v0.4.0-apps-e2e`

Target: required example apps run end to end through the public V3 API.

Gate:

- VoiceTrail V3 screen flows run against live synced data.
- Required Instant examples and recipes have working Swift app surfaces, not
  only CLI or model proofs.
- SQLiteData CaseStudies, Reminders, SyncUps, and the Instant equivalent of
  CloudKitDemo meet the goals document acceptance cases.
- Auth, offline/reconnect, sharing, permissions, presence, topics, storage, and
  streams are exercised through app-facing adapters.

Current evidence: the required VoiceTrail and example-app sequence is complete
through `f3ee07c`. The final CloudKitDemo-equivalent gate created a fresh app,
pushed and pulled the Swift-owned sharing schema and permissions without
drift, strictly type-checked the server-normalized TypeScript, and proved exact
shared-counter values and roles in both SDK directions. Its evidence is at
`/tmp/instant-data-swift-cloudkit-demo-v3-20260719T093505Z/evidence.json`.
The clean aggregate then passed 1,100 Swift Testing cases across 94 suites, 28
isolated macro tests, the runnable app build, and the complete pinned
TypeScript matrix.

### `v1.0.0`

Target: the complete definition of done in
`docs/instant-swift-data-goals.md` passes from a clean checkout with reproducible
Swift/TypeScript evidence and benchmark artifacts.

### V1 readiness audit — 2026-07-19

The `v0.4.0-apps-e2e` matrix closes the syntax, app-port, live data-plane,
schema, permissions, auth, sharing, storage, room, presence/topic, and stream
acceptance rows. The remaining work is narrower than another port phase.

The artifact-aware parity gap is closed through `ffc9ea3`. The coverage reader
now accepts the strict CloudKitDemo V3 fresh-app shape as evidence for both
live-transport directions without changing the static source ledger, and the
fresh-app gate writes its own `swift-coverage-final.json`. The clean run at
`/tmp/instant-data-swift-cloudkit-demo-v3-20260719T095155Z/evidence.json`
records 295 cases: 28 exact, 265 adapted, 2 not applicable, and zero blocked.

No V1 release packets remain. `validation/verify-v1-release.sh` composes the
app boundaries, artifact-aware zero-blocked coverage, benchmark comparison,
full Swift suite, isolated macro lane, runnable products, and complete
TypeScript matrix into one archiveable command.

The performance packet is complete through `08a9295`. The release-mode gate
compares 15 equivalent logical workloads across Swift and canonical TypeScript
1.0.49, including durable enqueue, offline restore, and reconnect outbox drain.
Swift is slower in all 15 measurements on the recorded Apple M1 Max, so the
checked baseline names and quantifies 15 optimization targets instead of
masking them behind an aggregate pass. The three durable runtime workloads
record deterministic local Swift actor-hop breakdowns, and the fresh live
Todos gate separately measured authenticated connect, two accepted mutations,
offline enqueue, and real reconnect drain with zero compiler/runtime warnings.
The combined checked evidence is
`validation/benchmarks/v1-cross-sdk-performance-2026-07-19.json`.

The clean gate passed at revision `95bd966` and is bound to the annotated
`v1.0.0` tag. Evidence is in
`/tmp/instant-data-swift-v1-release-20260719T103430Z/evidence.json`: 1,106 Swift
tests across 96 suites, 28 isolated macro tests, all 14 runnable products, the
complete TypeScript matrix, 295 classified parity records with zero blocked,
15 quantified benchmark workloads, fresh CloudKitDemo and Todos app
boundaries, live actor-hop evidence, and zero compiler/runtime warnings.

The locally adapted magic-code extra-fields test can be promoted with live
transport evidence when that auth surface is revisited, but it is not an
unclassified parity hole: the ledger already names the upstream test, Swift
tests, adaptation, and remaining transport difference.

## Porting Discipline

For every canonical Instant behavior, port the upstream source-of-truth test
before implementing or extending the Swift behavior:

1. Name the pinned upstream test file and test case in the Swift test.
2. Preserve the upstream inputs, event order, and assertions where the SDK
   architecture permits an exact port; document every necessary adaptation.
3. Run the ported test red before changing production code whenever the
   behavior is not already implemented.
4. Implement only enough production behavior to satisfy the ported contract,
   then add narrow Swift-specific lifecycle or concurrency boundary tests.
5. Update `InstantParityCoverage` when the port becomes more exact or an old
   adaptation note is no longer true.

Local design probes and convenience tests do not replace the pinned upstream
test ports.

## Execution Packets

### Packet 0: Restore a trustworthy green baseline — complete

Purpose: remove uncertainty before changing the public API or transport.

- Diagnose the five failing tests listed above.
- Add the required `SAFETY:` ownership comment for the unchecked WebSocket
  wrapper only after confirming the actual serialization guarantee.
- Determine why the platform-adapter runner emits four new cancellation rows
  while its public test still expects 25 rows.
- Fix the local-integration regression where the CLI reports one room member
  while the test requires two.
- Reconcile cancellation evidence counts and benchmark actor-hop expectations
  with the implementation that produced them.
- Fix real regressions; update expectations only for verified intentional
  behavior.
- Run the full local suite and local E2E harness.
- Keep this separate from V3 syntax changes.

Commit target: `Restore deterministic validation baseline`.

### Packet 1: Freeze and compile the direct fetch lifecycle — complete

Purpose: turn the recordings-list sketch into the first executable V3 slice.

The public `InstantQuery` spelling, `.instantFetch($rows, query)` modifier, and
VoiceTrail-shaped compile fixture are implemented. Existing dynamic `FetchAll`
tests prove cached initial state, query replacement, stale-subscription
cancellation, and error preservation.

- Add a small VoiceTrail fixture target or compile-test fixture.
- Implement the chosen dynamic attachment spelling for `@FetchAll`.
- Make the wrapper own subscription task creation, replacement, cancellation,
  cached initial emission, and error state.
- Prove search/scope changes cancel stale observation and install the new query.
- Keep `@Fetch` reserved for the rows-plus-counts composite variant.
- Update the V3 decision log and recordings-list sketch to exactly match the
  compiling fixture.

Commit target: `Compile V3 recordings list fetch lifecycle`.

### Packet 2: Add typed message sends and change envelopes — complete

Purpose: make V3 mutations compile and preserve optimistic/server semantics.

Commits `4e5fea1`, `524028f`, and `2fbcb29` add durable transaction-specific
lifecycle events, the public `InstantMessage`/`db.send` surface, and the
VoiceTrail rename fixture. The tests prove optimistic and accepted callbacks
once, failure once, passive-refresh isolation, and retry without replay.

- Add `db.send(message, onOptimisticCommit:onServerAccepted:onFailure:)` over
  the existing transaction/outbox core.
- Generate or explicitly define the smallest typed change envelope needed by
  the recordings-list rename flow.
- Guarantee callbacks run once for their corresponding action phase.
- Keep passive remote refreshes from invoking local action callbacks.
- Prove optimistic state, server acceptance, server rejection, relaunch, and
  retry behavior.

Commit target: `Add V3 typed message mutation lifecycle`.

### Packet 3: Promote live validation transport into the runtime

Purpose: reach real bidirectional sync as quickly as possible.

- Give the runtime one owned live-session state machine.
- Send `init`, authenticate, install queries, receive refreshes, apply canonical
  join rows, and advance the transaction checkpoint.
- Send outbox transactions and correlate `transact-ok`/refresh/rejection with
  durable pending mutations.
- Reconnect with bounded backoff, resubscribe active queries, rejoin rooms, and
  resume outbox drain.
- Route normal public clients and wrappers through this session; eliminate the
  validation-only architectural fork.

Commit targets, split if needed:

1. `Own authenticated live session in runtime` — implemented in `1c627e8`.
2. `Apply live refreshes through public subscriptions` — implemented in
   `af88570` and `ecf2145`.
3. `Drain durable outbox through live session` — implemented in `378b76f`.
4. `Reconnect and restore live runtime state` — query and durable-outbox
   restoration implemented in `abe63c5`; outgoing room/presence/topic
   restoration implemented in `4138549` and `44c11b1`; incoming ephemeral
   room events implemented in `a98fe60`; stream reader restore, retry, and
   inline materialization implemented through `029a3db`. File-backed stream
   fetching and remaining storage transport are still open.

Each commit must have its own boundary case and pass the existing local suite.

### Packet 4: Pin and enforce the canonical TypeScript contract

Purpose: make “exact shape” reproducible.

- Replace `latest` TypeScript dependencies with exact versions or workspace
  references tied to the pinned `upstream/instant` revision.
- Commit the lockfile used by validation.
- Add `typecheck` and `test` scripts; do not rely on `tsx` execution alone.
- Record the Swift package revision, TypeScript package versions, upstream
  commit, app id, and schema hash in every boundary evidence run.
- Compare normalized values for strings, booleans, integers/doubles, dates,
  JSON, enums, optional absent/null values, IDs, lookup refs, one/many links,
  `$users`, `$files`, and transaction metadata.
- Treat unknown fields, lossy number/date conversion, missing required fields,
  and enum decode failures as explicit warnings or errors with stable codes.

The dependency and generated-contract subgate is complete through `8ebc352`,
`9c8a338`, and `510f5e5`: no `latest` dependencies remain, the pnpm lockfile is
committed, generated and pulled recording artifacts type-check against
`@instantdb/core`/`admin`/`instant-cli` 1.0.49 and TypeScript 5.9.3, and evidence
records the upstream revision and artifact hashes. The remaining Packet 4 work
is the full normalized value/error matrix across actual cross-SDK data.

### Packet 5: Make schema and permissions deployable acceptance inputs

Purpose: prove generation against the server, not only fixture text.

- Keep Swift declarations as the source for schema and permissions fixtures.
- Type-check generated TypeScript against the pinned SDK.
- Create/reset an ephemeral validation app and install the generated contract.
- Read the server schema back and compare normalized entities, attributes,
  links, and permissions. Room declarations are local SDK type metadata: prove
  their generated shape with strict TypeScript compilation because the
  canonical schema migration omits them and a fresh server pull returns
  `rooms: {}`. Prove their behavior separately through live room traffic.
- Fail on generated drift or manual fixture edits.

Commit targets:

1. `Type-check generated Instant schema and permissions`
2. `Install and verify generated contract on ephemeral app`

The recording-action acceptance instance of both targets is complete through
`8ebc352`–`e27c446` and `eb35a31`. The checked-in live command creates a fresh
ephemeral app, pushes, pulls, verifies, type-checks, emits non-secret evidence,
and refuses dirty-worktree or upstream-revision drift. Broader app schemas and
permission sets remain future Packet 5 inputs.

### Packet 6: Auth and two-user sharing

Purpose: make permissions meaningful end to end.

- Implement the V3 `@InstantAuth` state machine over real transport. The public
  state owner, provider contract, executable syntax fixture, local lifecycle,
  and durable relaunch proof are implemented in `c82b3ca` through `2e7c9d5`.
  Credentialed server verification, restoration, sign-out invalidation, and
  rejection by both SDKs are implemented through `c2847fa`.
- Prove session restoration and sign-out invalidation.
- Create owner/reader/writer identities and a share link.
- Prove allowed and rejected reads/writes from both SDKs.
- Reconcile rejected optimistic writes and expose actionable recovery text.

The sharing boundary now runs across both SDKs. Run the guarded verifier
against sourced ephemeral credentials:

```bash
INSTANT_SWIFT_DATA_ALLOW_EPHEMERAL_APP_MUTATION=1 \
  validation/verify-sharing-contract-live.sh
```

It generates from Swift, pushes and pulls schema/perms, verifies server
normalization, strictly type-checks the pulled artifacts, creates fresh owner,
reader, writer, and outsider identities, launches the normal Swift WebSocket
runtime as the reader, and writes non-secret aggregate evidence. The Swift
reader must observe server value `1`, optimistic rejected value `2`, and
refetched server value `1`, with zero pending mutations and one retained failed
mutation. Commit `fd52385` adds the Swift-side allowed writer path, and the
aggregate `validation/verify-v0.3-schema-auth-sharing.sh` gate now requires all
schema, permission, reader, writer, restoration, sign-out, and invalidation
assertions together on one clean revision.

Commit targets:

1. `Run V3 auth through live Instant transport`
2. `Prove two-user sharing and permission rejection`

### Packet 7: Complete remaining V3 wrappers

Implement in independently gated commits:

- `@InstantSyncStatus`
- queryable `$files` and upload/delete progress
- `@Room`, `@Presence`, and `@Topic` — compiling and lifecycle-tested through
  `a7c1ad3`, `9fe9c25`, `031e4fe`, and generated-schema typechecking in
  `8b979c0`; canonical cross-SDK boundary pending
- `@LocalID` — compiling and lifecycle-tested through `709b58d`
- composite `@Fetch` and `@InstantFetchBuilder`
- recording-specific message flows — start, finish, attachment, canonical refs,
  rejection, relaunch, and exact bidirectional live SDK projection covered
  through `4a9b7eb`, `33028f6`, and `771ed4c`
- playback-specific room/presence/topic flows

Every wrapper must have local lifecycle tests and a canonical TypeScript
boundary case when it represents remote data.

### Packet 8: Run apps through the real public surface

Purpose: replace CLI/model-only confidence with working app acceptance.

- Start with the five VoiceTrail V3 fixture screens as a coherent app.
- Port required examples in the order that expands surface coverage fastest:
  todos, auth, chat/mobile-chat, presence/topic recipes, Reminders sharing,
  SyncUps, storage/app-builder, streams, and CloudKitDemo-equivalent sharing.
- Keep app business logic in testable models and public wrappers.
- Remove fixture-only adapters as their public equivalents become available.

## End-to-End Shape Matrix

The release harness must prove each applicable row in both directions:

| Surface | Swift to TS | TS to Swift | Failure proof |
| --- | --- | --- | --- |
| Scalars/optionals | exact value/absence | exact decode | required/type mismatch |
| Dates/numbers | canonical wire value | no lossy decode | overflow/invalid date |
| JSON and enums | exact nested shape | typed decode | unknown enum/case shape |
| One/many links | nested canonical query | typed includes/reverse links | invalid link/lookup |
| Optimistic writes | observed after accept | remote refresh observed | rollback/reconcile |
| Offline/reconnect | queued then visible | server changes restored | bounded retry |
| Auth | session accepted | session refresh observed | invalid/expired token |
| Sharing/permissions | owner/writer succeeds | role changes observed | reader/outsider denied |
| Presence/topics | Swift event observed | TS event observed | disconnect cleanup |
| Files | metadata/content visible | metadata/content decoded | permission/upload failure |
| Streams | ordered chunks visible | ordered chunks decoded | cancellation/backpressure |

## Required Gates

### Packet gate

- Focused tests for the changed seam.
- Full `swift test` green.
- Swift 6 strict-concurrency build green.
- Generated artifacts unchanged unless the packet intentionally changes them.

### Contract gate

- TypeScript install uses the committed lockfile.
- TypeScript type-check and fixture tests pass.
- Swift local validation and TypeScript contract consumption pass.
- No unexpected Swift or TypeScript warnings.

### Live milestone gate

- A fresh or reset Instant validation app uses the generated schema and perms.
- Swift-to-TypeScript and TypeScript-to-Swift live cases pass.
- The relevant permission rejection case passes.
- Evidence JSONL contains revisions, schema hash, stable case ids, exact
  expected/actual data, warnings, latency, and success status.
- The milestone is rerun from a clean checkout before its annotated tag.

## Immediate Next Step

The V3 recordings-list boundary is complete through `ea978d0`, `99ab8a0`,
`4bba77f`, `d7f92ce`, and `6fa8019`. The fixture now uses canonical
`v3_capture_recordings` owner/readers/writers links plus the share and
viewer-filtered membership graph; the public syntax remains `@FetchAll` plus
`.instantFetch($rows, rowsQuery)`. The live gate creates a fresh app, installs
the Swift-generated VoiceTrail schema and permissions, type-checks the exact
TypeScript graph, and proves owner, reader, reader-to-writer replacement,
revocation-to-empty, and cancellation through the normal Swift WebSocket
runtime. Clean evidence for revision `6fa8019` is at
`/tmp/instant-data-swift-voice-trail-recordings-20260718T234408Z/evidence.json`.

That gate also closed two cross-SDK runtime gaps: typed relation predicates now
encode canonical dotted ID paths such as `owner.id`, and `refresh-ok` replaces
each query's authoritative triple set while retaining triples still owned by
another active query. Full verification is green at 912 Swift tests in 37
suites plus the generated-contract and TypeScript fixture suites.

The playback disconnect/rejoin boundary is complete through `45daf84`,
`2faa5bf`, `3f916f6`, `66049f5`, and `ece3022`. The recorded `@Room`,
`@Presence`, and `@Topic` syntax did not need to change. The source chain is
the pinned Reactor room loop, the Swift parity test, the shared TypeScript
payload contract, and `validation/verify-playback-room-contract-live.sh`.
Clean evidence for revision `ece3022` is at
`/tmp/instant-data-swift-playback-room-reconnect-clean-ece3022-20260718T1957Z/evidence.json`.

The preferences boundary is complete through `4ddf46b`, `ff71165`, `7176dfa`,
`cd8f8d5`, `6038411`, `9e6868f`, `5214b59`, `15fb55f`, and `02e06cf`. The syntax in `screens/v3/preferences.md` remains the
target: `@ConnectionStatus`, `@InstantSyncStatus`, and `@InstantStorageStatus`
own observation and renderable state, while flush and clear-download actions
use call-site callbacks. The source tests cover every recorded sync phase and
exact local-cache, stream-cache, and downloaded-file measurements. The clean
fresh-app gate at revision `1e81ab1` authenticates the public wrapper, measures
12 stream bytes and 7 downloaded bytes, clears exactly one 4-byte audio file,
and retains the transcript with zero warnings.

The first integrated live packet is complete through `6e649b0`, `e970238`,
`9bc6fc2`, `28b6cc7`, `75a02c4`, and `636c922`. `VoiceTrailV3App` owns the five
settled screens and
`voicetrail-v3` is the thin executable host. The capture screen now sends its
public start, attachment, and finish messages; its local app test verifies the
exact durable recording, transcription, and attachment shapes. The clean
aggregate gate at `636c922` creates a fresh app, pushes and reads back the
generated contract, drives create, attachment, and finish through the same
`db.send` server-acceptance lifecycle as the capture screen, and observes the
exact final graph through canonical TypeScript: recording `finished`, duration
`12_750`, transcription `ready`, and a screenshot attachment at offset `2_500`.
It also runs the recordings, playback, preferences, and auth live contracts on
the same app with zero compiler/runtime warnings. Evidence is at
`/tmp/instant-data-swift-voice-trail-v3-app-20260719T004933Z/evidence.json`.

The playback binding is complete in `7cad7ee` and `1dcee4b`. The app target now
owns `recording.playback`, presence, reaction, comment-draft, and
comment-committed payloads. The clean aggregate rerun proves those app types in
both directions before and after forced reconnect. Evidence is at
`/tmp/instant-data-swift-voice-trail-v3-app-20260719T005834Z/evidence.json`.

The Todos app boundary is complete through `122d4e0`. `todos-v3` is a thin
runnable SwiftUI host over the shared `TodosV3App` target. Its clean fresh-app
gate proves the requested `@InstantEntity`, `@FetchAll`, typed-message, room,
presence, and offline/reconnect surface through the real Swift and canonical
TypeScript SDKs. The final run observed one remote viewer and exactly one
offline mutation before reconnect, then zero pending mutations after server
acceptance. Evidence is at
`/tmp/instant-data-swift-todos-v3-20260719T012426Z/evidence.json`.

The standalone Auth boundary is complete through `9c0b683`. `auth-v3` is a
thin runnable SwiftUI host over `AuthV3App`; the shared module owns the user,
five-provider catalog, bootstrap, and login screen. VoiceTrail consumes that
same module. Its clean fresh-app gate proves app-owned `signedIn`, relaunch,
and `signedOut` states around the canonical server-verified token lifecycle,
including TypeScript rejection after invalidation. Evidence is at
`/tmp/instant-data-swift-auth-v3-app-20260719T013823Z/evidence.json`.

The Mobile Chat app boundary is complete through `5f3276a`. The desired syntax
is no longer an open design question for this slice: the app target compiles it,
the source-first schema and live-evidence tests pin it, and the clean getadb gate
proves it against canonical TypeScript SDK 1.0.49. Evidence is at
`/tmp/instant-data-swift-mobile-chat-v3-20260719T022106Z/evidence.json`. Full
verification is green at 939 Swift Testing cases across 48 suites, 28 macro
tests, and the complete TypeScript typecheck, contract, and fixture matrix.

The first presence recipe boundary, Typing Indicator, is complete through
`2c36ab7`. The app and helper tests pin the exact upstream
`typing-indicator-example/1234` room, `id` and `chat-input` keys, one-second
timeout replacement, write-only behavior, and cleanup. The clean fresh-app gate
proves the four exact presence frames in both directions without widening or
lossy normalization; `null` remains `null`. It also proves remote-peer cleanup,
zero app namespaces or permissions, five exact server system-schema warnings,
and zero compiler/runtime warnings. Evidence is at
`/tmp/instant-data-swift-typing-indicator-v3-20260719T025123Z/evidence.json`.
Full verification is green at 950 Swift Testing cases across 51 suites, 28 macro
tests, and the complete TypeScript typecheck, contract, and fixture matrix.

The Reactions topic recipe is complete through `e84679b`, with its final clean
live evidence recorded at `e1f100a`. The desired
`@Room`/`@Topic` syntax compiles in `PresenceRecipesV3App`, and the clean
fresh-app gate proves the exact payload in both directions plus unsubscribe
cleanup. Evidence is at
`/tmp/instant-data-swift-reactions-v3-20260719T032236Z/evidence.json`. Full
verification is green at 960 Swift Testing cases across 54 suites, 28 macro
tests, the `presence-recipes-v3` build, and the complete TypeScript typecheck,
contract, and fixture matrix.

The Avatar Stack presence recipe is complete through `22980dc`; credential
redaction was source-tested first in `cb1777d` and implemented in `7af4dd7`.
The runnable host
compiles the exact name-only `@Room`/`@Presence` surface while the wrapper keeps
peer ids out of app presence JSON. The gate proves both SDK directions, one
remote peer, disconnect cleanup to zero, empty app permissions, five pinned
server system-schema warnings, and zero compiler/runtime warnings. Evidence is
at `/tmp/instant-data-swift-avatar-stack-v3-20260719T034215Z/evidence.json`.
Full verification is green at 971 Swift Testing cases across 57 suites, 28
macro tests, the `presence-recipes-v3` build, and the complete TypeScript
typecheck, contract, live-support, and fixture matrix.

The canonical Cursors presence recipe is complete through `fb946c0`, with its
fresh-app gate recorded at `e09d871`. The shared host compiles the desired
`@Room`/`@Presence` surface, and the exact dynamic cursor-space payload is
generated, verified, strict-typechecked, and observed through both Swift and
canonical TypeScript SDK 1.0.49. Clear removes the remote cursor while keeping
the peer connected; disconnect then removes the peer. The clean gate recorded
the expected empty app schema and permissions, five exact server system-schema
warnings, schema SHA-256
`50085a139e9caba2a19686194f31fa6fa4d8dae66f1aef2292ca3f7a8e4394ae`,
permissions SHA-256
`fbedb26406126ca62a8725cb698494ac186944ebd4a0c15288ba8b0fc989ba37`,
and zero compiler/runtime warnings at
`/tmp/instant-data-swift-cursors-v3-20260719T040045Z/evidence.json`. Full
verification is green at 982 Swift Testing cases across 60 suites, 28 macro
tests, the `presence-recipes-v3` build, and the complete TypeScript typecheck,
contract, live-support, and fixture matrix.

The canonical Custom Cursors presence recipe is complete through `8f3e9e2`.
The shared host compiles the desired `@Room`/`@Presence` surface with required
top-level `name`, exact dynamic cursor data, and the canonical encoded avatar
URL. The clean fresh-app gate proves Swift name/cursor publication in
TypeScript and TypeScript name/cursor publication in Swift. Clearing the
dynamic key produces zero remote cursors while retaining one named peer;
disconnect then removes that peer. The gate recorded the expected empty app
schema and permissions, the same five exact server system-schema warnings,
schema SHA-256
`50085a139e9caba2a19686194f31fa6fa4d8dae66f1aef2292ca3f7a8e4394ae`,
permissions SHA-256
`fbedb26406126ca62a8725cb698494ac186944ebd4a0c15288ba8b0fc989ba37`,
and zero compiler/runtime warnings at
`/tmp/instant-data-swift-custom-cursors-v3-20260719T042442Z/evidence.json`.
Full verification is green at 992 Swift Testing cases across 63 suites, the
`presence-recipes-v3` build, and the complete TypeScript typecheck, contract,
live-support, and fixture matrix.

The canonical Merge Tile Game recipe is complete through `59a5e2d`, with its
clean fresh-app gate recorded at the same revision. The runnable host compiles the app-owned
`@FetchOne` board, typed initialize/merge/reset messages, and
`@Room`/`@Presence` color surface. Canonical TypeScript observes Swift's
`0-0` merge and Swift color, then publishes a distinct `0-1` merge and color;
both SDKs retain both cells in the exact 16-cell board. Swift then observes the
canonical full-board reset and TypeScript disconnect. The server-readback gate
records one app entity, two attributes, no links, one four-rule permissions
namespace, the five system-schema warnings plus explicit
`server-json-as-any` for `boards.state`, schema SHA-256
`08c7de132f7de3268c04472cbe72136d82f5b94b5e5bbb2159c0f896b1fed7b9`,
permissions SHA-256
`f1192523fd4726637595a197e42319a6658b46def546deea051329b55e505231`,
and zero compiler/runtime warnings at
`/tmp/instant-data-swift-merge-tile-game-v3-20260719T045650Z/evidence.json`.
Full verification is green at 1,007 Swift Testing cases across 66 suites, the
`presence-recipes-v3` build, and the complete TypeScript typecheck, contract,
live-support, and fixture matrix.

The canonical Stroopwafel app is complete through `3584c15`. Its pinned source
tests define the desired syntax and exact durable graph before implementation;
the runnable SwiftUI host, generated schema/permissions, canonical TypeScript
contract, and fresh-app verifier now pass together. The final gate records four
entities, 21 attributes, four links, 17 allow rules, exact normalized server
warnings, schema SHA-256
`fc1bbbe52ed594dc72dd46501c2fb14e419b0974b6db946176cfe08c600f0813`,
permissions SHA-256
`e693f551cf212c8b8d5425aadcf4cebae590119cf9663f9b09b956d553ef356b`,
and zero compiler/runtime warnings at
`/tmp/instant-data-swift-stroopwafel-v3-20260719T054351Z/evidence.json`.
The post-port aggregate is green at 1,027 Swift Testing cases across 71
suites, the `stroopwafel-v3` build, and the complete TypeScript typecheck,
contract, live-support, and fixture matrix.

The canonical Reminders app is complete through `e72c99a`. The clean fresh-app
gate records six namespaces, 29 attributes, nine links, 21 allow rules, exact
normalized server warnings, canonical TypeScript `Date` objects, both data
directions, reader write denial before writer promotion, outsider invisibility,
and zero compiler/runtime warnings at
`/tmp/instant-data-swift-reminders-v3-20260719T070753Z/evidence.json`. The
post-port aggregate is green at 1,049 Swift Testing cases across 76 suites and
the complete TypeScript typecheck, contract, live-support, and fixture matrix.

The canonical SyncUps app is complete through `b689469`. The clean fresh-app
gate records three entities, nine attributes, two required links, twelve allow
rules, the two exact server-canonical link-name warnings, canonical TypeScript
`Date` objects, both nested data directions, authenticated Swift state, zero
pending mutations, and zero compiler/runtime warnings at
`/tmp/instant-data-swift-syncups-v3-20260719T073704Z/evidence.json`. The
post-port aggregate at `194ef4d` is green at 1,067 Swift Testing cases across
83 suites, the `syncups-v3` build, and the complete TypeScript typecheck,
contract, live-support, and fixture matrix.

The canonical App Builder and Storage slice is complete through `7f9acc5`.
The clean fresh-app gate records three authored namespaces, thirteen authored
attributes, two links, five allow rules, eight exact server-normalization
warnings, both generated-code directions, server-issued file ids, canonical
Storage metadata, exact downloaded `App.tsx` bytes in both SDKs, authenticated
Swift state, zero pending mutations, and zero compiler/runtime warnings at
`/tmp/instant-data-swift-app-builder-v3-20260719T082431Z/evidence.json`.
During the live gate, `where(owner == ownerID)` also exposed and fixed generic
overload selection so typed relation filters now lower to canonical dotted id
paths, and the owner list was brought back to the pinned source by removing an
unsupported non-indexed server order.
The post-port aggregate passes 1,083 Swift Testing cases across 90 suites, 28
macro tests, the runnable app build, and the complete TypeScript matrix.

The Streams V3 boundary is complete through `2ec8a17`. The clean fresh-app
gate proves exact ordered UTF-8 content and server-issued identities in both
SDK directions using the pinned AI-chat and resumable-stream sources. The
runtime packet also covers file-backed reads, cancellation, bounded retries,
reader and writer reconnect, metadata bootstrap, and terminal flush
acknowledgement. Evidence is at
`/tmp/instant-data-swift-streams-v3-20260719T092305Z/evidence.json`; the
post-port aggregate passes 1,096 Swift Testing cases across 92 suites plus 28
macro tests.

Packet 8 is complete through `f3ee07c`. The final CloudKitDemo-equivalent app
uses the settled sharing namespaces and public wrappers, and its clean
fresh-app boundary proves owner, read-only, read-write, denial, role
replacement, revocation, exact cross-SDK increments, visible share state, and
relaunch. Evidence is at
`/tmp/instant-data-swift-cloudkit-demo-v3-20260719T093505Z/evidence.json`; the
post-port aggregate passes 1,100 Swift Testing cases across 94 suites, 28
isolated macro tests, the runnable app build, and the complete TypeScript
matrix. Next, audit the full `v1.0.0` goals definition against the accumulated
evidence and schedule only the remaining gaps.

The product-payload mismatch is resolved: playback presence stores and encodes
`offsetSeconds: Double`, offers `Duration` as a computed product convenience,
and includes optional `focusedSegmentID`. Typed `InstantID` values encode as
canonical strings while retaining legacy keyed-shape decoding. The live room
gate must assert this exact presence shape.

The recording-screen fixture remains independent of the stream app gate; its
stream-cache measurement does not replace the required cross-SDK stream proof.
