import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public enum InstantDiagnosticLevel: String, Codable, CaseIterable, Sendable {
  case trace
  case debug
  case info
  case notice
  case warning
  case error
  case critical

  fileprivate var priority: Int {
    switch self {
    case .trace: 0
    case .debug: 1
    case .info: 2
    case .notice: 3
    case .warning: 4
    case .error: 5
    case .critical: 6
    }
  }
}

public struct InstantDiagnosticEntry: Codable, Hashable, Sendable {
  public var schemaVersion: Int
  public var timestampMilliseconds: Int64
  public var sequence: UInt64
  public var sessionID: String
  public var processID: Int32
  public var processName: String
  public var isMainThread: Bool
  public var level: InstantDiagnosticLevel
  public var subsystem: String
  public var category: String
  public var event: String
  public var message: String
  public var metadata: [String: String]
  public var correlationID: String?
  public var fileID: String
  public var line: UInt
  public var function: String
}

public struct InstantDiagnosticsConfiguration: Hashable, Sendable {
  public var fileURL: URL?
  public var minimumLevel: InstantDiagnosticLevel
  /// The most the log file may hold before it becomes `<name>.previous.jsonl` (replacing the
  /// older one) and a new file starts, so the log never holds more than twice this. `nil` lets
  /// the file grow without limit.
  ///
  /// An app records thousands of entries an hour: on 2026-09-26 an iPhone recording wrote
  /// 27.5 MB in an hour to a file nothing ever trimmed (#254).
  public var maximumFileBytes: Int?

  public static let defaultMaximumFileBytes = 16 * 1_024 * 1_024

  public init(
    fileURL: URL?,
    minimumLevel: InstantDiagnosticLevel = .debug,
    maximumFileBytes: Int? = Self.defaultMaximumFileBytes
  ) {
    self.fileURL = fileURL
    self.minimumLevel = minimumLevel
    self.maximumFileBytes = maximumFileBytes.map { max(1, $0) }
  }

  public static func environment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Self {
    guard
      let rawPath = environment["INSTANT_SWIFT_DATA_LOG_PATH"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !rawPath.isEmpty,
      rawPath.lowercased() != "off"
    else {
      return Self(fileURL: nil)
    }
    let level =
      environment["INSTANT_SWIFT_DATA_LOG_LEVEL"]
      .flatMap { InstantDiagnosticLevel(rawValue: $0.lowercased()) }
      ?? .debug
    // INSTANT_SWIFT_DATA_LOG_MAX_BYTES=0 lets a long tool run keep everything.
    let maximumFileBytes =
      environment["INSTANT_SWIFT_DATA_LOG_MAX_BYTES"].flatMap(Int.init)
      .map { $0 > 0 ? $0 : nil }
      ?? defaultMaximumFileBytes
    return Self(
      fileURL: URL(fileURLWithPath: rawPath),
      minimumLevel: level,
      maximumFileBytes: maximumFileBytes
    )
  }
}

public struct InstantDiagnosticsStatus: Hashable, Sendable {
  public var fileURL: URL?
  public var sessionID: String
  public var lastWriteError: String?

  public init(fileURL: URL?, sessionID: String, lastWriteError: String?) {
    self.fileURL = fileURL
    self.sessionID = sessionID
    self.lastWriteError = lastWriteError
  }
}

/// Optional sink for Instant diagnostic entries so host apps can dual-write them
/// into their own collectors (for example Scribe's Tailscale WebSocket lane).
public typealias InstantDiagnosticHandler = @Sendable (InstantDiagnosticEntry) -> Void

// SAFETY: mutable configuration, sequence, handlers, and error state are protected by `lock`.
public final class InstantDiagnostics: @unchecked Sendable {
  public static let shared: InstantDiagnostics = {
    let diagnostics = InstantDiagnostics(configuration: .environment())
    // A tool that logs and exits still gets its last entries into the file.
    atexit { InstantDiagnostics.shared.flush() }
    return diagnostics
  }()

  private static let sensitiveMetadataKeys: Set<String> = [
    "accesstoken",
    "admintoken",
    "authorization",
    "codeverifier",
    "cookie",
    "idtoken",
    "magiccode",
    "oauthtoken",
    "password",
    "refreshtoken",
    "registrationkey",
    "secret",
    "sharetoken",
  ]

