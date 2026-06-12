@_exported public import InstantSwiftDataCore
import Dependencies
import Foundation
import IssueReporting

@attached(member, names: named(instantNamespace))
public macro InstantEntity(_ namespace: String? = nil) =
  #externalMacro(module: "InstantSwiftDataMacros", type: "InstantEntityMacro")

public struct InstantSwiftDataClient: Sendable {
  public let runtime: InstantRuntime?

  private var transactOperation:
    @Sendable (InstantStoreTransaction) async throws -> InstantStoreMutationResult
  private var queryOperation: @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot]
  private var observeOperation: @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>
  private var pendingMutationsOperation: @Sendable () async -> [PendingMutation]
  private var localIDOperation: @Sendable (String) async throws -> String

  public init(runtime: InstantRuntime) {
    self.runtime = runtime
    self.transactOperation = { transaction in
      try await runtime.transact(transaction)
    }
    self.queryOperation = { plan in
      await runtime.query(plan)
    }
    self.observeOperation = { plan in
      await runtime.observe(plan)
    }
    self.pendingMutationsOperation = {
      await runtime.pendingMutations()
    }
    self.localIDOperation = { name in
      try await runtime.localID(named: name)
    }
  }

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    localID: @escaping @Sendable (String) async throws -> String
  ) {
    self.runtime = nil
    self.transactOperation = transact
    self.queryOperation = query
    self.observeOperation = observe
    self.pendingMutationsOperation = pendingMutations
    self.localIDOperation = localID
  }

  public static func unimplemented(_ message: String) -> Self {
    let error = InstantError(
      code: .implementationFailed,
      operation: "access default InstantSwiftData client",
      message: message,
      recovery: "Bootstrap Instant Swift Data before reading the dependency, or override it in tests."
    )

    return Self(
      transact: { _ in
        throw error
      },
      query: { _ in
        throw error
      },
      observe: { _ in
        AsyncStream { continuation in
          reportIssue(error)
          continuation.finish()
        }
      },
      pendingMutations: {
        reportIssue(error)
        return []
      },
      localID: { _ in
        throw error
      }
    )
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration
  ) async throws -> Self {
    try await Self(runtime: InstantRuntime.bootstrap(configuration: configuration))
  }

  @discardableResult
  public func transact(
    _ transaction: InstantStoreTransaction
  ) async throws -> InstantStoreMutationResult {
    try await transactOperation(transaction)
  }

  public func query(_ plan: InstantQueryPlan) async throws -> [InstantEntitySnapshot] {
    try await queryOperation(plan)
  }

  public func observe(_ plan: InstantQueryPlan) async -> AsyncStream<InstantQueryEmission> {
    await observeOperation(plan)
  }

  public func pendingMutations() async -> [PendingMutation] {
    await pendingMutationsOperation()
  }

  public func localID(named name: String) async throws -> String {
    try await localIDOperation(name)
  }
}

public enum InstantSwiftDataBootstrapContext: String, Sendable {
  case live
  case preview
  case test
  case cli
}

private enum DefaultInstantSwiftDataKey: TestDependencyKey {
  static var testValue: InstantSwiftDataClient {
    .unimplemented("No test InstantSwiftData client has been configured.")
  }

  static var previewValue: InstantSwiftDataClient {
    .unimplemented("No preview InstantSwiftData client has been configured.")
  }
}

extension DefaultInstantSwiftDataKey: DependencyKey {
  static var liveValue: InstantSwiftDataClient {
    .unimplemented("No live InstantSwiftData client has been configured.")
  }
}

extension DependencyValues {
  public var defaultInstantSwiftData: InstantSwiftDataClient {
    get { self[DefaultInstantSwiftDataKey.self] }
    set { self[DefaultInstantSwiftDataKey.self] = newValue }
  }

  public mutating func bootstrapInstantSwiftData(
    appID: String,
    persistenceURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = []
  ) async throws {
    let date = self.date
    let uuid = self.uuid
    let url =
      persistenceURL
      ?? Self.defaultInstantSwiftDataPersistenceURL(
        appID: appID,
        context: context,
        uniqueID: context == .test ? uuid().uuidString.lowercased() : nil
      )

    self.defaultInstantSwiftData = try await InstantSwiftDataClient.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: url,
        initialAttributes: initialAttributes,
        now: {
          InstantTimestamp(milliseconds: Int64((date().timeIntervalSince1970 * 1000).rounded()))
        },
        makeID: {
          uuid().uuidString.lowercased()
        }
      )
    )
  }

  public static func defaultInstantSwiftDataPersistenceURL(
    appID: String,
    context: InstantSwiftDataBootstrapContext,
    uniqueID: String? = nil
  ) -> URL {
    let fileName = sanitizedPersistenceName(appID) + ".sqlite"

    switch context {
    case .live:
      return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".instant-swift-data", isDirectory: true)
        .appendingPathComponent("apps", isDirectory: true)
        .appendingPathComponent(fileName)

    case .cli:
      return defaultCLIHomeURL()
        .appendingPathComponent("state.sqlite")

    case .preview:
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataPreviews", isDirectory: true)
        .appendingPathComponent(fileName)

    case .test:
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataTests", isDirectory: true)
        .appendingPathComponent((uniqueID ?? UUID().uuidString.lowercased()) + "-" + fileName)
    }
  }

  private static func sanitizedPersistenceName(_ appID: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = appID.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return name.isEmpty ? "default" : name
  }

  private static func defaultCLIHomeURL() -> URL {
    if let path = ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_HOME"] {
      return URL(fileURLWithPath: path, isDirectory: true)
    }

    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".instant-swift-data", isDirectory: true)
  }
}

@propertyWrapper
public struct FetchAll<Element: Sendable>: Sendable {
  public var wrappedValue: [Element]
  public var loadError: InstantError?
  public var isLoading: Bool

  public init(wrappedValue: [Element] = []) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
  }

  public var projectedValue: Self {
    get { self }
    set { self = newValue }
  }
}
