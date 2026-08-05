# Production performance readiness plan — Instant Swift Data

**Date:** 2026-08-05 (America/New_York)  
**Status:** plan — research + evaluation complete; implementation not started by this document  
**Audience:** next implementing agents (library first, then Scribe)  
**Repos:** `instant-data-swift` (+ Scribe verification in `realtime-voice-sqlite-instant`)  
**Library HEAD when written:** `626a212b` (docs after **v1.5.3**)  
**Scribe pin when written:** `exact: "1.5.3"`

**Related:**

- Handoff (offline model, Jetsam thrash fixed, apply isolation partial):  
  `docs/handoffs/2026-08-05-live-sync-offline-persistence-and-scribe-jetsam-handoff.md`
- Scribe pointer:  
  `realtime-voice-sqlite-instant/handoffs/2026-08-05-instant-sync-jetsam-and-offline-model-handoff.md`
- Product budgets:  
  `realtime-voice-sqlite-instant/docs/performance-budget.md`
- Soak (thrash gate only):  
  `docs/scribe-shaped-memory-soak.md`
- Concurrency contract:  
  `docs/swift-concurrency-guidance.md`
- ADR boundary: `docs/adr/0001-application-sync-boundary.md`  
- Retention: ADR 0007–0009, optimistic empty-protect 0013

**Issues (Instant tracker, not GitHub):** #134 (apply/receive isolation remainder), #150 (soak gate), schema/perms poison as separate app defects when writing.

---

## 0. One-paragraph verdict

Instant Swift Data is **not production-ready** for always-on Scribe as of 2026-08-05.  
**v1.5.1** fixed infinite short-page Jetsam thrash; **v1.5.3** fixed *legacy failed-outbox* poison during server apply.  
On a physical iPad today, with **1.5.3** pinned, idle-ish physical footprint still climbed **~88 MB → ~880–945 MB** (and later samples **~1.3–1.4 GB**) while the library thrashed: permanent mutation rejects (`permission-denied`, missing required attributes) × **`failMutation` holding the operation gate 160+ s** × ack-timeout reclaim × receive-loop death × reconnect.  

**Causal story:** dynamic thrash on a **structurally high memory floor** (full triple indexes × 3 maps + second full snapshot cache + durable failed outbox).  
**This week:** stop thrash (error isolation + short gates + poison outbox policy).  
**Next:** absolute memory/CPU budgets that fail at 400 MB, not 1 GiB.  
**Later:** structural efficiency under ADR — never “become TypeScript in-memory” and never silent-discard failed writes.

**Evaluator scores (independent):** overall **~2.5/10** production readiness (memory ~1.5, reliability ~2, energy ~2, observability ~6.5, test confidence ~2.5).

---

## 1. Live evidence (do not re-derive)

### 1.1 Source

Tailnet dual-write lane: `~/Library/Logs/Scribe/diagnostics.jsonl`  
Device: physical iPad (`deviceName: iPad`)  
Library pin in app: **1.5.3** (Package.resolved)

### 1.2 Memory time series (physical footprint)

| Local time (EDT) | phys_footprint | resident | Notes |
|------------------|----------------|----------|--------|
| 13:09:24 | **88 MB** | 173 MB | Post-restart-ish low |
| 13:10:24 | 835 MB | 1159 MB | +747 MB in 1 min |
| 13:11–13:12 | 870–875 MB | ~1150 MB | User ~880 MB report ~13:20 |
| 13:13–13:15 | 886–946 MB | ~1100–1170 MB | Still climbing |
| 13:21–13:23 | **1313–1379 MB** | ~1335–1518 MB | New commit sample `4f4a7b37` |
| 13:24–13:25 | 931–944 MB | ~1478–1508 MB | Still far above budget |

**Product fail line:** RSS/footprint **>400 MB** (`docs/performance-budget.md`). **Target ≤250 MB** after 60 min recording.

