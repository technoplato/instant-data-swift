import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// Nested include limits must bound authoritative and persisted live-query triples (#044 / #155).
///
/// SQLite Data: `LIMIT 2` on a child join keeps two rows per parent.
/// TypeScript instaql applies nested limits client-side after Reactor constructs
/// the raw query store. This Swift-specific containment acts earlier because
/// Swift shares one authoritative hot store across every live query.
///
/// Swift `runtime.query` already returns two children (L1), but the observe path
/// used to apply every decoded child to the hot store before persistence trimmed
/// `instant_live_query_triples`. A Mac recordings list query with
/// `segments.$limit: 2` therefore materialized hundreds of historical segments.
///
/// Bound query inserts once in the live-refresh translator and use that exact
/// set for both authoritative operations and query-result replacement. Retain
/// the persistence save/load defense. Live `transact` is unchanged. Non-JSON
/// query keys stay unfiltered so existing prune tests keep their synthetic keys.
@Suite(.serialized)
struct InstantLiveQueryNestedLimitMemoryTests {
  private let childCount = 10
  private let nestedLimit = 2

  @Test
  func nestedLimitKeepsTwoNewestChildrenPerParent() {
    let fixture = NestedLimitFixture(childCount: childCount)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: fixture.queryKey,
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(
      retained,
      [fixture.recordingID, fixture.segmentID(8), fixture.segmentID(9)]
    )
    print("nested_limit_retained_entity_count: \(retained.count)")
  }

  @Test
  func nestedLimitFollowsRecordingIDStringWhenRefTriplesAreAbsent() {
    let fixture = NestedLimitFixture(childCount: childCount, childLink: .recordingID)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: fixture.queryKey,
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(
      retained,
      [fixture.recordingID, fixture.segmentID(8), fixture.segmentID(9)]
    )
  }

  @Test
  func nestedLimitIsPerParentNotGlobal() {
    let fixture = NestedLimitFixture(childCount: 10, recordingCount: 2)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: fixture.queryKey,
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(
      retained,
      [
        "recording-0",
        "recording-1",
        "recording-0-segment-8",
        "recording-0-segment-9",
        "recording-1-segment-8",
        "recording-1-segment-9",
      ]
    )
  }

  @Test
  func nonJSONQueryKeyKeepsEveryEntity() {
    let fixture = NestedLimitFixture(childCount: childCount)
    let retained = InstantLiveQueryNestedLimit.retainedEntityIDs(
      queryKey: "query-active-page",
      triples: fixture.allTriples,
      attributes: fixture.attributes
    )
    expectNoDifference(retained.count, childCount + 1)
  }

