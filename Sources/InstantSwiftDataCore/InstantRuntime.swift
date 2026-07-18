import Foundation

public struct InstantRuntimeConfiguration: Sendable {
  public static let defaultAPIURI = URL(string: "https://api.instantdb.com")!
  public static let defaultWebSocketURI = URL(
    string: "wss://api.instantdb.com/runtime/session"
  )!

  public var appID: String
  public var apiURI: URL
  public var websocketURI: URL
  public var firstPartyURL: URL?
  public var persistenceURL: URL
  public var initialAttributes: [InstantAttribute]
  public var now: @Sendable () -> InstantTimestamp
  public var makeID: @Sendable () -> String
  public var refreshTokenVerifier: InstantRefreshTokenVerifier
  public var magicCodeExchange: InstantMagicCodeExchange
  public var idTokenExchange: InstantIDTokenExchange
  public var oauthExchange: InstantOAuthExchange
  public var authTokenInvalidator: InstantAuthTokenInvalidator
  public var mutationTransport: InstantMutationTransportClient
  public var liveTransport: InstantLiveTransportClient?
  public var userCookieSyncClient: InstantUserCookieSyncClient
  public var platformAppClient: InstantPlatformAppClient
  public var appBuilderCodeGenerator: AppBuilderCodeGeneratorClient
  var actorHopRecorder: InstantActorHopRecorder?
  var liveReconnectSleep: @Sendable (UInt64) async throws -> Void = { milliseconds in
    try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
  }

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    platformAppClient: InstantPlatformAppClient = .local,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient = .local
  ) {
    self.init(
      appID: appID,
      apiURI: Self.defaultAPIURI,
      websocketURI: Self.defaultWebSocketURI,
      persistenceURL: persistenceURL,
      initialAttributes: initialAttributes,
      now: now,
      makeID: makeID,
      refreshTokenVerifier: refreshTokenVerifier,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      mutationTransport: .local,
      liveTransport: nil,
      platformAppClient: platformAppClient,
      appBuilderCodeGenerator: appBuilderCodeGenerator
    )
  }

  public init(
    appID: String,
    apiURI: URL = Self.defaultAPIURI,
    websocketURI: URL = Self.defaultWebSocketURI,
    firstPartyURL: URL? = nil,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    mutationTransport: InstantMutationTransportClient = .local,
    liveTransport: InstantLiveTransportClient? = nil,
    userCookieSyncClient: InstantUserCookieSyncClient = .live,
    platformAppClient: InstantPlatformAppClient = .local,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient = .local
  ) {
    self.appID = appID
    self.apiURI = apiURI
    self.websocketURI = websocketURI
    self.firstPartyURL = firstPartyURL
    self.persistenceURL = persistenceURL
    self.initialAttributes = initialAttributes
    self.now = now
    self.makeID = makeID
    self.refreshTokenVerifier = refreshTokenVerifier
    self.magicCodeExchange = magicCodeExchange
    self.idTokenExchange = idTokenExchange
    self.oauthExchange = oauthExchange
    self.authTokenInvalidator = authTokenInvalidator
    self.mutationTransport = mutationTransport
    self.liveTransport = liveTransport
    self.userCookieSyncClient = userCookieSyncClient
    self.platformAppClient = platformAppClient
    self.appBuilderCodeGenerator = appBuilderCodeGenerator
    self.actorHopRecorder = nil
  }

  public static func isValidAPIURI(_ url: URL) -> Bool {
    isValidEndpointURI(url, allowedSchemes: ["http", "https"])
  }

  public static func isValidWebSocketURI(_ url: URL) -> Bool {
    isValidEndpointURI(url, allowedSchemes: ["ws", "wss"])
  }

  private static func isValidEndpointURI(_ url: URL, allowedSchemes: Set<String>) -> Bool {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(),
      allowedSchemes.contains(scheme),
      components.host?.isEmpty == false,
      components.query == nil,
      components.fragment == nil
    else {
      return false
    }
    return true
  }
}

private actor InstantAuthSessionObservers {
  private var continuations: [UUID: AsyncStream<InstantAuthSession?>.Continuation] = [:]

  func observe(current session: InstantAuthSession?) -> AsyncStream<InstantAuthSession?> {
    let id = UUID()
    let stream = AsyncStream<InstantAuthSession?>.makeStream(bufferingPolicy: .bufferingNewest(1))
    continuations[id] = stream.continuation
    stream.continuation.yield(session)
    stream.continuation.onTermination = { @Sendable _ in
      Task { await self.cancel(id: id) }
    }
    return stream.stream
  }

  func yield(_ session: InstantAuthSession?) {
    for continuation in continuations.values {
      continuation.yield(session)
    }
  }

  private func cancel(id: UUID) {
    continuations[id] = nil
  }
}

// SAFETY: upload cancellation state is protected by `lock`.
private final class InstantFileUploadProgressCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var isCancelled = false

  func cancel() {
    lock.lock()
    defer { lock.unlock() }
    isCancelled = true
  }

  func check() throws {
    lock.lock()
    defer { lock.unlock() }
    if isCancelled {
      throw CancellationError()
    }
  }
}

private actor InstantRuntimeLiveRoomPresenceState {
  private var sessionsByRoom: [InstantRoomHandle: JSONValue] = [:]

  func replace(
    room: InstantRoomHandle,
    sessions: [String: InstantLiveJSONValue],
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantRoomPresenceMember] {
    var value = JSONValue.object(sessions.mapValues(\.jsonValue))
    if let excludingSessionID {
      value.dissocIn([.key(excludingSessionID)])
    }
    sessionsByRoom[room] = value
    return members(
      room: room,
      sessions: value,
      excludingSessionID: excludingSessionID,
      appID: appID,
      updatedAt: updatedAt
    )
  }

  func patch(
    room: InstantRoomHandle,
    edits: [InstantLiveJSONValue],
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) throws -> [InstantRoomPresenceMember] {
    var sessions = sessionsByRoom[room] ?? .object([:])
    for (index, edit) in edits.enumerated() {
      guard case let .array(parts) = edit,
        parts.count >= 2,
        case let .array(rawPath) = parts[0],
        let operation = parts[1].stringValue
      else {
        throw malformedPatch(index: index)
      }
      let path = try rawPath.map { component -> JSONValuePathComponent in
        guard let key = component.stringValue else {
          throw malformedPatch(index: index)
        }
        return .key(key)
      }
      switch operation {
      case "+":
        guard parts.count == 3 else { throw malformedPatch(index: index) }
        sessions.insertIn(path, parts[2].jsonValue)
      case "r":
        guard parts.count == 3 else { throw malformedPatch(index: index) }
        sessions.assocIn(path, parts[2].jsonValue)
      case "-":
        guard parts.count == 2 else { throw malformedPatch(index: index) }
        sessions.dissocIn(path)
      default:
        throw malformedPatch(index: index)
      }
    }
    if let excludingSessionID {
      sessions.dissocIn([.key(excludingSessionID)])
    }
    sessionsByRoom[room] = sessions
    return members(
      room: room,
      sessions: sessions,
      excludingSessionID: excludingSessionID,
      appID: appID,
      updatedAt: updatedAt
    )
  }

  func current(
    room: InstantRoomHandle,
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantRoomPresenceMember] {
    members(
      room: room,
      sessions: sessionsByRoom[room] ?? .object([:]),
      excludingSessionID: excludingSessionID,
      appID: appID,
      updatedAt: updatedAt
    )
  }

  func remove(room: InstantRoomHandle) {
    sessionsByRoom[room] = nil
  }

  private func members(
    room: InstantRoomHandle,
    sessions: JSONValue,
    excludingSessionID: String?,
    appID: String,
    updatedAt: InstantTimestamp
  ) -> [InstantRoomPresenceMember] {
    guard case let .object(sessionValues) = sessions else { return [] }
    return sessionValues.compactMap { sessionID, rawEnvelope in
      guard sessionID != excludingSessionID,
        case let .object(envelope) = rawEnvelope,
        case let .object(values)? = envelope["data"]
      else {
        return nil
      }
      let peerID: String
      if case let .string(value)? = envelope["peer-id"] {
        peerID = value
      } else {
        peerID = sessionID
      }
      let userID: String
      if case let .object(user)? = envelope["user"],
        case let .string(value)? = user["id"]
      {
        userID = value
      } else {
        userID = peerID
      }
      return InstantRoomPresenceMember(
        appID: appID,
        room: room,
        userID: userID,
        values: values,
        updatedAt: updatedAt
      )
    }
    .sorted { $0.id < $1.id }
  }

  private func malformedPatch(index: Int) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "apply Instant live presence patch",
      path: "edits[\(index)]",
      message: "Instant patch-presence contained a malformed edit.",
      recovery: "Inspect the canonical Instant patch-presence payload."
    )
  }
}

private actor InstantRuntimeLiveSession {
  private struct RegisteredQuery: Sendable {
    var query: InstantLiveJSONValue
    var observerCount: Int
  }

  private struct QueuedBroadcast: Sendable {
    var topic: String
    var payload: JSONValue
  }

  private struct RegisteredRoom: Sendable {
    var room: InstantRoomHandle
    var presence: [String: JSONValue]?
    var queuedBroadcasts: [QueuedBroadcast] = []
    var isConnected = false
  }

  private struct RegisteredStreamReader: Sendable {
    var reader: InstantLiveStreamReaderState
    var observerCount: Int
  }

  private var session: InstantLiveWebSocketSession?
  private var receiverTask: Task<Void, Never>?
  private var registeredQueries: [String: RegisteredQuery] = [:]
  private var serverAttributes: [InstantLiveJSONValue] = []
  private var inFlightMutationIDs: Set<String> = []
  private var registeredRooms: [InstantRoomHandle: RegisteredRoom] = [:]
  private var registeredStreamReaders: [String: RegisteredStreamReader] = [:]
  private var makeID: (@Sendable () -> String)?
  private var sessionID: String?
  private var isOpened = false
  private var generation = 0

  var isOpen: Bool {
    isOpened
  }

  var currentSessionID: String? {
    sessionID
  }

  func open(
    request: InstantLiveSessionRequest,
    transport: InstantLiveTransportClient,
    makeID: @escaping @Sendable () -> String
  ) async throws {
    generation += 1
    receiverTask?.cancel()
    receiverTask = nil
    if let session {
      await session.close()
    }
    session = nil
    sessionID = nil
    serverAttributes = []
    inFlightMutationIDs.removeAll()
    for room in Array(registeredRooms.keys) {
      registeredRooms[room]?.isConnected = false
    }
    isOpened = false
    let opened = try await transport.connect(request)
    do {
      try await instantLiveWithTimeout(
        operation: "open Instant live session",
        timeoutMilliseconds: 10_000
      ) {
        try await opened.send(request.initMessage(clientEventID: makeID()))
      }
      let event = try await instantLiveWithTimeout(
        operation: "open Instant live session",
        timeoutMilliseconds: 10_000
      ) {
        InstantLiveServerEvent(message: try await opened.receive())
      }
      switch event {
      case let .initOK(initOK):
        guard !initOK.sessionID.isEmpty else {
          throw InstantError(
            code: .networkFailed,
            operation: "open Instant live session",
            message: "Instant live init-ok did not include a session-id.",
            recovery: "Inspect the Instant runtime WebSocket init response."
          )
        }
        self.session = opened
        self.serverAttributes = initOK.attrs
        self.makeID = makeID
        self.sessionID = initOK.sessionID
        self.isOpened = true

      case let .error(error):
        throw InstantError(
          code: .networkFailed,
          operation: "open Instant live session",
          serverEventID: error.clientEventID,
          message: error.message,
          recovery: "Inspect the Instant runtime WebSocket init request and credentials."
        )

      default:
        throw InstantError(
          code: .networkFailed,
          operation: "open Instant live session",
          message: "Expected init-ok from Instant live transport, received \(event.op).",
          recovery: "Inspect the Instant runtime WebSocket protocol handling."
        )
      }
      for room in registeredRooms.keys.sorted(by: Self.roomOrder) {
        guard let registration = registeredRooms[room] else { continue }
        try await send(
          .joinRoom(
            registration.room,
            presence: registration.presence,
            clientEventID: makeID()
          ),
          through: opened
        )
      }
      for key in registeredQueries.keys.sorted() {
        guard let registration = registeredQueries[key] else { continue }
        try await send(
          .addQuery(registration.query, clientEventID: makeID()),
          through: opened
        )
      }
      for key in registeredStreamReaders.keys.sorted() {
        guard let registration = registeredStreamReaders[key] else { continue }
        try await registration.reader.reconnect(clientEventID: makeID()) { message in
          try await self.send(message, through: opened)
        }
      }
    } catch {
      await opened.close()
      session = nil
      sessionID = nil
      serverAttributes = []
      isOpened = false
      throw error
    }
  }

  func startReceiving(
    onEvent: @escaping @Sendable (
      InstantLiveServerEvent,
      [InstantLiveJSONValue]
    ) async throws -> Void,
    onFailure: @escaping @Sendable (Error) async -> Void
  ) {
    guard receiverTask == nil, let session, isOpened else { return }
    let generation = generation
    receiverTask = Task { [weak self] in
      do {
        while !Task.isCancelled {
          let message = try await session.receive()
          try Task.checkCancellation()
          let event = InstantLiveServerEvent(message: message)
          guard let attributes = try await self?.record(event, generation: generation) else {
            return
          }
          try await onEvent(event, attributes)
        }
      } catch is CancellationError {
        await self?.receiverEnded(
          generation: generation,
          session: session,
          failure: nil,
          onFailure: onFailure
        )
      } catch {
        await self?.receiverEnded(
          generation: generation,
          session: session,
          failure: error,
          onFailure: onFailure
        )
      }
    }
  }

  func registerQuery(
    _ query: InstantLiveJSONValue,
    key: String,
    clientEventID: String
  ) async throws {
    if var registration = registeredQueries[key] {
      registration.observerCount += 1
      registeredQueries[key] = registration
      return
    }
    registeredQueries[key] = RegisteredQuery(query: query, observerCount: 1)
    guard let session, isOpened else { return }
    try await send(.addQuery(query, clientEventID: clientEventID), through: session)
  }

  func unregisterQuery(key: String, clientEventID: String) async throws {
    guard var registration = registeredQueries[key] else { return }
    if registration.observerCount > 1 {
      registration.observerCount -= 1
      registeredQueries[key] = registration
      return
    }
    registeredQueries[key] = nil
    guard let session, isOpened else { return }
    try await send(
      .removeQuery(registration.query, clientEventID: clientEventID),
      through: session
    )
  }

  func refreshRegisteredQueries() async throws {
    guard let session, isOpened, let makeID else { return }
    for key in registeredQueries.keys.sorted() {
      guard let registration = registeredQueries[key] else { continue }
      try await send(
        .removeQuery(registration.query, clientEventID: makeID()),
        through: session
      )
      try await send(
        .addQuery(registration.query, clientEventID: makeID()),
        through: session
      )
    }
  }

  func registerStreamReader(
    key: String,
    clientID: String? = nil,
    streamID: String? = nil,
    initialByteOffset: Int64,
    ruleParams: InstantLiveJSONValue? = nil,
    clientEventID: String
  ) async throws {
    if var registration = registeredStreamReaders[key] {
      registration.observerCount += 1
      registeredStreamReaders[key] = registration
      return
    }
    let reader = try InstantLiveStreamReaderState(
      clientID: clientID,
      streamID: streamID,
      initialByteOffset: initialByteOffset,
      ruleParams: ruleParams
    )
    registeredStreamReaders[key] = RegisteredStreamReader(reader: reader, observerCount: 1)
    guard let session, isOpened else { return }
    let message = try await reader.subscribeMessage(clientEventID: clientEventID)
    try await send(message, through: session)
    await reader.recordSubscriptionEventID(clientEventID)
  }

  func unregisterStreamReader(key: String, clientEventID: String) async throws {
    guard var registration = registeredStreamReaders[key] else { return }
    if registration.observerCount > 1 {
      registration.observerCount -= 1
      registeredStreamReaders[key] = registration
      return
    }
    registeredStreamReaders[key] = nil
    guard let subscriptionEventID = await registration.reader.subscriptionEventID,
      let session,
      isOpened
    else {
      return
    }
    try await send(
      .unsubscribeStream(
        subscriptionEventID: subscriptionEventID,
        clientEventID: clientEventID
      ),
      through: session
    )
  }

  func takeDeliveredStreamAppend(clientEventID: String?) async
    -> InstantLiveStreamAppend?
  {
    guard let clientEventID else { return nil }
    for key in registeredStreamReaders.keys.sorted() {
      guard let registration = registeredStreamReaders[key],
        await registration.reader.subscriptionEventID == clientEventID,
        let append = await registration.reader.takeDeliveredAppend()
      else {
        continue
      }
      return append
    }
    return nil
  }

  func recordDeliveredStreamAppend(_ append: InstantLiveStreamAppend) async {
    guard let clientEventID = append.clientEventID else { return }
    let deliveredByteCount = Int64(append.content?.utf8.count ?? 0)
      + append.files.reduce(Int64(0)) { $0 + $1.size }
    for key in registeredStreamReaders.keys.sorted() {
      guard let registration = registeredStreamReaders[key],
        await registration.reader.subscriptionEventID == clientEventID
      else {
        continue
      }
      await registration.reader.recordSeenOffset(append.offset + deliveredByteCount)
      return
    }
  }

  func sendMutations(_ mutations: [InstantTransportMutation]) async throws {
    guard let session, isOpened else { return }
    for mutation in mutations.sorted(by: Self.mutationOrder) where mutation.status == .pending {
      guard inFlightMutationIDs.insert(mutation.mutationID).inserted else { continue }
      do {
        let txSteps = try InstantLiveMutationEncoder.resolveAttributeIDs(
          in: mutation.txSteps,
          attrs: serverAttributes
        )
        try await send(
          try .transact(txSteps, clientEventID: mutation.mutationID),
          through: session
        )
      } catch {
        inFlightMutationIDs.remove(mutation.mutationID)
        throw error
      }
    }
  }

  func joinRoom(
    _ room: InstantRoomHandle,
    clientEventID: String
  ) async throws {
    guard registeredRooms[room] == nil else { return }
    registeredRooms[room] = RegisteredRoom(room: room)
    guard let session, isOpened else { return }
    try await send(.joinRoom(room, clientEventID: clientEventID), through: session)
  }

  func leaveRoom(
    _ room: InstantRoomHandle,
    clientEventID: String
  ) async throws {
    guard registeredRooms.removeValue(forKey: room) != nil else { return }
    guard let session, isOpened else { return }
    try await send(.leaveRoom(room, clientEventID: clientEventID), through: session)
  }

  func setPresence(
    room: InstantRoomHandle,
    values: [String: JSONValue],
    clientEventID: String
  ) async throws {
    guard var registration = registeredRooms[room] else { return }
    registration.presence = values
    registeredRooms[room] = registration
    guard registration.isConnected, let session, isOpened else { return }
    try await send(
      .setPresence(room: room, values: values, clientEventID: clientEventID),
      through: session
    )
  }

  func publishTopic(
    room: InstantRoomHandle,
    topic: String,
    payload: JSONValue,
    clientEventID: String
  ) async throws {
    guard var registration = registeredRooms[room] else { return }
    guard registration.isConnected, let session, isOpened else {
      registration.queuedBroadcasts.append(
        QueuedBroadcast(topic: topic, payload: payload)
      )
      registeredRooms[room] = registration
      return
    }
    try await send(
      .clientBroadcast(
        room: room,
        topic: topic,
        payload: payload,
        clientEventID: clientEventID
      ),
      through: session
    )
  }

  func roomHandle(id: String) -> InstantRoomHandle? {
    registeredRooms.keys.first { $0.id == id }
  }

  private func record(
    _ event: InstantLiveServerEvent,
    generation: Int
  ) async throws -> [InstantLiveJSONValue]? {
    guard generation == self.generation else { return nil }
    switch event {
    case let .refreshOK(refreshOK) where !refreshOK.attrs.isEmpty:
      serverAttributes = refreshOK.attrs
    case let .transactOK(transactOK):
      if let clientEventID = transactOK.clientEventID {
        inFlightMutationIDs.remove(clientEventID)
      }
    case let .error(error):
      if let clientEventID = error.clientEventID {
        inFlightMutationIDs.remove(clientEventID)
      }
    case let .joinRoomOK(room):
      try await recordRoomEvent(op: room.op, roomID: room.roomID)
    case let .leaveRoomOK(room):
      try await recordRoomEvent(op: room.op, roomID: room.roomID)
    case let .refreshPresence(refresh):
      try await recordRoomEvent(op: "refresh-presence", roomID: refresh.roomID)
    case let .patchPresence(patch):
      try await recordRoomEvent(op: "patch-presence", roomID: patch.roomID)
    case let .serverBroadcast(broadcast):
      try await recordRoomEvent(op: "server-broadcast", roomID: broadcast.roomID)
    case let .streamAppend(append):
      for key in registeredStreamReaders.keys.sorted() {
        guard let registration = registeredStreamReaders[key] else { continue }
        switch await registration.reader.receive(append) {
        case .ignored:
          continue
        case .requestReconnect:
          throw InstantError(
            code: .networkFailed,
            operation: "retry Instant live stream append",
            serverEventID: append.clientEventID,
            message: append.error ?? "Instant requested a stream reconnect.",
            recovery: "Reconnect the live session and resubscribe from the last seen byte offset."
          )
        case .deliver, .failure:
          break
        }
      }
    default:
      break
    }
    return serverAttributes
  }

  private static func mutationOrder(
    _ lhs: InstantTransportMutation,
    _ rhs: InstantTransportMutation
  ) -> Bool {
    if lhs.createdAt == rhs.createdAt {
      return lhs.mutationID < rhs.mutationID
    }
    return lhs.createdAt < rhs.createdAt
  }

  private func send(
    _ message: InstantLiveMessage,
    through session: InstantLiveWebSocketSession
  ) async throws {
    try await instantLiveWithTimeout(
      operation: "send Instant live session message",
      timeoutMilliseconds: 10_000
    ) {
      try await session.send(message)
    }
  }

  private func receiverEnded(
    generation: Int,
    session: InstantLiveWebSocketSession,
    failure: Error?,
    onFailure: @escaping @Sendable (Error) async -> Void
  ) async {
    guard generation == self.generation else { return }
    self.session = nil
    sessionID = nil
    receiverTask = nil
    isOpened = false
    for room in Array(registeredRooms.keys) {
      registeredRooms[room]?.isConnected = false
    }
    await session.close()
    if let failure {
      await onFailure(failure)
    }
  }

  func close() async {
    generation += 1
    let session = session
    let receiverTask = receiverTask
    self.session = nil
    sessionID = nil
    self.receiverTask = nil
    serverAttributes = []
    inFlightMutationIDs.removeAll()
    for room in Array(registeredRooms.keys) {
      registeredRooms[room]?.isConnected = false
    }
    isOpened = false
    receiverTask?.cancel()
    if let session {
      await session.close()
    }
  }

  private func recordRoomEvent(op: String, roomID: String) async throws {
    guard let room = registeredRooms.keys.first(where: { $0.id == roomID }),
      var registration = registeredRooms[room]
    else {
      return
    }
    switch op {
    case "join-room-ok":
      registration.isConnected = true
      let queuedBroadcasts = registration.queuedBroadcasts
      registration.queuedBroadcasts = []
      registeredRooms[room] = registration
      guard let session, isOpened, let makeID else { return }
      if let presence = registration.presence {
        try await send(
          .setPresence(room: room, values: presence, clientEventID: makeID()),
          through: session
        )
      }
      for broadcast in queuedBroadcasts {
        try await send(
          .clientBroadcast(
            room: room,
            topic: broadcast.topic,
            payload: broadcast.payload,
            clientEventID: makeID()
          ),
          through: session
        )
      }

    case "refresh-presence", "patch-presence", "server-broadcast":
      registration.isConnected = true
      registeredRooms[room] = registration

    case "leave-room-ok":
      registration.isConnected = false
      registeredRooms[room] = registration

    default:
      break
    }
  }

  private static func roomOrder(_ lhs: InstantRoomHandle, _ rhs: InstantRoomHandle) -> Bool {
    if lhs.type == rhs.type {
      return lhs.id < rhs.id
    }
    return lhs.type < rhs.type
  }
}

