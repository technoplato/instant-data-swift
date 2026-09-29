# Plan: guest-only OAuth token forwarding, log-safe auth sessions, outbox across a guest link (#113)

- planId: 2026-09-29-sharing-accounts-auth-parity
- agentId: claude-opus-5.5-sharing-accounts (Claude Code CLI subagent)
- role: mower (upstream parity fix, redaction, a pinning test, and ten lines of guidance)
- branch: agent/claude-opus-5.5/sharing-accounts (no merge to main from this plan)
- Instant issue: #113. User context: "audit that I can upload upgrade an anonymous account to an
  account that already exists, and the recordings will be merged in the uh real users library."

Steps (tests first; baseline and after runs recorded in CHANGELOG.md):

1. `signInWithOAuth` forwards the current refresh token only for a guest session, as upstream
   `Reactor.exchangeCodeForToken` does (Reactor.js 2381-2394). `signInWithIDToken` keeps forwarding
   any current token, as upstream `Reactor.signInWithIdToken` does (Reactor.js 2408-2423); a test pins it.
2. `InstantAuthSession` prints, debug-prints, and reflects without its refresh token or email, so
   `String(describing:)`, `String(reflecting:)`, `dump`, and `customDump` of a session, a signed-in
   event, an identity transition, or a promotion result never contain the token. Codable, Equatable,
   and Hashable stay unchanged.
3. A test pins that a mutation queued by a guest stays pending after the guest links into an existing
   account and is delivered on the next connection under the promoted session. The divergence from
   upstream `Reactor.updateUser` (Reactor.js 2240-2274, drops pending mutations) is documented in
   `skills/instant-data/SKILL.md` with the reason (Scribe ADR 0005 linked-guest access, Scribe ADR 0014
   section 9 adoption, Instant guest-auth docs "Handling conflicting users").

Touching: Sources/InstantSwiftDataCore/InstantRuntime.swift (signInWithOAuth only),
Sources/InstantSwiftDataCore/InstantModels.swift (InstantAuthSession extension only),
Tests/InstantSwiftDataCoreTests/InstantStoreTests.swift and Tests/InstantSwiftDataTests/BootstrapTests.swift
(the two tests that pinned forwarding a non-guest token to OAuth), new test files, skills/instant-data/SKILL.md,
CHANGELOG.md, docs/audits/commit-changelog.md.

Conflict check (2026-09-29 00:28 EDT): no open channel or claim newer than 2026-09-27 on these paths. Four Scribe
worktrees build this checkout in edit mode, so every Sources edit is additive and compiles on its own.
