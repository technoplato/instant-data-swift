import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantBoundedQueryMaterializationTests {
  @Test
  func tenThousandOrderedRowsRetainOnlyTheRequestedWindowAndOneLookahead() async throws {
    let fixture = BoundedQueryFixture(rowCount: 10_000)
    let store = fixture.store()

    let leading = await store.materializePageWithMetrics(
      InstantQueryPlan(
        id: "bounded.leading",
        namespace: fixture.namespace,
        order: InstantQueryOrder(fixture.score.name),
        limit: 5
      )
    )
    expectNoDifference(
      leading.page.values.map(\.id),
      ["item-09999", "item-09998", "item-09997", "item-09996", "item-09995"]
    )
    expectNoDifference(leading.page.pageInfo?.hasPreviousPage, false)
    expectNoDifference(leading.page.pageInfo?.hasNextPage, true)
    expectNoDifference(leading.metrics.examinedCandidateCount, 10_000)
    expectNoDifference(leading.metrics.matchingCandidateCount, 10_000)
    expectNoDifference(leading.metrics.materializedSnapshotCount, 5)
    expectNoDifference(leading.metrics.maximumRetainedCandidateCount, 6)
    expectNoDifference(leading.metrics.boundedSelectionCount, 1)

    let offset = await store.materializePageWithMetrics(
      InstantQueryPlan(
        id: "bounded.offset",
        namespace: fixture.namespace,
        order: InstantQueryOrder(fixture.score.name),
        offset: 10,
        limit: 5
      )
    )
    expectNoDifference(
      offset.page.values.map(\.id),
      ["item-09989", "item-09988", "item-09987", "item-09986", "item-09985"]
    )
    expectNoDifference(offset.page.pageInfo?.hasPreviousPage, true)
    expectNoDifference(offset.page.pageInfo?.hasNextPage, true)
    expectNoDifference(offset.metrics.materializedSnapshotCount, 5)
    expectNoDifference(offset.metrics.maximumRetainedCandidateCount, 16)

    let after = try #require(leading.page.pageInfo?.endCursor)
    let cursorPage = await store.materializePageWithMetrics(
      InstantQueryPlan(
        id: "bounded.cursor",
        namespace: fixture.namespace,
        order: InstantQueryOrder(fixture.score.name),
        limit: 5,
        after: after
      )
    )
    expectNoDifference(
      cursorPage.page.values.map(\.id),
      ["item-09994", "item-09993", "item-09992", "item-09991", "item-09990"]
    )
    expectNoDifference(cursorPage.page.pageInfo?.hasPreviousPage, true)
    expectNoDifference(cursorPage.page.pageInfo?.hasNextPage, true)
    expectNoDifference(cursorPage.metrics.materializedSnapshotCount, 5)
    expectNoDifference(cursorPage.metrics.maximumRetainedCandidateCount, 6)

    let trailing = await store.materializePageWithMetrics(
      InstantQueryPlan(
        id: "bounded.trailing-cursor",
        namespace: fixture.namespace,
        order: InstantQueryOrder(fixture.score.name),
        last: 3,
        before: InstantQueryCursor(
          entityID: "item-09950",
          sortValue: .number(50)
        )
      )
    )
    expectNoDifference(
      trailing.page.values.map(\.id),
      ["item-09953", "item-09952", "item-09951"]
    )
    expectNoDifference(trailing.page.pageInfo?.hasPreviousPage, true)
    expectNoDifference(trailing.page.pageInfo?.hasNextPage, true)
    expectNoDifference(trailing.metrics.materializedSnapshotCount, 3)
    expectNoDifference(trailing.metrics.maximumRetainedCandidateCount, 4)
  }

  @Test
  func indexedEqualityWithoutExplicitOrderUsesServerCreationTimeAndPageInfo() async throws {
    let fixture = ImplicitOrderIndexedFixture()
    let result = await fixture.store.materializePageWithMetrics(
      InstantQueryPlan(
        id: "bounded.implicit-order",
        namespace: fixture.namespace,
        filters: [.equals(field: fixture.category.name, value: .string("included"))],
        limit: 2
      )
    )

    expectNoDifference(result.page.values.map(\.id), ["z-oldest", "m-middle"])
    let pageInfo = try #require(result.page.pageInfo)
    expectNoDifference(
      pageInfo.startCursor,
      InstantQueryCursor(entityID: "z-oldest", sortValue: .number(10))
    )
    expectNoDifference(
      pageInfo.endCursor,
      InstantQueryCursor(entityID: "m-middle", sortValue: .number(20))
    )
    expectNoDifference(pageInfo.hasPreviousPage, false)
    expectNoDifference(pageInfo.hasNextPage, true)
    expectNoDifference(result.metrics.examinedCandidateCount, 3)
    expectNoDifference(result.metrics.matchingCandidateCount, 3)
    expectNoDifference(result.metrics.materializedSnapshotCount, 2)
    expectNoDifference(result.metrics.maximumRetainedCandidateCount, 3)
    expectNoDifference(result.metrics.boundedSelectionCount, 1)

    let materialized = await fixture.store.materialize(
      InstantQueryPlan(
        id: "bounded.implicit-order.values",
        namespace: fixture.namespace,
        filters: [.equals(field: fixture.category.name, value: .string("included"))],
        limit: 2
      )
    )
    expectNoDifference(materialized.map(\.id), result.page.values.map(\.id))
    expectNoDifference(materialized.map(\.values), result.page.values.map(\.values))
  }

  @Test
  func indexedEqualsMaterializeDropsAStaleCachedPrefixAfterAWrite() async throws {
    let fixture = ImplicitOrderIndexedFixture()
    let plan = InstantQueryPlan(
      id: "bounded.implicit-order.cached",
      namespace: fixture.namespace,
      filters: [.equals(field: fixture.category.name, value: .string("included"))],
      limit: 2
    )
    let first = await fixture.store.materialize(plan)
    let second = await fixture.store.materialize(plan)
    expectNoDifference(first.map(\.id), ["z-oldest", "m-middle"])
    expectNoDifference(second.map(\.id), first.map(\.id))
    expectNoDifference(second.map(\.values), first.map(\.values))

    let prepared = try await fixture.store.prepareCurrent(
      InstantStoreTransaction(
        id: "exclude-oldest",
        operations: [
          .insert(
            InstantTriple(
              entityID: "z-oldest",
              attributeID: fixture.category.id,
              value: .string("excluded"),
              txID: "exclude-oldest",
              txTime: InstantTimestamp(milliseconds: 11)
            )
          )
        ]
      )
    )
    _ = await fixture.store.commitAndPublish(prepared)

    let afterWrite = await fixture.store.materialize(plan)
    expectNoDifference(afterWrite.map(\.id), ["m-middle", "a-latest"])
  }

  @Test
  func finitePaginationRequiresPositiveBoundsAndComposesThemInOrder() async throws {
    let fixture = BoundedQueryFixture(rowCount: 10)
    let store = fixture.store()
    let attributes = AttributeStore(attributes: [fixture.id, fixture.score, fixture.category])
    let invalidPlans: [(plan: InstantQueryPlan, message: String)] = [
      (
        InstantQueryPlan(id: "bounded.zero-limit", namespace: fixture.namespace, limit: 0),
        "Pagination 'limit' must be greater than 0."
      ),
      (
        InstantQueryPlan(id: "bounded.zero-first", namespace: fixture.namespace, first: 0),
        "Pagination 'first' must be greater than 0."
      ),
      (
        InstantQueryPlan(id: "bounded.zero-last", namespace: fixture.namespace, last: 0),
        "Pagination 'last' must be greater than 0."
      ),
    ]

    for invalid in invalidPlans {
      let issue = try #require(TripleIndexes.validate(invalid.plan, attributes: attributes))
      expectNoDifference(issue.path, "pagination")
      expectNoDifference(issue.message, invalid.message)
      let page = await store.materializePage(invalid.plan)
      expectNoDifference(page.values, [])
    }

    let compoundPlan = InstantQueryPlan(
      id: "bounded.compound",
      namespace: fixture.namespace,
      order: InstantQueryOrder(fixture.score.name, .descending),
      offset: 1,
      limit: 2,
      first: 6,
      last: 3
    )
    expectNoDifference(TripleIndexes.validate(compoundPlan, attributes: attributes), nil)
    let compound = await store.materializePageWithMetrics(compoundPlan)
    expectNoDifference(compound.page.values.map(\.id), ["item-00004", "item-00005"])
    expectNoDifference(compound.metrics.materializedSnapshotCount, 2)
    expectNoDifference(compound.metrics.maximumRetainedCandidateCount, 8)
  }

  @Test
  func boundedIndexedFilterMatchesTheUnboundedQueryWithoutRetainingItsMatchSet() async {
    let fixture = BoundedQueryFixture(rowCount: 200)
    let store = fixture.store()
    let filters: [InstantQueryFilter] = [
      .equals(field: fixture.category.name, value: .string("even"))
    ]
    let order = InstantQueryOrder(fixture.score.name, .descending)
    let unbounded = await store.materialize(
      InstantQueryPlan(
        id: "unbounded.filtered",
        namespace: fixture.namespace,
        filters: filters,
        order: order
      )
    )
    let bounded = await store.materializePageWithMetrics(
      InstantQueryPlan(
        id: "bounded.filtered",
        namespace: fixture.namespace,
        filters: filters,
        order: order,
        offset: 7,
        limit: 6
      )
    )

    expectNoDifference(
      bounded.page.values,
      Array(unbounded.dropFirst(7).prefix(6))
    )
    expectNoDifference(bounded.metrics.examinedCandidateCount, 100)
    expectNoDifference(bounded.metrics.matchingCandidateCount, 100)
    expectNoDifference(bounded.metrics.materializedSnapshotCount, 6)
    expectNoDifference(bounded.metrics.maximumRetainedCandidateCount, 14)
    expectNoDifference(bounded.metrics.boundedSelectionCount, 1)
  }

  @Test
  func reverseIncludeBoundsChildrenBeforeSnapshotAndDeferredValueMaterialization() async throws {
    let fixture = BoundedReverseIncludeFixture(childCount: 10_000)
    let store = fixture.store()
    let measurement = await store.materializePageWithMetrics(fixture.query)
    let parent = try #require(measurement.page.values.first)
    let children = try #require(parent.links?[fixture.reverseRelationName])

    expectNoDifference(parent.id, fixture.parentID)
    expectNoDifference(children.map(\.id), ["child-09999", "child-09998"])
    expectNoDifference(children.compactMap { $0.number(fixture.rank.name) }, [9_999, 9_998])
    expectNoDifference(children.compactMap { $0.values[fixture.payload.name] }, [])
    expectNoDifference(measurement.metrics.examinedCandidateCount, 10_001)
    expectNoDifference(measurement.metrics.matchingCandidateCount, 10_001)
    expectNoDifference(measurement.metrics.materializedSnapshotCount, 3)
    expectNoDifference(measurement.metrics.maximumRetainedCandidateCount, 2)
    expectNoDifference(measurement.metrics.boundedSelectionCount, 2)
  }

  @Test
  func boundedObservationStillEmitsAReorderedLeadingPage() async throws {
    let fixture = BoundedQueryFixture(rowCount: 3)
    let store = fixture.store()
    let plan = InstantQueryPlan(
      id: "bounded.observed",
      namespace: fixture.namespace,
      order: InstantQueryOrder(fixture.score.name, .descending),
      limit: 2
    )
    let stream = await store.observe(plan)

    let initial = try await nextBoundedQueryEmission(from: stream)
    expectNoDifference(initial.values.map(\.id), ["item-00000", "item-00001"])

    let entityID = "item-leading"
    let timestamp = InstantTimestamp(milliseconds: 20_000)
    let prepared = try await store.prepareCurrent(
      InstantStoreTransaction(
        id: "insert-leading",
        operations: [
          .insert(
            InstantTriple(
              entityID: entityID,
              attributeID: fixture.id.id,
              value: .string(entityID),
              txID: "insert-leading",
              txTime: timestamp
            )
          ),
          .insert(
            InstantTriple(
              entityID: entityID,
              attributeID: fixture.score.id,
              value: .number(100),
              txID: "insert-leading",
              txTime: timestamp
            )
          ),
          .insert(
            InstantTriple(
              entityID: entityID,
              attributeID: fixture.category.id,
              value: .string("even"),
              txID: "insert-leading",
              txTime: timestamp
            )
          ),
        ]
      )
    )
    _ = await store.commitAndPublish(prepared)

    let updated = try await nextBoundedQueryEmission(from: stream)
    expectNoDifference(updated.sequence, initial.sequence + 1)
    expectNoDifference(updated.values.map(\.id), [entityID, "item-00000"])
  }
}

