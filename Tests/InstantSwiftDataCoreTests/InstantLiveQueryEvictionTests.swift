import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// A live query's rows leave memory after it unsubscribes, and come back from SQLite when a query or a write needs
/// them (1.10.0's eviction).
///
/// Reactor.js keeps one store per query subscription: unsubscribing drops it from memory, the stored copy stays in
/// IndexedDB, and it loads again when the query subscribes again. Swift's one hot store kept every entity a session's
/// queries loaded until relaunch: a memory audit found 32.7k triples after a long recording's queries ended, where the
/// queries still on screen held about 13.4k.
@Suite(.serialized)
struct InstantLiveQueryEvictionTests {
  typealias Writes = InstantLiveQueryResultWriteTests

  actor Evictions {
    private(set) var batches: [Int] = []

    func record(_ evictedEntityCount: Int) {
      batches.append(evictedEntityCount)
    }
  }

  struct Fixture {
    var runtime: InstantRuntime
    var session: LiveReactorParitySession
    var evictions: Evictions
    var url: URL
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

  /// A runtime whose eviction grace passes at once, unless `graceNeverEnds`.
  static func makeFixture(appID: String, graceNeverEnds: Bool = false) async throws -> Fixture {
    let url = try Writes.temporaryCacheURL()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    let evictions = Evictions()
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.liveQueryEvictionGraceMilliseconds = 60_000
    if graceNeverEnds {
      configuration.liveQueryEvictionSleep = { @Sendable _ in try await Task.sleep(for: .seconds(3_600)) }
    } else {
      configuration.liveQueryEvictionSleep = { @Sendable _ in }
    }
    configuration.onLiveQueryEvictionFinishedForTesting = { count in await evictions.record(count) }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.connect()
    return Fixture(runtime: runtime, session: session, evictions: evictions, url: url)
  }

  /// Subscribes `plan`, has the server answer it with the first `count` todos, and waits until the store holds them.
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
      await todoIDs(in: fixture.runtime).isSuperset(of: Set((0..<texts.count).map(Writes.todoID)))
    }
    return observation
  }

  static func todoIDs(in runtime: InstantRuntime) async -> Set<String> {
    Set(await runtime.store.snapshot().triples.map(\.entityID))
  }

  static func waitForEviction(_ fixture: Fixture, batches: Int = 1) async throws {
    try await Writes.waitFor("\(batches) eviction batches") {
      await fixture.evictions.batches.count >= batches
    }
  }

  @Test
  func aQueryThatUnsubscribesLeavesMemoryAfterTheGraceAndSQLiteKeepsItsRows() async throws {
    let fixture = try await Self.makeFixture(appID: "eviction-unsubscribe")
    let observation = try await Self.subscribe(TodoExample.query, answeringWith: Self.texts(100), in: fixture)
    #expect(await fixture.runtime.store.currentTripleCount() == 400)

    await observation.cancel()
    try await Self.waitForEviction(fixture)

    #expect(await fixture.evictions.batches == [100])
    #expect(await fixture.runtime.store.currentTripleCount() == 0)
    let stored = try await fixture.runtime.persistence.loadCompactState().snapshot.store.triples
    #expect(stored.count == 400)
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func aQueryThatSubscribesAgainOfflineShowsItsRowsFromSQLiteInItsFirstEmission() async throws {
    let fixture = try await Self.makeFixture(appID: "eviction-resubscribe")
    let observation = try await Self.subscribe(TodoExample.query, answeringWith: Self.texts(100), in: fixture)
    await observation.cancel()
    try await Self.waitForEviction(fixture)
    _ = try await fixture.runtime.closeConnection()

    let again = await fixture.runtime.observeQueryLease(TodoExample.query)
    var iterator = again.stream.makeAsyncIterator()
    let first: InstantQueryEmission = try #require(await iterator.next())

    #expect(first.values.count == 100)
    #expect(first.values.first?.values["text"] == .one(.string("todo 0")))
    await again.cancel()
  }

  @Test
  func aRowAnotherActiveQueryHoldsStaysInMemory() async throws {
    let fixture = try await Self.makeFixture(appID: "eviction-overlap")
    let list = try await Self.subscribe(TodoExample.query, answeringWith: Self.texts(100), in: fixture)
    let firstTen = try await Self.subscribe(Self.firstTen, answeringWith: Array(Self.texts(100).prefix(10)), in: fixture)

    await list.cancel()
    try await Self.waitForEviction(fixture)

    let remaining = await Self.todoIDs(in: fixture.runtime)
    expectNoDifference(remaining, Set((0..<10).map(Writes.todoID)))
    await firstTen.cancel()
    _ = try await fixture.runtime.closeConnection()
  }

  @Test
  func aRowAPendingWriteHoldsStaysInMemory() async throws {
    let fixture = try await Self.makeFixture(appID: "eviction-outbox")
    let observation = try await Self.subscribe(TodoExample.query, answeringWith: Self.texts(20), in: fixture)
    _ = try await fixture.runtime.closeConnection()
    // Offline, so the write stays in the outbox.
    try await fixture.runtime.transact(
      operations: TodoExample.updateTextOperations(
        id: Writes.todoID(3),
        text: "pending",
        updatedAt: InstantTimestamp(milliseconds: 1_800_000_000_000),
        transactionID: "pending-write"
      )
    )

    await observation.cancel()
    try await Self.waitForEviction(fixture)

    let remaining = await Self.todoIDs(in: fixture.runtime)
    expectNoDifference(remaining, [Writes.todoID(3)])
  }

  @Test
  func aWriteToAnEvictedRowLoadsItFirst() async throws {
    let fixture = try await Self.makeFixture(appID: "eviction-write")
    let observation = try await Self.subscribe(TodoExample.query, answeringWith: Self.texts(20), in: fixture)
    await observation.cancel()
    try await Self.waitForEviction(fixture)
    _ = try await fixture.runtime.closeConnection()

    // The update requires the todo to exist, and sets only its text.
    try await fixture.runtime.transact(
      operations: TodoExample.updateTextOperations(
        id: Writes.todoID(5),
        text: "changed",
        updatedAt: InstantTimestamp(milliseconds: 1_800_000_000_000),
        transactionID: "write-to-evicted"
      )
    )

    let row = await fixture.runtime.store.snapshot().triples.filter { $0.entityID == Writes.todoID(5) }
    expectNoDifference(Set(row.map(\.attributeID)), ["todos/id", "todos/text", "todos/isCompleted", "todos/createdAt"])
    #expect(row.first { $0.attributeID == "todos/text" }?.value == .string("changed"))
  }

  @Test
  func trimMemoryEvictsAtOnceWhatNoActiveQueryHolds() async throws {
    let fixture = try await Self.makeFixture(appID: "eviction-trim", graceNeverEnds: true)
    let list = try await Self.subscribe(TodoExample.query, answeringWith: Self.texts(100), in: fixture)
    let firstTen = try await Self.subscribe(Self.firstTen, answeringWith: Array(Self.texts(100).prefix(10)), in: fixture)
    await list.cancel()
    #expect(await fixture.runtime.store.currentTripleCount() == 400)

    let trimmed = try await fixture.runtime.trimMemory()

    #expect(trimmed.evictedEntityCount == 90)
    let remaining = await Self.todoIDs(in: fixture.runtime)
    expectNoDifference(remaining, Set((0..<10).map(Writes.todoID)))
    await firstTen.cancel()
    _ = try await fixture.runtime.closeConnection()
  }
}
