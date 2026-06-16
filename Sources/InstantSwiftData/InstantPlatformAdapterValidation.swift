import Foundation

#if canImport(SwiftUI)
  import SwiftUI
#endif

public struct PlatformAdapterValidationDetails: Codable, Equatable, Sendable {
  public var cachePath: String
  public var adapter: String
  public var bindingAdapters: [String]
  public var todoIDs: [String]
  public var todoTitles: [String]
  public var previousTodoTitles: [String]
  public var fetchAllTitleBatches: [[String]]
  public var fetchTitleBatches: [[String]]
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
  public var queryCount: Int?
  public var observationCount: Int?
  public var loadErrorOperation: String?
  public var isLoading: Bool?
  public var nilQueryCleared: Bool?
  public var nilRequestCleared: Bool?
  public var cancellationTerminated: Bool?

  public init(
    cachePath: String,
    adapter: String,
    bindingAdapters: [String] = [],
    todoIDs: [String] = [],
    todoTitles: [String] = [],
    previousTodoTitles: [String] = [],
    fetchAllTitleBatches: [[String]] = [],
    fetchTitleBatches: [[String]] = [],
    todoCount: Int = 0,
    selectedTodoID: String? = nil,
    selectedTodoTitle: String? = nil,
    localID: String? = nil,
    authUserID: String? = nil,
    roomMemberIDs: [String] = [],
    topicMessageIDs: [String] = [],
    fileIDs: [String] = [],
    streamChunkIDs: [String] = [],
    shareIDs: [String] = [],
    queryCount: Int? = nil,
    observationCount: Int? = nil,
    loadErrorOperation: String? = nil,
    isLoading: Bool? = nil,
    nilQueryCleared: Bool? = nil,
    nilRequestCleared: Bool? = nil,
    cancellationTerminated: Bool? = nil
  ) {
    self.cachePath = cachePath
    self.adapter = adapter
    self.bindingAdapters = bindingAdapters
    self.todoIDs = todoIDs
    self.todoTitles = todoTitles
    self.previousTodoTitles = previousTodoTitles
    self.fetchAllTitleBatches = fetchAllTitleBatches
    self.fetchTitleBatches = fetchTitleBatches
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
    self.queryCount = queryCount
    self.observationCount = observationCount
    self.loadErrorOperation = loadErrorOperation
    self.isLoading = isLoading
    self.nilQueryCleared = nilQueryCleared
    self.nilRequestCleared = nilRequestCleared
    self.cancellationTerminated = cancellationTerminated
  }

  private enum CodingKeys: String, CodingKey {
    case cachePath
    case adapter
    case bindingAdapters
    case todoIDs
    case todoTitles
    case previousTodoTitles
    case fetchAllTitleBatches
    case fetchTitleBatches
    case todoCount
    case selectedTodoID
    case selectedTodoTitle
    case localID
    case authUserID
    case roomMemberIDs
    case topicMessageIDs
    case fileIDs
    case streamChunkIDs
    case shareIDs
    case queryCount
    case observationCount
    case loadErrorOperation
    case isLoading
    case nilQueryCleared
    case nilRequestCleared
    case cancellationTerminated
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      cachePath: container.decode(String.self, forKey: .cachePath),
      adapter: container.decode(String.self, forKey: .adapter),
      bindingAdapters: container.decodeIfPresent([String].self, forKey: .bindingAdapters) ?? [],
      todoIDs: container.decodeIfPresent([String].self, forKey: .todoIDs) ?? [],
      todoTitles: container.decodeIfPresent([String].self, forKey: .todoTitles) ?? [],
      previousTodoTitles: container.decodeIfPresent([String].self, forKey: .previousTodoTitles)
        ?? [],
      fetchAllTitleBatches: container
        .decodeIfPresent([[String]].self, forKey: .fetchAllTitleBatches) ?? [],
      fetchTitleBatches: container.decodeIfPresent([[String]].self, forKey: .fetchTitleBatches)
        ?? [],
      todoCount: container.decodeIfPresent(Int.self, forKey: .todoCount) ?? 0,
      selectedTodoID: container.decodeIfPresent(String.self, forKey: .selectedTodoID),
      selectedTodoTitle: container.decodeIfPresent(String.self, forKey: .selectedTodoTitle),
      localID: container.decodeIfPresent(String.self, forKey: .localID),
      authUserID: container.decodeIfPresent(String.self, forKey: .authUserID),
      roomMemberIDs: container.decodeIfPresent([String].self, forKey: .roomMemberIDs) ?? [],
      topicMessageIDs: container.decodeIfPresent([String].self, forKey: .topicMessageIDs) ?? [],
      fileIDs: container.decodeIfPresent([String].self, forKey: .fileIDs) ?? [],
      streamChunkIDs: container.decodeIfPresent([String].self, forKey: .streamChunkIDs) ?? [],
      shareIDs: container.decodeIfPresent([String].self, forKey: .shareIDs) ?? [],
      queryCount: container.decodeIfPresent(Int.self, forKey: .queryCount),
      observationCount: container.decodeIfPresent(Int.self, forKey: .observationCount),
      loadErrorOperation: container.decodeIfPresent(String.self, forKey: .loadErrorOperation),
      isLoading: container.decodeIfPresent(Bool.self, forKey: .isLoading),
      nilQueryCleared: container.decodeIfPresent(Bool.self, forKey: .nilQueryCleared),
      nilRequestCleared: container.decodeIfPresent(Bool.self, forKey: .nilRequestCleared),
      cancellationTerminated: container.decodeIfPresent(Bool.self, forKey: .cancellationTerminated)
    )
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
  private static let projectedBindingAdapters = [
    "@FetchAll",
    "@InfiniteQuery",
    "@FetchOne",
    "@Fetch",
    "@LocalID",
    "@AuthSession",
    "@RoomPresence",
    "@RoomTopicMessages",
    "@StoredFiles",
    "@StreamChunks",
    "@Shares",
  ]

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
    evidence.append(
      try validateProjectedBindings(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp,
        todo: PlatformAdapterTodo(
          id: todoID,
          title: "Bind public adapter wrappers",
          isCompleted: false,
          createdAt: createdAt
        ),
        localID: localID.wrappedValue,
        authSession: authSession.wrappedValue,
        room: room,
        member: member,
        topicMessage: topicMessage,
        storedFile: storedFile,
        chunk: chunk,
        share: share
      )
    )