  @Test
  func translatorBoundsAuthoritativeOperationsAndReplacementToNewestTwoChildren() throws {
    let fixture = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))

    let translation = try fixture.translation(transactionID: "nested-limit-translation")
    let transactionTriples = translation.transaction.operations.compactMap(\.insertedTriple)
    let replacement = try #require(translation.queryResultReplacements.first)
    let expectedEntityIDs: Set<String> = [
      fixture.recordingID,
      fixture.segmentID(8),
      fixture.segmentID(9),
    ]

    expectNoDifference(Set(transactionTriples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(Set(replacement.triples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(transactionTriples, replacement.triples)
    expectNoDifference(transactionTriples.count, 8)
  }

  @Test
  func translatorAppliesNestedLimitPerParent() throws {
    let fixture = NestedLimitLiveRefreshFixture(
      recordingCount: 2,
      childIndices: Array(0..<childCount)
    )

    let translation = try fixture.translation(transactionID: "nested-limit-two-parents")
    let transactionTriples = translation.transaction.operations.compactMap(\.insertedTriple)
    let replacement = try #require(translation.queryResultReplacements.first)
    let expectedEntityIDs: Set<String> = [
      "recording-0",
      "recording-1",
      "recording-0-segment-8",
      "recording-0-segment-9",
      "recording-1-segment-8",
      "recording-1-segment-9",
    ]

    expectNoDifference(Set(transactionTriples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(Set(replacement.triples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(transactionTriples, replacement.triples)
    expectNoDifference(transactionTriples.count, 16)
  }

  @Test
  func translatorBoundsServerAttributeTriplesUsingOpaqueLocalAttributeMetadata() throws {
    let fixture = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))

    let translation = try InstantLiveRefreshTranslator.translate(
      fixture.serverIDRefresh(
        transactionID: "nested-limit-server-attribute-ids",
        childLink: .recordingID
      ),
      existingAttributes: NestedLimitLiveRefreshFixture.opaqueLocalAttributes,
      receivedAt: InstantTimestamp(milliseconds: 1)
    )
    let transactionTriples = translation.transaction.operations.compactMap(\.insertedTriple)
    let replacement = try #require(translation.queryResultReplacements.first)
    let expectedEntityIDs: Set<String> = [
      fixture.recordingID,
      fixture.segmentID(8),
      fixture.segmentID(9),
    ]
    let expectedLocalAttributeIDs: Set<String> = [
      "local-recording-id",
      "local-recording-updated-at",
      "local-segment-id",
      "local-segment-recording-id",
      "local-segment-index",
    ]

    expectNoDifference(Set(transactionTriples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(Set(replacement.triples.map(\.entityID)), expectedEntityIDs)
    expectNoDifference(transactionTriples, replacement.triples)
    expectNoDifference(Set(transactionTriples.map(\.attributeID)), expectedLocalAttributeIDs)
  }

  @Test
  func translatorLeavesUnboundedAndNonQueryComputationsUnchanged() throws {
    let fixture = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))

    let unbounded = try fixture.translation(
      transactionID: "nested-limit-unbounded",
      query: fixture.query(nestedLimit: nil)
    )
    let unboundedTriples = unbounded.transaction.operations.compactMap(\.insertedTriple)
    expectNoDifference(Set(unboundedTriples.map(\.entityID)).count, childCount + 1)
    let unboundedReplacement = try #require(unbounded.queryResultReplacements.first)
    expectNoDifference(unboundedReplacement.triples, unboundedTriples)

    let nonQuery = try fixture.translation(
      transactionID: "nested-limit-non-query",
      includesQuery: false
    )
    let nonQueryTriples = nonQuery.transaction.operations.compactMap(\.insertedTriple)
    expectNoDifference(Set(nonQueryTriples.map(\.entityID)).count, childCount + 1)
    expectNoDifference(nonQuery.queryResultReplacements.count, 0)
  }

  @Test
  func sequentialRefreshRetractsDepartingChildAndPlateausAtRootPlusTwo() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("sequential-window")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-limit-sequential-window",
        persistenceURL: cacheURL,
        initialAttributes: NestedLimitLiveRefreshFixture.attributes
      )
    )
    var maximumTripleCount = 0

    for offset in 0..<12 {
      let fixture = NestedLimitLiveRefreshFixture(
        childIndices: Array(offset..<(offset + childCount))
      )
      _ = try await runtime.applyLiveRefresh(
        fixture.refresh(transactionID: "nested-limit-window-\(offset)")
      )
      let snapshot = await runtime.store.snapshot()
      maximumTripleCount = max(maximumTripleCount, snapshot.triples.count)
      expectNoDifference(
        Set(snapshot.triples.map(\.entityID)),
        [fixture.recordingID, fixture.segmentID(offset + 8), fixture.segmentID(offset + 9)]
      )
    }

    expectNoDifference(maximumTripleCount, 8)
  }

  @Test
  func departingChildStaysWhileAnotherLiveQueryOwnsIt() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("overlapping-owner")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-limit-overlapping-owner",
        persistenceURL: cacheURL,
        initialAttributes: NestedLimitLiveRefreshFixture.attributes
      )
    )
    let first = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))
    let segmentOwnerQuery = first.segmentQuery()
    _ = try await runtime.applyLiveRefresh(
      first.refresh(
        transactionID: "nested-limit-overlap-first",
        additionalComputations: [
          first.segmentsOnlyComputation(query: segmentOwnerQuery, indices: [8])
        ]
      )
    )

    let shifted = NestedLimitLiveRefreshFixture(childIndices: Array(1...childCount))
    _ = try await runtime.applyLiveRefresh(
      shifted.refresh(transactionID: "nested-limit-overlap-shift")
    )
    let snapshot = await runtime.store.snapshot()

    expectNoDifference(
      Set(snapshot.triples.map(\.entityID)),
      [
        shifted.recordingID,
        shifted.segmentID(8),
        shifted.segmentID(9),
        shifted.segmentID(10),
      ]
    )
  }

  @Test
  func departingChildStaysWhilePendingOptimisticMutationOwnsIt() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("pending-owner")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "nested-limit-pending-owner",
        persistenceURL: cacheURL,
        initialAttributes: NestedLimitLiveRefreshFixture.attributes
      )
    )
    let first = NestedLimitLiveRefreshFixture(childIndices: Array(0..<childCount))
    _ = try await runtime.applyLiveRefresh(
      first.refresh(transactionID: "nested-limit-pending-first")
    )
    let pendingAt = InstantTimestamp(milliseconds: 2)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "nested-limit-pending-child",
        operations: [
          .insert(
            InstantTriple(
              entityID: first.segmentID(8),
              attributeID: NestedLimitLiveRefreshFixture.segmentIndexAttribute.id,
              value: .number(8),
              txID: "nested-limit-pending-child",
              txTime: pendingAt
            )
          )
        ]
      ),
      createdAt: pendingAt
    )

    let shifted = NestedLimitLiveRefreshFixture(childIndices: Array(1...childCount))
    _ = try await runtime.applyLiveRefresh(
      shifted.refresh(transactionID: "nested-limit-pending-shift")
    )
    let snapshot = await runtime.store.snapshot()
    let protectedChildTriples = snapshot.triples.filter { $0.entityID == first.segmentID(8) }

    expectNoDifference(
      Set(protectedChildTriples.map(\.attributeID)),
      [
        NestedLimitLiveRefreshFixture.segmentIDAttribute.id,
        NestedLimitLiveRefreshFixture.segmentRecordingAttribute.id,
        NestedLimitLiveRefreshFixture.segmentIndexAttribute.id,
      ]
    )
    let pendingMutationIDs = await runtime.pendingMutations().map(\.id)
    expectNoDifference(pendingMutationIDs, ["nested-limit-pending-child"])
  }

  @Test
  func bootstrapLoadsOnlyTheLimitedLiveQueryPage() async throws {
    let cacheURL = temporaryNestedLimitCacheURL("scoped-nested")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }
    let fixture = NestedLimitFixture(childCount: childCount)

    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(attributes: fixture.attributes, triples: fixture.allTriples)
    )
    let state = try await persistence.loadCompactState()
    let now = InstantTimestamp(milliseconds: 1)
    let didSave = try await persistence.saveLiveRefresh(
      state.snapshot,
      queryResults: [
        InstantPersistedLiveQueryResult(
          replacement: InstantLiveQueryResultReplacement(
            key: fixture.queryKey,
            triples: fixture.allTriples,
            pageInfo: nil
          ),
          updatedAt: now
        )
      ],
      storeChanged: false,
      outboxChanged: false,
      metadataKey: "nested-limit.watermark",
      metadataValue: "bloated-observe",
      metadataUpdatedAt: now,
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)

    let reloaded = try SQLitePersistenceStore(fileURL: cacheURL)
    try await reloaded.bootstrap()
    let loaded = try await reloaded.loadCompactState()
    let hotEntityIDs = Set(loaded.snapshot.store.triples.map(\.entityID))
    expectNoDifference(hotEntityIDs.count, 1 + nestedLimit)
    expectNoDifference(
      hotEntityIDs,
      [fixture.recordingID, fixture.segmentID(8), fixture.segmentID(9)]
    )
    let storedCount = try await reloaded.storedTripleEntityCountForTesting()
    expectNoDifference(storedCount, childCount + 1)
    print("nested_limit_hot_store_entity_count: \(hotEntityIDs.count)")
    print("sqlite_entity_count: \(storedCount)")
  }
}

