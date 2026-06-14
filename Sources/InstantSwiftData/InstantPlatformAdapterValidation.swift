import Foundation

public struct PlatformAdapterValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var adapter: String
  public var todoIDs: [String]
  public var todoTitles: [String]
  public var todoCount: Int
  public var selectedTodoID: String?
  public var selectedTodoTitle: String?
  public var localID: String?
  public var authUserID: String?
  public var roomMemberIDs: [String]
  public var topicMessageIDs: [String]
  public var fileIDs: [String]
  public var streamChunkIDs: [String]
  public var shareIDs: [String]

  public init(
    cachePath: String,
    adapter: String,
    todoIDs: [String] = [],
    todoTitles: [String] = [],
    todoCount: Int = 0,
    selectedTodoID: String? = nil,
    selectedTodoTitle: String? = nil,
    localID: String? = nil,
    authUserID: String? = nil,
    roomMemberIDs: [String] = [],
    topicMessageIDs: [String] = [],
    fileIDs: [String] = [],
    streamChunkIDs: [String] = [],
    shareIDs: [String] = []
  ) {
    self.cachePath = cachePath
    self.adapter = adapter
    self.todoIDs = todoIDs
    self.todoTitles = todoTitles
    self.todoCount = todoCount
    self.selectedTodoID = selectedTodoID
    self.selectedTodoTitle = selectedTodoTitle
    self.localID = localID
    self.authUserID = authUserID
    self.roomMemberIDs = roomMemberIDs
    self.topicMessageIDs = topicMessageIDs
    self.fileIDs = fileIDs
    self.streamChunkIDs = streamChunkIDs
    self.shareIDs = shareIDs
  }
}

public struct PlatformAdapterValidationResult: Sendable {
  public var appID: String
  public var cacheURL: URL
  public var evidence: [ValidationEvidenceRow<PlatformAdapterValidationDetails>]

  public init(
    appID: String,
    cacheURL: URL,
    evidence: [ValidationEvidenceRow<PlatformAdapterValidationDetails>]
  ) {
    self.appID = appID
    self.cacheURL = cacheURL
    self.evidence = evidence
  }
}

