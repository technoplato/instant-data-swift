import Foundation
import TailnetInstantDBLogger
import InstantSwiftData

/// Host wiring for the extracted Tailnet WebSocket diagnostics package.
///
/// Collector path (same as Scribe):
/// `wss://laptop.tail91224c.ts.net/scribe-diagnostics`
/// → Tailscale Serve → `127.0.0.1:8767`
/// → `~/Library/Logs/Scribe/diagnostics.jsonl`
public enum RecipesTailnetDiagnostics {
  public static let defaultEndpoint = URL(
    string: "wss://laptop.tail91224c.ts.net/scribe-diagnostics"
  )!

  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var logger: InstantDBLogger = .noop
    var bridgeHandlerID: UUID?
  }

  private static let state = State()

  /// Process-wide logger used by the recipes host and auth screens.
  public static var logger: InstantDBLogger {
    state.lock.lock()
    defer { state.lock.unlock() }
    return state.logger
  }

  /// Starts the Tailnet WebSocket writer + Instant library diagnostic bridge.
  /// Safe when the collector is down (spool + soft retry).
  @discardableResult
  public static func start(
    appID: String,
    isLive: Bool,
    recipe: String?
  ) -> InstantDBLogger {
    let spoolURL =
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
      .appendingPathComponent("recipes-v3-diagnostics-outbox.jsonl")
      ?? FileManager.default.temporaryDirectory
      .appendingPathComponent("recipes-v3-diagnostics-outbox.jsonl")

    let context = InstantDBLogContext(
      subsystem: "com.technoplato.InstantSwiftData.RecipesV3",
      deviceName: ProcessInfo.processInfo.hostName,
      buildCommit: "",
      buildBranch: "",
      buildIsDirty: false,
      projectName: "InstantRecipesV3"
    )

    let webSocketLogger = InstantDBLogger.webSocket(
      endpoint: defaultEndpoint,
      context: context,
      spoolURL: spoolURL
    )

    state.lock.lock()
    state.logger = webSocketLogger
    if state.bridgeHandlerID == nil {
      state.bridgeHandlerID = webSocketLogger.bridgeInstantDiagnostics(minimumLevel: .info)
    }
    state.lock.unlock()

    webSocketLogger.enqueue(
      level: .info,
      category: "recipes.diagnostics",
      name: "tailnet.logger.started",
      message: "Recipes Tailnet diagnostics writer started.",
      metadata: [
        "appID": appID,
        "live": isLive.description,
        "recipe": recipe ?? "catalog",
        "endpoint": defaultEndpoint.absoluteString,
        "spool": spoolURL.path,
      ]
    )
    return webSocketLogger
  }

  public static func logAuth(
    name: String,
    message: String,
    metadata: [String: String] = [:],
    level: InstantDBLogLevel = .info
  ) {
    logger.enqueue(
      level: level,
      category: "recipes.auth",
      name: name,
      message: message,
      metadata: metadata
    )
  }
}
