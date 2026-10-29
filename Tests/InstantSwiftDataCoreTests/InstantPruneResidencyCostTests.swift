// History:
// - 2026-10-28: a prune batch reads the hot store's facts only of entities it can drop, and checks a kept entity again
//   only when a later batch releases another of its facts (#1319).

import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #1319: on a phone's store every prune batch held the operation gate 1.0-3.5 s, and on a copy of that store on a Mac
/// 300-660 ms, because each batch materialized every fact of every entity it might drop (#259's whole-entity rule) and
/// of every entity an earlier batch kept. A recording keeps its has-many links on itself (2,888 attachment links and 736
/// segment links on one of them), so a batch that released a list of recordings, or that carried one, read 31,000-57,000
/// facts for a few hundred entities.
///
/// Here one entity, the hub, holds 5,000 facts no result owns, and every result releases two of its other facts, as a
/// recording list releases a recording's title. The whole-entity rule keeps the hub. A batch has to know that much, not
/// read its 5,002 facts.
@Suite(.serialized)
struct InstantPruneResidencyCostTests {
  static let hubID = "prune-hub"
  static let hubTagCount = 5_000
  static let smallResultCount = 24
  static let todosPerSmallResult = 100
  /// One result larger than a batch, released over later batches a chunk at a time (#1129).
  static let todosInLargeResult = 1_200

  static let tagsAttribute = InstantAttribute(
    id: "todos/tags",
    namespace: TodoExample.namespace,
    name: "tags",
    valueType: .string,
    cardinality: .many
  )

  static var attributes: [InstantAttribute] { TodoExample.attributes + [tagsAttribute] }

  static func todo(_ index: Int) -> [InstantTriple] {
    InstantPruneGateHoldTests.todoTriples(index)
  }

  static let hubTime = InstantTimestamp(milliseconds: 1_700_000_319_000)

  /// The hub's id and text, which every result holds, as a recording list holds each recording's title.
  static var hubListedFacts: [InstantTriple] {
    [
      InstantTriple(entityID: hubID, attributeID: "todos/id", value: .string(hubID), txID: "seed", txTime: hubTime),
      InstantTriple(entityID: hubID, attributeID: "todos/text", value: .string("hub"), txID: "seed", txTime: hubTime),
    ]
  }

  /// The hub's links, which no result holds.
  static var hubTags: [InstantTriple] {
    (0..<hubTagCount).map {
      InstantTriple(entityID: hubID, attributeID: "todos/tags", value: .string("tag-\($0)"), txID: "seed", txTime: hubTime)
    }
  }

  struct Seeded {
    var url: URL
    var releasedFactCount: Int
  }

  static func seed() async throws -> Seeded {
    let url = try InstantPruneGateHoldTests.temporaryCacheURL()
    let seededAt = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    let persistence = try SQLitePersistenceStore(fileURL: url)
    try await persistence.bootstrap()
    var results: [InstantPersistedLiveQueryResult] = []
    var triples = hubListedFacts + hubTags
    var releasedFactCount = 0
    func add(key: String, todos: Range<Int>, offset: Int) {
      let resultTriples = todos.flatMap(todo) + hubListedFacts
      triples.append(contentsOf: todos.flatMap(todo))
      releasedFactCount += resultTriples.count
      results.append(
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(key: key, triples: resultTriples, pageInfo: nil),
          updatedAt: InstantTimestamp(milliseconds: seededAt + Int64(offset))
        )
      )
    }
    for result in 0..<smallResultCount {
      add(
        key: "hub-small-result-\(result)",
        todos: (result * todosPerSmallResult)..<((result + 1) * todosPerSmallResult),
        offset: result
      )
    }
    let largeStart = smallResultCount * todosPerSmallResult
    add(key: "hub-large-result", todos: largeStart..<(largeStart + todosInLargeResult), offset: smallResultCount)
    let saved = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(store: InstantStoreSnapshot(attributes: attributes, triples: triples), outbox: []),
      queryResults: results,
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.prune-residency",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 100),
      expectedStoreRevision: 0,
      expectedOutboxRevision: 0,
      expectedAttributeRevision: 0
    )
    #expect(saved)
    return Seeded(url: url, releasedFactCount: releasedFactCount)
  }

  @Test
  func aBatchReadsTheFactsOnlyOfEntitiesItCanDrop() async throws {
    let seeded = try await Self.seed()
    let session = LiveReactorParitySession(messages: [liveReactorInitOK(attrs: liveReactorTodoServerAttrs)])
    var configuration = InstantRuntimeConfiguration(
      appID: "prune-residency",
      persistenceURL: seeded.url,
      initialAttributes: Self.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.liveQueryResultPruneBatchTripleCount = 1_000
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    // One live query is open, so every seeded result is closed.
    let observation = await runtime.observeQueryLease(TodoExample.query)
    await runtime.store.resetFactsMaterializedForPruneForTesting()

    let pruned = try await runtime.pruneLiveQueryResults(
      policy: configuration.liveQueryResultPruningPolicy,
      now: configuration.now()
    )

    let materialized = await runtime.store.factsMaterializedForPruneForTesting
    let snapshot = await runtime.store.snapshot()
    await observation.cancel()
    _ = try? await runtime.closeConnection()

    expectNoDifference(pruned.removedQueryKeys.count, Self.smallResultCount + 1)
    // The hub stays whole: it holds facts no result owns.
    let hubFacts = snapshot.triples.filter { $0.entityID == Self.hubID }
    expectNoDifference(hubFacts.count, Self.hubTagCount + 2)
    // Every todo only the closed results held is gone.
    expectNoDifference(snapshot.triples.filter { $0.entityID.hasPrefix("prune-todo-") }.count, 0)
    // Each fact a batch may drop is read once; the hub's 5,002 never.
    #expect(
      materialized <= seeded.releasedFactCount,
      "the prune materialized \(materialized) facts to release \(seeded.releasedFactCount)"
    )
  }
}
