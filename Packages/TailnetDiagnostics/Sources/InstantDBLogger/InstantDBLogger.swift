import CryptoKit
import Dependencies
import DependenciesMacros
import Foundation
import InstantSwiftData
import InstantToolsLogging
import os

public typealias IssueLogReference = InstantToolsLogging.IssueLogReference
public typealias LogContributingPath = InstantToolsLogging.LogContributingPath
public typealias LogPathRelationship = InstantToolsLogging.LogPathRelationship

public enum InstantDBLogLevel: String, Codable, CaseIterable, Sendable {
  case debug
  case info
  case notice
  case warning
  case error
  case critical
}

public struct InstantDBLogEvent: Codable, Equatable, Sendable {
  public var contributingPaths: [LogContributingPath]
  public var timestampMs: Double?
  public var level: InstantDBLogLevel
  public var category: String
  public var name: String
  public var message: String
  public var metadata: [String: String]
  public var issueReferences: [IssueLogReference]
  public var fileID: String
  public var function: String
  public var sourceLine: Int

  public init(
    timestampMs: Double? = nil,
    level: InstantDBLogLevel = .info,
    category: String,
    contributingPaths: [LogContributingPath] = [],
    name: String,
    message: String,
    metadata: [String: String] = [:],
    issueReferences: [IssueLogReference] = [],
    fileID: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
    self.timestampMs = timestampMs
    self.level = level
    self.category = category
    self.contributingPaths = contributingPaths
    self.name = name
    self.message = InstantDBLogRedactor.redact(message)
    self.metadata = InstantDBLogRedactor.redact(metadata)
    self.issueReferences = LogEvent(
      category: category,
      contributingPaths: contributingPaths,
      id: "issue-reference-inference",
      issueReferences: issueReferences,
      level: .info,
      message: message,
      metadata: metadata,
      name: name,
      timestamp: Date(timeIntervalSince1970: 0),
      fileID: fileID,
      line: line,
      function: function
    ).issueReferences
    self.fileID = String(describing: fileID)
    self.function = String(describing: function)
    self.sourceLine = Int(line)
  }

  private enum CodingKeys: String, CodingKey {
    case contributingPaths
    case timestampMs
    case level
    case category
    case name
    case message
    case metadata
    case issueReferences
    case fileID
    case function
    case sourceLine
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    contributingPaths =
      try container.decodeIfPresent([LogContributingPath].self, forKey: .contributingPaths) ?? []
    timestampMs = try container.decodeIfPresent(Double.self, forKey: .timestampMs)
    level = try container.decode(InstantDBLogLevel.self, forKey: .level)
    category = try container.decode(String.self, forKey: .category)
    name = try container.decode(String.self, forKey: .name)
    message = try container.decode(String.self, forKey: .message)
    metadata = try container.decode([String: String].self, forKey: .metadata)
    fileID = try container.decode(String.self, forKey: .fileID)
    function = try container.decode(String.self, forKey: .function)
    sourceLine = try container.decode(Int.self, forKey: .sourceLine)
    let explicitReferences =
      try container.decodeIfPresent([IssueLogReference].self, forKey: .issueReferences) ?? []
    issueReferences = LogEvent(
      category: category,
      id: "legacy-instantdb-log-event",
      issueReferences: explicitReferences,
      level: LogLevel(rawValue: level.rawValue) ?? .info,
      message: message,
      metadata: metadata,
      name: name,
      timestamp: Date(timeIntervalSince1970: (timestampMs ?? 0) / 1_000)
    ).issueReferences
  }

  public var sourceLocation: String {
    "\(fileID):\(sourceLine)"
  }
}

public struct InstantDBLogEntry: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var timestampMs: Double
  public var level: InstantDBLogLevel
  public var subsystem: String
  public var category: String
  public var name: String
  public var message: String
  public var metadata: [String: String]
  public var sessionID: String
  public var platform: String
  public var deviceName: String
  public var appVersion: String
  public var buildCommit: String
  public var fileID: String
  public var function: String
  public var sourceLine: Int
  public var timestampLocal: String
  public var projectName: String
  public var buildBranch: String
  public var buildIsDirty: Bool
  public var contributingPaths: [LogContributingPath]
  public var issueReferences: [IssueLogReference]

  public init(
    id: String,
    timestampMs: Double,
    level: InstantDBLogLevel,
    subsystem: String,
    category: String,
    name: String,
    message: String,
    metadata: [String: String],
    sessionID: String,
    platform: String,
    deviceName: String,
    appVersion: String,
    buildCommit: String,
    fileID: String,
    function: String,
    sourceLine: Int,
    timestampLocal: String = "",
    projectName: String = "",
    buildBranch: String = "",
    buildIsDirty: Bool = false,
    contributingPaths: [LogContributingPath] = [],
    issueReferences: [IssueLogReference] = []
  ) {
    self.id = id
    self.timestampMs = timestampMs
    self.level = level
    self.subsystem = subsystem
    self.category = category
    self.name = name
    self.message = message
    self.metadata = metadata
    self.sessionID = sessionID
    self.platform = platform
    self.deviceName = deviceName
    self.appVersion = appVersion
    self.buildCommit = buildCommit
    self.fileID = fileID
    self.function = function
    self.sourceLine = sourceLine
    self.timestampLocal = timestampLocal
    self.projectName = projectName
    self.buildBranch = buildBranch
    self.buildIsDirty = buildIsDirty
    self.contributingPaths = contributingPaths
    self.issueReferences = issueReferences
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case timestampMs
    case level
    case subsystem
    case category
    case name
    case message
    case metadata
    case sessionID
    case platform
    case deviceName
    case appVersion
    case buildCommit
    case fileID
    case function
    case sourceLine
    case timestampLocal
    case projectName
    case buildBranch
    case buildIsDirty
    case contributingPaths
    case issueReferences
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    timestampMs = try container.decode(Double.self, forKey: .timestampMs)
    level = try container.decode(InstantDBLogLevel.self, forKey: .level)
    subsystem = try container.decode(String.self, forKey: .subsystem)
    category = try container.decode(String.self, forKey: .category)
    name = try container.decode(String.self, forKey: .name)
    message = try container.decode(String.self, forKey: .message)
    metadata = try container.decode([String: String].self, forKey: .metadata)
    sessionID = try container.decode(String.self, forKey: .sessionID)
    platform = try container.decode(String.self, forKey: .platform)
    deviceName = try container.decode(String.self, forKey: .deviceName)
    appVersion = try container.decode(String.self, forKey: .appVersion)
    buildCommit = try container.decode(String.self, forKey: .buildCommit)
    fileID = try container.decode(String.self, forKey: .fileID)
    function = try container.decode(String.self, forKey: .function)
    sourceLine = try container.decode(Int.self, forKey: .sourceLine)
    timestampLocal = try container.decodeIfPresent(String.self, forKey: .timestampLocal) ?? ""
    projectName = try container.decodeIfPresent(String.self, forKey: .projectName) ?? ""
    buildBranch = try container.decodeIfPresent(String.self, forKey: .buildBranch) ?? ""
    buildIsDirty = try container.decodeIfPresent(Bool.self, forKey: .buildIsDirty) ?? false
    contributingPaths =
      try container.decodeIfPresent([LogContributingPath].self, forKey: .contributingPaths) ?? []
    let explicitReferences =
      try container.decodeIfPresent([IssueLogReference].self, forKey: .issueReferences) ?? []
    issueReferences = LogEvent(
      category: category,
      id: id,
      issueReferences: explicitReferences,
      level: LogLevel(rawValue: level.rawValue) ?? .info,
      message: message,
      metadata: metadata,
      name: name,
      timestamp: Date(timeIntervalSince1970: timestampMs / 1_000)
    ).issueReferences
  }

  public var sourceLocation: String {
    "\(fileID):\(sourceLine)"
  }
}

