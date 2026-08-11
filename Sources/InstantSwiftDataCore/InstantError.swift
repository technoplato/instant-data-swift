import Foundation

/// Structured Instant failure with a human-readable summary for UI and logs.
///
/// Do not rely on Swift's default `localizedDescription` for this type. Without
/// `LocalizedError` / `CustomNSError`, UIKit and SwiftUI collapse every case to
/// `InstantSwiftDataCore.InstantError error 1`, which hides `code`, `operation`,
/// `message`, and `recovery`. Those fields are the product surface for bootstrap
/// and delivery failures.
public struct InstantError: Error, Hashable, Codable, Sendable, CustomStringConvertible {
  public enum Code: String, Codable, Sendable, CaseIterable {
    case validationFailed
    case persistenceFailed
    case authFailed
    case networkFailed
    case permissionRejected
    case decodeFailed
    case implementationFailed

    /// Stable `NSError` / `CustomNSError` integer for this code.
    ///
    /// Starts at 1 so a missing bridge never looks like a valid Instant code.
    public var stableErrorCode: Int {
      switch self {
      case .validationFailed: 1
      case .persistenceFailed: 2
      case .authFailed: 3
      case .networkFailed: 4
      case .permissionRejected: 5
      case .decodeFailed: 6
      case .implementationFailed: 7
      }
    }

    /// Short product-facing label for alerts and diagnostics.
    public var displayName: String {
      switch self {
      case .validationFailed:
        "Schema or configuration validation failed"
      case .persistenceFailed:
        "Local Instant cache failed"
      case .authFailed:
        "Authentication failed"
      case .networkFailed:
        "Network or live transport failed"
      case .permissionRejected:
        "Permission rejected"
      case .decodeFailed:
        "Could not decode Instant data"
      case .implementationFailed:
        "Internal Instant implementation error"
      }
    }
  }

  public var code: Code
  public var operation: String
  public var namespace: String?
  public var path: String?
  public var localID: String?
  public var serverEventID: String?
  public var serverStatus: Int?
  public var serverType: String?
  public var serverHint: InstantLiveJSONValue?
  public var serverTraceID: String?
  public var serverOriginalEventTraceID: String?
  public var localMutationDisposition: InstantMutationLocalStateDisposition?
  public var recovery: String
  public var message: String
  public var cachedQuery: InstantCachedQuery?

  public init(
    code: Code,
    operation: String,
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil,
    serverEventID: String? = nil,
    message: String,
    recovery: String,
    cachedQuery: InstantCachedQuery? = nil
  ) {
    self.code = code
    self.operation = operation
    self.namespace = namespace
    self.path = path
    self.localID = localID
    self.serverEventID = serverEventID
    self.serverStatus = nil
    self.serverType = nil
    self.serverHint = nil
    self.serverTraceID = nil
    self.serverOriginalEventTraceID = nil
    self.localMutationDisposition = nil
    self.message = message
    self.recovery = recovery
    self.cachedQuery = cachedQuery
  }

  public init(
    code: Code,
    operation: String,
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil,
    serverEventID: String? = nil,
    serverStatus: Int? = nil,
    serverType: String? = nil,
    serverHint: InstantLiveJSONValue? = nil,
    serverTraceID: String? = nil,
    serverOriginalEventTraceID: String? = nil,
    localMutationDisposition: InstantMutationLocalStateDisposition? = nil,
    message: String,
    recovery: String,
    cachedQuery: InstantCachedQuery? = nil
  ) {
    self.code = code
    self.operation = operation
    self.namespace = namespace
    self.path = path
    self.localID = localID
    self.serverEventID = serverEventID
    self.serverStatus = serverStatus
    self.serverType = serverType
    self.serverHint = serverHint
    self.serverTraceID = serverTraceID
    self.serverOriginalEventTraceID = serverOriginalEventTraceID
    self.localMutationDisposition = localMutationDisposition
    self.message = message
    self.recovery = recovery
    self.cachedQuery = cachedQuery
  }

  public var description: String {
    var parts = ["[\(code.rawValue)] \(operation): \(message)"]
    if let namespace {
      parts.append("namespace: \(namespace)")
    }
    if let path {
      parts.append("path: \(path)")
    }
    if let localID {
      parts.append("local id: \(localID)")
    }
    if let serverEventID {
      parts.append("server event: \(serverEventID)")
    }
    if let serverStatus {
      parts.append("server status: \(serverStatus)")
    }
    if let serverType {
      parts.append("server type: \(serverType)")
    }
    if let serverTraceID {
      parts.append("server trace: \(serverTraceID)")
    }
    if let serverOriginalEventTraceID {
      parts.append("server original-event trace: \(serverOriginalEventTraceID)")
    }
    if let localMutationDisposition {
      parts.append("local mutation state: \(localMutationDisposition.rawValue)")
    }
    if let serverHint {
      parts.append("server hint: \(String(describing: serverHint))")
    }
    if let cachedQuery {
      parts.append(
        "cached query: \(cachedQuery.queryID) results: \(cachedQuery.emission.values.count)"
      )
    }
    parts.append("fix: \(recovery)")
    return parts.joined(separator: "; ")
  }

  /// Multi-line summary intended for alerts and bootstrap failure screens.
  public var userFacingSummary: String {
    var lines = [
      code.displayName + ".",
      "While: \(operation).",
      message,
    ]
    if let namespace {
      lines.append("Namespace: \(namespace).")
    }
    if let path {
      lines.append("Path: \(path).")
    }
    if let serverStatus {
      lines.append("Server status: \(serverStatus).")
    }
    if let serverType {
      lines.append("Server type: \(serverType).")
    }
    if let serverTraceID {
      lines.append("Server trace: \(serverTraceID).")
    }
    lines.append("What to do: \(recovery)")
    return lines.joined(separator: "\n")
  }

  public var recoveryMessage: String {
    recovery
  }
}

extension InstantError: LocalizedError {
  public var errorDescription: String? {
    userFacingSummary
  }

  public var failureReason: String? {
    "\(code.displayName) during \(operation)"
  }

  public var recoverySuggestion: String? {
    recovery
  }

  public var helpAnchor: String? {
    code.rawValue
  }
}

extension InstantError: CustomNSError {
  public static var errorDomain: String { "InstantSwiftDataCore.InstantError" }

  public var errorCode: Int { code.stableErrorCode }

  public var errorUserInfo: [String: Any] {
    var info: [String: Any] = [
      NSLocalizedDescriptionKey: userFacingSummary,
      NSLocalizedFailureReasonErrorKey: failureReason ?? code.displayName,
      NSLocalizedRecoverySuggestionErrorKey: recovery,
      "InstantErrorCode": code.rawValue,
      "InstantErrorOperation": operation,
      "InstantErrorMessage": message,
      "InstantErrorRecovery": recovery,
    ]
    if let namespace { info["InstantErrorNamespace"] = namespace }
    if let path { info["InstantErrorPath"] = path }
    if let localID { info["InstantErrorLocalID"] = localID }
    if let serverEventID { info["InstantErrorServerEventID"] = serverEventID }
    if let serverStatus { info["InstantErrorServerStatus"] = serverStatus }
    if let serverType { info["InstantErrorServerType"] = serverType }
    if let serverTraceID { info["InstantErrorServerTraceID"] = serverTraceID }
    if let serverOriginalEventTraceID {
      info["InstantErrorServerOriginalEventTraceID"] = serverOriginalEventTraceID
    }
    if let localMutationDisposition {
      info["InstantErrorLocalMutationDisposition"] = localMutationDisposition.rawValue
    }
    return info
  }
}
