# Handoff: Live sync, offline persistence (TS vs Swift), Scribe Jetsam, recipes 5 GB

**Date:** 2026-08-05 (America/New_York)  
**Repos:** instant-data-swift + realtime-voice-sqlite-instant (Scribe)  
**Audience:** next agent taking ownership  
**Status:** open — thrash fix + instrumentation landed; receive-loop / apply resilience **not** fixed; user wants this to work with less churn  

---

## 1. What the user needs (motivation)

1. **Scribe iPad continuously dying during recording** (Jetsam / multi‑GB memory).
2. **Clarity** whether Instant TypeScript “does the same thing” as Swift (live receive-loop kill on bad apply).
3. **How offline works** if TS keeps server updates in memory — and how that maps to Swift SQLite.
4. **Less churn** — a single handoff so the next agent can act without re-deriving the whole story.
5. **recipes-v3** showed the same library class of pain (idle multi‑GB, then live apply errors) and got a debug panel so failures are visible.

User quote (paraphrased): *I just need this to work. Document findings for a handoff.*

---

## 2. Mental model: Instant is *not* “one SQLite row store” in TypeScript

### 2.1 TypeScript Instant (upstream Reactor)

Canonical sources (vendored checkout):

- `upstream/instant/client/packages/core/src/Reactor.js`
- `upstream/instant/client/packages/core/src/store.ts`
- `upstream/instant/client/packages/core/src/IndexedDBStorage.ts`

**Hot path (live, in-memory):**

| Concern | TS behavior |
|--------|-------------|
| Query results | **In-memory** triple stores **per subscribed query** (`createStore` from triples on `add-query-ok` / `refresh-ok`) |
| Server pushes | Mostly **`refresh-ok`**: server sends recomputed query results as triples; client **rebuilds** that query’s store, then re-applies optimistic mutations (`_applyOptimisticUpdates` → `s.transact`) |
| Client writes | Optimistic `tx-steps` in a **pending mutations** map; WS `transact`; server confirms with `transact-ok` |
| Socket life | `onclose` → `_scheduleReconnect` (backoff / optional SSE). Transport death ≠ “SQLite apply failed” |

**Offline / restart path (persisted):**

TS does **persist**, but **not** by replaying every server mutation into one SQLite DB:

| Persisted object | Storage | Role |
|------------------|---------|------|
| `pendingMutations` | IndexedDB `kv` store (via `PersistedObject`) | Unacked **client** mutations survive reload; flushed when online |
| `querySubs` | IndexedDB `querySubs` store | Last known **query result snapshots** (stores/triples/page-info/processed-tx-id) so UI can hydrate offline |
| Other kv | IndexedDB `kv` | e.g. current user |

So offline works as:

1. **Last good query snapshots** reload from IndexedDB → app can render without network.  
2. **Pending client mutations** reload and re-send when the socket is up.  
3. Live server truth is re-established via **refresh/re-query**, not by applying a long chain of server mutation logs into SQLite on the client.

There is **no** Instant TS API equivalent to “apply server mutation `773e50f4…` into durable storage or kill the receive loop.”

### 2.2 Swift Instant (this library)

| Concern | Swift behavior |
|--------|----------------|
| Facts | **One local SQLite** triple store (plus outbox, live query metadata, etc.) |
| Server updates | **`applyServerTransaction`** (and live refresh paths that still end in durable apply) |
| Client writes | Optimistic outbox + SQLite |
| Live failure | If **apply** throws → `handleLiveSessionFailure` → diagnostic **`connection.receive-loop-failed`** with `persistenceFailed` / `apply server transaction` |

Motivation for SQLite in Swift (product): Scribe is always-on voice, offline-first, multi-device, agent-diagnosable from disk; a single durable store is the intentional adaptation of Instant’s *ideas* to Apple offline. Documented across `docs/instantdb-swift-data-plan.md`, ADRs 0001/0009/0011, etc.

**Important:** This is an **adaptation**, not byte-for-byte Reactor parity. Churn comes from treating “TS online refresh” and “Swift SQLite apply” as the same step.

---

## 3. Answer: “If TS keeps mutations in memory, how is offline persisted?”

