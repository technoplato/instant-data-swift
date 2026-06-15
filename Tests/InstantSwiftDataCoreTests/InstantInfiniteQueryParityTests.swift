import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantInfiniteQueryParityTests {
  @Test
  func upstreamInfiniteQueryInitialSnapshotMatchesLiveSubscriptionData() async throws {
    let runtime = try await infiniteQueryRuntime()
    let plan = infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    let subscription = await runtime.subscribeInfiniteQuery(plan)
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "initial", in: runtime)
    let live = try #require(await iterator.next())
    expectNoDifference(loadedValues(live), [0, 1, 2, 3], infiniteInitialSnapshotSource)

    let initialSnapshot = try await runtime.infiniteQueryInitialSnapshot(plan)
    expectNoDifference(loadedValues(initialSnapshot), loadedValues(live), infiniteInitialSnapshotSource)
    expectNoDifference(initialSnapshot.canLoadNextPage, false, infiniteInitialSnapshotSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryNoOrderFieldUsesImplicitStableOrder() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(infiniteItemsQuery(limit: 4, order: nil))
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "no-order", in: runtime)
    let snapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(snapshot), [0, 1, 2, 3], infiniteNoOrderSource)
    #expect(loadedValues(snapshot) != [3, 2, 10, 1, 2, 3])
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryAddingNewNumbersLoadsNextPageOnDemand() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "first", in: runtime)
    let firstPageSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(firstPageSnapshot), [0, 1, 2, 3], infiniteAddingNewNumbersSource)

    try await upsertNumberItems([5, 6, 7, 8], prefix: "second", in: runtime)
    let beforeLoad = try #require(await iterator.next())
    expectNoDifference(loadedValues(beforeLoad), [0, 1, 2, 3], infiniteAddingNewNumbersSource)
    expectNoDifference(beforeLoad.canLoadNextPage, true, infiniteAddingNewNumbersSource)

    subscription.loadNextPage()
    let afterLoad = try #require(await iterator.next())
    expectNoDifference(loadedValues(afterLoad), [0, 1, 2, 3, 5, 6, 7, 8], infiniteAddingNewNumbersSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryAddingNegativeNumbersPrependsLeadingRows() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "non-negative", in: runtime)
    let nonNegativeSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(nonNegativeSnapshot), [0, 1, 2, 3], infiniteNegativeNumbersSource)

    try await upsertNumberItems([-1], prefix: "negative-one", in: runtime)
    let negativeOneSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(negativeOneSnapshot), [-1, 0, 1, 2, 3], infiniteNegativeNumbersSource)

    try await upsertNumberItems([-4], prefix: "negative-four", in: runtime)
    let negativeFourSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(negativeFourSnapshot), [-4, -1, 0, 1, 2, 3], infiniteNegativeNumbersSource)

    try await upsertNumberItems([-2], prefix: "negative-two", in: runtime)
    let negativeTwoSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(negativeTwoSnapshot), [-4, -2, -1, 0, 1, 2, 3], infiniteNegativeNumbersSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryAddZeroTwiceKeepsDuplicateSortValues() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value", .descending))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberEntries(
      [("zero-a", 0), ("zero-b", 0)],
      transactionID: "tx-zero-twice",
      in: runtime
    )
    let duplicateZeroSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(duplicateZeroSnapshot), [0, 0], infiniteZeroTwiceSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryDescendingLoadsDuplicateLowerValues() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value", .descending))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([4, 5], prefix: "desc-top", in: runtime)
    let descendingTopSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(descendingTopSnapshot), [5, 4], infiniteDescendingSource)

    try await upsertNumberItems([1], prefix: "desc-one", in: runtime)
    let descendingOneSnapshot = try #require(await iterator.next())
    expectNoDifference(loadedValues(descendingOneSnapshot), [5, 4, 1], infiniteDescendingSource)

    try await upsertNumberEntries(
      [("desc-one-duplicate", 1), ("desc-two", 2), ("desc-three", 3)],
      transactionID: "tx-desc-more",
      in: runtime
    )
    let beforeLoad = try #require(await iterator.next())
    expectNoDifference(loadedValues(beforeLoad), [5, 4, 3, 2], infiniteDescendingSource)
    expectNoDifference(beforeLoad.canLoadNextPage, true, infiniteDescendingSource)

    subscription.loadNextPage()
    let afterLoad = try #require(await iterator.next())
    expectNoDifference(loadedValues(afterLoad), [5, 4, 3, 2, 1, 1], infiniteDescendingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryDuplicateBoundaryValuesAcrossDescendingPages() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 3, order: InstantQueryOrder("value", .descending))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberEntries(
      [
        ("value-5", 5),
        ("value-4", 4),
        ("value-3", 3),
        ("value-2-a", 2),
        ("value-2-b", 2),
        ("value-2-c", 2),
        ("value-1", 1),
      ],
      transactionID: "tx-desc-boundary",
      in: runtime
    )
    let firstPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(firstPage), [5, 4, 3], infiniteDuplicateBoundarySource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteDuplicateBoundarySource)

    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(secondPage), [5, 4, 3, 2, 2, 2], infiniteDuplicateBoundarySource)
    expectNoDifference(secondPage.canLoadNextPage, true, infiniteDuplicateBoundarySource)

    subscription.loadNextPage()
    let finalPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(finalPage), [5, 4, 3, 2, 2, 2, 1], infiniteDuplicateBoundarySource)
    expectNoDifference(finalPage.canLoadNextPage, false, infiniteDuplicateBoundarySource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryLoadNextPageDoesNotDuplicatePages() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([1, 2, 3, 4, 5, 6], prefix: "rapid", in: runtime)
    let firstPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(firstPage), [1, 2], infiniteRapidLoadSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteRapidLoadSource)

    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(secondPage), [1, 2, 3, 4], infiniteRapidLoadSource)
    expectNoDifference(secondPage.canLoadNextPage, true, infiniteRapidLoadSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryDeletingLoadedItemKeepsNextPageClosed() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([1, 2, 3, 4, 5, 6], prefix: "delete", in: runtime)
    let firstPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(firstPage), [1, 2, 3, 4], infiniteDeletingSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteDeletingSource)

    subscription.loadNextPage()
    let loaded = try #require(await iterator.next())
    expectNoDifference(loadedValues(loaded), [1, 2, 3, 4, 5, 6], infiniteDeletingSource)
    expectNoDifference(loaded.canLoadNextPage, false, infiniteDeletingSource)

    try await deleteNumberItem("delete-2-3", transactionID: "tx-delete-three", in: runtime)
    let deleted = try #require(await iterator.next())
    expectNoDifference(loadedValues(deleted), [1, 2, 4, 5, 6], infiniteDeletingSource)
    expectNoDifference(deleted.canLoadNextPage, false, infiniteDeletingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryUpdatingOutOfWindowItemReordersIntoVisibleChunk() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 3, order: InstantQueryOrder("value"))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([10, 20, 30, 40, 50, 60], prefix: "update", in: runtime)
    _ = try #require(await iterator.next())

    try await upsertNumberEntries(
      [("update-5-60", 15)],
      transactionID: "tx-update-sixty-to-fifteen",
      in: runtime
    )
    let reordered = try #require(await iterator.next())
    expectNoDifference(loadedValues(reordered), [10, 15, 20], infiniteUpdateSource)
    expectNoDifference(reordered.canLoadNextPage, true, infiniteUpdateSource)

    subscription.loadNextPage()
    let loaded = try #require(await iterator.next())
    expectNoDifference(loadedValues(loaded), [10, 15, 20, 30, 40, 50], infiniteUpdateSource)
    expectNoDifference(loaded.canLoadNextPage, false, infiniteUpdateSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryPageSizeOneAscending() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value"))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([0, 1], prefix: "page-one-asc", in: runtime)
    let firstPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(firstPage), [0], infinitePageOneAscendingSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infinitePageOneAscendingSource)

    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(secondPage), [0, 1], infinitePageOneAscendingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryPageSizeOneDescending() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value", .descending))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    try await upsertNumberItems([0, -1], prefix: "page-one-desc", in: runtime)
    let firstPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(firstPage), [0], infinitePageOneDescendingSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infinitePageOneDescendingSource)

    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(secondPage), [0, -1], infinitePageOneDescendingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryEarlyLoadNextPageDoesNotBankFuturePages() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value"))
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    _ = try #require(await iterator.next())
    subscription.loadNextPage()

    try await upsertNumberItems([0, 1], prefix: "early-load", in: runtime)
    let firstPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(firstPage), [0], infiniteEarlyLoadSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteEarlyLoadSource)

    subscription.loadNextPage()
    let secondPage = try #require(await iterator.next())
    expectNoDifference(loadedValues(secondPage), [0, 1], infiniteEarlyLoadSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryInvalidQueryEmitsErrorResponse() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      InstantQueryPlan(
        id: "items.invalid-infinite",
        namespace: "missing_items",
        order: InstantQueryOrder("value"),
        limit: 4
      )
    )
    var iterator = subscription.snapshots.makeAsyncIterator()

    let snapshot = try #require(await iterator.next())
    expectNoDifference(snapshot.values, [], infiniteInvalidQuerySource)
    expectNoDifference(snapshot.canLoadNextPage, false, infiniteInvalidQuerySource)
    expectNoDifference(snapshot.error?.code, .validationFailed, infiniteInvalidQuerySource)
    #expect(snapshot.error?.message.isEmpty == false)
    #expect(await iterator.next() == nil)
    subscription.loadNextPage()
    subscription.unsubscribe()
  }
}

