import Foundation

/// Experiment-only switches for the TS-vs-Swift measurement (plan 2026-09-30-ts-parity, #306).
///
/// Each one is read once from the environment. Unset, the library behaves exactly as without this
/// file. This is a measurement tool on a measurement branch, not a configuration surface.
enum InstantMeasurementSwitches {
  /// `INSTANT_SWIFT_DATA_EXPERIMENT_SQLITE_SYNCHRONOUS`: `FULL`, `NORMAL`, or `OFF`. Unset keeps SQLite's
  /// default for the store's WAL connection (FULL: the WAL is synced on every commit).
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
