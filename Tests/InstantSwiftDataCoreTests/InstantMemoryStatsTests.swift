import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// The store's size for a periodic health report, and how much of it no query, pending write or observer holds
/// (1.10.0): the entity count, fact count and estimated bytes, cheap enough to report often, and a read-only estimate
/// of what eviction could drop, so eviction is sized from device numbers before it risks data.
@Suite(.serialized)
struct InstantMemoryStatsTests {
  typealias Writes = InstantLiveQueryResultWriteTests

  enum Rows {
    static let namespace = "rows"
    static let primaryKey = InstantAttribute.primaryKey(namespace: namespace)
    static let title = InstantAttribute(
      id: "rows/title",
      namespace: namespace,
      name: "title",
      valueType: .string,
      isRequired: false
    )
    static let attributes = [primaryKey, title]
  }

  static func row(_ id: String, title: String) -> [InstantTriple] {
    [
      InstantTriple(entityID: id, attributeID: Rows.primaryKey.id, value: .string(id), txID: "tx-1", txTime: InstantTimestamp(milliseconds: 1)),
      InstantTriple(entityID: id, attributeID: Rows.title.id, value: .string(title), txID: "tx-1", txTime: InstantTimestamp(milliseconds: 1)),
    ]
  }

  @Test
  func theStoreCountsItsEntitiesAndFactsAndItsBytesGrowWithItsValues() async throws {
    let short = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: Rows.attributes, triples: Self.row("row-1", title: "a") + Self.row("row-2", title: "b"))
    )
    let long = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: Rows.attributes,
        triples: Self.row("row-1", title: "a") + Self.row("row-2", title: String(repeating: "spoken words ", count: 100))
      )
    )

    let shortStats = await short.memoryStats()
    let longStats = await long.memoryStats()

    #expect(shortStats.entityCount == 2)
    #expect(shortStats.factCount == 4)
    #expect(shortStats.estimatedBytes > 0)
    #expect(longStats.estimatedBytes - shortStats.estimatedBytes >= 1_300)
  }

  /// The counts are kept as the store changes; the byte estimate walks every fact. This prints the walk's time on a
  /// store the size a memory audit found after a long recording (about 32,700 facts) for the release notes, and bounds it
  /// loosely so a much slower walk fails.
  @Test
  func theByteEstimateWalksAStoreOfThirtyThousandFactsQuickly() async throws {
    var triples: [InstantTriple] = []
    for index in 0..<16_400 {
      triples += Self.row(String(format: "00000000-0000-4000-8000-%012ld", index), title: "segment \(index) words spoken")
    }
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Rows.attributes, triples: triples))
    let clock = ContinuousClock()
    var stats = await store.memoryStats()
    var durations: [Duration] = []
    for _ in 0..<5 {
      let started = clock.now
      stats = await store.memoryStats()
      durations.append(started.duration(to: clock.now))
    }
    let median = durations.sorted()[2]
    print("memory-stats: \(stats.factCount) facts, \(stats.entityCount) entities, \(stats.estimatedBytes) estimated bytes; median of 5 walks \(median)")
    #expect(stats.factCount == 32_800)
    #expect(median < .seconds(2))
  }

  @Test
  func theCountsFollowWritesAndDeletes() async throws {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: Rows.attributes, triples: Self.row("row-1", title: "a") + Self.row("row-2", title: "b"))
    )
    let delete = try await store.prepareCurrent(
      InstantStoreTransaction(id: "delete", operations: [.deleteEntity("row-2")])
    )
    _ = await store.commitAndPublish(delete)
    let afterDelete = await store.memoryStats()
    #expect(afterDelete.entityCount == 1)
    #expect(afterDelete.factCount == 2)

    let create = try await store.prepareCurrent(
      InstantStoreTransaction(id: "create", operations: Self.row("row-3", title: "c").map { .insert($0) })
    )
    _ = await store.commitAndPublish(create)
    let afterCreate = await store.memoryStats()
    #expect(afterCreate.entityCount == 2)
    #expect(afterCreate.factCount == 4)
  }

  // MARK: - What eviction could drop

  struct Fixture {
    var runtime: InstantRuntime
    var session: LiveReactorParitySession
  }

  static let firstTen = InstantQueryPlan(
    id: "examples.todos.first-ten",
    namespace: TodoExample.namespace,
    order: InstantQueryOrder("createdAt", .ascending),
    limit: 10
  )

  static func texts(_ count: Int) -> [String] {
    (0..<count).map { "todo \($0)" }
  }

  static func makeFixture(appID: String) async throws -> Fixture {
    let url = try Writes.temporaryCacheURL()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    return Fixture(runtime: runtime, session: session)
  }

  /// Subscribes `plan`, has the server answer it with `texts`' todos, and waits until the store holds them.
  static func subscribe(
    _ plan: InstantQueryPlan,
    answeringWith texts: [String],
    in fixture: Fixture
  ) async throws -> InstantQueryObservationLease {
    let query = try InstantLiveQueryEncoder.encode(plan)
    let observation = await fixture.runtime.observeQueryLease(plan)
    try await Writes.waitFor("\(plan.id)'s add-query") {
      await fixture.session.sentMessages().contains { $0.op == "add-query" && $0.fields["q"] == query }
    }
    await fixture.session.enqueue(
      liveReactorAddQueryOK(query: query, processedTransactionID: "server-tx-\(plan.id)", result: Writes.todoResult(texts))
    )
    try await Writes.waitFor("the store to hold \(texts.count) todos") {
      let ids = Set(await fixture.runtime.store.snapshot().triples.map(\.entityID))
      return ids.isSuperset(of: Set((0..<texts.count).map(Writes.todoID)))
    }
    return observation
  }

  /// The list of 100 todos, given up, while the first ten stay subscribed.
  static func listGivenUpWhileTheFirstTenStay(appID: String) async throws -> (Fixture, InstantQueryObservationLease) {
    let fixture = try await makeFixture(appID: appID)
    let list = try await subscribe(TodoExample.query, answeringWith: texts(100), in: fixture)
    let firstTen = try await subscribe(firstTen, answeringWith: Array(texts(100).prefix(10)), in: fixture)
    await list.cancel()
    try await Writes.waitFor("the list's query to unregister") {
      await fixture.session.sentMessages().contains { $0.op == "remove-query" }
    }
    return (fixture, firstTen)
  }

  @Test
  func theEvictableEstimateCountsWhatNoActiveQueryHoldsAndDropsNothing() async throws {
    let (fixture, firstTen) = try await Self.listGivenUpWhileTheFirstTenStay(appID: "evictable-queries")

    let estimate = try await fixture.runtime.evictableMemoryEstimate()

    #expect(estimate.entityCount == 90)
    #expect(estimate.factCount == 360)
    #expect(estimate.estimatedBytes > 0)
    #expect(estimate.heldByActiveQueriesCount == 10)
    #expect(await fixture.runtime.store.currentTripleCount() == 400)
    await firstTen.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func theEvictableEstimateLeavesOutARowAPendingWriteHolds() async throws {
    let (fixture, firstTen) = try await Self.listGivenUpWhileTheFirstTenStay(appID: "evictable-pending")
    _ = try await fixture.runtime.closeConnection()
    try await fixture.runtime.transact(
      operations: TodoExample.updateTextOperations(
        id: Writes.todoID(50),
        text: "pending",
        updatedAt: InstantTimestamp(milliseconds: 1_800_000_000_000),
        transactionID: "pending-write"
      )
    )

    let estimate = try await fixture.runtime.evictableMemoryEstimate()

    #expect(estimate.entityCount == 89)
    #expect(estimate.heldByPendingWritesCount == 1)
    await firstTen.cancel()
  }

  @Test
  func theEvictableEstimateLeavesOutTheNamespaceALocalObserverReads() async throws {
    let (fixture, firstTen) = try await Self.listGivenUpWhileTheFirstTenStay(appID: "evictable-local")
    // A local observation reads the store alone, so a row it does not show yet may enter its page.
    let local = await fixture.runtime.observeLocallyLease(InstantQueryPlan(id: "local-todos", namespace: TodoExample.namespace, limit: 1))
    var iterator = local.stream.makeAsyncIterator()
    _ = await iterator.next()

    let estimate = try await fixture.runtime.evictableMemoryEstimate()

    #expect(estimate.entityCount == 0)
    #expect(estimate.inLocalObserverNamespacesCount == 90)
    await local.cancel()
    await firstTen.cancel()
    _ = try await fixture.runtime.closeConnection()
  }
}