- **Server mutations** are **not** primarily offline-persisted as a mutation log on the client in TS.  
- Offline durability is: **(a)** last **query result** snapshots in IndexedDB, **(b)** **client pending mutations** in IndexedDB, **(c)** re-sync when online.  
- **Swift** persists **both** optimistic client work **and** applied server facts into **SQLite**. That is why a bad server apply is a first-class failure mode in Swift and almost invisible in the same form in TS.

**Mental picture:**

```text
TypeScript Instant
  online:  WS → rebuild in-memory query stores from refresh-ok
  offline: IndexedDB querySubs + pendingMutations
  online again: flush pendingMutations + re-subscribe / refresh

Swift Instant
  online:  WS → apply into SQLite (+ notify observers)
  offline: SQLite is already the truth surface
  online again: outbox flush + live apply of server txs into SQLite
```

---

## 4. Incident chronology and evidence

### 4.1 Scribe iPad Jetsam during recording

- **Symptom:** Continuous crashes during recording.  
- **Lane:** Tailnet WebSocket → `~/Library/Logs/Scribe/diagnostics.jsonl` (dual-write with Instant debugLogs; app lane was trustworthy).  
- **Evidence:** Physical footprint **~50 MB → 3–4.7 GB** in ~60s, then silence.  
- **Correlated:** After pin to **instant-data-swift 1.5.0**, short lists had `canLoadNextPage=true` with only **7–8** rows (page size 50). Storm of `recording.query.list.next-page.requested`.  
- **1.4.0 builds:** short lists correctly `canLoadNextPage=false`.

**Root cause (paging thrash):**

1. **Library 1.5.0:** pre-kickstart infinite query trusted remote `hasNextPage` without liveTuple kickstart; short pages stayed open forever.  
2. **App amplifier:** Recording list “Load older” `.onAppear` + ProgressView swap re-fired `loadNextPage` forever.

**Fixes landed:**

| Repo | Version / commit | What |
|------|------------------|------|
| instant-data-swift | **v1.5.1** (`cdd1ba42` / tag `43e3385c`) | Pre-kickstart: local fullness only; closed window no-op expand; regression test |
| realtime-voice-sqlite-instant | `39722d4` | Pin 1.5.1; short-page client close; remove onAppear thrash; constellation gate |

**Secondary (older sessions):** media-retry scan thrash (already capped earlier: 15s min, delivery caps). Not the primary 2026-08-05 session.

### 4.2 Instrumentation (so we can answer “auth / junk / remote hasNext”)

| Repo | Version / commit | What |
|------|------------------|------|
| instant-data-swift | **v1.5.2** (`adeea919`) | `infinite.*` InstantDiagnostics: subscribe, starter, expand, kickstart, loadNext no-ops, remote page-info decode; auth/owner fingerprints |
| realtime-voice-sqlite-instant | `5f0c984` | `InstantDiagnostics.addHandler` → InstantDBLogger dual-write (Tailnet file when reachable); list `ownerFingerprintsSample` |

**Filter on Mac:**

```bash
jq -c 'select((.entry.category // .category // "") | startswith("instant-library"))' \
  ~/Library/Logs/Scribe/diagnostics.jsonl | tail -50
```

### 4.3 recipes-v3 idle multi‑GB + live apply error

- **Process:** `recipes-v3 --recipe linked-infinite` idle at **~5.11 GB** (Activity Monitor), PID 89530.  
- **Relaunch after panel:** PID 54290, **~63–120 MB** footprint/RSS — healthy *for that session*.  
- **Debug panel** (`1a7303ac`): Scribe-style floating panel — memory, peak, threads, sparkline, scrollable logs (InstantDiagnostics + Linked Infinite durable log), Copy all, Reveal logs. Default **expanded**.  
- **Panel showed:**  
  - `websocket.session-opened`  
  - then **`connection.receive-loop-failed`** / `persistenceFailed` / `apply server transaction: Mutation '773e50f4-…'`  
- **Also noisy:** `probe.full-namespace.failed` every snapshot (recipe diagnostic; 10s transport timeout after loop is dead) — **not** Instant TS core.

