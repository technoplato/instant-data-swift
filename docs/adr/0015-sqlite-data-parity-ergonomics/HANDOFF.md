# Handoff — ADR 0015 / Instant issue #155

**Written:** 2026-08-06 ~17:47 America/New_York (EDT)  
**Purpose:** Full continuity for the next agent. Chat is disposable; this file +
issue **#155** + `plan.md` + `qanda.md` are not.

---

## 0. Session / lookup identity

| Field | Value |
| --- | --- |
| **Primary Instant issue** | [#155](https://issues.knophy.com/issues/155) — *Stop Instant library logic leaking into Scribe; ship SQLiteData-parity write/observe ergonomics* |
| **Claimant on #155** | `grok-build/architecture-audit-155` (`InProgress`) |
| **Originating Grok session (user paste)** | Session ID `019fd475-f696-75e3-8109-438f65a143de` (title was “Install Latest Build…” but work pivoted to architecture audit) |
| **This agent session (tool paths)** | Workspace often under `.../sessions/.../019fd815-0dfb-7491-9a9d-4b4e40067bbd/` (terminal logs for test runs) |
| **Model** | Grok 4.5 (user_info / Grok Build) |
| **Repos** | `main` only, no PR stacks (user explicit) |
| **Primary repos** | Library: `/Users/laptop/Sync/instant-data-swift` · App: `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` |
| **App → library link** | `Packages/instant-data-swift` → symlink to library checkout |
| **ADR folder (canonical)** | `/Users/laptop/Sync/instant-data-swift/docs/adr/0015-sqlite-data-parity-ergonomics/` |
| **Skill for process** | `$adr-decision-qanda` → `/Users/laptop/Sync/skills/adr-decision-qanda/SKILL.md` (Phase A interview, Phase B plan+issue) |
| **Library dual-dev skill** | `$instant-data` → `/Users/laptop/Sync/instant-data-swift/skills/instant-data/SKILL.md` (active iteration) |

### Cold resume (do this first, every time)

```bash
cd /Users/laptop/Sync/tools/realtime-voice-sqlite-instant
scripts/with-instant-tools-credentials node scripts/instant-tools.mjs query-issue 155

# Then read, in order:
# 1) this HANDOFF.md
# 2) plan.md          (what step is next)
# 3) qanda.md         (only if a product decision is unclear)
# 4) overviews/01-recordings-list.md  (list shape)
# 5) findings.md      (what to delete)

# Implement the first unsatisfied criterion on #155.
# After each coherent commit: update-issue workLog + successCriteria; never leave progress only in chat.
```

---

## 1. Why this work exists (problem statement)

Scribe had reinvented Instant as an **app mini-runtime**:

| Smell | Location (approx) | Problem |
| --- | --- | --- |
| `ScribeInstantStore` (~3k LOC) | `Sources/ScribeSharedSupport/ScribeInstantStore.swift` | Bootstrap + multi-subscribe merge + rehydrate domain graphs |
| `ScribeSharedRealtimeTranscriptionPlanner.liveChanges` / `finalChanges` / `shouldWriteEntities` | `ScribeSharedRealtimeTranscription.swift` | Full previous+current `Recording` document diff |
| `ScribeSharedRealtimeSyncPlanner` | same module family | Merge Instant rows → domain `Recording` |
| `SharedRecordingSnapshotMutationCoordinator` | `SharedRecordingSnapshotClientLive.swift` | Serial queue + **full lastSaved Recording cache** |
| `SegmentSyncStatusTracker` | `SharedModels/InstantEntitySyncStatus.swift` | Fake process-local “sync status” |
| Dual timelines | list + active recording | Memory thrash (#044 related) |

**User verdict:** library logic leaking into the app; polish of `liveChanges` is wrong — delete the model. Goal: SQLiteData-level ergonomics, thin Scribe, better memory.

**Upstream prior art (cite these, not random checkouts):**

| Prior art | Path |
| --- | --- |
| SQLiteData | `/Users/laptop/Sync/instant-data-swift/upstream/sqlite-data` |
| Instant TS | `/Users/laptop/Sync/instant-data-swift/upstream/instant/client/packages/core/src` (esp. `Reactor.js`) |
| PF research (aggregations/sectioning) | `/Users/laptop/Sync/tca/pointfree-research` (ep328, ep374 HTML) |
| Sync boundary | `instant-data-swift/docs/adr/0001-application-sync-boundary.md` |
| Open segment / status | `instant-data-swift/docs/adr/0014-entity-lifecycle-status-and-draft-visibility-in-fetch.md` |
| Scribe product | `realtime-voice-sqlite-instant/docs/adr/0006-instant-observed-transcript-no-dual-timeline.md` |

---

## 2. Process invented this session

### `$adr-decision-qanda` skill

Path: `/Users/laptop/Sync/skills/adr-decision-qanda/SKILL.md`  
Discovery: `~/.agents/skills/adr-decision-qanda` → symlink to that path.

**Phase A — Interview**

- One question / one overview at a time  
- ASCII in overviews and chat  
- Hard separator before next question  
- All decisions in `qanda.md`  
- Plain English (user rejected airline-mechanic metaphors)

**Phase B — Plan** (added when user asked how to turn ADR into plan)

- Write `plan.md` with ordered steps  
- Map each step to Instant issue `successCriteria` ids  
- `workLog` on claim / land / block with **full commit SHA**  
- Cold resume must not depend on chat  

### Agents.md updates

- **Library** `/Users/laptop/Sync/instant-data-swift/AGENTS.md` (same inode as `Agents.md`): fundamentals, write contract (local-only transact), enum policy, multi-bag list, aggregations, correctness over convenience  
- **Scribe** `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/AGENTS.md`: same themes + Instant* name aliases + multi-bag list  

---

## 3. Product / architecture decisions (from `qanda.md`)

Do **not** re-litigate these without user. Full text in `qanda.md`.

| ID | Decision |
| --- | --- |
| Q01 | Always outbox open segments — never skip outbox for interim |
| Q02 | Words = **JSON on segment**, not Instant word entities (`start`/`end`/`text`) |
| Q03–Q04 | Strict Codable JSON types; TS schema gen should carry types where possible |
| Q05 | **Delete** app Instant stores — no `ScribeInstantStore` façade long-term |
| Q06 | **Delete** `liveChanges` / full-document diff planners — do not polish |
| Q07 | Write loop: `recordingSegmentID`; upsert open segment; finalize; new id |
| Q08 | Real sync status from library on fetch — not process-local tracker |
| Q09 | No full lastSaved Recording coordinator |
| Q11 | Memory / performance / ergonomics **before** new features |
| Q12 | Cite vendored sqlite-data / instant TS only for library work |
| Q13 | List: summary + activity ADT; idle no badge; 2-line preview when active/playback |
| Q14 | Active transcription: observe segments; map at request; no stored full transcriptText |
| Q15–Q26 | `transact` = **local only**; never await server on writes; `transactionID` is handle; observe separately |
| Q17 | Teardown order after library path works; **main commits only**; delete store after path proven |
| Q20–Q29 | Relational limit-N segments + map; SQLiteData select prior art; nested limit was library gap |
| Q23 | Activity identity = Instant **client id** |
| Q24 | Generate full transcript by format on demand |
| Q28 | First library milestone: nested limit + map (done L1/L2) |
| Q30 | Aggregations/grouping/sectioning **in scope** |
| Q31 | List = summary + 2 segments + **real attachment thumbnails**; multi-bag map; enums for kind; simplify entity names |

### Recording list shape (current product truth)

```text
Row =
  recording summary (title, duration, activity, …)
  + previewLines[≤2] from Segment.query.order(start).limit(2)
  + thumbnails[] from Attachment entities (not a count)
```

Idle: no badge, hide segment preview; thumbs may still show.  
“Bags” = informal name for each top-level include’s entity array.

### Write contract (library boundary — all apps)

- `await transact` / `save` → local materialize + durable outbox only  
- **Never** server ack on ordinary writes  
- Server wait only via explicitly named wait/observe APIs or entity syncStatus on fetch  

---

## 4. Implementation landed (code)

### Library commits (`instant-data-swift` on `main`)

| SHA | What |
| --- | --- |
| `3948460c4c92f43b3b092f1dc7a979e5cc7c0c92` | **L1** Nested `limit`/`first`/`last` on includes; local materialize applies bounds; live InstaQL passes limit; offset/cursors still banned on nested includes |
| `443ca5ef…` | Mark plan L1 done |
| `1aebc0fdf1560d5a6f76188d5c33c5ab18a41150` | **L2** `InstantFetchRequest(query, children: reverseRelation, map:)` snapshot path so links survive |
| `e7137622…` | Mark plan L2 done |
| `6eecc6e1201b535fa4a5baadf4b3f1cc10cdf953` | **L2b** multi-bag map `(root, bagA, bagB)`; `InstantMediaKind` + `InstantContentType`; Q31 docs |

**Key source files:**

| File | Change |
| --- | --- |
| `Sources/InstantSwiftDataCore/InstantModels.swift` | `InstantQueryIncludePlan.limit/first/last`; `includedEntitySnapshots`; `isSupportedIncludeQuery` allows bounds |
| `Sources/InstantSwiftDataCore/TripleIndexes.swift` | Apply first/last/limit after sort in `materializeSnapshots` |
| `Sources/InstantSwiftDataCore/InstantLiveQuery.swift` | Nested limit/first/last on wire |
| `Sources/InstantSwiftData/InstantTypedAPI.swift` | Include precondition only blocks offset/cursors; `decodeIncludedChildren` |
| `Sources/InstantSwiftData/InstantSwiftData.swift` | Single- and multi-bag `InstantFetchRequest` map inits |
| `Sources/InstantSwiftData/InstantMediaKind.swift` | **New** — `InstantMediaKind`, `InstantContentType` enums |
| Tests | `InstantNestedIncludeLimitTests.swift`, `InstantIncludedMapFetchTests.swift` (single + multi bag), validation parity updated |

**API examples (library):**

```swift
// L1 — nested limit
Root.query.include(Root.segments, Segment.query.order(...).limit(2))

// L2 — one bag
InstantFetchRequest(query, children: Root.segments, map: { root, segments in Row(...) })

// L2b — two bags (list: segments + attachments)
InstantFetchRequest(
  query
    .include(Root.segments, Segment.query.limit(2))
    .include(Root.attachments, Attachment.query.limit(24)),
  children: Root.segments, Root.attachments,
  map: { root, segments, attachments in Row(...) }
)
```

**Tests to re-run:**

```bash
cd /Users/laptop/Sync/instant-data-swift
swift test --filter InstantNestedIncludeLimitTests
swift test --filter InstantIncludedMapFetchTests
swift test --filter upstreamNestedIncludePaginationRestriction
```

### Scribe commits (`realtime-voice-sqlite-instant` on `main`)

| SHA | What |
| --- | --- |
| `c55ce08…` | `Sources/ScribeSharedSupport/InstantEntityNames.swift` typealiases |
| `1dd2c01…` | AGENTS.md fundamentals + multi-bag + enum policy |

**Typealiases (aliases only — full rename not done):**

```swift
// InstantEntityNames.swift
typealias InstantRecording = ScribeInstantRealtimeRecording
typealias InstantSegment = ScribeInstantRealtimeSegment
typealias InstantAttachment = ScribeInstantRecordingAttachment
```

Note: domain TCA model `SharedModels.Recording` is **not** the Instant entity. Do not conflate.

### ADR / docs artifacts (library tree)

```text
docs/adr/0015-sqlite-data-parity-ergonomics/
  README.md          status, cold resume, links
  plan.md            executable steps L1…S5, P1, S0
  qanda.md           all decisions
  findings.md        smells + milestone list
  HANDOFF.md         this file
  overviews/
    01-recordings-list.md           list + thumbs + multi-bag walkthrough
    02-active-transcription.md      open segment write loop
    03-list-query-syntax-sketch.md  real vs goal Instant APIs, SQLiteData prior art
docs/adr/0015-sqlite-data-parity-ergonomics.md   stub body
```

---

## 5. Issue #155 criteria state (at handoff)

| Criterion | Status |
| --- | --- |
| `issue-155-L1-nested-limit` | **DONE** |
| `issue-155-L2-map-selection` | **DONE** |
| `issue-155-L2b-multibag` | **DONE** |
| `issue-155-L3-aggregate-group` | TODO |
| `issue-155-L4-sync-status` | TODO (ADR 0014) |
| `issue-155-P1-client-id` | TODO (parallel OK) |
| `issue-155-S0-entity-names` | TODO (aliases only) |
| `issue-155-S1-list-switch` | TODO — **likely next product integration** |
| `issue-155-S2-write-path` | TODO |
| `issue-155-S3-coordinator` | TODO |
| `issue-155-S4-delete-store` | TODO |
| `issue-155-S5-words-json` | TODO |

Claim still: `grok-build/architecture-audit-155`. Re-claim or keep if continuing same agent id.

---

## 6. What is *not* done (critical for next agent)

1. **Scribe list does not use multi-bag API yet.** Library can do it; app still uses old multi-subscribe / store paths.  
2. **Reverse relations** on real Scribe Instant entities (`segments`, `attachments`) may still be free-string FKs — must wire real `@InstantRelation` / reverse tokens for include to work as in the overview.  
3. **ScribeInstantStore still exists** — do not delete until S1–S2 paths work and are tested.  
4. **liveChanges planners still exist** — still scheduled for deletion after write path rewrite.  
5. **`@Selection` / Columns macros** — not implemented; multi-bag map is the interim.  
6. **Aggregations / grouping (L3)** — decided in scope, not coded.  
7. **Entity sync status on fetch (L4)** — ADR 0014 proposed, not shipped.  
8. **Client id (P1)** — decided as activity identity, not implemented.  
9. **Words as JSON on segment (S5)** — decided, schema/write path not migrated.  
10. **Full rename** off `ScribeInstantRealtime*` — only typealiases.  
11. **Ordering key-path noise reduction** — user wish, not done.  
12. **`screens/` directory** for finalized ADR — not materialized yet.  
13. **Uncommitted in library?** Check `git status` for leftover `docs/adr/0014-…` or `.perf-runs/`.

---

## 7. Recommended next work (ordered)

### Path A — Integrate list (user was aiming here)

**S1-ish:**

1. Audit Instant entity schema: ensure `Recording`↔`Segment` and `Recording`↔`Attachment` reverse relations exist (or add them).  
2. Build Scribe list `InstantFetchRequest` multi-bag map → `RecordingListRow` (see `overviews/01-recordings-list.md`).  
3. Wire list UI to rows (thumbs via `storageFileID`; kind via `InstantMediaKind` / `ScribeRecordingAttachment.Kind`).  
4. Delete multi-subscribe list merge path that dual-joins recordings/transcriptions/segments.  
5. Tests + issue workLog + mark S1 when proven.

### Path B — Parallel library

- **P1:** expose Instant client/local id; activity ADT comparison.  
- **L4:** sync status on fetch (coordinate ADR 0014).  
- **L3:** group/count/section maps.

### Path C — Write path teardown (after list or in parallel carefully)

- S2: `recordingSegmentID` upsert only; delete liveChanges.  
- S3: delete lastSaved coordinator.  
- S5: words JSON.  
- S4: **delete** `ScribeInstantStore` (bootstrap only at composition root).

**User said:** do not delete store first; after path works, rip the band-aid. Main commits only.

---

## 8. API design notes still open (not blocking S1)

| Topic | Status |
| --- | --- |
| Single `children:` vs multi-bag | Multi-bag landed for **two** reverse includes; more than two not generalized |
| Infer single include (Variation B) | **Rejected** by user |
| Map on include (child map) | Deferred; multi-bag parent map preferred for list |
| Bags as generated struct vs positional args | Positional `map(root, a, b)` shipped; generated Bags struct still nicer long-term |
| SQLiteData `.select { Columns }` | Long-term; not shipped |

---

## 9. How to verify environment

```bash
# Library
cd /Users/laptop/Sync/instant-data-swift
git log --oneline -5
git status -sb
swift test --filter InstantNestedIncludeLimitTests
swift test --filter InstantIncludedMapFetchTests

# App
cd /Users/laptop/Sync/tools/realtime-voice-sqlite-instant
git log --oneline -5
ls Packages/instant-data-swift   # should be symlink
git status -sb

# Issue
scripts/with-instant-tools-credentials node scripts/instant-tools.mjs query-issue 155
```

---

## 10. Glossary for this program

| Term | Meaning |
| --- | --- |
| **Bag** | Array of entities from one top-level `.include` on a parent (not a type) |
| **Multi-bag map** | `map(root, bagA, bagB)` after two includes |
| **recordingSegmentID** | The segment currently being written during speech (not “open segment” name) |
| **Local-only transact** | Success = SQLite + outbox durable; not server ack |
| **Composition root** | App startup / dependency bootstrap — not a product Instant store type |
| **Domain Recording** | TCA/SharedModels timeline model |
| **InstantRecording** | Instant schema entity (typealias to ScribeInstantRealtimeRecording for now) |

---

## 11. Explicit non-goals until fundamentals move

User: library memory, performance, ergonomics first — **no new product features** that depend on Instant until this program advances.

---

## 12. Message to the next agent

You are not starting from zero. **L1/L2/L2b are done.** The gap is **Scribe not consuming the new APIs** and the **old store/planners still owning the world**. Prefer S1 list multi-bag integration next unless the user redirects to P1/L4. Always append #155 workLog with real SHAs. Read `overviews/01-recordings-list.md` before coding the list.

If something in this handoff conflicts with a newer `workLog` on #155, **trust the issue**.


---

## Resume note (2026-08-06 18:15 EDT)

Next agent after cold resume found L1/L2/L2b done and executed **S1 partial**:

| Landed | SHA / note |
| --- | --- |
| Library `InstantFetchRequest(snapshotsOf:)` | `de1fa08e242f632dac05c4f3414698e4ba58c4e2` |
| Scribe multi-bag list observation + schema links + dual-write | `c269476db7798b0d0599d22deaaefe39b15ee1fe` |
| Instant schema push | `recordingSegments`, `recordingHasAttachments` |

**Still open for S1 full:** nested include limit on the Scribe pin (L1 not in published 1.5.6; `swift package edit` hits Tailnet InstantDBLogger name clash), ListRequest Fetch seed still dual top-level, store teardown (S4) not started.

**Next:** pin library after L1 or fix dual-dev package edit; then InstantFetchRequest multi-bag seed; or parallel P1/L4.