private actor InstantRuntimeReconnectController {
  private var task: Task<Void, Never>?
  private var generation = 0
  private var restartRequested = false

  func start(
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    reconnect: @escaping @Sendable () async throws -> Void
  ) {
    guard task == nil else {
      restartRequested = true
      return
    }

    generation += 1
    let generation = generation
    task = Task { [weak self] in
      var attempt: UInt64 = 0
      while !Task.isCancelled {
        let delay = min(attempt * 1_000, 10_000)
        do {
          try await sleep(delay)
          try Task.checkCancellation()
          try await reconnect()
          await self?.finish(
            generation: generation,
            sleep: sleep,
            reconnect: reconnect
          )
          return
        } catch is CancellationError {
          await self?.cancelled(generation: generation)
          return
        } catch {
          attempt += 1
        }
      }
      await self?.cancelled(generation: generation)
    }
  }

  func cancel() {
    generation += 1
    restartRequested = false
    task?.cancel()
    task = nil
  }

  private func finish(
    generation: Int,
    sleep: @escaping @Sendable (UInt64) async throws -> Void,
    reconnect: @escaping @Sendable () async throws -> Void
  ) {
    guard generation == self.generation else { return }
    task = nil
    guard restartRequested else { return }
    restartRequested = false
    start(sleep: sleep, reconnect: reconnect)
  }

  private func cancelled(generation: Int) {
    guard generation == self.generation else { return }
    task = nil
    restartRequested = false
  }
}

private struct InstantSharedRootWriteTarget: Hashable, Sendable {
  var namespace: String?
  var id: String
}

private struct InstantAppliedServerTransaction: Sendable {
  var application: InstantServerTransactionApplicationResult
  var confirmedMutation: PendingMutation?
  var mergedAttributeCount: Int
}

public final class InstantRuntime: Sendable {
  public static let selectedAppIDMetadataKey = "cli.selected_app_id"
  public static let cookieSyncLastUpdatedMetadataKey = "lastSyncedUserCookie"
  public static let cookieSyncIntervalMilliseconds: Int64 = 24 * 60 * 60 * 1000
  private static let authUsersNamespace = "$users"

  public let configuration: InstantRuntimeConfiguration
  public let store: InstantStore
  public let persistence: SQLitePersistenceStore
  let outbox: InstantOutbox
  private let authSessionObservers = InstantAuthSessionObservers()
  private let connectionStatusObservers =
    InstantSnapshotObservers<String, InstantConnectionStatus>()
  private let mutationLifecycleObservers =
    InstantSnapshotObservers<String, InstantMutationLifecycleEvent>()
  private let roomPresenceObservers =
    InstantSnapshotObservers<InstantRoomPresenceObservationKey, [InstantRoomPresenceMember]>()
  private let roomTopicObservers =
    InstantSnapshotObservers<InstantRoomTopicObservationKey, [InstantRoomTopicMessage]>()
  private let storedFilesObservers =
    InstantSnapshotObservers<InstantStoredFilesObservationKey, [InstantStoredFile]>()
  private let streamChunksObservers =
    InstantSnapshotObservers<InstantStreamChunksObservationKey, [InstantStreamChunk]>()
  private let streamContentObservers = InstantStreamContentObservers()
  private let sharesObservers =
    InstantSnapshotObservers<InstantSharesObservationKey, [InstantShareSnapshot]>()
  private let operationGate = AsyncSerialGate()
  private let mutationFlushGate = AsyncSerialGate()
  private let liveSession = InstantRuntimeLiveSession()
  private let liveRoomPresenceState = InstantRuntimeLiveRoomPresenceState()
  private let reconnectController = InstantRuntimeReconnectController()

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
    try validateEndpoints(configuration)
    try validateInitialAttributes(configuration.initialAttributes)

