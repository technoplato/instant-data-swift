// History:
// - 2026-10-23: the local cache's free pages, as SQLite counts them, and what one compaction did with them (#1015).

import Foundation

/// The local cache's SQLite file as SQLite counts it: its pages, the free ones among them, and how it gives free pages
/// back to the file system (#1015).
///
/// SQLite reuses a free page before it grows the file, but a file in `auto_vacuum = NONE` never shrinks: on one iPhone
/// 676 MB of a 916 MB cache were free pages. ``InstantRuntime/compactLocalCache(holdingWhile:)`` gives them back.
/// Caches stay in `auto_vacuum = NONE`: `INCREMENTAL` would give free pages back in small steps, but its pointer-map
/// pages made every write cost more (measured on the library's own write path: +3.0% for transactions and server
/// applies, +5.8% for acknowledgements and refreshes).
public struct InstantLocalCacheFile: Hashable, Codable, Sendable {
  /// How SQLite gives free pages back to the file system: `PRAGMA auto_vacuum`.
  public enum AutoVacuum: String, Hashable, Codable, Sendable {
    /// Never: free pages stay in the file, for SQLite to reuse, until a `VACUUM` rewrites it. Every cache the library
    /// creates.
    case none
    /// At every commit.
    case full
    /// In steps, with `PRAGMA incremental_vacuum`.
    case incremental
  }

  public var pageSize: Int
  public var pageCount: Int
  public var freePageCount: Int
  public var autoVacuum: AutoVacuum

  public init(pageSize: Int, pageCount: Int, freePageCount: Int, autoVacuum: AutoVacuum) {
    self.pageSize = pageSize
    self.pageCount = pageCount
    self.freePageCount = freePageCount
    self.autoVacuum = autoVacuum
  }

  /// The file's size as of its last commit, free pages included; the WAL and its index are apart.
  public var byteCount: Int64 { Int64(pageSize) * Int64(pageCount) }
  /// The part of the file that holds no data.
  public var freeByteCount: Int64 { Int64(pageSize) * Int64(freePageCount) }
  /// The pages that hold data.
  public var livePageCount: Int { pageCount - freePageCount }
}

extension InstantLocalCacheFile.AutoVacuum {
  /// `PRAGMA auto_vacuum`'s value: 0, 1 or 2.
  init(sqliteValue: Int64) {
    switch sqliteValue {
    case 1: self = .full
    case 2: self = .incremental
    default: self = .none
    }
  }
}

/// What one ``InstantRuntime/compactLocalCache(holdingWhile:)`` did (#1015).
public struct InstantLocalCacheCompaction: Hashable, Sendable {
  public enum Outcome: Hashable, Sendable {
    /// The free pages were within the cache's allowance: nothing was written.
    case notNeeded
    /// One `VACUUM` rewrote the file without its free pages.
    case compacted
    /// The `VACUUM` did not start, for this reason; the next call tries again.
    case held(Hold)
  }

  /// Why the `VACUUM` did not start.
  public enum Hold: Hashable, Sendable {
    /// The device's thermal state is serious or critical.
    case deviceIsHot
    /// Low Power Mode is on.
    case lowPowerMode
    /// The volume lacks the room the `VACUUM` needs while it runs: a copy of the live pages, and a WAL as large.
    case insufficientDiskSpace(availableBytes: Int64, requiredBytes: Int64)
    /// The task was cancelled.
    case cancelled
    /// The application's `hold` gave this reason.
    case application(String)
  }

  public var outcome: Outcome
  /// The file before compaction, and after it.
  public var before: InstantLocalCacheFile
  public var after: InstantLocalCacheFile
  /// How long the `VACUUM` held the store, when it ran: every write waited for it.
  public var vacuumDuration: Duration?

  public init(
    outcome: Outcome,
    before: InstantLocalCacheFile,
    after: InstantLocalCacheFile,
    vacuumDuration: Duration? = nil
  ) {
    self.outcome = outcome
    self.before = before
    self.after = after
    self.vacuumDuration = vacuumDuration
  }
}

/// When compaction is worth a `VACUUM` (#1015).
///
/// A `VACUUM` in WAL mode writes the live pages three times (a temporary copy, the WAL, the checkpoint): on a copy of
/// the phone's cache, 630-645 MB for 197 MB of live pages. It runs only when the free pages are both a large share of
/// the file and a large amount, so each run gives back a lot for what it writes; between runs SQLite reuses the free
/// pages, at no cost.
package struct InstantLocalCacheCompactionPolicy: Hashable, Sendable {
  /// The share of the file's pages that must be free...
  package var minimumFreeFraction = 0.25
  /// ...and the free bytes, at least.
  package var minimumFreeBytes: Int64 = 64 * 1_024 * 1_024

  package init(minimumFreeFraction: Double = 0.25, minimumFreeBytes: Int64 = 64 * 1_024 * 1_024) {
    self.minimumFreeFraction = minimumFreeFraction
    self.minimumFreeBytes = minimumFreeBytes
  }

  /// Whether `file` holds enough free pages for a `VACUUM`.
  package func needsCompaction(_ file: InstantLocalCacheFile) -> Bool {
    file.freeByteCount >= minimumFreeBytes
      && Double(file.freePageCount) >= Double(file.pageCount) * minimumFreeFraction
  }

  /// The room a `VACUUM` of `file` needs on its volume while it runs: a temporary copy of the live pages and a WAL as
  /// large (measured: 382-393 MB beyond the file for 197 MB of live pages), and some slack.
  package func requiredDiskBytes(_ file: InstantLocalCacheFile) -> Int64 {
    2 * Int64(file.livePageCount) * Int64(file.pageSize) + 32 * 1_024 * 1_024
  }
}

/// What compaction asks of the device before its `VACUUM` (#1015).
package struct InstantStorageMaintenanceConditions: Hashable, Sendable {
  /// The thermal state is serious or critical.
  package var isHot: Bool
  package var isLowPowerModeEnabled: Bool
  /// The room left on the cache's volume, when the system says.
  package var availableDiskBytes: Int64?

  package init(isHot: Bool = false, isLowPowerModeEnabled: Bool = false, availableDiskBytes: Int64? = nil) {
    self.isHot = isHot
    self.isLowPowerModeEnabled = isLowPowerModeEnabled
    self.availableDiskBytes = availableDiskBytes
  }

  /// The device now: `ProcessInfo`'s thermal state and Low Power Mode, and the room on the cache's volume.
  package static func current(cacheURL: URL) -> Self {
    let processInfo = ProcessInfo.processInfo
    let isHot =
      switch processInfo.thermalState {
      case .serious, .critical: true
      default: false
      }
    let directory = cacheURL.deletingLastPathComponent()
    #if os(macOS) || os(iOS) || os(visionOS)
      let available = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
        .volumeAvailableCapacityForImportantUsage
    #else
      let available = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?
        .volumeAvailableCapacity.map(Int64.init)
    #endif
    return Self(isHot: isHot, isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled, availableDiskBytes: available)
  }
}
