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
  public let configuration: InstantRuntimeConfiguration
  public let store: InstantStore
  public let outbox: InstantOutbox
  public let persistence: SQLitePersistenceStore
  private let transactionGate = AsyncSerialGate()

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
    let snapshot = try await persistence.loadSnapshot()
    let store = InstantStore(snapshot: snapshot.store)
    let outbox = InstantOutbox(mutations: snapshot.outbox)
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
    await transactionGate.enter()
    do {
      let result = try await performTransact(transaction, createdAt: createdAt, source: source)
      await transactionGate.leave()
      return result
    } catch {
      await transactionGate.leave()
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

  public func query(_ plan: InstantQueryPlan) async -> [InstantEntitySnapshot] {
    await store.materialize(plan)
  }

  public func pendingMutations() async -> [PendingMutation] {
    await outbox.pending()
  }

  public func localID(named name: String) async throws -> String {
    try await persistence.localID(named: name, makeID: configuration.makeID)
  }
}