    let persistence = try SQLitePersistenceStore(fileURL: configuration.persistenceURL)
    configuration.actorHopRecorder?.record(.persistence)
    try await persistence.bootstrap()
    configuration.actorHopRecorder?.record(.persistence)
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
      configuration.actorHopRecorder?.record(.store)
      let storeSnapshot = await store.mergeAttributes(configuration.initialAttributes)
      configuration.actorHopRecorder?.record(.persistence)
      try await persistence.saveStoreSnapshot(storeSnapshot)
    }

    await runtime.syncUserCookieOnStartup()

    return runtime
  }

  private static func validateInitialAttributes(_ attributes: [InstantAttribute]) throws {
    if let attribute = attributes.first(where: {
      $0.name == InstantQueryOrder.serverCreatedAtField
    }) {
      throw InstantError(
        code: .validationFailed,
        operation: "bootstrap attributes",
        namespace: attribute.namespace,
        path: attribute.name,
        localID: attribute.id,
        message: "'\(InstantQueryOrder.serverCreatedAtField)' is reserved for order-only metadata.",
        recovery:
          "Rename the schema field, and use InstantQueryOrder.serverCreatedAt when ordering by "
          + "server creation time."
      )
    }
  }

  private static func validateEndpoints(_ configuration: InstantRuntimeConfiguration) throws {
    guard InstantRuntimeConfiguration.isValidAPIURI(configuration.apiURI) else {
      throw Self.endpointValidationFailed(
        name: "apiURI",
        requirement: "an absolute http or https URL with a host and no query or fragment"
      )
    }
    guard InstantRuntimeConfiguration.isValidWebSocketURI(configuration.websocketURI) else {
      throw endpointValidationFailed(
        name: "websocketURI",
        requirement: "an absolute ws or wss URL with a host and no query or fragment"
      )
    }
    if let firstPartyURL = configuration.firstPartyURL {
      guard InstantRuntimeConfiguration.isValidAPIURI(firstPartyURL) else {
        throw endpointValidationFailed(
          name: "firstPartyURL",
          requirement: "an absolute http or https URL with a host and no query or fragment"
        )
      }
    }
  }

  private static func endpointValidationFailed(name: String, requirement: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "bootstrap endpoint configuration",
      path: name,
      message: "\(name) must be \(requirement).",
      recovery: "Check the Instant runtime endpoint configuration before bootstrapping."
    )
  }

  private static func cookieSyncISOString(from timestamp: InstantTimestamp) -> String {
    let date = Date(timeIntervalSince1970: Double(timestamp.milliseconds) / 1000)
    return cookieSyncDateFormatter().string(from: date)
  }

  private static func cookieSyncMilliseconds(from value: String) -> Int64? {
    for formatter in cookieSyncDateFormatters() {
      guard let date = formatter.date(from: value) else { continue }
      return Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
    return nil
  }

  private static func cookieSyncDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private static func cookieSyncDateFormatters() -> [ISO8601DateFormatter] {
    let internetDateTimeFormatter = ISO8601DateFormatter()
    internetDateTimeFormatter.formatOptions = [.withInternetDateTime]
    return [cookieSyncDateFormatter(), internetDateTimeFormatter]
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
    await enterOperationGate()
    do {
      let result = try await performTransact(transaction, createdAt: createdAt, source: source)
      await leaveOperationGate()
      await sendPendingMutationsToLiveSession()
      return result
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performTransact(
    _ transaction: InstantStoreTransaction,
    createdAt: InstantTimestamp?,
    source: String
  ) async throws -> InstantStoreMutationResult {
    var mutation: PendingMutation?

    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      if transaction.operations.isEmpty {
        recordActorHop(.store)
        await store.replaceSnapshot(state.snapshot.store)
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: state.snapshot.store.triples.count,
          emissions: []
        )
      }
      try await authorizeSharedRootWrites(transaction: transaction, snapshot: state.snapshot.store)
      if let existingMutation = state.snapshot.outbox.first(where: { $0.id == transaction.id }) {
        recordActorHop(.store)
        await store.replaceSnapshot(state.snapshot.store)
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        guard existingMutation.status == .pending else {
          throw validationFailed(
            operation: "transact",
            localID: transaction.id,
            message:
              "Mutation '\(transaction.id)' already exists in the local outbox with status '\(existingMutation.status.rawValue)'.",
            recovery:
              "Use a new transaction id, or retry the existing outbox mutation before sending it again."
          )
        }
        guard existingMutation.transaction == transaction else {
          throw validationFailed(
            operation: "transact",
            localID: transaction.id,
            message:
              "Mutation '\(transaction.id)' is already pending with different operations.",
            recovery:
              "Reuse the same prepared transaction when retrying, or generate a new transaction id."
          )
        }
        return InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: state.snapshot.store.triples.count,
          emissions: []
        )
      }
      let pendingMutation: PendingMutation
      if let mutation {
        pendingMutation = mutation
      } else {
        let newMutation = PendingMutation(
          id: transaction.id,
          createdAt: createdAt ?? configuration.now(),
          transaction: transaction
        )
        mutation = newMutation
        pendingMutation = newMutation
      }
      let outboxSnapshot = (state.snapshot.outbox + [pendingMutation])
        .sorted(by: PendingMutation.creationOrder)
      recordActorHop(.store)
      let prepared = try await store.prepare(transaction, applyingTo: state.snapshot.store)
      recordActorHop(.persistence)
      let didSave = try await persistence.saveSnapshot(
        InstantPersistenceSnapshot(store: prepared.snapshot, outbox: outboxSnapshot),
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision
      )
      if didSave {
        recordActorHop(.store)
        let committed = await store.commitAndPublish(prepared)
        recordActorHop(.outbox)
        await outbox.replace(with: outboxSnapshot)
        _ = try? await publishConnectionStatusWithGateHeld()
        return committed.result
      }
    }

    throw transactionChangedDuringPersistence(id: transaction.id)
  }

  @discardableResult
  public func applyServerTransaction(
    _ transaction: InstantStoreTransaction,
    processedTransactionID: String? = nil,
    receivedAt: InstantTimestamp? = nil
  ) async throws -> InstantServerTransactionApplicationResult {
    await enterOperationGate()
    do {
      let result = try await performApplyServerTransaction(
        transaction,
        processedTransactionID: processedTransactionID,
        receivedAt: receivedAt
      )
      await leaveOperationGate()
      return result.application
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performApplyServerTransaction(
    _ transaction: InstantStoreTransaction,
    processedTransactionID: String?,
    receivedAt: InstantTimestamp?,
    confirmingMutationID: String? = nil,
    mergingAttributes attributesToMerge: [InstantAttribute] = []
  ) async throws -> InstantAppliedServerTransaction {
    let processedTransactionID = (processedTransactionID ?? transaction.id)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !processedTransactionID.isEmpty else {
      throw validationFailed(
        operation: "apply server transaction",
        message: "Processed transaction id must not be empty.",
        recovery: "Pass the Instant transaction id that has been fully received from the server."
      )
    }
    let transactionID = transaction.id.trimmingCharacters(in: .whitespacesAndNewlines)

    var transaction = transaction
    transaction.id = transactionID.isEmpty ? processedTransactionID : transactionID
    let metadataUpdatedAt = receivedAt ?? configuration.now()
    let confirmingMutationID = confirmingMutationID?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty

    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      let confirmation = confirmingMutationID.flatMap {
        InstantOutbox.confirming(id: $0, in: state.snapshot.outbox)
      }
      let outboxSnapshot = confirmation?.mutations ?? state.snapshot.outbox
      let outboxChanged = outboxSnapshot != state.snapshot.outbox
      var storeSnapshot = state.snapshot.store
      let tripleCountBeforeFailedWriteCleanup = storeSnapshot.triples.count
      storeSnapshot.removeTriplesWrittenByFailedMutations(outboxSnapshot)
      let removedFailedWriteTriples =
        tripleCountBeforeFailedWriteCleanup - storeSnapshot.triples.count
      let mergedAttributeCount = mergeLiveRefreshAttributes(
        attributesToMerge,
        into: &storeSnapshot
      )
      let storeAttributesChanged = mergedAttributeCount > 0
      if transaction.operations.isEmpty, removedFailedWriteTriples == 0 {
        recordActorHop(.persistence)
        let didSave =
          if storeAttributesChanged, outboxChanged {
            try await persistence.saveSnapshot(
              InstantPersistenceSnapshot(store: storeSnapshot, outbox: outboxSnapshot),
              metadataKey: processedTransactionIDMetadataKey,
              metadataValue: processedTransactionID,
              metadataUpdatedAt: metadataUpdatedAt,
              expectedStoreRevision: state.storeRevision,
              expectedOutboxRevision: state.outboxRevision
            )
          } else if storeAttributesChanged {
            try await persistence.saveStoreSnapshot(
              storeSnapshot,
              metadataKey: processedTransactionIDMetadataKey,
              metadataValue: processedTransactionID,
              metadataUpdatedAt: metadataUpdatedAt,
              expectedStoreRevision: state.storeRevision,
              expectedOutboxRevision: state.outboxRevision
            )
          } else if outboxChanged {
            try await persistence.saveOutbox(
              outboxSnapshot,
              metadataKey: processedTransactionIDMetadataKey,
              metadataValue: processedTransactionID,
              metadataUpdatedAt: metadataUpdatedAt,
              expectedStoreRevision: state.storeRevision,
              expectedOutboxRevision: state.outboxRevision
            )
          } else {
            try await persistence.saveMetadataValue(
              processedTransactionID,
              key: processedTransactionIDMetadataKey,
              updatedAt: metadataUpdatedAt,
              expectedStoreRevision: state.storeRevision,
              expectedOutboxRevision: state.outboxRevision
            )
        }
        if didSave {
          recordActorHop(.store)
          await store.replaceSnapshot(storeSnapshot)
          recordActorHop(.outbox)
          await outbox.replace(with: outboxSnapshot)
          _ = try? await publishConnectionStatusWithGateHeld()
          let application = InstantStoreMutationResult(
            transactionID: transaction.id,
            changedEntityIDs: [],
            tripleCount: storeSnapshot.triples.count,
            emissions: []
          ).serverApplicationResult(
            processedTransactionID: processedTransactionID,
            pendingMutations: outboxSnapshot
          )
          if let mutation = confirmation?.mutation {
            await publishMutationLifecycle(mutation)
          }
          return InstantAppliedServerTransaction(
            application: application,
            confirmedMutation: confirmation?.mutation,
            mergedAttributeCount: mergedAttributeCount
          )
        }
        continue
      }

      recordActorHop(.store)
      let preparedServer = try await store.prepare(transaction, applyingTo: storeSnapshot)
      let prepared = try await rebaseLocalMutations(
        outboxSnapshot,
        over: preparedServer
      )
      recordActorHop(.persistence)
      let didSave =
        if outboxChanged {
          try await persistence.saveSnapshot(
            InstantPersistenceSnapshot(store: prepared.snapshot, outbox: outboxSnapshot),
            metadataKey: processedTransactionIDMetadataKey,
            metadataValue: processedTransactionID,
            metadataUpdatedAt: metadataUpdatedAt,
            expectedStoreRevision: state.storeRevision,
            expectedOutboxRevision: state.outboxRevision
          )
        } else {
          try await persistence.saveStoreSnapshot(
            prepared.snapshot,
            metadataKey: processedTransactionIDMetadataKey,
            metadataValue: processedTransactionID,
            metadataUpdatedAt: metadataUpdatedAt,
            expectedStoreRevision: state.storeRevision,
            expectedOutboxRevision: state.outboxRevision
          )
        }
      if didSave {
        recordActorHop(.store)
        let committed = await store.commitAndPublish(prepared)
        recordActorHop(.outbox)
        await outbox.replace(with: outboxSnapshot)
        _ = try? await publishConnectionStatusWithGateHeld()
        let application = committed.result.serverApplicationResult(
          processedTransactionID: processedTransactionID,
          pendingMutations: outboxSnapshot
        )
        if let mutation = confirmation?.mutation {
          await publishMutationLifecycle(mutation)
        }
        return InstantAppliedServerTransaction(
          application: application,
          confirmedMutation: confirmation?.mutation,
          mergedAttributeCount: mergedAttributeCount
        )
      }
    }

    throw serverTransactionChangedDuringPersistence(id: processedTransactionID)
  }

  @discardableResult
  public func applyLiveRefresh(
    _ refreshOK: InstantLiveRefreshOK,
    receivedAt: InstantTimestamp? = nil
  ) async throws -> InstantLiveRefreshApplicationResult {
    let receivedAt = receivedAt ?? configuration.now()
    await enterOperationGate()
    do {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      let translated = try InstantLiveRefreshTranslator.translate(
        refreshOK,
        existingAttributes: state.snapshot.store.attributes,
        receivedAt: receivedAt
      )

      let applied = try await performApplyServerTransaction(
        translated.transaction,
        processedTransactionID: translated.processedTransactionID,
        receivedAt: receivedAt,
        confirmingMutationID: translated.confirmationMutationID,
        mergingAttributes: translated.attributesToMerge
      )

      await leaveOperationGate()
      return InstantLiveRefreshApplicationResult(
        transaction: translated.transaction,
        application: applied.application,
        confirmedMutation: applied.confirmedMutation,
        insertedTripleCount: translated.transaction.operations.count,
        mergedAttributeCount: applied.mergedAttributeCount
      )
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  @discardableResult
  public func confirmMutationIfPresent(id: String) async throws -> PendingMutation? {
    await enterOperationGate()
    do {
      let result = try await performConfirmMutationIfPresent(id: id)
      await leaveOperationGate()
      return result.mutation
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performConfirmMutationIfPresent(
    id: String
  ) async throws -> (mutation: PendingMutation?, pendingMutationCount: Int) {
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      guard let update = InstantOutbox.confirming(id: id, in: state.snapshot.outbox) else {
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        return (
          mutation: nil,
          pendingMutationCount: state.snapshot.outbox.filter { $0.status == .pending }.count
        )
      }
      recordActorHop(.persistence)
      let didSave = try await persistence.saveOutbox(
        update.mutations,
        expectedOutboxRevision: state.outboxRevision
      )
      if didSave {
        recordActorHop(.outbox)
        await outbox.replace(with: update.mutations)
        _ = try? await publishConnectionStatusWithGateHeld()
        await publishMutationLifecycle(update.mutation)
        return (
          mutation: update.mutation,
          pendingMutationCount: update.mutations.filter { $0.status == .pending }.count
        )
      }
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  private func rebaseLocalMutations(
    _ mutations: [PendingMutation],
    over preparedServer: PreparedStoreMutation
  ) async throws -> PreparedStoreMutation {
    var snapshot = preparedServer.snapshot
    for mutation in mutations.sorted(by: PendingMutation.creationOrder)
    where mutation.status == .pending {
      let operations = mutation.transaction.operations.filter(\.isRebasedLocalWrite)
      guard !operations.isEmpty else { continue }
      let preparedLocal = try await store.prepare(
        InstantStoreTransaction(id: mutation.transaction.id, operations: operations),
        applyingTo: snapshot
      )
      snapshot = preparedLocal.snapshot
    }
    var result = preparedServer.result
    result.tripleCount = snapshot.triples.count
    return PreparedStoreMutation(
      result: result,
      snapshot: snapshot,
      sequence: preparedServer.sequence
    )
  }

  private func mergeLiveRefreshAttributes(
    _ attributes: [InstantAttribute],
    into snapshot: inout InstantStoreSnapshot
  ) -> Int {
    guard !attributes.isEmpty else { return 0 }
    let previousAttributes = Dictionary(
      uniqueKeysWithValues: snapshot.attributes.map { ($0.id, $0) }
    )
    var attributeStore = AttributeStore(attributes: snapshot.attributes)
    attributeStore.merge(attributes)
    snapshot.attributes = attributeStore.attributes
    return snapshot.attributes.filter { previousAttributes[$0.id] != $0 }.count
  }

  @discardableResult
  package func migrateLocalPersistenceSnapshot(
    name: String,
    transform: @Sendable (InstantPersistenceSnapshot) throws -> InstantPersistenceSnapshot
  ) async throws -> Bool {
    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        let nextSnapshot = try transform(state.snapshot)
        if nextSnapshot == state.snapshot {
          recordActorHop(.store)
          await store.replaceSnapshot(state.snapshot.store)
          recordActorHop(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          await leaveOperationGate()
          return false
        }
        recordActorHop(.persistence)
        let didSave = try await persistence.saveSnapshot(
          nextSnapshot,
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          recordActorHop(.store)
          await store.replaceSnapshot(nextSnapshot.store)
          recordActorHop(.outbox)
          await outbox.replace(with: nextSnapshot.outbox)
          await leaveOperationGate()
          return true
        }
      }

      throw persistenceChangedDuringMigration(name: name)
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func observe(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) async -> AsyncStream<InstantQueryEmission> {
    await enterOperationGate()
    recordActorHop(.persistence)
    let attributes: [InstantAttribute]
    if let state = try? await persistence.loadState() {
      recordActorHop(.store)
      await store.replaceSnapshot(state.snapshot.store)
      attributes = state.snapshot.store.attributes
    } else {
      recordActorHop(.store)
      attributes = await store.snapshot().attributes
    }
    if TripleIndexes.validate(plan, attributes: AttributeStore(attributes: attributes)) != nil {
      await leaveOperationGate()
      return Self.emptyObservation(plan)
    }
    recordActorHop(.store)
    let stream = await store.observe(plan, remotePageInfo: remotePageInfo)
    await leaveOperationGate()
    guard configuration.liveTransport != nil else { return stream }

    let query: InstantLiveJSONValue
    let registrationKey: String
    do {
      query = try InstantLiveQueryEncoder.encode(plan)
      registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    } catch {
      await recordConnectionError(error)
      return stream
    }

    do {
      try await liveSession.registerQuery(
        query,
        key: registrationKey,
        clientEventID: configuration.makeID()
      )
    } catch {
      await recordConnectionError(error)
    }
    return Self.liveObservation(stream) { [weak self] in
      guard let self else { return }
      do {
        try await self.liveSession.unregisterQuery(
          key: registrationKey,
          clientEventID: self.configuration.makeID()
        )
      } catch {
        await self.recordConnectionError(error)
      }
    }
  }

  public func query(_ plan: InstantQueryPlan) async throws -> [InstantEntitySnapshot] {
    try await queryOnce(plan).values
  }

  public func queryOnce(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        if let issue = TripleIndexes.validate(
          plan,
          attributes: AttributeStore(attributes: state.snapshot.store.attributes)
        ) {
          throw validationFailed(
            operation: "validate query",
            namespace: issue.namespace,
            path: issue.path,
            message: issue.message,
            recovery: issue.recovery
          )
        }
        if try await persistedConnectionState() == .closed {
          recordActorHop(.persistence)
          let cachedState = try await persistence.loadStateAndCachedQuery(cacheKey: plan.cacheKey)
          if let issue = TripleIndexes.validate(
            plan,
            attributes: AttributeStore(attributes: cachedState.state.snapshot.store.attributes)
          ) {
            throw validationFailed(
              operation: "validate query",
              namespace: issue.namespace,
              path: issue.path,
              message: issue.message,
              recovery: issue.recovery
            )
          }
          let freshCachedQuery = await freshCachedQueryForClosedQuery(
            cachedState.cachedQuery,
            plan: plan,
            state: cachedState.state
          )
          throw InstantError(
            code: .networkFailed,
            operation: "queryOnce",
            namespace: plan.namespace,
            message: "Cannot run query '\(plan.id)' while the Instant connection is closed.",
            recovery:
              "Call connect() or run 'instant-swift-data connection connect' before querying again.",
            cachedQuery: freshCachedQuery
          )
        }
        recordActorHop(.store)
        await store.replaceSnapshot(state.snapshot.store)
        recordActorHop(.store)
        let emission = await store.materializeEmission(plan)
        recordActorHop(.persistence)
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
          await leaveOperationGate()
          return emission
        }
      }

      throw queryCacheChangedDuringMaterialization(plan)
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func freshCachedQueryForClosedQuery(
    _ cachedQuery: InstantCachedQuery?,
    plan: InstantQueryPlan,
    state: InstantPersistenceState
  ) async -> InstantCachedQuery? {
    guard let cachedQuery else { return nil }
    guard cachedQuery.storeRevision != state.storeRevision else { return cachedQuery }

    recordActorHop(.store)
    await store.replaceSnapshot(state.snapshot.store)
    recordActorHop(.store)
    let localEmission = await store.materializeEmission(plan)
    guard cachedQuery.emission.queryID == localEmission.queryID,
      cachedQuery.emission.values == localEmission.values,
      cachedQuery.emission.pageInfo == localEmission.pageInfo
    else {
      return nil
    }
    return cachedQuery
  }

  public func cachedQuery(_ plan: InstantQueryPlan) async throws -> InstantCachedQuery? {
    recordActorHop(.persistence)
    return try await persistence.cachedQuery(cacheKey: plan.cacheKey)
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

  public func syncState() async throws -> InstantSyncState {
    InstantSyncState(
      processedTransactionID: try await persistence.loadMetadataValue(
        key: processedTransactionIDMetadataKey
      )
    )
  }

  public func markProcessedTransaction(id transactionID: String) async throws -> InstantSyncState {
    let transactionID = transactionID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !transactionID.isEmpty else {
      throw validationFailed(
        operation: "mark processed transaction",
        message: "Transaction id must not be empty.",
        recovery: "Pass the Instant transaction id that has been fully processed."
      )
    }

    await operationGate.enter()
    do {
      try await persistence.saveMetadataValue(
        transactionID,
        key: processedTransactionIDMetadataKey,
        updatedAt: configuration.now()
      )
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
      return InstantSyncState(processedTransactionID: transactionID)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func connectionStatus() async throws -> InstantConnectionStatus {
    await operationGate.enter()
    do {
      let status = try await connectionStatusWithGateHeld()
      await operationGate.leave()
      return status
    } catch {
      if configuration.liveTransport != nil {
        await liveSession.close()
      }
      await operationGate.leave()
      throw error
    }
  }

  public func observeConnectionStatus() async throws -> AsyncStream<InstantConnectionStatus> {
    await operationGate.enter()
    do {
      let status = try await connectionStatusWithGateHeld()
      let stream = await connectionStatusObservers.observe(
        key: configuration.appID,
        current: status
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func connect() async throws -> InstantConnectionStatus {
    await reconnectController.cancel()
    return try await connectLiveSession(reportsFailure: true)
  }

  private func connectLiveSession(reportsFailure: Bool) async throws -> InstantConnectionStatus {
    await operationGate.enter()
    do {
      if let liveTransport = configuration.liveTransport {
        let session = try await persistence.loadAuthSession(key: authSessionKey)
        do {
          try await liveSession.open(
            request: InstantLiveSessionRequest(
              appID: configuration.appID,
              websocketURI: configuration.websocketURI,
              refreshToken: session?.refreshToken
            ),
            transport: liveTransport,
            makeID: configuration.makeID
          )
          try await liveSession.sendMutations(
            await outboxTransportMutations().filter { $0.status == .pending }
          )
        } catch {
          await liveSession.close()
          if reportsFailure {
            try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
          } else {
            try await saveClosedConnectionMetadataWithGateHeld()
          }
          _ = try? await publishConnectionStatusWithGateHeld()
          throw error
        }
      }
      try await saveOpenedConnectionMetadataWithGateHeld()
      let status = try await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
      if configuration.liveTransport != nil {
        await liveSession.startReceiving(
          onEvent: { [weak self] event, attributes in
            guard let self else { return }
            try await self.handleLiveServerEvent(event, serverAttributes: attributes)
          },
          onFailure: { [weak self] error in
            guard let self else { return }
            await self.handleLiveSessionFailure(error)
          }
        )
      }
      return status
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func closeConnection() async throws -> InstantConnectionStatus {
    await reconnectController.cancel()
    await operationGate.enter()
    do {
      await liveSession.close()
      try await persistence.saveMetadataValue(
        InstantConnectionState.closed.rawValue,
        key: connectionStateMetadataKey,
        updatedAt: configuration.now()
      )
      let status = try await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
      return status
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func connectionStatusWithGateHeld() async throws -> InstantConnectionStatus {
    let state = try await persistence.loadState()
    let session = try await persistence.loadAuthSession(key: authSessionKey)
    let processedTransactionID = try await persistence.loadMetadataValue(
      key: processedTransactionIDMetadataKey
    )
    let storedState = try await persistedConnectionState()
    let lastErrorMessage = try await persistence.loadMetadataValue(
      key: connectionLastErrorMetadataKey
    )
    let liveSessionIsOpen = await liveSession.isOpen
    return InstantConnectionStatus(
      appID: configuration.appID,
      apiURI: configuration.apiURI,
      websocketURI: configuration.websocketURI,
      transport: configuration.liveTransport == nil ? .localCacheOnly : .webSocket,
      state: connectionState(
        storedState,
        isAuthenticated: session != nil,
        liveSessionIsOpen: liveSessionIsOpen
      ),
      isAuthenticated: session != nil,
      userID: session?.userID,
      pendingMutationCount: state.snapshot.outbox.filter { $0.status == .pending }.count,
      processedTransactionID: processedTransactionID,
      lastErrorMessage: lastErrorMessage
    )
  }

  @discardableResult
  private func publishConnectionStatusWithGateHeld() async throws -> InstantConnectionStatus {
    let status = try await connectionStatusWithGateHeld()
    await connectionStatusObservers.publish(status, for: configuration.appID)
    return status
  }

  private func publishMutationLifecycle(_ mutation: PendingMutation) async {
    let event: InstantMutationLifecycleEvent
    switch mutation.status {
    case .confirmed:
      event = .serverAccepted(mutation)
    case .failed:
      event = .failed(mutation)
    case .pending:
      return
    }
    await mutationLifecycleObservers.publish(event, for: mutation.id)
  }

  private func persistedConnectionState() async throws -> InstantConnectionState {
    recordActorHop(.persistence)
    return try await persistence.loadMetadataValue(key: connectionStateMetadataKey)
      .flatMap(InstantConnectionState.init(rawValue:))
      ?? .opened
  }

  private func saveOpenedConnectionMetadataWithGateHeld() async throws {
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.opened.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: configuration.now()
    )
    recordActorHop(.persistence)
    try await persistence.deleteMetadataValue(key: connectionLastErrorMetadataKey)
  }

  private func saveClosedConnectionMetadataWithGateHeld() async throws {
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.closed.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: configuration.now()
    )
    recordActorHop(.persistence)
    try await persistence.deleteMetadataValue(key: connectionLastErrorMetadataKey)
  }

  private func saveErroredConnectionMetadataWithGateHeld(message: String) async throws {
    let now = configuration.now()
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      InstantConnectionState.errored.rawValue,
      key: connectionStateMetadataKey,
      updatedAt: now
    )
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      message,
      key: connectionLastErrorMetadataKey,
      updatedAt: now
    )
  }

  private func recordConnectionError(_ error: Error) async {
    await operationGate.enter()
    do {
      try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
    } catch {
      await operationGate.leave()
    }
  }

  private func handleLiveSessionFailure(_: Error) async {
    await operationGate.enter()
    do {
      try await saveClosedConnectionMetadataWithGateHeld()
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
    } catch {
      await operationGate.leave()
    }
    await reconnectController.start(
      sleep: configuration.liveReconnectSleep,
      reconnect: { [weak self] in
        guard let self else { throw CancellationError() }
        _ = try await self.connectLiveSession(reportsFailure: false)
      }
    )
  }

  private func handleLiveServerEvent(
    _ event: InstantLiveServerEvent,
    serverAttributes: [InstantLiveJSONValue]
  ) async throws {
    switch event {
    case let .addQueryOK(queryOK):
      guard !queryOK.result.isEmpty else { return }
      guard let query = queryOK.query,
        let processedTransactionID = queryOK.processedTransactionID?.nilIfEmpty
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "apply Instant live query result",
          message: "A non-empty add-query-ok must include q and processed-tx-id.",
          recovery: "Inspect the canonical Instant add-query-ok payload."
        )
      }
      try await applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: nil,
          processedTransactionID: processedTransactionID,
          attrs: serverAttributes,
          computations: [
            .object([
              "instaql-query": query,
              "instaql-result": .array(queryOK.result),
            ])
          ]
        )
      )

    case let .refreshOK(refreshOK):
      try await applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: refreshOK.clientEventID,
          processedTransactionID: refreshOK.processedTransactionID,
          attrs: refreshOK.attrs.isEmpty ? serverAttributes : refreshOK.attrs,
          computations: refreshOK.computations
        )
      )

    case let .transactOK(transactOK):
      guard let clientEventID = transactOK.clientEventID?.nilIfEmpty,
        transactOK.transactionID?.nilIfEmpty != nil
      else {
        throw InstantError(
          code: .decodeFailed,
          operation: "confirm Instant live transaction",
          message: "transact-ok must include client-event-id and tx-id.",
          recovery: "Inspect the canonical Instant transact-ok payload."
        )
      }
      _ = try await confirmMutationIfPresent(id: clientEventID)

    case let .refreshPresence(refresh):
      try await applyLivePresenceRefresh(refresh)

    case let .patchPresence(patch):
      try await applyLivePresencePatch(patch)

    case let .serverBroadcast(broadcast):
      try await applyLiveServerBroadcast(broadcast)

    case let .streamAppend(append):
      guard let delivery = await liveSession.takeDeliveredStreamAppend(
        clientEventID: append.clientEventID
      ) else {
        return
      }
      try await applyLiveStreamAppend(delivery)
      await liveSession.recordDeliveredStreamAppend(delivery)

    case let .error(error):
      if let clientEventID = error.clientEventID?.nilIfEmpty,
        await pendingMutations().contains(where: { $0.id == clientEventID })
      {
        _ = try await failMutation(id: clientEventID, message: error.message)
        try await liveSession.refreshRegisteredQueries()
        return
      }
      throw InstantError(
        code: .networkFailed,
        operation: "receive Instant live server event",
        serverEventID: error.clientEventID,
        message: error.message,
        recovery: "Inspect the Instant runtime WebSocket event and reconnect."
      )

    case .initOK, .addQueryExists, .joinRoomOK, .leaveRoomOK, .other:
      break
    }
  }

  private func applyLiveStreamAppend(_ append: InstantLiveStreamAppend) async throws {
    if !append.files.isEmpty {
      throw InstantError(
        code: .implementationFailed,
        operation: "apply Instant live stream append",
        serverEventID: append.clientEventID,
        message: "File-backed live stream appends are not implemented yet.",
        recovery: "Use inline stream content until the canonical file-fetch packet is ported."
      )
    }
    if let content = append.content, !content.isEmpty {
      _ = try await appendStreamContent(
        streamID: append.streamID,
        content: content,
        expectedOffset: append.offset
      )
    }
    if append.done {
      _ = try await closeStream(
        streamID: append.streamID,
        abortReason: append.abortReason
      )
    }
  }

  private func applyLivePresenceRefresh(
    _ refresh: InstantLivePresenceRefresh
  ) async throws {
    guard let room = await liveSession.roomHandle(id: refresh.roomID) else { return }
    let remoteMembers = await liveRoomPresenceState.replace(
      room: room,
      sessions: refresh.sessions,
      excludingSessionID: await liveSession.currentSessionID,
      appID: configuration.appID,
      updatedAt: configuration.now()
    )
    let localMembers = try await persistence.loadRoomPresence(
      appID: configuration.appID,
      room: room
    )
    await roomPresenceObservers.publish(
      mergedRoomPresence(local: localMembers, remote: remoteMembers),
      for: roomPresenceObservationKey(room)
    )
  }

  private func applyLivePresencePatch(
    _ patch: InstantLivePresencePatch
  ) async throws {
    guard let room = await liveSession.roomHandle(id: patch.roomID) else { return }
    let remoteMembers = try await liveRoomPresenceState.patch(
      room: room,
      edits: patch.edits,
      excludingSessionID: await liveSession.currentSessionID,
      appID: configuration.appID,
      updatedAt: configuration.now()
    )
    let localMembers = try await persistence.loadRoomPresence(
      appID: configuration.appID,
      room: room
    )
    await roomPresenceObservers.publish(
      mergedRoomPresence(local: localMembers, remote: remoteMembers),
      for: roomPresenceObservationKey(room)
    )
  }

  private func applyLiveServerBroadcast(
    _ broadcast: InstantLiveServerBroadcast
  ) async throws {
    guard let room = await liveSession.roomHandle(id: broadcast.roomID) else { return }
    guard !broadcast.topic.isEmpty,
      case let .object(envelope)? = broadcast.envelope,
      let rawPayload = envelope["data"]
    else {
      throw InstantError(
        code: .decodeFailed,
        operation: "apply Instant live server broadcast",
        message: "server-broadcast must include room-id, topic, and data.data.",
        recovery: "Inspect the canonical Instant server-broadcast payload."
      )
    }
    let peerID: String
    if case let .string(value)? = envelope["peer-id"] {
      peerID = value
    } else {
      peerID = "unknown-peer"
    }
    let userID: String
    if case let .object(user)? = envelope["user"],
      case let .string(value)? = user["id"]
    {
      userID = value
    } else {
      userID = peerID
    }
    let message = InstantRoomTopicMessage(
      id: broadcast.clientEventID?.nilIfEmpty ?? configuration.makeID(),
      appID: configuration.appID,
      room: room,
      topic: broadcast.topic,
      userID: userID,
      payload: rawPayload.jsonValue,
      createdAt: configuration.now()
    )
    let durableMessages = try await persistence.loadRoomTopicMessages(
      appID: configuration.appID,
      room: room,
      topic: broadcast.topic,
      limit: nil
    )
    await roomTopicObservers.publish(
      durableMessages + [message],
      for: roomTopicObservationKey(room: room, topic: broadcast.topic)
    )
  }

  private func sendPendingMutationsToLiveSession() async {
    guard configuration.liveTransport != nil else { return }
    do {
      try await liveSession.sendMutations(
        await outboxTransportMutations().filter { $0.status == .pending }
      )
    } catch {
      await recordConnectionError(error)
    }
  }

  private static func liveObservation<Element: Sendable>(
    _ source: AsyncStream<Element>,
    onTermination: @escaping @Sendable () async -> Void
  ) -> AsyncStream<Element> {
    let output = AsyncStream<Element>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let task = Task {
      for await emission in source {
        output.continuation.yield(emission)
      }
      output.continuation.finish()
    }
    output.continuation.onTermination = { @Sendable _ in
      task.cancel()
      Task {
        await onTermination()
      }
    }
    return output.stream
  }

  private func connectionState(
    _ state: InstantConnectionState,
    isAuthenticated: Bool,
    liveSessionIsOpen: Bool
  ) -> InstantConnectionState {
    switch state {
    case .opened, .authenticated:
      if configuration.liveTransport != nil, !liveSessionIsOpen {
        return .closed
      }
      return isAuthenticated ? .authenticated : .opened
    case .connecting, .closed, .errored:
      return state
    }
  }

  public func authSession() async throws -> InstantAuthSession? {
    try await persistence.loadAuthSession(key: authSessionKey)
  }

  @discardableResult
  public func syncUserCookieToEndpoint(
    _ session: InstantAuthSession?
  ) async throws -> InstantUserCookieSyncRequest? {
    guard let firstPartyURL = configuration.firstPartyURL else { return nil }

    let syncedAt = configuration.now()
    let request = InstantUserCookieSyncRequest(
      appID: configuration.appID,
      firstPartyURL: firstPartyURL,
      user: session.map(InstantUserCookieSyncUser.init),
      syncedAt: syncedAt
    )
    do {
      try await configuration.userCookieSyncClient.sync(request)
    } catch {
      // Match Instant's Reactor: endpoint failures are logged there, but the
      // local last-sync marker is still advanced to avoid retry loops.
    }
    recordActorHop(.persistence)
    try await persistence.saveMetadataValue(
      Self.cookieSyncISOString(from: syncedAt),
      key: appScopedCookieSyncLastUpdatedMetadataKey,
      updatedAt: syncedAt
    )
    return request
  }

  private func syncUserCookieOnStartup() async {
    guard configuration.firstPartyURL != nil else { return }

    do {
      recordActorHop(.persistence)
      let lastSynced = try await persistence.loadMetadataValue(
        key: appScopedCookieSyncLastUpdatedMetadataKey
      )
      let lastSyncedMilliseconds = lastSynced.flatMap(Self.cookieSyncMilliseconds(from:)) ?? 0
      let now = configuration.now()
      let shouldSync =
        lastSyncedMilliseconds == 0
        || now.milliseconds - lastSyncedMilliseconds >= Self.cookieSyncIntervalMilliseconds
      guard shouldSync else { return }

      recordActorHop(.persistence)
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      _ = try await syncUserCookieToEndpoint(session)
    } catch {
      // Match Instant's Reactor startup behavior: cookie sync failures are
      // intentionally non-fatal to runtime bootstrap.
    }
  }

  public func observeAuthSession() async throws -> AsyncStream<InstantAuthSession?> {
    await operationGate.enter()
    do {
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      let stream = await authSessionObservers.observe(current: session)
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
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

  public func sendMagicCode(email rawEmail: String) async throws -> InstantMagicCodeChallenge {
    let email = try normalizedEmail(rawEmail, operation: "send magic code")
    let now = configuration.now()
    let challenge = try await configuration.magicCodeExchange.send(
      InstantMagicCodeSendRequest(
        appID: configuration.appID,
        email: email,
        sentAt: now,
        makeID: configuration.makeID
      )
    )

    await operationGate.enter()
    do {
      try await persistence.saveMagicCodeChallenge(challenge, key: magicCodeChallengeKey(email: email))
      await operationGate.leave()
      return challenge
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func signInWithMagicCode(
    email rawEmail: String,
    code rawCode: String
  ) async throws -> InstantAuthSession {
    try await signInWithMagicCodeResult(email: rawEmail, code: rawCode).session
  }

  public func signInWithMagicCodeResult(
    email rawEmail: String,
    code rawCode: String,
    extraFields: [String: InstantValue] = [:]
  ) async throws -> InstantMagicCodeSignInResult {
    let email = try normalizedEmail(rawEmail, operation: "sign in with magic code")
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with magic code",
        message: "Magic code must not be empty.",
        recovery: "Run 'instant-swift-data auth magic-code send <email>' and enter the returned local verification code."
      )
    }
    let extraFields = try validatedMagicCodeExtraFields(extraFields)

    await operationGate.enter()
    do {
      let key = magicCodeChallengeKey(email: email)
      guard let challenge = try await persistence.loadMagicCodeChallenge(key: key) else {
        throw authValidationFailed(
          operation: "sign in with magic code",
          message: "No pending magic code exists for '\(email)'.",
          recovery: "Run 'instant-swift-data auth magic-code send \(email)' before verifying."
        )
      }
      recordActorHop(.persistence)
      let stateBeforeVerification = try await persistence.loadState()
      try validateMagicCodeExtraFieldsSchema(
        extraFields,
        state: stateBeforeVerification
      )
      let now = configuration.now()
      let verification = try await configuration.magicCodeExchange.verify(
        InstantMagicCodeVerifyRequest(
          appID: configuration.appID,
          email: email,
          code: code,
          challenge: challenge,
          verifiedAt: now
        )
      )
      let session = InstantAuthSession(
        appID: configuration.appID,
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        isGuest: false,
        createdAt: now,
        updatedAt: now
      )
      let created = try await saveMagicCodeUserFields(
        userID: session.userID,
        email: email,
        extraFields: extraFields,
        verifiedAt: now
      )
      try await persistence.saveAuthSession(session, key: authSessionKey)
      try await persistence.deleteMagicCodeChallenge(key: key)
      await authSessionObservers.yield(session)
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
      _ = try? await syncUserCookieToEndpoint(session)
      return InstantMagicCodeSignInResult(session: session, created: created)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func saveMagicCodeUserFields(
    userID: String,
    email: String,
    extraFields: [String: InstantValue],
    verifiedAt: InstantTimestamp
  ) async throws -> Bool {
    recordActorHop(.persistence)
    let state = try await persistence.loadState()
    let attributes = AttributeStore(attributes: state.snapshot.store.attributes)
    let canWriteUsers =
      attributes.namespaces.isEmpty || attributes.namespaces.contains(Self.authUsersNamespace)
    guard canWriteUsers else {
      guard extraFields.isEmpty else {
        throw validationFailed(
          operation: "sign in with magic code",
          namespace: Self.authUsersNamespace,
          message:
            "Cannot write magic-code extra fields because the '$users' namespace is not declared in the local schema.",
          recovery:
            "Declare '$users' attributes before signing in with magic-code extra fields, or omit extra fields for this schema."
        )
      }
      return false
    }

    let userExists = state.snapshot.store.triples.contains { triple in
      triple.entityID == userID && triple.attributeID.hasPrefix(Self.authUsersNamespace + "/")
    }
    guard !userExists else { return false }

    let transactionID = "auth.magic-code.\(configuration.makeID())"
    var operations: [InstantTripleOperation] = [
      .requireEntityMissing(entityID: userID, namespace: Self.authUsersNamespace),
      .insert(
        InstantTriple(
          entityID: userID,
          attributeID: InstantAttribute.primaryKeyID(namespace: Self.authUsersNamespace),
          value: .string(userID),
          txID: transactionID,
          txTime: verifiedAt
        )
      ),
      .insert(
        InstantTriple(
          entityID: userID,
          attributeID: "\(Self.authUsersNamespace)/email",
          value: .string(email),
          txID: transactionID,
          txTime: verifiedAt
        )
      ),
    ]
    for (field, value) in extraFields.sorted(by: { $0.key < $1.key }) {
      operations.append(
        .insert(
          InstantTriple(
            entityID: userID,
            attributeID: "\(Self.authUsersNamespace)/\(field)",
            value: value,
            txID: transactionID,
            txTime: verifiedAt
          )
        )
      )
    }

    _ = try await performApplyServerTransaction(
      InstantStoreTransaction(id: transactionID, operations: operations),
      processedTransactionID: transactionID,
      receivedAt: verifiedAt
    )
    return !userExists
  }

  private func validateMagicCodeExtraFieldsSchema(
    _ extraFields: [String: InstantValue],
    state: InstantPersistenceState
  ) throws {
    guard !extraFields.isEmpty else { return }
    let attributes = AttributeStore(attributes: state.snapshot.store.attributes)
    guard
      attributes.namespaces.isEmpty
        || attributes.namespaces.contains(Self.authUsersNamespace)
    else {
      throw validationFailed(
        operation: "sign in with magic code",
        namespace: Self.authUsersNamespace,
        message:
          "Cannot write magic-code extra fields because the '$users' namespace is not declared in the local schema.",
        recovery:
          "Declare '$users' attributes before signing in with magic-code extra fields, or omit extra fields for this schema."
      )
    }
  }

  private func validatedMagicCodeExtraFields(
    _ extraFields: [String: InstantValue]
  ) throws -> [String: InstantValue] {
    var validated: [String: InstantValue] = [:]
    for (rawField, value) in extraFields {
      let field = rawField.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !field.isEmpty else {
        throw validationFailed(
          operation: "sign in with magic code",
          message: "Magic-code extra field names must not be empty.",
          recovery: "Remove empty extra-field names before signing in."
        )
      }
      guard !field.contains("/") else {
        throw validationFailed(
          operation: "sign in with magic code",
          path: field,
          message: "Magic-code extra field names must not contain '/'.",
          recovery: "Pass field names such as 'username' or 'displayName', not attribute ids."
        )
      }
      guard field != "id", field != "email" else {
        throw validationFailed(
          operation: "sign in with magic code",
          path: field,
          message: "Magic-code extra fields cannot override the managed '\(field)' field.",
          recovery: "Let Instant Swift Data derive the user id and verified email from the auth response."
        )
      }
      switch value {
      case .ref, .lookupRef:
        throw validationFailed(
          operation: "sign in with magic code",
          path: field,
          message: "Magic-code extra fields cannot contain ref values.",
          recovery: "Use JSON-compatible scalar, date, null, or object values for auth extra fields."
        )
      case .null, .string, .number, .bool, .date, .json:
        validated[field] = value
      }
    }
    return validated
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

    let now = configuration.now()
    let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedUserID: String?
    if let trimmedUserID, !trimmedUserID.isEmpty {
      normalizedUserID = trimmedUserID
    } else {
      normalizedUserID = nil
    }
    let verification = try await configuration.refreshTokenVerifier.verify(
      InstantRefreshTokenVerificationRequest(
        appID: configuration.appID,
        refreshToken: token,
        userID: normalizedUserID,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func signInWithIDToken(
    clientName rawClientName: String,
    idToken rawIDToken: String,
    nonce rawNonce: String? = nil
  ) async throws -> InstantAuthSession {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with id token",
        message: "Client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'google-ios'."
      )
    }
    let idToken = rawIDToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !idToken.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with id token",
        message: "ID token must not be empty.",
        recovery: "Pass the ID token returned by the native OAuth provider."
      )
    }
    let now = configuration.now()
    let refreshToken = try await authSession()?.refreshToken
    let verification = try await configuration.idTokenExchange.signIn(
      InstantIDTokenSignInRequest(
        appID: configuration.appID,
        clientName: clientName,
        idToken: idToken,
        nonce: rawNonce,
        refreshToken: refreshToken,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func signInWithOAuth(
    code rawCode: String,
    codeVerifier rawCodeVerifier: String? = nil
  ) async throws -> InstantAuthSession {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "sign in with oauth",
        message: "OAuth authorization code must not be empty.",
        recovery: "Pass the authorization code returned by the OAuth callback."
      )
    }

    let now = configuration.now()
    // Match Instant's transport shape: pass the current refresh token so a live
    // OAuth exchange can upgrade/link the existing session when supported.
    let refreshToken = try await authSession()?.refreshToken
    let verification = try await configuration.oauthExchange.signIn(
      InstantOAuthSignInRequest(
        appID: configuration.appID,
        code: code,
        codeVerifier: rawCodeVerifier,
        refreshToken: refreshToken,
        signedInAt: now,
        makeID: configuration.makeID
      )
    )
    let session = InstantAuthSession(
      appID: configuration.appID,
      userID: verification.userID,
      refreshToken: verification.refreshToken,
      isGuest: false,
      createdAt: now,
      updatedAt: now
    )
    try await saveAuthSession(session)
    return session
  }

  public func oauthAuthorizationURL(
    clientName rawClientName: String,
    redirectURL: URL
  ) throws -> URL {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "create oauth authorization URL",
        message: "OAuth client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'google'."
      )
    }
    guard redirectURL.scheme?.isEmpty == false else {
      throw authValidationFailed(
        operation: "create oauth authorization URL",
        message: "OAuth redirect URL must be absolute.",
        recovery: "Pass the redirect URL registered with the OAuth client."
      )
    }

    var components = try endpointComponents(path: ["runtime", "oauth", "start"])
    components.queryItems = [
      URLQueryItem(name: "app_id", value: configuration.appID),
      URLQueryItem(name: "client_name", value: clientName),
      URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString),
    ]
    guard let url = components.url else {
      throw endpointFailed(operation: "create oauth authorization URL")
    }
    return url
  }

  public func issuerURI() throws -> URL {
    var components = try endpointComponents(path: ["runtime", configuration.appID])
    components.queryItems = nil
    guard let url = components.url else {
      throw endpointFailed(operation: "create oauth issuer URI")
    }
    return url
  }

  public func signOut() async throws {
    try await signOut(invalidateToken: true)
  }

  public func signOut(invalidateToken: Bool = true) async throws {
    let signedOutAt = configuration.now()
    var invalidationRequest: InstantAuthTokenInvalidationRequest?
    await operationGate.enter()
    do {
      let session = try await persistence.loadAuthSession(key: authSessionKey)
      if invalidateToken, let refreshToken = session?.refreshToken {
        invalidationRequest = InstantAuthTokenInvalidationRequest(
          appID: configuration.appID,
          refreshToken: refreshToken,
          signedOutAt: signedOutAt
        )
      }
      try await persistence.deleteAuthSession(key: authSessionKey)
      await authSessionObservers.yield(nil)
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }

    _ = try? await syncUserCookieToEndpoint(nil)

    if let invalidationRequest {
      do {
        try await configuration.authTokenInvalidator.invalidate(invalidationRequest)
      } catch {
        // Match Instant's client: failed token invalidation must not undo local sign-out.
      }
    }
  }

  public func joinRoom(_ room: InstantRoomHandle = .default) async throws -> InstantRoomHandle {
    let room = try validatedRoom(room, operation: "join room")
    if configuration.liveTransport != nil {
      try await liveSession.joinRoom(room, clientEventID: configuration.makeID())
    }
    return room
  }

  public func leaveRoom(_ room: InstantRoomHandle = .default) async throws -> InstantRoomHandle {
    let room = try validatedRoom(room, operation: "leave room")
    if configuration.liveTransport != nil {
      try await liveSession.leaveRoom(room, clientEventID: configuration.makeID())
      await liveRoomPresenceState.remove(room: room)
    }
    return room
  }

  @discardableResult
  public func setPresence(
    room: InstantRoomHandle,
    userID: String? = nil,
    values: [String: JSONValue]
  ) async throws -> InstantRoomPresenceMember {
    let room = try validatedRoom(room, operation: "set room presence")

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "set room presence")
      let now = configuration.now()
      let member = InstantRoomPresenceMember(
        appID: configuration.appID,
        room: room,
        userID: userID,
        values: values,
        updatedAt: now
      )
      try await persistence.saveRoomPresence(member)
      let localMembers = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      let members = await combinedRoomPresence(localMembers, room: room)
      await roomPresenceObservers.publish(
        members,
        for: roomPresenceObservationKey(room)
      )
      if configuration.liveTransport != nil {
        try await liveSession.setPresence(
          room: room,
          values: values,
          clientEventID: configuration.makeID()
        )
      }
      await operationGate.leave()
      return member
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func roomPresence(room: InstantRoomHandle) async throws -> [InstantRoomPresenceMember] {
    let room = try validatedRoom(room, operation: "list room presence")
    let localMembers = try await persistence.loadRoomPresence(
      appID: configuration.appID,
      room: room
    )
    return await combinedRoomPresence(localMembers, room: room)
  }

  public func observeRoomPresence(room: InstantRoomHandle) async throws
    -> AsyncStream<[InstantRoomPresenceMember]>
  {
    let room = try validatedRoom(room, operation: "observe room presence")

    await operationGate.enter()
    do {
      let localMembers = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      let members = await combinedRoomPresence(localMembers, room: room)
      let stream = await roomPresenceObservers.observe(
        key: roomPresenceObservationKey(room),
        current: members
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func leavePresence(room: InstantRoomHandle, userID: String? = nil) async throws -> String {
    let room = try validatedRoom(room, operation: "leave room presence")

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "leave room presence")
      try await persistence.deleteRoomPresence(
        appID: configuration.appID,
        room: room,
        userID: userID
      )
      let localMembers = try await persistence.loadRoomPresence(
        appID: configuration.appID,
        room: room
      )
      let members = await combinedRoomPresence(localMembers, room: room)
      await roomPresenceObservers.publish(
        members,
        for: roomPresenceObservationKey(room)
      )
      await operationGate.leave()
      return userID
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeRoomPresenceObservationCount(room: InstantRoomHandle) async throws -> Int {
    let room = try validatedRoom(room, operation: "inspect room presence observers")
    return await roomPresenceObservers.activeCount(for: roomPresenceObservationKey(room))
  }

  @discardableResult
  public func publishTopicMessage(
    room: InstantRoomHandle,
    topic rawTopic: String,
    userID: String? = nil,
    payload: JSONValue
  ) async throws -> InstantRoomTopicMessage {
    let room = try validatedRoom(room, operation: "publish room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "publish room topic",
      recovery: "Pass the room topic name to publish."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedRoomUserID(userID, operation: "publish room topic")
      let message = InstantRoomTopicMessage(
        id: configuration.makeID(),
        appID: configuration.appID,
        room: room,
        topic: topic,
        userID: userID,
        payload: payload,
        createdAt: configuration.now()
      )
      try await persistence.saveRoomTopicMessage(message)
      let messages = try await persistence.loadRoomTopicMessages(
        appID: configuration.appID,
        room: room,
        topic: topic,
        limit: nil
      )
      await roomTopicObservers.publish(
        messages,
        for: roomTopicObservationKey(room: room, topic: topic)
      )
      if configuration.liveTransport != nil {
        try await liveSession.publishTopic(
          room: room,
          topic: topic,
          payload: payload,
          clientEventID: configuration.makeID()
        )
      }
      await operationGate.leave()
      return message
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func roomTopicMessages(
    room: InstantRoomHandle,
    topic rawTopic: String,
    limit: Int? = nil
  ) async throws -> [InstantRoomTopicMessage] {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "list room topic",
        message: "Topic message limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to list every local message."
      )
    }
    let room = try validatedRoom(room, operation: "list room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "list room topic",
      recovery: "Pass the room topic name to list."
    )
    return try await persistence.loadRoomTopicMessages(
      appID: configuration.appID,
      room: room,
      topic: topic,
      limit: limit
    )
  }

  public func observeRoomTopicMessages(
    room: InstantRoomHandle,
    topic rawTopic: String
  ) async throws -> AsyncStream<[InstantRoomTopicMessage]> {
    let room = try validatedRoom(room, operation: "observe room topic")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "observe room topic",
      recovery: "Pass the room topic name to observe."
    )

    await operationGate.enter()
    do {
      let messages = try await persistence.loadRoomTopicMessages(
        appID: configuration.appID,
        room: room,
        topic: topic,
        limit: nil
      )
      let stream = await roomTopicObservers.observe(
        key: roomTopicObservationKey(room: room, topic: topic),
        current: messages
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeRoomTopicObservationCount(
    room: InstantRoomHandle,
    topic rawTopic: String
  ) async throws -> Int {
    let room = try validatedRoom(room, operation: "inspect room topic observers")
    let topic = try validatedNonEmpty(
      rawTopic,
      label: "Topic",
      operation: "inspect room topic observers",
      recovery: "Pass the room topic name to inspect."
    )
    return await roomTopicObservers.activeCount(
      for: roomTopicObservationKey(room: room, topic: topic)
    )
  }

  public func uploadFile(
    from sourceURL: URL,
    name rawName: String? = nil,
    contentType rawContentType: String? = nil
  ) async throws -> InstantStoredFile {
    let file = try await preparedStoredFile(
      from: sourceURL,
      name: rawName,
      contentType: rawContentType,
      operation: "upload file"
    )
    return try await savePreparedStoredFile(file, contentsOf: sourceURL)
  }

  public func uploadFileProgress(
    from sourceURL: URL,
    name rawName: String? = nil,
    contentType rawContentType: String? = nil
  ) async throws -> AsyncThrowingStream<InstantFileUploadProgress, Error> {
    let file = try await preparedStoredFile(
      from: sourceURL,
      name: rawName,
      contentType: rawContentType,
      operation: "upload file"
    )
    let totalByteCount = try await persistence.regularFileByteCount(
      at: sourceURL,
      operation: "upload file"
    )
    let cancellation = InstantFileUploadProgressCancellation()

    return AsyncThrowingStream(bufferingPolicy: .bufferingOldest(2)) { continuation in
      Task {
        let startedAt = self.configuration.now()
        continuation.yield(
          InstantFileUploadProgress(
            operationID: file.id,
            appID: file.appID,
            fileID: file.id,
            fileName: file.name,
            contentType: file.contentType,
            state: .loading,
            completedByteCount: 0,
            totalByteCount: totalByteCount,
            progress: 0,
            updatedAt: startedAt
          )
        )
        do {
          try await Task.sleep(nanoseconds: 5_000_000)
          try cancellation.check()
          let savedFile = try await self.savePreparedStoredFile(file, contentsOf: sourceURL)
          continuation.yield(
            InstantFileUploadProgress(
              operationID: file.id,
              appID: file.appID,
              fileID: file.id,
              fileName: file.name,
              contentType: file.contentType,
              state: .success,
              completedByteCount: savedFile.byteCount,
              totalByteCount: max(totalByteCount, savedFile.byteCount),
              progress: 1,
              file: savedFile,
              updatedAt: self.configuration.now()
            )
          )
          continuation.finish()
        } catch is CancellationError {
          return
        } catch {
          continuation.yield(
            InstantFileUploadProgress(
              operationID: file.id,
              appID: file.appID,
              fileID: file.id,
              fileName: file.name,
              contentType: file.contentType,
              state: .error,
              completedByteCount: 0,
              totalByteCount: totalByteCount,
              progress: 0,
              errorMessage: error.localizedDescription,
              updatedAt: self.configuration.now()
            )
          )
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        cancellation.cancel()
      }
    }
  }

  private func savePreparedStoredFile(
    _ file: InstantStoredFile,
    contentsOf sourceURL: URL
  ) async throws -> InstantStoredFile {
    try Task.checkCancellation()
    await operationGate.enter()
    do {
      let savedFile = try await persistence.saveStoredFile(file, contentsOf: sourceURL)
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(
        files,
        for: storedFilesObservationKey
      )
      await operationGate.leave()
      return savedFile
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func preparedStoredFile(
    from sourceURL: URL,
    name rawName: String?,
    contentType rawContentType: String?,
    operation: String
  ) async throws -> InstantStoredFile {
    let name = try resolvedFileName(rawName, sourceURL: sourceURL, operation: operation)
    let contentType = rawContentType?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    let userID = try await resolvedFileUserID(operation: operation)
    let now = configuration.now()
    return InstantStoredFile(
      id: configuration.makeID(),
      appID: configuration.appID,
      name: name,
      contentType: contentType,
      byteCount: 0,
      localPath: "",
      ownerUserID: userID,
      createdAt: now,
      updatedAt: now
    )
  }

  public func storedFiles() async throws -> [InstantStoredFile] {
    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "list files")
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await operationGate.leave()
      return files
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStoredFiles() async throws -> AsyncStream<[InstantStoredFile]> {
    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "observe files")
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      let stream = await storedFilesObservers.observe(
        key: storedFilesObservationKey,
        current: files
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func storedFileContents(id rawID: String) async throws -> InstantStoredFileContents {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "read file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "read file")
      guard let contents = try await persistence.readStoredFileContents(
        appID: configuration.appID,
        fileID: id
      ) else {
        throw validationFailed(
          operation: "read file",
          localID: id,
          message: "No local file exists for id '\(id)'.",
          recovery: "Run 'instant-swift-data files list' to inspect local file ids."
        )
      }
      await operationGate.leave()
      return contents
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func deleteStoredFile(id rawID: String) async throws -> InstantStoredFile {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "delete file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedFileUserID(operation: "delete file")
      guard let file = try await persistence.deleteStoredFile(
        appID: configuration.appID,
        fileID: id
      ) else {
        throw validationFailed(
          operation: "delete file",
          localID: id,
          message: "No local file exists for id '\(id)'.",
          recovery: "Run 'instant-swift-data files list' to inspect local file ids."
        )
      }
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(
        files,
        for: storedFilesObservationKey
      )
      await operationGate.leave()
      return file
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  func activeStoredFilesObservationCount() async -> Int {
    await storedFilesObservers.activeCount(for: storedFilesObservationKey)
  }

  public func appendStreamChunk(
    streamID rawStreamID: String,
    payload: JSONValue
  ) async throws -> InstantStreamChunk {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "append stream chunk",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(
        operation: "append stream chunk",
        noun: "Stream"
      )
      let chunk = try await persistence.appendStreamChunk(
        appID: configuration.appID,
        streamID: streamID,
        chunkID: configuration.makeID(),
        payload: payload,
        userID: userID,
        createdAt: configuration.now()
      )
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: nil,
        afterIndex: nil
      )
      await streamChunksObservers.publish(
        chunks,
        for: streamChunksObservationKey(streamID: streamID)
      )
      await operationGate.leave()
      return chunk
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamChunks(
    streamID rawStreamID: String,
    limit: Int? = nil,
    afterIndex: Int64? = nil
  ) async throws
    -> [InstantStreamChunk]
  {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "read stream chunks",
        message: "Stream chunk limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to read every local chunk."
      )
    }
    if let afterIndex, afterIndex < 0 {
      throw validationFailed(
        operation: "read stream chunks",
        message: "Stream chunk after-index must be greater than or equal to 0.",
        recovery: "Pass a previously emitted chunk index, or omit afterIndex to read every local chunk."
      )
    }
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "read stream chunks",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream chunks", noun: "Stream")
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: limit,
        afterIndex: afterIndex
      )
      await operationGate.leave()
      return chunks
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStreamChunks(
    streamID rawStreamID: String,
    afterIndex: Int64? = nil
  ) async throws
    -> AsyncStream<[InstantStreamChunk]>
  {
    if let afterIndex, afterIndex < 0 {
      throw validationFailed(
        operation: "observe stream chunks",
        message: "Stream chunk after-index must be greater than or equal to 0.",
        recovery: "Pass a previously emitted chunk index, or omit afterIndex to observe every local chunk."
      )
    }
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "observe stream chunks",
      recovery: "Pass a stream id, such as 'chat/lobby'."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(
        operation: "observe stream chunks",
        noun: "Stream"
      )
      let chunks = try await persistence.loadStreamChunks(
        appID: configuration.appID,
        streamID: streamID,
        limit: nil,
        afterIndex: nil
      )
      let stream = await streamChunksObservers.observe(
        key: streamChunksObservationKey(streamID: streamID),
        current: chunks
      )
      await operationGate.leave()
      if let afterIndex {
        return Self.streamChunks(after: afterIndex, from: stream)
      }
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private static func streamChunks(
    after afterIndex: Int64,
    from stream: AsyncStream<[InstantStreamChunk]>
  ) -> AsyncStream<[InstantStreamChunk]> {
    let mapped = AsyncStream<[InstantStreamChunk]>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let task = Task {
      for await chunks in stream {
        mapped.continuation.yield(chunks.filter { $0.index > afterIndex })
      }
      mapped.continuation.finish()
    }
    mapped.continuation.onTermination = { @Sendable _ in
      task.cancel()
    }
    return mapped.stream
  }

  public func createStream(clientID rawClientID: String) async throws -> InstantStreamMetadata {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "create stream",
      recovery: "Pass a stable, unique client id for the writer."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "create stream", noun: "Stream")
      let metadata = try await persistence.createStream(
        appID: configuration.appID,
        streamID: configuration.makeID(),
        clientID: clientID,
        userID: userID,
        createdAt: configuration.now()
      )
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamMetadata(streamID rawStreamID: String) async throws -> InstantStreamMetadata {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "read stream metadata",
      recovery: "Pass the persistent stream id returned by createStream(clientID:)."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream metadata", noun: "Stream")
      guard let metadata = try await persistence.loadStreamMetadata(
        appID: configuration.appID,
        streamID: streamID
      ) else {
        throw streamNotFound(
          operation: "read stream metadata",
          localID: streamID,
          recovery: "Create the stream first, or read by the matching client id."
        )
      }
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamMetadata(clientID rawClientID: String) async throws -> InstantStreamMetadata {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "read stream metadata",
      recovery: "Pass the client id used when creating the stream."
    )

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream metadata", noun: "Stream")
      guard let metadata = try await persistence.loadStreamMetadata(
        appID: configuration.appID,
        clientID: clientID
      ) else {
        throw streamNotFound(
          operation: "read stream metadata",
          localID: clientID,
          recovery: "Create the stream first, or read by the persistent stream id."
        )
      }
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func appendStreamContent(
    streamID rawStreamID: String,
    content: String,
    expectedOffset: Int64? = nil
  ) async throws -> InstantStreamContentAppend {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "append stream content",
      recovery: "Pass the persistent stream id returned by createStream(clientID:)."
    )
    try validateStreamByteOffset(expectedOffset, operation: "append stream content")

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(
        operation: "append stream content",
        noun: "Stream"
      )
      guard let append = try await persistence.appendStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        chunkID: configuration.makeID(),
        content: content,
        expectedOffset: expectedOffset,
        userID: userID,
        createdAt: configuration.now()
      ) else {
        throw streamNotFound(
          operation: "append stream content",
          localID: streamID,
          recovery: "Create the stream before appending content."
        )
      }
      try await publishStreamContentUpdates(streamID: streamID)
      await operationGate.leave()
      return append
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func closeStream(
    streamID rawStreamID: String,
    abortReason rawAbortReason: String? = nil
  ) async throws -> InstantStreamMetadata {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "close stream",
      recovery: "Pass the persistent stream id returned by createStream(clientID:)."
    )
    let abortReason = rawAbortReason?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedAbortReason = abortReason?.isEmpty == true ? nil : abortReason

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "close stream", noun: "Stream")
      guard let metadata = try await persistence.closeStream(
        appID: configuration.appID,
        streamID: streamID,
        abortReason: normalizedAbortReason,
        updatedAt: configuration.now()
      ) else {
        throw streamNotFound(
          operation: "close stream",
          localID: streamID,
          recovery: "Create the stream before closing it."
        )
      }
      try await publishStreamContentUpdates(streamID: streamID)
      await operationGate.leave()
      return metadata
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamContent(
    streamID rawStreamID: String,
    byteOffset: Int64 = 0
  ) async throws -> InstantStreamContentRead {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "read stream content",
      recovery: "Pass a persistent stream id."
    )
    try validateStreamByteOffset(byteOffset, operation: "read stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream content", noun: "Stream")
      guard let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        byteOffset: byteOffset
      ) else {
        throw streamNotFound(
          operation: "read stream content",
          localID: streamID,
          recovery: "Create the stream first, or read by the matching client id."
        )
      }
      await operationGate.leave()
      return read
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func streamContent(
    clientID rawClientID: String,
    byteOffset: Int64 = 0
  ) async throws -> InstantStreamContentRead {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "read stream content",
      recovery: "Pass the client id used when creating the stream."
    )
    try validateStreamByteOffset(byteOffset, operation: "read stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "read stream content", noun: "Stream")
      guard let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        clientID: clientID,
        byteOffset: byteOffset
      ) else {
        throw streamNotFound(
          operation: "read stream content",
          localID: clientID,
          recovery: "Create the stream first, or read by the persistent stream id."
        )
      }
      await operationGate.leave()
      return read
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStreamContent(
    streamID rawStreamID: String,
    byteOffset: Int64 = 0
  ) async throws -> AsyncStream<InstantStreamContentRead> {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "observe stream content",
      recovery: "Pass a persistent stream id."
    )
    try validateStreamByteOffset(byteOffset, operation: "observe stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "observe stream content", noun: "Stream")
      guard let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        byteOffset: byteOffset
      ) else {
        throw streamNotFound(
          operation: "observe stream content",
          localID: streamID,
          recovery: "Create the stream first, or observe by the matching client id."
        )
      }
      let stream = await streamContentObservers.observe(
        key: streamContentObservationKey(streamID: read.metadata.id),
        byteOffset: byteOffset,
        current: read
      )
      await operationGate.leave()
      return await liveStreamContentObservation(
        stream,
        key: "stream-id:\(read.metadata.id):\(byteOffset)",
        streamID: read.metadata.id,
        initialByteOffset: read.byteOffset + read.byteCount
      )
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStreamContent(
    clientID rawClientID: String,
    byteOffset: Int64 = 0
  ) async throws -> AsyncStream<InstantStreamContentRead> {
    let clientID = try validatedNonEmpty(
      rawClientID,
      label: "Stream client id",
      operation: "observe stream content",
      recovery: "Pass the client id used when creating the stream."
    )
    try validateStreamByteOffset(byteOffset, operation: "observe stream content")

    await operationGate.enter()
    do {
      _ = try await resolvedAuthenticatedUserID(operation: "observe stream content", noun: "Stream")
      guard let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        clientID: clientID,
        byteOffset: byteOffset
      ) else {
        throw streamNotFound(
          operation: "observe stream content",
          localID: clientID,
          recovery: "Create the stream first, or observe by the persistent stream id."
        )
      }
      let stream = await streamContentObservers.observe(
        key: streamContentObservationKey(streamID: read.metadata.id),
        byteOffset: byteOffset,
        current: read
      )
      await operationGate.leave()
      return await liveStreamContentObservation(
        stream,
        key: "client-id:\(clientID):\(byteOffset)",
        clientID: clientID,
        initialByteOffset: read.byteOffset + read.byteCount
      )
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func liveStreamContentObservation(
    _ stream: AsyncStream<InstantStreamContentRead>,
    key: String,
    clientID: String? = nil,
    streamID: String? = nil,
    initialByteOffset: Int64
  ) async -> AsyncStream<InstantStreamContentRead> {
    guard configuration.liveTransport != nil else { return stream }
    do {
      try await liveSession.registerStreamReader(
        key: key,
        clientID: clientID,
        streamID: streamID,
        initialByteOffset: initialByteOffset,
        clientEventID: configuration.makeID()
      )
    } catch {
      await recordConnectionError(error)
    }
    return Self.liveObservation(stream) { [weak self] in
      guard let self else { return }
      do {
        try await self.liveSession.unregisterStreamReader(
          key: key,
          clientEventID: self.configuration.makeID()
        )
      } catch {
        await self.recordConnectionError(error)
      }
    }
  }

  func activeStreamChunksObservationCount(streamID rawStreamID: String) async throws -> Int {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "inspect stream observers",
      recovery: "Pass a stream id to inspect."
    )
    return await streamChunksObservers.activeCount(
      for: streamChunksObservationKey(streamID: streamID)
    )
  }

  func activeStreamContentObservationCount(streamID rawStreamID: String) async throws -> Int {
    let streamID = try validatedNonEmpty(
      rawStreamID,
      label: "Stream id",
      operation: "inspect stream content observers",
      recovery: "Pass a stream id to inspect."
    )
    return await streamContentObservers.activeCount(
      for: streamContentObservationKey(streamID: streamID)
    )
  }

  public func createShare(
    rootNamespace rawRootNamespace: String,
    rootID rawRootID: String
  ) async throws -> InstantShareSnapshot {
    let rootNamespace = try validatedNonEmpty(
      rawRootNamespace,
      label: "Share root namespace",
      operation: "create share",
      recovery: "Pass the namespace of the root record to share, such as 'remindersLists'."
    )
    let rootID = try validatedNonEmpty(
      rawRootID,
      label: "Share root id",
      operation: "create share",
      recovery: "Pass the id of the root record to share."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "create share", noun: "Share")
      let activeRootShares = try await persistence.loadActiveShareSnapshots(
        appID: configuration.appID,
        rootNamespace: rootNamespace,
        rootID: rootID
      )
      if let activeRootShare = activeRootShares.first {
        guard activeRootShare.share.ownerUserID == userID else {
          throw shareRootOwnershipPermissionRejected(snapshot: activeRootShare, userID: userID)
        }
        throw duplicateShareRejected(snapshot: activeRootShare)
      }
      let now = configuration.now()
      let shareID = configuration.makeID()
      let share = InstantShare(
        id: shareID,
        appID: configuration.appID,
        rootNamespace: rootNamespace,
        rootID: rootID,
        ownerUserID: userID,
        token: "local-share-\(configuration.makeID())",
        createdAt: now,
        updatedAt: now
      )
      let membership = InstantShareMembership(
        appID: configuration.appID,
        shareID: shareID,
        userID: userID,
        role: .owner,
        acceptedAt: now
      )
      let snapshot = try await persistence.createShare(share, ownerMembership: membership)
      for membership in snapshot.memberships where !membership.isRevoked {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func acceptShare(token rawToken: String) async throws -> InstantShareSnapshot {
    let token = try validatedNonEmpty(
      rawToken,
      label: "Share token",
      operation: "accept share",
      recovery: "Pass the token printed by 'instant-swift-data shares create'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "accept share", noun: "Share")
      guard
        let snapshot = try await persistence.acceptShare(
          appID: configuration.appID,
          token: token,
          userID: userID,
          acceptedAt: configuration.now()
        )
      else {
        throw shareNotFound(operation: "accept share", localID: token)
      }
      for membership in snapshot.memberships where !membership.isRevoked {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func shares() async throws -> [InstantShareSnapshot] {
    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "list shares", noun: "Share")
      let snapshots = try await persistence.loadShareSnapshots(
        appID: configuration.appID,
        userID: userID
      )
      await operationGate.leave()
      return snapshots
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeShares() async throws -> AsyncStream<[InstantShareSnapshot]> {
    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "observe shares", noun: "Share")
      let snapshots = try await persistence.loadShareSnapshots(
        appID: configuration.appID,
        userID: userID
      )
      let stream = await sharesObservers.observe(
        key: sharesObservationKey(userID: userID),
        current: snapshots
      )
      await operationGate.leave()
      return stream
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func updateShareMembershipRole(
    shareID rawShareID: String,
    userID rawTargetUserID: String,
    role: InstantShareRole
  ) async throws -> InstantShareSnapshot {
    let shareID = try validatedNonEmpty(
      rawShareID,
      label: "Share id",
      operation: "update share role",
      recovery: "Pass a share id from 'instant-swift-data shares list'."
    )
    let targetUserID = try validatedNonEmpty(
      rawTargetUserID,
      label: "Share member user id",
      operation: "update share role",
      recovery: "Pass the user id of an accepted share member."
    )
    guard role != .owner else {
      throw validationFailed(
        operation: "update share role",
        localID: shareID,
        message: "The owner role cannot be assigned through membership role updates.",
        recovery: "Create a new share as the intended owner, or assign reader/writer to members."
      )
    }

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "update share role", noun: "Share")
      guard let snapshot = try await persistence.loadShareSnapshot(
        appID: configuration.appID,
        shareID: shareID
      ), !snapshot.share.isRevoked else {
        throw shareNotFound(operation: "update share role", localID: shareID)
      }
      guard snapshot.share.ownerUserID == userID else {
        throw shareRolePermissionRejected(snapshot: snapshot, userID: userID)
      }
      guard snapshot.share.ownerUserID != targetUserID else {
        throw validationFailed(
          operation: "update share role",
          localID: targetUserID,
          message: "The share owner's membership role cannot be changed.",
          recovery: "Update reader/writer roles for accepted non-owner members."
        )
      }
      guard snapshot.memberships.contains(where: { membership in
        membership.userID == targetUserID && !membership.isRevoked
      }) else {
        throw shareMembershipNotFound(
          operation: "update share role",
          shareID: shareID,
          userID: targetUserID
        )
      }
      guard let updated = try await persistence.updateShareMembershipRole(
        appID: configuration.appID,
        shareID: shareID,
        userID: targetUserID,
        role: role,
        updatedAt: configuration.now()
      ) else {
        throw shareMembershipNotFound(
          operation: "update share role",
          shareID: shareID,
          userID: targetUserID
        )
      }
      for membership in updated.memberships where !membership.isRevoked {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return updated
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func revokeShare(id rawShareID: String) async throws -> InstantShareSnapshot {
    let shareID = try validatedNonEmpty(
      rawShareID,
      label: "Share id",
      operation: "revoke share",
      recovery: "Pass a share id from 'instant-swift-data shares list'."
    )

    await operationGate.enter()
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "revoke share", noun: "Share")
      guard let snapshot = try await persistence.loadShareSnapshot(
        appID: configuration.appID,
        shareID: shareID
      ) else {
        throw shareNotFound(operation: "revoke share", localID: shareID)
      }
      guard snapshot.share.ownerUserID == userID else {
        throw sharePermissionRejected(snapshot: snapshot, userID: userID)
      }
      let revoked = try await persistence.revokeShare(
        appID: configuration.appID,
        shareID: shareID,
        revokedAt: configuration.now()
      ) ?? snapshot
      for membership in revoked.memberships {
        try await publishShares(for: membership.userID)
      }
      await operationGate.leave()
      return revoked
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func authorizeSharedRootWrites(
    transaction: InstantStoreTransaction,
    snapshot: InstantStoreSnapshot
  ) async throws {
    let targets = sharedRootWriteTargets(in: transaction, snapshot: snapshot)
    guard !targets.isEmpty else { return }

    for target in targets.sorted(by: sharedRootWriteTargetSort) {
      let snapshots = try await persistence.loadActiveShareSnapshots(
        appID: configuration.appID,
        rootNamespace: target.namespace,
        rootID: target.id
      )
      guard !snapshots.isEmpty else { continue }

      guard let session = try await persistence.loadAuthSession(key: authSessionKey) else {
        throw sharedRootWritePermissionRejected(snapshot: snapshots[0], userID: nil)
      }

      if target.namespace != nil {
        guard canWriteSharedRoot(snapshots, userID: session.userID) else {
          throw sharedRootWritePermissionRejected(
            snapshot: snapshots[0],
            userID: session.userID
          )
        }
      } else {
        let snapshotsByNamespace = Dictionary(grouping: snapshots, by: \.share.rootNamespace)
        for namespace in snapshotsByNamespace.keys.sorted() {
          let namespaceSnapshots = snapshotsByNamespace[namespace] ?? []
          guard canWriteSharedRoot(namespaceSnapshots, userID: session.userID) else {
            throw sharedRootWritePermissionRejected(
              snapshot: namespaceSnapshots[0],
              userID: session.userID
            )
          }
        }
      }
    }
  }

  private func sharedRootWriteTargets(
    in transaction: InstantStoreTransaction,
    snapshot: InstantStoreSnapshot
  ) -> Set<InstantSharedRootWriteTarget> {
    let attributesByID = Dictionary(
      snapshot.attributes.map { ($0.id, $0) },
      uniquingKeysWith: { lhs, _ in lhs }
    )
    var targets: Set<InstantSharedRootWriteTarget> = []

    for operation in transaction.operations {
      switch operation {
      case let .insert(triple), let .merge(triple), let .retract(triple):
        let attribute = attributesByID[triple.attributeID]
        let namespace = sharedRootNamespace(for: triple.attributeID, attribute: attribute)
        targets.insert(InstantSharedRootWriteTarget(namespace: namespace, id: triple.entityID))
        insertRefWriteTargets(
          for: triple.value,
          attribute: attribute,
          snapshot: snapshot,
          attributesByID: attributesByID,
          into: &targets
        )

      case let .insertByLookup(lookup, attributeID, value, _, _),
        let .mergeByLookup(lookup, attributeID, value, _, _),
        let .retractByLookup(lookup, attributeID, value, _, _):
        let attribute = attributesByID[attributeID]
        insertRefWriteTargets(
          for: value,
          attribute: attribute,
          snapshot: snapshot,
          attributesByID: attributesByID,
          into: &targets
        )
        let sourceIDs = entityIDs(
          matching: lookup,
          snapshot: snapshot,
          attributesByID: attributesByID
        )
        if sourceIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
          lookup,
          attributesByID: attributesByID
        ) {
          targets.insert(target)
        }
        guard !sourceIDs.isEmpty else { continue }
        let namespace = sharedRootNamespace(for: attributeID, attribute: attribute)
        for entityID in sourceIDs {
          targets.insert(InstantSharedRootWriteTarget(namespace: namespace, id: entityID))
        }

      case let .deleteEntity(entityID):
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: entityID,
            namespace: nil,
            snapshot: snapshot,
            attributesByID: attributesByID
          )
        )

      case let .deleteEntityInNamespace(entityID, namespace):
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: entityID,
            namespace: namespace,
            snapshot: snapshot,
            attributesByID: attributesByID
          )
        )

      case let .deleteEntityByLookup(lookup):
        let lookupAttribute = lookupAttribute(for: lookup.attributeID, attributesByID: attributesByID)
        let lookupNamespace = lookupAttribute?.namespace
        let entityIDs = entityIDs(
          matching: lookup,
          snapshot: snapshot,
          attributesByID: attributesByID
        )
        if entityIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
          lookup,
          attributesByID: attributesByID
        ) {
          targets.formUnion(
            cascadeDeleteWriteTargets(
              entityID: target.id,
              namespace: target.namespace,
              snapshot: snapshot,
              attributesByID: attributesByID
            )
          )
          targets.insert(target)
        } else {
          for entityID in entityIDs {
            targets.formUnion(
              cascadeDeleteWriteTargets(
                entityID: entityID,
                namespace: lookupNamespace,
                snapshot: snapshot,
                attributesByID: attributesByID
              )
            )
          }
        }

      case .requireEntityMissing, .requireEntityMissingByLookup, .requireEntityExists,
        .requireEntityExistsByLookup, .requireTripleExists, .ruleParams, .ruleParamsByLookup:
        break
      }
    }

    return targets
  }

  private func primaryKeyLookupWriteTarget(
    _ lookup: InstantLookupRef,
    attributesByID: [String: InstantAttribute]
  ) -> InstantSharedRootWriteTarget? {
    let attribute = attributesByID[lookup.attributeID]
    let isPrimaryKey = attribute?.primaryKey == true
      || attribute?.name == "id"
      || lookup.attributeID.hasSuffix("/id")
    guard isPrimaryKey, case let .string(entityID) = lookup.value else { return nil }
    return InstantSharedRootWriteTarget(
      namespace: sharedRootNamespace(for: lookup.attributeID, attribute: attribute),
      id: entityID
    )
  }

  private func sharedRootNamespace(
    for attributeID: String,
    attribute: InstantAttribute?
  ) -> String? {
    if let attribute {
      return attribute.namespace
    }
    let parts = attributeID.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty else { return nil }
    return String(parts[0])
  }

  private func insertRefWriteTargets(
    for value: InstantValue,
    attribute: InstantAttribute?,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute],
    into targets: inout Set<InstantSharedRootWriteTarget>
  ) {
    let targetNamespace: String?
    if let attribute {
      guard attribute.valueType == .ref else { return }
      targetNamespace = attribute.linkNamespace
    } else {
      targetNamespace = nil
    }

    switch value {
    case let .ref(entityID):
      targets.insert(InstantSharedRootWriteTarget(namespace: targetNamespace, id: entityID))

    case let .lookupRef(lookup):
      let entityIDs = entityIDs(
        matching: lookup,
        snapshot: snapshot,
        attributesByID: attributesByID
      )
      if entityIDs.isEmpty, let target = primaryKeyLookupWriteTarget(
        lookup,
        attributesByID: attributesByID
      ) {
        targets.insert(
          InstantSharedRootWriteTarget(
            namespace: targetNamespace ?? target.namespace,
            id: target.id
          )
        )
      }
      for entityID in entityIDs {
        targets.insert(InstantSharedRootWriteTarget(namespace: targetNamespace, id: entityID))
      }

    case .null, .bool, .number, .string, .date, .json:
      break
    }
  }

  private struct RuntimeLookupAttribute {
    var attribute: InstantAttribute
    var isReverse: Bool
    var namespace: String
  }

  private func lookupAttribute(
    for attributeID: String,
    attributesByID: [String: InstantAttribute]
  ) -> RuntimeLookupAttribute? {
    if let attribute = attributesByID[attributeID] {
      return RuntimeLookupAttribute(
        attribute: attribute,
        isReverse: false,
        namespace: attribute.namespace
      )
    }
    guard let attribute = attributesByID.values.first(where: { $0.reverseIdentity == attributeID })
    else {
      return nil
    }
    return RuntimeLookupAttribute(
      attribute: attribute,
      isReverse: true,
      namespace: attribute.linkNamespace
        ?? sharedRootNamespace(for: attributeID, attribute: nil)
        ?? attribute.namespace
    )
  }

  private func cascadeDeleteWriteTargets(
    entityID: String,
    namespace: String?,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute],
    visited: Set<InstantSharedRootWriteTarget> = []
  ) -> Set<InstantSharedRootWriteTarget> {
    let visit = InstantSharedRootWriteTarget(namespace: namespace, id: entityID)
    guard !visited.contains(visit) else { return [] }
    var visited = visited
    visited.insert(visit)
    var targets: Set<InstantSharedRootWriteTarget> = [
      visit
    ]

    let outgoingTriples = snapshot.triples.filter { triple in
      guard triple.entityID == entityID else { return false }
      guard let namespace else { return true }
      return attributesByID[triple.attributeID]?.namespace == namespace
    }
    let incomingTriples = snapshot.triples.filter { triple in
      guard let attribute = attributesByID[triple.attributeID],
        attribute.valueType == .ref,
        case let .ref(targetID) = triple.value
      else {
        return false
      }
      guard targetID == entityID else { return false }
      guard let namespace else { return true }
      return attribute.linkNamespace == namespace
    }

    for triple in outgoingTriples {
      guard let attribute = attributesByID[triple.attributeID],
        attribute.valueType == .ref,
        case let .ref(targetID) = triple.value
      else {
        continue
      }
      targets.insert(InstantSharedRootWriteTarget(namespace: attribute.linkNamespace, id: targetID))
      if attribute.onDeleteReverse == .cascade {
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: targetID,
            namespace: attribute.linkNamespace,
            snapshot: snapshot,
            attributesByID: attributesByID,
            visited: visited
          )
        )
      }
    }

    for triple in incomingTriples {
      let attribute = attributesByID[triple.attributeID]
      targets.insert(
        InstantSharedRootWriteTarget(namespace: attribute?.namespace, id: triple.entityID)
      )
      if attribute?.onDelete == .cascade {
        targets.formUnion(
          cascadeDeleteWriteTargets(
            entityID: triple.entityID,
            namespace: attribute?.namespace,
            snapshot: snapshot,
            attributesByID: attributesByID,
            visited: visited
          )
        )
      }
    }

    return targets
  }

  private func entityIDs(
    matching lookup: InstantLookupRef,
    snapshot: InstantStoreSnapshot,
    attributesByID: [String: InstantAttribute]
  ) -> [String] {
    guard let lookupAttribute = lookupAttribute(
      for: lookup.attributeID,
      attributesByID: attributesByID
    ) else {
      return entityIDs(
        matchingForwardAttribute: lookup.attributeID,
        value: lookup.value,
        snapshot: snapshot
      )
    }

    if lookupAttribute.isReverse {
      guard case let .ref(sourceID) = lookup.value else { return [] }
      let ids = snapshot.triples.compactMap { triple -> String? in
        guard triple.entityID == sourceID,
          triple.attributeID == lookupAttribute.attribute.id
        else {
          return nil
        }
        return triple.value.refValue
      }
      return Array(Set(ids)).sorted()
    }

    return entityIDs(
      matchingForwardAttribute: lookupAttribute.attribute.id,
      value: lookup.value,
      snapshot: snapshot
    )
  }

  private func entityIDs(
    matchingForwardAttribute attributeID: String,
    value expectedValue: InstantLookupValue,
    snapshot: InstantStoreSnapshot
  ) -> [String] {
    let ids = snapshot.triples.compactMap { triple -> String? in
      guard triple.attributeID == attributeID,
        lookupValue(expectedValue, matches: triple.value)
      else {
        return nil
      }
      return triple.entityID
    }
    return Array(Set(ids)).sorted()
  }

  private func lookupValue(_ lookupValue: InstantLookupValue, matches value: InstantValue) -> Bool {
    switch (lookupValue, value) {
    case (.null, .null):
      return true
    case let (.bool(lhs), .bool(rhs)):
      return lhs == rhs
    case let (.number(lhs), .number(rhs)):
      return lhs == rhs
    case let (.string(lhs), .string(rhs)):
      return lhs == rhs
    case let (.date(lhs), .date(rhs)):
      return lhs == rhs
    case let (.json(lhs), .json(rhs)):
      return lhs == rhs
    case let (.ref(lhs), .ref(rhs)):
      return lhs == rhs
    case (.null, _), (.bool, _), (.number, _), (.string, _), (.date, _), (.json, _), (.ref, _):
      return false
    }
  }

  private func canWriteSharedRoot(
    _ snapshots: [InstantShareSnapshot],
    userID: String
  ) -> Bool {
    snapshots.contains { snapshot in
      snapshot.memberships.contains { membership in
        membership.userID == userID
          && !membership.isRevoked
          && membership.role.canWriteSharedRoot
      }
    }
  }

  private func sharedRootWriteTargetSort(
    _ lhs: InstantSharedRootWriteTarget,
    _ rhs: InstantSharedRootWriteTarget
  ) -> Bool {
    if lhs.id == rhs.id {
      return (lhs.namespace ?? "") < (rhs.namespace ?? "")
    }
    return lhs.id < rhs.id
  }

  public func pendingMutations() async -> [PendingMutation] {
    recordActorHop(.outbox)
    return await outbox.pending()
  }

  public func observeMutationLifecycle(
    id rawID: String
  ) async throws -> AsyncStream<InstantMutationLifecycleEvent> {
    let id = try validatedNonEmpty(
      rawID,
      label: "Mutation id",
      operation: "observe mutation lifecycle",
      recovery: "Pass the transaction id used to submit the mutation."
    )
    let state = try await persistence.loadState()
    let current: InstantMutationLifecycleEvent =
      if let mutation = state.snapshot.outbox.first(where: { $0.id == id }),
        mutation.status == .failed
      {
        .failed(mutation)
      } else {
        .waiting
      }
    return await mutationLifecycleObservers.observe(key: id, current: current)
  }

  public func outboxMutations() async -> [PendingMutation] {
    await outbox.all()
  }

  public func outboxTransportMutations(includeFailed: Bool = false) async
    -> [InstantTransportMutation]
  {
    await outbox.all()
      .filter { mutation in
        switch mutation.status {
        case .pending:
          return true
        case .confirmed:
          return false
        case .failed:
          return includeFailed
        }
      }
      .map(InstantTransportMutation.init)
  }

  public func flushPendingMutations(limit: Int? = nil) async throws
    -> InstantMutationTransportFlushResult
  {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "flush outbox",
        message: "Flush limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to flush every pending mutation."
      )
    }

    await enterMutationFlushGate()
    do {
      let request: InstantMutationTransportRequest
      let selectedMutationIDs: Set<String>

      await enterOperationGate()
      do {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        let pending = state.snapshot.outbox
          .filter { $0.status == .pending }
          .sorted(by: PendingMutation.creationOrder)
        let selected = Array(pending.prefix(limit ?? pending.count))
        request = InstantMutationTransportRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          websocketURI: configuration.websocketURI,
          mutations: selected.map(InstantTransportMutation.init)
        )
        selectedMutationIDs = Set(selected.map(\.id))

        guard !selected.isEmpty else {
          recordActorHop(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          await leaveOperationGate()
          await leaveMutationFlushGate()
          return InstantMutationTransportFlushResult(
            request: request,
            results: [],
            confirmed: [],
            failed: [],
            pendingMutationCount: pending.count,
            mutationCount: state.snapshot.outbox.count
          )
        }

        guard try await persistedConnectionState() != .closed else {
          throw InstantError(
            code: .networkFailed,
            operation: "flush outbox",
            message: "Cannot flush \(selected.count) pending mutation(s) while the Instant connection is closed.",
            recovery: "Call connect() before flushing pending mutations."
          )
        }

        await leaveOperationGate()
      } catch {
        await leaveOperationGate()
        throw error
      }

      let response: InstantMutationTransportResponse
      do {
        recordActorHop(.mutationTransport)
        response = try await configuration.mutationTransport.send(request)
      } catch {
        await recordConnectionError(error)
        throw error
      }
      let results = response.results.filter { selectedMutationIDs.contains($0.mutationID) }

      await enterOperationGate()
      do {
        for _ in 0..<5 {
          recordActorHop(.persistence)
          let latestState = try await persistence.loadState()
          let update = InstantOutbox.applyingTransportResults(
            results,
            in: latestState.snapshot.outbox,
            allowedMutationIDs: selectedMutationIDs
          )
          recordActorHop(.persistence)
          let didSave = try await persistence.saveOutbox(
            update.mutations,
            expectedOutboxRevision: latestState.outboxRevision
          )
          if didSave {
            recordActorHop(.outbox)
            await outbox.replace(with: update.mutations)
            if let failed = update.failed.first {
              try await saveErroredConnectionMetadataWithGateHeld(
                message: failed.failureMessage ?? "Mutation '\(failed.id)' failed during transport flush."
              )
            } else if !update.mutations.contains(where: { $0.status == .failed }),
              try await persistedConnectionState() != .closed
            {
              try await saveOpenedConnectionMetadataWithGateHeld()
            }
            _ = try? await publishConnectionStatusWithGateHeld()
            for mutation in update.confirmed + update.failed {
              await publishMutationLifecycle(mutation)
            }
            let remainingPendingCount = update.mutations.filter { $0.status == .pending }.count
            await leaveOperationGate()
            await leaveMutationFlushGate()
            return InstantMutationTransportFlushResult(
              request: request,
              results: results,
              confirmed: update.confirmed,
              failed: update.failed,
              pendingMutationCount: remainingPendingCount,
              mutationCount: update.mutations.count
            )
          }
        }

        throw outboxChangedDuringFlush()
      } catch {
        await leaveOperationGate()
        throw error
      }
    } catch {
      await leaveMutationFlushGate()
      throw error
    }
  }

  @discardableResult
  public func confirmMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        guard let update = InstantOutbox.confirming(id: id, in: state.snapshot.outbox) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw outboxMutationNotFound(id: id)
        }
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: update.mutations)
          _ = try? await publishConnectionStatusWithGateHeld()
          await publishMutationLifecycle(update.mutation)
          await operationGate.leave()
          return update.mutation
        }
      }

      throw outboxChangedDuringStatusUpdate(id: id)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func failMutation(id: String, message: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        guard let update = InstantOutbox.failing(
          id: id,
          message: message,
          in: state.snapshot.outbox
        ) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw outboxMutationNotFound(id: id)
        }
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: update.mutations)
          try await saveErroredConnectionMetadataWithGateHeld(message: message)
          _ = try? await publishConnectionStatusWithGateHeld()
          await publishMutationLifecycle(update.mutation)
          await operationGate.leave()
          return update.mutation
        }
      }

      throw outboxChangedDuringStatusUpdate(id: id)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func retryMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        guard let update = InstantOutbox.retrying(id: id, in: state.snapshot.outbox) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw outboxMutationNotFound(id: id)
        }
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: update.mutations)
          if !update.mutations.contains(where: { $0.status == .failed }),
            try await persistedConnectionState() != .closed
          {
            try await saveOpenedConnectionMetadataWithGateHeld()
          }
          _ = try? await publishConnectionStatusWithGateHeld()
          await operationGate.leave()
          await sendPendingMutationsToLiveSession()
          return update.mutation
        }
      }

      throw outboxChangedDuringStatusUpdate(id: id)
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  public func drainPendingMutationsLocally(limit: Int? = nil) async throws -> [PendingMutation] {
    if let limit, limit < 0 {
      throw validationFailed(
        operation: "drain outbox",
        message: "Drain limit must be greater than or equal to 0.",
        recovery: "Pass a non-negative --limit value, or omit --limit to drain every pending mutation."
      )
    }

    await enterOperationGate()
    do {
      for _ in 0..<5 {
        recordActorHop(.persistence)
        let state = try await persistence.loadState()
        let update = InstantOutbox.confirmingPending(limit: limit, in: state.snapshot.outbox)
        guard !update.confirmed.isEmpty else {
          recordActorHop(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          await leaveOperationGate()
          return []
        }
        recordActorHop(.persistence)
        let didSave = try await persistence.saveOutbox(
          update.mutations,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          recordActorHop(.outbox)
          await outbox.replace(with: update.mutations)
          _ = try? await publishConnectionStatusWithGateHeld()
          for mutation in update.confirmed {
            await publishMutationLifecycle(mutation)
          }
          await leaveOperationGate()
          return update.confirmed
        }
      }

      throw outboxChangedDuringDrain()
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  public func localID(named name: String) async throws -> String {
    try await persistence.localID(named: name, makeID: configuration.makeID)
  }

  public func localIDs() async throws -> [InstantLocalID] {
    try await persistence.loadLocalIDs()
  }

  private func saveAuthSession(_ session: InstantAuthSession) async throws {
    await operationGate.enter()
    do {
      try await persistence.saveAuthSession(session, key: authSessionKey)
      await authSessionObservers.yield(session)
      _ = try? await publishConnectionStatusWithGateHeld()
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }
    _ = try? await syncUserCookieToEndpoint(session)
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

  private func outboxChangedDuringStatusUpdate(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "update outbox mutation",
      localID: id,
      message: "The local outbox changed repeatedly while updating mutation '\(id)'.",
      recovery: "Retry the outbox update after inspecting the current outbox."
    )
  }

  private func outboxChangedDuringDrain() -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "drain outbox",
      message: "The local outbox changed repeatedly while draining pending mutations.",
      recovery: "Retry the drain after inspecting the current outbox."
    )
  }

  private func outboxChangedDuringFlush() -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "flush outbox",
      message: "The local outbox changed repeatedly while applying transport results.",
      recovery: "Retry the flush after inspecting the current outbox."
    )
  }

  private func transactionChangedDuringPersistence(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "persist transaction",
      localID: id,
      message: "The local store changed repeatedly while persisting transaction '\(id)'.",
      recovery: "Retry the transaction after reloading the local cache."
    )
  }

  private func serverTransactionChangedDuringPersistence(id: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "apply server transaction",
      localID: id,
      message: "The local store changed repeatedly while applying server transaction '\(id)'.",
      recovery: "Retry after reloading the local cache."
    )
  }

  private func persistenceChangedDuringMigration(name: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: "migrate local persistence",
      localID: name,
      message: "The local store changed repeatedly while applying migration '\(name)'.",
      recovery: "Retry after reloading the local cache."
    )
  }

  private func validationFailed(
    operation: String,
    namespace: String? = nil,
    path: String? = nil,
    localID: String? = nil,
    message: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      namespace: namespace,
      path: path,
      localID: localID,
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

  private func endpointComponents(path pathComponents: [String]) throws -> URLComponents {
    guard InstantRuntimeConfiguration.isValidAPIURI(configuration.apiURI) else {
      throw Self.endpointValidationFailed(
        name: "apiURI",
        requirement: "an absolute http or https URL with a host and no query or fragment"
      )
    }
    var url = configuration.apiURI
    for pathComponent in pathComponents {
      url.appendPathComponent(pathComponent)
    }
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw endpointFailed(operation: "create Instant endpoint URL")
    }
    return components
  }

  private func endpointFailed(operation: String) -> InstantError {
    InstantError(
      code: .implementationFailed,
      operation: operation,
      message: "The Instant endpoint URL could not be constructed.",
      recovery: "Check the configured apiURI and appID before retrying."
    )
  }

  private func shareNotFound(operation: String, localID: String) -> InstantError {
    validationFailed(
      operation: operation,
      localID: localID,
      message: "Share '\(localID)' was not found or has been revoked.",
      recovery: "Check the share id or token, then create a new share if needed."
    )
  }

  private func streamNotFound(
    operation: String,
    localID: String,
    recovery: String
  ) -> InstantError {
    validationFailed(
      operation: operation,
      localID: localID,
      message: "Stream '\(localID)' was not found.",
      recovery: recovery
    )
  }

  private func validateStreamByteOffset(
    _ byteOffset: Int64?,
    operation: String
  ) throws {
    if let byteOffset, byteOffset < 0 {
      throw validationFailed(
        operation: operation,
        message: "Stream byte offset must be greater than or equal to 0.",
        recovery: "Pass a non-negative byte offset, or omit it to start at the beginning."
      )
    }
  }

  private func shareMembershipNotFound(
    operation: String,
    shareID: String,
    userID: String
  ) -> InstantError {
    validationFailed(
      operation: operation,
      localID: userID,
      message: "User '\(userID)' is not an active member of share '\(shareID)'.",
      recovery: "Have the user accept the share token before updating their role."
    )
  }

  private func sharePermissionRejected(snapshot: InstantShareSnapshot, userID: String) -> InstantError {
    InstantError(
      code: .permissionRejected,
      operation: "revoke share",
      localID: snapshot.share.id,
      message:
        "User '\(userID)' cannot revoke share '\(snapshot.share.id)' owned by '\(snapshot.share.ownerUserID)'.",
      recovery: "Sign in as the share owner before revoking it."
    )
  }

  private func shareRolePermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String
  ) -> InstantError {
    let message =
      "User '\(userID)' cannot update roles for share '\(snapshot.share.id)' owned by '\(snapshot.share.ownerUserID)'."
    return InstantError(
      code: .permissionRejected,
      operation: "update share role",
      localID: snapshot.share.id,
      message: message,
      recovery: "Sign in as the share owner before updating member roles."
    )
  }

  private func duplicateShareRejected(snapshot: InstantShareSnapshot) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    return validationFailed(
      operation: "create share",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message:
        "Shared root '\(root)' already has active share '\(snapshot.share.id)'.",
      recovery: "Use the existing share token, or revoke the current share before creating another one."
    )
  }

  private func shareRootOwnershipPermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String
  ) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    let message =
      "User '\(userID)' cannot create a share for shared root '\(root)' owned by '\(snapshot.share.ownerUserID)'."
    return InstantError(
      code: .permissionRejected,
      operation: "create share",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message: message,
      recovery: "Sign in as the share owner, or ask the owner to manage the existing share."
    )
  }

  private func sharedRootWritePermissionRejected(
    snapshot: InstantShareSnapshot,
    userID: String?
  ) -> InstantError {
    let root = "\(snapshot.share.rootNamespace)/\(snapshot.share.rootID)"
    let role = userID.flatMap { userID in
      snapshot.memberships.first { $0.userID == userID }?.role.rawValue
    }
    let message: String
    if let userID {
      if let role {
        message =
          "User '\(userID)' has \(role) access to shared root '\(root)' and cannot write it."
      } else {
        message =
          "User '\(userID)' is not a member of share '\(snapshot.share.id)' for shared root '\(root)'."
      }
    } else {
      message = "Shared root '\(root)' requires a signed-in owner or writer before it can be written."
    }

    return InstantError(
      code: .permissionRejected,
      operation: "write shared root",
      namespace: snapshot.share.rootNamespace,
      localID: snapshot.share.rootID,
      message: message,
      recovery: "Sign in as the share owner or a writer before mutating the shared record."
    )
  }

  private func normalizedEmail(_ email: String, operation: String) throws -> String {
    let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard email.contains("@"), email.contains(".") else {
      throw authValidationFailed(
        operation: operation,
        message: "Email address '\(email)' is not valid.",
        recovery: "Pass an email address such as user@example.com."
      )
    }
    return email
  }

  private func resolvedRoomUserID(_ userID: String?, operation: String) async throws -> String {
    if let userID = userID?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty {
      return userID
    }
    if let session = try await persistence.loadAuthSession(key: authSessionKey) {
      return session.userID
    }
    throw authValidationFailed(
      operation: operation,
      message: "Room operations require a signed-in user.",
      recovery: "Run 'instant-swift-data auth guest' first, or pass --user-id <id>."
    )
  }

  private func resolvedFileUserID(operation: String) async throws -> String {
    try await resolvedAuthenticatedUserID(operation: operation, noun: "File")
  }

  private func resolvedAuthenticatedUserID(operation: String, noun: String) async throws -> String {
    if let session = try await persistence.loadAuthSession(key: authSessionKey) {
      return session.userID
    }
    throw authValidationFailed(
      operation: operation,
      message: "\(noun) operations require a signed-in user.",
      recovery: "Run 'instant-swift-data auth guest' first."
    )
  }

  private func resolvedFileName(
    _ rawName: String?,
    sourceURL: URL,
    operation: String
  ) throws -> String {
    let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? sourceURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
      throw validationFailed(
        operation: operation,
        message: "File name must not be empty.",
        recovery: "Pass --name <name>, or upload a file path with a non-empty last path component."
      )
    }
    return name
  }

  private func validatedRoom(
    _ room: InstantRoomHandle,
    operation: String
  ) throws -> InstantRoomHandle {
    InstantRoomHandle(
      type: try validatedNonEmpty(
        room.type,
        label: "Room type",
        operation: operation,
        recovery: "Pass a room type, such as 'chat'."
      ),
      id: try validatedNonEmpty(
        room.id,
        label: "Room id",
        operation: operation,
        recovery: "Pass a room id, such as 'lobby'."
      )
    )
  }

  private func validatedNonEmpty(
    _ value: String,
    label: String,
    operation: String,
    recovery: String
  ) throws -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else {
      throw validationFailed(
        operation: operation,
        message: "\(label) must not be empty.",
        recovery: recovery
      )
    }
    return value
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

  private func magicCodeChallengeKey(email: String) -> String {
    "auth.magic_code:\(configuration.appID):\(email)"
  }

  private var processedTransactionIDMetadataKey: String {
    "sync.processed_transaction_id:\(configuration.appID)"
  }

  private var connectionStateMetadataKey: String {
    "connection.state:\(configuration.appID)"
  }

  private var connectionLastErrorMetadataKey: String {
    "connection.last_error:\(configuration.appID)"
  }

  private var appScopedCookieSyncLastUpdatedMetadataKey: String {
    "\(Self.cookieSyncLastUpdatedMetadataKey):\(configuration.appID)"
  }

  private func roomPresenceObservationKey(_ room: InstantRoomHandle) -> InstantRoomPresenceObservationKey {
    InstantRoomPresenceObservationKey(appID: configuration.appID, room: room)
  }

  private func combinedRoomPresence(
    _ localMembers: [InstantRoomPresenceMember],
    room: InstantRoomHandle
  ) async -> [InstantRoomPresenceMember] {
    guard configuration.liveTransport != nil else { return localMembers }
    let currentSessionID = await liveSession.currentSessionID
    let remoteMembers = await liveRoomPresenceState.current(
      room: room,
      excludingSessionID: currentSessionID,
      appID: configuration.appID,
      updatedAt: configuration.now()
    )
    return mergedRoomPresence(local: localMembers, remote: remoteMembers)
  }

  private func mergedRoomPresence(
    local: [InstantRoomPresenceMember],
    remote: [InstantRoomPresenceMember]
  ) -> [InstantRoomPresenceMember] {
    var membersByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
    for member in remote {
      membersByID[member.id] = member
    }
    return membersByID.values.sorted { $0.id < $1.id }
  }

  private func roomTopicObservationKey(
    room: InstantRoomHandle,
    topic: String
  ) -> InstantRoomTopicObservationKey {
    InstantRoomTopicObservationKey(
      appID: configuration.appID,
      room: room,
      topic: topic
    )
  }

  private var storedFilesObservationKey: InstantStoredFilesObservationKey {
    InstantStoredFilesObservationKey(appID: configuration.appID)
  }

  private func streamChunksObservationKey(streamID: String) -> InstantStreamChunksObservationKey {
    InstantStreamChunksObservationKey(appID: configuration.appID, streamID: streamID)
  }

  private func streamContentObservationKey(streamID: String) -> InstantStreamContentObservationKey {
    InstantStreamContentObservationKey(appID: configuration.appID, streamID: streamID)
  }

  private func sharesObservationKey(userID: String) -> InstantSharesObservationKey {
    InstantSharesObservationKey(appID: configuration.appID, userID: userID)
  }

  private func publishStreamContentUpdates(streamID: String) async throws {
    let key = streamContentObservationKey(streamID: streamID)
    let byteOffsets = await streamContentObservers.byteOffsets(for: key)
    for byteOffset in byteOffsets {
      if let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        byteOffset: byteOffset
      ) {
        await streamContentObservers.publish(read, for: key, byteOffset: byteOffset)
      }
    }
  }

  private func publishShares(for userID: String) async throws {
    let snapshots = try await persistence.loadShareSnapshots(
      appID: configuration.appID,
      userID: userID
    )
    await sharesObservers.publish(snapshots, for: sharesObservationKey(userID: userID))
  }

  private static func emptyObservation(_ plan: InstantQueryPlan) -> AsyncStream<InstantQueryEmission> {
    AsyncStream<InstantQueryEmission> { continuation in
      continuation.yield(InstantQueryEmission(queryID: plan.id, sequence: 0, values: []))
      continuation.finish()
    }
  }

  private func recordActorHop(_ boundary: InstantActorHopBoundary) {
    configuration.actorHopRecorder?.record(boundary)
  }

  private func enterOperationGate() async {
    recordActorHop(.operationGate)
    await operationGate.enter()
  }

  private func leaveOperationGate() async {
    recordActorHop(.operationGate)
    await operationGate.leave()
  }

  private func enterMutationFlushGate() async {
    recordActorHop(.mutationFlushGate)
    await mutationFlushGate.enter()
  }

  private func leaveMutationFlushGate() async {
    recordActorHop(.mutationFlushGate)
    await mutationFlushGate.leave()
  }
}

