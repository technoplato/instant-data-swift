// History:
// - 2026-10-25: added (#1121): a device's store opens through the library's bootstrap with each fact stored once, and
//   keeps every fact; measured on a scratch copy.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1121 on a store a device holds. A scratch copy of `INSTANT_1121_STORE` (a `.sqlite` file with its `-wal` and
/// `-shm`; credential rows deleted, as the phone replay gate copies one) opens through the library's own bootstrap,
/// which rebuilds its fact table once. Every fact is compared column for column before and after, and the fact table's
/// size, the bootstrap's time and the file's free pages are printed as `FACTLAYOUT` lines. Skipped without
/// `INSTANT_1121_STORE`; `INSTANT_1121_SCRATCH` names the directory for the copy (the temporary directory by default).
/// The copy is deleted afterwards, and the store it names is never written.
@Suite
struct InstantFactLayoutDeviceStoreTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_1121_STORE"] != nil))
  func aDevicesStoreOpensWithEachFactStoredOnce() async throws {
    let environment = ProcessInfo.processInfo.environment
    let source = URL(fileURLWithPath: try #require(environment["INSTANT_1121_STORE"]))
    let scratch = environment["INSTANT_1121_SCRATCH"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.temporaryDirectory
    let store = try PhoneReplayGateTests.scratchCopy(of: source, in: scratch)
    defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
    let factsBefore = try FactLayout.facts(store)
    let layoutBefore = try FactLayout.read(store)

    let started = ContinuousClock.now
    let persistence = try SQLitePersistenceStore(
      fileURL: store,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: PhoneReplayGateTests.scribeDeferredAttributeIDs
      ),
      localLookup: InstantLocalLookupPolicy(attributeIDs: ["recordings/id", "transcriptionSegments/recordingID"])
    )
    try await persistence.bootstrap()
    let bootstrap = started.duration(to: .now)
    let file = try await persistence.localCacheFile()
    let factsAfter = try FactLayout.facts(store)
    let layoutAfter = try FactLayout.read(store)

    let mebibytes = { (pages: Int) in String(format: "%.1f", Double(pages) * 4_096 / 1_048_576) }
    print(
      "FACTLAYOUT device facts=\(factsBefore.count) btreesBefore=\(layoutBefore.btrees.joined(separator: ","))"
        + " pagesBefore=\(layoutBefore.pages) mbBefore=\(mebibytes(layoutBefore.pages))"
        + " pagesAfter=\(layoutAfter.pages) mbAfter=\(mebibytes(layoutAfter.pages))"
        + " bootstrapMs=\(bootstrap.components.seconds * 1_000 + bootstrap.components.attoseconds / 1_000_000_000_000_000)"
        + " filePages=\(file.pageCount) freePages=\(file.freePageCount)"
    )
    expectNoDifference(factsAfter.count, factsBefore.count)
    let changed = zip(factsBefore, factsAfter).filter { $0 != $1 }.count
    #expect(changed == 0, "\(changed) of \(factsBefore.count) facts read back differently")
    #expect(layoutAfter.withoutRowid && layoutAfter.jsonIsComputed, "the bootstrap rebuilt the table: \(layoutAfter)")
    #expect(Double(layoutAfter.pages) * 4_096 / 1_048_576 <= 75, "the fact table takes \(mebibytes(layoutAfter.pages)) MB")
    expectNoDifference(try CheckpointCadence.integrity(store), "ok")
  }
}
