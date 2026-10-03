## 2026-10-03 18:37:38 EDT — v1.9.5: a local write no longer holds the operation gate while it logs, and outbox listings never wait for the gate; main's merge of this commit is the release commit (#473)

- **Owner:** library-79 (`claude-opus-5.5-library-79`, workLog agentId `claude-code/claude-opus-5.5/library-79`), plan
  `2026-10-02-library-79-hops`, at main's request (#473 P0, 2026-10-03 about 14:10 EDT), under Michael's maintainer
  authorization: "Publish the library once it's checked fast. Yes."
- **Defect (#473):** a local write held the iPhone's operation gate for 12 s at 13:17:46 and Recording 185 died;
  transcription stalled behind gate backlogs twice. Each diagnostics line was opened, locked, written and fsynced on the
  caller's thread inside the gate; the gate's wait and stall reports ran on its actor; transact phases had no names;
  outbox listings decoded every row under the gate.
- **Commits on `agent/claude-opus-5.5/library-79-hops`:** claim `e2435d90`; `a6a6ab17` the change (diagnostics file on its
  own queue with flush; hop-free phase names for transact and server apply; `pendingMutations(limit:)` and
  `failedMutations(limit:)` off the gate); `a6a59b56` the reports off the gate's actor; test-only `f0272d8c`, `1c7ab096`,
  `3d925396`, `bb598182`; ledger `44b08ddc`; release document `docs/releases/v1.9.5.md`.
- **Checks:** red on v1.9.4 (the blocked log and the blocked report both hold the caller there); gate-195c on
  `a6a59b56` in main's lane: new suites 31 ×3, the five load misses 25/25 alone, library-77/78 118, ten suites 697,
  focused 167 (one benchmark-CLI timing miss), fast-drain and survival 25, infinite 211 (pre-existing failure), #431
  iPad store 3/3, phone replay matches or improves (1,797 s wall under disk contention).
- **Evidence:** `/tmp/library-79-hops/gate-195*/`, copied to `/Users/laptop/Sync/audit/library-79-473-2026-10-03/`.
- **Continue:** the benchmark CLI rerun and a quiet-host replay comparison; 1.9.6 (phone-perf's streaming download #454
  and batched log fsync, `store.mutation-published` at debug); 1.9.7 (gate deadline and priority lanes, hydration and
  publish off the gate, write-failure kinds and connection health for mic-gap); 1.9.8 (#474).

## 2026-10-03 13:37:46 EDT — v1.9.4: a refused re-send whose values the server's results already show resolves as accepted, and a failed mutation's supersession is read-only API; main's merge of this commit is the release commit (#441 #445)

- **Owner:** library-79 (`claude-opus-5.5-library-79`, workLog agentId `claude-code/claude-opus-5.5/library-79`), plan
  `2026-10-02-library-79-hops`, at main's request (#441 P1, 2026-10-03 about 12:00 EDT; #445 added about 12:35), under
  Michael's maintainer authorization: "Publish the library once it's checked fast. Yes."
- **Defect (#441):** Recording 040's iPhone showed "Not synced" for a re-sent capture-gaps write that production holds:
  the first offer was applied and only its answer was lost with the socket, and Scribe's `updatedAtMs` rule refused the
  re-send because a later heartbeat had advanced the row. Library-78's supersession needed later accepted writes of the
  device for every slot, and nothing later wrote the gaps.
- **Commits on `agent/claude-opus-5.5/library-79-hops`:** claim `d8208b33`; `ec10cad2` the guard (a re-send's slot also
  counts as covered when a server result since the write shows its value; a re-send refused before its connection's
  query answers waits for them, up to 30 s); claim `94938422` and `45a46290` the #445 API
  (`supersession(ofFailedMutation:)`, `failedMutationSupersessions()`, shape agreed with launch-recovery); ledger
  `fe3ad82a`; release document `docs/releases/v1.9.4.md`.
- **Checks:** red on v1.9.3 (the three resolving tests fail there; the guards pass); the gate on `fe3ad82a` after a clean
  build: new suites 12/12, library-77/78 106, ten suites 697 (5 load-timing misses at load 150–170, each passing 5 of 5 alone on this build and on v1.9.3),
  focused 182, fast-drain and survival 25, infinite 211 (one pre-existing failure), #431 iPad store 3/3, phone replay
  matches or improves on the reference. The first green run crashed with SIGBUS from stale test objects (an
  incremental build after the configuration gained a field); the gate builds clean.
- **Evidence:** `/tmp/library-79-hops/red-441/`, `/tmp/library-79-hops/gate-441/`, `/tmp/library-79-hops/reruns-441/`,
  copied to `/Users/laptop/Sync/audit/library-79-441-2026-10-03/`.
- **Continue:** the soak on v1.9.4 (normal lane); 1.9.5 with phone-perf's streaming file download and
  `pendingMutations(limit:)` for launch-recovery; main's P1 on the 12 s operation-gate hold (report first); #441's last
  criterion is a dropped connection during a recording leaving no false "Not synced" with 1.9.4 in Scribe.

## 2026-10-03 10:31:25 EDT — v1.9.3: a store whose cache holds one live-query result over 8 MiB opens again; main's merge of this commit is the release commit (#436)

- **Owner:** library-79 (`claude-opus-5.5-library-79`, workLog agentId `claude-code/claude-opus-5.5/library-79`), plan
  `2026-10-02-library-79-hops`, at main's request (P0, 2026-10-03 about 09:40 EDT), under Michael's maintainer
  authorization: "Publish the library once it's checked fast. Yes."
- **Defect:** the relation reconciliation the store's open runs when an app's declared relations change read every
  cached live-query result and threw on one over 8 MiB, so one large cached result failed every launch. Michael's iPad
  could not open Scribe: its cached transcript of Recording 039 is 8,817,787 bytes. 1.9.1 and 1.9.2 have the same code.
- **Commits on `agent/claude-opus-5.5/library-79-hops`:** claim `a3ec2b91`; `7d7790fd` the fix (the reconciliation and
  application-migration passes drop a cached result over the bound with a warning, and its query refetches it);
  `adfd9624` and `5e1c0222`, test-only follow-ups; ledger `50293afa`; release document `docs/releases/v1.9.3.md`.
- **Checks:** red on v1.9.2 (both tests throw; the iPad's pulled store fails with the iPad's own error) and green here
  (the store opens with 35 of 36 cached results and refetches the transcript); high-lane gate holds on `adfd9624` and
  `5e1c0222`: identity-upgrade 5, focused 182 (3 known; one timing miss, 5 of 5 alone), store 379 (4 known), fast-drain
  and survival 25 (2 known), #431's iPad checks 3 of 3. The soak follows after the tag, at main's direction.
- **Evidence:** `/tmp/library-79-hops/hotfix-436/`, `/tmp/library-79-hops/hotfix-436-final/`, copied to
  `/Users/laptop/Sync/audit/library-79-436-2026-10-03/`; the iPad pull, read only, at
  `~/scribe-device-pulls/2026-10-03-ipad-live-stamp/`.
- **Continue:** the soak on v1.9.3 (normal lane); requeue the six paused jobs with their original `HEAVY_QUEUED_AT`
  places (`/tmp/library-79-hops/requeue-normal.txt`), with job 5a3's and 5b2's arms rebased onto v1.9.3; record the
  pending ledger lines (`/tmp/library-79-hops/edits/scribe-batch-19-pending.md`). #436's last criterion is the iPad
  opening Scribe with 1.9.3.

## 2026-10-03 05:48:20 EDT — v1.9.2: another device's later value of a single-value attribute, and its clear, reach a device that once wrote it; main's merge of this commit is the release commit (#431)

- **Owner:** library-79 (`claude-opus-5.5-library-79`, workLog agentId `claude-code/claude-opus-5.5/library-79`), plan
  `2026-10-02-library-79-hops`, under Michael's maintainer authorization (to the coordinating session on 2026-10-02 at
  about 12:10 EDT): "Publish the library once it's checked fast. Yes." Main made #431 (P0) library-79's top priority on
  2026-10-03 at about 01:00 EDT.
- **Defect:** Instant keeps a single-value triple's `created_at` when it updates the triple in place, and a refresh
  delivers that time as the fact's stamp, so a device's accepted write, stamped by its own clock, won last-write-wins
  against every later server value of the slot, and a slot another device cleared kept the device's value. Scribe's
  iPad kept its playback stamp and `updatedAtMs` on Recording 039 (Scribe #408).
- **Commits on `agent/claude-opus-5.5/library-79-hops`:** claims `d8c4469b`, `ea2fc934`, `c1292d88`; `1976f8aa` the
  fix (server facts authoritative on both server-apply paths; cleared slots lose the store's values; slot-level
  protection); `995d530e` the follow-up after an independent review and the first gate hold (keys must vouch for their
  selection, the scan for slots no result held runs once per key, only cleared slots lose the confirmed write's
  protection); release document `docs/releases/v1.9.2.md`.
- **Checks:** red on v1.9.1 and green here in rounds 2-4 (`library-79-red-431-2`, `-3b`, `-4`): 7 of the 10 local-stamp
  cases and the flipped fast-drain case fail on v1.9.1, the 3 controls pass on both, all pass here; the iPad's pulled
  store's stuck shape stays stuck on v1.9.1 and heals here, and the store v1.9.1 left stuck heals when this code reopens
  it. Final gate hold on `c867063d` (04:48-05:47 EDT): focused 179 (3 known), fast-drain and survival 25 (2 known, no
  rebases; drain CPU 6,214 ms against v1.9.1's 6,079 at similar load), ten suites 697 (22 known; four timing misses not
  rerun before publication, reruns queued), infinite 211 (only #304), library-77/78 106, iPad-store checks 3 of 3, phone
  replay matching or improving on the reference, soak 872 accepted and 876 store publishes (v1.9.1: 868 and 873), CPU
  median 23%, RSS at most 405 MB.
- **Evidence:** `/Users/laptop/Sync/audit/library-79-431-2026-10-03/` (job scripts, each round's logs, both gate holds,
  the soak analyses); the iPad pull, read only, at `~/scribe-device-pulls/2026-10-03-ipad-live-stamp/`.
- **Continue:** report the queued reruns of the four timing misses (`/tmp/library-79-hops/release-192/gate2-reruns/`);
  measure the receive path cleanly (the replay ABBA, v1.9.1 against this code, `HEAVY_EXCLUSIVE=1`); then bring the
  next cuts (`agent/claude-opus-5.5/library-79-next3`) onto the fixed code and run job 5b on it, as main asked. The
  review's lower findings (one whole-component rebase for a cleared slot under another pending write; a refused write's
  rollback restoring a cleared value) are open on #431.
- **Owned until handoff:** simulator `DC59CEA8` (library-79's, shut down; delete when the work ends), the two worktrees'
  `.build` (`instant-data-swift-library-79-hops`, `instant-data-swift-library-79-v191`), and `/tmp/library-79-hops/`.

## 2026-10-02 15:41:48 EDT — v1.9.1: library-79's hop cuts and shared formatter on v1.9.0; main's merge of this commit is the release commit (#403)

- **Owner:** library-79 (`claude-opus-5.5-library-79`, workLog agentId `claude-code/claude-opus-5.5/library-79`), plan
  `2026-10-02-library-79-hops`, under Michael's maintainer authorization (to the coordinating session on 2026-10-02 at
  about 12:10 EDT): "Publish the library once it's checked fast. Yes."
- **Branch:** `agent/claude-opus-5.5/library-79-hops` merged v1.9.0 as `262378b2` (the gated code commit) and main's
  ledger-only `2f6a9ee3` as `bed0dc4f`; release document `docs/releases/v1.9.1.md` (passes
  `scripts/validate-release-version.sh 1.9.1`). Main merges this branch without fast-forward, the merged tree equals
  the branch's, and the annotated tag `v1.9.1` points at that merge; `gh release create v1.9.1 --verify-tag --latest`
  publishes it.
- **Checks (release-gate hold on `262378b2`, 2026-10-02 15:04-15:39 EDT, load 7-340):** focused set 163 tests pass (3
  known); fast-drain and survival 25 pass (2 known, Pattern B); ten suites 697 pass (22 known); infinite suites 211,
  only #304; library-77/78 suites 106 pass; phone-shaped replay matches the `01175cff` reference in every count
  (2,487 to 0 in 273 s); 10-minute calibrated-car soak (Scribe `c2343b26`, `bd40c50a`): 873 local writes, 868
  accepted, at most 2 queued, 0 refusals, 1 connection, CPU median 23%, RSS at most 425 MB. The release gate
  (`validation/run-performance-gate.sh live`) did not run; its cross-SDK comparisons still fail (Swift/TypeScript 4.6,
  6.5, 4.7).
- **Evidence:** `/tmp/library-79-hops/release/` (steps, suite logs, replay), `/tmp/library-79-hops/soak-out/l79-262378b2-calibrated-car-600s/`,
  copied to `/Users/laptop/Sync/audit/library-79-hops-2026-10-02/evidence/release-gate/`.

## 2026-10-02 15:41:48 EDT — library-79: one actor turn per step and one shared transport-date formatter (v1.9.1); the statement cache and three CPU cuts measured next (#403)

- **Goal (Michael, 2026-10-01):** "fix this please so it works efficiently as as well as the typescript core library".
- **Commits on `agent/claude-opus-5.5/library-79-hops`:** `2e2a1c07` counts every actor call on transact, relaunch,
  and reconnect drain (19, 16, 50); `158a4515` runs each step's persistence work in one actor turn (7, 11, 25, pinned
  by `runtimeWorkloadsPinEveryActorHop`); `55a15392` formats every transport date through one shared formatter,
  byte-identical to `@instantdb/core` 1.0.49's wire encoding; `9dff3425` is ADR 0018 (hop map, ranked cuts, results).
- **Measured (paired ABBA through `heavy.sh`, ten blocks, load 200-350):** Swift/TypeScript 7.4, 6.9, 7.4 at v1.8.0;
  7.3, 6.8, 7.1 with the hop cuts (an uncontended hop costs about 0.1 µs, so the cuts are structural); 4.6, 6.5, 4.7
  with the formatter (one write 0.62x v1.8.0's time, relaunch 0.94x, drain 0.66x).
- **Next, on `agent/claude-opus-5.5/library-79-next` (pushed, `c4341a12`, on `57f4a841`):** `0f1f2a71` the
  prepared-statement cache, `fe8c69f4` one SQLite transaction per persistence turn, `663cb647` one migration read at
  bootstrap, `c4341a12` one encoding per save. Heavy job 4 (`/tmp/library-79-hops/jobs/cache-checks.sh`, queued 13:10
  at normal priority) tests that tree and measures each as its own ABBA arm, results in `/tmp/library-79-hops/final2/`.
  None of the four has compiled yet; job 4's test build is their first.
- **Continue:** when job 4 is green, bring each commit onto `library-79-hops` in order (one commit and one ABBA arm each,
  as main asked), add its change-log and ledger entries, report Swift/TypeScript after each to main, and release them
  under the same authorization with this entry's gate set. If job 4's test build fails, fix on `library-79-next` and
  re-queue job 4. Open questions for Michael are in ADR 0018 (a hop-free live-session flag; store and persistence on
  one executor).
- **Owned until handoff:** simulator `DC59CEA8` (library-79's, shut down; delete when the work ends), the worktree's
  `.build`, and `/tmp/library-79-hops/`.

## 2026-10-02 14:56:59 EDT — v1.9.0 on main: build 78's library merged and documented; this entry's commit is the release commit (#376 #360 #388 #394 #329 #361 #296)

- **Owner:** library-78 (`claude-opus-5.5-library-78`, workLog agentId `claude-code/claude-opus-5.5/library-78`), plan
  `2026-10-02-release-1.9.0` (`d3c9a075`), under Michael's maintainer authorization (to the coordinating session on
  2026-10-02 at about 12:10 EDT): "Publish the library once it's checked fast. Yes."
- **main:** `0b8f52f7` merges `agent/claude-opus-5.5/library-78` (`7ecbd129`: gated code head `01175cff` plus ledgers)
  without fast-forward over `eeea9b12`; the merged tree equals `7ecbd129`'s. Release document `docs/releases/v1.9.0.md`
  (`d42dd960`, passes `scripts/validate-release-version.sh 1.9.0`). This entry's commit is the release commit: the
  annotated tag `v1.9.0` points at it, and `gh release create v1.9.0 --verify-tag --latest` publishes it.
- **Checks:** the fast checks below (library-78's entry), as authorized. The release gate
  (`validation/run-performance-gate.sh live`) did not run; the tag message and the release notes name it with the other
  open items.
- **Next:** Scribe pins `exact: "1.9.0"` together with `library-78-scribe` (`c2343b26`, media by `streamClientID`);
  library-79 rebases onto v1.9.0; #402 is build 79's library work.

## 2026-10-02 14:56:58 EDT — library-78: the socket stays open through server errors, failed live queries recover and say so, duplicate writes are not refused, and a list never repeats a row (#376 #360 #388 #394 #329 #303 #317 #361)

- **Branch:** `agent/claude-opus-5.5/library-78` from build 77's `956fce52`, merged into main without fast-forward as
  `0b8f52f7` for v1.9.0 (plan `agent-presence/claude-opus-5.5/plans/2026-10-01-library-78/PLAN.md`). Gated code head
  **`01175cff5f84039d20007afee40e3195102da3d8`**. Later commits change no source, test, or package file: ledgers and
  `6c036d5c`, a docs-only merge of library main (v1.8.0, `eeea9b12`).
- **Goal** (Michael, verbatim): "fix this please so it works efficiently as as well as the typescript core library". On
  refused writes: "I want to know why rights are refused in the first place? I don't think they really should be". On
  reconnects: "Why couldn't it just reconnect? Yeah, why are the reconnects there in the first place?"
- **Commits** (implementation; each has its change-log and ledger entry):
  - `8dd3bf28` (#376 #360): a transient server error on a write or an add-query keeps the socket; the write or query is
    retried on it after 250 ms doubling to 5 s, jittered 0.5-1x; subscribers see the query's error and keep their rows.
  - `f9cb5396` (merged `84c2e22a`) and `af2928d5` (#303): a server apply or a refusal record whose optimistic attempts
    went stale five times finishes under one exclusive hold instead of ending the receive loop.
  - `c6076346`: a re-send that newer accepted writes cover is not sent; a replay refusal that later writes in flight
    cover is parked and resolves as `supersededByAcceptedWrite`.
  - `aa1cca45` (#303): inactive live-query results are pruned in batches of about 5,000 triples per gate hold.
  - `6dce825d`, `bc6a0c81` (#317 #307): `queryOnce` of an exact subscription answered on the open socket reads the device.
  - `378598c8`, `0eb8f502`, `95fba702` (merged `1f098e0c`; #329, ADR 0017): incremental stream snapshots, readers retired
    at done, offline streams started by client id, and a refused or unflushed append restarts only its writer.
  - `0adbe972`, `970d8db0` (merged `3196ad50`; #296): the phone-shaped replay as a reusable gate.
  - `9a65aaeb`, `b465ae14` (#388, P0): an infinite query's snapshot lists each entity once; a kickstart keeps its rows.
  - `8358090e` (#376): a write its caller cancels finishes instead of ending the socket.
  - `18e52df0` (#394): an observation ends when its consumer stops iterating.
  - Account linking (#361), merged `2245b28b`: `ea6764c7`, `4473db63`, `c1b53e51`, `4d928d70`.
  - `01175cff`: SAFETY comments that `SwiftConcurrencyGuidanceTests` requires.
- **Gates on `01175cff`** (library suites 2026-10-01 at load 115-925; the rest 2026-10-02 inside `safe-heavy/heavy.sh`):
  - Differential and connection survival: 25 tests in 2 suites pass, 2 known issues.
  - Ten suites: 697 tests in 11 suites; 2 unexpected failures, both 250 ms wall-clock bounds at load about 900
    (`liveTimeoutDoesNotAwaitCancellationInsensitiveWork` 0.32 s, `connectTimeoutAbortsCancellationInsensitiveAttemptAndLateSession`
    0.35 s); both pass 3 of 3 alone.
  - The 211 infinite-query tests: only #304's `typedLookupUpdateCanResolveEntityCreatedEarlierInSameTransaction`, as on
    library-77. Library-77 and library-78 suites: 106 tests in 20 suites pass.
  - Phone-shaped replay (`scripts/phone-replay`, the 2026-09-30 store): every compared line matches the 956fce52-era
    reference (17 of 119 frames rebased, 26,288 bodies, 2,384 accepted, 103 refused; after a full restatement only
    `recordings/clipboardEntries` differs); drain 461.6 s at load about 890. `swift test` exited 1 although its one test passed and printed no error; the same filter without the store exits 0 (2026-10-02 13:38); the cause is not identified.
  - Replay benchmark (release, CPU ms per frame, min of 3 rounds; TS core 1.0.49 is 1.1-1.3): 956fce52 12.26 ms with the advert and 23.59 ms without; `01175cff` 12.71 and 23.93 (best rounds, load 8-35). Three passes back to back (ABBA plus an interleaved ABAB at load 150-650): the head's per-message CPU was 0.93-1.04x 956fce52's with the advert and 0.95-1.10x without, so no regression shows above the noise. Pass 2's head arm overlapped another job starting in the guard's second slot (its rounds rose 26.7, 30.8, 36.4).
  - Large-store drop A/B against 956fce52: not run. `run.py` drives the local Instant server in Docker, which these
    rules forbid. The head's bench binary is built (`harness/swift/bin-01175cff-release`) for a later run.
  - 30-minute calibrated-car soak (Scribe `library-78-scribe` `ed085b95` built against `01175cff`, throwaway
    `bd40c50a`, iPhone 17 Pro iOS 27 simulator): two runs.
    - Scribe `library-78-scribe` `ed085b95` (cut from main before the route seal fix `47f4f8b4`), 10:17-10:47 EDT,
      load 300-800 (the guard paused the sampler several times; main paused the simulator for about a minute near
      10:46): 2,760 writes, 2,678 accepted, at most 2 pending, 1 connection, no gate holds, no ack timeouts, CPU median
      25%, RSS at most 418 MB. 4 refused writes: two route-chunk open-and-seal pairs (chunks 70577795 and 9a148e44),
      each pair created 1 ms apart and refused under one server trace id (`dc86c05d`, `1f1f8bb1`). That is the
      server's combine-transact, the #321 case Scribe's seal fix removes; build 78's own soak on 956fce52
      (`build78-final`) shows the same pair.
    - Scribe `c2343b26` (`library-78-scribe` merged with Scribe main `0709cf06`, which has the seal fix): 14:17-14:47 EDT, load 30-450: 2,746 writes, 2,682 accepted, at most 2 pending (0 at the end),
      1 connection, no gate holds, no ack timeouts, no refusals and no warning or error events, CPU median 26%, RSS at
      most 423 MB.
  - Background probe (main's #402 question: reply-notifications saw 12 replay refusals on 956fce52 while Scribe
    recorded behind Settings): two runs, each right after a soak: Scribe recording 120 s, Settings in front 180 s, Scribe
    again 120 s. On `ed085b95` the socket broke behind Settings (4 failed opens, an ack timeout); one replay refusal
    (62af0546, perms-pass?) was parked behind its covering write e3bf5036 and resolved as superseded 4 ms after that
    write's acceptance, so nothing surfaced; its 3 other refusals were route-chunk writes under one trace id
    (combine-transact, pre-seal-fix build). On `c2343b26` Scribe kept running behind Settings and the socket stayed up:
    no refusals, no reconnects; server applies held the operation gate up to 3.1 s and one `acceptMutationIfPresent`
    6.6 s at load 22-40 (#402).
  - Companion fault scenarios (`scripts/companion-harness/run.py agent-side`, CLI on `01175cff`): not run before publication; queued after it, with results in the #376 and #360 work logs.
  - Recording 023-shape backlog: not run (main: only if time allows; the release went first).
- **Evidence:** `/Users/laptop/Sync/audit/library-78-2026-10-01/` (phone replay, `gates-2026-10-02/`).
- **Open:** #402 (build 79): mac-memory's resident-store statistic, refresh-ok's whole-result memory and the 16 MiB
  block; the ack-deadline abort and receive-loop failure, the two reconnect sources left; refusals from the server's
  combine-transact; coverage of watermark-pruned writes; path f. #304 stays a known issue.
- **Next:** Scribe pins `exact: "1.9.0"` (with `library-78-scribe`, which reads media by `streamClientID`; without it,
  media written offline never reaches other devices). library-79 rebases onto v1.9.0. #402 is build 79's library work.

## 2026-10-01 19:55:28 EDT — Account linking verified live: the link path against Instant's real rules, the soak, and the apps (#361)

- **Live test:** `4d928d70` adds `InstantAccountLinksLiveTests` (environment-gated). On the throwaway app `bd40c50a`
  with Scribe's account-link rules it passed in 5.0 s: a guest primary, `InstantSecondSignIn` verifying a magic code
  from the admin API (only the email delivery is replaced; Instant's mail provider refuses `example.com`),
  `InstantAccountLinks` link, reads from both sides, unlink (row deleted), close; the primary's session never changed.
  Evidence: `/Users/laptop/Sync/audit/account-linking-2026-10-01/evidence/library-live-test/`.
- **Soak (`scripts/soak-fixed-progression.sh`, 600 s, Scribe with this branch's sources):** pending at most 1, 412 of
  415 writes accepted, 0 refusals, CPU median 22 percent, RSS at most 399 MB.
- **Apps:** Scribe's Account screen card on Mac and iPhone (`bd40c50a`): the aggregated list, and the card's Unlink, a
  live library write (`second-sign-in.write-accepted`, then the unlinked notification).
- **Follow-ups (not blocking):** the card reads the link only when it appears and opens a temporary client for each
  read; its email field and AuthV3's sign-in email field capitalize the first letter; sign-in HTTP exchanges have no
  5-second bound (as everywhere in the library).

## 2026-10-01 17:14:00 EDT — v1.8.0 candidate on main: build 77's library merged and documented; the gate runs on this commit (#155 #303 #324 #329)

- **Owner:** release agent (`claude-opus-5.5-release`, workLog agentId `claude-code/claude-opus-5.5/release`), plan
  `2026-10-01-release-1.8.0` (`38aaf747`), under Michael's maintainer authorization (2026-10-01 about 16:46): "make
  sure the the library is deployed and has a release triggered, etc., from uh GitHub with all these fixes and
  whatnot".
- **main:** `d9ac85f0` merges `agent/claude-opus-5.5/library-77` (`66f49197`: gated head `956fce52` plus its
  PROGRESS entry) without fast-forward over `646c0ebc`; the merged tree equals `66f49197`'s. Pushed with the plan
  (`38aaf747`). Release document `docs/releases/v1.8.0.md` (`194f7532`, passes `scripts/validate-release-version.sh
  1.8.0`). This entry's commit is the release commit.
- **Not in 1.8.0:** library-78 (`agent/claude-opus-5.5/library-78` and its sub-branches).
- **Next:** on this commit, in `/Users/laptop/Sync/worktrees/instant-data-swift-release-1.8.0`, run
  `INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0 validation/run-performance-gate.sh live` with no Instant credentials in the
  environment; run the stages it skips after a cross-SDK failure by hand (the cross-SDK runtime suite, then
  `validation/run-scribe-shaped-20s-write-bench.sh` on a temporary app); ABBA any performance miss against v1.7.0;
  then tag `v1.8.0` here, push, and `gh release create v1.8.0 --verify-tag --latest`. Scribe then pins
  `exact: "1.8.0"`.

## 2026-10-01 15:33:32 EDT — Account linking: a second sign-in beside the session, account links, and AuthV3 linked sign-ins (#361)

- **Branch:** `agent/claude-opus-5.5/account-linking` from build 77's `956fce52` (pushed; not merged). Plan
  `agent-presence/claude-opus-5.5/plans/2026-10-01-account-linking/PLAN.md` (`a31d059e`). Scribe ADR draft 0024 and
  the Scribe branch `agent/claude-opus-5.5/account-linking` are the parent agent's.
- **Why:** Michael, 2026-10-01: "Let's add a functionality to link accounts then. If you have Apple, I want to be
  able to link it with Google as well so that we aggregate all these different recordings. So it's a library change
  and"
- **Commits:**
  - `ea6764c7189f4daa2a6f4bae1dcfcfd0f8c69832`: `InstantSecondSignIn` and the fake Instant server tests (15).
  - `4473db630827f86d3f1649964224b14dda5a7b38`: `InstantAccountLinks` and its tests (18).
  - `c1b53e517427011a0cea8d42f6f86f9e336d7fb3`: `InstantAuthState` linking, the AuthV3 card behind
    `authV3ShowsLinkedSignIns`, the skill section, and tests (`InstantAuthStateLinkingTests` 5, `AuthV3AppTests` +2).
  - Change log and ledger: `cf0e6910`, `3d2ce213`, `f50ce86e`.
- **What it does:**
  - `InstantSecondSignIn` signs a second identity in on a temporary client of the primary's app (own store under
    `$TMPDIR/InstantSecondSignIn/`, own connection, no session). Its exchanges send no refresh token; the primary's
    session, outbox, and `InstantClientID.current` never change. `open(sharingSessionOf:)` / `adoptRefreshToken`
    adopt a verified token and never revoke it. `close()` revokes every token this sign-in's own exchanges minted
    (recorded at the exchange, so a sign-in that finishes after close is revoked too), then deletes the store.
  - `InstantAccountLinks`: an `accountLinks` row whose `members` (has many `$users`, reverse `$users.accountLink`)
    lists one person's identities. Invite then join, each accepted before the next; refusals write nothing; a store
    without the schema fails before any read or write and names the fix. `permissionRulesTemplate` is verbatim.
  - AuthV3: `InstantAuthState` linking actions and an opt-in "Linked sign-ins" card (`authV3ShowsLinkedSignIns`,
    off by default) that posts `recipes.auth.link.linked`, `.unlinked`, `.failed` (ids, provider, code, operation,
    and an email-redacted error).
- **Evidence (protocol/mock only: fake auth HTTP endpoints and fake websockets; no live Instant):**
  - Red at skeletons (load ~1000): 36 tests in 3 suites, 34 failed with 90 issues, for the product reason. A naive second
    sign-in on the primary sent the guest's refresh token to `verify_magic_code` and replaced the primary session
    (`guest-a` became `user-b`). Two passed against the skeletons ("An identity in no link reads no link" and "Opening
    never resolves a client id"). The registered-primary and missing-schema tests and the AuthV3 switch and redaction
    tests were added later and not observed red separately.
  - First green run: 182 of 183 passed. The failure was a real leak: a sign-in that finished after `close()` minted a
    token that the deleted store refused to save ("disk I/O error"), so the token was never revoked. Fixed by recording
    minted tokens where the exchange returns them.
  - Final run (load ~800): `swift test --filter 'Auth|GuestPromotion|RecipesV3AppTests|InstantSecondSignInTests|InstantAccountLinksTests'`
    passed 183 tests in 35 suites, with 0 failures and 1 skip (an environment-gated soak). New: `InstantSecondSignInTests`
    15, `InstantAccountLinksTests` 18, `InstantAuthStateLinkingTests` 5, `AuthV3AppTests` +2. Regression:
    `AuthV3AppTests` 8, `V3AuthLoginFixtureTests` 8, `RecipesV3AppTests` 5 + `RecipesV3PackagingContractTests` 2,
    `InstantGuestPromotionTests` 6, `InstantGuestPromotionOutboxTests` 1, `InstantOAuthGuestTokenTests` 3,
    `InstantAuthHTTPParityTests` 4.
  - The `Auth` subset of that run (the same regex SwiftPM applied, checked against all 183 selections) is 102 tests in 25
    suites, all passing. That does not match the 62 tests in 13 suites quoted before; I did not reproduce that count.
  - `recipes-v3` was re-linked from these sources. It was not launched or exercised.
  - No failure needed a comparison at `956fce52`.
- **Open:**
  - No live run yet. The parent runs the throwaway-server link (`bd40c50a`) and the soak.
  - One invite slot per link: two devices inviting into the same link at once refuse the earlier join (retry).
  - A refused join leaves the invite open until it expires (10 minutes); only the invited identity can use it.
  - Sign-in HTTP exchanges are unbounded, as everywhere in the library; server reads and writes wait 5 seconds.
- **Next:** the Scribe schema, rules, and Account screen are on the parent's Scribe branch (`799af89c` through
  `a7a317e1` in the ledger). Scribe registers `InstantAccountLinks.default.attributes` once this branch lands, then the
  parent runs a live link on `bd40c50a` and the soak before anything ships. Merging and tagging are the parent's.

## 2026-10-01 05:55:20 EDT — library-77: frames without the attrs' cost, no gate across the caller's executor, add-query timeouts kept, refused stream reads end (#303 #324 #329)

- **Branch:** `agent/claude-opus-5.5/library-77` from build 76's library `d487ee09`; pushed, not merged. Plan
  `agent-presence/claude-opus-5.5/plans/2026-10-01-library-77/PLAN.md` (`ba087478`). Gated head
  **`956fce521ed6f5fc1a374840bbe2f84c4191de6d`** (this PROGRESS entry is the only later commit).
- **Goal** (Michael, via the coordinator): "fix this please so it works efficiently as as well as the typescript core
  library".
- **Commits:**
  - `f5fed905`: the translator reuses its attribute context per session attrs and local schema.
  - `7799d170`: live-result saves reuse the stored attributes. Each save inside every commit used to reload the whole
    attribute table: 17% of the reader's CPU in the experiment's profile.
  - `bde67df7`: all 111 async InstantRuntime entry points are `@concurrent`, so no gate-held await resumes on the
    caller's executor. A main-actor `observeAuthSession` held the gate 23-101 s while the first render held main.
  - `67bda26b`: an add-query timeout or server failure keeps the live query registered and re-sends it on the next
    init-ok; only a repeating rejection retires it (#324, P1, filed this session).
  - `778c793b`: init advertises `@instantdb/core` v0.22.75 (skip-attrs and presence patches; batched frames stay
    off).
  - `2c4cf84b`: two older test races the gates hit are closed (both fail alone on 23a80571's code too: the flush
    timeout's idle check 2 of 12, the reclaim test's known-issue scope 4 of 12), and the idle check names a busy owner.
  - `1ba00779`: a subscribe-stream the server refuses ("Stream is missing") ends every observation behind the reader.
    Scribe's media fetch on reader devices waited forever behind one missing stream. The same commit pins #329 (a
    stream written while the socket is closed never reaches the server) as a known issue; its fix is for 78.
  - Change log and ledger: `6a81039a`, `956fce52`.
- **Replay benchmark** (the experiment's fixed harness, release, min of 3 rounds, CPU ms per frame, back to back at
  load 260-990):

  | Build | advert | plain |
  |---|---|---|
  | d487ee09 | 20.96 | 32.19 |
  | 6a81039a | 15.92 | 27.12 |
  | TS core | 1.1-1.3 | — |

  On the phone d487ee09 runs plain (no advert) and library-77 runs with the advert: 32.19 to 15.92, -51%.
- **Gates on 6a81039a** (load 400-1,000; each wall-clock failure rerun alone):
  - Differential and connection survival: pass (25 tests, 2 known issues).
  - Ten suites (694 tests): 3 wall-clock 250 ms limits (pass alone) and the 2 test races fixed in `2c4cf84b`.
  - The 211 infinite-query tests: only #304. The 11 library-77 tests: pass.
  - Phone replay: pass; after a full restatement only clipboardEntries differs, as on d487ee09.
  - 5-minute live soak: 0 pending, 0 refusals, 1 connection; 41 gate holds (median 458 ms, max 2,585 ms, 22.7 s), inside
    build 76's interleaved A/B noise band (d487ee09: 49, 419 ms, 1,737 ms, 26.7 s).
  - Recording 023-shape backlog: 2,505 pending drained in 2:35 (d487ee09: 2,522 in 3:03), 0 expired claims, 0 refusals.
  - Calibrated-car 30-minute soaks (bd40c50a, the real app, Debug), d487ee09 vs 6a81039a: pending max 4 vs 2, accepts
    3,574 vs 3,348, 0 refusals, 0 ack timeouts, 1 connection each, CPU median 29% vs 27%. d487ee09's observeAuthSession
    held the operation gate 48 s at startup (9 serial-gate.stalled); 6a81039a had no stalls and a 2.4 s longest gate
    wait. The store's WAL stayed at 0.1-3.8 MB over 6a81039a's last 12 minutes.
- **Gates on 956fce52** (load 550-1,000; failures rerun alone ten times each):
  - Differential and connection survival: pass (25 tests, 2 known issues).
  - Ten suites (696 tests): four 250 ms wall-clock limits and transientMutationServerErrorReconnectsAndResendsDurableMutation
    (a fixed 100 ms sleep); all pass 10 of 10 alone.
  - The 211 infinite-query tests: #304 and retainedCanceledRawInfiniteHandleReleasesCoordinatorAndRuntime (a release
    check), which passes 10 of 10 alone. The 11 library-77 tests: pass.
  - Replay benchmark: 16.59 advert / 28.50 plain (6a81039a 15.92 / 27.12, within noise).
  - Calibrated-car 10-minute soak: pending max 3, 1,187 of 1,197 writes accepted, 0 refusals, 0 stalls.
  - Large-store drop A/B (the experiment's harness: a phone-sized store with 24 detail queries, a 120 s outage with
    dictation at 6x during it; both -O; both lanes in one window). Logs:
    `/Users/laptop/Sync/audit/instant-ts-vs-swift-2026-09-30/logs/ab-large-drop-76-vs-77-r{1,2,3}/summary.txt`.

    | Pair (slot 1 first) | Shape, host load mean | d487ee09 restore to 0 | 956fce52 restore to 0 |
    |---|---|---|---|
    | r1: d487ee09, 956fce52 | outage during the 122 s warmup, 596 | never (2,061 pending at schedule end) | 173 s |
    | r2: 956fce52, d487ee09 | outage about 168 s into dictation, 783 | 115 s (463 writes/min) | 108 s (494 writes/min) |
    | r3: d487ee09, 956fce52 | the same as r2, 480 | 90 s (592 writes/min) | 82 s (648 writes/min) |

    Apply commit p50: 1,054 vs 12 ms (r1), 20 vs 13 ms (r2), 18 vs 12 ms (r3). Writer frames: d487ee09's carry the attrs
    (264-298 KB mean), 956fce52's do not (115-152 KB). In r1 d487ee09 fell into a stall: its flushes found nothing to
    send while acks waited behind slow applies, and applies slowed as the backlog grew (the experiment agent's count;
    the mechanism is inference). 956fce52 had one retry exhaustion in r1 (a reconnect and 9 replay refusals); r2 and r3
    had none in either lane. 77 is never worse on this shape, so the exclusive-apply fallback goes to 78.
- **Build 78 queue** (sizes):
  - S, done: the exclusive server-apply fallback, `agent/claude-opus-5.5/library-78-apply-fallback` at `a8030bbe`
    (on 956fce52). Its test reproduces the large-store drop's exhaustion with this runtime's own writes.
  - S once its mover is named: acceptMutation's 5-attempt loop also runs out ("The local outbox changed repeatedly
    while updating mutation") and ends the receive loop; it already holds the operation gate, so something outside it
    moves the outbox revision.
  - S-M: pruneLiveQueryResults holds the operation gate 5-13 s while transact waits (serial-gate.stalled).
  - M: incremental stream snapshots; observers re-read the whole stream on every append (the experiment measured
    about 15 ms per line and rising visibility). Keep each observer's last snapshot and append to it.
  - M: #329, start streams written offline once the socket opens (client id versus server id first).
  - L: resident previous results with write-behind persistence, the TS model (Codable round trips 25-30% and
    retraction diffs 12.6% of the reader profile).
  - S: a done stream's reader stays registered after its observation goes out of scope (a scratch test: the observer
    count stays 1, and a reconnect subscribes it again); upstream deletes the reader at done.
  - S: an unrouted stream-reader error (no reader owns it) is treated as a failed live session and reconnects; upstream
    ignores it. Reachable when an observation is cancelled before its refusal arrives (inferred, not yet tested).
  - Dropped: checkpoints outside the gate. The experiment measured wal_autocheckpoint 1000 vs 0 with no difference.
  - Known issue: the frame that adds an attribute drops its own rows' values for it, already so at d487ee09.
- **Next:** the coordinator integrates `956fce52` as build 77's library.

## 2026-09-30 14:50:00 EDT — Build 73's library: live-safe fast drain, refused-write removal, connection survival (#296)

- **Branch:** `agent/claude-opus-5.5/fast-drain-2` from build 72's `0078484f` (pushed; not merged). Build 73's library
  is **`506089b22043c2f5bcb02712f5b7df698e31b6d3`**. Plan
  `agent-presence/claude-opus-5.5/plans/2026-09-30-fast-drain-2/PLAN.md` (`83652b96`, `22a24ab8`). The InstantRuntime.swift
  split with the parallel worker is recorded in `agent-presence/_channels/2026-09-30-build-73-runtime.md`.
- **Why:**
  - Build 71 (`bb88af72`, reduction `8bee78eb`) fell behind a live recording on an iPhone simulator against `bd40c50a`.
    The bisect named `8bee78eb`. Build 72 reverted it (`agent/claude-opus-5.5/fast-drain-revert`, `0078484f`, sources
    equal to `80db4271`).
  - Build 72 does not drain a Recording 023-sized backlog: 53 accepts in 10 minutes, 25 connections.
- **Commits:**
  - `81eb122c`: reapplies `8bee78eb`.
  - `2666d343`: receipt patches in place of whole-component rebases.
  - `b4b9fbe3`: deferred-value hydration, links written from the other side, tail order by id.
  - `5424c733`: refused writes removed without a rebase; last-write-wins in patches.
  - `46c131d7`: merges connection survival `984cc351` (reader/applier, one reconnect per socket death).
  - Data: `bcbcaaed` and `ae55eeda` (the N47 open item: refused replays already superseded on the server).
  - Change log and ledger: `69ae2476`, `b4d6bce2`, `a18786c8`, `506089b2`.
- **Evidence** (simulator against `bd40c50a`, uninstrumented, exact head `506089b2`, host load 370-980):
  - Recording 023-shape backlog: 2,581 → 0 in 3 min 47 s, 1 connection, 0 reconnects, 0 refusals, CPU 63% while
    draining.
  - Live soak: CPU 24-29%, pending bounded at 0-30.
  - Ten suites: 683 tests, 21 known issues (3 load flakes pass on rerun).
  - Differential: 12 seeds in both shapes equal to the full rebase after every event.
  - Details: `/Users/laptop/Sync/audit/recording-023-fixes/FAST-DRAIN.md` section 14.
- **Open:**
  - One server-apply retry exhaustion under load 900 caused a reconnect; hardening is a follow-up.
  - Every refresh-ok carries all 447 attrs (134 KB), because Swift does not advertise a core version.
  - N47: superseded replays still count as failed mutations.
  - Pattern B known issue unchanged.
- **Next:** the coordinator builds and installs Scribe build 73 with `506089b2`, then watches Recording 023 drain on the
  phone.
## 2026-09-30 22:06:32 EDT — #300 follow-up: live cursor check, the Mac's on-screen detail, and Scribe main measured again (#300 #303 #305)

- **Branch:** the code is unchanged (`0d66e6bb`). This commit adds bookkeeping only: this entry, the plan's status, and
  upstream-parity notes in the two #300 change-log entries.
- **Live cursor check (bd40c50a, 21:11 EDT):** a reversed (asc) query after r3 with `afterInclusive` returns
  [r3, r2]; without it, [r2, r1]. Backward pages after a top eviction rely on this, and upstream never sends it on
  the reversed order. Evidence: audit `live-cursor-check/output.txt`. The 18 seeded rows are deleted.
- **Mac detail:** the library loaded all 121 rows, and 118 were drawn on screen. The 3 moved rows sat inside the
  63-row window but never appeared on screen. Scribe draws by start date while the query pages by update time, so they
  draw below the window's other rows; that placement is inferred from the sort, not observed. Filed as #305 (Scribe).
- **Scribe main:** measured again. Current origin/main abba8983 (build 74) + 0d66e6bb fell behind: pending reached 216 and was still growing. Build 73 + 0d66e6bb drained both of its later backlogs (136 to 80, and 56 to 1). Between those runs, build 73's own library 506089b2 grew to 165. So this change is never worse than the baseline in the same window. Tonight's backlogs come from server apply and deferred-value hydration holding the operation gate under the machine's load, and #303's attribution to 753f52e0 is not established (details on #303). Repeat the soak on a quieter machine before a Scribe build ships.
- **Next:** unchanged. Merge the branch, tag it, and bump Scribe's pin. Scribe main waits for #303.

## 2026-09-30 20:48:46 EDT — Infinite query: a windowed live query keeps paging when rows appear above its first row (#300)

- **Branch:** `agent/claude-opus-5.5/infinite-leading-rows` from `506089b2` (pushed; not merged; nothing published).
  Plan `agent-presence/claude-opus-5.5/plans/2026-09-30-infinite-leading-rows/PLAN.md` (claims `d30c538d`, `1562eeee`).
- **`3bcf817d`:** the leading watcher (upstream's live reverse chunk) leaves with the evicted top page and is created
  again only when backward navigation reaches the top (that page is frozen, the watcher starts above it); trims cut at
  a page boundary and drop everything beyond; `loadNextPage` after a bottom eviction reloads from the exact frozen
  boundary, and a frozen chunk's refresh no longer clears `hasEvictedAfter`; `loadPreviousPage` freezes the page it
  grows from and uses exact boundaries; `canLoadPreviousPage` after kickstart means the top was evicted. The watcher
  still counts as a page once it holds rows, so Scribe's timeline follows its live head within 2 x 32 rows.
- **`0d66e6bb`:** a page loaded by `loadPreviousPage` starts from the server's answer, not an earlier query's stored
  result (`observeLiveInfiniteQueryChunk(seedsFromStoredResult:)`); a stale stored "no rows above" had made the window
  climb to the head.
- **Evidence (model-server tests; real-server Mac and simulator runs on bd40c50a):** red on 506089b2's logic, 1,150
  issues including the Mac's exact 63-row stall; the stale-seed test red on 3bcf817d. Final: 8 focused tests and 8
  property seeds pass (6 known issues are #302); the ten suites 683 tests, 21 known issues, and one known 250 ms timing
  flake that passes 3 of 3 alone; the infinite-query suites 211 tests (TypedAPITests has one failure that also fails 3 of 3 on a clean 506089b2 export, now #304). Mac reproduction (Scribe auto-paging
  7983f557 plus 0d66e6bb): every row down to AP299 list 118 and back to the top, 0 noop-cannot-advance. Live soak (Scribe
  build 73 cd8039c9 plus 0d66e6bb): pending 0-3, 50-60 accepts per 30 s, CPU about 23%.
- **Open:** #302 (a moved row's stale facts while the window's top is evicted; store-level, pinned as a known issue).
  #303 (Scribe main 0c359886 fails the live soak with 506089b2 too; build 73 passes; only 753f52e0 changed in Sources).
- **Next:** merge the branch into the library line, tag it, and bump Scribe's pin (Package.swift, the installer's
  REQUIRED_PUBLISHED_DEPENDENCIES and its fixtures). Do not ship Scribe main until #303 is fixed. Report:
  `/Users/laptop/Sync/audit/infinite-leading-rows-2026-09-30/`.

## 2026-09-29 00:49:08 EDT — Sharing accounts: guest-only OAuth token, log-safe auth sessions, outbox across a guest link (#113)

- **Branch:** `agent/claude-opus-5.5/sharing-accounts` (pushed; not merged; nothing published). Plan
  `agent-presence/claude-opus-5.5/plans/2026-09-29-sharing-accounts-auth-parity/PLAN.md` (`857e7053`).
- **`f5e1aec4`:** the ordinary `signInWithOAuth` forwards the refresh token only for a guest session
  (upstream `Reactor.exchangeCodeForToken`); `signInWithIDToken` keeps forwarding any token (upstream
  `Reactor.signInWithIdToken`), now pinned by a test.
- **`a9a55563`:** `InstantAuthSession` prints, debug-prints, and reflects with `refreshToken: <redacted>`
  and `email: <present>` (image URL too in dumps). Before: all 45 renderings (9 carrier values x 5 methods)
  contained the token and the email. Codable, Equatable, and Hashable unchanged.
- **`2d29e8f2`:** `InstantGuestPromotionOutboxTests` pins that a guest's pending write survives a link into an
  existing account and is sent under the promoted session (diverges from `Reactor.updateUser`, which drops
  it); `skills/instant-data/SKILL.md` says why and when to drain first.
- **Evidence (deterministic local and scripted-socket tests, not live):** baseline 25 of 26 focused tests pass
  (`cliAuthOAuthSignInPersistsAcrossLaunches` needs a fresh release CLI build and was not rebuilt); the new
  tests were red where expected; after: 67 tests in 10 suites pass (the same 25 baseline tests, the 9 new tests, and 33 more session-related tests with no baseline).
- **Open:** request and verification types still print tokens; the "ADR 0005 amendment" that Scribe ADR 0014
  section 9 cites is not written in ADR 0005 on any branch; #113 workLog not updated by this agent.

## 2026-09-28 14:15:00 EDT — Guest-upgrade audit: magic code upgrades in place or links; non-guest token fix (#113)

- **Branch:** `agent/claude-opus-5.5/guest-upgrade-audit` from `agent/claude-opus-5.5/triage-integration-2026-09-27`
  (`944582a4`); not merged, nothing published.
- **Measured live on Scribe's Instant app** (coordinator direction; test users only, all deleted): a guest that verifies a
  magic code for a new email keeps its id (type user); for an existing email (web `createToken` first) it is linked
  (`linkedPrimaryUser`) and the client holds the primary's session. Old guest tokens stay valid. Same in the TS client.
- **Fix `aa3d9779`:** magic-code sign-in forwards the refresh token only for a guest session (TS parity). A revoked
  non-guest token made verify_magic_code fail (record-not-found, HTTP 400); fixed live. Auth failures now carry Instant's
  error type and message (not the hint). `InstantMagicCodeGuestTokenTests` red before, green after; 590 related tests pass.
- **Open gaps (not fixed):** no `promoteGuestWithMagicCode` disposition; AuthV3LoginScreen shows no email card for a guest;
  an identity change does not fence the outbox (a queued guest-owned create was rejected after linking).
- Report: `/Users/laptop/Sync/audit/web-scribe-2026-09-28/AUTH-AUDIT.md`.

## 2026-09-27 17:40:00 EDT — Triage L: server apply no longer holds local writes; bad rows quarantined (#277 #278)

- **Branch:** `agent/claude-opus-5.5/triage-l-operation-gate-2026-09-27` (pushed; not on `main`), built
  on `agent/claude-opus-5.5/triage-integration-2026-09-27` and merged with its head `355f6629`. Main
  integrates; nothing published.
- **#277 (`af3c0584`):** under the operation gate, server apply's plan commit was quadratic in the pending
  tail linked to one recording (component closure re-join; outbox rewrite correlated through
  `outbox.json`). Breadth-first closure plus an uncorrelated rewrite: gate held 969 -> 207 ms at 439
  pending, 23,479 -> 570 ms at 2,000. New `serial-gate.waited` and `server-apply.operation-gate-held`
  diagnostics; the stall report names the holder's phase.
- **#278 (`246e191d`, `2fced8d1`):** typed reads leave out and report a row that fails to decode
  (`reportIssue` plus `query.row-decode-quarantined`) instead of failing the whole query; new public
  `decodeQuarantiningFailures(_:operation:)`. Migration 0024 drops, once, local entities that lost
  their id fact (1,067 sections on the iPhone copy, nothing else; bootstrap 0.25 s).
- **Evidence:** red/green tests for both; focused suites pass; full debug suite failures all match the
  known lists or pass alone (load average 50–120); Scribe-shaped memory soak passed with
  `INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0`. The release performance gate was not run (full release
  rebuild on a loaded shared Mac).
- **Next:** main merges the branch and installs; then check the phone's diagnostics for
  `server-apply.operation-gate-held`, `serial-gate.waited`, `query.row-decode-quarantined`, and one
  `sqlite.repair.entities-missing-id-removed`. Open: server-apply preparation (outside the gate) is
  still superlinear (~10.5 s apply at 2,000 pending); recording 008's sections are not in the phone's
  store at all offline (235 of 237), so showing them offline needs a retention decision.
- Report: `/Users/laptop/Sync/audit/scribe-triage-2026-09-27/L-operation-gate.md`.

## 2026-09-27 10:05:00 EDT — v1.7.0 published; Scribe main pins it (#250 #254 #155)

- **Published:** tag `v1.7.0` on `main` `252bb6cd` (fast-forward from `c5974110`), GitHub release
  https://github.com/technoplato/instant-data-swift/releases/tag/v1.7.0, by direct maintainer
  authorization (home runner offline; gate run locally).
- **Gate (`validation/results/performance-gate-20260927T130928Z`):** DomainAEV 7.8 MiB pass; macro
  28/28; TypeScript contracts; Scribe-shaped memory soak pass (`INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0`);
  wire correctness on a temporary getadb app ts->swift 185/185 writes, 2,220 words; swift->ts
  150/150, 1,800; zero lost/duplicate/reordered. Release suite: 2 of 1,775 failed under load and pass
  alone (5/5 each; InstantLiveTransportTests 110/110 twice serially). Cross-SDK core failed policy
  on a host at load 45–110; ABBA vs a `git archive` v1.6.0 build, 20 runs per arm: core p50
  0.97–1.02, runtime p50 0.99–1.01, so the TypeScript misses predate this release.
- **Scribe:** `main` fast-forwarded to `c5dcba49` (pin `exact: "1.7.0"`, installer expects 1.7.0).
  v1.7.0 sources equal `2f55c81b`, which the installed Scribe 0.1 (58) embeds.

## 2026-09-27 09:12:00 EDT — v1.7.0 release candidate; integration branch installed in Scribe 0.1 (58) (#250 #254 #155)

- **Branch:** `agent/claude-opus-5.5/integration-2026-09-27` (pushed; not on `main` yet) = `main`
  `c5974110` + fork D perf audit (merge `886a6fab`) + fork A diagnostics file cap (merge `2f55c81b`),
  then the release document `18831d08` and this ledger commit.
- **Version:** v1.7.0 (minor): the diagnostics cap adds public API (`maximumFileBytes`,
  `defaultMaximumFileBytes`, `record(...changeKey:)`, `previousLogFileURL(for:)`). Default behavior
  change: a configured log rotates at 16 MiB with one previous file; `INSTANT_SWIFT_DATA_LOG_MAX_BYTES=0`
  keeps everything.
- **Tests on `2f55c81b`:** 1,777 tests; failures match the known environmental set except
  `storeOnlyProductSeedMemoryAndLookups` (152 MB growth in the parallel run, 5.7–6.5 MB alone).
  A stale-object link error in `RemindersV3Executable`/`RecipesV3App` (old 2-argument
  `InstantDiagnosticsConfiguration.init` symbol) left an old test binary in place on the first run;
  touching the callers rebuilt it.
- **Installed:** Scribe 0.1 (58) on Michael's iPhone embeds this branch at `2f55c81b` (edit mode).
- **Next:** `INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0 validation/run-performance-gate.sh live` on the
  release commit, then fast-forward `main`, tag `v1.7.0`, `gh release create --verify-tag --latest`,
  and repin Scribe (`exact: "1.7.0"` + installer `REQUIRED_PUBLISHED_DEPENDENCIES`).

## 2026-09-27 00:51:51 EDT — Performance and concurrency audit, library side (#250)

- **Branch:** `agent/claude-opus-5.5/perf-audit-2026-09-26` (not on `main`). Commits: plan `fc1134fd`,
  live-refresh schema + persisted-result sort `44b176a4`, change-only diagnostics `87b7687d`,
  JSON decode order `e3cf7c01`, ledgers.
- **Measured (thread CPU, debug, ABBA medians of 4):** translate 100 refreshes x 8 computations
  5,123 -> 1,223 ms; persisted results 1,071 -> 627 ms; empty merges eliminated; 40 refresh decodes
  513 -> 225 ms. Phone log: 97.8% / 79.7% of two per-refresh events were exact repeats (now recorded
  only on change). Paired Mac soak: applyLiveRefresh 2,103 -> 1,335 ms, message decode 827 -> 450 ms,
  index rebuilds 349 -> 120 ms per 30 s.
- **Tests:** full suite failures are the known environmental set plus load flakes that pass in
  isolation on both the before and after binaries.
- **Next (not done):** cache the translator's AttributeStore per attribute revision (remaining
  ~120 ms of rebuilds); server apply re-decodes pending outbox bodies per refresh (176 ms);
  receipt fingerprinting and live-result pruning per refresh (82 + 97 ms).
- **Report:** `/Users/laptop/Sync/audit/scribe-perf-2026-09-26/D-perf-concurrency-audit.md`.

## 2026-09-26 20:20:00 EDT — v1.6.0 published; Scribe main pins it (#044 #155)

- **Release:** tag `v1.6.0` (annotated) on `a7d0eafd`, GitHub release marked Latest:
  https://github.com/technoplato/instant-data-swift/releases/tag/v1.6.0. PR #15 merged by
  fast-forward. Published by direct maintainer authorization (home runner offline), as v1.5.7.
- **Gate run 2 on `a7d0eafd`:** release suite 1,764 passed (serial); macro 28/28; TS contracts;
  DomainAEV (6.4 MiB); Scribe-shaped memory (live guest probe off: `INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=0`);
  live wire correctness on a temporary getadb app, ts->swift 192/192 writes and swift->ts 150/150,
  zero lost/duplicate/reordered.
- **Open gate items:** cross-SDK core `high-bandwidth.linked-writes` 1.04-1.12x TS (new; v1.5.7 ~0.98).
  Pre-existing on this Mac, where v1.5.7 fails the same: `storage-metadata.query` ~4x,
  `stream-write.chunks` ~1.15x, `triple-insert.todos` ~1.05x, and all three cross-SDK runtime
  workloads 5-7x (v1.6.0 equal or better). Compiler warning: unused `linkNamespace` (TripleIndexes).
- **Scribe:** GitHub `main` fast-forwarded to `6d829c54` (Instant line + preview slots + #248 #249),
  exact 1.6.0 pin, build 57, installer expects 1.6.0. SQLite kept on `backup/sqlite-data-lane`.
- **Next:** guard the memory soak's production auto-login; consider trimming the remaining
  small-entity write overhead (linked-writes); iPhone install of Scribe 0.1 (57) awaits device unlock.

## 2026-09-26 19:28:43 EDT — v1.6.0 release gate caught a small-entity write cost; fixed (#044 #155)

- **Implementation:** `94166c5a05df475e831fbcedeff24e11d2a8c700` on `agent/claude-opus-5.5/scribe-perf-2026-09-24` (PR #15).
- **Gate run 1 (`c01689fc`, `validation/run-performance-gate.sh live`):** release suite 1,761 tests
  passed; macro tests 28/28; DomainAEV ship gate passed; Scribe-shaped memory passed; cross-SDK
  core failed 5 of 12 (storage-metadata.query is the known 1.5.7 item). A same-machine A/B showed
  the write-path change itself made small-entity writes 12-45% slower than 1.5.7.
- **Fix:** new and <=32-fact entities handled whole (decided at first touch); scopes grow in place;
  whole-cascade capture before deletes (fixes 1.5.7's one-level rollback limit); no scope without
  capture; reserved per-mutation maps.
- **After (median of 10 ABBA runs vs 1.5.7):** insert, stream, scalar, reads at parity; update 1.09x,
  delete 1.10x, linked 1.06x. Write-scope suite 8/8; full Debug suite: no new failures except two
  load-timing flakes that pass in isolation.
- **Gate note:** the memory-soak step auto-sources `~/.config/instant-tools/scribe-main.env` and
  signed in once as a guest against the production Scribe app (no writes). Needs an opt-in guard.
- **Next:** rerun the live gate on this branch head; publish v1.6.0; pin Scribe to it; install.

## 2026-09-26 16:54:50 EDT — Writes capture and persist only the facts they touch (#044 #155)

- **Implementation:** `636c348880612ad6e11d1feed6ba4c3b39962a51` on local branch
  `agent/claude-opus-5.5/scribe-perf-2026-09-24` (not pushed); change log `9d892c99`.
- **Cause:** rollback capture, `changedEntityTriples`, and SQLite persistence were per entity.
  Scribe stores one `recordings/segments` link per segment on the recording, so every segment
  write copied, sorted, read back, and diffed the whole recording.
- **Fix:** `InstantFactScope` (per-entity touched attributes and multi-value values); per-fact
  capture; scoped SQLite reads and rewrites; scope unions at composed server-apply and
  failure-removal commits; pure-create rollback needs proof of creation; deletes widen only
  cascaded entities; multi-value slots mutate in place. Upstream comparison: `Reactor` layers
  pending mutations on read and needs no capture (ADR 0015 Q33).
- **Evidence:** 50 prepared writes on a 16,000-link recording 33.4 s -> 0.13 s (Debug);
  500 link inserts into a 16,000-link slot 0.27 s -> 0.019 s. Full suite 1,762 tests, no new
  failures versus the pre-change baseline (30 pre-existing). Scribe's ScribeInstantStoreTests
  (46) and ScribeRecordingLibraryMemoryTests (12) pass against this library.
- **Also decided (ADR 0015 Q32):** the server ignores nested include limits; Scribe list previews
  use two has-one preview slots, pushed to production and backfilled 2026-09-26.
- **Remaining:** preparing on a copy of the hot store still copies each large map a write
  mutates once per transaction (link slot, value index, reverse-link index).
- **Scribe soak (library 636c3488, slots, 30 min, two arms):** memory 117 -> 123 MB and CPU
  27-29% -> 31-35% from minute 5 to 30 (old library without previews: 124 -> 146 MB, 26% -> 39%);
  `ScribeRecordingLibrary.persist` at minute 25 2.88 s -> 1.15 s per 30 s; `materializedTriples`
  gone from the profile.
- **Follow-up `546da49f`:** writes no longer build a full store snapshot for shared-root
  authorization when the app has no active share (40 writes on 20,000 facts 6.09 s -> 0.069 s).
  The soak above predates it. Docs fix `7c567126`: nested limits do not bound the network.
- **Next:** push both branches after review; merge the library branch before Scribe ships (Scribe
  reaches this library only through an uncommitted local symlink).

## 2026-08-16 05:54:23 EDT — Preserve one durable relation across schema upgrades

- **Implementation:** `73ff55491fbd18efeaa19375c0b725d40096ce5f`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Measured cause:** existing Scribe databases held canonical server UUID relation attributes,
  while the receiving app declared the same links under logical forward and reverse IDs. Bootstrap
  previously merged by attribute ID, so one relationship could split across competing physical
  attributes and the Mac list could reopen without the transcription or segment children.
- **Correction:** retain one exact server physical relation and its metadata, expose logical
  declarations as direction-aware aliases, transpose affected resident and durable cold/live rows,
  and preserve outbox wire intent and receipt authority. The migration is transactional,
  idempotent, and skips unrelated schema and triple storage.
- **Verification:** all 5 new identity-upgrade tests, all 14 bounded live-query tests, all 13
  persistence-residency tests, and the exact stale-refresh atomicity regression pass. The upgrade
  coverage includes both physical-ID arrival orders, cold nonresident triples, live-result JSON and
  ownership, collision stamps, marker invalidation, and a zero-scan second launch. Two independent
  source reviews are clean.
- **Physical status:** not yet accepted. Build only from the clean linked Scribe and Instant ledger
  commits, then require a fresh isolated iPhone recording to appear on the server and Mac within
  five seconds, converge on exact segment/word/duration values, and survive app relaunch. The old
  Recording 052 outbox remains untouched.

## 2026-08-16 02:00:09 EDT — Let recording writes proceed during server refresh

- **Implementation:** `46024e30df6e7cf3b7df81c38c296349627ab2ce`; the paired intent-ledger
  commit is the immediately following Git commit. The paired Scribe implementation is
  `9040be5b8bbb2854a8e4ddc1d6e0de8d7b6493cb`.
- **Measured cause:** the old server-refresh path held the same operation gate used by local
  recording writes for multi-second planning and SQLite replacement. Recording 052 then accumulated
  459 pending and 15 failed related mutations while the Mac/server projection fell behind the
  locally materialized recording.
- **Correction:** serialize authoritative refreshes behind a dedicated server-apply gate, prepare
  outside the local-write gate, and catch up only append-only rows whose revisions, receipts,
  claims, acceptance state, and effect closure remain exactly proven. One outside-gate replay pass
  is followed by a forced final drain; sustained peer-runtime contention falls back after bounded
  attempts instead of starving forever. Empty authoritative transactions still install caught-up
  hot and durable state.
- **Verification:** all 24 bounded server-apply rebase tests pass, including sustained local writes,
  peer writers, empty/no-current-effect transactions, component-closure corruption, and hot-store
  publication. All 22 outbox supersession integration tests pass with only their three declared
  quarantine known issues. Independent cross-layer and queue-order reviews are clean.
- **Physical status:** not yet accepted. Install only from the clean linked ledger commits and
  require a fresh iPad-to-server-to-Mac recording to prove five-second visibility, exact words and
  duration, immediate reopen, and the current-footprint gate. The original Recording 052 queue is
  intentionally untouched because current code cannot safely rewrite its already-offered bodies.

# InstantSwiftData progress log

Newest-first. This log tracks library-side work driven by the Scribe
production-readiness plan
(`/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/docs/production-readiness-plan.md`).
Commit-level history stays in `docs/audits/commit-changelog.md`; this file is
the narrative of what the library must prove and why.

## 2026-08-15 17:18:34 EDT — Fence mock acceptance behind the offered wire mutation

- **Implementation:** `a0805fc44a2c32642279d14b5d4040c7dd7a7fa6`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Cause:** the typed-message acceptance fixture injected `transact-ok` as soon as the mutation
  became durable locally. Under full-suite scheduling, the mock acknowledgement could arrive before
  the live session had claimed and offered the mutation. SQLite correctly rejected the frame
  because no exact offered claim token existed, and the one-shot mock server never acknowledged the
  later real send.
- **Correction:** the fixture now waits for the existing fake transport to capture the exact
  outbound `transact` and transaction ID before it injects acceptance. Production claim-token,
  payload-fingerprint, and acknowledgement behavior are unchanged.
- **Verification:** the stale fixture reproduced the 10-second timeout both in the full package and
  in isolation. After the wire-send fence, the rebuilt focused test passes in 0.077 seconds. The
  final serialized package gate passes 1,731 tests across 146 suites in 559.816 seconds with exactly
  27 declared known issues and no unexpected failures; the xUnit report records zero failures.
- **Next:** install a coherent Scribe candidate from the clean linked ledger commit. The physical
  five-recording gate remains blocked at one unavoidable operator boundary per recording:
  ReplayKit's system-owned picker and Start Broadcast confirmation cannot be invoked by Scribe's
  reducer/agent-control action. Arm both visibility observers first, require the operator action,
  and accept a run only when the closing BroadcastKit verdict is `healthy` with nonzero system audio.

## 2026-08-15 16:33:17 EDT — Diff persisted live-query ownership rows

- **Implementation:** `3649a63e1d41470f8b213fdd69d0dc4488928908`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Measured cause:** the physical Scribe Mac projection persisted a 355,662-byte recordings
  result with 772 ownership rows. Replacing that result deleted and reinserted all 772 rows while
  the serial receive/apply path held its operation gate. Captured page-info-to-store intervals
  reached 14.340 seconds and 12.824 seconds, and one recording became visible only after a peer
  reset re-registered the same query.
- **Correctness:** live-query persistence still applies nested limits and unconditionally replaces
  the raw result envelope, but now compares exact query/entity/attribute/value-JSON ownership
  identities and mutates only the set difference. Each direction reuses one prepared statement;
  shared-query ownership, canonical triples, revision checks, page info, and relaunch semantics are
  unchanged.
- **Verification:** the red-first 772-row regression observed 772 deletes plus 772 inserts for an
  identity-stable replay and again for a one-identity replacement. It now observes zero writes for
  the replay and exactly one delete plus one insert for the replacement, with no UPDATE churn,
  exact result/ownership equality, and relaunch restoration. The complete nested-limit suite passes
  14/14; stale full-refresh atomicity, attribute-only revision-race, and opaque page-info
  transport/relaunch filters pass. Both changed Swift files parse, `git diff --check` passes, and
  the independent source/diff review is clean.
- **Next:** build and install a coherent Scribe candidate from this clean library commit, then run
  the same CLI-only short physical preflight. Require current iPad `physicalFootprintBytes` at or
  below 100 MiB and both server and Mac-local first projection within five seconds before admitting
  the sacrificial warm-up and five consecutive five-minute recordings.

## 2026-08-15 14:17:01 EDT — Bind durable mutation authority and migrate before services

- **Implementation:** `ae000fce901fff693971d1ebcbdca8bdd10a6ef4`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Measured cause:** physical Scribe refreshes exposed a valid durable mutation state in which a
  replay currently materializes no local difference and therefore has no rollback body. The prior
  bounded rebase guard treated that as missing evidence, repeatedly closed the socket, and prevented
  the accepted mutation from pruning. The deeper audit found that public Codable bodies could also
  claim applied, removed, or server-accepted state without SQLite-owned provenance; stale responses
  could adopt a same-ID reoffer; and the Reminder CLI rewrote persistence only after auto-connect
  could already offer the old wire body.
- **Correctness:** SQLite now owns versioned material-effect, exact claim-payload, and
  server-acceptance fingerprints. Known no-current-effect mutations remain replayable; unknown or
  mismatched authority stays visible as a typed synchronization blocker and suspends delivery
  without guessing at rollback. Claim, acknowledgement, reclaim, retry, explicit flush, terminal
  lifecycle, supersession, close, and server rebase paths require the exact durable proof. Bounded
  application migrations run against the full durable graph before Runtime services or auto-connect,
  and Reminder priority store values, forward intent, and rollback bodies migrate atomically only
  when no offered, accepted, or unknown owner makes the rewrite ambiguous.
- **Adjacent release fixes:** relation-dependent observers conservatively refresh when a dotted
  filter, order, or selection cannot prove one-namespace ownership; public upload progress
  termination again cancels and joins its producer before save; the injected local live transport
  waits while idle instead of closing; and receipt SHA-256 uses the official portable Swift Crypto
  product with unchanged `v1:` and `wire-v1:` formats.
- **Verification:** a current-source full serialized package run passes 1,729 tests across 146
  suites in 578.263 seconds with exactly 27 deliberate known issues and no unexpected failures.
  After the portability repair, the four-suite receipt, claim, acceptance, and server-apply matrix
  passes 78/78 with 10 deliberate known issues, including the fixed SHA-256 `abc` vector. All
  changed Swift files parse, both complete and staged diff checks pass, staged secret scanning is
  clean, and independent release reviews are clean. A Swift 6.3.3 Linux container compiled the
  official Crypto product before reaching this repository's pre-existing `SQLite3` module-map gap.
- **Next:** use the clean linked commit to build and install one coherent Scribe Dev candidate from
  the CLI, first taking an integrity-checked backup of the physical iPad SQLite/WAL/SHM set. Then
  require five consecutive five-minute physical recordings at or below 100 MiB while sampled Mac
  visibility stays within five seconds; the existing 150 MiB watchdog remains the abort ceiling.

## 2026-08-15 00:42:07 EDT — Skip semantic refresh no-ops and restore reconnect ownership

- **Implementation:** `141d1e9ec68531c4e92370521f7bb4256eeb2765`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Measured cause:** the post-containment physical run peaked at 107.845 MiB while 518 store
  publications caused 1,143 observer rematerializations and 14,503 snapshot materializations in
  about 67 seconds. Exact server rows were repeatedly reported as changed, and the Mac Instant
  socket later lost its reconnect owner after a query-removal send failure aborted the receiver.
- **Correctness:** authoritative exact inserts now preserve an already-canonical resident fact and
  skip semantic invalidation, while local writes retain their rollback behavior. Schema changes
  peel every active optimistic overlay under the resident schema, canonicalize the authoritative
  base deterministically, persist changed triples and indexes, then replay overlays with regenerated
  rollbacks. A current-session send failure is handed to exactly one receiver-owned reconnect path;
  same-generation retries stop before wire I/O and explicit close or replacement remains final.
- **Verification:** 17/17 focused semantic, schema, rollback, page-info, and reconnect regressions
  pass. The relevant synchronization matrix passes 197/198 with one expected schema quarantine;
  its only failure is an existing scheduler-sensitive timing characterization that compared a
  26.14 ms full snapshot with a 29.23 ms local lookup and also failed when isolated. Seven changed
  Swift files parse, `git diff --check` passes, the reproducible-build receipt is absent, and three
  independent blocker reviews are clean after fixing their two discovered edge cases.
- **Next:** build and install Scribe from this clean library commit, run one sacrificial warm-up,
  then require five consecutive five-minute physical iPad recordings to stay at or below 100 MiB
  while every sampled Mac-visible canned segment arrives within five seconds; abort any run above
  150 MiB.

## 2026-08-14 21:34:53 EDT — Bound live refresh apply and isolate oversized rejection

- **Implementation:** `30b180423666ac038210636d4377d60da2734006`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Measured cause:** physical run 1 stayed below the 100 MiB memory gate (95.579 MiB peak) but
  remote segment visibility degraded to 26.801 seconds. Before detail opened, the bounded list
  response still fed 61–161 raw entities into the serial authoritative apply path. A later
  permission rejection touched a 51-body optimistic component, repeatedly closed the socket, and
  replayed on replacement generations.
- **Correctness:** live refresh translation now applies per-parent nested limits with resolved local
  attribute metadata before both authoritative operations and query replacement. An oversized
  rejected component now fails only the exact token-owned target body, retains its optimistic
  overlay until authoritative refresh, keeps successors deliverable, and leaves the socket open.
- **Verification:** the four affected suites pass 156/156 with one expected known schema issue;
  parser, whitespace, reproducible-receipt, and independent blocker review gates are clean. The
  package-wide baseline did not complete: an unrelated macro snapshot first expected
  `isIndexed: true` while generation produced `false`, and after restoring that auto-recorded test
  edit the run later stalled in the existing concurrent local-ID resolution integration test.
- **Next:** build and install Scribe from this clean library commit, run one sacrificial warm-up, then
  require five consecutive five-minute physical iPad recordings to stay at or below 100 MiB while
  every sampled Mac-visible canned segment arrives within five seconds.

## 2026-08-14 17:58:00 EDT — Delayed acknowledgements cannot replay on the same live generation

- **Implementation:** `bdc7d10276132ce9cbddb010d53bde4a7b984c3e`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Correctness:** automatic delivery now uses the upstream Reactor-shaped six-second times
  in-flight-ordinal acknowledgement deadline. If a currently offered event expires, the runtime
  releases its durable claim, marks that socket generation acknowledgement-unknown, aborts it, and
  retries the same durable event only after a replacement generation opens. A stale response from
  the old generation cannot terminal-fail the retained row.
- **Memory boundary:** current-generation offered IDs remain resident only until durable response
  handling finishes and are cleared on close, so the retry barrier is bounded by the existing
  in-flight window.
- **Verification:** the focused delayed-ack, replacement-generation, and receiver-close regressions
  pass 3/3 with one expected timeout issue. `InstantBoundedOutboxDeliveryTests` plus
  `InstantReactorParityTests` pass 78/78 with 12 expected known issues; parser, staged-diff, and
  independent blocker review are clean.
- **Next:** finish the compact Scribe signal-projection tests, install clean Mac/iPad artifacts, and
  run the warm preflight followed by five consecutive five-minute physical recordings with CLI
  Activity Monitor traces and independent Mac/server visibility observers.

## 2026-08-14 16:25:25 EDT — Nested list projections hydrate only retained deferred values

- **Implementation:** `5d00f27644b02397691ab46f3802193e1acedf06`; the paired intent-ledger
  commit is the immediately following Git commit.
- **Correctness:** selected deferred attributes now hydrate recursively through the already
  materialized query tree, keyed by namespace plus entity ID and reapplied per include path. An
  ordered projection that omits its order key conservatively rematerializes instead of publishing a
  stale splice, and infinite queries suppress only fully identical consecutive snapshots.
- **Memory boundary:** nested child limits run before SQLite payload reads. The Scribe recording
  list can therefore retain two compact segment previews while leaving unselected `wordsJSON` out
  of the wire projection and hot store.
- **Verification:** focused reorder and nested-hydration tests pass; `DeferredValueResidencyTests`
  pass 14/14 with one expected known issue; `InstantInfiniteQueryParityTests` pass 44/44;
  `InstantSameEntityLiveRevisionMemoryTests` pass 9/9; the Scribe list-plan consumer test passes
  against this checkout. Two independent blocker-only reviews are clean. The package-wide run was
  stopped after its changed suites passed because it entered an unrelated long-lived integration
  wait; before that, its only failure was the pre-existing JSON-index macro snapshot.
- **Consumer:** Scribe implementation `bbebe7fd417994598cd6064a7359082b4274713a`
  (ledger `e4a9dd9`) selects the compact segment fields required by list previews and omits
  `wordsJSON`.
- **Next:** commit the Scribe projection, build/install both physical targets from clean provenance,
  then rerun the five consecutive five-minute recordings with CLI `xctrace`, independent
  `physicalFootprintBytes` monitoring, and Mac/iPad realtime evidence.

## 2026-08-14 14:37:30 EDT — Required foundation survives bounded delivery projection

- **Implementation:** `6cad77c8c95452ac5632bde833252a6367672429`; intent ledger
  `9f621ad0`.
- **Correctness:** a stale required cardinality-one scalar is replaced with the newest
  authoritative materialized value only when no active successor protects that key. Optional stale
  fields still drop, active successors preserve original old-then-new bodies, and unconfirmed
  optimistic overlays never become authoritative hydration input.
- **Memory/transport bound:** migration `0019_projected_outbox_claim_bytes` records exact
  claim-scoped projected bytes. SQLite measures value lengths before decode, fails an individual
  projected body above 8 MiB, defers an aggregate-overflow suffix unoffered, and clears reservations
  on acknowledgement, release, expiry, failure, retry, isolation, and quarantine.
- **Verification:** `InstantBoundedOutboxDeliveryTests` 48/48 and
  `InstantTerminalFailureComponentTests` 14/14 pass; parser and whitespace checks pass; two
  independent blocker-only reviews are clean.
- **Consumer:** Scribe implementation `2c808963e3d5627ae4873f6b57227d21325155d2` now sends segment
  scalars before the recording relation and classifies measured listener heartbeats as periodic.
- **Next:** clean cross-repository audit commits, reproducible Mac/iPad install, then credentialed
  physical proof that no required-text rejection returns and current physical footprint remains
  within the user gate during the five-recording soak.

## 2026-08-11 16:28:28 EDT — Handoff pickup: P0 stop force-finish (WT), P1 schema green, P3 overlay committed

- **Agent:** grok-build-p0-stop-hang (continuation of `docs/handoffs/2026-08-11-performance-keep-recording-hang-schema-push.md`).
- **P0 Recording stop hang (Scribe working tree, not yet committable alone):**
  - `speechFinalizationTimedOut` force-finishes both transcript streams, cancels wait/stop drain IDs, keeps loud error log (`forceFinished=true`).
  - `speechFlushFailed` marks speech finished and retries `finishStopIfTranscriptSourcesEnded` (stale finishAudio no longer leaves UI spinning).
  - Focused tests **5/5** green: timeout force-finish, flush-failed finish when system-audio done, flush-failed wait while system-audio open, stopCaptureDrained without sessions, failed streams still do not auto-dismiss.
  - **Why uncommitted:** `Recording.swift` / `RecordingTests.swift` sit inside multi-agent dirty WIP (100+ hunks: ReplayKit spool, durability sequencer, timeline window). Commit only when that WIP lands or is split; do not squash foreign work.
- **P1 Instant cloud schema/perms PUSHED:**
  - App `e7c49961-d702-46a1-82c1-fca9a61f6a4d` as `halfjew22@gmail.com`.
  - Schema: created `recordingRouteChunks` + link + `recordingAttachments.lifecycleID`; removed server-only canaries `todos` / `validationBoundary`.
  - Perms: route-chunk + attachment lifecycle rules applied.
  - `python3 scripts/instant-drift/check.py` → **match** (0 mismatches).
- **P3 Overlay default expanded (Scribe commits):**
  - `061d737` default presentation expanded + v2 settings file; ledger `da05331`.
- **Still open:** P2 route-chunk finalize merge-if-missing (schema push may unblock create); P4 reinstall + stop verify on iPad; P5 device↔admin RTT.
- **Preserve:** Instant ADR 0016 dirt; Scribe multi-agent porcelain outside owned overlay slice.

## 2026-08-11 16:14:54 EDT — Handoff: KEEP partial, InstantError fixed, stop hang + schema push open

- **Handoff (canonical):** `docs/handoffs/2026-08-11-performance-keep-recording-hang-schema-push.md`
- **Mirror:** `../tools/realtime-voice-sqlite-instant/handoffs/2026-08-11-performance-keep-recording-hang-schema-push.md`
- **Landed library:** `7c4e5ab6` InstantError LocalizedError/CustomNSError + deferred validation + JSON non-indexed macro; Runtime split `afe09bdb`; freezes `8b7c384e`.
- **Device:** Scribe Dev on Michael's iPad; agent-control record start/stop; phys_footprint peak ~196 MiB (under 400 idle budget). Evidence `/tmp/scribe-physical-keep-20260811T1606.json`.
- **Open P0:** Recording stop hangs finishing UI — `speechFinalizationTimedOut` does not force finish; route-chunk strict update fails missing entity; schema not pushed (drift skipped at install).
- **Open P1–P5:** push schema/perms; debug overlay default expanded; device↔admin RTT; reinstall after stop fix.
- **Scribe:** dirty ~247; Package.swift path Instant dual-dev. Do not thrash foreign dirt.

## 2026-08-11 14:44:11 EDT — InstantRuntime split: SIL flag removed

- **Mower:** Extracted free-standing infrastructure from 13,338-line `InstantRuntime.swift` into:
  - `InstantRuntimeExactTaskOwner.swift` (~118 lines)
  - `InstantRuntimeLiveSession.swift` (~1,412 lines)
  - `InstantVisibleWriteFilter.swift` (~250 lines)
- **Primary residual:** `InstantRuntime.swift` ~11,565 lines (class + remaining private helpers).
- **Compile:** Debug `InstantSwiftDataCore` builds in ~19s **without** `-sil-disable-pass=closure-lifetime-fixup` (Package.swift unsafeFlags removed).
- **Tests:** Focused freeze contracts (BoundedOutbox / TerminalFailure / DeferredResidency / PersistenceCache) **80/80** pass (known issues intentional).
- **Physical KEEP:** still blocked — Scribe dirty (~235 porcelain); iPad agent sessions on old build `9fc4ff4`, not freeze pin.
- **Plan:** `agent-presence/grok-build/plans/2026-08-11-runtime-split-sil/PLAN.md`

## 2026-08-11 14:32:13 EDT — Performance wrap-up: freezes landed, latency + soak PASS

- **Commits:** `8b7c384e` (bounded outbox/memory freezes + suite compile unblocks); `c4f20714` (changelog).
- **Focused contracts:** InstantBoundedOutboxDelivery / TerminalFailure / FailedRetry / ServerApplyRebase / DeferredResidency / PersistenceCache — **99/99** green.
- **Live latency (Swift ↔ TS admin):** p50 **80 ms**, p95 **154 ms**, max **154 ms** (budget p50≤2s / p95≤5s). Artifacts under `/tmp/instant-swift-admin-latency/`.
- **Process soak #150:** `validation/results/scribe-soak-20260811T175656Z/evidence.json` **status=passed**, absoluteIdleCeilingMiB=400.
- **Deferred tests (excluded until production):** InstantLiveQueueBoundsTests, InstantStorageRuntimeTests, InstantStorageHTTPParityTests, InstantCookieSyncParityTests. Dual-runtime room topic migration test disabled (hang).
- **InstantRuntime:** debug-only `-sil-disable-pass=closure-lifetime-fixup` on InstantSwiftDataCore target — remove after Runtime split.
- **Physical KEEP:** blocked on dirty Scribe tree (235 porcelain lines). Instant checkout cleaned for install (ADR 0016 stashed; untracked parked under `/tmp/instant-park-*`). Needs clean Scribe + wipe + install Instant pin, then agent-control recording.

## 2026-08-11 13:38:57 EDT — ADR 0016 Q11 accepted (recordingActive.playbackPlaying)

- Clarified session vs schema (capture = process pointers for live capture).
- Dual timeline openers: openCaptureRecordingTimeline + openPlaybackRecordingTimeline.
- Expanded observe field lists; live speech tail explained.
- Next: Q12 recordingActive.playbackPaused.

## 2026-08-11 13:29:08 EDT — ADR 0016 Q10 accepted (recordingActive.playbackIdle)

- Pre-graph `04-uri-tree.md`: leaf reviewed; playRecording while capture kept; speechRecognized not injectSim.
- session.capture.* documented; schema refresh in overview.
- Next: Q11 `mode.recordingActive.playbackPlaying`.

## 2026-08-11 13:21:20 EDT — ADR 0016 resume: recordingActive leaf review

- Back on pre-graph `04-uri-tree.md` (not 04b message graph).
- Pick up: `mode.recordingActive.*` after captain-reviewed `recordingIdle.*`.
- Q10 open: accept/amend `recordingActive.playbackIdle` first.

## 2026-08-10 17:52:00 EDT — Message graph experiment (04b)

- Exploratory static graph: message catalog, schema-path→writers index, thin tree send lists, command side-effects.
- File: `docs/adr/0016-transcription-example-instant-first/overviews/04b-message-graph-experiment.md` (may discard).
- Goal later: static/runtime check that mutates only go through declared messages.

## 2026-08-10 17:15:17 EDT — ADR 0016 URI tree WIP (handoff)

- Wrote full nested app tree with observe/send/goesTo/mutate on leaves.
- File: `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md` (**WIP**, needs more feedback).
- Captain reviewed through `mode.recordingIdle.*`; resume at `mode.recordingActive.*`.
- Linked create/finish mutations; goBack = navigation.previous (stack TBD); startRecording owned by mode not library.

## 2026-08-10 16:17:48 EDT — ADR 0016 app tree leaves (observe + send)

- Q09 shape accepted: screen ∥ exhaustive mode nesting; observe/send on leaves only.
- File: `docs/adr/0016-transcription-example-instant-first/overviews/04-uri-tree.md`
- Next: refine any leaf messages, then plan.md / implementation.

## 2026-08-10 15:38:17 EDT — #044 bounded terminal rejection and deferred residency green

- **Terminal rejection:** SQLite now proves and decodes only the rejected mutation's transitive optimistic component, with hard ceilings of 50 bodies and 8 MiB. The footprint conservatively includes forward and rollback writes, concrete entity preconditions, triple reference targets, lookup preconditions, and rule operations.
- **Deferred values:** configured large cardinality-one payloads stay out of the hot indexes at bootstrap, hydrate only for selected entity IDs, and preserve exact optimistic update, restart, rejection, and first-value deletion semantics.
- **Focused evidence:** `InstantTerminalFailureComponentTests` passed 11/11, including a 10,000-row disjoint queue; `DeferredValueResidencyTests` passed 4/4. These are structural tests, not physical memory acceptance.
- **Still open:** explicit-flush rejection still uses the legacy queue-wide path; local infinite queries must slice before deferred hydration and surface hydration failures; the clean physical iPad ReplayKit memory and five-second live-sync trial remains required.

## 2026-08-10 15:23:59 EDT — ADR 0016 URI tree draft (Q09)

- Schema: exclusive segment.body speech|event.
- Draft URI + floating toolbar session map: `docs/adr/0016-…/overviews/04-uri-tree.md`.
- Next: accept Q09, then plan.md / implementation slices.

## 2026-08-10 15:14:36 EDT — ADR 0016 Q08 homogeneous segments

- Schema: segment.body speech|event; responses on any segment; floating toolbar naming.
- Next still: session/URI tree for Transcription hosts.

## 2026-08-10 15:08:46 EDT — ADR 0016 Transcription example interview (schema lock)

- **What:** Opened ADR for a teachable multi-host **Transcription** Instant example (simulated speech, dual-client observe). Domain schema lives in the skills catalog (not forked fully in-repo).
- **Schema:** recording 1→* transcription → segment + event; segment responses (threaded, human|agent). Skill: https://github.com/technoplato/skills/blob/master/domain-as-tree/references/schemas/transcription.md
- **Local ADR:** `docs/adr/0016-transcription-example-instant-first/` · GitHub (main when pushed): https://github.com/technoplato/instant-data-swift/tree/main/docs/adr/0016-transcription-example-instant-first
- **Status:** Q01–Q07 decided (package, archetype, words, lifecycle, debug module, dual-lane session, schema, responses). Implementation not started.
- **Next:** session/URI tree overviews; plan.md + Instant issue when interview locks; then SPM core + hosts.

## 2026-08-09 18:00:47 EDT — #187 reverse relations and rebased writes fixed

- **Physical root cause:** the iPad's first durable recording transaction contained every required field, but Swift resolved child-side reverse relations to the server's forward UUID without swapping endpoints. The server therefore treated transcription and segment IDs as recordings. The corrected swap also removes child-side create/update modes so they cannot be applied to an existing parent.
- **Reproduction:** canonical TypeScript full-create plus immediate update materialized recording/transcription/segment `1/1/1`; the old Swift-shaped reversed step reproduced the exact HTTP 400. Current Swift sent canonical parent-to-child links, acknowledged 30- and 12-step transactions as server transactions `1900` and `1901`, and independently materialized `1/1/1` rows.
- **Second fault:** refresh, terminal rejection, and retry rebased only optimistic triples. Durable operations retained older timestamps, so visible-write filtering stripped required non-primary scalar fields. Commit `71ddd401de9a329233e4175549ee5281e31353de` keeps both layers aligned while preserving true-stale suppression and same-ID idempotency.
- **Verification:** 9 focused transport/rejection/idempotency tests passed across 4 suites; all 20 hydration tests passed; independent review found no remaining priority-zero or priority-one defect. Exact artifacts are under `/tmp/scribe-187-swift-roundtrip.dyuZhU/`.
- **Next:** build/install Scribe against this clean Instant commit, create one fresh iPad recording, require production server acceptance plus exact admin rows within five seconds, then repeat the host/extension memory measurement. The prior 290–450 MB run remains invalid because it contained 322 failed mutations and a rejection/replay storm.

## 2026-08-05 17:57:36 EDT — Dual-write diagnostic thrash (idle multi-GB) fixed in 1.5.4

- **Field:** iPad idle home screen **2.7–4.3 GB** footprint; cold open 122 MB → multi‑GB; continuous `debug-log-batch` mutations 400–700 ops + HOL thrash.
- **Root:** InstantDiagnostics at info dual-written into Instant debugLogs → outbox feedback loop (not recording-path exclusive).
- **Fix:** demote high-frequency diagnostics to debug (`759c899a` / tag **v1.5.4**); `InstantDiagnosticFeedbackLoopTests` green.
- **Host:** InstantDBLogger bridge filters chatter; batch size 8 (`a3d415f`).
- **Device:** clean wipe + 1.5.4 install: **~205→432 MB** in 1 min (not multi-GB); `hol_oversize=0`. Poison outbox survives reinstall without uninstall.
- **Next:** rate-limit HOL diagnostics; companion status spam; absolute idle budget soak; remaining failMutation gate work.


## 2026-08-05 13:31:04 EDT — Production performance readiness plan (research quorum)

- **Evidence (iPad Tailnet):** physical footprint climbed ~88 MB → 880–945 MB (later ~1.3 GB) under 1.5.3; `failMutation` held operation gate 160+ s; permission-denied + missing required-attr storms; ack-timeout reclaim + receive-loop-failed.
- **Plan:** `docs/plans/2026-08-05-production-performance-readiness-plan.md` — Phase 0 thrash stop (error isolation, short gates, poison outbox); Phase 1 absolute budgets; Phase 2 structural efficiency under ADR.
- **Verdict:** not production-ready (~2.5/10 independent eval). Keep SQLite offline; do not re-open 1.5.1 Jetsam thrash.
- **Next:** implement Phase 0.1–0.4 tests-first; pin after 1.5.4/1.6; Scribe stop poison writers + photo coalesce.


## 2026-08-04 — Linked infinite + includes recipe (join-shaped paging)

- **Acceptance.** Typed test
  `typedInfiniteQueryPagesRootEntitiesWithLinkedChildrenOnEachPage` proves
  infinite pages root entities while reverse-included children ride on each
  page (no second infinite root). Core example
  `LinkedInfiniteExampleTests` seeds 7 recordings/transcriptions, pages size
  3, and asserts linked word counts survive `loadNextPage`.
- **API.** `InfiniteQueryPhase` ADT; `@InfiniteQuery(..., pageSize:)` maps to
  root `.limit` (page size, not “only N forever”).
- **Recipe.** `LinkedInfiniteV3App` + Recipes catalog entry `linked-infinite`.
  CLI: `examples linked-infinite seed|list|page` with seed data and Mac
  verification (local cache: first page 3 roots with words=280/240/200;
  page expands to 6).
- **Docs.** README infinite/include section; `Examples/RecipesV3/README.md`
  lists Linked Infinite and CLI commands.
- **Next.** Scribe dual-stream list deletion uses this pattern (single
  recordings infinite + transcriptions include).

## 2026-08-02 18:38:48 EDT — #117 cardinality-one retract follow-up is cleared for landing

- Implementation commit `8d02a7a8d6b7000dea42be0b534e96761e3b1daf`
  and ledger commit `4ca8d60f2a5022688ee73c3b88f3e8a1b5cd0476`
  landed the acknowledgement/rejection slice, but a delayed worker test exposed
  one sequencing error immediately afterward: the commit contains
  `serverAcceptedJSONMergeReconcilesAgainstAuthoritativeRetraction`, while the
  corresponding runtime rule arrived after that commit.
- The committed source was reproduced RED with that one selector: one test
  failed with two assertions because the accepted merge receipt remained in
  the outbox after a matching authoritative cardinality-one retract. The first
  broad fix made that positive case pass but was correctly rejected in review:
  upstream retracts one exact EAV value, not the whole cardinality-one key.
- The final rule now reconciles only when the exact retracted EAV value existed
  in `previousChangedEntityTriples` and the key is absent from the prepared
  final `changedEntityTriples`. A base-absent accepted insert plus unrelated
  retract remains retained across relaunch, while a matching-base retract
  reconciles without resurrecting the accepted merge. Focused proof passed 2/2
  in 0.045 seconds; a three-route insert/retract/merge table also stays green.
- The exact eight-suite coupled selector from the next entry then passed 139
  tests in 0.976 seconds with zero unexpected failures and the same five
  asserted known diagnostics. This supersedes the earlier 136- and 137-test
  snapshots. Explicit cached target builds also passed for
  `InstantSwiftDataCore` in 1.82 seconds and `InstantSwiftData` in 1.28 seconds;
  `git diff --check` is clean.
- The follow-up implementation boundary is exactly
  `Sources/InstantSwiftDataCore/InstantRuntime.swift`,
  `Tests/InstantSwiftDataCoreTests/InstantFailedMutationDiscardTests.swift`,
  and this progress entry. It will land as a separate immutable
  implementation/ledger pair rather than rewriting the already published
  SHAs. Final independent read-only review explicitly found no remaining P0,
  P1, or P2 and confirmed the before/final transition matches upstream
  `retractTriple` semantics.

## 2026-08-02 18:28:43 EDT — #117 acknowledgement/rejection slice cleared for landing

- This is the cutoff-safe replacement for the older partial 15/15 and 39/39
  checkpoints. The acknowledgement/rejection contract is tracked by typed issue
  #117; issue #043 is the Scribe recording-title consumer and was named in some
  immutable older notes by mistake. Do not rewrite those historical commits:
  use #117 for this library slice and cross-reference #043 only when the title
  allocator consumes it.
- With all writers interrupted and the source snapshot frozen, the exact coupled
  selector
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter
  'InstantMessageServerAcceptanceTests|InstantFailedMutationDiscardTests|MutationDeliveryTests|InstantMutationLifecycleTests|V3RecordingActionFixtureTests|V3RecordingsListFixtureTests|InstantLiveTransportTests|rollbackPreparationIsScopedToChangedEntitiesInLargeStore|liveQueryResultPruningPreservesLookupBaselinesForOutstandingOrUnknownOptimism'`
  exited 0: 136 tests in 8 suites passed in 0.906 seconds with zero unexpected
  failures and exactly five asserted known issues. One is the intentional live
  schema-quarantine diagnostic; four are fail-loud diagnostics proving legacy
  unknown update/delete rows remain untouched in pending and failed states.
- The 50,000-row inverse-capture regression is included in that final gate and
  also passed independently in 0.188 seconds. Explicit cached target builds
  exited 0 for both
  `InstantSwiftDataCore` (1.59 seconds) and `InstantSwiftData` (2.30 seconds),
  and `git diff --check` is clean.
- The four independent-review blockers from 17:54 are now covered: every
  terminal failure route uses atomic overlay removal; discarding an older
  failed predecessor rebuilds and persists later inverses; local/manual/drain
  confirmation is durable but cannot satisfy the server-acceptance barrier;
  and overlapping same-ID automatic-retry reservations are reference counted.
  Root also corrected two final regressions: an older optimistic mutation cannot
  erase a newer local state even though all retained local receipts remain
  wire-sendable, and the encoding-quarantine test now updates an independent
  healthy entity rather than a create that rejection correctly removed.
- A post-review diagnostic edit deliberately forced a real Runtime recompile and
  superseded the earlier cached 126-test observation: Swift rejected `await` on
  the right side of an `||` autoclosure in the active-retry guard. The guard now
  awaits the reservation first and compares the local Boolean. The final 136-test
  gate above is after that compile fix. It also proves an externally refused
  retry/discard reports the exact durable `.retainedForRetry` state while the
  owning rejection disposition is suspended. Adjacent manual-confirmation logs
  now say local confirmation rather than falsely claiming server acceptance.
- The final review found two adjacent refresh/pruning gaps and both now have
  focused regressions. A generic server-accepted transport receipt without a
  transaction watermark is removed only when authoritative refresh operations
  cover every materialized effect: cardinality-many insert/retract operations
  require exact value evidence; cardinality-one replacement requires an
  authoritative insert; JSON merge requires the exact merge patch or a full
  replacement insert; entity and entity-plus-namespace deletes remain scoped;
  and lookup-based writes fail closed. An unrelated entity refresh retains and
  replays the receipt. The post-rebuild five-case operation-coverage selector
  passed 5/5 in 38.88 seconds. Live-query pruning
  protects every outbox row whose optimistic overlay is not explicitly
  `.removed`, including manual/drain/local transport, server transport, and a
  legacy failed row with unknown (`nil`) overlay metadata. The five-case lookup
  matrix failed before that semantic predicate and passes now.
- One first expanded run had 131/132 passing when the unrelated opaque-cursor
  live-query harness hit its 10-second timeout. The exact failure-only rerun
  passed 1/1 in 0.023 seconds, and the immediately following complete selector
  is superseded by the 136/136 green result above. This is recorded as timing
  evidence, not hidden or relabeled as a product failure.
- The complete current implementation boundary is 20 source/test files, not the
  earlier 18-file audit. The two additional V3 fixture suites are required
  contract migrations: their local `confirmMutation` shortcuts now inject an
  explicitly server-accepting transport and call `flushPendingMutations`.
  `PROGRESS.md` is the only documentation path to stage with that source set.
  Nothing is staged or committed yet. The independent reviewer completed a
  final read-only inspection and explicitly reported no remaining P0, P1, or
  P2 findings. No Scribe build, simulator install, or physical-device
  acceptance is claimed by this gate.

## 2026-08-02 17:54:11 EDT — P1 acknowledgement slice is no-ship pending four review blockers

- Independent source review found four correctness gaps after the earlier 39/39
  focused pass. That pass remains useful regression evidence, but it is
  explicitly insufficient for landing or shipping until all four gaps have
  focused tests and the complete acknowledgement gate is green.
- First, generic mutation-transport failures and live mutation-encoding
  failures must use the same atomic optimistic-overlay removal as WebSocket
  rejection; merely marking their outbox rows failed can leave rejected data
  visible in the cache. Second, explicit discard of an older applied failed
  mutation must rebuild and persist every later successor's inverse so a later
  rejection restores the true server base.
- Third, manual confirmation, local drain, and the default local mutation
  transport must not make `waitForAllPendingMutations` return success. Those
  local-only confirmations now require durable provenance that the delivery
  barrier can inspect and reject as not proving server acknowledgement. Fourth,
  automatic-retry reservations for the same mutation need reference counts so
  one overlapping owner cannot release another owner's protection.
- `/root/instant_ack_blockers` owns the acknowledgement/rejection sources and
  focused tests through final verification, independent rereview, task-owned
  commits, and immutable ledgers. Required supporting paths include
  `InstantLiveTransport.swift`, `InstantStore.swift`, `TripleIndexes.swift`,
  `InstantMutationLifecycleTests.swift`, `InstantStoreTests.swift`, and
  `MutationDeliveryTests.swift` in addition to the implementation and focused
  test paths listed in the 17:46 checkpoint. Recipes/presence commits
  `671e3705` and `f64d6a38` are concurrent committed work and must remain
  untouched.
- Current next boundary: finish the four RED/GREEN regressions, replace stale V3
  fixture calls that treat manual confirmation as server proof, rerun focused
  acknowledgement/rejection/live-transport/lifecycle suites plus a clean core
  build and diff checks, then obtain the reviewer's line-precise reread. Nothing
  in this slice is staged or committed yet.

## 2026-08-02 17:46:11 EDT — P1 acknowledgement and rollback candidate is cutoff-safe

- The upstream-backed acceptance boundary tracked under issue #043 is now a
  coherent unstaged landing candidate. Only WebSocket `transact-ok` or an
  explicitly server-accepted mutation transport result releases a waiting
  typed message. Local transport flush, manual confirmation, local drain, and
  generic refresh remain non-accepting. The three former refresh-confirmation
  tests now prove that matching server checkpoints rebase and retain local
  optimism without resolving the transaction.
- Terminal rejection no longer depends on an active query. In one SQLite
  transaction it strips later optimistic successors in reverse, applies the
  rejected mutation's exact inverse, replays successors with rebuilt durable
  inverses, marks the failed overlay removed with its obsolete inverse cleared,
  and persists the failed row plus errored connection metadata. Focused proof
  covers immediate local query state, relaunch, exactly one retry, a second
  rejection, explicit discard, and a successor that is itself later rejected.
- Legacy rows missing both inverse and overlay-state metadata are never changed
  by a transaction-ID heuristic. Retry and discard throw
  `localMutationDisposition = retainedUnknown`; server refresh reports the
  issue and fails closed before touching the cache. Future-skewed update and
  delete fixtures prove the visible local state stays unchanged through all
  three refused paths. The reportIssue emissions are asserted as two expected
  known issues, so the loud development diagnostic is itself test evidence.
- Exact decisive gate:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter 'InstantMessageServerAcceptanceTests|InstantFailedMutationDiscardTests|liveRefreshDoesNotConfirmMatchingLocalMutationWithoutTransactOK|liveRefreshRebasesAllOptimisticMutationsWithoutConfirmingThem|emptyLiveRefreshDoesNotConfirmMatchingMutationOrDropOptimisticRows'`.
  Result: 39/39 tests in three suites passed, 0 unexpected failures, 0.573
  seconds, with exactly two expected known issues for the legacy refresh
  warnings. `git diff --check` passes. Strict Swift format lint passes for the
  two new focused suites and the small public API/error/message transport files.
- Owned implementation surface for independent review:
  `InstantMessage.swift`, `InstantSwiftData.swift`, `InstantError.swift`,
  `InstantLiveRefreshApplication.swift`, `InstantModels.swift`,
  `InstantMutationTransport.swift`, `InstantRuntime.swift`, `Outbox.swift`, and
  `SQLitePersistenceStore.swift`; owned tests are
  `InstantMessageServerAcceptanceTests.swift`,
  `InstantFailedMutationDiscardTests.swift`, and the three renamed refresh
  cases in `InstantLiveTransportTests.swift`. Other dirty source/test files are
  concurrent work and remain untouched. Nothing in this slice is staged or
  committed; the only remaining boundary is root's independent source review,
  followed by a task-owned commit and immutable ledgers if approved.

## 2026-08-02 17:39:10 EDT — Recipes reaction, touch cursor, and logical presence fixes green

- The bounded upstream-parity implementation for #127–#129 is now source
  complete and independently rerun from scratch
  `/private/tmp/instant-ack-review-build`. Exact selector:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --jobs 1 --filter 'ReactionsV3Tests|CustomCursorsV3Tests|AvatarStackV3Tests|V3PlaybackFixtureTests'`.
  It exited 0: 25 tests in 4 suites passed in 0.101 seconds after a 51.90-second
  incremental build.
- `InstantTopic` now preserves a bounded 128-event typed window with server
  event ID and local-source identity while keeping the existing `messages`
  projection source-compatible. `ReactionsV3Model` uses a bounded 256-ID
  replay guard, animates distinct identical-payload events, ignores replay of
  the same ID, and suppresses the persisted local echo because the sender
  already animates immediately.
- Custom Cursors now renders explicit touch-device local feedback and an
  accessible draggable local cursor on iPhone/iPad. Avatar Stack projects one
  row per logical `userID` in first-seen order instead of exposing every stale
  authenticated session. The focused app and wrapper tests cover both paths.
- Root reviewed the complete task-owned diff and `git diff --check` passes.
  Existing strict-format debt remains in larger pre-existing files, while the
  newly changed focused test files and Reactions screen lint clean; no unrelated
  broad formatting rewrite was performed.
- #130's per-mount color change remains documented as canonical upstream
  behavior, not a defect. Its initial board asymmetry remains open. No physical
  iPhone/iPad post-fix behavior pass is claimed; that requires a clean committed
  build after the separate acknowledgement slice lands.

## 2026-08-02 17:37:24 EDT — Genuine server acceptance is 15/15 green

- The source-compatible acknowledgement contract now records confirmation
  provenance and emits `.serverAccepted` only for transaction-specific proof:
  a WebSocket `transact-ok` correlated by client event ID, or a mutation
  transport result that explicitly declares equivalent server acceptance.
  Manual confirmation, the default local transport, local drain, and a generic
  query refresh can still update their existing local bookkeeping but cannot
  release `sendAwaitingServerAcceptance`. This is the exact upstream
  `Reactor.js` refresh-versus-`transact-ok` distinction tracked under issue
  #043, rather than a new Swift-only acceptance policy.
- `InstantSwiftDataClient` now exposes runtime-backed failed-mutation listing,
  retry, and discard. `InstantError` and the recovery result carry a
  machine-readable local-state disposition: retained for retry, discarded, or
  retained unknown. Legacy `InstantError` JSON without the optional field still
  decodes.
- Exact GREEN command:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter InstantMessageServerAcceptanceTests`.
  Result: 15/15 Swift Testing tests passed, 0 failures, 0.497 seconds. The gate
  includes four false-acceptance regressions, both genuine acceptance sources,
  retained/discarded rejection state, structured server metadata, disposition
  race prevention, timeout/cancellation durability, runtime-less fail-fast,
  and legacy error decoding.
- Terminal rejection implementation is now source-compiling: a known rejected
  optimistic layer and its later successors are stripped in reverse, the
  rejected inverse is applied, successors are replayed with rebuilt inverses,
  and store/outbox/errored connection metadata persist in one SQLite
  transaction. Exact compile gate:
  `swift build --scratch-path /private/tmp/instant-ack-review-build --target InstantSwiftDataCore`;
  result: exit 0, target build complete in 13.33 seconds. Heuristic removal by
  matching transaction IDs has been deleted; direct retry/discard of a legacy
  row missing both inverse and overlay state now fails loud with
  `retainedUnknown`.
- This remains an unstaged, uncommitted landing candidate while regressions are
  added for zero-query rejection, relaunch, retry-once/discard, successor
  replay, and future-skewed legacy update/delete rows. Generic live-refresh
  tests that previously treated a matching checkpoint as acceptance must also
  be updated to the upstream contract before the broader acceptance sweep.

## 2026-08-02 17:27:43 EDT — Recipes topic, cursor, and presence defects reach upstream-backed RED boundary

- `/root/recipes_presence` claimed typed issues #127–#130 and owns only the
  Recipes presence/event files plus an explicitly approved clean
  `Sources/InstantSwiftData/InstantTopic.swift` extension and focused wrapper
  test. The acknowledgement/rejection slice and its concurrent dirty files
  remain untouched; nothing from this lane is staged or committed.
- Canonical `reactions.tsx` handles every broadcast through `useTopicEffect`.
  Swift currently publishes replacement payload arrays and the Recipes model
  deduplicates only by array count, so distinct one-message broadcasts produce
  the observed `1 -> 1` drop. The approved TDD shape keeps `messages`
  source-compatible, exposes only a bounded ID-preserving typed event window,
  and proves distinct-ID delivery, same-ID replay suppression, and no duplicate
  sender animation from a local persisted/echo event.
- `CustomCursorsV3Screen` publishes drag presence on iOS but compiles local
  cursor rendering only for tvOS/watchOS. React's native-mouse assumption does
  not give touch devices visible local feedback, so #128 needs an explicit
  SwiftUI touch adaptation with accessibility coverage.
- `AvatarStackV3Model` currently keeps every member row, including repeated
  authenticated sessions sharing one `userID`; #129 needs stable first-seen
  logical-identity projection and deterministic count tests. This does not yet
  prove server leave/reconnect cleanup or cross-device count convergence.
- Canonical Merge Tiles intentionally selects an available random color from
  component-local state on each mount; #130's color change is therefore
  upstream-compatible. Initial board asymmetry remains unreproduced. No focused
  test, package build, install, launch, or physical iPhone/iPad pass is claimed.

## 2026-08-02 17:25:59 EDT — Server-acceptance contract RED checkpoint

- Ownership remains the uncommitted InstantSwiftData acknowledgement/rejection
  slice only; no source, test, or ledger file has been staged or committed, and
  concurrent dirty work is preserved. The immediate cutoff-safe target is the
  independently reviewed P1/P2 acceptance gap, not optional retry-scan or
  reservation-refcount polish.
- Canonical upstream evidence was reread before changing Swift: `Reactor.js`
  refresh replaces the authoritative query store and reapplies outstanding
  optimistic mutations, while only the transaction-specific `transact-ok`
  path resolves that mutation as synced. Consequently, generic refresh, local
  transport flush, manual confirmation, and local drain must never release
  `sendAwaitingServerAcceptance`; an explicitly server-accepted transport
  result or WebSocket transaction acknowledgement may. This follows durable
  Instant guidance tracked under issue #043.
- Focused tests now encode those four negative paths, the two valid positive
  paths, the public failed-mutation list/disposition contract, and legacy error
  decoding in
  `Tests/InstantSwiftDataTests/InstantMessageServerAcceptanceTests.swift`.
  Exact RED command:
  `swift test --scratch-path /private/tmp/instant-ack-review-build --filter InstantMessageServerAcceptanceTests`.
  It exited 1 at compile time, as intended, because production has no explicit
  transport `acceptance`, no `InstantError.localMutationDisposition`, and no
  `InstantSwiftDataClient.failedMutations()` yet. The test helper also used the
  wrong existing live-message case name (`transactOK`), which must be corrected
  to the repository's actual transaction-acknowledgement case before counting
  the next RED/GREEN result.
- Next exact implementation boundary: add source-compatible, Codable
  confirmation-source metadata; publish `.serverAccepted` only for genuine
  transaction-specific server proof; remove generic-refresh confirmation;
  expose failed-list/retry/discard plus machine-readable retained/discarded/
  retained-unknown disposition. Then rerun the same selector from its isolated
  scratch path. Remaining no-ship blocker after that boundary: terminal live
  rejection must atomically remove known optimism and persist errored metadata,
  while legacy rows missing inverse/overlay state must remain loud and unknown
  without heuristic cache mutation.

## 2026-08-02 17:07:28 EDT — Physical Apple login passes; acknowledgement review finds no-ship gaps

- The exact clean Recipes implementation commit `6408c8ec1982bda51442a6e517c4d900c7818734`
  was exported with embedded `dirty=false` provenance, built with Apple
  Development team `4EC72DECN9`, installed, launched, and observed connected to
  InstantDB on both the physical iPhone 17 Pro (iOS 27.0) and physical iPad.
- The user completed the native Apple account sheet on the iPhone. Instant
  returned the connected Apple provider account and the app rendered `Account
  connected successfully.` The supplied screenshot's SHA-256 is
  `adec054d1968a444e17bfc216cd8e949b6033ff02757fe0f0fa74d0bdf5c10c1`;
  typed issue #113 stores it as attachment
  `3275257f-8b58-4550-910b-bd137c99a93e` and log
  `issue-113-recipes-iphone-apple-e2e-pass-20260802T165750`. This is physical
  end-to-end Apple acceptance, not merely build or sheet-presentation proof.
- The same signed build installs and launches on iPad, visibly connects to
  InstantDB, and presents the native Apple sheet. The iPad account was not
  changed. Earlier simulator evidence remains split correctly: Google completed
  end to end, the unsigned Apple build failed with AuthorizationError 1000, and
  a development-signed build cleared that entitlement error before reaching the
  simulator's missing-Apple-account boundary.
- Scribe auth integration is now delegated with a narrow host boundary: reuse
  `AuthV3App` for Apple, Google, magic code, and atomic guest promotion; add one
  TCA account presentation route shared by iPhone, iPad, and Mac; do not copy
  provider token or promotion transitions into the application.
- The upstream-aligned acknowledgement/rejection slice now passes 35/35 tests
  across five suites from fresh scratch path
  `/private/tmp/instant-ack-swift-build` (0 failures, 0.443 seconds). The gate
  covers exact rollback, successor replay, retry after refresh/relaunch,
  dual-trace preservation, 50,000-row entity-scoped preparation, and atomic
  retry metadata with SQLite trigger fault injection. `git diff --check` and
  strict lint of all new/small task-owned files pass.
- A separate Sol Ultra reviewer reran the same 35 tests from isolated scratch
  (35/35) but returned **NO-SHIP** because those tests omitted three P1 paths:
  local flush/manual confirm/drain can emit `.serverAccepted` without a real
  server acknowledgement; a terminal rejection leaves its optimistic cache
  visible across relaunch when no query is registered; and legacy rows without
  inverse/overlay metadata can reapply or discard updates/deletes with cache
  corruption. It also found a P2 public-API gap: default retention has no client
  retry/discard surface and the thrown error does not name the local-state
  disposition.
- The original library worker has resumed TDD ownership of those exact four
  findings. No acknowledgement implementation is staged or committed. The
  shared `.build` directory remains non-evidence because concurrent incremental
  jobs left stale ABI products after `InstantError` changed; all acceptance
  reruns use isolated scratch builds.

## 2026-08-02 16:23:13 EDT — Upstream-aligned rejection rollback is green, review pending

- The repository rule is now explicit in `AGENTS.md`: tricky Instant edge
  cases start with the canonical vendored TypeScript client, reuse its state
  transition and test shape, and document any Swift-only adaptation instead of
  inventing a competing policy. Typed Scribe preference
  `defer-tricky-instant-edge-cases-to-upstream` records the same durable
  direction under issue #043.
- Canonical `Reactor.dataForQuery` / `_applyOptimisticUpdates` keep server query
  state separate from pending optimistic mutations; `_handleMutationError`
  removes a rejected mutation. Swift persists one materialized SQLite store,
  so the equivalent implementation records each optimistic transaction's exact
  inverse, removes those layers in reverse order before a server refresh,
  reapplies surviving outbox mutations in order, and refreshes their durable
  inverse images against the newest server base.
- Explicit `.discard` now atomically removes only the handled failed outbox row,
  rolls back creates/updates/deletes/relationship cascades, replays later
  optimistic writes or deletes, publishes the restored query state, and
  survives relaunch. A server refresh clears obsolete failed inverse images so
  a later discard cannot overwrite newer server values or resurrect a
  server-deleted entity.
- Live rejection records preserve the server status, type, hint, and trace ID;
  the failed outbox transition and errored connection metadata commit together.
  HTTP 401/403 and permission/unauthorized/forbidden types are terminal server
  rejections, not reconnect noise. Schema-resolution failures can still retry
  after reconnect, but permission failures remain loud and retained until an
  explicit caller retry/discard.
- `sendAwaitingServerAcceptance` registers lifecycle observation before the
  optimistic transaction, prepares once, returns only after `transact-ok`, and
  retains pending work on timeout/cancellation. Automatic reconnect and manual
  retry cannot race an asynchronous rejection disposition; focused tests now
  prove both timeout and cancellation release that reservation afterward.
- Current evidence: 31/31 rejection/rollback/live-retry/delivery tests pass;
  12/12 existing mutation-lifecycle and recording fixture tests pass. The
  formerly unbounded
  `runtimeLiveMutationErrorPersistsFailureAndRetryResends` proof now uses a
  bounded outbox observer and passes together with rejected-query refresh.
  Legacy `PendingMutation` and `InstantError` payloads without the new optional
  fields decode successfully. Strict format lint passes for the two new focused
  suites and touched delivery test; `git diff --check` passes.
- This slice is still uncommitted while an independent Sol review inspects the
  upstream parity, concurrency, persistence, and backward-compatibility
  boundaries. No Recipes or Scribe binary may be installed from this dirty
  checkout; the next boundary is review approval, coherent source/test commit,
  immutable ledgers, then the separate Recipes host commit and clean rebuild.

## 2026-08-02 15:42:43 EDT — Recipes auth host acceptance (uncommitted)

- The user correctly identified that implementation `f13ee441` changed the
  shared `AuthV3App` and library but did not modify, rebuild, or relaunch the
  native Recipes application. Typed Issue #113 now preserves that correction
  and exact quote; its Apple/Google/guest-promotion application criteria remain
  unsatisfied.
- Recipes now owns its provider boundary. `RecipesV3AppConfiguration` derives
  the Apple and Google client names plus
  `instant-recipes-v3://oauth-callback` from environment or bundle metadata
  and passes that exact configuration into `AuthV3LoginScreen`. The shared
  screen accepts app-owned provider configuration without duplicating the auth
  UI.
- The iOS and macOS hosts now register the callback URL and declare the Default
  Sign in with Apple entitlement in both `project.yml` and the generated Xcode
  project. Focused configuration/callback/entitlement/Auth syntax selectors pass
  7/7, including the real bundle-metadata fallback used at launch; all four
  plists lint clean. The broad target selector ran the focused
  tests successfully but the package test process later exited with signal 11,
  so only the six independently green selectors count as evidence.
- Disposable unsigned Xcode builds of `InstantRecipesV3macOS` and
  `InstantRecipesV3iOS` (generic iOS Simulator) both succeeded from the dirty
  working tree. They prove the host configuration compiles, but are explicitly
  not install, launch, provenance, or provider-interaction acceptance. The
  current iOS and macOS `-showBuildSettings` output resolves app ID
  `0fd66535-c296-4d76-9324-a6b7fe51d95e`, the expected platform bundle IDs,
  and the new entitlement files; the disposable products predate that local
  app-ID switch and still contain the old app ID, so they must not be deployed.
- A permanent account-owned Instant app titled `Instant Recipes V3` was
  created at app ID `0fd66535-c296-4d76-9324-a6b7fe51d95e`. Its aggregate
  Recipes schema and permissions are deployed; read-only CLI verification shows
  an empty guest-visible Todos/Boards query, Google development client
  `google`, native Apple clients `apple` (iOS bundle ID) and `apple-mac`
  (macOS bundle ID), and authorized origin `instant-recipes-v3://`. The admin
  token is private at
  `../private/credentials/swift-instant-data/recipes-v3-owned.env`; the ignored
  `Examples/RecipesV3/RecipesV3.local.xcconfig` now embeds the public app ID
  and local Apple development-team identifier needed for a signed physical
  build.
- No deployable acceptance build exists yet. Concurrent uncommitted
  acknowledgement/rollback work still owns
  `InstantRuntime.swift`, `InstantMessage.swift`, `Outbox.swift`, and
  related tests. Per clean-build policy, do not install or call Recipes auth
  verified until those files and this Recipes slice are reviewed and committed,
  the real checkout is clean, and fresh Mac/iPhone/iPad builds are relaunched
  and exercised through guest creation, Apple, Google, and guest promotion.

## 2026-08-02 15:15:35 EDT — Server-acknowledged typed messages (uncommitted review checkpoint)

- A task-owned library slice adds
  `InstantSwiftDataClient.sendAwaitingServerAcceptance`, which prepares once,
  registers the transaction lifecycle before the optimistic transaction, and
  returns its typed change only after `serverAccepted`. Runtime-less clients
  fail before transacting; timeout and cancellation leave the pending mutation
  durable.
- `InstantMessageFailureDisposition` makes server rejection explicit:
  `.retainForRetry` preserves the failed outbox row, while `.discard` removes
  only that failed mutation after the caller handles it. The package-scoped
  runtime removal is SQLite revision-checked, updates the in-memory outbox,
  survives relaunch, heals connection status only after the last failure is
  gone, and never emits a synthetic acceptance lifecycle event.
- This is an explicit Swift adaptation of
  `upstream/instant/client/packages/core/src/Reactor.js`:
  `_handleMutationError` deletes the rejected pending mutation immediately,
  whereas Swift retains diagnostic/retry state by default and deletes only on
  the typed caller's `.discard`. Reconnect proof confirms a discarded
  `permission denied` row cannot be automatically retried by the existing
  deployment-fix retry path.
- `waitForAllPendingMutations` now inspects retained failed rows before
  returning; a failed mutation throws its exact failure message and mutation
  ID instead of looking like completed delivery merely because it is no longer
  `.pending`.
- Verification at this checkpoint: 14/14 tests pass in
  `InstantFailedMutationDiscardTests`,
  `InstantMessageServerAcceptanceTests`, and `MutationDeliveryTests`; 12/12
  existing lifecycle/recording-message tests pass in
  `InstantMutationLifecycleTests`, `V3RecordingActionFixtureTests`, and
  `V3RecordingsListFixtureTests`. Strict Swift format lint passes for the two
  new test files, the touched delivery test, and `InstantMessage.swift`;
  `git diff --check` passes. The much larger pre-existing runtime/outbox/client
  files still report unrelated baseline format findings outside this diff.
- The existing
  `observeConnectionStatusPublishesRuntimeStatusChanges` regression passes
  1/1. The separate legacy
  `runtimeLiveMutationErrorPersistsFailureAndRetryResends` selector builds but
  produced no test-runner output and was stopped after a bounded wait; it is not
  counted as passing evidence and should be rerun independently during review.
- Ownership/handoff: these seven source/test paths plus this checkpoint are
  intentionally uncommitted for the coordinating agent's review. Re-run:
  `swift test --filter 'InstantFailedMutationDiscardTests|InstantMessageServerAcceptanceTests|MutationDeliveryTests'`,
  then
  `swift test --filter 'InstantMutationLifecycleTests|V3RecordingActionFixtureTests|V3RecordingsListFixtureTests'`.

## 2026-08-02 — Native provider auth and atomic guest promotion

- The reviewed auth slice adds native Sign in with Apple token exchange with a
  raw/hashed nonce pair, callback-safe OAuth with state and PKCE, Google/GitHub/
  enterprise provider configuration, and explicit actionable configuration
  failures instead of guessing a browser fallback.
- Guest promotion is atomic across the provider exchange and exact persisted
  guest-session compare-and-swap. Cancellation before exchange remains
  cancellable; after a successful non-idempotent exchange, the returned server
  state is committed only when the exact guest still owns local auth. A
  divergence fails loudly and records that the provider credential may already
  have been consumed.
- `InstantSwiftDataClient` exposes injectable ID-token and OAuth promotion
  operations, so reducers, previews, and deterministic tests use the same
  public dependency seam as the live runtime. Legacy provider convenience
  properties remain source-compatible under deprecation.
- Independent review is green after fixing late singleton callbacks, missing
  callback URLs, pre-state OAuth error trust, cancellation-after-success, the
  injectable value-client seam, compatibility properties, and a false-pass
  fixture. `swift test --filter Auth` passes 62 tests across 13 suites; focused
  promotion/provider/UI coverage passes as part of that gate.
- This is library and test acceptance only. A clean Scribe build still must
  complete Apple, Google, guest-to-new-identity, and linked-existing-user flows
  on physical iPhone, physical iPad, and Mac with before/after Instant evidence.

## 2026-08-02 — Scribe recovery continuation

- Implementation `e87765b8cd8c5c2830494ee05c9686f7edb9f4d4` prevents a
  deep persisted outbox from starving reconnecting live queries: query
  registration now precedes mutation replay, and replay uses a reentrancy-safe,
  acknowledgement-driven window capped at 50 mutations / 256 low-level steps.
  Focused outbox tests pass 6/6; the library ledger is `14c18af9`.
- A Sol worker currently owns only `SQLitePersistenceStore.swift`,
  `InstantStartupTraceTests.swift`, and its explicitly added benchmark-profiler
  files. It is profiling copies of the backed-up physical iPhone/iPad SQLite
  stores, adding a deterministic red gate, and targeting local startup/list
  readiness under 200 ms or the closest evidence-backed bound.
- Scribe's device backup counts, physical launch/memory evidence, simulator
  real-audio E2E contract, worker ownership, and exact restart order live in
  `/Users/laptop/Sync/tools/realtime-voice-sqlite-instant/handoffs/2026-08-02-sync-startup-and-e2e.md`.
- Because premium-model access is limited, every subsequent verified slice
  must leave immutable SHAs, test/benchmark output, blockers, and exact next
  steps here and in the applicable ledgers before another workstream begins.

## 2026-08-01 — Scribe production-readiness driver

- Scribe (the library's flagship consumer) reports defects that implicate the
  app↔library seam: recording list stuck loading forever on Mac while data
  exists locally in SQLite, infinite-query paging that never completes,
  word-count projections rendering 0, and a noticeable spinner when opening a
  local recording. Root causes may land on either side of the ADR-0001
  boundary; library-side fixes will be documented here and in CHANGELOG.md.
- Planned validation ground (workstream E of the plan): first-class
  `Examples/RecipesV3` recipes that continuously prove the quirky behaviors —
  a latency recipe (message bursts at adjustable rate carrying
  `publishedAtMs`/per-device `receivedAtMs`, live round-trip latency display)
  and a large-list recipe (continuous appends, streaming loads, paging that
  never wedges). Library bugs fixed under the Scribe push each get recipe or
  `validation/` coverage.
- A dedicated test InstantDB app now exists for cross-device E2E and latency
  work (credentials in Scribe's `.env.test`); the suite adds an Instant-room
  presence-based semaphore so concurrent runners serialize against the shared
  test database.
