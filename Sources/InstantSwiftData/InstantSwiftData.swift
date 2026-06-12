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
  private var loadOperation: (@Sendable (InstantSwiftDataClient) async throws -> [Element])?

  public init(wrappedValue: [Element] = []) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = nil
  }

  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>
  ) where Element: InstantEntityModel {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = { client in
      try await client.query(query)
    }
  }

  public var projectedValue: Self {
    get { self }
    set { self = newValue }
  }

  public mutating func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public mutating func load(using client: InstantSwiftDataClient) async throws {
    guard let loadOperation else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchAll",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchAll with an InstantEntityQuery, or pass a query to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchAll",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public mutating func load(
    _ query: InstantEntityQuery<Element>
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public mutating func load(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws where Element: InstantEntityModel {
    self.loadOperation = { client in
      try await client.query(query)
    }
    try await load(using: client)
  }
}

@propertyWrapper
public struct FetchOne<Element: Sendable>: Sendable {
  public var wrappedValue: Element?
  public var loadError: InstantError?
  public var isLoading: Bool
  private var loadOperation: (@Sendable (InstantSwiftDataClient) async throws -> Element?)?

  public init(wrappedValue: Element? = nil) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = nil
  }

  public init(
    wrappedValue: Element? = nil,
    _ query: InstantEntityQuery<Element>
  ) where Element: InstantEntityModel {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = { client in
      var query = query
      if query.plan.limit == nil {
        query = query.limit(1)
      }
      return try await client.query(query).first
    }
  }

  public var projectedValue: Self {
    get { self }
    set { self = newValue }
  }

  public mutating func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public mutating func load(using client: InstantSwiftDataClient) async throws {
    guard let loadOperation else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchOne",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchOne with an InstantEntityQuery, or pass a query to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load FetchOne",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public mutating func load(
    _ query: InstantEntityQuery<Element>
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(query, using: client)
  }

  public mutating func load(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws where Element: InstantEntityModel {
    self.loadOperation = { client in
      var query = query
      if query.plan.limit == nil {
        query = query.limit(1)
      }
      return try await client.query(query).first
    }
    try await load(using: client)
  }
}

@propertyWrapper
public struct Fetch<Value: Sendable>: Sendable {
  public var wrappedValue: Value
  public var loadError: InstantError?
  public var isLoading: Bool
  private var loadOperation: (@Sendable (InstantSwiftDataClient) async throws -> Value)?

  public init(wrappedValue: Value) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = nil
  }

  public init(
    wrappedValue: Value,
    load: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value
  ) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = load
  }

  public var projectedValue: Self {
    get { self }
    set { self = newValue }
  }

  public mutating func load() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(using: client)
  }

  public mutating func load(using client: InstantSwiftDataClient) async throws {
    guard let loadOperation else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load Fetch",
        message: "No Instant load operation has been configured for this fetch wrapper.",
        recovery: "Initialize @Fetch with a load operation, or pass an operation to load(_:using:)."
      )
      loadError = error
      throw error
    }

    isLoading = true
    do {
      wrappedValue = try await loadOperation(client)
      loadError = nil
      isLoading = false
    } catch let error as CancellationError {
      loadError = nil
      isLoading = false
      throw error
    } catch let error as InstantError {
      loadError = error
      isLoading = false
      throw error
    } catch {
      let error = InstantError(
        code: .implementationFailed,
        operation: "load Fetch",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and fetch load operation."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public mutating func load(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value
  ) async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await load(operation, using: client)
  }

  public mutating func load(
    _ operation: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value,
    using client: InstantSwiftDataClient
  ) async throws {
    self.loadOperation = operation
    try await load(using: client)
  }
}