### 1.3 Event storm (recent 8–12 MB of journal)

| Event | Count (order) | Meaning |
|-------|---------------|---------|
| `outbox.flush.head-of-line-wait` | ~550 | Flush stuck at head (step budget / poison) |
| `outbox.mutation.ack-timeout-reclaim` | ~151 | 10 s in-flight timeout → resend |
| `outbox.mutation.server-error-terminal` | ~65 | Permanent server reject |
| `serial-gate.stalled` | ~56 | Holder often **`failMutation`** for **160+ s** |
| `connection.receive-loop-failed` | ~13 | Live receive aborted → reconnect |
| `photo-library.asset.persisted` | hundreds | App amplifier (not Instant store GC) |

### 1.4 Error strings that matter

1. **`Permission denied: not perms-pass?`** — server `permission-denied` on mutation path.  
2. **`Missing required attributes`** — e.g. `transcriptionSegments/startTimeSeconds`, `transcriptionWords/wallClockEndedAtMs` (server-side required-attr validation).  

These are **terminal mutation rejects**, not “network flaky.”  
They must **not** kill the WebSocket; they must **not** hold the serial gate for minutes.

### 1.5 What is already fixed (do not re-open)

| Version | Fix | Class |
|---------|-----|--------|
| **1.5.1** | Pre-kickstart local fullness; closed-window no-op expand | Infinite short-page Jetsam |
| **1.5.2** | Infinite + page-info diagnostics | Instrumentation |
| **1.5.3** | Isolate **failed legacy** outbox rows during **server apply** | recipes `773e50f4…` apply poison |

Today’s cascade is a **different class** than 1.5.3.

---

## 2. Mental model (keep this stable)

### 2.1 Offline (intentional Swift adaptation)

```text
TypeScript Instant
  online:  WS → rebuild per-query in-memory stores (refresh-ok)
  offline: IndexedDB querySubs + pendingMutations
  errors:  per mutation/query; socket life is transport-only

Swift Instant
  online:  WS → apply into ONE SQLite triple store (+ observers)
  offline: SQLite is already truth + outbox
  errors:  MUST be row-scoped; do not kill receive for validation
```

**Keep** SQLite offline-first for Scribe (ADR 0001, handoff §2–3).  
**Do not** “fix performance” by dropping durable apply.

### 2.2 Memory architecture (structural floor)

```text
Process RAM
  InstantStore: AttributeStore + TripleIndexes (EAV + AEV + VAE)  ← full corpus
  Outbox: pending + failed (full tx + rollback images)
  Infinite coordinator: all loaded chunk snapshots
  SQLitePersistenceStore.cachedState: second full snapshot
  App: TCA, audio, photo buffers, diagnostics

SQLite
  instant_triples, instant_outbox, live_query_results + ownership,
  query_cache, files/streams …
```

ADR 0009 GC bounds **ownership caches**, not the always-hot global store.  
Multi-hundred-MB **healthy** floor after full hydrate is plausible.  
**88 → 900+ MB over minutes** is thrash on top of that floor — not “expected idle.”

### 2.3 Concurrency (Swift adaptation of Reactor)

TS has one event loop → no gate.  
Swift actors reenter at `await` → **`AsyncSerialGate` (`operation`)** serializes multi-await critical sections.  

**Contract addition:** gate = **short consistency critical section**, not “do all of failMutation work here.”  
Stall threshold is already **5 s** (matches repo rule). Holding **160 s** is a product emergency.

---

## 3. Causal chain (implementers’ map)

```text
Poison durable outbox
  (permission-denied + missing required attributes)
        │
        ▼
Many terminal server errors
        │
        ▼
failMutation under operationGate
  · prepareTerminalFailureRemoval: reverse-rollback successors + replay
  · O(successors × store prepare) on Scribe-scale triples
  · recordsConnectionFailure:true marks connection "errored"
  · hold 160+ s → serial-gate.stalled (transact / applyLiveRefresh wait)
        │
        ├─► HOL waits: flush cannot advance
        ├─► acks not processed → ack-timeout-reclaim → resend poison
        └─► late/unmatched error after row already .failed
                  └─► throw from handleLiveServerEvent
                        └─► connection.receive-loop-failed
                              └─► reconnect + re-subscribe + re-apply
                                    └─► footprint climb / energy burn
```

