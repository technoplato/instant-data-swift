# Cross-Repository Commit Changelog

Newest entries go at the top. Timestamps include seconds and use Eastern Time
(`America/New_York`). Each substantive commit records the repository, full
commit SHA, and high-level reason. Changelog-only bookkeeping commits are
visible in Git history but are not self-recorded because a commit cannot
contain its own final SHA.

## July 28, 2026 at 9:11:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6f2d44d6ba7f16c2594911180f6cd1009f77de2a`
- High-level reason: Stream ReplayKit screen video and app audio from iPhone
  through LiveKit WebRTC to a dedicated Mac receiver while preserving the
  existing transcription and periodic screen-image handoff paths.

## July 28, 2026 at 8:28:02 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `18ad7afe3a9aacf578c0743c8f566e180811673c`
- High-level reason: Keep the live bottom margin proportional in extremely
  short landscape transcript viewports instead of allowing its minimum clamp
  to push all current text off screen.

## July 28, 2026 at 8:24:11 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `176aefd04691641ed5d4a597f1926deabc3ded4e`
- High-level reason: Re-anchor a following live transcript after viewport-size
  changes so rotation and window resizing keep the newest line on its lower
  reading line.

## July 28, 2026 at 8:13:24 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `f1f65dabf5472863b2c0e197a6a9bfa8139a414d`
- High-level reason: Give short live transcripts a viewport-aware minimum
  content height so the newest line reaches the same lower-screen reading
  position as long scrolling transcripts.

## July 28, 2026 at 8:10:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `553ff85130037033d32e0cf2811cdd03394cf4ee`
- High-level reason: Show a satellite uplink icon on the recording page's
  native ReplayKit broadcast launcher while keeping periodic screen-frame
  attachments as a separate opt-in control.

## July 28, 2026 at 8:00:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `9ce87285f352aa467642ba94b8bb58d2399d98c4`
- High-level reason: Add bounded transcript voice commands and a bottom-pinned
  full-screen reader, disable all automatic heart-rate workout consumption,
  document the guest App Clip path, and expose the supported CarPlay surfaces.

## July 27, 2026 at 8:49:00 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `52a8c458b0adb5aa35152f3db357bac83b2d7c7d`
- High-level reason: Add a minimal recording App Clip that creates or reuses an
  Instant guest session, uploads a finalized M4A, waits for server
  acknowledgement before showing Saved, and preserves failed drafts for retry.

## July 27, 2026 at 7:20:14 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `48dff46f57070548884e3430311bcdedb4de2859`
- High-level reason: Remove the redundant speech-provider icon from the Home
  recording control and constrain the live transcript to a vertical,
  viewport-width scroll surface so horizontal swipes cannot shift the text.

## July 27, 2026 at 6:24:23 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `eabe24c19933ede3f90845a917c6909d2d79f775`
- High-level reason: Add runtime-selectable Apple Speech Analyzer transcription
  with on-device model preparation, time-indexed progressive results, explicit
  finalization, visible device-local provider controls, and an immutable
  Deepgram-or-Apple choice for each active microphone and system-audio session.

## July 27, 2026 at 4:20:15 PM EDT

- Repository: `realtime-voice-sqlite-instant`
- Commit: `d20544726099fbe95c4c3332434097851ceac3e8`
- High-level reason: Keep live Watch heart-rate samples associated with the
  requesting iPhone recording, bound the relay, replace indefinite waiting
  with an actionable timeout, and expose the full recovery message.

## July 27, 2026 at 4:06:21 PM EDT

- Repository: `instant-data-swift`
- Commit: `c0514a7c3dff580766b6bc689271f5c8c1a7d571`
- High-level reason: Remove repeated full-snapshot sorting from optimistic
  live-data rebases after physical iPhone and Apple Watch CPU reports
  identified it as the shared recording-freeze hot path.

## July 27, 2026 at 2:14:01 PM EDT

- Repository: `instant-data-swift`
- Commit: `442dc5e9182c98f9c3af6ac88d410f956d9aa084`
- High-level reason: Preserve the repeated clean current-head signing result,
  ready Watch state, and protected-log freshness boundary without presenting
  compilation as installation or runtime acceptance.

