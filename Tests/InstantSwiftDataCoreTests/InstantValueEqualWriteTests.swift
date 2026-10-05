import Foundation
@testable import InstantSwiftDataCore
import Testing

/// A local write that sets a stored field to the value it already holds changes nothing an observer can see (#572).
///
/// Scribe's attachment metadata mutation sets every field on each update, and the recording's row is saved again
/// often. The store keeps the value and its time, takes the write's transaction ID, and still counted the row as
/// changed, so every page that reads it was spliced or materialized again, and yielded the same values. Upstream
/// `Reactor.js` runs every query again on a local transaction but does not notify a query whose result is deep-equal.
/// The row stays among the entities the write touched, for persistence and for the before-image a rejected
/// mutation's rollback restores.
@Suite
struct InstantValueEqualWriteTests {
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
    static let count = InstantAttribute(
      id: "rows/count",
      namespace: namespace,
      name: "count",
      valueType: .number,
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
    static let attributes = [primaryKey, userPrimaryKey, title, count, owner, userName]
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

  static func store() -> InstantStore {
    InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: Rows.attributes,
        triples: [
          triple("row-1", Rows.primaryKey, .string("row-1"), tx: 1),
          triple("row-1", Rows.title, .string("a"), tx: 1),
          triple("row-1", Rows.count, .number(1), tx: 1),
          triple("row-1", Rows.owner, .ref("user-1"), tx: 1),
          triple("row-2", Rows.primaryKey, .string("row-2"), tx: 1),
          triple("row-2", Rows.title, .string("b"), tx: 1),
          triple("row-2", Rows.count, .number(2), tx: 1),
          triple("user-1", Rows.userPrimaryKey, .string("user-1"), tx: 1),
          triple("user-1", Rows.userName, .string("Michael"), tx: 1),
        ]
      )
    )
  }

  /// Every row, the rows titled "a", the first row by count, and the users.
  static let plans = [
    InstantQueryPlan(id: "all", namespace: Rows.namespace),
    InstantQueryPlan(id: "titled-a", namespace: Rows.namespace, filters: [.equals(field: "title", value: .string("a"))]),
    InstantQueryPlan(id: "first-by-count", namespace: Rows.namespace, order: InstantQueryOrder("count"), limit: 1),
    InstantQueryPlan(id: "users", namespace: Rows.users),
  ]

  actor Observed {
    private(set) var last: [String: InstantQueryEmission] = [:]
    private var streams: [AsyncStream<InstantQueryEmission>] = []

    func observe(_ plans: [InstantQueryPlan], in store: InstantStore) async throws {
      for plan in plans {
        let stream = await store.observe(plan)
        var iterator = stream.makeAsyncIterator()
        let initial: InstantQueryEmission = try #require(await iterator.next())
        last[plan.id] = initial
        streams.append(stream)
      }
    }
  }

  static func reSetRowOne(tx: Int64) -> [InstantTripleOperation] {
    [
      .insert(triple("row-1", Rows.title, .string("a"), tx: tx)),
      .insert(triple("row-1", Rows.count, .number(1), tx: tx)),
      .insert(triple("row-1", Rows.owner, .ref("user-1"), tx: tx)),
    ]
  }

  @Test
  func aWriteThatSetsEveryFieldOfAnObservedRowToItsValueRefreshesNoObserver() async throws {
    let store = Self.store()
    let observed = Observed()
    try await observed.observe(Self.plans, in: store)

    let prepared = try await store.prepareCurrent(InstantStoreTransaction(id: "tx-2", operations: Self.reSetRowOne(tx: 2)))
    #expect(prepared.result.changedEntityIDs.contains("row-1"))
    let committed = await store.commitAndPublish(prepared)

    #expect(committed.result.emissions.map(\.queryID) == [])
    let metrics = await store.lastPublishMetrics
    #expect(metrics.splicedObserverCount == 0)
    #expect(metrics.rematerializedObserverCount == 0)
    #expect(metrics.skippedObserverCount == Self.plans.count)
  }

  @Test
  func aWriteThatSetsOneFieldToItsValueAndChangesAnotherStillPublishes() async throws {
    let store = Self.store()
    let observed = Observed()
    try await observed.observe(Self.plans, in: store)

    let prepared = try await store.prepareCurrent(
      InstantStoreTransaction(
        id: "tx-2",
        operations: [
          .insert(Self.triple("row-1", Rows.title, .string("a"), tx: 2)),
          .insert(Self.triple("row-1", Rows.count, .number(3), tx: 2)),
        ]
      )
    )
    let committed = await store.commitAndPublish(prepared)

    let all = try #require(committed.result.emissions.first { $0.queryID == "all" })
    #expect(all.values.first { $0.id == "row-1" }?.values["count"] == .one(.number(3)))
    // The first row by count is now row-2.
    let first = try #require(committed.result.emissions.first { $0.queryID == "first-by-count" })
    #expect(first.values.map(\.id) == ["row-2"])
  }

  @Test
  func aWriteThatSetsAFieldToItsValueKeepsTheBeforeImageARollbackRestores() async throws {
    let store = Self.store()
    let observed = Observed()
    try await observed.observe(Self.plans, in: store)

    let prepared = try await store.prepareCurrent(InstantStoreTransaction(id: "tx-2", operations: Self.reSetRowOne(tx: 2)))
    let before = prepared.previousChangedEntityTriples["row-1", default: []]
    #expect(before.first { $0.attributeID == Rows.title.id }?.txID == "tx-1")
    _ = await store.commitAndPublish(prepared)

    // The slot keeps its value and time, and takes the write's transaction ID, which a rollback gives back.
    let title = await store.snapshot().triples.first { $0.entityID == "row-1" && $0.attributeID == Rows.title.id }
    #expect(title?.value == .string("a"))
    #expect(title?.txID == "tx-2")
    #expect(title?.txTime == InstantTimestamp(milliseconds: 1_000))
  }

  @Test
  func commitsPublishedTogetherRefreshOnlyForTheRowsTheyChanged() async throws {
    let store = Self.store()
    let observed = Observed()
    try await observed.observe(Self.plans, in: store)

    // A row-1 change, then row-1 set to its new values again, published together: one refresh, with the change.
    let change = try await store.prepareCurrent(
      InstantStoreTransaction(id: "tx-2", operations: [.insert(Self.triple("row-1", Rows.title, .string("c"), tx: 2))])
    )
    let first = await store.commitDeferringPublication(change)
    let reSet = try await store.prepareCurrent(
      InstantStoreTransaction(id: "tx-3", operations: [.insert(Self.triple("row-1", Rows.title, .string("c"), tx: 3))])
    )
    let second = await store.commitDeferringPublication(reSet)
    let firstTicket = try #require(first.publication)
    let secondTicket = try #require(second.publication)
    let emissions = await store.publishCommittedChanges(firstTicket)
    _ = await store.publishCommittedChanges(secondTicket)
    let all = try #require(emissions.first { $0.queryID == "all" })
    #expect(all.values.first { $0.id == "row-1" }?.values["title"] == .one(.string("c")))

    // Row-1 set to its values again, alone: nothing to publish.
    let again = try await store.prepareCurrent(
      InstantStoreTransaction(id: "tx-4", operations: [.insert(Self.triple("row-1", Rows.title, .string("c"), tx: 4))])
    )
    let third = await store.commitDeferringPublication(again)
    if let ticket = third.publication {
      let none = await store.publishCommittedChanges(ticket)
      #expect(none.map(\.queryID) == [])
      let metrics = await store.lastPublishMetrics
      #expect(metrics.rematerializedObserverCount + metrics.splicedObserverCount == 0)
    }
  }
}
