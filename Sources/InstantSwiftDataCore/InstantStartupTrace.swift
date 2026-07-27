import Foundation

#if canImport(OSLog)
  import OSLog
#endif

public struct InstantStartupTraceEvent: Hashable, Sendable {
  public enum Kind: String, Hashable, Sendable {
    case started
    case completed
    case failed
    case milestone
  }

  public var traceID: String
  public var phase: String
  public var kind: Kind
  public var elapsedMilliseconds: Int64
  public var durationMilliseconds: Int64?
  public var metadata: [String: String]

  public init(
    traceID: String,
    phase: String,
    kind: Kind,
    elapsedMilliseconds: Int64,
    durationMilliseconds: Int64? = nil,
    metadata: [String: String] = [:]
  ) {
    self.traceID = traceID
    self.phase = phase
    self.kind = kind
    self.elapsedMilliseconds = elapsedMilliseconds
    self.durationMilliseconds = durationMilliseconds
    self.metadata = metadata
  }
}

public struct InstantStartupStopwatch: Sendable {
  fileprivate var startedAtNanoseconds: UInt64
}

/// A lightweight, monotonic trace shared by bootstrap, persistence, queries, and product libraries.
///
/// Live traces emit unified-log events and feed the existing structured Instant diagnostics sink. A
/// custom recorder can be supplied in tests or performance harnesses without changing app features.
// SAFETY: Immutable stored properties and the Sendable recorder closure make concurrent access safe;
// no actor or lock is required after initialization.
public final class InstantStartupTrace: @unchecked Sendable {
  public let id: String

  private let startedAtNanoseconds: UInt64
  private let recordOperation: @Sendable (InstantStartupTraceEvent) -> Void

  public init(
    id: String = UUID().uuidString.lowercased(),
    record: @escaping @Sendable (InstantStartupTraceEvent) -> Void
  ) {
    self.id = id
    self.startedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
    self.recordOperation = record
  }

  public static var disabled: Self {
    Self(id: "disabled") { _ in }
  }

  public static func live(id: String = UUID().uuidString.lowercased()) -> Self {
    Self(id: id) { event in
      recordLive(event)
    }
  }

  @discardableResult
  public func started(
    _ phase: String,
    metadata: [String: String] = [:]
  ) -> InstantStartupStopwatch {
    let stopwatch = InstantStartupStopwatch(
      startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds
    )
    record(.started, phase: phase, metadata: metadata)
    return stopwatch
  }

  public func completed(
    _ phase: String,
    since stopwatch: InstantStartupStopwatch,
    metadata: [String: String] = [:]
  ) {
    completed(
      phase,
      durationMilliseconds: milliseconds(
        from: stopwatch.startedAtNanoseconds,
        to: DispatchTime.now().uptimeNanoseconds
      ),
      metadata: metadata
    )
  }

  public func completed(
    _ phase: String,
    durationMilliseconds: Int64,
    metadata: [String: String] = [:]
  ) {
    record(
      .completed,
      phase: phase,
      durationMilliseconds: max(0, durationMilliseconds),
      metadata: metadata
    )
  }

  public func failed(
    _ phase: String,
    error: any Error,
    since stopwatch: InstantStartupStopwatch,
    metadata: [String: String] = [:]
  ) {
    var metadata = metadata
    metadata["errorType"] = String(reflecting: type(of: error))
    metadata["errorDescription"] = String(describing: error)
    record(
      .failed,
      phase: phase,
      durationMilliseconds: milliseconds(
        from: stopwatch.startedAtNanoseconds,
        to: DispatchTime.now().uptimeNanoseconds
      ),
      metadata: metadata
    )
  }

  public func milestone(
    _ phase: String,
    metadata: [String: String] = [:]
  ) {
    record(.milestone, phase: phase, metadata: metadata)
  }

  public func stopwatch() -> InstantStartupStopwatch {
    InstantStartupStopwatch(startedAtNanoseconds: DispatchTime.now().uptimeNanoseconds)
  }

  private func record(
    _ kind: InstantStartupTraceEvent.Kind,
    phase: String,
    durationMilliseconds: Int64? = nil,
    metadata: [String: String]
  ) {
    recordOperation(
      InstantStartupTraceEvent(
        traceID: id,
        phase: phase,
        kind: kind,
        elapsedMilliseconds: milliseconds(
          from: startedAtNanoseconds,
          to: DispatchTime.now().uptimeNanoseconds
        ),
        durationMilliseconds: durationMilliseconds,
        metadata: metadata
      )
    )
  }

  private func milliseconds(
    from startNanoseconds: UInt64,
    to endNanoseconds: UInt64
  ) -> Int64 {
    guard endNanoseconds >= startNanoseconds else { return 0 }
    let milliseconds = (endNanoseconds - startNanoseconds) / 1_000_000
    return Int64(clamping: milliseconds)
  }

  private static func recordLive(_ event: InstantStartupTraceEvent) {
    var metadata = event.metadata
    metadata["traceID"] = event.traceID
    metadata["phase"] = event.phase
    metadata["kind"] = event.kind.rawValue
    metadata["elapsedMilliseconds"] = String(event.elapsedMilliseconds)
    if let durationMilliseconds = event.durationMilliseconds {
      metadata["durationMilliseconds"] = String(durationMilliseconds)
    }

    InstantDiagnostics.shared.record(
      event.kind == .failed ? .error : .notice,
      subsystem: "instant-swift-data-core",
      category: "startup",
      event: "startup.\(event.phase).\(event.kind.rawValue)",
      message: "Instant startup trace milestone.",
      metadata: metadata,
      correlationID: event.traceID
    )

    #if canImport(OSLog)
      let metadataDescription = metadata
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: " ")
      Logger(subsystem: "com.instantdb.swift", category: "startup").notice(
        "[InstantStartup] \(metadataDescription, privacy: .public)"
      )
    #endif
  }
}