public struct InstantDBLogContext: Equatable, Sendable {
  public var subsystem: String
  public var sessionID: String
  public var platform: String
  public var deviceName: String
  public var appVersion: String
  public var buildCommit: String
  public var buildBranch: String
  public var buildIsDirty: Bool
  public var projectName: String
  public var timeZoneIdentifier: String

  public init(
    subsystem: String,
    sessionID: String? = nil,
    platform: String? = nil,
    deviceName: String? = nil,
    appVersion: String? = nil,
    buildCommit: String = "",
    buildBranch: String = "",
    buildIsDirty: Bool = false,
    projectName: String = "Scribe",
    timeZoneIdentifier: String = TimeZone.current.identifier
  ) {
    let resolvedPlatform = platform ?? Self.currentPlatform
    self.subsystem = subsystem
    self.sessionID = sessionID ?? UUID().uuidString.lowercased()
    self.platform = resolvedPlatform
    self.deviceName = deviceName ?? resolvedPlatform
    self.appVersion = appVersion ?? Self.currentAppVersion
    self.buildCommit = buildCommit
    self.buildBranch = buildBranch
    self.buildIsDirty = buildIsDirty
    self.projectName = projectName
    self.timeZoneIdentifier = timeZoneIdentifier
  }

  private static var currentPlatform: String {
    #if os(iOS)
      "iOS"
    #elseif os(macOS)
      "macOS"
    #elseif os(watchOS)
      "watchOS"
    #elseif os(tvOS)
      "tvOS"
    #elseif os(visionOS)
      "visionOS"
    #else
      "unknown"
    #endif
  }

  private static var currentAppVersion: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    return [version, build].compactMap { $0 }.joined(separator: " (")
      + (version != nil && build != nil ? ")" : "")
  }
}

public enum InstantDBLogRedactor {
  public static func redact(_ metadata: [String: String]) -> [String: String] {
    metadata.mapValues { $0 }.reduce(into: [:]) { result, pair in
      result[pair.key] = isSensitiveKey(pair.key) ? "<redacted>" : redact(pair.value)
    }
  }

  public static func redact(_ message: String) -> String {
    message.replacingOccurrences(
      of:
        #"(?i)\b(authorization|api[ _-]?key|token|secret|password|credential)\b\s*[:=]\s*(?:Token\s+)?[^\s,;]+"#,
      with: "$1=<redacted>",
      options: .regularExpression
    )
  }

  private static func isSensitiveKey(_ key: String) -> Bool {
    let normalized = key.lowercased().filter(\.isLetter)
    return ["apikey", "authorization", "credential", "password", "secret", "token"]
      .contains { normalized.contains($0) }
  }
}

struct ScribeDeepgramLogRecord {
  static func jsonLine(
    event: InstantDBLogEvent,
    processSessionID: String,
    uptimeMilliseconds: Int,
    id: String = UUID().uuidString.lowercased()
  ) throws -> Data {
    let timestampMs = event.timestampMs ?? Date().timeIntervalSince1970 * 1_000
    let record: [String: Any] = [
      "category": event.category,
      "contributingPaths": try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(event.contributingPaths)
      ),
      "fileID": event.fileID,
      "function": event.function,
      "id": id,
      "isProtectedEvidence": event.isProtectedRemoteEvidence,
      "level": event.level.rawValue,
      "message": event.message,
      "metadata": event.metadata,
      "name": event.name,
      "issueReferences": try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(event.issueReferences)
      ),
      "processSessionID": processSessionID,
      "sourceLine": event.sourceLine,
      "timestampMs": timestampMs,
      "uptimeMilliseconds": uptimeMilliseconds,
      "wallClockEpochMilliseconds": Int(timestampMs.rounded()),
    ]
    var data = try JSONSerialization.data(
      withJSONObject: record,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
    data.append(Character("\n").asciiValue!)
    return data
  }
}

/// A process-local JSON-lines trace that remains readable even when remote Instant delivery is
/// unavailable. The Watch stores it in Documents so `devicectl` can copy it without stopping Scribe.
public enum ScribeDeepgramLog {
  fileprivate static let processSessionID = UUID().uuidString.lowercased()
  private static let writer = ScribeDeepgramLogWriter()

