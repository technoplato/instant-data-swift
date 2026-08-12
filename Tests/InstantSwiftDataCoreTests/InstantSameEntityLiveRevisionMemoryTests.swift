import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Memory mirror of the live-speech balloon (#044 / #155).
///
/// SQLite Data: a screen owns a `FetchKeyRequest` that runs SQL. GRDB invalidates
/// by table. Closing the screen cancels the request. A live-row update does not
/// re-read finalized history.
///
/// Instant TypeScript (`upstream/instant/client/packages/core/src/store.ts`,
/// `Reactor.js`): one in-memory EAV store plus per-query `querySubs` result
/// caches. Pending mutations are a Map, not a second full graph.
///
/// Instant Swift Data: `InstantStore` keeps the entire corpus in RAM. SQLite is a
/// second copy of that corpus. `InstantFetchKeyRequest` does not run SQL. On each
/// `commitAndPublish`, Instant rematerializes every observer whose namespace
/// matches from those RAM maps and rebuilds the sorted result.
///
/// These tests measure retained UTF-8 bytes of rematerialized emissions, not only
/// row counts. The split live/history contract is the SQLite Data shape.
@Suite(.serialized)
struct InstantSameEntityLiveRevisionMemoryTests {
  private let siblingCount = 1_000
  private let siblingTextByteCount = 1_024
  private let livePutCount = 50

  @Test
  func unboundedLivePutCopiesFinalizedHistoryBytes() async throws {
    let fixture = try await MemoryFixture.seeded(siblingCount: siblingCount, siblingTextByteCount: siblingTextByteCount)
    let historyBytes = siblingCount * siblingTextByteCount
    let observation = await fixture.store.observe(fixture.unboundedPlan)
    var iterator = observation.makeAsyncIterator()
    let seeded = await iterator.next()
    let seededBytes = seeded?.retainedUTF8ByteCount ?? 0
    #expect(
      seededBytes >= historyBytes,
      "Seeded unbounded observation retained \(seededBytes) bytes; finalized history text is \(historyBytes) bytes."
    )

    let published = try await fixture.applyLiveRevision(revision: 1, text: "I", publishing: true)
    let publishedBytes = published.result.emissions.reduce(0) { $0 + $1.retainedUTF8ByteCount }
    #expect(
      publishedBytes >= historyBytes,
      """
      A live put rematerialized \(publishedBytes) UTF-8 bytes across \
      \(published.result.emissions.count) emissions (\(published.result.emissions.first?.values.count ?? 0) rows). \
      Finalized history is \(historyBytes) bytes. Instant TypeScript querySubs would keep a per-query cache; \
      SQLite Data would SQL-select only the live row. InstantStore rebuilt the namespace from TripleIndexes.
      """
    )
  }

  @Test
  func liveAndHistoryScreensDoNotRereadFinalizedHistoryOnLivePut() async throws {
    let fixture = try await MemoryFixture.seeded(siblingCount: siblingCount, siblingTextByteCount: siblingTextByteCount)
    let historyBytes = siblingCount * siblingTextByteCount
    let liveLease = await fixture.store.observeQueryLease(fixture.livePlan)
    let historyLease = await fixture.store.observeQueryLease(fixture.historyPlan)
    var liveIterator = liveLease.stream.makeAsyncIterator()
    var historyIterator = historyLease.stream.makeAsyncIterator()
    let liveSeed = try #require(await liveIterator.next())
    let historySeed = try #require(await historyIterator.next())
    expectNoDifference(liveSeed.values.count, 1)
    expectNoDifference(historySeed.values.count, siblingCount)
    #expect(historySeed.retainedUTF8ByteCount >= historyBytes)

    let liveText = "I think this is the live row"
    let published = try await fixture.applyLiveRevision(revision: 1, text: liveText, publishing: true)
    let publishedHistory = published.result.emissions.contains { $0.queryID == fixture.historyPlan.id }
    let liveEmission = published.result.emissions.first { $0.queryID == fixture.livePlan.id }
    let publishedBytes = published.result.emissions.reduce(0) { $0 + $1.retainedUTF8ByteCount }
    let liveBound = liveText.utf8.count * 4 + 256

    expectNoDifference(liveEmission?.values.count, 1)
    expectNoDifference(liveEmission?.values.first?.id, MemoryFixture.liveEntityID)
    expectNoDifference(publishedHistory, false)
    #expect(
      publishedBytes <= liveBound,
      """
      Live put published \(publishedBytes) UTF-8 bytes; live row is \(liveText.utf8.count) bytes; \
      finalized history is \(historyBytes) bytes. InstantFetchKeyRequest does not run SQL; commitAndPublish \
      rematerialized every namespace observer from RAM TripleIndexes.
      """
    )
  }

  @Test
  func closingTheHistoryScreenCancelsThatRequest() async throws {
    let fixture = try await MemoryFixture.seeded(siblingCount: 32, siblingTextByteCount: 16)
    let liveLease = await fixture.store.observeQueryLease(fixture.livePlan)
    let historyLease = await fixture.store.observeQueryLease(fixture.historyPlan)
    var liveIterator = liveLease.stream.makeAsyncIterator()
    _ = await liveIterator.next()
    let openedCount = await fixture.store.activeObservationCount()
    expectNoDifference(openedCount, 2)

    await historyLease.cancel()
    let afterHistoryClose = await fixture.store.activeObservationCount()
    expectNoDifference(afterHistoryClose, 1)

    let published = try await fixture.applyLiveRevision(revision: 1, text: "I", publishing: true)
    expectNoDifference(
      published.result.emissions.contains { $0.queryID == fixture.historyPlan.id },
      false
    )
    expectNoDifference(published.result.emissions.first?.queryID, fixture.livePlan.id)
    expectNoDifference(published.result.emissions.first?.values.count, 1)

    await liveLease.cancel()
    let afterLiveClose = await fixture.store.activeObservationCount()
    expectNoDifference(afterLiveClose, 0)
    let afterClose = try await fixture.applyLiveRevision(revision: 2, text: "I think", publishing: true)
    expectNoDifference(afterClose.result.emissions, [])
  }

  @Test
  func livePutsDoNotGrowPhysicalFootprintWithRevisionCount() async throws {
    let fixture = try await MemoryFixture.seeded(siblingCount: siblingCount, siblingTextByteCount: siblingTextByteCount)
    let liveLease = await fixture.store.observeQueryLease(fixture.livePlan)
    let historyLease = await fixture.store.observeQueryLease(fixture.historyPlan)
    var liveIterator = liveLease.stream.makeAsyncIterator()
    var historyIterator = historyLease.stream.makeAsyncIterator()
    _ = await liveIterator.next()
    _ = await historyIterator.next()

    let baseline = InstantProcessMemory.sample()
    var lastPublishedBytes = 0
    for revision in 1...livePutCount {
      let published = try await fixture.applyLiveRevision(
        revision: revision,
        text: String(repeating: "w", count: min(revision, 64)),
        publishing: true
      )
      lastPublishedBytes = published.result.emissions.reduce(0) { $0 + $1.retainedUTF8ByteCount }
    }
    let after = InstantProcessMemory.sample()
    let historyBytes = siblingCount * siblingTextByteCount
    #expect(
      lastPublishedBytes <= 64 * 4 + 256,
      """
      After \(livePutCount) live puts the last publish copied \(lastPublishedBytes) bytes. \
      Finalized history is \(historyBytes) bytes. Observation work must stay with the live row.
      """
    )
    if let baseline, let after {
      let growth = Int64(after.physicalFootprintBytes) - Int64(baseline.physicalFootprintBytes)
      #expect(
        growth < 8_000_000,
        """
        Physical footprint grew \(growth) bytes across \(livePutCount) live puts \
        (baseline \(baseline.physicalFootprintBytes), after \(after.physicalFootprintBytes)). \
        History corpus is \(historyBytes) bytes. InstantStore must not copy that corpus on each put.
        """
      )
    }

    _ = liveLease
    _ = historyLease
  }

  @Test
  func snapshotRetainsTheCorpusWhileLiveObservationStaysLocal() async throws {
    let fixture = try await MemoryFixture.seeded(siblingCount: siblingCount, siblingTextByteCount: siblingTextByteCount)
    let snapshot = await fixture.store.snapshot()
    let snapshotBytes = snapshot.triples.reduce(0) { $0 + $1.value.retainedUTF8ByteCount }
    let historyBytes = siblingCount * siblingTextByteCount
    #expect(
      snapshotBytes >= historyBytes,
      "InstantStore.snapshot() reconstructed \(snapshotBytes) triple bytes; history text is \(historyBytes) bytes. The RAM TripleIndexes hold the corpus; SQLite is a second copy."
    )

    let liveLease = await fixture.store.observeQueryLease(fixture.livePlan)
    var liveIterator = liveLease.stream.makeAsyncIterator()
    _ = await liveIterator.next()
    let published = try await fixture.applyLiveRevision(revision: 1, text: "I", publishing: true)
    let liveBytes = published.result.emissions.reduce(0) { $0 + $1.retainedUTF8ByteCount }
    #expect(
      liveBytes < snapshotBytes / 10,
      """
      Live observation published \(liveBytes) bytes after a put while snapshot() holds \(snapshotBytes) bytes. \
      FetchInstantKeyRequest must not rebuild the RAM corpus. SQLite Data FetchKeyRequest.fetch(_ db:) runs SQL.
      """
    )
    expectNoDifference(snapshot.triples.count, (siblingCount + 1) * 3)
  }

  @Test
  func finalizingTheLiveRowPublishesHistoryAndClearsLive() async throws {
    let fixture = try await MemoryFixture.seeded(siblingCount: 8, siblingTextByteCount: 16)
    let liveLease = await fixture.store.observeQueryLease(fixture.livePlan)
    let historyLease = await fixture.store.observeQueryLease(fixture.historyPlan)
    var liveIterator = liveLease.stream.makeAsyncIterator()
    var historyIterator = historyLease.stream.makeAsyncIterator()
    _ = await liveIterator.next()
    _ = await historyIterator.next()

    let timestamp = InstantTimestamp(milliseconds: 9_000)
    let prepared = try await fixture.store.prepareCurrent(
      InstantStoreTransaction(
        id: "finalize-live",
        operations: [
          .insert(
            InstantTriple(
              entityID: MemoryFixture.liveEntityID,
              attributeID: "segments/finalized",
              value: .bool(true),
              txID: "finalize-live",
              txTime: timestamp
            )
          )
        ]
      )
    )
    let published = await fixture.store.commitAndPublish(prepared)
    let liveEmission = published.result.emissions.first { $0.queryID == fixture.livePlan.id }
    let historyEmission = published.result.emissions.first { $0.queryID == fixture.historyPlan.id }
    expectNoDifference(liveEmission?.values.count, 0)
    expectNoDifference(historyEmission?.values.count, 9)
    expectNoDifference(
      historyEmission?.values.map(\.id).contains(MemoryFixture.liveEntityID),
      true
    )
  }

  @Test
  func livePutSplicesChangedRowWithoutRematerializingSiblings() async throws {
    let fixture = try await MemoryFixture.seeded(
      siblingCount: siblingCount,
      siblingTextByteCount: siblingTextByteCount
    )
    let observation = await fixture.store.observe(fixture.unboundedPlan)
    var iterator = observation.makeAsyncIterator()
    _ = await iterator.next()

    let published = try await fixture.applyLiveRevision(revision: 1, text: "I think", publishing: true)
    let metrics = await fixture.store.lastPublishMetrics
    expectNoDifference(published.result.emissions.first?.values.count, siblingCount + 1)
    expectNoDifference(metrics.splicedObserverCount, 1)
    expectNoDifference(metrics.rematerializedObserverCount, 0)
    print("primary: \(metrics.materializedSnapshotCount)")
    #expect(
      metrics.materializedSnapshotCount <= 4,
      """
      Live put materialized \(metrics.materializedSnapshotCount) snapshots. \
      Instant TypeScript notifyOne re-runs instaql then areObjectsDeepEqual; \
      SQLite Data invalidates by table and re-runs the screen SQL. InstantStore \
      must splice the live row instead of walking \(siblingCount) siblings.
      """
    )
  }

  @Test
  func includeObserverSkipsUnrelatedNamespaceMutation() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: TodoProjectExample.attributes + MemoryFixture.attributes
      )
    )
    let seed = InstantStoreTransaction(
      id: "seed-include-skip",
      operations: TodoProjectExample.createProjectOperations(
        id: "project-1",
        title: "Launch",
        createdAt: createdAt,
        transactionID: "seed-include-skip"
      ) + TodoExample.createOperations(
        id: "todo-1",
        text: "linked",
        createdAt: createdAt,
        transactionID: "seed-include-skip"
      ) + TodoProjectExample.linkOperations(
        todoID: "todo-1",
        projectID: "project-1",
        updatedAt: createdAt,
        transactionID: "seed-include-skip"
      )
    )
    _ = await store.commitAndPublish(try await store.prepareCurrent(seed))
    let lease = await store.observeQueryLease(TodoProjectExample.projectsWithTodosQuery)
    var iterator = lease.stream.makeAsyncIterator()
    _ = await iterator.next()

    let published = await store.commitAndPublish(
      try await store.prepareCurrent(
        InstantStoreTransaction(
          id: "unrelated-segment",
          operations: [
            .insert(
              InstantTriple(
                entityID: "segment-unrelated",
                attributeID: "segments/text",
                value: .string("ignore"),
                txID: "unrelated-segment",
                txTime: createdAt
              )
            )
          ]
        )
      )
    )
    let metrics = await store.lastPublishMetrics
    expectNoDifference(published.result.emissions, [])
    expectNoDifference(metrics.skippedObserverCount, 1)
    expectNoDifference(metrics.rematerializedObserverCount, 0)
    await lease.cancel()
  }

  @Test
  func includeObserverSplicesParentWhenIncludedChildChanges() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    var operations: [InstantTripleOperation] = []
    for index in 0..<32 {
      operations += TodoProjectExample.createProjectOperations(
        id: "project-\(index)",
        title: "Project \(index)",
        createdAt: InstantTimestamp(milliseconds: createdAt.milliseconds + Int64(index)),
        transactionID: "seed-include-splice"
      )
    }
    operations += TodoExample.createOperations(
      id: "todo-live",
      text: "before",
      createdAt: createdAt,
      transactionID: "seed-include-splice"
    )
    operations += TodoProjectExample.linkOperations(
      todoID: "todo-live",
      projectID: "project-0",
      updatedAt: createdAt,
      transactionID: "seed-include-splice"
    )
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: TodoProjectExample.attributes)
    )
    _ = await store.commitAndPublish(
      try await store.prepareCurrent(
        InstantStoreTransaction(id: "seed-include-splice", operations: operations)
      )
    )
    let lease = await store.observeQueryLease(TodoProjectExample.projectsWithTodosQuery)
    var iterator = lease.stream.makeAsyncIterator()
    let seeded = try #require(await iterator.next())
    expectNoDifference(seeded.values.count, 32)

    let published = await store.commitAndPublish(
      try await store.prepareCurrent(
        InstantStoreTransaction(
          id: "update-included-todo",
          operations: [
            .insert(
              InstantTriple(
                entityID: "todo-live",
                attributeID: "todos/text",
                value: .string("after"),
                txID: "update-included-todo",
                txTime: InstantTimestamp(milliseconds: createdAt.milliseconds + 100)
              )
            )
          ]
        )
      )
    )
    let metrics = await store.lastPublishMetrics
    let emission = try #require(published.result.emissions.first)
    expectNoDifference(emission.values.count, 32)
    expectNoDifference(
      emission.values.first { $0.id == "project-0" }?
        .includedEntitySnapshots(named: "todos").first?.values["text"]?.first,
      .string("after")
    )
    expectNoDifference(metrics.splicedObserverCount, 1)
    expectNoDifference(metrics.rematerializedObserverCount, 0)
    #expect(
      metrics.materializedSnapshotCount <= 4,
      "Included-child put materialized \(metrics.materializedSnapshotCount) snapshots; splice the parent row instead of rematerializing 32 projects."
    )
    await lease.cancel()
  }
}

