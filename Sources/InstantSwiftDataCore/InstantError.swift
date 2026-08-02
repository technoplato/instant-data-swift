import Foundation

public struct InstantError: Error, Hashable, Codable, Sendable, CustomStringConvertible {
  public enum Code: String, Codable, Sendable {
    case validationFailed
    case persistenceFailed
    case authFailed
    case networkFailed
    case permissionRejected
    case decodeFailed
    case implementationFailed
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
    var parts = ["\(operation): \(message)"]
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

  public var recoveryMessage: String {
    recovery
  }
}