private struct NestedLimitLiveRefreshFixture {
  private struct WireAttributeIDs {
    var recordingID: String
    var recordingUpdatedAt: String
    var segmentID: String
    var segmentRecording: String
    var segmentRecordingID: String
    var segmentIndex: String

    static let local = Self(
      recordingID: NestedLimitLiveRefreshFixture.recordingIDAttribute.id,
      recordingUpdatedAt: NestedLimitLiveRefreshFixture.recordingUpdatedAtAttribute.id,
      segmentID: NestedLimitLiveRefreshFixture.segmentIDAttribute.id,
      segmentRecording: NestedLimitLiveRefreshFixture.segmentRecordingAttribute.id,
      segmentRecordingID: NestedLimitLiveRefreshFixture.segmentRecordingIDAttribute.id,
      segmentIndex: NestedLimitLiveRefreshFixture.segmentIndexAttribute.id
    )
    static let server = Self(
      recordingID: "server-recordings-id",
      recordingUpdatedAt: "server-recordings-updated-at",
      segmentID: "server-segments-id",
      segmentRecording: "server-segments-recording",
      segmentRecordingID: "server-segments-recording-id",
      segmentIndex: "server-segments-index"
    )
  }

  enum ChildLink {
    case recording
    case recordingID
  }

  let recordingCount: Int
  let childIndices: [Int]
  let recordingID = "recording-a"