## July 27, 2026 at 2:00:16 PM EDT

- Repository: `instant-data-swift`
- Commit: `c6f8e84048312857c195a1d1d9206d6bd8edfe0c`
- High-level reason: Reconcile the cross-repository audit with the final
  server-acknowledged delivery fix, full suites, clean six-lane performance
  evidence, and the exact unsigned-versus-signed physical Watch boundary.

## July 27, 2026 at 1:55:54 PM EDT

- Repository: `instant-data-swift`
- Commit: `c211737939daaba1641dfce5b7cf700d3743778d`
- High-level reason: Availability-gate the Duration-based live delivery waiter
  so InstantSwiftData continues compiling for its iOS 15 and watchOS 8 package
  deployment targets while newer Scribe targets use the explicit server-ack
  boundary.

## July 27, 2026 at 1:43:44 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `30068d53ad186c2c1c6bedc85f0026e9779e6d28`
- High-level reason: Make explicit logger and replay durability boundaries wait
  for actual Instant server acknowledgement instead of invoking a local
  mutation transport that could remove outbox work before remote observation.

## July 27, 2026 at 1:42:48 PM EDT

- Repository: `instant-data-swift`
- Commit: `e228326c4059227aa0171495cbe902110ebcf9c5`
- High-level reason: Wait for actual live server acknowledgement without
  locally confirming the durable outbox, and preserve causally required older
  scalar writes during ordered replay while continuing to filter isolated
  stale retries.

## July 27, 2026 at 1:20:59 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `5e96ee33b3984a91e64bfe61b65e726c373af033`
- High-level reason: Carry Deepgram finalization acknowledgements through the
  transcript stream and hold stop persistence behind a reducer-owned,
  five-second-bounded provider acknowledgement so the final transcript cannot
  be discarded by the former fixed 500 ms delay.

## July 27, 2026 at 1:05:33 PM EDT

- Repository: `instant-data-swift`
- Commit: `82b74dd2267d325c500852cb43a850d1c5783172`
- High-level reason: Reject stale live-refresh writes atomically, preserve
  migration and relaunch ownership boundaries, normalize duplicate canonical
  query computations with final-result-wins semantics, and serialize live
  registration with durable pruning.

## July 27, 2026 at 1:02:29 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d52ca57adf558e86bbe35a4a1c949fb53f4c099e`
- High-level reason: Keep the live Apple Watch BPM and exact failure reason
  visible outside the compressed iPhone recording toolbar, and let the active
  recording retry the dependency-controlled heart-rate session without showing
  a stale sample.

## July 27, 2026 at 12:55:33 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0c71d6e4b2c7266d42ba508d5377ee0184aa0617`
- High-level reason: Bound diagnostic action-key extraction to known TCA enum
  wrappers so payload cases cannot replace the real leaf action or trigger an
  unbounded CustomDump traversal; refresh the committed heart-rate snapshot and
  restore the 466-test Scribe suite.

## July 27, 2026 at 12:39:15 PM EDT

- Repository: `instant-data-swift`
- Commit: `5f75dc984510e26fc80502b8550bee33b525e397`
- High-level reason: Apply Reactor-aligned age, entry, and owned-triple bounds
  to durable live query results; preserve active and optimistic owners; and
  transactionally collect only global triples whose final semantic owner is
  gone.

## July 27, 2026 at 12:28:17 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `a76f39a96ec6ad3ef13dc0f17dd120725249247f`
- High-level reason: Model simulator heart-rate streams behind the Point-Free
  dependency boundary with controlled clocks and dates while preserving the
  live HealthKit and WatchConnectivity dependency on physical devices.

## July 27, 2026 at 12:27:31 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `ed2a0b7a3cf19b06d6ab331d392b825701192561`
- High-level reason: Make iPhone and Watch transcript sections seekable, keep
  Watch playback following the active section, configure spoken-audio output,
  expose the active route, and peak-normalize unusually quiet PCM for playback.

