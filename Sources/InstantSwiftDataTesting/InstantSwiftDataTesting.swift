@_exported import InstantSwiftData
@_exported import InstantSwiftDataCore
import Foundation

public struct InstantValidationEvidenceSummary: Codable, Equatable, Sendable {
  public var caseID: String?
  public var side: String?
  public var appID: String?
  public var rowCount: Int
  public var ok: Bool
  public var events: [String]
  public var failedEvents: [String]

  public init<Details>(
    rows: [ValidationEvidenceRow<Details>]
  ) where Details: Encodable & Sendable {
    self.caseID = rows.sameValue(\.caseID)
    self.side = rows.sameValue(\.side)
    self.appID = rows.sameValue(\.appID)
    self.rowCount = rows.count
    self.ok = !rows.isEmpty && rows.allSatisfy(\.ok)
    self.events = rows.map(\.event)
    self.failedEvents = rows.filter { !$0.ok }.map(\.event)
  }
}

public struct InstantValidationFailure: Error, Codable, Equatable, Sendable, CustomStringConvertible {
  public var summary: InstantValidationEvidenceSummary
  public var message: String

  public init(summary: InstantValidationEvidenceSummary, message: String) {
    self.summary = summary
    self.message = message
  }

  public var description: String {
    message
  }
}

public struct InstantLocalTodoValidationRun: Sendable {
  public var result: LocalTodoValidationResult
  public var summary: InstantValidationEvidenceSummary

  public init(
    result: LocalTodoValidationResult,
    summary: InstantValidationEvidenceSummary
  ) {
    self.result = result
    self.summary = summary
  }
}

public struct InstantLocalIntegrationValidationRun: Sendable {
  public var result: LocalIntegrationValidationResult
  public var summary: InstantValidationEvidenceSummary

  public init(
    result: LocalIntegrationValidationResult,
    summary: InstantValidationEvidenceSummary
  ) {
    self.result = result
    self.summary = summary
  }
}

public struct InstantDraftValidationRun: Sendable {
  public var result: DraftValidationResult
  public var summary: InstantValidationEvidenceSummary

  public init(
    result: DraftValidationResult,
    summary: InstantValidationEvidenceSummary
  ) {
    self.result = result
    self.summary = summary
  }
}

public struct InstantPlatformAdapterValidationRun: Sendable {
  public var result: PlatformAdapterValidationResult
  public var summary: InstantValidationEvidenceSummary

  public init(
    result: PlatformAdapterValidationResult,
    summary: InstantValidationEvidenceSummary
  ) {
    self.result = result
    self.summary = summary
  }
}

public struct InstantSyncUpsRecordingValidationRun: Sendable {
  public var result: SyncUpsRecordingValidationResult
  public var summary: InstantValidationEvidenceSummary

  public init(
    result: SyncUpsRecordingValidationResult,
    summary: InstantValidationEvidenceSummary
  ) {
    self.result = result
    self.summary = summary
  }
}

public enum InstantSwiftDataTestHarness {
  public static func summarize<Details>(
    _ rows: [ValidationEvidenceRow<Details>]
  ) -> InstantValidationEvidenceSummary where Details: Encodable & Sendable {
    InstantValidationEvidenceSummary(rows: rows)
  }

  public static func requireAllEvidenceOK<Details>(
    _ rows: [ValidationEvidenceRow<Details>]
  ) throws -> InstantValidationEvidenceSummary where Details: Encodable & Sendable {
    let summary = summarize(rows)
    guard summary.rowCount > 0 else {
      throw InstantValidationFailure(
        summary: summary,
        message: "Expected at least one validation evidence row."
      )
    }
    guard summary.ok else {
      throw InstantValidationFailure(
        summary: summary,
        message: "Validation evidence contains failed events: \(summary.failedEvents.joined(separator: ", "))."
      )
    }
    return summary
  }

  public static func runLocalTodoValidation(
    appID: String = "local-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> InstantLocalTodoValidationRun {
    let result = try await InstantSwiftDataLocalTodoValidation.run(
      appID: appID,
      cacheURL: cacheURL,
      timestamp: timestamp,
      makeID: makeID
    )
    return InstantLocalTodoValidationRun(
      result: result,
      summary: try requireAllEvidenceOK(result.evidence)
    )
  }

  public static func runLocalIntegrationValidation(
    appID: String = "local-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> InstantLocalIntegrationValidationRun {
    let result = try await InstantSwiftDataLocalIntegrationValidation.run(
      appID: appID,
      cacheURL: cacheURL,
      timestamp: timestamp,
      makeID: makeID
    )
    return InstantLocalIntegrationValidationRun(
      result: result,
      summary: try requireAllEvidenceOK(result.evidence)
    )
  }

  public static func runDraftValidation(
    appID: String = "draft-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> InstantDraftValidationRun {
    let result = try await InstantSwiftDataDraftValidation.run(
      appID: appID,
      cacheURL: cacheURL,
      timestamp: timestamp,
      makeID: makeID
    )
    return InstantDraftValidationRun(
      result: result,
      summary: try requireAllEvidenceOK(result.evidence)
    )
  }

  public static func runPlatformAdapterValidation(
    appID: String = "platform-adapter-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> InstantPlatformAdapterValidationRun {
    let result = try await InstantSwiftDataPlatformAdapterValidation.run(
      appID: appID,
      cacheURL: cacheURL,
      timestamp: timestamp,
      makeID: makeID
    )
    return InstantPlatformAdapterValidationRun(
      result: result,
      summary: try requireAllEvidenceOK(result.evidence)
    )
  }

  public static func runSyncUpsRecordingValidation(
    appID: String = "local-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> InstantSyncUpsRecordingValidationRun {
    let result = try await InstantSwiftDataSyncUpsRecordingValidation.run(
      appID: appID,
      cacheURL: cacheURL,
      timestamp: timestamp,
      makeID: makeID
    )
    return InstantSyncUpsRecordingValidationRun(
      result: result,
      summary: try requireAllEvidenceOK(result.evidence)
    )
  }
}

private extension Array {
  func sameValue<Value: Equatable>(_ keyPath: KeyPath<Element, Value>) -> Value? {
    guard let first = first?[keyPath: keyPath],
      allSatisfy({ $0[keyPath: keyPath] == first })
    else {
      return nil
    }
    return first
  }
}
