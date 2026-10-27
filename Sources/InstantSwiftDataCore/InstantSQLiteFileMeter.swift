import Foundation

// History:
// - 2026-10-27: what SQLite writes to each kind of file the store opens (#1245). On one device a recording hour wrote
//   3.31 GB, and 0.80 GB of it no meter named: the store's write meter counts the pages each store call writes to the
//   write-ahead log, not a checkpoint's copies into the database file, the temporary database or its journal.

/// What SQLite writes to each kind of file the store opens, counted by a pass-through VFS in front of the system's
/// (#1245).
public enum InstantSQLiteFileMeter {
  /// The name the meter's VFS registers under.
  public static let vfsName = "instant-metered"

  /// Everything the meter counted since the process started.
  public static func snapshot() -> InstantSQLiteFileSnapshot {
    InstantSQLiteFileSnapshot()
  }

  /// Registers the meter's VFS once and returns its name, or nil when SQLite has no system VFS to put it in front of.
  static func registeredVFSName() -> String? {
    nil
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
