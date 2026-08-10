# ADR 0016 — Findings (inventory)

Recorded 2026-08-10 while opening the interview. Not decisions.

## User intent (verbatim / paraphrased)

- Start small; user will read every line of code.
- New **example** named **Transcription** (not a recipe surface; **no V3 suffix**).
- **Instant first** — eliminate TCA as a bottleneck for examining the Instant
  API; later consume from TCA 1 and TCA 2.
- Shared **core** with hosts: **CLI**, **TUI** (said "2e" — treated as TUI until
  corrected), **Mac app**, **iOS/iPad app**.
- Domain: recordings list, recording row, playback screen, recording screen.
- Create recording → active until stop/pause; stop then create new behaves like
  the stopwatch "favorite" / active lane (toolshed **proxy domain modeling**).
- **Simulated** audio / transcript feed (rate controllable); no real recording
  dependencies.
- **Two windows** that sync over the network; prove writes observe on peers.
- Shape transcript object from a **simplified consolidated view** of Scribe
  (`realtime-voice-sqlite-instant`), not the full production graph.
- Interview uses **DomainAsTree** inside ADR 0016; user will feedback domain
  history and wants the Q&A process adapted into ADR design of the skill.
- Diagnostic: is current Instant/Scribe modeling doomed, or fixable?
- `/pfw-spm` for SPM packaging; `/adr-decision-qanda` + `/domain-as-tree` before
  large implementation.

## Skills hygiene (done this session)

| Item | Result |
| --- | --- |
| RS-PFW skills | Canonical tree moved to `/Users/laptop/Sync/skills/archived/rs-pfw/` |
| Discovery | Removed `/Users/laptop/.agents/skills/rs-pfw-*` symlinks |
| Git | skills repo commit `33f8e0b` — archive only; no delete of content |
| PFW skills | Still active: `/Users/laptop/Sync/skills/pfw/*` → `.agents` / `.claude` / `.codex` |
| Note | Skills text still points at `tca-rust-port` crate paths; they are **not** yet copied into the Rust port repo itself — only archived in the skills repo. Re-enable later by restoring discovery links. |

## Prior art: SyncUps stopwatch proxy

User-quoted product string (Live Activity probe): *Requires a favorite
stopwatch. Updates the title word-by-word to test if Live Activity receives
updates.*

Located via GitHub code search / toolshed history (not a stock Point-Free demo):

| Artifact | Location |
| --- | --- |
| Domain mapping plan | `technoplato/toolshed` `.cursor/plans/proxy_domain_modeling_1485166e.plan.md` |
| Widgets / Live Activities plan | `technoplato/toolshed` `.cursor/plans/widgets_&_live_activities_e4f6a3d8.plan.md` |
| SpecStory sessions (Dec 2025) | toolshed `.specstory/history/*stopwatch*` / floating-controls |
| Intended code home | `toolshed/references/swift-composable-architecture/Examples/SyncUps/` — files such as `FloatingStopwatchControls.swift`, `Stopwatch.swift` |
| Submodule pin (Live Activities) | toolshed commit `5d6e6d6` pinned TCA submodule `be0fe599…` — **that commit is not present** in the local submodule checkout on this machine (submodule currently incomplete; only `Examples/TicTacToe` checked out) |
| Stock SyncUps (meetings, not stopwatches) | `/Users/laptop/Development/learning/pointfree/swift-composable-architecture/Examples/SyncUps` |
| Instant SyncUps port (meeting recorder + speech client, not FAB stopwatch) | `Sources/SyncUpsV3App/` |

### Domain mapping (from toolshed plan — keep as product metaphor)

| Stopwatch | Transcription |
| --- | --- |
| Favorite stopwatch | Active recording / transcription |
| Non-favorite running | Playback of a previous recording |
| Stopwatch detail | Recording detail |
| Floating controls / FAB | Global create + control bar |
| Idle FAB | Create new recording (becomes favorite/active) |

Constraints from that exploration (may simplify for v1):

1. At most two "active" lanes: favorite (record) + one non-favorite (playback)
2. Starting non-favorite pauses other non-favorites
3. Favorite keeps running during local playback

## Prior art: Instant examples in this package

| Example | What it covers | Fit for Transcription |
| --- | --- | --- |
| `VoiceTrailV3App` | Auth + recordings list/capture/playback tabs; capture-shaped entities | Closest screen inventory; heavier than "start small" |
| `SyncUpsV3App` | Meetings, attendees, speech-client meeting transcript | Stopwatch metaphor source was a **fork** of SyncUps UI, not this Instant port |
| `RecipesV3App` | Live multi-platform demo harness | Boot/env patterns only |
| Scribe | Full product schema (`recordingSegments`, `wordsJSON`, activity ADT, media) | Canonical domain truth; **too large** to paste wholesale into a learnable example |

## Scribe shape to simplify (candidate minimum)

From Scribe `instant.schema.ts` + ADR 0015 open-segment recipe:

- **Recording** — id, title, state/activity, timestamps, duration
- **Recording segment** — id, recording ref, text, `wordsJSON`, `isFinal`, order/time
- **Activity ADT** — active/playback/idle with Instant client id (optional for v1 dual-window)
- **Write contract** — `transact`/`save` = local + outbox only; never await server
- **Simulated speech** — clock-driven token stream → open-segment upserts (replace real `SpeechClient`)

