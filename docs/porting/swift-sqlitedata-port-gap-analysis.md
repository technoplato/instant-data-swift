# Swift Instant port — gap analysis against SQLiteData inventory

Companion to [`upstream-sqlitedata-test-inventory.md`](upstream-sqlitedata-test-inventory.md).
That document says what Point-Free SQLiteData has. This one says what Instant has,
what is adapted, and what needs human attention.

**Upstream at** `0c79d7a5748fc6d9ce7a1ba2b50f31b175305049` · vendored at
`upstream/sqlite-data` · **261 runtime tests** (verified twice; see inventory).

---

## 1. Headline

| Measure | Value |
| --- | ---: |
| Upstream runtime tests | 261 |
| Core library (non-CloudKit) | 57 |
| CloudKit / SyncEngine | 186 |
| Example app tests | 18 |
| Instant `sqlite.*` parity records (before this work) | 41 |
| Instant `sqlite.*` parity records (after inventory completion) | 263 |
| Upstream tests with a parity record | **261 / 261** |

SQLiteData ergonomics that Instant is *supposed* to match (fetch wrappers, drafts,
example models, concurrency, cancellation) were largely already ported. This pass
makes that **checkable** and closes the remaining portable core holes (date
roundtrip, assertQuery-shaped materialization dumps, empty batches, selection
initializer edges, example names that were only paraphrased).

---

## 2. Human attention required

These are deliberate Instant ≠ SQLiteData boundaries. Do **not** “port” them by
pretending Instant is GRDB.

### 2.1 CloudKit SyncEngine suite — **186 tests, `notApplicable`**

Almost the entire CloudKit folder is Apple CloudKit plumbing:

- account lifecycle / soft log-out
- zone change batches, metadatabase, CKShare permissions
- mock CloudKit database, record types, assets as CKAsset
- SyncEngine start/stop, schema triggers

**Instant equivalent domain** is optimistic outbox + Instant sharing + live
websocket — covered elsewhere (`InstantLiveShare*`, outbox, CloudKit *demo*
V3 ports). Mapping each CloudKit SyncEngine test 1:1 would mean reimplementing
CloudKit inside Instant, which is the wrong product.

**Human decision if ever needed:** which *domain rules* (e.g. “sharee cannot
mutate owner-private fields”) still need Instant-native tests beyond what
exists. That is a product checklist, not a mechanical port.

### 2.2 SQL-only surfaces — **`notApplicable`**

| Upstream | Why Instant cannot port literally |
| --- | --- |
| `AssertQueryTests` `*IncludeSQL` (2) | Dumps raw SQL text; Instant has no SQL |
| `DatabaseFunctionTests` (2) | SQLite UDFs |
| `CustomFunctionTests.basics` (1) | SQLite UDF add/remove |
| `PrimaryKeyMigrationTests` (13) | Integer/rowid → UUID table rewrites |

**Adapted instead:** the non-SQL half of `AssertQueryTests` (6) now dumps
stable Instant materialization rows via
`assertQueryStyleMaterializationSnapshotsMatchExpectedTables`.

### 2.3 Instant always optimistic / multi-device

Every Instant query is local-first with an outbox. SQLiteData tests that assume
“the `DatabaseQueue` is the only writer” still pass as **local** Instant
tests, but they do **not** prove cross-device convergence. Cross-device is a
separate live-acceptance gate.

---

## 3. What was ported or linked this pass

| Upstream | Instant | Status |
| --- | --- | --- |
| `DateTests.roundtrip` | `dateAttributeRoundtripInsertUpdateMaterializesEqualValue` | **new adapted test** |
| `AssertQueryTests` (6 non-SQL) | `assertQueryStyleMaterializationSnapshotsMatchExpectedTables` | **new adapted test** |
| `QueryCursorTests` empty insert/update | `emptyRuntimeTransactionDoesNotPersistPendingMutation` | linked |
| `MigrationTests.dates` | existing date conversion/coercion tests | linked |
| FetchOne selection edges | existing TypedAPI selection/animation tests | linked |
| `RemindersListsTests.move` | `remindersListsModelMovesSourceListToFront` | linked |
| `SearchRemindersTests.deleteCompleted` | existing search model port | linked |
| `SyncUpFormTests.saveNew` | existing form model port | linked |

---

## 4. Enforcement

`Tests/InstantSwiftDataCoreTests/InstantSQLiteDataParityReconciliationTests.swift`
pins:

1. vendored checkout is at `0c79d7a…`
2. extractor still sees **261** upstream runtime tests
3. every upstream test name is cited by some `sqlite-data` parity record
4. every `adapted`/`exact` record names a real Swift test `func`

---

## 5. Order of work

| Step | Status |
| --- | --- |
| 1 Inventory all upstream tests | **done** — 261, dual-method + subagent |
| 2 Gap analysis + human callouts | **done** — this file |
| 3 Port remaining portable core | **done** — ergonomics suite |
| 4 Record every test in parity registry | **done** — 222 new rows |
| 5 Reconciliation suite | **done** |
| 6 Optional: Instant-native domain ports of selected CloudKit *rules* | open, needs human prioritization |
