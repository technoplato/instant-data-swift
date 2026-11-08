# ADR 0015 step L3: aggregates derived when a query is read

- Status: **Shipped** (criterion `issue-155-L3-aggregate-group`)
- Date: 2026-11-08
- Drove it: Scribe #2005 slice 2 (a recording row's picture and thread counts, derived at read time with no second
  stored copy), decision 7e9e6e6f ("derived from rather than bolted on to"), the elegance line of 2026-11-07.

## What shipped

Three shapes, each the Instant counterpart of a SQLiteData one:

| SQLiteData | Instant Swift Data |
| --- | --- |
| `.group(by: \.id).leftJoin(Child.all) { ... }.select { Row.Columns(count: $1.id.count(filter: ...)) }` | `InstantFetchRequest(query, counting: Parent.children.count(where: ...)) { parent, count in Row(...) }` |
| `fetchAll(db, sectionBy: \.field)` / `@FetchAll(..., sectionBy:)` | `InstantFetchRequest(query).sectioned(by: \.field)` (or `order:` for sections sorted by name), observed with `@Fetch` |
| `.group(by: \.field).select { ($0.field, $0.count()) }` | `.sectioned(by: \.field)` then `.map { sections in ... section.count ... }` |

### Counts on rows

```swift
let pictureCount = Recording.attachments.count(where: .any(Attachment.kind == "image", Attachment.kind == "screenFrame"))
let threadCount = Recording.threads.count()

InstantFetchRequest(
  Recording.query.order(Recording.startedAtMs, .descending).limit(50),
  counting: pictureCount, threadCount
) { recording, pictures, threads in
  RecordingRow(recording: recording, pictureCount: pictures, threadCount: threads)
}
```

- `count(where:)` exists on a reverse relation (`InstantReverseRelation`) and on a forward many-link
  (`InstantAttributePath<Parent, InstantID<Child>>`, how Scribe's recordings hold their attachments).
- The request adds the counts to the query itself, so a count is declared once and arrives positionally, as L2's
  `children:` does. One to three counts per request.
- A request that decodes snapshots itself (Scribe's list request) adds counts with `query.counting(a, b)` and reads them
  with `snapshot.count(a)`. Reading a count the query does not count reports an issue and reads 0.
- When the query also includes the relation, the count covers that include's children (its `where` applies) before its
  `limit`: a row shows twelve pictures and how many more there are.

### Sections and grouped counts

`InstantResultsSectionCollection<Element, SectionName>` and `InstantResultsSection` copy SQLiteData's
`ResultsSectionCollection` and `ResultsSection`: `sectionNames`, `subscript(sectionName:)`, `contains(sectionName:)`,
`index(ofSectionNamed:)`, `RandomAccessCollection` of sections, each section an `Identifiable` (by name)
`RandomAccessCollection` of rows. Grouping runs once per emission, off the main thread, never in a view's body.

- `sectioned(by:)`: sections in the order of their first rows; rows keep the query's order within a section. A query
  ordered by what it sections by yields sections in that order (recordings newest first, sectioned by day: newest day
  first).
- `sectioned(by:order:)`: sections sorted by name (a `Comparable` name), as SQLiteData orders sections by their
  expression.
- `InstantFetchRequest(query)` (the rows, no transform) and `InstantFetchRequest.map(_:)` compose them.

## Decisions and why

1. **Counted on this device.** Instant answers aggregates for admin queries only (`instaql.clj` `query-one`:
   "Aggregates are currently only available for admin queries."; and "You can not combine aggregates with child queries
   at this time."), so a client cannot ask the server for a per-row count. The query brings the children down and the
   store counts them, the same adaptation upstream's client makes for a nested `limit` (`queryValidation.ts`:
   `// 'limit', // only supported client side`).
2. **A count rides as an include.** Each count is stored on its relation's `InstantQueryIncludePlan.counts` (a count
   alone makes a count-only include, `countOnly`). Every include-aware path then covers it unchanged: the wire, the
   observer's refresh decision (a changed child linked to a shown row refreshes it, #1007), the stored results, the
   ownership rows, validation. A separate plan field would have needed each of those taught again, and the observer's
   no-include fast paths would have left counts stale.
3. **Narrow on the wire, whole per row.** A count-only include asks for each child's `id` and the fields its counts'
   predicates read, filtered to the children some count admits (one predicate on the wire, or their `or`). A counted
   include goes up without its nested `limit`/`first`/`last`: the nested-limit pass trims stored results by the bounds
   written on the wire, so a bound there would leave a relaunch counting only the first rows. The server sends every
   child either way (it bounds top-level namespaces only, ADR 0015 Q32); the store still windows the include's rows.
4. **Never materializes a child row to count it.** The store reads only the fields the filters read, and a child no
   filter reads counts by its namespace membership alone.
5. **On the snapshot, optional.** `InstantEntitySnapshot.counts` (and `InstantLinkedEntitySnapshot.counts`, for counts
   on included rows) is nil when a query counts nothing. New plan fields are optional and added to the cache key only
   when present, so results stored before L3 decode and keep their keys. The answer digest (#1498) writes counts only
   when present, so a changed count rewrites the cached row and older rows keep their digests.
6. **Sections live in Core.** `InstantSwiftData` re-exports Core, so apps see them, and Core's cost tests can measure
   grouping alone.

## What it costs

Measured by `InstantCountedIncludeTests.countingTenThousandChildrenCostsLessThanLinkingThem`: one thread, the in-memory
store, 1,000 rows each linked by 10 children (10,000 children), two counts per row (all, and one kind); median of five.

| Shape (Mac mini, 2026-11-08) | Optimized: time | allocations | bytes | Debug: time | allocations |
| --- | --- | --- | --- | --- | --- |
| Count the children (L3) | 13.9-14.5 ms | 24,034 | 6.5 MB | 46.5 ms | 232,803 |
| Link every child as rows, count in the map (before L3) | 37.8 ms | 19,052 | 13.8 MB | 80.5 ms | 409,683 |
| 10,000 rows into 100 sections | 2.4-2.6 ms | 20,816 | 2.5 MB | 2.9 ms | 20,816 |

Counting is 2.7 times faster and allocates half the bytes, but about 26% more often: it reads each counted child's
field through a small snapshot. Reading the counted fields straight from the store's slots would remove most of those;
not done in this step. The optimized run built only the core test product (`swift build -c release -Xswiftc
-enable-testing --product InstantSwiftDataCoreTests`, run with `swiftpm-testing-helper`), three runs in one job.

The wire is the real cost: a count downloads one narrowed fact set per counted child on every refresh of its query,
because a refresh restates its result whole. Count relations with tens of children per row. For Scribe's list, count in
a query of its own (the threads or pictures of the page's recordings) rather than inside the list query, so a segment
written during a recording does not restate every counted child, and a new picture restates only the small query.

## Not done

- Counts other than `count` (min, max, sum): upstream's admin aggregate is `count` only; add when a screen needs one.
- A `@FetchAll(..., sectionBy:)` overload: `@Fetch` with `sectioned(by:)` gives the same result and observation.
- Server-side counts: wait for Instant to answer client aggregates.