    evidence.append(
      try await validateFilteredReload(
        client: client,
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateDynamicQueryReload(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateFetchOneDynamicQueryReload(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateFetchRequestDynamicReload(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateNilQueryClearsWithoutClient(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateFetchOneNilQueryClearsWithoutClient(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateFetchRequestNilRequestClearsWithoutClient(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateCachedPriorOnError(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateCancellationCleanup(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateFetchRequestCancellationCleanup(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateInfiniteQueryDynamicCancellation(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateInfiniteQueryDynamicLoad(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )
    evidence.append(
      try await validateLiveWrapperDynamicCancellation(
        appID: appID,
        cacheURL: cacheURL,
        timestamp: timestamp
      )
    )

    return PlatformAdapterValidationResult(appID: appID, cacheURL: cacheURL, evidence: evidence)
  }

  private static func validateProjectedBindings(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp,
    todo: PlatformAdapterTodo,
    localID: String?,
    authSession: InstantAuthSession?,
    room: InstantRoomHandle,
    member: InstantRoomPresenceMember,
    topicMessage: InstantRoomTopicMessage,
    storedFile: InstantStoredFile,
    chunk: InstantStreamChunk,
    share: InstantShareSnapshot
  ) throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    #if canImport(SwiftUI)
      @FetchAll var all: [PlatformAdapterTodo] = []
      $all.binding.wrappedValue = [todo]

      @InfiniteQuery var infinite: [PlatformAdapterTodo] = []
      $infinite.binding.wrappedValue = [todo]

      @FetchOne var one: PlatformAdapterTodo? = nil
      $one.binding.wrappedValue = todo

      @Fetch var count = 0
      $count.binding.wrappedValue = 1

      @LocalID var local: String?
      $local.binding.wrappedValue = localID

      @AuthSession var auth: InstantAuthSession?
      $auth.binding.wrappedValue = authSession

      @RoomPresence(room: room) var presence: [InstantRoomPresenceMember]
      $presence.binding.wrappedValue = [member]

      @RoomTopicMessages(room: room, topic: topicMessage.topic, limit: 1)
      var topicMessages: [InstantRoomTopicMessage]
      $topicMessages.binding.wrappedValue = [topicMessage]

      @StoredFiles var files: [InstantStoredFile]
      $files.binding.wrappedValue = [storedFile]

      @StreamChunks(chunk.streamID, limit: 1) var chunks: [InstantStreamChunk]
      $chunks.binding.wrappedValue = [chunk]

      @Shares var shares: [InstantShareSnapshot]
      $shares.binding.wrappedValue = [share]

      guard
        all.map(\.id.rawValue) == [todo.id.rawValue],
        infinite.map(\.id.rawValue) == [todo.id.rawValue],
        one?.id == todo.id,
        count == 1,
        local == localID,
        auth?.userID == authSession?.userID,
        presence.map(\.id) == [member.id],
        topicMessages.map(\.id) == [topicMessage.id],
        files.map(\.id) == [storedFile.id],
        chunks.map(\.id) == [chunk.id],
        shares.map(\.share.id) == [share.share.id]
      else {
        throw validationFailure(
          operation: "validate platform adapter projected bindings",
          message: "Expected every public platform adapter wrapper to expose a mutable binding."
        )
      }

      return evidenceRow(
        event: "projected-bindings",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "Projected bindings",
          bindingAdapters: projectedBindingAdapters,
          todoIDs: all.map(\.id.rawValue),
          todoTitles: all.map(\.title),
          todoCount: count,
          selectedTodoID: one?.id.rawValue,
          selectedTodoTitle: one?.title,
          localID: local,
          authUserID: auth?.userID,
          roomMemberIDs: presence.map(\.userID),
          topicMessageIDs: topicMessages.map(\.id),
          fileIDs: files.map(\.id),
          streamChunkIDs: chunks.map(\.id),
          shareIDs: shares.map(\.share.id)
        )
      )
    #else
      return evidenceRow(
        event: "projected-bindings",
        appID: appID,
        timestamp: timestamp,
        details: PlatformAdapterValidationDetails(
          cachePath: cacheURL.path,
          adapter: "Projected bindings(unavailable)"
        )
      )
    #endif
  }

  private static func validateFilteredReload(
    client: InstantSwiftDataClient,
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let title = "Engineering"
    let activeID = InstantID<PlatformAdapterTodo>(rawValue: "adapter-filtered-reload")
    let activeQuery = PlatformAdapterTodo.query
      .where(PlatformAdapterTodo.title == title)
      .where(PlatformAdapterTodo.isCompleted == false)
      .order(PlatformAdapterTodo.createdAt)
    let fetchAll = FetchAll<PlatformAdapterTodo>(activeQuery)
    let fetch = Fetch<[PlatformAdapterTodo]>(
      wrappedValue: [],
      load: { client in
        try await client.query(activeQuery)
      }
    )
    var fetchAllTitleBatches = [fetchAll.wrappedValue.map(\.title)]
    var fetchTitleBatches = [fetch.wrappedValue.map(\.title)]

    try await client.transact(id: "validation.platform-adapters.filtered.create") {
      PlatformAdapterTodo.create(
        id: activeID,
        PlatformAdapterTodo.title.set(title),
        PlatformAdapterTodo.isCompleted.set(false),
        PlatformAdapterTodo.createdAt.set(date(from: timestamp()))
      )
    }
    try await fetchAll.load(using: client)
    try await fetch.load(using: client)
    fetchAllTitleBatches.append(fetchAll.wrappedValue.map(\.title))
    fetchTitleBatches.append(fetch.wrappedValue.map(\.title))

    try await client.transact(id: "validation.platform-adapters.filtered.inactive") {
      PlatformAdapterTodo.update(
        id: activeID,
        PlatformAdapterTodo.isCompleted.set(true)
      )
    }
    try await fetchAll.load(using: client)
    try await fetch.load(using: client)
    fetchAllTitleBatches.append(fetchAll.wrappedValue.map(\.title))
    fetchTitleBatches.append(fetch.wrappedValue.map(\.title))

    try await client.transact(id: "validation.platform-adapters.filtered.active") {
      PlatformAdapterTodo.update(
        id: activeID,
        PlatformAdapterTodo.isCompleted.set(false)
      )
    }
    try await fetchAll.load(using: client)
    try await fetch.load(using: client)
    fetchAllTitleBatches.append(fetchAll.wrappedValue.map(\.title))
    fetchTitleBatches.append(fetch.wrappedValue.map(\.title))

    let expectedBatches = [[], [title], [], [title]]
    guard
      fetchAllTitleBatches == expectedBatches,
      fetchTitleBatches == expectedBatches,
      fetchAll.loadError == nil,
      fetch.loadError == nil,
      fetchAll.isLoading == false,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter filtered reload",
        message: "Expected @FetchAll and @Fetch to reload active rows after inactive/active updates."
      )
    }

    return evidenceRow(
      event: "fetch-all-filtered-reload",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@FetchAll/@Fetch(filtered)",
        todoIDs: fetchAll.wrappedValue.map(\.id.rawValue),
        todoTitles: fetchAll.wrappedValue.map(\.title),
        fetchAllTitleBatches: fetchAllTitleBatches,
        fetchTitleBatches: fetchTitleBatches,
        todoCount: fetchAll.wrappedValue.count,
        queryCount: 6,
        observationCount: 0,
        isLoading: fetchAll.isLoading || fetch.isLoading
      )
    )
  }

  private static func validateDynamicQueryReload(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let open = todoSnapshot(
      id: "adapter-dynamic-open",
      title: "Open dynamic",
      isCompleted: false,
      createdAt: date(from: timestamp())
    )
    let done = todoSnapshot(
      id: "adapter-dynamic-done",
      title: "Done dynamic",
      isCompleted: true,
      createdAt: date(from: timestamp())
    )
    let recorder = PlatformAdapterLifecycleRecorder(queryResults: [[open], [done]])
    let client = lifecycleClient(recorder)
    let fetch = FetchAll<PlatformAdapterTodo>(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt)
    )

    try await fetch.load(
      PlatformAdapterTodo.query
        .where(PlatformAdapterTodo.isCompleted == false)
        .order(PlatformAdapterTodo.createdAt),
      using: client
    )
    let previousTitles = fetch.wrappedValue.map(\.title)

    try await fetch.load(
      PlatformAdapterTodo.query
        .where(PlatformAdapterTodo.isCompleted == true)
        .order(PlatformAdapterTodo.createdAt),
      using: client
    )
    let titles = fetch.wrappedValue.map(\.title)
    let counts = await recorder.counts()
    let plans = await recorder.queryPlans()

    guard
      previousTitles == ["Open dynamic"],
      titles == ["Done dynamic"],
      counts.queryCount == 2,
      counts.observationCount == 0,
      plans.map(\.filters) == [
        [.equals(field: "isCompleted", value: .bool(false))],
        [.equals(field: "isCompleted", value: .bool(true))],
      ],
      plans.map(\.order) == [
        InstantQueryOrder("createdAt"),
        InstantQueryOrder("createdAt"),
      ],
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter dynamic FetchAll",
        message: "Expected dynamic FetchAll loads to reload from two non-nil queries."
      )
    }

    return evidenceRow(
      event: "fetch-all-dynamic-query",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@FetchAll(dynamic)",
        todoIDs: fetch.wrappedValue.map(\.id.rawValue),
        todoTitles: titles,
        previousTodoTitles: previousTitles,
        todoCount: fetch.wrappedValue.count,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading
      )
    )
  }

  private static func validateFetchOneDynamicQueryReload(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let open = todoSnapshot(
      id: "adapter-fetch-one-open",
      title: "Open single",
      isCompleted: false,
      createdAt: date(from: timestamp())
    )
    let done = todoSnapshot(
      id: "adapter-fetch-one-done",
      title: "Done single",
      isCompleted: true,
      createdAt: date(from: timestamp())
    )
    let recorder = PlatformAdapterLifecycleRecorder(queryResults: [[open], [done]])
    let client = lifecycleClient(recorder)
    let fetch = FetchOne<PlatformAdapterTodo?>(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt)
    )

    try await fetch.load(
      PlatformAdapterTodo.query
        .where(PlatformAdapterTodo.isCompleted == false)
        .order(PlatformAdapterTodo.createdAt),
      using: client
    )
    let previousTitle = fetch.wrappedValue?.title

    try await fetch.load(
      PlatformAdapterTodo.query
        .where(PlatformAdapterTodo.isCompleted == true)
        .order(PlatformAdapterTodo.createdAt),
      using: client
    )
    let selectedTodo = fetch.wrappedValue
    let counts = await recorder.counts()
    let plans = await recorder.queryPlans()

    guard
      previousTitle == "Open single",
      selectedTodo?.title == "Done single",
      counts.queryCount == 2,
      counts.observationCount == 0,
      plans.map(\.filters) == [
        [.equals(field: "isCompleted", value: .bool(false))],
        [.equals(field: "isCompleted", value: .bool(true))],
      ],
      plans.map(\.limit) == [1, 1],
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter dynamic FetchOne",
        message: "Expected dynamic FetchOne loads to replace the selected optional entity."
      )
    }

