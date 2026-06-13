@_exported public import InstantSwiftDataCore
import Dependencies
import Foundation
import IssueReporting

#if canImport(SwiftUI)
  public import SwiftUI
#endif

@attached(member, names: named(instantNamespace), named(Draft))
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
  private var flushPendingMutationsOperation:
    @Sendable (Int?) async throws -> InstantMutationTransportFlushResult
  private var connectionStatusOperation: @Sendable () async throws -> InstantConnectionStatus
  private var connectOperation: @Sendable () async throws -> InstantConnectionStatus
  private var closeConnectionOperation: @Sendable () async throws -> InstantConnectionStatus
  private var localIDOperation: @Sendable (String) async throws -> String
  private var authSessionOperation: @Sendable () async throws -> InstantAuthSession?
  private var observeAuthSessionOperation:
    @Sendable () async throws -> AsyncStream<InstantAuthSession?>
  private var signInAsGuestOperation: @Sendable () async throws -> InstantAuthSession
  private var sendMagicCodeOperation: @Sendable (String) async throws -> InstantMagicCodeChallenge
  private var signInWithMagicCodeOperation:
    @Sendable (String, String) async throws -> InstantAuthSession
  private var signInWithRefreshTokenOperation:
    @Sendable (String, String?) async throws -> InstantAuthSession
  private var signInWithIDTokenOperation:
    @Sendable (String, String, String?) async throws -> InstantAuthSession
  private var signInWithOAuthOperation:
    @Sendable (String, String?) async throws -> InstantAuthSession
  private var oauthAuthorizationURLOperation: @Sendable (String, URL) throws -> URL
  private var issuerURIOperation: @Sendable () throws -> URL
  private var signOutOperation: @Sendable (Bool) async throws -> Void

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
    self.flushPendingMutationsOperation = { limit in
      try await runtime.flushPendingMutations(limit: limit)
    }
    self.connectionStatusOperation = {
      try await runtime.connectionStatus()
    }
    self.connectOperation = {
      try await runtime.connect()
    }
    self.closeConnectionOperation = {
      try await runtime.closeConnection()
    }
    self.localIDOperation = { name in
      try await runtime.localID(named: name)
    }
    self.authSessionOperation = {
      try await runtime.authSession()
    }
    self.observeAuthSessionOperation = {
      try await runtime.observeAuthSession()
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
    self.signInWithIDTokenOperation = { clientName, idToken, nonce in
      try await runtime.signInWithIDToken(
        clientName: clientName,
        idToken: idToken,
        nonce: nonce
      )
    }
    self.signInWithOAuthOperation = { code, codeVerifier in
      try await runtime.signInWithOAuth(code: code, codeVerifier: codeVerifier)
    }
    self.oauthAuthorizationURLOperation = { clientName, redirectURL in
      try runtime.oauthAuthorizationURL(clientName: clientName, redirectURL: redirectURL)
    }
    self.issuerURIOperation = {
      try runtime.issuerURI()
    }
    self.signOutOperation = { invalidateToken in
      try await runtime.signOut(invalidateToken: invalidateToken)
    }
  }

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    queryOnce: (@Sendable (InstantQueryPlan) async throws -> InstantQueryEmission)? = nil,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    flushPendingMutations:
      (@Sendable (Int?) async throws -> InstantMutationTransportFlushResult)? = nil,
    connectionStatus: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    connect: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    closeConnection: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    localID: @escaping @Sendable (String) async throws -> String,
    authSession: (@Sendable () async throws -> InstantAuthSession?)? = nil,
    observeAuthSession: (@Sendable () async throws -> AsyncStream<InstantAuthSession?>)? = nil,
    signInAsGuest: (@Sendable () async throws -> InstantAuthSession)? = nil,
    sendMagicCode: (@Sendable (String) async throws -> InstantMagicCodeChallenge)? = nil,
    signInWithMagicCode: (@Sendable (String, String) async throws -> InstantAuthSession)? = nil,
    signInWithRefreshToken:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOut: (@Sendable () async throws -> Void)? = nil,
    signInWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantAuthSession)? = nil,
    signInWithOAuth:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOutWithOptions: (@Sendable (Bool) async throws -> Void)? = nil
  ) {
    self.init(
      transact: transact,
      queryOnce: queryOnce,
      query: query,
      observe: observe,
      pendingMutations: pendingMutations,
      flushPendingMutations: flushPendingMutations,
      connectionStatus: connectionStatus,
      connect: connect,
      closeConnection: closeConnection,
      localID: localID,
      authSession: authSession,
      observeAuthSession: observeAuthSession,
      signInAsGuest: signInAsGuest,
      sendMagicCode: sendMagicCode,
      signInWithMagicCode: signInWithMagicCode,
      signInWithRefreshToken: signInWithRefreshToken,
      oauthAuthorizationURL: nil,
      issuerURI: nil,
      signOut: signOut,
      signInWithIDToken: signInWithIDToken,
      signInWithOAuth: signInWithOAuth,
      signOutWithOptions: signOutWithOptions
    )
  }

  public init(
    transact: @escaping @Sendable (InstantStoreTransaction) async throws
      -> InstantStoreMutationResult,
    queryOnce: (@Sendable (InstantQueryPlan) async throws -> InstantQueryEmission)? = nil,
    query: @escaping @Sendable (InstantQueryPlan) async throws -> [InstantEntitySnapshot],
    observe: @escaping @Sendable (InstantQueryPlan) async -> AsyncStream<InstantQueryEmission>,
    pendingMutations: @escaping @Sendable () async -> [PendingMutation],
    flushPendingMutations:
      (@Sendable (Int?) async throws -> InstantMutationTransportFlushResult)? = nil,
    connectionStatus: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    connect: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    closeConnection: (@Sendable () async throws -> InstantConnectionStatus)? = nil,
    localID: @escaping @Sendable (String) async throws -> String,
    authSession: (@Sendable () async throws -> InstantAuthSession?)? = nil,
    observeAuthSession: (@Sendable () async throws -> AsyncStream<InstantAuthSession?>)? = nil,
    signInAsGuest: (@Sendable () async throws -> InstantAuthSession)? = nil,
    sendMagicCode: (@Sendable (String) async throws -> InstantMagicCodeChallenge)? = nil,
    signInWithMagicCode: (@Sendable (String, String) async throws -> InstantAuthSession)? = nil,
    signInWithRefreshToken:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    oauthAuthorizationURL: (@Sendable (String, URL) throws -> URL)? = nil,
    issuerURI: (@Sendable () throws -> URL)? = nil,
    signOut: (@Sendable () async throws -> Void)? = nil,
    signInWithIDToken:
      (@Sendable (String, String, String?) async throws -> InstantAuthSession)? = nil,
    signInWithOAuth:
      (@Sendable (String, String?) async throws -> InstantAuthSession)? = nil,
    signOutWithOptions: (@Sendable (Bool) async throws -> Void)? = nil
  ) {
    let authError = InstantError(
      code: .implementationFailed,
      operation: "access InstantSwiftData auth",
      message: "No auth client has been configured.",
      recovery: "Bootstrap Instant Swift Data before using auth, or override auth closures in tests."
    )
    let transportError = InstantError(
      code: .implementationFailed,
      operation: "flush InstantSwiftData mutations",
      message: "No mutation transport client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before flushing mutations, or override the flush closure in tests."
    )
    let runtimeStatusError = InstantError(
      code: .implementationFailed,
      operation: "inspect InstantSwiftData connection",
      message: "No runtime connection status client has been configured.",
      recovery:
        "Bootstrap Instant Swift Data before inspecting connection status, or override the status closure in tests."
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
    self.flushPendingMutationsOperation = flushPendingMutations ?? { _ in throw transportError }
    self.connectionStatusOperation = connectionStatus ?? { throw runtimeStatusError }
    self.connectOperation = connect ?? { throw runtimeStatusError }
    self.closeConnectionOperation = closeConnection ?? { throw runtimeStatusError }
    self.localIDOperation = localID
    self.authSessionOperation = authSession ?? { throw authError }
    self.observeAuthSessionOperation = observeAuthSession ?? { throw authError }
    self.signInAsGuestOperation = signInAsGuest ?? { throw authError }
    self.sendMagicCodeOperation = sendMagicCode ?? { _ in throw authError }
    self.signInWithMagicCodeOperation = signInWithMagicCode ?? { _, _ in throw authError }
    self.signInWithRefreshTokenOperation = signInWithRefreshToken ?? { _, _ in throw authError }
    self.signInWithIDTokenOperation = signInWithIDToken ?? { _, _, _ in throw authError }
    self.signInWithOAuthOperation = signInWithOAuth ?? { _, _ in throw authError }
    self.oauthAuthorizationURLOperation = oauthAuthorizationURL ?? { _, _ in throw authError }
    self.issuerURIOperation = issuerURI ?? { throw authError }
    self.signOutOperation =
      signOutWithOptions ?? { _ in
        if let signOut {
          try await signOut()
        } else {
          throw authError
        }
      }
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
      flushPendingMutations: { _ in
        throw error
      },
      connectionStatus: {
        throw error
      },
      connect: {
        throw error
      },
      closeConnection: {
        throw error
      },
      localID: { _ in
        throw error
      },
      authSession: {
        throw error
      },
      observeAuthSession: {
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
      oauthAuthorizationURL: { _, _ in
        throw error
      },
      issuerURI: {
        throw error
      },
      signOut: {
        throw error
      },
      signInWithIDToken: { _, _, _ in
        throw error
      },
      signInWithOAuth: { _, _ in
        throw error
      },
      signOutWithOptions: { _ in
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

  public func flushPendingMutations(limit: Int? = nil) async throws
    -> InstantMutationTransportFlushResult
  {
    try await flushPendingMutationsOperation(limit)
  }

  public func connectionStatus() async throws -> InstantConnectionStatus {
    try await connectionStatusOperation()
  }

  @discardableResult
  public func connect() async throws -> InstantConnectionStatus {
    try await connectOperation()
  }

  @discardableResult
  public func closeConnection() async throws -> InstantConnectionStatus {
    try await closeConnectionOperation()
  }

  public func localID(named name: String) async throws -> String {
    try await localIDOperation(name)
  }

  public func authSession() async throws -> InstantAuthSession? {
    try await authSessionOperation()
  }

  public func observeAuthSession() async throws -> AsyncStream<InstantAuthSession?> {
    try await observeAuthSessionOperation()
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

  public func signInWithIDToken(
    clientName: String,
    idToken: String,
    nonce: String? = nil
  ) async throws -> InstantAuthSession {
    try await signInWithIDTokenOperation(clientName, idToken, nonce)
  }

  public func signInWithOAuth(
    code: String,
    codeVerifier: String? = nil
  ) async throws -> InstantAuthSession {
    try await signInWithOAuthOperation(code, codeVerifier)
  }

  public func oauthAuthorizationURL(
    clientName: String,
    redirectURL: URL
  ) throws -> URL {
    try oauthAuthorizationURLOperation(clientName, redirectURL)
  }

  public func issuerURI() throws -> URL {
    try issuerURIOperation()
  }

  public func signOut() async throws {
    try await signOut(invalidateToken: true)
  }

  public func signOut(invalidateToken: Bool = true) async throws {
    try await signOutOperation(invalidateToken)
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

  public var task: Void {
    get async throws {
      try await withTaskCancellationHandler {
        await cancellation.wait()
        try Task.checkCancellation()
      } onCancel: {
        self.cancel()
      }
    }
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

// SAFETY: all mutable fetch state is protected by `lock`.
private final class FetchStorage<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var _wrappedValue: Value
  private var _loadError: InstantError?
  private var _isLoading: Bool

  init(value: Value) {
    self._wrappedValue = value
    self._loadError = nil
    self._isLoading = false
  }

  var wrappedValue: Value {
    get {
      withLock { _wrappedValue }
    }
    set {
      withLock {
        _wrappedValue = newValue
      }
    }
  }

  var loadError: InstantError? {
    get {
      withLock { _loadError }
    }
    set {
      withLock {
        _loadError = newValue
      }
    }
  }

  var isLoading: Bool {
    get {
      withLock { _isLoading }
    }
    set {
      withLock {
        _isLoading = newValue
      }
    }
  }

  private func withLock<Result>(_ operation: () throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try operation()
  }
}

// SAFETY: the only mutable state is `isCancelled`, which is protected by `lock`.
private final class FetchSubscriptionCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private let operation: @Sendable () -> Void
  private var isCancelled = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

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
    let continuations = self.continuations
    self.continuations.removeAll()
    lock.unlock()

    operation()
    for continuation in continuations {
      continuation.resume()
    }
  }

  func wait() async {
    await withCheckedContinuation { continuation in
      lock.lock()
      if isCancelled {
        lock.unlock()
        continuation.resume()
      } else {
        continuations.append(continuation)
        lock.unlock()
      }
    }
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

private enum InstantRefreshTokenVerifierKey: TestDependencyKey {
  static var testValue: InstantRefreshTokenVerifier {
    .local
  }

  static var previewValue: InstantRefreshTokenVerifier {
    .local
  }
}

extension InstantRefreshTokenVerifierKey: DependencyKey {
  static var liveValue: InstantRefreshTokenVerifier {
    .local
  }
}

private enum InstantIDTokenExchangeKey: TestDependencyKey {
  static var testValue: InstantIDTokenExchange {
    .local
  }

  static var previewValue: InstantIDTokenExchange {
    .local
  }
}

extension InstantIDTokenExchangeKey: DependencyKey {
  static var liveValue: InstantIDTokenExchange {
    .local
  }
}

private enum InstantOAuthExchangeKey: TestDependencyKey {
  static var testValue: InstantOAuthExchange {
    .local
  }

  static var previewValue: InstantOAuthExchange {
    .local
  }
}

extension InstantOAuthExchangeKey: DependencyKey {
  static var liveValue: InstantOAuthExchange {
    .local
  }
}

private enum InstantAuthTokenInvalidatorKey: TestDependencyKey {
  static var testValue: InstantAuthTokenInvalidator {
    .local
  }

  static var previewValue: InstantAuthTokenInvalidator {
    .local
  }
}

extension InstantAuthTokenInvalidatorKey: DependencyKey {
  static var liveValue: InstantAuthTokenInvalidator {
    .local
  }
}

private enum InstantMutationTransportKey: TestDependencyKey {
  static var testValue: InstantMutationTransportClient {
    .local
  }

  static var previewValue: InstantMutationTransportClient {
    .local
  }
}

extension InstantMutationTransportKey: DependencyKey {
  static var liveValue: InstantMutationTransportClient {
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

  public var instantRefreshTokenVerifier: InstantRefreshTokenVerifier {
    get { self[InstantRefreshTokenVerifierKey.self] }
    set { self[InstantRefreshTokenVerifierKey.self] = newValue }
  }

  public var instantIDTokenExchange: InstantIDTokenExchange {
    get { self[InstantIDTokenExchangeKey.self] }
    set { self[InstantIDTokenExchangeKey.self] = newValue }
  }

  public var instantOAuthExchange: InstantOAuthExchange {
    get { self[InstantOAuthExchangeKey.self] }
    set { self[InstantOAuthExchangeKey.self] = newValue }
  }

  public var instantAuthTokenInvalidator: InstantAuthTokenInvalidator {
    get { self[InstantAuthTokenInvalidatorKey.self] }
    set { self[InstantAuthTokenInvalidatorKey.self] = newValue }
  }

  public var instantMutationTransport: InstantMutationTransportClient {
    get { self[InstantMutationTransportKey.self] }
    set { self[InstantMutationTransportKey.self] = newValue }
  }

  public mutating func bootstrapInstantSwiftData(
    appID: String,
    persistenceURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = []
  ) async throws {
    try await self.bootstrapInstantSwiftData(
      appID: appID,
      apiURI: InstantRuntimeConfiguration.defaultAPIURI,
      websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
      persistenceURL: persistenceURL,
      context: context,
      initialAttributes: initialAttributes
    )
  }

  public mutating func bootstrapInstantSwiftData(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    persistenceURL: URL? = nil,
    context: InstantSwiftDataBootstrapContext = .live,
    initialAttributes: [InstantAttribute] = []
  ) async throws {
    let date = self.date
    let uuid = self.uuid
    let magicCodeExchange = self.instantMagicCodeExchange
    let refreshTokenVerifier = self.instantRefreshTokenVerifier
    let idTokenExchange = self.instantIDTokenExchange
    let oauthExchange = self.instantOAuthExchange
    let authTokenInvalidator = self.instantAuthTokenInvalidator
    let mutationTransport = self.instantMutationTransport
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
        apiURI: apiURI,
        websocketURI: websocketURI,
        persistenceURL: url,
        initialAttributes: initialAttributes,
        now: {
          InstantTimestamp(milliseconds: Int64((date().timeIntervalSince1970 * 1000).rounded()))
        },
        makeID: {
          uuid().uuidString.lowercased()
        },
        refreshTokenVerifier: refreshTokenVerifier,
        magicCodeExchange: magicCodeExchange,
        idTokenExchange: idTokenExchange,
        oauthExchange: oauthExchange,
        authTokenInvalidator: authTokenInvalidator,
        mutationTransport: mutationTransport
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
  private let storage: FetchStorage<[Element]>
  private var loadOperation: (@Sendable (InstantSwiftDataClient) async throws -> [Element])?
  private var subscribeOperation:
    (@Sendable (InstantSwiftDataClient) async -> FetchSubscription<[Element]>)?

  public var wrappedValue: [Element] {
    get { storage.wrappedValue }
    set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<[Element]> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: [Element] = []) {
    self.storage = FetchStorage(value: wrappedValue)
    self.loadOperation = nil
    self.subscribeOperation = nil
  }

  public init(
    wrappedValue: [Element] = [],
    _ query: InstantEntityQuery<Element>
  ) where Element: InstantEntityModel {
    self.storage = FetchStorage(value: wrappedValue)
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

  public mutating func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public mutating func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
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
        operation: "observe FetchAll",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public mutating func task(
    _ query: InstantEntityQuery<Element>
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public mutating func task(
    _ query: InstantEntityQuery<Element>,
    using client: InstantSwiftDataClient
  ) async throws where Element: InstantEntityModel {
    self.loadOperation = { client in
      try await client.query(query)
    }
    self.subscribeOperation = { client in
      await client.subscribe(query)
    }
    try await task(using: client)
  }
}

@propertyWrapper
public struct FetchOne<Element: Sendable>: Sendable {
  private let storage: FetchStorage<Element?>
  private var loadOperation: (@Sendable (InstantSwiftDataClient) async throws -> Element?)?
  private var subscribeOperation:
    (@Sendable (InstantSwiftDataClient) async -> FetchSubscription<Element?>)?

  public var wrappedValue: Element? {
    get { storage.wrappedValue }
    set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<Element?> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: Element? = nil) {
    self.storage = FetchStorage(value: wrappedValue)
    self.loadOperation = nil
    self.subscribeOperation = nil
  }

  public init(
    wrappedValue: Element? = nil,
    _ query: InstantEntityQuery<Element>
  ) where Element: InstantEntityModel {
    self.storage = FetchStorage(value: wrappedValue)
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

  public mutating func task() async throws {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(using: client)
  }

  public mutating func task(using client: InstantSwiftDataClient) async throws {
    isLoading = true
    do {
      let subscription = try await subscribe(using: client)
      defer { subscription.cancel() }
      for try await value in subscription {
        try Task.checkCancellation()
        wrappedValue = value
        loadError = nil
        isLoading = false
      }
      try Task.checkCancellation()
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
        operation: "observe FetchOne",
        message: String(describing: error),
        recovery: "Inspect the configured InstantSwiftDataClient and query decoder."
      )
      loadError = error
      isLoading = false
      throw error
    }
  }

  public mutating func task(
    _ query: InstantEntityQuery<Element>
  ) async throws where Element: InstantEntityModel {
    @Dependency(\.defaultInstantSwiftData) var client
    try await task(query, using: client)
  }

  public mutating func task(
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
    try await task(using: client)
  }
}

@propertyWrapper
public struct Fetch<Value: Sendable>: Sendable {
  private let storage: FetchStorage<Value>
  private var loadOperation: (@Sendable (InstantSwiftDataClient) async throws -> Value)?

  public var wrappedValue: Value {
    get { storage.wrappedValue }
    set { storage.wrappedValue = newValue }
  }

  public var loadError: InstantError? {
    get { storage.loadError }
    set { storage.loadError = newValue }
  }

  public var isLoading: Bool {
    get { storage.isLoading }
    set { storage.isLoading = newValue }
  }

  #if canImport(SwiftUI)
    public var binding: Binding<Value> {
      Binding(
        get: { storage.wrappedValue },
        set: { storage.wrappedValue = $0 }
      )
    }
  #endif

  public init(wrappedValue: Value) {
    self.storage = FetchStorage(value: wrappedValue)
    self.loadOperation = nil
  }

  public init(
    wrappedValue: Value,
    load: @escaping @Sendable (InstantSwiftDataClient) async throws -> Value
  ) {
    self.storage = FetchStorage(value: wrappedValue)
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