**Library owns** isolation, gate bounds, reclaim policy, connection status semantics.  
**Scribe owns** stopping poison writers (schema push, required attrs in same tx, perms).  
**App owns** photo-library flood coalescing.

---

## 4. Research quorum summary

Five parallel research agents + two independent evaluators. Consensus:

| Topic | Consensus |
|-------|-----------|
| 1.5.3 incomplete for today | Yes |
| Cascade B is primary *time* driver | Yes |
| Structural floor A is real | Yes — measure after thrash dies |
| Keep SQLite offline | Yes |
| Soak #150 false confidence for idle 880 MB | Yes (768 MiB growth / 1 GiB ceiling) |
| Cross-SDK benches not hard gates | Yes (all rows optimization-target, still `ok`) |
| Gate = short CS | Yes |
| Absolute idle + storm + gate-latency tests required | Yes |

**Disagreement resolved:** neither “only structural” nor “only thrash.” Hybrid: thrash first this week; floor reduction after measurable baseline.

---

## 5. Three-phase ship plan

### Phase 0 — Emergency stop thrash (days)

**Goal:** Device stays alive; socket stays useful under poison; gate never multi-minute.

| ID | Change | Owner | Success metric |
|----|--------|-------|----------------|
| **P0.1** | Mutation/query validation errors **never throw** out of receive path; late/duplicate errors log + return | Library | `connection.receive-loop-failed` from permission/missing-attr = **0** |
| **P0.2** | `failMutation`: short gate (CAS mark failed); heavy successor rebase **outside** gate or entity-scoped/batched ≤ **5 s** | Library | `serial-gate.stalled` holder `failMutation` = **0**; hold p95 ≤ 5 s |
| **P0.3** | `recordsConnectionFailure: false` for permission/validation terminal fails | Library | Connection stays opened/authenticated through N permanent rejects |
| **P0.4** | Terminal poison never re-enters in-flight / reclaim-as-pending; stop reclaim storm | Library | `ack-timeout-reclaim` not storming on known-failed heads |
| **P0.5** | Apply/`refresh-ok` failures: quarantine + keep prior SQLite; **do not** advance processed-tx; continue loop | Library | Apply throw ≠ session death (except true corruption) |
| **P0.6** | Composition instrumentation: triples / outbox pending+failed / live keys / footprint | Library | Agent can attribute RAM buckets from terminal |
| **P0.7** | Stop poison writers: required attrs + perms; loud failed inventory | Scribe | New `server-error-terminal` rate → 0 healthy session |
| **P0.8** | Coalesce photo-library change storm | Scribe | Log rate within budget; no multi-GB import buffers |

**Phase 0 exit (physical iPad, production-shaped store):**

- 10 min idle + short recording window: **no Jetsam**
- phys_footprint **&lt;400 MB** (trend toward ≤250 MB)
- 0 repeating `receive-loop-failed` from mutation validation
- 0 gate holds &gt;10 s; p99 hold &lt;5 s
- Online outbox pending not sustained &gt;100; failed non-increasing without new user actions
- Dual diagnostic lanes still required (library self-suspicion)

### Phase 1 — Production budgets (release gate)

**Goal:** `docs/performance-budget.md` numbers are **CI + device** gates, not aspirational docs.

