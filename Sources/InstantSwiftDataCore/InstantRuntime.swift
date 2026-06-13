import Foundation

public struct InstantRuntimeConfiguration: Sendable {
  public static let defaultAPIURI = URL(string: "https://api.instantdb.com")!
  public static let defaultWebSocketURI = URL(
    string: "wss://api.instantdb.com/runtime/session"
  )!

  public var appID: String
  public var apiURI: URL
  public var websocketURI: URL
  public var persistenceURL: URL
  public var initialAttributes: [InstantAttribute]
  public var now: @Sendable () -> InstantTimestamp
  public var makeID: @Sendable () -> String
  public var refreshTokenVerifier: InstantRefreshTokenVerifier
  public var magicCodeExchange: InstantMagicCodeExchange
  public var idTokenExchange: InstantIDTokenExchange
  public var oauthExchange: InstantOAuthExchange
  public var authTokenInvalidator: InstantAuthTokenInvalidator
  public var mutationTransport: InstantMutationTransportClient
  var actorHopRecorder: InstantActorHopRecorder?

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local
  ) {
    self.init(
      appID: appID,
      apiURI: Self.defaultAPIURI,
      websocketURI: Self.defaultWebSocketURI,
      persistenceURL: persistenceURL,
      initialAttributes: initialAttributes,
      now: now,
      makeID: makeID,
      refreshTokenVerifier: refreshTokenVerifier,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      mutationTransport: .local
    )
  }

  public init(
    appID: String,
    apiURI: URL = Self.defaultAPIURI,
    websocketURI: URL = Self.defaultWebSocketURI,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    mutationTransport: InstantMutationTransportClient = .local
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.websocketURI = websocketURI
    self.persistenceURL = persistenceURL
    self.initialAttributes = initialAttributes
    self.now = now
    self.makeID = makeID
    self.refreshTokenVerifier = refreshTokenVerifier
    self.magicCodeExchange = magicCodeExchange
    self.idTokenExchange = idTokenExchange
    self.oauthExchange = oauthExchange
    self.authTokenInvalidator = authTokenInvalidator
    self.mutationTransport = mutationTransport
    self.actorHopRecorder = nil
  }

  public static func isValidAPIURI(_ url: URL) -> Bool {
    isValidEndpointURI(url, allowedSchemes: ["http", "https"])
  }

  public static func isValidWebSocketURI(_ url: URL) -> Bool {
    isValidEndpointURI(url, allowedSchemes: ["ws", "wss"])
  }

  private static func isValidEndpointURI(_ url: URL, allowedSchemes: Set<String>) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      allowedSchemes.contains(scheme),
      components.host?.isEmpty == false,
      components.query == nil,
      components.fragment == nil
    else {
      return false
    }
    return true
  }
}

private actor InstantAuthSessionObservers {
  private var continuations: [UUID: AsyncStream<InstantAuthSession?>.Continuation] = [:]

  func observe(current session: InstantAuthSession?) -> AsyncStream<InstantAuthSession?> {
    let id = UUID()
    let stream = AsyncStream<InstantAuthSession?>.makeStream(bufferingPolicy: .bufferingNewest(1))
    continuations[id] = stream.continuation
    stream.continuation.yield(session)
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.cancel(id: id) }
    }
    return stream.stream
  }

  func yield(_ session: InstantAuthSession?) {
    for continuation in continuations.values {
      continuation.yield(session)
    }
  }

  private func cancel(id: UUID) {
    continuations[id] = nil
  }
}

private final class InstantFileUploadProgressCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var isCancelled = false

  func cancel() {
    lock.lock()
    defer { lock.unlock() }
    isCancelled = true
  }

  func check() throws {
    lock.lock()
    defer { lock.unlock() }
    if isCancelled {
      throw CancellationError()
    }
  }
}

private struct InstantSharedRootWriteTarget: Hashable, Sendable {
  var namespace: String?
  var id: String
}

public final class InstantRuntime: Sendable {
  public static let selectedAppIDMetadataKey = "cli.selected_app_id"

  public let configuration: InstantRuntimeConfiguration
  public let store: InstantStore
  public let persistence: SQLitePersistenceStore
  let outbox: InstantOutbox
  private let authSessionObservers = InstantAuthSessionObservers()
  private let roomPresenceObservers =
    InstantSnapshotObservers<InstantRoomPresenceObservationKey, [InstantRoomPresenceMember]>()
  private let roomTopicObservers =
    InstantSnapshotObservers<InstantRoomTopicObservationKey, [InstantRoomTopicMessage]>()
  private let storedFilesObservers =
    InstantSnapshotObservers<InstantStoredFilesObservationKey, [InstantStoredFile]>()
  private let streamChunksObservers =
    InstantSnapshotObservers<InstantStreamChunksObservationKey, [InstantStreamChunk]>()
  private let operationGate = AsyncSerialGate()
  private let mutationFlushGate = AsyncSerialGate()

  private init(
    configuration: InstantRuntimeConfiguration,
    store: InstantStore,
    outbox: InstantOutbox,
    persistence: SQLitePersistenceStore
  ) {
    self.configuration = configuration
    self.store = store
    self.outbox = outbox
    self.persistence = persistence
  }

  public static func bootstrap(configuration: InstantRuntimeConfiguration) async throws -> Self {
    try validateEndpoints(configuration)
    try validateInitialAttributes(configuration.initialAttributes)

    let persistence = try SQLitePersistenceStore(fileURL: configuration.persistenceURL)
    configuration.actorHopRecorder?.record(.persistence)
    try await persistence.bootstrap()
    configuration.actorHopRecorder?.record(.persistence)
    let state = try await persistence.loadState()
    let store = InstantStore(snapshot: state.snapshot.store)
    let outbox = InstantOutbox(mutations: state.snapshot.outbox)
    let runtime = Self(
      configuration: configuration,
      store: store,
      outbox: outbox,
      persistence: persistence
    )

    if !configuration.initialAttributes.isEmpty {
      configuration.actorHopRecorder?.record(.store)
      let storeSnapshot = await store.mergeAttributes(configuration.initialAttributes)
      configuration.actorHopRecorder?.record(.persistence)
      try await persistence.saveStoreSnapshot(storeSnapshot)
    }

    return runtime
  }

  private static func validateInitialAttributes(_ attributes: [InstantAttribute]) throws {
    if let attribute = attributes.first(where: {
      $0.name == InstantQueryOrder.serverCreatedAtField
    }) {
      throw InstantError(
        code: .validationFailed,
        operation: "bootstrap attributes",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: attribute.id,
        message: "'\(InstantQueryOrder.serverCreatedAtField)' is reserved for order-only metadata.",
        recovery:
          "Rename the schema field, and use InstantQueryOrder.serverCreatedAt when ordering by "
          + "server creation time."
      )
    }
  }

  private static func validateEndpoints(_ configuration: InstantRuntimeConfiguration) throws {
    guard InstantRuntimeConfiguration.isValidAPIURI(configuration.apiURI) else {
      throw Self.endpointValidationFailed(
        name: "apiURI",
        requirement: "an absolute http or https URL with a host and no query or fragment"
      )
    }
    guard InstantRuntimeConfiguration.isValidWebSocketURI(configuration.websocketURI) else {
      throw endpointValidationFailed(
        name: "websocketURI",
        requirement: "an absolute ws or wss URL with a host and no query or fragment"
      )
    }
  }

