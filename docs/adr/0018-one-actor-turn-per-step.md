# ADR 0018: One Actor Turn per Step, and the CPU Costs Behind the Hops, on Local Writes, Relaunch, and Outbox Drain

- Status: Accepted for 1 to 8, which ship in v1.9.1 (Michael's authorization through main, 2026-10-02); 9 to 12
  proposed, measured on `agent/claude-opus-5.5/library-79-next`, landing after v1.9.1
- Date: 2026-10-02
- Issue: #403 (related: #402, #155, #303)
- Scope: `InstantRuntime.transact`, `bootstrap`, `queryOnce`, `pendingMutations`, `connect`, `flushPendingMutations`,
  the connection status every write publishes, `SQLitePersistenceStore`'s calling convention and statement lifetime,
  and transport date encoding

## Context

Michael, verbatim (2026-10-01): "fix this please so it works efficiently as as well as the typescript core library".

The v1.8.0 release gate's cross-SDK runtime benchmark (`InstantCrossSDKRuntimeBenchmark.swift`, one todo, 7
iterations, load about 900) measured Swift at 6.7x to 9.6x TypeScript's p50:

| Workload | Swift p50 | TypeScript p50 | Ratio | Hops the recorder counted |
|---|---|---|---|---|
| `pending-mutation-enqueue.update` (one `transact`) | 3.05 ms | 0.46 ms | 6.7x | 9 |
| `offline-restore.relaunch` | 5.60 ms | 0.68 ms | 8.3x | 12 |
| `reconnect-outbox-drain` | 5.85 ms | 0.61 ms | 9.6x | 29 |

Two facts frame the gap. TypeScript's side persists to `fake-indexeddb` in memory, and `Reactor.js` saves pending
mutations up to 100 ms after `pushOps` returns (`PersistedObject` with `saveThrottleMs: 100`, Reactor.js:468-477),
while Swift's write contract makes `await transact` mean a committed SQLite row. So part of the ratio is durability
the library must keep. And the hop recorder counted only some call sites: one transact made 19 actor calls, not 9.

### Where the hops were (library-78's head `d95c9625`; v1.8.0 has the same paths)

Each row is one await into another isolation domain. "Protects" is the property the call exists for.

**transact** (`InstantRuntime.swift`), 19 calls:

| Line | Call | Protects | Reactor.js |
|---|---|---|---|
| 2204, 2207 | operation gate enter, leave | serial local writes across a multi-await critical section | none: one event loop |
| 2265 → 13052 | `loadStateWithSource` | the hot store matches SQLite's revisions (other runtimes share the file) | none: one process |
| 2276 | `hasActiveShares` | shared-root write authorization | none |
| 2283 | `loadOutboxMutations(ids:)` | idempotent replay of a transaction id | `pushOps` makes a new event id |
| 2332 | `loadOutboxAliasReplay` | superseded ids stay reserved | none |
| 2348 | `latestOutboxCreationTimestamp` | monotonic `createdAt`; the outbox-tail test for #296 stamping | `order` from the in-memory map |
| 2380 | `serverApplyGate.isHeld` | no tail supersession while a refresh prepares off the gate | none |
| 2386 | `loadImmediateSupersessionTail` (eligible writes only) | same-entity supersession | none |
| 2432 | `store.prepareCurrent` | prepare the optimistic indexes beside the hot store | `instaml.transform` |
| 2469 | `saveLocalMutation` | the durability point: triples and outbox row in one revision-checked transaction | `kv` save, 100 ms later |
| 2483 | `store.commitAndPublish` | durable before visible, then publish to queries | `notifyAll()` |
| 6911-6923 | six status reads, `liveSession.isOpen` | the pending count and state that status observers show | none per write |
| 6950 | `connectionStatusObservers.publish` | deliver that status | none per write |

**relaunch** (`bootstrap`, then `query`, then `pendingMutations()`), 16 calls: `persistence.bootstrap` (1812),
`synchronizationBlocker` (1831), `loadCompactState` (1848), `store.mergeAttributesIfChanged` (1877),
`pruneLiveQueryResults` (1986), a startup cookie task even without a first-party URL (2030 → 6445); in the query the
gate (5950, 6029), `loadStateWithSource`, the stored connection state (5969), `store.materializeEmission` (6001),
`saveQueryCache` (6011); in `pendingMutations()` the gate (11980, 11989), `loadStateWithSource` and
`loadOutboxMutations` (11984). Reactor.js opens storage and waits for `pendingMutations` to load (Reactor.js:450-490).

