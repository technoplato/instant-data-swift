import Foundation
@testable import InstantSwiftDataCore
import Testing

/// The store drops from memory the facts of entities no observer shows or could show, and puts back facts read from
/// SQLite (1.10.0's eviction). Reactor.js keeps one store per query subscription, so a query that unsubscribes leaves
/// memory with it; Swift's one hot store kept every entity a session's queries ever loaded until relaunch.
@Suite
struct InstantStoreEvictionTests {
  enum Rows {
    static let namespace = "rows"
    static let users = "users"
    static let primaryKey = InstantAttribute.primaryKey(namespace: namespace)
    static let userPrimaryKey = InstantAttribute.primaryKey(namespace: users)
    static let title = InstantAttribute(
      id: "rows/title",
      namespace: namespace,
      name: "title",
      valueType: .string,
      isRequired: false,
      isIndexed: true
    )
    static let owner = InstantAttribute(
      id: "rows/owner",
      namespace: namespace,
      name: "owner",
      valueType: .ref,
      isRequired: false,
      linkNamespace: users
    )
    static let userName = InstantAttribute(
      id: "users/name",
      namespace: users,
      name: "name",
      valueType: .string,
      isRequired: false
    )
    static let attributes = [primaryKey, userPrimaryKey, title, owner, userName]
  }

  static func triple(_ entityID: String, _ attribute: InstantAttribute, _ value: InstantValue, tx: Int64) -> InstantTriple {
    InstantTriple(
      entityID: entityID,
      attributeID: attribute.id,
      value: value,
      txID: "tx-\(tx)",
      txTime: InstantTimestamp(milliseconds: 1_000 * tx)
    )
  }

  static let rowOne = [
    triple("row-1", Rows.primaryKey, .string("row-1"), tx: 1),
    triple("row-1", Rows.title, .string("a"), tx: 1),
    triple("row-1", Rows.owner, .ref("user-1"), tx: 1),
  ]
  static let rowTwo = [
    triple("row-2", Rows.primaryKey, .string("row-2"), tx: 1),
    triple("row-2", Rows.title, .string("b"), tx: 1),
  ]
  static let userOne = [
    triple("user-1", Rows.userPrimaryKey, .string("user-1"), tx: 1),
    triple("user-1", Rows.userName, .string("Michael"), tx: 1),
  ]

  static func store() -> InstantStore {
    InstantStore(snapshot: InstantStoreSnapshot(attributes: Rows.attributes, triples: rowOne + rowTwo + userOne))
  }

  static func entityIDs(_ store: InstantStore) async -> Set<String> {
    Set(await store.snapshot().triples.map(\.entityID))
  }

  static func firstEmission(_ stream: AsyncStream<InstantQueryEmission>) async throws -> InstantQueryEmission {
    var iterator = stream.makeAsyncIterator()
    let first: InstantQueryEmission = try #require(await iterator.next())
    return first
  }

  @Test
  func evictingAnEntityDropsItsFactsAndKeepsOtherEntitiesLinksToIt() async throws {
    let store = Self.store()
    let before = await store.currentTripleCount()

    let eviction = await store.evict(["user-1"])

    #expect(eviction.evictedEntityIDs == ["user-1"])
    #expect(eviction.removedTripleCount == 2)
    #expect(await Self.entityIDs(store) == ["row-1", "row-2"])
    #expect(await store.currentTripleCount() == before - 2)
    // Row 1's link to the evicted user is row 1's own fact.
    let owner = await store.snapshot().triples.first { $0.entityID == "row-1" && $0.attributeID == Rows.owner.id }
    #expect(owner?.value == .ref("user-1"))
  }

  @Test
  func anEntityALiveQueryObserverShowsIsNotEvicted() async throws {
    let store = Self.store()
    let lease = await store.observeLiveQueryLease(
      InstantQueryPlan(id: "titled-a", namespace: Rows.namespace, filters: [.equals(field: "title", value: .string("a"))]),
      registrationKey: "key-titled-a",
      remotePageInfo: nil
    )
    let shown = try await Self.firstEmission(lease.stream)
    #expect(shown.values.map(\.id) == ["row-1"])

    let eviction = await store.evict(["row-1", "row-2"])

    #expect(eviction.evictedEntityIDs == ["row-2"])
    #expect(await Self.entityIDs(store) == ["row-1", "user-1"])
    await lease.cancel()
  }

  @Test
  func anEntityInTheNamespaceOfALocalObserverIsNotEvicted() async throws {
    let store = Self.store()
    // A local observation reads the store alone, so a row it does not show yet may enter its page.
    let stream = await store.observe(InstantQueryPlan(id: "first-row", namespace: Rows.namespace, limit: 1))
    _ = try await Self.firstEmission(stream)

    let eviction = await store.evict(["row-2", "user-1"])

    #expect(eviction.evictedEntityIDs == ["user-1"])
    #expect(await Self.entityIDs(store) == ["row-1", "row-2"])
  }

  @Test
  func hydratingPutsTheFactsBackAndRefreshesTheObserversThatSeeThem() async throws {
    let store = Self.store()
    _ = await store.evict(["row-2"])
    let lease = await store.observeLiveQueryLease(
      InstantQueryPlan(id: "rows", namespace: Rows.namespace),
      registrationKey: "key-rows",
      remotePageInfo: nil
    )
    var iterator = lease.stream.makeAsyncIterator()
    let first: InstantQueryEmission = try #require(await iterator.next())
    #expect(first.values.map(\.id) == ["row-1"])

    let hydrated = await store.hydrate(Self.rowTwo)

    #expect(hydrated == ["row-2"])
    let next: InstantQueryEmission = try #require(await iterator.next())
    #expect(Set(next.values.map(\.id)) == ["row-1", "row-2"])
    await lease.cancel()
  }

  @Test
  func hydrationKeepsANewerFactInMemory() async throws {
    let store = Self.store()
    _ = await store.evict(["row-1"])
    // A write after the eviction sets row 1's title; SQLite's older facts come back around it.
    let prepared = try await store.prepareCurrent(
      InstantStoreTransaction(id: "tx-5", operations: [.insert(Self.triple("row-1", Rows.title, .string("z"), tx: 5))])
    )
    _ = await store.commitAndPublish(prepared)

    _ = await store.hydrate(Self.rowOne)

    let rowOne = await store.snapshot().triples.filter { $0.entityID == "row-1" }
    #expect(rowOne.first { $0.attributeID == Rows.title.id }?.value == .string("z"))
    #expect(rowOne.first { $0.attributeID == Rows.owner.id }?.value == .ref("user-1"))
    #expect(rowOne.count == 3)
  }
}
