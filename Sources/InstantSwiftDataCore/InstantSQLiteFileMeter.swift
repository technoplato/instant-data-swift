import Foundation
import SQLite3
import os

// History:
// - 2026-10-27: what SQLite writes to each kind of file the store opens (#1245). On one device a recording hour wrote
//   3.31 GB, and 0.80 GB of it no meter named: the store's write meter counts the pages each store call writes to the
//   write-ahead log, not a checkpoint's copies into the database file, the temporary database or its journal. The
//   storage audit's test shim (#1076, `StorageIOCounters`) showed the method; this is its production part: counts
//   only, no per-page maps, no journal, one lock and a few additions per call.

/// What SQLite writes to each kind of file the store opens, counted by a pass-through VFS in front of the system's
/// (#1245).
///
/// Every connection the store opens (its writer and its readers) opens through the meter's VFS, so SQLite's own files
/// for it count too: the write-ahead log, a checkpoint's copies into the database file, the temporary database and its
/// journal, a statement journal, a sort's transient file. Each call goes to the system's file unchanged; the meter
/// adds the bytes to its kind's counts under one lock, and allocates nothing.
///
///     let before = InstantSQLiteFileMeter.snapshot()
///     // ... a minute of writes
///     let minute = InstantSQLiteFileMeter.snapshot().subtracting(before)
///     minute[.database].bytesWritten  // what checkpoints copied into the database file
public enum InstantSQLiteFileMeter {
  /// The name the meter's VFS registers under.
  public static let vfsName = "instant-metered"

  /// Everything the meter counted since the process started.
  public static func snapshot() -> InstantSQLiteFileSnapshot {
    let counts = state.withLock { $0 }
    var files: [InstantSQLiteFileSnapshot.Kind: InstantSQLiteFileSnapshot.Counts] = [:]
    for (index, kind) in InstantSQLiteFileSnapshot.Kind.allCases.enumerated() where counts[index] != .init() {
      files[kind] = counts[index]
    }
    return InstantSQLiteFileSnapshot(files: files)
  }

  /// Registers the meter's VFS once and returns its name, or nil when SQLite has no system VFS to put it in front of
  /// (a connection then opens through SQLite's default, uncounted).
  static func registeredVFSName() -> String? {
    MeteredVFS.install() ? vfsName : nil
  }

  /// Each kind's counts, by ``InstantSQLiteFileSnapshot/Kind``'s position in `allCases`: an array of fixed length,
  /// so a count changes in place and allocates nothing.
  fileprivate static let state = OSAllocatedUnfairLock(
    initialState: [InstantSQLiteFileSnapshot.Counts](
      repeating: .init(),
      count: InstantSQLiteFileSnapshot.Kind.allCases.count
    )
  )

  fileprivate static func count(_ kind: Int, _ update: (inout InstantSQLiteFileSnapshot.Counts) -> Void) {
    // Unchecked: `update` runs at once, inside the lock, on this thread; it is not kept or sent anywhere.
    state.withLockUnchecked { update(&$0[kind]) }
  }
}

