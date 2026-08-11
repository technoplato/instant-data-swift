# ADR 0016 — Transcription example (Instant-first, multi-host)

## What this ADR is

**Product:** a teachable multi-host app named **Transcription** in the
`instant-data-swift` monorepo.

**Problem it answers:** Can we model recordings + live transcript writes +
dual-client observe with Instant Swift Data **without** Scribe’s full media
stack — and is Scribe’s shape doomed or just under-documented?

**Not this ADR:** Scribe product work, ADR 0015 library ergonomics (related
but separate), books/library domain, recipes UI.

| Link | Local | GitHub |
| --- | --- | --- |
| Domain schema | `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/transcription.md` | https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/transcription.md |
| Global types | `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/global.md` | https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/global.md |
| Schema catalog | `/Users/laptop/Sync/skills/domain-as-tree/references/schemas/CATALOG.md` | https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/CATALOG.md |
| This ADR folder | `docs/adr/0016-transcription-example-instant-first/` | https://github.com/technoplato/instant-data-swift/tree/main/docs/adr/0016-transcription-example-instant-first |
| Q&A log | [`qanda.md`](./qanda.md) | https://github.com/technoplato/instant-data-swift/blob/main/docs/adr/0016-transcription-example-instant-first/qanda.md |
| **Agent handoff** | [`HANDOFF.md`](./HANDOFF.md) | (local; commit with ADR) |
| **Implementation plan** | [`plan.md`](./plan.md) | https://github.com/technoplato/instant-data-swift/blob/main/docs/adr/0016-transcription-example-instant-first/plan.md |
| App tree | [`overviews/04-uri-tree.md`](./overviews/04-uri-tree.md) | |
| Findings | [`findings.md`](./findings.md) | https://github.com/technoplato/instant-data-swift/blob/main/docs/adr/0016-transcription-example-instant-first/findings.md |
| Scribe (stress case) | `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant` | (private app; local checkout) |
| Process | `$adr-decision-qanda` + `$domain-as-tree` (PISS) | skill: https://github.com/technoplato/skills/tree/master/domain-as-tree |

- **Status:** Decisions locked  
- **Date opened:** 2026-08-10  
- **Decisions locked:** 2026-08-11  
- **Instant issue:** [#193](https://issues.knophy.com/issues/193)  
  “Build Transcription multi-host Instant example (ADR 0016)”  
- **Related ADRs:** 0001 (app/sync boundary), 0014 (entity lifecycle), 0015
  (ergonomics / open-segment); toolshed SyncUps stopwatch proxy  
- **Related issues:** #155 (ergonomics), #186 (TCA recipes later)

## One-line goal

Build a **small, line-by-line-readable** Instant Swift Data example:
shared **Transcription** core, simulated speech, list / active recording /
playback, dual-client network observation. Hosts: CLI, TUI, Mac, iOS/iPad.
Later: TCA 1 and TCA 2 consumers. No real mic in v1.

## Domain shape (schema interview — see skill file)

```text
recording 1 ──* transcription 1 ──* segment
segment.body = speech (words) | event (clipboard, …)
segment 1 ──* response (parent = root | reply)
```
`*` = zero or many.


Canonical field lists: skill `transcription.md`. This ADR must not drift a
second full schema.

## Locked decisions (see `qanda.md` Q01–Q25)

| ID | Decision |
| --- | --- |
| Q01 | Monorepo **Transcription** core + multi-host; no `V3` suffix |
| Q02 | Archetype + simulated speech + rate slider; DEV debug always expanded |
| Q03 | Words as typed array on segment; derived text/times from words |
| Q04 | Recording is list identity; stop is message → finished |
| Q04b | Extract Recipes debug panel into its own SPM module |
| Q05–Q08 | Floating toolbar; schema skill; responses; segment body ADT |
| Q09–Q18 | App tree; mode leaves (paused dual-track reviewed) |
| Q14–Q17 | Kill process bag; prefs in schema; `timeline(recordingId)`; flat mode names |
| Q19–Q21 | Active mode leaves accepted |
| Q22–Q24 | Idle mode leaves; public mutate **`recording.create`** only |
| Q25 | **Program** navigation stack (Swift Navigation style); `goBack` pops |

Full mode tree: `overviews/04-uri-tree.md`. Execute: `plan.md` + #193.

## Non-goals (initial)

- Real microphone / speech-recognition dependencies  
- Full Scribe media pipeline, widgets, Live Activities (later)  
- Deleting VoiceTrail / SyncUps / Recipes  
- Shipping as the Scribe product  

## Interview process

One question at a time. Answers in `qanda.md` first.

| Phase | Step | Home |
| --- | --- | --- |
| A | Archetype | Q02 · `overviews/00-archetype.md` |
| B | Schema | skill `transcription.md` · Q06 · `overviews/01-schema.md` (pointer) |
| C | Session / floating toolbar | Q05 · `overviews/03-session-mode-floating-toolbar.md` |
| D+ | URI tree, messages, contracts, frames | overviews (TBD) |
| Z | Plan + Instant issue criteria | **done** — `plan.md` + #193 |

Schema vs session stay separate. Dots = URI paths or nested types — not
session fields smuggled onto entities.

## Package shape (intent — not built)

```text
Sources/
  Transcription/           # core
  TranscriptionCLI/
  TranscriptionTUI/
  TranscriptionMac/
  TranscriptioniOS/
Examples/Transcription/
```

## Upstream / prior art

| Concern | Path |
| --- | --- |
| Instant library | this repo |
| Scribe full schema | `realtime-voice-sqlite-instant/instant.schema.ts` |
| Open-segment recipe | `docs/adr/0015-…/open-segment-write-recipe.md` |
| Stopwatch FAB proxy | toolshed plans / missing TCA submodule pin |
| PISS skill | `/Users/laptop/Sync/skills/domain-as-tree` |