## July 27, 2026 at 12:26:49 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `04d905d60a6c7238388a38e12df6343f9a4aa4e0`
- High-level reason: Make the Watch converge on a late-arriving paired-iPhone
  account session, automatically page the full recording library, expose its
  exact total, and remove the Watch-only eight-recording display cap.

## July 27, 2026 at 12:10:19 PM EDT

- Repository: `instant-data-swift`
- Commit: `f9c5e9f12fc34435659c6a7c6a6ca4fec1b248e5`
- High-level reason: Persist canonical live-query triples and page information
  atomically with server refreshes, restore ownership across relaunch, and
  retract only rows no longer owned by any durable query.

## July 27, 2026 at 12:08:06 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7db22dc7ab01f38b4c92e2dec15364fedfdca4e5`
- High-level reason: Add strict live Apple Watch heart-rate measurement to
  active recordings using an acknowledged WatchConnectivity control channel,
  a HealthKit workout session, fresh-sample enforcement, and recording UI on
  both the Watch and paired iPhone.

## July 27, 2026 at 12:01:58 PM EDT

- Repository: `instant-data-swift`
- Commit: `f6041883ed4b5bae5324311d7c64baa279b8fcae`
- High-level reason: Replace the unbounded live infinite-query subscription
  with limited starter, forward, and reverse cursor chunks; atomically apply
  authoritative page windows; freeze loaded intervals; preserve local-first
  starter rows; and cancel every replaced or final Reactor registration.

## July 27, 2026 at 11:51:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `12ae2e7495bdcd51bcc20d8f9bde38340dca7544`
- High-level reason: Select direct Deepgram for physical-Watch production
  transcription so transient paired-phone reachability cannot terminate live
  PCM delivery, while preserving WatchConnectivity only for asynchronous
  companion responsibilities such as Instant identity bootstrap.

## July 27, 2026 at 11:35:59 AM EDT

- Repository: `instant-data-swift`
- Commit: `f5e0ce1724ee1bee3f11f7e7c873cf5fcfc8dad6`
- High-level reason: Record the accepted private opaque-cursor design, exact
  before/after pagination flow, local-cursor safety boundary, and remaining
  continuous page-info and bounded infinite-query ownership follow-up.

## July 27, 2026 at 11:34:56 AM EDT

- Repository: `instant-data-swift`
- Commit: `11edea370b20bd273fa5e0cfa5de632ff7ffa224`
- High-level reason: Preserve canonical live query page information and opaque
  Reactor cursors through decoding, persistence, one-shot materialization, and
  exact after/before re-encoding so bounded remote pagination can use server
  frontiers without reconstructing lossy client cursors.

## July 27, 2026 at 11:21:38 AM EDT

- Repository: `instant-data-swift`
- Commit: `f3e9fe041f1e67e0410c3a585cf162f941cca08f`
- High-level reason: Expose the library-owned composite fetch request directly
  to actors and TCA effects, preserving the same transformed load,
  `combineLatest` observation, error, and cancellation behavior used by
  `@Fetch` without requiring wrapper state.

## July 27, 2026 at 11:12:45 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `8858d0bc75a51509416e2b06328c133e549b86a4`
- High-level reason: Preserve the clean signed production Watch build,
  successful physical installation and launch, settled passive UI evidence,
  runtime-only Deepgram override handling, and the remaining spoken-production
  acceptance boundary in the durable Watch transcription guide.

## July 27, 2026 at 11:08:30 AM EDT

- Repository: `instant-data-swift`
- Commit: `3dd5dae2996813b41e581a7cfa0a0d0a5eae5f3e`
- High-level reason: Record that the clean production `ScribeSharedWatch`
  generic build now compiles and signs for arm64/arm64_32 with strict code-sign
  verification, while preserving install and live production acceptance as
  separate remaining device work.

## July 27, 2026 at 11:02:29 AM EDT

- Repository: `instant-data-swift`
- Commit: `865ead6e670851aae223d3b61582dcbef2d9102f`
- High-level reason: Reconcile the durable audit with the complete physical
  Watch PCM/WAV/Deepgram/final-transcript proof, the production audio-policy
  port and watchOS build, the 447-test Scribe suite, and the remaining signed
  deployment, persistence, reliability-soak, and ReplayKit boundaries.

