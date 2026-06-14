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
  public var pendingMutationIDs: [String]
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
    pendingMutationIDs: [String],
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
    self.pendingMutationIDs = pendingMutationIDs
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
    case pendingMutationIDs
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
      pendingMutationIDs: try container.decodeIfPresent([String].self, forKey: .pendingMutationIDs)
        ?? [],
      createdID: try container.decodeIfPresent(String.self, forKey: .createdID),
      editedID: try container.decodeIfPresent(String.self, forKey: .editedID),
      relationAuthorID: try container.decodeIfPresent(String.self, forKey: .relationAuthorID),
      relationPostID: try container.decodeIfPresent(String.self, forKey: .relationPostID)
    )
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
    evidence.append(
      try await evidenceRow(
        event: "relation",
        runtime: runtime,
        cacheURL: cacheURL,
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
        pendingMutationIDs: pending.map(\.id),
        createdID: createdID,
        editedID: editedID,
        relationAuthorID: relationAuthorID,
        relationPostID: relationPostID
      )
    )
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
