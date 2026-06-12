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
  public var recovery: String
  public var message: String

  public init(
    code: Code,
    operation: String,
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil,
    serverEventID: String? = nil,
    message: String,
    recovery: String
  ) {
    self.code = code
    self.operation = operation
    self.namespace = namespace
    self.path = path
    self.localID = localID
    self.serverEventID = serverEventID
    self.message = message
    self.recovery = recovery
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
    parts.append("fix: \(recovery)")
    return parts.joined(separator: "; ")
  }
}