private struct MemoryFixture {
  static let liveEntityID = "segment-live"

  var store: InstantStore
  var livePlan: InstantQueryPlan
  var historyPlan: InstantQueryPlan
  var unboundedPlan: InstantQueryPlan

  static func seeded(siblingCount: Int, siblingTextByteCount: Int) async throws -> Self {
    let siblingText = String(repeating: "h", count: siblingTextByteCount)
    let seed = siblingTriples(count: siblingCount, text: siblingText) + liveTriples(revision: 0, text: "")
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: attributes, triples: seed)
    )
    return Self(
      store: store,
      livePlan: InstantQueryPlan(
        id: "live-segments",
        namespace: "segments",
        filters: [.equals(field: "finalized", value: .bool(false))]
      ),
      historyPlan: InstantQueryPlan(
        id: "history-segments",
        namespace: "segments",
        filters: [.equals(field: "finalized", value: .bool(true))]
      ),
      unboundedPlan: InstantQueryPlan(id: "all-segments", namespace: "segments")
    )
  }

  func applyLiveRevision(
    revision: Int,
    text: String,
    publishing: Bool
  ) async throws -> PreparedStoreMutation {
    let timestamp = InstantTimestamp(milliseconds: Int64(revision + 1_000))
    let transaction = InstantStoreTransaction(
      id: "live-\(revision)",
      operations: [
        .insert(
          InstantTriple(
            entityID: Self.liveEntityID,
            attributeID: "segments/text",
            value: .string(text),
            txID: "live-\(revision)",
            txTime: timestamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: Self.liveEntityID,
            attributeID: "segments/revision",
            value: .number(Double(revision)),
            txID: "live-\(revision)",
            txTime: timestamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: Self.liveEntityID,
            attributeID: "segments/finalized",
            value: .bool(false),
            txID: "live-\(revision)",
            txTime: timestamp
          )
        ),
      ]
    )
    let prepared = try await store.prepareCurrent(transaction)
    if publishing {
      return await store.commitAndPublish(prepared)
    }
    return await store.commit(prepared)
  }

  fileprivate static let attributes = [
    InstantAttribute(
      id: "segments/text",
      namespace: "segments",
      name: "text",
      valueType: .string,
      cardinality: .one
    ),
    InstantAttribute(
      id: "segments/revision",
      namespace: "segments",
      name: "revision",
      valueType: .number,
      cardinality: .one
    ),
    InstantAttribute(
      id: "segments/finalized",
      namespace: "segments",
      name: "finalized",
      valueType: .boolean,
      cardinality: .one,
      isIndexed: true
    ),
  ]

  private static func liveTriples(revision: Int, text: String) -> [InstantTriple] {
    [
      InstantTriple(
        entityID: liveEntityID,
        attributeID: "segments/text",
        value: .string(text),
        txID: "seed-live",
        txTime: InstantTimestamp(milliseconds: Int64(revision))
      ),
      InstantTriple(
        entityID: liveEntityID,
        attributeID: "segments/revision",
        value: .number(Double(revision)),
        txID: "seed-live",
        txTime: InstantTimestamp(milliseconds: Int64(revision))
      ),
      InstantTriple(
        entityID: liveEntityID,
        attributeID: "segments/finalized",
        value: .bool(false),
        txID: "seed-live",
        txTime: InstantTimestamp(milliseconds: Int64(revision))
      ),
    ]
  }

  private static func siblingTriples(count: Int, text: String) -> [InstantTriple] {
    (0..<count).flatMap { index in
      [
        InstantTriple(
          entityID: "segment-final-\(index)",
          attributeID: "segments/text",
          value: .string(text),
          txID: "seed-final-\(index)",
          txTime: InstantTimestamp(milliseconds: 1)
        ),
        InstantTriple(
          entityID: "segment-final-\(index)",
          attributeID: "segments/revision",
          value: .number(Double(index)),
          txID: "seed-final-\(index)",
          txTime: InstantTimestamp(milliseconds: 1)
        ),
        InstantTriple(
          entityID: "segment-final-\(index)",
          attributeID: "segments/finalized",
          value: .bool(true),
          txID: "seed-final-\(index)",
          txTime: InstantTimestamp(milliseconds: 1)
        ),
      ]
    }
  }
}