    return evidenceRow(
      event: "fetch-one-dynamic-query",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@FetchOne(dynamic)",
        todoIDs: [selectedTodo?.id.rawValue].compactMap { $0 },
        todoTitles: [selectedTodo?.title].compactMap { $0 },
        previousTodoTitles: [previousTitle].compactMap { $0 },
        todoCount: selectedTodo == nil ? 0 : 1,
        selectedTodoID: selectedTodo?.id.rawValue,
        selectedTodoTitle: selectedTodo?.title,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading
      )
    )
  }

  private static func validateFetchRequestDynamicReload(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let open = todoSnapshot(
      id: "adapter-fetch-request-open",
      title: "Open request",
      isCompleted: false,
      createdAt: date(from: timestamp())
    )
    let done = todoSnapshot(
      id: "adapter-fetch-request-done",
      title: "Done request",
      isCompleted: true,
      createdAt: date(from: timestamp())
    )
    let recorder = PlatformAdapterLifecycleRecorder(queryResults: [
      [open],
      [open, done],
      [done],
      [open, done],
    ])
    let client = lifecycleClient(recorder)
    let fetch = Fetch(wrappedValue: PlatformAdapterTodoFacts())

    try await fetch.load(
      PlatformAdapterTodoFactsRequest(
        rowsQuery: PlatformAdapterTodo.query
          .where(PlatformAdapterTodo.isCompleted == false)
          .order(PlatformAdapterTodo.createdAt),
        countQuery: PlatformAdapterTodo.query
      ),
      using: client
    )
    let previousTitles = fetch.wrappedValue.todos.map(\.title)

    try await fetch.load(
      PlatformAdapterTodoFactsRequest(
        rowsQuery: PlatformAdapterTodo.query
          .where(PlatformAdapterTodo.isCompleted == true)
          .order(PlatformAdapterTodo.createdAt),
        countQuery: PlatformAdapterTodo.query
      ),
      using: client
    )
    let counts = await recorder.counts()
    let plans = await recorder.queryPlans()
    let titles = fetch.wrappedValue.todos.map(\.title)

    guard
      previousTitles == ["Open request"],
      titles == ["Done request"],
      fetch.wrappedValue.count == 2,
      counts.queryCount == 4,
      counts.observationCount == 0,
      plans.map(\.filters) == [
        [.equals(field: "isCompleted", value: .bool(false))],
        [],
        [.equals(field: "isCompleted", value: .bool(true))],
        [],
      ],
      plans.map(\.order) == [
        InstantQueryOrder("createdAt"),
        nil,
        InstantQueryOrder("createdAt"),
        nil,
      ],
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter dynamic Fetch request",
        message: "Expected dynamic @Fetch request loads to replace composite request values."
      )
    }

    return evidenceRow(
      event: "fetch-request-dynamic-query",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@Fetch(request dynamic)",
        todoIDs: fetch.wrappedValue.todos.map(\.id.rawValue),
        todoTitles: titles,
        previousTodoTitles: previousTitles,
        todoCount: fetch.wrappedValue.count,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading
      )
    )
  }

  private static func validateNilQueryClearsWithoutClient(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let cached = PlatformAdapterTodo(
      id: InstantID(rawValue: "adapter-nil-query-cached"),
      title: "Cached nil query",
      isCompleted: false,
      createdAt: date(from: timestamp())
    )
    let recorder = PlatformAdapterLifecycleRecorder()
    let fetch = FetchAll<PlatformAdapterTodo>(
      wrappedValue: [cached],
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt)
    )
    fetch.loadError = InstantError(
      code: .implementationFailed,
      operation: "previous adapter FetchAll load",
      message: "previous failure",
      recovery: "Retry with a non-nil query."
    )
    fetch.isLoading = true

    try await fetch.load(
      nil as InstantEntityQuery<PlatformAdapterTodo>?,
      using: lifecycleClient(recorder)
    )
    let counts = await recorder.counts()

    guard
      fetch.wrappedValue.isEmpty,
      counts.queryCount == 0,
      counts.observationCount == 0,
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter nil FetchAll query",
        message: "Expected a nil FetchAll query to clear cached results without calling the client."
      )
    }

    return evidenceRow(
      event: "fetch-all-nil-query",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@FetchAll(nil)",
        previousTodoTitles: [cached.title],
        todoCount: fetch.wrappedValue.count,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading,
        nilQueryCleared: fetch.wrappedValue.isEmpty
      )
    )
  }

  private static func validateFetchOneNilQueryClearsWithoutClient(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let cached = PlatformAdapterTodo(
      id: InstantID(rawValue: "adapter-fetch-one-nil-query-cached"),
      title: "Cached optional nil query",
      isCompleted: false,
      createdAt: date(from: timestamp())
    )
    let recorder = PlatformAdapterLifecycleRecorder()
    let fetch = FetchOne<PlatformAdapterTodo?>(
      wrappedValue: cached,
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt)
    )
    fetch.loadError = InstantError(
      code: .implementationFailed,
      operation: "previous adapter FetchOne load",
      message: "previous failure",
      recovery: "Retry with a non-nil query."
    )
    fetch.isLoading = true

    try await fetch.load(
      nil as InstantEntityQuery<PlatformAdapterTodo>?,
      using: lifecycleClient(recorder)
    )
    let counts = await recorder.counts()

    guard
      fetch.wrappedValue == nil,
      counts.queryCount == 0,
      counts.observationCount == 0,
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter nil FetchOne query",
        message: "Expected a nil FetchOne query to clear cached optional state without calling the client."
      )
    }

    return evidenceRow(
      event: "fetch-one-nil-query",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@FetchOne(nil)",
        previousTodoTitles: [cached.title],
        todoCount: fetch.wrappedValue == nil ? 0 : 1,
        selectedTodoID: fetch.wrappedValue?.id.rawValue,
        selectedTodoTitle: fetch.wrappedValue?.title,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading,
        nilQueryCleared: fetch.wrappedValue == nil
      )
    )
  }

  private static func validateFetchRequestNilRequestClearsWithoutClient(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let cached = PlatformAdapterTodo(
      id: InstantID(rawValue: "adapter-fetch-request-nil-cached"),
      title: "Cached request nil",
      isCompleted: false,
      createdAt: date(from: timestamp())
    )
    let recorder = PlatformAdapterLifecycleRecorder()
    let fetch = Fetch(wrappedValue: PlatformAdapterTodoFacts())
    fetch.wrappedValue = PlatformAdapterTodoFacts(todos: [cached], count: 1)
    fetch.loadError = InstantError(
      code: .implementationFailed,
      operation: "previous adapter Fetch request load",
      message: "previous failure",
      recovery: "Retry with a non-nil request."
    )
    fetch.isLoading = true

    try await fetch.load(
      nil as PlatformAdapterTodoFactsRequest?,
      using: lifecycleClient(recorder)
    )
    let counts = await recorder.counts()

    guard
      fetch.wrappedValue == PlatformAdapterTodoFacts(),
      counts.queryCount == 0,
      counts.observationCount == 0,
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter nil Fetch request",
        message: "Expected a nil @Fetch request to reset to its default without calling the client."
      )
    }

    return evidenceRow(
      event: "fetch-request-nil-request",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@Fetch(request nil)",
        previousTodoTitles: [cached.title],
        todoCount: fetch.wrappedValue.count,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading,
        nilRequestCleared: fetch.wrappedValue == PlatformAdapterTodoFacts()
      )
    )
  }

  private static func validateCachedPriorOnError(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let cached = todoSnapshot(
      id: "adapter-error-cached",
      title: "Cached before error",
      isCompleted: false,
      createdAt: date(from: timestamp())
    )
    let error = InstantError(
      code: .implementationFailed,
      operation: "query dynamic FetchAll",
      message: "dynamic query failed",
      recovery: "Retry with a valid dynamic query."
    )
    let recorder = PlatformAdapterLifecycleRecorder(
      queryResults: [[cached]],
      fallbackError: error
    )
    let client = lifecycleClient(recorder)
    let fetch = FetchAll<PlatformAdapterTodo>(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt)
    )

    try await fetch.load(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt),
      using: client
    )
    let previousTitles = fetch.wrappedValue.map(\.title)

    do {
      try await fetch.load(
        PlatformAdapterTodo.query.where(PlatformAdapterTodo.title == "missing"),
        using: client
      )
      throw validationFailure(
        operation: "validate platform adapter cached FetchAll error",
        message: "Expected the second non-nil FetchAll query to fail."
      )
    } catch let error as InstantError {
      guard error.operation == "query dynamic FetchAll" else {
        throw error
      }
    }

    let counts = await recorder.counts()
    let titles = fetch.wrappedValue.map(\.title)
    guard
      previousTitles == ["Cached before error"],
      titles == previousTitles,
      counts.queryCount == 2,
      counts.observationCount == 0,
      fetch.loadError?.operation == "query dynamic FetchAll",
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter cached FetchAll error",
        message: "Expected FetchAll to keep cached prior results and record the load error."
      )
    }

    return evidenceRow(
      event: "fetch-all-cached-prior-error",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@FetchAll(error)",
        todoIDs: fetch.wrappedValue.map(\.id.rawValue),
        todoTitles: titles,
        previousTodoTitles: previousTitles,
        todoCount: fetch.wrappedValue.count,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        loadErrorOperation: fetch.loadError?.operation,
        isLoading: fetch.isLoading
      )
    )
  }

  private static func validateCancellationCleanup(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let recorder = PlatformAdapterLifecycleRecorder()
    let fetch = FetchAll<PlatformAdapterTodo>(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt)
    )
    let task = Task {
      let fetch = fetch
      try await fetch.task(using: lifecycleClient(recorder))
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter FetchAll observation"
    ) {
      let counts = await recorder.counts()
      return counts.observationCount == 1
    }

    task.cancel()
    do {
      try await task.value
      throw validationFailure(
        operation: "validate platform adapter FetchAll cancellation",
        message: "Expected wrapper task cancellation to throw CancellationError."
      )
    } catch is CancellationError {
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter FetchAll cancellation cleanup"
    ) {
      let counts = await recorder.counts()
      return counts.terminationCount >= 1
    }

    let counts = await recorder.counts()
    let cancellationTerminated = counts.terminationCount >= 1
    guard
      counts.queryCount == 0,
      counts.observationCount == 1,
      cancellationTerminated,
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter FetchAll cancellation cleanup",
        message: "Expected cancellation to terminate observation without recording a load error."
      )
    }

    return evidenceRow(
      event: "fetch-all-cancellation",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@FetchAll(cancellation)",
        todoCount: fetch.wrappedValue.count,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading,
        cancellationTerminated: cancellationTerminated
      )
    )
  }

  private static func validateFetchRequestCancellationCleanup(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let recorder = PlatformAdapterLifecycleRecorder()
    let fetch = Fetch(
      wrappedValue: PlatformAdapterTodoFacts(),
      PlatformAdapterTodoFactsRequest(
        rowsQuery: PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt),
        countQuery: PlatformAdapterTodo.query
      )
    )
    let task = Task {
      let fetch = fetch
      try await fetch.task(using: lifecycleClient(recorder))
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter Fetch request observation"
    ) {
      let counts = await recorder.counts()
      return counts.observationCount == 1
    }

    task.cancel()
    do {
      try await task.value
      throw validationFailure(
        operation: "validate platform adapter Fetch request cancellation",
        message: "Expected @Fetch request task cancellation to throw CancellationError."
      )
    } catch is CancellationError {
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter Fetch request cancellation cleanup"
    ) {
      let counts = await recorder.counts()
      return counts.terminationCount >= 1
    }

    let counts = await recorder.counts()
    let cancellationTerminated = counts.terminationCount >= 1
    guard
      counts.queryCount == 0,
      counts.observationCount == 1,
      cancellationTerminated,
      fetch.loadError == nil,
      fetch.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter Fetch request cancellation cleanup",
        message: "Expected @Fetch request cancellation to terminate without recording a load error."
      )
    }

    return evidenceRow(
      event: "fetch-request-cancellation",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@Fetch(request cancellation)",
        todoCount: fetch.wrappedValue.count,
        queryCount: counts.queryCount,
        observationCount: counts.observationCount,
        isLoading: fetch.isLoading,
        cancellationTerminated: cancellationTerminated
      )
    )
  }

  private static func validateInfiniteQueryDynamicCancellation(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let recorder = PlatformAdapterInfiniteQueryLifecycleRecorder()
    let client = infiniteQueryLifecycleClient(recorder)
    let infinite = InfiniteQuery<PlatformAdapterTodo>(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt).limit(1)
    )
    let firstTask = Task {
      let infinite = infinite
      try await infinite.task(using: client)
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery first subscription"
    ) {
      let counts = await recorder.counts()
      return counts.subscribeCount == 1
    }

    let secondTask = Task {
      let infinite = infinite
      try await infinite.task(using: client)
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery replacement subscription"
    ) {
      let counts = await recorder.counts()
      return counts.subscribeCount == 2
    }

    await recorder.yieldSecond(
      InstantInfiniteQuerySnapshot(
        queryID: PlatformAdapterTodo.query.plan.id,
        sequence: 2,
        values: [
          todoSnapshot(
            id: "platform-adapter-infinite-second",
            title: "Second infinite subscription",
            isCompleted: false,
            createdAt: date(from: timestamp())
          )
        ],
        canLoadNextPage: true
      )
    )

    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery replacement value"
    ) {
      infinite.wrappedValue.map(\.title) == ["Second infinite subscription"]
    }

    await recorder.releaseFirstSubscription()
    do {
      try await firstTask.value
      throw validationFailure(
        operation: "validate platform adapter InfiniteQuery replacement",
        message: "Expected replacing a pending @InfiniteQuery task to cancel the stale task."
      )
    } catch is CancellationError {
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery stale cancellation"
    ) {
      let counts = await recorder.counts()
      return counts.firstUnsubscribeCount >= 1
    }

    infinite.loadNextPage()
    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery latest loadNextPage"
    ) {
      let counts = await recorder.counts()
      return counts.secondLoadNextPageCount == 1
    }

    secondTask.cancel()
    do {
      try await secondTask.value
      throw validationFailure(
        operation: "validate platform adapter InfiniteQuery cancellation",
        message: "Expected canceling the replacement @InfiniteQuery task to throw CancellationError."
      )
    } catch is CancellationError {
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery final cancellation"
    ) {
      let counts = await recorder.counts()
      return counts.secondUnsubscribeCount >= 1
    }

    let counts = await recorder.counts()
    let cancellationTerminated = counts.firstUnsubscribeCount >= 1
      && counts.secondUnsubscribeCount >= 1
    guard
      counts.subscribeCount == 2,
      counts.firstLoadNextPageCount == 0,
      counts.secondLoadNextPageCount == 1,
      cancellationTerminated,
      infinite.wrappedValue.map(\.title) == ["Second infinite subscription"],
      infinite.loadError == nil,
      infinite.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter InfiniteQuery lifecycle",
        message:
          "Expected @InfiniteQuery to ignore stale pending subscriptions and target the live subscription."
      )
    }

    return evidenceRow(
      event: "infinite-query-dynamic-cancellation",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@InfiniteQuery(dynamic cancellation)",
        todoTitles: infinite.wrappedValue.map(\.title),
        previousTodoTitles: ["First infinite subscription"],
        todoCount: infinite.wrappedValue.count,
        observationCount: counts.subscribeCount,
        isLoading: infinite.isLoading,
        cancellationTerminated: cancellationTerminated
      )
    )
  }

  private static func validateInfiniteQueryDynamicLoad(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let recorder = PlatformAdapterInfiniteQueryLoadRecorder(
      staleSnapshot: InstantInfiniteQuerySnapshot(
        queryID: PlatformAdapterTodo.query.plan.id,
        sequence: 1,
        values: [
          todoSnapshot(
            id: "platform-adapter-infinite-stale-load",
            title: "Stale infinite load",
            isCompleted: false,
            createdAt: date(from: timestamp())
          )
        ],
        canLoadNextPage: true
      ),
      freshSnapshot: InstantInfiniteQuerySnapshot(
        queryID: PlatformAdapterTodo.query.plan.id,
        sequence: 2,
        values: [
          todoSnapshot(
            id: "platform-adapter-infinite-fresh-load",
            title: "Fresh infinite load",
            isCompleted: false,
            createdAt: date(from: timestamp())
          )
        ],
        canLoadNextPage: false
      ),
      clearedStaleSnapshot: InstantInfiniteQuerySnapshot(
        queryID: PlatformAdapterTodo.query.plan.id,
        sequence: 3,
        values: [
          todoSnapshot(
            id: "platform-adapter-infinite-cleared-load",
            title: "Cleared stale infinite load",
            isCompleted: false,
            createdAt: date(from: timestamp())
          )
        ],
        canLoadNextPage: true
      )
    )
    let client = infiniteQueryLoadClient(recorder)
    let infinite = InfiniteQuery<PlatformAdapterTodo>(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt).limit(1)
    )

    let staleLoad = Task {
      let infinite = infinite
      try await infinite.load(using: client)
    }
    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery stale load"
    ) {
      await recorder.loadCount() == 1
    }

    try await infinite.load(
      PlatformAdapterTodo.query.order(PlatformAdapterTodo.createdAt).limit(2),
      using: client
    )
    let freshTitles = infinite.wrappedValue.map(\.title)
    let loadLimitsAfterReplacement = await recorder.plans().map(\.limit)
    await recorder.releasePendingLoad(1)
    do {
      try await staleLoad.value
      throw validationFailure(
        operation: "validate platform adapter InfiniteQuery stale load",
        message: "Expected a stale @InfiniteQuery load to be canceled after replacement."
      )
    } catch is CancellationError {
    }

    let clearedLoad = Task {
      let infinite = infinite
      try await infinite.load(using: client)
    }
    try await waitForLifecycle(
      operation: "wait for platform adapter InfiniteQuery clearable load"
    ) {
      await recorder.loadCount() == 3
    }

    try await infinite.load(nil, using: client)
    await recorder.releasePendingLoad(3)
    do {
      try await clearedLoad.value
      throw validationFailure(
        operation: "validate platform adapter InfiniteQuery nil query",
        message: "Expected clearing an @InfiniteQuery query to cancel the pending load."
      )
    } catch is CancellationError {
    }

    let counts = await recorder.loadCount()
    let loadLimits = await recorder.plans().map(\.limit)
    let nilQueryCleared = infinite.wrappedValue.isEmpty
      && infinite.loadError == nil
      && infinite.isLoading == false
      && infinite.pageInfo == nil
      && infinite.canLoadNextPage == false
    guard
      freshTitles == ["Fresh infinite load"],
      counts == 3,
      loadLimitsAfterReplacement == [1, 2],
      loadLimits == [1, 2, 2],
      nilQueryCleared
    else {
      throw validationFailure(
        operation: "validate platform adapter InfiniteQuery dynamic load",
        message:
          "Expected @InfiniteQuery load replacement and nil-query clearing to ignore stale completions."
      )
    }

    return evidenceRow(
      event: "infinite-query-dynamic-load",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@InfiniteQuery(dynamic load)",
        todoTitles: infinite.wrappedValue.map(\.title),
        previousTodoTitles: freshTitles,
        fetchAllTitleBatches: [freshTitles, infinite.wrappedValue.map(\.title)],
        todoCount: infinite.wrappedValue.count,
        queryCount: counts,
        loadErrorOperation: infinite.loadError?.operation,
        isLoading: infinite.isLoading,
        nilQueryCleared: nilQueryCleared
      )
    )
  }

  private static func validateLiveWrapperDynamicCancellation(
    appID: String,
    cacheURL: URL,
    timestamp: @escaping @Sendable () -> InstantTimestamp
  ) async throws -> ValidationEvidenceRow<PlatformAdapterValidationDetails> {
    let firstRoom = InstantRoomHandle(type: "validation", id: "first-live-room")
    let secondRoom = InstantRoomHandle(type: "validation", id: "second-live-room")
    let recorder = PlatformAdapterLiveWrapperLifecycleRecorder(
      appID: appID,
      updatedAt: timestamp(),
      delayFirstObservation: true
    )
    let client = liveWrapperLifecycleClient(recorder)
    let presence = RoomPresence(room: firstRoom)
    let firstTask = Task {
      let presence = presence
      try await presence.task(using: client)
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter live wrapper first observation"
    ) {
      let counts = await recorder.counts()
      return counts.observationCount == 1
    }

    let secondTask = Task {
      let presence = presence
      try await presence.task(room: secondRoom, using: client)
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter live wrapper replacement"
    ) {
      let counts = await recorder.counts()
      return counts.observationCount == 2
        && presence.wrappedValue.map(\.userID) == ["presence-second-live-room"]
    }

    await recorder.releaseFirstObservation()
    do {
      try await firstTask.value
      throw validationFailure(
        operation: "validate platform adapter live wrapper replacement",
        message: "Expected replacing an active live wrapper task to cancel the first subscription."
      )
    } catch is CancellationError {
    }

    secondTask.cancel()
    do {
      try await secondTask.value
      throw validationFailure(
        operation: "validate platform adapter live wrapper cancellation",
        message: "Expected the replacement live wrapper task to surface cancellation."
      )
    } catch is CancellationError {
    }

    try await waitForLifecycle(
      operation: "wait for platform adapter live wrapper final cancellation"
    ) {
      let counts = await recorder.counts()
      return counts.terminationCount >= 2
    }

    let counts = await recorder.counts()
    let observedRooms = await recorder.observedRooms()
    let cancellationTerminated = counts.terminationCount >= 2
    guard
      observedRooms == [firstRoom, secondRoom],
      counts.observationCount == 2,
      cancellationTerminated,
      presence.wrappedValue.map(\.userID) == ["presence-second-live-room"],
      presence.loadError == nil,
      presence.isLoading == false
    else {
      throw validationFailure(
        operation: "validate platform adapter live wrapper lifecycle",
        message:
          "Expected a dynamic @RoomPresence task to replace its active subscription cleanly."
      )
    }

    return evidenceRow(
      event: "live-wrapper-dynamic-cancellation",
      appID: appID,
      timestamp: timestamp,
      details: PlatformAdapterValidationDetails(
        cachePath: cacheURL.path,
        adapter: "@RoomPresence(dynamic cancellation)",
        roomMemberIDs: presence.wrappedValue.map(\.userID),
        observationCount: counts.observationCount,
        isLoading: presence.isLoading,
        cancellationTerminated: cancellationTerminated
      )
    )
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

  private static func todoSnapshot(
    id: String,
    title: String,
    isCompleted: Bool,
    createdAt: Date
  ) -> InstantEntitySnapshot {
    InstantEntitySnapshot(
      id: id,
      namespace: PlatformAdapterTodo.instantNamespace,
      values: [
        "title": .one(.string(title)),
        "isCompleted": .one(.bool(isCompleted)),
        "createdAt": .one(.date(createdAt)),
      ]
    )
  }

  private static func lifecycleClient(
    _ recorder: PlatformAdapterLifecycleRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { plan in
        try await recorder.query(plan: plan)
      },
      observe: { plan in
        await recorder.observe(plan: plan)
      },
      pendingMutations: { [] },
      localID: { name in "adapter-lifecycle-\(name)" }
    )
  }

  private static func infiniteQueryLifecycleClient(
    _ recorder: PlatformAdapterInfiniteQueryLifecycleRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      subscribeInfiniteQuery: { plan in
        await recorder.subscribe(plan: plan)
      },
      pendingMutations: { [] },
      localID: { name in "adapter-infinite-lifecycle-\(name)" }
    )
  }

  private static func infiniteQueryLoadClient(
    _ recorder: PlatformAdapterInfiniteQueryLoadRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      infiniteQueryInitialSnapshot: { plan in
        try await recorder.initialSnapshot(plan: plan)
      },
      pendingMutations: { [] },
      localID: { name in "adapter-infinite-load-\(name)" }
    )
  }

  private static func liveWrapperLifecycleClient(
    _ recorder: PlatformAdapterLiveWrapperLifecycleRecorder
  ) -> InstantSwiftDataClient {
    InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { continuation in continuation.finish() } },
      pendingMutations: { [] },
      localID: { name in "adapter-live-wrapper-\(name)" },
      roomPresence: { room in
        await recorder.roomPresence(room: room)
      },
      observeRoomPresence: { room in
        await recorder.observeRoomPresence(room: room)
      }
    )
  }

  private static func waitForLifecycle(
    operation: String,
    until condition: @escaping @Sendable () async -> Bool
  ) async throws {
    for _ in 0..<100 {
      if await condition() {
        return
      }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw validationFailure(
      operation: operation,
      message: "Timed out waiting for platform adapter lifecycle evidence."
    )
  }

  private static func validationFailure(
    operation: String,
    message: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      message: message,
      recovery:
        "Inspect public adapter wrapper dynamic query, nil query, error, and cancellation handling."
    )
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

private actor PlatformAdapterLifecycleRecorder {
  private var queryResults: [[InstantEntitySnapshot]]
  private var fallbackError: InstantError?
  private var queryCount = 0
  private var observationCount = 0
  private var terminationCount = 0
  private var plans: [InstantQueryPlan] = []

  init(
    queryResults: [[InstantEntitySnapshot]] = [],
    fallbackError: InstantError? = nil
  ) {
    self.queryResults = queryResults
    self.fallbackError = fallbackError
  }

  func query(plan: InstantQueryPlan) throws -> [InstantEntitySnapshot] {
    queryCount += 1
    plans.append(plan)
    if !queryResults.isEmpty {
      return queryResults.removeFirst()
    }
    if let fallbackError {
      throw fallbackError
    }
    return []
  }

  func observe(plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
    observationCount += 1
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      continuation.yield(InstantQueryEmission(queryID: plan.id, sequence: 0, values: []))
      continuation.onTermination = { @Sendable _ in
        Task {
          await self.recordTermination()
        }
      }
    }
  }

  func counts() -> (queryCount: Int, observationCount: Int, terminationCount: Int) {
    (queryCount, observationCount, terminationCount)
  }

  func queryPlans() -> [InstantQueryPlan] {
    plans
  }

  private func recordTermination() {
    terminationCount += 1
  }
}

