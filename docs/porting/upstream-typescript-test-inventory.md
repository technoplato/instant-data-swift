# Upstream InstantDB TypeScript — complete test inventory

**Source:** `<package root>/upstream/instant/client/packages` (github.com/instantdb/instant)  
**Commit:** `e71017612aed4031710a35e2fcace30d38d557ac 2026-06-11`  
**Packages enumerated:** `core`, `react` (plus `react-common`, `react-native`, `admin` — see §3)

| Number | Value | Meaning |
| --- | ---: | --- |
| Test files | 19 | in `core`; `react` has none |
| Declarations | 186 | `test(`/`it(` calls you can grep in source |
| **Runtime cases** | **225** | after expanding 1 `test.each` table (9) and 2 loop-generated `it`s (31 + 2) |
| Collected by vitest | 225 | every core file is `.ts` at this commit, so all of them run — see §1.1 |
| Offline-portable | 206 | excludes the 19 e2e cases needing a live app — see §1.2 |

Every row is greppable. To locate a test in the upstream tree:

```sh
cd upstream/instant/client/packages
grep -rn "<greppable>" core/__tests__/src
```

---

## 1. `@instantdb/core`

19 test files · 186 declarations · **225 runtime cases**.

### 1.1 Everything here is collected

`core/vitest.config.ts` defines two projects:

```js
{ name: 'e2e',  include: ['**/**.e2e.test.ts'] }
{ name: 'node', include: ['**/**.test.ts'], exclude: ['**/**.e2e.test.{ts,js}'] }
```

At this commit every core test file is `.ts`, so both globs bite and all 225 cases
run. Worth knowing because it is **not** true of every upstream commit: at
`337c2d40` (2026-03-31) three of these files were still `.js`, which neither glob
matches, and 16 cases — including all of `Reactor` — were silently collected by no
project. If this repository ever moves its vendored checkout backward or forward,
re-check that before trusting a green upstream run.

### 1.2 What the `.e2e.test.ts` files do

They are not "slower unit tests." Each **provisions a real Instant backend per test
case** and drives a real client against it, via `makeE2ETest` in
`core/__tests__/src/utils/e2e.ts`, which wraps vitest's `test.extend` with three
fixtures:

```ts
db:         POST {apiUrl}/dash/apps/ephemeral  { title: `e2e-${task.id}`, schema, rules }
            → init({ appId: app.id, apiURI, websocketURI, schema })
appId:      the ephemeral app's id
adminToken: the ephemeral app's admin token
```

So for **every case**: a throwaway app is created server-side with that test's
schema *and permission rules*, a real client connects over a real websocket, and
the admin token is handed to the test so it can call admin HTTP endpoints too.
`apiUrl` is `http://localhost:{8888 + DEV_SLOT}` locally and
`https://api.instantdb.com` when `CI=1`. They run under headless Chromium
(`@vitest/browser-playwright`), not node.

| File | Cases | What only a live backend can prove |
| --- | ---: | --- |
| `infiniteQuery.e2e.test.ts` | 12 | server-side cursors and page boundaries — duplicate boundary values across pages, rapid `loadNextPage` not double-fetching, an out-of-window update reordering into view, deletion mid-scroll |
| `auth-extra-fields.e2e.test.ts` | 4 | the magic-code round trip — a real code generated via admin API, redeemed, `$users` extra fields and the `created` flag checked for new and returning users |
| `cookieSync.e2e.test.ts` | 2 | the session-cookie sync decision on startup, against a real route handler |
| `simple.e2e.test.ts` | 1 | smoke: a real client connects and `queryOnce` |

Two consequences worth stating: these are the only upstream tests that exercise
*permission rules* at all (the `rules` argument to `makeE2ETest`), and the only
ones where a failure can mean "the server changed" rather than "the client
regressed."

### 1.3 The benchmark: `core/__tests__/src/instaql.bench.ts`

One `bench('big query')`, run by `pnpm bench` / `bench:ci` (`vitest bench`), never
by `pnpm test`. It builds a store from the Zeneca fixture
(`data/zeneca/attrs.json` + `triples.json`, 777 KB of triples) and repeatedly runs
one deeply nested read:

```ts
query(ctx, { users: { bookshelves: { books: {}, users: { bookshelves: {} } } } })
```

Four join levels with a **cycle** — `users → bookshelves → books` and
`users → bookshelves → users → bookshelves` — against a fixed fixture. It measures
join/materialization cost with no network and no I/O, which makes it the one
upstream number directly comparable to a Swift benchmark on the same fixture.

| Greppable | File | Kind |
| --- | --- | --- |
| `big query` | `core/__tests__/src/instaql.bench.ts:23` | `bench` |

The **only** benchmark in the entire `core` package.

### `core/__tests__/src/Reactor.test.ts`

6 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 34 | querySubs round-trips | `querySubs round-trips` |
| 107 | rewrite mutations | `rewrite mutations` |
| 153 | rewrite mutations works with multiple transactions | `rewrite mutations works with multiple transactions` |
| 203 | optimisticTx is not overwritten by refresh-ok | `optimisticTx is not overwritten by refresh-ok` |
| 360 | we don't cleanup mutations we're still waiting on | `we don't cleanup mutations we're still waiting on` |
| 414 | getLocalId always returns the same id | `getLocalId always returns the same id` |

### `core/__tests__/src/auth-extra-fields.e2e.test.ts`

4 runtime cases · vitest project: `e2e` · **needs a live app**

| Line | Test name | Greppable |
| ---: | --- | --- |
| 46 | new user with extraFields gets fields written and created=true | `new user with extraFields gets fields written and created=true` |
| 68 | returning user gets created=false | `returning user gets created=false` |
| 85 | sign in without extraFields works (backwards compat) | `sign in without extraFields works (backwards compat)` |
| 98 | admin verify_magic_code returns { user, created } for checkMagicCode | `admin verify_magic_code returns { user, created } for checkMagicCode` |

### `core/__tests__/src/cookieSync.e2e.test.ts`

2 runtime cases · vitest project: `e2e` · **needs a live app**

| Line | Test name | Greppable |
| ---: | --- | --- |
| 77 | syncs user cookie on startup when last sync is at least a day old | `syncs user cookie on startup when last sync is at least a day old` |
| 123 | does not sync user cookie on startup when last sync is recent | `does not sync user cookie on startup when last sync is recent` |

### `core/__tests__/src/datalog.test.ts`

5 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 27 | matchPattern | `matchPattern` |
| 60 | querySingle | `querySingle` |
| 68 | queryWhere | `queryWhere` |
| 84 | query | `query` |
| 108 | play | `play` |

### `core/__tests__/src/infiniteQuery.e2e.test.ts`

12 runtime cases · vitest project: `e2e` · **needs a live app**

| Line | Test name | Greppable |
| ---: | --- | --- |
| 48 | get initial data for useSyncExternalStore > empty result | `empty result` |
| 89 | infinite scroll number line > no order field | `no order field` |
| 118 | infinite scroll number line > adding new numbers | `adding new numbers` |
| 151 | infinite scroll number line > adding negative numbers | `adding negative numbers` |
| 192 | infinite scroll number line > add zero twice | `add zero twice` |
| 219 | unique queries > descending | `descending` |
| 254 | unique queries > duplicate boundary values across pages (desc) | `duplicate boundary values across pages (desc)` |
| 293 | unique queries > rapid loadNextPage calls do not duplicate pages | `rapid loadNextPage calls do not duplicate pages` |
| 324 | unique queries > deleting an item | `deleting an item` |
| 361 | unique queries > updating an out-of-window item can reorder into visible chunk | `updating an out-of-window item can reorder into visible chunk` |
| 397 | unique queries > page size 1, asc | `page size 1, asc` |
| 426 | unique queries > page size 1, desc | `page size 1, desc` |

### `core/__tests__/src/instaml.test.ts`

