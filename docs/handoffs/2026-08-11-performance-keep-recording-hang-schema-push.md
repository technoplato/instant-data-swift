# Handoff: Performance KEEP, InstantError, recording hang, schema push, device RTT

**Written:** 2026-08-11 16:12:59 EDT  
**Author session:** Grok Build (continuation of ChatGPT/Codex 019fe994 performance wrap + device trial)  
**Repos:** `instant-data-swift` + consumer `realtime-voice-sqlite-instant` (Scribe)  
**Mode for implementer:** agent with write/execute (schema push, install, code fixes)

Mirror copy (same content):  
`../tools/realtime-voice-sqlite-instant/handoffs/2026-08-11-performance-keep-recording-hang-schema-push.md`

---

## 1. Mission (what the captain wants)

1. **Reasonable Instant performance on physical device** including KEEP criteria:
   - App opens and records after freezes
   - Memory under budgets (idle ≤400 MiB phys_footprint hard ceiling used in soak/device tools)
   - Live Swift↔server / admin RTT observable (lab p50≤2s / p95≤5s already passed; **device RTT still needed**)
2. **Never show opaque `InstantSwiftDataCore.InstantError error 1`** — surface exact operation/message/recovery from the library.
3. **Fix recording hang** on stop: “Finishing the current recording without discarding transcript results…” never ends (screenshot 2026-08-11 ~16:08).
4. **Debug build overlay default expanded** (not hidden).
5. **Push Instant schema/perms to server** — captain explicitly rejected skipping push; install previously skipped the drift gate.
6. **Measure device→server latency** and observe round-trip on the laptop (admin/TS observe).

---

## 2. Repository tips (as of handoff write)

### instant-data-swift

| Item | Value |
|------|--------|
| Path | `/Users/laptop/Sync/instant-data-swift` |
| Branch | `main` (ahead of origin by ~131) |
| HEAD (write time) | `b5b67a9d` — later audit commits may exist; **performance/error fix tip is `7c4e5ab6` / ledger `afc6f7b2`** |
| Working tree | Often dirty: ADR 0016 `04-uri-tree.md` + `qanda.md` (other agent; **do not stash/reset**) |
| Symlink into Scribe | `Packages/instant-data-swift` → this checkout |

**Key commits (this thread):**

| SHA | Subject |
|-----|---------|
| `8b7c384e` | Bounded outbox/memory freezes + suite compile unblocks |
| `c4f20714` | Changelog for freezes |
| `e24044c5` | PROGRESS wrap-up evidence |
| `afe09bdb` | InstantRuntime split; remove SIL `closure-lifetime-fixup` flag |
| `01874de8` | Changelog Runtime split |
| **`7c4e5ab6`** | **InstantError LocalizedError/CustomNSError; deferred validation clarity; macro JSON non-indexed** |
| **`afc6f7b2`** | Changelog InstantError fix |

Later commits on main (`bbc2b970`, `0e1e3924`, `b5b67a9d`, …) are **audit logs / other agents** — preserve them.

### realtime-voice-sqlite-instant (Scribe)

| Item | Value |
|------|--------|
| Path | `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` |
| Branch | `main` (ahead of origin by ~72) |
| HEAD tip | `cd6ae06` (moving; device binary was **`505216be3050`**) |
| Working tree | **~247 dirty porcelain lines** — multi-agent WIP; **never stash/reset foreign work** |
| Instant dep (dirty) | `Package.swift` uses **`.package(path: "Packages/instant-data-swift")`** for dual-dev (was `exact: 1.5.6`) |
| Device install | Scribe Dev `com.michaellustig.scribesharedios.dev` on **Michael's iPad** `B5731923-30F8-54EE-A73A-998AA89155E7` |

**Uncommitted Scribe change from this thread (must re-verify with `git diff`):**

- `Sources/ScribeSharedSupport/ScribeInstantStore.swift`
  - Bootstrap failure presentation uses `InstantError.userFacingSummary`
  - Deferred residency attribute list adjusted (timeline deferred; transcriptText not deferred while string fields stay macro-indexed)

---