Durable log path: `/tmp/linked-infinite-debug.jsonl`  
Recipes Instant diagnostics path (when configured): `/tmp/recipes-instant-swift-data.jsonl` or temp dir under app.

---

## 5. Upstream triage: “Does Instant TypeScript support this behavior?”

### 5.1 Behavior in question

Swift:

```text
applyServerTransaction fails
  → handleLiveSessionFailure
  → connection.receive-loop-failed
  → live session effectively broken until reconnect/recovery
```

### 5.2 Verdict

| Question | Answer |
|----------|--------|
| Does Instant TS kill the receive loop because a **durable apply** failed? | **No** — that path doesn’t exist in the same form. |
| Does Instant TS support live sync + reconnect? | **Yes** (in-memory refresh + socket reconnect). |
| Is Swift’s kill-on-apply “parity”? | **No** — Swift-specific fail-loud coupling of SQLite apply to the receive loop. |
| Ownership of receive-loop-failed | **Library (Swift)** — fix resilience and/or root apply error; don’t “wait for Instant TS to add applyServerTransaction.” |

### 5.3 TS references (for the next agent)

- `_handleReceive` switch: `init-ok`, `add-query-ok`, `refresh-ok`, `transact-ok`, `error` — **no** SQLite apply.  
- `_transportOnClose` → `_scheduleReconnect`.  
- `_applyOptimisticUpdates` is pure in-memory `s.transact`.  
- Client `pushTx` **catches** transform errors instead of tearing down the socket.

---

## 6. Why it feels like endless churn

1. **Two storage models** called “Instant” — people assume apply/persist semantics match.  
2. **Two product surfaces** (Scribe + recipes Linked Infinite) hit **related but different** library defects (paging thrash vs apply/receive-loop).  
3. **1.5.0** fixed blank-detail optimistic protection but introduced pre-kickstart `hasNextPage` thrash.  
4. **App UI thrash** amplified library bugs (onAppear / ProgressView; constellation auto-page; Linked Infinite last-row onAppear + full-namespace probes).  
5. **Dual diagnostic lanes** (Tailnet WS vs Instant debugLogs) caused false “no logs” conclusions historically; dual-write is intentional during library development.

Motivation for handoff: stop re-deriving this every session; next agent should **own one outcome** (receive-loop resilience + identify mutation apply failure) without re-litigating Jetsam thrash (already fixed) or offline theory.

---

## 7. Current pins and artifacts

### instant-data-swift

| Tag / commit | Role |
|--------------|------|
| v1.5.0 | Blank-detail optimistic protection (empty live replacement) |
| **v1.5.1** | Infinite short-page thrash fix |
| **v1.5.2** | Infinite-query + remote page-info instrumentation |
| **1a7303ac** | recipes-v3 debug panel (memory + logs) |

### realtime-voice-sqlite-instant

| Commit | Role |
|--------|------|
| `39722d4` | Jetsam thrash app defenses + pin 1.5.1 |
| `5f0c984` | Diagnostics bridge + pin **1.5.2** + owner fingerprint inventory |

Scribe `Package.swift` should be `exact: "1.5.2"`. Local editable symlink `Packages/instant-data-swift` may override for day-to-day dev.

### Logs

- Scribe Tailnet: `~/Library/Logs/Scribe/diagnostics.jsonl`  
- Linked Infinite: `/tmp/linked-infinite-debug.jsonl`  
- Recipes InstantDiagnostics file: under temp / `recipes-instant-swift-data.jsonl` when bridge installed  

---

## 8. Open work (for the receiving agent)

### P0 — Make live sync resilient and correct (library)

