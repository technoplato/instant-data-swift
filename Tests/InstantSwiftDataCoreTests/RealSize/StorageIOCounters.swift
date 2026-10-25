// History:
// - 2026-10-24: what SQLite asks the file system to do, for the storage audit's exercises (#1076): a VFS shim that
//   counts write calls and bytes, syncs, reads and truncates per kind of file, the page behind every frame the
//   write-ahead log takes and every page a checkpoint copies, and the b-tree each of those pages belongs to.
// - 2026-10-24: the page behind every read of the database file too (#1076): on the phone-shaped store a write read
//   about 416 MB of it, and the b-tree those reads land on names the statement to look at. And the time each sync
//   takes: an hour of recording asked for about 1,040 full syncs, and their cost is the time a commit waits for the
//   drive.
// - 2026-10-24: a journal of each watched file's writes since its last full sync, with the bytes each replaced, so a
//   test can open the files as a power loss would leave them (#1118: the store's log now holds up to 4,000 frames
//   between checkpoints, and a power loss can take what the last checkpoint did not sync).
// - 2026-10-25: whether a file counts is asked at each call from the watched directory, not once at open, so a store
//   another test left open does not count in a later watch (#1115's per-b-tree test shares the process).

import Foundation
import SQLite3
import os

/// The kind of file SQLite opened, from the flags it opened it with (#1076).
enum StorageIOFileKind: String, CaseIterable, Comparable, Sendable {
  /// A database file: the store itself.
  case database = "db"
  /// The write-ahead log beside it (`-wal`). In WAL mode every committed page is written here first.
  case wal
  /// A rollback journal or a super-journal. The store runs in WAL mode, so this stays empty.
  case journal
  /// A statement journal: a statement inside a transaction that may have to undo its own changes.
  case statementJournal = "stmtjournal"
  /// Temporary tables and their indexes, and the transient files a sort or `VACUUM` writes.
  case temporary = "temp"
  case other

  init(openFlags: Int32) {
    if openFlags & SQLITE_OPEN_MAIN_DB != 0 {
      self = .database
    } else if openFlags & SQLITE_OPEN_WAL != 0 {
      self = .wal
    } else if openFlags & (SQLITE_OPEN_MAIN_JOURNAL | SQLITE_OPEN_SUPER_JOURNAL) != 0 {
      self = .journal
    } else if openFlags & SQLITE_OPEN_SUBJOURNAL != 0 {
      self = .statementJournal
    } else if openFlags & (SQLITE_OPEN_TEMP_DB | SQLITE_OPEN_TEMP_JOURNAL | SQLITE_OPEN_TRANSIENT_DB) != 0 {
      self = .temporary
    } else {
      self = .other
    }
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}

/// What SQLite asked one kind of file for (#1076).
struct StorageIOCounts: Equatable, Sendable {
  var opens = 0
  var writes = 0
  var bytesWritten = 0
  var reads = 0
  var bytesRead = 0
  /// `xSync` calls: each one is an `fsync`, or an `F_FULLFSYNC` when SQLite asks for a full sync.
  var syncs = 0
  /// The syncs SQLite asked to be full: on Apple's file systems, `F_FULLFSYNC` flushes the drive's own cache too.
  var fullSyncs = 0
  /// Time spent inside the syncs: the caller (a commit or a checkpoint) waits this long for the drive.
  var syncNanoseconds: UInt64 = 0
  var truncates = 0

  func subtracting(_ earlier: Self) -> Self {
    Self(
      opens: opens - earlier.opens,
      writes: writes - earlier.writes,
      bytesWritten: bytesWritten - earlier.bytesWritten,
      reads: reads - earlier.reads,
      bytesRead: bytesRead - earlier.bytesRead,
      syncs: syncs - earlier.syncs,
      fullSyncs: fullSyncs - earlier.fullSyncs,
      syncNanoseconds: syncNanoseconds &- earlier.syncNanoseconds,
      truncates: truncates - earlier.truncates
    )
  }
}

/// Everything ``StorageIOCounters`` counted, or what it counted between two snapshots (#1076).
struct StorageIOSnapshot: Equatable, Sendable {
  var files: [StorageIOFileKind: StorageIOCounts] = [:]
  /// Frames the write-ahead log took, by the page each frame holds. A page that changes in ten transactions takes ten
  /// frames, and each frame is a whole page however few of its bytes changed.
  var walFramesByPage: [UInt32: Int] = [:]
  /// Pages a checkpoint copied from the write-ahead log into the database file, by page.
  var databaseWritesByPage: [UInt32: Int] = [:]
  /// Whole pages read from the database file, by page: what the page cache did not hold. A page the write-ahead log
  /// holds is read from the log instead, and is not counted here.
  var databaseReadsByPage: [UInt32: Int] = [:]
  /// Times the write-ahead log started over at its first frame (SQLite wrote its 32-byte header).
  var walRestarts = 0
  /// Files SQLite deleted: temporary files, journals, a write-ahead log at close.
  var deletes = 0
  /// The page size the write-ahead log's header names (4,096 until a header is seen).
  var pageSize = 4_096