**reconnect drain** (`connect()` then `flushPendingMutations()`), 50 calls: the reconnect controller (6538), the
connection gate (6550, 6721), the operation gate (6553, 6712), two metadata writes (6708), and the status's six
reads, open flag, and publish (6709); the flush gate (12190, 12197), the flush owner's task (12191), the gate
(12264, 12315), the claim (12267), `releaseMutationReservations` on an empty set (12274), the resident outbox
(12294), the stored state (12300), two counts (12313-12314), the transport, deadline, renewal, watchdog, and
disposition tasks (12362-12498),
the gate (12634, 12666), the confirmation (12638), the resident outbox (12645), the failed count (12652), the stored
state (12657), two metadata writes (12659), the status again (12661), the claim release (12663), and two counts
(12664-12665). Reactor.js handles `transact-ok` in one synchronous pass (Reactor.js:807-845) and sends the queue on
`init-ok` in one loop (Reactor.js:637-641, 1589-1623).

## Decision

**Enter each actor once per step** (Point-Free rule 2: "Enter an actor once, then work synchronously", `run` at
ep362@12:16; await-per-call measured 25-42% slower than a `Mutex`, and `run` 160% faster, ep364). The persistence
store gets `run(_:)`: a synchronous closure on its executor, so several of its methods cost one hop and nothing
interleaves between them. Every method keeps its own SQLite transaction and revision check; `run` adds none, so each
read and write is the same statement as before, in the same order.

What this branch changes (all behind the same API; no public surface):

1. transact reads in one turn: state, shares, the same-id check, the alias check, the cursor, and the tail. The read
   stops where the attempt would stop. The tail read splits into a synchronous read and its rare repair, which keeps
   its own hop and its test hook.
2. transact saves and reads the status it changed in a second turn. The save's transaction commits before the status
   read starts; a failed status read publishes nothing and never undoes the write, as the `try?` did before.
3. The connection status reads in one turn everywhere (six reads were six hops), and skips `liveSession.isOpen` when
   no live transport exists, because `connectionState(_:isAuthenticated:liveSessionIsOpen:)` reads it only then.
4. The server-apply gate's held flag is read without a hop (`AsyncSerialGate.isHeldSnapshot`, an
   `OSAllocatedUnfairLock<Bool>` written in the same actor turn as the holder). A lock fits a "tiny, local isolation
   domain" (ep358@4:01); contention grows with the work under it (ep360@27:15), and here there is none.
5. Relaunch opens the store in one turn (schema, blocker, compact state) when the app has no persistence migrations;
   the query reads its state and the stored connection state in one turn; `pendingMutations()` reads the state and
   the rows in one turn; the cookie task starts only with a first-party URL.
6. The explicit flush claims and reads in one turn, skips `releaseMutationReservations` for an empty set (it returns
   at once), refreshes the resident outbox in one call, and settles the confirmation in one turn. Failures still
   surface where their awaits did: the turns keep each later read's outcome and throw it at the same point.
7. Every actor call and task on the three paths is now recorded, and `InstantCrossSDKRuntimeBenchmarkTests` pins them.

The measurement then showed that hops were not where the time went (Results), so two CPU cuts follow, each its own
commit, at main's request:

8. **One shared ISO 8601 formatter for transport dates** (`55a15392`). Lowering a mutation for the wire created an
   `ISO8601DateFormatter` per date value, and a transact lowers its mutation more than once (the delivery step count,
   the wire-intent fingerprint). One formatter with the same options now formats every value, behind an `NSLock`
   that hands back only `String`s (rule 6: never hand out the protected object). The strings are byte-identical:
   pinned against `@instantdb/core` 1.0.49's own wire encoding of 79 dates, a fresh formatter over 2,005 dates, and
   3,200 concurrent calls.
9. **A prepared-statement cache on the persistence actor** (`0f1f2a71`, measured by heavy job 4). Statements are keyed by their SQL
   text, prepared once with `SQLITE_PREPARE_PERSISTENT`, reset and unbound on release, bounded to 64 entries (least
   recently used out), never kept for DDL or for statements with more than 32 parameters (built for one batch size),
   finalized before every close (`sqlite3_close` refuses to close while statements are live), and finalized when a
   statement moves SQLite's schema cookie. A nested use of the same SQL gets a one-off statement, as every statement
   was before.