## July 27, 2026 at 10:58:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `3fe73a038202bb9838932fd56ff96f0202cf6f4b`
- High-level reason: Carry the recording-compatible Watch audio-session policy
  proven by the physical Deepgram probe into the production transcription
  path, preserve TCA ordering invariants, and document the evidence and
  operational acceptance procedure.

## July 27, 2026 at 10:45:54 AM EDT

- Repository: `instant-data-swift`
- Commit: `5aa73734891a439075a1a3997d03818feaed2ace`
- High-level reason: Record the Watch auto-run readiness fix and the final
  clean Scribe package verification of 446 tests across 47 suites.

## July 27, 2026 at 10:44:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `64692d14118d0ff25d9eac95f3526981fd55606a`
- High-level reason: Preserve proof that blocked remote diagnostics do not
  block local credential persistence while replacing scheduler-yield sampling
  with a bounded monotonic evidence window under parallel-suite load.

## July 27, 2026 at 10:43:16 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `6699ea5f5ce4542d066cebbb815bf6d6b9ee4cf2`
- High-level reason: Start the Watch probe's eight-second auto-run window only
  after capture, WAV append, and Deepgram streaming report active, so physical
  startup latency cannot consume the diagnostic recording window.

## July 27, 2026 at 10:40:47 AM EDT

- Repository: `instant-data-swift`
- Commit: `c399e0080ac882c641d032fc2d661bb7a088c8dd`
- High-level reason: Reconcile the final audit with the Watch probe's
  recording-compatible asynchronous activation policy and the authoritative
  Scribe package, performance-safety, and artifact-sanitization evidence.

## July 27, 2026 at 10:40:18 AM EDT

- Repository: `instant-data-swift`
- Commit: `01782d2945459b0c382ebb7cd6476595fcae482b`
- High-level reason: Preserve exact final suite totals and distinguish the
  physical Watch build/install/launch/prepared evidence from the remaining
  human recording and ReplayKit broadcast acceptance interactions.

## July 27, 2026 at 10:33:55 AM EDT

- Repository: `instant-data-swift`
- Commit: `a4245d7620552df9aa272b22d8a6eca82f1ca9eb`
- High-level reason: Give nonblocking utility-priority startup cookie sync a
  five-second wall-clock evidence window under parallel-suite load while
  preserving its exact request and retention assertions.

## July 27, 2026 at 10:31:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `875393835ad2cd3f802165469ce73c1259bd9b06`
- High-level reason: Keep the physical Apple Watch microphone session on the
  recording-compatible default route policy while retaining asynchronous
  activation required before opening its Deepgram WebSocket.

## July 27, 2026 at 10:30:34 AM EDT

- Repository: `instant-data-swift`
- Commit: `af4a545cd73c74750107520fe590eac98af92f73`
- High-level reason: Wait for all automatic composite-fetch observations with
  a bounded condition before asserting recorder totals, preserving exact
  observation coverage without sampling asynchronous task registration.

## July 27, 2026 at 10:29:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `39800e5d07e6a85a58698d40de38335894386118`
- High-level reason: Show the reproducible-build timestamp prominently on the
  Apple Watch audio probe so the installed diagnostic binary can be identified
  directly from its screen.

## July 27, 2026 at 10:26:14 AM EDT

- Repository: `instant-data-swift`
- Commit: `b6f72262a5dd662dc2f17b6ce10442f669dcc0d5`
- High-level reason: Remove a race-prone assertion about the transient state of
  intentional live-transport auto-connect while retaining explicit WebSocket,
  connect-opened, and close-closed behavior checks.

## July 27, 2026 at 10:23:13 AM EDT

- Repository: `instant-data-swift`
- Commit: `b7eaceccec880bdfbb6b747a9c0335bae9ca509f`
- High-level reason: Make composite fetch fixtures independent of concurrent
  task order and prevent a load-only assertion from racing an empty automatic
  observation during the full parallel suite.

## July 27, 2026 at 10:18:42 AM EDT

