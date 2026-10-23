// History
// 2026-10-23  #1021  Created. The bundle's tests made their stores in the temp dir and most never removed them: a day
//                    of agents' runs had left 42 GB there and filled the Mac mini's disk. The biggest makers now
//                    register their stores here, and the process removes them when it exits.

import Foundation

/// Stores a test keeps in the temp dir, removed when the test process exits (#1021).
///
/// Nothing is removed while the bundle runs: a runtime's background work can still read its SQLite file after its test
/// returns, and a store deleted under it reports a "disk I/O error" (SQLite 6922, the file gone) as an issue. A run
/// that is killed leaves its stores behind; `scripts/known-failing-tests.sh` sweeps those after the next run.
enum InstantTestScratch {
  /// A new, empty directory named `<prefix>-<UUID>` in the temp dir.
  static func directory(_ prefix: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    registry.add([directory])
    return directory
  }

  /// `url`, a SQLite file in the temp dir, removed with its `-wal`, `-shm` and `-journal` files.
  static func store(_ url: URL) -> URL {
    registry.add(["", "-wal", "-shm", "-journal"].map { URL(fileURLWithPath: url.path + $0) })
    return url
  }

  fileprivate static let registry = InstantTestScratchRegistry()
}

// SAFETY: `lock` protects `paths` and `installedExitHandler`; tests on any thread register, and the exit handler reads.
private final class InstantTestScratchRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var paths: [URL] = []
  private var installedExitHandler = false

  func add(_ urls: [URL]) {
    let installs = lock.withLock { () -> Bool in
      paths.append(contentsOf: urls)
      defer { installedExitHandler = true }
      return !installedExitHandler
    }
    if installs {
      atexit { InstantTestScratch.registry.removeAll() }
    }
  }

  func removeAll() {
    let urls = lock.withLock { () -> [URL] in
      defer { paths = [] }
      return paths
    }
    for url in urls {
      try? FileManager.default.removeItem(at: url)
    }
  }
}
