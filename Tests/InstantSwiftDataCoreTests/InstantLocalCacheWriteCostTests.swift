import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1015: what a cache's `auto_vacuum` mode costs the library's own writes. `auto_vacuum = INCREMENTAL` keeps pointer-map
// pages, which every allocation, free and balance that moves a page or an overflow chain updates; a synthetic
// Scribe-shaped SQL workload wrote 7.6% more with them. This runs the library's real write path twice per round, once
// for a cache created in each mode: FastDrainFixture's server history (a server apply), its pending segment writes
// (`transact`, six per segment) and its drain (an acknowledgement and a refresh frame per write), and prints one
// `WRITECOST` line per phase with the process's logical bytes written. It is skipped unless
// `INSTANT_LOCAL_CACHE_WRITE_COST` is set, and scales with:
//   INSTANT_LOCAL_CACHE_WRITE_COST_ROUNDS            rounds, each mode once (default 3)
//   INSTANT_LOCAL_CACHE_WRITE_COST_PENDING_SEGMENTS  pending segments (default 200: 1,200 writes)
//   INSTANT_LOCAL_CACHE_WRITE_COST_SERVER_SEGMENTS   segments the server already holds (default 300)
//   INSTANT_LOCAL_CACHE_WRITE_COST_FRAMES            drain frames (default 120)
//
// `measureCompactionOnAStoreCopy` runs compaction on a scratch copy of a real store (its credential rows deleted) and
// prints what it did, what it wrote and the process's peak memory, and checks every table's rows after it. It is
// skipped unless `INSTANT_LOCAL_CACHE_COMPACTION_STORE` names a store (`<appID>.sqlite` or its directory).
@Suite(.serialized)
struct InstantLocalCacheWriteCostTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_LOCAL_CACHE_COMPACTION_STORE"] != nil))
  func measureCompactionOnAStoreCopy() async throws {
    let environment = ProcessInfo.processInfo.environment
    let store = try PhoneReplayGateTests.storeFile(at: try #require(environment["INSTANT_LOCAL_CACHE_COMPACTION_STORE"]))
    let url = try PhoneReplayGateTests.scratchCopy(of: store, in: FileManager.default.temporaryDirectory)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let runtime = try await PhoneReplayGateTests.runtime(
      url,
      appID: store.deletingPathExtension().lastPathComponent,
      deferred: InstantDeferredValueResidencyPolicy(attributeIDs: PhoneReplayGateTests.scribeDeferredAttributeIDs)
    )
    let rows = try InstantLocalCacheCompactionTests.tableChecksums(at: url)
    let memoryBefore = Self.footprint()
    let usageBefore = ServerApplyProcessUsage.now()

    let compaction = try await runtime.compactLocalCache()

    let usageAfter = ServerApplyProcessUsage.now()
    let memoryAfter = Self.footprint()
    let megabytes = { (bytes: Int64) in String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    print(
      """
      COMPACTION \(compaction.outcome.logDescription): \(compaction.before.pageCount) pages (\(megabytes(compaction.before.byteCount))), \
      \(compaction.before.freePageCount) free (\(megabytes(compaction.before.freeByteCount))) -> \(compaction.after.pageCount) pages \
      (\(megabytes(compaction.after.byteCount))), \(compaction.after.freePageCount) free; VACUUM \(compaction.vacuumDuration.map { "\($0)" } ?? "-"); \
      writes \(megabytes(Int64(usageAfter.logicalWriteBytes - usageBefore.logicalWriteBytes))); \
      cpu \((usageAfter.cpuNanoseconds - usageBefore.cpuNanoseconds) / 1_000_000) ms; footprint \(megabytes(memoryBefore.current)) before, \
      peak \(megabytes(memoryBefore.peak)) before and \(megabytes(memoryAfter.peak)) after
      """
    )
    #expect(compaction.outcome == .compacted)
    let rowsAfter = try InstantLocalCacheCompactionTests.tableChecksums(at: url)
    #expect(rowsAfter == rows)
  }

  /// The process's memory footprint now, and the most it has reached.
  static func footprint() -> (current: Int64, peak: Int64) {
    var info = rusage_info_v4()
    _ = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
      }
    }
    return (Int64(info.ri_phys_footprint), Int64(info.ri_lifetime_max_phys_footprint))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_LOCAL_CACHE_WRITE_COST"] != nil))
  func measureWritesInEachAutoVacuumMode() async throws {
    let environment = ProcessInfo.processInfo.environment
    let rounds = environment["INSTANT_LOCAL_CACHE_WRITE_COST_ROUNDS"].flatMap(Int.init) ?? 3
    let pendingSegments = environment["INSTANT_LOCAL_CACHE_WRITE_COST_PENDING_SEGMENTS"].flatMap(Int.init) ?? 200
    let serverSegments = environment["INSTANT_LOCAL_CACHE_WRITE_COST_SERVER_SEGMENTS"].flatMap(Int.init) ?? 300
    let drainFrames = environment["INSTANT_LOCAL_CACHE_WRITE_COST_FRAMES"].flatMap(Int.init) ?? 120
    var totals: [InstantLocalCacheFile.AutoVacuum: (setup: UInt64, drain: UInt64)] = [:]
    for round in 1...rounds {
      for mode in round.isMultiple(of: 2)
        ? [InstantLocalCacheFile.AutoVacuum.incremental, .none] : [.none, .incremental]
      {
        let (setup, drain, file) = try await SQLitePersistenceStore.$newCacheAutoVacuum.withValue(mode) {
          let start = ServerApplyProcessUsage.now()
          var fixture = try await FastDrainFixture.make(
            suffix: "write-cost-\(mode.rawValue)",
            serverSegmentCount: serverSegments,
            pendingSegmentCount: pendingSegments,
            scribeLinks: true,
            defersSegmentText: true,
            liveLines: true
          )
          let afterSetup = ServerApplyProcessUsage.now()
          var window = try await fixture.claimWindow()
          var delivered = 0
          for _ in 0..<drainFrames {
            if delivered == window.mutations.count {
              window = try await fixture.claimWindow()
              delivered = 0
            }
            guard delivered < window.mutations.count else { break }
            let mutation = window.mutations[delivered]
            delivered += 1
            _ = try await fixture.acceptAndRefresh(mutation, claimToken: window.token)
          }
          let afterDrain = ServerApplyProcessUsage.now()
          let file = try await fixture.runtime.persistence.localCacheFile()
          return (
            afterSetup.logicalWriteBytes - start.logicalWriteBytes,
            afterDrain.logicalWriteBytes - afterSetup.logicalWriteBytes,
            file
          )
        }
        #expect(file.autoVacuum == mode)
        let total = totals[mode] ?? (0, 0)
        totals[mode] = (total.setup + setup, total.drain + drain)
        print(
          "WRITECOST round=\(round) mode=\(mode.rawValue) setupKB=\(setup / 1024) drainKB=\(drain / 1024) pages=\(file.pageCount) free=\(file.freePageCount)"
        )
      }
    }
    let none = totals[.none] ?? (0, 0)
    let incremental = totals[.incremental] ?? (0, 0)
    func percent(_ incremental: UInt64, _ none: UInt64) -> String {
      none == 0 ? "n/a" : String(format: "%+.2f%%", (Double(incremental) / Double(none) - 1) * 100)
    }
    print(
      """
      WRITECOST summary rounds=\(rounds): setup none \(none.setup / 1024) KB, incremental \(incremental.setup / 1024) KB \
      (\(percent(incremental.setup, none.setup))); drain none \(none.drain / 1024) KB, incremental \
      \(incremental.drain / 1024) KB (\(percent(incremental.drain, none.drain)))
      """
    )
  }
}
