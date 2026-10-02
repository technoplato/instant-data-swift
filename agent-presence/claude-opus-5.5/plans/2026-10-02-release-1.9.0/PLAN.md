# Plan: publish v1.9.0 from main with build 78's library (#376 #360 #388 #394 #329 #303 #317 #361 #296)

- **planId:** `2026-10-02-release-1.9.0`
- **agentId:** `claude-opus-5.5-library-78` (issue workLog agentId `claude-code/claude-opus-5.5/library-78`)
- **Role:** mower. This publishes work that is already gated. It changes no source code and adds no public surface
  beyond what library-78 already carries.
- **Maintainer authorization (Michael, to the coordinating session on 2026-10-02 at about 12:10 EDT, verbatim):**
  "Publish the library once it's checked fast. Yes."

## Outcome

`main` carries build 78's library (`agent/claude-opus-5.5/library-78`, gated code head `01175cff`, merged without
fast-forward as `0b8f52f7` over `eeea9b12`). `v1.9.0` is tagged on main's release commit and published on GitHub with
release notes that explain every change since v1.8.0 in plain words. Scribe then pins `exact: "1.9.0"`, and library-79
rebases onto it.

## Steps (no code)

1. Merge library-78 into main without fast-forward (done: `0b8f52f7`, first parent `eeea9b12`).
2. Write `docs/releases/v1.9.0.md`; it must pass `scripts/validate-release-version.sh 1.9.0`. Cite library-78's gate
   evidence (`/Users/laptop/Sync/audit/library-78-2026-10-01/`).
3. Record the release document and the merge in `CHANGELOG.md`, `docs/audits/commit-changelog.md`, and `PROGRESS.md`.
   That ledger commit is the release commit.
4. Fast checks only, as authorized: library-78's gates on `01175cff` (library suites, the phone-shaped replay, the
   replay benchmark, a 30-minute Scribe soak with zero refusals on Scribe main's sources). The release gate
   (`validation/run-performance-gate.sh live`) does not run; the tag message and the release notes name it as a known
   open gate item.
5. Annotated tag listing the checks that ran and every known open item; push main and the tag;
   `gh release create v1.9.0 --verify-tag --latest`.

## Touching

- `docs/releases/v1.9.0.md` (new)
- `CHANGELOG.md`
- `PROGRESS.md`
- `docs/audits/commit-changelog.md`

## Conflict check

- The latest claims on main for `CHANGELOG.md`, `PROGRESS.md`, and `docs/audits/commit-changelog.md` belong to plans
  merged in `0b8f52f7` (library-78, account-linking) and to release-1.8.0, all finished.
- `claude-opus-5.5-library-79` claims the same three logs on its unmerged branch (plan `2026-10-02-library-79-hops`).
  All three are newest-first logs; each of us only prepends entries, and library-79's rebase onto v1.9.0 keeps both in
  timestamp order. Noted in `agent-presence/_channels/2026-10-02-release-1.9.0.md`.
- No earlier claim exists for `docs/releases/v1.9.0.md`.
