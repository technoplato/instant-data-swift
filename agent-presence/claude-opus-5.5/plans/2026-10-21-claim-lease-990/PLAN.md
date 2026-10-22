# Plan: a relaunch releases the delivery claims of a process that has ended instead of waiting out their deadlines (#990)

- **planId:** `2026-10-21-claim-lease-990`
- **agentId:** `claude-code-no-words-990-sync`
- **Role:** grower, ordered for a P0 (#990): a small behavior change in the automatic claim path; no public API changes.
- **Branch:** `agent/claude/claim-lease-990`, from tag `v1.9.11` (`7c62d93d`). Not merged, tagged or released by this
  agent; a release agent decides.
- **Outcome:** a runtime that finds claims left by a process that has ended releases them at its next claim and
  offers the ordered head at once, as upstream `Reactor.js` re-sends every pending mutation on `init-ok`
  (`_flushPendingMessages`). Before: a claim pass admits nothing while another claimant holds a live claim, and each
  claim's deadline is 6 s times its in-flight ordinal, so a relaunch reclaimed one left-behind claim every 6 s; on a
  device 18 such claims held delivery for 97 s. Claims of a process that still runs keep their lease.

## Steps (no code here)

1. Red: a relaunch with 18 claims a previous launch left behind offers the head at once (it measured 107,500 virtual
   ms at v1.9.11); a claim releases an ended claimant's claims and restarts their ordinals; a running claimant keeps
   its lease; the claimant id names its process and launch; the live liveness probe. Declarations only, so the red
   commit compiles.
2. Green: claimant ids name `process-<pid>-<launch>/<runtime>`; the claim request carries whether a claimant's
   process has ended (default: never); the store releases those claims inside the claim transaction, before expired
   claims are reclaimed, and logs `outbox.claims.ended-claimant-released` with the wait it avoided.
3. Focused suites (bounded delivery, fast drain, hydration, supersession, terminal components, replay gate, live
   transport) through heavy.sh; CHANGELOG; PROGRESS.

## Touching

- `Sources/InstantSwiftDataCore/InstantOutboxClaimant.swift` (new)
- `Sources/InstantSwiftDataCore/BoundedOutboxDelivery.swift`
- `Sources/InstantSwiftDataCore/InstantRuntime.swift`
- `Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift`
- `Tests/InstantSwiftDataCoreTests/InstantBoundedOutboxDeliveryTests.swift`

## Conflict check

The last claims on these paths (energy-669, receipt-quarantine #696, live-query-704) shipped in v1.9.10 and v1.9.11.
No commit on any ref touches `Sources/` after `v1.9.11`. Because main may not be pushed for this work, these claims
sit on the branch, not on main; the release merge surfaces them.