private extension InstantStoreMutationResult {
  func serverApplicationResult(
    processedTransactionID: String,
    pendingMutations: [PendingMutation]
  ) -> InstantServerTransactionApplicationResult {
    InstantServerTransactionApplicationResult(
      mutation: self,
      syncState: InstantSyncState(processedTransactionID: processedTransactionID),
      pendingMutationCount: pendingMutations.filter { $0.status == .pending }.count
    )
  }
}

private extension InstantTripleOperation {
  var localWriteTransactionIDs: [String] {
    switch self {
    case let .merge(triple), let .insert(triple), let .retract(triple):
      return [triple.txID]

    case let .mergeByLookup(_, _, _, txID, _),
      let .insertByLookup(_, _, _, txID, _),
      let .retractByLookup(_, _, _, txID, _):
      return [txID]

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
      .ruleParams, .ruleParamsByLookup:
      return []
    }
  }

  var isRebasedLocalWrite: Bool {
    switch self {
    case .merge, .mergeByLookup, .insert, .insertByLookup, .retract, .retractByLookup,
      .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup:
      return true

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .ruleParams, .ruleParamsByLookup:
      return false
    }
  }
}

private extension InstantStoreSnapshot {
  mutating func removeTriplesWrittenByFailedMutations(_ mutations: [PendingMutation]) {
    let failedTransactionIDs = Set(
      mutations
        .filter { $0.status == .failed }
        .flatMap { mutation in
          [mutation.id, mutation.transaction.id]
            + mutation.transaction.operations.flatMap(\.localWriteTransactionIDs)
        }
        .filter { !$0.isEmpty }
    )
    guard !failedTransactionIDs.isEmpty else { return }
    triples.removeAll { failedTransactionIDs.contains($0.txID) }
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