  subscript(kind: StorageIOFileKind) -> StorageIOCounts { files[kind] ?? StorageIOCounts() }

  var walFrames: Int { walFramesByPage.values.reduce(0, +) }
  var databasePagesWritten: Int { databaseWritesByPage.values.reduce(0, +) }
  var databasePagesRead: Int { databaseReadsByPage.values.reduce(0, +) }
  var bytesWritten: Int { files.values.reduce(0) { $0 + $1.bytesWritten } }
  var syncs: Int { files.values.reduce(0) { $0 + $1.syncs } }
  var fullSyncs: Int { files.values.reduce(0) { $0 + $1.fullSyncs } }
  var syncNanoseconds: UInt64 { files.values.reduce(0) { $0 + $1.syncNanoseconds } }

  func subtracting(_ earlier: Self) -> Self {
    var files: [StorageIOFileKind: StorageIOCounts] = [:]
    for (kind, counts) in self.files {
      let delta = counts.subtracting(earlier[kind])
      if delta != StorageIOCounts() { files[kind] = delta }
    }
    return Self(
      files: files,
      walFramesByPage: Self.subtracting(walFramesByPage, earlier.walFramesByPage),
      databaseWritesByPage: Self.subtracting(databaseWritesByPage, earlier.databaseWritesByPage),
      databaseReadsByPage: Self.subtracting(databaseReadsByPage, earlier.databaseReadsByPage),
      walRestarts: walRestarts - earlier.walRestarts,
      deletes: deletes - earlier.deletes,
      pageSize: pageSize
    )
  }

  private static func subtracting(_ later: [UInt32: Int], _ earlier: [UInt32: Int]) -> [UInt32: Int] {
    var delta: [UInt32: Int] = [:]
    for (page, count) in later {
      let difference = count - (earlier[page] ?? 0)
      if difference > 0 { delta[page] = difference }
    }
    return delta
  }
}

/// What SQLite asks the file system to do, counted by a VFS shim registered in front of the system's own (#1076).
///
/// The store's own meter (`InstantStorageWriteMeter`) counts the pages each store call's transactions dirty. This
/// counts what reaches the files: write calls and bytes per kind of file, `fsync`s, truncates, the page behind each
/// write-ahead-log frame, and the pages each checkpoint copies into the database file. A pass-through: every call goes
/// to the system VFS unchanged, so the store behaves as it does on a device.
///
///     StorageIOCounters.install(asDefault: true)   // before the runtime opens its store
///     let before = StorageIOCounters.snapshot()
///     try await runtime.transact(...)
///     let cost = StorageIOCounters.snapshot().subtracting(before)
enum StorageIOCounters {
  /// The shim's VFS name, for `sqlite3_open_v2`'s last argument when it is not the default.
  static let vfsName = "instant-storage-io"

  /// Registers the shim. With `asDefault`, every connection opened afterwards goes through it, the runtime's included.
  static func install(asDefault: Bool) {
    StorageIOShim.install(asDefault: asDefault)
  }

  /// Counts only files under `directory` (temporary files, which have no name, always count). `nil` counts every file.
  ///
  /// SQLite opens a file by its resolved path, and the temporary directory is a symbolic link (`/var` is
  /// `/private/var`), so the prefix is the directory's real path; the first run compared the link and counted nothing.
  static func watch(directory: URL?) {
    let prefix = directory.map { directory -> String in
      guard let resolved = realpath(directory.path, nil) else { return directory.standardizedFileURL.path }
      defer { free(resolved) }
      return String(cString: resolved)
    }
    storageIOShimState.withLock { $0.pathPrefix = prefix }
  }

  static func snapshot() -> StorageIOSnapshot {
    storageIOShimState.withLock { $0.snapshot }
  }

  /// Journals every database and write-ahead log under `directory` that a connection opens through the shim from now
  /// on: each write and truncate since the file's last full sync, with the bytes it replaced, so
  /// ``powerLossImage(of:in:keepingUnsyncedWrites:)`` can take them back (#1118). `nil` stops and forgets the journals.
  static func journalUnsyncedWrites(under directory: URL?) {
    StorageIOJournal.shared.watch(directory: directory)
  }

  /// What the journal holds for `store` and its write-ahead log now.
  static func unsyncedWrites(of store: URL) -> StorageIOUnsyncedWrites {
    StorageIOJournal.shared.unsyncedWrites(of: store)
  }

