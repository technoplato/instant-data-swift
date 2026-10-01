import Foundation

/// Experiment-only switches for the TS-vs-Swift measurement (plan 2026-09-30-ts-parity, #306).
///
/// Each one is read once from the environment. Unset, the library behaves exactly as without this
/// file. This is a measurement tool on a measurement branch, not a configuration surface.
enum InstantMeasurementSwitches {
  /// `INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_SYNCHRONOUS`: `FULL`, `NORMAL`, or `OFF`. Unset keeps SQLite's
  /// default for the store's WAL connection. Apple's build sets DEFAULT_WAL_SYNCHRONOUS=1, so that default is
  /// already NORMAL (no fsync per commit; checkpoints still sync).
  static let sqliteSynchronous: String? = {
    guard let value = ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_SYNCHRONOUS"]?
      .uppercased(), ["FULL", "NORMAL", "OFF", "EXTRA"].contains(value)
    else { return nil }
    return value
  }()

  /// `INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_CACHE_SIZE`: an integer for `PRAGMA cache_size` (SQLite's
  /// default is -2000, about 2 MiB). Unset keeps the library's `cache_size = 0`.
  static let sqliteCacheSize: Int? = {
    ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_CACHE_SIZE"].flatMap(Int.init)
  }()

  /// `INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_WAL_AUTOCHECKPOINT`: pages for `PRAGMA wal_autocheckpoint`. Apple's
  /// SQLite defaults to 1,000, and its checkpoints use F_FULLFSYNC (`checkpoint_fullfsync = 1`); a commit that
  /// crosses the threshold runs the checkpoint inline, under whatever gate the commit holds. 0 disables it.
  static let sqliteWALAutocheckpoint: Int? = {
    ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_WAL_AUTOCHECKPOINT"].flatMap(Int.init)
  }()

  /// `INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_CHECKPOINT_FULLFSYNC`: `0` or `1` for `PRAGMA checkpoint_fullfsync`.
  static let sqliteCheckpointFullFsync: Int? = {
    ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_CHECKPOINT_FULLFSYNC"].flatMap(Int.init)
  }()

  /// `INSTANT_SWIFT_DATA_EXPERIMENT_CORE_VERSION`: when set (for example `v1.0.49`), the init frame also
  /// advertises `@instantdb/core` at that version, as the TypeScript client does. The server keys its
  /// session features on that entry (session.clj `get-supported-features`): above v0.20.4 it stops
  /// sending every attribute with every refresh-ok, and stops sending refresh-ok frames whose results
  /// did not change.
  static let initVersions: [String: String] = {
    var versions = ["InstantDB-Swift": "0.1.0"]
    if let core = ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_EXPERIMENT_CORE_VERSION"], !core.isEmpty {
      versions["@instantdb/core"] = core
    }
    return versions
  }()
}
