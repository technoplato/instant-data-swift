# Open-segment write recipe

**Status:** library-owned recipe (ADR 0015 / Instant issue [#155](https://issues.knophy.com/issues/155))  
**Plan step:** S2 write path + overview 10 “open-segment write recipe”  
**Related:** overview `02-active-transcription.md`, ADR 0014 (always outbox; sync status on fetch), Q01/Q07/Q26 in `qanda.md`  
**Compile-checked example:** `Sources/InstantSwiftDataCore/OpenSegmentWriteRecipe.swift`  
**Typed entity sketch:** `Sources/InstantSwiftData/OpenSegmentWriteRecipeEntities.swift`  
**Codable JSON (SQLiteData-shaped):** `Sources/InstantSwiftData/InstantCodableJSON.swift`  
(`Type.JSONRepresentation` / `Type.JSONStringRepresentation`, loud encode/decode)

---

## When to use

Use this recipe for **live speech and other high-churn segment rewrites**:

- One recording is open.
- Speech tokens arrive often (many updates per second).
- Only the **current open transcription segment** changes.
- Peers (other devices / list preview) should see interim text via Instant outbox + observe.

Do **not** use full-document previous/current `Recording` diffs, multi-segment sweeps, or an app Instant “store” façade for this path.

---

## Write contract (memorize)

| API | Means | Does not mean |
| --- | --- | --- |
| `await client.transact { … }` / `runtime.transact(operations:)` | Local materialize + **durable outbox** finished | Server ack |
| Offline | Must succeed | Network required |
| `transactionID` on the mutation result | Handle for observe / CLI wait | “Write failed if server is slow” |
| Server wait | Explicit `observeTransaction` / entity sync status (L4) / CLI wait helpers | Nested inside save |

Five seconds is the timeout for any bounded wait. Long “just in case” timeouts hide stalls.

---

## Exact steps

```text
speech token arrives
       │
       ▼
1. Know recordingID, recordingSegmentID (or allocate once), ownerUserID
       │
       ▼
2. Ensure recording row exists (once per recording session)
   · title / startedAtMs / ownerUserID + owner link
   · optional summary fields (duration, activity) only when they change
       │
       ▼
3. Create/link THAT segment once (durable relation barrier)
   · recordingID + recording ref
   · ownerUserID + owner ref when permissions require it
       │
       ▼
4. For every later interim, assign the same complete scalar field set only
   · text
   · wordsJSON = strict Codable [Word] as UTF-8 JSON string
   · times / segmentIndex / isFinal
   · recordingID / ownerUserID scalar identities
   · updatedAtMs (monotonic wall clock for this write)
   · primary key is included by the typed update; no refs or partial patches
       │
       ▼
5. await client.transact { mutations }   // local + outbox only
       │
       ▼
section final from speech?
  yes → same id, isFinal=true; clear recordingSegmentID
        next speech → new segment id
  no  → keep same id; next token rewrites the same row
```

### Pure field snapshot (app domain → Instant fields)

The app tracks **which** segment is open (`recordingSegmentID`) and the speech
domain (words, times, finalize). Instant only receives **row fields** for that
segment (plus ensure-recording once). No previous full graph.

```swift
// Conceptual — see OpenSegmentWriteRecipe / OpenSegmentWriteRecipeEntities
struct OpenSegmentFields {
  var recordingID: String
  var segmentID: String          // recordingSegmentID
  var ownerUserID: String
  var segmentIndex: Int
  var text: String
  var words: [OpenSegmentWord]   // encoded strictly to wordsJSON
  var isFinal: Bool
  var startTimeSeconds: Double
  var endTimeSeconds: Double
  var updatedAtMs: Double
  var title: String?             // only when ensuring / updating recording
}
```

### Core (triple) shape — offline unit-testable

```swift
let wordsJSON = try OpenSegmentWriteRecipe.encodeWordsJSON(words)
// Initial create/link only. This relation-bearing transaction is an ordered
// outbox barrier and is not supersession eligible.
let ops =
  OpenSegmentWriteRecipe.ensureRecordingOperations(
    recordingID: recordingID,
    title: title,
    ownerUserID: ownerUserID,
    updatedAtMs: nowMs,
    transactionID: txID
  )
  + OpenSegmentWriteRecipe.openSegmentUpsertOperations(
    segmentID: segmentID,
    recordingID: recordingID,
    ownerUserID: ownerUserID,
    text: text,
    wordsJSON: wordsJSON,
    wordCount: words.count,
    segmentIndex: segmentIndex,
    isFinal: false,
    startTimeSeconds: start,
    endTimeSeconds: end,
    updatedAtMs: nowMs,
    transactionID: txID
  )
_ = try await runtime.transact(operations: ops, source: "speech.open-segment")
// returns when local + outbox are durable — not when the server acks
```

`openSegmentUpsertOperations` and `operations(for:)` remain compatibility
builders for that initial relation-bearing write. They always include the
segment’s recording ref (even with `linkOwnerRef: false`), so do **not** call
them on every token while expecting supersession. Subsequent interims use the
app’s typed scalar-only mutation shown below.

### App-facing typed shape (InstantEntityModel)

Product apps declare schema entities (short names preferred: `InstantRecording`,
`InstantSegment`) and upsert with ordinary `update` / `create` mutations:

```swift
let wordsJSON = try OpenSegmentWriteRecipe.encodeWordsJSON(words)

// Once per recording/segment: establish relations. This transaction is a
// durable ordering barrier, not a supersession candidate.
try await client.transact(
  InstantMutationBatch([
    InstantRecording.update(
      id: recordingID,
      InstantRecording.title.set(title),
      InstantRecording.ownerUserID.set(ownerUserID),
      InstantRecording.owner.set(ownerID),
      InstantRecording.updatedAtMs.set(nowMs)
    ),
    InstantSegment.update(
      id: segmentID,
      InstantSegment.recording.set(recordingID),
      InstantSegment.ownerUserID.set(ownerUserID),
      InstantSegment.owner.set(ownerID),
      InstantSegment.text.set(text),
      InstantSegment.wordsJSON.set(wordsJSON),
      InstantSegment.wordCount.set(Double(words.count)),
      InstantSegment.segmentIndex.set(Double(segmentIndex)),
      InstantSegment.isFinal.set(false),
      InstantSegment.updatedAtMs.set(nowMs)
    ),
  ])
)

// Every later interim: one segment, complete scalar assignment, exact same
// attribute set, no refs. Typed update includes the segment primary key.
try await client.transact(
  InstantSegment.update(
    id: segmentID,
    InstantSegment.recordingID.set(recordingID),
    InstantSegment.ownerUserID.set(ownerUserID),
    InstantSegment.text.set(text),
    InstantSegment.wordsJSON.set(wordsJSON),
    InstantSegment.wordCount.set(Double(words.count)),
    InstantSegment.segmentIndex.set(Double(segmentIndex)),
    InstantSegment.isFinal.set(false),
    InstantSegment.startTimeSeconds.set(start),
    InstantSegment.endTimeSeconds.set(end),
    InstantSegment.updatedAtMs.set(nowMs)
  )
)
```

Library recipe entities in
`OpenSegmentWriteRecipeEntities.swift` mirror this pattern under recipe
namespaces (`recipe_recordings` / `recipe_transcription_segments`) so the
spelling is compile-checked without coupling the library to Scribe schema.

---

## Ownership + Instant permissions

Instant permissions for user-owned rows typically require **both**:

1. A scalar **`ownerUserID`** (string user id) for filters / indexes, and  
2. An **`owner` ref link** to `$users` (or your user namespace) so rule graphs
   can walk ownership.

Write both on the relation-bearing create and keep the scalar owner identity in
every later interim assignment. The established refs remain on the entity; do
not resend them in the scalar hot loop merely to restate unchanged ownership.
Missing owner fields often surface as **silent server denial** on outbox
delivery — fail loud in dev; never swallow encode/permission errors with
`try?`.

Guest / unauthenticated speech still needs a stable owner identity your perms
accept (guest user id from auth session). Do not invent a second “local-only”
write path that skips outbox.

---

## Words as strict Codable JSON on the segment

- Wire field: **`wordsJSON`** (Instant string or json attribute).
- App type: `Codable` array of `{ start, end, text }` (and only those fields
  you intentionally version).
- **Encode and decode throw** (or surface `InstantError.decodeFailed`) — never
  silent `try?` that drops words.
- Prefer Instant’s SQLiteData-shaped API (mirrors structured-queries
  `Type.JSONRepresentation`):
  - `[OpenSegmentWord].JSONRepresentation` → Instant `.json`
  - `[OpenSegmentWord].JSONStringRepresentation` → JSON text in `.string`
    (Scribe schema today)
  - `attribute.setJSON(words)` / `setJSONString(words)`
  - `snapshot.codableJSON` / `codableJSONString` on read
- Shared `InstantCodableJSON.encoder` uses **sorted keys** (stable wire); date
  strategy matches structured-queries ISO-8601 strings. Encode/decode failures
  throw `InstantError` (stricter than SQLiteData’s bind-time `.invalid`).
- Words are **not** Instant word entities on the live path (no per-word outbox
  thrash). Export / “full transcript” is generated on demand from segments +
  wordsJSON (SRT, Markdown, JSON, …) — **do not store joined full transcript
  text** on the recording or list row.

```swift
public struct OpenSegmentWord: Codable, Equatable, Sendable {
  public var start: Double
  public var end: Double
  public var text: String
}

// Library helper — throws on encode/decode failure
let json = try OpenSegmentWriteRecipe.encodeWordsJSON(words)
let again = try OpenSegmentWriteRecipe.decodeWordsJSON(json)

// Or attribute-path spelling (Scribe string column):
// static let wordsJSON =
//   InstantAttributePath<Self, [OpenSegmentWord].JSONStringRepresentation>("wordsJSON")
// try Segment.update(id: id, Segment.wordsJSON.setJSONString(words))
```

---

## Observation

Observe what you write — **bounded**:

```text
Active transcript UI
  @FetchAll / subscribe
    segments where recording == currentRecordingID
    order by segmentIndex / start
    (no unbounded whole-library segment dump)

List preview
  recording include segments limit 2 (nested limit — L1)
  map/truncate to UI lines — not full timelines
```

Sync status (pending / confirmed / rejected) is a **library projection on
fetch** when L4 / ADR 0014 lands. Domain `isFinal` stays on the segment model
and is orthogonal to sync status.

---

## Non-goals (explicit)

| Non-goal | Why |
| --- | --- |
| Full-document previous/current `Recording` diffs | Anti-pattern; invents mutations from dual graphs |
| `waitUntilDelivered` / server ack inside save | Breaks offline; hides delivery as “await save” |
| App `ScribeInstantStore` / snapshot client as Instant door | Façade; bootstrap + feature `transact` / `@Fetch*` instead |
| Per-word Instant entities on live path | Outbox and memory thrash; use wordsJSON |
| Stored joined `transcriptionText` | Generate formats on demand |
| Skipping outbox for interim text | Peers never see live speech; Q01 locked |

---

## Follow-on: outbox same-entity supersession

High-churn open-segment upserts enqueue many pending ops for the **same entity
id**. Library **immediate-tail supersession** replaces only the one exact
never-claimed, never-offered durable tail when both mutations are complete
assignments of the same schema-known cardinality-one scalar attributes. It does
not scan or group the queue, cross an intervening barrier, merge partial patches,
or choose by `updatedAtMs` / another domain payload revision.

The one-time segment create that carries `recording` / `owner` refs is such a
barrier. Supersession begins only after the first later scalar-only assignment;
every subsequent interim must use that identical scalar attribute set. Ordinary
ref-bearing upserts never qualify.

**Full recipe (eligibility, rollback, aliases, retention, tests):**
[`follow-on-outbox-same-entity-supersession.md`](./follow-on-outbox-same-entity-supersession.md)  
**Implementation:** `InstantRuntime.performTransact`, `SQLitePersistenceStore`,
and `OutboxSameEntitySupersession.canReplaceImmediateTail`

Always outbox every interim write. The library may replace an eligible physical
tail after local materialization; apps must not invent a “skip outbox for
interim” mode. Returned transaction IDs remain observable through durable
aliases. Those aliases are append-only today, so supersession bounds full
mutation bodies and rollback graphs, **not total durable metadata bytes**.

---

## Who owns what

| Layer | Owns |
| --- | --- |
| App | `recordingSegmentID`; speech interim vs final; schema; words Codable type; export generators; when to roll a new segment |
| Library | Materialize, durable outbox, reconnect, delivery, rejection isolation; (goal) sync status on fetch; (follow-on) same-entity supersession |
| App must not | Full-document Instant planners; Instant store façades; fake process-local sync maps; silent `try?` on wordsJSON |

---

## Verification

```bash
# Unit tests (no network) — words JSON + mutation shape
cd /Users/laptop/Sync/instant-data-swift
swift test --filter OpenSegmentWriteRecipe

# Related live / network stress (optional; needs Instant credentials)
# validation/run-scribe-shaped-20s-write-bench.sh
```

---

## References

- Overview 02 active transcription write loop  
- Overview 10 façade deletion + target Instant write  
- ADR 0014 always-outbox open segments  
- Skill `$instant-data` — live speech write shape  
- Scribe product engine (domain only): `ScribeOpenSegmentCore` in the consumer app  
- Network bench shape: `ScribeOpenSegmentNetworkBench` (#156)
