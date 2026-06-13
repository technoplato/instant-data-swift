import Foundation

public enum InstantSwiftDataValidationStatus: Sendable {
  case localTodos
}

public struct ValidationEvidenceRow<Details: Encodable & Sendable>: Encodable, Sendable {
  public var caseID: String
  public var side: String
  public var event: String
  public var appID: String
  public var entityID: String?
  public var timestampMs: Int64
  public var ok: Bool
  public var details: Details

  public init(
    caseID: String,
    side: String,
    event: String,
    appID: String,
    entityID: String? = nil,
    timestampMs: Int64,
    ok: Bool,
    details: Details
  ) {
    self.caseID = caseID
    self.side = side
    self.event = event
    self.appID = appID
    self.entityID = entityID
    self.timestampMs = timestampMs
    self.ok = ok
    self.details = details
  }

  private enum CodingKeys: String, CodingKey {
    case caseID = "case"
    case side
    case event
    case appID
    case entityID
    case timestampMs
    case ok
    case details
  }
}

public struct LocalTodoValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var todoIDs: [String]
  public var todoTexts: [String]
  public var pendingMutationIDs: [String]
  public var queryCacheCount: Int

  public init(
    cachePath: String,
    todoIDs: [String],
    todoTexts: [String],
    pendingMutationIDs: [String],
    queryCacheCount: Int
  ) {
    self.cachePath = cachePath
    self.todoIDs = todoIDs
    self.todoTexts = todoTexts
    self.pendingMutationIDs = pendingMutationIDs
    self.queryCacheCount = queryCacheCount
  }
}

public struct LocalTodoValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var evidence: [ValidationEvidenceRow<LocalTodoValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    evidence: [ValidationEvidenceRow<LocalTodoValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.evidence = evidence
  }
}

public enum InstantSwiftDataLocalTodoValidation {
  public static func run(
    appID: String = "local-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> LocalTodoValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataValidation-\(makeID())", isDirectory: true)
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

    var evidence: [ValidationEvidenceRow<LocalTodoValidationDetails>] = []

    let seedTransactionID = makeID()
    let seededAt = timestamp()
    let seedRecords = try await TodoExample.seedRecords.asyncMap { seed in
      (try await runtime.localID(named: seed.localIDName), seed)
    }
    try await runtime.transact(
      InstantStoreTransaction(
        id: seedTransactionID,
        operations: TodoExample.seedOperations(
          records: seedRecords,
          baseCreatedAt: seededAt,
          transactionID: seedTransactionID
        )
      ),
      createdAt: seededAt,
      source: "validation.local.todos.seed"
    )
    evidence.append(
      try await evidenceRow(event: "seed", runtime: runtime, cacheURL: cacheURL, timestamp: timestamp)
    )

    let terminalID = try await runtime.localID(named: "examples.todos.seed.terminal")
    let updateTransactionID = makeID()
    let updatedAt = timestamp()
    try await runtime.transact(
      InstantStoreTransaction(
        id: updateTransactionID,
        operations: TodoExample.updateTextOperations(
          id: terminalID,
          text: "Run the validated terminal workflow",
          updatedAt: updatedAt,
          transactionID: updateTransactionID
        )
      ),
      createdAt: updatedAt,
      source: "validation.local.todos.update"
    )
    evidence.append(
      try await evidenceRow(event: "update", runtime: runtime, cacheURL: cacheURL, timestamp: timestamp)
    )

    let cachedTodos = try TodoExample.decode(
      (try await runtime.cachedQuery(TodoExample.query))?.emission.values ?? []
    )
    guard cachedTodos.map(\.text).contains("Run the validated terminal workflow") else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate local todos",
        message: "Expected the query cache to contain the updated seed todo.",
        recovery: "Inspect local query cache persistence and materialization."
      )
    }
    evidence.append(
      try await evidenceRow(event: "cache", runtime: runtime, cacheURL: cacheURL, timestamp: timestamp)
    )

    let currentTodos = try await TodoExample.decode(runtime.query(TodoExample.query))
    let resetTransactionID = makeID()
    let resetAt = timestamp()
    try await runtime.transact(
      InstantStoreTransaction(
        id: resetTransactionID,
        operations: TodoExample.resetOperations(ids: currentTodos.map(\.id))
      ),
      createdAt: resetAt,
      source: "validation.local.todos.reset"
    )
    evidence.append(
      try await evidenceRow(event: "reset", runtime: runtime, cacheURL: cacheURL, timestamp: timestamp)
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
    guard relaunchedTodos.isEmpty else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate local todos relaunch",
        message: "Expected reset todos to remain empty after relaunch.",
        recovery: "Inspect SQLite triple persistence and reset operations."
      )
    }
    evidence.append(
      try await evidenceRow(event: "relaunch", runtime: relaunchedRuntime, cacheURL: cacheURL, timestamp: timestamp)
    )

    return LocalTodoValidationResult(appID: appID, cacheURL: cacheURL, evidence: evidence)
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<LocalTodoValidationDetails> {
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    let pending = await runtime.pendingMutations()
    let cachedQueries = try await runtime.cachedQueries()
    return ValidationEvidenceRow(
      caseID: "validation.local.todos",
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: LocalTodoValidationDetails(
        cachePath: cacheURL.path,
        todoIDs: todos.map(\.id),
        todoTexts: todos.map(\.text),
        pendingMutationIDs: pending.map(\.id),
        queryCacheCount: cachedQueries.count
      )
    )
  }
}

private extension Sequence {
  func asyncMap<Transformed>(
    _ transform: (Element) async throws -> Transformed
  ) async throws -> [Transformed] {
    var transformed: [Transformed] = []
    for element in self {
      transformed.append(try await transform(element))
    }
    return transformed
  }
}
