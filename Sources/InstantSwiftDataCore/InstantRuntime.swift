import Foundation
import IssueReporting

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
  public var guestAuthenticator: InstantGuestAuthenticator
  public var magicCodeExchange: InstantMagicCodeExchange
  public var idTokenExchange: InstantIDTokenExchange
  public var oauthExchange: InstantOAuthExchange
  public var authTokenInvalidator: InstantAuthTokenInvalidator
  public var mutationTransport: InstantMutationTransportClient
  public var liveTransport: InstantLiveTransportClient?
  public var autoConnectLiveTransport: Bool
  public var liveShareContract: InstantLiveShareContract?
  public var userCookieSyncClient: InstantUserCookieSyncClient
  public var platformAppClient: InstantPlatformAppClient
  public var appBuilderCodeGenerator: AppBuilderCodeGeneratorClient
  public var startupTrace: InstantStartupTrace = .disabled
  package var actorHopRecorder: InstantActorHopRecorder?
  package var isLocalOnly: Bool
  var queryCachePruningPolicy = InstantQueryCachePruningPolicy(
    maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
    maxEntries: 1_000,
    maxEncodedJSONBytes: 1_000_000
  )
  var queryCachePruningWriteInterval = 64
  var liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
    maxAgeMilliseconds: 1_000 * 60 * 60 * 24 * 7 * 52,
    maxEntries: 1_000,
    maxTripleCount: 1_000_000
  )
  var liveQueryResultPruningWriteInterval = 64
  var liveReconnectSleep: @Sendable (UInt64) async throws -> Void = { milliseconds in
    try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
  }
  var onLiveQueryResultPruneActiveKeysCapturedForTesting:
    (@Sendable (Set<String>) async -> Void)? = nil

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    guestAuthenticator: InstantGuestAuthenticator = .local,
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
      guestAuthenticator: guestAuthenticator,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      mutationTransport: .local,
      liveTransport: nil,
      liveShareContract: nil,
      platformAppClient: platformAppClient,
      appBuilderCodeGenerator: appBuilderCodeGenerator
    )
  }

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute],
    now: @escaping @Sendable () -> InstantTimestamp,
    makeID: @escaping @Sendable () -> String,
    refreshTokenVerifier: InstantRefreshTokenVerifier,
    magicCodeExchange: InstantMagicCodeExchange,
    idTokenExchange: InstantIDTokenExchange,
    oauthExchange: InstantOAuthExchange,
    authTokenInvalidator: InstantAuthTokenInvalidator,
    platformAppClient: InstantPlatformAppClient,
    appBuilderCodeGenerator: AppBuilderCodeGeneratorClient
  ) {
    self.init(
      appID: appID,
      persistenceURL: persistenceURL,
      initialAttributes: initialAttributes,
      now: now,
      makeID: makeID,
      refreshTokenVerifier: refreshTokenVerifier,
      guestAuthenticator: .local,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      platformAppClient: platformAppClient,
      appBuilderCodeGenerator: appBuilderCodeGenerator
    )
  }

  public init(
    appID: String,
    persistenceURL: URL,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    },
    makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
    refreshTokenVerifier: InstantRefreshTokenVerifier = .local,
    guestAuthenticator: InstantGuestAuthenticator = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    liveShareContract: InstantLiveShareContract?,
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
      guestAuthenticator: guestAuthenticator,
      magicCodeExchange: magicCodeExchange,
      idTokenExchange: idTokenExchange,
      oauthExchange: oauthExchange,
      authTokenInvalidator: authTokenInvalidator,
      mutationTransport: .local,
      liveTransport: nil,
      liveShareContract: liveShareContract,
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
    guestAuthenticator: InstantGuestAuthenticator = .local,
    magicCodeExchange: InstantMagicCodeExchange = .local,
    idTokenExchange: InstantIDTokenExchange = .local,
    oauthExchange: InstantOAuthExchange = .local,
    authTokenInvalidator: InstantAuthTokenInvalidator = .local,
    mutationTransport: InstantMutationTransportClient = .local,
    liveTransport: InstantLiveTransportClient? = nil,
    liveShareContract: InstantLiveShareContract? = nil,
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
    self.guestAuthenticator = guestAuthenticator
    self.magicCodeExchange = magicCodeExchange
    self.idTokenExchange = idTokenExchange
    self.oauthExchange = oauthExchange
    self.authTokenInvalidator = authTokenInvalidator
    self.mutationTransport = mutationTransport
    self.liveTransport = liveTransport
    self.autoConnectLiveTransport = false
    self.liveShareContract = liveShareContract
    self.userCookieSyncClient = userCookieSyncClient
    self.platformAppClient = platformAppClient
    self.appBuilderCodeGenerator = appBuilderCodeGenerator
    self.actorHopRecorder = nil
    self.isLocalOnly = false
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

private actor InstantRuntimeActiveRoomPresenceState {
  private var userIDsByRoom: [InstantRoomHandle: Set<String>] = [:]

  func activate(userID: String, in room: InstantRoomHandle) {
    userIDsByRoom[room, default: []].insert(userID)
  }

  func deactivate(userID: String, in room: InstantRoomHandle) {
    userIDsByRoom[room]?.remove(userID)
    if userIDsByRoom[room]?.isEmpty == true {
      userIDsByRoom[room] = nil
    }
  }

  func removeAll(in room: InstantRoomHandle) {
    userIDsByRoom[room] = nil
  }

  func activeMembers(
    _ members: [InstantRoomPresenceMember],
    in room: InstantRoomHandle
  ) -> [InstantRoomPresenceMember] {
    guard let activeUserIDs = userIDsByRoom[room] else { return [] }
    return members.filter { activeUserIDs.contains($0.userID) }
  }
}

private struct InstantLiveMutationEncodingFailure: Sendable {
  var message: String
  var mutationID: String
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
    var observerCount: Int
    var presence: [String: JSONValue]?
    var queuedBroadcasts: [QueuedBroadcast] = []
    var isConnected = false
  }

  private struct RegisteredStreamReader: Sendable {
    var reader: InstantLiveStreamReaderState
    var observerCount: Int
  }

  private struct BufferedStreamAppend: Sendable {
    var chunks: [String]
    var offset: Int64
    var done: Bool
    var abortReason: String?

    var endOffset: Int64 {
      offset + chunks.reduce(Int64(0)) { $0 + Int64($1.utf8.count) }
    }
  }

  private struct RegisteredStreamWriter: Sendable {
    var clientID: String
    var reconnectToken: String
    var streamID: String
    var buffer: [BufferedStreamAppend] = []
  }

  private var session: InstantLiveWebSocketSession?
  private var receiverTask: Task<Void, Never>?
  private var registeredQueries: [String: RegisteredQuery] = [:]
  private var serverAttributes: [InstantLiveJSONValue] = []
  private var inFlightMutationIDs: Set<String> = []
  private var inFlightMutationStepCounts: [String: Int] = [:]
  /// When each in-flight mutation send began, so an
  /// unacknowledged mutation is retried instead of blocking its queue forever.
  private var inFlightMutationDeadlines: [String: Date] = [:]
  private var hasReportedDeepOutbox = false
  /// Bounds the number of transactions sharing the socket at once.
  static let maximumMutationsPerFlush = 50
  /// Bounds the low-level transaction work sharing the socket at once. One
  /// oversize mutation is still allowed through when the window is empty so
  /// an old large write cannot permanently block ordered delivery.
  static let maximumTransactionStepsInFlight = 256
  /// An online write that is not acknowledged this quickly is a real problem,
  /// not a slow network: surface it and retry rather than waiting minutes.
  static let inFlightMutationTimeout: TimeInterval = 10
  static let deepOutboxReportingThreshold = 100
  private var registeredRooms: [InstantRoomHandle: RegisteredRoom] = [:]
  private var registeredStreamReaders: [String: RegisteredStreamReader] = [:]
  private var pendingStreamStarts:
    [String: AsyncThrowingStream<InstantLiveStartStreamOK, Error>.Continuation] = [:]
  private var pendingStreamFlushes:
    [String: AsyncThrowingStream<InstantLiveStreamFlushed, Error>.Continuation] = [:]
  private var registeredStreamWriters: [String: RegisteredStreamWriter] = [:]
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

  func startStream(
    clientID: String,
    reconnectToken: String,
    ruleParams: InstantLiveJSONValue? = nil,
    clientEventID: String,
    registersWriter: Bool = true
  ) async throws -> InstantLiveStartStreamOK {
    guard let session, isOpened else {
      throw InstantError(
        code: .networkFailed,
        operation: "start Instant live stream",
        message: "The Instant live session is not open.",
        recovery: "Connect before creating a live write stream."
      )
    }
    let response = AsyncThrowingStream<InstantLiveStartStreamOK, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    pendingStreamStarts[clientEventID] = response.continuation
    do {
      try await send(
        .startStream(
          clientID: clientID,
          reconnectToken: reconnectToken,
          ruleParams: ruleParams,
          clientEventID: clientEventID
        ),
        through: session
      )
      let responseStream = response.stream
      let acknowledged = try await instantLiveWithTimeout(
        operation: "start Instant live stream",
        timeoutMilliseconds: 10_000
      ) {
        var iterator = responseStream.makeAsyncIterator()
        return try await iterator.next()
      }
      guard let started = acknowledged else {
        throw InstantError(
          code: .networkFailed,
          operation: "start Instant live stream",
          serverEventID: clientEventID,
          message: "Instant closed the start-stream response without an acknowledgement.",
          recovery: "Reconnect and retry the write stream with the same reconnect token."
        )
      }
      pendingStreamStarts[clientEventID] = nil
      if registersWriter {
        registeredStreamWriters[started.streamID] = RegisteredStreamWriter(
          clientID: clientID,
          reconnectToken: reconnectToken,
          streamID: started.streamID
        )
      }
      return started
    } catch {
      pendingStreamStarts[clientEventID]?.finish(throwing: error)
      pendingStreamStarts[clientEventID] = nil
      throw error
    }
  }

  func appendStream(
    streamID: String,
    chunks: [String],
    offset: Int64,
    done: Bool,
    abortReason: String?,
    clientEventID: String
  ) async throws {
    guard let session, isOpened, var writer = registeredStreamWriters[streamID] else { return }
    let buffered = BufferedStreamAppend(
      chunks: chunks,
      offset: offset,
      done: done,
      abortReason: abortReason
    )
    writer.buffer.append(buffered)
    registeredStreamWriters[streamID] = writer
    try await sendStreamAppend(buffered, streamID: streamID, through: session, clientEventID: clientEventID)
  }

  func finishStream(
    streamID: String,
    offset: Int64,
    abortReason: String?,
    clientEventID: String
  ) async throws {
    guard registeredStreamWriters[streamID] != nil else { return }
    let response = AsyncThrowingStream<InstantLiveStreamFlushed, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    pendingStreamFlushes[streamID] = response.continuation
    do {
      try await appendStream(
        streamID: streamID,
        chunks: [],
        offset: offset,
        done: true,
        abortReason: abortReason,
        clientEventID: clientEventID
      )
      let responseStream = response.stream
      let acknowledged = try await instantLiveWithTimeout(
        operation: "finish Instant live stream",
        timeoutMilliseconds: 10_000
      ) {
        var iterator = responseStream.makeAsyncIterator()
        return try await iterator.next()
      }
      guard let flushed = acknowledged, flushed.done else {
        throw InstantError(
          code: .networkFailed,
          operation: "finish Instant live stream",
          message: "Instant did not confirm the terminal stream flush.",
          recovery: "Reconnect the writer and resend its terminal append."
        )
      }
      pendingStreamFlushes[streamID] = nil
    } catch {
      pendingStreamFlushes[streamID]?.finish(throwing: error)
      pendingStreamFlushes[streamID] = nil
      throw error
    }
  }

  func reconnectStreamWriters() async throws {
    guard isOpened, let makeID else { return }
    for streamID in registeredStreamWriters.keys.sorted() {
      guard var writer = registeredStreamWriters[streamID] else { continue }
      let started = try await startStream(
        clientID: writer.clientID,
        reconnectToken: writer.reconnectToken,
        clientEventID: makeID(),
        registersWriter: false
      )
      guard started.streamID == streamID else {
        throw InstantError(
          code: .decodeFailed,
          operation: "reconnect Instant live stream writer",
          serverEventID: started.clientEventID,
          message: "Instant resolved writer '\(writer.clientID)' to unexpected stream '\(started.streamID)'.",
          recovery: "Reconnect using the original writer client id and reconnect token."
        )
      }
      writer.buffer.removeAll { $0.endOffset <= started.offset }
      registeredStreamWriters[streamID] = writer
      guard let session else { throw CancellationError() }
      for append in writer.buffer {
        try await sendStreamAppend(
          append,
          streamID: streamID,
          through: session,
          clientEventID: makeID()
        )
      }
    }
  }

  private func sendStreamAppend(
    _ append: BufferedStreamAppend,
    streamID: String,
    through session: InstantLiveWebSocketSession,
    clientEventID: String
  ) async throws {
    try await send(
      .appendStream(
        streamID: streamID,
        chunks: append.chunks,
        offset: append.offset,
        done: append.done,
        abortReason: append.abortReason,
        clientEventID: clientEventID
      ),
      through: session
    )
  }

  func ownsStreamWriter(streamID: String) -> Bool {
    registeredStreamWriters[streamID] != nil
  }

  func open(
    request: InstantLiveSessionRequest,
    transport: InstantLiveTransportClient,
    makeID: @escaping @Sendable () -> String
  ) async throws {
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "transport",
      event: "websocket.session-opening",
      message: "Opening a low-level Instant WebSocket session.",
      metadata: [
        "appID": request.appID,
        "websocketHost": request.websocketURI.host ?? "unknown",
        "hasRefreshToken": String(request.refreshToken?.isEmpty == false),
      ]
    )
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
    inFlightMutationStepCounts.removeAll()
    inFlightMutationDeadlines.removeAll()
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
        InstantDiagnostics.shared.record(
          .notice,
          subsystem: "instant-swift-data-core",
          category: "transport",
          event: "websocket.session-opened",
          message: "Low-level Instant WebSocket session opened.",
          metadata: [
            "appID": request.appID,
            "sessionID": initOK.sessionID,
            "serverAttributeCount": String(initOK.attrs.count),
          ]
        )

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
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "transport",
        event: "websocket.session-open-failed",
        message: "Low-level Instant WebSocket session failed to open.",
        metadata: ["appID": request.appID]
      )
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
    clientEventID: String,
    requiresServerAcknowledgement: Bool = false
  ) async throws {
    if var registration = registeredQueries[key] {
      registration.observerCount += 1
      registeredQueries[key] = registration
      guard requiresServerAcknowledgement, let session, isOpened else { return }
      // Upstream queryOnce always sends add-query, even when this exact query is
      // already subscribed. Instant answers with add-query-exists, which gives
      // the one-shot operation a fresh server acknowledgement while retaining
      // the materialized query store.
      try await send(.addQuery(query, clientEventID: clientEventID), through: session)
      return
    }
    registeredQueries[key] = RegisteredQuery(query: query, observerCount: 1)
    guard let session, isOpened else { return }
    try await send(.addQuery(query, clientEventID: clientEventID), through: session)
  }

  @discardableResult
  func unregisterQuery(key: String, clientEventID: String) async throws -> Bool {
    guard var registration = registeredQueries[key] else { return false }
    if registration.observerCount > 1 {
      registration.observerCount -= 1
      registeredQueries[key] = registration
      return false
    }
    registeredQueries[key] = nil
    guard let session, isOpened else { return true }
    try await send(
      .removeQuery(registration.query, clientEventID: clientEventID),
      through: session
    )
    return true
  }

  @discardableResult
  func retireRejectedQuery(key: String) -> Bool {
    registeredQueries.removeValue(forKey: key) != nil
  }

  func activeQueryKeys() -> Set<String> {
    Set(registeredQueries.keys)
  }

  /// The raw attribute payload the server sent in the current session's `init-ok`, or the most
  /// recent `refresh-ok` that carried one.
  func currentServerAttributes() -> [InstantLiveJSONValue] {
    serverAttributes
  }

  func mutationReservationCountsForTesting() -> (
    ids: Int,
    stepCounts: Int,
    deadlines: Int
  ) {
    (
      ids: inFlightMutationIDs.count,
      stepCounts: inFlightMutationStepCounts.count,
      deadlines: inFlightMutationDeadlines.count
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

  func recordDeliveredStreamAppend(
    _ append: InstantLiveStreamAppend,
    seenOffset: Int64
  ) async {
    guard let clientEventID = append.clientEventID else { return }
    for key in registeredStreamReaders.keys.sorted() {
      guard let registration = registeredStreamReaders[key],
        await registration.reader.subscriptionEventID == clientEventID
      else {
        continue
      }
      await registration.reader.recordSeenOffset(seenOffset)
      await registration.reader.resetFileFetchFailures()
      return
    }
  }

  func recordStreamFileFetchFailure(
    clientEventID: String?
  ) async -> InstantLiveStreamReaderDisposition {
    guard let clientEventID else { return .ignored }
    for key in registeredStreamReaders.keys.sorted() {
      guard let registration = registeredStreamReaders[key],
        await registration.reader.subscriptionEventID == clientEventID
      else {
        continue
      }
      return await registration.reader.recordFileFetchFailure()
    }
    return .ignored
  }

  func retireRejectedStreamReader(
    clientEventID: String?,
    message: String
  ) async -> Bool {
    guard let clientEventID else { return false }
    for key in registeredStreamReaders.keys.sorted() {
      guard let registration = registeredStreamReaders[key],
        await registration.reader.subscriptionEventID == clientEventID
      else {
        continue
      }
      _ = await registration.reader.recordServerFailure(
        clientEventID: clientEventID,
        message: message
      )
      registeredStreamReaders[key] = nil
      return true
    }
    return false
  }

  @discardableResult
  func sendMutations(
    _ mutations: [InstantTransportMutation]
  ) async throws -> [InstantLiveMutationEncodingFailure] {
    guard let session, isOpened else {
      InstantDiagnostics.shared.record(
        .warning,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.flush.skipped-not-open",
        message: "Skipped an outbox flush because the live session is not open.",
        metadata: [
          "pendingInputCount": String(mutations.count),
          "sessionPresent": String(session != nil),
          "isOpened": String(isOpened),
        ]
      )
      return []
    }
    reclaimExpiredInFlightMutations()
    var encodingFailures: [InstantLiveMutationEncodingFailure] = []
    let pending = mutations
      .sorted(by: Self.mutationOrder)
      .filter { $0.status == .pending }
    reportDeepOutboxIfNeeded(pendingCount: pending.count)
    var sentCount = 0
    var skippedAlreadyInFlight = 0
    var stoppedForMutationBudget = false
    var stoppedForStepBudget = false
    // High-frequency path: keep at debug so host dual-write bridges that default
    // to minimumLevel `.info` (Scribe InstantDBLogger) do not re-ingest every flush
    // into Instant as multi-hundred-op debug-log batches (feedback → multi-GB idle).
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.flush.started",
      message: "Starting an Instant outbox flush against the live transport.",
      metadata: [
        "pendingCount": String(pending.count),
        "inFlightMutationCount": String(inFlightMutationIDs.count),
        "inFlightStepCount": String(inFlightMutationStepCounts.values.reduce(0, +)),
        "maxMutationsPerFlush": String(Self.maximumMutationsPerFlush),
        "maxStepsInFlight": String(Self.maximumTransactionStepsInFlight),
      ]
    )
    for mutation in pending {
      let inFlightMutationCount = inFlightMutationIDs.count
      let inFlightStepCount = inFlightMutationStepCounts.values.reduce(0, +)
      if inFlightMutationCount >= Self.maximumMutationsPerFlush {
        stoppedForMutationBudget = true
        break
      }
      let mutationStepCount = mutation.txSteps.count
      let fitsStepBudget =
        inFlightStepCount + mutationStepCount <= Self.maximumTransactionStepsInFlight
      // Preserve outbox order. Wait for an acknowledgement when the next
      // mutation does not fit, except that an empty window admits one oversize
      // mutation so it cannot become a permanent head-of-line blocker.
      if !(fitsStepBudget || inFlightMutationCount == 0) {
        stoppedForStepBudget = true
        InstantDiagnostics.shared.record(
          .notice,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.flush.head-of-line-wait",
          message:
            "Outbox flush stopped at a head-of-line mutation that does not fit the in-flight step budget.",
          metadata: [
            "mutationID": mutation.mutationID,
            "mutationStepCount": String(mutationStepCount),
            "inFlightMutationCount": String(inFlightMutationCount),
            "inFlightStepCount": String(inFlightStepCount),
            "maxStepsInFlight": String(Self.maximumTransactionStepsInFlight),
            "oversizeHead": String(mutationStepCount > Self.maximumTransactionStepsInFlight),
          ],
          correlationID: mutation.mutationID
        )
        break
      }
      guard inFlightMutationIDs.insert(mutation.mutationID).inserted else {
        skippedAlreadyInFlight += 1
        continue
      }
      let txSteps: [InstantTransportStep]
      do {
        txSteps = try InstantLiveMutationEncoder.resolveAttributeIDs(
          in: mutation.txSteps,
          attrs: serverAttributes
        )
      } catch {
        inFlightMutationIDs.remove(mutation.mutationID)
        inFlightMutationStepCounts[mutation.mutationID] = nil
        inFlightMutationDeadlines[mutation.mutationID] = nil
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.encoding-quarantined",
          message: "Quarantined a mutation that cannot be encoded against server attributes.",
          metadata: [
            "mutationID": mutation.mutationID,
            "mutationStepCount": String(mutationStepCount),
          ],
          correlationID: mutation.mutationID
        )
        reportIssue(
          """
          Instant quarantined a mutation it can never deliver.

          \(String(describing: error))

          Mutation: \(mutation.mutationID)
          Deploy the schema (npx instant-cli push schema) so this attribute \
          exists on the server, then the quarantined mutation can be retried.
          """
        )
        encodingFailures.append(
          InstantLiveMutationEncodingFailure(
            message: String(describing: error),
            mutationID: mutation.mutationID
          )
        )
        continue
      }
      // Reserve the complete in-flight window before suspension. A very fast
      // transact-ok may be received while `send` is still awaiting the
      // transport; that acknowledgement must be able to clear every piece of
      // reservation state without the resumed sender recreating part of it.
      inFlightMutationStepCounts[mutation.mutationID] = mutationStepCount
      inFlightMutationDeadlines[mutation.mutationID] =
        Date().addingTimeInterval(Self.inFlightMutationTimeout)
      do {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.send",
          message: "Sending an outbox mutation on the live Instant transport.",
          metadata: [
            "mutationID": mutation.mutationID,
            "mutationStepCount": String(mutationStepCount),
            "resolvedStepCount": String(txSteps.count),
            "inFlightMutationCount": String(inFlightMutationIDs.count),
            "inFlightStepCount": String(
              inFlightMutationStepCounts.values.reduce(0, +)
            ),
            "ackTimeoutSeconds": String(Int(Self.inFlightMutationTimeout)),
          ],
          correlationID: mutation.mutationID
        )
        try await send(
          try .transact(txSteps, clientEventID: mutation.mutationID),
          through: session
        )
        sentCount += 1
      } catch {
        inFlightMutationIDs.remove(mutation.mutationID)
        inFlightMutationStepCounts[mutation.mutationID] = nil
        inFlightMutationDeadlines[mutation.mutationID] = nil
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.send-failed",
          message: "Live transport send failed for an outbox mutation.",
          metadata: [
            "mutationID": mutation.mutationID,
            "mutationStepCount": String(mutationStepCount),
          ],
          correlationID: mutation.mutationID
        )
        throw error
      }
    }
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.flush.finished",
      message: "Finished one Instant outbox flush pass.",
      metadata: [
        "pendingCount": String(pending.count),
        "sentCount": String(sentCount),
        "encodingFailureCount": String(encodingFailures.count),
        "skippedAlreadyInFlight": String(skippedAlreadyInFlight),
        "stoppedForMutationBudget": String(stoppedForMutationBudget),
        "stoppedForStepBudget": String(stoppedForStepBudget),
        "inFlightMutationCount": String(inFlightMutationIDs.count),
        "inFlightStepCount": String(inFlightMutationStepCounts.values.reduce(0, +)),
      ]
    )
    return encodingFailures
  }

  /// Releases mutations the server never acknowledged so the next flush retries
  /// them, instead of leaving them blocked for the lifetime of the session.
  private func reclaimExpiredInFlightMutations() {
    let now = Date()
    let expired = inFlightMutationDeadlines.filter { $0.value <= now }.map(\.key)
    guard !expired.isEmpty else { return }
    for mutationID in expired {
      inFlightMutationIDs.remove(mutationID)
      inFlightMutationStepCounts[mutationID] = nil
      inFlightMutationDeadlines[mutationID] = nil
      InstantDiagnostics.shared.record(
        .warning,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.mutation.ack-timeout-reclaim",
        message:
          "Reclaimed an in-flight mutation that received no server acknowledgement within the timeout.",
        metadata: [
          "mutationID": mutationID,
          "ackTimeoutSeconds": String(Int(Self.inFlightMutationTimeout)),
          "remainingInFlightCount": String(inFlightMutationIDs.count),
        ],
        correlationID: mutationID
      )
    }
    InstantDiagnostics.shared.record(
      .warning,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.ack-timeout-batch",
      message:
        "Instant did not acknowledge in-flight mutation(s) within the timeout and is retrying them.",
      metadata: [
        "expiredCount": String(expired.count),
        "ackTimeoutSeconds": String(Int(Self.inFlightMutationTimeout)),
        "expiredMutationIDs": expired.prefix(12).joined(separator: ","),
      ]
    )
    reportIssue(
      """
      Instant did not acknowledge \(expired.count) mutation(s) within \
      \(Int(Self.inFlightMutationTimeout))s and is retrying them.

      If this repeats, the device is writing faster than the transport can \
      confirm. Inspect the Instant WebSocket endpoint and server response.
      """
    )
  }

  private func reportDeepOutboxIfNeeded(pendingCount: Int) {
    guard pendingCount >= Self.deepOutboxReportingThreshold else {
      hasReportedDeepOutbox = false
      return
    }
    guard !hasReportedDeepOutbox else { return }
    hasReportedDeepOutbox = true
    InstantDiagnostics.shared.record(
      .error,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.deep-pending",
      message:
        "Instant has a deep undelivered outbox; local writes are durable but not reaching the server.",
      metadata: [
        "pendingCount": String(pendingCount),
        "deepOutboxThreshold": String(Self.deepOutboxReportingThreshold),
        "inFlightMutationCount": String(inFlightMutationIDs.count),
      ]
    )
    reportIssue(
      """
      Instant has \(pendingCount) undelivered mutations queued locally.

      Local writes are durable, but nothing is reaching the server. Check the \
      connection state and any quarantined mutation reported above; a single \
      undeliverable mutation or a failing transport will hold the whole queue.
      """
    )
  }

  func joinRoom(
    _ room: InstantRoomHandle,
    clientEventID: String
  ) async throws {
    if var registration = registeredRooms[room] {
      registration.observerCount += 1
      registeredRooms[room] = registration
      return
    }
    registeredRooms[room] = RegisteredRoom(room: room, observerCount: 1)
    guard let session, isOpened else { return }
    try await send(.joinRoom(room, clientEventID: clientEventID), through: session)
  }

  func leaveRoom(
    _ room: InstantRoomHandle,
    clientEventID: String
  ) async throws {
    guard var registration = registeredRooms[room] else { return }
    if registration.observerCount > 1 {
      registration.observerCount -= 1
      registeredRooms[room] = registration
      return
    }
    registeredRooms[room] = nil
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
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "transport",
      event: "websocket.message-decoded",
      message: "Decoded an Instant WebSocket server message.",
      metadata: [
        "op": event.op,
        "generation": String(generation),
        "sessionID": sessionID ?? "none",
      ]
    )
    switch event {
    case let .refreshOK(refreshOK) where !refreshOK.attrs.isEmpty:
      serverAttributes = refreshOK.attrs
    case let .transactOK(transactOK):
      if let clientEventID = transactOK.clientEventID {
        inFlightMutationIDs.remove(clientEventID)
        inFlightMutationStepCounts[clientEventID] = nil
        inFlightMutationDeadlines[clientEventID] = nil
      }
    case let .error(error):
      if let clientEventID = error.clientEventID {
        inFlightMutationIDs.remove(clientEventID)
        inFlightMutationStepCounts[clientEventID] = nil
        inFlightMutationDeadlines[clientEventID] = nil
        pendingStreamStarts[clientEventID]?.finish(
          throwing: InstantError(
            code: .networkFailed,
            operation: "start Instant live stream",
            serverEventID: clientEventID,
            message: error.message,
            recovery: "Inspect the stream create permission and reconnect token."
          )
        )
        pendingStreamStarts[clientEventID] = nil
      }
    case let .startStreamOK(started):
      if let clientEventID = started.clientEventID {
        pendingStreamStarts[clientEventID]?.yield(started)
        pendingStreamStarts[clientEventID]?.finish()
      }
    case let .streamFlushed(flushed):
      pendingStreamFlushes[flushed.streamID]?.yield(flushed)
      if flushed.done {
        pendingStreamFlushes[flushed.streamID]?.finish()
      }
      if var writer = registeredStreamWriters[flushed.streamID] {
        writer.buffer.removeAll { $0.endOffset <= flushed.offset }
        if flushed.done {
          registeredStreamWriters[flushed.streamID] = nil
        } else {
          registeredStreamWriters[flushed.streamID] = writer
        }
      }
    case let .appendFailed(failed):
      guard registeredStreamWriters[failed.streamID] == nil else {
        throw InstantError(
          code: .networkFailed,
          operation: "retry Instant live stream writer",
          message: "Instant could not flush stream '\(failed.streamID)'.",
          recovery: "Reconnect the writer with its original token and resend unflushed chunks."
        )
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
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "transport",
      event: "websocket.message-sending",
      message: "Sending an Instant WebSocket message.",
      metadata: [
        "op": message.op,
        "fieldCount": String(message.fields.count),
        "sessionID": sessionID ?? "none",
      ],
      correlationID: message.clientEventID
    )
    do {
      try await instantLiveWithTimeout(
        operation: "send Instant live session message",
        timeoutMilliseconds: 10_000
      ) {
        try await session.send(message)
      }
      // Routine send chatter is debug; failures remain error-level.
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "transport",
        event: "websocket.message-sent",
        message: "Sent an Instant WebSocket message.",
        metadata: [
          "op": message.op,
          "clientEventID": message.clientEventID ?? "",
        ],
        correlationID: message.clientEventID
      )
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "transport",
        event: "websocket.message-send-failed",
        message: "Failed to send an Instant WebSocket message.",
        metadata: ["op": message.op],
        correlationID: message.clientEventID
      )
      throw error
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
    for continuation in pendingStreamStarts.values {
      continuation.finish(throwing: failure ?? CancellationError())
    }
    pendingStreamStarts.removeAll()
    for continuation in pendingStreamFlushes.values {
      continuation.finish(throwing: failure ?? CancellationError())
    }
    pendingStreamFlushes.removeAll()
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
    inFlightMutationStepCounts.removeAll()
    inFlightMutationDeadlines.removeAll()
    for room in Array(registeredRooms.keys) {
      registeredRooms[room]?.isConnected = false
    }
    isOpened = false
    for continuation in pendingStreamStarts.values {
      continuation.finish(throwing: CancellationError())
    }
    pendingStreamStarts.removeAll()
    for continuation in pendingStreamFlushes.values {
      continuation.finish(throwing: CancellationError())
    }
    pendingStreamFlushes.removeAll()
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
  var transaction: InstantStoreTransaction
  var application: InstantServerTransactionApplicationResult
  var confirmedMutation: PendingMutation?
  var mergedAttributeCount: Int
}

