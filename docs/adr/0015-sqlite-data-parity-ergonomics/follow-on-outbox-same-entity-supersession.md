# Recipe: same-entity outbox supersession (high-churn segments)

**Status:** Active recipe — pure policy + tests landed; full outbox enqueue
integration is intentional follow-on (see Remaining work).  
**Plan / issue:** ADR 0015 / Instant issue
[#155](https://issues.knophy.com/issues/155)  
**Parent write shape:** [`open-segment-write-recipe.md`](./open-segment-write-recipe.md)  
**Compile-checked policy:**
`Sources/InstantSwiftDataCore/OutboxSameEntitySupersession.swift`  
**Tests:**
`Tests/InstantSwiftDataCoreTests/OutboxSameEntitySupersessionTests.swift`

---

## Problem

Live open-segment speech issues many updates to the **same** segment entity ID
(10→× human write rates on `wordsJSON` / `text` / `updatedAtMs`).

Each `await client.transact` / `runtime.transact` means:

1. Local materialize the latest row fields.
2. Append a **new durable pending outbox mutation** (write contract: never
   server ack inside save).

Without supersession, the durable SQLite outbox can queue **dozens to hundreds
of pending upserts for one entity**. That raises:

- Head-of-line (HOL) delivery cost — every superseded intent still encodes and
  sends.
- Memory / disk thrash (full op graphs + rollback metadata per pending row).
- Misleading “pending count” diagnostics during intentional high-churn speech.
- Longer reconnect drain after offline speech sessions.

Local row correctness is already fine (each materialize overwrites the prior
local triples). The waste is **duplicate pending delivery of superseded intent**.

```text
token 1  → local seg-1 v1  + outbox [tx1]
token 2  → local seg-1 v2  + outbox [tx1, tx2]
token 3  → local seg-1 v3  + outbox [tx1, tx2, tx3]
  …
token N  → local seg-1 vN  + outbox [tx1…txN]   // local correct; outbox fat
```

Desired:

```text
token N  → local seg-1 vN  + outbox [txN]       // one pending upsert for that entity
```

---

## Desired policy

When a **new** pending outbox mutation **fully replaces** a prior **pending**
mutation for the same entity primary key and operation kind, **drop (or mark
superseded)** the older entry so only the **latest local intent** remains to
deliver.

| Term | Meaning |
| --- | --- |
| Entity primary key | `(namespace, entityID)` — e.g. `(recipe_transcription_segments, seg-1)` |
| Operation kind | Closed set: `upsert` / `delete` / `link` / `media` / `other` |
| Fully replaces | Newer entry’s entity key **set** equals the older’s (v1: singleton key, pure upsert) and both are supersedable upserts |
| Latest intent | Highest `payloadRevisionMs` (e.g. segment `updatedAtMs`), then `createdAtMs`, then stable `transactionID` |

**Write contract unchanged:** `transact` / `save` still means local materialize
+ durable outbox only. Supersession only trims **redundant pending delivery
work** after the new mutation is accepted into the outbox snapshot. Offline
must still succeed. Server ack is still observe/wait, not part of save.

### Exact algorithm (pure)

Input: ordered or unordered sequence of outbox candidates (policy re-sorts).  
Output: `kept` vs `superseded` transaction IDs.

```text
entries E  (each: id, status, entityKeys, opKind, createdAtMs,
            payloadRevisionMs?, flags…)

1. Sort E by (payloadRevisionMs ?? createdAtMs) asc,
             then createdAtMs asc,
             then id asc
   // later intent wins

2. kept = []; superseded = []

3. Group candidates that are *eligible*:
     status == pending
     && !isPermissionPoison
     && !isFailedTerminal   // status already pending; fail/confirm excluded
     && opKind == upsert
     && entityKeys.count == 1   // v1 singleton full-replace only
     && !flags.media
     && !flags.inFlightToServer // optional: skip already-sent (see below)

4. For each eligible group key K = (namespace, entityID, opKind):
     let group = eligible filtered to K, in sort order
     if group.count >= 2:
       superseded += all but last
       kept      += last
     else:
       kept += group

5. kept += every non-eligible entry (failed, confirmed, delete, link,
   media, multi-entity batch, poison, in-flight, unrelated)

6. Return { keptIDs, supersededIDs }  // partition of input ids
```

ASCII flow (enqueue-time view):

```text
new pending upsert U for (ns, id)
        │
        ▼
persist local materialize + U in outbox snapshot
        │
        ▼
scan other pending entries P where
  P.eligible && same (ns, id) && same opKind(upsert)
  && entityKeys(P) == entityKeys(U) == { (ns,id) }
        │
        ├── none → deliver queue unchanged (plus U)
        │
        └── some older P → mark/drop P as superseded
                          keep U (and any non-eligible peers)
        │
        ▼
durable outbox: pending upsert count for (ns,id) ≤ 1
delivery still completes for survivor U
```

### In-flight nuance

If a mutation has already been **sent** to the server and is awaiting
`transact-ok` / transport ack (`inFlightToServer`), v1 **does not supersede it**
by default. Dropping a sent mutation can race with server apply and confuse
client deferred waiters. Prefer:

- Supersede only **not-yet-sent** pending rows, **or**
- Supersede in-flight only with an explicit library flag and tests that prove
  cancel/replace semantics match product needs.

Document any future change next to this recipe and the policy tests.

---

## What is NOT superseded

| Case | Why |
| --- | --- |
| `status == failed` (terminal) | Must stay visible; discard is a user/agent action (`discardFailed`) |
| Permission poison (`permissionRejected` / perms-pass fail) | Fail loud; never silently drop the evidence row |
| `status == confirmed` | Already accepted / pruned path — not pending work |
| Different `opKind` (e.g. upsert vs delete) | Delete after upsert is not a replace; causal ops must both deliver or compose |
| Link / unlink batches | Cardinality and peer refs; not a full row replace |
| Media transfer mutations | Independent isolation; never coalesce with entity upserts |
| Unrelated entities | Different `(namespace, entityID)` |
| Multi-entity batches (v1) | e.g. ensure-recording + segment in one tx — not a singleton full-replace; keep both until a later policy extends to exact multi-key set match |
| Different op kinds in same entity stream | Only upsert supersedes upsert |
| App-side rate limiting as a substitute | Apps still write every interim; library owns coalesce |

---

## Entry criteria / non-goals

### Entry criteria (this recipe is active when)

1. Open-segment write recipe documented and used on the speech path  
   ([`open-segment-write-recipe.md`](./open-segment-write-recipe.md)).
2. Words as strict Codable JSON on the segment (no silent `try?`).
3. Pure policy + unit tests green (offline, no network).
4. Completeness lanes remain green under moderate soak after full enqueue
   integration (not required for pure policy land).

### Non-goals

- Deleting failed terminal mutations without visibility.
- Silencing permission-denied poison.
- App-side rate limiting or “skip outbox for interim” (forbidden by Q01 / ADR
  0014).
- Full attribute-level merge of partial patches (v1 is **whole upsert replace**
  for the same singleton entity key).
- Changing the write contract so `transact` waits for server ack.
- Required for façade delete (`ScribeInstantStore`) — helpful for speech
  performance under load, **not** a gate on façade peel.

---

## How apps observe correctness

| Check | Expected |
| --- | --- |
| Local row for open segment | Always latest fields after each `transact` (materialize independent of supersession) |
| Outbox pending count for that entity | ≤ **1** pending **upsert** of that op kind for `(namespace, entityID)` after policy runs |
| Other entities / deletes / media | Unchanged counts |
| Delivery | Survivor mutation still delivers; peers observe final segment state via normal query/observe |
| Offline speech | Many local upserts succeed; after reconnect, drain does not send every intermediate wordsJSON |
| Diagnostics | Supersede events may log `outbox.mutation.superseded` with old/new transaction IDs (integration) |

CLI / agent checks (integration, not pure policy):

```text
outbox inspect → pending upserts grouped by entity ≤ 1 for open segment
observe segment → text/wordsJSON match last speech token
```

---

## Upstream TypeScript vs Swift durable outbox

**Cite before inventing policy:**

- `upstream/instant/client/packages/core/src/Reactor.js`
  - `pushTx` / `pushOps` — each transact gets a new `eventId` and is **appended**
    to `pendingMutations` (Map). No same-entity drop of older pending ops.
  - `_rewriteMutations` / `rewriteTxSteps` — rewrites **attr ids** and drops
    attr-schema steps already covered by `processedTxId`; **not** same-entity
    upsert coalescing.
  - Pending cleanup after confirm / processed-tx watermark (`pendingTxCleanupTimeout`).
- Related Swift notes: ADR 0010 (reconnect preserves older scalar while a
  queued successor exists; delivery order preserves causal transition).
  Supersession **removes** the need to send the older successor once a full
  replace is pending — deliberate for high-churn upserts.

### Deliberate divergences (document and keep)

| Topic | TypeScript Reactor | Swift Instant (this recipe) |
| --- | --- | --- |
| Pending store | In-memory Map (+ kv) | **Durable SQLite outbox** — cost of N pending rows is disk + HOL |
| Attr rewrite | `_rewriteMutations` for schema/attr-id churn | Keep; orthogonal to entity supersession |
| Same-entity upsert pile | Allowed; all pending send | **Coalesce eligible pending upserts** to latest intent |
| Write API | `pushTx` resolves on server path / timeout | `transact` = local + outbox only (never server ack) |
| Failed / poison | Error path on mutation | Terminal failed stays until discard; poison not supersedable |

Do **not** port a novel partial-attribute “diff planner” from the app. Policy is
**library outbox**, full upsert replace for same key, pure and testable.

---

## Implementation map

| Layer | Path | State |
| --- | --- | --- |
| Recipe (this doc) | `docs/adr/0015-…/follow-on-outbox-same-entity-supersession.md` | Active |
| Pure policy | `Sources/InstantSwiftDataCore/OutboxSameEntitySupersession.swift` | Landed |
| Unit tests | `Tests/InstantSwiftDataCoreTests/OutboxSameEntitySupersessionTests.swift` | Landed |
| Enqueue hook | `InstantRuntime` after building `outboxSnapshot` with new pending | `// TODO recipe entry` — do not break delivery tests |
| Open-segment parent | `open-segment-write-recipe.md` + `OpenSegmentWriteRecipe.swift` | Links here |
| Skill | `skills/instant-data/SKILL.md` live speech section | Cross-link |

### Remaining work (full outbox integration)

1. At durable enqueue (after local prepare succeeds), map `PendingMutation` →
   `OutboxSupersessionCandidate` (entity keys from ops, op kind, flags).
2. Run `OutboxSameEntitySupersession.decide(entries:)`.
3. Persist outbox **without** superseded rows (or with status/tombstone that
   flush skips); keep creation order of survivors.
4. Log supersessions; ensure `observeTransaction` for superseded IDs resolves
   clearly (superseded-by / dropped-as-redundant — product decision, default:
   treat as locally satisfied by successor materialize).
5. Expand integration tests: 50 open-segment upserts offline → pending count 1;
   delivery of survivor; failed/poison neighbors untouched.
6. Soak: speech-shaped 20s write bench pending depth and HOL time.

---

## Verification (pure policy)

```bash
cd /Users/laptop/Sync/instant-data-swift
swift test --filter OutboxSameEntitySupersession
```

Expected: high-churn sequences of 10–100 same-entity upserts keep **one**
survivor; failed, poison, delete, media, multi-entity, and unrelated keys are
never dropped.

---

## Related

- ADR 0015 overview 02 (active transcription), overview 10 (façade inventory)
- ADR 0014 (always outbox for open-segment interim)
- ADR 0010 (wait / reconnect / successor filtering)
- Instant issue #155, performance soaks
- `OpenSegmentWriteRecipe` (speech write shape; supersession is library follow-on)
