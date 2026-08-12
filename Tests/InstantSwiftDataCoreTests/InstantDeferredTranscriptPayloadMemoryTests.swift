import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Scribe-shaped deferred transcript payloads (#044 / #155).
///
/// SQLite Data: GRDB keeps the corpus on disk. A screen SQL LIMIT loads the
/// visible page. A live-row update does not copy finalized `text` / `wordsJSON`
/// into RAM.
///
/// Instant TypeScript (`upstream/instant/client/packages/core/src/store.ts`,
/// `Reactor.js`): the hot graph is in-memory EAV of every triple, including
/// blobs. IndexedDB stores `querySubs` and `pendingMutations`, not a second
/// full graph. TypeScript has no deferred-attribute strip.
///
/// Instant Swift Data: `InstantDeferredValueResidencyPolicy` is a deliberate
/// SQLite-backed divergence. Configured non-indexed cardinality-one payloads
/// stay in SQLite. `TripleIndexes` keeps identity and order. A selected page
/// hydrates only those fields. Live `transact` still writes every revision to
/// the outbox. This suite measures hot-store UTF-8 bytes for Scribe segment
/// `text` + `wordsJSON` strings, not JSON route chunks.
@Suite(.serialized)
struct InstantDeferredTranscriptPayloadMemoryTests {
  private let siblingCount = 1_000
  private let payloadByteCount = 1_024
  private let pageSize = 32

  @Test
  func residentCorpusKeepsTranscriptPayloadsInTheHotStore() async throws {
    let cacheURL = temporaryTranscriptCacheURL("resident")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let fixture = TranscriptPayloadFixture(
      siblingCount: siblingCount,
      payloadByteCount: payloadByteCount
    )
    try await seedTranscriptCache(cacheURL, fixture: fixture)
    let runtime = try await transcriptRuntime(cacheURL, fixture: fixture, defersPayloads: false)
    let hotBytes = payloadBytes(in: await runtime.store.snapshot().triples, fixture: fixture)
    let corpusBytes = siblingCount * payloadByteCount * 2
    #expect(
      hotBytes >= corpusBytes,
      """
      Resident bootstrap retained \(hotBytes) UTF-8 payload bytes in TripleIndexes; \
      the 1,000-row text+wordsJSON corpus is \(corpusBytes) bytes. This is the Instant \
      Scribe RAM floor when segment payloads are not deferred.
      """
    )
    print("baseline_hot_store_payload_bytes: \(hotBytes)")
  }

  @Test
  func deferredCorpusLeavesTranscriptPayloadsOutOfTheHotStore() async throws {
    let cacheURL = temporaryTranscriptCacheURL("deferred")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let fixture = TranscriptPayloadFixture(
      siblingCount: siblingCount,
      payloadByteCount: payloadByteCount
    )
    try await seedTranscriptCache(cacheURL, fixture: fixture)
    let runtime = try await transcriptRuntime(cacheURL, fixture: fixture, defersPayloads: true)

    let hotTriples = await runtime.store.snapshot().triples
    let hotBytes = payloadBytes(in: hotTriples, fixture: fixture)
    expectNoDifference(hotBytes, 0)
    #expect(
      hotTriples.allSatisfy {
        $0.attributeID != fixture.textAttribute.id
          && $0.attributeID != fixture.wordsJSONAttribute.id
      }
    )

    let subscription = await runtime.subscribeInfiniteQuery(fixture.timelinePlan(limit: pageSize))
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()
    let firstPage = try #require(await iterator.next())
    expectNoDifference(firstPage.values.count, pageSize)
    expectNoDifference(
      firstPage.values.first?.values[fixture.textAttribute.name],
      .one(.string(fixture.payload("text-0")))
    )
    expectNoDifference(
      firstPage.values.first?.values[fixture.wordsJSONAttribute.name],
      .one(.string(fixture.payload("words-0")))
    )
    let pageMetrics = await runtime.persistence.deferredValueDecodeMetricsForTesting()
    expectNoDifference(pageMetrics.valueCount, pageSize * 2)
    #expect(pageMetrics.encodedByteCount >= payloadByteCount * pageSize * 2)

    let liveID = fixture.entityID(siblingCount - 1)
    let liveText = "live-revision"
    let transactionID = "live-put-deferred-transcript"
    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .requireEntityExists(entityID: liveID, namespace: fixture.namespace),
          .insert(
            InstantTriple(
              entityID: liveID,
              attributeID: fixture.textAttribute.id,
              value: .string(liveText),
              txID: transactionID,
              txTime: InstantTimestamp(milliseconds: 10_000)
            )
          ),
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 10_000)
    )

    let afterPutBytes = payloadBytes(in: await runtime.store.snapshot().triples, fixture: fixture)
    expectNoDifference(afterPutBytes, 0)
    let liveQuery = InstantQueryPlan(
      id: "live-row",
      namespace: fixture.namespace,
      filters: [.equals(field: fixture.idAttribute.name, value: .string(liveID))],
      limit: 1,
      selectedFields: [fixture.textAttribute.name]
    )
    let liveValue = try await runtime.query(liveQuery).first?.values[fixture.textAttribute.name]
    expectNoDifference(liveValue, .one(.string(liveText)))
    print("primary: \(afterPutBytes)")
    print("hydrated_page_rows: \(firstPage.values.count)")
    print("corpus_payload_bytes: \(siblingCount * payloadByteCount * 2)")
  }
}