private actor InstantLiveQueryAcknowledgementState {
  private enum Outcome: Sendable {
    case acknowledged
    case rejected(InstantError)
  }

  private var revisions: [String: Int] = [:]
  private var outcomes: [String: (revision: Int, outcome: Outcome)] = [:]
  private var waiters: [String: [UUID: AsyncThrowingStream<Void, Error>.Continuation]] = [:]

  func revision(for key: String) -> Int {
    revisions[key, default: 0]
  }

  func record(key: String) {
    revisions[key, default: 0] += 1
    outcomes[key] = (revisions[key, default: 0], .acknowledged)
    let continuations = waiters.removeValue(forKey: key).map { Array($0.values) } ?? []
    for continuation in continuations {
      continuation.yield(())
      continuation.finish()
    }
  }

  func reject(key: String, error: InstantError) {
    revisions[key, default: 0] += 1
    outcomes[key] = (revisions[key, default: 0], .rejected(error))
    let continuations = waiters.removeValue(forKey: key).map { Array($0.values) } ?? []
    for continuation in continuations {
      continuation.finish(throwing: error)
    }
  }

  func wait(for key: String, after observedRevision: Int) async throws {
    if revisions[key, default: 0] > observedRevision {
      if let outcome = outcomes[key], outcome.revision > observedRevision {
        try resolve(outcome.outcome)
      }
      return
    }
    let id = UUID()
    let stream = AsyncThrowingStream<Void, Error>(bufferingPolicy: .bufferingNewest(1)) {
      continuation in
      if revisions[key, default: 0] > observedRevision {
        if let outcome = outcomes[key], outcome.revision > observedRevision {
          switch outcome.outcome {
          case .acknowledged:
            continuation.yield(())
            continuation.finish()
          case let .rejected(error):
            continuation.finish(throwing: error)
          }
        } else {
          continuation.yield(())
          continuation.finish()
        }
      } else {
        waiters[key, default: [:]][id] = continuation
        continuation.onTermination = { @Sendable _ in
          Task {
            await self.cancelWaiter(key: key, id: id)
          }
        }
      }
    }
    var iterator = stream.makeAsyncIterator()
    _ = try await iterator.next()
  }

  private func resolve(_ outcome: Outcome) throws {
    if case let .rejected(error) = outcome {
      throw error
    }
  }

  private func cancelWaiter(key: String, id: UUID) {
    waiters[key]?[id] = nil
    if waiters[key]?.isEmpty == true {
      waiters[key] = nil
    }
  }
}

// SAFETY: `lock` protects every read and write of the cadence counter.
private final class InstantQueryCachePruningCadence: @unchecked Sendable {
  private let lock = NSLock()
  private var writesSinceLastPrune = 0

  func shouldPrune(afterSuccessfulWriteWithInterval interval: Int) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let interval = max(1, interval)
    if writesSinceLastPrune >= interval - 1 {
      writesSinceLastPrune = 0
      return true
    }
    writesSinceLastPrune += 1
    return false
  }
}