**Landed 2026-08-05 (`ca483b54` / #134):** Failed pre-overlay outbox rows no longer hard-throw inside `performApplyServerTransaction`. That was the recipes-v3 `773e50f4-…` receive-loop thrash (and the remaining half of #134 after connect-path isolation). Live verify on the poisoned recipes SQLite: ~121 MB RSS, probes succeed, no `connection.receive-loop-failed` from apply. Retry/discard still refuse without guessing. Open remainder of #134: public recovery API, upgrade docs, physical iPhone in-place recovery.

Original checklist (items 1–2 done for failed+unknown; item 3 partial):


1. **Reproduce** recipes-v3 or Scribe with live app id; capture full InstantError for mutation `773e50f4…` (not truncated).  
2. **Classify apply failure:** schema drift, junk remote data, `unknownOptimisticOverlayState`, attribute rewrite, empty processed-tx-id, etc. (`InstantRuntime.performApplyServerTransaction`).  
3. **Parity-aligned resilience (recommended direction):**  
   - Do **not** kill the entire receive loop for every apply failure if isolation is possible (log, quarantine, continue — closer to TS mutation/query-level errors).  
   - Or: fix root cause so apply never fails for valid server traffic, and only fail-loud for true corruption.  
4. **Cite upstream:** Reactor `_handleReceive` / `_transportOnClose` as the resilience shape; document intentional Swift differences in an ADR if isolation is chosen.

### P1 — Reduce recipe noise

- Linked Infinite `probe.full-namespace` after every snapshot: gate, single-flight, or skip when connection not authenticated.  
- Review `last-row-onAppear` auto `loadNextPage` for thrash under stuck `canLoadNextPage` (library fix reduces this; recipe still aggressive).

### P1 — Scribe verification

- Clean install Scribe with **1.5.2** + bridge commit.  
- During recording: no next-page storm; footprint stays tens of MB; `instant-library.infinite-query` events visible on Tailnet file.  
- Confirm `ownerFingerprintsSample` shows one owner for “I only have 7 recordings.”

### P2 — Docs / user education

- This handoff is the narrative. Optional: short ADR “Swift SQLite apply vs TS querySubs + pendingMutations offline.”

### Explicit non-goals for next slice

- Do not re-pin to 1.5.0 for thrash (already fixed in 1.5.1).  
- Do not re-implement Scribe debug overlay in the library.  
- Do not invent TS “applyServerTransaction” parity for its own sake.

---

## 9. Suggested first commands for next agent

```bash
# Library
cd /Users/laptop/Sync/instant-data-swift
git log --oneline -15
git show v1.5.1 --stat | head
git show v1.5.2 --stat | head

# Reproduce recipes (credentials if present)
pgrep -x recipes-v3
# kill by basename only: pgrep -x recipes-v3 | xargs kill
swift build --product recipes-v3
.build/debug/recipes-v3 --recipe linked-infinite
# Watch panel +:
tail -f /tmp/linked-infinite-debug.jsonl

# Upstream TS (read-only)
less upstream/instant/client/packages/core/src/Reactor.js  # _handleReceive, _transportOnClose, pendingMutations

# Scribe diagnostics
python3 - ~/Library/Logs/Scribe/diagnostics.jsonl <<'PY'
# filter iPad / infinite-library / next-page as needed
PY
```

---

## 10. Glossary (for handoff continuity)

| Term | One line |
|------|----------|
| **Pre-kickstart** | Infinite query before liveTuple cursors; only local expand |
| **Local fullness** | Window size ≥ pageSize → may load more pre-kickstart |
| **Closed window** | `canLoadNextPage == false` for this phase |
| **No-op expand** | loadNextPage when already closed: republish, no heavier work |
| **querySubs (TS)** | Persisted last query result snapshots for offline UI |
| **pendingMutations (TS)** | Client outbox in IndexedDB |
| **applyServerTransaction (Swift)** | Persist a server mutation into SQLite |
| **receive-loop-failed** | Swift live loop aborted after error (often apply/persist) |
| **Jetsam** | iOS kills process for memory |

---

## 11. Success criteria for “this works”

1. Scribe recording on iPad: **no Jetsam**, no next-page storm, stable memory.  
2. Live Instant: **socket stays useful** after rare apply glitches *or* apply never fails on valid data; full error always logged.  
3. recipes Linked Infinite: panel shows **stable &lt; few hundred MB** idle; no receive-loop death on seed, or death is fixed with root cause named.  
4. Offline: Swift SQLite still source of truth offline; document offline model so agents stop re-asking “how does TS persist if it’s in memory?”

---

*End of handoff. Written for continuity; prefer this file over conversation scrollback.*
