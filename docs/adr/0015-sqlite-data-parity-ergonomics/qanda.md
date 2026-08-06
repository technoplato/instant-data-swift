# ADR 0015 — Q&A log

Single file for the whole interview. Newest questions go at the bottom as
`open`. Chat presents **one** `asking` / overview item at a time.

Process skill: `$adr-decision-qanda`.

---

## Q01 — Always outbox-sync open segments

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Always local materialize + durable outbox for interim open-segment updates; never skip outbox to save cost.
- **Question:** Must other devices see non-final text in real time?

### Answer

Yes. Always outbox-sync open segments. Every interim upsert goes local + durable
outbox + peers. Fix cost with write shape (open segment only), never by skipping
the outbox.

### Follow-ups spawned

- Q07 — sparse open-segment write API spelling

---

## Q02 — Words storage model

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** No separate Instant word entities; words live on the segment.
- **Question:** Are per-word Instant rows required during live speech?

### Answer

Words are a **JSON array / blob on the segment**, not Instant entities. Fields:
start time, end time, text. No need to index words in InstantDB.

### Follow-ups spawned

- Q03 — strict Codable typing for JSON attributes
- Q04 — TypeScript schema generics for JSON

---

## Q03 — Strict Codable types for JSON attributes

- **Status:** decided (intent); API spelling open
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Schema-level Encodable/Decodable binding; fail loud on drift.
- **Question:** How strict should JSON blob encode/decode be?

### Answer

Must specify an encodable type at the schema level (a struct). At write and read
time, no schema drift: very strict parsing and encoding. Instant does not do
this for free — library/app schema tooling must.

Exact macro/API spelling deferred (open item under Q07/Q14).

---

## Q04 — TypeScript schema generation for typed JSON

- **Status:** decided (intent); implementation open
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** When generating `instant.schema.ts`, provide Instant TS generics/types for JSON fields where the Instant API allows.
- **Question:** Should TS schema generation carry typed JSON?

### Answer

Yes — provide generics to the Instant schema generation path so TS stays aligned
with the Swift Codable types.

---

## Q05 — App-level Instant stores / ScribeInstantStore

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Delete shadow stores; composition root only for bootstrap.
- **Question:** Is ScribeInstantStore acceptable?

### Answer

No. App-level Instant stores are a complete anti-pattern. Remove Instant store
façades. Features should look like Todos / VoiceTrail: `@Fetch*` + `transact` /
`save`, not a 3k-line store. Multi-subscribe merge, domain rehydration merge
loops, and full-document snapshot coordinators do not belong in the app.

---

## Q06 — liveChanges / previous-current full Recording diff

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Do not polish `liveChanges`; delete the model.
- **Question:** Keep liveChanges/finalChanges/shouldWriteEntities?

### Answer

No. Do not emit “open + just-finalized via full-document state diff.” Correct
model: **record the open segment, publish updates to that segment, finalize it,
move to the next segment and publish that one.** No previous full Recording
cache. No 300ms full saveSnapshot of the whole timeline for Instant planning.
Push back accepted: red-testing liveChanges is lower value than removing the
path.

---

## Q07 — Active transcription write loop (product)

- **Status:** decided (product shape)
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** One open segment id; upsert only that row (+ words JSON); finalize; new id.
- **Question:** What is the live write loop?

### Answer

- Keep which segment is open in app speech state
- Upsert that segment only (text + words JSON + isFinal false)
- When speech finalizes the section: set isFinal true, stop touching that id for
  the rest of the session under current product scope
- Start a new segment id for the next interim and publish that

Late renames / post-final text edits are **not** current use cases. Allowed
eventually, not an invariant the system must encode now.

---

## Q08 — Sync status ownership

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Library projects status on fetch rows immediately.
- **Question:** Process-local SegmentSyncStatusTracker OK?

### Answer

No. Library must own immediate / real sync status on observed entities. App only
displays it. Delete fake process-local maps.

---

## Q09 — Mutation coordinator / lastSaved full Recording

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Library owns serialization/coalescing if needed; app must not retain full previous Recording for Instant diffs.
- **Question:** Keep SharedRecordingSnapshotMutationCoordinator?

### Answer

No as a full-document cache. Concurrent save ordering and outbox supersession
belong at the library level (or become unnecessary if writes are single-segment
upserts).

---