extension InstantQueryEmission {
  fileprivate var retainedUTF8ByteCount: Int {
    values.reduce(0) { $0 + $1.retainedUTF8ByteCount }
  }
}

extension InstantEntitySnapshot {
  fileprivate var retainedUTF8ByteCount: Int {
    values.values.reduce(0) { partial, materialized in
      partial + materialized.values.reduce(0) { $0 + $1.retainedUTF8ByteCount }
    }
  }
}

extension InstantValue {
  fileprivate var retainedUTF8ByteCount: Int {
    switch self {
    case .null, .number, .bool, .date:
      return 0
    case let .string(value), let .ref(value):
      return value.utf8.count
    case let .json(value):
      return value.retainedUTF8ByteCount
    case let .lookupRef(lookup):
      return lookup.value.instantValue.retainedUTF8ByteCount
    }
  }
}

extension JSONValue {
  fileprivate var retainedUTF8ByteCount: Int {
    switch self {
    case .null, .bool, .number:
      return 0
    case let .string(value):
      return value.utf8.count
    case let .array(values):
      return values.reduce(0) { $0 + $1.retainedUTF8ByteCount }
    case let .object(object):
      return object.reduce(0) { $0 + $1.key.utf8.count + $1.value.retainedUTF8ByteCount }
    }
  }
}