/// What ``InstantSQLiteFileMeter`` counted, by kind of file (#1245).
public struct InstantSQLiteFileSnapshot: Sendable, Equatable {
  /// The kind of file SQLite opened, from the flags it opened it with.
  public enum Kind: String, CaseIterable, Sendable {
    /// The store's database file. In WAL mode only a checkpoint writes it: each page the log holds, copied once.
    case database = "db"
    /// The write-ahead log beside it (`-wal`): each page a transaction changes, as a frame (the page and a 24-byte
    /// header).
    case wal
    /// A rollback journal. The store runs in WAL mode, so this stays empty.
    case journal
    /// A statement journal: a statement inside a transaction that may have to undo its own changes.
    case statementJournal = "stmtjournal"
    /// The temporary database: `CREATE TEMP TABLE`s and their indexes.
    case temporary = "temp"
    /// The temporary database's rollback journal.
    case temporaryJournal = "tempjournal"
    /// A file one statement writes and deletes: a sort, a `DISTINCT` or `IN` b-tree spilled from memory, `VACUUM`'s
    /// copy.
    case transient
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
      } else if openFlags & SQLITE_OPEN_TEMP_DB != 0 {
        self = .temporary
      } else if openFlags & SQLITE_OPEN_TEMP_JOURNAL != 0 {
        self = .temporaryJournal
      } else if openFlags & SQLITE_OPEN_TRANSIENT_DB != 0 {
        self = .transient
      } else {
        self = .other
      }
    }
  }
  /// What SQLite asked of one kind of file.
  public struct Counts: Sendable, Equatable {
    public var writes: Int
    public var bytesWritten: Int
    public var reads: Int
    public var bytesRead: Int
    /// `xSync` calls: an `fsync`, or an `F_FULLFSYNC` when SQLite asks for a full sync.
    public var syncs: Int
    /// The syncs SQLite asked to be full (`F_FULLFSYNC` on Apple's file systems: the drive's own cache too).
    public var fullSyncs: Int
    /// Time spent in the syncs: the commit or checkpoint that asked waited this long for the drive.
    public var syncNanoseconds: UInt64
    public var truncates: Int

    public init(
      writes: Int = 0,
      bytesWritten: Int = 0,
      reads: Int = 0,
      bytesRead: Int = 0,
      syncs: Int = 0,
      fullSyncs: Int = 0,
      syncNanoseconds: UInt64 = 0,
      truncates: Int = 0
    ) {
      self.writes = writes
      self.bytesWritten = bytesWritten
      self.reads = reads
      self.bytesRead = bytesRead
      self.syncs = syncs
      self.fullSyncs = fullSyncs
      self.syncNanoseconds = syncNanoseconds
      self.truncates = truncates
    }

    /// What was counted after `earlier`.
    public func subtracting(_ earlier: Self) -> Self {
      Self(
        writes: max(0, writes - earlier.writes),
        bytesWritten: max(0, bytesWritten - earlier.bytesWritten),
        reads: max(0, reads - earlier.reads),
        bytesRead: max(0, bytesRead - earlier.bytesRead),
        syncs: max(0, syncs - earlier.syncs),
        fullSyncs: max(0, fullSyncs - earlier.fullSyncs),
        syncNanoseconds: syncNanoseconds >= earlier.syncNanoseconds ? syncNanoseconds - earlier.syncNanoseconds : 0,
        truncates: max(0, truncates - earlier.truncates)
      )
    }
  }

  /// By kind of file; a kind SQLite did not touch is absent.
  public var files: [Kind: Counts]

  public init(files: [Kind: Counts] = [:]) {
    self.files = files
  }

  public subscript(kind: Kind) -> Counts { files[kind] ?? Counts() }

  /// Every kind's bytes written.
  public var bytesWritten: Int { files.values.reduce(0) { $0 + $1.bytesWritten } }

  /// What was counted after `earlier`.
  public func subtracting(_ earlier: Self) -> Self {
    var files: [Kind: Counts] = [:]
    for (kind, counts) in self.files {
      let delta = counts.subtracting(earlier[kind])
      if delta != Counts() { files[kind] = delta }
    }
    return Self(files: files)
  }
}

/// The meter's header at the start of the bytes SQLite allocates for each of its files; the system VFS's own file
/// follows it. `base` must stay first: SQLite reads `pMethods` at offset 0.
private struct MeteredFile {
  var base: sqlite3_file
  var real: UnsafeMutablePointer<sqlite3_file>
  /// The file's ``InstantSQLiteFileSnapshot/Kind``, as its position in `allCases`.
  var kind: Int
}

/// The pass-through VFS: every call goes to the system VFS's file; writes, reads, syncs and truncates are counted.
private enum MeteredVFS {
  // SAFETY: written once, inside `installation`'s lock, before the VFS is registered; SQLite calls the methods that
  // read them only on files opened through the registered VFS, after `sqlite3_vfs_register` (which takes SQLite's own
  // mutex) published them.
  nonisolated(unsafe) static var realVFS: UnsafeMutablePointer<sqlite3_vfs>?
  nonisolated(unsafe) static var meteredVFS: UnsafeMutablePointer<sqlite3_vfs>?
  nonisolated(unsafe) static var ioMethods: [UnsafeMutablePointer<sqlite3_io_methods>] = []
  static let installation = OSAllocatedUnfairLock(initialState: false)

  /// Where the system VFS's file starts in the bytes SQLite allocates for one of the meter's files.
  static let realFileOffset = (MemoryLayout<MeteredFile>.stride + 15) & ~15

  static let kinds = InstantSQLiteFileSnapshot.Kind.allCases

  /// Registers the VFS once (not as the default); false when SQLite has no system VFS.
  static func install() -> Bool {
    installation.withLock { installed in
      if installed { return true }
      precondition(MemoryLayout<MeteredFile>.offset(of: \MeteredFile.base) == 0)
      guard let real = sqlite3_vfs_find("unix") ?? sqlite3_vfs_find(nil) else { return false }
      realVFS = real
      ioMethods = (1...3).map { version in
        let methods = UnsafeMutablePointer<sqlite3_io_methods>.allocate(capacity: 1)
        methods.initialize(to: makeIOMethods(version: Int32(version)))
        return methods
      }
      let vfs = UnsafeMutablePointer<sqlite3_vfs>.allocate(capacity: 1)
      vfs.initialize(to: makeVFS(real: real))
      meteredVFS = vfs
      installed = sqlite3_vfs_register(vfs, 0) == SQLITE_OK
      return installed
    }
  }

