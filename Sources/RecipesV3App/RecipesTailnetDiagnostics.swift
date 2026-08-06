import Foundation
import InstantSwiftData

/// Host wiring for Tailnet WebSocket diagnostics in Recipes.
///
/// TailnetDiagnostics is a **sibling path package** (`Packages/TailnetDiagnostics`)
/// that itself depends on InstantSwiftData. Declaring it as a package dependency
/// of instant-data-swift creates a path-package cycle that crashes dual-dev
/// `swift package edit` into Scribe (SIGBUS / empty graph). Recipes therefore
/// keep a no-op logger here; wire the real Tailnet package from a separate
/// Recipes host Package.swift when live collector diagnostics are needed.
public enum RecipesTailnetDiagnostics {
  public static let defaultEndpoint = URL(
    string: "wss://laptop.tail91224c.ts.net/scribe-diagnostics"
  )!

  /// Starts diagnostics when a host supplies a Tailnet logger. Default no-op.
  @discardableResult
  public static func start(
    appID: String,
    isLive: Bool,
    recipe: String?
  ) -> Bool {
    _ = (appID, isLive, recipe)
    return true
  }

  public enum LogLevel: String, Sendable {
    case debug, info, notice, warning, error, critical
  }

  public static func logAuth(
    name: String,
    message: String,
    metadata: [String: String] = [:],
    level: LogLevel = .info
  ) {
    _ = (name, message, metadata, level)
  }
}