private actor PlatformAdapterInfiniteQueryLifecycleRecorder {
  private var subscribeCount = 0
  private var firstLoadNextPageCount = 0
  private var secondLoadNextPageCount = 0
  private var firstUnsubscribeCount = 0
  private var secondUnsubscribeCount = 0
  private var firstContinuation: CheckedContinuation<InstantInfiniteQuerySubscription, Never>?
  private let firstStream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
    bufferingPolicy: .bufferingNewest(1)
  )
  private let secondStream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
    bufferingPolicy: .bufferingNewest(1)
  )

  deinit {
    firstStream.continuation.finish()
    secondStream.continuation.finish()
  }

  func subscribe(plan: InstantQueryPlan) async -> InstantInfiniteQuerySubscription {
    subscribeCount += 1
    switch subscribeCount {
    case 1:
      return await withCheckedContinuation { continuation in
        firstContinuation = continuation
      }
    default:
      return subscription(name: .second)
    }
  }

  func releaseFirstSubscription() {
    firstContinuation?.resume(returning: subscription(name: .first))
    firstContinuation = nil
  }

  func yieldSecond(_ snapshot: InstantInfiniteQuerySnapshot) {
    secondStream.continuation.yield(snapshot)
  }

  func counts() -> (
    subscribeCount: Int,
    firstLoadNextPageCount: Int,
    secondLoadNextPageCount: Int,
    firstUnsubscribeCount: Int,
    secondUnsubscribeCount: Int
  ) {
    (
      subscribeCount,
      firstLoadNextPageCount,
      secondLoadNextPageCount,
      firstUnsubscribeCount,
      secondUnsubscribeCount
    )
  }

  private func subscription(name: SubscriptionName) -> InstantInfiniteQuerySubscription {
    InstantInfiniteQuerySubscription(
      snapshots: name == .first ? firstStream.stream : secondStream.stream,
      loadNextPage: {
        Task {
          await self.recordLoadNextPage(name: name)
        }
      },
      unsubscribe: {
        Task {
          await self.recordUnsubscribe(name: name)
        }
      }
    )
  }

  private func recordLoadNextPage(name: SubscriptionName) {
    switch name {
    case .first:
      firstLoadNextPageCount += 1
    case .second:
      secondLoadNextPageCount += 1
    }
  }

  private func recordUnsubscribe(name: SubscriptionName) {
    switch name {
    case .first:
      firstUnsubscribeCount += 1
    case .second:
      secondUnsubscribeCount += 1
    }
  }

  private enum SubscriptionName: Sendable {
    case first
    case second
  }
}

