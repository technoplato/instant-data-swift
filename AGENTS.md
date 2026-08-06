# Repository Instructions

## Fundamentals first (active program)

**This library works, but memory, performance, and ergonomics are still a work
in progress.** Prefer finishing those over new product surface area until
ADR 0015 / issue #155 say otherwise.

- Interview pack: `docs/adr/0015-sqlite-data-parity-ergonomics/`
- Large decisions: personal skill `$adr-decision-qanda` (one question at a time,
  ASCII, hard chat separator before the next question).
- Dual app+library guidance: `skills/instant-data/SKILL.md` (**in active
  iteration** with the user while Scribe co-develops Instant).

### Write contract (library boundary — all apps)

- **`transact` / `save` never wait for the server.** Success means local
  materialize + durable outbox only. Offline must succeed.
- `async` means local runtime/SQLite work finished — same idea as SQLiteData
  `database.write` waiting on the DB queue, **not** a cloud round-trip.
- `InstantStoreMutationResult.transactionID` is the delivery handle (already
  returned). Document it as primary; publicize `observeTransaction(id:)` (wrap
  existing mutation lifecycle). Entity **sync status on fetch** is the normal UI
  path.
- Server waits use **explicitly named** APIs only (`waitForAllPendingMutations`,
  observe transaction). Do not overload ordinary writes so `await` sometimes
  means network.
- Prefer clearer docs over inventing a second transaction id type.

### Point-Free quality bar

Code and documentation quality must be **on par with Point-Free**. Before
shaping public APIs or doc comments, read how the real libraries teach:

- Vendored: `upstream/sqlite-data`
- Also on machine: `/Users/laptop/Sync/tca/sqlite-data`, Point-Free trees under
  `/Users/laptop/Sync/tca/pfw` (and related TCA / sharing checkouts)
- Prefer short, precise API commentary that states **what success waits for**
  (local DB vs server), with a one-line example — not vague “async write.”

### Correctness over convenience

Prefer the **most correct** relational / library-owned design over the easiest
app shortcut (no denormalized full transcript previews to dodge query work).
Example: list screens use a **bounded nested include** (e.g. two latest segments
per recording) plus a **map/truncate** helper for UI lines — see ADR 0015
`overviews/03-list-query-syntax-sketch.md`. Always attach explicit child limits
on list includes; architecture-test against unbounded segment loads on lists.

Also target SQLiteData-parity **aggregations, group-by counts, and sectioned
list shapes** (not only flat arrays). Prior art: Point-Free research under
`/Users/laptop/Sync/tca/pointfree-research` (ep328 aggregations, ep374
sectioning) and `upstream/sqlite-data` Reminders/SyncUps group+count+@Selection.

### Prefer algebraic data types (enums) over plain strings

Use enums / ADTs for closed sets (media kind, content type, activity, status).
Rarely store free-form strings for those fields. Wire with stable `rawValue`
when Instant attributes are string-typed. Library helpers: `InstantMediaKind`,
`InstantContentType`.


---

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
- For tricky synchronization, optimistic-state, rejection, reconnect, query,
  auth, and persistence edge cases, defer to the vendored upstream Instant
  implementation first. Prefer the same state transition and test shape over a
  novel local design; when Swift's architecture requires an adaptation, name
  the upstream source and document precisely why the implementation differs.
- Treat `docs/adr/0001-application-sync-boundary.md` as canonical. Applications
  own schema, query/observation lifetime and dynamic inputs, mutations, auth,
  and sharing. The library owns cache/materialization, optimistic observation,
  persistent outbox/reconnection, delivery, and rejection isolation.
- Do not add a public `queryLocal`. Select local-only behavior with an injected
  local-only `InstantSwiftDataClient` that uses ordinary public APIs.
- This library and its primary consumer, Scribe
  (`../tools/realtime-voice-sqlite-instant`), are developed together and both
  change daily. Scribe consumes this checkout directly through the
  `Packages/instant-data-swift` symlink, so library changes reach a real device
  immediately and a Scribe symptom is as likely to originate here as in the app.
  Reproduce against Scribe's actual workload before declaring a fix, and
  remember that reinstalling Scribe does not reset library state — the triple
  cache and the outbox are persistent on disk.
