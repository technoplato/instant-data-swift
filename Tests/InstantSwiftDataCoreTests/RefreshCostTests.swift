import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1147 (2026-10-24): a refresh of an open page should cost what changed in it, not the page or the schema. The server
// restates the whole page after every write that touches it (the live window about 19 times a minute while recording),
// and an allocation-site recording of one 64-line refresh (`MemorySiteExercises` S03, about 22,400 allocations and
// 21.7 MB) found steps that each rebuilt maps of the whole schema (2,283 attributes on the phone) or of the whole page.
// Each step here is held by a one-thread allocation count, so the tests a parallel bundle runs beside them do not land
// in the count.
//
// History:
// - 2026-10-24: #1147: the nested-limit pass.

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
    #expect(
      withLarge <= withSmall + 4_096,
      "The pass allocated \(withLarge) bytes with 2,283 attributes against \(withSmall) with 16."
    )
    #expect(withLarge <= 64 * 1_024, "The pass allocated \(withLarge) bytes for a 64-row page it keeps whole.")
  }

  // MARK: - Helpers

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