  static func methods(matching version: Int32) -> UnsafePointer<sqlite3_io_methods> {
    UnsafePointer(ioMethods[Int(min(max(version, 1), 3)) - 1])
  }

  static func header(_ file: UnsafeMutablePointer<sqlite3_file>?) -> UnsafeMutablePointer<MeteredFile> {
    UnsafeMutableRawPointer(file!).assumingMemoryBound(to: MeteredFile.self)
  }

  static func real(_ file: UnsafeMutablePointer<sqlite3_file>?) -> UnsafeMutablePointer<sqlite3_file> {
    header(file).pointee.real
  }

  static func realMethods(_ file: UnsafeMutablePointer<sqlite3_file>?) -> sqlite3_io_methods {
    real(file).pointee.pMethods.pointee
  }

  static func makeVFS(real: UnsafeMutablePointer<sqlite3_vfs>) -> sqlite3_vfs {
    var vfs = sqlite3_vfs()
    vfs.iVersion = real.pointee.iVersion
    vfs.szOsFile = Int32(realFileOffset) + real.pointee.szOsFile
    vfs.mxPathname = real.pointee.mxPathname
    vfs.zName = UnsafePointer(strdup(InstantSQLiteFileMeter.vfsName))
    vfs.pAppData = nil
    vfs.xOpen = { _, name, file, flags, outFlags in
      guard let real = MeteredVFS.realVFS, let file else { return SQLITE_ERROR }
      let raw = UnsafeMutableRawPointer(file)
      let realFile = (raw + MeteredVFS.realFileOffset).bindMemory(to: sqlite3_file.self, capacity: 1)
      memset(realFile, 0, Int(real.pointee.szOsFile))
      let kind = InstantSQLiteFileSnapshot.Kind(openFlags: flags)
      let header = raw.bindMemory(to: MeteredFile.self, capacity: 1)
      header.initialize(
        to: MeteredFile(
          base: sqlite3_file(pMethods: nil),
          real: realFile,
          kind: MeteredVFS.kinds.firstIndex(of: kind) ?? MeteredVFS.kinds.count - 1
        )
      )
      let result = real.pointee.xOpen(real, name, realFile, flags, outFlags)
      // SQLite calls xClose on a file whose `pMethods` is set, even when the open failed; the system VFS sets its own
      // only when it has something to close.
      if let methods = realFile.pointee.pMethods {
        header.pointee.base.pMethods = MeteredVFS.methods(matching: methods.pointee.iVersion)
      }
      return result
    }
    vfs.xDelete = { _, name, syncDirectory in
      MeteredVFS.realVFS!.pointee.xDelete(MeteredVFS.realVFS, name, syncDirectory)
    }
    vfs.xAccess = { _, name, flags, out in
      MeteredVFS.realVFS!.pointee.xAccess(MeteredVFS.realVFS, name, flags, out)
    }
    vfs.xFullPathname = { _, name, count, out in
      MeteredVFS.realVFS!.pointee.xFullPathname(MeteredVFS.realVFS, name, count, out)
    }
    vfs.xDlOpen = { _, name in MeteredVFS.realVFS!.pointee.xDlOpen(MeteredVFS.realVFS, name) }
    vfs.xDlError = { _, count, out in MeteredVFS.realVFS!.pointee.xDlError(MeteredVFS.realVFS, count, out) }
    vfs.xDlSym = { _, handle, symbol in
      MeteredVFS.realVFS!.pointee.xDlSym(MeteredVFS.realVFS, handle, symbol)
    }
    vfs.xDlClose = { _, handle in MeteredVFS.realVFS!.pointee.xDlClose(MeteredVFS.realVFS, handle) }
    vfs.xRandomness = { _, count, out in
      MeteredVFS.realVFS!.pointee.xRandomness(MeteredVFS.realVFS, count, out)
    }
    vfs.xSleep = { _, microseconds in MeteredVFS.realVFS!.pointee.xSleep(MeteredVFS.realVFS, microseconds) }
    vfs.xCurrentTime = { _, out in MeteredVFS.realVFS!.pointee.xCurrentTime(MeteredVFS.realVFS, out) }
    vfs.xGetLastError = { _, count, out in
      MeteredVFS.realVFS!.pointee.xGetLastError(MeteredVFS.realVFS, count, out)
    }
    if real.pointee.iVersion >= 2 {
      vfs.xCurrentTimeInt64 = { _, out in
        MeteredVFS.realVFS!.pointee.xCurrentTimeInt64(MeteredVFS.realVFS, out)
      }
    }
    if real.pointee.iVersion >= 3 {
      vfs.xSetSystemCall = { _, name, pointer in
        MeteredVFS.realVFS!.pointee.xSetSystemCall(MeteredVFS.realVFS, name, pointer)
      }
      vfs.xGetSystemCall = { _, name in
        MeteredVFS.realVFS!.pointee.xGetSystemCall(MeteredVFS.realVFS, name)
      }
      vfs.xNextSystemCall = { _, name in
        MeteredVFS.realVFS!.pointee.xNextSystemCall(MeteredVFS.realVFS, name)
      }
    }
    return vfs
  }