private actor PlatformAdapterInfiniteQueryLoadRecorder {
  private let staleSnapshot: InstantInfiniteQuerySnapshot
  private let freshSnapshot: InstantInfiniteQuerySnapshot
  private let clearedStaleSnapshot: InstantInfiniteQuerySnapshot
  private var count = 0
  private var capturedPlans: [InstantQueryPlan] = []
  private var pendingContinuations: [Int: CheckedContinuation<Void, Never>] = [:]

  init(
    staleSnapshot: InstantInfiniteQuerySnapshot,
    freshSnapshot: InstantInfiniteQuerySnapshot,
    clearedStaleSnapshot: InstantInfiniteQuerySnapshot
  ) {
    self.staleSnapshot = staleSnapshot
    self.freshSnapshot = freshSnapshot
    self.clearedStaleSnapshot = clearedStaleSnapshot
  }

  func initialSnapshot(plan: InstantQueryPlan) async throws -> InstantInfiniteQuerySnapshot {
    count += 1
    capturedPlans.append(plan)
    switch count {
    case 1:
      await waitForRelease(count)
      return staleSnapshot
    case 2:
      return freshSnapshot
    case 3:
      await waitForRelease(count)
      return clearedStaleSnapshot
    default:
      return freshSnapshot
    }
  }

  func loadCount() -> Int {
    count
  }

  func plans() -> [InstantQueryPlan] {
    capturedPlans
  }

  func releasePendingLoad(_ count: Int) {
    pendingContinuations.removeValue(forKey: count)?.resume()
  }

  private func waitForRelease(_ count: Int) async {
    await withCheckedContinuation { continuation in
      pendingContinuations[count] = continuation
    }
  }
}

