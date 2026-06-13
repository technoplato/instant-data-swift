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
  private var queryOnceOperation:
    @Sendable (InstantQueryPlan) async throws -> InstantQueryEmission
  private var queryOperation: @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot]
  private var observeOperation: @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>
  private var pendingMutationsOperation: @Sendable () async -> [PendingMutation]
  private var localIDOperation: @Sendable (String) async throws -> String
  private var authSessionOperation: @Sendable () async throws -> InstantAuthSession?
  private var signInAsGuestOperation: @Sendable () async throws -> InstantAuthSession
  private var sendMagicCodeOperation: @Sendable (String) async throws -> InstantMagicCodeChallenge
  private var signInWithMagicCodeOperation:
    @Sendable (String, String) async throws -> InstantAuthSession
  private var signInWithRefreshTokenOperation:
    @Sendable (String, String?) async throws -> InstantAuthSession
  private var signOutOperation: @Sendable () async throws -> Void

  public init(runtime: InstantRuntime) {
    self.runtime = runtime
    self.transactOperation = { transaction in
      try await runtime.transact(transaction)
    }
    self.queryOnceOperation = { plan in
      try await runtime.queryOnce(plan)
    }
    self.queryOperation = { plan in
      try await runtime.query(plan)
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
    self.authSessionOperation = {
      try await runtime.authSession()
    }
    self.signInAsGuestOperation = {
      try await runtime.signInAsGuest()
    }
    self.sendMagicCodeOperation = { email in
      try await runtime.sendMagicCode(email: email)
    }
    self.signInWithMagicCodeOperation = { email, code in
      try await runtime.signInWithMagicCode(email: email, code: code)
    }
    self.signInWithRefreshTokenOperation = { refreshToken, userID in
      try await runtime.signInWithRefreshToken(refreshToken, userID: userID)
    }
    self.signOutOperation = {
      try await runtime.signOut()
    }
  }

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    queryOnce: (@Sendable (InstantQueryPlan) async throws -> InstantQueryEmission)? = nil,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    localID: @escaping @Sendable (String) async throws -> String,
    authSession: (@Sendable () async throws -> InstantAuthSession?)? = nil,
    signInAsGuest: (@Sendable () async throws -> InstantAuthSession)? = nil,
    sendMagicCode: (@Sendable (String) async throws -> InstantMagicCodeChallenge)? = nil,
    signInWithMagicCode: (@Sendable (String, String) async throws -> InstantAuthSession)? = nil,
    signInWithRefreshToken:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOut: (@Sendable () async throws -> Void)? = nil
  ) {
    let authError = InstantError(
      code: .implementationFailed,
      operation: "access InstantSwiftData auth",
      message: "No auth client has been configured.",
      recovery: "Bootstrap Instant Swift Data before using auth, or override auth closures in tests."
    )

    self.runtime = nil
    self.transactOperation = transact
    self.queryOnceOperation =
      queryOnce
      ?? { plan in
        InstantQueryEmission(queryID: plan.id, sequence: 0, values: try await query(plan))
      }
    self.queryOperation = query
    self.observeOperation = observe
    self.pendingMutationsOperation = pendingMutations
    self.localIDOperation = localID
    self.authSessionOperation = authSession ?? { throw authError }
    self.signInAsGuestOperation = signInAsGuest ?? { throw authError }
    self.sendMagicCodeOperation = sendMagicCode ?? { _ in throw authError }
    self.signInWithMagicCodeOperation = signInWithMagicCode ?? { _, _ in throw authError }
    self.signInWithRefreshTokenOperation = signInWithRefreshToken ?? { _, _ in throw authError }
    self.signOutOperation = signOut ?? { throw authError }
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
      },
      authSession: {
        throw error
      },
      signInAsGuest: {
        throw error
      },
      sendMagicCode: { _ in
        throw error
      },
      signInWithMagicCode: { _, _ in
        throw error
      },
      signInWithRefreshToken: { _, _ in
        throw error
      },
      signOut: {
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

  public func queryOnce(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    try await queryOnceOperation(plan)
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

  public func authSession() async throws -> InstantAuthSession? {
    try await authSessionOperation()
  }

  public func signInAsGuest() async throws -> InstantAuthSession {
    try await signInAsGuestOperation()
  }

  public func sendMagicCode(email: String) async throws -> InstantMagicCodeChallenge {
    try await sendMagicCodeOperation(email)
  }

  public func signInWithMagicCode(email: String, code: String) async throws -> InstantAuthSession {
    try await signInWithMagicCodeOperation(email, code)
  }

  public func signInWithRefreshToken(
    _ refreshToken: String,
    userID: String? = nil
  ) async throws -> InstantAuthSession {
    try await signInWithRefreshTokenOperation(refreshToken, userID)
  }

  public func signOut() async throws {
    try await signOutOperation()
  }

  public func subscribe<Entity: InstantEntityModel>(
    _ query: InstantEntityQuery<Entity>
  ) async -> FetchSubscription<[Entity]> {
    let emissions = await observe(query.plan)
    let stream = AsyncThrowingStream<[Entity], Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in emissions {
        do {
          try Task.checkCancellation()
          stream.continuation.yield(try Entity.decode(emission.values))
        } catch {
          stream.continuation.finish(throwing: error)
          return
        }
      }
      stream.continuation.finish()
    }
    stream.continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
    return FetchSubscription(stream: stream.stream) {
      task.cancel()
      stream.continuation.finish()
    }
  }
}