private func nextBoundedQueryEmission(
  from stream: AsyncStream<InstantQueryEmission>
) async throws -> InstantQueryEmission {
  try await withThrowingTaskGroup(of: InstantQueryEmission.self) { group in
    group.addTask {
      var iterator = stream.makeAsyncIterator()
      guard let emission = await iterator.next() else {
        throw BoundedQueryObservationEnded()
      }
      return emission
    }
    group.addTask {
      try await Task.sleep(for: .seconds(5))
      throw BoundedQueryObservationTimedOut()
    }
    defer { group.cancelAll() }
    guard let emission = try await group.next() else {
      throw BoundedQueryObservationEnded()
    }
    return emission
  }
}

private struct BoundedQueryObservationEnded: Error, CustomStringConvertible {
  var description: String {
    "The bounded-query observation ended before emitting the expected value."
  }
}

private struct BoundedQueryObservationTimedOut: Error, CustomStringConvertible {
  var description: String {
    "The bounded-query observation did not emit within five seconds."
  }
}

private struct BoundedQueryFixture {
  let namespace = "items"
  let rowCount: Int
  let id: InstantAttribute
  let score: InstantAttribute
  let category: InstantAttribute

  init(rowCount: Int) {
    self.rowCount = rowCount
    self.id = .primaryKey(namespace: namespace)
    self.score = InstantAttribute(
      id: "items/score",
      namespace: namespace,
      name: "score",
      valueType: .number,
      isIndexed: true
    )
    self.category = InstantAttribute(
      id: "items/category",
      namespace: namespace,
      name: "category",
      valueType: .string,
      isIndexed: true
    )
  }

