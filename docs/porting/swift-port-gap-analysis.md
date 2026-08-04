# Swift port — gap analysis against the upstream inventory

Companion to [`upstream-typescript-test-inventory.md`](upstream-typescript-test-inventory.md).
That document says what upstream has. This one says what we have, what has to
change, and what still has to be written.

**Upstream at** `e71017612aed4031710a35e2fcace30d38d557ac` (2026-06-11) ·
vendored at `upstream/instant` · **Swift tree** is the working tree that carries
this file.

---

## 1. Headline

The behavioral port of `@instantdb/core` is **substantially complete** — far more
complete than a naive count of parity records suggests. The remaining work is
mostly *hygiene and enforcement*, plus one genuine missing artifact (the
benchmark).

| Measure | Value |
| --- | ---: |
| Upstream core test files | 19 |
| Upstream core declarations | 186 |
| Upstream core runtime cases | 225 |
| Swift `@Test` cases in the library | 1338 |
| Parity records in `InstantParityCoverage.swift` | 250 (176 citing core) |
| Upstream declarations with a parity record | **186 / 186** |
| — recorded `exact` | 30 |
| — recorded `adapted` | 140 |
| — recorded `notApplicable` | 1 |
| Upstream benchmarks with a Swift equivalent | **0 / 1** |

The two counts that looked like large gaps on first pass were **false alarms**,
and both were checked case-by-case rather than by record count:

- **Date coercion.** The registry holds a few records against 33 upstream runtime
  cases (31 valid + 2 invalid, loop-generated from one declaration each), which
  looked like a hole by record count. It is not: `InstantDateCoercionTests`
  drives a table containing **all** upstream date strings, plus 3 Swift-only
  cases upstream does not have (`2026-04-28T04:7:00.000Z`,
  `2026-04-28T4:07:00.000Z`, `2026-04-28T04:07:7.000Z`). Coverage here is a
  superset.
- **`Where OR` (`test.each`, 9 rows).** One record, but
  `InstantQueryExecutionParityTests` asserts all nine upstream row labels
  individually, including the two awkward ones —
  ``with references in both `or` & `and` clauses, no matches`` and
  ``…, with matches``.

The lesson for anything below: **a parity record is a claim about a Swift test,
not a measurement of it.** One record routinely covers several upstream cases, so
record counts under-report coverage, and a record can also over-claim. Only
case-level checks settle it.

---

## 2. What needs altering

### 2.1 A stale Swift test name, cited by four records — **defect**

Four records name `staticFetchAllStartsObservationWithoutTaskOrLoad`. No such
test exists. The real one is
`staticFetchAllStartsObservationOnFirstReadWithoutTaskOrLoad`
(`Tests/InstantSwiftDataTests/TypedAPITests.swift:4684`) — the registry is missing
`OnFirstRead`.

Affected records: `instant.svelte.use-query-starts-loading`,
`instant.svelte.use-query-subscribes-on-mount`,
`instant.vue.use-query-starts-loading`,
`instant.vue.use-query-subscribes-when-mounted`.

Nothing catches this today, which is the real problem — see §4.

### 2.2 Paraphrased upstream test names — **blocks automation**

Many records store a *description* where the upstream test's literal name belongs:

| Record | `sourceTestName` stored | Upstream literal |
| --- | --- | --- |
| `instant.query.logical-or` | `Where OR test.each` | `Where OR %s` (9 rows) |
| `instant.auth-extra-fields.magic-code` | `magic-code sign-in creates $users extra fields, returns created flag, and reports returning users` | four separate tests |
| `instant.datalog.pattern-query` | `matchPattern / query` | two tests (this form is fine) |
| `instant.persisted-object.indexeddb-connection-recovery` | `IndexedDBStorage recovers when the database connection closes` | no such upstream test |

The `a / b` join form is good and should stay — it honestly records one Swift test
covering several upstream ones. The problem is the *paraphrases*: they make it
impossible to mechanically answer "did upstream add a test we have not ported?"
Twenty core-citing records currently fail to resolve to any upstream test name.

**Change:** `sourceTestName` must hold upstream's literal string, joined with
` / ` when one Swift test covers several. Where the Swift test genuinely has no
1:1 upstream counterpart, keep the prose in `notes` and leave `sourceTestName`
empty rather than inventing a name.

### 2.3 Records that cite a non-existent upstream test

`instant.persisted-object.indexeddb-connection-recovery` names an upstream test
that is not in `PersistedObject.test.ts` (which has 6: saves values, merges
existing values, load notification, gc max items, gc max size, gc max age). Either
it was written against an older upstream, or it is a Swift-only test mislabeled as
a port. Resolve it, do not delete the Swift test.

---

## 3. What needs writing

### 3.1 The benchmark — **the one real missing artifact**

Upstream's only benchmark, `instaql.bench.ts` `big query`, has **no Swift
equivalent and no parity record.**

What exists on the Swift side today:

| Where | What |
| --- | --- |
| `benchmarks/Benchmarks/InstantSwiftDataBenchmarking/Benchmarks.swift` | `LocalWrite.transact.100`, `LocalRead.queryOnce.after1kWrites`, `LocalStore.reopen.with1kEntities` |
| `benchmarks/upstream-instant/{write,observe,shared}.ts` | TypeScript counterparts for cross-SDK comparison |
| `Tests/…/InstantCrossSDKBenchmarkTests.swift` | pins that both SDKs run equivalent operation counts |
| `Tests/…/BenchmarkTests.swift` | `benchmark.local.todos` determinism |

