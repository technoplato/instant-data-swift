import CustomDump
import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: a write is prepared on a copy of the store's indexes, and the copy shared every dictionary with the store, so
/// the write's first change copied each one whole: every entity's facts, every reverse ref, every indexed attribute's
/// values. A store grows with a recording, so each line's write cost more than the last.
@Suite
struct InstantPrepareCopyCostTests {
  /// Preparing one line's write into a store of 20,000 lines costs about what it costs into a store of 2,000.
  @Test
  func preparingAWriteCostsAboutTheSameWhateverTheStoresSize() async throws {
    let small = try await Self.store(lineCount: 2_000)
    let large = try await Self.store(lineCount: 20_000)
    let transaction = Self.lineWrite(index: 999_999)
    // Warm both stores' paths once.
    _ = try await small.prepareCurrent(transaction)
    _ = try await large.prepareCurrent(transaction)
    let smallCost = try await Self.cost(of: transaction, in: small)
    let largeCost = try await Self.cost(of: transaction, in: large)
    let ratio = Double(largeCost) / Double(max(smallCost, 1))
    print("prepare: \(smallCost / 1_000) us into 2,000 lines, \(largeCost / 1_000) us into 20,000 (ratio \(ratio))")
    // Copying whole maps measured 9.7; the shards about 2 alone and 3.8 while a whole bundle runs beside it (#1021), so
    // the bound leaves room for that load and still fails on whole-map copies.
    #expect(ratio < 5, "preparing into the larger store cost \(ratio) times as much")
  }

  // MARK: - Helpers

  static let namespace = "copyCostSegments"

  static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: namespace),
    InstantAttribute(id: "\(namespace)/recordingID", namespace: namespace, name: "recordingID", valueType: .string, isIndexed: true),
    InstantAttribute(id: "\(namespace)/segmentIndex", namespace: namespace, name: "segmentIndex", valueType: .number, isIndexed: true),
    InstantAttribute(id: "\(namespace)/startTimeSeconds", namespace: namespace, name: "startTimeSeconds", valueType: .number, isIndexed: true),
    InstantAttribute(id: "\(namespace)/updatedAtMs", namespace: namespace, name: "updatedAtMs", valueType: .number, isIndexed: true),
    InstantAttribute(id: "\(namespace)/text", namespace: namespace, name: "text", valueType: .string),
  ]

  static func lineWrite(index: Int) -> InstantStoreTransaction {
    let id = InstantManyCardinalitySortCostTests.uuidString(seed: 11, index: index)
    let transactionID = "tx-line-\(index)"
    func insert(_ name: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: "\(namespace)/\(name)",
          value: value,
          txID: transactionID,
          txTime: InstantTimestamp(milliseconds: Int64(index) + 1)
        )
      )
    }
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert("id", .string(id)),
        insert("recordingID", .string("recording")),
        insert("segmentIndex", .number(Double(index))),
        insert("startTimeSeconds", .number(Double(index) * 5)),
        insert("updatedAtMs", .number(Double(index) + 1_791_700_000_000)),
        insert("text", .string("line \(index)")),
      ]
    )
  }

  static func store(lineCount: Int) async throws -> InstantStore {
    var triples: [InstantTriple] = []
    triples.reserveCapacity(lineCount * 6)
    for index in 0..<lineCount {
      for operation in lineWrite(index: index).operations {
        if case let .insert(triple) = operation { triples.append(triple) }
      }
    }
    return InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes, triples: triples))
  }

  static func cost(of transaction: InstantStoreTransaction, in store: InstantStore) async throws -> UInt64 {
    var total: UInt64 = 0
    for _ in 0..<20 {
      total += try await store.preparationThreadCPUNanoseconds(transaction)
    }
    return total
  }
}

extension InstantStore {
  /// The thread CPU one preparation of `transaction` takes on the store's executor, discarded afterwards.
  fileprivate func preparationThreadCPUNanoseconds(_ transaction: InstantStoreTransaction) throws -> UInt64 {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    _ = try prepareCurrent(transaction)
    return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
  }
}