  public static func append(_ event: InstantDBLogEvent) {
    writer.enqueue(event)
  }

  public static func flush() async {
    await writer.flush()
  }

  public static func trace(
    level: InstantDBLogLevel = .debug,
    category: String,
    name: String,
    message: String,
    metadata: [String: String] = [:],
    fileID: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
    append(
      InstantDBLogEvent(
        timestampMs: Date().timeIntervalSince1970 * 1_000,
        level: level,
        category: category,
        name: name,
        message: message,
        metadata: metadata,
        fileID: fileID,
        line: line,
        function: function
      )
    )
  }
}

private final class ScribeDeepgramLogWriter: @unchecked Sendable {
  private let buffer: InstantDBLogEnqueueBuffer

  init(fileManager: FileManager = .default) {
    #if os(watchOS)
      let directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    #else
      let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    #endif
    let spool = InstantDBLogJSONLSpool(
      url: directory.appending(path: "scribe-deepgram.log"),
      limits: .device
    )
    buffer = InstantDBLogEnqueueBuffer(
      capacity: InstantDBLogDeliveryLimits.maximumPendingEvents
    ) { event in
      do {
        let data = try ScribeDeepgramLogRecord.jsonLine(
          event: event,
          processSessionID: ScribeDeepgramLog.processSessionID,
          uptimeMilliseconds: Int(ProcessInfo.processInfo.systemUptime * 1_000)
        )
        try await spool.append(line: data)
      } catch {
        Logger(subsystem: "InstantDBLogger", category: "LocalSpool").error(
          "Could not append local diagnostics: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  func enqueue(_ event: InstantDBLogEvent) {
    guard !Bundle.main.bundlePath.hasSuffix(".xctest") else { return }
    buffer.enqueue(event)
  }

  func flush() async {
    let fence = buffer.currentFenceSequence()
    await buffer.wait(until: fence)
  }
}

@DependencyClient
public struct InstantDBLogger: Sendable {
  public var append: @Sendable (InstantDBLogEvent) async -> Void = { _ in }
  public var recent:
    @Sendable (_ limit: Int, _ sessionID: String?) async throws -> [InstantDBLogEntry] =
      { _, _ in [] }
  public var observeRecent:
    @Sendable (_ limit: Int, _ sessionID: String?) async -> AsyncStream<[InstantDBLogEntry]> =
      { _, _ in .finished }
  public var flush: @Sendable () async throws -> Void = {}
  public var setRemoteObservabilityEnabled: @Sendable (Bool) async -> Void = { _ in }
  public var queueMetrics: @Sendable () -> InstantDBLogQueueMetrics = {
    InstantDBLogEnqueueBuffer.shared.metrics()
  }

  public static func waitForEnqueuedEvents() async {
    await InstantDBLogEnqueueBuffer.shared.waitUntilDrained()
  }
}

public enum InstantDBLogDeliveryLimits {
  public static let maximumPendingEvents = 256
  public static let maximumPendingMutations = 256
}

public struct InstantDBLogQueueMetrics: Equatable, Sendable {
  public var capacity: Int
  public var pendingCount: Int
  public var isDraining: Bool
  public var acceptedCount: Int
  public var droppedCount: Int

  public init(
    capacity: Int,
    pendingCount: Int,
    isDraining: Bool,
    acceptedCount: Int,
    droppedCount: Int
  ) {
    self.capacity = capacity
    self.pendingCount = pendingCount
    self.isDraining = isDraining
    self.acceptedCount = acceptedCount
    self.droppedCount = droppedCount
  }

  public static let idle = Self(
    capacity: 0,
    pendingCount: 0,
    isDraining: false,
    acceptedCount: 0,
    droppedCount: 0
  )
}

final class InstantDBLogEnqueueBuffer: @unchecked Sendable {
  private struct Delivery: Sendable {
    var append: @Sendable (InstantDBLogEvent) async -> Void
    var event: InstantDBLogEvent
    var sequence: UInt64
  }

  private struct Waiter {
    var continuation: CheckedContinuation<Void, Never>
    var targetSequence: UInt64
  }

  static let shared = InstantDBLogEnqueueBuffer(
    capacity: InstantDBLogDeliveryLimits.maximumPendingEvents
  )

  private let capacity: Int
  private let defaultAppend: (@Sendable (InstantDBLogEvent) async -> Void)?
  private let lock = NSLock()
  private var acceptedCount = 0
  private var completedOutOfOrder: Set<UInt64> = []
  private var completedThroughSequence: UInt64 = 0
  private var drainTask: Task<Void, Never>?
  private var droppedCount = 0
  private var nextSequence: UInt64 = 0
  private var pending: [Delivery] = []
  private var waiters: [Waiter] = []

  init(capacity: Int) {
    self.capacity = max(1, capacity)
    self.defaultAppend = nil
    pending.reserveCapacity(self.capacity)
  }

  init(
    capacity: Int,
    append: @escaping @Sendable (InstantDBLogEvent) async -> Void
  ) {
    self.capacity = max(1, capacity)
    self.defaultAppend = append
    pending.reserveCapacity(self.capacity)
  }

  func enqueue(_ event: InstantDBLogEvent) {
    guard let defaultAppend else {
      preconditionFailure("Use enqueue(_:append:) when the buffer has no default append closure.")
    }
    enqueue(event, append: defaultAppend)
  }

  func enqueue(
    _ event: InstantDBLogEvent,
    append: @escaping @Sendable (InstantDBLogEvent) async -> Void
  ) {
    let continuations: [CheckedContinuation<Void, Never>] = lock.withLock {
      acceptedCount += 1
      nextSequence += 1
      let delivery = Delivery(append: append, event: event, sequence: nextSequence)
      var continuations: [CheckedContinuation<Void, Never>] = []
      if pending.count == capacity {
        guard let indexToReplace = replacementIndex(for: delivery) else {
          droppedCount += 1
          continuations.append(contentsOf: markCompleted(delivery.sequence))
          return continuations
        }
        let replaced = pending.remove(at: indexToReplace)
        droppedCount += 1
        continuations.append(contentsOf: markCompleted(replaced.sequence))
      }
      pending.append(delivery)
      if drainTask == nil {
        drainTask = Task(priority: .utility) { [weak self] in
          await self?.drain()
        }
      }
      return continuations
    }
    continuations.forEach { $0.resume() }
  }

  func metrics() -> InstantDBLogQueueMetrics {
    lock.withLock {
      InstantDBLogQueueMetrics(
        capacity: capacity,
        pendingCount: pending.count,
        isDraining: drainTask != nil,
        acceptedCount: acceptedCount,
        droppedCount: droppedCount
      )
    }
  }

  func waitUntilDrained() async {
    await wait(until: currentFenceSequence())
  }

  func currentFenceSequence() -> UInt64 {
    lock.withLock { nextSequence }
  }

  func wait(until targetSequence: UInt64) async {
    guard targetSequence > 0 else { return }
    await withCheckedContinuation { continuation in
      let shouldResume = lock.withLock {
        guard completedThroughSequence < targetSequence else { return true }
        waiters.append(
          Waiter(continuation: continuation, targetSequence: targetSequence)
        )
        return false
      }
      if shouldResume {
        continuation.resume()
      }
    }
  }

  private func replacementIndex(for incoming: Delivery) -> Int? {
    if let ordinaryIndex = pending.firstIndex(where: {
      !$0.event.isProtectedRemoteEvidence
    }) {
      return ordinaryIndex
    }
    return incoming.event.isProtectedRemoteEvidence ? pending.startIndex : nil
  }

  private func drain() async {
    while true {
      let delivery: Delivery? = lock.withLock {
        if !pending.isEmpty {
          return pending.removeFirst()
        }
        drainTask = nil
        return nil
      }
      guard let delivery else { return }
      await delivery.append(delivery.event)
      let continuations = lock.withLock { markCompleted(delivery.sequence) }
      continuations.forEach { $0.resume() }
    }
  }

  private func markCompleted(
    _ sequence: UInt64
  ) -> [CheckedContinuation<Void, Never>] {
    if sequence == completedThroughSequence + 1 {
      completedThroughSequence = sequence
      while completedOutOfOrder.remove(completedThroughSequence + 1) != nil {
        completedThroughSequence += 1
      }
    } else if sequence > completedThroughSequence {
      completedOutOfOrder.insert(sequence)
    }

    var ready: [CheckedContinuation<Void, Never>] = []
    waiters.removeAll { waiter in
      guard waiter.targetSequence <= completedThroughSequence else { return false }
      ready.append(waiter.continuation)
      return true
    }
    return ready
  }
}

extension InstantDBLogEvent {
  public var isProtectedRemoteEvidence: Bool {
    level == .error
      || level == .critical
      || !issueReferences.isEmpty
  }
}

extension InstantDBLogger: TestDependencyKey {
  public static var testValue: InstantDBLogger { .noop }
  public static var previewValue: InstantDBLogger {
    var client = InstantDBLogger()
    client.recent = { _, _ in
      [
        InstantDBLogEntry(
          id: "preview-log",
          timestampMs: 1_700_000_000_000,
          level: .info,
          subsystem: "preview",
          category: "app",
          name: "preview.ready",
          message: "Instant debug logging is ready.",
          metadata: [:],
          sessionID: "preview-session",
          platform: "preview",
          deviceName: "Preview",
          appVersion: "1",
          buildCommit: "preview",
          fileID: "Preview.swift",
          function: "preview",
          sourceLine: 1
        )
      ]
    }
    return client
  }
}

extension InstantDBLogger {
  public func enqueue(
    level: InstantDBLogLevel = .info,
    category: String,
    name: String,
    message: String,
    metadata: [String: String] = [:],
    fileID: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) {
    let event = InstantDBLogEvent(
      timestampMs: Date().timeIntervalSince1970 * 1_000,
      level: level,
      category: category,
      name: name,
      message: message,
      metadata: metadata,
      fileID: fileID,
      line: line,
      function: function
    )
    ScribeDeepgramLog.append(event)
    InstantDBLogEnqueueBuffer.shared.enqueue(event, append: append)
  }

  public func log(
    level: InstantDBLogLevel = .info,
    category: String,
    name: String,
    message: String,
    metadata: [String: String] = [:],
    fileID: StaticString = #fileID,
    line: UInt = #line,
    function: StaticString = #function
  ) async {
    let event = InstantDBLogEvent(
      timestampMs: Date().timeIntervalSince1970 * 1_000,
      level: level,
      category: category,
      name: name,
      message: message,
      metadata: metadata,
      fileID: fileID,
      line: line,
      function: function
    )
    ScribeDeepgramLog.append(event)
    await append(event)
  }

  /// Writes every event to each destination so one diagnostics lane can still report another's
  /// failure.
  ///
  /// Scribe develops `instant-data-swift` alongside the app, so the Instant client is itself a
  /// routine suspect. A lane that depends on that client cannot be trusted to report its own
  /// outage: on 2026-08-04 the InstantDB `debugLogs` lane went dark on the iPad for two days while
  /// the app kept running, and only the tailnet WebSocket lane recorded the failing startup. Fanning
  /// out keeps the two lanes failing independently, which is the whole point of running both.
  ///
  /// Delivery is concurrent and isolated. `append` never rethrows, and `flush` drains every
  /// destination before rethrowing the first failure, so a wedged lane cannot stop the others.
  public static func fanOut(_ destinations: [Self]) -> Self {
    guard let primary = destinations.first else { return .noop }
    guard destinations.count > 1 else { return primary }
    return Self(
      append: { event in
        await withTaskGroup(of: Void.self) { group in
          for destination in destinations {
            group.addTask { await destination.append(event) }
          }
        }
      },
      // Reads stay on the primary lane deliberately: interleaving two independent journals would
      // produce an order that matches neither, and the caller cannot tell which lane dropped what.
      recent: { limit, sessionID in try await primary.recent(limit, sessionID) },
      observeRecent: { limit, sessionID in await primary.observeRecent(limit, sessionID) },
      flush: {
        var firstFailure: (any Error)?
        for destination in destinations {
          do {
            try await destination.flush()
          } catch {
            firstFailure = firstFailure ?? error
          }
        }
        if let firstFailure { throw firstFailure }
      },
      setRemoteObservabilityEnabled: { isEnabled in
        for destination in destinations {
          await destination.setRemoteObservabilityEnabled(isEnabled)
        }
      },
      queueMetrics: { primary.queueMetrics() }
    )
  }

  public static var noop: Self {
    var client = Self()
    client.append = { _ in }
    client.recent = { _, _ in [] }
    client.observeRecent = { _, _ in .finished }
    client.flush = {}
    client.setRemoteObservabilityEnabled = { _ in }
    client.queueMetrics = { InstantDBLogEnqueueBuffer.shared.metrics() }
    return client
  }
}

extension InstantDBLogger: DependencyKey {
  public static var liveValue: InstantDBLogger { testValue }
}

extension DependencyValues {
  public var instantDBLogger: InstantDBLogger {
    get { self[InstantDBLogger.self] }
    set { self[InstantDBLogger.self] = newValue }
  }
}

extension InstantDBLogger {
  public static func instant(
    client: InstantSwiftDataClient,
    context: InstantDBLogContext,
    // Keep batches well under Instant's 256 in-flight step budget. Each log
    // entity expands to ~20–22 attribute ops; 32× logs → ~700 ops per mutation
    // (field thrash: permanent HOL + multi-GB idle while dual-writing library
    // diagnostics). 8 logs ≈ ~176 ops and still amortizes network.
    batchSize: Int = 8,
    batchInterval: Duration = .milliseconds(100),
    now: @escaping @Sendable () -> Date = { Date() },
    uuid: @escaping @Sendable () -> UUID = { UUID() },
    localFallback: @escaping @Sendable (InstantDBLogEvent) -> Void = {
      ScribeDeepgramLog.append($0)
    }
  ) -> Self {
    let writer = InstantDBLogWriter(
      client: client,
      context: context,
      batchSize: batchSize,
      batchInterval: batchInterval,
      now: now,
      uuid: uuid,
      localFallback: localFallback
    )
    return Self(
      append: { event in await writer.append(event) },
      recent: { limit, sessionID in try await writer.recent(limit: limit, sessionID: sessionID) },
      observeRecent: { limit, sessionID in
        await writer.observeRecent(limit: limit, sessionID: sessionID)
      },
      flush: {
        await InstantDBLogger.waitForEnqueuedEvents()
        try await writer.flush()
      },
      setRemoteObservabilityEnabled: { _ in },
      queueMetrics: { InstantDBLogEnqueueBuffer.shared.metrics() }
    )
  }
}

public enum InstantDBLogSchema {
  public static let namespace = "debugLogs"
  public static let issueLinkNamespace = "instantToolsLogIssueLinks"
  public static let instantAttributes: [InstantAttribute] =
    InstantDBLogEntity.instantAttributes + InstantDBLogIssueLinkEntity.instantAttributes
}

public enum InstantDBLoggerError: Error, LocalizedError {
  case deliveryBackpressured
  case deliveryTimedOut

  public var errorDescription: String? {
    switch self {
    case .deliveryBackpressured:
      "The diagnostics outbox is full, so the batch remains in the bounded local journal."
    case .deliveryTimedOut:
      "Timed out waiting for InstantDB debug logs to reach the server."
    }
  }
}

private actor InstantDBLogWriter {
  private struct PendingEntry: Sendable {
    var entry: InstantDBLogEntry
    var event: InstantDBLogEvent
  }

  let batchInterval: Duration
  let batchSize: Int
  let client: InstantSwiftDataClient
  let context: InstantDBLogContext
  let now: @Sendable () -> Date
  let uuid: @Sendable () -> UUID
  let localFallback: @Sendable (InstantDBLogEvent) -> Void
  let fallbackLogger = Logger(subsystem: "InstantDBLogger", category: "Writer")
  private var didReportBackpressure = false
  private var isDelivering = false
  private var isFlushing = false
  private var pendingEntries: [PendingEntry] = []
  private var scheduledDelivery: Task<Void, Never>?

  init(
    client: InstantSwiftDataClient,
    context: InstantDBLogContext,
    batchSize: Int,
    batchInterval: Duration,
    now: @escaping @Sendable () -> Date,
    uuid: @escaping @Sendable () -> UUID,
    localFallback: @escaping @Sendable (InstantDBLogEvent) -> Void
  ) {
    self.client = client
    self.context = context
    self.batchSize = max(1, batchSize)
    self.batchInterval = batchInterval
    self.now = now
    self.uuid = uuid
    self.localFallback = localFallback
  }

  func append(_ event: InstantDBLogEvent) async {
    // Instant-only filter (Tailnet WS still receives these via fanOut):
    // notice/info library outbox/mutation/query/transport chatter dual-written
    // into debugLogs re-enters this writer as multi-attr batches and was the
    // multi‑GB idle thrash on iPad 2026-08-05 (HOL + transaction.server-accepted
    // storm on debug-log-batch mutations). Keep warning+ for Instant forensics.
    if Self.shouldDropFromInstantLane(event) {
      return
    }
    let timestampMs = event.timestampMs ?? now().timeIntervalSince1970 * 1_000
    let timestamp = Date(timeIntervalSince1970: timestampMs / 1_000)
    let entry = InstantDBLogEntry(
      id: uuid().uuidString.lowercased(),
      timestampMs: timestampMs,
      level: event.level,
      subsystem: context.subsystem,
      category: event.category,
      name: event.name,
      message: event.message,
      metadata: event.metadata,
      sessionID: context.sessionID,
      platform: context.platform,
      deviceName: context.deviceName,
      appVersion: context.appVersion,
      buildCommit: context.buildCommit,
      fileID: event.fileID,
      function: event.function,
      sourceLine: event.sourceLine,
      timestampLocal: Self.localTimestamp(
        timestamp,
        timeZoneIdentifier: context.timeZoneIdentifier
      ),
      projectName: context.projectName,
      buildBranch: context.buildBranch,
      buildIsDirty: context.buildIsDirty,
      contributingPaths: event.contributingPaths,
      issueReferences: event.issueReferences
    )
    let pendingEntry = PendingEntry(entry: entry, event: event)
    if pendingEntries.count == InstantDBLogDeliveryLimits.maximumPendingEvents {
      let replacementIndex =
        pendingEntries.firstIndex { !$0.event.isProtectedRemoteEvidence }
        ?? (event.isProtectedRemoteEvidence ? pendingEntries.startIndex : nil)
      guard let replacementIndex else { return }
      pendingEntries.remove(at: replacementIndex)
    }
    pendingEntries.append(pendingEntry)
    guard !isFlushing else { return }
    scheduleDeliveryIfNeeded()
  }

  /// Drop high-volume Instant-library diagnostics from the Instant debugLogs
  /// lane only. Warning/error/critical still land for forensics.
  private static func shouldDropFromInstantLane(_ event: InstantDBLogEvent) -> Bool {
    guard event.category.hasPrefix("instant-library.") else { return false }
    let chatterCategories: Set<String> = [
      "instant-library.outbox",
      "instant-library.mutation",
      "instant-library.query",
      "instant-library.transport",
    ]
    guard chatterCategories.contains(event.category) else { return false }
    switch event.level {
    case .debug, .info, .notice:
      return true
    case .warning, .error, .critical:
      return false
    }
  }

  private func scheduleDeliveryIfNeeded(delay: Duration? = nil) {
    guard scheduledDelivery == nil, !pendingEntries.isEmpty, !isFlushing else { return }
    let delay = delay ?? batchInterval
    scheduledDelivery = Task(priority: .utility) { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self?.scheduledBatchIsReady()
    }
  }

  private func scheduledBatchIsReady() async {
    scheduledDelivery = nil
    guard !isFlushing else { return }
    let delivered = (try? await deliverNextBatch()) == true
    scheduleDeliveryIfNeeded(
      delay: delivered && pendingEntries.count >= batchSize ? .zero : nil
    )
  }

  @discardableResult
  private func deliverNextBatch() async throws -> Bool {
    guard !isDelivering, !pendingEntries.isEmpty else { return false }
    isDelivering = true
    defer { isDelivering = false }
    let pendingMutationCount = await client.pendingMutations()
      .lazy
      .filter { $0.status == .pending }
      .count
    guard pendingMutationCount < InstantDBLogDeliveryLimits.maximumPendingMutations else {
      if !didReportBackpressure, let first = pendingEntries.first {
        localFallback(
          InstantDBLogEvent(
            level: .warning,
            category: "diagnostics",
            name: "diagnostics.remote-delivery.backpressured",
            message:
              "Skipped remote diagnostic persistence because its Instant outbox is saturated.",
            metadata: [
              "failedEventCategory": first.event.category,
              "failedEventName": first.event.name,
              "pendingMutationCount": pendingMutationCount.description,
              "pendingMutationLimit":
                InstantDBLogDeliveryLimits.maximumPendingMutations.description,
            ],
            issueReferences: first.event.issueReferences
          )
        )
        fallbackLogger.warning(
          "Paused Instant debug logging at \(pendingMutationCount, privacy: .public) pending mutations."
        )
        didReportBackpressure = true
      }
      throw InstantDBLoggerError.deliveryBackpressured
    }
    didReportBackpressure = false

    let batch = Array(pendingEntries.prefix(batchSize))
    do {
      let entitiesAndLinks = try batch.map { pendingEntry in
        (
          try InstantDBLogEntity(pendingEntry.entry),
          try pendingEntry.entry.issueReferences.map {
            try InstantDBLogIssueLinkEntity(
              entry: pendingEntry.entry,
              logNamespace: InstantDBLogSchema.namespace,
              reference: $0
            )
          }
        )
      }
      let first = batch[0].entry
      let transactionID =
        batch.count == 1
        ? "debug-log-\(first.id)"
        : "debug-log-batch-\(first.id)"
      let createdAt = InstantTimestamp(
        milliseconds: Int64(first.timestampMs.rounded())
      )
      try await client.transact(id: transactionID, createdAt: createdAt) {
        for (entity, issueLinks) in entitiesAndLinks {
          entity.upsertMutation
          for issueLink in issueLinks {
            issueLink.upsertMutation
          }
        }
      }
      let acknowledgedIDs = Set(batch.map(\.entry.id))
      pendingEntries.removeAll { acknowledgedIDs.contains($0.entry.id) }
      return true
    } catch {
      let error = error as NSError
      let first = batch[0]
      localFallback(
        InstantDBLogEvent(
          level: .error,
          category: "diagnostics",
          name: "diagnostics.remote-delivery.failed",
          message: "Could not persist a structured diagnostic batch to InstantDB.",
          metadata: [
            "batchEventCount": batch.count.description,
            "errorCode": error.code.description,
            "errorDomain": error.domain,
            "failedEventCategory": first.event.category,
            "failedEventName": first.event.name,
          ],
          issueReferences: batch.flatMap(\.event.issueReferences)
        )
      )
      fallbackLogger.error(
        "Could not persist Instant debug log batch: \(error.localizedDescription, privacy: .public)"
      )
      throw error
    }
  }

  private static func localTimestamp(
    _ date: Date,
    timeZoneIdentifier: String
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
    return formatter.string(from: date)
  }

  func recent(limit: Int, sessionID: String?) async throws -> [InstantDBLogEntry] {
    let boundedLimit = UInt(max(1, min(limit, 1_000)))
    let baseQuery = InstantDBLogEntity.query
      .order(InstantDBLogEntity.timestampMs, .descending)
      .limit(boundedLimit)
    let query =
      sessionID.map {
        baseQuery.where(InstantDBLogEntity.sessionID == $0)
      } ?? baseQuery
    return try await client.query(query).map { try $0.entry }
  }

  func observeRecent(
    limit: Int,
    sessionID: String?
  ) async -> AsyncStream<[InstantDBLogEntry]> {
    let boundedLimit = UInt(max(1, min(limit, 1_000)))
    let baseQuery = InstantDBLogEntity.query
      .order(InstantDBLogEntity.timestampMs, .descending)
      .limit(boundedLimit)
    let query =
      sessionID.map {
        baseQuery.where(InstantDBLogEntity.sessionID == $0)
      } ?? baseQuery
    let subscription = await client.subscribe(query)
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        do {
          for try await entities in subscription {
            continuation.yield(
              entities.compactMap { try? $0.entry }
            )
          }
        } catch {
          // Consumers can recreate the observation; logging must never crash the host app.
        }
        continuation.finish()
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
        subscription.cancel()
      }
    }
  }

  func flush() async throws {
    let targetIDs = Set(pendingEntries.map(\.entry.id))
    guard !targetIDs.isEmpty else {
      await awaitServerDeliveryWithoutFailingOnUnrelatedMutations()
      return
    }
    isFlushing = true
    scheduledDelivery?.cancel()
    scheduledDelivery = nil
    defer {
      isFlushing = false
      scheduleDeliveryIfNeeded()
    }
    while pendingEntries.contains(where: { targetIDs.contains($0.entry.id) }) {
      if try await deliverNextBatch() == false {
        try await Task.sleep(for: .milliseconds(1))
      }
    }
    await awaitServerDeliveryWithoutFailingOnUnrelatedMutations()
  }

  /// Waits for server acknowledgement without letting an unrelated mutation
  /// take remote diagnostics down with it.
  ///
  /// `waitForAllPendingMutations` is a whole-outbox barrier: it throws on the
  /// first `.failed` row it sees, whatever wrote it. A device that upgraded
  /// across the acknowledgement release carries rows that can never be retried,
  /// so every flush threw and diagnostics went permanently silent — the worst
  /// possible failure for the lane you use to diagnose the device (#134, #135).
  ///
  /// The loop above has already confirmed this flush's own entries left the
  /// queue, so the barrier is a best-effort durability check rather than this
  /// method's correctness condition. A failure is reported locally and the
  /// flush still succeeds. Delivery of the logger's own entries is unchanged;
  /// only somebody else's terminal failure stops being fatal here.
  private func awaitServerDeliveryWithoutFailingOnUnrelatedMutations() async {
    do {
      try await client.waitForAllPendingMutations(
        timeout: .seconds(10),
        pollInterval: .milliseconds(100)
      )
    } catch is CancellationError {
      // Cancellation is the caller's intent and must not be swallowed as a
      // diagnostic warning.
    } catch {
      fallbackLogger.warning(
        """
        Instant diagnostics could not confirm server delivery: \
        \(String(describing: error), privacy: .public)
        """
      )
    }
  }
}

@InstantEntity("debugLogs")
private struct InstantDBLogEntity: Codable, Hashable, InstantEntityModel {
  static let timestampMs = InstantAttributePath<Self, Double>("timestampMs")
  static let sessionID = InstantAttributePath<Self, String>("sessionID")

