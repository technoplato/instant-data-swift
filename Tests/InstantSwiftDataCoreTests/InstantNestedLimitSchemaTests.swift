import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// History:
// - 2026-11-04: #1109: the nested-limit pass found the attributes it needed by walking the whole schema on every call,
//   hashing every attribute's id and copying every attribute (2,283 on the phone). It runs twice a refresh, in the
//   translator and in the result's save: in a 90 s trace of the phone transcribing speech (build 251), the pass was
//   374 ms and the walk (`AttributeLookup.init`) 258 ms of it, 1.1% of all the app's CPU.

/// The nested-limit pass reads a schema indexed once, not walked once a call (#1109).
@Suite
struct InstantNestedLimitSchemaTests {
  /// Wherever a schema indexed once is given, the pass keeps exactly what it keeps when it searches the schema's
  /// attributes: the first attribute of an id, of a reverse identity and of a namespace and name, as the searches find it,
  /// over pages with nested includes by ref link and by string link, limits, orders and attributes the schema does not
  /// declare.
  @Test(arguments: [UInt64(11_090), 11_091, 11_092, 11_093])
  func aSchemaIndexedOnceKeepsWhatTheSearchedSchemaKeeps(seed: UInt64) {
    var random = InfiniteWindowRandom(seed: seed)
    for round in 0..<120 {
      let attributes = Self.randomSchema(&random)
      let schema = InstantLiveQueryNestedLimit.Schema(attributes)
      let triples = Self.randomListPage(&random)
      for queryKey in Self.randomQueryKeys(&random) {
        let label = "round \(round) key \(queryKey)"
        expectNoDifference(
          InstantLiveQueryNestedLimit.limitedTriples(queryKey: queryKey, triples: triples, schema: schema),
          InstantLiveQueryNestedLimit.limitedTriples(queryKey: queryKey, triples: triples, attributes: attributes),
          "\(label)"
        )
        expectNoDifference(
          InstantLiveQueryNestedLimit.retainedEntityIDs(queryKey: queryKey, triples: triples, schema: schema),
          InstantLiveQueryNestedLimit.retainedEntityIDs(queryKey: queryKey, triples: triples, attributes: attributes),
          "\(label)"
        )
      }
    }
  }

  /// A one-row result and a small list with two lines per recording, the shapes most refreshes restate: with the schema
  /// indexed once, the pass costs about the same with the phone's 2,283 attributes as with sixteen.
  @Test
  func theNestedLimitPassCostsTheSameWithTheWholeSchemaIndexed() {
    let small = InstantLiveQueryNestedLimit.Schema(Self.listAttributes(count: 16))
    let large = InstantLiveQueryNestedLimit.Schema(Self.listAttributes(count: 2_283))
    let row = Self.listPage(recordings: 1, linesPerRecording: 0)
    let list = Self.listPage(recordings: 4, linesPerRecording: 3)
    for (name, page, key) in [("one row", row, Self.rowKey), ("list", list, Self.listKey)] {
      expectNoDifference(
        InstantLiveQueryNestedLimit.limitedTriples(queryKey: key, triples: page, schema: large),
        InstantLiveQueryNestedLimit.limitedTriples(queryKey: key, triples: page, schema: small),
        "\(name)"
      )
      guard RealSizeBudget.isOptimized else { continue }
      let cost = Self.cpuNanosecondsPerCall(
        small: { _ = InstantLiveQueryNestedLimit.limitedTriples(queryKey: key, triples: page, schema: small) },
        large: { _ = InstantLiveQueryNestedLimit.limitedTriples(queryKey: key, triples: page, schema: large) }
      )
      #expect(
        cost.large < cost.small * 1.5,
        "\(name): the pass took \(Int(cost.large)) ns a call with 2,283 attributes against \(Int(cost.small)) with 16."
      )
    }
  }

  /// The translator bounds each restated result with the schema its attribute context indexed once, so translating a
  /// refresh of a one-row query costs about the same with 2,283 attributes as with sixteen.
  @Test
  func translatingARefreshCostsTheSameWithTheWholeSchema() throws {
    let refresh = Self.refresh(Self.listPage(recordings: 1, linesPerRecording: 0), query: Self.rowQuery)
    func translate(_ context: InstantLiveRefreshAttributeContext, _ attributes: [InstantAttribute]) throws
      -> InstantLiveRefreshTranslation
    {
      try InstantLiveRefreshTranslator.translate(
        refresh,
        existingAttributes: attributes,
        receivedAt: InstantTimestamp(milliseconds: 1),
        attributeContext: context
      )
    }
    let smallAttributes = Self.listAttributes(count: 16)
    let largeAttributes = Self.listAttributes(count: 2_283)
    let small = try InstantLiveRefreshTranslator.attributeContext(serverAttributes: [], existingAttributes: smallAttributes)
    let large = try InstantLiveRefreshTranslator.attributeContext(serverAttributes: [], existingAttributes: largeAttributes)
    let fromSmall = try translate(small, smallAttributes)
    let fromLarge = try translate(large, largeAttributes)
    expectNoDifference(fromLarge.transaction, fromSmall.transaction)
    expectNoDifference(fromLarge.queryResultReplacements.map(\.triples), fromSmall.queryResultReplacements.map(\.triples))
    #expect(fromSmall.queryResultReplacements.first?.triples.count == 6)
    guard RealSizeBudget.isOptimized else { return }
    let cost = Self.cpuNanosecondsPerCall(
      small: { _ = try? translate(small, smallAttributes) },
      large: { _ = try? translate(large, largeAttributes) }
    )
    #expect(
      cost.large < cost.small * 1.5,
      "Translating took \(Int(cost.large)) ns with 2,283 attributes against \(Int(cost.small)) with 16."
    )
  }
}