- Repository: `instant-data-swift`
- Commit: `25d6b9718b475657af5d4553f1434c17a6342862`
- High-level reason: Keep synthetic relaunch and migration fixtures inside the
  production cache-retention window and document the lock protecting the
  pruning cadence's unchecked `Sendable` state.

## July 27, 2026 at 10:14:50 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `cb88d6c664b88f34ce3c0d5e87ca49bf591c5958`
- High-level reason: Reuse the already bootstrapped live Instant runtime for
  Scribe's read-only local projections, eliminating the second SQLite runtime
  while retaining live freshness semantics for ordinary one-shot queries.

## July 27, 2026 at 10:14:43 AM EDT

- Repository: `instant-data-swift`
- Commit: `91578fe1e6b3da54b52939f0d8736da99b68343f`
- High-level reason: Correct the deterministic offline-relaunch benchmark to
  the measured 11-hop contract after bootstrap pruning was integrated into the
  existing persistence actor call rather than adding a new hop.

## July 27, 2026 at 10:13:43 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `bb6ca8673966a6723eecabd61a95318d06c27247`
- High-level reason: Authorize the physical Apple Watch recording session for
  long-form audio streaming and configure its Deepgram WebSocket to surface
  connection failures immediately on constrained or expensive networks.

## July 27, 2026 at 10:13:01 AM EDT

- Repository: `instant-data-swift`
- Commit: `0ba57bdbdc5e4375e91189c9b1fe40cb69bb7a4a`
- High-level reason: Prune persisted query cache rows at bootstrap and then
  every 64 successful cache writes, preserving active observations without
  adding retention work to every one-shot query.

## July 27, 2026 at 10:05:15 AM EDT

- Repository: `instant-data-swift`
- Commit: `760afdb4dee3ce23408d48b233bb8501bf481181`
- High-level reason: Derive an injectable read-only local client facet from an
  existing runtime so composition roots can use ordinary query APIs over local
  state without a second SQLite bootstrap or a public `queryLocal` method.

## July 27, 2026 at 10:03:51 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `21be1b8e764a0d78d96b962354db156e675b4877`
- High-level reason: Route Scribe's explicitly local projection loaders through
  an injected local-only Instant client sharing the live client's SQLite file,
  avoiding server acknowledgement waits without exposing `queryLocal`.

## July 27, 2026 at 9:59:16 AM EDT

- Repository: `instant-data-swift`
- Commit: `da5010dee7b70a0ee65891b2859ebc4fd8e3d2f2`
- High-level reason: Avoid re-materializing flat query observers in namespaces
  untouched by a commit while preserving conservative invalidation for
  relationship paths, includes, schema changes, and unresolved entities.

## July 27, 2026 at 9:56:00 AM EDT

- Repository: `instant-data-swift`
- Commit: `c0a030425a3191d600649fd8e69740d32ff21f7c`
- High-level reason: Invoke the Reactor-compatible query-cache retention policy
  after production one-shot writes, preserving active observation keys while
  bounding unloaded rows by age, count, and encoded size.

## July 27, 2026 at 9:48:11 AM EDT

- Repository: `instant-data-swift`
- Commit: `7ec460ab9d76362209c8a5b0e76e9664a6740cfb`
- High-level reason: Decode cardinality-one entity snapshot fields through
  schema-owned typed attribute paths, with centralized wire semantics and
  explicit namespace mismatch validation.

## July 27, 2026 at 9:45:23 AM EDT

- Repository: `instant-data-swift`
- Commit: `d3e6e704121d0c4c4431a7b346a6c1d49f6e5312`
- High-level reason: Add a dependency-controlled zero-argument typed ID
  initializer with canonical lowercase formatting, while preserving raw-value
  identity and keeping the core module independent of Dependencies.

## July 27, 2026 at 9:43:57 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `2f9d9471bde8f5d7825577a31088d4229db50c24`
- High-level reason: Preserve the bootstrapped Instant diagnostic logger across
  the iPhone WatchConnectivity speech relay so Watch audio, Deepgram send, and
  transcript timing checkpoints reach the canonical remote log.

