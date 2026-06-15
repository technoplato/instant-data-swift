import Foundation

public struct DraftValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var draftTodoAttributeIDs: [String]
  public var draftTodoIDs: [String]
  public var draftTodoTitles: [String]
  public var draftTodoCompletionStates: [Bool]
  public var draftTodoNotes: [String?]
  public var draftAuthorIDs: [String]
  public var draftAuthorNames: [String]
  public var draftPostAttributeIDs: [String]
  public var draftPostIDs: [String]
  public var draftPostTitles: [String]
  public var draftPostAuthorIDs: [String]
  public var draftPostAuthorAttributeValueType: String?
  public var draftPostAuthorLinkNamespace: String?
  public var draftPostAuthorForwardIdentity: String?
  public var draftPostAuthorReverseIdentity: String?
  public var draftMutationSummaries: [DraftValidationMutationSummary]
  public var pendingMutationIDs: [String]
  public var newDraftIDWasNil: Bool
  public var newDraftAssignmentAttributeIDs: [String]
  public var newDraftIncludedPrimaryKeyAssignment: Bool
  public var createdID: String?
  public var editedID: String?
  public var relationAuthorID: String?
  public var relationPostID: String?

  public init(
    cachePath: String,
    draftTodoAttributeIDs: [String],
    draftTodoIDs: [String],
    draftTodoTitles: [String],
    draftTodoCompletionStates: [Bool],
    draftTodoNotes: [String?],
    draftAuthorIDs: [String] = [],
    draftAuthorNames: [String] = [],
    draftPostAttributeIDs: [String] = [],
    draftPostIDs: [String] = [],
    draftPostTitles: [String] = [],
    draftPostAuthorIDs: [String] = [],
    draftPostAuthorAttributeValueType: String? = nil,
    draftPostAuthorLinkNamespace: String? = nil,
    draftPostAuthorForwardIdentity: String? = nil,
    draftPostAuthorReverseIdentity: String? = nil,
    draftMutationSummaries: [DraftValidationMutationSummary] = [],
    pendingMutationIDs: [String],
    newDraftIDWasNil: Bool = false,
    newDraftAssignmentAttributeIDs: [String] = [],
    newDraftIncludedPrimaryKeyAssignment: Bool = false,
    createdID: String? = nil,
    editedID: String? = nil,
    relationAuthorID: String? = nil,
    relationPostID: String? = nil
  ) {
    self.cachePath = cachePath
    self.draftTodoAttributeIDs = draftTodoAttributeIDs
    self.draftTodoIDs = draftTodoIDs
    self.draftTodoTitles = draftTodoTitles
    self.draftTodoCompletionStates = draftTodoCompletionStates
    self.draftTodoNotes = draftTodoNotes
    self.draftAuthorIDs = draftAuthorIDs
    self.draftAuthorNames = draftAuthorNames
    self.draftPostAttributeIDs = draftPostAttributeIDs
    self.draftPostIDs = draftPostIDs
    self.draftPostTitles = draftPostTitles
    self.draftPostAuthorIDs = draftPostAuthorIDs
    self.draftPostAuthorAttributeValueType = draftPostAuthorAttributeValueType
    self.draftPostAuthorLinkNamespace = draftPostAuthorLinkNamespace
    self.draftPostAuthorForwardIdentity = draftPostAuthorForwardIdentity
    self.draftPostAuthorReverseIdentity = draftPostAuthorReverseIdentity
    self.draftMutationSummaries = draftMutationSummaries
    self.pendingMutationIDs = pendingMutationIDs
    self.newDraftIDWasNil = newDraftIDWasNil
    self.newDraftAssignmentAttributeIDs = newDraftAssignmentAttributeIDs
    self.newDraftIncludedPrimaryKeyAssignment = newDraftIncludedPrimaryKeyAssignment
    self.createdID = createdID
    self.editedID = editedID
    self.relationAuthorID = relationAuthorID
    self.relationPostID = relationPostID
  }

  private enum CodingKeys: String, CodingKey {
    case cachePath
    case draftTodoAttributeIDs
    case draftTodoIDs
    case draftTodoTitles
    case draftTodoCompletionStates
    case draftTodoNotes
    case draftAuthorIDs
    case draftAuthorNames
    case draftPostAttributeIDs
    case draftPostIDs
    case draftPostTitles
    case draftPostAuthorIDs
    case draftPostAuthorAttributeValueType
    case draftPostAuthorLinkNamespace
    case draftPostAuthorForwardIdentity
    case draftPostAuthorReverseIdentity
    case draftMutationSummaries
    case pendingMutationIDs
    case newDraftIDWasNil
    case newDraftAssignmentAttributeIDs
    case newDraftIncludedPrimaryKeyAssignment
    case createdID
    case editedID
    case relationAuthorID
    case relationPostID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      cachePath: try container.decode(String.self, forKey: .cachePath),
      draftTodoAttributeIDs: try container.decodeIfPresent(
        [String].self, forKey: .draftTodoAttributeIDs
      ) ?? [],
      draftTodoIDs: try container.decodeIfPresent([String].self, forKey: .draftTodoIDs) ?? [],
      draftTodoTitles: try container.decodeIfPresent([String].self, forKey: .draftTodoTitles) ?? [],
      draftTodoCompletionStates: try container.decodeIfPresent(
        [Bool].self, forKey: .draftTodoCompletionStates
      ) ?? [],
      draftTodoNotes: try container.decodeIfPresent([String?].self, forKey: .draftTodoNotes) ?? [],
      draftAuthorIDs: try container.decodeIfPresent([String].self, forKey: .draftAuthorIDs) ?? [],
      draftAuthorNames: try container.decodeIfPresent([String].self, forKey: .draftAuthorNames)
        ?? [],
      draftPostAttributeIDs: try container.decodeIfPresent(
        [String].self, forKey: .draftPostAttributeIDs
      ) ?? [],
      draftPostIDs: try container.decodeIfPresent([String].self, forKey: .draftPostIDs) ?? [],
      draftPostTitles: try container.decodeIfPresent([String].self, forKey: .draftPostTitles) ?? [],
      draftPostAuthorIDs: try container.decodeIfPresent(
        [String].self, forKey: .draftPostAuthorIDs
      ) ?? [],
      draftPostAuthorAttributeValueType: try container.decodeIfPresent(
        String.self, forKey: .draftPostAuthorAttributeValueType
      ),
      draftPostAuthorLinkNamespace: try container.decodeIfPresent(
        String.self, forKey: .draftPostAuthorLinkNamespace
      ),
      draftPostAuthorForwardIdentity: try container.decodeIfPresent(
        String.self, forKey: .draftPostAuthorForwardIdentity
      ),
      draftPostAuthorReverseIdentity: try container.decodeIfPresent(
        String.self, forKey: .draftPostAuthorReverseIdentity
      ),
      draftMutationSummaries: try container.decodeIfPresent(
        [DraftValidationMutationSummary].self, forKey: .draftMutationSummaries
      ) ?? [],
      pendingMutationIDs: try container.decodeIfPresent([String].self, forKey: .pendingMutationIDs)
        ?? [],
      newDraftIDWasNil: try container.decodeIfPresent(Bool.self, forKey: .newDraftIDWasNil)
        ?? false,
      newDraftAssignmentAttributeIDs: try container.decodeIfPresent(
        [String].self, forKey: .newDraftAssignmentAttributeIDs
      ) ?? [],
      newDraftIncludedPrimaryKeyAssignment: try container.decodeIfPresent(
        Bool.self, forKey: .newDraftIncludedPrimaryKeyAssignment
      ) ?? false,
      createdID: try container.decodeIfPresent(String.self, forKey: .createdID),
      editedID: try container.decodeIfPresent(String.self, forKey: .editedID),
      relationAuthorID: try container.decodeIfPresent(String.self, forKey: .relationAuthorID),
      relationPostID: try container.decodeIfPresent(String.self, forKey: .relationPostID)
    )
  }
}

