import Foundation

public struct ServerTransactionLoopbackValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var todoIDs: [String]
  public var todoTexts: [String]
  public var pendingMutationIDs: [String]
  public var processedTransactionID: String?
  public var mutationTransactionID: String?
  public var changedEntityIDs: [String]
  public var emissionQueryIDs: [String]
  public var observerTodoIDs: [String]
  public var pendingMutationCount: Int
  public var storeRevision: Int64
  public var outboxRevision: Int64

  public init(
    cachePath: String,
    todoIDs: [String] = [],
    todoTexts: [String] = [],
    pendingMutationIDs: [String] = [],
    processedTransactionID: String? = nil,
    mutationTransactionID: String? = nil,
    changedEntityIDs: [String] = [],
    emissionQueryIDs: [String] = [],
    observerTodoIDs: [String] = [],
    pendingMutationCount: Int = 0,
    storeRevision: Int64 = 0,
    outboxRevision: Int64 = 0
  ) {
    self.cachePath = cachePath
    self.todoIDs = todoIDs
    self.todoTexts = todoTexts
    self.pendingMutationIDs = pendingMutationIDs
    self.processedTransactionID = processedTransactionID
    self.mutationTransactionID = mutationTransactionID
    self.changedEntityIDs = changedEntityIDs
    self.emissionQueryIDs = emissionQueryIDs
    self.observerTodoIDs = observerTodoIDs
    self.pendingMutationCount = pendingMutationCount
    self.storeRevision = storeRevision
    self.outboxRevision = outboxRevision
  }
}

public struct ServerTransactionLoopbackValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var evidence: [ValidationEvidenceRow<ServerTransactionLoopbackValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    evidence: [ValidationEvidenceRow<ServerTransactionLoopbackValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.evidence = evidence
  }
}

public enum InstantSwiftDataServerTransactionLoopbackValidation {
  public static func run(
    appID: String = "server-transaction-loopback-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> ServerTransactionLoopbackValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataServerLoopback-\(makeID())", isDirectory: true)
        .appendingPathComponent("state.sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: timestamp,
        makeID: makeID
      )
    )

    var evidence: [ValidationEvidenceRow<ServerTransactionLoopbackValidationDetails>] = []
    let localCreatedAt = timestamp()
    let serverCreatedAt = InstantTimestamp(milliseconds: localCreatedAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "validation.loopback.local",
        operations: TodoExample.createOperations(
          id: "validation-loopback-local",
          text: "Local optimistic transaction",
          createdAt: localCreatedAt,
          transactionID: "validation.loopback.local"
        )
      ),
      createdAt: localCreatedAt,
      source: "validation.server.loopback.local"
    )
    evidence.append(
      try await evidenceRow(
        event: "local-outbox",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )

    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    guard let initialEmission = await iterator.next() else {
      throw validationError(
        operation: "validate server loopback observer",
        message: "Expected the live todo observer to emit the local optimistic row."
      )
    }
    let initialTodos = try TodoExample.decode(initialEmission.values)
    guard initialTodos.map(\.id) == ["validation-loopback-local"] else {
      throw validationError(
        operation: "validate server loopback observer",
        message: "Expected the initial live todo observer emission to contain only the local row."
      )
    }

    let application = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "validation.loopback.server",
        operations: TodoExample.createOperations(
          id: "validation-loopback-server",
          text: "Server-applied transaction",
          createdAt: serverCreatedAt,
          transactionID: "validation.loopback.server"
        )
      ),
      receivedAt: InstantTimestamp(milliseconds: serverCreatedAt.milliseconds + 1)
    )
    evidence.append(
      try await evidenceRow(
        event: "server-apply",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        application: application
      )
    )

    guard let observerEmission = await iterator.next() else {
      throw validationError(
        operation: "validate server loopback observer",
        message: "Expected the live todo observer to emit the server-applied row."
      )
    }
    let observerTodos = try TodoExample.decode(observerEmission.values)
    guard observerTodos.map(\.id) == ["validation-loopback-local", "validation-loopback-server"]
    else {
      throw validationError(
        operation: "validate server loopback observer",
        message: "Expected the observer to contain local and server todos after applying the server transaction."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "observer-publish",
        runtime: runtime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        application: application,
        observerTodos: observerTodos
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: timestamp,
        makeID: makeID
      )
    )
    let relaunchedTodos = try await TodoExample.decode(relaunchedRuntime.query(TodoExample.query))
    let relaunchedSyncState = try await relaunchedRuntime.syncState()
    let relaunchedPending = await relaunchedRuntime.pendingMutations()
    guard relaunchedTodos.map(\.id) == ["validation-loopback-local", "validation-loopback-server"],
      relaunchedSyncState.processedTransactionID == "validation.loopback.server",
      relaunchedPending.map(\.id) == ["validation.loopback.local"]
    else {
      throw validationError(
        operation: "validate server loopback relaunch",
        message: "Expected the server transaction checkpoint and local outbox to persist across relaunch."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "relaunch",
        runtime: relaunchedRuntime,
        cacheURL: cacheURL,
        timestamp: timestamp,
        application: application
      )
    )

    return ServerTransactionLoopbackValidationResult(
      appID: appID,
      cacheURL: cacheURL,
      evidence: evidence
    )
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp,
    application: InstantServerTransactionApplicationResult? = nil,
    observerTodos: [TodoRecord] = []
  ) async throws -> ValidationEvidenceRow<ServerTransactionLoopbackValidationDetails> {
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    let pending = await runtime.pendingMutations()
    let syncState = try await runtime.syncState()
    let state = try await runtime.persistence.loadState()
    return ValidationEvidenceRow(
      caseID: "validation.server.transaction.loopback",
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: ServerTransactionLoopbackValidationDetails(
        cachePath: cacheURL.path,
        todoIDs: todos.map(\.id),
        todoTexts: todos.map(\.text),
        pendingMutationIDs: pending.map(\.id),
        processedTransactionID: syncState.processedTransactionID,
        mutationTransactionID: application?.mutation.transactionID,
        changedEntityIDs: application?.mutation.changedEntityIDs.sorted() ?? [],
        emissionQueryIDs: application?.mutation.emissions.map(\.queryID) ?? [],
        observerTodoIDs: observerTodos.map(\.id),
        pendingMutationCount: application?.pendingMutationCount ?? pending.count,
        storeRevision: state.storeRevision,
        outboxRevision: state.outboxRevision
      )
    )
  }

  private static func validationError(
    operation: String,
    message: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery: "Inspect server transaction application, observer publishing, and outbox persistence."
    )
  }
}