  func store() -> InstantStore {
    var triples: [InstantTriple] = []
    triples.reserveCapacity(rowCount * 3)
    for index in 0..<rowCount {
      let entityID = String(format: "item-%05d", index)
      let timestamp = InstantTimestamp(milliseconds: Int64(index + 1))
      let transactionID = "seed-\(index)"
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: id.id,
          value: .string(entityID),
          txID: transactionID,
          txTime: timestamp
        )
      )
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: score.id,
          value: .number(Double(rowCount - index)),
          txID: transactionID,
          txTime: timestamp
        )
      )
      triples.append(
        InstantTriple(
          entityID: entityID,
          attributeID: category.id,
          value: .string(index.isMultiple(of: 2) ? "even" : "odd"),
          txID: transactionID,
          txTime: timestamp
        )
      )
    }
    return InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [id, score, category],
        triples: triples
      )
    )
  }
}

private struct ImplicitOrderIndexedFixture {
  let namespace = "implicit-items"
  let identifier: InstantAttribute
  let category: InstantAttribute
  let store: InstantStore

  init() {
    let identifier = InstantAttribute.primaryKey(namespace: namespace)
    let category = InstantAttribute(
      id: "implicit-items/category",
      namespace: namespace,
      name: "category",
      valueType: .string,
      isIndexed: true
    )
    self.identifier = identifier
    self.category = category
    let rows: [(id: String, createdAt: Int64)] = [
      ("a-latest", 30),
      ("m-middle", 20),
      ("z-oldest", 10),
    ]
    self.store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [identifier, category],
        triples: rows.flatMap { row in
          let timestamp = InstantTimestamp(milliseconds: row.createdAt)
          return [
            InstantTriple(
              entityID: row.id,
              attributeID: identifier.id,
              value: .string(row.id),
              txID: "seed-\(row.id)",
              txTime: timestamp
            ),
            InstantTriple(
              entityID: row.id,
              attributeID: category.id,
              value: .string("included"),
              txID: "seed-\(row.id)",
              txTime: timestamp
            ),
          ]
        }
      )
    )
  }
}