## 3. What already works (do not re-litigate)

### Lab / library

| Gate | Evidence | Status |
|------|----------|--------|
| Bounded freezes (50/256/8 MiB, terminal rejection, deferred residency contracts) | `8b7c384e`; focused suites green in session | PASS |
| Swift ↔ TS admin latency | `/tmp/instant-swift-admin-latency/`; p50 ~80 ms, p95 ~154 ms | PASS |
| Process soak #150 | `validation/results/scribe-soak-20260811T175656Z/evidence.json` status=passed, ceiling 400 MiB | PASS |
| InstantRuntime SIL hang | Split TU (`InstantRuntimeLiveSession`, ExactTaskOwner, VisibleWrite); Package.swift **no longer** has debug `sil-disable-pass` | PASS |
| InstantError presentation unit tests | `Tests/InstantSwiftDataCoreTests/InstantErrorPresentationTests.swift` | PASS |

### Device (partial KEEP)

| Gate | Evidence | Status |
|------|----------|--------|
| Wipe + install Scribe Dev with local Instant | Installed; process launches | PASS |
| App opens (post InstantError/deferred fix) | Agent session connected | PASS |
| Agent-control session | `agent-1` AppFeature, build `505216b`, 265 actions | PASS (session may be stale after hours) |
| Start + stop recording via agent-control | `newRecordingButtonTapped` / `stopButtonTapped` | PASS path taken |
| phys_footprint under budget | `/tmp/scribe-physical-keep-20260811T1606.json` — idle ~37 MB, peak ~196 MB, after stop ~130 MB | PASS budgets |
| Clean-git shipping provenance | Dirty trees + path Instant + skipped drift | **FAIL** (expected for dual-dev) |
| Cloud outbox clean drain | encoding quarantine + route-chunk strict update fail | **FAIL** |
| Stop UI finishes cleanly | Screenshot + logs show hang / late finish | **FAIL / flaky** |
| Schema pushed to Instant cloud | Drift skipped; push never run this session | **FAIL** |
| Device↔admin RTT measured this install | Not run | **FAIL** |

Physical KEEP evidence file:

```text
/tmp/scribe-physical-keep-20260811T1606.json
```

---

## 4. Root causes already diagnosed (use these first)

### 4.1 Opaque `InstantError error 1` (FIXED in library)

- Casting `InstantError` to `NSError` without `CustomNSError` → domain `InstantSwiftDataCore.InstantError`, **code always 1**.
- Scribe already documented this in `ScribeDiagnosticErrorMetadata.swift`.
- **Fixed in `7c4e5ab6`:** `LocalizedError` + `CustomNSError`, `userFacingSummary`, stable codes 1–7 per `Code` case.
- Device logs after reinstall show the **new** multi-line summaries (e.g. route-chunk strict update).

### 4.2 Bootstrap “Could Not Open Scribe” (FIXED dual-layer)

**Cause A — deferred residency vs macro indexing:**

- Scribe deferred `"sharedRecordings/timeline"` / `"sharedRecordings/transcriptText"`.
- `@InstantEntity` macro previously emitted **`isIndexed: true` for every field**.
- Deferred policy **rejects indexed attributes** → `validationFailed` at bootstrap → open screen with opaque error 1.

**Fix A (library):** macro leaves **JSON** attributes non-indexed (`InstantSwiftDataMacros.swift` in `7c4e5ab6`).

**Fix B (Scribe, dirty):** deferred list uses payload attributes that validate (samplesJSON, locationRoute, timeline); do **not** defer string transcriptText until explicitly non-indexed.

**Cause B — presentation:** Scribe bootstrap UI used `error.localizedDescription` without Instant structured text; improved via `bootstrapFailurePresentation` in dirty `ScribeInstantStore.swift`.

### 4.3 Recording hang on stop (NOT FIXED — captain screenshot)

**UI copy:**

- Warning: “Recording stop is still waiting for the exact speech or system-audio transcript stream to finish. No transcript was discarded.”
- Spinner: “Finishing the current recording without discarding transcript results…”
- Footer: “Finishing recording…”

**Source:**