extension InstantNestedLimitSchemaTests {
  static let rowQuery: InstantLiveJSONValue = .object([
    "recordings": .object(["$": .object(["where": .object(["id": .string("recording-0")])])])
  ])
  static let rowKey = #"{"recordings":{"$":{"where":{"id":"recording-0"}}}}"#
  /// Scribe's list shape: recordings with their two newest lines.
  static let listKey =
    #"{"recordings":{"$":{"limit":12,"order":{"startedAtMs":"desc"}},"segments":{"$":{"limit":2,"order":{"segmentIndex":"desc"}}}}}"#

  /// Recordings and their lines, then other namespaces' attributes up to `count`.
  static func listAttributes(count: Int) -> [InstantAttribute] {
    var attributes: [InstantAttribute] = [
      .primaryKey(namespace: "recordings"),
      InstantAttribute(id: "recordings/title", namespace: "recordings", name: "title", valueType: .string),
      InstantAttribute(
        id: "recordings/startedAtMs", namespace: "recordings", name: "startedAtMs", valueType: .number, isIndexed: true
      ),
      InstantAttribute(id: "recordings/ownerUserID", namespace: "recordings", name: "ownerUserID", valueType: .string),
      InstantAttribute(id: "recordings/durationMs", namespace: "recordings", name: "durationMs", valueType: .number),
      InstantAttribute(id: "recordings/deletedAtMs", namespace: "recordings", name: "deletedAtMs", valueType: .number),
      .primaryKey(namespace: "transcriptionSegments"),
      InstantAttribute(
        id: "transcriptionSegments/recording", namespace: "transcriptionSegments", name: "recording", valueType: .ref,
        cardinality: .one, isIndexed: true, forwardIdentity: "transcriptionSegments/recording",
        reverseIdentity: "recordings/segments", linkNamespace: "recordings"
      ),
      InstantAttribute(
        id: "transcriptionSegments/recordingID", namespace: "transcriptionSegments", name: "recordingID",
        valueType: .string, isIndexed: true
      ),
      InstantAttribute(
        id: "transcriptionSegments/segmentIndex", namespace: "transcriptionSegments", name: "segmentIndex",
        valueType: .number, isIndexed: true
      ),
      InstantAttribute(id: "transcriptionSegments/text", namespace: "transcriptionSegments", name: "text", valueType: .string),
    ]
    attributes += (attributes.count..<max(count, attributes.count)).map {
      InstantAttribute(id: "other/field-\($0)", namespace: "other", name: "field-\($0)", valueType: .string)
    }
    return attributes
  }

  /// `recordings` recordings with six facts each and `linesPerRecording` lines each linked to its recording.
  static func listPage(recordings: Int, linesPerRecording: Int) -> [InstantTriple] {
    var triples: [InstantTriple] = []
    for recording in 0..<recordings {
      let id = "recording-\(recording)"
      triples.append(triple(id, "recordings/id", .string(id)))
      triples.append(triple(id, "recordings/title", .string("Recording \(recording)")))
      triples.append(triple(id, "recordings/startedAtMs", .number(Double(1_000 + recording))))
      triples.append(triple(id, "recordings/ownerUserID", .string("owner")))
      triples.append(triple(id, "recordings/durationMs", .number(Double(60_000 * recording))))
      triples.append(triple(id, "recordings/deletedAtMs", .number(0)))
      for line in 0..<linesPerRecording {
        let lineID = "\(id)-line-\(line)"
        triples.append(triple(lineID, "transcriptionSegments/id", .string(lineID)))
        triples.append(triple(lineID, "transcriptionSegments/recording", .ref(id)))
        triples.append(triple(lineID, "transcriptionSegments/segmentIndex", .number(Double(line))))
        triples.append(triple(lineID, "transcriptionSegments/text", .string("line \(line) of \(id)")))
      }
    }
    return triples
  }