| ID | Change | Owner |
|----|--------|-------|
| **P1.1** | Absolute **idle footprint** gate (fail &gt;400 MB; target ≤250 MB after settle) | Library + Scribe |
| **P1.2** | Idle growth ≤10 MB / 10 min (budget) | Library soak |
| **P1.3** | Rewrite #150 soak: thrash clause **and** plateau clause; stop calling 768 MiB growth “production ready” | Library |
| **P1.4** | Storm suite: permission-denied + missing-attr + reclaim (CI) | Library |
| **P1.5** | `failMutation` / gate contention wall-clock tests on ~100k–500k triples | Library |
| **P1.6** | Hard-fail cross-SDK ratio / package-benchmark baselines (Release or ratio-only) | Library |
| **P1.7** | Mutation→ack p50/p95; outbox depth; single websocket; reconnect ceiling | Library + Scribe regression gate |
| **P1.8** | Recipes-v3 **scribe-library** canary: full namespaces + `--soak` exit codes | Library |
| **P1.9** | Gate hold/wait **histograms** always-on (not only 5 s stall) | Library |

**Phase 1 exit:** all performance-budget rows enforceable from terminal on Scribe-shaped data; green CI cannot mean “didn’t thrash to multi‑GB.”

### Phase 2 — Structural efficiency (after thrash dead)

**Goal:** cost scales with active work, not only full history — **ADR-first**.

| ID | Change | Notes |
|----|--------|-------|
| **P2.1** | Reduce double full-snapshot residency (`cachedState` vs indexes) without correctness loss | Measure first (P0.6) |
| **P2.2** | Incremental store commit / structural sharing (TS `store.ts` direction) | Attacks 6–300× cross-SDK ratios |
| **P2.3** | Notify deep-equal / revision-equal skip (TS `notifyOne`) | CPU/UI |
| **P2.4** | Coalesce durable refresh writes under load (TS 100 ms throttle) | Keep 5 s ack fail-loud |
| **P2.5** | Optional distant frozen infinite-chunk data eviction | Keep cursors; rematerialize from store |
| **P2.6** | Cold-namespace / query-scoped materialization | **Requires new ADR**; not Phase 0 |
| **P2.7** | Failed-outbox retention policy (age/count) with **explicit** recovery API | Loud, never silent success |
| **P2.8** | Custom SQLite `SerialExecutor` only if hop histograms demand | Not a thrash fix |

---

## 6. Add / change / remove matrix

### 6.1 Add (library)

| Item | Why |
|------|-----|
| Non-throwing terminal mutation + late-error path | Stops receive-loop death |
| Short-gate failMutation + deferred rebase | Stops 160 s freezes |
| Apply quarantine path + diagnostics event | TS-shaped isolation for SQLite apply |
| `serial_gate.hold_ms` / `wait_ms` histograms | Budgetable, not binary stall only |
| Memory composition samples | Attribution for 880 MB |
| Tests in §7 | Close false confidence |
| Live resilience validation script | Device/ephemeral app |
| Hard thresholds on cross-SDK / package-benchmark | Make “performance” real |
| Recipe `scribe-library` / soak CLI | Terminal canary without Scribe UI |

### 6.2 Change (library)

| Item | From → To |
|------|-----------|
| Soak #150 | Thrash-only loose growth → **absolute idle + thrash** |
| Connection `errored` on mutation deny | Always → **only transport/protocol** |
| In-flight timeout | 10 s reclaim that resends poison → **5 s + never reclaim terminal-failed** |
| Full `refreshRegisteredQueries` after every fail | Always → **targeted or none** (TS deletes mut, notifies) |
| Cross-SDK `ok: true` with 0/15 meets | Soft → **fail** when ratio exceeds cap |
| `INSTANT_DATA_PERFORMANCE_BENCHMARKS.md` | Recommendation → **acceptance gates** after Phase 0 |

### 6.3 Remove / stop treating as sufficient

| Artifact | Stop claiming |
|----------|---------------|
| 768 MiB growth / 1 GiB ceiling alone | “Production memory ready” |
| Local-only soak without live/outbox poison | Full reliability |
| Cross-SDK all-optimization-target green | Speed parity |
| Todos / presence recipes | Scribe energy proof |
| Mocked `LockedMemoryMeter` unit tests | Real RAM proof |
| “VSZ is huge” | Leak diagnosis (VSZ is not RAM) |
| Longer timeouts | Resilience |