  init(recordingCount: Int = 1, childIndices: [Int]) {
    self.recordingCount = recordingCount
    self.childIndices = childIndices
  }

  static let recordingIDAttribute = InstantAttribute.primaryKey(namespace: "recordings")
  static let recordingUpdatedAtAttribute = InstantAttribute(
    id: "recordings/updatedAtMs",
    namespace: "recordings",
    name: "updatedAtMs",
    valueType: .number,
    isIndexed: true
  )
  static let segmentIDAttribute = InstantAttribute.primaryKey(
    namespace: "transcriptionSegments"
  )
  static let segmentRecordingAttribute = InstantAttribute(
    id: "transcriptionSegments/recording",
    namespace: "transcriptionSegments",
    name: "recording",
    valueType: .ref,
    cardinality: .one,
    isIndexed: true,
    forwardIdentity: "transcriptionSegments/recording",
    reverseIdentity: "recordings/segments",
    linkNamespace: "recordings"
  )
  static let segmentIndexAttribute = InstantAttribute(
    id: "transcriptionSegments/segmentIndex",
    namespace: "transcriptionSegments",
    name: "segmentIndex",
    valueType: .number,
    isIndexed: true
  )
  static let segmentRecordingIDAttribute = InstantAttribute(
    id: "transcriptionSegments/recordingID",
    namespace: "transcriptionSegments",
    name: "recordingID",
    valueType: .string,
    isIndexed: true
  )

  static var attributes: [InstantAttribute] {
    [
      recordingIDAttribute,
      recordingUpdatedAtAttribute,
      segmentIDAttribute,
      segmentRecordingAttribute,
      segmentRecordingIDAttribute,
      segmentIndexAttribute,
    ]
  }