private struct TranscriptPayloadFixture {
  let namespace = "transcriptionSegments"
  let siblingCount: Int
  let payloadByteCount: Int

  let idAttribute = InstantAttribute.primaryKey(namespace: "transcriptionSegments")
  let recordingIDAttribute = InstantAttribute(
    id: "transcriptionSegments/recordingID",
    namespace: "transcriptionSegments",
    name: "recordingID",
    valueType: .string,
    isIndexed: true
  )
  let segmentIndexAttribute = InstantAttribute(
    id: "transcriptionSegments/segmentIndex",
    namespace: "transcriptionSegments",
    name: "segmentIndex",
    valueType: .number,
    isIndexed: true
  )
  let textAttribute = InstantAttribute(
    id: "transcriptionSegments/text",
    namespace: "transcriptionSegments",
    name: "text",
    valueType: .string,
    isIndexed: false
  )
  let wordsJSONAttribute = InstantAttribute(
    id: "transcriptionSegments/wordsJSON",
    namespace: "transcriptionSegments",
    name: "wordsJSON",
    valueType: .string,
    isRequired: false,
    isIndexed: false
  )

  var attributes: [InstantAttribute] {
    [
      idAttribute,
      recordingIDAttribute,
      segmentIndexAttribute,
      textAttribute,
      wordsJSONAttribute,
    ]
  }

  var deferredAttributeIDs: [String] {
    [textAttribute.id, wordsJSONAttribute.id]
  }

  func entityID(_ index: Int) -> String {
    "segment-\(index)"
  }

  func payload(_ marker: String) -> String {
    marker + String(repeating: "x", count: max(0, payloadByteCount - marker.utf8.count))
  }

  func timelinePlan(limit: Int) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "scribe-timeline",
      namespace: namespace,
      filters: [.equals(field: recordingIDAttribute.name, value: .string("recording-a"))],
      order: InstantQueryOrder(segmentIndexAttribute.name),
      limit: limit,
      selectedFields: [textAttribute.name, wordsJSONAttribute.name]
    )
  }
}

private func transcriptRuntime(
  _ cacheURL: URL,
  fixture: TranscriptPayloadFixture,
  defersPayloads: Bool
) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "deferred-transcript-payloads",
      persistenceURL: cacheURL,
      initialAttributes: fixture.attributes,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: defersPayloads ? fixture.deferredAttributeIDs : []
      )
    )
  )
}

private func seedTranscriptCache(
  _ cacheURL: URL,
  fixture: TranscriptPayloadFixture
) async throws {
  let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
  try await persistence.bootstrap()
  var triples: [InstantTriple] = []
  triples.reserveCapacity(fixture.siblingCount * 5)
  for index in 0..<fixture.siblingCount {
    let entityID = fixture.entityID(index)
    let timestamp = InstantTimestamp(milliseconds: Int64(index + 1))
    let txID = "seed-\(entityID)"
    triples.append(
      InstantTriple(
        entityID: entityID,
        attributeID: fixture.idAttribute.id,
        value: .string(entityID),
        txID: txID,
        txTime: timestamp
      )
    )
    triples.append(
      InstantTriple(
        entityID: entityID,
        attributeID: fixture.recordingIDAttribute.id,
        value: .string("recording-a"),
        txID: txID,
        txTime: timestamp
      )
    )
    triples.append(
      InstantTriple(
        entityID: entityID,
        attributeID: fixture.segmentIndexAttribute.id,
        value: .number(Double(index)),
        txID: txID,
        txTime: timestamp
      )
    )
    triples.append(
      InstantTriple(
        entityID: entityID,
        attributeID: fixture.textAttribute.id,
        value: .string(fixture.payload("text-\(index)")),
        txID: txID,
        txTime: timestamp
      )
    )
    triples.append(
      InstantTriple(
        entityID: entityID,
        attributeID: fixture.wordsJSONAttribute.id,
        value: .string(fixture.payload("words-\(index)")),
        txID: txID,
        txTime: timestamp
      )
    )
  }
  try await persistence.saveStoreSnapshot(
    InstantStoreSnapshot(attributes: fixture.attributes, triples: triples)
  )
}

private func payloadBytes(
  in triples: [InstantTriple],
  fixture: TranscriptPayloadFixture
) -> Int {
  let payloadIDs = Set(fixture.deferredAttributeIDs)
  return triples.reduce(0) { partial, triple in
    guard payloadIDs.contains(triple.attributeID), case .string(let text) = triple.value else {
      return partial
    }
    return partial + text.utf8.count
  }
}

private func temporaryTranscriptCacheURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantDeferredTranscriptPayloadMemoryTests-\(name)-\(UUID().uuidString)")
    .appendingPathComponent("state.sqlite")
}