### 6.4 Keep (non-negotiable)

- SQLite offline-first + outbox  
- ADR 0007 bounded infinite chunks + 1.5.1 short-page close  
- ADR 0008/0009 ownership + GC bounds  
- ADR 0013 optimistic empty-protect  
- Fail-loud permission denials (visible failed rows)  
- Dual-write diagnostics during library development  
- 5 s timeout culture  
- Strict Swift 6 concurrency settings  

---

## 7. Tests & recipes that must exist

### 7.1 Deterministic (library CI)

| Test (name suggestion) | Assert |
|------------------------|--------|
| `PermissionDeniedReceiveLoopSurvivalTests` | 50+ permission-denied → loop alive; next refresh applies |
| `MissingRequiredAttributeReceiveLoopSurvivalTests` | Same for server required-attr errors |
| `DuplicateTerminalErrorDoesNotKillReceiveLoopTests` | Second error after `.failed` → no throw |
| `AckTimeoutReclaimDoesNotRependTerminalFailedTests` | Failed head not reclaimed as pending |
| `FailMutationLargeStoreLatencyTests` | ~100k–500k triples: failMutation hold **&lt;5 s** |
| `OperationGateContendedFlushTests` | Concurrent fail + transact + queryOnce under 5 s after leave |
| `ServerApplyQuarantineContinuesReceiveLoopTests` | Bad refresh quarantine; prior triples intact; processed-tx not advanced |
| `ConnectionStatusNotErroredOnPermissionDenyTests` | Status stays connected |
| `ScribeIdleFootprintBudgetTests` | Absolute footprint after settle **≤400 MB fail / ≤250 MB target** (Release or documented Debug allowance) |
| `OutboxAckTimeoutReclaimStormTests` | Fake clock: reclaim rate bounded; log rate bounded |
| `StartupScalingBudgetTests` | 100 vs 5000 recordings: load/decode ratio ≤2× |

### 7.2 Live / soak scripts

```bash
# Existing thrash gate (keep, tighten later)
validation/verify-scribe-shaped-memory-soak.sh

# NEW
validation/verify-scribe-shaped-live-resilience.sh   # poison + live
validation/verify-gate-contention.sh
validation/verify-outbox-depth-budget.sh
validation/verify-recipes-v3-perf-canary.sh
```

Wire into `validation/verify-v1-release.sh` only when thresholds are honest.

### 7.3 Recipes

| Recipe | Role |
|--------|------|
| Linked Infinite soak profile | Keep as thrash detector; raise fidelity to segments/attachments/debugLogs |
| **NEW `scribe-library`** | Production counts + background deny injection + footprint exit code |
| Todos / presence | Demos only — not energy proof |

---

## 8. Instrumentation & terminal SOP

### 8.1 Metric catalog (minimum)

| Metric | Budget start |
|--------|--------------|
| `serial_gate.hold_ms` / `wait_ms` (p50/p95) | p95 hold ≤100 ms normal; ≥5 s critical |
| `serial_gate.stall` | 0 in healthy soak |
| `outbox.depth` by status | online pending ≤10; fail &gt;100 × 5 min |
| `outbox.apply_ack_ms` | p50 ≤2 s; p95 ≤5 s |
| `memory.phys_footprint` | ≤250 MB target / 400 MB fail |
| `connection.receive_loop_failed` | 0 healthy |
| `ws.connections` | exactly 1 |
| `ws.reconnect_attempts` / 10 min outage | ≤8 |
| Composition: triples, outbox failed/pending, live keys | trend stable idle |

Emit via `InstantDiagnostics` JSONL + optional `OSSignposter` for xctrace.

### 8.2 Daily agent SOP (no GUI)

