import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1152 (2026-10-24): a recording's lines are one many-cardinality slot on the recording (`recordings/segments`, the
// forward side of the line's `recording` link), and a write is prepared on a copy of the store's indexes that shares
// their storage with the store. The slot's first change in a prepare copied every value it held, so each finished line
// copied its recording's whole link set: +523 KB per line on a recording with 2,318 lines at the phone's size (the
// memory audit's E04 and M13, docs/audits/2026-10-24-memory-audit.md). The same insert rewrote the map of derived index
// shapes, one entry per attribute in the schema, with an unchanged entry, copying all of it. Counted on the calling
// thread only, so the tests a parallel bundle runs beside these do not land in the count.
//
// History:
// - 2026-10-24: #1152: the cost tests.

@Suite
struct LinkSetWriteCostTests {
  @Test("A line linked to a recording that holds 2,318 lines allocates what one linked to a new recording does")
  func linkingALineDoesNotCopyTheRecordingsOtherLinks() {
    let attributes = Self.attributes(count: 16)
    let indexes = Self.indexes(linkedLines: ["long": 2_318, "new": 0], attributes: attributes)
    let long = Self.bytesAllocatedPerPreparedLine(on: indexes, recordingID: "long", attributes: attributes)
    let new = Self.bytesAllocatedPerPreparedLine(on: indexes, recordingID: "new", attributes: attributes)
    #expect(
      long <= new + 8_192,
      "A line linked to the recording with 2,318 lines allocated \(long) bytes; one linked to a new recording \(new)."
    )
  }

  @Test("A line linked to its recording allocates the same bytes with 2,283 attributes as with 16")
  func linkingALineDoesNotCopyTheSchema() {
    let small = Self.attributes(count: 16)
    let large = Self.attributes(count: 2_283)
    let withSmall = Self.bytesAllocatedPerPreparedLine(
      on: Self.indexes(linkedLines: ["recording": 40], attributes: small), recordingID: "recording", attributes: small
    )
    let withLarge = Self.bytesAllocatedPerPreparedLine(
      on: Self.indexes(linkedLines: ["recording": 40], attributes: large), recordingID: "recording", attributes: large
    )
    #expect(
      withLarge <= withSmall + 4_096,
      "A line linked to its recording allocated \(withLarge) bytes with 2,283 attributes against \(withSmall) with 16."
    )
  }

  /// The prepared copy gains the line and the indexes it was copied from keep exactly what they held, at every size a
  /// link set passes through as a recording grows.
  @Test(arguments: [0, 1, 31, 32, 33, 2_318])
  func aPreparedLineChangesOnlyItsCopy(linkedLines: Int) {
    let attributes = Self.attributes(count: 16)
    let installed = Self.indexes(linkedLines: ["recording": linkedLines], attributes: attributes)
    let before = Self.linkedLineIDs(installed, recordingID: "recording")
    var prepared = installed
    for operation in Self.finishedLine("added", recordingID: "recording", txID: "tx-added") {
      prepared.apply(operation, attributes: attributes)
    }
    expectNoDifference(Self.linkedLineIDs(installed, recordingID: "recording"), before)
    expectNoDifference(Self.linkedLineIDs(prepared, recordingID: "recording"), (before + ["added"]).sorted())
    expectNoDifference(installed.containsStoredEntity("added"), false)
    expectNoDifference(prepared.containsStoredEntity("added"), true)
  }

  // MARK: - Helpers

  /// Bytes allocated on this thread to prepare one finished line (its id, its text and its link to `recordingID`) on a
  /// copy of `indexes`, the way the store prepares each write on a copy of the indexes it holds.
  private static func bytesAllocatedPerPreparedLine(
    on indexes: TripleIndexes,
    recordingID: String,
    attributes: AttributeStore
  ) -> Int {
    let iterations = 20
    var bytes = 0
    for iteration in -2..<iterations {
      let operations = finishedLine("\(recordingID)-line-\(iteration)", recordingID: recordingID, txID: "tx-\(recordingID)")
      var prepared = indexes
      RealSizeAllocations.start(onCurrentThreadOnly: true)
      for operation in operations {
        prepared.apply(operation, attributes: attributes)
      }
      let counted = RealSizeAllocations.stop().allocatedBytes
      // The first two warm the shared transaction-id interner and anything else allocated once.
      if iteration >= 0 { bytes += counted }
      withExtendedLifetime(prepared) {}
    }
    return bytes / iterations
  }

  /// A finished line as the store applies it: its primary key, its text, and its link, stored on the recording's side.
  private static func finishedLine(_ lineID: String, recordingID: String, txID: String) -> [InstantTripleOperation] {
    [
      .insert(triple(lineID, "transcriptionSegments/id", .string(lineID), txID: txID)),
      .insert(triple(lineID, "transcriptionSegments/text", .string("words of \(lineID)"), txID: txID)),
      .insert(triple(recordingID, "recordings/segments", .ref(lineID), txID: txID)),
    ]
  }

  private static func linkedLineIDs(_ indexes: TripleIndexes, recordingID: String) -> [String] {
    indexes.triples(entityID: recordingID)
      .filter { $0.attributeID == "recordings/segments" }
      .compactMap(\.value.refValue)
      .sorted()
  }

  /// Each recording with its primary key and `linkedLines[recording]` lines linked to it.
  private static func indexes(linkedLines: [String: Int], attributes: AttributeStore) -> TripleIndexes {
    var triples: [InstantTriple] = []
    for (recordingID, count) in linkedLines.sorted(by: { $0.key < $1.key }) {
      triples.append(triple(recordingID, "recordings/id", .string(recordingID), txID: "seed"))
      for line in 0..<count {
        let lineID = "\(recordingID)-seed-\(line)"
        triples.append(triple(lineID, "transcriptionSegments/id", .string(lineID), txID: "seed"))
        triples.append(triple(recordingID, "recordings/segments", .ref(lineID), txID: "seed"))
      }
    }
    return TripleIndexes(triples: triples, attributes: attributes)
  }

  /// Scribe's recording, its lines and the link between them (`recordingSegments`: forward on the recording, has many),
  /// then other namespaces' attributes up to `count`.
  private static func attributes(count: Int) -> AttributeStore {
    var attributes: [InstantAttribute] = [
      .primaryKey(namespace: "recordings"),
      .primaryKey(namespace: "transcriptionSegments"),
      InstantAttribute(
        id: "transcriptionSegments/text", namespace: "transcriptionSegments", name: "text", valueType: .string
      ),
      InstantAttribute(
        id: "recordings/segments", namespace: "recordings", name: "segments", valueType: .ref, isRequired: false,
        cardinality: .many, isIndexed: true, forwardIdentity: "recordings/segments",
        reverseIdentity: "transcriptionSegments/recording", linkNamespace: "transcriptionSegments"
      ),
    ]
    attributes += (attributes.count..<count).map {
      InstantAttribute(id: "other/field-\($0)", namespace: "other", name: "field-\($0)", valueType: .string)
    }
    return AttributeStore(attributes: attributes)
  }

  private static func triple(_ entityID: String, _ attributeID: String, _ value: InstantValue, txID: String) -> InstantTriple {
    InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: txID, txTime: InstantTimestamp(milliseconds: 1))
  }
}