  var id: InstantID<Self>
  var timestampMs: Double
  var level: String
  var subsystem: String
  var category: String
  var name: String
  var message: String
  var metadataJSON: String
  var sessionID: String
  var platform: String
  var deviceName: String
  var appVersion: String
  var buildCommit: String
  var fileID: String
  var function: String
  var sourceLine: Int
  var timestampLocal: String
  var projectName: String
  var buildBranch: String
  var buildIsDirty: Bool
  var contributingPathsJSON: String
  var issueReferencesJSON: String

  init(_ entry: InstantDBLogEntry) throws {
    id = .init(rawValue: entry.id)
    timestampMs = entry.timestampMs
    level = entry.level.rawValue
    subsystem = entry.subsystem
    category = entry.category
    name = entry.name
    message = entry.message
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    metadataJSON = String(decoding: try encoder.encode(entry.metadata), as: UTF8.self)
    sessionID = entry.sessionID
    platform = entry.platform
    deviceName = entry.deviceName
    appVersion = entry.appVersion
    buildCommit = entry.buildCommit
    fileID = entry.fileID
    function = entry.function
    sourceLine = entry.sourceLine
    timestampLocal = entry.timestampLocal
    projectName = entry.projectName
    buildBranch = entry.buildBranch
    buildIsDirty = entry.buildIsDirty
    contributingPathsJSON = String(
      decoding: try encoder.encode(entry.contributingPaths),
      as: UTF8.self
    )
    issueReferencesJSON = String(
      decoding: try encoder.encode(entry.issueReferences),
      as: UTF8.self
    )
  }