  /// A copy of `store` and its write-ahead log in `directory` as a power loss would leave them: each file as its last
  /// full sync left it, plus the first `kept` of the writes and truncates after that sync, as a drive that wrote them
  /// in order and lost power partway (#1118). Apple's drives make only `F_FULLFSYNC` durable, so a plain sync is not
  /// a barrier here. No `-shm`: SQLite rebuilds the log's index when it opens the copy. `store` is not touched.
  static func powerLossImage(of store: URL, in directory: URL, keepingUnsyncedWrites kept: Int = 0) throws -> URL {
    try StorageIOJournal.shared.image(of: store, in: directory, keeping: kept)
  }
}

/// The journal's count for one store and its log, since each file's last full sync (#1118).
struct StorageIOUnsyncedWrites: Equatable, Sendable {
  var databaseWrites = 0
  var databaseBytes = 0
  var walWrites = 0
  var walBytes = 0
  /// Full syncs each file has had since it was first journaled.
  var databaseFullSyncs = 0
  var walFullSyncs = 0
  /// Syncs that were not full, on either file: on Apple's drives they do not make a write durable.
  var partialSyncs = 0
}

/// The b-tree each page of a store belongs to, read from SQLite's `dbstat` table on a connection of its own that
/// bypasses the shim, so reading the map is not counted (#1076).
struct StorageIOPageMap: Sendable {
  /// The table or index each page belongs to; an overflow page belongs to the b-tree whose row spilled onto it.
  var nameByPage: [UInt32: String]
  /// Pages each table and index holds, and the bytes those pages leave unused.
  var pagesByName: [String: (pages: Int, unusedBytes: Int)]

  static func read(store: URL) throws -> StorageIOPageMap {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(store.path, &connection, SQLITE_OPEN_READONLY, "unix") == SQLITE_OK, let connection else {
      sqlite3_close_v2(connection)
      throw StorageIOError("open \(store.lastPathComponent) for its page map")
    }
    defer { sqlite3_close_v2(connection) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, "SELECT name, pageno, unused FROM dbstat", -1, &statement, nil) == SQLITE_OK
    else { throw StorageIOError(String(cString: sqlite3_errmsg(connection))) }
    defer { sqlite3_finalize(statement) }
    var nameByPage: [UInt32: String] = [:]
    var pagesByName: [String: (pages: Int, unusedBytes: Int)] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "(unnamed)"
      nameByPage[UInt32(sqlite3_column_int64(statement, 1))] = name
      var entry = pagesByName[name] ?? (0, 0)
      entry.pages += 1
      entry.unusedBytes += Int(sqlite3_column_int64(statement, 2))
      pagesByName[name] = entry
    }
    return StorageIOPageMap(nameByPage: nameByPage, pagesByName: pagesByName)
  }

  /// Frames or page writes by the b-tree they belong to; a page no b-tree holds now is `(free or other)`: a freelist
  /// page, or a page a later transaction freed.
  func byName(_ countsByPage: [UInt32: Int]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for (page, count) in countsByPage {
      counts[nameByPage[page] ?? "(free or other)", default: 0] += count
    }
    return counts
  }
}

struct StorageIOError: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}

/// One stable line per measure, `STORAGEIO <exercise> <step> key=value ...`, keys in the order given, so the same
/// exercise run before and after a fix diffs line by line (#1076).
struct StorageIOLine {
  var exercise: String
  var step: String
  var fields: [(String, String)] = []

  init(_ exercise: String, _ step: String) {
    self.exercise = exercise
    self.step = step
  }

  mutating func add(_ key: String, _ value: Int) { fields.append((key, String(value))) }
  mutating func add(_ key: String, _ value: Double, digits: Int = 1) {
    fields.append((key, String(format: "%.\(digits)f", value)))
  }
  mutating func add(_ key: String, _ value: String) { fields.append((key, value)) }

  /// Write bytes, calls and syncs per kind of file, divided by `per` (the logical writes the interval held).
  mutating func add(io: StorageIOSnapshot, per count: Int = 1) {
    let divisor = Double(max(1, count))
    for kind in StorageIOFileKind.allCases {
      let counts = io[kind]
      guard counts != StorageIOCounts() else { continue }
      add("\(kind.rawValue)WriteKB", Double(counts.bytesWritten) / 1_024 / divisor)
      add("\(kind.rawValue)Writes", Double(counts.writes) / divisor)
      add("\(kind.rawValue)Syncs", Double(counts.syncs) / divisor, digits: 3)
      if counts.fullSyncs > 0 { add("\(kind.rawValue)FullSyncs", Double(counts.fullSyncs) / divisor, digits: 3) }
      if counts.syncs > 0 {
        add("\(kind.rawValue)SyncMs", Double(counts.syncNanoseconds) / 1_000_000 / divisor, digits: 3)
      }
      if counts.truncates > 0 { add("\(kind.rawValue)Truncates", Double(counts.truncates) / divisor, digits: 3) }
      if counts.bytesRead > 0 { add("\(kind.rawValue)ReadKB", Double(counts.bytesRead) / 1_024 / divisor) }
    }
    add("walFrames", Double(io.walFrames) / divisor)
    add("walDistinctPages", Double(io.walFramesByPage.count) / divisor)
    add("checkpointPages", Double(io.databasePagesWritten) / divisor)
    add("walRestarts", Double(io.walRestarts) / divisor, digits: 3)
  }