- Warning: `Recording.swift` `case .speechFinalizationTimedOut` (~3753)
- Spinner: `RecordingView.swift` `isFinishingTranscriptDrain` (~1767)
- Predicate: `isFinishingTranscriptDrain` ⇔ `speechFinalizationPhase != .inactive` (~1041)

**Device log timeline (2026-08-11 EDT):**

| Time | Event |
|------|--------|
| 16:06:39 | `recording.stop.speech-input-close.failed` — session stale; active session is **none** |
| 16:06:39 | system-audio transcript finished |
| 16:06:44 | `recording.stop.transcript-drain.timed-out` — **speechFinished=false**, systemAudioFinished=true |
| 16:07:11 | `speechTranscriptStreamEnded` → stop continues |
| 16:07:11 | `recording.sqlite.typed-write.failed` / `transaction.failed` / durability **blocked** |

**Bug A (Scribe stop machine):**  
`speechFinalizationTimedOut` only sets `connectionStatus` + logs. It does **not**:

- force `speechTranscriptStreamFinished = true`, or  
- clear stale `speechSessionID`, or  
- call `finishStopIfTranscriptSourcesEnded` / force finish.

`speechFlushFailed` returns `.none` and leaves finalization phase waiting.

`finishStopIfTranscriptSourcesEnded` requires:

```swift
speechSessionID == nil || speechTranscriptStreamFinished
systemAudioSessionID == nil || systemAudioTranscriptStreamFinished
```

So after stale session + timeout, UI can spin until a late stream end (or forever).

**Bug B (route-chunk finalize):**  
Finalize uses **strict update** on `recordingRouteChunks` entity that does not exist:

```text
errorOperation: strict update entity
errorNamespace: recordingRouteChunks
errorMessage: No existing entity was found for '<id>'
recovery: Create the entity before using a strict update, or use merge for upsert-style writes.
```

Likely create never succeeded (encoding quarantine / schema not on server / write path).

**Earlier related:** `outbox.mutation.encoding-quarantined` during record — local schema ahead of server for route chunks / perms.

### 4.4 Why schema was not pushed (captain: push it)

- Installer `require_instant_configuration_matches_server` failed with **~31 mismatches** (local has `recordingRouteChunks`, attachment lifecycle fields; server has extra `todos` / `validationBoundary`, etc.).
- To get a binary on device under captain “install now,” agent **skipped** the drift gate (user-authorized dirty install).
- Historical PROGRESS notes: `instant-cli push` can fail with missing role / ownership — still captain wants push attempted with proper login.

### 4.5 Debug overlay default

- `ScribeBuildDebugOverlaySettings` default `presentation: .hidden` (`Sources/SharedModels/ScribeBuildDebugOverlaySettings.swift` ~75, decode fallback ~99).
- Captain wants **default `.expanded`**, not hidden.
- File-backed `@Shared` — existing devices keep stored value; need default change **and** migration or key bump for devices that already have `.hidden`.

### 4.6 Dual-dev Instant pin thrash (install lessons)

- `scripts/use-local-instant.sh` + SPM edit mode is **not enough** for Xcode DerivedData: build re-checked out **remote 1.5.6** and lost Instant HEAD APIs (`InstantAttributeSelection`, etc.).
- Working approach: dirty `Package.swift` **path** dependency:

  ```swift
  .package(path: "Packages/instant-data-swift"),
  ```

- Installer `verify_app_bundle` then fails looking for embedded Instant git revision of clean pin — **bypass** with direct:

  ```bash
  xcrun devicectl device install app --device <id> ".build/device-deployment/ios-device/Build/Products/Debug-iphoneos/Scribe Shared.app"
  ```

- App Clip sometimes unsigned → codesign Clip + parent before install (identity `Apple Development: Michael Lustig (5TF6D88GSE)` / hash from last build).

- Diagnostics LaunchAgent refuses dirty `scripts/diagnostics-ws`; if collector down, start manually:

  ```bash
  node scripts/diagnostics-ws/collector.mjs serve \
    --host 127.0.0.1 --port 8767 --path /scribe-diagnostics \
    --journal ~/Library/Logs/Scribe/diagnostics.jsonl
  ```

  Port **8765** is occupied by Foldkit portal; supervised collector is **8767**. Tailscale Serve: `https://laptop.tail91224c.ts.net` → `http://127.0.0.1:8767`.

