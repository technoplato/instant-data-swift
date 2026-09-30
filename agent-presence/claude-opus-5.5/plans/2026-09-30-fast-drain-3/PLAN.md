# Plan: build 75's library: the phone's persisting decline and Scribe-shaped refused writes (#296)

- planId: 2026-09-30-fast-drain-3
- agentId: claude-opus-5.5-fast-drain
- role: mower (removes repeated whole-component rebases; no new public surface)
- Issue: #296 (Recording 023), open item 2
- Branch: agent/claude-opus-5.5/fast-drain-3 from agent/claude-opus-5.5/fast-drain-2 (ad1da185, build 73's library 506089b2)

Evidence:
- Build 73 on Michael's iPhone drains at about 25 writes a minute. Collector session 7ded00b0 showed a
  whole-component rebase (about 290 changed entities, 2.2-4.7 s under the gate) every 16-17 s from 17:38:15 on.
- An offline replay of the phone's stored live-query results against a scratch copy of its pre-71 store (no
  transport, auth rows deleted) names the persisting decline: changesShadowedFact on recordings/clipboardEntries of
  Recording 023. The device's resident value (local write f0f2430b, stamp 1790720767475) is stamped later than the
  server's restated fact (1790718230668). The full rebase's last-write-wins keeps the resident value, so every frame
  rebased the component and changed nothing.
- The same replay shows the splice refusing the pre-71 refused create 7998e83b, because of a reverse-form link
  (transcriptionSegments/recording) that a later write re-asserts. Build 73's 9 refusals on the phone add two more
  splice gaps: refused writes that share slots (3 summaries on one recording; a create plus an update on each of 3
  segments).

Steps (no code here):

1. Tests first: a restated server fact that loses to a later-stamped resident fact, on a shadowed slot with no pending
   writer, must not rebase. Then the fix: skip it, as the full rebase's last-write-wins does.
2. Tests first: remove chains of refused writes on shared slots, a refused create plus a refused update on the same
   segment with later writes, and reverse-form links re-asserted by later writes, without the full rebase. Every read
   must equal a full-rebase twin. Then extend the splice.
3. A phone-shaped replay: the pre-71 store copy driven through the phone's refusals and acceptances. It must show no
   rebases after the refusals are removed.
4. Gates, as for build 73: the live soak, the Recording 023-shape backlog (plus a phone-shaped one with refused creates),
   the ten suites, and the differential.

Touching:

- Sources/InstantSwiftDataCore/InstantRuntime.swift (server-apply reduction and splice)
- Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (reduction context)
- Tests/InstantSwiftDataCoreTests/InstantFastDrainTests.swift
- CHANGELOG.md, docs/audits/commit-changelog.md, PROGRESS.md

Conflict check: these paths' latest claims are this agent's own fast-drain plans. The connection-survival worker is
done, and its branch is merged into fast-drain-2.