## Q10 — Analogy style for explanations

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Plain English only.
- **Question:** Airline-mechanic style OK?

### Answer

No. Plain English. No airline/restaurant metaphors unless requested.

---

## Q11 — Fundamentals priority vs new features

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Memory, performance, ergonomics before more features.
- **Question:** Can feature work continue in parallel?

### Answer

Library functions today with terrible performance, terrible memory, and
ergonomics still WIP. Nail those three first. No more feature work until
fundamentals are solid. Agents.md must state this at the top.

---

## Q12 — Dual SQLiteData checkout citations

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Prefer library vendored `upstream/sqlite-data` when citing from Instant work.
- **Question:** Why two SQLiteData paths?

### Answer

User does not want two competing sources. For Instant library work, cite
`/Users/laptop/Sync/instant-data-swift/upstream/sqlite-data` (and Instant TS
under the same repo’s `upstream/instant`). The `/Users/laptop/Sync/tca/sqlite-data`
checkout is not required as a second reference in guidance.

---

## Q13 — Overview: recordings list (10-foot)

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Summary list + product activity ADT + bounded latest-segment preview. No full timelines. No previous/current document diffing.
- **Question:** Does the revised `overviews/01-recordings-list.md` match what you want?

### Answer (final)

**Accepted** with refinements:

- Summary list; no full timelines / all segments / all words / second full in-memory graph.
- No multi-subscribe merge; no full-document Instant diffing (anti-pattern).
- **Activity is an ADT** (algebraic data type). Cases include at least:
  - `active(device: …)` — which device is currently recording; **other** should
    carry a device/client id when known (prefer Instant local/client id — Q23)
  - `playback` (this device; may also carry device id later)
  - idle is the default/absent presentation: **do not show an “idle” badge**
- Active · this device → continue recording here on tap.
- Latest segment **bounded preview**: **two lines** of text (not unlimited).
- **Idle rows hide preview** (no latest-segment text when idle).
- Playback **is** a list status (user accepted the overview including playback).
- Active-elsewhere UX details remain later (Q19).

User: “Does this revised list overview match what you want? … that all looks good.”

### Follow-ups spawned

- Q18 — preview = two **lines** of text (decided here; close Q18)
- Q19 — how “active on other device” is represented
- Q20 — list data shape: bounded include vs denormalized latestSegmentText
- Q22 — screens directory when ADR finalized (process)

---

## Q14 — Overview: active transcription (10-foot)

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Observe segments for this recording; app tracks current recording segment id; upsert that segment only; words JSON; always outbox; library syncStatus on rows.
- **Question:** Does `overviews/02-active-transcription.md` match what you want?

### Answer

**Accepted** with nitpicks:

- Rename **open segment id** → **recording segment id** (the segment currently being recorded/updated for this speech lane).
- **No `transcriptionText` / full joined transcript storage.** Segments + words JSON only. If a full document is needed, **generate on demand** (“generate full transcript”) into the format required (SRT, DTT, Markdown, JSON, …) — same family as copy-as-format. We will not guess every export format in the DB.
- Write loop and observation overview otherwise accepted (including library sync status on rows, always outbox, no full-document diff).
- User reaction to previous/current full-document diff approach: reject as imbecilic; do not revive.

### Follow-ups spawned

- Q15 — await on write hot path
- Q23 — Instant client / device local id in library for activity ADT
- Q24 — export / generate-full-transcript surface (formats) — may defer

---

## Q15 — await on writes vs SQLiteData

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Hot path never waits for server ack. `await transact` must mean local materialize + durable outbox only. Return/use `transactionID` for optional later observation. No polymorphic “async sometimes means network.”
- **Question:** Is that the right await rule for recording-segment upserts?

### Library facts (investigated 2026-08-06)

1. **`transact` already returns a transaction id** via
   `InstantStoreMutationResult.transactionID`
   (`InstantSwiftDataCore/InstantStore.swift`).
2. Builder form `transact(id:createdAt:build:)` generates an id (runtime
   `makeID()` or UUID) and returns that result after local apply
   (`InstantTypedAPI.swift` ~2342–2377).
3. **ADR 0010 (Accepted):** `transact` commits optimistically to SQLite and
   starts live delivery **without blocking the caller** for server ack.
   `waitForAllPendingMutations` is the **exceptional** server-wait API (CLI /
   short-lived tools / explicit durability).