  private static func endpointValidationFailed(name: String, requirement: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "bootstrap endpoint configuration",
      path: name,
      message: "\(name) must be \(requirement).",
      recovery: "Check the Instant runtime endpoint configuration before bootstrapping."
    )
  }

  @discardableResult
  public func transact(
    operations: [InstantTripleOperation],
    source: String = "local"
  ) async throws -> InstantStoreMutationResult {
    let transactionID = configuration.makeID()
    return try await transact(
      InstantStoreTransaction(id: transactionID, operations: operations),
      createdAt: configuration.now(),
      source: source
    )
  }

  @discardableResult
  public func transact(
    _ transaction: InstantStoreTransaction,
    createdAt: InstantTimestamp? = nil,
    source: String = "local"
  ) async throws -> InstantStoreMutationResult {
    await enterOperationGate()
    do {
      let result = try await performTransact(transaction, createdAt: createdAt, source: source)
      await leaveOperationGate()
      return result
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performTransact(
    _ transaction: InstantStoreTransaction,
    createdAt: InstantTimestamp?,
    source: String
  ) async throws -> InstantStoreMutationResult {
    var mutation: PendingMutation?

    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      if transaction.operations.isEmpty {
        recordActorHop(.store)
        await store.replaceSnapshot(state.snapshot.store)
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: state.snapshot.store.triples.count,
          emissions: []
        )
      }
      try await authorizeSharedRootWrites(transaction: transaction, snapshot: state.snapshot.store)
      if let existingMutation = state.snapshot.outbox.first(where: { $0.id == transaction.id }) {
        recordActorHop(.store)
        await store.replaceSnapshot(state.snapshot.store)
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        guard existingMutation.status == .pending else {
          throw validationFailed(
            operation: "transact",
            localID: transaction.id,
            message:
              "Mutation '\(transaction.id)' already exists in the local outbox with status '\(existingMutation.status.rawValue)'.",
            recovery:
              "Use a new transaction id, or retry the existing outbox mutation before sending it again."
          )
        }
        guard existingMutation.transaction == transaction else {
          throw validationFailed(
            operation: "transact",
            localID: transaction.id,
            message:
              "Mutation '\(transaction.id)' is already pending with different operations.",
            recovery:
              "Reuse the same prepared transaction when retrying, or generate a new transaction id."
          )
        }
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: state.snapshot.store.triples.count,
          emissions: []
        )
      }
      let pendingMutation: PendingMutation
      if let mutation {
        pendingMutation = mutation
      } else {
        let newMutation = PendingMutation(
          id: transaction.id,
          createdAt: createdAt ?? configuration.now(),
          transaction: transaction
        )
        mutation = newMutation
        pendingMutation = newMutation
      }
      let outboxSnapshot = (state.snapshot.outbox + [pendingMutation])
        .sorted(by: PendingMutation.creationOrder)
      recordActorHop(.store)
      let prepared = try await store.prepare(transaction, applyingTo: state.snapshot.store)
      recordActorHop(.persistence)
      let didSave = try await persistence.saveSnapshot(
        InstantPersistenceSnapshot(store: prepared.snapshot, outbox: outboxSnapshot),
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision
      )
      if didSave {
        recordActorHop(.store)
        let committed = await store.commitAndPublish(prepared)
        recordActorHop(.outbox)
        await outbox.replace(with: outboxSnapshot)
        return committed.result
      }
    }

    throw transactionChangedDuringPersistence(id: transaction.id)
  }

  public func observe(_ plan: InstantQueryPlan) async -> AsyncStream<InstantQueryEmission> {
    await enterOperationGate()
    recordActorHop(.persistence)
    let attributes: [InstantAttribute]
    if let state = try? await persistence.loadState() {
      recordActorHop(.store)
      await store.replaceSnapshot(state.snapshot.store)
      attributes = state.snapshot.store.attributes
    } else {
      recordActorHop(.store)
      attributes = await store.snapshot().attributes
    }
    if TripleIndexes.validate(plan, attributes: AttributeStore(attributes: attributes)) != nil {
      await leaveOperationGate()
      return Self.emptyObservation(plan)
    }
    recordActorHop(.store)
    let stream = await store.observe(plan)
    await leaveOperationGate()
    return stream
  }

  public func query(_ plan: InstantQueryPlan) async throws -> [InstantEntitySnapshot] {
    try await queryOnce(plan).values
  }

  public func queryOnce(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        if let issue = TripleIndexes.validate(
          plan,
          attributes: AttributeStore(attributes: state.snapshot.store.attributes)
        ) {
          throw validationFailed(
            operation: "validate query",
            namespace: issue.namespace,
            path: issue.path,
            message: issue.message,
            recovery: issue.recovery
          )
        }
        if try await persistedConnectionState() == .closed {
          recordActorHop(.persistence)
          let cachedQuery = try await persistence.cachedQuery(cacheKey: plan.cacheKey)
          throw InstantError(
            code: .networkFailed,
            operation: "queryOnce",
            namespace: plan.namespace,
            message: "Cannot run query '\(plan.id)' while the Instant connection is closed.",
            recovery:
              "Call connect() or run 'instant-swift-data connection connect' before querying again.",
            cachedQuery: cachedQuery
          )
        }
        recordActorHop(.store)
        await store.replaceSnapshot(state.snapshot.store)
        recordActorHop(.store)
        let emission = await store.materializeEmission(plan)
        recordActorHop(.persistence)
        let didSave = try await persistence.saveQueryCache(
          InstantCachedQuery(
            queryID: plan.id,
            plan: plan,
            emission: emission,
            updatedAt: configuration.now(),
            storeRevision: state.storeRevision
          ),
          expectedStoreRevision: state.storeRevision
        )
        if didSave {
          await leaveOperationGate()
          return emission
        }
      }

      throw queryCacheChangedDuringMaterialization(plan)
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func cachedQuery(_ plan: InstantQueryPlan) async throws -> InstantCachedQuery? {
    recordActorHop(.persistence)
    return try await persistence.cachedQuery(cacheKey: plan.cacheKey)
  }

  public func cachedQueries() async throws -> [InstantCachedQuery] {
    try await persistence.loadQueryCache()
  }

  public func selectedAppID() async throws -> String? {
    try await persistence.loadMetadataValue(key: Self.selectedAppIDMetadataKey)
  }

  public func saveSelectedAppID(_ appID: String) async throws -> String {
    let appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !appID.isEmpty else {
      throw validationFailed(
        operation: "select app",
        message: "App id must not be empty.",
        recovery: "Pass an app id, or set INSTANT_APP_ID for a temporary override."
      )
    }

    await operationGate.enter()
    do {
      try await persistence.saveMetadataValue(
        appID,
        key: Self.selectedAppIDMetadataKey,
        updatedAt: configuration.now()
      )
      await operationGate.leave()
      return appID
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func syncState() async throws -> InstantSyncState {
    InstantSyncState(
      processedTransactionID: try await persistence.loadMetadataValue(
        key: processedTransactionIDMetadataKey
      )
    )
  }

  public func markProcessedTransaction(id transactionID: String) async throws -> InstantSyncState {
    let transactionID = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !transactionID.isEmpty else {
      throw validationFailed(
        operation: "mark processed transaction",
        message: "Transaction id must not be empty.",
        recovery: "Pass the Instant transaction id that has been fully processed."
      )
    }

    await operationGate.enter()
    do {
      try await persistence.saveMetadataValue(
        transactionID,
        key: processedTransactionIDMetadataKey,
        updatedAt: configuration.now()
      )
      await operationGate.leave()
      return InstantSyncState(processedTransactionID: transactionID)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func connectionStatus() async throws -> InstantConnectionStatus {
    await operationGate.enter()
    do {
      let status = try await connectionStatusWithGateHeld()
      await operationGate.leave()
      return status
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func connect() async throws -> InstantConnectionStatus {
    await operationGate.enter()
    do {
      try await saveOpenedConnectionMetadataWithGateHeld()
      let status = try await connectionStatusWithGateHeld()
      await operationGate.leave()
      return status
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func closeConnection() async throws -> InstantConnectionStatus {
    await operationGate.enter()
    do {
      try await persistence.saveMetadataValue(
        InstantConnectionState.closed.rawValue,
        key: connectionStateMetadataKey,
        updatedAt: configuration.now()
      )
      let status = try await connectionStatusWithGateHeld()
      await operationGate.leave()
      return status
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func connectionStatusWithGateHeld() async throws -> InstantConnectionStatus {
    let state = try await persistence.loadState()
    let session = try await persistence.loadAuthSession(key: authSessionKey)
    let processedTransactionID = try await persistence.loadMetadataValue(
      key: processedTransactionIDMetadataKey
    )
    let storedState = try await persistedConnectionState()
    let lastErrorMessage = try await persistence.loadMetadataValue(
      key: connectionLastErrorMetadataKey
    )
    return InstantConnectionStatus(
      appID: configuration.appID,
      apiURI: configuration.apiURI,
      websocketURI: configuration.websocketURI,
      transport: .localCacheOnly,
      state: connectionState(storedState, isAuthenticated: session != nil),
      isAuthenticated: session != nil,
      userID: session?.userID,
      pendingMutationCount: state.snapshot.outbox.filter { $0.status == .pending }.count,
      processedTransactionID: processedTransactionID,
      lastErrorMessage: lastErrorMessage
    )
  }

  private func persistedConnectionState() async throws -> InstantConnectionState {
    recordActorHop(.persistence)
    return try await persistence.loadMetadataValue(key: connectionStateMetadataKey)
      .flatMap(InstantConnectionState.init(rawValue:))
      ?? .opened
  }

  private func saveOpenedConnectionMetadataWithGateHeld() async throws {
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.opened.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: configuration.now()
    )
    recordActorHop(.persistence)
    try await persistence.deleteMetadataValue(key: connectionLastErrorMetadataKey)
  }

  private func saveErroredConnectionMetadataWithGateHeld(message: String) async throws {
    let now = configuration.now()
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.errored.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: now
    )
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      message,
      key: connectionLastErrorMetadataKey,
      updatedAt: now
    )
  }

  private func recordConnectionError(_ error: Error) async {
    await operationGate.enter()
    do {
      try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
      await operationGate.leave()
    } catch {
      await operationGate.leave()
    }
  }

  private func connectionState(
    _ state: InstantConnectionState,
    isAuthenticated: Bool
  ) -> InstantConnectionState {
    switch state {
    case .opened, .authenticated:
      return isAuthenticated ? .authenticated : .opened
    case .connecting, .closed, .errored:
      return state
    }
  }

  public func authSession() async throws -> InstantAuthSession? {
    try await persistence.loadAuthSession(key: authSessionKey)
  }

  public func observeAuthSession() async throws -> AsyncStream<InstantAuthSession?> {
    await operationGate.enter()
    do {
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      let stream = await authSessionObservers.observe(current: session)
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func signInAsGuest() async throws -> InstantAuthSession {
    let now = configuration.now()
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: configuration.makeID(),
      isGuest: true,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func sendMagicCode(email rawEmail: String) async throws -> InstantMagicCodeChallenge {
    let email = try normalizedEmail(rawEmail, operation: "send magic code")
    let now = configuration.now()
    let challenge = try await configuration.magicCodeExchange.send(
      InstantMagicCodeSendRequest(
        appID: configuration.appID,
        email: email,
        sentAt: now,
        makeID: configuration.makeID
      )
    )

    await operationGate.enter()
    do {
      try await persistence.saveMagicCodeChallenge(challenge, key: magicCodeChallengeKey(email: email))
      await operationGate.leave()
      return challenge
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func signInWithMagicCode(
    email rawEmail: String,
    code rawCode: String
  ) async throws -> InstantAuthSession {
    let email = try normalizedEmail(rawEmail, operation: "sign in with magic code")
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with magic code",
        message: "Magic code must not be empty.",
        recovery: "Run 'instant-swift-data auth magic-code send <email>' and enter the returned local verification code."
      )
    }

    await operationGate.enter()
    do {
      let key = magicCodeChallengeKey(email: email)
      guard let challenge = try await persistence.loadMagicCodeChallenge(key: key) else {
        throw authValidationFailed(
          operation: "sign in with magic code",
          message: "No pending magic code exists for '\(email)'.",
          recovery: "Run 'instant-swift-data auth magic-code send \(email)' before verifying."
        )
      }
      let now = configuration.now()
      let verification = try await configuration.magicCodeExchange.verify(
        InstantMagicCodeVerifyRequest(
          appID: configuration.appID,
          email: email,
          code: code,
          challenge: challenge,
          verifiedAt: now
        )
      )
      let session = InstantAuthSession(
        appID: configuration.appID,
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        isGuest: false,
        createdAt: now,
        updatedAt: now
      )
      try await persistence.saveAuthSession(session, key: authSessionKey)
      try await persistence.deleteMagicCodeChallenge(key: key)
      await authSessionObservers.yield(session)
      await operationGate.leave()
      return session
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func signInWithRefreshToken(
    _ refreshToken: String,
    userID: String? = nil
  ) async throws -> InstantAuthSession {
    let token = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !token.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with token",
        message: "Refresh token must not be empty.",
        recovery: "Pass a refresh token, or use 'instant-swift-data auth guest'."
      )
    }

    let now = configuration.now()
    let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedUserID: String?
    if let trimmedUserID, !trimmedUserID.isEmpty {
      normalizedUserID = trimmedUserID
    } else {
      normalizedUserID = nil
    }
    let verification = try await configuration.refreshTokenVerifier.verify(
      InstantRefreshTokenVerificationRequest(
        appID: configuration.appID,
        refreshToken: token,
        userID: normalizedUserID,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func signInWithIDToken(
    clientName rawClientName: String,
    idToken rawIDToken: String,
    nonce rawNonce: String? = nil
  ) async throws -> InstantAuthSession {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with id token",
        message: "Client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'google-ios'."
      )
    }
    let idToken = rawIDToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !idToken.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with id token",
        message: "ID token must not be empty.",
        recovery: "Pass the ID token returned by the native OAuth provider."
      )
    }
    let now = configuration.now()
    let refreshToken = try await authSession()?.refreshToken
    let verification = try await configuration.idTokenExchange.signIn(
      InstantIDTokenSignInRequest(
        appID: configuration.appID,
        clientName: clientName,
        idToken: idToken,
        nonce: rawNonce,
        refreshToken: refreshToken,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func signInWithOAuth(
    code rawCode: String,
    codeVerifier rawCodeVerifier: String? = nil
  ) async throws -> InstantAuthSession {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with oauth",
        message: "OAuth authorization code must not be empty.",
        recovery: "Pass the authorization code returned by the OAuth callback."
      )
    }

    let now = configuration.now()
    // Match Instant's transport shape: pass the current refresh token so a live
    // OAuth exchange can upgrade/link the existing session when supported.
    let refreshToken = try await authSession()?.refreshToken
    let verification = try await configuration.oauthExchange.signIn(
      InstantOAuthSignInRequest(
        appID: configuration.appID,
        code: code,
        codeVerifier: rawCodeVerifier,
        refreshToken: refreshToken,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func oauthAuthorizationURL(
    clientName rawClientName: String,
    redirectURL: URL
  ) throws -> URL {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "create oauth authorization URL",
        message: "OAuth client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'google'."
      )
    }
    guard redirectURL.scheme?.isEmpty == false else {
      throw authValidationFailed(
        operation: "create oauth authorization URL",
        message: "OAuth redirect URL must be absolute.",
        recovery: "Pass the redirect URL registered with the OAuth client."
      )
    }

    var components = try endpointComponents(path: ["runtime", "oauth", "start"])
    components.queryItems = [
      URLQueryItem(name: "app_id", value: configuration.appID),
      URLQueryItem(name: "client_name", value: clientName),
      URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
    ]
    guard let url = components.url else {
      throw endpointFailed(operation: "create oauth authorization URL")
    }
    return url
  }

  public func issuerURI() throws -> URL {
    var components = try endpointComponents(path: ["runtime", configuration.appID])
    components.queryItems = nil
    guard let url = components.url else {
      throw endpointFailed(operation: "create oauth issuer URI")
    }
    return url
  }

  public func signOut() async throws {
    try await signOut(invalidateToken: true)
  }

  public func signOut(invalidateToken: Bool = true) async throws {
    let signedOutAt = configuration.now()
    var invalidationRequest: InstantAuthTokenInvalidationRequest?
    await operationGate.enter()
    do {
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      if invalidateToken, let refreshToken = session?.refreshToken {
        invalidationRequest = InstantAuthTokenInvalidationRequest(
          appID: configuration.appID,
          refreshToken: refreshToken,
          signedOutAt: signedOutAt
        )
      }
      try await persistence.deleteAuthSession(key: authSessionKey)
      await authSessionObservers.yield(nil)
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }

    if let invalidationRequest {
      do {
        try await configuration.authTokenInvalidator.invalidate(invalidationRequest)
      } catch {
        // Match Instant's client: failed token invalidation must not undo local sign-out.
      }
    }
  }

  @discardableResult
  public func setPresence(
    room: InstantRoomHandle,
    userID: String? = nil,
    values: [String: JSONValue]
  ) async throws -> InstantRoomPresenceMember {
    let room = try validatedRoom(room, operation: "set room presence")

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "set room presence")
      let now = configuration.now()
      let member = InstantRoomPresenceMember(
        appID: configuration.appID,
        room: room,
        userID: userID,
        values: values,
        updatedAt: now
      )
      try await persistence.saveRoomPresence(member)
      let members = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      await roomPresenceObservers.publish(
        members,
        for: roomPresenceObservationKey(room)
      )
      await operationGate.leave()
      return member
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func roomPresence(room: InstantRoomHandle) async throws -> [InstantRoomPresenceMember] {
    let room = try validatedRoom(room, operation: "list room presence")
    return try await persistence.loadRoomPresence(appID: configuration.appID, room: room)
  }

  public func observeRoomPresence(room: InstantRoomHandle) async throws
    -> AsyncStream<[InstantRoomPresenceMember]>
  {
    let room = try validatedRoom(room, operation: "observe room presence")

    await operationGate.enter()
    do {
      let members = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      let stream = await roomPresenceObservers.observe(
        key: roomPresenceObservationKey(room),
        current: members
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func leavePresence(room: InstantRoomHandle, userID: String? = nil) async throws -> String {
    let room = try validatedRoom(room, operation: "leave room presence")

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "leave room presence")
      try await persistence.deleteRoomPresence(
        appID: configuration.appID,
        room: room,
        userID: userID
      )
      let members = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      await roomPresenceObservers.publish(
        members,
        for: roomPresenceObservationKey(room)
      )
      await operationGate.leave()
      return userID
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeRoomPresenceObservationCount(room: InstantRoomHandle) async throws -> Int {
    let room = try validatedRoom(room, operation: "inspect room presence observers")
    return await roomPresenceObservers.activeCount(for: roomPresenceObservationKey(room))
  }

  @discardableResult
  public func publishTopicMessage(
    room: InstantRoomHandle,
    topic rawTopic: String,
    userID: String? = nil,
    payload: JSONValue
  ) async throws -> InstantRoomTopicMessage {
    let room = try validatedRoom(room, operation: "publish room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "publish room topic",
      recovery: "Pass the room topic name to publish."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "publish room topic")
      let message = InstantRoomTopicMessage(
        id: configuration.makeID(),
        appID: configuration.appID,
        room: room,
        topic: topic,
        userID: userID,
        payload: payload,
        createdAt: configuration.now()
      )
      try await persistence.saveRoomTopicMessage(message)
      let messages = try await persistence.loadRoomTopicMessages(
        appID: configuration.appID,
        room: room,
        topic: topic,
        limit: nil
      )
      await roomTopicObservers.publish(
        messages,
        for: roomTopicObservationKey(room: room, topic: topic)
      )
      await operationGate.leave()
      return message
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func roomTopicMessages(
    room: InstantRoomHandle,
    topic rawTopic: String,
    limit: Int? = nil
  ) async throws -> [InstantRoomTopicMessage] {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "list room topic",
        message: "Topic message limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to list every local message."
      )
    }
    let room = try validatedRoom(room, operation: "list room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "list room topic",
      recovery: "Pass the room topic name to list."
    )
    return try await persistence.loadRoomTopicMessages(
      appID: configuration.appID,
      room: room,
      topic: topic,
      limit: limit
    )
  }

  public func observeRoomTopicMessages(
    room: InstantRoomHandle,
    topic rawTopic: String
  ) async throws -> AsyncStream<[InstantRoomTopicMessage]> {
    let room = try validatedRoom(room, operation: "observe room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "observe room topic",
      recovery: "Pass the room topic name to observe."
    )

    await operationGate.enter()
    do {
      let messages = try await persistence.loadRoomTopicMessages(
        appID: configuration.appID,
        room: room,
        topic: topic,
        limit: nil
      )
      let stream = await roomTopicObservers.observe(
        key: roomTopicObservationKey(room: room, topic: topic),
        current: messages
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeRoomTopicObservationCount(
    room: InstantRoomHandle,
    topic rawTopic: String
  ) async throws -> Int {
    let room = try validatedRoom(room, operation: "inspect room topic observers")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "inspect room topic observers",
      recovery: "Pass the room topic name to inspect."
    )
    return await roomTopicObservers.activeCount(
      for: roomTopicObservationKey(room: room, topic: topic)
    )
  }

  public func uploadFile(
    from sourceURL: URL,
    name rawName: String? = nil,
    contentType rawContentType: String? = nil
  ) async throws -> InstantStoredFile {
    let file = try await preparedStoredFile(
      from: sourceURL,
      name: rawName,
      contentType: rawContentType,
      operation: "upload file"
    )
    return try await savePreparedStoredFile(file, contentsOf: sourceURL)
  }

  public func uploadFileProgress(
    from sourceURL: URL,
    name rawName: String? = nil,
    contentType rawContentType: String? = nil
  ) async throws -> AsyncThrowingStream<InstantFileUploadProgress, Error> {
    let file = try await preparedStoredFile(
      from: sourceURL,
      name: rawName,
      contentType: rawContentType,
      operation: "upload file"
    )
    let totalByteCount = try await persistence.regularFileByteCount(
      at: sourceURL,
      operation: "upload file"
    )
    let cancellation = InstantFileUploadProgressCancellation()

    return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(2)) { continuation in
      Task {
        let startedAt = self.configuration.now()
        continuation.yield(
          InstantFileUploadProgress(
            operationID: file.id,
            appID: file.appID,
            fileID: file.id,
            fileName: file.name,
            contentType: file.contentType,
            state: .loading,
            completedByteCount: 0,
            totalByteCount: totalByteCount,
            progress: 0,
            updatedAt: startedAt
          )
        )
        do {
          try await Task.sleep(nanoseconds: 5_000_000)
          try cancellation.check()
          let savedFile = try await self.savePreparedStoredFile(file, contentsOf: sourceURL)
          continuation.yield(
            InstantFileUploadProgress(
              operationID: file.id,
              appID: file.appID,
              fileID: file.id,
              fileName: file.name,
              contentType: file.contentType,
              state: .success,
              completedByteCount: savedFile.byteCount,
              totalByteCount: max(totalByteCount, savedFile.byteCount),
              progress: 1,
              file: savedFile,
              updatedAt: self.configuration.now()
            )
          )
          continuation.finish()
        } catch is CancellationError {
          return
        } catch {
          continuation.yield(
            InstantFileUploadProgress(
              operationID: file.id,
              appID: file.appID,
              fileID: file.id,
              fileName: file.name,
              contentType: file.contentType,
              state: .error,
              completedByteCount: 0,
              totalByteCount: totalByteCount,
              progress: 0,
              errorMessage: error.localizedDescription,
              updatedAt: self.configuration.now()
            )
          )
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        cancellation.cancel()
      }
    }
  }

  private func savePreparedStoredFile(
    _ file: InstantStoredFile,
    contentsOf sourceURL: URL
  ) async throws -> InstantStoredFile {
    try Task.checkCancellation()
    await operationGate.enter()
    do {
      let savedFile = try await persistence.saveStoredFile(file, contentsOf: sourceURL)
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(
        files,
        for: storedFilesObservationKey
      )
      await operationGate.leave()
      return savedFile
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func preparedStoredFile(
    from sourceURL: URL,
    name rawName: String?,
    contentType rawContentType: String?,
    operation: String
  ) async throws -> InstantStoredFile {
    let name = try resolvedFileName(rawName, sourceURL: sourceURL, operation: operation)
    let contentType = rawContentType?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    let userID = try await resolvedFileUserID(operation: operation)
    let now = configuration.now()
    return InstantStoredFile(
      id: configuration.makeID(),
      appID: configuration.appID,
      name: name,
      contentType: contentType,
      byteCount: 0,
      localPath: "",
      ownerUserID: userID,
      createdAt: now,
      updatedAt: now
    )
  }

  public func storedFiles() async throws -> [InstantStoredFile] {
    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "list files")
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await operationGate.leave()
      return files
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStoredFiles() async throws -> AsyncStream<[InstantStoredFile]> {
    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "observe files")
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      let stream = await storedFilesObservers.observe(
        key: storedFilesObservationKey,
        current: files
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func storedFileContents(id rawID: String) async throws -> InstantStoredFileContents {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "read file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "read file")
      guard let contents = try await persistence.readStoredFileContents(
        appID: configuration.appID,
        fileID: id
      ) else {
        throw validationFailed(
          operation: "read file",
          localID: id,
          message: "No local file exists for id '\(id)'.",
          recovery: "Run 'instant-swift-data files list' to inspect local file ids."
        )
      }
      await operationGate.leave()
      return contents
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func deleteStoredFile(id rawID: String) async throws -> InstantStoredFile {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "delete file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "delete file")
      guard let file = try await persistence.deleteStoredFile(
        appID: configuration.appID,
        fileID: id
      ) else {
        throw validationFailed(
          operation: "delete file",
          localID: id,
          message: "No local file exists for id '\(id)'.",
          recovery: "Run 'instant-swift-data files list' to inspect local file ids."
        )
      }
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(
        files,
        for: storedFilesObservationKey
      )
      await operationGate.leave()
      return file
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeStoredFilesObservationCount() async -> Int {
    await storedFilesObservers.activeCount(for: storedFilesObservationKey)
  }

  public func appendStreamChunk(
    streamID rawStreamID: String,
    payload: JSONValue
  ) async throws -> InstantStreamChunk {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "append stream chunk",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(
        operation: "append stream chunk",
        noun: "Stream"
      )
      let chunk = try await persistence.appendStreamChunk(
        appID: configuration.appID,
        streamID: streamID,
        chunkID: configuration.makeID(),
        payload: payload,
        userID: userID,
        createdAt: configuration.now()
      )
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: nil
      )
      await streamChunksObservers.publish(
        chunks,
        for: streamChunksObservationKey(streamID: streamID)
      )
      await operationGate.leave()
      return chunk
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamChunks(streamID rawStreamID: String, limit: Int? = nil) async throws
    -> [InstantStreamChunk]
  {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "read stream chunks",
        message: "Stream chunk limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to read every local chunk."
      )
    }
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "read stream chunks",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream chunks", noun: "Stream")
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: limit
      )
      await operationGate.leave()
      return chunks
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStreamChunks(streamID rawStreamID: String) async throws
    -> AsyncStream<[InstantStreamChunk]>
  {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "observe stream chunks",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(
        operation: "observe stream chunks",
        noun: "Stream"
      )
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: nil
      )
      let stream = await streamChunksObservers.observe(
        key: streamChunksObservationKey(streamID: streamID),
        current: chunks
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeStreamChunksObservationCount(streamID rawStreamID: String) async throws -> Int {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "inspect stream observers",
      recovery: "Pass a stream id to inspect."
    )
    return await streamChunksObservers.activeCount(
      for: streamChunksObservationKey(streamID: streamID)
    )
  }

  public func createShare(
    rootNamespace rawRootNamespace: String,
    rootID rawRootID: String
  ) async throws -> InstantShareSnapshot {
    let rootNamespace = try validatedNonEmpty(
      rawRootNamespace,
      label: "Share root namespace",
      operation: "create share",
      recovery: "Pass the namespace of the root record to share, such as 'remindersLists'."
    )
    let rootID = try validatedNonEmpty(
      rawRootID,
      label: "Share root id",
      operation: "create share",
      recovery: "Pass the id of the root record to share."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "create share", noun: "Share")
      let activeRootShares = try await persistence.loadActiveShareSnapshots(
        appID: configuration.appID,
        rootNamespace: rootNamespace,
        rootID: rootID
      )
      if let activeRootShare = activeRootShares.first {
        guard activeRootShare.share.ownerUserID == userID else {
          throw shareRootOwnershipPermissionRejected(snapshot: activeRootShare, userID: userID)
        }
        throw duplicateShareRejected(snapshot: activeRootShare)
      }
      let now = configuration.now()
      let shareID = configuration.makeID()
      let share = InstantShare(
        id: shareID,
        appID: configuration.appID,
        rootNamespace: rootNamespace,
        rootID: rootID,
        ownerUserID: userID,
        token: "local-share-\(configuration.makeID())",
        createdAt: now,
        updatedAt: now
      )
      let membership = InstantShareMembership(
        appID: configuration.appID,
        shareID: shareID,
        userID: userID,
        role: .owner,
        acceptedAt: now
      )
      let snapshot = try await persistence.createShare(share, ownerMembership: membership)
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func acceptShare(token rawToken: String) async throws -> InstantShareSnapshot {
    let token = try validatedNonEmpty(
      rawToken,
      label: "Share token",
      operation: "accept share",
      recovery: "Pass the token printed by 'instant-swift-data shares create'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "accept share", noun: "Share")
      guard
        let snapshot = try await persistence.acceptShare(
          appID: configuration.appID,
          token: token,
          userID: userID,
          acceptedAt: configuration.now()
        )
      else {
        throw shareNotFound(operation: "accept share", localID: token)
      }
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func shares() async throws -> [InstantShareSnapshot] {
    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "list shares", noun: "Share")
      let snapshots = try await persistence.loadShareSnapshots(
        appID: configuration.appID,
        userID: userID
      )
      await operationGate.leave()
      return snapshots
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func updateShareMembershipRole(
    shareID rawShareID: String,
    userID rawTargetUserID: String,
    role: InstantShareRole
  ) async throws -> InstantShareSnapshot {
    let shareID = try validatedNonEmpty(
      rawShareID,
      label: "Share id",
      operation: "update share role",
      recovery: "Pass a share id from 'instant-swift-data shares list'."
    )
    let targetUserID = try validatedNonEmpty(
      rawTargetUserID,
      label: "Share member user id",
      operation: "update share role",
      recovery: "Pass the user id of an accepted share member."
    )
    guard role != .owner else {
      throw validationFailed(
        operation: "update share role",
        localID: shareID,
        message: "The owner role cannot be assigned through membership role updates.",
        recovery: "Create a new share as the intended owner, or assign reader/writer to members."
      )
    }

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "update share role", noun: "Share")
      guard let snapshot = try await persistence.loadShareSnapshot(
        appID: configuration.appID,
        shareID: shareID
      ), !snapshot.share.isRevoked else {
        throw shareNotFound(operation: "update share role", localID: shareID)
      }
      guard snapshot.share.ownerUserID == userID else {
        throw shareRolePermissionRejected(snapshot: snapshot, userID: userID)
      }
      guard snapshot.share.ownerUserID != targetUserID else {
        throw validationFailed(
          operation: "update share role",
          localID: targetUserID,
          message: "The share owner's membership role cannot be changed.",
          recovery: "Update reader/writer roles for accepted non-owner members."
        )
      }
      guard snapshot.memberships.contains(where: { membership in
        membership.userID == targetUserID && !membership.isRevoked
      }) else {
        throw shareMembershipNotFound(
          operation: "update share role",
          shareID: shareID,
          userID: targetUserID
        )
      }
      guard let updated = try await persistence.updateShareMembershipRole(
        appID: configuration.appID,
        shareID: shareID,
        userID: targetUserID,
        role: role,
        updatedAt: configuration.now()
      ) else {
        throw shareMembershipNotFound(
          operation: "update share role",
          shareID: shareID,
          userID: targetUserID
        )
      }
      await operationGate.leave()
      return updated
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func revokeShare(id rawShareID: String) async throws -> InstantShareSnapshot {
    let shareID = try validatedNonEmpty(
      rawShareID,
      label: "Share id",
      operation: "revoke share",
      recovery: "Pass a share id from 'instant-swift-data shares list'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "revoke share", noun: "Share")
      guard let snapshot = try await persistence.loadShareSnapshot(
        appID: configuration.appID,
        shareID: shareID
      ) else {
        throw shareNotFound(operation: "revoke share", localID: shareID)
      }
      guard snapshot.share.ownerUserID == userID else {
        throw sharePermissionRejected(snapshot: snapshot, userID: userID)
      }
      let revoked = try await persistence.revokeShare(
        appID: configuration.appID,
        shareID: shareID,
        revokedAt: configuration.now()
      ) ?? snapshot
      await operationGate.leave()
      return revoked
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func authorizeSharedRootWrites(
    transaction: InstantStoreTransaction,
    snapshot: InstantStoreSnapshot
  ) async throws {
    let targets = sharedRootWriteTargets(in: transaction, snapshot: snapshot)
    guard !targets.isEmpty else { return }

    for target in targets.sorted(by: sharedRootWriteTargetSort) {
      let snapshots = try await persistence.loadActiveShareSnapshots(
        appID: configuration.appID,
        rootNamespace: target.namespace,
        rootID: target.id
      )
      guard !snapshots.isEmpty else { continue }

      guard let session = try await persistence.loadAuthSession(key: authSessionKey) else {
        throw sharedRootWritePermissionRejected(snapshot: snapshots[0], userID: nil)
      }

      if target.namespace != nil {
        guard canWriteSharedRoot(snapshots, userID: session.userID) else {
          throw sharedRootWritePermissionRejected(
            snapshot: snapshots[0],
            userID: session.userID
          )
        }
      } else {
        let snapshotsByNamespace = Dictionary(grouping: snapshots, by: \.share.rootNamespace)
        for namespace in snapshotsByNamespace.keys.sorted() {
          let namespaceSnapshots = snapshotsByNamespace[namespace] ?? []
          guard canWriteSharedRoot(namespaceSnapshots, userID: session.userID) else {
            throw sharedRootWritePermissionRejected(
              snapshot: namespaceSnapshots[0],
              userID: session.userID
            )
          }
        }
      }
    }
  }

  private func sharedRootWriteTargets(
    in transaction: InstantStoreTransaction,
    snapshot: InstantStoreSnapshot
  ) -> Set<InstantSharedRootWriteTarget> {
    let attributesByID = Dictionary(
      snapshot.attributes.map { ($0.id, $0) },
      uniquingKeysWith: { lhs, _ in lhs }
    )
    var targets: Set<InstantSharedRootWriteTarget> = []

    for operation in transaction.operations {
      switch operation {
      case let .insert(triple), let .merge(triple), let .retract(triple):
        let attribute = attributesByID[triple.attributeID]
        let namespace = sharedRootNamespace(for: triple.attributeID, attribute: attribute)
        targets.insert(InstantSharedRootWriteTarget(namespace: namespace, id: triple.entityID))
        insertRefWriteTargets(
          for: triple.value,
          attribute: attribute,
          snapshot: snapshot,
          attributesByID: attributesByID,
          into: &targets
        )

      case let .insertByLookup(lookup, attributeID, value, _, _),
        let .mergeByLookup(lookup, attributeID, value, _, _),
        let .retractByLookup(lookup, attributeID, value, _, _):
        let attribute = attributesByID[attributeID]
        insertRefWriteTargets(
          for: value,
          attribute: attribute,
          snapshot: snapshot,
          attributesByID: attributesByID,
          into: &targets
        )
        let sourceIDs = entityIDs(matching: lookup, snapshot: snapshot)
        if sourceIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
          lookup,
          attributesByID: attributesByID
        ) {
          targets.insert(target)
        }
        guard !sourceIDs.isEmpty else { continue }
        let namespace = sharedRootNamespace(for: attributeID, attribute: attribute)
        for entityID in sourceIDs {
          targets.insert(InstantSharedRootWriteTarget(namespace: namespace, id: entityID))
        }

      case let .deleteEntity(entityID):
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: entityID,
            snapshot: snapshot,
            attributesByID: attributesByID
          )
        )

      case let .deleteEntityByLookup(lookup):
        let entityIDs = entityIDs(matching: lookup, snapshot: snapshot)
        if entityIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
          lookup,
          attributesByID: attributesByID
        ) {
          targets.formUnion(
            cascadeDeleteWriteTargets(
              entityID: target.id,
              snapshot: snapshot,
              attributesByID: attributesByID
            )
          )
          targets.insert(target)
        } else {
          for entityID in entityIDs {
            targets.formUnion(
              cascadeDeleteWriteTargets(
                entityID: entityID,
                snapshot: snapshot,
                attributesByID: attributesByID
              )
            )
          }
        }

      case .requireEntityMissing, .requireEntityMissingByLookup, .requireEntityExists,
        .requireEntityExistsByLookup, .requireTripleExists, .ruleParams, .ruleParamsByLookup:
        break
      }
    }

    return targets
  }

  private func primaryKeyLookupWriteTarget(
    _ lookup: InstantLookupRef,
    attributesByID: [String: InstantAttribute]
  ) -> InstantSharedRootWriteTarget? {
    let attribute = attributesByID[lookup.attributeID]
    let isPrimaryKey = attribute?.primaryKey == true
      || attribute?.name == "id"
      || lookup.attributeID.hasSuffix("/id")
    guard isPrimaryKey, case let .string(entityID) = lookup.value else { return nil }
    return InstantSharedRootWriteTarget(
      namespace: sharedRootNamespace(for: lookup.attributeID, attribute: attribute),
      id: entityID
    )
  }

  private func sharedRootNamespace(
    for attributeID: String,
    attribute: InstantAttribute?
  ) -> String? {
    if let attribute {
      return attribute.namespace
    }
    let parts = attributeID.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return nil }
    return String(parts[0])
  }

  private func insertRefWriteTargets(
    for value: InstantValue,
    attribute: InstantAttribute?,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute],
    into targets: inout Set<InstantSharedRootWriteTarget>
  ) {
    let targetNamespace: String?
    if let attribute {
      guard attribute.valueType == .ref else { return }
      targetNamespace = attribute.linkNamespace
    } else {
      targetNamespace = nil
    }

    switch value {
    case let .ref(entityID):
      targets.insert(InstantSharedRootWriteTarget(namespace: targetNamespace, id: entityID))

    case let .lookupRef(lookup):
      let entityIDs = entityIDs(matching: lookup, snapshot: snapshot)
      if entityIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
        lookup,
        attributesByID: attributesByID
      ) {
        targets.insert(
          InstantSharedRootWriteTarget(
            namespace: targetNamespace ?? target.namespace,
            id: target.id
          )
        )
      }
      for entityID in entityIDs {
        targets.insert(InstantSharedRootWriteTarget(namespace: targetNamespace, id: entityID))
      }

    case .null, .bool, .number, .string, .date, .json:
      break
    }
  }

  private func cascadeDeleteWriteTargets(
    entityID: String,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute],
    visited: Set<String> = []
  ) -> Set<InstantSharedRootWriteTarget> {
    guard !visited.contains(entityID) else { return [] }
    var visited = visited
    visited.insert(entityID)
    var targets: Set<InstantSharedRootWriteTarget> = [
      InstantSharedRootWriteTarget(namespace: nil, id: entityID)
    ]

    let outgoingTriples = snapshot.triples.filter { $0.entityID == entityID }
    let incomingTriples = snapshot.triples.filter { triple in
      guard attributesByID[triple.attributeID]?.valueType == .ref,
        case let .ref(targetID) = triple.value
      else {
        return false
      }
      return targetID == entityID
    }

    for triple in outgoingTriples {
      guard let attribute = attributesByID[triple.attributeID],
        attribute.valueType == .ref,
        case let .ref(targetID) = triple.value
      else {
        continue
      }
      targets.insert(InstantSharedRootWriteTarget(namespace: nil, id: targetID))
      if attribute.onDeleteReverse == .cascade {
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: targetID,
            snapshot: snapshot,
            attributesByID: attributesByID,
            visited: visited
          )
        )
      }
    }

    for triple in incomingTriples {
      let attribute = attributesByID[triple.attributeID]
      targets.insert(InstantSharedRootWriteTarget(namespace: nil, id: triple.entityID))
      if attribute?.onDelete == .cascade {
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: triple.entityID,
            snapshot: snapshot,
            attributesByID: attributesByID,
            visited: visited
          )
        )
      }
    }

    return targets
  }

  private func entityIDs(
    matching lookup: InstantLookupRef,
    snapshot: InstantStoreSnapshot
  ) -> [String] {
    let ids = snapshot.triples.compactMap { triple -> String? in
      guard triple.attributeID == lookup.attributeID,
        lookupValue(lookup.value, matches: triple.value)
      else {
        return nil
      }
      return triple.entityID
    }
    return Array(Set(ids)).sorted()
  }

  private func lookupValue(_ lookupValue: InstantLookupValue, matches value: InstantValue) -> Bool {
    switch (lookupValue, value) {
    case (.null, .null):
      return true
    case let (.bool(lhs), .bool(rhs)):
      return lhs == rhs
    case let (.number(lhs), .number(rhs)):
      return lhs == rhs
    case let (.string(lhs), .string(rhs)):
      return lhs == rhs
    case let (.date(lhs), .date(rhs)):
      return lhs == rhs
    case let (.json(lhs), .json(rhs)):
      return lhs == rhs
    case let (.ref(lhs), .ref(rhs)):
      return lhs == rhs
    case (.null, _), (.bool, _), (.number, _), (.string, _), (.date, _), (.json, _), (.ref, _):
      return false
    }
  }

  private func canWriteSharedRoot(
    _ snapshots: [InstantShareSnapshot],
    userID: String
  ) -> Bool {
    snapshots.contains { snapshot in
      snapshot.memberships.contains { membership in
        membership.userID == userID
          && !membership.isRevoked
          && membership.role.canWriteSharedRoot
      }
    }
  }

  private func sharedRootWriteTargetSort(
    _ lhs: InstantSharedRootWriteTarget,
    _ rhs: InstantSharedRootWriteTarget
  ) -> Bool {
    if lhs.id == rhs.id {
      return (lhs.namespace ?? "") < (rhs.namespace ?? "")
    }
    return lhs.id < rhs.id
  }

  public func pendingMutations() async -> [PendingMutation] {
    recordActorHop(.outbox)
    return await outbox.pending()
  }

  public func outboxMutations() async -> [PendingMutation] {
    await outbox.all()
  }

  public func outboxTransportMutations(includeFailed: Bool = false) async
    -> [InstantTransportMutation]
  {
    await outbox.all()
      .filter { mutation in
        switch mutation.status {
        case .pending:
          return true
        case .confirmed:
          return false
        case .failed:
          return includeFailed
        }
      }
      .map(InstantTransportMutation.init)
  }

  public func flushPendingMutations(limit: Int? = nil) async throws
    -> InstantMutationTransportFlushResult
  {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "flush outbox",
        message: "Flush limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to flush every pending mutation."
      )
    }

    await enterMutationFlushGate()
    do {
      let request: InstantMutationTransportRequest
      let selectedMutationIDs: Set<String>

      await enterOperationGate()
      do {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        let pending = state.snapshot.outbox
          .filter { $0.status == .pending }
          .sorted(by: PendingMutation.creationOrder)
        let selected = Array(pending.prefix(limit ?? pending.count))
        request = InstantMutationTransportRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          websocketURI: configuration.websocketURI,
          mutations: selected.map(InstantTransportMutation.init)
        )
        selectedMutationIDs = Set(selected.map(\.id))

        guard !selected.isEmpty else {
          recordActorHop(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          await leaveOperationGate()
          await leaveMutationFlushGate()
          return InstantMutationTransportFlushResult(
            request: request,
            results: [],
            confirmed: [],
            failed: [],
            pendingMutationCount: pending.count,
            mutationCount: state.snapshot.outbox.count
          )
        }

        guard try await persistedConnectionState() != .closed else {
          throw InstantError(
            code: .networkFailed,
            operation: "flush outbox",
            message: "Cannot flush \(selected.count) pending mutation(s) while the Instant connection is closed.",
            recovery: "Call connect() before flushing pending mutations."
          )
        }

        await leaveOperationGate()
      } catch {
        await leaveOperationGate()
        throw error
      }

      let response: InstantMutationTransportResponse
      do {
        recordActorHop(.mutationTransport)
        response = try await configuration.mutationTransport.send(request)
      } catch {
        await recordConnectionError(error)
        throw error
      }
      let results = response.results.filter { selectedMutationIDs.contains($0.mutationID) }

      await enterOperationGate()
      do {
        for _ in 0..<5 {
          recordActorHop(.persistence)
          let latestState = try await persistence.loadState()
          let update = InstantOutbox.applyingTransportResults(
            results,
            in: latestState.snapshot.outbox,
            allowedMutationIDs: selectedMutationIDs
          )
          recordActorHop(.persistence)
          let didSave = try await persistence.saveOutbox(
            update.mutations,
            expectedOutboxRevision: latestState.outboxRevision
          )
          if didSave {
            recordActorHop(.outbox)
            await outbox.replace(with: update.mutations)
            if let failed = update.failed.first {
              try await saveErroredConnectionMetadataWithGateHeld(
                message: failed.failureMessage ?? "Mutation '\(failed.id)' failed during transport flush."
              )
            } else if !update.mutations.contains(where: { $0.status == .failed }),
              try await persistedConnectionState() != .closed
            {
              try await saveOpenedConnectionMetadataWithGateHeld()
            }
            let remainingPendingCount = update.mutations.filter { $0.status == .pending }.count
            await leaveOperationGate()
            await leaveMutationFlushGate()
            return InstantMutationTransportFlushResult(
              request: request,
              results: results,
              confirmed: update.confirmed,
              failed: update.failed,
              pendingMutationCount: remainingPendingCount,
              mutationCount: update.mutations.count
            )
          }
        }

        throw outboxChangedDuringFlush()
      } catch {
        await leaveOperationGate()
        throw error
      }
    } catch {
      await leaveMutationFlushGate()
      throw error
    }
  }

  @discardableResult
  public func confirmMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        guard let update = InstantOutbox.confirming(id: id, in: state.snapshot.outbox) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw outboxMutationNotFound(id: id)
        }
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: update.mutations)
          await operationGate.leave()
          return update.mutation
        }
      }

      throw outboxChangedDuringStatusUpdate(id: id)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func failMutation(id: String, message: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        guard let update = InstantOutbox.failing(
          id: id,
          message: message,
          in: state.snapshot.outbox
        ) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw outboxMutationNotFound(id: id)
        }
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: update.mutations)
          try await saveErroredConnectionMetadataWithGateHeld(message: message)
          await operationGate.leave()
          return update.mutation
        }
      }

      throw outboxChangedDuringStatusUpdate(id: id)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func retryMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        guard let update = InstantOutbox.retrying(id: id, in: state.snapshot.outbox) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw outboxMutationNotFound(id: id)
        }
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: update.mutations)
          if !update.mutations.contains(where: { $0.status == .failed }),
            try await persistedConnectionState() != .closed
          {
            try await saveOpenedConnectionMetadataWithGateHeld()
          }
          await operationGate.leave()
          return update.mutation
        }
      }

      throw outboxChangedDuringStatusUpdate(id: id)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func drainPendingMutationsLocally(limit: Int? = nil) async throws -> [PendingMutation] {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "drain outbox",
        message: "Drain limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to drain every pending mutation."
      )
    }

    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        let update = InstantOutbox.confirmingPending(limit: limit, in: state.snapshot.outbox)
        guard !update.confirmed.isEmpty else {
          recordActorHop(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          await leaveOperationGate()
          return []
        }
        recordActorHop(.persistence)
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          recordActorHop(.outbox)
          await outbox.replace(with: update.mutations)
          await leaveOperationGate()
          return update.confirmed
        }
      }

      throw outboxChangedDuringDrain()
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func localID(named name: String) async throws -> String {
    try await persistence.localID(named: name, makeID: configuration.makeID)
  }

  public func localIDs() async throws -> [InstantLocalID] {
    try await persistence.loadLocalIDs()
  }

  private func saveAuthSession(_ session: InstantAuthSession) async throws {
    await operationGate.enter()
    do {
      try await persistence.saveAuthSession(session, key: authSessionKey)
      await authSessionObservers.yield(session)
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func outboxMutationNotFound(id: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "update outbox mutation",
      localID: id,
      message: "No pending or historical outbox mutation exists for id '\(id)'.",
      recovery: "Run 'instant-swift-data outbox inspect' to list known mutation ids."
    )
  }

  private func outboxChangedDuringStatusUpdate(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "update outbox mutation",
      localID: id,
      message: "The local outbox changed repeatedly while updating mutation '\(id)'.",
      recovery: "Retry the outbox update after inspecting the current outbox."
    )
  }

  private func outboxChangedDuringDrain() -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "drain outbox",
      message: "The local outbox changed repeatedly while draining pending mutations.",
      recovery: "Retry the drain after inspecting the current outbox."
    )
  }

  private func outboxChangedDuringFlush() -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "flush outbox",
      message: "The local outbox changed repeatedly while applying transport results.",
      recovery: "Retry the flush after inspecting the current outbox."
    )
  }

  private func transactionChangedDuringPersistence(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "persist transaction",
      localID: id,
      message: "The local store changed repeatedly while persisting transaction '\(id)'.",
      recovery: "Retry the transaction after reloading the local cache."
    )
  }

  private func validationFailed(
    operation: String,
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      namespace: namespace,
      path: path,
      localID: localID,
      message: message,
      recovery: recovery
    )
  }

  private func authValidationFailed(
    operation: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .authFailed,
      operation: operation,
      message: message,
      recovery: recovery
    )
  }

  private func endpointComponents(path pathComponents: [String]) throws -> URLComponents {
    guard InstantRuntimeConfiguration.isValidAPIURI(configuration.apiURI) else {
      throw Self.endpointValidationFailed(
        name: "apiURI",
        requirement: "an absolute http or https URL with a host and no query or fragment"
      )
    }
    var url = configuration.apiURI
    for pathComponent in pathComponents {
      url.appendPathComponent(pathComponent)
    }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw endpointFailed(operation: "create Instant endpoint URL")
    }
    return components
  }

  private func endpointFailed(operation: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: operation,
      message: "The Instant endpoint URL could not be constructed.",
      recovery: "Check the configured apiURI and appID before retrying."
    )
  }

  private func shareNotFound(operation: String, localID: String) -> InstantError {
    validationFailed(
      operation: operation,
      localID: localID,
      message: "Share '\(localID)' was not found or has been revoked.",
      recovery: "Check the share id or token, then create a new share if needed."
    )
  }

  private func shareMembershipNotFound(
    operation: String,
    shareID: String,
    userID: String
  ) -> InstantError {
    validationFailed(
      operation: operation,
      localID: userID,
      message: "User '\(userID)' is not an active member of share '\(shareID)'.",
      recovery: "Have the user accept the share token before updating their role."
    )
  }

  private func sharePermissionRejected(snapshot: InstantShareSnapshot, userID: String) -> InstantError {
    InstantError(
      code: .permissionRejected,
      operation: "revoke share",
      localID: snapshot.share.id,
      message:
        "User '\(userID)' cannot revoke share '\(snapshot.share.id)' owned by '\(snapshot.share.ownerUserID)'.",
      recovery: "Sign in as the share owner before revoking it."
    )
  }

  private func shareRolePermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String
  ) -> InstantError {
    let message =
      "User '\(userID)' cannot update roles for share '\(snapshot.share.id)' owned by '\(snapshot.share.ownerUserID)'."
    return InstantError(
      code: .permissionRejected,
      operation: "update share role",
      localID: snapshot.share.id,
      message: message,
      recovery: "Sign in as the share owner before updating member roles."
    )
  }

  private func duplicateShareRejected(snapshot: InstantShareSnapshot) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    return validationFailed(
      operation: "create share",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message:
        "Shared root '\(root)' already has active share '\(snapshot.share.id)'.",
      recovery: "Use the existing share token, or revoke the current share before creating another one."
    )
  }

  private func shareRootOwnershipPermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String
  ) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    let message =
      "User '\(userID)' cannot create a share for shared root '\(root)' owned by '\(snapshot.share.ownerUserID)'."
    return InstantError(
      code: .permissionRejected,
      operation: "create share",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message: message,
      recovery: "Sign in as the share owner, or ask the owner to manage the existing share."
    )
  }

  private func sharedRootWritePermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String?
  ) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    let role = userID.flatMap { userID in
      snapshot.memberships.first { $0.userID == userID }?.role.rawValue
    }
    let message: String
    if let userID {
      if let role {
        message =
          "User '\(userID)' has \(role) access to shared root '\(root)' and cannot write it."
      } else {
        message =
          "User '\(userID)' is not a member of share '\(snapshot.share.id)' for shared root '\(root)'."
      }
    } else {
      message = "Shared root '\(root)' requires a signed-in owner or writer before it can be written."
    }

    return InstantError(
      code: .permissionRejected,
      operation: "write shared root",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message: message,
      recovery: "Sign in as the share owner or a writer before mutating the shared record."
    )
  }

  private func normalizedEmail(_ email: String, operation: String) throws -> String {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard email.contains("@"), email.contains(".") else {
      throw authValidationFailed(
        operation: operation,
        message: "Email address '\(email)' is not valid.",
        recovery: "Pass an email address such as user@example.com."
      )
    }
    return email
  }

  private func resolvedRoomUserID(_ userID: String?, operation: String) async throws -> String {
    if let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
      return userID
    }
    if let session = try await persistence.loadAuthSession(key: authSessionKey) {
      return session.userID
    }
    throw authValidationFailed(
      operation: operation,
      message: "Room operations require a signed-in user.",
      recovery: "Run 'instant-swift-data auth guest' first, or pass --user-id <id>."
    )
  }

  private func resolvedFileUserID(operation: String) async throws -> String {
    try await resolvedAuthenticatedUserID(operation: operation, noun: "File")
  }

  private func resolvedAuthenticatedUserID(operation: String, noun: String) async throws -> String {
    if let session = try await persistence.loadAuthSession(key: authSessionKey) {
      return session.userID
    }
    throw authValidationFailed(
      operation: operation,
      message: "\(noun) operations require a signed-in user.",
      recovery: "Run 'instant-swift-data auth guest' first."
    )
  }

  private func resolvedFileName(
    _ rawName: String?,
    sourceURL: URL,
    operation: String
  ) throws -> String {
    let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      throw validationFailed(
        operation: operation,
        message: "File name must not be empty.",
        recovery: "Pass --name <name>, or upload a file path with a non-empty last path component."
      )
    }
    return name
  }

  private func validatedRoom(
    _ room: InstantRoomHandle,
    operation: String
  ) throws -> InstantRoomHandle {
    InstantRoomHandle(
      type: try validatedNonEmpty(
        room.type,
        label: "Room type",
        operation: operation,
        recovery: "Pass a room type, such as 'chat'."
      ),
      id: try validatedNonEmpty(
        room.id,
        label: "Room id",
        operation: operation,
        recovery: "Pass a room id, such as 'lobby'."
      )
    )
  }

  private func validatedNonEmpty(
    _ value: String,
    label: String,
    operation: String,
    recovery: String
  ) throws -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw validationFailed(
        operation: operation,
        message: "\(label) must not be empty.",
        recovery: recovery
      )
    }
    return value
  }

  private func queryCacheChangedDuringMaterialization(_ plan: InstantQueryPlan) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "cache query result",
      message: "The local SQLite store changed repeatedly while materializing query '\(plan.id)'.",
      recovery: "Retry the query, or reduce concurrent writes against the same local cache."
    )
  }

  private var authSessionKey: String {
    "auth:\(configuration.appID)"
  }

  private func magicCodeChallengeKey(email: String) -> String {
    "auth.magic_code:\(configuration.appID):\(email)"
  }

  private var processedTransactionIDMetadataKey: String {
    "sync.processed_transaction_id:\(configuration.appID)"
  }

  private var connectionStateMetadataKey: String {
    "connection.state:\(configuration.appID)"
  }

  private var connectionLastErrorMetadataKey: String {
    "connection.last_error:\(configuration.appID)"
  }

  private func roomPresenceObservationKey(_ room: InstantRoomHandle) -> InstantRoomPresenceObservationKey {
    InstantRoomPresenceObservationKey(appID: configuration.appID, room: room)
  }

  private func roomTopicObservationKey(
    room: InstantRoomHandle,
    topic: String
  ) -> InstantRoomTopicObservationKey {
    InstantRoomTopicObservationKey(
      appID: configuration.appID,
      room: room,
      topic: topic
    )
  }

  private var storedFilesObservationKey: InstantStoredFilesObservationKey {
    InstantStoredFilesObservationKey(appID: configuration.appID)
  }

  private func streamChunksObservationKey(streamID: String) -> InstantStreamChunksObservationKey {
    InstantStreamChunksObservationKey(appID: configuration.appID, streamID: streamID)
  }

  private static func emptyObservation(_ plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
    AsyncStream<InstantQueryEmission> { continuation in
      continuation.yield(InstantQueryEmission(queryID: plan.id, sequence: 0, values: []))
      continuation.finish()
    }
  }

  private func recordActorHop(_ boundary: InstantActorHopBoundary) {
    configuration.actorHopRecorder?.record(boundary)
  }

  private func enterOperationGate() async {
    recordActorHop(.operationGate)
    await operationGate.enter()
  }

  private func leaveOperationGate() async {
    recordActorHop(.operationGate)
    await operationGate.leave()
  }

  private func enterMutationFlushGate() async {
    recordActorHop(.mutationFlushGate)
    await mutationFlushGate.enter()
  }

  private func leaveMutationFlushGate() async {
    recordActorHop(.mutationFlushGate)
    await mutationFlushGate.leave()
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
