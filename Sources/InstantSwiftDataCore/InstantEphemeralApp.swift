import Foundation

public struct InstantEphemeralApp: Codable, Equatable, Sendable {
  public var appID: String
  public var title: String
  public var createdAt: InstantTimestamp
  public var isLocalOnly: Bool
  public var transport: String

  public init(
    appID: String,
    title: String,
    createdAt: InstantTimestamp,
    isLocalOnly: Bool,
    transport: String
  ) {
    self.appID = appID
    self.title = title
    self.createdAt = createdAt
    self.isLocalOnly = isLocalOnly
    self.transport = transport
  }
}

public enum InstantEphemeralApps {
  public static let localTransport = "local-cache-only"

  public static func makeLocal(
    title: String,
    createdAt: @autoclosure () -> InstantTimestamp = InstantTimestamp(
      milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded())
    ),
    makeID: @autoclosure () -> String = UUID().uuidString
  ) throws -> InstantEphemeralApp {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else {
      throw InstantError(
        code: .validationFailed,
        operation: "create local ephemeral app",
        message: "Expected a non-empty title.",
        recovery: "Pass '--title \"My test app\"' with a visible title."
      )
    }

    return InstantEphemeralApp(
      appID: "local-ephemeral-\(makeID().lowercased())",
      title: title,
      createdAt: createdAt(),
      isLocalOnly: true,
      transport: localTransport
    )
  }
}