29 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 30 | simple update transform | `simple update transform` |
| 49 | undefined is ignored in update | `undefined is ignored in update` |
| 71 | ignores id attrs | `ignores id attrs` |
| 92 | optimistically adds attrs if they don't exist | `optimistically adds attrs if they don't exist` |
| 123 | lookup resolves attr ids | `lookup resolves attr ids` |
| 148 | lookup creates unique attrs for custom lookups | `lookup creates unique attrs for custom lookups` |
| 188 | lookup creates unique attrs for lookups in link values | `lookup creates unique attrs for lookups in link values` |
| 247 | lookup creates unique attrs for lookups in link values with arrays | `lookup creates unique attrs for lookups in link values with arrays` |
| 320 | lookup creates unique attrs for lookups in link values when fwd-ident exists | `lookup creates unique attrs for lookups in link values when fwd-ident exists` |
| 377 | lookup creates unique attrs for lookups in link values when rev-ident exists | `lookup creates unique attrs for lookups in link values when rev-ident exists` |
| 434 | lookup doesn't override attrs for lookups in link values | `lookup doesn't override attrs for lookups in link values` |
| 483 | lookup doesn't override attrs for lookups in self links | `lookup doesn't override attrs for lookups in self links` |
| 536 | lookup creates unique ref attrs for ref lookup | `lookup creates unique ref attrs for ref lookup` |
| 601 | lookup creates unique ref attrs for ref lookup in link value | `lookup creates unique ref attrs for ref lookup in link value` |
| 656 | lookups create entities from links | `lookups create entities from links` |
| 684 | lookups create entities from unlinks | `lookups create entities from unlinks` |
| 714 | mode: update | `mode: update` |
| 773 | it throws if you use an invalid link attr | `it throws if you use an invalid link attr` |
| 786 | it doesn't throw if you have a period in your attr | `it doesn't throw if you have a period in your attr` |
| 833 | it doesn't create duplicate ref attrs | `it doesn't create duplicate ref attrs` |
| 896 | Schema: uses info in \`attrs\` and \`links\` | `Schema: uses info in \`attrs\` and \`links\`` |
| 987 | Schema: doesn't create duplicate ref attrs | `Schema: doesn't create duplicate ref attrs` |
| 1058 | Schema: lookup creates unique attrs for custom lookups | `Schema: lookup creates unique attrs for custom lookups` |
| 1109 | Schema: lookup creates unique attrs for lookups in link values | `Schema: lookup creates unique attrs for lookups in link values` |
| 1193 | Schema: lookup creates unique attrs for lookups in link values with arrays | `Schema: lookup creates unique attrs for lookups in link values with arrays` |
| 1290 | Schema: lookup creates unique ref attrs for ref lookup | `Schema: lookup creates unique ref attrs for ref lookup` |
| 1376 | Schema: lookup creates unique ref attrs for ref lookup in link value | `Schema: lookup creates unique ref attrs for ref lookup in link value` |
| 1451 | Schema: populates checked-data-type | `Schema: populates checked-data-type` |
| 1587 | instatx should not be too permissive | `instatx should not be too permissive` |

### `core/__tests__/src/instaql.test.ts`

45 declarations → **53 runtime cases** · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 33 | Simple Query Without Where | `Simple Query Without Where` |
| 41 | Simple Where | `Simple Where` |
| 49 | Simple Where has expected keys | `Simple Where has expected keys` |
| 57 | Simple Where with multiple clauses | `Simple Where with multiple clauses` |
| 89 | Where in | `Where in` |
| 119 | Where %like% | `Where %like%` |
| 135 | Where like equality | `Where like equality` |
| 151 | Where startsWith deep | `Where startsWith deep` |
| 167 | Where endsWith deep | `Where endsWith deep` |
| 183 | like case sensitivity | `like case sensitivity` |
| 203 | like special regex characters | `like special regex characters` |
| 241 | Where and | `Where and` |
| 260 | Where OR multiple OR matches | `Where OR %s` |
| 260 | Where OR mix of matching and non-matching | `Where OR %s` |
| 260 | Where OR with and | `Where OR %s` |
| 260 | Where OR with references | `Where OR %s` |
| 260 | Where OR with references in both \`or\` & \`and\` clauses, no matches | `Where OR %s` |
| 260 | Where OR with references in both \`or\` & \`and\` clauses, with matches | `Where OR %s` |
| 260 | Where OR with nested ors | `Where OR %s` |
| 260 | Where OR with ands in ors | `Where OR %s` |
| 260 | Where OR with ands in ors in ands | `Where OR %s` |
| 383 | Get association | `Get association` |
| 397 | Get reverse association | `Get reverse association` |
| 411 | Get deep association | `Get deep association` |
| 435 | Nested wheres | `Nested wheres` |
| 456 | Nested wheres with OR queries | `Nested wheres with OR queries` |
| 479 | Nested wheres with AND queries | `Nested wheres with AND queries` |
| 502 | Deep where | `Deep where` |
| 512 | Missing etype | `Missing etype` |
| 516 | Missing inner etype | `Missing inner etype` |
| 529 | Missing filter attr | `Missing filter attr` |
| 539 | multiple connections | `multiple connections` |
| 565 | query forward references work with and without id | `query forward references work with and without id` |
| 588 | query reverse references work with and without id | `query reverse references work with and without id` |
| 619 | objects are created by etype | `objects are created by etype` |
| 639 | create and update triples in one tx | `create and update triples in one tx` |
| 675 | object values | `object values` |
| 697 | pagination limit | `pagination limit` |
| 709 | nested limit works but warns | `nested limit works but warns` |
| 733 | pagination offset waits for pageInfo | `pagination offset waits for pageInfo` |
| 830 | pagination last | `pagination last` |
| 842 | pagination first | `pagination first` |
| 854 | Leading queries should ignore the start cursor | `Leading queries should ignore the start cursor` |
| 945 | Leading queries should ignore the end cursor for optimistic adds | `Leading queries should ignore the end cursor for optimistic adds` |
| 1000 | arbitrary ordering | `arbitrary ordering` |
| 1020 | arbitrary ordering with dates | `arbitrary ordering with dates` |
| 1139 | arbitrary ordering with strings | `arbitrary ordering with strings` |
| 1181 | $isNull | `$isNull` |
| 1196 | $isNull with relations | `$isNull with relations` |
| 1233 | $isNull with reverse relations | `$isNull with reverse relations` |
| 1249 | $not and $ne | `$not and $ne` |
| 1266 | comparators | `comparators` |
| 1343 | fields | `fields` |

### `core/__tests__/src/instaqlInference.test.ts`

3 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 7 | many-to-many with inference | `many-to-many with inference` |
| 84 | one-to-one with inference | `one-to-one with inference` |
| 161 | one-to-one without inference | `one-to-one without inference` |

### `core/__tests__/src/queryValidation.test.ts`

14 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 99 | validates top level types | `validates top level types` |
| 106 | top level entitiy names | `top level entitiy names` |
| 131 | links | `links` |
| 157 | dollar sign object | `dollar sign object` |
| 185 | all valid dollar sign keys | `all valid dollar sign keys` |
| 240 | where clause type validation | `where clause type validation` |
| 306 | where clause operators | `where clause operators` |
| 506 | where clause unknown operators | `where clause unknown operators` |
| 518 | where clause unknown attributes | `where clause unknown attributes` |
| 530 | where clause id validation | `where clause id validation` |
| 565 | where clause logical operators | `where clause logical operators` |
| 600 | where clause dot notation validation | `where clause dot notation validation` |
| 795 | pagination parameters can only be used at top-level namespaces | `pagination parameters can only be used at top-level namespaces` |
| 983 | relations with complex objects | `relations with complex objects` |

### `core/__tests__/src/schema.test.ts`

1 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 11 | runs without exception | `runs without exception` |

### `core/__tests__/src/serializeSchema.test.ts`

1 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 106 | ability to parse stringified schema into real schema object | `ability to parse stringified schema into real schema object` |

### `core/__tests__/src/simple.e2e.test.ts`

1 runtime cases · vitest project: `e2e` · **needs a live app**

| Line | Test name | Greppable |
| ---: | --- | --- |
| 4 | can make a query | `can make a query` |

### `core/__tests__/src/store.test.ts`

17 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 91 | simple add | `simple add` |
| 103 | cardinality-one add | `cardinality-one add` |
| 121 | link/unlink | `link/unlink` |
| 170 | link/unlink multi | `link/unlink multi` |
| 226 | link/unlink without update | `link/unlink without update` |
| 257 | delete entity | `delete entity` |
| 311 | on-delete cascade | `on-delete cascade` |
| 347 | on-delete-reverse cascade | `on-delete-reverse cascade` |
| 388 | new attrs | `new attrs` |
| 412 | delete attr | `delete attr` |
| 444 | update attr | `update attr` |
| 481 | JSON serialization round-trips | `JSON serialization round-trips` |
| 486 | ruleParams no-ops | `ruleParams no-ops` |
| 501 | deepMerge | `deepMerge` |
| 565 | recursive links w same id | `recursive links w same id` |
| 637 | date conversion | `date conversion` |
| 703 | v0 store restores | `v0 store restores` |

### `core/__tests__/src/transactionValidation.test.ts`

20 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 88 | validates basic transaction chunk | `validates basic transaction chunk` |
| 98 | validates transaction chunk arrays | `validates transaction chunk arrays` |
| 109 | validates create operations | `validates create operations` |
| 154 | validates update operations | `validates update operations` |
| 172 | validates merge operations | `validates merge operations` |
| 182 | validates delete operations | `validates delete operations` |
| 189 | validates link operations | `validates link operations` |
| 210 | validates unlink operations | `validates unlink operations` |
| 225 | validates entity existence | `validates entity existence` |
| 244 | validates attribute types | `validates attribute types` |
| 282 | validates transaction chunk structure | `validates transaction chunk structure` |
| 298 | validates operation structure | `validates operation structure` |
| 305 | validates chained operations | `validates chained operations` |
| 325 | validates multiple entity types | `validates multiple entity types` |
| 341 | validates link relationships | `validates link relationships` |
| 360 | validates without schema | `validates without schema` |
| 371 | validates UUID format for entity IDs | `validates UUID format for entity IDs` |
| 390 | allows lookup values in square bracket | `allows lookup values in square bracket` |
| 397 | allows lookup values in link | `allows lookup values in link` |
| 402 | lookup proxy | `lookup proxy` |

### `core/__tests__/src/utils/PersistedObject.test.ts`

7 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 22 | PersistedObject saves values to storage | `PersistedObject saves values to storage` |
| 50 | PersistedObject merges existing values | `PersistedObject merges existing values` |
| 124 | PersistedObject notifies you when it loads a key from storage | `PersistedObject notifies you when it loads a key from storage` |
| 142 | PersistedObject garbage collects when we exceed max items | `PersistedObject garbage collects when we exceed max items` |
| 222 | PersistedObject garbage collects when we exceed max size | `PersistedObject garbage collects when we exceed max size` |
| 308 | PersistedObject garbage collects when we exceed max age | `PersistedObject garbage collects when we exceed max age` |
| 395 | IndexedDBStorage recovers when the database connection closes | `IndexedDBStorage recovers when the database connection closes` |

### `core/__tests__/src/utils/dates.test.ts`

5 declarations → **36 runtime cases** · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 43 | coerceToDate > parse-date-value-works-for-valid-dates > should parse ${dateString} to ${expected} _(×31 generated)_ | `should parse ${dateString} to ${expected}` |
| 55 | coerceToDate > parse-date-value-throws-for-invalid-dates > throws for invalid date string: ${dateString} _(×2 generated)_ | `throws for invalid date string: ${dateString}` |
| 62 | coerceToDate > additional edge cases > should handle Date instances | `should handle Date instances` |
| 68 | coerceToDate > additional edge cases > should handle number timestamps | `should handle number timestamps` |
| 77 | coerceToDate > additional edge cases > should throw for unsupported types | `should throw for unsupported types` |

### `core/__tests__/src/utils/object.test.ts`

7 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 10 | assocInMutative > adds value at a shallow path | `adds value at a shallow path` |
| 16 | assocInMutative > adds value at a nested path | `adds value at a nested path` |
| 24 | insertInMutative > it works on normal objects | `it works on normal objects` |
| 34 | insertInMutative > inserts on arrays | `inserts on arrays` |
| 62 | dissocInMutative > deletes a shallow property | `deletes a shallow property` |
| 68 | dissocInMutative > deletes a nested property | `deletes a nested property` |
| 73 | dissocInMutative > works on arrays | `works on arrays` |

### `core/__tests__/src/utils/weakHash.test.ts`

6 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 6 | no collisions across many integer-varying queries | `no collisions across many integer-varying queries` |
| 37 | is stable across object key order and undefined values | `is stable across object key order and undefined values` |
| 41 | keeps array and top-level undefined explicit | `keeps array and top-level undefined explicit` |
| 47 | distinguishes objects by their toJSON output | `distinguishes objects by their toJSON output` |
| 54 | handles bigint values without throwing | `handles bigint values without throwing` |
| 64 | produces a stable hash for a known query | `produces a stable hash for a known query` |

### `core/__tests__/src/utils/weakHashLegacy.test.ts`

1 runtime cases · vitest project: `node`

| Line | Test name | Greppable |
| ---: | --- | --- |
| 8 | produces a stable hash for a known query | `produces a stable hash for a known query` |

---

## 2. `@instantdb/react`

**The react package has zero runtime tests.** Verified four ways:

- no `*.test.*` / `*.spec.*` file anywhere under `react/` (the one `find` hit is
  `tsconfig.test.json`, a config file)
- no `__tests__` directory
- `grep -rnE "(test|it|describe|expect)\s*\(" react/src/` returns nothing
- `react/package.json` sets `"test:ci": "pnpm run test:types"` — CI runs the type
  checker and nothing else. Compare `core`, whose `test:ci` is
  `vitest run && pnpm run test:types`.

What it has is one **compile-time** type-assertion file, checked by
`tsc -p tsconfig.test.json --noEmit`. These pin inferred types, not behavior, so
they have no runtime analogue to port — the Swift equivalent is the type system
doing its job, or a test that would fail to compile if inference broke.

### `react/src/__types__/typesTests.ts`

4 assertion functions

| Line | Assertion function | Greppable |
| ---: | --- | --- |
| 13 | `_testUseDatesTest` | `_testUseDatesTest` |
| 34 | `_testUseDatesFalseTest` | `_testUseDatesFalseTest` |
| 55 | `_testUseDatesUndefinedTest` | `_testUseDatesUndefinedTest` |
| 75 | `_testDataNoSchema` | `_testDataNoSchema` |

`react-native/src/__types__/typesTests.ts` duplicates the same functions.

---

## 3. Every other client package, for completeness

Enumerated so "core and react" is provably the whole client-facing surface.

| Package | Test files | Note |
| --- | ---: | --- |
| `core` | 19 | §1 — the whole runtime suite |
| `react` | 0 | §2 — type tests only |
| `react-common` | 0 | no tests |
| `react-native` | 0 | type tests only, duplicate of react's |
| `react-native-mmkv` | 0 | — |
| `admin` | 0 | `test:ci` is type-check only |
| `solidjs` | 0 | — |
| `version` | 0 | — |
| `python` | 0 | tests live outside `packages/` |
| `cli` | 17 | tooling, not client behavior |
| `platform` | 7 | platform/OAuth API, not client behavior |
| `webhooks` | 3 | server-side |
| `svelte` | 1 | other framework binding |
| `vue` | 1 | other framework binding |
| `resumable-stream` | 1 | tooling |
| `mcp` | 1 | tooling |
| `components` | 1 | — |
| `create-instant-app` | 1 | — |

---

## 4. Using this as the Swift port's coverage target

Three tiers, in porting order:

1. **206 offline-portable cases** (the `node` project) — pure, no server.
2. **19 e2e cases** — `auth-extra-fields` (4), `cookieSync` (2), `infiniteQuery`
   (12), `simple` (1). Each provisions a real ephemeral app; see §1.2. These map
   onto the library's live-acceptance gate, not the unit suite.
3. **1 benchmark** — §1.3.

Reconciliation against `InstantParityCoverage.swift` lives in
`docs/porting/swift-port-gap-analysis.md`, and is enforced by
`Tests/InstantSwiftDataCoreTests/InstantUpstreamParityReconciliationTests.swift`.

### Reproducing this inventory

The reconciliation suite re-derives these counts from the vendored checkout on
every run and fails if they move, so the numbers above cannot silently rot.