  init(snapshot: InstantEntitySnapshot) throws {
    id = .init(rawValue: snapshot.id)
    timestampMs = try snapshot.logValue("timestampMs")
    level = try snapshot.logValue("level")
    subsystem = try snapshot.logValue("subsystem")
    category = try snapshot.logValue("category")
    name = try snapshot.logValue("name")
    message = try snapshot.logValue("message")
    metadataJSON = try snapshot.logValue("metadataJSON")
    sessionID = try snapshot.logValue("sessionID")
    platform = try snapshot.logValue("platform")
    deviceName = try snapshot.logValue("deviceName")
    appVersion = try snapshot.logValue("appVersion")
    buildCommit = try snapshot.logValue("buildCommit")
    fileID = try snapshot.logValue("fileID")
    function = try snapshot.logValue("function")
    sourceLine = try snapshot.logValue("sourceLine")
    timestampLocal = (try? snapshot.logValue("timestampLocal")) ?? ""
    projectName = (try? snapshot.logValue("projectName")) ?? ""
    buildBranch = (try? snapshot.logValue("buildBranch")) ?? ""
    buildIsDirty = (try? snapshot.logValue("buildIsDirty")) ?? false
    contributingPathsJSON = (try? snapshot.logValue("contributingPathsJSON")) ?? "[]"
    issueReferencesJSON = (try? snapshot.logValue("issueReferencesJSON")) ?? "[]"
  }