  var text: String {
    (["STORAGEIO", exercise, step] + fields.map { "\($0.0)=\($0.1)" }).joined(separator: " ")
  }

  func print() { Swift.print(text) }
}

// MARK: - The shim

private struct StorageIOShimState: Sendable {
  var snapshot = StorageIOSnapshot()
  var pathPrefix: String?
  /// Every path a file was opened at, so each call can ask whether its file is under the watched directory now.
  var paths: [String] = []
  var pathSlots: [String: Int] = [:]

  mutating func slot(for path: String?) -> Int {
    guard let path else { return -1 }
    if let slot = pathSlots[path] { return slot }
    paths.append(path)
    pathSlots[path] = paths.count - 1
    return paths.count - 1
  }

  /// Whether a file's calls count now: a file with no name (a temporary one) always does, a named one when nothing is
  /// watched or it is under the watched directory. Asked at each call, not once at open (#1115): a store another test
  /// opened before a watch began must not count in it.
  func counts(_ slot: Int) -> Bool {
    guard let pathPrefix, slot >= 0 else { return true }
    return paths[slot].hasPrefix(pathPrefix)
  }
}

private let storageIOShimState = OSAllocatedUnfairLock(initialState: StorageIOShimState())

/// The shim's own header at the start of each file SQLite allocates for it; the system VFS's file follows it.
/// `base` must stay first: SQLite reads `pMethods` at offset 0.
private struct StorageIOShimFile {
  var base: sqlite3_file
  var real: UnsafeMutablePointer<sqlite3_file>
  var kind: StorageIOFileKind
  /// The file's path in ``StorageIOShimState/paths``, or -1 for a file with no name.
  var pathSlot: Int
  /// The file's journal (``StorageIOJournal``), or -1 when it is not journaled.
  var journal: Int
}

/// Every write and truncate since each watched file's last full sync, with the bytes each one replaced, so an image
/// of the files can take them back as a power loss would (#1118). A file's journal is its path's: the writer and any
/// reader of one file share it. The lock is held across the real call, so an image never sees half of one.
private final class StorageIOJournal: @unchecked Sendable {
  static let shared = StorageIOJournal()

  enum Entry {
    /// A write at `offset` over `replaced` (the bytes there before, those inside the old size) in a file of
    /// `sizeBefore` bytes.
    case write(offset: Int64, length: Int, replaced: [UInt8], sizeBefore: Int64)
    /// A truncate to `size` of a file of `sizeBefore` bytes, which removed `removed`.
    case truncate(size: Int64, removed: [UInt8], sizeBefore: Int64)
  }

  struct File {
    var path: String
    var kind: StorageIOFileKind
    var entries: [Entry] = []
    var fullSyncs = 0
    var partialSyncs = 0
  }

  // SAFETY: `lock` guards `prefix` and `files`; SQLite calls the shim from any thread.
  private let lock = NSLock()
  private var prefix: String?
  private var files: [File] = []

  /// A file keeps its journal's index while it is open, so watching another directory empties the journals and keeps
  /// them.
  func watch(directory: URL?) {
    lock.withLock {
      prefix = directory.map { Self.resolved($0.path) }
      for index in files.indices { files[index].entries = [] }
    }
  }

  /// The journal a file opened at `path` writes to: its path's, made on first use; -1 for a file not watched.
  func journal(path: String?, kind: StorageIOFileKind) -> Int {
    guard kind == .database || kind == .wal, let path else { return -1 }
    return lock.withLock {
      guard let prefix, path.hasPrefix(prefix) else { return -1 }
      if let index = files.firstIndex(where: { $0.path == path }) { return index }
      files.append(File(path: path, kind: kind))
      return files.count - 1
    }
  }

  func write(
    _ journal: Int,
    _ real: UnsafeMutablePointer<sqlite3_file>,
    _ buffer: UnsafeRawPointer?,
    _ amount: Int32,
    _ offset: sqlite3_int64
  ) -> Int32 {
    lock.withLock {
      let methods = real.pointee.pMethods.pointee
      let size = Self.size(of: real)
      let replaced = Self.read(real, from: offset, to: min(offset + Int64(amount), size))
      let result = methods.xWrite(real, buffer, amount, offset)
      if result == SQLITE_OK, files.indices.contains(journal) {
        files[journal].entries.append(.write(offset: offset, length: Int(amount), replaced: replaced, sizeBefore: size))
      }
      return result
    }
  }

