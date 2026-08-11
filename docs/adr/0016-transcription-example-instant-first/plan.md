# ADR 0016 — Implementation plan

- **Status:** Ready to execute (decisions locked 2026-08-11)
- **Parent issue:** [#193](https://issues.knophy.com/issues/193)
- **Related:** #155 (ergonomics / open-segment), #186 (TCA recipes later), ADR 0001, 0014, 0015
- **Process:** Commits on `main` only. Each step = coherent commit(s) + Instant workLog.
- **Do not start** until criteria for that step are claimed on #193.

## Parent outcome

Ship a **small, line-by-line-readable** Instant Swift Data example named
**Transcription**: shared core, simulated speech, nine flat mode leaves,
program navigation stack, multi-host proof (CLI first, then TUI / Mac / iOS).

Not Scribe product work. Not real mic in v1.

## Prior art

| Concern | Path |
| --- | --- |
| Instant library | this repo (`Sources/`, tests) |
| Write contract | ADR 0001 / Agents.md — `transact` local + outbox only |
| Open-segment writes | ADR 0015 `open-segment-write-recipe.md`; Scribe stress prior art |
| Schema skill | `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md` |
| App tree (SoR) | `overviews/04-uri-tree.md` |
| Decisions | `qanda.md` (Q01–Q25) |
| Package patterns | `VoiceTrailV3App`, `RecipesV3App`, `Package.swift` |
| Navigation | Swift Navigation–style stack in the **program** (Q25) |

## Done means (parent #193)

See issue `successCriteria`. Plan step ids map 1:1 to criterion ids below.

## Work items

| ID | Step | Repo | Depends | Criterion id | Tests / evidence |
| --- | --- | --- | --- | --- | --- |
| T0 | Fold decided schema into Instant entities + permissions notes (`recording`, `transcription`, `segment`, `response`, `preference`) from skill file — no second schema | instant-data-swift | — | `issue-193-T0-schema` | Entity types compile; fields match skill; architecture note for wall+relative times |
| T1 | SPM **Transcription** core target (no host UI yet): mutations `recording.create`, finish fields, `segment.upsertSpeech` + `when isFinal` | instant-data-swift | T0 | `issue-193-T1-core-mutations` | Focused tests: create → capture ids; finish explicit fields; open-segment upsert + finalize |
| T2 | Simulated speech dependency (`speechRecognized` only; no mic) + speech rate prefs | instant-data-swift | T1 | `issue-193-T2-sim-speech` | Clock-driven words; rate changes stream; offline create still succeeds |
| T3 | Program model: `screen` stack + nine flat `mode` leaves + handle args; `goBack` → `navigation.previous` | instant-data-swift | T1 | `issue-193-T3-program-mode` | Unit: mode transitions table; stack push/pop; A+A capture/playback ids legal |
| T4 | **CLI host** — library list, start/stop/pause, playback, timeline print, dual-process optional | instant-data-swift | T2, T3 | `issue-193-T4-cli` | Executable runs; scripted happy path; dual CLI observe when online credentials available |
| T5 | Extract Recipes debug panel to shared SPM module (Q04b); Transcription DEV always expanded | instant-data-swift | — | `issue-193-T5-debug-module` | Module builds; Recipes still links; Transcription imports |
| T6 | **TUI host** — same program, terminal UI | instant-data-swift | T3, T4 | `issue-193-T6-tui` | Build + smoke session |
| T7 | **Mac app** — multi-window dual-client network observe proof | instant-data-swift | T3, T4 | `issue-193-T7-mac-dual` | Two windows / two clients; write on A appears on B |
| T8 | **iOS / iPad** host shell | instant-data-swift | T3, T4 | `issue-193-T8-ios` | Build + simulator smoke |
| T9 | Docs pass: README example path, Point-Free–quality public comments (what `await` waits for), kill `createLinked` language everywhere | instant-data-swift | T4 | `issue-193-T9-docs` | Doc review; no createLinked in tree |

## Execution order

```text
T0 → T1 → T2 → T3 → T4     (core + CLI first — teachable path)
T5 parallel after T0       (debug module; do not block CLI)
T6, T7, T8 after T4        (hosts share core + program)
T9 with or just after T4
```

**v1 bar:** T0–T4 + T9 prove the product. T5–T8 complete multi-host claim.

## Out of scope (this plan)

- Real microphone / speech-recognition SDKs
- Scribe media pipeline, widgets, Live Activities
- TCA 1 / TCA 2 consumers (later; relate #186)
- Deleting VoiceTrail / SyncUps / Recipes
- Library ergonomics work owned by #155 (consume when ready; do not re-scope)

## Locked decisions agents must not re-litigate

See `HANDOFF.md` and `qanda.md`. Short list:

- App roots: `screen` + `mode` only; prefs in **schema**
- Nine **flat** mode leaves; handles as associated values
- `startRecording` → `recording.create` (not `createLinked`)
- `speechRecognized` + `when isFinal` open-segment path
- `goBack` = program stack pop (`navigation.previous`)
- `transact` never waits for server

## Cold-agent resume recipe

```bash
cd /Users/laptop/Sync/tools/realtime-voice-sqlite-instant
scripts/with-instant-tools-credentials node scripts/instant-tools.mjs query-issue 193
# Read workLog + successCriteria — first unsatisfied issue-193-T*
# Read:
#   /Users/laptop/Sync/instant-data-swift/docs/adr/0016-transcription-example-instant-first/plan.md
#   overviews/04-uri-tree.md
#   qanda.md only if a decision is unclear
# Implement that step on main; append workLog with full commit SHA; re-query
```

## Per-step workLog template

```text
state: claimed | in-progress | landed | blocked | verified
summary: model=grok-4.5 plan step T1 — what landed — tests — next step id
commitSha: <full sha when landed>
agentId: <stable agent id>
```