  static var opaqueLocalAttributes: [InstantAttribute] {
    [
      InstantAttribute(
        id: "local-recording-id",
        namespace: "recordings",
        name: "id",
        valueType: .string,
        primaryKey: true
      ),
      InstantAttribute(
        id: "local-recording-updated-at",
        namespace: "recordings",
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "local-segment-id",
        namespace: "transcriptionSegments",
        name: "id",
        valueType: .string,
        primaryKey: true
      ),
      InstantAttribute(
        id: "local-segment-recording",
        namespace: "transcriptionSegments",
        name: "recording",
        valueType: .ref,
        isIndexed: true,
        forwardIdentity: "transcriptionSegments/recording",
        reverseIdentity: "recordings/segments",
        linkNamespace: "recordings"
      ),
      InstantAttribute(
        id: "local-segment-recording-id",
        namespace: "transcriptionSegments",
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "local-segment-index",
        namespace: "transcriptionSegments",
        name: "segmentIndex",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }

  var recordingIDs: [String] {
    recordingCount == 1
      ? [recordingID]
      : (0..<recordingCount).map { "recording-\($0)" }
  }

  func segmentID(_ index: Int, recordingID: String? = nil) -> String {
    let recordingID = recordingID ?? self.recordingID
    return recordingCount == 1 ? "segment-\(index)" : "\(recordingID)-segment-\(index)"
  }

  func query(nestedLimit: Int? = 2) -> InstantLiveJSONValue {
    var segmentOptions: [String: InstantLiveJSONValue] = [
      "order": .object(["segmentIndex": .string("desc")])
    ]
    if let nestedLimit {
      segmentOptions["limit"] = .number(Double(nestedLimit))
    }
    return .object([
      "recordings": .object([
        "$": .object([
          "limit": .number(50),
          "order": .object(["updatedAtMs": .string("desc")]),
        ]),
        "segments": .object(["$": .object(segmentOptions)]),
      ])
    ])
  }

  func segmentQuery() -> InstantLiveJSONValue {
    .object(["transcriptionSegments": .object([:])])
  }

  func translation(
    transactionID: String,
    query: InstantLiveJSONValue? = nil,
    includesQuery: Bool = true
  ) throws -> InstantLiveRefreshTranslation {
    try InstantLiveRefreshTranslator.translate(
      refresh(
        transactionID: transactionID,
        query: query,
        includesQuery: includesQuery
      ),
      existingAttributes: Self.attributes,
      receivedAt: InstantTimestamp(milliseconds: 1)
    )
  }

  func refresh(
    transactionID: String,
    query: InstantLiveJSONValue? = nil,
    includesQuery: Bool = true,
    additionalComputations: [InstantLiveJSONValue] = []
  ) -> InstantLiveRefreshOK {
    InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: transactionID,
      attrs: [],
      computations: [computation(query: query, includesQuery: includesQuery)]
        + additionalComputations
    )
  }

  func serverIDRefresh(
    transactionID: String,
    childLink: ChildLink = .recording
  ) -> InstantLiveRefreshOK {
    InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: transactionID,
      attrs: Self.serverAttributes,
      computations: [
        computation(attributeIDs: .server, childLink: childLink)
      ]
    )
  }

  private func computation(
    query: InstantLiveJSONValue? = nil,
    includesQuery: Bool = true,
    attributeIDs: WireAttributeIDs = .local,
    childLink: ChildLink = .recording
  ) -> InstantLiveJSONValue {
    var object: [String: InstantLiveJSONValue] = [
      "instaql-result": .array([
        .object([
          "data": .object([
            "datalog-result": .object([
              "join-rows": .array(recordingRows(attributeIDs: attributeIDs))
            ])
          ]),
          "child-nodes": .array([
            .object([
              "data": .object([
                "datalog-result": .object([
                  "join-rows": .array(
                    segmentRows(
                      indices: childIndices,
                      attributeIDs: attributeIDs,
                      childLink: childLink
                    )
                  )
                ])
              ]),
              "child-nodes": .array([]),
            ])
          ]),
        ])
      ])
    ]
    if includesQuery {
      object["instaql-query"] = query ?? self.query()
    }
    return .object(object)
  }