  func truncate(_ journal: Int, _ real: UnsafeMutablePointer<sqlite3_file>, _ newSize: sqlite3_int64) -> Int32 {
    lock.withLock {
      let size = Self.size(of: real)
      let removed = Self.read(real, from: newSize, to: size)
      let result = real.pointee.pMethods.pointee.xTruncate(real, newSize)
      if result == SQLITE_OK, files.indices.contains(journal) {
        files[journal].entries.append(.truncate(size: newSize, removed: removed, sizeBefore: size))
      }
      return result
    }
  }

  /// A full sync makes everything before it durable, so the journal starts over; a plain one does not.
  func sync(_ journal: Int, _ real: UnsafeMutablePointer<sqlite3_file>, _ flags: Int32) -> Int32 {
    lock.withLock {
      let result = real.pointee.pMethods.pointee.xSync(real, flags)
      guard result == SQLITE_OK, files.indices.contains(journal) else { return result }
      if flags & 0x0F == SQLITE_SYNC_FULL {
        files[journal].entries = []
        files[journal].fullSyncs += 1
      } else {
        files[journal].partialSyncs += 1
      }
      return result
    }
  }

  func unsyncedWrites(of store: URL) -> StorageIOUnsyncedWrites {
    let database = Self.resolved(store.path)
    return lock.withLock {
      var counts = StorageIOUnsyncedWrites()
      for file in files where file.path == database || file.path == database + "-wal" {
        let bytes = file.entries.reduce(0) { total, entry in
          if case let .write(_, length, _, _) = entry { return total + length }
          return total
        }
        if file.kind == .wal {
          counts.walWrites = file.entries.count
          counts.walBytes = bytes
          counts.walFullSyncs = file.fullSyncs
        } else {
          counts.databaseWrites = file.entries.count
          counts.databaseBytes = bytes
          counts.databaseFullSyncs = file.fullSyncs
        }
        counts.partialSyncs += file.partialSyncs
      }
      return counts
    }
  }

  func image(of store: URL, in directory: URL, keeping kept: Int) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent(store.lastPathComponent)
    let database = Self.resolved(store.path)
    try lock.withLock {
      for suffix in ["", "-wal"] where FileManager.default.fileExists(atPath: store.path + suffix) {
        let copy = target.path + suffix
        try FileManager.default.copyItem(atPath: store.path + suffix, toPath: copy)
        let entries = files.first(where: { $0.path == database + suffix })?.entries ?? []
        let handle = try FileHandle(forUpdating: URL(fileURLWithPath: copy))
        defer { try? handle.close() }
        // Newest first, each one taken back, until only the first `kept` remain.
        for entry in entries.dropFirst(min(kept, entries.count)).reversed() {
          switch entry {
          case let .write(offset, _, replaced, sizeBefore):
            if !replaced.isEmpty {
              try handle.seek(toOffset: UInt64(offset))
              try handle.write(contentsOf: replaced)
            }
            if try handle.seekToEnd() > UInt64(sizeBefore) { try handle.truncate(atOffset: UInt64(sizeBefore)) }
          case let .truncate(size, removed, sizeBefore):
            if sizeBefore > size {
              try handle.seek(toOffset: UInt64(size))
              try handle.write(contentsOf: removed)
            } else {
              try handle.truncate(atOffset: UInt64(sizeBefore))
            }
          }
        }
      }
    }
    return target
  }

  private static func size(of real: UnsafeMutablePointer<sqlite3_file>) -> Int64 {
    var size: sqlite3_int64 = 0
    _ = real.pointee.pMethods.pointee.xFileSize(real, &size)
    return size
  }

  private static func read(_ real: UnsafeMutablePointer<sqlite3_file>, from start: Int64, to end: Int64) -> [UInt8] {
    guard end > start else { return [] }
    var bytes = [UInt8](repeating: 0, count: Int(end - start))
    _ = bytes.withUnsafeMutableBytes { buffer in
      real.pointee.pMethods.pointee.xRead(real, buffer.baseAddress, Int32(buffer.count), start)
    }
    return bytes
  }

  /// SQLite names a file by its resolved path, and the temporary directory is a symbolic link (`/var` is
  /// `/private/var`), so a path is compared with its directory resolved.
  static func resolved(_ path: String) -> String {
    let url = URL(fileURLWithPath: path)
    let directory = url.deletingLastPathComponent().path
    guard let real = realpath(directory, nil) else { return url.standardizedFileURL.path }
    defer { free(real) }
    return String(cString: real) + "/" + url.lastPathComponent
  }
}

private enum StorageIOShim {
  nonisolated(unsafe) static var realVFS: UnsafeMutablePointer<sqlite3_vfs>?
  nonisolated(unsafe) static var shimVFS: UnsafeMutablePointer<sqlite3_vfs>?
  nonisolated(unsafe) static var ioMethods: [UnsafeMutablePointer<sqlite3_io_methods>] = []
  static let installation = OSAllocatedUnfairLock(initialState: false)

