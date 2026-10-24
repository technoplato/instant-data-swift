// History:
// - 2026-10-24: what SQLite asks the file system to do, for the storage audit's exercises (#1076): a VFS shim that
//   counts write calls and bytes, syncs, reads and truncates per kind of file, the page behind every frame the
//   write-ahead log takes and every page a checkpoint copies, and the b-tree each of those pages belongs to.

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
  /// Times the write-ahead log started over at its first frame (SQLite wrote its 32-byte header).
  var walRestarts = 0
  /// Files SQLite deleted: temporary files, journals, a write-ahead log at close.
  var deletes = 0
  /// The page size the write-ahead log's header names (4,096 until a header is seen).
  var pageSize = 4_096

  subscript(kind: StorageIOFileKind) -> StorageIOCounts { files[kind] ?? StorageIOCounts() }

  var walFrames: Int { walFramesByPage.values.reduce(0, +) }
  var databasePagesWritten: Int { databaseWritesByPage.values.reduce(0, +) }
  var bytesWritten: Int { files.values.reduce(0) { $0 + $1.bytesWritten } }
  var syncs: Int { files.values.reduce(0) { $0 + $1.syncs } }

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
  static func watch(directory: URL?) {
    storageIOShimState.withLock { $0.pathPrefix = directory?.standardizedFileURL.path }
  }

  static func snapshot() -> StorageIOSnapshot {
    storageIOShimState.withLock { $0.snapshot }
  }
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
}

private let storageIOShimState = OSAllocatedUnfairLock(initialState: StorageIOShimState())

/// The shim's own header at the start of each file SQLite allocates for it; the system VFS's file follows it.
/// `base` must stay first: SQLite reads `pMethods` at offset 0.
private struct StorageIOShimFile {
  var base: sqlite3_file
  var real: UnsafeMutablePointer<sqlite3_file>
  var kind: StorageIOFileKind
  var counted: Bool
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
    guard header.counted else { return }
    let kind = header.kind
    storageIOShimState.withLockUnchecked { state in
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
    guard header.counted else { return }
    let kind = header.kind
    let bytes = buffer?.assumingMemoryBound(to: UInt8.self)
    let length = Int64(amount)
    storageIOShimState.withLockUnchecked { state in
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
      let counted = storageIOShimState.withLock { state in
        guard let prefix = state.pathPrefix, let path else { return true }
        return URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(prefix)
      }
      let header = raw.bindMemory(to: StorageIOShimFile.self, capacity: 1)
      header.initialize(
        to: StorageIOShimFile(
          base: sqlite3_file(pMethods: nil),
          real: realFile,
          kind: StorageIOFileKind(openFlags: flags),
          counted: counted
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
        if let prefix = state.pathPrefix, let path,
          !URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(prefix)
        {
          return
        }
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
      StorageIOShim.count(file) {
        $0.reads += 1
        $0.bytesRead += Int(amount)
      }
      return result
    }
    methods.xWrite = { file, buffer, amount, offset in
      let result = StorageIOShim.realMethods(file).xWrite(StorageIOShim.real(file), buffer, amount, offset)
      if result == SQLITE_OK { StorageIOShim.countWrite(file, buffer, amount, offset) }
      return result
    }
    methods.xTruncate = { file, size in
      StorageIOShim.count(file) { $0.truncates += 1 }
      return StorageIOShim.realMethods(file).xTruncate(StorageIOShim.real(file), size)
    }
    methods.xSync = { file, flags in
      StorageIOShim.count(file) {
        $0.syncs += 1
        if flags & 0x0F == SQLITE_SYNC_FULL { $0.fullSyncs += 1 }
      }
      return StorageIOShim.realMethods(file).xSync(StorageIOShim.real(file), flags)
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