private actor PlatformAdapterLiveWrapperLifecycleRecorder {
  private let appID: String
  private let updatedAt: InstantTimestamp
  private let delayFirstObservation: Bool
  private var observationCount = 0
  private var terminationCount = 0
  private var rooms: [InstantRoomHandle] = []
  private var didReleaseFirstObservation = false
  private var firstObservationContinuations: [CheckedContinuation<Void, Never>] = []

  init(
    appID: String,
    updatedAt: InstantTimestamp,
    delayFirstObservation: Bool = false
  ) {
    self.appID = appID
    self.updatedAt = updatedAt
    self.delayFirstObservation = delayFirstObservation
  }

  func roomPresence(room: InstantRoomHandle) -> [InstantRoomPresenceMember] {
    [member(room: room)]
  }

  func observeRoomPresence(room: InstantRoomHandle) async -> AsyncStream<[InstantRoomPresenceMember]> {
    observationCount += 1
    rooms.append(room)
    if delayFirstObservation, room.id == "first-live-room" {
      await waitForFirstObservationRelease()
    }
    let members = [member(room: room)]
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      continuation.yield(members)
      continuation.onTermination = { @Sendable _ in
        Task {
          await self.recordTermination()
        }
      }
    }
  }

  func counts() -> (observationCount: Int, terminationCount: Int) {
    (observationCount, terminationCount)
  }

  func observedRooms() -> [InstantRoomHandle] {
    rooms
  }

  func releaseFirstObservation() {
    didReleaseFirstObservation = true
    let continuations = firstObservationContinuations
    firstObservationContinuations.removeAll()
    for continuation in continuations {
      continuation.resume()
    }
  }

  private func waitForFirstObservationRelease() async {
    guard !didReleaseFirstObservation else { return }
    await withCheckedContinuation { continuation in
      firstObservationContinuations.append(continuation)
    }
  }

  private func recordTermination() {
    terminationCount += 1
  }

  private func member(room: InstantRoomHandle) -> InstantRoomPresenceMember {
    InstantRoomPresenceMember(
      appID: appID,
      room: room,
      userID: "presence-\(room.id)",
      values: ["room": .string(room.id)],
      updatedAt: updatedAt
    )
  }
}