  /// Where the system VFS's file starts in the bytes SQLite allocates for one of the shim's files.
  static let realFileOffset = (MemoryLayout<StorageIOShimFile>.stride + 15) & ~15

  static func install(asDefault: Bool) {
    installation.withLock { installed in
      if !installed {
        precondition(MemoryLayout<StorageIOShimFile>.offset(of: \StorageIOShimFile.base) == 0)
        guard let real = sqlite3_vfs_find("unix") ?? sqlite3_vfs_find(nil) else {
          preconditionFailure("SQLite has no default VFS")
        }
        realVFS = real
        ioMethods = (1...3).map { version in
          let methods = UnsafeMutablePointer<sqlite3_io_methods>.allocate(capacity: 1)
          methods.initialize(to: makeIOMethods(version: Int32(version)))
          return methods
        }
        let vfs = UnsafeMutablePointer<sqlite3_vfs>.allocate(capacity: 1)
        vfs.initialize(to: makeVFS(real: real))
        shimVFS = vfs
        installed = true
      }
      _ = sqlite3_vfs_register(shimVFS, asDefault ? 1 : 0)
    }
  }

  static func methods(matching version: Int32) -> UnsafePointer<sqlite3_io_methods> {
    UnsafePointer(ioMethods[Int(min(max(version, 1), 3)) - 1])
  }

  static func shim(_ file: UnsafeMutablePointer<sqlite3_file>?) -> UnsafeMutablePointer<StorageIOShimFile> {
    UnsafeMutableRawPointer(file!).assumingMemoryBound(to: StorageIOShimFile.self)
  }

  static func real(_ file: UnsafeMutablePointer<sqlite3_file>?) -> UnsafeMutablePointer<sqlite3_file> {
    shim(file).pointee.real
  }

  static func realMethods(_ file: UnsafeMutablePointer<sqlite3_file>?) -> sqlite3_io_methods {
    real(file).pointee.pMethods.pointee
  }

  static func count(_ file: UnsafeMutablePointer<sqlite3_file>?, _ update: (inout StorageIOCounts) -> Void) {
    let header = shim(file).pointee
    // A journaled file belongs to a power-loss test, not to a measurement.
    guard header.journal < 0 else { return }
    let kind = header.kind
    storageIOShimState.withLockUnchecked { state in
      guard state.counts(header.pathSlot) else { return }
      var counts = state.snapshot.files[kind] ?? StorageIOCounts()
      update(&counts)
      state.snapshot.files[kind] = counts
    }
  }

  static func bigEndian32(_ bytes: UnsafePointer<UInt8>) -> UInt32 {
    UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
  }

  /// Counts one write. For the write-ahead log it reads the page size off the log's 32-byte header and the page number
  /// off every 24-byte frame header the write holds; for the database file, the pages a checkpoint copies.
  ///
  /// Apple's SQLite writes a frame's header and its page in one 4,120-byte call, where SQLite's own `walWriteOneFrame`
  /// makes two; the first run of this shim, which looked only for 24-byte writes, saw no frames at all. So every frame
  /// boundary inside the write is read, whichever way the writes are cut.
  static func countWrite(
    _ file: UnsafeMutablePointer<sqlite3_file>?,
    _ buffer: UnsafeRawPointer?,
    _ amount: Int32,
    _ offset: sqlite3_int64
  ) {
    let header = shim(file).pointee
    guard header.journal < 0 else { return }
    let kind = header.kind
    let bytes = buffer?.assumingMemoryBound(to: UInt8.self)
    let length = Int64(amount)
    storageIOShimState.withLockUnchecked { state in
      guard state.counts(header.pathSlot) else { return }
      var counts = state.snapshot.files[kind] ?? StorageIOCounts()
      counts.writes += 1
      counts.bytesWritten += Int(amount)
      state.snapshot.files[kind] = counts
      switch kind {
      case .wal:
        guard let bytes else { return }
        var start = offset
        if offset == 0, length >= 32 {
          // The log's header: SQLite starts the log over at its first frame.
          let size = Int(bigEndian32(bytes + 8))
          state.snapshot.pageSize = size == 1 ? 65_536 : size
          state.snapshot.walRestarts += 1
          start = 32
        }
        guard start >= 32 else { return }
        let frameSize = Int64(state.snapshot.pageSize + 24)
        var frameStart = 32 + (start - 32 + frameSize - 1) / frameSize * frameSize
        while frameStart + 24 <= offset + length {
          state.snapshot.walFramesByPage[bigEndian32(bytes + Int(frameStart - offset)), default: 0] += 1
          frameStart += frameSize
        }
      case .database:
        let pageSize = Int64(state.snapshot.pageSize)
        guard offset % pageSize == 0, length % pageSize == 0 else { return }
        for page in 0..<(length / pageSize) {
          state.snapshot.databaseWritesByPage[UInt32(offset / pageSize + page + 1), default: 0] += 1
        }
      default:
        return
      }
    }
  }

