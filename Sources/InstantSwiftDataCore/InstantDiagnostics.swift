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

  public init(
    fileURL: URL?,
    minimumLevel: InstantDiagnosticLevel = .debug
  ) {
    self.fileURL = fileURL
    self.minimumLevel = minimumLevel
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
    return Self(fileURL: URL(fileURLWithPath: rawPath), minimumLevel: level)
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

// SAFETY: mutable configuration, sequence, and error state are protected by `lock`.
public final class InstantDiagnostics: @unchecked Sendable {
  public static let shared = InstantDiagnostics(configuration: .environment())

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
    lock.withLock {
      self.configuration = configuration
      self.lastWriteError = nil
    }
  }

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
    lock.withLock {
      guard let fileURL = configuration.fileURL,
        level.priority >= configuration.minimumLevel.priority
      else {
        return
      }

      sequence &+= 1
      let entry = InstantDiagnosticEntry(
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

      do {
        var data = try encoder.encode(entry)
        data.append(0x0A)
        try Self.append(data, to: fileURL)
        lastWriteError = nil
      } catch {
        lastWriteError = String(describing: error)
      }
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
    context["errorDescription"] = String(describing: error)
    if let instantError = error as? InstantError {
      context["errorCode"] = instantError.code.rawValue
      context["errorOperation"] = instantError.operation
      context["errorNamespace"] = instantError.namespace
      context["errorPath"] = instantError.path
      context["serverEventID"] = instantError.serverEventID
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

  private static func append(_ data: Data, to fileURL: URL) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

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
    _ = fsync(descriptor)
  }
}