  func segmentsOnlyComputation(
    query: InstantLiveJSONValue,
    indices: [Int]
  ) -> InstantLiveJSONValue {
    .object([
      "instaql-query": query,
      "instaql-result": .array([
        .object([
          "data": .object([
            "datalog-result": .object([
              "join-rows": .array(segmentRows(indices: indices))
            ])
          ]),
          "child-nodes": .array([]),
        ])
      ]),
    ])
  }

  private func recordingRows(
    attributeIDs: WireAttributeIDs = .local
  ) -> [InstantLiveJSONValue] {
    recordingIDs.enumerated().map { index, id in
      .array([
        wireTriple(id, attributeIDs.recordingID, .string(id)),
        wireTriple(
          id,
          attributeIDs.recordingUpdatedAt,
          .number(Double(index + 1))
        ),
      ])
    }
  }

  private func segmentRows(
    indices: [Int],
    attributeIDs: WireAttributeIDs = .local,
    childLink: ChildLink = .recording
  ) -> [InstantLiveJSONValue] {
    recordingIDs.flatMap { recordingID in
      indices.map { index in
        let id = segmentID(index, recordingID: recordingID)
        return .array([
          wireTriple(id, attributeIDs.segmentID, .string(id)),
          wireTriple(
            id,
            childLink == .recording
              ? attributeIDs.segmentRecording
              : attributeIDs.segmentRecordingID,
            .string(recordingID)
          ),
          wireTriple(id, attributeIDs.segmentIndex, .number(Double(index))),
        ])
      }
    }
  }

  private func wireTriple(
    _ entityID: String,
    _ attributeID: String,
    _ value: InstantLiveJSONValue
  ) -> InstantLiveJSONValue {
    .array([
      .string(entityID),
      .string(attributeID),
      value,
      .number(1),
    ])
  }

  private static var serverAttributes: [InstantLiveJSONValue] {
    [
      serverAttribute(
        id: WireAttributeIDs.server.recordingID,
        namespace: "recordings",
        name: "id"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.recordingUpdatedAt,
        namespace: "recordings",
        name: "updatedAtMs",
        checkedDataType: "number"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentID,
        namespace: "transcriptionSegments",
        name: "id"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentRecording,
        namespace: "transcriptionSegments",
        name: "recording",
        reverseNamespace: "recordings",
        reverseName: "segments"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentRecordingID,
        namespace: "transcriptionSegments",
        name: "recordingID"
      ),
      serverAttribute(
        id: WireAttributeIDs.server.segmentIndex,
        namespace: "transcriptionSegments",
        name: "segmentIndex",
        checkedDataType: "number"
      ),
    ]
  }

  private static func serverAttribute(
    id: String,
    namespace: String,
    name: String,
    checkedDataType: String = "string",
    reverseNamespace: String? = nil,
    reverseName: String? = nil
  ) -> InstantLiveJSONValue {
    var object: [String: InstantLiveJSONValue] = [
      "id": .string(id),
      "forward-identity": .array([
        .string("forward-\(id)"),
        .string(namespace),
        .string(name),
      ]),
      "value-type": .string(reverseNamespace == nil ? "blob" : "ref"),
      "checked-data-type": .string(checkedDataType),
      "cardinality": .string("one"),
    ]
    if let reverseNamespace, let reverseName {
      object["reverse-identity"] = .array([
        .string("reverse-\(id)"),
        .string(reverseNamespace),
        .string(reverseName),
      ])
    }
    return .object(object)
  }
}

private extension InstantTripleOperation {
  var insertedTriple: InstantTriple? {
    guard case let .insert(triple) = self else { return nil }
    return triple
  }
}

private struct NestedLimitFixture {
  let childCount: Int
  let recordingCount: Int
  let childLink: ChildLink
  let recordingID = "recording-a"

