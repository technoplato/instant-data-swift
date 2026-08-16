# Local writes must not wait for a server refresh

- planId: `2026-08-15-local-write-server-refresh`
- agentId: `codex-desktop/01a00071-f1c1-7193-adcd-3bc9f30b5f95/root`
- role: `mower`
- issue: Instant issue `#008` — Recording and transcription break after leaving the app
- channel: `agent-presence/_channels/01a00071-recording-052-sync-correctness.md`

## Outcome

Restore Instant's local-first write contract for Scribe Recording 052: an incoming
server refresh may take seconds to prepare, but it must not prevent a recording
write from materializing locally and entering the durable outbox. The server
refresh must detect that revision race, retry against the new local write, and
preserve both the authoritative refresh and the optimistic local effect.

## Evidence

- The installed iPad build held `applyLiveRefresh(_:receivedAt:)` at the global
  operation gate for 5–21 seconds while recording writes queued behind it.
- Scribe reported 154 local-durability failures during Recording 052.
- The iPad retained 9,612 words and 480 seconds, while the server and Mac remain
  at 7,091 words and 405 seconds with 459 local mutations still pending.
- Reopening the same build took 24.4 seconds to publish the first recording list.

## Steps

1. Add a deterministic race test that pauses a prepared server refresh and proves
   a local transaction reaches SQLite and the hot store before the refresh resumes.
2. Separate long server-apply preparation from the short local-write commit lane,
   while preserving one-at-a-time server apply and revision-checked retry.
3. Prove the resumed server refresh retries after the local revision change and
   publishes the authoritative value with the local optimistic overlay replayed.
4. Run the focused race and bounded server-apply suites, then the broader live
   transport and package correctness gates in proportion to the change.
5. Commit the implementation and required ledgers before a physical Scribe build.

## Touching

- `Sources/InstantSwiftDataCore/InstantRuntime.swift`
- `Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift`
- `PROGRESS.md`
- `CHANGELOG.md`
- `docs/audits/commit-changelog.md`

## Conflict check

Both production and test paths have historical append-only claims, but the current
working tree is clean and no active agent is editing either path. Root will append
its own claims and coordinate this narrow server-apply/local-write split in the
named channel before editing source.