private struct PlatformAdapterTodoFacts: Equatable, Sendable {
  var todos: [PlatformAdapterTodo] = []
  var count = 0
}

private struct PlatformAdapterTodoFactsRequest: InstantFetchKeyRequest {
  var rowsQuery: InstantEntityQuery<PlatformAdapterTodo>
  var countQuery: InstantEntityQuery<PlatformAdapterTodo>

  func fetch(using client: InstantSwiftDataClient) async throws -> PlatformAdapterTodoFacts {
    let todos = try await client.query(rowsQuery)
    let count = try await client.query(countQuery).count
    return PlatformAdapterTodoFacts(todos: todos, count: count)
  }

  func subscribe(
    using client: InstantSwiftDataClient
  ) async throws -> FetchSubscription<PlatformAdapterTodoFacts> {
    let subscription = await client.subscribe(rowsQuery)
    let stream = AsyncThrowingStream<PlatformAdapterTodoFacts, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      do {
        for try await todos in subscription {
          try Task.checkCancellation()
          stream.continuation.yield(
            PlatformAdapterTodoFacts(todos: todos, count: todos.count)
          )
        }
        stream.continuation.finish()
      } catch {
        stream.continuation.finish(throwing: error)
      }
    }
    stream.continuation.onTermination = { @Sendable _ in
      task.cancel()
      subscription.cancel()
    }
    return FetchSubscription<PlatformAdapterTodoFacts>(stream: stream.stream) {
      task.cancel()
      subscription.cancel()
      stream.continuation.finish()
    }
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