  var entry: InstantDBLogEntry {
    get throws {
      InstantDBLogEntry(
        id: id.rawValue,
        timestampMs: timestampMs,
        level: InstantDBLogLevel(rawValue: level) ?? .info,
        subsystem: subsystem,
        category: category,
        name: name,
        message: message,
        metadata: try JSONDecoder().decode(
          [String: String].self,
          from: Data(metadataJSON.utf8)
        ),
        sessionID: sessionID,
        platform: platform,
        deviceName: deviceName,
        appVersion: appVersion,
        buildCommit: buildCommit,
        fileID: fileID,
        function: function,
        sourceLine: sourceLine,
        timestampLocal: timestampLocal,
        projectName: projectName,
        buildBranch: buildBranch,
        buildIsDirty: buildIsDirty,
        contributingPaths: try JSONDecoder().decode(
          [LogContributingPath].self,
          from: Data(contributingPathsJSON.utf8)
        ),
        issueReferences: try JSONDecoder().decode(
          [IssueLogReference].self,
          from: Data(issueReferencesJSON.utf8)
        )
      )
    }
  }

  var upsertMutation: InstantMutation {
    Self.update(
      id: id,
      Self.timestampMs.set(timestampMs),
      Self.level.set(level),
      Self.subsystem.set(subsystem),
      Self.category.set(category),
      Self.name.set(name),
      Self.message.set(message),
      Self.metadataJSON.set(metadataJSON),
      Self.sessionID.set(sessionID),
      Self.platform.set(platform),
      Self.deviceName.set(deviceName),
      Self.appVersion.set(appVersion),
      Self.buildCommit.set(buildCommit),
      Self.fileID.set(fileID),
      Self.function.set(function),
      Self.sourceLine.set(sourceLine),
      Self.timestampLocal.set(timestampLocal),
      Self.projectName.set(projectName),
      Self.buildBranch.set(buildBranch),
      Self.buildIsDirty.set(buildIsDirty),
      Self.contributingPathsJSON.set(contributingPathsJSON),
      Self.issueReferencesJSON.set(issueReferencesJSON)
    )
  }
}

@InstantEntity("instantToolsLogIssueLinks")
private struct InstantDBLogIssueLinkEntity: Codable, Hashable, InstantEntityModel {
  var category: String
  var contributingPathsJSON: String
  var id: InstantID<Self>
  var issueID: String
  var level: String
  var logID: String
  var logNamespace: String
  var message: String
  var name: String
  var timestampMs: Double
  var viewerURL: String