---

## 5. Exact next work (ordered)

### Priority 0 — unblock captain UI hang (Scribe)

Files:

- `Sources/RecordingFeature/Recording.swift`
- `Sources/RecordingFeature/RecordingView.swift` (copy only if needed)
- `Tests/RecordingFeatureTests/RecordingTests.swift` (timeout tests already mention the warning string ~873)

Implement:

1. **`speechFlushFailed`:** if session missing/stale, set speech stream finished (or nil session) and call `finishStopIfTranscriptSourcesEnded`.
2. **`speechFinalizationTimedOut`:** force-complete stop drain (do not only set `.error` status). Keep loud log. Cancel wait IDs.
3. Optional hard deadline (10–15s) that always exits finishing phase.
4. Tests: stop with no active speech session finishes; timeout forces finish when speechFinished stays false.

### Priority 1 — push schema + perms (Instant cloud)

From Scribe root, with captain Instant platform login:

```bash
# Prefer project-pinned instant-cli (see package.json / docs)
# App ID: config/scribe-shared-instant.json (shared Instant app)

# 1) See current drift
python3 scripts/instant-drift/check.py --repo-root .

# 2) Push (exact flags per docs/production-readiness-plan.md and current CLI)
# Examples that appear in repo history:
npx instant-cli push schema --yes
npx instant-cli push perms --yes
# or push all if that's the supported path

# 3) Re-check until drift gate is green (or only server-only canaries remain intentionally)
python3 scripts/instant-drift/check.py --repo-root .
```

If push fails on role/ownership: stop and report exact CLI error; do not silently skip again without captain ack.

After push: stop skipping drift in install for localDev (or keep skip only if captain re-authorizes).

### Priority 2 — route-chunk finalize correctness (Scribe + maybe Instant)

- Find finalize write for `recordingRouteChunks` (strict update).
- Prefer **merge / create-if-missing** so stop durability cannot block forever when create never landed.
- Correlate with encoding quarantine logs (`outbox.mutation.encoding-quarantined`).

### Priority 3 — debug overlay default expanded (Scribe)

File: `Sources/SharedModels/ScribeBuildDebugOverlaySettings.swift`

- Default `presentation = .expanded`
- Decode default `.expanded` if key missing
- Migrate: if needed, version key or one-time promotion so existing `.hidden` files don’t trap captain

### Priority 4 — reinstall fixed binary + verify open/stop

Device: Michael's iPad `B5731923-30F8-54EE-A73A-998AA89155E7`  
Bundle: `com.michaellustig.scribesharedios.dev`

```bash
# Ensure path Instant + clean Instant tree (park ADR 0016 dirt if needed)
# Build (dirty Scribe install requires gate bypasses used in this session)
# Install + launch:
xcrun devicectl device process launch --device B5731923-30F8-54EE-A73A-998AA89155E7 \
  --terminate-existing \
  --environment-variables '{"SCRIBE_AGENT_CONTROL":"1"}' \
  com.michaellustig.scribesharedios.dev

scripts/scribe-agent-control sessions
# Prefer newest session / matching build commit
```

### Priority 5 — device → server RTT (observe on laptop)

1. Ensure schema pushed so mutates encode.
2. Collector on 8767 + Tailscale Serve.
3. Agent-control short recording or a single known transact.
4. Correlate:
   - Device journal `~/Library/Logs/Scribe/diagnostics.jsonl` (Instant mutation / durability timestamps, `transactionID`s)
   - Laptop TS admin live observe of same IDs (reuse `/tmp/instant-swift-admin-latency/` recipes and `validate-swift-admin-latency` workflow if present)
5. Report p50/p95 device→admin visibility and any reverse path.

Helper already on machine:

```bash
python3 scripts/scribe-device-perf.py run --session <id> \
  --record-seconds 30 --settle-seconds 20 \
  --out /tmp/scribe-perf.json
python3 scripts/scribe-device-perf.py sample --since-seconds 600
```