public struct DraftValidationMutationSummary: Codable, Equatable, Sendable {
  public var mutationID: String
  public var transactionID: String
  public var status: String
  public var operationKinds: [String]
  public var preconditionKinds: [String]
  public var preconditionNamespaces: [String]
  public var txStepKinds: [String]
  public var txStepEntityIDs: [String]
  public var txStepAttributeIDs: [String]
  public var txStepValueTypes: [String]
  public var txStepValueSummaries: [String]
  public var txStepOptionModes: [String]
  public var operationValueTypes: [String]
  public var operationValueSummaries: [String]
  public var primaryKeyStepCount: Int
  public var draftAssignmentAttributeIDs: [String]
  public var refAttributeIDs: [String]

  public init(
    mutationID: String,
    transactionID: String,
    status: String,
    operationKinds: [String],
    preconditionKinds: [String],
    preconditionNamespaces: [String],
    txStepKinds: [String],
    txStepEntityIDs: [String],
    txStepAttributeIDs: [String],
    txStepValueTypes: [String],
    txStepValueSummaries: [String],
    txStepOptionModes: [String],
    operationValueTypes: [String],
    operationValueSummaries: [String],
    primaryKeyStepCount: Int,
    draftAssignmentAttributeIDs: [String],
    refAttributeIDs: [String]
  ) {
    self.mutationID = mutationID
    self.transactionID = transactionID
    self.status = status
    self.operationKinds = operationKinds
    self.preconditionKinds = preconditionKinds
    self.preconditionNamespaces = preconditionNamespaces
    self.txStepKinds = txStepKinds
    self.txStepEntityIDs = txStepEntityIDs
    self.txStepAttributeIDs = txStepAttributeIDs
    self.txStepValueTypes = txStepValueTypes
    self.txStepValueSummaries = txStepValueSummaries
    self.txStepOptionModes = txStepOptionModes
    self.operationValueTypes = operationValueTypes
    self.operationValueSummaries = operationValueSummaries
    self.primaryKeyStepCount = primaryKeyStepCount
    self.draftAssignmentAttributeIDs = draftAssignmentAttributeIDs
    self.refAttributeIDs = refAttributeIDs
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
        initialAttributes: draftValidationAttributes,
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
    let newDraftIDWasNil = draft.id == nil
    let newDraftAssignmentAttributeIDs = draft.instantAssignments.map(\.attributeID)
    let newDraftIncludedPrimaryKeyAssignment = newDraftAssignmentAttributeIDs.contains(
      DraftValidationTodo.instantNamespace + "/id"
    )
    guard newDraftIDWasNil else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate typed draft create",
        namespace: DraftValidationTodo.instantNamespace,
        message: "Expected a newly initialized generated draft to omit its managed Instant id.",
        recovery: "Inspect generated Draft memberwise defaults for primary-keyed @InstantEntity models."
      )
    }
    guard !newDraftIncludedPrimaryKeyAssignment else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate typed draft create",
        namespace: DraftValidationTodo.instantNamespace,
        localID: DraftValidationTodo.instantNamespace + "/id",
        message: "Expected generated draft assignments to exclude the managed Instant id.",
        recovery: "Inspect generated Draft assignments and managed primary-key handling."
      )
    }
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
        newDraftIDWasNil: newDraftIDWasNil,
        newDraftAssignmentAttributeIDs: newDraftAssignmentAttributeIDs,
        newDraftIncludedPrimaryKeyAssignment: newDraftIncludedPrimaryKeyAssignment,
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
        newDraftIDWasNil: newDraftIDWasNil,
        newDraftAssignmentAttributeIDs: newDraftAssignmentAttributeIDs,
        newDraftIncludedPrimaryKeyAssignment: newDraftIncludedPrimaryKeyAssignment,
        editedID: editedID.rawValue,
        timestamp: timestamp
      )
    )

    let relationTimestamp = timestamp()
    let expectedForwardIdentity = DraftValidationPost.author.attributeID
    let expectedReverseIdentity = DraftValidationAuthor.instantNamespace + "/posts"
    guard
      let authorAttribute = draftPostAuthorAttribute,
      authorAttribute.valueType == .ref,
      authorAttribute.linkNamespace == DraftValidationAuthor.instantNamespace,
      authorAttribute.forwardIdentity == expectedForwardIdentity,
      authorAttribute.reverseIdentity == expectedReverseIdentity
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate typed relation draft metadata",
        namespace: DraftValidationPost.instantNamespace,
        localID: expectedForwardIdentity,
        message: "Expected @InstantRelation to generate ref metadata for the draft author field.",
        recovery: "Inspect generated InstantAttribute metadata for @InstantRelation reverse links."
      )
    }
    let authorID = try await client.save(
      DraftValidationAuthor.Draft(name: "Draft relation author"),
      localIDName: "validation.typed-drafts.author",
      transactionID: "validation.typed-drafts.author",
      createdAt: relationTimestamp
    )
    let postID = try await client.save(
      DraftValidationPost.Draft(
        title: "Post from relation draft",
        author: authorID
      ),
      localIDName: "validation.typed-drafts.post",
      transactionID: "validation.typed-drafts.post",
      createdAt: relationTimestamp
    )
    guard
      let savedPost = try await client.query(
        DraftValidationPost.query.order(DraftValidationPost.title)
      ).first,
      savedPost.author == authorID
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate typed relation draft",
        namespace: DraftValidationPost.instantNamespace,
        localID: postID.rawValue,
        message: "Expected a generated draft with an Instant relation field to save a ref value.",
        recovery: "Inspect generated Draft assignments for @InstantRelation ref attributes."
      )
    }
    try await validateMutationShapes(
      runtime: runtime,
      createdID: createdID.rawValue,
      createdAt: createTimestamp,
      authorID: authorID.rawValue,
      postID: postID.rawValue
    )
    evidence.append(
      try await evidenceRow(
        event: "relation",
        runtime: runtime,
        cacheURL: cacheURL,
        newDraftIDWasNil: newDraftIDWasNil,
        newDraftAssignmentAttributeIDs: newDraftAssignmentAttributeIDs,
        newDraftIncludedPrimaryKeyAssignment: newDraftIncludedPrimaryKeyAssignment,
        relationAuthorID: authorID.rawValue,
        relationPostID: postID.rawValue,
        timestamp: timestamp
      )
    )

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: draftValidationAttributes,
        now: timestamp,
        makeID: makeID
      )
    )
    evidence.append(
      try await evidenceRow(
        event: "relaunch",
        runtime: relaunchedRuntime,
        cacheURL: cacheURL,
        newDraftIDWasNil: newDraftIDWasNil,
        newDraftAssignmentAttributeIDs: newDraftAssignmentAttributeIDs,
        newDraftIncludedPrimaryKeyAssignment: newDraftIncludedPrimaryKeyAssignment,
        createdID: createdID.rawValue,
        editedID: editedID.rawValue,
        relationAuthorID: authorID.rawValue,
        relationPostID: postID.rawValue,
        timestamp: timestamp
      )
    )

    return DraftValidationResult(appID: appID, cacheURL: cacheURL, evidence: evidence)
  }

  private static func evidenceRow(
    event: String,
    runtime: InstantRuntime,
    cacheURL: URL,
    newDraftIDWasNil: Bool = false,
    newDraftAssignmentAttributeIDs: [String] = [],
    newDraftIncludedPrimaryKeyAssignment: Bool = false,
    createdID: String? = nil,
    editedID: String? = nil,
    relationAuthorID: String? = nil,
    relationPostID: String? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<DraftValidationDetails> {
    let client = InstantSwiftDataClient(runtime: runtime)
    let todos = try await client.query(DraftValidationTodo.query.order(DraftValidationTodo.createdAt))
    let authors = try await client.query(DraftValidationAuthor.query.order(DraftValidationAuthor.name))
    let posts = try await client.query(DraftValidationPost.query.order(DraftValidationPost.title))
    let pending = await client.pendingMutations()
    let summaries = mutationSummaries(pending)
    let postAuthorAttribute = draftPostAuthorAttribute
    return ValidationEvidenceRow(
      caseID: "validation.typed.drafts",
      side: "swift",
      event: event,
      appID: runtime.configuration.appID,
      entityID: editedID ?? createdID ?? relationPostID ?? relationAuthorID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: DraftValidationDetails(
        cachePath: cacheURL.path,
        draftTodoAttributeIDs: DraftValidationTodo.instantAttributes.map(\.id),
        draftTodoIDs: todos.map(\.id.rawValue),
        draftTodoTitles: todos.map(\.title),
        draftTodoCompletionStates: todos.map(\.isCompleted),
        draftTodoNotes: todos.map(\.notes),
        draftAuthorIDs: authors.map(\.id.rawValue),
        draftAuthorNames: authors.map(\.name),
        draftPostAttributeIDs: DraftValidationPost.instantAttributes.map(\.id),
        draftPostIDs: posts.map(\.id.rawValue),
        draftPostTitles: posts.map(\.title),
        draftPostAuthorIDs: posts.map(\.author.rawValue),
        draftPostAuthorAttributeValueType: postAuthorAttribute?.valueType.rawValue,
        draftPostAuthorLinkNamespace: postAuthorAttribute?.linkNamespace,
        draftPostAuthorForwardIdentity: postAuthorAttribute?.forwardIdentity,
        draftPostAuthorReverseIdentity: postAuthorAttribute?.reverseIdentity,
        draftMutationSummaries: summaries,
        pendingMutationIDs: pending.map(\.id),
        newDraftIDWasNil: newDraftIDWasNil,
        newDraftAssignmentAttributeIDs: newDraftAssignmentAttributeIDs,
        newDraftIncludedPrimaryKeyAssignment: newDraftIncludedPrimaryKeyAssignment,
        createdID: createdID,
        editedID: editedID,
        relationAuthorID: relationAuthorID,
        relationPostID: relationPostID
      )
    )
  }

  private static func validateMutationShapes(
    runtime: InstantRuntime,
    createdID: String,
    createdAt: InstantTimestamp,
    authorID: String,
    postID: String
  ) async throws {
    let summaries = mutationSummaries(await runtime.pendingMutations())
    try requireMutationShape(
      summaries,
      mutationID: "validation.typed-drafts.create",
      transactionID: "validation.typed-drafts.create",
      entityID: createdID,
      operationKinds: [
        "requireEntityMissing",
        "insert",
        "insert",
        "insert",
        "insert",
        "insert",
      ],
      preconditionKinds: ["entity-missing"],
      preconditionNamespaces: [DraftValidationTodo.instantNamespace],
      txStepAttributeIDs: [
        "draftValidationTodos/id",
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ],
      txStepKinds: ["add-triple", "add-triple", "add-triple", "add-triple", "add-triple"],
      txStepValueTypes: ["string", "string", "boolean", "string", "null"],
      txStepValueSummaries: [
        "string:\(createdID)",
        "string:Create from generated draft",
        "boolean:false",
        transportDateSummary(from: createdAt),
        "null",
      ],
      txStepOptionModes: ["create", "create", "create", "create", "create"],
      operationValueTypes: ["string", "string", "boolean", "date", "null"],
      operationValueSummaries: [
        "string:\(createdID)",
        "string:Create from generated draft",
        "boolean:false",
        "date:\(createdAt.milliseconds)",
        "null",
      ],
      primaryKeyStepCount: 1,
      draftAssignmentAttributeIDs: [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ],
      refAttributeIDs: []
    )
    try requireMutationShape(
      summaries,
      mutationID: "validation.typed-drafts.edit",
      transactionID: "validation.typed-drafts.edit",
      entityID: createdID,
      operationKinds: [
        "insert",
        "insert",
        "insert",
        "insert",
        "insert",
      ],
      preconditionKinds: [],
      preconditionNamespaces: [],
      txStepAttributeIDs: [
        "draftValidationTodos/id",
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ],
      txStepKinds: ["add-triple", "add-triple", "add-triple", "add-triple", "add-triple"],
      txStepValueTypes: ["string", "string", "boolean", "string", "string"],
      txStepValueSummaries: [
        "string:\(createdID)",
        "string:Edit from generated draft",
        "boolean:true",
        transportDateSummary(from: createdAt),
        "string:Edited through Draft(existing)",
      ],
      txStepOptionModes: ["none", "none", "none", "none", "none"],
      operationValueTypes: ["string", "string", "boolean", "date", "string"],
      operationValueSummaries: [
        "string:\(createdID)",
        "string:Edit from generated draft",
        "boolean:true",
        "date:\(createdAt.milliseconds)",
        "string:Edited through Draft(existing)",
      ],
      primaryKeyStepCount: 1,
      draftAssignmentAttributeIDs: [
        "draftValidationTodos/title",
        "draftValidationTodos/isCompleted",
        "draftValidationTodos/createdAt",
        "draftValidationTodos/notes",
      ],
      refAttributeIDs: []
    )
    try requireMutationShape(
      summaries,
      mutationID: "validation.typed-drafts.author",
      transactionID: "validation.typed-drafts.author",
      entityID: authorID,
      operationKinds: ["requireEntityMissing", "insert", "insert"],
      preconditionKinds: ["entity-missing"],
      preconditionNamespaces: [DraftValidationAuthor.instantNamespace],
      txStepAttributeIDs: [
        "draftValidationAuthors/id",
        "draftValidationAuthors/name",
      ],
      txStepKinds: ["add-triple", "add-triple"],
      txStepValueTypes: ["string", "string"],
      txStepValueSummaries: [
        "string:\(authorID)",
        "string:Draft relation author",
      ],
      txStepOptionModes: ["create", "create"],
      operationValueTypes: ["string", "string"],
      operationValueSummaries: [
        "string:\(authorID)",
        "string:Draft relation author",
      ],
      primaryKeyStepCount: 1,
      draftAssignmentAttributeIDs: ["draftValidationAuthors/name"],
      refAttributeIDs: []
    )
    try requireMutationShape(
      summaries,
      mutationID: "validation.typed-drafts.post",
      transactionID: "validation.typed-drafts.post",
      entityID: postID,
      operationKinds: ["requireEntityMissing", "insert", "insert", "insert"],
      preconditionKinds: ["entity-missing"],
      preconditionNamespaces: [DraftValidationPost.instantNamespace],
      txStepAttributeIDs: [
        "draftValidationPosts/id",
        "draftValidationPosts/title",
        "draftValidationPosts/author",
      ],
      txStepKinds: ["add-triple", "add-triple", "add-triple"],
      txStepValueTypes: ["string", "string", "string"],
      txStepValueSummaries: [
        "string:\(postID)",
        "string:Post from relation draft",
        "string:\(authorID)",
      ],
      txStepOptionModes: ["create", "create", "create"],
      operationValueTypes: ["string", "string", "ref"],
      operationValueSummaries: [
        "string:\(postID)",
        "string:Post from relation draft",
        "ref:\(authorID)",
      ],
      primaryKeyStepCount: 1,
      draftAssignmentAttributeIDs: [
        "draftValidationPosts/title",
        "draftValidationPosts/author",
      ],
      refAttributeIDs: ["draftValidationPosts/author"]
    )
  }

  private static func requireMutationShape(
    _ summaries: [DraftValidationMutationSummary],
    mutationID: String,
    transactionID: String,
    entityID: String,
    operationKinds: [String],
    preconditionKinds: [String],
    preconditionNamespaces: [String],
    txStepAttributeIDs: [String],
    txStepKinds: [String],
    txStepValueTypes: [String],
    txStepValueSummaries: [String],
    txStepOptionModes: [String],
    operationValueTypes: [String],
    operationValueSummaries: [String],
    primaryKeyStepCount: Int,
    draftAssignmentAttributeIDs: [String],
    refAttributeIDs: [String]
  ) throws {
    guard let summary = summaries.first(where: { $0.mutationID == mutationID }) else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected pending mutation '\(mutationID)' to be recorded.",
        recovery: "Inspect generated draft save transaction ids and outbox persistence."
      )
    }
    guard summary.transactionID == transactionID else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft transaction id '\(transactionID)', got '\(summary.transactionID)'.",
        recovery: "Inspect generated draft save transaction ids."
      )
    }
    guard summary.status == InstantMutationStatus.pending.rawValue else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft mutation status 'pending', got '\(summary.status)'.",
        recovery: "Inspect draft validation outbox status transitions."
      )
    }
    guard summary.operationKinds == operationKinds else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft mutation operations \(operationKinds), got \(summary.operationKinds).",
        recovery: "Inspect InstantSwiftDataClient.save(_:) create/update lowering."
      )
    }
    guard summary.preconditionKinds == preconditionKinds else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft preconditions \(preconditionKinds), got \(summary.preconditionKinds).",
        recovery: "Inspect strict nil-id draft create preconditions and edit upsert semantics."
      )
    }
    guard summary.preconditionNamespaces == preconditionNamespaces else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft precondition namespaces \(preconditionNamespaces), got \(summary.preconditionNamespaces).",
        recovery: "Inspect generated draft entity namespaces."
      )
    }
    guard summary.txStepEntityIDs.allSatisfy({ $0 == entityID }) else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft step entities to all be '\(entityID)', got \(summary.txStepEntityIDs).",
        recovery: "Inspect generated draft save entity id selection."
      )
    }
    guard summary.txStepKinds == txStepKinds else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft transport steps \(txStepKinds), got \(summary.txStepKinds).",
        recovery: "Inspect transport lowering for generated draft mutations."
      )
    }
    guard summary.txStepAttributeIDs == txStepAttributeIDs else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft step attributes \(txStepAttributeIDs), got \(summary.txStepAttributeIDs).",
        recovery: "Inspect generated Draft assignments and primary key write lowering."
      )
    }
    guard summary.txStepValueTypes == txStepValueTypes else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft step value types \(txStepValueTypes), got \(summary.txStepValueTypes).",
        recovery: "Inspect generated Draft assignment value conversion."
      )
    }
    guard summary.txStepValueSummaries == txStepValueSummaries else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft step values \(txStepValueSummaries), got \(summary.txStepValueSummaries).",
        recovery: "Inspect generated Draft assignment payloads."
      )
    }
    guard summary.txStepOptionModes == txStepOptionModes else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft step option modes \(txStepOptionModes), got \(summary.txStepOptionModes).",
        recovery: "Inspect transport lowering for create-mode nil-id drafts and edit upserts."
      )
    }
    guard summary.operationValueTypes == operationValueTypes else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft operation value types \(operationValueTypes), got \(summary.operationValueTypes).",
        recovery: "Inspect generated Draft assignment value conversion."
      )
    }
    guard summary.operationValueSummaries == operationValueSummaries else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft operation values \(operationValueSummaries), got \(summary.operationValueSummaries).",
        recovery: "Inspect generated Draft assignment payloads."
      )
    }
    guard summary.primaryKeyStepCount == primaryKeyStepCount else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected \(primaryKeyStepCount) generated draft primary-key steps, got \(summary.primaryKeyStepCount).",
        recovery: "Inspect managed Instant id handling in generated draft saves."
      )
    }
    guard summary.draftAssignmentAttributeIDs == draftAssignmentAttributeIDs else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft assignment attributes \(draftAssignmentAttributeIDs), got \(summary.draftAssignmentAttributeIDs).",
        recovery: "Inspect generated Draft writable fields."
      )
    }
    guard summary.refAttributeIDs == refAttributeIDs else {
      throw draftMutationShapeError(
        mutationID: mutationID,
        message: "Expected generated draft ref assignment attributes \(refAttributeIDs), got \(summary.refAttributeIDs).",
        recovery: "Inspect generated Draft writable relation fields."
      )
    }
  }

  private static func draftMutationShapeError(
    mutationID: String,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "validate typed draft mutation shape",
      localID: mutationID,
      message: message,
      recovery: recovery
    )
  }

  private static func mutationSummaries(
    _ pending: [PendingMutation]
  ) -> [DraftValidationMutationSummary] {
    pending.map { mutation in
      let transportMutation = InstantTransportMutation(mutation)
      let stepAttributeIDs = transportMutation.txSteps.compactMap(\.draftValidationAttributeID)
      let primaryKeyStepCount = stepAttributeIDs.filter {
        $0.isDraftValidationPrimaryKeyID
      }.count
      let insertedTriples = mutation.transaction.operations.compactMap(\.draftValidationInsertedTriple)
      return DraftValidationMutationSummary(
        mutationID: mutation.id,
        transactionID: mutation.transaction.id,
        status: mutation.status.rawValue,
        operationKinds: mutation.transaction.operations.map(\.draftValidationKind),
        preconditionKinds: transportMutation.preconditions.map { $0.kind.rawValue },
        preconditionNamespaces: transportMutation.preconditions.map { $0.namespace ?? "none" },
        txStepKinds: transportMutation.txSteps.map(\.draftValidationKind),
        txStepEntityIDs: transportMutation.txSteps.compactMap(\.draftValidationEntityID),
        txStepAttributeIDs: stepAttributeIDs,
        txStepValueTypes: transportMutation.txSteps.compactMap(\.draftValidationValueType),
        txStepValueSummaries: transportMutation.txSteps.compactMap(\.draftValidationValueSummary),
        txStepOptionModes: transportMutation.txSteps.map(\.draftValidationOptionMode),
        operationValueTypes: insertedTriples.map { $0.value.draftValidationType },
        operationValueSummaries: insertedTriples.map { $0.value.draftValidationSummary },
        primaryKeyStepCount: primaryKeyStepCount,
        draftAssignmentAttributeIDs: stepAttributeIDs.filter {
          !$0.isDraftValidationPrimaryKeyID
        },
        refAttributeIDs: insertedTriples.compactMap { triple in
          triple.value.draftValidationType == "ref" ? triple.attributeID : nil
        }
      )
    }
  }

  private static func transportDateSummary(from timestamp: InstantTimestamp) -> String {
    InstantTransportValue(InstantValue.date(date(from: timestamp))).draftValidationSummary
  }

  private static func date(from timestamp: InstantTimestamp) -> Date {
    Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
  }

  private static var draftPostAuthorAttribute: InstantAttribute? {
    DraftValidationPost.instantAttributes.first {
      $0.id == DraftValidationPost.author.attributeID
    }
  }
}