  /// Counts one read, and for the database file the page a whole-page read fetched.
  static func countRead(_ file: UnsafeMutablePointer<sqlite3_file>?, _ amount: Int32, _ offset: sqlite3_int64) {
    let header = shim(file).pointee
    guard header.journal < 0 else { return }
    let kind = header.kind
    storageIOShimState.withLockUnchecked { state in
      guard state.counts(header.pathSlot) else { return }
      var counts = state.snapshot.files[kind] ?? StorageIOCounts()
      counts.reads += 1
      counts.bytesRead += Int(amount)
      state.snapshot.files[kind] = counts
      let pageSize = Int64(state.snapshot.pageSize)
      guard kind == .database, offset % pageSize == 0, Int64(amount) == pageSize else { return }
      state.snapshot.databaseReadsByPage[UInt32(offset / pageSize + 1), default: 0] += 1
    }
  }

  static func makeVFS(real: UnsafeMutablePointer<sqlite3_vfs>) -> sqlite3_vfs {
    var vfs = sqlite3_vfs()
    vfs.iVersion = real.pointee.iVersion
    vfs.szOsFile = Int32(realFileOffset) + real.pointee.szOsFile
    vfs.mxPathname = real.pointee.mxPathname
    vfs.zName = UnsafePointer(strdup(StorageIOCounters.vfsName))
    vfs.pAppData = nil
    vfs.xOpen = { _, name, file, flags, outFlags in
      guard let real = StorageIOShim.realVFS, let file else { return SQLITE_ERROR }
      let raw = UnsafeMutableRawPointer(file)
      let realFile = (raw + StorageIOShim.realFileOffset).bindMemory(to: sqlite3_file.self, capacity: 1)
      memset(realFile, 0, Int(real.pointee.szOsFile))
      let path = name.map { String(cString: $0) }
      let pathSlot = storageIOShimState.withLock { $0.slot(for: path) }
      let kind = StorageIOFileKind(openFlags: flags)
      let header = raw.bindMemory(to: StorageIOShimFile.self, capacity: 1)
      header.initialize(
        to: StorageIOShimFile(
          base: sqlite3_file(pMethods: nil),
          real: realFile,
          kind: kind,
          pathSlot: pathSlot,
          journal: StorageIOJournal.shared.journal(path: path, kind: kind)
        )
      )
      let result = real.pointee.xOpen(real, name, realFile, flags, outFlags)
      if let methods = realFile.pointee.pMethods {
        header.pointee.base.pMethods = StorageIOShim.methods(matching: methods.pointee.iVersion)
      }
      if result == SQLITE_OK { StorageIOShim.count(file) { $0.opens += 1 } }
      return result
    }
    vfs.xDelete = { _, name, syncDirectory in
      guard let real = StorageIOShim.realVFS else { return SQLITE_ERROR }
      let path = name.map { String(cString: $0) }
      storageIOShimState.withLock { state in
        if let prefix = state.pathPrefix, let path, !path.hasPrefix(prefix) { return }
        state.snapshot.deletes += 1
      }
      return real.pointee.xDelete(real, name, syncDirectory)
    }
    vfs.xAccess = { _, name, flags, out in
      StorageIOShim.realVFS!.pointee.xAccess(StorageIOShim.realVFS, name, flags, out)
    }
    vfs.xFullPathname = { _, name, count, out in
      StorageIOShim.realVFS!.pointee.xFullPathname(StorageIOShim.realVFS, name, count, out)
    }
    vfs.xDlOpen = { _, name in StorageIOShim.realVFS!.pointee.xDlOpen(StorageIOShim.realVFS, name) }
    vfs.xDlError = { _, count, out in StorageIOShim.realVFS!.pointee.xDlError(StorageIOShim.realVFS, count, out) }
    vfs.xDlSym = { _, handle, symbol in
      StorageIOShim.realVFS!.pointee.xDlSym(StorageIOShim.realVFS, handle, symbol)
    }
    vfs.xDlClose = { _, handle in StorageIOShim.realVFS!.pointee.xDlClose(StorageIOShim.realVFS, handle) }
    vfs.xRandomness = { _, count, out in
      StorageIOShim.realVFS!.pointee.xRandomness(StorageIOShim.realVFS, count, out)
    }
    vfs.xSleep = { _, microseconds in StorageIOShim.realVFS!.pointee.xSleep(StorageIOShim.realVFS, microseconds) }
    vfs.xCurrentTime = { _, out in StorageIOShim.realVFS!.pointee.xCurrentTime(StorageIOShim.realVFS, out) }
    vfs.xGetLastError = { _, count, out in
      StorageIOShim.realVFS!.pointee.xGetLastError(StorageIOShim.realVFS, count, out)
    }
    if real.pointee.iVersion >= 2 {
      vfs.xCurrentTimeInt64 = { _, out in
        StorageIOShim.realVFS!.pointee.xCurrentTimeInt64(StorageIOShim.realVFS, out)
      }
    }
    if real.pointee.iVersion >= 3 {
      vfs.xSetSystemCall = { _, name, pointer in
        StorageIOShim.realVFS!.pointee.xSetSystemCall(StorageIOShim.realVFS, name, pointer)
      }
      vfs.xGetSystemCall = { _, name in
        StorageIOShim.realVFS!.pointee.xGetSystemCall(StorageIOShim.realVFS, name)
      }
      vfs.xNextSystemCall = { _, name in
        StorageIOShim.realVFS!.pointee.xNextSystemCall(StorageIOShim.realVFS, name)
      }
    }
    return vfs
  }

