# Repository Instructions

- Use the Point-Free-style Instant Data (`pfw-instant-data`) guidance on every
  task in this repository.
- Always start with the installed `pfw` skill. Then read
  `skills/instant-data/SKILL.md` and route to the relevant companions:
  - `skills/instant-data-modeling/SKILL.md` for schema, entities, projections,
    queries, fetch wrappers, drafts, permissions, and mutations.
  - `skills/instant-data-dependencies/SKILL.md` for bootstrap, `@Dependency`,
    live/local-only clients, previews, tests, CLI, transport, auth, storage, or
    media effect seams.
  - `skills/instant-data-testing/SKILL.md` for unit tests, adapter tests,
    offline/outbox/reconnect behavior, architecture checks, media isolation,
    and Swift/TypeScript validation.
- Also apply the relevant installed `pfw-*` skills. This usually includes
  `pfw-testing`, `pfw-custom-dump`, `pfw-dependencies`, `pfw-sqlite-data`, and
  `pfw-structured-queries`; use other Point-Free skills when their domain is in
  scope.
- Prefer a test-driven workflow. Add or tighten the smallest focused test
  first, make the smallest implementation change that passes, then refactor and
  run broader validation in proportion to risk.
- Preserve upstream parity deliberately. Inspect the corresponding vendored
  Instant TypeScript and SQLiteData source/tests before changing behavior, and
  record exact versus adapted behavior when porting a test or API.
- Treat `docs/adr/0001-application-sync-boundary.md` as canonical. Applications
  own schema, query/observation lifetime and dynamic inputs, mutations, auth,
  and sharing. The library owns cache/materialization, optimistic observation,
  persistent outbox/reconnection, delivery, and rejection isolation.
- Do not add a public `queryLocal`. Select local-only behavior with an injected
  local-only `InstantSwiftDataClient` that uses ordinary public APIs.
- Keep explicit flush/status APIs limited to CLI, diagnostics, tests, and real
  user-visible operations. Keep entity delivery independent from media
  transfer and preserve per-item or per-stream rejection isolation.
- Do not claim live synchronization from compilation, fixtures, or local-only
  tests. Distinguish deterministic local evidence, protocol/mock evidence,
  credentialed Swift/TypeScript boundary evidence, and installed-app/UI
  evidence.