private let draftValidationAttributes =
  DraftValidationTodo.instantAttributes
  + DraftValidationAuthor.instantAttributes
  + DraftValidationPost.instantAttributes

private extension InstantTripleOperation {
  var draftValidationKind: String {
    switch self {
    case .requireEntityMissing:
      "requireEntityMissing"
    case .requireEntityMissingByLookup:
      "requireEntityMissingByLookup"
    case .requireEntityExists:
      "requireEntityExists"
    case .requireEntityExistsByLookup:
      "requireEntityExistsByLookup"
    case .requireTripleExists:
      "requireTripleExists"
    case .merge:
      "merge"
    case .mergeByLookup:
      "mergeByLookup"
    case .insert:
      "insert"
    case .insertByLookup:
      "insertByLookup"
    case .retract:
      "retract"
    case .retractByLookup:
      "retractByLookup"
    case .deleteEntity:
      "deleteEntity"
    case .deleteEntityInNamespace:
      "deleteEntityInNamespace"
    case .deleteEntityByLookup:
      "deleteEntityByLookup"
    case .ruleParams:
      "ruleParams"
    case .ruleParamsByLookup:
      "ruleParamsByLookup"
    }
  }

  var draftValidationAttributeID: String? {
    switch self {
    case let .insert(triple), let .merge(triple), let .retract(triple):
      triple.attributeID
    case let .insertByLookup(_, attributeID, _, _, _),
      let .mergeByLookup(_, attributeID, _, _, _),
      let .retractByLookup(_, attributeID, _, _, _),
      let .requireTripleExists(_, attributeID, _):
      attributeID
    default:
      nil
    }
  }