4. **`async` today is not “wait for Instant cloud.”** It is async for local
   runtime/SQLite actor work. Returning from `await transact` means local store
   + outbox enqueue succeeded (or threw). Offline must still succeed.
5. **Lifecycle already exists:** `runtime.observeMutationLifecycle(id:)` →
   `AsyncStream<InstantMutationLifecycleEvent>` (pending / serverAccepted /
   failed / …). Typed `send` can fire `onOptimisticCommit` then optionally wait
   on that stream; fire-and-forget `send` returns a `Task` and does not block
   the caller.
6. **Polymorphic risk (user concern):** `InstantMessage.send` overloads can
   either fire optimistic + callbacks or **await terminal server lifecycle**.
   That is two different meanings of “async send” and is the smell to clean up
   in API design — not to paper over with longer timeouts.

### Answer

**Accepted** as a **library-wide** rule (not Scribe-only):

- `await transact` / `save` = **local-first commit only** (local SQLite +
  durable outbox). Never server acknowledgement.
- Offline must succeed.
- **No write API awaits the server.** Server is always a separate observe/wait
  path with names that say so (`wait…`, `observeTransaction`, entity
  `syncStatus` on fetch).
- `async` means local runtime/DB work finished — same family as SQLiteData
  `database.write`, not a cloud round-trip.
- Thread-blocking sync writes rejected (pushback accepted).
- Transaction id already exists on `InstantStoreMutationResult`; product code
  should treat it as the delivery handle; publicize
  `observeTransaction(id:)` (wrap existing lifecycle).

Clarification on “surface transaction id”: the field **already exists**. Work
item is documentation + ergonomics (primary documented return / handle), not
inventing a second id type. Do not bury “you can find transactionID if you
know where to look.”

### Follow-ups spawned

- Q26 — API shape details (closed with same answer)

---

## Q26 — Write API shape: local-only await + transaction id (vs sync)

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Keep `async throws` for local commit (SQLite/actor),
  document hard rule “never means server,” always surface `transactionID`,
  public `observeTransaction(id:)` on the client (wrap lifecycle). Never await
  server on **any** write (library boundary). Full thread-blocking sync write
  rejected.
- **Question:** Accept recommendation, or require a truly synchronous write API?

### Answer

**Accept.** User: pushback on blocking sync is right; intended shape is fine;
“Never await server on any writes… we're talking about the library… be
generic.” Point-Free–level docs/code quality bar added to Agents.md (Q27).

---

## Q27 — Point-Free parity for code and documentation quality

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Match Point-Free quality of commentary, API docs, and
  examples (SQLiteData, TCA, TCA2 checkouts on machine).
- **Question:** Documentation/code quality bar?

### Answer

Yes. Agents must aim for **code quality and documentation quality on par with
Point-Free**. Visit local references: SQLiteData, TCA / pfw trees under
`/Users/laptop/Sync/tca` (and library `upstream/sqlite-data`). Write API
commentary in the same clear style (e.g. “async throws for local-only
completion; observe transaction as AsyncStream or entity syncStatus on fetch”).

---



## Q16 — Agents.md + instant-data skill dual lifecycle

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Fundamentals banner in Agents.md; evolve `skills/instant-data` for Scribe+library co-development; mark in-active-iteration with user.
- **Question:** Confirm skill text once drafted.

### Answer

Landed during interview: Scribe + Instant Agents.md fundamentals, write
contract, correctness-over-convenience, aggregations note; `$instant-data`
active iteration; `$adr-decision-qanda`. Further edits as work proceeds.


---

## Q17 — Deletion order / migration plan for ScribeInstantStore

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Library nested limit+map (+ Selection) first; prove list/write path; then delete app façade on main (no PR stacks).
- **Question:** Order of removal for store, planners, coordinator, word entities?

### Answer

**Accepted** with process notes:

- Work lands as **commits on `main`**, not PR stacks.
- **Do not delete ScribeInstantStore first** — ship/test nested limit + map path,
  then **rip the band-aid**: remove the store entirely (not a long-lived hollow
  façade). Bootstrap Instant only at the **composition root** (app entry /
  dependency setup) — no product type named ScribeInstantStore.
- Activity **client id** work can **parallel**.
- Aggregations/grouping/Selection: same program, follow-on **main commits**
  (user: not “PRs”).