  enum ChildLink {
    case recordingRef
    case recordingID
  }

  init(
    childCount: Int,
    recordingCount: Int = 1,
    childLink: ChildLink = .recordingRef
  ) {
    self.childCount = childCount
    self.recordingCount = recordingCount
    self.childLink = childLink
  }
  let queryKey =
    """
    {"recordings":{"$":{"fields":["title"],"limit":50,"order":{"updatedAtMs":"desc"}},"segments":{"$":{"limit":2,"order":{"segmentIndex":"desc"}}}}}
    """

  let recordingIDAttribute = InstantAttribute.primaryKey(namespace: "recordings")
  let recordingUpdatedAtAttribute = InstantAttribute(
    id: "recordings/updatedAtMs",
    namespace: "recordings",
    name: "updatedAtMs",
    valueType: .number,
    isIndexed: true
  )
  let segmentIDAttribute = InstantAttribute.primaryKey(namespace: "transcriptionSegments")
  let segmentRecordingAttribute = InstantAttribute(
    id: "transcriptionSegments/recording",
    namespace: "transcriptionSegments",
    name: "recording",
    valueType: .ref,
    cardinality: .one,
    isIndexed: true,
    forwardIdentity: "transcriptionSegments/recording",
    reverseIdentity: "recordings/segments",
    linkNamespace: "recordings"
  )
  let segmentRecordingIDAttribute = InstantAttribute(
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

  var attributes: [InstantAttribute] {
    [
      recordingIDAttribute,
      recordingUpdatedAtAttribute,
      segmentIDAttribute,
      segmentRecordingAttribute,
      segmentRecordingIDAttribute,
      segmentIndexAttribute,
    ]
  }

  func segmentID(_ index: Int) -> String {
    recordingCount == 1 ? "segment-\(index)" : "recording-0-segment-\(index)"
  }

  var allTriples: [InstantTriple] {
    let time = InstantTimestamp(milliseconds: 1)
    var triples: [InstantTriple] = []
    let recordingIDs: [String]
    if recordingCount == 1 {
      recordingIDs = [recordingID]
    } else {
      recordingIDs = (0..<recordingCount).map { "recording-\($0)" }
    }
    for (recordingIndex, id) in recordingIDs.enumerated() {
      triples.append(
        contentsOf: [
          InstantTriple(
            entityID: id,
            attributeID: recordingIDAttribute.id,
            value: .string(id),
            txID: "seed-\(id)",
            txTime: time
          ),
          InstantTriple(
            entityID: id,
            attributeID: recordingUpdatedAtAttribute.id,
            value: .number(Double(recordingIndex + 1)),
            txID: "seed-\(id)",
            txTime: time
          ),
        ]
      )
      for index in 0..<childCount {
        let entityID =
          recordingCount == 1
          ? "segment-\(index)"
          : "\(id)-segment-\(index)"
        let txID = "seed-\(entityID)"
        triples.append(
          contentsOf: [
            InstantTriple(
              entityID: entityID,
              attributeID: segmentIDAttribute.id,
              value: .string(entityID),
              txID: txID,
              txTime: time
            ),
            InstantTriple(
              entityID: entityID,
              attributeID: childLink == .recordingRef
                ? segmentRecordingAttribute.id
                : segmentRecordingIDAttribute.id,
              value: childLink == .recordingRef ? .ref(id) : .string(id),
              txID: txID,
              txTime: time
            ),
            InstantTriple(
              entityID: entityID,
              attributeID: segmentIndexAttribute.id,
              value: .number(Double(index)),
              txID: txID,
              txTime: time
            ),
          ]
        )
      }
    }
    return triples
  }
}

private func temporaryNestedLimitCacheURL(_ name: String) -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "InstantLiveQueryNestedLimitMemoryTests-\(name)-\(UUID().uuidString)"
    )
    .appendingPathComponent("state.sqlite")
}
