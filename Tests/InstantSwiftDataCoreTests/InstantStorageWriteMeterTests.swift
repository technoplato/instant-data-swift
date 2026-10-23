import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: a device writes tens of megabytes a minute to its local store while it records, and nothing said which store
/// call wrote them. The storage write meter counts, for each store call, its write transactions and the pages SQLite
/// wrote for them.
@Suite
struct InstantStorageWriteMeterTests {
  @Test
  func eachStoreCallsWritesAreCountedUnderItsName() async throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantStorageWriteMeterTests-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try SQLitePersistenceStore(fileURL: url, declaredAttributes: TodoExample.attributes)
    try await store.bootstrap()

    let before = InstantStorageWriteMeter.snapshot()
    let triples = (0..<200).map { index in
      InstantTriple(
        entityID: "todo-\(index)",
        attributeID: TodoExample.attributes[1].id,
        value: .string(String(repeating: "words of todo \(index) ", count: 8)),
        txID: "tx-\(index)",
        txTime: InstantTimestamp(milliseconds: Int64(index) + 1)
      )
    }
    try await store.saveStoreSnapshot(InstantStoreSnapshot(attributes: TodoExample.attributes, triples: triples))
    let counted = InstantStorageWriteMeter.snapshot().subtracting(before)

    let save = try #require(counted.operations["saveStoreSnapshot(_:)"], "operations: \(counted.operations)")
    #expect(save.transactions >= 1)
    // 200 facts of about 160 bytes each fill more than a few 4 KB pages.
    #expect(save.pagesWritten >= 8, "pages: \(save.pagesWritten)")
  }
}
