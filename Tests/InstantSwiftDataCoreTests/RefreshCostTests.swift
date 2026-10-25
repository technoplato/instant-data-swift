import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1147 (2026-10-24): a refresh of an open page should cost what changed in it, not the page or the schema. The server
// restates the whole page after every write that touches it (the live window about 19 times a minute while recording),
// and an allocation-site recording of one 64-line refresh (`MemorySiteExercises` S03, about 22,400 allocations and
// 21.7 MB) found steps that each rebuilt maps of the whole schema (2,283 attributes on the phone) or of the whole page.
// Each step here is held by a one-thread allocation count, so the tests a parallel bundle runs beside them do not land
// in the count. The schema-size bounds hold in optimized builds, where the counts were measured: an unoptimized build
// copies each attribute out of the schema's array onto the heap while it scans it, as the #1108 test says.
//
// History:
// - 2026-10-24: #1147: the nested-limit pass: its cost, and its shortcut's equivalence with the general pass.
// - 2026-10-24: #1147: the deferred-value hydration of an emission.
// - 2026-10-24: #1147: a refresh frame's parse.
// - 2026-10-25: #1147: the schema-size bounds hold in optimized builds only (a debug bundle failed them, v1.9.39's check).

@Suite
struct RefreshCostTests {
  /// The nested-limit pass bounds nested includes the server does not limit; a query with none passes through it. Run
  /// twice per refresh (the translator, then the persisted result), it built maps of every attribute and of every row
  /// before finding nothing to drop: about 6.5 MB of the recorded refresh.
  @Test("A page with no nested include passes the nested-limit pass at the same small cost with 2,283 attributes as with 16")
  func aPageWithNoNestedIncludePassesThroughTheNestedLimitPass() {
    let page = Self.page(rows: 64)
    let small = Self.attributes(count: 16)
    let large = Self.attributes(count: 2_283)
    expectNoDifference(
      InstantLiveQueryNestedLimit.limitedTriples(queryKey: page.key, triples: page.triples, attributes: large),
      page.triples
    )
    let withSmall = Self.bytesAllocated {
      _ = InstantLiveQueryNestedLimit.limitedTriples(queryKey: page.key, triples: page.triples, attributes: small)
    }
    let withLarge = Self.bytesAllocated {
      _ = InstantLiveQueryNestedLimit.limitedTriples(queryKey: page.key, triples: page.triples, attributes: large)
    }
    guard RealSizeBudget.isOptimized else { return }
    #expect(
      withLarge <= withSmall + 4_096,
      "The pass allocated \(withLarge) bytes with 2,283 attributes against \(withSmall) with 16."
    )
    #expect(withLarge <= 64 * 1_024, "The pass allocated \(withLarge) bytes for a 64-row page it keeps whole.")
  }

  /// Wherever the shortcut for queries with no nested include applies, it keeps exactly what the general pass keeps:
  /// rows of other namespaces left out, links to rows outside the result dropped, rows past a limit sorted by the general
  /// pass, attributes the schema does not declare named by their ids.
  @Test(arguments: [UInt64(81_147), 81_148, 81_149, 81_150])
  func theShortcutKeepsWhatTheGeneralPassKeeps(seed: UInt64) {
    var random = InfiniteWindowRandom(seed: seed)
    let attributes = Self.attributes(count: 40) + [
      InstantAttribute(
        id: "transcriptionSegments/links", namespace: "transcriptionSegments", name: "links", valueType: .ref,
        isRequired: false, cardinality: .many, linkNamespace: "transcriptionSegments"
      ),
      InstantAttribute(
        id: "server-attribute-7f3a", namespace: "transcriptionSegments", name: "opaque", valueType: .string
      ),
    ]
    for round in 0..<200 {
      var triples: [InstantTriple] = []
      for row in 0..<random.int(0...12) {
        let id = "line-\(random.int(0...15))"
        triples.append(Self.triple(id, "transcriptionSegments/segmentIndex", .number(Double(random.int(0...9)))))
        if random.chance(30) { triples.append(Self.triple(id, "transcriptionSegments/links", .ref("line-\(random.int(0...15))"))) }
        if random.chance(20) { triples.append(Self.triple(id, "server-attribute-7f3a", .string("row \(row)"))) }
        if random.chance(15) { triples.append(Self.triple("other-\(row)", "other/field-30", .string("elsewhere"))) }
        if random.chance(10) { triples.append(Self.triple("unknown-\(row)", "undeclared/field", .string("?"))) }
      }
      let limit = random.chance(30) ? "" : #","limit":\#(random.int(0...10))"#
      let otherNode = random.chance(25) ? #","other":{"$":{}}"# : ""
      let key = #"{"transcriptionSegments":{"$":{"order":{"segmentIndex":"desc"}\#(limit)}}\#(otherNode)}"#
      for queryKey in [key, "not-json", #"{"transcriptionSegments":{"$":{}},"x":1}"#] {
        let label = "round \(round) key \(queryKey)"
        expectNoDifference(
          InstantLiveQueryNestedLimit.limitedTriples(queryKey: queryKey, triples: triples, attributes: attributes),
          InstantLiveQueryNestedLimit.generalLimitedTriplesForTesting(queryKey: queryKey, triples: triples, attributes: attributes),
          "\(label)"
        )
        expectNoDifference(
          InstantLiveQueryNestedLimit.retainedEntityIDs(queryKey: queryKey, triples: triples, attributes: attributes),
          InstantLiveQueryNestedLimit.generalRetainedEntityIDsForTesting(queryKey: queryKey, triples: triples, attributes: attributes),
          "\(label)"
        )
      }
    }
  }

  /// A selected page's text and words stay on disk until an emission shows them; hydrating an emission grouped and
  /// mapped every attribute of the schema three times to find the two deferred ones: about 2.2 MB of the recorded refresh.
  @Test("Hydrating a 64-row emission's deferred text allocates the same with 2,283 attributes as with 16")
  func hydratingAnEmissionDoesNotMapTheSchema() {
    let policy = InstantDeferredValueResidencyPolicy(attributeIDs: ["transcriptionSegments/text", "transcriptionSegments/wordsJSON"])
    let deferred = [
      InstantAttribute(id: "transcriptionSegments/text", namespace: "transcriptionSegments", name: "text", valueType: .string),
      InstantAttribute(id: "transcriptionSegments/wordsJSON", namespace: "transcriptionSegments", name: "wordsJSON", valueType: .string),
    ]
    let small = deferred + Self.attributes(count: 16)
    let large = deferred + Self.attributes(count: 2_283)
    let plan = InstantQueryPlan(
      id: "page", namespace: "transcriptionSegments",
      selectedFields: ["recordingID", "segmentIndex", "text", "wordsJSON"]
    )
    let snapshots = (0..<64).map { row in
      InstantEntitySnapshot(
        id: "line-\(row)", namespace: "transcriptionSegments",
        values: ["recordingID": .one(.string("recording")), "segmentIndex": .one(.number(Double(row)))]
      )
    }
    let values = snapshots.flatMap { snapshot in
      [
        Self.triple(snapshot.id, "transcriptionSegments/text", .string("the words of \(snapshot.id)")),
        Self.triple(snapshot.id, "transcriptionSegments/wordsJSON", .string("[{\"w\":\"\(snapshot.id)\"}]")),
      ]
    }
    let emission = InstantQueryEmission(queryID: "page", sequence: 1, values: snapshots)
    func hydrate(_ attributes: [InstantAttribute]) -> InstantQueryEmission {
      _ = policy.hasRequestedAttributes(for: plan, attributes: attributes)
      _ = policy.hydrationRequests(for: plan, values: snapshots, attributes: attributes)
      return policy.hydrating(emission, for: plan, with: values, attributes: attributes)
    }
    expectNoDifference(hydrate(large), hydrate(small))
    expectNoDifference(hydrate(large).values.first?.values["text"], .one(.string("the words of line-0")))
    guard RealSizeBudget.isOptimized else { return }
    let withSmall = Self.bytesAllocated { _ = hydrate(small) }
    let withLarge = Self.bytesAllocated { _ = hydrate(large) }
    #expect(
      withLarge <= withSmall + 4_096,
      "Hydrating allocated \(withLarge) bytes with 2,283 attributes against \(withSmall) with 16."
    )
  }

  /// Every refresh restates the whole page, so its frame's parse runs about 19 times a minute on the live window alone.
  /// Each join row is an array of four-element arrays: growing every array by doubling, a byte buffer per escaped string
  /// and a new string for every repeated id made about 111 allocations a line.
  @Test("Decoding a 64-line page's refresh frame allocates under 50 times a line")
  func decodingARefreshFrameCostsLittlePerLine() throws {
    let rows = (0..<64).map { line in
      RealSizeAccount.segment(
        recordingID: RealSizeID.make(.recording, 1), line: line, revision: 4, serial: 0, id: RealSizeID.make(.segment, line)
      ).joinRow()
    }
    let query = InstantLiveJSONValue.object(["transcriptionSegments": .object(["$": .object(["limit": .number(64)])])])
    let frame = MemoryReplayServer.encoded(MemoryReplayServer.refreshFrame(query, rows: rows, tx: "1"))
    let decoded = try InstantLiveMessage.decoded(fromFrame: frame)
    expectNoDifference(decoded.op, "refresh-ok")
    expectNoDifference(decoded, try JSONDecoder().decode(InstantLiveMessage.self, from: Data(frame.utf8)))
    let allocations = Self.allocations { _ = try? InstantLiveMessage.decoded(fromFrame: frame) }
    #expect(allocations < 50 * 64, "Decoding the 64-line frame allocated \(allocations) times (\(allocations / 64) a line).")
  }

  // MARK: - Helpers

  /// Allocations this thread makes per call of `body`.
  static func allocations(iterations: Int = 10, _ body: () -> Void) -> Int {
    body()
    RealSizeAllocations.start(onCurrentThreadOnly: true)
    for _ in 0..<iterations { body() }
    return RealSizeAllocations.stop().allocations / iterations
  }

  /// Bytes this thread allocates per call of `body`.
  static func bytesAllocated(iterations: Int = 10, _ body: () -> Void) -> Int {
    body()
    RealSizeAllocations.start(onCurrentThreadOnly: true)
    for _ in 0..<iterations { body() }
    return RealSizeAllocations.stop().allocatedBytes / iterations
  }

  /// A refresh's page of transcript lines: `rows` lines of one recording, sixteen facts each, and the query's key as the
  /// runtime registers it (sorted keys).
  static func page(rows: Int) -> (key: String, triples: [InstantTriple]) {
    let key = #"{"transcriptionSegments":{"$":{"limit":256,"order":{"segmentIndex":"asc"},"where":{"recordingID":"recording"}}}}"#
    var triples: [InstantTriple] = []
    for row in 0..<rows {
      let id = "line-\(row)"
      triples.append(triple(id, "transcriptionSegments/id", .string(id)))
      triples.append(triple(id, "transcriptionSegments/recordingID", .string("recording")))
      triples.append(triple(id, "transcriptionSegments/segmentIndex", .number(Double(row))))
      for field in 0..<13 {
        triples.append(triple(id, "transcriptionSegments/field-\(field)", .string("value \(field) of \(id)")))
      }
    }
    return (key, triples)
  }

  /// A recording's lines with sixteen fields, then other namespaces' attributes up to `count`.
  static func attributes(count: Int) -> [InstantAttribute] {
    var attributes: [InstantAttribute] = [
      .primaryKey(namespace: "transcriptionSegments"),
      InstantAttribute(
        id: "transcriptionSegments/recordingID", namespace: "transcriptionSegments", name: "recordingID",
        valueType: .string, isIndexed: true
      ),
      InstantAttribute(
        id: "transcriptionSegments/segmentIndex", namespace: "transcriptionSegments", name: "segmentIndex",
        valueType: .number, isIndexed: true
      ),
    ]
    attributes += (0..<13).map {
      InstantAttribute(
        id: "transcriptionSegments/field-\($0)", namespace: "transcriptionSegments", name: "field-\($0)", valueType: .string
      )
    }
    attributes += (attributes.count..<count).map {
      InstantAttribute(id: "other/field-\($0)", namespace: "other", name: "field-\($0)", valueType: .string)
    }
    return attributes
  }

  static func triple(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> InstantTriple {
    InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: "tx", txTime: InstantTimestamp(milliseconds: 1))
  }
}