  init(
    entry: InstantDBLogEntry,
    logNamespace: String,
    reference: IssueLogReference
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    category = entry.category
    contributingPathsJSON = String(
      decoding: try encoder.encode(entry.contributingPaths),
      as: UTF8.self
    )
    id = .init(
      rawValue: deterministicIssueLinkID(
        logNamespace: logNamespace,
        logID: entry.id,
        issueID: reference.issueID
      )
    )
    issueID = reference.issueID
    level = entry.level.rawValue
    logID = entry.id
    self.logNamespace = logNamespace
    message = entry.message
    name = entry.name
    timestampMs = entry.timestampMs
    viewerURL = reference.viewerURL
  }

  init(snapshot: InstantEntitySnapshot) throws {
    category = try snapshot.logValue("category")
    contributingPathsJSON = try snapshot.logValue("contributingPathsJSON")
    id = .init(rawValue: snapshot.id)
    issueID = try snapshot.logValue("issueID")
    level = try snapshot.logValue("level")
    logID = try snapshot.logValue("logID")
    logNamespace = try snapshot.logValue("logNamespace")
    message = try snapshot.logValue("message")
    name = try snapshot.logValue("name")
    timestampMs = try snapshot.logValue("timestampMs")
    viewerURL = try snapshot.logValue("viewerURL")
  }

