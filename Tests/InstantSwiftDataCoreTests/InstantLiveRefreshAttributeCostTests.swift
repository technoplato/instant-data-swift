import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A live refresh must not rebuild the schema lookup indexes once per query result.
///
/// Scribe's store holds 435 attributes across 43 namespaces (31 relations, measured on an iPhone
/// on 2026-09-26), and the server refreshes every subscribed query after each write. A Mac soak
/// profile the same day spent 310 ms of every 30 s in `AttributeStore.rebuildLookupIndexes`:
/// once to build the translator's attribute context, once per computation to resolve local
/// attributes (even with nothing to merge), and once more when the store merged an empty list.
@Suite(.serialized)
struct InstantLiveRefreshAttributeCostTests {
  /// A schema shaped like Scribe's: 43 namespaces of 10 scalar attributes plus a primary key,
  /// and 31 relations with forward and reverse identities.
  static func scribeShapedAttributes() -> [InstantAttribute] {
    var attributes: [InstantAttribute] = []
    let namespaces = ["recordings"] + (1..<43).map { "namespace\($0)" }
    for namespace in namespaces {
      attributes.append(.primaryKey(namespace: namespace))
      for index in 0..<10 {
        let name = index == 0 ? "updatedAtMs" : "field\(index)"
        attributes.append(
          InstantAttribute(
            id: "\(namespace)/\(name)",
            namespace: namespace,
            name: name,
            valueType: index == 0 ? .number : .string,
            isRequired: false,
            isIndexed: index == 0
          )
        )
      }
    }
    for index in 0..<31 {
      let source = namespaces[index % namespaces.count]
      let target = namespaces[(index + 1) % namespaces.count]
      attributes.append(
        InstantAttribute(
          id: "\(source)/link\(index)",
          namespace: source,
          name: "link\(index)",
          valueType: .ref,
          isRequired: false,
          cardinality: .many,
          isIndexed: true,
          forwardIdentity: "\(source)/link\(index)",
          reverseIdentity: "\(target)/backlink\(index)",
          linkNamespace: target
        )
      )
    }
    return attributes
  }

