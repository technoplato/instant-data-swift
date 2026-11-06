# Plan 2026-11-06-held-writes-696: every held write ends known: verify it on the server, then complete or discard it

- planId: 2026-11-06-held-writes-696
- agentId: claude-code/held-writes-696@al (tools/agent-run, claude, opus)
- role: grower (P0 #696, criteria 5-8 merged from #134; a public recovery API the issue names; the commander's ruling of
  2026-11-06 09:33 keeps them in scope)
- issue: #696 (related #134, #441, #445, #1435)

## Why

Since 1.9.10 a retained mutation whose local cache effect is unknown (no SQLite-owned preparation receipt, which includes
a row that predates durable optimistic-overlay metadata) is moved at launch, whole, into `instant_outbox_quarantined`,
and every other write synchronizes. The library lists, counts and sends again a held mutation; nothing settles one.
#134's first criterion asks for a public, documented recovery API that verifies the authoritative server effect, then
completes or discards the mutation, without guessing at the local cache effect.

Two facts shape the design:

- The device's merged view is not evidence. `queryOnce` answers from the local store after the server's answer is
  applied: unsent later writes overlay it, and a held write's own leftover optimistic effect can still be in the
  triples. A verify that read it could call a write applied that never landed. The verify reads the rows the server's
  answer carried.
- A differing value is not proof that a write never landed: a later write can replace it, and the server keeps a value's
  first-insert time, not its last update (`triple.clj`, `ea-conflict-update-set` without `overwrite-t`), so timestamps
  cannot rule a later write out. "Not applied" therefore needs delivery evidence: the kept outbox row says it was never
  offered (`delivery_started = 0`), or the server refused it with a client-error status.

## Steps (no code here)

1. This plan and its claims, landed on main.
2. Red (`InstantHeldWriteVerificationTests`, synthetic fixtures only; no device store is committed): the verdict as a
   pure function of the write's slots, the server's rows and the delivery evidence; and through a fake live server, held
   rows shaped like #134's (no overlay metadata) and #696's (no preparation receipt): the server applied it and the
   acknowledgement was lost (applied, complete); the server refused it (not applied, discard); it never left the device
   (not applied, discard); it was sent, no answer came, and the server's rows do not hold it (cannot tell, stays held,
   says why); a later accepted write of this device replaced it (applied); another writer replaced it after a send whose
   answer never came (cannot tell); the held write's own effect is still in the local cache but not on the server (never
   applied); the server cannot be read (cannot tell); a deletion, retraction or lookup step (cannot tell). Complete and
   discard re-verify, refuse any other verdict, record a resolution with its evidence, and leave each body's SHA-256
   unchanged; lifecycle observers see accepted or failed instead of waiting. A retainedUnknown row still in the outbox is
   held first, the same move launch makes.
3. Green: a pure verdict (`InstantHeldWriteVerification`), a one-shot read of the server's own rows (the `add-query-ok`
   answer for the read's registration, taken where it arrives), persistence for the resolution and its evidence, and
   `verifyQuarantinedMutation(id:)`, `completeQuarantinedMutation(id:)`, `discardQuarantinedMutation(id:)` on the runtime
   and the client.
4. Upgrade guidance (criterion 7): what launch does to an existing outbox, and how an installed iPhone or iPad recovers
   its held writes in place.
5. Release v1.9.79 (release record, PROGRESS.md, CHANGELOG two-commit entry, cross-repository ledger), tagged on main.
6. Scribe pins 1.9.79 in its own worktree; build, install, `zsh scripts/e2e-sync/gate.sh`; criteria ticked with evidence
   (criterion 6 recorded as not meetable as worded: its 34 rows are gone).

## Touching

Sources/InstantSwiftDataCore/InstantQuarantinedMutation.swift, Sources/InstantSwiftDataCore/InstantHeldWriteVerification.swift
(new), Sources/InstantSwiftDataCore/SQLitePersistenceStore.swift (the quarantine section and the held-row lifecycle only),
Sources/InstantSwiftDataCore/InstantRuntime.swift (the quarantine API beside `retryQuarantinedMutation`, a server-rows read
beside `queryOnceThroughLive`, and one capture line in the `add-query-ok` handler; not the acknowledgement wait, not
`applyLiveRefresh`), Sources/InstantSwiftData/InstantSwiftData.swift (the quarantine API only),
Tests/InstantSwiftDataCoreTests/InstantHeldWriteVerificationTests.swift (new), docs/held-writes.md (new),
docs/releases/v1.9.79.md (new), PROGRESS.md, CHANGELOG.md, docs/audits/commit-changelog.md.

## Conflict check

The quarantine files carry only #696's first claim (2026-10-14). InstantRuntime.swift, SQLitePersistenceStore.swift and
InstantSwiftData.swift carry the 2026-11-04/05 perf plans (#1796, #1797, #653, #1491); this plan touches none of their
regions. No outbox column, no schema migration: the quarantine table gains its evidence column only when a resolution is
first written, as the table itself is created only by the first quarantine. Channel:
agent-presence/_channels/2026-11-06-held-writes-696.md.

## Amendment 1 (2026-11-06T14:24:12-0500): InstantSlotCoverage is Codable

A completion or discard records its verification beside the kept row, as JSON; the verification's slots are
`InstantSlotCoverage` (#445), so that struct and its `Operation` and `Coverage` enums gain `Codable` (synthesized,
additive, declarations only). Touching adds Sources/InstantSwiftDataCore/InstantModels.swift.

## Outcome (2026-11-06T16:13:55-0500)

Landed on main: red `e48ab65d`, green `9d26d2ca`, guide `339ca746`, release `ae2c6b99` (tag v1.9.79), changelog
`1fd335e9`, ledgers `26431e1c` and `eee3ea19`. Mac mini: red 9 of 10 fault tests fail; green 23 tests in 3 suites
pass; the whole bundle 1,756 tests, its two unlisted failures not this change's (#1948 fails the same at v1.9.78; a CPU
ratio passes alone). The consuming app pins 1.9.79 (its `a1ed2555b`); no separate build was cut for an invisible pin,
the next cut carries it. #696: criteria 1-5, 7 and 8 met; 6 recorded as not meetable as worded (its 34 rows are gone).
Claims released.