  var upsertMutation: InstantMutation {
    Self.update(
      id: id,
      Self.category.set(category),
      Self.contributingPathsJSON.set(contributingPathsJSON),
      Self.issueID.set(issueID),
      Self.level.set(level),
      Self.logID.set(logID),
      Self.logNamespace.set(logNamespace),
      Self.message.set(message),
      Self.name.set(name),
      Self.timestampMs.set(timestampMs),
      Self.viewerURL.set(viewerURL)
    )
  }
}

private func deterministicIssueLinkID(
  logNamespace: String,
  logID: String,
  issueID: String
) -> String {
  let name = "\(logNamespace)/\(logID)/issues/\(issueID)"
  var input = Data([
    0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
  ])
  input.append(contentsOf: name.utf8)
  var bytes = Array(Insecure.SHA1.hash(data: input).prefix(16))
  bytes[6] = (bytes[6] & 0x0f) | 0x50
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  let hex = bytes.map { String(format: "%02x", $0) }.joined()
  return [
    String(hex.prefix(8)),
    String(hex.dropFirst(8).prefix(4)),
    String(hex.dropFirst(12).prefix(4)),
    String(hex.dropFirst(16).prefix(4)),
    String(hex.dropFirst(20)),
  ].joined(separator: "-")
}

extension InstantEntitySnapshot {
  fileprivate func logValue<Value: InstantValueDecodable>(_ path: String) throws -> Value {
    try Value.decodeInstantValue(
      values[path]?.first,
      namespace: namespace,
      path: path,
      localID: id,
      operation: "decode Instant debug log"
    )
  }
}
