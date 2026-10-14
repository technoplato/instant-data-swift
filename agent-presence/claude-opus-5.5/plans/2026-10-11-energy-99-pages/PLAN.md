# Plan: a publication refreshes only the pages a write can reach (#654, #669)

- **planId:** `2026-10-11-energy-99-pages`
- **agentId:** `claude-opus-5.5-energy-99-lib` (the energy-99 library helper; continues `2026-10-10-energy-98-write`)
- **Role:** mower. The same result in every observer for less CPU; nothing a person sees changes.
- **Branch:** `agent/claude/energy-98-write`, after #653's equal-result fix.
- **Goal (the user, verbatim, 2026-10-10 23:09):** "We want all of our functionality but to reduce and eliminate any
  waste or spurious processor etc behavior" "Don’t remove any functionality, fix the underlying problems"
- **Issues:** #654 (library memory and pages: every page re-runs on every write), #669 (the energy-98 umbrella)

## Steps (no code here)

1. Profile the write path with 32 page observers (Time Profiler, release harness).
2. A red test: an update that keeps an entity's place in a filtered, ordered list refreshes only the page that shows
   it; a randomized test compares every observer with a fresh materialization after every write.
3. The refresh check compares each changed entity's place in the observer's result set (in it or not, and its order
   value) before and after the publication, for plans that read only their own namespace; the result an observer holds
   must be verified against the store the publication started from.
4. Measure: the release harness with 32 page observers, before and after.

Touching `Sources/InstantSwiftDataCore/InstantStore.swift`, `Sources/InstantSwiftDataCore/TripleIndexes.swift`, and new
`Tests/InstantSwiftDataCoreTests/InstantPageRefreshEnergyTests.swift`, added 2026-10-11 EDT.