private struct BoundedReverseIncludeFixture {
  let parentNamespace = "parents"
  let childNamespace = "children"
  let reverseRelationName = "children"
  let parentID = "parent"
  let childCount: Int
  let parentIdentifier: InstantAttribute
  let childIdentifier: InstantAttribute
  let rank: InstantAttribute
  let payload: InstantAttribute
  let parent: InstantAttribute

  init(childCount: Int) {
    self.childCount = childCount
    self.parentIdentifier = .primaryKey(namespace: parentNamespace)
    self.childIdentifier = .primaryKey(namespace: childNamespace)
    self.rank = InstantAttribute(
      id: "children/rank",
      namespace: childNamespace,
      name: "rank",
      valueType: .number,
      isIndexed: true
    )
    self.payload = InstantAttribute(
      id: "children/payload",
      namespace: childNamespace,
      name: "payload",
      valueType: .json
    )
    self.parent = InstantAttribute(
      id: "children/parent",
      namespace: childNamespace,
      name: "parent",
      valueType: .ref,
      isIndexed: true,
      forwardIdentity: "children/parent",
      reverseIdentity: "parents/children",
      linkNamespace: parentNamespace
    )
  }

  var query: InstantQueryPlan {
    InstantQueryPlan(
      id: "parents.with-bounded-children",
      namespace: parentNamespace,
      limit: 1,
      includes: [
        InstantQueryInclude(
          reverseRelationName,
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "children.latest-two",
            namespace: childNamespace,
            order: InstantQueryOrder(rank.name, .descending),
            limit: 2,
            selectedFields: [rank.name, payload.name]
          )
        )
      ]
    )
  }

  func store() -> InstantStore {
    var triples: [InstantTriple] = [
      InstantTriple(
        entityID: parentID,
        attributeID: parentIdentifier.id,
        value: .string(parentID),
        txID: "seed-parent",
        txTime: InstantTimestamp(milliseconds: 1)
      )
    ]
    triples.reserveCapacity(1 + childCount * 4)
    for index in 0..<childCount {
      let childID = String(format: "child-%05d", index)
      let transactionID = "seed-child-\(index)"
      let timestamp = InstantTimestamp(milliseconds: Int64(index + 2))
      triples.append(
        InstantTriple(
          entityID: childID,
          attributeID: childIdentifier.id,
          value: .string(childID),
          txID: transactionID,
          txTime: timestamp
        )
      )
      triples.append(
        InstantTriple(
          entityID: childID,
          attributeID: rank.id,
          value: .number(Double(index)),
          txID: transactionID,
          txTime: timestamp
        )
      )
      triples.append(
        InstantTriple(
          entityID: childID,
          attributeID: payload.id,
          value: .json(.string(String(repeating: "x", count: 1_024))),
          txID: transactionID,
          txTime: timestamp
        )
      )
      triples.append(
        InstantTriple(
          entityID: childID,
          attributeID: parent.id,
          value: .ref(parentID),
          txID: transactionID,
          txTime: timestamp
        )
      )
    }
    return InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: [parentIdentifier, childIdentifier, rank, payload, parent],
        triples: triples
      ),
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: [payload.id]
      )
    )
  }
}

private extension InstantLinkedEntitySnapshot {
  func number(_ field: String) -> Double? {
    guard case let .number(value)? = values[field]?.first else { return nil }
    return value
  }
}