  static func makeIOMethods(version: Int32) -> sqlite3_io_methods {
    var methods = sqlite3_io_methods()
    methods.iVersion = version
    methods.xClose = { file in
      let real = MeteredVFS.real(file)
      return real.pointee.pMethods.pointee.xClose(real)
    }
    methods.xRead = { file, buffer, amount, offset in
      let result = MeteredVFS.realMethods(file).xRead(MeteredVFS.real(file), buffer, amount, offset)
      // SQLITE_IOERR_SHORT_READ, a C macro Swift does not import: a read past the file's end, which SQLite expects.
      if result == SQLITE_OK || result == SQLITE_IOERR | (2 << 8) {
        InstantSQLiteFileMeter.count(MeteredVFS.header(file).pointee.kind) {
          $0.reads += 1
          $0.bytesRead += Int(amount)
        }
      }
      return result
    }
    methods.xWrite = { file, buffer, amount, offset in
      let result = MeteredVFS.realMethods(file).xWrite(MeteredVFS.real(file), buffer, amount, offset)
      if result == SQLITE_OK {
        InstantSQLiteFileMeter.count(MeteredVFS.header(file).pointee.kind) {
          $0.writes += 1
          $0.bytesWritten += Int(amount)
        }
      }
      return result
    }
    methods.xTruncate = { file, size in
      InstantSQLiteFileMeter.count(MeteredVFS.header(file).pointee.kind) { $0.truncates += 1 }
      return MeteredVFS.realMethods(file).xTruncate(MeteredVFS.real(file), size)
    }
    methods.xSync = { file, flags in
      let started = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
      let result = MeteredVFS.realMethods(file).xSync(MeteredVFS.real(file), flags)
      let elapsed = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) &- started
      InstantSQLiteFileMeter.count(MeteredVFS.header(file).pointee.kind) {
        $0.syncs += 1
        if flags & 0x0F == SQLITE_SYNC_FULL { $0.fullSyncs += 1 }
        $0.syncNanoseconds &+= elapsed
      }
      return result
    }
    methods.xFileSize = { file, size in
      MeteredVFS.realMethods(file).xFileSize(MeteredVFS.real(file), size)
    }
    methods.xLock = { file, lock in MeteredVFS.realMethods(file).xLock(MeteredVFS.real(file), lock) }
    methods.xUnlock = { file, lock in MeteredVFS.realMethods(file).xUnlock(MeteredVFS.real(file), lock) }
    methods.xCheckReservedLock = { file, out in
      MeteredVFS.realMethods(file).xCheckReservedLock(MeteredVFS.real(file), out)
    }
    methods.xFileControl = { file, operation, argument in
      MeteredVFS.realMethods(file).xFileControl(MeteredVFS.real(file), operation, argument)
    }
    methods.xSectorSize = { file in MeteredVFS.realMethods(file).xSectorSize(MeteredVFS.real(file)) }
    methods.xDeviceCharacteristics = { file in
      MeteredVFS.realMethods(file).xDeviceCharacteristics(MeteredVFS.real(file))
    }
    if version >= 2 {
      methods.xShmMap = { file, region, size, extend, out in
        MeteredVFS.realMethods(file).xShmMap(MeteredVFS.real(file), region, size, extend, out)
      }
      methods.xShmLock = { file, offset, count, flags in
        MeteredVFS.realMethods(file).xShmLock(MeteredVFS.real(file), offset, count, flags)
      }
      methods.xShmBarrier = { file in MeteredVFS.realMethods(file).xShmBarrier(MeteredVFS.real(file)) }
      methods.xShmUnmap = { file, deleteFlag in
        MeteredVFS.realMethods(file).xShmUnmap(MeteredVFS.real(file), deleteFlag)
      }
    }
    if version >= 3 {
      methods.xFetch = { file, offset, amount, out in
        MeteredVFS.realMethods(file).xFetch(MeteredVFS.real(file), offset, amount, out)
      }
      methods.xUnfetch = { file, offset, pointer in
        MeteredVFS.realMethods(file).xUnfetch(MeteredVFS.real(file), offset, pointer)
      }
    }
    return methods
  }
}