Primary metric: **phys_footprint** from `process.memory.sample` (same class as debug overlay).

### Priority 6 — continuity bookkeeping

- Instant: `PROGRESS.md` newest-first entry; two-commit change-log pattern for new implementation SHAs.
- Scribe: handoff already mirrored under `handoffs/`.
- Cross-repo audit: `docs/audits/commit-changelog.md` in Instant after substantive commits.
- Do **not** commit entire 247-line dirty Scribe tree as one ball of mud — only owned paths.

---

## 6. Files map

### Instant (`instant-data-swift`) — landed

| Path | Role |
|------|------|
| `Sources/InstantSwiftDataCore/InstantError.swift` | LocalizedError, CustomNSError, `userFacingSummary` |
| `Sources/InstantSwiftDataCore/DeferredValueResidency.swift` | Louder missing-attribute messages |
| `Sources/InstantSwiftDataCore/InstantDiagnostics.swift` | Prefer InstantError structured fields |
| `Sources/InstantSwiftDataCore/InstantStartupTrace.swift` | Prefer InstantError on failure |
| `Sources/InstantSwiftDataMacros/InstantSwiftDataMacros.swift` | JSON `isIndexed: false` |
| `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift` | Runtime split extract |
| `Sources/InstantSwiftDataCore/InstantRuntimeExactTaskOwner.swift` | Runtime split extract |
| `Sources/InstantSwiftDataCore/InstantVisibleWriteFilter.swift` | Runtime split extract |
| `Package.swift` | No SIL disable flag on Core (post-split) |
| `Tests/InstantSwiftDataCoreTests/InstantErrorPresentationTests.swift` | Regression guards |

### Scribe — dirty / next

| Path | Role |
|------|------|
| `Sources/RecordingFeature/Recording.swift` | **Stop hang fix (P0)** |
| `Sources/RecordingFeature/RecordingView.swift` | Finishing UI copy |
| `Tests/RecordingFeatureTests/RecordingTests.swift` | Timeout / finish contracts |
| `Sources/ScribeSharedSupport/ScribeInstantStore.swift` | Bootstrap presentation + deferred list (partially edited) |
| `Sources/SharedModels/ScribeBuildDebugOverlaySettings.swift` | Default expanded (P3) |
| `Sources/ScribeSharedSupport/ScribeDiagnosticErrorMetadata.swift` | Already flattens InstantError for logs |
| `Package.swift` | Path Instant dual-dev (dirty) |
| `instant.schema.ts` / `instant.perms.ts` | Push targets (P1) |
| `scripts/instant-drift/check.py` | Drift gate |
| `scripts/install_scribe_all_devices.py` | Clean install; dirty needs bypasses |
| `scripts/scribe-device-perf.py` | Device memory fence posts |
| `scripts/scribe-agent-control` | Drive UI without taps |
| `scripts/diagnostics-ws/collector.mjs` | Agent + journal on :8767 |

### Evidence paths

| Path | Content |
|------|---------|
| `/tmp/scribe-physical-keep-20260811T1606.json` | Device record trial summary |
| `/tmp/instant-swift-admin-latency/` | Lab admin latency artifacts |
| `validation/results/scribe-soak-20260811T175656Z/` | Soak pass |
| `~/Library/Logs/Scribe/diagnostics.jsonl` | Device dual-write journal (live after reinstall) |
| Parked ADR dirt | `/tmp/instant-park-install-*` if used |

---

## 7. Device / infra cheatsheet

| Item | Value |
|------|--------|
| iPad | Michael's iPad · `B5731923-30F8-54EE-A73A-998AA89155E7` · iPad13,8 · iOS 27.0 |
| Tailscale node | `ipad-pro-12-9-gen-5` (was online during trial) |
| Scribe Dev bundle | `com.michaellustig.scribesharedios.dev` |
| Collector health | `curl -s http://127.0.0.1:8767/health` |
| Agent sessions | `scripts/scribe-agent-control sessions` |
| Start record | `send recordingList.newRecordingButtonTapped` |
| Stop record | `send recordingList.activeRecording.stopButtonTapped` |
| Signing identity used | Apple Development: Michael Lustig (5TF6D88GSE) |