public enum InstantSwiftDataPlatformAdapterValidation {
  public static func run(
    appID: String = "platform-adapter-validation",
    cacheURL: URL? = nil,
    timestamp: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
  ) async throws -> PlatformAdapterValidationResult {
    let cacheURL =
      cacheURL
      ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("InstantSwiftDataPlatformAdapters-\(makeID())", isDirectory: true)
        .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: PlatformAdapterTodo.instantAttributes,
        now: timestamp,
        makeID: makeID
      )
    )
    let client = InstantSwiftDataClient(runtime: runtime)
    var evidence: [ValidationEvidenceRow<PlatformAdapterValidationDetails>] = []

    let todoID = InstantID<PlatformAdapterTodo>(rawValue: makeID())
    let createdAt = date(from: timestamp())
    try await client.transact(id: "validation.platform-adapters.seed") {
      PlatformAdapterTodo.create(
        id: todoID,
        PlatformAdapterTodo.title.set("Bind public adapter wrappers"),
        PlatformAdapterTodo.isCompleted.set(false),
        PlatformAdapterTodo.createdAt.set(createdAt)
      )
    }

    let todos = FetchAll<PlatformAdapterTodo>(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt)
    )
    try await runTask(
      {
        try await todos.task(using: client)
      },
      until: {
        todos.wrappedValue.map(\.id.rawValue) == [todoID.rawValue]
      }
    )
    evidence.append(
      evidenceRow(
        event: "fetch-all",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@FetchAll",
          todoIDs: todos.wrappedValue.map(\.id.rawValue),
          todoTitles: todos.wrappedValue.map(\.title),
          todoCount: todos.wrappedValue.count
        )
      )
    )

    let todo = FetchOne<PlatformAdapterTodo?>(
      PlatformAdapterTodo.query.where(PlatformAdapterTodo.isCompleted == false)
    )
    try await runTask(
      {
        try await todo.task(using: client)
      },
      until: {
        todo.wrappedValue?.id == todoID
      }
    )
    evidence.append(
      evidenceRow(
        event: "fetch-one",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@FetchOne",
          todoIDs: [todoID.rawValue],
          todoTitles: [todo.wrappedValue?.title].compactMap { $0 },
          todoCount: todo.wrappedValue == nil ? 0 : 1,
          selectedTodoID: todo.wrappedValue?.id.rawValue,
          selectedTodoTitle: todo.wrappedValue?.title
        )
      )
    )

    let todoCount = Fetch<Int>(
      wrappedValue: 0,
      load: { client in
        try await client.query(PlatformAdapterTodo.query).count
      },
      subscribe: { client in
        await client.subscribe(PlatformAdapterTodo.query).map(\.count)
      }
    )
    try await runTask(
      {
        try await todoCount.task(using: client)
      },
      until: {
        todoCount.wrappedValue == 1
      }
    )
    evidence.append(
      evidenceRow(
        event: "fetch",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@Fetch",
          todoIDs: [todoID.rawValue],
          todoTitles: todos.wrappedValue.map(\.title),
          todoCount: todoCount.wrappedValue
        )
      )
    )

    let localID = LocalID("validation.platform-adapters.local-id")
    try await localID.task(using: client)
    evidence.append(
      evidenceRow(
        event: "local-id",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@LocalID",
          localID: localID.wrappedValue
        )
      )
    )

    _ = try await client.signInWithRefreshToken("adapter-refresh", userID: "adapter-user")

    let authSession = AuthSession()
    try await runTask(
      {
        try await authSession.task(using: client)
      },
      until: {
        authSession.wrappedValue?.userID == "adapter-user"
      }
    )
    evidence.append(
      evidenceRow(
        event: "auth-session",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@AuthSession",
          authUserID: authSession.wrappedValue?.userID
        )
      )
    )

    let room = InstantRoomHandle(type: "validation", id: "platform-adapters")
    let member = try await client.setRoomPresence(
      room: room,
      values: ["name": .string("Adapter")]
    )

    let presence = RoomPresence(room: room)
    try await runTask(
      {
        try await presence.task(using: client)
      },
      until: {
        presence.wrappedValue.map(\.id) == [member.id]
      }
    )
    evidence.append(
      evidenceRow(
        event: "room-presence",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@RoomPresence",
          authUserID: authSession.wrappedValue?.userID,
          roomMemberIDs: presence.wrappedValue.map(\.userID)
        )
      )
    )

    let topicMessage = try await client.publishRoomTopicMessage(
      room: room,
      topic: "sendEmoji",
      payload: .object(["emoji": .string("sparkles")])
    )

    let topicMessages = RoomTopicMessages(room: room, topic: "sendEmoji", limit: 1)
    try await runTask(
      {
        try await topicMessages.task(using: client)
      },
      until: {
        topicMessages.wrappedValue.map(\.id) == [topicMessage.id]
      }
    )
    evidence.append(
      evidenceRow(
        event: "room-topic-messages",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@RoomTopicMessages",
          authUserID: authSession.wrappedValue?.userID,
          roomMemberIDs: presence.wrappedValue.map(\.userID),
          topicMessageIDs: topicMessages.wrappedValue.map(\.id)
        )
      )
    )

    let sourceURL = cacheURL.deletingLastPathComponent().appendingPathComponent("adapter.txt")
    try Data("adapter validation".utf8).write(to: sourceURL)
    let storedFile = try await client.uploadFile(
      from: sourceURL,
      name: "adapter.txt",
      contentType: "text/plain"
    )

    let files = StoredFiles()
    try await runTask(
      {
        try await files.task(using: client)
      },
      until: {
        files.wrappedValue.map(\.id) == [storedFile.id]
      }
    )
    evidence.append(
      evidenceRow(
        event: "stored-files",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@StoredFiles",
          fileIDs: files.wrappedValue.map(\.id)
        )
      )
    )

    let chunk = try await client.appendStreamChunk(
      streamID: "validation/platform-adapters",
      payload: .object(["text": .string("adapter chunk")])
    )

    let chunks = StreamChunks("validation/platform-adapters", limit: 1)
    try await runTask(
      {
        try await chunks.task(using: client)
      },
      until: {
        chunks.wrappedValue.map(\.id) == [chunk.id]
      }
    )
    evidence.append(
      evidenceRow(
        event: "stream-chunks",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@StreamChunks",
          streamChunkIDs: chunks.wrappedValue.map(\.id)
        )
      )
    )

    let share = try await client.createShare(
      rootNamespace: PlatformAdapterTodo.instantNamespace,
      rootID: todoID.rawValue
    )

    let shares = Shares()
    try await runTask(
      {
        try await shares.task(using: client)
      },
      until: {
        shares.wrappedValue.map(\.share.id) == [share.share.id]
      }
    )
    evidence.append(
      evidenceRow(
        event: "shares",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "@Shares",
          authUserID: authSession.wrappedValue?.userID,
          shareIDs: shares.wrappedValue.map(\.share.id)
        )
      )
    )

    return PlatformAdapterValidationResult(appID: appID, cacheURL: cacheURL, evidence: evidence)
  }

  private static func evidenceRow(
    event: String,
    appID: String,
    timestamp: @escaping @Sendable () -> InstantTimestamp,
    details: PlatformAdapterValidationDetails
  ) -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    ValidationEvidenceRow(
      caseID: "validation.platform.adapters",
      side: "swift",
      event: event,
      appID: appID,
      timestampMs: timestamp().milliseconds,
      ok: true,
      details: details
    )
  }

  private static func date(from timestamp: InstantTimestamp) -> Date {
    Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
  }

  private static func runTask(
    _ operation: @escaping @Sendable () async throws -> Void,
    until condition: @escaping @Sendable () -> Bool
  ) async throws {
    let task = Task {
      try await operation()
    }

    do {
      try await waitUntil(condition)
    } catch {
      task.cancel()
      do {
        _ = try await task.value
      } catch is CancellationError {
      }
      throw error
    }

    task.cancel()
    do {
      _ = try await task.value
    } catch is CancellationError {
    }
  }

  private static func waitUntil(
    _ condition: @escaping @Sendable () -> Bool
  ) async throws {
    for _ in 0..<100 {
      if condition() {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw InstantError(
      code: .validationFailed,
      operation: "validate platform adapter task binding",
      message: "Timed out waiting for a public adapter wrapper to bind its local value.",
      recovery:
        "Inspect wrapper task/subscription cancellation and local InstantRuntime observation delivery."
    )
  }
}

@InstantEntity
private struct PlatformAdapterTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<PlatformAdapterTodo>
  var title: String
  var isCompleted: Bool = false
  var createdAt: Date

  init(
    id: InstantID<PlatformAdapterTodo>,
    title: String,
    isCompleted: Bool,
    createdAt: Date
  ) {
    self.id = id
    self.title = title
    self.isCompleted = isCompleted
    self.createdAt = createdAt
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
    self.id = InstantID(rawValue: snapshot.id)
    self.title = title
    self.isCompleted = isCompleted
    self.createdAt = createdAt
  }

  private static func decodeError(
    snapshot: InstantEntitySnapshot,
    path: String,
    expectedType: String
  ) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode platform adapter validation todo",
      namespace: Self.instantNamespace,
      path: path,
      localID: snapshot.id,
      message: "Expected \(expectedType) for platform adapter validation field '\(path)'.",
      recovery: "Inspect platform adapter validation schema attributes and local triples."
    )
  }
}
