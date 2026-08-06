import Foundation
import InstantSwiftData

extension InstantDBLogger {
  /// Maps an Instant library diagnostic level onto the host log level.
  ///
  /// Library `trace` collapses to `debug` because the host enum has no trace case.
  public static func logLevel(
    bridging level: InstantDiagnosticLevel
  ) -> InstantDBLogLevel {
    switch level {
    case .trace, .debug:
      return .debug
    case .info:
      return .info
    case .notice:
      return .notice
    case .warning:
      return .warning
    case .error:
      return .error
    case .critical:
      return .critical
    }
  }

  /// Forwards `InstantDiagnostics` entries into this dual-write logger (Tailnet WS
  /// + Instant debugLogs when those lanes are configured and reachable).
  ///
  /// Safe when the collector is down: enqueue is non-blocking and the WebSocket
  /// writer already fails soft. Call once at Scribe Instant bootstrap.
  /// High-chatter Instant library categories. Dual-writing these into Instant
  /// `debugLogs` re-enters the outbox (each batch is hundreds of tx steps) and
  /// was the primary idle multi‑GB thrash on iPad 2026-08-05. Tailnet still
  /// receives library thrash signals via notice+ events (HOL wait, reclaim) and
  /// InstantDiagnostics file configuration when enabled.
  private static let dualWriteChatterCategories: Set<String> = [
    "outbox",
    "query",
    "transport",
    "mutation",
  ]

  @discardableResult
  public func bridgeInstantDiagnostics(
    minimumLevel: InstantDiagnosticLevel = .info
  ) -> UUID {
    let logger = self
    return InstantDiagnostics.shared.addHandler { entry in
      guard entry.level.priorityBridgeComparable(to: minimumLevel) else { return }
      // Drop routine chatter entirely for Instant dual-write. Notice+ still
      // passes (e.g. outbox.flush.head-of-line-wait, reclaim, failures).
      if Self.dualWriteChatterCategories.contains(entry.category),
        entry.level.priorityBridgeComparable(to: .notice) == false
      {
        return
      }
      var metadata = entry.metadata
      metadata["librarySubsystem"] = entry.subsystem
      metadata["libraryCategory"] = entry.category
      metadata["librarySessionID"] = entry.sessionID
      metadata["librarySequence"] = entry.sequence.description
      metadata["libraryProcessID"] = entry.processID.description
      metadata["libraryProcessName"] = entry.processName
      metadata["libraryFileID"] = entry.fileID
      metadata["libraryFunction"] = entry.function
      metadata["libraryLine"] = entry.line.description
      if let correlationID = entry.correlationID {
        metadata["libraryCorrelationID"] = correlationID
      }
      var event = InstantDBLogEvent(
        timestampMs: Double(entry.timestampMilliseconds),
        level: Self.logLevel(bridging: entry.level),
        // Prefix so Tailnet filters can isolate library-originated rows.
        category: "instant-library.\(entry.category)",
        name: entry.event,
        message: entry.message,
        metadata: metadata
      )
      event.fileID = entry.fileID
      event.function = entry.function
      event.sourceLine = Int(entry.line)
      logger.enqueue(
        level: event.level,
        category: event.category,
        name: event.name,
        message: event.message,
        metadata: event.metadata
      )
    }
  }
}

extension InstantDiagnosticLevel {
  fileprivate func priorityBridgeComparable(to minimum: InstantDiagnosticLevel) -> Bool {
    priorityValue >= minimum.priorityValue
  }

  fileprivate var priorityValue: Int {
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