## July 27, 2026 at 9:42:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `17c2d6243b9231e6201d906b0d55e771ee8fb981`
- High-level reason: Serialize live recording snapshot saves and deletes through
  a bounded tail-task coordinator so overlapping reducer effects cannot finish
  persistence mutations out of submission order.

## July 27, 2026 at 9:38:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `fa2210b2ed3b1789083dd7ee1954010d4a8a4ad1`
- High-level reason: Keep cumulative transcript text out of live persistence
  transactions while retaining normalized segment and word delivery, then
  explicitly write the complete fallback string during finalization.

## July 27, 2026 at 9:32:38 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d8bab8f969c1ae73ebe074186e6b6e01bd9dbded`
- High-level reason: Structurally redact benchmark credentials before
  performance reports reach disk and provide an atomic sanitizer with hash
  provenance for existing ignored artifacts.

## July 27, 2026 at 9:29:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `62157d2cde816bb395913c7c0a6ef938f347a2fe`
- High-level reason: Correlate transcript source attribution with the audio
  frames actually sent under each context and use the exact `System Audio`
  fallback whenever reliable application metadata is unavailable.

## July 27, 2026 at 9:29:36 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `eaecd9d084651dd1b497fafc0a6b8ee10567b658`
- High-level reason: Load generator-produced, Git-ignored provenance into the
  SwiftPM build plugin and reject stale commits, mismatched source roots, or
  dirty worktrees before compiling reproducible build metadata.

## July 27, 2026 at 9:27:54 AM EDT

- Repository: `instant-data-swift`
- Commit: `0bda5d56651ac8e1b5e107b7a5a74ccc4f6c7a68`
- High-level reason: Persist only an unencodable mutation as failed, keep the
  shared live connection open, and continue sending healthy mutations behind
  it instead of poisoning every delivery attempt.

## July 27, 2026 at 9:22:10 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e15d6f9b0de75bf5b3589b4b7058ac13d651e569`
- High-level reason: Embed clean-build commit, branch, dirty state, timestamps,
  host, source root, artifact location, configuration, platform, and
  architecture in the standalone Watch audio probe's structured startup log.

## July 27, 2026 at 9:21:59 AM EDT

- Repository: `instant-data-swift`
- Commit: `ea1ca27e3cd0be0414ea328ef9e1ab1e10f7278d`
- High-level reason: Assign monotonic implicit outbox timestamps so mutations
  created in the same millisecond retain insertion order across persistence and
  relaunch without changing deliberately supplied domain timestamps.

## July 27, 2026 at 9:18:04 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `46fe3966ea42ca925de3881466c2c404b31308b6`
- High-level reason: Wait for the asynchronously enqueued WebSocket timeout
  diagnostic before asserting it, removing a scheduler-dependent suite flake.

## July 27, 2026 at 9:17:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `1d8db6978969a375fccca52b5174b2f3fe5ce7df`
- High-level reason: Retain only the newest 4,096 Watch relay chunk timings in a
  circular buffer and avoid false latency attribution after older timings are
  evicted.

## July 27, 2026 at 9:16:13 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `850b5169a1745fa6adf6d8e2216477be1e6dd3b3`
- High-level reason: Require explicit process opt-in before structured
  diagnostics can use the dedicated remote Instant app, while preserving local
  diagnostics by default.

## July 27, 2026 at 9:14:49 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `d3969e79955eb8f63400bd623600cea7d026d593`
- High-level reason: Restore a saved Watch credential through the phone relay,
  persist validated replacements on the phone, inject relay credential sources
  explicitly, and keep remote diagnostics off the credential critical path.

## July 27, 2026 at 9:14:44 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `578d9835801628609ecbaf9bad46fdb79a054c2e`
- High-level reason: Attach build provenance to structured diagnostics, record
  startup milestones locally, and preserve a privacy-safe local checkpoint when
  a remote diagnostic write fails.

## July 27, 2026 at 9:12:06 AM EDT

- Repository: `instant-data-swift`
- Commit: `ac10cb37652315a4d81d488de1848ebd2cc8af9d`
- High-level reason: Reference-count shared live-room registrations so one
  observer leaving cannot tear down the server room while another observer is
  still consuming it.

