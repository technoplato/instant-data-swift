# ADR 0015 — Implementation plan

- **Status:** Ready to execute (decisions locked)
- **Parent issue:** [#155](https://issues.knophy.com/issues/155)
- **Related:** #044 memory, #092 streams, library ADR 0014, Scribe ADR 0006
- **Process:** Commits on `main` only (no PR stacks). Each step = coherent commit(s) + Instant workLog.
- **Prior art:** SQLiteData join / `group` / `count` / `@Selection` / `.select { Row.Columns }` in `upstream/sqlite-data`; TS Instant in `upstream/instant/...`; PF research optional under `/Users/laptop/Sync/tca/pointfree-research` (ep328, ep374).

## Follows SQLiteData?

**Yes.** Target ergonomics:

| SQLiteData | Instant goal (this plan) |
| --- | --- |
| `@FetchAll` + join + `.select { Columns }` | Nested include (bounded) + request-time **map** / Selection-shaped row |
| `.group` + aggregate counts | Aggregations / sectioned maps (not only flat arrays) |
| `database.write` local-only | `transact` local-only (never server) — already ADR 0010/Q26 |
| No app SyncStore façade | Delete `ScribeInstantStore` after path works |

If Instant wire cannot nest-limit includes, document **Swift-local bound materialize** as an adaptation — still present the same app API shape.

## Done means (parent #155)

See issue successCriteria; plan steps below map 1:1 to criteria ids to add/update on #155.

## Work items

| ID | Step | Repo | Depends | Criterion id | Tests / evidence |
| --- | --- | --- | --- | --- | --- |
| L1 | Nested limit-per-parent on reverse `include` (e.g. 2 segments/recording) | instant-data-swift | — | `issue-155-L1-nested-limit` **done** `3948460c` | Unit: InstantNestedIncludeLimit; validation parity |
| L2 | Request-time **map** (+ Selection/Columns-shaped list row direction) | instant-data-swift | L1 | `issue-155-L2-map-selection` | Fetch returns flat list DTO; no dig into full Segment graph in sample |
| L3 | Aggregations / group / sectioned result maps | instant-data-swift | L2 | `issue-155-L3-aggregate-group` | Count-on-row or sectioned fixture like Reminders/SyncUps |
| L4 | Entity sync status on fetch (coordinate ADR 0014) | instant-data-swift | — | `issue-155-L4-sync-status` | Status ADT on observed row in test |
| P1 | Instant **client id** for activity ADT (parallel) | instant-data-swift + Scribe | — | `issue-155-P1-client-id` | this vs other device comparison |
| S1 | Scribe list → new query; **delete** multi-subscribe list merge | Scribe | L1–L2 | `issue-155-S1-list-switch` | List tests; no dual stream merge |
| S2 | Write path: `recordingSegmentID` upsert only; **delete** liveChanges/diff planners | Scribe | L4 optional | `issue-155-S2-write-path` | Planner deleted or unused; segment-only writes |
| S3 | **Delete** mutation coordinator full `lastSaved` cache | Scribe | S2 | `issue-155-S3-coordinator` | No full Recording retained for Instant diff |
| S4 | **Delete** `ScribeInstantStore`; bootstrap only at composition root | Scribe | S1–S3 | `issue-155-S4-delete-store` | No store type; features use `@Fetch*` / client |
| S5 | Words JSON on segment; drop process-local sync tracker | Scribe | S2 | `issue-155-S5-words-json` | Schema + strict Codable; no word entity live path |

## Execution order

```text
L1 → L2 → S1          (list unblocked)
L3, L4, P1            (parallel after or beside L2 as capacity allows)
S2 → S3 → S5 → S4     (write path then delete store last among Scribe steps)
```

Do **not** S4 before S1/S2 work. After S1–S5 verified, rip store completely.

## Out of scope (this plan)

- New product features unrelated to Instant ergonomics/memory
- GitHub Issues as tracker
- PR stacks (main commits only)

## Cold-agent resume recipe

```bash
cd /Users/laptop/Sync/tools/realtime-voice-sqlite-instant
scripts/with-instant-tools-credentials node scripts/instant-tools.mjs query-issue 155
# Read workLog + successCriteria — find first unsatisfied issue-155-L* / S* / P*
# Read:
#   /Users/laptop/Sync/instant-data-swift/docs/adr/0015-sqlite-data-parity-ergonomics/plan.md
#   qanda.md (only if a decision is unclear)
#   findings.md
# Implement that step on main; append workLog with commit SHA; re-query issue
```

## Per-step workLog template

```text
state: in-progress | landed | blocked | verified
summary: plan step L2 — what landed — tests run — next step id
commitSha: <full sha when landed>
```

## References

- Interview: `qanda.md`
- Smells/deletes: `findings.md`
- List query sketch: `overviews/03-list-query-syntax-sketch.md`
- Skill: `$adr-decision-qanda` Phase B