- Teardown sequence after library path works:

  1. Library: nested limit + map (+ Selection-shaped rows as we can)
  2. Library: aggregate/group/section helpers (follow-on main commits)
  3. Scribe list: new query; delete multi-subscribe list merge
  4. Scribe write: recordingSegmentID upsert only; delete liveChanges/diff planners
  5. Delete SharedRecordingSnapshotMutationCoordinator + lastSaved full cache
  6. **Delete ScribeInstantStore** (bootstrap stays composition-root only)
  7. Words as JSON on segment; drop process-local SegmentSyncStatusTracker


---

## Q18 — Latest segment preview limit on list rows

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Two lines of preview text; idle rows hide preview.
- **Question:** Is N=1 enough for the list item preview?

### Answer

Preview is **two lines** of text (UI line limit). Idle rows **hide** preview entirely.

---

## Q19 — “Active on other device” representation

- **Status:** decided (identity via Q23; field still product schema)
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Explicit durable activity on the recording carrying Instant client id; this vs other = compare to local client id.
- **Question:** How do we mark active-here vs active-elsewhere?

### Answer

Compare activity’s **client id** to this process’s Instant **local client id**
(Q23). Durable product field on the recording (or equivalent), not TCA-only
inference. Exact write rules when starting/stopping record/playback remain
implementation detail under the ADT.

---

---

## Q20 — List latest-segment data shape

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Relational bounded include of latest N segments (not denormalized full transcript). Library query ergonomics + map/truncate helpers.
- **Question:** Denormalized preview fields vs bounded include for list preview?

### Answer

**Not denorm of convenience transcript fields** as the primary design. Prefer
the **most correct** approach:

1. List query supports **include / nested limit** of the **two most recent
   segments** per recording (library must make this safe and non-thrashy —
   document misuse).
2. Library ergonomics provide a **nice map** from raw Instant rows → list row
   view model, including **truncate** segment text for display (e.g. a segment
   body that is 400 lines long still only paints two preview lines). InstantDB
   cannot do that display map server-side; the library/app mapping layer does.

Denormalized fields are an anti-pattern if used to avoid fixing query
ergonomics. Correctness over ease (Agents.md).

Sketch: `overviews/01-recordings-list.md` + `overviews/03-list-query-syntax-sketch.md`.

### Redesign note (same day)

User rejected freeform post-query map / digging into linked `Segment` types.
Want projection **in the query** (SQLiteData `.select { Row.Columns }` prior
art), type-safe include child `.select` so parent select slots are fragments not
full entities. View must not truncate. See overview 03 **v2**.


### Follow-ups spawned

- Q28 — exact include/limit syntax vs Instant TS capabilities (implementation)


---

## Q21 — Visuals in ADR interview turns

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Always show ASCII for screen/flow overviews.
- **Question:** Require ASCII in interview questions?

### Answer

Yes. “Show the ASCII as well of things in these questions. Visuals are worth a thousand words.” Skill `$adr-decision-qanda` updated.

---

## Q22 — Screens directory when ADR finalized

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** On ADR accept, materialize a `screens/` tree for every designed feature screen.
- **Question:** Where do finalized screen designs live?

### Answer

Once ADRs are finalized, there should be a **screens directory** with all the
different screens for all the different features that have these designs.
Process skill and ADR README updated.

---

## Q23 — Instant client / device local id for activity ADT

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Port Instant TS client/device local identity into Instant Swift Data if missing; activity `active(device:)` uses that id (this device vs other = compare to local client id). List “other device” can show which device when known.
- **Question:** Use Instant’s local/client id as the stable “which device is recording” handle?

### Answer

**Yes.** Instant **client id** is the right identity for activity (not user id,
not a free-form device name). Port/expose TS client id / local id patterns in
Swift if incomplete.

```text
RecordingActivity
  ├── active(clientId:)
  ├── playback(clientId:)
  └── (absent)  // idle: no badge, no preview

this phone localClientId = A
Mac        localClientId = B
recording.activity = active(clientId: B)
  → phone list: ACTIVE · other
  → Mac list:   ACTIVE · this device → open / continue recording
```

### Follow-ups spawned

- Q19 can fold into implementation of client id + activity field (still open for lease/write rules if needed)

---

---

## Q24 — Generate full transcript on demand (no stored transcriptText)

