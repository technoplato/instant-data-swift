# Plan: a windowed live infinite query keeps paging when rows appear above its first row (#300)

- planId: 2026-09-30-infinite-leading-rows
- agentId: claude-opus-5.5-infinite-leading-rows
- role: mower (fixes a defect in the live coordinator's retention window; no new public surface)
- Issue: #300 (found by claude-opus-5.5-auto-paging while implementing #299)
- Branch: agent/claude-opus-5.5/infinite-leading-rows from 506089b2 (build 73's library). Pushed, not merged.

Evidence (the issue, and a code read of 506089b2 `InstantLiveInfiniteQueryCoordinator`):
- `retainedPageChunkKeys` counts a non-empty leading watcher as a page. With the window full, the next forward page
  evicts the watcher (`.previous`), `ensureLeadingWatcher` subscribes a new one at the first visible cursor, it finds
  the same leading rows, and `setReverseChunk` evicts the page just loaded (`.next`). `loadNextPage` then finds the
  last forward chunk already advanced and logs `infinite.load-next.noop-cannot-advance` while `canLoadNextPage` stays
  true. Reproduced on the Mac against bd40c50a: 63 of 121 rows, stalled
  (`/Users/laptop/Sync/audit/auto-paging-2026-09-30/traces/`).
- Upstream `client/packages/core/src/infiniteQuery.ts` never evicts. Its reverse chunk shows rows ordered before the
  first row and advances (freeze, then a new reverse chunk at its end cursor) when it fills. Chunks share exact
  boundary cursors: inclusive in one query, exclusive in the next.

Steps (no code here):

1. Reproduce in a library test first (deterministic, scripted fake server): leading rows present, a full window,
   `loadNextPage`. Red on 506089b2.
2. A property test with a model server that answers cursor queries and pushes refreshes: page through a list while
   rows are inserted above the first row or moved there at random, slide the window down and back up, and check at
   every quiescent point that the window is a contiguous, duplicate-free slice of the list, that the page flags are
   true only when navigation can advance, and that every row is reached exactly once per traversal.
3. Fix the live coordinator, keeping upstream ordering and cursor semantics:
   - the leading watcher (upstream's live reverse chunk) is not a page; it leaves with the top page and is created
     again only when navigation reaches the top of the list;
   - a trim cuts the window at a page boundary and drops everything beyond the cut;
   - `loadNextPage` after a bottom eviction loads the evicted page again from its exact boundary;
     `loadPreviousPage` uses exact boundaries and freezes the page it grows from;
   - a full leading watcher advances only while the window has room; otherwise `canLoadPreviousPage` reports the
     rows above it.
4. Validate: the focused tests; InstantInfiniteQueryParityTests, DeferredValueResidencyTests, TypedAPITests; the ten
   suites against the 506089b2 baseline (683 tests, 21 known issues); the auto-paging Mac reproduction (121 rows
   reachable with leading rows present); a live-recording soak on an iPhone simulator against bd40c50a (pending
   near 0). Heavy builds run under `/usr/bin/lockf -k /tmp/scribe-heavy-build.lock`.

Touching:

- Sources/InstantSwiftDataCore/InstantInfiniteQuery.swift (`InstantLiveInfiniteQueryCoordinator` navigation, trim,
  leading watcher, and page flags; the retention policy's documentation)
- Tests/InstantSwiftDataCoreTests/InstantInfiniteQueryLeadingRowsTests.swift (new)
- Tests/InstantSwiftDataCoreTests/InstantInfiniteQueryParityTests.swift (the live-window test's expectations, only
  where the fix changes them)
- Sources/InstantSwiftDataCore/InstantRuntime.swift (added 2026-09-30 19:02 EDT; `observeLiveInfiniteQueryChunk` only: a
  defaulted parameter so a chunk created by backward navigation is not seeded from a persisted result. The property
  test's trace showed such a page reusing the original leading watcher's query, whose cached "no rows above" made the
  window believe it reached the top and climb to the head.)
- CHANGELOG.md, docs/audits/commit-changelog.md, PROGRESS.md

Conflict check: the last claims on InstantInfiniteQuery.swift and its parity tests are from 2026-08 and 2026-09-26
(#250, landed). No open branch changes either file (checked `git log --all --since=2026-09-20`). The library branch
agent/claude-opus-5.5/list-owner-scope adds only audit-ledger lines on top of 506089b2; the ledger is newest-first,
so a merge resolves by keeping both blocks in time order. Scribe's auto-paging worker (#299) owns the app side and is
told through #300's work log.
