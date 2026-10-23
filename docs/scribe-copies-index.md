# Scribe copies index

**Audit date:** 2026-08-19  
**Canonical file:** `/Users/laptop/Sync/tools/docs/scribe-copies-index.md`  
**Do not delete copies.** This is an inventory, not a cleanup.

Copies of this file also live in the three named heads so each repo opens with the same audit.

---

## MISSING FROM THE THREE CANONICAL HEADS

The three heads Michael named:

| Named head | What exists on disk | Verdict |
| --- | --- | --- |
| **Instant Swift Data** | Instant-backed Scribe at `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` (`main`) plus the library at `/Users/laptop/Sync/instant-data-swift` | Product + library exist |
| **SQLite Data** | `/Users/laptop/Sync/tools/scribe-sqlite-data` (`scribe-sqlite-data`) | Product exists |
| **Couchbase Lite** | No worktree of `technoplato/scribe`. Closest head: `/Users/laptop/Sync/sync/engines` (CouchbaseData + mini Scribe, **no git commits yet**) | **Full Scribe product missing** |

A feature in 1 of 3 but not the others counts as missing from the three as a set.

### Headline: Couchbase Lite is not a Scribe product

**Couchbase Lite Scribe (full app).** Missing from Instant + SQLite + there is no third product head. The only Couchbase Scribe is a bench/mini app in `/Users/laptop/Sync/sync/engines` (`Sources/Scribe`, `ScribeLive`, `ScribeSchema`): recordings list, current-segment rewrite, committed stream, CLI `transcription`/`list`. It is **not** a fork of `technoplato/scribe`. GitHub has no `scribe-couchbase` repo. `$scribe-sync` (2026-08-17) also found no Couchbase in the Scribe/Instant trees.

That mini app is missing almost every product feature below (Watch, tvOS, widgets, App Clip, SharePlay, LiveKit, Instant issues, agent control, stream companion, TestFlight, public sharing, attachments, location, heart rate, …). Couchbase Lite 4.1 also has **no watchOS/tvOS slices** (vendor gap, documented in that README).

### In an old Scribe copy, missing from Instant + SQLite + Couchbase

These are confirmed in `/Users/laptop/Sync/tools/realtime-voice` (`codex/multiple-providers`, SHA `243cdeb`) unless noted.

**1. Transcript search + corpus discovery**

- **Where:** `Sources/SearchClient`, `SearchClientLive`, `SearchClientNeo4j`; spec `docs/features/SEARCH_AND_DISCOVERY.md`
- **Missing from:** Instant Swift Data, SQLite Data, Couchbase Lite
- **Does:** Current-transcript search and corpus search (sections, speakers, notes, clipboard, links, titles) with Neo4j-backed indexing

**2. Neo4j graph ingest**

- **Where:** `docs/features/GRAPH_SCHEMA_AND_INGEST.md`; `scripts/domain_ontology.py` (named in that spec)
- **Missing from:** all three
- **Does:** Recording/session/segment/word/task graph for “what happened” queries. Live Neo4j is source of truth in that copy.

**3. Multi-provider transcription (AssemblyAI + Voxtral)**

- **Where:** `docs/features/MULTI_PROVIDER_PROVISIONING.md`; `SettingsFeature` + typed `TranscriptionMethod`
- **Missing from:** all three (Instant + SQLite `SpeechRecognitionProvider` is only `.appleSpeechAnalyzer` / `.deepgram`)
- **Does:** First-class AssemblyAI and Voxtral runtimes with on-device / private-remote / third-party topologies

**4. Settings workspace (provider rail)**

- **Where:** `Sources/SettingsFeature`; `docs/features/SETTINGS_WORKSPACE.md`
- **Missing from:** all three (heads have Mac settings / speech-provider bits, not this rail)
- **Does:** Transcription / General / Shortcuts / Files workspace with credential drafts vs persisted settings

**5. Cloudflare tunnel as a private Speech Analyzer host**

- **Where:** `Sources/CloudflareTunnelClient` + `CloudflareTunnelClientLive`
- **Missing from:** all three
- **Does:** Install/auth/run `cloudflared` and expose a private remote Speech Analyzer URL. Heads only mention cloudflared in **public-sharing** docs, not as a transcription host.