  /// A schema of the list's attributes in a random order, with repeated ids, repeated namespaces and names of other
  /// types, a second reverse identity, and other namespaces' attributes.
  static func randomSchema(_ random: inout InfiniteWindowRandom) -> [InstantAttribute] {
    var attributes = listAttributes(count: 11 + random.int(0...6))
    if random.chance(30) {
      attributes.append(
        InstantAttribute(id: "recordings/title", namespace: "recordings", name: "title", valueType: .number)
      )
    }
    if random.chance(30) {
      attributes.append(
        InstantAttribute(
          id: "transcriptionSegments/recording-string", namespace: "transcriptionSegments", name: "recording",
          valueType: .string
        )
      )
    }
    if random.chance(30) {
      attributes.append(
        InstantAttribute(
          id: "transcriptionSegments/owner", namespace: "transcriptionSegments", name: "owner", valueType: .ref,
          cardinality: .one, reverseIdentity: "recordings/segments", linkNamespace: "recordings"
        )
      )
    }
    if random.chance(30) {
      attributes.append(
        InstantAttribute(
          id: "recordings/segments", namespace: "recordings", name: "segments", valueType: .ref,
          cardinality: .many, linkNamespace: "transcriptionSegments"
        )
      )
    }
    for index in attributes.indices.reversed() where index > 0 {
      attributes.swapAt(index, random.int(0...index))
    }
    return attributes
  }

  /// Recordings, their lines linked by ref or by the recording's id as a string, and facts of undeclared attributes.
  static func randomListPage(_ random: inout InfiniteWindowRandom) -> [InstantTriple] {
    var triples: [InstantTriple] = []
    for recording in 0..<random.int(0...4) {
      let id = "recording-\(recording)"
      triples.append(triple(id, "recordings/id", .string(id)))
      if random.chance(80) { triples.append(triple(id, "recordings/startedAtMs", .number(Double(random.int(0...9))))) }
      if random.chance(50) { triples.append(triple(id, "recordings/title", .string("title \(random.int(0...3))"))) }
      if random.chance(20) { triples.append(triple(id, "recordings/segments", .ref("\(id)-line-\(random.int(0...5))"))) }
      for line in 0..<random.int(0...5) {
        let lineID = "\(id)-line-\(line)"
        triples.append(triple(lineID, "transcriptionSegments/id", .string(lineID)))
        if random.chance(70) {
          triples.append(triple(lineID, "transcriptionSegments/recording", .ref(id)))
        } else {
          triples.append(triple(lineID, "transcriptionSegments/recordingID", .string(id)))
        }
        if random.chance(80) {
          triples.append(triple(lineID, "transcriptionSegments/segmentIndex", .number(Double(random.int(0...9)))))
        }
        if random.chance(15) { triples.append(triple(lineID, "undeclared/field", .string("?"))) }
      }
    }
    return triples
  }

  static func randomQueryKeys(_ random: inout InfiniteWindowRandom) -> [String] {
    let topLimit = random.chance(40) ? "" : #","limit":\#(random.int(0...4))"#
    let lineLimit = random.chance(30) ? "" : #","limit":\#(random.int(0...3))"#
    let lineOrder = random.chance(50) ? #""order":{"segmentIndex":"desc"}"# : #""order":{"segmentIndex":"asc"}"#
    return [
      #"{"recordings":{"$":{"order":{"startedAtMs":"desc"}\#(topLimit)},"segments":{"$":{\#(lineOrder)\#(lineLimit)}}}}"#,
      #"{"recordings":{"$":{"order":{"title":"asc"}\#(topLimit)}}}"#,
      #"{"transcriptionSegments":{"$":{\#(lineOrder)\#(lineLimit)},"recording":{"$":{}}}}"#,
      "not-json",
    ]
  }

  /// A refresh-ok that restates `triples` as the one result of `query`.
  static func refresh(_ triples: [InstantTriple], query: InstantLiveJSONValue) -> InstantLiveRefreshOK {
    func value(_ value: InstantValue) -> InstantLiveJSONValue {
      switch value {
      case let .string(text): .string(text)
      case let .number(number): .number(number)
      case let .ref(id): .string(id)
      default: .null
      }
    }
    let rows: [InstantLiveJSONValue] = triples.map { triple in
      .array([.array([.string(triple.entityID), .string(triple.attributeID), value(triple.value), .number(1)])])
    }
    return InstantLiveRefreshOK(
      clientEventID: nil,
      processedTransactionID: "schema-tx",
      attrs: [],
      computations: [
        .object([
          "instaql-query": query,
          "instaql-result": .array([
            .object([
              "data": .object(["datalog-result": .object(["join-rows": .array(rows)])]),
              "child-nodes": .array([]),
            ])
          ]),
        ])
      ]
    )
  }

  static func triple(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> InstantTriple {
    InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: "tx", txTime: InstantTimestamp(milliseconds: 1))
  }

  /// Thread CPU per call of `small` and of `large`, each the least of five rounds of 300 calls taken in turns, so a
  /// round a busy machine slowed counts for neither.
  static func cpuNanosecondsPerCall(small: () -> Void, large: () -> Void) -> (small: Double, large: Double) {
    small()
    large()
    var best = (small: Double.infinity, large: Double.infinity)
    for _ in 0..<5 {
      var start = ThreadCPUClock.nanoseconds()
      for _ in 0..<300 { small() }
      best.small = min(best.small, Double(ThreadCPUClock.nanoseconds() - start) / 300)
      start = ThreadCPUClock.nanoseconds()
      for _ in 0..<300 { large() }
      best.large = min(best.large, Double(ThreadCPUClock.nanoseconds() - start) / 300)
    }
    return best
  }
}