- Scribe is an always-on voice recorder, so this library's steady-state cost is
  a user-visible property: it holds a live websocket, a persistent outbox, and a
  local triple store while the phone is in a pocket. Connection churn, a backoff
  that resets instead of growing, retrying while the OS reports no network path,
  an outbox that never drains, and per-change full-result recomputation all
  present to the user as a hot phone and a dead battery. Backoff, reachability
  gating, and retry cadence are correctness behavior with upstream parity
  obligations — see `Reactor.js` `_scheduleReconnect`, whose `_reconnectTimeoutMs`
  lives on the reactor and is reset only on `init-ok`, and which skips the
  attempt entirely when `_isOnline` is false. Any divergence needs a cited
  reason.
- Prove attribution from evidence before naming a layer, and say which kind of
  evidence you have. Reading a plausible defect in this library's source is a
  hypothesis, not a diagnosis: on 2026-08-03 a retry storm on a device was
  attributed to this library's reconnect controller purely from code reading,
  when the failing socket belonged to the application's own `InstantDBLogger`
  and the library's sync socket had emitted no errors at all. Two checks would
  have caught it immediately — the observed retry intervals did not match the
  accused code's delay formula, and the log subsystem named a different
  component. Match measured timings against the specific formula you are
  blaming, confirm the subsystem actually belongs to the layer you are
  accusing, and state plainly when a conclusion is inference rather than
  measurement. Release thresholds and the commands that measure them live in
  `../tools/realtime-voice-sqlite-instant/docs/performance-budget.md`; when a
  change moves one of those numbers, record the measured before/after.
- Keep explicit flush/status APIs limited to CLI, diagnostics, tests, and real
  user-visible operations. Keep entity delivery independent from media
  transfer and preserve per-item or per-stream rejection isolation.
- Do not claim live synchronization from compilation, fixtures, or local-only
  tests. Distinguish deterministic local evidence, protocol/mock evidence,
  credentialed Swift/TypeScript boundary evidence, and installed-app/UI
  evidence.
- Commit methodically in small, coherent, test-driven slices. Immediately
  before every commit, re-check `git status`, stage only the intended paths,
  inspect the complete staged diff, and include the high-level reason in the
  commit message.
- The user has limited ChatGPT and Sol Ultra access. Written continuity is a
  required deliverable: at each coherent checkpoint, update `PROGRESS.md` with
  immutable commits, verification evidence, active ownership, blockers, and
  exact continuation steps. Never leave the only restartable account in chat
  context. Keep increments small enough to review and resume, then mirror each
  substantive commit through `CHANGELOG.md` and the cross-repository audit.
- After every substantive commit in this repository or
  `../tools/realtime-voice-sqlite-instant`, add a newest-first entry to
  `docs/audits/commit-changelog.md` with a human-readable timestamp including
  seconds in `America/New_York`, the repository name, the full commit SHA, and
  the high-level reason. A changelog-only commit cannot contain its own final
  SHA; identify that bookkeeping commit through Git history rather than a
  self-referential entry.
- Multiple agents may work directly on `main`. Preserve their changes, commit
  owned work promptly, and coordinate immediately when another agent leaves
  related work uncommitted. Keep this repository and
  `../tools/realtime-voice-sqlite-instant` clean at handoff.

<!-- change-log-skill:start -->
## Change log, commits, and build provenance

- Use the global `$change-log` skill for repository changes.
- Inspect Git state first and preserve unrelated work. Stage only explicit
  task-owned paths.
- Commit each coherent verified increment. Do not commit every edit, wait for an
  oversized batch, or leave finished task-owned work uncommitted.
- Use two commits: implementation first; then prepend `CHANGELOG.md` with the
  implementation SHA using `python3 scripts/change-log/record_change.py` and make
  a changelog-only ledger commit. Do not recursively log the ledger commit.
- Every entry uses machine-local human time including seconds, year, and timezone;
  records the commit and subject, change details, files and reasons, short
  verbatim user statements, and a durable SpecStory URI or exact absence reason.
- Capture terminal Codex context with `specstory run codex` or
  `specstory sync codex --local-time-zone`. Public sharing requires explicit
  user authorization. Do not invent SpecStory links for Codex desktop tasks.
- Produce installable or distributable builds only from a clean commit. Run
  `python3 scripts/change-log/build_provenance.py` from the real build and compile
  or embed its output in the binary. Log the embedded commit, branch, dirty=false,
  local/ISO build time, host, source root, and artifact location at startup.
<!-- change-log-skill:end -->