```bash
# 1) Dual lanes alive?
# scripts/diagnostics-ws/README.md — collector health first if both silent

# 2) Memory samples
jq -c 'select(.entry.name=="process.memory.sample")
  | {t:.entry.timestampLocal,
     fp:.entry.metadata.physicalFootprintBytes,
     rss:.entry.metadata.residentBytes}' \
  ~/Library/Logs/Scribe/diagnostics.jsonl | tail -20

# 3) Thrash counters
python3 - <<'PY'
import json,collections
from pathlib import Path
c=collections.Counter(); holds=[]
path=Path.home()/"Library/Logs/Scribe/diagnostics.jsonl"
# prefer last 10MB
size=path.stat().st_size
with path.open("rb") as f:
    if size>10_000_000: f.seek(size-10_000_000); f.readline()
    for raw in f:
        try: o=json.loads(raw)
        except: continue
        e=o.get("entry") or o
        n=e.get("name") or e.get("event") or ""
        if n: c[n]+=1
        if n=="serial-gate.stalled":
            md=e.get("metadata") or {}
            try: holds.append(int(md.get("holderHeldMilliseconds") or 0))
            except: pass
print("top", c.most_common(20))
print("stall max_ms", max(holds) if holds else None, "n", len(holds))
PY

# 4) Library unit gates
cd /Users/laptop/Sync/instant-data-swift
swift test --filter 'AsyncSerialGate|InstantOutboxDeliveryStall|LinkedInfiniteScribeShapedMemorySoak|InstantStoreWriteScaling'
validation/verify-scribe-shaped-memory-soak.sh

# 5) Device behavior without taps (app with SCRIBE_AGENT_CONTROL=1)
# $scribe-agent-control readState / listActions / sendAction

# 6) Pre-release only: xctrace Power Profiler / Allocations (CLI export)
# see ~/.agents/skills/instruments-profiling/
```

### 8.3 Point-Free concurrency guidance (mapped)

| PF pattern | Instant mapping |
|------------|-----------------|
| Coarse actors + Sendable values (ep193) | Store / Outbox / Persistence / Transport |
| Structured task ownership (ep196–199) | Runtime owns receive/flush; cancel on close |
| Streams + backpressure (ep198) | `bufferingNewest(1)` |
| TestClock / continuous clock | Reconnect, 5 s budgets, stall tests without wall sleep |
| `@Dependency` test keys | Transport, clocks, IDs |
| `reportIssue` | Gate stalls, decode fail, poison outbox |
| TCA TestStore | **Scribe product** only — not InstantRuntime as reducer |

---

## 9. Upstream TS patterns to port (ordered)

1. **Error isolation shape** of `_handleReceiveError` — mutation/query never default-kill socket  
2. **Confirmed mutation cleanup** + timeout safety valve (`_cleanupPendingMutations*`)  
3. **Deep-equal / version skip** on notify  
4. **Persist throttle / idle GC** for non-critical durable meta  
5. **Structural-sharing incremental commit** (store.ts) — primary long-term ratio fix  
6. **Sacred-key unload** on final unsub (RAM); durable GC separate  
7. **Preload bounds** (warm N hottest results)  
8. **Infinite chunk lifecycle** discipline (already largely ADR 0007)  

**Do not port:** “no SQLite,” silent delete of failed mutations without recovery UX, or infinite timeouts.

---

## 10. Production-ready definition (pass/fail)

Physical device, production-shaped account (order: hundreds of recordings, thousands of words/segments, attachments present), Release or production-like localDev.