  static func makeIOMethods(version: Int32) -> sqlite3_io_methods {
    var methods = sqlite3_io_methods()
    methods.iVersion = version
    methods.xClose = { file in
      let real = StorageIOShim.real(file)
      return real.pointee.pMethods.pointee.xClose(real)
    }
    methods.xRead = { file, buffer, amount, offset in
      let result = StorageIOShim.realMethods(file).xRead(StorageIOShim.real(file), buffer, amount, offset)
      StorageIOShim.countRead(file, amount, offset)
      return result
    }
    methods.xWrite = { file, buffer, amount, offset in
      let journal = StorageIOShim.shim(file).pointee.journal
      let result =
        journal >= 0
        ? StorageIOJournal.shared.write(journal, StorageIOShim.real(file), buffer, amount, offset)
        : StorageIOShim.realMethods(file).xWrite(StorageIOShim.real(file), buffer, amount, offset)
      if result == SQLITE_OK { StorageIOShim.countWrite(file, buffer, amount, offset) }
      return result
    }
    methods.xTruncate = { file, size in
      StorageIOShim.count(file) { $0.truncates += 1 }
      let journal = StorageIOShim.shim(file).pointee.journal
      return journal >= 0
        ? StorageIOJournal.shared.truncate(journal, StorageIOShim.real(file), size)
        : StorageIOShim.realMethods(file).xTruncate(StorageIOShim.real(file), size)
    }
    methods.xSync = { file, flags in
      let started = DispatchTime.now().uptimeNanoseconds
      let journal = StorageIOShim.shim(file).pointee.journal
      let result =
        journal >= 0
        ? StorageIOJournal.shared.sync(journal, StorageIOShim.real(file), flags)
        : StorageIOShim.realMethods(file).xSync(StorageIOShim.real(file), flags)
      let elapsed = DispatchTime.now().uptimeNanoseconds &- started
      StorageIOShim.count(file) {
        $0.syncs += 1
        if flags & 0x0F == SQLITE_SYNC_FULL { $0.fullSyncs += 1 }
        $0.syncNanoseconds &+= elapsed
      }
      return result
    }
    methods.xFileSize = { file, size in
      StorageIOShim.realMethods(file).xFileSize(StorageIOShim.real(file), size)
    }
    methods.xLock = { file, lock in StorageIOShim.realMethods(file).xLock(StorageIOShim.real(file), lock) }
    methods.xUnlock = { file, lock in StorageIOShim.realMethods(file).xUnlock(StorageIOShim.real(file), lock) }
    methods.xCheckReservedLock = { file, out in
      StorageIOShim.realMethods(file).xCheckReservedLock(StorageIOShim.real(file), out)
    }
    methods.xFileControl = { file, operation, argument in
      StorageIOShim.realMethods(file).xFileControl(StorageIOShim.real(file), operation, argument)
    }
    methods.xSectorSize = { file in StorageIOShim.realMethods(file).xSectorSize(StorageIOShim.real(file)) }
    methods.xDeviceCharacteristics = { file in
      StorageIOShim.realMethods(file).xDeviceCharacteristics(StorageIOShim.real(file))
    }
    if version >= 2 {
      methods.xShmMap = { file, region, size, extend, out in
        StorageIOShim.realMethods(file).xShmMap(StorageIOShim.real(file), region, size, extend, out)
      }
      methods.xShmLock = { file, offset, count, flags in
        StorageIOShim.realMethods(file).xShmLock(StorageIOShim.real(file), offset, count, flags)
      }
      methods.xShmBarrier = { file in StorageIOShim.realMethods(file).xShmBarrier(StorageIOShim.real(file)) }
      methods.xShmUnmap = { file, deleteFlag in
        StorageIOShim.realMethods(file).xShmUnmap(StorageIOShim.real(file), deleteFlag)
      }
    }
    if version >= 3 {
      methods.xFetch = { file, offset, amount, out in
        StorageIOShim.realMethods(file).xFetch(StorageIOShim.real(file), offset, amount, out)
      }
      methods.xUnfetch = { file, offset, pointer in
        StorageIOShim.realMethods(file).xUnfetch(StorageIOShim.real(file), offset, pointer)
      }
    }
    return methods
  }
}
