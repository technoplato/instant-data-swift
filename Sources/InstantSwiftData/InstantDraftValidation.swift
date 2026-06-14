import Foundation

public struct DraftValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var draftTodoAttributeIDs: [String]
  public var draftTodoIDs: [String]
  public var draftTodoTitles: [String]
  public var draftTodoCompletionStates: [Bool]
  public var draftTodoNotes: [String?]
  public var pendingMutationIDs: [String]
  public var createdID: String?
  public var editedID: String?

  public init(
    cachePath: String,
    draftTodoAttributeIDs: [String],
    draftTodoIDs: [String],
    draftTodoTitles: [String],
    draftTodoCompletionStates: [Bool],
    draftTodoNotes: [String?],
    pendingMutationIDs: [String],
    createdID: String? = nil,
    editedID: String? = nil
  ) {
    self.cachePath = cachePath
    self.draftTodoAttributeIDs = draftTodoAttributeIDs
    self.draftTodoIDs = draftTodoIDs
    self.draftTodoTitles = draftTodoTitles
    self.draftTodoCompletionStates = draftTodoCompletionStates
    self.draftTodoNotes = draftTodoNotes
    self.pendingMutationIDs = pendingMutationIDs
    self.createdID = createdID
    self.editedID = editedID
  }
}

public struct DraftValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var evidence: [ValidationEvidenceRow<DraftValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    evidence: [ValidationEvidenceRow<DraftValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.evidence = evidence
  }
}

public enum InstantSwiftDataDraftValidation {
  public static func run(
    appID: String = "draft-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> DraftValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataDraftValidation-\(makeID())", isDirectory: true)
        .appendingPathComponent("state.sqlite")
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: DraftValidationTodo.instantAttributes,
        now: timestamp,
        makeID: makeID
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    var evidence: [ValidationEvidenceRow<DraftValidationDetails>] = []

    let createTimestamp = timestamp()
    let createDate = date(from: createTimestamp)
    let draft = DraftValidationTodo.Draft(
      title: "Create from generated draft",
      isCompleted: false,
      createdAt: createDate
    )
    let createdID = try await client.save(
      draft,
      localIDName: "validation.typed-drafts.todo",
      transactionID: "validation.typed-drafts.create",
      createdAt: createTimestamp
    )
    evidence.append(
      try await evidenceRow(
        event: "create",
        runtime: runtime,
        cacheURL: cacheURL,
        createdID: createdID.rawValue,
        timestamp: timestamp
      )
    )

    guard
      let createdTodo = try await client.query(
        DraftValidationTodo.query.order(DraftValidationTodo.createdAt)
      ).first
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate typed draft create",
        namespace: DraftValidationTodo.instantNamespace,
        localID: createdID.rawValue,
        message: "Expected a nil-id generated draft save to create one local entity.",
        recovery: "Inspect generated Draft assignments and InstantSwiftDataClient.save(_:) create semantics."
      )
    }
    var editDraft = DraftValidationTodo.Draft(createdTodo)
    editDraft.title = "Edit from generated draft"
    editDraft.isCompleted = true
    editDraft.notes = "Edited through Draft(existing)"
    let editTimestamp = timestamp()
    let editedID = try await client.save(
      editDraft,
      transactionID: "validation.typed-drafts.edit",
      createdAt: editTimestamp
    )
    guard editedID == createdID else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate typed draft edit",
        namespace: DraftValidationTodo.instantNamespace,
        localID: createdID.rawValue,
        message: "Expected editing a generated draft to save back to the created entity id.",
        recovery: "Inspect Draft(existing) id copying and InstantSwiftDataClient.save(_:) update semantics."
      )
    }
    evidence.append(
      try await evidenceRow(
        event: "edit",
        runtime: runtime,
        cacheURL: cacheURL,
        editedID: editedID.rawValue,
        timestamp: timestamp
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: DraftValidationTodo.instantAttributes,
        now: timestamp,
        makeID: makeID
      )
    )
    evidence.append(
      try await evidenceRow(
        event: "relaunch",
        runtime: relaunchedRuntime,
        cacheURL: cacheURL,
        createdID: createdID.rawValue,
        editedID: editedID.rawValue,
        timestamp: timestamp
      )
    )

    return DraftValidationResult(appID: appID, cacheURL: cacheURL, evidence: evidence)
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    createdID: String? = nil,
    editedID: String? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<DraftValidationDetails> {
    let client = InstantSwiftDataClient(runtime: runtime)
    let todos = try await client.query(DraftValidationTodo.query.order(DraftValidationTodo.createdAt))
    let pending = await client.pendingMutations()
    return ValidationEvidenceRow(
      caseID: "validation.typed.drafts",
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      entityID: editedID ?? createdID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: DraftValidationDetails(
        cachePath: cacheURL.path,
        draftTodoAttributeIDs: DraftValidationTodo.instantAttributes.map(\.id),
        draftTodoIDs: todos.map(\.id.rawValue),
        draftTodoTitles: todos.map(\.title),
        draftTodoCompletionStates: todos.map(\.isCompleted),
        draftTodoNotes: todos.map(\.notes),
        pendingMutationIDs: pending.map(\.id),
        createdID: createdID,
        editedID: editedID
      )
    )
  }

  private static func date(from timestamp: InstantTimestamp) -> Date {
    Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
  }
}

@InstantEntity
private struct DraftValidationTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<DraftValidationTodo>
  var title: String
  var isCompleted: Bool = false
  var createdAt: Date
  var notes: String?

  init(
    id: InstantID<DraftValidationTodo>,
    title: String,
    isCompleted: Bool,
    createdAt: Date,
    notes: String? = nil
  ) {
    self.id = id
    self.title = title
    self.isCompleted = isCompleted
    self.createdAt = createdAt
    self.notes = notes
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first else {
      throw Self.decodeError(snapshot: snapshot, path: "title", expectedType: "string")
    }
    guard case let .bool(isCompleted) = snapshot.values["isCompleted"]?.first else {
      throw Self.decodeError(snapshot: snapshot, path: "isCompleted", expectedType: "boolean")
    }
    guard case let .date(createdAt) = snapshot.values["createdAt"]?.first else {
      throw Self.decodeError(snapshot: snapshot, path: "createdAt", expectedType: "date")
    }
    let notes: String?
    switch snapshot.values["notes"]?.first {
    case let .some(.string(value)):
      notes = value
    case .some(.null), .none:
      notes = nil
    default:
      throw Self.decodeError(snapshot: snapshot, path: "notes", expectedType: "string or null")
    }

    self.id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.isCompleted = isCompleted
    self.createdAt = createdAt
    self.notes = notes
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    path: String,
    expectedType: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode typed draft validation todo",
      namespace: Self.instantNamespace,
      path: path,
      localID: snapshot.id,
      message: "Expected \(expectedType) for draft validation field '\(path)'.",
      recovery: "Inspect generated draft validation schema attributes and local triples."
    )
  }
}
