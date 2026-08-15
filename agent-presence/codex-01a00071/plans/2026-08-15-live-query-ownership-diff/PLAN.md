planId: 2026-08-15-live-query-ownership-diff
agentId: codex-desktop/01a00071-f1c1-7193-adcd-3bc9f30b5f95/root
role: mower
outcome: Remove full persisted live-query ownership rewrites from repeated bounded refreshes so Instant issue #155's five-second Scribe Mac projection gate can be measured without serialized SQLite churn.
channel: agent-presence/_channels/01a00071-five-recording-sync-soak.md

steps:
  - Add a deterministic persistence regression that counts ownership-row mutations across identical and one-row-changed live-query replacements.
  - Replace delete-all/reinsert-all ownership persistence with an exact previous-versus-next identity diff using one prepared mutation statement per direction.
  - Preserve nested-limit enforcement, shared-query ownership, query-result revisions, raw persisted results, and relaunch behavior.
  - Run focused and proportionate package validation, then repeat the same CLI-only physical Mac visibility preflight before admitting any five-minute recording.
  - Record immutable verification and continuation evidence in PROGRESS.md, CHANGELOG.md, and the cross-repository commit audit.

touching:
  - Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift
  - Tests/InstantSwiftDataCoreTests/InstantLiveQueryNestedLimitMemoryTests.swift
  - PROGRESS.md
  - CHANGELOG.md
  - docs/audits/commit-changelog.md

conflictCheck: Existing claims are historical or belong to this same Codex desktop task. This plan appends its own claims and publishes the exact mower split before implementation.