---

## 8. Known log signatures to grep

```bash
# Hang / stop
rg 'transcript-drain|speech-input-close|speechFinalization|Finishing' ~/Library/Logs/Scribe/diagnostics.jsonl

# Route chunk / schema
rg 'recordingRouteChunks|encoding-quarantined|strict update entity' ~/Library/Logs/Scribe/diagnostics.jsonl

# Memory
python3 scripts/scribe-device-perf.py sample --since-seconds 600

# Open failure (legacy)
rg 'Could Not Open Scribe|scribe.bootstrap.failed|error 1' ~/Library/Logs/Scribe/diagnostics.jsonl
```

---

## 9. Coordination / multi-agent rules

- Protocol: `realtime-voice-sqlite-instant/docs/agent-coordination-protocol.md` (touch claims, plan-before-code on contended paths).
- Multiple agents on **main** — commit owned slices only; preserve foreign dirt.
- Instant ADR 0016 files often dirty — park with `cp` + `git checkout --` if install needs clean Instant; restore for ADR agent.
- Do not force-push; do not `reset --hard` shared checkouts.

---

## 10. Captain quotes (verbatim intent)

> “Just go ahead and install right now And you can wipe and launch with agent control”

> “could not open scribe, instantswiftdatacore.instanterror error 1, first improve this message and make it much more clear from the library exactly what happened and fix this please”

> “yep” (run recording + memory sample)

> Screenshot + hang: finishing without discarding transcript; not ending.

> “Recording is hanging… big bug… by default… turn on the debug menu in expanded mode… Make sure the schema is pushed to the server. I don't know why you wouldn't push it… measure the latency from the device to the server and observe the round trip on the machine.”

> “create a handoff document to pick up work where you left off, be super detailed”

---

## 11. Suggested first commands for next agent

```bash
# 0) Orient
cd /Users/laptop/Sync/instant-data-swift && git log -5 --oneline && git status -sb
cd /Users/laptop/Sync/tools/realtime-voice-sqlite-instant && git status -sb | head
curl -s http://127.0.0.1:8767/health; scripts/scribe-agent-control sessions

# 1) Read hang sites
# Recording.swift: speechFinalizationTimedOut, speechFlushFailed, finishStopIfTranscriptSourcesEnded
# RecordingView.swift: isFinishingTranscriptDrain ProgressView

# 2) Implement P0 tests first (RecordingFeatureTests), then fix stop machine

# 3) Schema push + drift green

# 4) Overlay default expanded

# 5) Rebuild/install dual-dev; force finish verified on device

# 6) Device RTT with admin observe
```

---

## 12. Definition of done (for this program slice)

- [x] Stop never spins > hard deadline after stop; tests prove timeout force-finish (working tree; multi-agent Recording.swift uncommitted)
- [ ] `recordingRouteChunks` finalize cannot block stop on missing entity (merge/create path)
- [x] Instant schema/perms pushed; drift gate green or documented canaries only
- [x] Debug overlay defaults to **expanded** for new installs (`061d737`)
- [ ] Fresh dual-dev (or clean) install opens, records, stops without hang banner stuck
- [ ] Device→server RTT numbers recorded (p50/p95) with transaction correlation on laptop
- [ ] Memory sample still under 400 MiB idle / reasonable peak during record
- [ ] PROGRESS + CHANGELOG updated for each owned Instant commit; Scribe commits owned-only

---

## 13. What not to do

- Do not re-disable SIL on InstantRuntime without measuring hang.
- Do not claim full KEEP while encoding quarantine + stop hang remain.
- Do not skip schema push again without explicit captain override.
- Do not install production bundle id (`com.michaellustig.scribesharedios`) via local side-load.
- Do not commit the entire dirty Scribe tree as one “fix everything” commit.

---

**End of handoff.** Next agent: start at **§5 Priority 0** (stop hang), then **Priority 1** (schema push).