- **Status:** decided (product rule); implementation deferred
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Never store full joined transcription text; export/generate by format when needed.
- **Question:** Store full transcript text for convenience?

### Answer

No. Store transcription **segments** with **words JSON** only. Generate full
transcript (SRT, DTT, Markdown, JSON, …) when the user asks — like existing
copy-format flows.

---

## Q25 — Chat separator after edits before next question

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Big bold ASCII separator in chat between “edits done” and “next question.”
- **Question:** How should the user find where to start reading again?

### Answer

Add to ADR process: big bold ASCII art separator in chat when done editing
docs/skills and when starting the next question, so the user does not scroll
blindly through edit chatter to re-ground.

## Q28 — Nested limit-per-parent include implementation

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Implement library support for list-safe nested segment limit + public map helpers; verify against Instant TS capabilities; soak-test thrash.
- **Question:** Ship nested `.include(segments, query.limit(2))` (or equivalent) as library work for #155? First milestone before deleting ScribeInstantStore?

### Answer

**Yes.** First library milestone: nested limit-per-parent include + request-time
**map** to flat list row. Then tear down ScribeInstantStore / planners (Q17).

Also expand milestone family to include SQLiteData-parity **aggregations /
grouping / sectioning** ergonomics (Q30) — not only flat arrays — informed by
Point-Free research (`/Users/laptop/Sync/tca/pointfree-research`, ep328 advanced
aggregations, ep374 sectioning, Reminders `group`+`count`+`@Selection`).

Should Instant grow a `@Selection` / `Columns`-like projection helper? **Yes,
goal** — app-defined row types with generated builders (like SQLiteData), not
hand-zip forever.

Why nested limit is hard today: include plan strips/forbids nested pagination
(not an Instant product rule against 2 segments — incomplete implementation).

Any reason NOT first? Only sequencing caveats (see chat): design TS vs local
bound materialize; activity client-id can parallel; do not block documenting
deletion plan while shipping this.


## Q29 — List query select/include API (v2 sketch)

- **Status:** decided
- **Decided:** 2026-08-06
- **Asked:** 2026-08-06
- **Recommendation:** SQLiteData-shaped parent `.select` into `RecordingListRow`; child include ends in `.select` to a fragment type so parent never digs into `Segment`; truncation in query projection not view.
- **Question:** Accept overview 03 v2 syntax direction?

### Answer

**Yes — matches mental model.** Product goal accepted:

- Nested limit **2 segments per recording** on include (library must grow; forbidden today).
- Request-time **map** (user prefers name "map" over "project") to flat `RecordingListRow` with **two preview lines**; empty segments → safe empty/default preview.
- View only paints list rows; no Segment type in the view.
- SQLiteData join+select is the prior art; Instant field-select/include today is incomplete for this.

Naming: prefer **map** for the fetch-time transform (see chat motivation for "project").

### Clarification for user (v3)

User could not tell invented names from real Instant APIs. Overview 03 rewritten:
real Instant (field select, include without nested limit, FetchRequest transform)
vs real SQLiteData (join + Columns select) vs goal sketch. Nested
`include(..., limit(2))` **fails today** (precondition). No official Fragment type.

## Q30 — Aggregations, grouping, sectioning (SQLiteData parity)

- **Status:** decided (in scope for #155 / ADR 0015 milestone family)
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Implement Instant ergonomics for aggregate list shapes and grouped results, not only flat `[Row]`.
- **Question:** Include aggregations/grouping in this work?

### Answer

**Yes.** Review Point-Free SQLiteData material (local research tree + episodes
328 aggregations, 374 sectioning, Reminders group/count/@Selection). Support
list shapes beyond a simple array (e.g. counts on list rows, ordered dictionary
/ sections for grouped UI) via query + map — same family as nested limit + map.
Document in ADR findings and implement as part of this library milestone, not a
forever-later nice-to-have.

### Prior art pointers

- `/Users/laptop/Sync/tca/pointfree-research` (html/extracted episodes)
- ep328 Modern Persistence: Advanced Aggregations
- ep374 WWDC26 SQLiteData sectioning (group via multi-query transform → any
  structure, e.g. ordered dict of sections)
- SQLiteData RemindersLists: `.group(by:)` + `$1.id.count()` + `@Selection`
- Instant vendored: `upstream/sqlite-data`