public enum InstantSwiftDataBootstrapContext: String, Sendable {
  case live
  case preview
  case test
  case cli
}

public struct FetchSubscription<Element: Sendable>: AsyncSequence, Sendable {
  public typealias AsyncIterator = AsyncThrowingStream<Element, Error>.Iterator

  private let stream: AsyncThrowingStream<Element, Error>
  private let cancellation: FetchSubscriptionCancellation

  public init(
    stream: AsyncThrowingStream<Element, Error>,
    cancel: @escaping @Sendable () -> Void
  ) {
    self.stream = stream
    self.cancellation = FetchSubscriptionCancellation(cancel)
  }

  public func makeAsyncIterator() -> AsyncIterator {
    stream.makeAsyncIterator()
  }

  public func cancel() {
    cancellation.cancel()
  }

  public func map<Mapped: Sendable>(
    _ transform: @escaping @Sendable (Element) throws -> Mapped
  ) -> FetchSubscription<Mapped> {
    let mapped = AsyncThrowingStream<Mapped, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      do {
        for try await value in self {
          try Task.checkCancellation()
          mapped.continuation.yield(try transform(value))
        }
        mapped.continuation.finish()
      } catch {
        mapped.continuation.finish(throwing: error)
      }
    }
    mapped.continuation.onTermination = { @Sendable _ in
      task.cancel()
      self.cancel()
    }
    return FetchSubscription<Mapped>(stream: mapped.stream) {
      task.cancel()
      mapped.continuation.finish()
      self.cancel()
    }
  }
}

// SAFETY: the only mutable state is `isCancelled`, which is protected by `lock`.
private final class FetchSubscriptionCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private let operation: @Sendable () -> Void
  private var isCancelled = false

  init(_ operation: @escaping @Sendable () -> Void) {
    self.operation = operation
  }

  deinit {
    cancel()
  }

  func cancel() {
    lock.lock()
    guard !isCancelled else {
      lock.unlock()
      return
    }
    isCancelled = true
    lock.unlock()

    operation()
  }
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

private enum InstantMagicCodeExchangeKey: TestDependencyKey {
  static var testValue: InstantMagicCodeExchange {
    .local
  }

  static var previewValue: InstantMagicCodeExchange {
    .local
  }
}

extension InstantMagicCodeExchangeKey: DependencyKey {
  static var liveValue: InstantMagicCodeExchange {
    .local
  }
}