  private let lock = NSLock()
  private let encoder: JSONEncoder
  private let sessionID: String
  private let processID: Int32
  private let processName: String
  private var configuration: InstantDiagnosticsConfiguration
  private var sequence: UInt64 = 0
  private var lastWriteError: String?
  private var handlers: [UUID: InstantDiagnosticHandler] = [:]
  private var hasActiveSink = false
  /// Last metadata emitted per `changeKey`, for events that record only transitions.
  private var lastMetadataByChangeKey: [String: [String: String]] = [:]
  private static let maximumChangeKeys = 512

  /// The log file is written off the caller's thread, in order (#473). A local write logs while it holds the
  /// runtime's operation gate, and each append created the directory, opened, locked, wrote and fsynced the file: on a
  /// hot, busy device that held the gate for seconds, and a recording died behind a 12 s hold. ``flush()`` waits for
  /// every entry recorded so far.
  private let fileWriteQueue = DispatchQueue(label: "InstantDiagnostics.file", qos: .utility)
  private let fileWriteQueueKey = DispatchSpecificKey<Void>()
  private var pendingFileWrites: [PendingFileWrite] = []
  private var pendingFileWriteBytes = 0
  private var fileWriteScheduled = false
  private var droppedFileWriteCount = 0
  /// A log file that falls this far behind (a disk that stopped answering) drops new entries instead of holding them.
  private static let maximumPendingFileWriteBytes = 8 * 1_024 * 1_024

  private struct PendingFileWrite {
    var data: Data
    var fileURL: URL
    var maximumFileBytes: Int?
  }

  /// A file is fsynced at most this often, not after every line (#473): a write survives an app crash once it is in
  /// the kernel's cache, and only a power loss in between can lose it. ``flush()`` syncs at once.
  private static let fileSyncIntervalSeconds: TimeInterval = 1
  // Read and written only on `fileWriteQueue`.
  private var unsyncedFileURLs: Set<URL> = []
  private var lastFileSyncAt: [URL: Date] = [:]
  private var fileSyncScheduled = false
  private var fileSyncCount = 0
  private var fileAppendCount = 0

  public init(
    configuration: InstantDiagnosticsConfiguration,
    sessionID: String = UUID().uuidString.lowercased(),
    processID: Int32 = ProcessInfo.processInfo.processIdentifier,
    processName: String = ProcessInfo.processInfo.processName
  ) {
    self.configuration = configuration
    self.sessionID = sessionID
    self.processID = processID
    self.processName = processName
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    self.hasActiveSink = configuration.fileURL != nil
    fileWriteQueue.setSpecific(key: fileWriteQueueKey, value: ())
  }

  public static func defaultLogFileURL(processName: String) -> URL {
    let baseURL =
      FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let safeName =
      processName
      .map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
    return
      baseURL
      .appendingPathComponent("Logs", isDirectory: true)
      .appendingPathComponent("InstantSwiftData", isDirectory: true)
      .appendingPathComponent(String(safeName) + ".jsonl")
  }

  public func configure(_ configuration: InstantDiagnosticsConfiguration) {
    // Entries recorded under the old configuration go to its file first.
    flush()
    lock.withLock {
      self.configuration = configuration
      self.lastWriteError = nil
      self.droppedFileWriteCount = 0
      refreshHasActiveSinkLocked()
    }
  }

  /// Registers a host-app sink for every diagnostic that meets the minimum level.
  /// Returns a token that must be passed to `removeHandler` when the sink is torn down.
  @discardableResult
  public func addHandler(_ handler: @escaping InstantDiagnosticHandler) -> UUID {
    let token = UUID()
    lock.withLock {
      handlers[token] = handler
      refreshHasActiveSinkLocked()
    }
    return token
  }

  public func removeHandler(_ token: UUID) {
    lock.withLock {
      handlers[token] = nil
      refreshHasActiveSinkLocked()
    }
  }

  private func refreshHasActiveSinkLocked() {
    hasActiveSink = configuration.fileURL != nil || !handlers.isEmpty
  }

  public var isEnabled: Bool { hasActiveSink }

  /// Whether an entry at `level` would be recorded (#473): a sink is configured and `level` reaches the configured
  /// minimum level. A caller that builds costly metadata for a frequent line checks this first.
  public func isEnabled(at level: InstantDiagnosticLevel) -> Bool {
    guard hasActiveSink else { return false }
    return lock.withLock { level.priority >= configuration.minimumLevel.priority }
  }