**6. Private remote host pairing (`ScribeHostClient`)**

- **Where:** `Sources/ScribeHostClient` + `ScribeHostClientLive`
- **Missing from:** all three
- **Does:** Configure/pair an exposed URL + host name for private-remote transcription

**7. Local speech-activity (VAD) client**

- **Where:** `/Users/laptop/Sync/tools/realtime-voice-scribe-shared` and `realtime-voice-instant-latency` → `Sources/SpeechActivityClient`
- **Missing from:** all three
- **Does:** Local speech-detected events from PCM. Instant `SpeechClient` has no `SpeechActivity` / `speechDetected` symbols.

### In Instant, missing from SQLite Data and Couchbase Lite

**8. Idempotent recording-pipeline cleanup**

- **Where:** Instant `Sources/RecordingFeature/RecordingCleanupCoordinator.swift`
- **Missing from:** SQLite Data, Couchbase Lite
- **Does:** Joins overlapping speech/system-audio teardown so TCA cancel does not double-release

**9. Memory-soak footprint watchdog**

- **Where:** Instant `Sources/ScribeSharedAppCore/MemorySoakFootprintWatchdog.swift`
- **Missing from:** SQLite Data, Couchbase Lite
- **Does:** Kill/fail a soak when RSS exceeds absolute or growth megabyte limits

**10. Debug Instant account override**

- **Where:** Instant `ScribeDebugInstantAccount.swift` / `ScribeDebugInstantAccountCredential.swift`
- **Missing from:** SQLite Data, Couchbase Lite
- **Does:** Point a build at a debug Instant account (also a JSON file under `~/Documents/Scribe`)

**11. Instant realtime engine (product door)**

- **Where:** Instant `ScribeInstantStore` / `ScribeInstantBootstrap` / Instant client `transact` + `@Fetch*`
- **Missing from:** SQLite Data (by design; CloudKit + SQLiteData), Couchbase Lite
- **Does:** Cross-device Instant sync. SQLite is the fallback lane. Couchbase has Sync Gateway, not Instant.

### In SQLite Data, missing from Instant and Couchbase Lite

**12. Cross-device playable WAV prefix + CloudKit dest pull**

- **Where:** SQLite `ScribePlayableAudioWAV.swift`, `ProgressiveWAVWriter.swift`, `ScribeSQLiteDataSchema` fetch/send loop
- **Missing from:** Instant, Couchbase Lite
- **Does:** Persist a playable prefix, grow by stream steps, dest `fetchChanges` every **3s**, **10s** user playable ceiling, **5s** send/fetch timeouts

**13. AVAudio tap-remove crash guard**