Explicitly out of first cut unless Q&A reopens: media files, shares, diarization,
full auth providers matrix, widgets, Live Activities.

## Existing package layout (for SPM decisions)

- Monorepo SPM: `Package.swift` products for `*V3App` libraries + `*V3Executable` + `Examples/*` XcodeGen projects
- Platforms today: iOS 16+, macOS 14+, …
- Dual-window + network proof strongly suggests **macOS multi-window** or two processes sharing one Instant app id

## Debug panel reuse (Recipes) → own SPM module

| Piece | Path today |
| --- | --- |
| Floating panel | `Sources/RecipesV3App/RecipesDebugPanel.swift` |
| Metrics + log ring | `Sources/RecipesV3App/RecipesDebugSupport.swift` |

**Decided (Q04b):** Extract into a dedicated SPM module (name TBD). Transcription
and Recipes both depend on it. Product rule: **DEV = always show expanded**;
no user/env flag to turn on.

## Interview discipline (user request)

ADR Q&A must **push back** when answers are nonsensical or incomplete — do not
rubber-stamp. Example applied in Q04: `stopped` is not a state; missing
`finished` leaf; “recording new” is a create message not a phase.

## Screens API inventory

`screens/v3/` (recordings-list, recording, playback, preferences, auth-login)
— designed around desired Instant API; closest inventory after VoiceTrail.

## PISS CLI (show a screen)

**PISS** = Platonic Ideal Software **Specification** (not “Platonic Ideal Software”).

Live code (folder still named `domain-as-tree-pis` / `lib/pis` until a code rename):

| Piece | Path |
| --- | --- |
| CLI runner | `/Users/laptop/Development/brainstorming/ideas/domain-as-tree-pis/source/src/lib/pis/cli.ts` |
| Frames / nodes | `…/source/src/lib/pis/registry.ts` (+ `domains/tea.ts`, `domains/counter.ts`) |
| In-app panel | `cd …/source && pnpm dev` → often `:8080` / `:8090` |
| Terminal | `pnpm pis:tui` |
| Dump | `pnpm pis:dump` |

```text
show <uri>              # ASCII frame + summary + messages + edges
send <uri> <message>
list | domains
help
```

Bare URI → `show`. Leaf review after schema + URI tree.

### URIs already registered (~41)

| Domain | URIs |
| --- | --- |
| **recorder** | `recorder`, `recorder.recordings.list.empty`, `recorder.recordings.list.populated`, `recorder.recording.active`, `recorder.recording.paused`, `recorder.playback`, `recorder.settings` |
| **bank** | `bank`, `bank.dashboard`, `bank.deposit.capture`, `bank.deposit.review`, `bank.transfer` |
| **timer** | `timer`, `timer.idle`, `timer.running`, `timer.paused`, `timer.finished` |
| **calculator** | `calculator`, `calculator.display` |
| **tea** | `tea`, `tea.home`, `tea.invite`, `tea.flattery`, `tea.credentials`, `tea.darjeeling`, `tea.field.brew`, `tea.perfect`, `tea.offer`, `tea.dissonance`, `tea.hollow.win`, `tea.goodday` |
| **counter(s)** | `counter`, `counter.ready`, `counters`, `counters.list.empty`, `counters.list.populated`, `counters.detail`, `counters.delete.confirm` |
| **self** | `piss`, `piss.cli`, `piss.settings` |

**Transcription** domain URIs: not registered yet (this ADR).

### Example: `show recorder.recordings.list.empty`

Node lives in `registry.ts`. Observe: `recordings: []`. Send: start recording →
`recorder.recording.active`.

```text
┌────────────────────────────┐
│  ·  ·  ·          9:41  ⚡ │
│                            │
│     No recordings yet      │
│   Capture sound. See words │
│   attributed in real time. │
│   ┌────────────────────┐   │
│   │  Start Recording   │   │
│   └────────────────────┘   │
│  ○ list   ● rec   ⚙ set    │
└────────────────────────────┘
```

### Example: `show recorder.recording.active`

```text
┌────────────────────────────┐
│  ·  ·  ·          9:41  ⚡ │
│  ● REC            02:14    │
│  Alice                     │
│  “the phase transition     │
│   happens when…”           │
│  Bob                       │
│  “right, and the entropy…” │
│   ┌──────┐    ┌──────┐     │
│   │Pause │    │ Stop │     │
│   └──────┘    └──────┘     │
│  ○ list   ● rec   ⚙ set    │
└────────────────────────────┘
```

Messages include `pause button pressed` → `recorder.recording.paused`,
`stop button pressed` → list populated.

## Open risks / blockers for later steps

1. Toolshed stopwatch **source tree missing locally** — need restore from submodule pin, SpecStory, or re-implement from plan ASCII.
2. Whether Transcription reuses VoiceTrail namespaces or gets a clean schema.
3. Parent Instant issue not created yet.
4. Recipes debug panel is owned by RecipesV3App — share/extract for Transcription hosts.
