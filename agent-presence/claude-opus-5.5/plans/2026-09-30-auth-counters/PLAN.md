# Plan: apps can turn off AuthV3LoginScreen's demo counters (#289)

- planId: 2026-09-30-auth-counters
- agentId: claude-opus-5.5-auth-counters
- role: grower (one new public environment value, ordered by the main session for Scribe's Account screen; public
  record #289)
- Branch: agent/claude-opus-5.5/auth-counters from 506089b2 (build 73's library). Pushed, never merged by me.
- Scribe side: branch agent/claude-opus-5.5/auth-counters in technoplato/scribe, plan 2026-09-30-auth-counters there.

Evidence:
- Michael's iPad, Scribe 0.1 (72), 2026-09-30 10:52: the Account sheet shows "Increment public" and "Increment mine".
- The collector logged 5 `transaction.failed` from that iPad between 10:51:37 and 10:51:41: "Entity namespace
  'recipe_public_counters' does not exist in the local schema." The first one comes with no tap: the card's `.task`
  creates the public counter row when the sheet opens. Each "Increment public" tap then fails twice (the create, then
  the fallback update). The same sheet opening also logged two `query-observation.validation-failed` (one for
  `recipe_public_counters`, one for `recipe_account_counters`).
- Cause: `AuthV3LoginScreen` always draws `AuthV3CountersCard` (Sources/AuthV3App/AuthApp.swift:156-159 at 506089b2),
  the Auth recipe's demo of a public row and a per-account row. Nothing lets a host app hide it. Scribe's schema has
  neither namespace.

Steps (no code in this commit):

1. Test first in Tests/AuthV3AppTests/AuthV3AppTests.swift: the new environment value defaults to on; rendered with
   a local-only client, the default screen writes the demo's public counter row, and the screen with the value off
   writes nothing and starts no counter query. Seen failing (it does not compile, then fails) before the change.
2. Sources/AuthV3App/AuthApp.swift: environment value `authV3ShowsDemoCounters` (default true, so the Auth recipe app
   and every other app keep today's screen), read by AuthV3LoginScreen around the counters card. Same shape as
   `authV3AllowsDiscardingGuestSession`.
3. Scope check: only the AuthV3 UI module changes, not the sync engine. `git diff --stat 506089b2` must list no
   Sources/InstantSwiftDataCore file; if none, the live-recording simulator soak is not required.
4. Records: CHANGELOG.md (two-commit convention), docs/audits/commit-changelog.md (library and Scribe commits), #289
   workLog.

Touching (claimed by this commit): Sources/AuthV3App/AuthApp.swift, Tests/AuthV3AppTests/AuthV3AppTests.swift,
CHANGELOG.md, docs/audits/commit-changelog.md.

Conflict check: no claims on the two AuthV3 files, and no branch that contains 506089b2 (fast-drain-2,
infinite-leading-rows, list-owner-scope, settings-scope, sharing-accounts) changes Sources/AuthV3App or
Tests/AuthV3AppTests. CHANGELOG.md and the audit ledger take newest-first entries from every plan; merges keep both
sides. I do not edit /Users/laptop/Sync/worktrees/instant-data-swift-combined or /Users/laptop/Sync/instant-data-swift.
