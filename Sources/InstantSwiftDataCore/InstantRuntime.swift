import Foundation

public struct InstantRuntimeConfiguration: Sendable {
  public var appID: String
  public var persistenceURL: URL
  public var initialAttributes: [InstantAttribute]
  public var now: @Sendable () -> InstantTimestamp
  public var makeID: @Sendable () -> String

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) {
    self.appID = appID
    self.persistenceURL = persistenceURL
    self.initialAttributes = initialAttributes
    self.now = now
    self.makeID = makeID
  }
}

public final class InstantRuntime: Sendable {
  public static let selectedAppIDMetadataKey = "cli.selected_app_id"

  public let configuration: InstantRuntimeConfiguration
  public let store: InstantStore
  public let persistence: SQLitePersistenceStore
  let outbox: InstantOutbox
  private let operationGate = AsyncSerialGate()

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
    let persistence = try SQLitePersistenceStore(fileURL: configuration.persistenceURL)
    try await persistence.bootstrap()
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
      let storeSnapshot = await store.mergeAttributes(configuration.initialAttributes)
      try await persistence.saveStoreSnapshot(storeSnapshot)
    }

    return runtime
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
    await operationGate.enter()
    do {
      let result = try await performTransact(transaction, createdAt: createdAt, source: source)
      await operationGate.leave()
      return result
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func performTransact(
    _ transaction: InstantStoreTransaction,
    createdAt: InstantTimestamp?,
    source: String
  ) async throws -> InstantStoreMutationResult {
    let mutation = PendingMutation(
      id: transaction.id,
      createdAt: createdAt ?? configuration.now(),
      transaction: transaction
    )

    let outboxSnapshot = await outbox.enqueue(mutation)
    let prepared = await store.prepare(transaction)
    try await persistence.saveSnapshot(
      InstantPersistenceSnapshot(store: prepared.snapshot, outbox: outboxSnapshot)
    )
    await store.publish(prepared.result.emissions)
    return prepared.result
  }

  public func observe(_ plan: InstantQueryPlan) async -> AsyncStream<InstantQueryEmission> {
    await store.observe(plan)
  }

  public func query(_ plan: InstantQueryPlan) async throws -> [InstantEntitySnapshot] {
    try await queryOnce(plan).values
  }

  public func queryOnce(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    await operationGate.enter()
    do {
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        await store.replaceSnapshot(state.snapshot.store)
        let emission = await store.materializeEmission(plan)
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
          await operationGate.leave()
          return emission
        }
      }

      throw queryCacheChangedDuringMaterialization(plan)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func cachedQuery(_ plan: InstantQueryPlan) async throws -> InstantCachedQuery? {
    try await persistence.cachedQuery(id: plan.id)
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

  public func authSession() async throws -> InstantAuthSession? {
    try await persistence.loadAuthSession(key: authSessionKey)
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

    let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedUserID: String
    if let trimmedUserID, !trimmedUserID.isEmpty {
      resolvedUserID = trimmedUserID
    } else {
      resolvedUserID = "token-\(configuration.makeID())"
    }
    let now = configuration.now()
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: resolvedUserID,
      refreshToken: token,
      isGuest: false,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func signOut() async throws {
    await operationGate.enter()
    do {
      try await persistence.deleteAuthSession(key: authSessionKey)
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func pendingMutations() async -> [PendingMutation] {
    await outbox.pending()
  }

  public func outboxMutations() async -> [PendingMutation] {
    await outbox.all()
  }

  @discardableResult
  public func confirmMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      guard let update = await outbox.markConfirmed(id: id) else {
        throw outboxMutationNotFound(id: id)
      }
      try await persistence.saveOutbox(update.mutations)
      await operationGate.leave()
      return update.mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func failMutation(id: String, message: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      guard let update = await outbox.markFailed(id: id, message: message) else {
        throw outboxMutationNotFound(id: id)
      }
      try await persistence.saveOutbox(update.mutations)
      await operationGate.leave()
      return update.mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func localID(named name: String) async throws -> String {
    try await persistence.localID(named: name, makeID: configuration.makeID)
  }

  private func saveAuthSession(_ session: InstantAuthSession) async throws {
    await operationGate.enter()
    do {
      try await persistence.saveAuthSession(session, key: authSessionKey)
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

  private func validationFailed(
    operation: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
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
}
