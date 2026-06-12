import Foundation

/// Configuration utilities for CLI
enum Config {
  static func resolveAppId(_ explicit: String?) throws -> String {
    if let appId = explicit { return appId }
    if let envAppId = ProcessInfo.processInfo.environment["INSTANT_APP_ID"] {
      return envAppId
    }
    throw CLIError.missingAppId
  }
  
  static func resolveToken(_ explicit: String?) throws -> String {
    if let token = explicit { return token }
    if let envToken = ProcessInfo.processInfo.environment["INSTANT_ADMIN_TOKEN"] {
      return envToken
    }
    throw CLIError.missingToken
  }
}
