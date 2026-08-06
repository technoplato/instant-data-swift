# Q&A — Scribe-shaped 20s write/memory parity CLI (#156)

Interview started 2026-08-06. One decision per entry.

---

## Q01 — Which process sides must the first baseline compare?

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation (superseded):** local-only fair pair + admin printed separately — **rejected by user**.
- **Question:** For the **v1 baseline CLI**, which lanes ship on day one?

### Answer

**Network-vs-network is the primary validity bar; local-vs-local is allowed only as a separate matrix; never mix local with network in one ratio.**

User corrections (verbatim gist):

- Do **not** want local-only as the main story.
- For the benchmark to be **valid**, writes must go **across the network** and be **observed by another process** (Swift or TypeScript).
- Fair axes: **local vs local**, and **network vs network**. **Never** local vs network.
- Not Scribe UI — lives in **instant-data-swift** library tooling.
- Admin Node (`@instantdb/admin`) is a real Instant app writer; Swift InstantRuntime with SQLite + outbox materialize as the app-side client.
- **RTT** explained simply below; user rejected “admin RTT makes fair ratios garbage” as a reason to drop network — they want network measured correctly, not avoided.

**V1 lanes (decided shape):**

| Matrix | Writer | Observer | Notes |
|--------|--------|----------|-------|
| **Network A** | TS `@instantdb/admin` | Swift InstantRuntime (live query/observe) | admin drives schema over network |
| **Network B** | Swift InstantRuntime `transact` (outbox → server) | TS admin **or** second Swift/TS client observe | symmetric network path |
| **Local A** (secondary) | TS core / local store | same process or second local observer | optional micro baseline only |
| **Local B** (secondary) | Swift local materialize | local observe | optional micro baseline only |

Compare only **Network A vs Network B** for “is Swift as fast/heavy as Instant over the wire?”  
Compare only **Local A vs Local B** for pure store cost.  
Never Network A vs Local B.

**Write validity rule:** a write only counts when the **observer process** has seen the update (not when the writer’s local `await` returns).

### Follow-ups spawned

- Q02 — Write profile: open-segment + words JSON (user already partially decided)
- Q03 — Exact network pairing: which writer/observer combos are required day one
- Q04 — Memory metric contract on **both** writer and observer processes
- Q05 — Disposable Instant app vs scribe-main for live lanes

---

## Glossary (user-facing)

### What is Zeneca?

**Zeneca** is InstantDB’s **stock sample dataset** that ships with the upstream TypeScript client tests: fixed `attrs.json` + a large `triples.json` graph (users, books, projects, etc.) used for their “big query” / deep-join microbench.  
It is **not** Scribe, not production data, and not our transcription schema. When docs say `LocalRead.deepJoin.zeneca` or `core.instaql.big-query.zeneca`, they mean: “run the same four-level join Instant uses in their own bench, on their toy graph, so Swift can be compared apples-to-apples with TypeScript **on that fixture**.”  
Our **#156** Scribe-shaped 20s harness is a **different** workload; Zeneca is only an existing microbench reference you may have seen in the repo.

### What is RTT?

**RTT = Round-Trip Time.**  
The wall-clock time for a message to go **to the server and back** (phone/laptop → Instant cloud → phone/laptop).  
Example: if the network takes 40 ms each way, RTT is ~80 ms — every server ack pays that tax.  
Local store writes pay **0 RTT**. That is why comparing “local writes per second” to “network writes per second” is meaningless: one is pure CPU/disk, the other includes waiting for the internet.

---

## Q02 — Write profile / schema shape

- **Status:** decided (partial; confirm remaining detail)
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Product ADR 0015 shape — **not** word entities.

### Answer (user)

- **No word entities.** Words are a **JSON blob/array on the current segment**.
- One **recording**; speech is **very fast**; the **current open segment is always the write target** (upsert segment with growing words JSON).
- Matches intended Scribe product write path (open-segment upsert, not full-document diff).

Still open for Q02 confirmation if needed: segment rotate policy during the 20s race (single segment entire run vs rotate every N words / every 1s) — default recommendation: **single open segment for whole 20s** to maximize superseding upserts on one entity id.

---

## Q03 — Required network writer/observer pairs for v1

- **Status:** decided
- **Asked:** 2026-08-06
- **Decided:** 2026-08-06
- **Recommendation:** Both directions.

### Answer

User: **“Uh just do both. Go ahead and get started.”**

Ship Net-A and Net-B:

1. **Net-A:** TS `@instantdb/admin` writer → Swift InstantRuntime observer  
2. **Net-B:** Swift InstantRuntime writer → TS admin query observer  

Both ~20s; valid write = observer saw monotonic `seq` advance; memory/CPU on both processes; network-vs-network compare only.

### Implementation entrypoints

- `validation/run-scribe-shaped-20s-write-bench.sh`
- `validation/ts-runner/src/scribe-shaped-20s-write-bench.ts`
- `Sources/InstantSwiftDataCore/ScribeOpenSegmentNetworkBench.swift`
- executable product `scribe-shaped-20s-write-bench`