## July 27, 2026 at 9:07:41 AM EDT

- Repository: `instant-data-swift`
- Commit: `2739e7e5298215af04768d2b2ddcf6c1f0340b62`
- High-level reason: Make automatic fetch observation generation-aware so a
  canceled or stale observer cannot supersede a newer explicit projected-value
  task and surface a spurious `CancellationError`.

## July 27, 2026 at 9:04:28 AM EDT

- Repository: `instant-data-swift`
- Commit: `aab5dec69a27493df3df5b8b54ed5c417405f0f5`
- High-level reason: Make ordering parity fixtures use genuinely later edit
  timestamps and prove the complete local order before validating the
  infinite-query window.

## July 27, 2026 at 9:04:08 AM EDT

- Repository: `instant-data-swift`
- Commit: `cabc4677fbb4f81741669d919c818b9d86762fd7`
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
- Commit: `d7dd19d499ce8bf3643c5cbb2967fab7746963ed`
- High-level reason: Preserve live-error `original-event` correlation, reject
  only the affected query without reconnecting the shared socket, fail
  one-shot queries promptly, and prevent stale automatic mutation delivery
  when the runtime is configured for manual connection.

## July 27, 2026 at 8:55:21 AM EDT

- Repository: `instant-data-swift`
- Commit: `6a185835b57162af967880f93ea8731f7ad20242`
- High-level reason: Adopt the intent-ledger workflow and install reusable
  change-recording and reproducible-build provenance helpers in Instant.

## July 27, 2026 at 8:39:12 AM EDT

- Repository: `instant-data-swift`
- Commit: `d532a447a6282ebee652e4b7bcdc31d398e06578`
- High-level reason: Refresh deterministic performance evidence for the
  optimized offline-restore hop count and ensure the Reminders move fixture
  writes later than its seeded triples.

## July 27, 2026 at 8:34:03 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `e12be12daffc0aba0baa8e6ac64e45db93afa853`
- High-level reason: Bound the live microphone PCM stream to its 256 newest
  buffers, record dropped-buffer diagnostics, and warn once when a speech
  consumer falls behind without interrupting local capture.

## July 27, 2026 at 8:28:05 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `7f4ce7eef4c92d3c8e129993dd5beeea32ec2e99`
- High-level reason: Close the remaining pasteboard crash path by making the
  clipboard read dependency async and isolating every live read to MainActor.

## July 27, 2026 at 8:22:56 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4755a03f48778aa3dcfdfadbcad38c1793d2c8e2`
- High-level reason: Establish shared commit discipline in Scribe so parallel
  work is staged deliberately, journaled centrally, and handed off cleanly.

## July 27, 2026 at 8:22:28 AM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `0e22a68a9440a3db68a46be45723bc1a08a223be`
- High-level reason: Preserve the existing parallel Watch companion auth,
  speech relay, wire-format, test, and session-record work before auditing it.

## July 27, 2026 at 8:21:39 AM EDT

- Repository: `instant-data-swift`
- Commit: `52cf4bcf7783146402a0c600c9ef256e12580beb`
- High-level reason: Establish the cross-repository commit journal and require
  small verified commits plus clean parallel-agent handoffs.

## July 27, 2026 at 8:20:35 AM EDT

- Repository: `instant-data-swift`
- Commit: `c086b819b13affdb5cba615fbcd72744e9df1e8f`
- High-level reason: Preserve the unedited comprehensive audit journal before
  reading or changing the audited working tree.

## July 26, 2026 at 4:41:41 PM EDT

- Repository: `realtime-voice-sqlite-instant` (Scribe)
- Commit: `4d3069103dbd0bbe5ca42624610dd9187b8d350a`
- High-level reason: Establish the Scribe baseline with the Watch companion
  speech relay and privacy-safe diagnostics checkpointed.

## July 26, 2026 at 4:41:39 PM EDT

- Repository: `instant-data-swift`
- Commit: `f70044d5aa00e4892d258cce1399428fd91d3dc0`
- High-level reason: Establish the Instant Swift baseline with startup tracing
  and hardened storage runtime behavior.