extension DependencyValues {
  public var defaultInstantSwiftData: InstantSwiftDataClient {
    get { self[DefaultInstantSwiftDataKey.self] }
    set { self[DefaultInstantSwiftDataKey.self] = newValue }
  }

  public var instantMagicCodeExchange: InstantMagicCodeExchange {
    get { self[InstantMagicCodeExchangeKey.self] }
    set { self[InstantMagicCodeExchangeKey.self] = newValue }
  }

  public mutating func bootstrapInstantSwiftData(
    appID: String,
    persistenceURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = []
  ) async throws {
    let date = self.date
    let uuid = self.uuid
    let magicCodeExchange = self.instantMagicCodeExchange
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
        },
        magicCodeExchange: magicCodeExchange
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
  private var subscribeOperation:
    (@Sendable (InstantSwiftDataClient) async -> FetchSubscription<[Element]>)?

  public init(wrappedValue: [Element] = []) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = nil
    self.subscribeOperation = nil
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
    self.subscribeOperation = { client in
      await client.subscribe(query)
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
    self.subscribeOperation = { client in
      await client.subscribe(query)
    }
    try await load(using: client)
  }

  public mutating func subscribe() async throws -> FetchSubscription<[Element]> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public mutating func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> {
    guard let subscribeOperation else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe FetchAll",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchAll with an InstantEntityQuery, or pass a query to subscribe(_:using:)."
      )
      loadError = error
      throw error
    }

    loadError = nil
    return await subscribeOperation(client)
  }

  public mutating func subscribe(
    _ query: InstantEntityQuery<Element>
  ) async throws -> FetchSubscription<[Element]> where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public mutating func subscribe(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<[Element]> where Element: InstantEntityModel {
    self.loadOperation = { client in
      try await client.query(query)
    }
    self.subscribeOperation = { client in
      await client.subscribe(query)
    }
    return try await subscribe(using: client)
  }
}

@propertyWrapper
public struct FetchOne<Element: Sendable>: Sendable {
  public var wrappedValue: Element?
  public var loadError: InstantError?
  public var isLoading: Bool
  private var loadOperation: (@Sendable (InstantSwiftDataClient) async throws -> Element?)?
  private var subscribeOperation:
    (@Sendable (InstantSwiftDataClient) async -> FetchSubscription<Element?>)?

  public init(wrappedValue: Element? = nil) {
    self.wrappedValue = wrappedValue
    self.loadError = nil
    self.isLoading = false
    self.loadOperation = nil
    self.subscribeOperation = nil
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
    self.subscribeOperation = { client in
      var query = query
      if query.plan.limit == nil {
        query = query.limit(1)
      }
      return await client.subscribe(query).map(\.first)
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
    self.subscribeOperation = { client in
      var query = query
      if query.plan.limit == nil {
        query = query.limit(1)
      }
      return await client.subscribe(query).map(\.first)
    }
    try await load(using: client)
  }

  public mutating func subscribe() async throws -> FetchSubscription<Element?> {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(using: client)
  }

  public mutating func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Element?> {
    guard let subscribeOperation else {
      let error = InstantError(
        code: .implementationFailed,
        operation: "subscribe FetchOne",
        message: "No Instant query has been configured for this fetch wrapper.",
        recovery: "Initialize @FetchOne with an InstantEntityQuery, or pass a query to subscribe(_:using:)."
      )
      loadError = error
      throw error
    }

    loadError = nil
    return await subscribeOperation(client)
  }

  public mutating func subscribe(
    _ query: InstantEntityQuery<Element>
  ) async throws -> FetchSubscription<Element?> where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    return try await subscribe(query, using: client)
  }

  public mutating func subscribe(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<Element?> where Element: InstantEntityModel {
    self.loadOperation = { client in
      var query = query
      if query.plan.limit == nil {
        query = query.limit(1)
      }
      return try await client.query(query).first
    }
    self.subscribeOperation = { client in
      var query = query
      if query.plan.limit == nil {
        query = query.limit(1)
      }
      return await client.subscribe(query).map(\.first)
    }
    return try await subscribe(using: client)
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
