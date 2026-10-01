# Plan: build 77's library: refresh frames without the attrs' cost, no operation gate across awaits, checkpoints off the gate (#303, #296)

- planId: 2026-10-01-library-77
- agentId: claude-opus-5.5-fast-drain
- role: mower (removes per-frame and per-commit cost; no new public surface)
- Branch: agent/claude-opus-5.5/library-77 from d487ee09 (build 76's library)
- Goal (Michael, via the coordinator): "fix this please so it works efficiently as as well as the typescript core library"

Evidence:
- Every refresh-ok carries all 447 attrs (about 134 KB of 151 KB), because init advertises only
  `InstantDB-Swift 0.1.0`. In #303's soaks a frame took 2-10 s, most of it decode and translation outside the gate.
  Attr-less frames already apply from the session's cached attrs, but the translator re-parses all of them and
  rebuilds the attribute context on every frame.
- `observeAuthSession()` holds the operation gate across awaits on the persistence and observer actors. On a fresh
  simulator it held the gate 23-101 s, and every transact, claim, and observation waited behind it (#303).
- Gate holds under host load are SQLite commit time. Apple's SQLite runs WAL commits at synchronous NORMAL; the
  auto-checkpoint (F_FULLFSYNC) runs inside the commit that crosses 1,000 pages. A benchmark showed p99 commit
  12-14 ms with checkpoints inside commits and 1.0-1.8 ms with checkpoints outside them.

Steps (no code here; tests first in each):

1. The translator caches the parsed session attrs and its attribute context by attrs revision and local attribute
   revision. Tests: attr-less frames apply like frames carrying the same attrs; one parse per revision; a schema
   change invalidates the cache.
2. observeAuthSession() releases the operation gate across its awaits without missing an auth change. Tests: a
   transact proceeds while the session load is slow; an auth change between load and observation is not lost. Then
   other gate-held awaits, guided by #303's sample.
3. If small: automatic checkpoints off, a PASSIVE checkpoint outside the gate on a WAL-size threshold, with a hard
   bound. Tests: bounded WAL under sustained writes; a crash in the middle of a checkpoint loses nothing.
4. The `@instantdb/core` 0.22.75 advert only after the experiment agent confirms it is safe.
5. Full gate set against d487ee09: live soak (the fixed-progression script once pushed, plus the current soak),
   Recording 023-shape backlog, phone replay, ten suites, infinite-query suites, differential.

Touching:

- Sources/InstantSwiftDataCore/InstantLiveRefreshApplication.swift, InstantRuntime.swift,
  InstantRuntimeLiveSession.swift, InstantLiveTransport.swift (advert, step 4), SQLitePersistenceStore.swift (step 3)
- Tests: InstantLiveRefreshAttributeCostTests.swift and new InstantLiveAttributeCacheTests.swift,
  InstantOperationGateAwaitTests.swift, InstantWALCheckpointTests.swift
- CHANGELOG.md, docs/audits/commit-changelog.md, PROGRESS.md

- Tests: InstantBoundedOutboxDeliveryTests.swift (added 2026-10-01 03:36 for two pre-existing test races the gates hit:
  the flush timeout's idle check, and the reclaim test's known-issue scope in InstantLiveTransportTests.swift)

Conflict check: these paths' latest claims are finished plans already merged into d487ee09 (perf audit, connection
survival, infinite leading rows, fast-drain-3, and stale-writes for InstantBoundedOutboxDeliveryTests.swift).
