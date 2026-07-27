# Cross-Repository Commit Changelog

Newest entries go at the top. Timestamps include seconds and use Eastern Time
(`America/New_York`). Each substantive commit records the repository, full
commit SHA, and high-level reason. Changelog-only bookkeeping commits are
visible in Git history but are not self-recorded because a commit cannot
contain its own final SHA.

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
