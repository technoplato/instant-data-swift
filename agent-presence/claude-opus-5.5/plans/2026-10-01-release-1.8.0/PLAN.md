# Plan: publish v1.8.0 from main with build 77's library (#155 #303 #324 #329)

- **planId:** `2026-10-01-release-1.8.0`
- **agentId:** `claude-opus-5.5-release` (issue workLog agentId `claude-code/claude-opus-5.5/release`)
- **Role:** mower. This publishes work that is already gated and shipping in Scribe 0.1 (77). It changes no
  source code and adds no public surface.
- **Maintainer authorization (Michael, 2026-10-01 about 16:46, verbatim):** "Make sure all this stuff is committed
  to main and pushed both for the libraries and for uh scribe and make sure the the library is deployed and has a
  release triggered, etc., from uh GitHub with all these fixes and whatnot, uh as well as scribe."

## Outcome

`main` carries build 77's library (`agent/claude-opus-5.5/library-77`, gated head `956fce52`, merged with its
PROGRESS-only entry `66f49197` as `d9ac85f0`). `v1.8.0` is tagged on main's release commit and published on GitHub
with release notes that explain every change since v1.7.0 in plain words. Scribe then pins `exact: "1.8.0"`.
Library-78 (agent `library-78`) is not part of 1.8.0.

## Steps (no code)

1. Merge library-77 into main without fast-forward (done: `d9ac85f0`, first parent `646c0ebc`).
2. Write `docs/releases/v1.8.0.md`; it must pass `scripts/validate-release-version.sh 1.8.0`. Cite library-77's
   gate evidence (`/Users/laptop/Sync/audit/recording-023-fixes/fast-drain/library-77/`, FAST-DRAIN.md section 15).
3. Record the release document and the merge in `CHANGELOG.md`, `docs/audits/commit-changelog.md`, and
   `PROGRESS.md`. That ledger commit is the release commit.
4. Run `validation/run-performance-gate.sh live` on the release commit with `INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0` and
   no Instant credentials in the environment, so no stage signs in to Scribe's production app. Run the stages the
   fail-closed gate skips by hand: the cross-SDK runtime suite, then the Scribe-shaped wire bench (temporary app).
5. Attribute any performance miss with a same-machine ABBA against v1.7.0 (cross-SDK core and runtime, about 20 runs
   per arm under load).
6. Annotated tag listing the green gates and every known open item; push main and the tag;
   `gh release create v1.8.0 --verify-tag --latest`.
7. Record the publication and Scribe's pin commit in PROGRESS and the audit ledger.

## Touching

- `docs/releases/v1.8.0.md` (new)
- `CHANGELOG.md`
- `PROGRESS.md`
- `docs/audits/commit-changelog.md`

## Conflict check

- The latest claims on main for `CHANGELOG.md`, `PROGRESS.md`, and `docs/audits/commit-changelog.md` belong to
  finished plans merged in `d9ac85f0` (library-77, fast-drain-3, auth-counters, infinite-leading-rows,
  connection-survival).
- `claude-opus-5.5-library-78` claims the same three logs on its unmerged branch (plan `2026-10-01-library-78`).
  All three are newest-first logs; each of us only prepends entries, and the later merge keeps both in timestamp
  order. Noted in `agent-presence/_channels/2026-10-01-release-1.8.0.md`.
- No earlier claim exists for `docs/releases/v1.8.0.md`.