private actor InstantAutomaticMutationRetryReservations {
  private var ownerCountsByMutationID: [String: Int] = [:]

  func reserve(_ mutationID: String) {
    ownerCountsByMutationID[mutationID, default: 0] += 1
  }

  func release(_ mutationID: String) {
    guard let ownerCount = ownerCountsByMutationID[mutationID] else { return }
    if ownerCount == 1 {
      ownerCountsByMutationID[mutationID] = nil
    } else {
      ownerCountsByMutationID[mutationID] = ownerCount - 1
    }
  }

  func contains(_ mutationID: String) -> Bool {
    ownerCountsByMutationID[mutationID] != nil
  }

  func snapshot() -> Set<String> {
    Set(ownerCountsByMutationID.keys)
  }
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
  private let storageTransport: InstantStorageTransportClient?
  private let streamFileTransport: InstantStreamFileTransportClient
  private let streamChunksObservers =
    InstantSnapshotObservers<InstantStreamChunksObservationKey, [InstantStreamChunk]>()
  private let streamContentObservers = InstantStreamContentObservers()
  private let sharesObservers =
    InstantSnapshotObservers<InstantSharesObservationKey, [InstantShareSnapshot]>()
  private let operationGate = AsyncSerialGate(label: "operation")
  private let authPromotionGate = AsyncSerialGate(label: "auth-promotion")
  private let connectionGate = AsyncSerialGate(label: "connection")
  private let mutationFlushGate = AsyncSerialGate(label: "mutation-flush")
  private let queryCachePruningCadence = InstantQueryCachePruningCadence()
  private let liveQueryResultPruningCadence = InstantQueryCachePruningCadence()
  private let liveSession = InstantRuntimeLiveSession()
  private let liveQueryResultState = InstantLiveQueryResultState()
  private let liveQueryAcknowledgements = InstantLiveQueryAcknowledgementState()
  private let liveRoomPresenceState = InstantRuntimeLiveRoomPresenceState()
  private let activeRoomPresenceState = InstantRuntimeActiveRoomPresenceState()
  private let reconnectController = InstantRuntimeReconnectController()
  private let automaticMutationRetryReservations = InstantAutomaticMutationRetryReservations()

  private init(
    configuration: InstantRuntimeConfiguration,
    store: InstantStore,
    outbox: InstantOutbox,
    persistence: SQLitePersistenceStore,
    storageTransport: InstantStorageTransportClient?,
    streamFileTransport: InstantStreamFileTransportClient
  ) {
    self.configuration = configuration
    self.store = store
    self.outbox = outbox
    self.persistence = persistence
    self.storageTransport = storageTransport
    self.streamFileTransport = streamFileTransport
  }

  public static func bootstrap(configuration: InstantRuntimeConfiguration) async throws -> Self {
    try await bootstrap(
      configuration: configuration,
      storageTransport: nil,
      streamFileTransport: .live
    )
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration,
    storageTransport: InstantStorageTransportClient?
  ) async throws -> Self {
    try await bootstrap(
      configuration: configuration,
      storageTransport: storageTransport,
      streamFileTransport: .live
    )
  }

  public static func bootstrap(
    configuration: InstantRuntimeConfiguration,
    storageTransport: InstantStorageTransportClient?,
    streamFileTransport: InstantStreamFileTransportClient
  ) async throws -> Self {
    let startupTrace = configuration.startupTrace
    let runtimeStopwatch = startupTrace.started(
      "runtime.bootstrap",
      metadata: [
        "appID": configuration.appID,
        "attributeCount": String(configuration.initialAttributes.count),
        "hasLiveTransport": String(configuration.liveTransport != nil),
      ]
    )
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "runtime",
      event: "runtime.bootstrap-started",
      message: "Bootstrapping the Instant runtime.",
      metadata: [
        "appID": configuration.appID,
        "persistencePath": configuration.persistenceURL.path,
        "attributeCount": String(configuration.initialAttributes.count),
        "hasLiveTransport": String(configuration.liveTransport != nil),
        "autoConnect": String(configuration.autoConnectLiveTransport),
        "hasStorageTransport": String(storageTransport != nil),
      ]
    )
    do {
      let validationStopwatch = startupTrace.stopwatch()
      try validateEndpoints(configuration)
      try validateInitialAttributes(configuration.initialAttributes)
      startupTrace.completed("runtime.validation", since: validationStopwatch)

      let persistence = try SQLitePersistenceStore(
        fileURL: configuration.persistenceURL,
        startupTrace: startupTrace
      )
      configuration.actorHopRecorder?.record(.persistence)
      let bootstrapPruningResult = try await persistence.bootstrap(
        queryCachePruningPolicy: configuration.queryCachePruningPolicy,
        now: configuration.now()
      )
      if let bootstrapPruningResult,
        !bootstrapPruningResult.removedCacheKeys.isEmpty
      {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-cache.pruned-at-bootstrap",
          message: "Pruned unloaded persisted query results during runtime bootstrap.",
          metadata: [
            "remainingCount": String(bootstrapPruningResult.remainingEntryCount),
            "removedCount": String(bootstrapPruningResult.removedCacheKeys.count),
          ]
        )
      }
      configuration.actorHopRecorder?.record(.persistence)
      var state = try await persistence.loadState()
      let storeMaterializationStopwatch = startupTrace.stopwatch()
      let store = InstantStore(snapshot: state.snapshot.store)
      let outbox = InstantOutbox(mutations: state.snapshot.outbox)
      startupTrace.completed(
        "runtime.store-materialization",
        since: storeMaterializationStopwatch,
        metadata: [
          "attributeCount": String(state.snapshot.store.attributes.count),
          "tripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
        ]
      )

      let attributeMergeStopwatch = startupTrace.stopwatch()
      var didChangeAttributes = false
      if !configuration.initialAttributes.isEmpty {
        var didBootstrapAttributes = false
        for attempt in 1...5 {
          configuration.actorHopRecorder?.record(.store)
          let storeMergeStopwatch = startupTrace.stopwatch()
          let storeSnapshot = await store.mergeAttributesIfChanged(configuration.initialAttributes)
          startupTrace.completed(
            "runtime.attribute-store-merge",
            since: storeMergeStopwatch,
            metadata: [
              "attempt": String(attempt),
              "changed": String(storeSnapshot != nil),
            ]
          )
          guard let storeSnapshot else {
            didBootstrapAttributes = true
            break
          }
          configuration.actorHopRecorder?.record(.persistence)
          let didSave = try await persistence.saveStoreSnapshot(
            storeSnapshot,
            replacing: state.snapshot.store,
            expectedStoreRevision: state.storeRevision,
            expectedOutboxRevision: state.outboxRevision
          )
          if didSave {
            didChangeAttributes = true
            state = InstantPersistenceState(
              snapshot: InstantPersistenceSnapshot(
                store: storeSnapshot,
                outbox: state.snapshot.outbox
              ),
              storeRevision: state.storeRevision + 1,
              outboxRevision: state.outboxRevision
            )
            didBootstrapAttributes = true
            break
          }
          configuration.actorHopRecorder?.record(.persistence)
          state = try await persistence.loadState()
          configuration.actorHopRecorder?.record(.store)
          await store.replaceSnapshot(state.snapshot.store)
          configuration.actorHopRecorder?.record(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
        }
        guard didBootstrapAttributes else {
          throw InstantError(
            code: .persistenceFailed,
            operation: "bootstrap attributes",
            message: "The local Instant cache changed repeatedly while bootstrapping schema attributes.",
            recovery: "Retry launch after other writers finish updating the shared cache."
          )
        }
      } else {
        startupTrace.completed(
          "runtime.attribute-store-merge",
          durationMilliseconds: 0,
          metadata: ["skipped": "true"]
        )
      }
      startupTrace.completed(
        "runtime.attribute-merge",
        since: attributeMergeStopwatch,
        metadata: [
          "changed": String(didChangeAttributes),
          "requestedAttributeCount": String(configuration.initialAttributes.count),
          "storedAttributeCount": String(state.snapshot.store.attributes.count),
        ]
      )

      let runtime = Self(
        configuration: configuration,
        store: store,
        outbox: outbox,
        persistence: persistence,
        storageTransport: storageTransport,
        streamFileTransport: streamFileTransport
      )

      do {
        configuration.actorHopRecorder?.record(.persistence)
        let pruning = try await persistence.pruneLiveQueryResults(
          policy: configuration.liveQueryResultPruningPolicy,
          now: configuration.now()
        )
        if !pruning.result.removedQueryKeys.isEmpty {
          state = pruning.state
          configuration.actorHopRecorder?.record(.store)
          await store.replaceSnapshot(state.snapshot.store)
          configuration.actorHopRecorder?.record(.outbox)
          await outbox.replace(with: state.snapshot.outbox)
          InstantDiagnostics.shared.record(
            .debug,
            subsystem: "instant-swift-data-core",
            category: "query",
            event: "live-query-results.pruned-at-bootstrap",
            message: "Pruned unloaded persisted live query results during runtime bootstrap.",
            metadata: [
              "remainingCount": String(pruning.result.remainingEntryCount),
              "remainingTripleCount": String(pruning.result.remainingTripleCount),
              "removedCount": String(pruning.result.removedQueryKeys.count),
              "removedOrphanedTripleCount": String(
                pruning.result.removedOrphanedTripleCount
              ),
            ]
          )
        }
      } catch {
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "live-query-results.bootstrap-prune-failed",
          message: "Could not prune persisted live query results during runtime bootstrap."
        )
      }

      Task(priority: .utility) {
        await runtime.syncUserCookieOnStartup()
      }
      runtime.startAutomaticLiveConnectionIfNeeded()
      startupTrace.completed(
        "runtime.services-scheduled",
        durationMilliseconds: 0,
        metadata: [
          "autoConnect": String(configuration.autoConnectLiveTransport),
          "cookieSyncScheduled": "true",
        ]
      )
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "runtime",
        event: "runtime.bootstrap-completed",
        message: "Instant runtime bootstrap completed.",
        metadata: [
          "appID": configuration.appID,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
          "storedAttributeCount": String(state.snapshot.store.attributes.count),
          "storedTripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
        ]
      )
      startupTrace.completed(
        "runtime.bootstrap",
        since: runtimeStopwatch,
        metadata: [
          "storedAttributeCount": String(state.snapshot.store.attributes.count),
          "storedTripleCount": String(state.snapshot.store.triples.count),
          "outboxCount": String(state.snapshot.outbox.count),
        ]
      )
      return runtime
    } catch {
      startupTrace.failed("runtime.bootstrap", error: error, since: runtimeStopwatch)
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "runtime",
        event: "runtime.bootstrap-failed",
        message: "Instant runtime bootstrap failed.",
        metadata: [
          "appID": configuration.appID,
          "persistencePath": configuration.persistenceURL.path,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      throw error
    }
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
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "mutation",
      event: "transaction.started",
      message: "Started an Instant transaction.",
      metadata: [
        "appID": configuration.appID,
        "operationCount": String(transaction.operations.count),
        "source": source,
      ],
      correlationID: transaction.id
    )
    var enteredOperationGate = false
    do {
      // A cancelled caller must not keep a queue slot and then run the write
      // anyway. Cancellation is honored only before acquisition, so a
      // transaction that has already started still commits atomically.
      try await enterOperationGateUnlessCancelled()
      enteredOperationGate = true
      let result = try await performTransact(transaction, createdAt: createdAt, source: source)
      await leaveOperationGate()
      enteredOperationGate = false
      if await liveSession.isOpen {
        await sendOutstandingMutationsToLiveSession()
      } else {
        startLiveMutationDeliveryIfNeeded()
      }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.optimistic-commit",
        message: "Transaction committed to the local cache and entered sync processing.",
        metadata: [
          "appID": configuration.appID,
          "changedEntityCount": String(result.changedEntityIDs.count),
          "emissionCount": String(result.emissions.count),
          "tripleCount": String(result.tripleCount),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: transaction.id
      )
      return result
    } catch {
      if enteredOperationGate {
        await leaveOperationGate()
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.failed",
        message: "Instant transaction failed.",
        metadata: [
          "appID": configuration.appID,
          "operationCount": String(transaction.operations.count),
          "source": source,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: transaction.id
      )
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
      let loadedState = try await persistence.loadStateWithSource()
      let state = loadedState.state
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
      var pendingMutation: PendingMutation
      if var existingDraft = mutation {
        if createdAt == nil {
          existingDraft.createdAt = Self.monotonicOutboxTimestamp(
            existingDraft.createdAt,
            after: state.snapshot.outbox
          )
          mutation = existingDraft
        }
        pendingMutation = existingDraft
      } else {
        let newMutation = PendingMutation(
          id: transaction.id,
          createdAt: createdAt
            ?? Self.monotonicOutboxTimestamp(
              configuration.now(),
              after: state.snapshot.outbox
            ),
          transaction: transaction
        )
        mutation = newMutation
        pendingMutation = newMutation
      }
      recordActorHop(.store)
      let prepared: PreparedStoreMutation
      if loadedState.source == .memory {
        prepared = try await store.prepareCurrent(transaction)
      } else {
        prepared = try await store.prepare(transaction, applyingTo: state.snapshot.store)
      }
      pendingMutation.rollbackTransaction = Self.rollbackTransaction(
        mutationID: pendingMutation.id,
        prepared: prepared
      )
      mutation = pendingMutation
      let outboxSnapshot = (state.snapshot.outbox + [pendingMutation])
        .sorted(by: PendingMutation.creationOrder)
      recordActorHop(.persistence)
      let didSave = try await persistence.saveLocalMutation(
        changedEntityTriples: prepared.changedEntityTriples,
        outbox: outboxSnapshot,
        pendingMutation: pendingMutation,
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

  private static func monotonicOutboxTimestamp(
    _ requested: InstantTimestamp,
    after mutations: [PendingMutation]
  ) -> InstantTimestamp {
    guard
      let latest = mutations.map(\.createdAt).max(),
      requested <= latest,
      latest.milliseconds < Int64.max
    else { return requested }
    return InstantTimestamp(milliseconds: latest.milliseconds + 1)
  }

  /// Upstream Instant keeps server query stores separate and reapplies pending mutations as an
  /// optimistic overlay (`Reactor.dataForQuery` / `_applyOptimisticUpdates`). Swift persists one
  /// materialized store, so it records the exact inverse of this optimistic layer instead.
  static func rollbackTransaction(
    mutationID: String,
    prepared: PreparedStoreMutation
  ) -> InstantStoreTransaction? {
    let changedEntityTriples = prepared.changedEntityTriples
    var operations: [InstantTripleOperation] = []
    for entityID in prepared.result.changedEntityIDs.sorted() {
      let before = prepared.previousChangedEntityTriples[entityID, default: []]
      let after = changedEntityTriples[entityID, default: []]
      let beforeSet = Set(before)
      let afterSet = Set(after)
      operations.append(
        contentsOf:
          after
          .filter { !beforeSet.contains($0) }
          .map(InstantTripleOperation.retract)
      )
      operations.append(
        contentsOf:
          before
          .filter { !afterSet.contains($0) }
          .map(InstantTripleOperation.insert)
      )
    }
    guard !operations.isEmpty else { return nil }
    return InstantStoreTransaction(
      id: "rollback-\(mutationID)",
      operations: operations
    )
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
    mergingAttributes attributesToMerge: [InstantAttribute] = [],
    liveQueryResultReplacements: [InstantLiveQueryResultReplacement] = []
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

    var baseTransaction = transaction
    baseTransaction.id = transactionID.isEmpty ? processedTransactionID : transactionID
    let metadataUpdatedAt = receivedAt ?? configuration.now()
    let confirmingMutationID = confirmingMutationID?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    let persistedLiveQueryResults = liveQueryResultReplacements.map {
      InstantPersistedLiveQueryResult(
        replacement: $0,
        updatedAt: metadataUpdatedAt
      )
    }

    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      // Legacy pre-overlay rows (1.1.x / early 1.2) can sit in the outbox as
      // `failed` with neither optimisticOverlayState nor rollbackTransaction.
      // Refusing *retry/discard* without guessing their local effect is correct
      // (#134). Refusing every *server apply* is not: live add-query-ok and
      // refresh-ok go through this path, and one poison row then kills the
      // receive loop forever (recipes-v3 `773e50f4-…`, Scribe indefinite
      // loading). Failed rows already skip optimistic protection and rebase;
      // isolate them and keep applying server truth. Still fail closed for
      // non-failed unknown rows (pending / unproven) whose overlay may still
      // be live in the cache.
      let isolatedFailedUnknownIDs = state.snapshot.outbox.compactMap { mutation -> String? in
        guard mutation.status == .failed,
          mutation.optimisticOverlayState == nil,
          mutation.rollbackTransaction == nil
        else { return nil }
        return mutation.id
      }
      if !isolatedFailedUnknownIDs.isEmpty {
        InstantDiagnostics.shared.record(
          .error,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.legacy-unknown-isolated",
          message:
            "Isolated failed mutation(s) that predate durable optimistic-overlay metadata; server apply continues.",
          metadata: [
            "mutationCount": String(isolatedFailedUnknownIDs.count),
            "mutationIDs": isolatedFailedUnknownIDs.joined(separator: ","),
            "operation": "apply server transaction",
          ]
        )
      }
      if let unknownMutation = state.snapshot.outbox.first(where: {
        $0.status != .failed
          && ($0.status != .confirmed || !$0.provesServerAcceptance)
          && $0.optimisticOverlayState == nil
          && $0.rollbackTransaction == nil
      }) {
        let error = unknownOptimisticOverlayState(
          id: unknownMutation.id,
          operation: "apply server transaction"
        )
        reportIssue("\(error)")
        throw error
      }
      var transaction = baseTransaction
      if !liveQueryResultReplacements.isEmpty {
        recordActorHop(.persistence)
        let retractions = try await persistence.liveQueryReplacementRetractions(
          for: liveQueryResultReplacements
        )
        // Empty/narrow server results must not retract triples still owned by a
        // pending optimistic mutation. Upstream keeps a separate server store and
        // reapplies the overlay; Swift materializes one store, so without this
        // guard a blank live refresh can wipe local transcriptions while the
        // outbox still believes they are durable (Scribe blank-detail 2026-08-04).
        let protectedEntityIDs = Self.pendingOptimisticEntityIDs(
          in: state.snapshot.outbox
        )
        let protectedRetractions = retractions.filter { operation in
          guard case let .retract(triple) = operation else { return true }
          return !protectedEntityIDs.contains(triple.entityID)
        }
        transaction.operations.insert(contentsOf: protectedRetractions, at: 0)
      }
      let prunedOutbox = InstantOutbox.pruningConfirmed(
        through: processedTransactionID,
        in: state.snapshot.outbox
      )
      let confirmation = confirmingMutationID.flatMap {
        InstantOutbox.confirming(id: $0, in: prunedOutbox)
      }
      let outboxSnapshot = confirmation?.mutations ?? prunedOutbox
      let outboxChanged = outboxSnapshot != state.snapshot.outbox
      var storeSnapshot = state.snapshot.store
      let mergedAttributeCount = mergeLiveRefreshAttributes(
        attributesToMerge,
        into: &storeSnapshot
      )
      let storeAttributesChanged = mergedAttributeCount > 0
      if transaction.operations.isEmpty {
        recordActorHop(.persistence)
        let didSave =
          if !persistedLiveQueryResults.isEmpty {
            try await persistence.saveLiveRefresh(
              InstantPersistenceSnapshot(store: storeSnapshot, outbox: outboxSnapshot),
              queryResults: persistedLiveQueryResults,
              storeChanged: storeAttributesChanged,
              outboxChanged: outboxChanged,
              metadataKey: processedTransactionIDMetadataKey,
              metadataValue: processedTransactionID,
              metadataUpdatedAt: metadataUpdatedAt,
              expectedStoreRevision: state.storeRevision,
              expectedOutboxRevision: state.outboxRevision
            )
          } else if storeAttributesChanged, outboxChanged {
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
          await store.installLiveQueryPageInfo(
            liveQueryResultReplacements,
            publishing: true
          )
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
            transaction: transaction,
            application: application,
            confirmedMutation: confirmation?.mutation,
            mergedAttributeCount: mergedAttributeCount
          )
        }
        continue
      }

      // Upstream keeps the authoritative query store separate from optimistic mutations, then
      // reapplies every still-pending mutation after a server refresh. Swift persists one
      // materialized store, so first remove the durable optimistic layers in reverse order.
      // This makes the new rollback image reflect the latest server value instead of the value
      // that happened to exist when the local mutation was originally created.
      recordActorHop(.store)
      storeSnapshot = try await removingLocalMutationOverlays(
        state.snapshot.outbox,
        from: storeSnapshot
      )
      let preparedServer = try await store.prepare(transaction, applyingTo: storeSnapshot)
      let rebase = try await rebaseLocalMutations(
        outboxSnapshot,
        over: preparedServer,
        authoritativeOperations: transaction.operations
      )
      let prepared = rebase.prepared
      let rebasedOutboxSnapshot = rebase.mutations
      let rebasedOutboxChanged = rebasedOutboxSnapshot != state.snapshot.outbox
      recordActorHop(.persistence)
      let didSave =
        if !persistedLiveQueryResults.isEmpty {
          try await persistence.saveLiveRefresh(
            InstantPersistenceSnapshot(store: prepared.snapshot, outbox: rebasedOutboxSnapshot),
            queryResults: persistedLiveQueryResults,
            storeChanged: true,
            outboxChanged: rebasedOutboxChanged,
            metadataKey: processedTransactionIDMetadataKey,
            metadataValue: processedTransactionID,
            metadataUpdatedAt: metadataUpdatedAt,
            expectedStoreRevision: state.storeRevision,
            expectedOutboxRevision: state.outboxRevision
          )
        } else if rebasedOutboxChanged {
          try await persistence.saveSnapshot(
            InstantPersistenceSnapshot(store: prepared.snapshot, outbox: rebasedOutboxSnapshot),
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
        await store.installLiveQueryPageInfo(
          liveQueryResultReplacements,
          publishing: false
        )
        let committed = await store.commitAndPublish(prepared)
        recordActorHop(.outbox)
        await outbox.replace(with: rebasedOutboxSnapshot)
        _ = try? await publishConnectionStatusWithGateHeld()
        let application = committed.result.serverApplicationResult(
          processedTransactionID: processedTransactionID,
          pendingMutations: rebasedOutboxSnapshot
        )
        if let mutation = confirmation?.mutation {
          await publishMutationLifecycle(mutation)
        }
        return InstantAppliedServerTransaction(
          transaction: transaction,
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
        mergingAttributes: translated.attributesToMerge,
        liveQueryResultReplacements: translated.queryResultReplacements
      )
      await liveQueryResultState.record(translated.queryResultReplacements)
      if !translated.queryResultReplacements.isEmpty,
        liveQueryResultPruningCadence.shouldPrune(
          afterSuccessfulWriteWithInterval: configuration.liveQueryResultPruningWriteInterval
        )
      {
        do {
          _ = try await performPruneLiveQueryResults(
            policy: configuration.liveQueryResultPruningPolicy,
            now: configuration.now()
          )
        } catch {
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "instant-swift-data-core",
            category: "query",
            event: "live-query-results.prune-failed",
            message: "Could not prune unloaded persisted live query results."
          )
        }
      }

      await leaveOperationGate()
      return InstantLiveRefreshApplicationResult(
        transaction: applied.transaction,
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
      InstantDiagnostics.shared.record(
        result.mutation == nil ? .debug : .notice,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: result.mutation == nil
          ? "transaction.confirmation-not-found"
          : "transaction.local-confirmed",
        message: result.mutation == nil
          ? "A caller's local confirmation did not match an outbox mutation."
          : "A caller locally confirmed an outbox mutation without server-acceptance proof.",
        metadata: ["pendingMutationCount": String(result.pendingMutationCount)],
        correlationID: id
      )
      return result.mutation
    } catch {
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.confirmation-failed",
        message: "Failed to apply a local outbox confirmation.",
        correlationID: id
      )
      throw error
    }
  }

  private func acceptMutationIfPresent(
    id: String,
    serverTransactionID: String
  ) async throws -> PendingMutation? {
    await enterOperationGate()
    do {
      let result = try await performAcceptMutationIfPresent(
        id: id,
        serverTransactionID: serverTransactionID
      )
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        result.mutation == nil ? .debug : .notice,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: result.mutation == nil
          ? "transaction.acceptance-not-found"
          : "transaction.server-accepted",
        message: result.mutation == nil
          ? "Server acceptance did not match a local outbox mutation."
          : "Instant accepted an outbox mutation and retained its optimistic overlay until the server watermark catches up.",
        metadata: [
          "pendingMutationCount": String(result.pendingMutationCount),
          "serverTransactionID": serverTransactionID,
        ],
        correlationID: id
      )
      return result.mutation
    } catch {
      await leaveOperationGate()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "mutation",
        event: "transaction.acceptance-failed",
        message: "Failed to retain an accepted Instant mutation until its server watermark.",
        correlationID: id
      )
      throw error
    }
  }

  private func performAcceptMutationIfPresent(
    id: String,
    serverTransactionID: String
  ) async throws -> (mutation: PendingMutation?, pendingMutationCount: Int) {
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      guard
        let update = InstantOutbox.accepting(
          id: id,
          serverTransactionID: serverTransactionID,
          in: state.snapshot.outbox
        )
      else {
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

  private func removingLocalMutationOverlays(
    _ mutations: [PendingMutation],
    from snapshot: InstantStoreSnapshot
  ) async throws -> InstantStoreSnapshot {
    var base = snapshot
    for mutation in mutations.sorted(by: PendingMutation.creationOrder).reversed() {
      guard mutation.optimisticOverlayState != .removed else { continue }
      guard let rollbackTransaction = mutation.rollbackTransaction else { continue }
      base = try await store.prepare(rollbackTransaction, applyingTo: base).snapshot
    }
    return base
  }

  /// Entity IDs still covered by a non-failed optimistic mutation that has not
  /// been explicitly removed. Live-query replacement retractions must not erase
  /// these while delivery is still pending.
  private static func pendingOptimisticEntityIDs(
    in mutations: [PendingMutation]
  ) -> Set<String> {
    var entityIDs: Set<String> = []
    for mutation in mutations {
      guard mutation.status != .failed else { continue }
      guard mutation.optimisticOverlayState != .removed else { continue }
      for operation in mutation.transaction.operations {
        switch operation {
        case let .requireEntityMissing(entityID, _),
          let .requireEntityExists(entityID, _),
          let .deleteEntity(entityID),
          let .deleteEntityInNamespace(entityID, _),
          let .ruleParams(entityID, _, _),
          let .requireTripleExists(entityID, _, _):
          entityIDs.insert(entityID)
        case let .merge(triple), let .insert(triple), let .retract(triple):
          entityIDs.insert(triple.entityID)
          if case let .ref(targetEntityID) = triple.value {
            entityIDs.insert(targetEntityID)
          }
        case .requireEntityMissingByLookup,
          .requireEntityExistsByLookup,
          .mergeByLookup,
          .insertByLookup,
          .retractByLookup,
          .deleteEntityByLookup,
          .ruleParamsByLookup:
          // Lookup-targeted writes cannot identify a concrete entity without
          // applying the lookup; skip broad protection here (rebase still runs).
          break
        }
      }
    }
    return entityIDs
  }

  private func rebaseLocalMutations(
    _ mutations: [PendingMutation],
    over preparedServer: PreparedStoreMutation,
    authoritativeOperations: [InstantTripleOperation]
  ) async throws -> (prepared: PreparedStoreMutation, mutations: [PendingMutation]) {
    var preparedRebase = preparedServer
    let authoritativeCoverage = InstantAuthoritativeWriteCoverage(
      operations: authoritativeOperations,
      attributes: preparedServer.attributes,
      previousChangedEntityTriples: preparedServer.previousChangedEntityTriples,
      changedEntityTriples: preparedServer.changedEntityTriples
    )
    let reconciledServerTransportIDs = Set(
      mutations.compactMap { mutation in
        mutation.status == .confirmed
          && mutation.confirmationSource == .serverTransport
          && mutation.serverTransactionID == nil
          && authoritativeCoverage.covers(mutation.transaction.operations)
          ? mutation.id
          : nil
      }
    )
    var rebasedMutationsByID = Dictionary(
      uniqueKeysWithValues: mutations.map { ($0.id, $0) }
    )
    // A server refresh removes failed optimistic layers instead of replaying them. Clear their
    // inverse at the same atomic persistence boundary so a later explicit discard cannot apply an
    // obsolete before-image over newer server data (or resurrect an entity the server deleted).
    for mutation in mutations
    where mutation.status == .failed
      && (mutation.optimisticOverlayState != nil || mutation.rollbackTransaction != nil)
    {
      rebasedMutationsByID[mutation.id]?.rollbackTransaction = nil
      rebasedMutationsByID[mutation.id]?.optimisticOverlayState = .removed
    }
    for mutation in mutations.sorted(by: PendingMutation.creationOrder)
    where mutation.status != .failed
      && !reconciledServerTransportIDs.contains(mutation.id) {
      let newestServerTimestamp =
        preparedRebase.indexes.newestTransactionTimeMilliseconds ?? 0
      let optimisticTimestamp = InstantTimestamp(
        milliseconds: newestServerTimestamp == Int64.max
          ? newestServerTimestamp
          : newestServerTimestamp + 1
      )
      let operations = mutation.transaction.operations
        .filter(\.isRebasedLocalWrite)
        .map { $0.rebased(at: optimisticTimestamp) }
      rebasedMutationsByID[mutation.id]?.rollbackTransaction = nil
      rebasedMutationsByID[mutation.id]?.optimisticOverlayState = .applied
      guard !operations.isEmpty else { continue }
      preparedRebase = try await store.prepare(
        InstantStoreTransaction(id: mutation.transaction.id, operations: operations),
        applyingTo: preparedRebase
      )
      rebasedMutationsByID[mutation.id]?.rollbackTransaction = Self.rollbackTransaction(
        mutationID: mutation.id,
        prepared: preparedRebase
      )
    }
    var result = preparedServer.result
    result.tripleCount = preparedRebase.indexes.tripleCount
    return (
      prepared: PreparedStoreMutation(
        result: result,
        sequence: preparedServer.sequence,
        attributes: preparedRebase.attributes,
        indexes: preparedRebase.indexes
      ),
      mutations: mutations.compactMap { mutation in
        guard !reconciledServerTransportIDs.contains(mutation.id) else { return nil }
        return rebasedMutationsByID[mutation.id] ?? mutation
      }
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

  /// The attributes this device holds durably, as opposed to the ones a live session happens to
  /// be holding in memory.
  package func persistedStoreAttributes() async throws -> [InstantAttribute] {
    await enterOperationGate()
    do {
      recordActorHop(.persistence)
      let attributes = try await persistence.loadState().snapshot.store.attributes
      await leaveOperationGate()
      return attributes
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  /// Writes the server's attribute set into the local cache.
  ///
  /// Instant models attributes as data: a device can only materialize namespaces it holds
  /// attributes for, and query observation refuses to subscribe to a namespace it cannot
  /// validate. A device that keeps the server's attribute set in memory only therefore goes
  /// permanently blind to every namespace added to the schema after its last sync — it never
  /// subscribes, so it never receives the payload that would have taught it the namespace.
  ///
  /// Upstream applies the set on every `init-ok`
  /// (`upstream/instant/client/packages/core/src/Reactor.js` line 640, `this._setAttrs(msg.attrs)`).
  /// Upstream replaces its whole in-memory attr store there and keeps locally minted attributes
  /// separately in `optimisticAttrs()`; this client persists a single attribute set, so it
  /// merges instead — a namespace/name pair the device already holds keeps its local attribute
  /// id, because local triples and pending mutations reference that id.
  ///
  /// The caller must already hold the operation gate.
  @discardableResult
  private func applyServerAttributesWithGateHeld(
    _ serverAttributes: [InstantLiveJSONValue]
  ) async throws -> Int {
    guard !serverAttributes.isEmpty else { return 0 }
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      let attributesToMerge = try InstantLiveRefreshTranslator.attributesToMerge(
        serverAttributes: serverAttributes,
        existingAttributes: state.snapshot.store.attributes
      )
      guard !attributesToMerge.isEmpty else { return 0 }
      var storeSnapshot = state.snapshot.store
      let mergedCount = mergeLiveRefreshAttributes(attributesToMerge, into: &storeSnapshot)
      guard mergedCount > 0 else { return 0 }
      recordActorHop(.persistence)
      let didSave = try await persistence.saveStoreSnapshot(
        storeSnapshot,
        replacing: state.snapshot.store,
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision
      )
      if didSave {
        // Merge into the live store rather than replacing its snapshot: the persisted triples
        // are the ones this loop read, and the in-memory store may already carry newer
        // optimistic ones.
        recordActorHop(.store)
        _ = await store.mergeAttributesIfChanged(attributesToMerge)
        InstantDiagnostics.shared.record(
          .notice,
          subsystem: "instant-swift-data-core",
          category: "connection",
          event: "connection.server-attributes-applied",
          message: "Stored attributes the server sent for namespaces this device did not have.",
          metadata: [
            "appID": configuration.appID,
            "mergedAttributeCount": String(mergedCount),
            "serverAttributeCount": String(serverAttributes.count),
            "namespaces": Set(attributesToMerge.map(\.namespace)).sorted()
              .joined(separator: ","),
          ]
        )
        return mergedCount
      }
      recordActorHop(.persistence)
      let reloaded = try await persistence.loadState()
      recordActorHop(.store)
      await store.replaceSnapshot(reloaded.snapshot.store)
      recordActorHop(.outbox)
      await outbox.replace(with: reloaded.snapshot.outbox)
    }
    throw InstantError(
      code: .persistenceFailed,
      operation: "apply server attributes",
      message: "The local Instant cache changed repeatedly while storing the server's attributes.",
      recovery: "Retry the connection after other writers finish updating the shared cache."
    )
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
    await observe(
      plan,
      remotePageInfo: remotePageInfo,
      connectsToLiveTransport: true
    )
  }

  package func observeLocally(
    _ plan: InstantQueryPlan
  ) async -> AsyncStream<InstantQueryEmission> {
    await observe(
      plan,
      remotePageInfo: nil,
      connectsToLiveTransport: false
    )
  }

  private func observe(
    _ plan: InstantQueryPlan,
    remotePageInfo: InstantQueryRemotePageInfo?,
    connectsToLiveTransport: Bool
  ) async -> AsyncStream<InstantQueryEmission> {
    let startupStopwatch = configuration.startupTrace.started(
      "query.observe",
      metadata: ["namespace": plan.namespace]
    )
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "query",
      event: "query-observation.started",
      message: "Started observing an Instant query.",
      metadata: [
        "appID": configuration.appID,
        "namespace": plan.namespace,
        "transport": connectsToLiveTransport && configuration.liveTransport != nil
          ? "websocket" : "local-cache",
      ],
      correlationID: plan.id
    )
    // Bootstrap hydrates the in-memory store once. Query declarations must not reread the whole
    // SQLite file or wait for connection/authentication work; subsequent local and remote
    // mutations update this actor-isolated store directly.
    recordActorHop(.store)
    let schemaSnapshotStopwatch = configuration.startupTrace.stopwatch()
    let attributes = await store.attributeSnapshot()
    configuration.startupTrace.completed(
      "query.schema-snapshot",
      since: schemaSnapshotStopwatch,
      metadata: ["namespace": plan.namespace]
    )
    if let issue = TripleIndexes.validate(
      plan,
      attributes: AttributeStore(attributes: attributes)
    ) {
      InstantDiagnostics.shared.record(
        .warning,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-observation.validation-failed",
        message: "Query observation failed schema validation and will emit no values.",
        metadata: ["namespace": plan.namespace],
        correlationID: plan.id
      )
      // A stream that stays empty forever reads exactly like a namespace with no rows, which is
      // how a device kept serving stale data for weeks without anyone noticing. Say it out loud.
      reportIssue(
        """
        Instant will emit nothing for the '\(plan.namespace)' query '\(plan.id)'.

        \(issue.message)

        \(issue.recovery)
        """
      )
      return Self.emptyObservation(plan)
    }
    let usesLiveTransport = connectsToLiveTransport && configuration.liveTransport != nil
    let liveRegistration: (query: InstantLiveJSONValue, key: String)?
    if usesLiveTransport {
      do {
        let query = try InstantLiveQueryEncoder.encode(plan)
        liveRegistration = (
          query: query,
          key: try InstantLiveQueryEncoder.registrationKey(for: query)
        )
      } catch {
        liveRegistration = nil
        await recordConnectionError(error)
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.encoding-failed",
          message: "Could not encode a live query observation.",
          metadata: ["namespace": plan.namespace],
          correlationID: plan.id
        )
      }
    } else {
      liveRegistration = nil
    }

    if liveRegistration != nil {
      await enterOperationGate()
    }
    recordActorHop(.store)
    let localRegistrationStopwatch = configuration.startupTrace.stopwatch()
    let stream = await store.observe(plan, remotePageInfo: remotePageInfo)
    configuration.startupTrace.completed(
      "query.local-registration",
      since: localRegistrationStopwatch,
      metadata: ["namespace": plan.namespace]
    )
    configuration.startupTrace.completed(
      "query.local-observer",
      since: startupStopwatch,
      metadata: ["namespace": plan.namespace]
    )
    guard let liveRegistration else {
      if !usesLiveTransport {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.local-registered",
          message: "Registered a local-cache query observation.",
          metadata: ["namespace": plan.namespace],
          correlationID: plan.id
        )
      }
      return stream
    }
    let query = liveRegistration.query
    let registrationKey = liveRegistration.key

    do {
      try await liveSession.registerQuery(
        query,
        key: registrationKey,
        clientEventID: configuration.makeID()
      )
      await leaveOperationGate()
      let isLiveSessionOpen = await liveSession.isOpen
      configuration.startupTrace.milestone(
        "query.live-registration",
        metadata: [
          "namespace": plan.namespace,
          "state": isLiveSessionOpen ? "registered" : "pending",
        ]
      )
      InstantDiagnostics.shared.record(
        isLiveSessionOpen ? .notice : .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: isLiveSessionOpen
          ? "query-observation.live-registered"
          : "query-observation.live-pending",
        message: isLiveSessionOpen
          ? "Registered a live Instant query observation."
          : "The live query will register automatically when the WebSocket session opens.",
        metadata: [
          "namespace": plan.namespace,
          "registrationKey": registrationKey,
          "autoConnect": String(configuration.autoConnectLiveTransport),
          "liveSessionOpen": String(isLiveSessionOpen),
        ],
        correlationID: plan.id
      )
    } catch {
      await leaveOperationGate()
      await recordConnectionError(error)
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-observation.registration-failed",
        message: "Could not register a live Instant query observation.",
        metadata: ["namespace": plan.namespace],
        correlationID: plan.id
      )
    }
    return Self.liveObservation(stream) { [weak self] in
      guard let self else { return }
      do {
        let didUnload = try await self.liveSession.unregisterQuery(
          key: registrationKey,
          clientEventID: self.configuration.makeID()
        )
        if didUnload {
          await self.liveQueryResultState.unload(key: registrationKey)
        }
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.live-unregistered",
          message: "Unregistered a live Instant query observation.",
          metadata: ["registrationKey": registrationKey],
          correlationID: plan.id
        )
      } catch {
        await self.liveQueryResultState.unload(key: registrationKey)
        await self.recordConnectionError(error)
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query-observation.unregister-failed",
          message: "Could not unregister a live Instant query observation.",
          correlationID: plan.id
        )
      }
    }
  }

  func observeLiveInfiniteQueryChunk(
    _ plan: InstantQueryPlan
  ) async -> AsyncStream<InstantQueryEmission> {
    guard configuration.liveTransport != nil else {
      return await store.observe(plan)
    }

    let query: InstantLiveJSONValue
    let registrationKey: String
    do {
      query = try InstantLiveQueryEncoder.encode(plan)
      registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    } catch {
      await recordConnectionError(error)
      return await store.observe(plan)
    }

    await enterOperationGate()
    let existingPageInfo = await liveQueryPageInfo(for: registrationKey)
    let stream = await store.observeLiveQuery(
      plan,
      registrationKey: registrationKey,
      remotePageInfo: existingPageInfo.map(InstantQueryRemotePageInfo.ready) ?? .waiting
    )
    do {
      try await liveSession.registerQuery(
        query,
        key: registrationKey,
        clientEventID: configuration.makeID()
      )
      await leaveOperationGate()
    } catch {
      await leaveOperationGate()
      await recordConnectionError(error)
    }
    return Self.liveObservation(stream) { [weak self] in
      guard let self else { return }
      do {
        let didUnload = try await self.liveSession.unregisterQuery(
          key: registrationKey,
          clientEventID: self.configuration.makeID()
        )
        if didUnload {
          await self.liveQueryResultState.unload(key: registrationKey)
        }
      } catch {
        await self.liveQueryResultState.unload(key: registrationKey)
        await self.recordConnectionError(error)
      }
    }
  }

  public func query(_ plan: InstantQueryPlan) async throws -> [InstantEntitySnapshot] {
    try await queryOnce(plan).values
  }

  public func queryOnce(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    let startedAt = Date()
    do {
      let usesLiveTransport: Bool
      if configuration.liveTransport != nil, configuration.autoConnectLiveTransport {
        usesLiveTransport = try await persistedConnectionState() != .closed
      } else {
        usesLiveTransport = false
      }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-once.started",
        message: "Started a one-shot Instant query.",
        metadata: [
          "appID": configuration.appID,
          "namespace": plan.namespace,
          "transport": usesLiveTransport ? "websocket" : "local-cache",
        ],
        correlationID: plan.id
      )
      let emission = try await usesLiveTransport
        ? queryOnceThroughLive(plan)
        : materializeLocalQueryOnce(plan, enforcesConnectionFreshness: true)
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-once.completed",
        message: "One-shot Instant query completed.",
        metadata: [
          "namespace": plan.namespace,
          "resultCount": String(emission.values.count),
          "sequence": String(emission.sequence),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: plan.id
      )
      return emission
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-once.failed",
        message: "One-shot Instant query failed.",
        metadata: [
          "namespace": plan.namespace,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ],
        correlationID: plan.id
      )
      throw error
    }
  }

  private func queryOnceThroughLive(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    let query = try InstantLiveQueryEncoder.encode(plan)
    let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    let observedRevision = await liveQueryAcknowledgements.revision(for: registrationKey)

    // Match Reactor.queryOnce + _flushPendingMessages: record the query before
    // reconnecting so an opening session sends add-query ahead of its durable
    // mutation backlog.
    await enterOperationGate()
    do {
      try await liveSession.registerQuery(
        query,
        key: registrationKey,
        clientEventID: configuration.makeID(),
        requiresServerAcknowledgement: true
      )
      await leaveOperationGate()
    } catch {
      await leaveOperationGate()
      throw error
    }
    defer {
      Task {
        do {
          let didUnload = try await self.liveSession.unregisterQuery(
            key: registrationKey,
            clientEventID: self.configuration.makeID()
          )
          if didUnload {
            await self.liveQueryResultState.unload(key: registrationKey)
          }
        } catch {
          await self.liveQueryResultState.unload(key: registrationKey)
        }
      }
    }
    try await ensureLiveConnectionIfNeeded()

    do {
      try await instantLiveWithTimeout(
        operation: "run Instant live query",
        timeoutMilliseconds: 10_000
      ) {
        try await self.liveQueryAcknowledgements.wait(
          for: registrationKey,
          after: observedRevision
        )
      }
    } catch {
      if let error = error as? InstantError,
        error.operation == "run Instant live query",
        error.code == .permissionRejected || error.code == .validationFailed
      {
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query.live-rejected",
          message: "Live query was rejected by Instant validation or permissions.",
          metadata: ["registrationKey": registrationKey],
          correlationID: plan.id
        )
        throw error
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query.live-ack-timeout",
        message:
          "Live query did not receive a server acknowledgement within the timeout.",
        metadata: [
          "registrationKey": registrationKey,
          "namespace": plan.namespace,
          "timeoutMilliseconds": "10000",
        ],
        correlationID: plan.id
      )
      await recordConnectionError(error)
      throw error
    }
    let pageInfo = await liveQueryPageInfo(for: registrationKey)
    return try await materializeLocalQueryOnce(
      plan,
      remotePageInfo: pageInfo.map(InstantQueryRemotePageInfo.ready)
    )
  }

  package func queryLocally(_ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    try await materializeLocalQueryOnce(plan, enforcesConnectionFreshness: false)
  }

  private func liveQueryPageInfo(for registrationKey: String) async -> InstantQueryPageInfo? {
    if let pageInfo = await liveQueryResultState.pageInfo(for: registrationKey) {
      return pageInfo
    }
    do {
      recordActorHop(.persistence)
      guard let result = try await persistence.liveQueryResult(key: registrationKey) else {
        return nil
      }
      await liveQueryResultState.record(result)
      return result.pageInfo
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "live-query-result.load-failed",
        message: "Could not load the persisted live query result.",
        metadata: ["registrationKey": registrationKey]
      )
      return nil
    }
  }

  private func materializeLocalQueryOnce(
    _ plan: InstantQueryPlan,
    enforcesConnectionFreshness: Bool = true,
    remotePageInfo: InstantQueryRemotePageInfo? = nil
  ) async throws
    -> InstantQueryEmission
  {
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
        if enforcesConnectionFreshness,
          !configuration.isLocalOnly,
          try await persistedConnectionState() == .closed
        {
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
        let emission = await store.materializeEmission(plan, remotePageInfo: remotePageInfo)
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
          if queryCachePruningCadence.shouldPrune(
            afterSuccessfulWriteWithInterval: configuration.queryCachePruningWriteInterval
          ) {
            await pruneQueryCache(preserving: plan.cacheKey)
          }
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

  private func pruneQueryCache(preserving cacheKey: String) async {
    recordActorHop(.store)
    var preservedCacheKeys = await store.activeQueryCacheKeys()
    preservedCacheKeys.insert(cacheKey)
    do {
      recordActorHop(.persistence)
      let result = try await persistence.pruneQueryCache(
        policy: configuration.queryCachePruningPolicy,
        now: configuration.now(),
        preservingCacheKeys: preservedCacheKeys
      )
      guard !result.removedCacheKeys.isEmpty else { return }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-cache.pruned",
        message: "Pruned unloaded persisted query results after materialization.",
        metadata: [
          "preservedCount": String(preservedCacheKeys.count),
          "remainingCount": String(result.remainingEntryCount),
          "removedCount": String(result.removedCacheKeys.count),
        ],
        correlationID: cacheKey
      )
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query-cache.prune-failed",
        message: "Could not prune persisted query results after materialization.",
        metadata: ["preservedCount": String(preservedCacheKeys.count)],
        correlationID: cacheKey
      )
    }
  }

  func pruneLiveQueryResults(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp
  ) async throws -> InstantLiveQueryResultPruningResult {
    await enterOperationGate()
    do {
      let result = try await performPruneLiveQueryResults(policy: policy, now: now)
      await leaveOperationGate()
      return result
    } catch {
      await leaveOperationGate()
      throw error
    }
  }

  private func performPruneLiveQueryResults(
    policy: InstantLiveQueryResultPruningPolicy,
    now: InstantTimestamp
  ) async throws -> InstantLiveQueryResultPruningResult {
    let activeQueryKeys = await liveSession.activeQueryKeys()
    if let onActiveKeysCaptured =
      configuration.onLiveQueryResultPruneActiveKeysCapturedForTesting
    {
      await onActiveKeysCaptured(activeQueryKeys)
    }
    recordActorHop(.persistence)
    let application = try await persistence.pruneLiveQueryResults(
      policy: policy,
      now: now,
      preservingQueryKeys: activeQueryKeys
    )
    guard !application.result.removedQueryKeys.isEmpty else {
      return application.result
    }
    if application.result.removedOrphanedTripleCount > 0 {
      recordActorHop(.store)
      await store.replaceSnapshot(application.state.snapshot.store)
    }
    for key in application.result.removedQueryKeys {
      await liveQueryResultState.unload(key: key)
    }
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "query",
      event: "live-query-results.pruned",
      message: "Pruned unloaded persisted live query results and newly orphaned triples.",
      metadata: [
        "activeCount": String(activeQueryKeys.count),
        "remainingCount": String(application.result.remainingEntryCount),
        "remainingTripleCount": String(application.result.remainingTripleCount),
        "removedCount": String(application.result.removedQueryKeys.count),
        "removedOrphanedTripleCount": String(
          application.result.removedOrphanedTripleCount
        ),
      ]
    )
    return application.result
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

  private func ensureLiveConnectionIfNeeded() async throws {
    guard configuration.liveTransport != nil else { return }
    guard configuration.autoConnectLiveTransport else { return }
    guard await !liveSession.isOpen else { return }
    guard try await persistedConnectionState() != .closed else { return }
    await reconnectController.cancel()
    _ = try await connectLiveSession(reportsFailure: true, onlyIfNeeded: true)
  }

  private func startLiveMutationDeliveryIfNeeded() {
    guard configuration.liveTransport != nil else { return }
    guard configuration.autoConnectLiveTransport else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        try await self.ensureLiveConnectionIfNeeded()
        await self.sendOutstandingMutationsToLiveSession()
      } catch {
        await self.scheduleReconnect(
          after: error,
          event: "connection.optimistic-transaction-connect-failed",
          message: "Instant could not connect after an optimistic transaction and will retry."
        )
      }
    }
  }

  private func startAutomaticLiveConnectionIfNeeded() {
    guard configuration.liveTransport != nil else { return }
    guard configuration.autoConnectLiveTransport else { return }
    Task { [weak self] in
      guard let self else { return }
      do {
        try await self.ensureLiveConnectionIfNeeded()
      } catch {
        await self.scheduleReconnect(
          after: error,
          event: "connection.auto-connect-failed",
          message: "Automatic Instant connection failed and will retry."
        )
      }
    }
  }

  private func reconnectAfterAuthChangeIfNeeded() async {
    guard configuration.liveTransport != nil else { return }
    guard configuration.autoConnectLiveTransport else { return }
    guard (try? await persistedConnectionState()) != .closed else { return }
    do {
      _ = try await connect()
    } catch {
      await scheduleReconnect(
        after: error,
        event: "connection.auth-reconnect-failed",
        message: "Instant could not reconnect after authentication changed and will retry."
      )
    }
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

  private func connectLiveSession(
    reportsFailure: Bool,
    onlyIfNeeded: Bool = false
  ) async throws -> InstantConnectionStatus {
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "connection",
      event: "connection.open-started",
      message: "Opening the Instant connection.",
      metadata: [
        "appID": configuration.appID,
        "transport": configuration.liveTransport == nil ? "local-cache" : "websocket",
        "isReconnect": String(!reportsFailure),
        "websocketHost": configuration.websocketURI.host ?? "unknown",
      ]
    )
    await connectionGate.enter()
    var enteredConnectionGate = true
    var enteredOperationGate = false
    do {
      recordActorHop(.operationGate)
      await operationGate.enter()
      enteredOperationGate = true
      if onlyIfNeeded {
        let persistedState = try await persistedConnectionState()
        let liveSessionIsOpen = await liveSession.isOpen
        if persistedState == .closed || liveSessionIsOpen {
          let status = try await connectionStatusWithGateHeld()
          recordActorHop(.operationGate)
          await operationGate.leave()
          enteredOperationGate = false
          await connectionGate.leave()
          enteredConnectionGate = false
          InstantDiagnostics.shared.record(
            .debug,
            subsystem: "instant-swift-data-core",
            category: "connection",
            event: "connection.open-reused",
            message: liveSessionIsOpen
              ? "Reused the existing Instant connection."
              : "Preserved the explicitly closed Instant connection.",
            metadata: [
              "appID": configuration.appID,
              "state": status.state.rawValue,
            ]
          )
          return status
        }
      }
      if let liveTransport = configuration.liveTransport {
        recordActorHop(.persistence)
        let session = try await persistence.loadAuthSession(key: authSessionKey)
        recordActorHop(.operationGate)
        await operationGate.leave()
        enteredOperationGate = false
        do {
          recordActorHop(.liveSession)
          try await liveSession.open(
            request: InstantLiveSessionRequest(
              appID: configuration.appID,
              websocketURI: configuration.websocketURI,
              refreshToken: session?.refreshToken
            ),
            transport: liveTransport,
            makeID: configuration.makeID
          )
          recordActorHop(.liveSession)
          let openedServerAttributes = await liveSession.currentServerAttributes()
          recordActorHop(.operationGate)
          await operationGate.enter()
          enteredOperationGate = true
          // Store the server's attribute set before anything reads the cache. Namespaces added
          // to the schema after this device's last sync are unknown to it until this runs, and
          // an unknown namespace cannot even be subscribed to, so nothing else would ever
          // deliver them.
          try await applyServerAttributesWithGateHeld(openedServerAttributes)
          try await retryPersistedTransientMutationFailuresWithGateHeld()
          recordActorHop(.operationGate)
          await operationGate.leave()
          enteredOperationGate = false
          recordActorHop(.liveSession)
          let encodingFailures = try await liveSession.sendMutations(
            await outboxTransportMutations()
          )
          // Recording a quarantined mutation must never tear down a healthy
          // connection: the write is already durable locally, and closing here
          // left every later mutation undeliverable.
          do {
            try await persistLiveMutationEncodingFailures(encodingFailures)
          } catch {
            reportIssue(
              """
              Instant could not record \(encodingFailures.count) quarantined \
              mutation(s), but the connection stays open.

              \(String(describing: error))
              """
            )
          }
        } catch {
          if enteredOperationGate {
            recordActorHop(.operationGate)
            await operationGate.leave()
            enteredOperationGate = false
          }
          recordActorHop(.liveSession)
          await liveSession.close()
          recordActorHop(.operationGate)
          await operationGate.enter()
          enteredOperationGate = true
          try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
          if reportsFailure {
            _ = try? await publishConnectionStatusWithGateHeld()
          }
          throw error
        }
      }
      if !enteredOperationGate {
        recordActorHop(.operationGate)
        await operationGate.enter()
        enteredOperationGate = true
      }
      try await saveOpenedConnectionMetadataWithGateHeld()
      let status = try await publishConnectionStatusWithGateHeld()
      recordActorHop(.operationGate)
      await operationGate.leave()
      enteredOperationGate = false
      await connectionGate.leave()
      enteredConnectionGate = false
      if configuration.liveTransport != nil {
        recordActorHop(.liveSession)
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
        do {
          recordActorHop(.liveSession)
          try await liveSession.reconnectStreamWriters()
        } catch {
          recordActorHop(.liveSession)
          await liveSession.close()
          await handleLiveSessionFailure(error)
        }
      }
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "connection",
        event: "connection.open-completed",
        message: "Instant connection opened.",
        metadata: [
          "appID": configuration.appID,
          "state": status.state.rawValue,
          "authenticated": String(status.isAuthenticated),
          "pendingMutationCount": String(status.pendingMutationCount),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      return status
    } catch {
      if enteredOperationGate {
        recordActorHop(.operationGate)
        await operationGate.leave()
      }
      if enteredConnectionGate {
        await connectionGate.leave()
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "connection",
        event: "connection.open-failed",
        message: "Instant connection failed to open.",
        metadata: [
          "appID": configuration.appID,
          "isReconnect": String(!reportsFailure),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      throw error
    }
  }

  @discardableResult
  public func closeConnection() async throws -> InstantConnectionStatus {
    await reconnectController.cancel()
    await connectionGate.enter()
    recordActorHop(.operationGate)
    await operationGate.enter()
    do {
      recordActorHop(.liveSession)
      await liveSession.close()
      try await persistence.saveMetadataValue(
        InstantConnectionState.closed.rawValue,
        key: connectionStateMetadataKey,
        updatedAt: configuration.now()
      )
      let status = try await publishConnectionStatusWithGateHeld()
      recordActorHop(.operationGate)
      await operationGate.leave()
      await connectionGate.leave()
      return status
    } catch {
      recordActorHop(.operationGate)
      await operationGate.leave()
      await connectionGate.leave()
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
      guard mutation.provesServerAcceptance else { return }
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
      await operationGate.leave()
    } catch {
      await operationGate.leave()
    }
  }

  private func handleLiveSessionFailure(_ error: Error) async {
    await scheduleReconnect(
      after: error,
      event: "connection.receive-loop-failed",
      message: "Instant live receive loop ended with an error."
    )
  }

  private func scheduleReconnect(
    after error: Error,
    event: String,
    message: String
  ) async {
    InstantDiagnostics.shared.record(
      error: error,
      subsystem: "instant-swift-data-core",
      category: "connection",
      event: event,
      message: message,
      metadata: ["appID": configuration.appID]
    )
    if let error = error as? InstantError,
      error.operation == "process Instant stream file retries"
    {
      await recordConnectionError(error)
      return
    }
    await operationGate.enter()
    do {
      try await saveErroredConnectionMetadataWithGateHeld(message: String(describing: error))
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
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "transport",
      event: "websocket.event-received",
      message: "Received an Instant WebSocket event.",
      metadata: [
        "appID": configuration.appID,
        "op": event.op,
        "serverAttributeCount": String(serverAttributes.count),
      ]
    )
    switch event {
    case let .addQueryOK(queryOK):
      guard let query = queryOK.query else {
        throw InstantError(
          code: .decodeFailed,
          operation: "apply Instant live query result",
          message: "add-query-ok must include q.",
          recovery: "Inspect the canonical Instant add-query-ok payload."
        )
      }
      let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
      guard !queryOK.result.isEmpty else {
        await liveQueryAcknowledgements.record(key: registrationKey)
        return
      }
      guard let processedTransactionID = queryOK.processedTransactionID?.nilIfEmpty else {
        throw InstantError(
          code: .decodeFailed,
          operation: "apply Instant live query result",
          message: "A non-empty add-query-ok must include processed-tx-id.",
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
      await liveQueryAcknowledgements.record(key: registrationKey)

    case let .addQueryExists(queryOK):
      guard let query = queryOK.query else {
        throw InstantError(
          code: .decodeFailed,
          operation: "acknowledge existing Instant live query",
          message: "add-query-exists must include q.",
          recovery: "Inspect the canonical Instant add-query-exists payload."
        )
      }
      let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
      await liveQueryAcknowledgements.record(key: registrationKey)

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
        let transactionID = transactOK.transactionID?.nilIfEmpty
      else {
        InstantDiagnostics.shared.record(
          .error,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.transact-ok-malformed",
          message: "Received transact-ok without client-event-id or tx-id.",
          metadata: [
            "clientEventIDPresent": String(transactOK.clientEventID?.nilIfEmpty != nil),
            "transactionIDPresent": String(transactOK.transactionID?.nilIfEmpty != nil),
          ]
        )
        throw InstantError(
          code: .decodeFailed,
          operation: "confirm Instant live transaction",
          message: "transact-ok must include client-event-id and tx-id.",
          recovery: "Inspect the canonical Instant transact-ok payload."
        )
      }
      InstantDiagnostics.shared.record(
        .debug,
        subsystem: "instant-swift-data-core",
        category: "outbox",
        event: "outbox.mutation.transact-ok",
        message: "Server acknowledged an outbox mutation (transact-ok).",
        metadata: [
          "mutationID": clientEventID,
          "serverTransactionID": transactionID,
        ],
        correlationID: clientEventID
      )
      _ = try await acceptMutationIfPresent(
        id: clientEventID,
        serverTransactionID: transactionID
      )
      await sendOutstandingMutationsToLiveSession()

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
      let seenOffset: Int64
      do {
        seenOffset = try await applyLiveStreamAppend(delivery)
      } catch let error as InstantError where error.operation == "fetch Instant stream file" {
        switch await liveSession.recordStreamFileFetchFailure(
          clientEventID: delivery.clientEventID
        ) {
        case let .failure(failure):
          throw failure
        case .requestReconnect, .deliver, .ignored:
          throw error
        }
      }
      await liveSession.recordDeliveredStreamAppend(delivery, seenOffset: seenOffset)

    case let .error(error):
      if let clientEventID = error.clientEventID?.nilIfEmpty,
        await mutationDeliveryBarrierMutations().contains(where: { mutation in
          mutation.id == clientEventID
            && (mutation.status == .pending
              || (mutation.status == .confirmed && !mutation.provesServerAcceptance))
        })
      {
        if Self.isRetryableMutationError(error) {
          InstantDiagnostics.shared.record(
            .warning,
            subsystem: "instant-swift-data-core",
            category: "outbox",
            event: "outbox.mutation.server-error-retryable",
            message: "Server returned a retryable error for an outbox mutation.",
            metadata: [
              "mutationID": clientEventID,
              "errorMessage": error.message,
              "serverStatus": error.status.map(String.init) ?? "",
              "serverType": error.type ?? "",
              "serverTraceID": error.traceID ?? "",
            ],
            correlationID: clientEventID
          )
          throw InstantError(
            code: .networkFailed,
            operation: "receive retryable Instant live mutation error",
            serverEventID: clientEventID,
            serverStatus: error.status,
            serverType: error.type,
            serverHint: error.hint,
            serverTraceID: error.traceID,
            serverOriginalEventTraceID: error.originalEventTraceID,
            message: error.message,
            recovery: "Reconnect and resend the durable pending mutation."
          )
        }
        InstantDiagnostics.shared.record(
          .error,
          subsystem: "instant-swift-data-core",
          category: "outbox",
          event: "outbox.mutation.server-error-terminal",
          message: "Server permanently rejected an outbox mutation.",
          metadata: [
            "mutationID": clientEventID,
            "errorMessage": error.message,
            "serverStatus": error.status.map(String.init) ?? "",
            "serverType": error.type ?? "",
            "serverTraceID": error.traceID ?? "",
            "serverHint": error.hint.map { String(describing: $0) } ?? "",
          ],
          correlationID: clientEventID
        )
        _ = try await failMutation(
          id: clientEventID,
          failure: Self.mutationFailure(from: error)
        )
        try await liveSession.refreshRegisteredQueries()
        await sendOutstandingMutationsToLiveSession()
        return
      }
      if await liveSession.retireRejectedStreamReader(
        clientEventID: error.clientEventID?.nilIfEmpty,
        message: error.message
      ) {
        return
      }
      if let originalEvent = error.originalEvent,
        originalEvent.op == "add-query",
        let query = originalEvent.fields["q"]
      {
        let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
        let rejection = InstantError(
          code: error.status == 401 || error.status == 403
            ? .permissionRejected
            : .validationFailed,
          operation: "run Instant live query",
          serverEventID: originalEvent.clientEventID ?? error.clientEventID,
          serverStatus: error.status,
          serverType: error.type,
          serverHint: error.hint,
          serverTraceID: error.traceID,
          serverOriginalEventTraceID: error.originalEventTraceID,
          message: error.message,
          recovery: "Inspect the rejected query and its Instant permissions without reconnecting the healthy live session."
        )
        if await liveSession.retireRejectedQuery(key: registrationKey) {
          await liveQueryResultState.unload(key: registrationKey)
        }
        await liveQueryAcknowledgements.reject(key: registrationKey, error: rejection)
        InstantDiagnostics.shared.record(
          error: rejection,
          subsystem: "instant-swift-data-core",
          category: "query",
          event: "query.live-rejected",
          message: "Instant rejected one live query without interrupting the shared socket.",
          metadata: ["registrationKey": registrationKey]
        )
        return
      }
      throw InstantError(
        code: .networkFailed,
        operation: "receive Instant live server event",
        serverEventID: error.clientEventID,
        serverStatus: error.status,
        serverType: error.type,
        serverHint: error.hint,
        serverTraceID: error.traceID,
        serverOriginalEventTraceID: error.originalEventTraceID,
        message: error.message,
        recovery: "Inspect the Instant runtime WebSocket event and reconnect."
      )

    case .initOK, .joinRoomOK, .leaveRoomOK, .startStreamOK,
      .streamFlushed, .appendFailed, .other:
      break
    }
  }

  private static func isRetryableMutationError(_ error: InstantLiveErrorMessage) -> Bool {
    let type = error.type?.lowercased() ?? ""
    if error.status == 401 || error.status == 403
      || type.contains("permission")
      || type.contains("unauthorized")
      || type.contains("forbidden")
    {
      return false
    }
    if let status = error.status,
      status == 408 || status == 425 || status == 429 || (500...599).contains(status)
    {
      return true
    }
    if type.contains("timeout")
      || type.contains("network")
      || type.contains("service-unavailable")
      || type.contains("temporarily-unavailable")
    {
      return true
    }
    return isRetryableMutationFailureMessage(error.message)
  }

  private static func isRetryableMutationFailureMessage(_ rawMessage: String) -> Bool {
    let message = rawMessage.lowercased()
    return message.contains("operation timed out")
      || message.contains("transaction timed out")
      || message.contains("service unavailable")
      || message.contains("temporarily unavailable")
      || isDeployFixableMutationFailureMessage(message)
  }

  private static func mutationFailure(
    from error: InstantLiveErrorMessage
  ) -> InstantMutationFailure {
    let status = error.status
    let type = error.type?.lowercased() ?? ""
    let message = error.message.lowercased()
    let code: InstantError.Code =
      if status == 401 || status == 403
        || type.contains("permission")
        || type.contains("unauthorized")
        || type.contains("forbidden")
        || message.contains("permission")
        || message.contains("unauthorized")
        || message.contains("forbidden")
      {
        .permissionRejected
      } else {
        .validationFailed
      }
    return InstantMutationFailure(
      code: code,
      message: error.message,
      status: error.status,
      type: error.type,
      hint: error.hint,
      traceID: error.traceID,
      originalEventTraceID: error.originalEventTraceID
    )
  }

  /// Failures a schema deployment resolves. Retrying them on a fresh session —
  /// which re-reads the server's attributes — lets a quarantined write deliver
  /// once the deployment lands. Permission rejections are deliberately excluded:
  /// upstream rejects those mutations, and silently replaying them would hide the
  /// exact denied write from the caller.
  private static func isDeployFixableMutationFailureMessage(_ message: String) -> Bool {
    message.contains("could not resolve")
  }

  private func retryPersistedTransientMutationFailuresWithGateHeld() async throws {
    let reservedMutationIDs = await automaticMutationRetryReservations.snapshot()
    recordActorHop(.persistence)
    let state = try await persistence.loadState()
    let retryIDs: [String] = state.snapshot.outbox.compactMap { mutation -> String? in
      guard mutation.status == .failed,
        mutation.failureMessage.map(Self.isRetryableMutationFailureMessage) == true,
        !reservedMutationIDs.contains(mutation.id)
      else { return nil }
      return mutation.id
    }
    for id in retryIDs {
      do {
        _ = try await performRetryMutationWithGateHeld(id: id)
      } catch let error as InstantError
        where error.localMutationDisposition == .retainedUnknown
      {
        // A row written before durable optimistic-overlay metadata existed can
        // never be retried automatically, because its local cache effect is
        // unknowable. Refusing it is correct; aborting this sweep is not.
        //
        // This sweep runs inside the live-connect path, so rethrowing closed
        // the socket, stored an `errored` connection state, and rethrew to the
        // caller. Every reconnect then repeated it, which meant one upgraded
        // device row stopped queries registering, stopped every later mutation,
        // and silenced the separate diagnostic-log client. Retain it, report it
        // for an authoritative recovery, and keep delivering everything else.
        reportIssue(
          """
          Instant retained mutation '\(id)' and skipped its automatic retry; \
          the connection stays open.

          \(String(describing: error))
          """
        )
        continue
      }
    }
  }

  private func applyLiveStreamAppend(_ append: InstantLiveStreamAppend) async throws -> Int64 {
    var current = try await persistence.loadStreamContent(
      appID: configuration.appID,
      streamID: append.streamID,
      byteOffset: 0
    )
    if current == nil {
      let userID = try await resolvedAuthenticatedUserID(
        operation: "bootstrap stream metadata",
        noun: "Stream"
      )
      _ = try await persistence.ensureStreamMetadata(
        appID: configuration.appID,
        streamID: append.streamID,
        clientID: append.clientID?.nilIfEmpty ?? append.streamID,
        userID: userID,
        createdAt: configuration.now()
      )
      current = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: append.streamID,
        byteOffset: 0
      )
    }
    guard let current else {
      throw InstantError(
        code: .persistenceFailed,
        operation: "bootstrap stream metadata",
        serverEventID: append.clientEventID,
        message: "Instant stream '\(append.streamID)' was not readable after metadata bootstrap.",
        recovery: "Inspect the local stream persistence transaction and retry the subscription."
      )
    }
    let seenOffset = current.byteOffset + current.byteCount
    let materialization = try await InstantStreamFileAppendMaterializer.materialize(
      append,
      seenOffset: seenOffset,
      transport: streamFileTransport
    )

    if !materialization.data.isEmpty {
      guard let content = String(data: materialization.data, encoding: .utf8) else {
        throw InstantError(
          code: .decodeFailed,
          operation: "materialize Instant stream append",
          path: "content",
          serverEventID: append.clientEventID,
          message: "Instant stream file content is not valid UTF-8.",
          recovery: "Reconnect from a server-confirmed UTF-8 byte boundary."
        )
      }
      _ = try await appendStreamContent(
        streamID: append.streamID,
        content: content,
        expectedOffset: seenOffset
      )
    }
    if append.done {
      _ = try await closeStream(
        streamID: append.streamID,
        abortReason: append.abortReason
      )
    }
    return materialization.nextSeenOffset
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
    let activeLocalMembers = await activeRoomPresenceState.activeMembers(
      localMembers,
      in: room
    )
    let observerCount = await roomPresenceObservers.activeCount(
      for: roomPresenceObservationKey(room)
    )
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "presence",
      event: "live-presence.refresh-applied",
      message: "Applied a live room presence refresh.",
      metadata: [
        "roomType": room.type,
        "sessionCount": String(refresh.sessions.count),
        "remoteMemberCount": String(remoteMembers.count),
        "localMemberCount": String(localMembers.count),
        "activeLocalMemberCount": String(activeLocalMembers.count),
        "observerCount": String(observerCount),
      ]
    )
    await roomPresenceObservers.publish(
      mergedRoomPresence(local: activeLocalMembers, remote: remoteMembers),
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
    let activeLocalMembers = await activeRoomPresenceState.activeMembers(
      localMembers,
      in: room
    )
    let observerCount = await roomPresenceObservers.activeCount(
      for: roomPresenceObservationKey(room)
    )
    InstantDiagnostics.shared.record(
      .trace,
      subsystem: "instant-swift-data-core",
      category: "presence",
      event: "live-presence.patch-applied",
      message: "Applied a live room presence patch.",
      metadata: [
        "roomType": room.type,
        "editCount": String(patch.edits.count),
        "remoteMemberCount": String(remoteMembers.count),
        "localMemberCount": String(localMembers.count),
        "activeLocalMemberCount": String(activeLocalMembers.count),
        "observerCount": String(observerCount),
      ]
    )
    await roomPresenceObservers.publish(
      mergedRoomPresence(local: activeLocalMembers, remote: remoteMembers),
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

  package func sendOutstandingMutationsToLiveSession() async {
    guard configuration.liveTransport != nil else { return }
    do {
      recordActorHop(.liveSession)
      let outstanding = await outboxTransportMutations()
      let encodingFailures = try await liveSession.sendMutations(outstanding)
      do {
        try await persistLiveMutationEncodingFailures(encodingFailures)
      } catch {
        reportIssue(
          """
          Instant could not record \(encodingFailures.count) quarantined \
          mutation(s), but delivery continues.

          \(String(describing: error))
          """
        )
      }
    } catch {
      await recordConnectionError(error)
    }
  }

  private func persistLiveMutationEncodingFailures(
    _ failures: [InstantLiveMutationEncodingFailure]
  ) async throws {
    for failure in failures {
      _ = try await failMutation(
        id: failure.mutationID,
        failure: InstantMutationFailure(
          code: .validationFailed,
          message: failure.message
        ),
        recordsConnectionFailure: false
      )
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
    let startedAt = Date()
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "auth",
      event: "guest-auth.started",
      message: "Starting Instant guest authentication.",
      metadata: ["appID": configuration.appID]
    )
    do {
      let now = configuration.now()
      let verification = try await configuration.guestAuthenticator.signIn(
        InstantGuestAuthRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          signedInAt: now,
          makeID: configuration.makeID
        )
      )
      let session = InstantAuthSession(
        appID: configuration.appID,
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        isGuest: true,
        createdAt: now,
        updatedAt: now,
        email: verification.email,
        imageURL: verification.imageURL,
        type: verification.type ?? .guest
      )
      _ = try await saveGuestUserFields(userID: session.userID, signedInAt: now)
      try await saveAuthSession(session)
      InstantDiagnostics.shared.record(
        .notice,
        subsystem: "instant-swift-data-core",
        category: "auth",
        event: "guest-auth.completed",
        message: "Instant guest authentication completed.",
        metadata: [
          "appID": configuration.appID,
          "userID": session.userID,
          "hasRefreshToken": String(session.refreshToken?.isEmpty == false),
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      return session
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "auth",
        event: "guest-auth.failed",
        message: "Instant guest authentication failed.",
        metadata: [
          "appID": configuration.appID,
          "durationMilliseconds": String(
            Int64((Date().timeIntervalSince(startedAt) * 1_000).rounded())
          ),
        ]
      )
      throw error
    }
  }

  public func sendMagicCode(email rawEmail: String) async throws -> InstantMagicCodeChallenge {
    let email = try normalizedEmail(rawEmail, operation: "send magic code")
    let now = configuration.now()
    let challenge = try await configuration.magicCodeExchange.send(
      InstantMagicCodeSendRequest(
        appID: configuration.appID,
        apiURI: configuration.apiURI,
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
      let currentRefreshToken = try await persistence.loadAuthSession(key: authSessionKey)?
        .refreshToken
      let verification = try await configuration.magicCodeExchange.verify(
        InstantMagicCodeVerifyRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          email: email,
          code: code,
          challenge: challenge,
          refreshToken: currentRefreshToken,
          extraFields: extraFields,
          verifiedAt: now
        )
      )
      let session = InstantAuthSession(
        appID: configuration.appID,
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        isGuest: false,
        createdAt: now,
        updatedAt: now,
        email: verification.email ?? email,
        imageURL: verification.imageURL,
        type: verification.type ?? .user
      )
      let locallyCreated = try await saveMagicCodeUserFields(
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
      await reconnectAfterAuthChangeIfNeeded()
      _ = try? await syncUserCookieToEndpoint(session)
      return InstantMagicCodeSignInResult(
        session: session,
        created: verification.created ?? locallyCreated
      )
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

  private func saveGuestUserFields(
    userID: String,
    signedInAt: InstantTimestamp
  ) async throws -> Bool {
    recordActorHop(.persistence)
    let state = try await persistence.loadState()
    let attributes = AttributeStore(attributes: state.snapshot.store.attributes)
    let canWriteUsers =
      attributes.namespaces.isEmpty || attributes.namespaces.contains(Self.authUsersNamespace)
    guard canWriteUsers else { return false }

    let userExists = state.snapshot.store.triples.contains { triple in
      triple.entityID == userID && triple.attributeID.hasPrefix(Self.authUsersNamespace + "/")
    }
    guard !userExists else { return false }

    let transactionID = "auth.guest.\(configuration.makeID())"
    _ = try await performApplyServerTransaction(
      InstantStoreTransaction(
        id: transactionID,
        operations: [
          .requireEntityMissing(entityID: userID, namespace: Self.authUsersNamespace),
          .insert(
            InstantTriple(
              entityID: userID,
              attributeID: InstantAttribute.primaryKeyID(namespace: Self.authUsersNamespace),
              value: .string(userID),
              txID: transactionID,
              txTime: signedInAt
            )
          ),
        ]
      ),
      processedTransactionID: transactionID,
      receivedAt: signedInAt
    )
    return true
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
        apiURI: configuration.apiURI,
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
      isGuest: verification.type == .guest,
      createdAt: now,
      updatedAt: now,
      email: verification.email,
      imageURL: verification.imageURL,
      type: verification.type
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
        apiURI: configuration.apiURI,
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
      updatedAt: now,
      email: verification.email,
      imageURL: verification.imageURL,
      type: verification.type ?? .user
    )
    try await saveAuthSession(session)
    return session
  }

  public func promoteGuestWithIDToken(
    clientName rawClientName: String,
    idToken rawIDToken: String,
    nonce rawNonce: String? = nil
  ) async throws -> InstantGuestPromotionExchangeResult {
    let clientName = rawClientName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clientName.isEmpty else {
      throw authValidationFailed(
        operation: "promote guest with id token",
        message: "Client name must not be empty.",
        recovery: "Pass the Instant OAuth client name, for example 'apple'."
      )
    }
    let idToken = rawIDToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !idToken.isEmpty else {
      throw authValidationFailed(
        operation: "promote guest with id token",
        message: "ID token must not be empty.",
        recovery: "Pass the ID token returned by the native OAuth provider."
      )
    }

    await authPromotionGate.enter()
    do {
      try Task.checkCancellation()
      let guest = try await guestPromotionSnapshot()
      let now = configuration.now()
      let verification = try await configuration.idTokenExchange.signIn(
        InstantIDTokenSignInRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          clientName: clientName,
          idToken: idToken,
          nonce: rawNonce,
          refreshToken: guest.refreshToken,
          signedInAt: now,
          makeID: configuration.makeID
        )
      )
      let session = promotedAuthSession(
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        email: verification.email,
        imageURL: verification.imageURL,
        type: verification.type,
        timestamp: now
      )
      let result = try await commitGuestPromotion(
        guest: guest.session,
        promoted: session,
        linkEvidence: verification.guestPromotionLinkEvidence
      )
      await authPromotionGate.leave()
      return result
    } catch {
      await authPromotionGate.leave()
      throw error
    }
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
        apiURI: configuration.apiURI,
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
      updatedAt: now,
      email: verification.email,
      imageURL: verification.imageURL,
      type: verification.type ?? .user
    )
    try await saveAuthSession(session)
    return session
  }

  public func promoteGuestWithOAuth(
    code rawCode: String,
    codeVerifier rawCodeVerifier: String? = nil
  ) async throws -> InstantGuestPromotionExchangeResult {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      throw authValidationFailed(
        operation: "promote guest with oauth",
        message: "OAuth authorization code must not be empty.",
        recovery: "Pass the authorization code returned by the OAuth callback."
      )
    }

    await authPromotionGate.enter()
    do {
      try Task.checkCancellation()
      let guest = try await guestPromotionSnapshot()
      let now = configuration.now()
      let verification = try await configuration.oauthExchange.signIn(
        InstantOAuthSignInRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          code: code,
          codeVerifier: rawCodeVerifier,
          refreshToken: guest.refreshToken,
          signedInAt: now,
          makeID: configuration.makeID
        )
      )
      let session = promotedAuthSession(
        userID: verification.userID,
        refreshToken: verification.refreshToken,
        email: verification.email,
        imageURL: verification.imageURL,
        type: verification.type,
        timestamp: now
      )
      let result = try await commitGuestPromotion(
        guest: guest.session,
        promoted: session,
        linkEvidence: verification.guestPromotionLinkEvidence
      )
      await authPromotionGate.leave()
      return result
    } catch {
      await authPromotionGate.leave()
      throw error
    }
  }

  private func guestPromotionSnapshot() async throws -> (
    session: InstantAuthSession,
    refreshToken: String
  ) {
    guard let session = try await authSession(), session.isGuest else {
      throw InstantError(
        code: .authFailed,
        operation: "promote guest account",
        message: "Guest promotion requires an active guest session.",
        recovery:
          "Sign in as a guest first, then exchange the provider credential without signing out."
      )
    }
    guard
      let refreshToken = session.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
      !refreshToken.isEmpty
    else {
      throw InstantError(
        code: .authFailed,
        operation: "promote guest account",
        message: "The active guest session has no refresh token to link during provider exchange.",
        recovery: "Create a fresh online guest session before connecting an auth provider."
      )
    }
    return (session, refreshToken)
  }

  private func promotedAuthSession(
    userID: String,
    refreshToken: String?,
    email: String?,
    imageURL: String?,
    type: InstantAuthUserType?,
    timestamp: InstantTimestamp
  ) -> InstantAuthSession {
    InstantAuthSession(
      appID: configuration.appID,
      userID: userID,
      refreshToken: refreshToken,
      isGuest: false,
      createdAt: timestamp,
      updatedAt: timestamp,
      email: email,
      imageURL: imageURL,
      type: type ?? .user
    )
  }

  private func commitGuestPromotion(
    guest: InstantAuthSession,
    promoted: InstantAuthSession,
    linkEvidence: InstantGuestPromotionLinkEvidence?
  ) async throws -> InstantGuestPromotionExchangeResult {
    // The provider exchange has already succeeded and may have consumed a one-time credential.
    // Cancellation can suppress stale UI callbacks, but it must not discard this server result.
    await operationGate.enter()
    do {
      let current = try await persistence.loadAuthSession(key: authSessionKey)
      guard current == guest else {
        let error = InstantError(
          code: .authFailed,
          operation: "promote guest account",
          message:
            "Provider exchange succeeded, but the local auth session changed before promotion could be committed.",
          recovery:
            "Keep the current session and reconcile it with Instant before retrying; the provider credential may already be consumed."
        )
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "auth",
          event: "guest-promotion.compare-and-swap-diverged",
          message: "Refused to overwrite auth after a successful guest-promotion exchange.",
          metadata: [
            "guestUserID": guest.userID,
            "promotedUserID": promoted.userID,
            "currentUserID": current?.userID ?? "signed-out",
            "currentIsGuest": current.map { String($0.isGuest) } ?? "none",
          ]
        )
        throw error
      }
      try await persistAuthSessionWithGateHeld(promoted)
      await operationGate.leave()
    } catch {
      await operationGate.leave()
      throw error
    }

    recordPersistedAuthSession(promoted)
    await reconnectAfterAuthChangeIfNeeded()
    _ = try? await syncUserCookieToEndpoint(promoted)

    let disposition: InstantGuestPromotionExchangeDisposition
    if promoted.userID == guest.userID {
      disposition = .upgradedInPlace
    } else if linkEvidence == .instantServerAcceptedGuestToken {
      disposition = .linkedToExistingUser
    } else {
      disposition = .identityChangedWithoutVerifiedLink
    }
    return InstantGuestPromotionExchangeResult(
      guestUserID: guest.userID,
      session: promoted,
      disposition: disposition
    )
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
          apiURI: configuration.apiURI,
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

    await reconnectAfterAuthChangeIfNeeded()
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
      await activeRoomPresenceState.removeAll(in: room)
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
      if configuration.liveTransport != nil {
        await activeRoomPresenceState.activate(userID: userID, in: room)
      }
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
      if configuration.liveTransport != nil {
        await activeRoomPresenceState.deactivate(userID: userID, in: room)
      }
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
    var file = file
    var uploadedPath: String?
    var uploadedRefreshToken: String?
    if let storageTransport {
      let refreshToken = try await storageRefreshToken(operation: "upload file")
      let response = try await storageTransport.upload(
        InstantStorageUploadRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          path: file.name,
          data: try Data(contentsOf: sourceURL),
          refreshToken: refreshToken,
          contentType: file.contentType
        )
      )
      file.id = response.id
      uploadedPath = file.name
      uploadedRefreshToken = refreshToken
    }
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
      if let storageTransport,
        let uploadedPath,
        let uploadedRefreshToken
      {
        _ = try? await storageTransport.delete(
          InstantStorageDeleteRequest(
            appID: configuration.appID,
            apiURI: configuration.apiURI,
            path: uploadedPath,
            refreshToken: uploadedRefreshToken
          )
        )
      }
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
    _ = try await resolvedFileUserID(operation: "list files")
    if storageTransport != nil, configuration.liveTransport != nil {
      do {
        let remote = try await queryOnce(Self.storedFilesQuery).values
        return try await mergedStoredFiles(remoteSnapshots: remote)
      } catch let error as InstantError where error.code == .networkFailed {
        // Preserve Instant's offline-first behavior: a disconnected device can
        // still enumerate files it has already downloaded.
      }
    }
    return try await persistence.loadStoredFiles(appID: configuration.appID)
  }

  public func storageSnapshot() async throws -> InstantStorageSnapshot {
    await operationGate.enter()
    do {
      let snapshot = try await persistence.storageSnapshot(appID: configuration.appID)
      await operationGate.leave()
      return snapshot
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  public func observeStoredFiles() async throws -> AsyncStream<[InstantStoredFile]> {
    if storageTransport != nil, configuration.liveTransport != nil {
      _ = try await resolvedFileUserID(operation: "observe files")
      do {
        _ = try await queryOnce(Self.storedFilesQuery)
      } catch let error as InstantError where error.code == .networkFailed {
        return try await localStoredFilesStream()
      }
      let remoteStream = await observe(Self.storedFilesQuery)
      return AsyncStream { continuation in
        let task = Task {
          for await emission in remoteStream {
            guard !Task.isCancelled else { break }
            do {
              continuation.yield(
                try await self.mergedStoredFiles(remoteSnapshots: emission.values)
              )
            } catch {
              continuation.finish()
              return
            }
          }
          continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
      }
    }
    return try await localStoredFilesStream()
  }

  private func localStoredFilesStream() async throws -> AsyncStream<[InstantStoredFile]> {
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

  public func storedFileContents(
    id rawID: String,
    name rawName: String? = nil
  ) async throws -> InstantStoredFileContents {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "read file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )
    let name = try rawName.map {
      try validatedNonEmpty(
        $0,
        label: "File name",
        operation: "read file",
        recovery: "Pass the storage path returned when the file was uploaded."
      )
    }

    let userID = try await resolvedFileUserID(operation: "read file")
    if let contents = try await persistence.readStoredFileContents(
      appID: configuration.appID,
      fileID: id
    ) {
      return contents
    }

    guard let storageTransport else {
      throw validationFailed(
        operation: "read file",
        localID: id,
        message: "No downloaded file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect available file ids."
      )
    }
    if let name {
      let refreshToken = try await storageRefreshToken(operation: "read file")
      let data = try await storageTransport.downloadFile(
        InstantStorageFileDownloadRequest(
          appID: configuration.appID,
          apiURI: configuration.apiURI,
          path: name,
          refreshToken: refreshToken
        )
      )
      let now = configuration.now()
      let file = InstantStoredFile(
        id: id,
        appID: configuration.appID,
        name: name,
        contentType: nil,
        byteCount: Int64(data.count),
        localPath: "",
        ownerUserID: userID,
        createdAt: now,
        updatedAt: now
      )
      let saved = try await persistence.saveDownloadedFile(file, data: data)
      let localFiles = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(localFiles, for: storedFilesObservationKey)
      return InstantStoredFileContents(file: saved, data: data)
    }
    guard configuration.liveTransport != nil else {
      throw validationFailed(
        operation: "read file",
        localID: id,
        message: "No downloaded file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect available file ids."
      )
    }
    let remoteFiles = try await remoteStoredFiles()
    guard let file = remoteFiles.first(where: { $0.id == id }), let remoteURL = file.remoteURL else {
      throw validationFailed(
        operation: "read file",
        localID: id,
        message: "No remote file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect remote file ids."
      )
    }
    let data = try await storageTransport.download(
      InstantStorageDownloadRequest(url: remoteURL)
    )
    let saved = try await persistence.saveDownloadedFile(file, data: data)
    let localFiles = try await persistence.loadStoredFiles(appID: configuration.appID)
    await storedFilesObservers.publish(localFiles, for: storedFilesObservationKey)
    return InstantStoredFileContents(file: saved, data: data)
  }

  @discardableResult
  public func deleteStoredFile(id rawID: String) async throws -> InstantStoredFile {
    let id = try validatedNonEmpty(
      rawID,
      label: "File id",
      operation: "delete file",
      recovery: "Pass the id returned by 'instant-swift-data files list'."
    )

    _ = try await resolvedFileUserID(operation: "delete file")
    let file = try await storedFiles().first(where: { $0.id == id })
    guard let file else {
      throw validationFailed(
        operation: "delete file",
        localID: id,
        message: "No local or remote file exists for id '\(id)'.",
        recovery: "Run 'instant-swift-data files list' to inspect available file ids."
      )
    }
    do {
      if let storageTransport {
        let refreshToken = try await storageRefreshToken(operation: "delete file")
        _ = try await storageTransport.delete(
          InstantStorageDeleteRequest(
            appID: configuration.appID,
            apiURI: configuration.apiURI,
            path: file.name,
            refreshToken: refreshToken
          )
        )
      }
      _ = try await persistence.deleteStoredFile(
        appID: configuration.appID,
        fileID: id
      )
      let files = try await persistence.loadStoredFiles(appID: configuration.appID)
      await storedFilesObservers.publish(
        files,
        for: storedFilesObservationKey
      )
      return file
    } catch {
      throw error
    }
  }

  private static let storedFilesQuery = InstantQueryPlan(
    id: "instant.storage.files",
    namespace: "$files",
    order: .serverCreatedAt
  )

  private func remoteStoredFiles() async throws -> [InstantStoredFile] {
    let emission = try await queryOnce(Self.storedFilesQuery)
    return try await mergedStoredFiles(
      remoteSnapshots: emission.values,
      includeLocalOnly: false
    )
  }

  private func mergedStoredFiles(
    remoteSnapshots: [InstantEntitySnapshot],
    includeLocalOnly: Bool = true
  ) async throws -> [InstantStoredFile] {
    let remote = remoteSnapshots.compactMap(remoteStoredFile(from:))
    let local = try await persistence.loadStoredFiles(appID: configuration.appID)
    var filesByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
    for var file in local {
      if let discovered = filesByID[file.id] {
        file.name = discovered.name
        file.contentType = discovered.contentType ?? file.contentType
        file.remoteURL = discovered.remoteURL
      }
      if includeLocalOnly || filesByID[file.id] != nil {
        filesByID[file.id] = file
      }
    }
    return filesByID.values.sorted {
      ($0.name, $0.id) < ($1.name, $1.id)
    }
  }

  private func remoteStoredFile(from snapshot: InstantEntitySnapshot) -> InstantStoredFile? {
    guard
      let name = snapshot.stringValue(for: "path"),
      let urlString = snapshot.stringValue(for: "url"),
      let url = URL(string: urlString)
    else { return nil }
    let unknownTimestamp = InstantTimestamp(milliseconds: 0)
    return InstantStoredFile(
      id: snapshot.id,
      appID: configuration.appID,
      name: name,
      contentType: snapshot.stringValue(for: "content-type"),
      byteCount: 0,
      localPath: "",
      ownerUserID: "",
      createdAt: unknownTimestamp,
      updatedAt: unknownTimestamp,
      remoteURL: url
    )
  }

  func activeStoredFilesObservationCount() async -> Int {
    await storedFilesObservers.activeCount(for: storedFilesObservationKey)
  }

  private func storageRefreshToken(operation: String) async throws -> String {
    guard let refreshToken = try await persistence.loadAuthSession(key: authSessionKey)?
      .refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
      !refreshToken.isEmpty
    else {
      throw InstantError(
        code: .authFailed,
        operation: operation,
        message: "Instant storage requires an authenticated refresh token.",
        recovery: "Sign in before uploading or deleting files."
      )
    }
    return refreshToken
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
      let metadata: InstantStreamMetadata
      if configuration.liveTransport != nil, await liveSession.isOpen {
        let started = try await liveSession.startStream(
          clientID: clientID,
          reconnectToken: configuration.makeID(),
          clientEventID: configuration.makeID()
        )
        guard started.clientID == clientID, started.offset == 0 else {
          throw InstantError(
            code: .decodeFailed,
            operation: "start Instant live stream",
            path: "offset",
            serverEventID: started.clientEventID,
            message:
              "Instant acknowledged client id '\(started.clientID)' at byte offset \(started.offset), expected '\(clientID)' at 0.",
            recovery: "Use a new client id, or reconnect the existing writer with its original token."
          )
        }
        metadata = try await persistence.ensureStreamMetadata(
          appID: configuration.appID,
          streamID: started.streamID,
          clientID: clientID,
          userID: userID,
          createdAt: configuration.now()
        )
      } else {
        metadata = try await persistence.createStream(
          appID: configuration.appID,
          streamID: configuration.makeID(),
          clientID: clientID,
          userID: userID,
          createdAt: configuration.now()
        )
      }
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
      try await liveSession.appendStream(
        streamID: streamID,
        chunks: [content],
        offset: append.offset,
        done: false,
        abortReason: nil,
        clientEventID: configuration.makeID()
      )
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
      try await liveSession.finishStream(
        streamID: streamID,
        offset: metadata.size ?? 0,
        abortReason: normalizedAbortReason,
        clientEventID: configuration.makeID()
      )
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
      let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        streamID: streamID,
        byteOffset: byteOffset
      )
      if read == nil, configuration.liveTransport == nil {
        throw streamNotFound(
          operation: "observe stream content",
          localID: streamID,
          recovery: "Create the stream first, or observe by the matching client id."
        )
      }
      let stream = await streamContentObservers.observe(
        key: streamContentObservationKey(streamID: streamID),
        byteOffset: byteOffset,
        current: read
      )
      await operationGate.leave()
      return await liveStreamContentObservation(
        stream,
        key: "stream-id:\(streamID):\(byteOffset)",
        streamID: streamID,
        initialByteOffset: read.map { $0.byteOffset + $0.byteCount } ?? byteOffset
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
      let read = try await persistence.loadStreamContent(
        appID: configuration.appID,
        clientID: clientID,
        byteOffset: byteOffset
      )
      if read == nil, configuration.liveTransport == nil {
        throw streamNotFound(
          operation: "observe stream content",
          localID: clientID,
          recovery: "Create the stream first, or observe by the persistent stream id."
        )
      }
      let stream = await streamContentObservers.observe(
        key: streamContentObservationKey(clientID: clientID),
        byteOffset: byteOffset,
        current: read
      )
      await operationGate.leave()
      return await liveStreamContentObservation(
        stream,
        key: "client-id:\(clientID):\(byteOffset)",
        clientID: clientID,
        initialByteOffset: read.map { $0.byteOffset + $0.byteCount } ?? byteOffset
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
    var gateIsHeld = true
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "list shares", noun: "Share")
      if let contract = configuration.liveShareContract {
        await operationGate.leave()
        gateIsHeld = false
        return try contract.snapshots(
          appID: configuration.appID,
          roots: try await query(contract.queryPlan)
        )
      }
      let snapshots = try await persistence.loadShareSnapshots(
        appID: configuration.appID,
        userID: userID
      )
      await operationGate.leave()
      return snapshots
    } catch {
      if gateIsHeld { await operationGate.leave() }
      throw error
    }
  }

  public func observeShares() async throws -> AsyncStream<[InstantShareSnapshot]> {
    await operationGate.enter()
    var gateIsHeld = true
    do {
      let userID = try await resolvedAuthenticatedUserID(operation: "observe shares", noun: "Share")
      if let contract = configuration.liveShareContract {
        await operationGate.leave()
        gateIsHeld = false
        let emissions = await observe(contract.queryPlan)
        return liveShareObservation(contract: contract, emissions: emissions)
      }
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
      if gateIsHeld { await operationGate.leave() }
      throw error
    }
  }

  private func liveShareObservation(
    contract: InstantLiveShareContract,
    emissions: AsyncStream<InstantQueryEmission>
  ) -> AsyncStream<[InstantShareSnapshot]> {
    contract.observe(
      appID: configuration.appID,
      emissions: emissions
    ) { [weak self] error in
      await self?.recordConnectionError(error)
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

  public func failedMutations() async -> [PendingMutation] {
    recordActorHop(.outbox)
    return await outbox.all().filter { $0.status == .failed }
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
    let current: InstantMutationLifecycleEvent
    if let mutation = state.snapshot.outbox.first(where: { $0.id == id }) {
      if mutation.status == .failed {
        current = .failed(mutation)
      } else if mutation.status == .confirmed, mutation.provesServerAcceptance {
        current = .serverAccepted(mutation)
      } else {
        current = .waiting
      }
    } else {
      current = .waiting
    }
    return await mutationLifecycleObservers.observe(key: id, current: current)
  }

  public func outboxMutations() async -> [PendingMutation] {
    await outbox.all().filter { $0.status != .confirmed }
  }

  package func mutationDeliveryBarrierMutations() async -> [PendingMutation] {
    await outbox.all()
  }

  func liveMutationReservationCountsForTesting() async -> (
    ids: Int,
    stepCounts: Int,
    deadlines: Int
  ) {
    await liveSession.mutationReservationCountsForTesting()
  }

  public func outboxTransportMutations(includeFailed: Bool = false) async
    -> [InstantTransportMutation]
  {
    let mutations = await outbox.all()
      .filter { mutation in
        switch mutation.status {
        case .pending:
          return true
        case .confirmed:
          return !mutation.provesServerAcceptance
        case .failed:
          return includeFailed
        }
      }
      .sorted(by: PendingMutation.creationOrder)
    let visibleWriteFilter = await store.visibleWriteFilter(
      for: InstantVisibleWriteFilter.writeKeys(in: mutations)
    )
    var laterQueuedWriteKeys: Set<InstantVisibleWriteKey> = []
    var filteredReversed: [PendingMutation] = []
    filteredReversed.reserveCapacity(mutations.count)
    for var mutation in mutations.reversed() {
      let mutationWriteKeys = InstantVisibleWriteFilter.writeKeys(
        in: mutation.transaction.operations
      )
      mutation.transaction.operations = visibleWriteFilter.discardingWritesOlderThanVisibleState(
        mutation.transaction.operations,
        preserving: laterQueuedWriteKeys
      )
      filteredReversed.append(mutation)
      laterQueuedWriteKeys.formUnion(mutationWriteKeys)
    }
    return filteredReversed.reversed().map { mutation in
      var transportMutation = InstantTransportMutation(mutation)
      // A local receipt preserves the existing public `.confirmed` result, but it is still
      // unacknowledged from Instant's perspective and must use the wire-level pending shape.
      if mutation.status == .confirmed, !mutation.provesServerAcceptance {
        transportMutation.status = .pending
      }
      return transportMutation
    }
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
        // Preserve every later optimistic layer while removing a rejected predecessor. Applying
        // confirmations first could remove an accepted successor from the outbox before the
        // predecessor's exact inverse is stripped and replayed over it.
        var terminalFailures: [PendingMutation] = []
        for result in results where result.outcome == .failed {
          recordActorHop(.persistence)
          let latestState = try await persistence.loadState()
          guard latestState.snapshot.outbox.contains(where: {
            $0.id == result.mutationID && $0.status == .pending
          }) else { continue }
          let message =
            result.message ?? "The Instant mutation transport rejected the mutation."
          terminalFailures.append(
            try await performFailMutationWithGateHeld(
              id: result.mutationID,
              failure: InstantMutationFailure(
                code: PendingMutation.failureCode(message: message),
                message: message
              )
            )
          )
        }

        let confirmationResults = results.filter { $0.outcome == .confirmed }
        var confirmedMutations: [PendingMutation] = []
        var didApplyConfirmations = confirmationResults.isEmpty
        if !confirmationResults.isEmpty {
          for _ in 0..<5 {
            recordActorHop(.persistence)
            let latestState = try await persistence.loadState()
            let update = InstantOutbox.applyingTransportResults(
              confirmationResults,
              in: latestState.snapshot.outbox,
              allowedMutationIDs: selectedMutationIDs
            )
            guard !update.confirmed.isEmpty else {
              recordActorHop(.outbox)
              await outbox.replace(with: latestState.snapshot.outbox)
              didApplyConfirmations = true
              break
            }
            recordActorHop(.persistence)
            let didSave = try await persistence.saveOutbox(
              update.mutations,
              expectedOutboxRevision: latestState.outboxRevision
            )
            guard didSave else { continue }
            recordActorHop(.outbox)
            await outbox.replace(with: update.mutations)
            for mutation in update.confirmed {
              await publishMutationLifecycle(mutation)
            }
            confirmedMutations = update.confirmed
            didApplyConfirmations = true
            break
          }
        }
        guard didApplyConfirmations else { throw outboxChangedDuringFlush() }

        let remainingMutations = await outbox.all()
        if terminalFailures.isEmpty,
          !remainingMutations.contains(where: { $0.status == .failed }),
          try await persistedConnectionState() != .closed
        {
          try await saveOpenedConnectionMetadataWithGateHeld()
        }
        _ = try? await publishConnectionStatusWithGateHeld()
        let remainingPendingCount = remainingMutations.filter { $0.status == .pending }.count
        await leaveOperationGate()
        await leaveMutationFlushGate()
        return InstantMutationTransportFlushResult(
          request: request,
          results: results,
          confirmed: confirmedMutations,
          failed: terminalFailures,
          pendingMutationCount: remainingPendingCount,
          mutationCount: remainingMutations.count
        )
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
    try await failMutation(
      id: id,
      failure: InstantMutationFailure(
        code: PendingMutation.failureCode(message: message),
        message: message
      )
    )
  }

  @discardableResult
  package func failMutation(
    id: String,
    failure: InstantMutationFailure,
    recordsConnectionFailure: Bool = true
  ) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      let mutation = try await performFailMutationWithGateHeld(
        id: id,
        failure: failure,
        recordsConnectionFailure: recordsConnectionFailure
      )
      await operationGate.leave()
      return mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func performFailMutationWithGateHeld(
    id: String,
    failure: InstantMutationFailure,
    recordsConnectionFailure: Bool = true
  ) async throws -> PendingMutation {
    for _ in 0..<5 {
      let state = try await persistence.loadState()
      guard let original = state.snapshot.outbox.first(where: { $0.id == id }),
        let update = InstantOutbox.failing(
          id: id,
          failure: failure,
          in: state.snapshot.outbox
        )
      else {
        await outbox.replace(with: state.snapshot.outbox)
        throw outboxMutationNotFound(id: id)
      }
      let removal = try await prepareTerminalFailureRemoval(
        original: original,
        failedMutations: update.mutations,
        snapshot: state.snapshot.store
      )
      let now = configuration.now()
      let metadataEntries =
        recordsConnectionFailure
        ? [
          InstantPersistenceMetadataEntry(
            key: connectionStateMetadataKey,
            value: InstantConnectionState.errored.rawValue,
            updatedAt: now
          ),
          InstantPersistenceMetadataEntry(
            key: connectionLastErrorMetadataKey,
            value: failure.message,
            updatedAt: now
          ),
        ]
        : []
      let nextSnapshot = InstantPersistenceSnapshot(
        store: removal.prepared?.snapshot ?? state.snapshot.store,
        outbox: removal.mutations
      )
      let didSave = try await persistence.saveSnapshot(
        nextSnapshot,
        replacing: state.snapshot,
        metadataEntries: metadataEntries,
        expectedStoreRevision: state.storeRevision,
        expectedOutboxRevision: state.outboxRevision
      )
      if didSave {
        if let prepared = removal.prepared {
          _ = await store.commitAndPublish(prepared)
        }
        await outbox.replace(with: removal.mutations)
        _ = try? await publishConnectionStatusWithGateHeld()
        await publishMutationLifecycle(removal.failedMutation)
        return removal.failedMutation
      }
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  private func prepareTerminalFailureRemoval(
    original: PendingMutation,
    failedMutations: [PendingMutation],
    snapshot: InstantStoreSnapshot
  ) async throws -> (
    prepared: PreparedStoreMutation?,
    mutations: [PendingMutation],
    failedMutation: PendingMutation
  ) {
    guard let failedIndex = failedMutations.firstIndex(where: { $0.id == original.id }) else {
      throw outboxMutationNotFound(id: original.id)
    }
    var mutations = failedMutations
    var failedMutation = mutations[failedIndex]

    // A pre-overlay-state row cannot tell us whether its optimistic writes are still materialized.
    // Preserve both the cache and the durable row until an authoritative recovery path proves the
    // state. A transaction id is correlation, not a safe inverse operation.
    guard original.optimisticOverlayState != nil || original.rollbackTransaction != nil else {
      mutations[failedIndex] = failedMutation
      return (nil, mutations, failedMutation)
    }

    failedMutation.optimisticOverlayState = .removed
    failedMutation.rollbackTransaction = nil
    mutations[failedIndex] = failedMutation
    guard original.optimisticOverlayState != .removed,
      let failedRollback = original.rollbackTransaction
    else {
      return (nil, mutations, failedMutation)
    }

    let successors = mutations.sorted(by: PendingMutation.creationOrder).filter { mutation in
      PendingMutation.creationOrder(original, mutation)
        && mutation.status != .failed
        && mutation.optimisticOverlayState != .removed
    }
    var prepared: PreparedStoreMutation?
    var changedEntityIDs: Set<String> = []

    // Strip successors in reverse so the rejected layer's exact inverse is applied to the state it
    // originally covered. Replaying them below rebuilds each successor inverse over the new base.
    for successor in successors.reversed() {
      guard let rollback = successor.rollbackTransaction else {
        guard successor.optimisticOverlayState != nil else {
          throw unknownOptimisticOverlayState(id: successor.id, operation: "reject mutation")
        }
        continue
      }
      let next = if let prepared {
        try await store.prepare(rollback, applyingTo: prepared)
      } else {
        try await store.prepare(rollback, applyingTo: snapshot)
      }
      changedEntityIDs.formUnion(next.result.changedEntityIDs)
      prepared = next
    }

    let removedFailure = if let prepared {
      try await store.prepare(failedRollback, applyingTo: prepared)
    } else {
      try await store.prepare(failedRollback, applyingTo: snapshot)
    }
    changedEntityIDs.formUnion(removedFailure.result.changedEntityIDs)
    var replayPrepared = removedFailure

    for successor in successors {
      guard let successorIndex = mutations.firstIndex(where: { $0.id == successor.id }) else {
        continue
      }
      var rebasedSuccessor = mutations[successorIndex]
      let newestTimestamp = replayPrepared.indexes.newestTransactionTimeMilliseconds ?? 0
      let optimisticTimestamp = InstantTimestamp(
        milliseconds: newestTimestamp == Int64.max ? newestTimestamp : newestTimestamp + 1
      )
      let operations = rebasedSuccessor.transaction.operations
        .filter(\.isRebasedLocalWrite)
        .map { $0.rebased(at: optimisticTimestamp) }
      rebasedSuccessor.rollbackTransaction = nil
      rebasedSuccessor.optimisticOverlayState = .applied
      if !operations.isEmpty {
        let replay = try await store.prepare(
          InstantStoreTransaction(id: rebasedSuccessor.transaction.id, operations: operations),
          applyingTo: replayPrepared
        )
        changedEntityIDs.formUnion(replay.result.changedEntityIDs)
        rebasedSuccessor.rollbackTransaction = Self.rollbackTransaction(
          mutationID: rebasedSuccessor.id,
          prepared: replay
        )
        replayPrepared = replay
      }
      mutations[successorIndex] = rebasedSuccessor
    }

    return (
      PreparedStoreMutation(
        result: InstantStoreMutationResult(
          transactionID: failedRollback.id,
          changedEntityIDs: changedEntityIDs,
          tripleCount: replayPrepared.indexes.tripleCount,
          emissions: []
        ),
        sequence: replayPrepared.sequence,
        attributes: replayPrepared.attributes,
        indexes: replayPrepared.indexes
      ),
      mutations,
      failedMutation
    )
  }

  /// Removes one server-rejected mutation and its still-visible optimistic writes after its caller
  /// has explicitly handled the failure.
  ///
  /// Instant's TypeScript reactor deletes a rejected mutation in `_handleMutationError` before
  /// rejecting the transaction promise. Instant Swift Data adapts that behavior by retaining a
  /// durable failed row for diagnostics and retry by default, and only deleting it through this
  /// package-scoped acknowledgement boundary after the caller returns `.discard`.
  @discardableResult
  package func discardFailedMutation(
    id: String,
    allowingActiveDisposition: Bool = false
  ) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      let hasActiveRetryReservation = await automaticMutationRetryReservations.contains(id)
      guard allowingActiveDisposition || !hasActiveRetryReservation
      else {
        throw activeMutationDispositionError(
          id: id,
          operation: "discard failed outbox mutation"
        )
      }
      for _ in 0..<5 {
        let state = try await persistence.loadState()
        guard let mutation = state.snapshot.outbox.first(where: { $0.id == id }) else {
          await outbox.replace(with: state.snapshot.outbox)
          throw InstantError(
            code: .validationFailed,
            operation: "discard failed outbox mutation",
            localID: id,
            message: "The failed outbox mutation '\(id)' was not found.",
            recovery: "Inspect the current outbox and discard only a retained failed mutation."
          )
        }
        guard mutation.status == .failed,
          let update = InstantOutbox.discardingFailed(id: id, in: state.snapshot.outbox)
        else {
          await outbox.replace(with: state.snapshot.outbox)
          throw InstantError(
            code: .validationFailed,
            operation: "discard failed outbox mutation",
            localID: id,
            message: "The outbox mutation '\(id)' is \(mutation.status.rawValue), not failed.",
            recovery: "Wait for a server rejection before explicitly discarding the mutation."
          )
        }
        guard mutation.optimisticOverlayState != nil || mutation.rollbackTransaction != nil else {
          await outbox.replace(with: state.snapshot.outbox)
          throw unknownOptimisticOverlayState(
            id: id,
            operation: "discard failed outbox mutation"
          )
        }
        let removal = try await prepareTerminalFailureRemoval(
          original: mutation,
          failedMutations: state.snapshot.outbox,
          snapshot: state.snapshot.store
        )
        let remainingMutations = removal.mutations.filter { $0.id != id }
        let nextSnapshot = InstantPersistenceSnapshot(
          store: removal.prepared?.snapshot ?? state.snapshot.store,
          outbox: remainingMutations
        )
        let didSave = try await persistence.saveSnapshot(
          nextSnapshot,
          replacing: state.snapshot,
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
        if didSave {
          await outbox.replace(with: remainingMutations)
          if let prepared = removal.prepared {
            _ = await store.commitAndPublish(prepared)
          }
          _ = try? await publishConnectionStatusWithGateHeld()
          await operationGate.leave()
          return update.mutation
        }
      }

      throw InstantError(
        code: .persistenceFailed,
        operation: "discard failed outbox mutation",
        localID: id,
        message: "The local outbox changed repeatedly while discarding mutation '\(id)'.",
        recovery: "Retry after inspecting the current outbox."
      )
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  package func withAutomaticMutationRetrySuspended<Result: Sendable>(
    id: String,
    operation: @Sendable () async throws -> Result
  ) async rethrows -> Result {
    await automaticMutationRetryReservations.reserve(id)
    do {
      let result = try await operation()
      await automaticMutationRetryReservations.release(id)
      return result
    } catch {
      await automaticMutationRetryReservations.release(id)
      throw error
    }
  }

  private func performRetryMutationWithGateHeld(
    id: String,
    requiringFailedStatus: Bool = false
  ) async throws -> PendingMutation {
    for _ in 0..<5 {
      recordActorHop(.persistence)
      let state = try await persistence.loadState()
      guard let original = state.snapshot.outbox.first(where: { $0.id == id }),
        let update = InstantOutbox.retrying(id: id, in: state.snapshot.outbox)
      else {
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        throw outboxMutationNotFound(id: id)
      }
      guard !requiringFailedStatus || original.status == .failed else {
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        throw InstantError(
          code: .validationFailed,
          operation: "retry failed outbox mutation",
          localID: id,
          localMutationDisposition: .retainedUnknown,
          message: "The outbox mutation '\(id)' is \(original.status.rawValue), not failed.",
          recovery: "Refresh the failed-mutation list and retry only a retained failed mutation."
        )
      }
      guard original.optimisticOverlayState != nil || original.rollbackTransaction != nil else {
        recordActorHop(.outbox)
        await outbox.replace(with: state.snapshot.outbox)
        throw unknownOptimisticOverlayState(id: id, operation: "retry outbox mutation")
      }

      var retriedMutation = update.mutation
      var retriedMutations = update.mutations
      let shouldReapplyOptimisticOverlay =
        original.optimisticOverlayState == .removed
      let preparedRetry: PreparedStoreMutation?
      if shouldReapplyOptimisticOverlay {
        let newestTimestamp = state.snapshot.store.triples.reduce(Int64.min) { newest, triple in
          max(newest, triple.txTime.milliseconds)
        }
        let optimisticTimestamp = InstantTimestamp(
          milliseconds: newestTimestamp == Int64.max
            ? newestTimestamp
            : max(newestTimestamp, 0) + 1
        )
        let operations = retriedMutation.transaction.operations
          .filter(\.isRebasedLocalWrite)
          .map { $0.rebased(at: optimisticTimestamp) }
        if operations.isEmpty {
          preparedRetry = nil
          retriedMutation.rollbackTransaction = nil
        } else {
          recordActorHop(.store)
          let prepared = try await store.prepare(
            InstantStoreTransaction(id: retriedMutation.transaction.id, operations: operations),
            applyingTo: state.snapshot.store
          )
          preparedRetry = prepared
          retriedMutation.rollbackTransaction = Self.rollbackTransaction(
            mutationID: retriedMutation.id,
            prepared: prepared
          )
        }
        retriedMutation.optimisticOverlayState = .applied
      } else {
        preparedRetry = nil
        if retriedMutation.optimisticOverlayState == nil {
          retriedMutation.optimisticOverlayState = .applied
        }
      }
      guard let retriedIndex = retriedMutations.firstIndex(where: { $0.id == id }) else {
        throw outboxMutationNotFound(id: id)
      }
      retriedMutations[retriedIndex] = retriedMutation
      let shouldClearConnectionFailure: Bool
      if retriedMutations.contains(where: { $0.status == .failed }) {
        shouldClearConnectionFailure = false
      } else {
        shouldClearConnectionFailure = try await persistedConnectionState() != .closed
      }
      let metadataEntries =
        shouldClearConnectionFailure
        ? [
          InstantPersistenceMetadataEntry(
            key: connectionStateMetadataKey,
            value: InstantConnectionState.opened.rawValue,
            updatedAt: configuration.now()
          )
        ]
        : []
      let deletingMetadataKeys =
        shouldClearConnectionFailure
        ? [connectionLastErrorMetadataKey]
        : []

      recordActorHop(.persistence)
      let didSave: Bool
      if let preparedRetry {
        didSave = try await persistence.saveLocalMutation(
          changedEntityTriples: preparedRetry.changedEntityTriples,
          outbox: retriedMutations,
          pendingMutation: retriedMutation,
          metadataEntries: metadataEntries,
          deletingMetadataKeys: deletingMetadataKeys,
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
      } else {
        didSave = try await persistence.saveOutbox(
          retriedMutations,
          metadataEntries: metadataEntries,
          deletingMetadataKeys: deletingMetadataKeys,
          expectedStoreRevision: state.storeRevision,
          expectedOutboxRevision: state.outboxRevision
        )
      }
      guard didSave else { continue }

      if let preparedRetry {
        recordActorHop(.store)
        _ = await store.commitAndPublish(preparedRetry)
      }
      recordActorHop(.outbox)
      await outbox.replace(with: retriedMutations)
      _ = try? await publishConnectionStatusWithGateHeld()
      return retriedMutation
    }

    throw outboxChangedDuringStatusUpdate(id: id)
  }

  @discardableResult
  public func retryMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      guard await !automaticMutationRetryReservations.contains(id) else {
        throw activeMutationDispositionError(
          id: id,
          operation: "retry outbox mutation"
        )
      }
      let mutation = try await performRetryMutationWithGateHeld(id: id)
      await operationGate.leave()
      await sendOutstandingMutationsToLiveSession()
      return mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  @discardableResult
  package func retryFailedMutation(id: String) async throws -> PendingMutation {
    await operationGate.enter()
    do {
      guard await !automaticMutationRetryReservations.contains(id) else {
        throw activeMutationDispositionError(
          id: id,
          operation: "retry failed outbox mutation"
        )
      }
      let mutation = try await performRetryMutationWithGateHeld(
        id: id,
        requiringFailedStatus: true
      )
      await operationGate.leave()
      await sendOutstandingMutationsToLiveSession()
      return mutation
    } catch {
      await operationGate.leave()
      throw error
    }
  }

  private func activeMutationDispositionError(
    id: String,
    operation: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: operation,
      localID: id,
      localMutationDisposition: .retainedForRetry,
      message: "The outbox mutation '\(id)' is awaiting a server-rejection disposition.",
      recovery: "Wait for the rejection handler to retain or discard the failed mutation."
    )
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
      try await persistAuthSessionWithGateHeld(session)
      await operationGate.leave()
      recordPersistedAuthSession(session)
    } catch {
      await operationGate.leave()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "auth",
        event: "auth-session.persistence-failed",
        message: "Failed to persist an Instant auth session.",
        metadata: [
          "appID": session.appID,
          "userID": session.userID,
          "isGuest": String(session.isGuest),
        ]
      )
      throw error
    }
    await reconnectAfterAuthChangeIfNeeded()
    _ = try? await syncUserCookieToEndpoint(session)
  }

  private func persistAuthSessionWithGateHeld(_ session: InstantAuthSession) async throws {
    try await persistence.saveAuthSession(session, key: authSessionKey)
    await authSessionObservers.yield(session)
    _ = try? await publishConnectionStatusWithGateHeld()
  }

  private func recordPersistedAuthSession(_ session: InstantAuthSession) {
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "auth",
      event: "auth-session.persisted",
      message: "Persisted and published an Instant auth session.",
      metadata: [
        "appID": session.appID,
        "userID": session.userID,
        "isGuest": String(session.isGuest),
        "hasRefreshToken": String(session.refreshToken?.isEmpty == false),
      ]
    )
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

  private func unknownOptimisticOverlayState(id: String, operation: String) -> InstantError {
    InstantError(
      code: .persistenceFailed,
      operation: operation,
      localID: id,
      localMutationDisposition: .retainedUnknown,
      message:
        "Mutation '\(id)' predates durable optimistic-overlay metadata, so its local cache effect is unknown.",
      recovery:
        "Retain the mutation and run an authoritative recovery that explicitly verifies the server effect before retrying or discarding it."
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
    let activeLocalMembers = await activeRoomPresenceState.activeMembers(
      localMembers,
      in: room
    )
    let currentSessionID = await liveSession.currentSessionID
    let remoteMembers = await liveRoomPresenceState.current(
      room: room,
      excludingSessionID: currentSessionID,
      appID: configuration.appID,
      updatedAt: configuration.now()
    )
    return mergedRoomPresence(local: activeLocalMembers, remote: remoteMembers)
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
    InstantStreamContentObservationKey(
      appID: configuration.appID,
      selector: .streamID(streamID)
    )
  }

  private func streamContentObservationKey(clientID: String) -> InstantStreamContentObservationKey {
    InstantStreamContentObservationKey(
      appID: configuration.appID,
      selector: .clientID(clientID)
    )
  }

  private func sharesObservationKey(userID: String) -> InstantSharesObservationKey {
    InstantSharesObservationKey(appID: configuration.appID, userID: userID)
  }

  private func publishStreamContentUpdates(streamID: String) async throws {
    guard let metadata = try await persistence.loadStreamMetadata(
      appID: configuration.appID,
      streamID: streamID
    ) else { return }
    let keys = [
      streamContentObservationKey(streamID: streamID),
      streamContentObservationKey(clientID: metadata.clientID),
    ]
    for key in keys {
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

  /// `operation` defaults to the caller's own function so a stalled gate names
  /// the function that is actually holding it rather than this wrapper.
  private func enterOperationGate(operation: String = #function) async {
    recordActorHop(.operationGate)
    await operationGate.enter(operation: operation)
  }

  /// Cancellation-aware variant for callers that already throw. A caller that
  /// throws here never acquired the gate and must not leave it.
  private func enterOperationGateUnlessCancelled(operation: String = #function) async throws {
    recordActorHop(.operationGate)
    try await operationGate.enterUnlessCancelled(operation: operation)
  }

  private func leaveOperationGate() async {
    recordActorHop(.operationGate)
    await operationGate.leave()
  }

  private func enterMutationFlushGate(operation: String = #function) async {
    recordActorHop(.mutationFlushGate)
    await mutationFlushGate.enter(operation: operation)
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

private extension InstantEntitySnapshot {
  func stringValue(for field: String) -> String? {
    guard case let .string(value) = values[field]?.first else { return nil }
    return value
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

  func rebased(at timestamp: InstantTimestamp) -> Self {
    switch self {
    case var .merge(triple):
      triple.txTime = timestamp
      return .merge(triple)

    case let .mergeByLookup(entity, attributeID, value, txID, _):
      return .mergeByLookup(
        entity: entity,
        attributeID: attributeID,
        value: value,
        txID: txID,
        txTime: timestamp
      )

    case var .insert(triple):
      triple.txTime = timestamp
      return .insert(triple)

    case let .insertByLookup(entity, attributeID, value, txID, _):
      return .insertByLookup(
        entity: entity,
        attributeID: attributeID,
        value: value,
        txID: txID,
        txTime: timestamp
      )

    case var .retract(triple):
      triple.txTime = timestamp
      return .retract(triple)

    case let .retractByLookup(entity, attributeID, value, txID, _):
      return .retractByLookup(
        entity: entity,
        attributeID: attributeID,
        value: value,
        txID: txID,
        txTime: timestamp
      )

    case .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup:
      return self

    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .ruleParams, .ruleParamsByLookup:
      return self
    }
  }
}

struct InstantVisibleWriteKey: Hashable, Sendable {
  var entityID: String
  var attributeID: String
}

private struct InstantAuthoritativeWriteCoverage: Sendable {
  private var replacementKeys: Set<InstantVisibleWriteKey> = []
  private var exactValues: Set<InstantAuthoritativeWriteValue> = []
  private var exactMergeValues: Set<InstantAuthoritativeWriteValue> = []
  private var fullyCoveredEntityIDs: Set<String> = []
  private var coveredNamespaces: Set<InstantAuthoritativeEntityNamespace> = []
  private var attributes: AttributeStore

  init(
    operations: [InstantTripleOperation],
    attributes: AttributeStore,
    previousChangedEntityTriples: [String: [InstantTriple]],
    changedEntityTriples: [String: [InstantTriple]]
  ) {
    self.attributes = attributes
    let previousValues = Set(
      previousChangedEntityTriples.values.lazy.flatMap { triples in
        triples.lazy.map {
          let key = InstantVisibleWriteKey(entityID: $0.entityID, attributeID: $0.attributeID)
          return InstantAuthoritativeWriteValue(key: key, value: $0.value)
        }
      }
    )
    let changedKeys = Set(
      changedEntityTriples.values.lazy.flatMap { triples in
        triples.lazy.map {
          InstantVisibleWriteKey(entityID: $0.entityID, attributeID: $0.attributeID)
        }
      }
    )
    for operation in operations {
      switch operation {
      case let .insert(triple):
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        replacementKeys.insert(key)
        exactValues.insert(InstantAuthoritativeWriteValue(key: key, value: triple.value))
      case let .retract(triple):
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        // Upstream retracts an exact EAV value, even for cardinality-one attributes. Treat
        // it as whole-slot replacement evidence only when this authoritative transition
        // actually removed that exact value and left the entity/attribute key absent.
        let value = InstantAuthoritativeWriteValue(key: key, value: triple.value)
        if attributes[triple.attributeID]?.cardinality == .one,
          previousValues.contains(value),
          !changedKeys.contains(key)
        {
          replacementKeys.insert(key)
        }
        exactValues.insert(value)
      case let .merge(triple):
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        exactMergeValues.insert(InstantAuthoritativeWriteValue(key: key, value: triple.value))
      case let .deleteEntity(entityID):
        fullyCoveredEntityIDs.insert(entityID)
      case let .deleteEntityInNamespace(entityID, namespace):
        coveredNamespaces.insert(
          InstantAuthoritativeEntityNamespace(entityID: entityID, namespace: namespace)
        )
      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists,
        .insertByLookup, .mergeByLookup, .retractByLookup,
        .deleteEntityByLookup,
        .ruleParams, .ruleParamsByLookup:
        break
      }
    }
  }

  func covers(_ operations: [InstantTripleOperation]) -> Bool {
    var hasMaterializedWrite = false
    for operation in operations {
      switch operation {
      case let .insert(triple), let .retract(triple):
        hasMaterializedWrite = true
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        let namespaceIsCovered = attributes[triple.attributeID].map {
          coveredNamespaces.contains(
            InstantAuthoritativeEntityNamespace(
              entityID: triple.entityID,
              namespace: $0.namespace
            )
          )
        } ?? false
        let isCovered: Bool
        if fullyCoveredEntityIDs.contains(triple.entityID) || namespaceIsCovered {
          isCovered = true
        } else if attributes[triple.attributeID]?.cardinality == .one {
          isCovered = replacementKeys.contains(key)
            || exactValues.contains(
              InstantAuthoritativeWriteValue(key: key, value: triple.value)
            )
        } else {
          isCovered = exactValues.contains(
            InstantAuthoritativeWriteValue(key: key, value: triple.value)
          )
        }
        guard isCovered else {
          return false
        }
      case let .merge(triple):
        hasMaterializedWrite = true
        let key = InstantVisibleWriteKey(
          entityID: triple.entityID,
          attributeID: triple.attributeID
        )
        let namespaceIsCovered = attributes[triple.attributeID].map {
          coveredNamespaces.contains(
            InstantAuthoritativeEntityNamespace(
              entityID: triple.entityID,
              namespace: $0.namespace
            )
          )
        } ?? false
        let exactMerge = InstantAuthoritativeWriteValue(key: key, value: triple.value)
        guard fullyCoveredEntityIDs.contains(triple.entityID)
          || namespaceIsCovered
          || (attributes[triple.attributeID]?.cardinality == .one
            && replacementKeys.contains(key))
          || exactMergeValues.contains(exactMerge)
        else { return false }
      case let .deleteEntity(entityID):
        hasMaterializedWrite = true
        guard fullyCoveredEntityIDs.contains(entityID) else { return false }
      case let .deleteEntityInNamespace(entityID, namespace):
        hasMaterializedWrite = true
        guard fullyCoveredEntityIDs.contains(entityID)
          || coveredNamespaces.contains(
            InstantAuthoritativeEntityNamespace(entityID: entityID, namespace: namespace)
          )
        else { return false }
      case .insertByLookup, .mergeByLookup, .retractByLookup, .deleteEntityByLookup:
        // The authoritative payload is lowered to concrete entity ids. Without resolving the
        // lookup against that exact payload, coverage cannot be proven, so retain the receipt.
        return false
      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists,
        .ruleParams, .ruleParamsByLookup:
        break
      }
    }
    return hasMaterializedWrite
  }
}

private struct InstantAuthoritativeWriteValue: Hashable, Sendable {
  var key: InstantVisibleWriteKey
  var value: InstantValue
}

private struct InstantAuthoritativeEntityNamespace: Hashable, Sendable {
  var entityID: String
  var namespace: String
}

struct InstantVisibleWriteFilter: Sendable {
  private var attributesByID: [String: InstantAttribute]
  private var newestVisibleWrite: [InstantVisibleWriteKey: InstantTimestamp]

  init(
    attributesByID: [String: InstantAttribute],
    newestVisibleWrite: [InstantVisibleWriteKey: InstantTimestamp]
  ) {
    self.attributesByID = attributesByID
    self.newestVisibleWrite = newestVisibleWrite
  }

  static func writeKeys(in mutations: [PendingMutation]) -> Set<InstantVisibleWriteKey> {
    writeKeys(in: mutations.flatMap(\.transaction.operations))
  }

  static func writeKeys(
    in operations: [InstantTripleOperation]
  ) -> Set<InstantVisibleWriteKey> {
    Set(
      operations.compactMap { operation in
        switch operation {
        case let .insert(triple), let .merge(triple):
          return InstantVisibleWriteKey(
            entityID: triple.entityID,
            attributeID: triple.attributeID
          )
        case .requireEntityMissing, .requireEntityMissingByLookup,
          .requireEntityExists, .requireEntityExistsByLookup,
          .requireTripleExists,
          .insertByLookup, .mergeByLookup,
          .retract, .retractByLookup,
          .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
          .ruleParams, .ruleParamsByLookup:
          return nil
        }
      }
    )
  }

  func discardingWritesOlderThanVisibleState(
    _ operations: [InstantTripleOperation],
    preserving queuedSuccessorWriteKeys: Set<InstantVisibleWriteKey> = []
  ) -> [InstantTripleOperation] {
    return operations.filter { operation in
      let triple: InstantTriple
      switch operation {
      case .insert(let value), .merge(let value):
        triple = value

      case .requireEntityMissing, .requireEntityMissingByLookup,
        .requireEntityExists, .requireEntityExistsByLookup,
        .requireTripleExists,
        .insertByLookup, .mergeByLookup,
        .retract, .retractByLookup,
        .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
        .ruleParams, .ruleParamsByLookup:
        return true
      }

      guard let attribute = attributesByID[triple.attributeID],
        attribute.cardinality == .one,
        !attribute.primaryKey
      else { return true }
      let key = InstantVisibleWriteKey(
        entityID: triple.entityID,
        attributeID: triple.attributeID
      )
      if queuedSuccessorWriteKeys.contains(key) { return true }
      guard let visibleWrite = newestVisibleWrite[key] else { return true }
      return visibleWrite <= triple.txTime
    }
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