private func infiniteQueryRuntime() async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "infinite-query-\(UUID().uuidString)",
      persistenceURL: temporaryInfiniteQueryCacheURL(),
      initialAttributes: [
        .primaryKey(namespace: "items"),
        InstantAttribute(
          id: infiniteQueryValueAttributeID,
          namespace: "items",
          name: "value",
          valueType: .number,
          isIndexed: true
        ),
      ],
      makeID: { UUID().uuidString.lowercased() }
    )
  )
}

private func infiniteItemsQuery(
  limit: Int,
  order: InstantQueryOrder?
) -> InstantQueryPlan {
  InstantQueryPlan(
    id: "items.infinite",
    namespace: "items",
    order: order,
    limit: limit
  )
}

private func upsertNumberItems(
  _ values: [Int],
  prefix: String,
  in runtime: InstantRuntime
) async throws {
  try await upsertNumberEntries(
    values.enumerated().map { offset, value in
      ("\(prefix)-\(offset)-\(value)", value)
    },
    transactionID: "tx-\(prefix)-\(UUID().uuidString)",
    in: runtime
  )
}

private func upsertNumberEntries(
  _ entries: [(id: String, value: Int)],
  transactionID: String,
  in runtime: InstantRuntime
) async throws {
  let txTime = InstantTimestamp(milliseconds: infiniteQueryTimestamp(for: transactionID))
  try await runtime.transact(
    InstantStoreTransaction(
      id: transactionID,
      operations: entries.flatMap { entry in
        [
          .insert(
            InstantTriple(
              entityID: entry.id,
              attributeID: InstantAttribute.primaryKeyID(namespace: "items"),
              value: .string(entry.id),
              txID: transactionID,
              txTime: txTime
            )
          ),
          .insert(
            InstantTriple(
              entityID: entry.id,
              attributeID: infiniteQueryValueAttributeID,
              value: .number(Double(entry.value)),
              txID: transactionID,
              txTime: txTime
            )
          ),
        ]
      }
    ),
    createdAt: txTime
  )
}

