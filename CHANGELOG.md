# Change Log

Newest entries appear first. Implementation commits and intent are recorded separately from ledger-only commits.

<!-- change-log:entries -->

## July 27th, 2026 at 8:55:43 a.m. EDT — `d7dd19d499ce` Fix live query error isolation

- **Implementation commit:** `d7dd19d499ce8bf3643c5cbb2967fab7746963ed`
- **Change:** Isolate rejected live queries and prevent stale manual-delivery sends
- **Details:**
  - Preserve the server original-event so add-query failures retire only the rejected registration, fail queryOnce promptly, and leave the shared socket opened for healthy queries.
  - Honor autoConnectLiveTransport before scheduling background mutation delivery so a confirmed mutation captured while disconnected cannot be sent after a later manual connect.
- **Files:**
  - `Sources/InstantSwiftDataCore/InstantLiveTransport.swift` — Decode and retain the server original-event on live errors.
  - `Sources/InstantSwiftDataCore/InstantRuntime.swift` — Route query rejection outcomes without reconnecting and gate automatic mutation delivery.
  - `Tests/InstantSwiftDataCoreTests/InstantReactorParityTests.swift` — Prove healthy-query isolation, prompt one-shot failure, and durable pending-mutation behavior.
- **User context (verbatim):**
  > maintain a human-readable timestamped commit audit journal and clean worktrees
- **SpecStory:** unavailable — Codex desktop sessions are not supported by the documented SpecStory CLI capture workflow, so no durable session URI is available.
