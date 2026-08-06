import Dependencies
import DependenciesMacros

/// Structured logging operations independent of their persistence transport.
@DependencyClient
public struct LoggerClient: Sendable {
  public var append: @Sendable (_ event: LogEvent) async throws -> Void
  public var recent: @Sendable (_ query: LogQuery) async throws -> [LogEvent]
}

extension LoggerClient: TestDependencyKey {
  public static let testValue = Self()
}

extension DependencyValues {
  public var instantToolsLogger: LoggerClient {
    get { self[LoggerClient.self] }
    set { self[LoggerClient.self] = newValue }
  }
}
