import Foundation

public struct TypeScriptServerTransactionOperation: Codable, Equatable, Sendable {
  public struct Value: Codable, Equatable, Sendable {
    public var type: String
    public var string: String?
    public var bool: Bool?
    public var dateMs: Int64?

    public init(
      type: String,
      string: String? = nil,
      bool: Bool? = nil,
      dateMs: Int64? = nil
    ) {
      self.type = type
      self.string = string
      self.bool = bool
      self.dateMs = dateMs
    }

    public static func string(_ value: String) -> Self {
      Self(type: "string", string: value)
    }

    public static func bool(_ value: Bool) -> Self {
      Self(type: "bool", bool: value)
    }

    public static func date(milliseconds: Int64) -> Self {
      Self(type: "date", dateMs: milliseconds)
    }
  }

  public var type: String
  public var entityID: String
  public var namespace: String?
  public var attributeID: String?
  public var value: Value?
  public var txTimeMs: Int64?

  public init(
    type: String,
    entityID: String,
    namespace: String? = nil,
    attributeID: String? = nil,
    value: Value? = nil,
    txTimeMs: Int64? = nil
  ) {
    self.type = type
    self.entityID = entityID
    self.namespace = namespace
    self.attributeID = attributeID
    self.value = value
    self.txTimeMs = txTimeMs
  }
}

public struct TypeScriptServerTransactionContract: Codable, Equatable, Sendable {
  public var caseID: String
  public var event: String
  public var appID: String
  public var transactionID: String
  public var processedTransactionID: String
  public var entityID: String
  public var text: String
  public var createdAtMs: Int64
  public var operations: [TypeScriptServerTransactionOperation]

  public init(
    caseID: String = "validation.typescript.server.transaction.contract",
    event: String = "typescript-server-transaction-contract",
    appID: String,
    transactionID: String,
    processedTransactionID: String? = nil,
    entityID: String,
    text: String,
    createdAtMs: Int64,
    operations: [TypeScriptServerTransactionOperation]? = nil
  ) {
    self.caseID = caseID
    self.event = event
    self.appID = appID
    self.transactionID = transactionID
    self.processedTransactionID = processedTransactionID ?? transactionID
    self.entityID = entityID
    self.text = text
    self.createdAtMs = createdAtMs
    self.operations =
      operations
      ?? Self.todoCreateOperations(
        entityID: entityID,
        text: text,
        createdAtMs: createdAtMs
      )
  }

  enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case event
    case appID
    case transactionID
    case processedTransactionID
    case entityID
    case text
    case createdAtMs
    case operations
  }

  private static func todoCreateOperations(
    entityID: String,
    text: String,
    createdAtMs: Int64
  ) -> [TypeScriptServerTransactionOperation] {
    [
      TypeScriptServerTransactionOperation(
        type: "requireEntityMissing",
        entityID: entityID,
        namespace: TodoExample.namespace
      ),
      TypeScriptServerTransactionOperation(
        type: "insert",
        entityID: entityID,
        attributeID: InstantAttribute.primaryKeyID(namespace: TodoExample.namespace),
        value: .string(entityID),
        txTimeMs: createdAtMs
      ),
      TypeScriptServerTransactionOperation(
        type: "insert",
        entityID: entityID,
        attributeID: "todos/text",
        value: .string(text),
        txTimeMs: createdAtMs
      ),
      TypeScriptServerTransactionOperation(
        type: "insert",
        entityID: entityID,
        attributeID: "todos/isCompleted",
        value: .bool(false),
        txTimeMs: createdAtMs
      ),
      TypeScriptServerTransactionOperation(
        type: "insert",
        entityID: entityID,
        attributeID: "todos/createdAt",
        value: .date(milliseconds: createdAtMs),
        txTimeMs: createdAtMs
      ),
    ]
  }
}

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
  public static func loadTypeScriptServerTransactionContract(
    from url: URL
  ) throws -> TypeScriptServerTransactionContract {
    try JSONDecoder().decode(
      TypeScriptServerTransactionContract.self,
      from: Data(contentsOf: url)
    )
  }

  public static func run(
    appID: String = "server-transaction-loopback-validation",
    cacheURL: URL? = nil,
    typeScriptServerTransactionContract: TypeScriptServerTransactionContract? = nil,
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
    let expectedTodoIDsWithoutTypeScript = [
      "validation-loopback-local",
      "validation-loopback-server",
    ]
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
    guard observerTodos.map(\.id) == expectedTodoIDsWithoutTypeScript else {
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

    var finalApplication = application
    var expectedFinalTodoIDs = expectedTodoIDsWithoutTypeScript
    if let typeScriptContract = typeScriptServerTransactionContract {
      guard typeScriptContract.appID == appID else {
        throw validationError(
          operation: "validate TypeScript server transaction contract",
          message:
            "Expected the TypeScript server transaction contract app id to match \(appID), got \(typeScriptContract.appID)."
        )
      }

      let typeScriptCreatedAt = InstantTimestamp(milliseconds: typeScriptContract.createdAtMs)
      let typeScriptApplication = try await runtime.applyServerTransaction(
        InstantStoreTransaction(
          id: typeScriptContract.transactionID,
          operations: try instantOperations(from: typeScriptContract)
        ),
        processedTransactionID: typeScriptContract.processedTransactionID,
        receivedAt: InstantTimestamp(milliseconds: typeScriptCreatedAt.milliseconds + 1)
      )
      guard
        typeScriptApplication.mutation.changedEntityIDs.contains(typeScriptContract.entityID),
        typeScriptApplication.mutation.emissions.contains(where: { $0.queryID == TodoExample.query.id })
      else {
        throw validationError(
          operation: "validate TypeScript server transaction contract",
          message:
            "Expected the TypeScript-authored server transaction to mutate \(typeScriptContract.entityID) and publish the todo observer."
        )
      }
      guard let typeScriptObserverEmission = await iterator.next() else {
        throw validationError(
          operation: "validate TypeScript server transaction contract observer",
          message: "Expected the live todo observer to emit the TypeScript-authored server transaction."
        )
      }
      let typeScriptObserverTodos = try TodoExample.decode(typeScriptObserverEmission.values)
      expectedFinalTodoIDs.append(typeScriptContract.entityID)
      guard typeScriptObserverTodos.map(\.id) == expectedFinalTodoIDs else {
        throw validationError(
          operation: "validate TypeScript server transaction contract observer",
          message: "Expected the observer to contain local, Swift server, and TypeScript-authored todos."
        )
      }
      evidence.append(
        try await evidenceRow(
          event: "typescript-contract-apply",
          runtime: runtime,
          cacheURL: cacheURL,
          timestamp: timestamp,
          application: typeScriptApplication,
          observerTodos: typeScriptObserverTodos
        )
      )
      finalApplication = typeScriptApplication
    }

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
    guard relaunchedTodos.map(\.id) == expectedFinalTodoIDs,
      relaunchedSyncState.processedTransactionID == finalApplication.syncState.processedTransactionID,
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
        application: finalApplication
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

  private static func instantOperations(
    from contract: TypeScriptServerTransactionContract
  ) throws -> [InstantTripleOperation] {
    guard !contract.operations.isEmpty else {
      throw validationError(
        operation: "decode TypeScript server transaction contract",
        message: "TypeScript server transaction contracts must include at least one operation."
      )
    }
    return try contract.operations.map { operation -> InstantTripleOperation in
      switch operation.type {
      case "requireEntityMissing":
        return .requireEntityMissing(
          entityID: operation.entityID,
          namespace: operation.namespace
        )

      case "insert":
        guard let attributeID = operation.attributeID, !attributeID.isEmpty else {
          throw validationError(
            operation: "decode TypeScript server transaction contract",
            message: "Insert operations must include an attribute id."
          )
        }
        guard let value = operation.value else {
          throw validationError(
            operation: "decode TypeScript server transaction contract",
            message: "Insert operations must include a value payload."
          )
        }
        guard let txTimeMs = operation.txTimeMs else {
          throw validationError(
            operation: "decode TypeScript server transaction contract",
            message: "Insert operations must include a txTimeMs value."
          )
        }
        return .insert(
          InstantTriple(
            entityID: operation.entityID,
            attributeID: attributeID,
            value: try instantValue(from: value),
            txID: contract.transactionID,
            txTime: InstantTimestamp(milliseconds: txTimeMs)
          )
        )

      default:
        throw validationError(
          operation: "decode TypeScript server transaction contract",
          message: "Unsupported TypeScript server transaction operation: \(operation.type)."
        )
      }
    }
  }

  private static func instantValue(
    from value: TypeScriptServerTransactionOperation.Value
  ) throws -> InstantValue {
    switch value.type {
    case "string":
      guard let string = value.string else {
        throw validationError(
          operation: "decode TypeScript server transaction contract",
          message: "String values must include a string payload."
        )
      }
      return .string(string)

    case "bool":
      guard let bool = value.bool else {
        throw validationError(
          operation: "decode TypeScript server transaction contract",
          message: "Bool values must include a bool payload."
        )
      }
      return .bool(bool)

    case "date":
      guard let dateMs = value.dateMs else {
        throw validationError(
          operation: "decode TypeScript server transaction contract",
          message: "Date values must include a dateMs payload."
        )
      }
      return .date(Date(timeIntervalSince1970: Double(dateMs) / 1000))

    default:
      throw validationError(
        operation: "decode TypeScript server transaction contract",
        message: "Unsupported TypeScript server transaction value: \(value.type)."
      )
    }
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