All three Swift workloads are **write/reopen** shaped. None of them is a
**deep-join read against a fixed fixture**, which is precisely what upstream's
one benchmark measures. So the comparison the user asked for — "similar, equal, if
not better" — currently cannot be made at all on that axis.

To write:

1. `LocalRead.deepJoin.zeneca` in the Swift benchmark suite: load the same
   `data/zeneca/{attrs,triples}.json` fixture and run the same four-level cyclic
   query (`users → bookshelves → {books, users → bookshelves}`).
2. `benchmarks/upstream-instant/deep-join.ts` running upstream's identical query,
   so the cross-SDK harness compares like with like on the same fixture.
3. A record `instant.instaql.bench.big-query` with a new
   `InstantParityCoverageSourceKind` for benchmarks, so the bench is tracked the
   same way tests are.
4. Extend `InstantCrossSDKBenchmarkTests` to pin the new workload's operation
   count, matching how the existing three are pinned.

### 3.2 Nothing else

Every one of the 186 upstream declarations resolves to a parity record, and the
two coarse-record areas that looked thin (dates, OR) were verified case-by-case
above. There is no upstream behavioral test without a Swift counterpart.

That claim is only as good as the check behind it — hence §4.

---

## 4. The thing that actually matters: make this checkable — **done**

Everything in §2 was found by hand. Nothing in the repository failed
when:

- upstream adds a test (we would not know)
- a Swift test is renamed and a record goes stale (§2.1 — happened, four times)
- a record cites an upstream test that does not exist (§2.3 — happened)
- a record is added with a paraphrased name (§2.2 — happened ~20 times)

`InstantParityCoverage.swift` already models status and completeness, and
`runParityCoverageValidation` already exists in the test harness. What is missing
is the *other* direction: reconciling the registry against real upstream source.

`Tests/InstantSwiftDataCoreTests/InstantUpstreamParityReconciliationTests.swift`
now closes that loop with six source invariants:

| Test | Asserts |
| --- | --- |
| `swiftTestNamesResolve` | every `swiftTestName` component is a `func` in `Tests/` |
| `coveredRecordsNameBothSides` | an `exact`/`adapted` record names both sides |
| `citedUpstreamTestNamesExist` | every core-citing `sourceTestName` exists upstream |
| `upstreamSurfaceMatchesTheRecordedInventory` | upstream is still 19 files / 186 declarations / 225 runtime cases |
| `everyUpstreamTestHasARecord` | no upstream test lacks a record |
| `upstreamCheckoutIsAtThePinnedCommit` | the checkout is at `e7101761`, the commit the documents describe |

The fourth is what keeps the other two honest: an extractor that quietly stops
recognizing a declaration form finds fewer tests, so fewer names need records and
everything goes green while coverage silently drops. It caught exactly that during
development — the Swift extractor initially missed the loop-generated date cases
and under-counted the runtime surface.

The suite needs the pinned `instantdb/instant` checkout; when it is absent the
upstream-facing tests record why (naming the expected path and the
`INSTANT_UPSTREAM_CHECKOUT` override) and return, so the suite still runs without
it.

---

## 5. Order of work

| Step | Change | Status |
| --- | --- | --- |
| 1 | Fix the stale `staticFetch…` names (§2.1) | **done** — 5 records, including a `staticFetchRequest…` variant found by the new suite |
| 2 | Add the reconciliation tests (§4) | **done** — 6 invariants, all passing |
| 3 | Replace paraphrased `sourceTestName`s with upstream literals (§2.2), resolve §2.3 | **done** — see below |
| 4 | Port `instaql.bench.ts` (§3.1) — Swift workload, TS counterpart, record, cross-SDK pin | open |
| 5 | Record measured Swift-vs-TypeScript numbers for the deep-join query | open |

### What step 3 turned up

Running the new suite against the registry surfaced more than the hand audit had:

| Record(s) | Was | Now |
| --- | --- | --- |
| `instant.query.logical-or` | `Where OR test.each` | the 9 literal row names |
| `instant.auth-extra-fields.magic-code` | one paraphrase | the 4 literal upstream names |
| `instant.query.leading-ignores-end-cursor` | `…ignore the end cursor for optimistic adds` | `Leading queries should ignore the start cursor` |
| `instant.transaction-validation.lookup-rule-params` | `lookup refs and rule params` | `allows lookup values in square bracket / allows lookup values in link / lookup proxy` |
| 8 × `instant.weak-hash*` | cited `__tests__/src/utils/weakHash{,Legacy}.test.ts` | **neither file exists upstream** — repointed at `src/utils/weakHash.ts`, the source they were really derived from |
| 2 × `instant.cookie-sync.*` | cited `__tests__/src/cookieSync.e2e.test.ts` | **does not exist upstream** — repointed at the three source files that do |
| `instant.persisted-object.indexeddb-connection-recovery` | cited a non-existent upstream test | source-derived from `src/utils/PersistedObject.ts` |
| 3 files (historical) | at older upstream commits were `.js` and never collected by vitest | at `e7101761` they are `.ts` and fully collected — §1.1 of the inventory |
| `instant.python.stream-append-materialization` | cited a suite name as a test | the 5 test funcs in it |

Several registry rows cited **files that do not exist as tests** at this commit
(weak-hash unit tests, a cookieSync e2e suite path, an IndexedDB connection-
recovery test name). The Swift tests behind them are real and worth keeping; what
was wrong was the claim that they port an upstream *test* rather than upstream
*source*. The registry already models source-derived records elsewhere
(`Reactor.js`, `infiniteQuery.ts`, `routeHandlerProtocol.ts`), so they now follow
that convention and the reconciliation skips them by design.