| Gate | Pass | Fail |
|------|------|------|
| Idle footprint after 5 min settle | ≤ **300 MB** (stretch ≤250) | > **400 MB** |
| Idle growth 5→15 min | ≤ **30 MB** | Sustained multi‑100 MB climb |
| 60 min recording footprint | ≤ **250 MB** | > **400 MB** or Jetsam |
| `connection.receive-loop-failed` / 10 min healthy | **0** | ≥1 repeating |
| `serial-gate.stalled` hold ≥5 s | **0** | ≥1 |
| `failMutation` hold p95 | ≤ **5 s** | >5 s |
| New terminal mutation errors healthy | **0** | Repeating schema/perms |
| `ack-timeout-reclaim` storm | **0** | >10 / 10 min without network loss |
| Outbox pending online | ≤ **10** | >100 × 5 min |
| Mutation → ack | p50 ≤2 s, p95 ≤5 s | >10 s |
| Websockets | **1** | ≥2 |
| Idle CPU foreground | ≤ **2%** one core | >5% |
| Jetsam / 24 h | **0** | ≥1 |

**Ship rule:** Phase 0 exit on device + library storm/latency tests green. Phase 1 absolute idle gate green before calling the library “production ready for Scribe.”

---

## 11. Risks of partial fixes

| If you only… | Then… |
|--------------|--------|
| Fix receive-loop isolation | Socket lives; gate still freezes product; memory/energy thrash continues |
| Cap outbox without isolation | Still reconnect/apply storms |
| Tighten soak only | CI fails without fixing field thrash |
| Lazy-hydrate global store without ADR | Blank-detail / retraction regressions return |
| Silent-discard failed mutations | Schema/perms outages become invisible again |
| Drop SQLite to match TS | Wrong product model; rewrite months |
| Raise timeouts | Violates 5 s rule; hides death spirals |

---

## 12. Suggested implementation slices (small commits)

1. **Tests first:** permission-denied / missing-attr / duplicate-error receive-loop survival (red).  
2. Make error path non-throwing + late-error ignore (green).  
3. Tests: failMutation hold budget + concurrent transact (red).  
4. Split failMutation critical section; `recordsConnectionFailure` policy (green).  
5. Tests: reclaim does not repend terminal-failed (red/green).  
6. Apply quarantine path (tests first).  
7. Composition diagnostics event.  
8. Scribe: schema/required attrs + photo coalesce (parallel).  
9. Tighten soak + absolute idle test.  
10. Tag **1.5.4** (or 1.6.0 if policy changes) + pin Scribe + device verify.

Use `$change-log` for each coherent verified slice; Instant issue `workLog` for #134 / #150 checkpoints.

---

## 13. Explicit non-goals (this plan)

- Re-implement Scribe debug overlay inside the library  
- Re-pin 1.5.0 or re-litigate fixed infinite thrash  
- Invent TS `applyServerTransaction` for its own sake  
- GUI-only profiling as the only measurement path  
- Matching TS heap layout byte-for-byte  
- Compensating for library HOL/gate death inside Scribe reducers  

---

## 14. Handoff continuity

**Previous handoff job** remains valid for apply/receive-loop resilience — this plan **expands** it with:

- Live 880 MB+ evidence and thrash counters  
- Structural memory floor + false-confidence soak critique  
- Phase plan, test matrix, terminal SOP, production numbers  

Next implementer should **not** re-research Jetsam thrash or offline theory.  
**Start at Phase 0.1–0.4 tests** and the causal chain in §3.

---

## 15. Research provenance

| Agent | Focus |
|-------|--------|
| Research A | Memory/storage architecture, GC bounds, soak gaps |
| Research B | Receive-loop / failMutation / outbox reclaim causal chain |
| Research C | TS vs Swift parity matrix + top-10 ports |
| Research D | PF concurrency, instrumentation, terminal CI |
| Research E | Recipes/tests/benchmarks false confidence audit |
| Eval 1 | Consensus / hybrid causal story / ranked week plan |
| Eval 2 | Independent scores (~2.5/10) / top-5 leverage / 3 phases |

Live diagnostics re-sampled during planning (13:09–13:25 EDT, 2026-08-05).

---

*End of plan. Prefer this file + the 2026-08-05 handoff over conversation scrollback.*
