import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1108 (2026-10-24): every transact asks whether it may replace the outbox's tail, and that check built a dictionary
// of every attribute in the schema before it looked at the write's shape: on a phone with 2,283 attributes about 1 MB
// allocated per write, though most writes (merges, a line linked to its recording) can never replace a tail. Counted
// on the calling thread only, so the tests a parallel bundle runs beside it do not land in the count.
//
// History:
// - 2026-10-24: #1108: the cost test.

@Suite(.serialized)
struct OutboxSupersessionSchemaCostTests {
  @Test("A write's tail-replacement check allocates the same bytes with 2,283 attributes as with 16")
  func tailReplacementCheckDoesNotGrowWithTheSchema() {
    let small = Self.schema(attributeCount: 16)
    let large = Self.schema(attributeCount: 2_283)
    // A transcript line merged in place, as the app writes one: never a tail replacement.
    let merge = InstantStoreTransaction(
      id: "merge-line",
      operations: (0..<8).map { .merge(Self.triple("line-1", field: $0, value: "merged")) }
    )
    // A whole scalar row inserted, as a live line's upsert is: a candidate.
    let upsert = InstantStoreTransaction(
      id: "upsert-line",
      operations: [.insert(Self.triple("line-1", field: nil, value: "line-1"))]
        + (0..<8).map { .insert(Self.triple("line-1", field: $0, value: "upserted")) }
    )

    for transaction in [merge, upsert] {
      expectNoDifference(
        OutboxSameEntitySupersession.isEligibleImmediateTailNewcomer(transaction, attributes: large),
        OutboxSameEntitySupersession.isEligibleImmediateTailNewcomer(transaction, attributes: small)
      )
      let withSmall = Self.bytesAllocatedPerCheck(transaction, attributes: small)
      let withLarge = Self.bytesAllocatedPerCheck(transaction, attributes: large)
      #expect(
        withLarge <= withSmall + 4_096,
        "\(transaction.id): \(withLarge) bytes allocated a check with 2,283 attributes against \(withSmall) with 16."
      )
    }
  }

  private static func bytesAllocatedPerCheck(_ transaction: InstantStoreTransaction, attributes: [InstantAttribute]) -> Int {
    let checks = 50
    _ = OutboxSameEntitySupersession.isEligibleImmediateTailNewcomer(transaction, attributes: attributes)
    RealSizeAllocations.start(onCurrentThreadOnly: true)
    for _ in 0..<checks {
      _ = OutboxSameEntitySupersession.isEligibleImmediateTailNewcomer(transaction, attributes: attributes)
    }
    return RealSizeAllocations.stop().allocatedBytes / checks
  }

  /// `ns/id` (the primary key), `ns/field-0` ... `ns/field-7` (the write's scalars), and other namespaces' attributes up
  /// to `attributeCount`.
  private static func schema(attributeCount: Int) -> [InstantAttribute] {
    var attributes = [
      InstantAttribute(id: "ns/id", namespace: "ns", name: "id", valueType: .string, cardinality: .one, primaryKey: true)
    ]
    attributes += (0..<8).map {
      InstantAttribute(id: "ns/field-\($0)", namespace: "ns", name: "field-\($0)", valueType: .string, cardinality: .one)
    }
    attributes += (attributes.count..<attributeCount).map {
      InstantAttribute(id: "other/field-\($0)", namespace: "other", name: "field-\($0)", valueType: .string, cardinality: .one)
    }
    return attributes
  }

  private static func triple(_ entityID: String, field: Int?, value: String) -> InstantTriple {
    InstantTriple(
      entityID: entityID,
      attributeID: field.map { "ns/field-\($0)" } ?? "ns/id",
      value: .string(value),
      txID: "tx",
      txTime: InstantTimestamp(milliseconds: 1)
    )
  }
}