  /// The configuration's file and the last write error. Writes are asynchronous; call ``flush()`` first to see the
  /// result of every entry recorded so far.
  public var status: InstantDiagnosticsStatus {
    lock.withLock {
      InstantDiagnosticsStatus(
        fileURL: configuration.fileURL,
        sessionID: sessionID,
        lastWriteError: lastWriteError
      )
    }
  }

  public func record(
    _ level: InstantDiagnosticLevel = .info,
    subsystem: String,
    category: String,
    event: String,
    message: String,
    metadata: [String: String] = [:],
    correlationID: String? = nil,
    fileID: String = #fileID,
    line: UInt = #line,
    function: String = #function
  ) {
    recordEntry(
      level, subsystem: subsystem, category: category, event: event, message: message,
      metadata: metadata, correlationID: correlationID, changeKey: nil,
      fileID: fileID, line: line, function: function
    )
  }

  /// Records a state snapshot only when its metadata differs from the last one recorded for the
  /// same `event` and `changeKey`.
  ///
  /// For snapshots that repeat on every refresh. On an iPhone on 2026-09-26, 97.8% of
  /// `infinite.starter.snapshot` and 79.7% of `infinite.remote-page-info.decoded` events repeated
  /// the previous one exactly.
  public func record(
    _ level: InstantDiagnosticLevel = .info,
    subsystem: String,
    category: String,
    event: String,
    message: String,
    metadata: [String: String] = [:],
    correlationID: String? = nil,
    changeKey: String,
    fileID: String = #fileID,
    line: UInt = #line,
    function: String = #function
  ) {
    recordEntry(
      level, subsystem: subsystem, category: category, event: event, message: message,
      metadata: metadata, correlationID: correlationID, changeKey: changeKey,
      fileID: fileID, line: line, function: function
    )
  }

  private func recordEntry(
    _ level: InstantDiagnosticLevel,
    subsystem: String,
    category: String,
    event: String,
    message: String,
    metadata: [String: String],
    correlationID: String?,
    changeKey: String?,
    fileID: String,
    line: UInt,
    function: String
  ) {
    guard hasActiveSink else { return }
    var entry: InstantDiagnosticEntry?
    var fileURL: URL?
    var maximumFileBytes: Int?
    var activeHandlers: [InstantDiagnosticHandler] = []
    lock.withLock {
      guard level.priority >= configuration.minimumLevel.priority else { return }
      // Emit when a host sink or a file path is configured. File path alone is
      // still supported for CLI/tools; Scribe installs a handler so events reach
      // the Tailscale dual-write collector even when the file path is unset.
      guard configuration.fileURL != nil || !handlers.isEmpty else { return }
      if let changeKey {
        let memoKey = event + "\u{1F}" + changeKey
        guard lastMetadataByChangeKey[memoKey] != metadata else { return }
        if lastMetadataByChangeKey.count >= Self.maximumChangeKeys {
          lastMetadataByChangeKey.removeAll(keepingCapacity: true)
        }
        lastMetadataByChangeKey[memoKey] = metadata
      }

      sequence &+= 1
      entry = InstantDiagnosticEntry(
        schemaVersion: 1,
        timestampMilliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()),
        sequence: sequence,
        sessionID: sessionID,
        processID: processID,
        processName: processName,
        isMainThread: Thread.isMainThread,
        level: level,
        subsystem: Self.bounded(subsystem, limit: 128),
        category: Self.bounded(category, limit: 128),
        event: Self.bounded(event, limit: 192),
        message: Self.bounded(message, limit: 4_096),
        metadata: Self.redacted(metadata),
        correlationID: correlationID.map(Self.redactedCorrelationID),
        fileID: Self.bounded(fileID, limit: 256),
        line: line,
        function: Self.bounded(function, limit: 256)
      )
      fileURL = configuration.fileURL
      maximumFileBytes = configuration.maximumFileBytes
      activeHandlers = Array(handlers.values)
    }

    guard let entry else { return }

    if let fileURL {
      do {
        var data = try encoder.encode(entry)
        data.append(0x0A)
        enqueueFileWrite(data, to: fileURL, maximumFileBytes: maximumFileBytes)
      } catch {
        lock.withLock { lastWriteError = String(describing: error) }
      }
    }

