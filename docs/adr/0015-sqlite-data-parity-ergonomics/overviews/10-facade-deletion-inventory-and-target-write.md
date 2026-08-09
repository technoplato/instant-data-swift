# Overview 10 — Kill Instant façades; target Instant + TCA write/read

**Status:** Owner-directed 2026-08-09 — prioritize migration + library SQLiteData
parity ergonomics **before** dual-wrestling app façade performance and library
performance as if they were one problem.

**Parent:** ADR 0015 / Instant issue [#155](https://issues.knophy.com/issues/155)  
**Scribe axioms:** repo root `Agents.md` (Instant I/O rules at top)

---

## 1. SQLiteData ergonomics Instant still lags (library first)

Borrow from `upstream/sqlite-data`. Gaps that force app hacks:

| SQLiteData | Instant today | Gap id |
| --- | --- | --- |
| `@FetchAll` / `@FetchOne` + structured query on feature state | `@Fetch` exists; rarely used in Scribe features | App adoption + docs |
| Join + `.select { Columns }` / `@Selection` list rows | Nested include + **map** (L1/L2/L2b **done**) | Columns macros still thin |
| `.group` + aggregates / sectioned lists | Not shipped | **L3** open |
| Row observation carries sync/delivery status | Not on fetch | **L4** / ADR 0014 open |
| `database.write { }` local-only, no app SyncStore | `transact` local+outbox (correct contract) | App still wraps in façades |
| One table model = one write surface | App still plans mutations from domain `Recording` graphs | Sparse open-segment **recipe + examples** weak |
| High-churn same-row updates | Outbox can pile supersedable ops | Same-entity supersession missing |
| Typed columns | JSON blobs need app Codable + loud fail | Typed JSON binding incomplete |

**Rule:** finish or land the missing library shapes (L3/L4 + write recipes), then
delete app adapters that only exist to paper over them. Do not optimize
`ScribeInstantStore` as a product.

---

## 2. Target architecture (Instant + TCA)

```text
Composition root (once)
  bootstrapInstantSwiftData(appID, schema attrs, live sync)
  install @Dependency(\.defaultInstantSwiftData)
  optional auth guest/sign-in

TCA feature
  @Fetch*  … observe entities (list, open recording, companion listeners, …)
  Action / effect:
    await client.transact { entity.upsertMutation }   // or library draft.save
    // business logic = which entity fields to set (open segment, title, …)
    // NOT = invent InstantMutation lists via planners

No: ScribeInstantStore, SharedRecordingSnapshotClient as Instant façade,
    full-document planners, manual multi-subscribe merge, process-local sync fakes.
```

### Target speech write (sketch)

Domain still has TCA `Recording` for UI/timeline. Instant write is **not** “save the
Recording document.”

On each speech update (open segment only):

1. Know `recordingID`, `segmentID` (or allocate once), `ownerUserID` from auth.
2. Ensure recording row exists (create once with title / `startedAtMs` / owner + owner link).
3. Upsert **one** `transcriptionSegments` entity:
   - `wordsJSON` = strict Codable `[Word]` (or agreed schema)
   - `text`, times, `segmentIndex`, `updatedAtMs`, `ownerUserID`, …
4. `await client.transact { … }` — local + outbox only.
5. UI observes via `@Fetch` / subscription on that segment or recording include
   (bounded). Sync status from library on fetch when L4 lands.

**Business logic that stays in the app:** when to roll a new segment, how to build
preview lines, export SRT/Markdown from segments on demand.

**Business logic that must not stay:** previous/current full `Recording` diff,
multi-stream rehydrate planners, wait-for-server inside save, serial “snapshot
client” as the only Instant door.

### Target stream companion (sketch)

```swift
// Feature or small Observable model
@FetchAll(ScribeInstantAgentCompanionListener.query.order(...).limit(50))
var listeners

// Write
try await client.transact {
  ScribeInstantAgentCompanionRequest(request).upsertMutation
}
```

No `ScribeInstantStore().loadStreamCompanionListeners()`.

---

## 3. Inventory — `ScribeInstantStore` (~122 refs)

### A. Definition / bootstrap (keep shape, kill type name)

| Location | Role |
| --- | --- |
| `ScribeInstantStore.swift` | Mega-file: bootstrap, CRUD, media, entities (~3.5k LOC) |
| `ScribeInstantBootstrap.swift` | Thin wrapper → still calls store.bootstrap |
| `ScribeSharedApp` / CLI / StreamAgentCLI / YouTube CLI | Call `ScribeInstantStore.bootstrap` |
| `ScribeInstantBootstrapView` | UI gate until Instant ready |

**Target:** `ScribeInstantBootstrap.bootstrap` owns composition root only; returns
`InstantSwiftDataClient`; **no** product store type.

### B. Production façades still calling the store

| Location | What it does via store |
| --- | --- |
| `StreamCompanionClient` live | **peeled 2026-08-09** → `InstantStreamCompanion` + Instant client |
| `AppFeature` | **peeled 2026-08-09** → `streamCompanionClient` only |
| `ScreenStreamSessionClient` | upsert/observe screen stream sessions |
| `ScribeImageAnalysisClient` | load/upsert image analysis + prompts |
| `ScribeSharedRealtimeTranscription` | load local realtime, `apply`, media, delete, waitUntilDelivered |
| `ScribeAgentRoomInstant` (extension methods) | agent room declare/observe/update + companion helpers |
| `ScribeAgentWatcher` / `ScribeAgentClaudeResponder` / YouTube audit | inject store for agent upserts |
| `ScribeRecordingLibrary` | **only** page-size constants (easy peel) |

### C. Write adapters (not named Store, still façades)

| Symbol | Role | Target |
| --- | --- | --- |
| `SharedRecordingSnapshotClient` | TCA dep: save/delete `Recording` | Delete; feature/effect → Instant |
| `SharedRecordingSnapshotMutationCoordinator` | Serial queue (lastSaved cache already reduced) | Prefer Instant client seriality / single writer if needed |
| `ScribeRecordingLibrary.save` + planner | Domain graph → mutations | Collapse to open-segment entity upserts |
| `ScribeSharedRealtimeTranscriptionPlanner` | openSegment/checkpoint upserts; deprecated liveChanges | Keep pure field mapping only if tiny; delete diff engine |
| `OpenSegmentWriterLive` | CLI/harness port to library.save | CLI may call Instant directly |

### D. Tests

| Location | Notes |
| --- | --- |
| `ScribeInstantStoreTests` | Large store suite — migrate or delete with S4 |
| `InstantStoreNamingTests` / architecture | Enforce no new façade |

---

## 4. Migration order (execute on main, #155 workLog)

```text
Phase 0  Document + AGENTS axioms (this file) — done with this commit
Phase 1  Peel easy: constants; StreamCompanion + AppFeature → client.transact/query
Phase 2  Screen stream + image analysis → client + @Fetch where UI observes
Phase 3  Speech: RecordingList/Recording effects stop SharedRecordingSnapshotClient;
         open-segment entity write helper (not store); delete snapshot client
Phase 4  Agent room/watcher/CLI: free functions or feature @Fetch; no store param
Phase 5  Move @InstantEntity models out of ScribeInstantStore.swift into InstantEntities/*
Phase 6  Bootstrap-only file; delete ScribeInstantStore type; architecture test red→green
```

Parallel **library:** L3 aggregates, L4 sync status on fetch, open-segment example in
instant-data-swift Examples, outbox supersession for high-frequency segment upserts.

**Performance soaks** re-enter after Phase 3 (speech path is Instant-only) so we
measure the real stack.

---

## 5. Acceptance (S4 done means)

- [ ] Zero product/feature references to `ScribeInstantStore` (bootstrap module may use private helpers)
- [ ] Zero `SharedRecordingSnapshotClient` in RecordingList/Recording
- [ ] List + live speech + stream companion use `@Fetch*` / `client.transact`
- [ ] Architecture test fails if `ScribeInstantStore` is reintroduced
- [ ] #155 criteria S3/S4/S5 verified; workLog SHAs on issue

---

## 6. Owner quotes (2026-08-09)

- Writes and reads should go through Instant; no façades, no stores.
- Features should not need a “snapshot client”; reducer → Instant `@Fetch` / `transact`.
- Entity models belong in the app (own files); planner/store are cruft.
- Prioritize this migration and library SQLiteData parity before more dual perf thrash.
