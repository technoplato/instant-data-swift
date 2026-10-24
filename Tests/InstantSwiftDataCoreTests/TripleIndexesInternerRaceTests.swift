import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1141 (2026-10-24): every copy of `TripleIndexes` shares one transaction-id interner, a class box that appends each
// new transaction id to an array and a dictionary, and the box was written with no lock and no uniqueness check. The
// store's own indexes intern on the store actor while a copy prepared elsewhere (a refused claimed write's component,
// hydrated between the operation gate's turns) interns off it: two threads appending to one array and one dictionary,
// a data race that corrupts the heap. Found by the concurrency audit (#1074, item A15).
//
// History:
// - 2026-10-24: #1141: the race test.

@Suite
struct TripleIndexesInternerRaceTests {
  @Test("Copies of the same indexes take new transaction ids on four threads at once, and each reads back its own")
  func copiesInternTransactionIDsOnFourThreads() async throws {
    let attributes = AttributeStore(attributes: [
      InstantAttribute(id: "ns/value", namespace: "ns", name: "value", valueType: .string, cardinality: .one)
    ])
    let original = TripleIndexes(attributes: attributes)
    let lanes = 4
    let writes = 20_000
    let entities = 16

    let newest = await withTaskGroup(of: (lane: Int, txIDs: [String]).self) { group in
      for lane in 0..<lanes {
        group.addTask { [original] in
          var copy = original
          for write in 0..<writes {
            _ = copy.apply(
              .insert(
                InstantTriple(
                  entityID: "lane-\(lane)-\(write % entities)",
                  attributeID: "ns/value",
                  value: .string("value-\(write)"),
                  txID: "tx-\(lane)-\(write)",
                  txTime: InstantTimestamp(milliseconds: Int64(write + 1))
                )
              ),
              attributes: attributes
            )
          }
          let txIDs = (0..<entities).map { entity in
            copy.triples(entityID: "lane-\(lane)-\(entity)").first?.txID ?? "missing"
          }
          return (lane, txIDs)
        }
      }
      var newest: [Int: [String]] = [:]
      for await result in group { newest[result.lane] = result.txIDs }
      return newest
    }

    for lane in 0..<lanes {
      expectNoDifference(newest[lane], (0..<entities).map { "tx-\(lane)-\(writes - entities + $0)" })
    }
  }
}
