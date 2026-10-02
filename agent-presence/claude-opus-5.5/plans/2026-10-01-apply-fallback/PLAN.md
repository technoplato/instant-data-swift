# Plan 2026-10-01-apply-fallback

- planId: 2026-10-01-apply-fallback
- agentId: claude-opus-5.5-fast-drain
- role: mower
- Outcome (#303): a server apply whose optimistic attempts all go stale because this runtime's own local writes keep
  changing the store applies once more under an exclusive operation-gate hold instead of throwing. Throwing ended the
  live receive loop: the reconnect re-sent in-flight writes, and Scribe's validUpdate rule refused them as replays. The
  experiment agent's large-store drop (pair-large-drop-r1) hit it on 6a81039a and ab33cb35 while dictation continued
  after an outage, Michael's car case.

Steps (no code here):

1. A red test: a same-runtime local write lands between each attempt's seed and its plan, so all five optimistic
   attempts go stale and the apply throws.
2. After the optimistic attempts, one more attempt with the operation gate held from seed to commit; local writes wait.
   A peer runtime writing the same file can still make it stale; that stays bounded and throws.
3. Update the peer test's expected attempt counts (one exclusive attempt more), and log the fallback.
4. Gates: the ten suites, the differential, the library-77 suites; the coordinator decides 77 or 78 from the
   large-store drop A/B (d487ee09 vs 956fce52).

Touching:

- Sources/InstantSwiftDataCore/InstantRuntime.swift (performApplyServerTransaction, a seed-loaded testing hook)
- Tests/InstantSwiftDataCoreTests/InstantBoundedServerApplyRebaseTests.swift
- CHANGELOG.md, docs/audits/commit-changelog.md

Conflict check: InstantRuntime.swift is claimed by this agent for plan 2026-10-01-library-77 (same branch line);
InstantBoundedServerApplyRebaseTests.swift's latest claim is this agent's merged fast-drain-2 plan.
