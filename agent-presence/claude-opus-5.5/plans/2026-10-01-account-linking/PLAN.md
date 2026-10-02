# Plan: a second sign-in held beside the session, and account linking in AuthV3 (#361)

- planId: 2026-10-01-account-linking
- agentId: claude-code/claude-opus-5.5/account-linking (claim lines use `claude-opus-5.5-account-linking`)
- role: grower (Michael ordered account linking; public record is #361 and Scribe ADR draft 0024)
- Branch: agent/claude-opus-5.5/account-linking from 956fce52 (build 77's library), worktree
  /Users/laptop/Sync/worktrees/instant-data-swift-account-linking. Pushed, never merged by me.
- Scribe side: plan `2026-10-01-account-linking` on Scribe main (c863828a), branch agent/claude-opus-5.5/account-linking.
- Goal (Michael, 2026-10-01): "Let's add a functionality to link accounts then. If you have Apple, I want to be able
  to link it with Google as well so that we aggregate all these different recordings. So it's a library change and"

Evidence:
- A client keeps one auth session per store file and app (`instant_auth_sessions`, key `auth:<appID>`). Signing in
  replaces it and reconnects as the new user; `signInWithOAuth` and `signInWithMagicCode` forward a guest's token and
  `signInWithIDToken` forwards any token, so a second sign-in on the primary client promotes or links the first
  identity instead of proving control of a second one.
- The vendored server links only guests (`$users.linkedPrimaryUser`) and joins two OAuth identities only on an email
  match (`upstream/instant/server/src/instant/runtime/routes.clj`, `upsert-oauth-link!`).
- A second runtime on its own temporary store already works in tests (`AuthV3AppTests` two clients, two files).

Steps (no code here; tests first in each):

1. `InstantSecondSignIn`: a temporary client of the primary's app (same endpoints and exchanges, its own temporary
   store and connection, no shared outbox, never `bootstrapInstantSwiftData`). It signs a second identity in by magic
   code, Apple ID token, Google OAuth code, or an existing refresh token (adopted, never revoked). It writes as that
   identity and waits for the server's acceptance of each write (5 s). `close()` revokes only a token it minted,
   closes the connection, and deletes the store. Tests: the primary's session row, store, and outbox never change;
   no exchange on the second client carries the primary's token (guest or not); close revokes the minted token only;
   failures and cancellation still clean up.
2. `InstantAccountLinks`: the link protocol over an app-declared namespace (default `accountLinks`, `members` to
   `$users`, reverse `accountLink`): create and invite as the first identity, join and clear the invite as the second,
   unlink, and the published rules template the app pastes into its permissions. Both identities write through
   temporary clients, so a backlogged primary outbox never delays a link. Tests: the frames each side sends, refusal
   when the second identity is already in another link, already-linked is a no-op, a 5 s acknowledgement timeout is a
   loud error naming the step, unlink.
3. AuthV3: a "Link another sign-in" action on `InstantAuthState` and an opt-in section in `AuthV3LoginScreen` (linked
   sign-ins, Link with Apple, Google, or email code, Unlink), off by default so Recipes and other hosts see no change
   until they opt in. Tests in `AuthV3AppTests` and the fixture tests.
4. Gates: focused suites, the auth and guest-promotion suites, the AuthV3 and Recipes app tests, a live link on the
   throwaway app `bd40c50a`, and the live-recording simulator soak (Scribe `scripts/soak-fixed-progression.sh`, pending
   near 0) before the change ships.
5. Records: change log (two commits), the cross-repository audit ledger for this branch and the Scribe branch,
   PROGRESS, `skills/instant-data/SKILL.md` (second sign-in and account links).

Touching:

- Sources/InstantSwiftData/InstantSecondSignIn.swift (new), Sources/InstantSwiftData/InstantAccountLinks.swift (new)
- Sources/InstantSwiftData/InstantAuth.swift (the link action on InstantAuthState)
- Sources/AuthV3App/AuthApp.swift (the opt-in linked sign-ins section), Sources/AuthV3App/AuthModels.swift (if needed)
- Tests: Tests/InstantSwiftDataTests/InstantSecondSignInTests.swift (new),
  Tests/InstantSwiftDataTests/InstantAccountLinksTests.swift (new), Tests/AuthV3AppTests/AuthV3AppTests.swift
- skills/instant-data/SKILL.md (auth section), CHANGELOG.md, docs/audits/commit-changelog.md, PROGRESS.md

Conflict check: the latest claims on these paths are finished plans merged into 956fce52 (auth-counters #289,
sharing-accounts auth parity #113, library-77 #303). library-78-apply-fallback touches only InstantRuntime.swift and
its tests, which this plan does not edit.