The profile of 1 to 8 then ranked three more CPU cuts, which main approved for after v1.9.1, one commit and one ABBA
arm each. They are on `agent/claude-opus-5.5/library-79-next` with the cache:

10. **One SQLite transaction per persistence turn** (`fe8c69f4`). A turn ran each method in its own SQLite
    transaction and each lone statement in its own implicit one, so a turn of six reads took and released SQLite's
    locks six times or more (the `fcntl` calls in transact's profile). `run(inOneTransaction:_:)` runs a turn in one:
    `.read` begins `DEFERRED` and admits only reads (a write there is a precondition failure); `.write` begins
    `IMMEDIATE`, because reading the outbox can quarantine a row. A write turn keeps every guarantee the methods' own
    transactions gave: each method's writes run in a savepoint, so a method that throws leaves nothing behind; the turn
    commits what finished before it, as their own commits did, and then rethrows; quarantine reports go out after the
    commit, one per method; and a failed commit drops the store's memory cache, because its methods may have cached
    what they wrote. Used for transact's two turns, the status, the query, `pendingMutations()`, connect's metadata and
    status, and the flush's claim and settlement.
11. **One migration read at bootstrap** (`663cb647`). Each of the 25 migrations opened an `IMMEDIATE` transaction on
    every launch only to find itself applied. Bootstrap reads the applied names once; a missing name still checks in
    its own transaction, so a migration another process applies meanwhile runs once. A `PRAGMA user_version` skip was
    rejected: restores rebuild `instant_outbox` and keep the header, and bootstrap deliberately reasserts the blocker
    index for them, so the always-run statements stay.
12. **One encoding per save** (`c4341a12`). Saving a local write computed its receipt digest twice, lowered it for the
    wire three times, and encoded its body twice. `InstantEncodedOutboxMutation` carries each value computed once by
    the same functions; admission returns it and the save stores it. The stored bytes are unchanged; both digests are
    SQLite authority.

### Ranked cuts (hops removed per unit of risk)

| Cut | Hops removed per call | Risk | Status |
|---|---|---|---|
| Connection status in one turn | 5 per status (1 per transact, 2 on the drain) | Very low: read-only, same reads | This branch |
| `isOpen` only with a live transport | 1 per status | None: the value is unused without one | This branch |
| transact's reads in one turn | 5 | Low: same reads, same order, revision-checked save | This branch |
| Save plus status in one turn | 1 | Low | This branch |
| Server-apply gate flag without a hop | 1 per transact | Low: a hint; the server apply revalidates | This branch |
| Relaunch, query, inspection turns | 2 + 1 + 1 | Low | This branch |
| Explicit flush turns, empty reservations, batch outbox | 12 per window | Low to medium: error paths reordered with care | This branch |
| `liveSession.isOpen` mirror for apps with a transport (Scribe) | 1 per status | Low to medium: three writes of the flag | Next (v1.9.x) |
| Lock-based operation gate fast path | 2 per gated call | Medium: the central primitive, and under 200 contending tasks a `Mutex` burned 2x an actor's CPU (ep364@21:10) | Later |
| Store and persistence on one executor (ep363@17:36) | 2 per transact | High: serializes queries behind SQLite | Later, with measurement |
| Write-behind query results (#402's note on proposal 5) | the reader's per-frame cost | High | Later |

The CPU cuts, ranked by the profile's share per unit of risk:

| Cut | What it removes | Risk | Status |
|---|---|---|---|
| 8. One shared transport-date formatter | about 30% of transact's samples, 34% of the flush's | Low: byte-identical, pinned against the TS core | v1.9.1 |
| 9. Prepared-statement cache | statement preparation: 33% of bootstrap's samples, 14% of the flush's | Low to medium: statement lifetime, bounded and finalized on close and schema change | library-79-next |
| 10. One SQLite transaction per turn | a transaction per method and per lone statement in each turn | Medium: transaction scope changes; savepoints keep each method's atomicity | library-79-next |
| 11. One migration read at bootstrap | 25 `IMMEDIATE` transactions per launch | Low: a read of what migrate checked one at a time | library-79-next |
| 12. One encoding per save | 1 receipt digest, 2 lowerings, 1 body encode per local write | Low: the same functions, byte-identical rows | library-79-next |

## Results

**Hop counts** (load-independent; the benchmark's recorder with every call recorded, pinned by
`InstantCrossSDKRuntimeBenchmarkTests.runtimeWorkloadsPinEveryActorHop`):

| Workload | v1.8.0 as recorded | All calls at library-78's head (`2e2a1c07`) | This branch (`158a4515`) |
|---|---|---|---|
| transact | 9 | 19 | 7 (gate 2, persistence 2, store 2, status publish 1) |
| relaunch | 12 | 16 | 11 (gate 4, persistence 5, store 2) |
| reconnect drain | 29 | 50 | 25 (the explicit flush's five tasks remain) |

Scribe's transact, with a live transport, adds the open-flag read and the delivery pump request: about 9 calls, from 21.

**Wall time**: a paired ABBA through `heavy.sh` on 2026-10-02, load 200-350. Ten palindromic blocks
(v1.8.0, base, hops, hops plus the formatter, TypeScript core 1.0.49, then back), seven iterations per run. The figures
are each arm's median run p50, and the ratios are the median of the per-block ratios.

| Workload | v1.8.0 | Base `d95c9625` | Hops `158a4515` | Hops + formatter `55a15392` (v1.9.1) | TypeScript |
|---|---|---|---|---|---|
| transact | 1.65 ms | 1.69 ms | 1.65 ms (0.999x v1.8.0) | 1.09 ms (0.621x) | 0.23 ms |
| relaunch | 1.95 ms | 2.01 ms | 1.89 ms (0.949x) | 1.87 ms (0.937x) | 0.29 ms |
| reconnect drain | 2.65 ms | 2.66 ms | 2.67 ms (0.985x) | 1.76 ms (0.655x) | 0.36 ms |
| Swift / TypeScript | 7.4x, 6.9x, 7.4x | | 7.3x, 6.8x, 7.1x | **4.6x, 6.5x, 4.7x** | |

So the hop cuts are structural, not a speedup. An uncontended actor round trip from a `@concurrent` caller costs
about 0.1 µs on this Mac (2,000 calls, one global enqueue), so removing twelve of transact's nineteen hops saves about
a microsecond. The time is CPU work, which the profile names: in the base build, creating an `ISO8601DateFormatter`
per transport date was about 30% of transact's samples and 34% of the explicit flush's, and SQLite statement
preparation (no statement cache) was 31% of bootstrap. The shared formatter (`55a15392`) took transact and the drain
down by a third. Its output is byte-identical, pinned against the TypeScript core's own wire encoding of 79 dates.

**Behavior**: library-78's gate filters on the hop build match its run at `01175cff` (fast-drain 25 passed; ten
suites 697 tests, 22 known issues, the updated hop pins, one 250 ms timing test under load; infinite suites 211, 10
known plus #304; library-77/78 suites 106 passed), and the phone-shaped replay matches the `01175cff` reference in
every count (2,487 to 0, 119 frames, 17 rebases, 26,288 bodies, 2,384 accepted, 103 refused).

## Consequences

- An actor turn now runs up to six short SQLite statements back to back. Other persistence callers wait for the turn
  instead of interleaving; the statements are the same, so the total time on the actor does not grow.
- Reads that used to follow a throw-early check now run before it (for example, the outbox reads before the shared-root
  authorization). They are reads; the only side effect any of them can have is quarantining a row that cannot be
  decoded, which the next read would do anyway.
- The startup diagnostic `query-cache.pruned-at-bootstrap` is now recorded after the compact state loads.
- Tests that pinned hop counts now pin every call (BenchmarkTests' local-todos pins grow where calls were uncounted).

## Decisions and open questions

Michael, verbatim (2026-10-02 about 12:10 EDT, relayed by main): "Publish the library once it's checked fast. Yes."
and "Yes, you have full reign to push anything to production you want." Main's release plan put cuts 1 to 8 in v1.9.1
(the cache only if its own measurement passed first) and approved cuts 10 to 12 for after it.

Still open:

1. Make the live-session open flag hop-free for apps with a live transport, which is Scribe's case? It saves one hop
   per status publish, and every write publishes one. (Proposed: yes, next.)
2. Try the store and persistence on one executor only behind a measured A/B on Scribe's own workload, since it trades
   hops for queries waiting on SQLite writes? (Proposed: yes, later.)