  var draftValidationInsertedTriple: InstantTriple? {
    switch self {
    case let .insert(triple):
      triple
    default:
      nil
    }
  }
}

private extension InstantTransportStep {
  var draftValidationKind: String {
    switch self {
    case .addTriple:
      "add-triple"
    case .deepMergeTriple:
      "deep-merge-triple"
    case .retractTriple:
      "retract-triple"
    case .deleteEntity:
      "delete-entity"
    case .ruleParams:
      "rule-params"
    }
  }

  var draftValidationEntityID: String? {
    switch self {
    case let .addTriple(entity, _, _, _),
      let .deepMergeTriple(entity, _, _, _),
      let .retractTriple(entity, _, _),
      let .deleteEntity(entity, _),
      let .ruleParams(entity, _, _):
      entity.draftValidationID
    }
  }

  var draftValidationAttributeID: String? {
    switch self {
    case let .addTriple(_, attributeID, _, _),
      let .deepMergeTriple(_, attributeID, _, _),
      let .retractTriple(_, attributeID, _):
      attributeID
    case .deleteEntity, .ruleParams:
      nil
    }
  }

  var draftValidationValueType: String? {
    switch self {
    case let .addTriple(_, _, value, _),
      let .deepMergeTriple(_, _, value, _),
      let .retractTriple(_, _, value),
      let .ruleParams(_, _, value):
      value.draftValidationType
    case .deleteEntity:
      nil
    }
  }