- **Where:** SQLite `Sources/AudioEngineTapSafety` (`ScribeRemoveInputTapIfPresent`, #147)
- **Missing from:** Instant, Couchbase Lite
- **Does:** Swallow `removeTapOnBus` after AirPods/route change already tore the tap down

**14. Grok listener LaunchAgent**

- **Where:** SQLite `scripts/scribe-grok-listener/` (`com.knophy.scribe-grok-listener`, #216)
- **Missing from:** Instant, Couchbase Lite
- **Does:** Watch local `SQLiteData.db` and start Grok on new `scribeRecordings` rows

**15. Agent-control launch identity (SQLite)**

- **Where:** SQLite `ScribeAgentControlLaunch.swift`
- **Missing from:** Instant (no this file), Couchbase Lite
- **Does:** Stamp diagnostics collector + device identity before the root store exists

**16. SQLite CloudKit mirror / dest agent room**

- **Where:** SQLite `ScribeSQLiteCloudKitMirror.swift`, `ScribeSQLiteDataAgentRoom.swift`
- **Missing from:** Instant, Couchbase Lite
- **Does:** CloudKit-backed recording rows and a SQLite-shaped agent room

**17. `SharedRecordingSnapshotClient` still linked**

- **Where:** SQLite `SharedRecordingSnapshotClient` + Live
- **Missing from Instant as a module** (AGENTS.md forbids it as the Instant door; Instant deleted the package)
- **Does:** Second write client (`save`/`delete` Recording). Instant law: do not use this.

### In Couchbase Lite mini Scribe only (not in Instant or SQLite product)

**18. CouchbaseData `@Fetch*` / Sync Gateway replicator**

- **Where:** `/Users/laptop/Sync/sync/engines/swift/Sources/CouchbaseData`
- **Missing from:** Instant product, SQLite Data product
- **Does:** SQLiteData-shaped `@FetchAll` / `@FetchOne` / drafts on Couchbase Lite 4.1 + Sync Gateway. Also PowerSync and Ditto benches in the same repo (not Scribe UI).

**19. Couchbase Recipes V3 + Instant-shaped auth**

- **Where:** same repo `Sources/Recipes*`, `src/couchbase/instant-auth.ts` port **16070**
- **Missing from:** Instant + SQLite Scribe products
- **Does:** Recipes catalog, share grants, magic-code auth copied from Instant. Not the Scribe recorder.

### Unconfirmed (named in leftovers, not proven live)

- **`RecordingStateProbe`** — directory listed under `realtime-voice/Sources`, **zero files**. Unconfirmed.
- **`ScribeBuildInfoTool`** — directory under `realtime-voice-ship/Sources`, **zero files**. Unconfirmed.
- **`RealtimeTranscriptionSyncClient`** (ship/bisect) — Instant absorbed this as `ScribeSharedRealtimeTranscriptionSync`. Treat as **ported**, not missing.

---

## CANONICAL THREE

### 1. Instant Swift Data (Scribe product)

- **Path:** `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant`
- **Kind:** git worktree of `technoplato/scribe` (common git dir: `/Users/laptop/Sync/tools/realtime-voice/.git`)
- **Remote:** `https://github.com/technoplato/scribe.git`
- **Branch:** `main` (ahead of `origin/main` by **138** commits)
- **HEAD:** `2793f70` — `Record recording list projection fix`
- **Stack:** InstantDB via Instant Swift Data (`ScribeInstantBootstrap` / `ScribeInstantStore` still present, ADR 0015 / #155 wants the store deleted)
- **README:** this file at `docs/scribe-copies-index.md`
- **Worktrees:** see COMPLETE INVENTORY (same repo as SQLite Data)
- **Library sibling:** `/Users/laptop/Sync/instant-data-swift` — Instant Swift Data **library**, not the app. Branch `autoresearch/2026-08-12-live-put-observation-memory`, HEAD `08d2bd45`, remote `https://github.com/technoplato/instant-data-swift.git`

### 2. SQLite Data (Scribe product)

- **Path:** `/Users/laptop/Sync/tools/scribe-sqlite-data`
- **Kind:** git worktree of the same `technoplato/scribe` repo
- **Remote:** `https://github.com/technoplato/scribe.git`
- **Branch:** `scribe-sqlite-data`
- **HEAD:** `6f2a186` — `Document 75e84d7 in change log.`
- **Dirty:** clean when audited
- **Stack:** Point-Free SQLiteData + CloudKit `SyncEngine`. localDev bundle `com.michaellustig.scribesqlitedata.dev` / `group.com.michaellustig.scribesqlitedata.dev`. Mac host `com.scribe.realtime`.
- **README:** this file at `docs/scribe-copies-index.md`

### 3. Couchbase Lite (named head)

- **Path:** `/Users/laptop/Sync/sync/engines`
- **Kind:** **exploration / bench**, not a `scribe` worktree. Local git repo, **no commits on `main`**, working tree is all untracked.
- **Remote:** none
- **Stack:** Couchbase Lite Swift 4.1 + Sync Gateway 4.1.1; also PowerSync and Ditto benches. Mini Scribe: list + open-segment rewrite. Platforms **macOS 14 + iOS 17 only**.
- **README:** `/Users/laptop/Sync/sync/engines/README.md` + `docs/sqlite-data-parity-inventory.md`
- **Full Scribe on Couchbase Lite:** does not exist on this machine or under `technoplato` on GitHub

---

## COMPLETE INVENTORY

`git worktree list` was run on every live Scribe/Instant git repo. Leftover `.git` files that point at `/Users/michael.lustig/...` are **orphaned** (old username; gitdir missing).

### A. `technoplato/scribe` worktrees (live)

| Path | Kind | Branch / HEAD | Dirty | Distinct |
| --- | --- | --- | --- | --- |
| `/Users/laptop/Sync/tools/realtime-voice` | old checkout; **common git dir** | `codex/multiple-providers` `243cdeb` | untracked `scripts/__pycache__/` | Multiple-provider / search / Neo4j / Cloudflare / Settings |
| `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` | **canonical Instant product** | `main` `2793f70` | clean | Instant-backed Scribe |
| `/Users/laptop/Sync/tools/scribe-sqlite-data` | **canonical SQLite product** | `scribe-sqlite-data` `6f2a186` | clean | SQLiteData + CloudKit fallback |
| `/Users/laptop/Sync/tools/scribe-install-dev-default-ac` | install snapshot | `install/dev-agent-control-default` `909219d` | clean | Agent-control default-on Dev |
| `/Users/laptop/Sync/tools/scribe-ipad-reinstall-clean` | install snapshot | `ipad-reinstall-clean-20260804-160037` `bcc6708` | clean | 2026-08-04 iPad reinstall |
| `/Users/laptop/Sync/tools/scribe-iphone-install-20260807` | install snapshot | `install/iphone-localdev-20260807` `6361bb9` | clean | 2026-08-07 iPhone localDev |
| `/Users/laptop/Sync/worktrees/scribe-plan-swift-audio-capture` | plan worktree | `agent/cursor-grok-4.6/plan-swift-audio-capture` `5a1a5d4` | clean | Plan to extract SwiftAudioCapture (#164) |
| `/Users/laptop/Sync/worktrees/autoresearch-2026-08-07-scribe-list-memory-scribe` | exploration | `autoresearch/2026-08-07-scribe-list-memory-scribe` `5168059` | **dirty** (`FileLogger.swift`, `SignalClassifierTests.swift`) | List-memory soak |
| `/Users/laptop/.treehouse/realtime-voice-sqlite-instant-dc15a1/1/realtime-voice-sqlite-instant` | leftover worktree | detached `fef2a3e` | clean | Treehouse copy; “Merge bounded recording intent memory plan” |

### B. `technoplato/scribe` worktrees registered but **gone from disk** (prunable)

| Path | HEAD / branch |
| --- | --- |
| `/private/tmp/claude-501/.../scribe-clean` | detached `274c20d` |
| `/private/tmp/install-companion-hotword5` | `install-companion-hotword` `165aeea` |
| `/private/tmp/install-companion-status3` | detached `c7d6d7e` |
| `/private/tmp/install-companion-status4` | `install-companion-agent-control` `51eb3a5` |
| `/private/tmp/scribe-install-1.5.3-ipad` | `agent/install-ipad-1.5.3-20260805` `4f4a7b3` |
| `/private/tmp/scribe-install-devices` | detached `909219d` |
| `/private/tmp/scribe-install-fast` | `install/fast-local-instant` `aa784a7` |
| `/private/tmp/scribe-ipad-install-fce413f` | detached `383c73b` |

### C. Orphaned leftover checkouts (`.git` points at `/Users/michael.lustig/...`, worktree broken)

| Path | Kind | Distinct (from `Sources/` on disk) |
| --- | --- | --- |
| `/Users/laptop/Sync/tools/realtime-voice-bisect` | leftover | `RealtimeTranscriptionSyncClient` (later absorbed) |
| `/Users/laptop/Sync/tools/realtime-voice-instant-latency` | leftover | `SpeechActivityClient` |
| `/Users/laptop/Sync/tools/realtime-voice-scribe-shared` | leftover | `SpeechActivityClient`; early Shared app |
| `/Users/laptop/Sync/tools/realtime-voice-scribe-working` | leftover | Smaller feature set (2026-04) |
| `/Users/laptop/Sync/tools/realtime-voice-ship` | leftover | `ScribeBuildInfoTool` dir empty; ship-era Shared app (2026-04) |

### D. Extra full clone (not a worktree of the live git dir)

| Path | Kind | Git | Distinct |
| --- | --- | --- | --- |
| `/Users/laptop/Sync/scribe-install.Lxh2mr/tools/realtime-voice-sqlite-instant` | old clone | own `.git`, origin = the Instant worktree, `main` `dccd3d1` | 2026-07-27 install sandbox |

### E. Instant Swift Data library copies

| Path | Kind | Branch / HEAD | Distinct |
| --- | --- | --- | --- |
| `/Users/laptop/Sync/instant-data-swift` | **canonical library** | `autoresearch/2026-08-12-live-put-observation-memory` `08d2bd45` | Library HEAD (not `main`) |
| `/Users/laptop/Sync/desert` | library worktree | `desert` `425b3a6a` | Desert host-loss experiment |
| `/Users/laptop/Sync/worktrees/autoresearch-2026-08-07-scribe-list-memory-instant` | library worktree | `autoresearch/2026-08-07-scribe-list-memory` `c4847a2e` | **dirty** test file; list-memory soak |
| `/Users/laptop/Sync/scribe-install.Lxh2mr/instant-data-swift` | old clone | `main` `49c583d4` | 2026-07-27 install sandbox |
| `*/.build/.../SourcePackages/checkouts/instant-data-swift` | SPM checkout | detached | Ignore; build artifact |

### F. Couchbase / sync engines

| Path | Kind | Git | Distinct |
| --- | --- | --- | --- |
| `/Users/laptop/Sync/sync/engines` | **named Couchbase Lite head** (mini) | local `main`, **zero commits** | CouchbaseData + mini Scribe + PowerSync/Ditto benches |
| `/Users/laptop/Sync/sync/engines/ios/ScribeSchemaBench` | bench host | inside engines | iOS schema bench |

### G. Credentials, evidence, runtime data (not app source)

| Path | Kind | Distinct |
| --- | --- | --- |
| `/Users/laptop/Sync/scribe-private` | credentials repo | ASC / TestFlight join; `main` `7b80a6f`; `origin/main` gone |
| `/Users/laptop/Sync/scribe-evidence` | evidence dumps | 2026-08-03 broadcast-split + mac-instant-store |
| `/Users/laptop/Documents/Scribe` | live Mac app data | recordings, settings, debug Instant account JSON |
| `/Users/laptop/Documents/ScribeBackups` | runtime backups | 2026-08-01 / 08-02 / 08-04 InstantSwiftData + group container |
| `/Users/laptop/Documents/Codex/2026-08-15/scribe-five-recording-*` | soak evidence | iPad backups / run folders |
| `/Users/laptop/Sync/scribe-install.Lxh2mr/Artifacts` | built apps | Scribe-iPhone.app, Scribe-Watch.app |
| `/Users/laptop/.config/instant-tools/scribe-main.env` | secrets | Instant tools env |
| `/Users/laptop/.config/scribe-asc` | secrets | App Store Connect |

### H. Related, not Scribe product copies

| Path | Why listed |
| --- | --- |
| `/Users/laptop/Sync/SwiftAudioCapture` | Planned extract from Scribe (#164); own repo |
| `/Users/laptop/Development/Personal/Public/old/Transcribe*` | Pre-Scribe Mac apps (2024) |
| `/Users/laptop/Development/Personal/Public/transcriber-react-native` | Earlier transcriber (TCA Transcriber, Expo module) |
| `/Users/laptop/.cursor/worktrees/toolshed/*/apps/transcriber` | toolshed transcriber, not Scribe |

**On-disk Scribe/Instant/Couchbase source trees counted:** 20  
**Ghost git worktrees (registered, disk gone):** 8  
**Orphan leftover product trees:** 5 (included in the 20)

---

## FEATURE MATRIX

Legend: **Y** = present in source; **—** = absent; **P** = partial / different door; **A** = absorbed under another name; **U** = unconfirmed.

| Feature | Instant product | SQLite Data | Couchbase Lite | Other copies | Notes |
| --- | --- | --- | --- | --- | --- |
| Dual speech: Deepgram + Apple Speech Analyzer | Y | Y | — | old realtime-voice + leftovers | Heads: two-case enum only |
| AssemblyAI + Voxtral + private-remote topologies | — | — | — | `realtime-voice` | Spec + SettingsFeature |
| Settings workspace rail | — | — | — | `realtime-voice` | Not Mac settings sheet |
| Transcript / corpus search + Neo4j | — | — | — | `realtime-voice` | Full client + spec |
| Cloudflare tunnel (transcription host) | — | — | — | `realtime-voice` | Distinct from public-sharing cloudflared docs |
| ScribeHostClient pairing | — | — | — | `realtime-voice` | |
| SpeechActivityClient (VAD) | — | — | — | shared + latency leftovers | |
| Instant sync / `@Fetch*` Instant | Y | — | — | install snapshots (older Instant) | SQLite must not grow an Instant façade |
| SQLiteData + CloudKit SyncEngine | — | Y | — | — | Fallback lane |
| Couchbase Lite + Sync Gateway | — | — | Y | engines only | Mini Scribe, not full app |
| Playable WAV prefix + 3s dest pull | — | Y | — | — | 10s ceiling / 5s timeouts |
| AudioEngineTapSafety (#147) | — | Y | — | — | |
| Grok listener LaunchAgent (#216) | — | Y | — | — | |
| RecordingCleanupCoordinator | Y | — | — | — | |
| MemorySoakFootprintWatchdog | Y | — | — | — | |
| Debug Instant account | Y | — | — | `~/Documents/Scribe` JSON | |
| SharedRecordingSnapshotClient | — | Y | — | install snapshots, ship | Instant forbids as Instant door |
| Recording list / chrome / map | Y | Y | P | most copies | Couchbase: list + segment only |
| Attachments / PhotoKit / clipboard images | Y | Y | — | modern worktrees | |
| Progressive media / playback | Y | Y | — | | SQLite has extra prefix rules |
| Watch app + widgets + App Clip + tv / vision hosts | Y | Y | — | modern worktrees | Couchbase: watch/tv abandoned |
| SharePlay transcription | Y | Y | — | | |
| System audio + ReplayKit broadcast | Y | Y | — | | SQLite App Group must be sqlitedata |
| Screen stream / LiveKit / OBS / YouTube | Y | Y | — | | |
| Stream companion + scribe-stream-agent | Y | Y | — | | |
| Agent remote control + diagnostics WS | Y | P | — | | SQLite has extra launch helper |
| Instant issues / instant-tools CLI | Y | Y | — | | Scripts still Instant-shaped on SQLite |
| Public segment sharing | Y | Y | — | | |
| YouTube comment plugin | Y | Y | — | | |
| Onboarding | Y | Y | — | | |
| Location + heart rate | Y | Y | — | | |
| Passive watcher / watched directory | Y | Y | — | old Settings Files section is different | |
| Press Pad mini-app | Y | Y | — | | |
| Open-segment CLI / diagnostics mini-apps | Y | Y | P | Couchbase: transcription CLI only | |
| Health monitor | Y | Y | — | | |
| TestFlight + localDev lanes | Y | Y | — | | Different bundle ids per lane |
| Feature mini-apps program (#164) | Y (docs + some hosts) | Y (docs) | — | plan-swift-audio-capture | Stream harness proposed, not a full extra app |
| RealtimeTranscriptionSyncClient module | A | A | — | ship, bisect | Now `ScribeSharedRealtimeTranscriptionSync` |
| RecordingStateProbe | U | U | — | `realtime-voice` empty dir | |
| ScribeBuildInfoTool | U | U | — | ship empty dir | |
| PowerSync / Ditto benches | — | — | Y (same engines repo) | | Not Scribe UI |
| Couchbase Recipes + share/auth | — | — | Y | | Not Scribe UI |

---

## SPREAD / ORPHANS

**→ Full Couchbase Scribe never got created.** Only `/Users/laptop/Sync/sync/engines`.

**→ `realtime-voice` on `codex/multiple-providers` is the feature attic.** Search, Neo4j, AssemblyAI/Voxtral, Settings workspace, Cloudflare host, ScribeHostClient live only there.

**→ Five leftover trees still occupy `tools/` with broken gitdirs** (`realtime-voice-{bisect,instant-latency,scribe-shared,scribe-working,ship}`). Source is readable; `git` is not.

**→ Eight `/private/tmp/scribe-install-*` worktrees are registered and prunable.** Disk is gone; `git worktree prune` would drop them (not done).

**→ Treehouse + Lxh2mr + three install worktrees** are extra Instant-era snapshots. Distinct only by age / install branch.

**→ Autoresearch list-memory worktrees are dirty** (Scribe + Instant library).

**→ Instant library HEAD is not `main`.** It sits on an autoresearch branch. `desert` is a second library experiment.

**→ `scribe-sqlite-data` AGENTS.md still opens with Instant I/O law** (copied from Instant). Agents can mis-apply Instant-only rules on the SQLite lane.

**→ Ancestors** under `Development/Personal/Public/old/Transcribe*` and `transcriber-react-native` are pre-Scribe. Not copies of this product.

**→ `SwiftAudioCapture`** is the planned sibling extract, own GitHub repo.

**→ Runtime data** in `~/Documents/Scribe` and `ScribeBackups` can look like more projects. They are not.

---

## WHERE THE INDEX LIVES

**Canonical:** `/Users/laptop/Sync/tools/docs/scribe-copies-index.md`

Copies of this file:

- `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/docs/scribe-copies-index.md`
- `/Users/laptop/Sync/tools/scribe-sqlite-data/docs/scribe-copies-index.md`
- `/Users/laptop/Sync/sync/engines/docs/scribe-copies-index.md`
- `/Users/laptop/Sync/instant-data-swift/docs/scribe-copies-index.md`

README pointers:

- Instant product `README.md`
- SQLite Data `README.md`
- Couchbase engines `README.md`
- Instant Swift Data library `README.md`

Agent pointers:

- Instant + SQLite `AGENTS.md` (and `CLAUDE.md` symlinks)
- Instant library `AGENTS.md`
- `$scribe-sync` + `references/worktrees-and-mapping.md`
- `$scribe-instant-sqlite-sync` redirect
- `$scribe-install` (Instant + SQLite skill copies)
- `$scribe-issue-tracker` (home, Instant repo, SQLite repo, Gemini)
- `$scribe-feedback-intake` (home, Instant repo, SQLite repo)
- `$scribe-agent-control`
- `$scribe-e2e-log-observer`
- `$scribe-active-transcript`
- `$sqlite-data-log-observer`
- `$instant-data` (library skill)
- `.cursor/rules/scribe-copies-index.mdc` in tools workspace, Instant product, SQLite Data, Instant library, Couchbase engines

---

## SEARCH GAPS

Searched: `/Users/laptop/Sync`, `/Users/laptop/Sync/tools`, `/Users/laptop/Sync/worktrees`, `/Users/laptop/.treehouse`, `/Users/laptop/Documents`, `/Users/laptop/Desktop`, `/Users/laptop/Downloads`, `/Users/laptop/Development` (via find hits), `/Users/laptop/.cursor/worktrees`, `/tmp` named scribe installs, `gh repo list technoplato`, `git worktree list` on every live Scribe/Instant repo, `find` under `$HOME` with prunes.

Not searched / incomplete:

- **`~/Library`** (DerivedData, Containers, Caches). Runtime containers exist; not treated as source.
- **`~/.Trash`**, Time Machine, other disks (only **Macintosh HD** is mounted)
- **`node_modules` / `.build` / `DerivedData` / `SourcePackages`** (ignored on purpose)
- **Spotlight `mdfind`** returned empty (index off or privacy)
- Home `find` was **capped at 400** and filled with false `*transcribe*` hits in editor extensions
- **`pi:karp-wiki`** broken symlink skipped
- **iCloud Drive** only if it lives under Documents (ScribeBackups found there)
- Did not clone or fetch GitHub `technoplato/instant-swift-data` (older name; local library is `instant-data-swift`)

If a copy lives only inside Library Containers or an unmounted volume, it is not in this index.