private func deleteNumberItem(
  _ id: String,
  transactionID: String,
  in runtime: InstantRuntime
) async throws {
  let txTime = InstantTimestamp(milliseconds: infiniteQueryTimestamp(for: transactionID))
  try await runtime.transact(
    InstantStoreTransaction(
      id: transactionID,
      operations: [.deleteEntityInNamespace(entityID: id, namespace: "items")]
    ),
    createdAt: txTime
  )
}

private func loadedValues(_ snapshot: InstantInfiniteQuerySnapshot) -> [Int] {
  snapshot.values.compactMap { entity in
    guard case let .one(.number(value)) = entity.values["value"] else { return nil }
    return Int(value)
  }
}

private func temporaryInfiniteQueryCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantInfiniteQueryParityTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func infiniteQueryTimestamp(for transactionID: String) -> Int64 {
  let offset = transactionID.utf8.reduce(Int64(0)) { partial, byte in
    (partial * 31 + Int64(byte)) % 1_000_000
  }
  return 1_767_225_600_000 + offset
}

private let infiniteQueryValueAttributeID = "items/value"

private let infiniteInitialSnapshotSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts empty result [adapted: Swift reads the local first-page snapshot instead of Reactor.getPreviousResult.]"
private let infiniteNoOrderSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts no order field [adapted: Swift observes the local store with implicit serverCreatedAt ordering.]"
private let infiniteAddingNewNumbersSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts adding new numbers [adapted: Swift uses a local infinite-query coordinator over InstantRuntime.observe.]"
private let infiniteNegativeNumbersSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts adding negative numbers [adapted: Swift prepends rows before the initial anchor instead of maintaining separate reverse subscriptions.]"
private let infiniteZeroTwiceSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts add zero twice [adapted: Swift relies on materialized duplicate scalar rows and id tie-breaking.]"
private let infiniteDescendingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts descending [adapted: Swift expands the local forward page window on loadNextPage.]"
private let infiniteDuplicateBoundarySource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts duplicate boundary values across pages (desc) [adapted: Swift uses full local ordering plus forward page counts instead of chunk subscriptions.]"
private let infiniteRapidLoadSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts rapid loadNextPage calls do not duplicate pages [adapted: upstream calls loadNextPage once; Swift asserts one expansion.]"
private let infiniteDeletingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts deleting an item [adapted: Swift recomputes the loaded local window after deletion.]"
private let infiniteUpdateSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts updating an out-of-window item can reorder into visible chunk [adapted: Swift recomputes the anchored forward chunk after local updates.]"
private let infinitePageOneAscendingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts page size 1, asc [adapted: Swift expands one local row per loaded page.]"
private let infinitePageOneDescendingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts page size 1, desc [adapted: Swift expands one local row per loaded page.]"
private let infiniteEarlyLoadSource =
  "upstream/instant/client/packages/core/src/infiniteQuery.ts loadNextPage endCursor guard [adapted: Swift loadNextPage no-ops until the current local window can load another page.]"
private let infiniteInvalidQuerySource =
  "upstream/instant/client/packages/core/src/infiniteQuery.ts sendError [adapted: Swift invalid infinite queries emit an error snapshot with no data and canLoadNextPage false.]"