  var draftValidationValueSummary: String? {
    switch self {
    case let .addTriple(_, _, value, _),
      let .deepMergeTriple(_, _, value, _),
      let .retractTriple(_, _, value),
      let .ruleParams(_, _, value):
      value.draftValidationSummary
    case .deleteEntity:
      nil
    }
  }

  var draftValidationOptionMode: String {
    switch self {
    case let .addTriple(_, _, _, options), let .deepMergeTriple(_, _, _, options):
      options?.mode.rawValue ?? "none"
    case .retractTriple, .deleteEntity, .ruleParams:
      "none"
    }
  }
}

private extension InstantTransportEntityRef {
  var draftValidationID: String {
    switch self {
    case let .id(id):
      id
    case let .lookup(lookup):
      "lookup:\(lookup.attributeID)"
    }
  }
}

private extension InstantTransportValue {
  var draftValidationType: String {
    switch self {
    case .null:
      "null"
    case .bool:
      "boolean"
    case .number:
      "number"
    case .string:
      "string"
    case .array:
      "array"
    case .object:
      "object"
    }
  }

  var draftValidationSummary: String {
    switch self {
    case .null:
      "null"
    case let .bool(value):
      "boolean:\(value)"
    case let .number(value):
      "number:\(value)"
    case let .string(value):
      "string:\(value)"
    case .array:
      "array"
    case .object:
      "object"
    }
  }
}