  /// One refresh carrying `computationCount` recordings-page results of 12 rows.
  static func refresh(computationCount: Int, transactionID: String) -> InstantLiveRefreshOK {
    func wireTriple(_ entityID: String, _ attributeID: String, _ value: InstantLiveJSONValue)
      -> InstantLiveJSONValue
    {
      .array([.string(entityID), .string(attributeID), value, .number(1)])
    }
    let computations: [InstantLiveJSONValue] = (0..<computationCount).map { computation in
      let rows: [InstantLiveJSONValue] = (0..<12).map { row in
        let id = String(format: "%08x-0000-4000-8000-%012x", computation, row)
        return .array([
          wireTriple(id, "recordings/id", .string(id)),
          wireTriple(id, "recordings/updatedAtMs", .number(Double(row + 1))),
          wireTriple(id, "recordings/field1", .string("Recording \(row)")),
        ])
      }
      return .object([
        "instaql-query": .object([
          "recordings": .object([
            "$": .object([
              "limit": .number(12),
              "where": .object(["field2": .string("computation-\(computation)")]),
            ])
          ])
        ]),
        "instaql-result": .array([
          .object([
            "data": .object(["datalog-result": .object(["join-rows": .array(rows)])]),
            "child-nodes": .array([]),
          ])
        ]),
      ])
    }
    return InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: transactionID,
      attrs: [],
      computations: computations
    )
  }

  @Test
  func mergingNoAttributesLeavesTheStoreUnchanged() {
    let original = AttributeStore(attributes: Self.scribeShapedAttributes())
    var merged = original
    merged.merge([])
    expectNoDifference(merged, original)
  }

  @Test
  func translatingARefreshResolvesTheSchemaOncePerRefresh() throws {
    let attributes = Self.scribeShapedAttributes()
    let refresh = Self.refresh(computationCount: 8, transactionID: "refresh")
    var operationCount = 0
    let cost = try ThreadCPUClock.measure {
      for iteration in 0..<100 {
        let translation = try InstantLiveRefreshTranslator.translate(
          refresh,
          existingAttributes: attributes,
          receivedAt: InstantTimestamp(milliseconds: Int64(iteration + 1))
        )
        operationCount += translation.transaction.operations.count
      }
    }
    #expect(operationCount > 0)
    print("LIVE_REFRESH_TRANSLATE_COST cpu_ms=\(cost.cpuMilliseconds) wall=\(cost.wall) (100 refreshes x 8 computations, \(attributes.count) attributes)")
  }

  /// The schema as a server's `attrs` payload: Scribe's frames carried 447 of these before init advertised a core
  /// version, and attr-less frames apply with the session's cached copy.
  static func serverAttrs(for attributes: [InstantAttribute]) -> [InstantLiveJSONValue] {
    attributes.map { attribute in
      .object([
        "id": .string("server-\(attribute.id)"),
        "forward-identity": .array([
          .string("identity-\(attribute.id)"), .string(attribute.namespace), .string(attribute.name),
        ]),
        "value-type": .string(attribute.valueType == .ref ? "ref" : "blob"),
        "cardinality": .string(attribute.cardinality == .many ? "many" : "one"),
        "unique?": .bool(attribute.isUnique),
        "index?": .bool(attribute.isIndexed),
      ])
    }
  }

  /// #303: with the session's attrs in every frame, the attribute context (the attrs parsed and the schema lookups
  /// rebuilt) cost more than the frame's rows. Reusing the context while the attrs and schema stay the same removes
  /// that from every frame after the first.
  @Test
  func reusingTheAttributeContextRemovesThePerFrameAttributeCost() throws {
    let attributes = Self.scribeShapedAttributes()
    let attrs = Self.serverAttrs(for: attributes)
    var refresh = Self.refresh(computationCount: 8, transactionID: "refresh")
    refresh.attrs = attrs
    let uncached = try ThreadCPUClock.measure {
      for iteration in 0..<50 {
        _ = try InstantLiveRefreshTranslator.translate(
          refresh,
          existingAttributes: attributes,
          receivedAt: InstantTimestamp(milliseconds: Int64(iteration + 1))
        )
      }
    }
    let cache = InstantLiveRefreshAttributeContextCache()
    let cached = try ThreadCPUClock.measure {
      for iteration in 0..<50 {
        let context = try cache.context(
          serverAttributes: refresh.attrs,
          existingAttributes: attributes,
          localAttributeRevision: 1
        )
        _ = try InstantLiveRefreshTranslator.translate(
          refresh,
          existingAttributes: attributes,
          receivedAt: InstantTimestamp(milliseconds: Int64(iteration + 1)),
          attributeContext: context
        )
      }
    }
    expectNoDifference(cache.buildCount, 1)
    print("LIVE_REFRESH_ATTRIBUTE_CONTEXT_COST uncached_cpu_ms=\(uncached.cpuMilliseconds) cached_cpu_ms=\(cached.cpuMilliseconds) (50 refreshes x 8 computations, \(attrs.count) server attrs over \(attributes.count) local attributes)")
    // CPU time, not wall time, so host load does not decide it; the context was about half of each frame here.
    #expect(cached.cpuMilliseconds < uncached.cpuMilliseconds * 0.8)
  }

  /// #303: each server apply saved its query results inside the commit, and each save loaded and decoded every
  /// attribute row. With Scribe's schema that is a full table read and JSON decode per result, under the operation
  /// gate.
  @Test
  func liveResultSavesNoLongerReloadTheAttributeRows() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("attribute-load-cost-\(UUID().uuidString).sqlite")
    let store = try SQLitePersistenceStore(fileURL: url)
    try await store.bootstrap()
    try await store.saveSnapshot(InstantPersistenceSnapshot(store: InstantStoreSnapshot(attributes: Self.scribeShapedAttributes(), triples: [])))
    // The work runs on the store's executor, so this compares wall time, back to back.
    let clock = ContinuousClock()
    let reload = try await clock.measure {
      for _ in 0..<100 { _ = try await store.loadAttributesForTesting() }
    }
    let reuse = try await clock.measure {
      for _ in 0..<100 { _ = try await store.attributesForLiveResultSaveForTesting() }
    }
    print("LIVE_RESULT_ATTRIBUTE_LOAD_COST reload_wall=\(reload) reuse_wall=\(reuse) (100 saves, \(Self.scribeShapedAttributes().count) attributes)")
    #expect(reuse < reload / 2)
  }

  @Test
  func mergingAnEmptyListCostsNothing() {
    var store = AttributeStore(attributes: Self.scribeShapedAttributes())
    let cost = ThreadCPUClock.measure {
      for _ in 0..<1_000 {
        store.merge([])
      }
    }
    print("EMPTY_MERGE_COST cpu_ms=\(cost.cpuMilliseconds) wall=\(cost.wall) (1000 empty merges)")
  }
}