    for handler in activeHandlers {
      handler(entry)
    }
  }

  public func record(
    error: Error,
    subsystem: String,
    category: String,
    event: String,
    message: String,
    metadata: [String: String] = [:],
    correlationID: String? = nil,
    fileID: String = #fileID,
    line: UInt = #line,
    function: String = #function
  ) {
    var context = metadata
    context["errorType"] = String(reflecting: type(of: error))
    if let instantError = error as? InstantError {
      // Prefer the structured Instant summary over Swift's opaque NSError collapse.
      context["errorDescription"] = instantError.userFacingSummary
      context["errorCode"] = instantError.code.rawValue
      context["errorOperation"] = instantError.operation
      context["errorMessage"] = instantError.message
      context["errorRecovery"] = instantError.recovery
      context["errorNamespace"] = instantError.namespace
      context["errorPath"] = instantError.path
      context["serverEventID"] = instantError.serverEventID
      context["serverStatus"] = instantError.serverStatus.map(String.init)
      context["serverType"] = instantError.serverType
      context["serverTraceID"] = instantError.serverTraceID
    } else {
      context["errorDescription"] =
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
    record(
      .error,
      subsystem: subsystem,
      category: category,
      event: event,
      message: message,
      metadata: context.compactMapValues { $0 },
      correlationID: correlationID,
      fileID: fileID,
      line: line,
      function: function
    )
  }

  private static func redacted(_ metadata: [String: String]) -> [String: String] {
    metadata.reduce(into: [:]) { result, element in
      let normalizedKey = element.key
        .lowercased()
        .filter(\.isLetter)
      result[bounded(element.key, limit: 128)] =
        sensitiveMetadataKeys.contains(normalizedKey)
        ? "<redacted>"
        : bounded(element.value, limit: 4_096)
    }
  }

  private static func bounded(_ value: String, limit: Int) -> String {
    guard value.count > limit else { return value }
    return String(value.prefix(limit)) + "…"
  }

  private static func redactedCorrelationID(_ value: String) -> String {
    // Generated query IDs contain a Base64-encoded canonical query plan, which
    // can include emails, search terms, user IDs, and share tokens. Preserve a
    // useful type marker without writing the query itself to disk.
    if value.hasPrefix("instant-query:") || value.hasPrefix("plan:") {
      return value.prefix { $0 != ":" } + ":<redacted>"
    }
    return bounded(value, limit: 256)
  }

  /// Waits until every entry recorded so far is in the log file. Reading the file or its ``status``, rotating it from
  /// outside, or exiting needs this first; ``configure(_:)`` calls it itself.
  public func flush() {
    if DispatchQueue.getSpecific(key: fileWriteQueueKey) != nil {
      drainFileWrites()
      syncWrittenFiles(force: true)
    } else {
      fileWriteQueue.sync {
        drainFileWrites()
        syncWrittenFiles(force: true)
      }
    }
  }

  /// How many times the log file was fsynced and appended to, for tests (#473).
  package var fileWriteCountsForTesting: (syncs: Int, appends: Int) {
    fileWriteQueue.sync { (fileSyncCount, fileAppendCount) }
  }

  private func enqueueFileWrite(_ data: Data, to fileURL: URL, maximumFileBytes: Int?) {
    let schedules = lock.withLock { () -> Bool in
      guard pendingFileWriteBytes + data.count <= Self.maximumPendingFileWriteBytes else {
        droppedFileWriteCount += 1
        lastWriteError =
          "Dropped \(droppedFileWriteCount) entries: the log file fell more than \(Self.maximumPendingFileWriteBytes) bytes behind."
        return false
      }
      pendingFileWrites.append(PendingFileWrite(data: data, fileURL: fileURL, maximumFileBytes: maximumFileBytes))
      pendingFileWriteBytes += data.count
      guard !fileWriteScheduled else { return false }
      fileWriteScheduled = true
      return true
    }
    if schedules {
      fileWriteQueue.async { [self] in drainFileWrites() }
    }
  }

  /// Writes the waiting entries in order, each run of entries for one file under one open and one lock. Runs on
  /// `fileWriteQueue`.
  private func drainFileWrites() {
    while true {
      let batch = lock.withLock { () -> [PendingFileWrite] in
        let batch = pendingFileWrites
        pendingFileWrites.removeAll()
        pendingFileWriteBytes = 0
        if batch.isEmpty { fileWriteScheduled = false }
        return batch
      }
      if batch.isEmpty {
        syncWrittenFiles(force: false)
        return
      }
      var index = batch.startIndex
      while index < batch.endIndex {
        let fileURL = batch[index].fileURL
        let maximumFileBytes = batch[index].maximumFileBytes
        var run: [Data] = []
        while index < batch.endIndex,
          batch[index].fileURL == fileURL,
          batch[index].maximumFileBytes == maximumFileBytes
        {
          run.append(batch[index].data)
          index += 1
        }
        do {
          try Self.append(run, to: fileURL, maximumFileBytes: maximumFileBytes)
          fileAppendCount += 1
          unsyncedFileURLs.insert(fileURL)
          lock.withLock { if droppedFileWriteCount == 0 { lastWriteError = nil } }
        } catch {
          lock.withLock { lastWriteError = String(describing: error) }
        }
      }
    }
  }

  /// Fsyncs each written file whose last sync is a second old, or every one when `force`; schedules the rest. Runs
  /// on `fileWriteQueue`.
  private func syncWrittenFiles(force: Bool) {
    let now = Date()
    for fileURL in unsyncedFileURLs {
      let lastSync = lastFileSyncAt[fileURL] ?? .distantPast
      guard force || now.timeIntervalSince(lastSync) >= Self.fileSyncIntervalSeconds else { continue }
      let descriptor = open(fileURL.path, O_WRONLY)
      if descriptor >= 0 {
        _ = fsync(descriptor)
        _ = close(descriptor)
        fileSyncCount += 1
      }
      lastFileSyncAt[fileURL] = now
      unsyncedFileURLs.remove(fileURL)
    }
    guard !unsyncedFileURLs.isEmpty, !fileSyncScheduled else { return }
    fileSyncScheduled = true
    fileWriteQueue.asyncAfter(deadline: .now() + Self.fileSyncIntervalSeconds) { [self] in
      fileSyncScheduled = false
      syncWrittenFiles(force: true)
    }
  }

  /// The file that holds the entries written before the last rotation.
  public static func previousLogFileURL(for fileURL: URL) -> URL {
    fileURL.deletingPathExtension().appendingPathExtension("previous.jsonl")
  }

  /// Appends `entries` in order under one open and one lock, rotating before an entry that would take the file past
  /// `maximumFileBytes`; the file being retired is fsynced first. The caller syncs the rest (`syncWrittenFiles`).
  private static func append(_ entries: [Data], to fileURL: URL, maximumFileBytes: Int?) throws {
    guard !entries.isEmpty else { return }
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    var remaining = entries[...]
    var attempts = 0
    // A writer that opened the file just before another rotated it holds the renamed file, so it
    // checks the path still names its file and reopens if not. Rotating from a stale descriptor
    // would move the new file over the previous one and lose a whole file of entries.
    while !remaining.isEmpty {
      attempts += 1
      guard attempts <= 4 + entries.count else { throw POSIXError(.EAGAIN) }
      let descriptor = open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
      guard descriptor >= 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      defer { _ = close(descriptor) }
      _ = fchmod(descriptor, 0o600)

      guard flock(descriptor, LOCK_EX) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      defer { _ = flock(descriptor, LOCK_UN) }

      var opened = stat()
      var current = stat()
      guard fstat(descriptor, &opened) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
      guard
        stat(fileURL.path, &current) == 0,
        current.st_ino == opened.st_ino,
        current.st_dev == opened.st_dev
      else { continue }

      var size = Int(opened.st_size)
      while let data = remaining.first {
        if let maximumFileBytes, size > 0, size + data.count > maximumFileBytes {
          _ = fsync(descriptor)
          guard rename(fileURL.path, previousLogFileURL(for: fileURL).path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
          }
          break
        }
        try data.withUnsafeBytes { rawBuffer in
          guard let baseAddress = rawBuffer.baseAddress else { return }
          var offset = 0
          while offset < rawBuffer.count {
            let result = write(descriptor, baseAddress.advanced(by: offset), rawBuffer.count - offset)
            if result < 0 {
              if errno == EINTR { continue }
              throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            offset += result
          }
        }
        size += data.count
        remaining.removeFirst()
      }
    }
  }
}