private extension InstantValue {
  var draftValidationType: String {
    switch self {
    case .null:
      "null"
    case .bool:
      "boolean"
    case .number:
      "number"
    case .string:
      "string"
    case .date:
      "date"
    case .json:
      "json"
    case .ref:
      "ref"
    case .lookupRef:
      "lookup-ref"
    }
  }

  var draftValidationSummary: String {
    switch self {
    case .null:
      "null"
    case let .bool(value):
      "boolean:\(value)"
    case let .number(value):
      "number:\(value)"
    case let .string(value):
      "string:\(value)"
    case let .date(value):
      "date:\(Int64((value.timeIntervalSince1970 * 1000).rounded()))"
    case .json:
      "json"
    case let .ref(value):
      "ref:\(value)"
    case let .lookupRef(lookup):
      "lookup-ref:\(lookup.attributeID)"
    }
  }
}

private extension String {
  var isDraftValidationPrimaryKeyID: Bool {
    guard let separator = lastIndex(of: "/") else { return false }
    return self[index(after: separator)...] == "id"
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

@InstantEntity
private struct DraftValidationAuthor: Hashable, Codable, InstantEntityModel {
  var id: InstantID<DraftValidationAuthor>
  var name: String

  init(
    id: InstantID<DraftValidationAuthor>,
    name: String
  ) {
    self.id = id
    self.name = name
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(name) = snapshot.values["name"]?.first else {
      throw Self.decodeError(snapshot: snapshot, path: "name", expectedType: "string")
    }
    self.id = InstantID(rawValue: snapshot.id)
    self.name = name
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    path: String,
    expectedType: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "decode draft validation author",
      namespace: instantNamespace,
      path: path,
      localID: snapshot.id,
      message: "Expected \(expectedType) for draft validation author field '\(path)'.",
      recovery: "Check generated Draft relation validation author schema."
    )
  }
}

@InstantEntity
private struct DraftValidationPost: Hashable, Codable, InstantEntityModel {
  var id: InstantID<DraftValidationPost>
  var title: String

  @InstantRelation(reverse: "posts")
  var author: InstantID<DraftValidationAuthor>

  init(
    id: InstantID<DraftValidationPost>,
    title: String,
    author: InstantID<DraftValidationAuthor>
  ) {
    self.id = id
    self.title = title
    self.author = author
  }

  init(snapshot: InstantEntitySnapshot) throws {
    guard case let .string(title) = snapshot.values["title"]?.first else {
      throw Self.decodeError(snapshot: snapshot, path: "title", expectedType: "string")
    }
    guard case let .ref(authorID) = snapshot.values["author"]?.first else {
      throw Self.decodeError(snapshot: snapshot, path: "author", expectedType: "ref")
    }
    self.id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.author = InstantID(rawValue: authorID)
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    path: String,
    expectedType: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "decode draft validation post",
      namespace: instantNamespace,
      path: path,
      localID: snapshot.id,
      message: "Expected \(expectedType) for draft validation post field '\(path)'.",
      recovery: "Check generated Draft relation validation post schema."
    )
  }
}
