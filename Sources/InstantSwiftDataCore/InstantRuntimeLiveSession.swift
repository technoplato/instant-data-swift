import Foundation
import IssueReporting

package struct InstantSupersededLiveSessionSend: Error, Sendable {}

/// The exact current receiver owns this send failure's status and reconnect.
///
/// The originating operation still fails with the same description, but
/// Runtime must not persist the caller's delayed copy after a newer connection
/// generation has closed or opened.
package struct InstantReceiverOwnedLiveSessionSendFailure:
  Error,
  Sendable,
  CustomStringConvertible
{
  package let description: String

  package init(_ error: Error) {
    self.description = String(describing: error)
  }
}


package struct InstantLiveMutationEncodingFailure: Sendable {
  var message: String
  var mutationID: String
}

package actor InstantRuntimeLiveSession {
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

  private struct ReceiverFailure {
    var error: Error
    var generation: Int
    var sessionIdentity: UUID
  }

  private struct SendGeneration: Hashable {
    var generation: Int
    var sessionIdentity: UUID
  }

  private var session: InstantLiveWebSocketSession?
  private let receiverTaskOwner = InstantRuntimeExactTaskOwner()
  private var registeredQueries: [String: RegisteredQuery] = [:]
  private var serverAttributes: [InstantLiveJSONValue] = []
  private var inFlightMutationIDs: Set<String> = []
  private var inFlightMutationStepCounts: [String: Int] = [:]
  /// When each in-flight mutation send began, so an
  /// unacknowledged mutation is retried instead of blocking its queue forever.
  private var inFlightMutationDeadlines: [String: Date] = [:]
  /// Mutation IDs offered on this socket generation, retained after a response
  /// is decoded until Runtime finishes its durable acknowledgement transition.
  private var offeredMutationIDsInCurrentGeneration: Set<String> = []
  private var acknowledgementUnknownMutationIDs: Set<String> = []
  private var hasReportedDeepOutbox = false
  /// Bounds the number of transactions sharing the socket at once.
  static let maximumMutationsPerFlush = InstantAutomaticOutboxClaimLimits.maximumMutationCount
  /// Bounds the low-level transaction work sharing the socket at once. One
  /// oversize mutation is still allowed through when the window is empty so
  /// an old large write cannot permanently block ordered delivery.
  static let maximumTransactionStepsInFlight = InstantAutomaticOutboxClaimLimits.maximumStepCount
  /// Hard bound for encoded durable JSON retained by one automatic claim.
  /// Oversized bodies are moved to durable quarantine by SQLite without first
  /// loading their raw string into Swift memory.
  static let maximumEncodedMutationBytesPerDeliveryWindow =
    InstantAutomaticOutboxClaimLimits.maximumEncodedBodyBytes
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
  private var receiverFailure: ReceiverFailure?
  private var inFlightSendCounts: [SendGeneration: Int] = [:]
  private var sendCompletionWaiters:
    [SendGeneration: [CheckedContinuation<Void, Never>]] = [:]

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
        timeoutMilliseconds: instantLiveOperationTimeoutMilliseconds
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
        timeoutMilliseconds: instantLiveOperationTimeoutMilliseconds
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
    receiverFailure = nil
    let replacedReceiver = receiverTaskOwner.requestStop()
    let replacedSession = session
    session = nil
    sessionID = nil
    serverAttributes = []
    inFlightMutationIDs.removeAll()
    inFlightMutationStepCounts.removeAll()
    inFlightMutationDeadlines.removeAll()
    offeredMutationIDsInCurrentGeneration.removeAll()
    acknowledgementUnknownMutationIDs.removeAll()
    for room in Array(registeredRooms.keys) {
      registeredRooms[room]?.isConnected = false
    }
    isOpened = false
    if let replacedSession {
      await closeGracefully(
        replacedSession,
        operation: "replace Instant live session"
      )
    }
    // Replacement owns the complete old receive-loop tail, including event
    // handling, receiverEnded, and its failure callback. Waiting here cannot
    // deadlock the actor: actor isolation is reentrant while the task value is
    // suspended, and the generation mismatch makes the old tail inert.
    await replacedReceiver.wait()
    receiverTaskOwner.resume()
    let opened = try await transport.connectSession(
      request,
      operation: "connect Instant live transport"
    )
    do {
      try await instantLiveWithTimeout(
        operation: "open Instant live session",
        timeoutMilliseconds: instantLiveOperationTimeoutMilliseconds,
        onAbandon: { opened.abort() }
      ) {
        try await opened.send(request.initMessage(clientEventID: makeID()))
      }
      let event = try await instantLiveWithTimeout(
        operation: "open Instant live session",
        timeoutMilliseconds: instantLiveOperationTimeoutMilliseconds,
        onAbandon: { opened.abort() }
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
        try await reconcileQueryMembership(
          key: key,
          fallbackQuery: registration.query,
          initialClientEventID: makeID()
        )
      }
      for key in registeredStreamReaders.keys.sorted() {
        guard let registration = registeredStreamReaders[key] else { continue }
        try await registration.reader.reconnect(clientEventID: makeID()) { message in
          try await self.send(message, through: opened)
        }
      }
    } catch {
      opened.abort()
      if session?.identity == opened.identity {
        session = nil
        sessionID = nil
        serverAttributes = []
        isOpened = false
      }
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
    onEventAcquired: (@Sendable () async -> Void)? = nil,
    onFailure: @escaping @Sendable (Error) async -> Void
  ) async throws {
    guard receiverTaskOwner.isIdle else { return }
    guard let session, isOpened else {
      throw Self.receiverStartFailure()
    }
    let generation = generation
    let sendGeneration = SendGeneration(
      generation: generation,
      sessionIdentity: session.identity
    )
    while inFlightSendCounts[sendGeneration, default: 0] > 0 {
      await withCheckedContinuation { continuation in
        sendCompletionWaiters[sendGeneration, default: []].append(continuation)
      }
    }
    guard
      receiverTaskOwner.isIdle,
      generation == self.generation,
      self.session?.identity == session.identity,
      isOpened
    else {
      throw Self.receiverStartFailure()
    }
    if let pendingFailure = takeReceiverFailure(
      generation: generation,
      session: session
    ) {
      _ = invalidateSessionIfCurrent(session, failure: pendingFailure)
      throw pendingFailure
    }
    _ = receiverTaskOwner.start { [weak self] in
      do {
        while !Task.isCancelled {
          let message = try await session.receive()
          try Task.checkCancellation()
          let event = InstantLiveServerEvent(message: message)
          guard await self?.canDeliverReceiverEvent(
            generation: generation,
            session: session
          ) == true else {
            return
          }
          guard let attributes = try await self?.record(event, generation: generation) else {
            return
          }
          await onEventAcquired?()
          try Task.checkCancellation()
          guard await self?.canDeliverReceiverEvent(
            generation: generation,
            session: session
          ) == true else {
            return
          }
          try await onEvent(event, attributes)
          await self?.finishDeliveringMutationResponse(event, generation: generation)
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
      guard requiresServerAcknowledgement else { return }
      // Upstream queryOnce always sends add-query, even when this exact query is
      // already subscribed. Instant answers with add-query-exists, which gives
      // the one-shot operation a fresh server acknowledgement while retaining
      // the materialized query store.
      try await reconcileQueryMembership(
        key: key,
        fallbackQuery: query,
        initialClientEventID: clientEventID
      )
      return
    }
    registeredQueries[key] = RegisteredQuery(query: query, observerCount: 1)
    try await reconcileQueryMembership(
      key: key,
      fallbackQuery: query,
      initialClientEventID: clientEventID
    )
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
    try await reconcileQueryMembership(
      key: key,
      fallbackQuery: registration.query,
      initialClientEventID: clientEventID
    )
    return registeredQueries[key] == nil
  }

  /// Reconciles the server's query membership after an actor-reentrant send.
  ///
  /// A query can be removed and equivalently re-added while the old
  /// `remove-query` is suspended in the transport. The command that finishes
  /// last must compensate itself so the final wire state matches the current
  /// local observer membership.
  private func reconcileQueryMembership(
    key: String,
    fallbackQuery: InstantLiveJSONValue,
    initialClientEventID: String
  ) async throws {
    var query = fallbackQuery
    var clientEventID = initialClientEventID

    while let currentSession = session, isOpened {
      let shouldBeRegistered: Bool
      let message: InstantLiveMessage
      if let registration = registeredQueries[key] {
        shouldBeRegistered = true
        query = registration.query
        message = .addQuery(query, clientEventID: clientEventID)
      } else {
        shouldBeRegistered = false
        message = .removeQuery(query, clientEventID: clientEventID)
      }

      do {
        try await send(message, through: currentSession)
      } catch is InstantSupersededLiveSessionSend {
        guard registeredQueries[key] != nil else { return }
        clientEventID = makeID?() ?? UUID().uuidString.lowercased()
        continue
      }

      let sessionIsCurrent = session?.identity == currentSession.identity && isOpened
      let isRegistered = registeredQueries[key] != nil
      if sessionIsCurrent {
        guard isRegistered != shouldBeRegistered else { return }
      } else {
        guard session != nil, isOpened, isRegistered else { return }
      }
      clientEventID = makeID?() ?? UUID().uuidString.lowercased()
    }
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

  func releaseMutationReservations(
    _ mutationIDs: Set<String>,
    timedOut: Bool
  ) {
    guard !mutationIDs.isEmpty else { return }
    let currentGenerationTimeouts = timedOut
      ? mutationIDs.intersection(offeredMutationIDsInCurrentGeneration)
      : []
    for mutationID in mutationIDs {
      inFlightMutationIDs.remove(mutationID)
      inFlightMutationStepCounts[mutationID] = nil
      inFlightMutationDeadlines[mutationID] = nil
    }
    guard timedOut else { return }
    acknowledgementUnknownMutationIDs.formUnion(currentGenerationTimeouts)
    if !currentGenerationTimeouts.isEmpty, let session {
      generation += 1
      session.abort()
    }
    InstantDiagnostics.shared.record(
      .warning,
      subsystem: "instant-swift-data-core",
      category: "outbox",
      event: "outbox.mutation.ack-timeout-batch",
      message: "Instant reclaimed durable delivery claims after no server acknowledgement.",
      metadata: [
        "expiredCount": String(mutationIDs.count),
        "currentGenerationExpiredCount": String(currentGenerationTimeouts.count),
        "acknowledgementBaseIntervalSeconds": String(
          InstantMutationAcknowledgementDeadlinePolicy.baseIntervalMilliseconds / 1_000
        ),
        "expiredMutationIDs": mutationIDs.sorted().prefix(12).joined(separator: ","),
      ]
    )
    guard !currentGenerationTimeouts.isEmpty else { return }
    reportIssue(
      """
      Instant did not acknowledge \(currentGenerationTimeouts.count) mutation(s) before their ordinal deadlines. The live session is being replaced before retry.

      If this repeats, inspect the Instant WebSocket endpoint and server response.
      """
    )
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
      guard mutations.isEmpty else {
        throw InstantError(
          code: .networkFailed,
          operation: "send claimed Instant live mutations",
          message: "The live session closed after SQLite claimed mutations but before they could be sent.",
          recovery: "Release the failed session's durable claims, reconnect, and resend them immediately."
        )
      }
      return []
    }
    if let acknowledgementUnknownMutationID = acknowledgementUnknownMutationIDs.min() {
      session.abort()
      throw InstantError(
        code: .networkFailed,
        operation: "retry acknowledgement-unknown Instant mutation",
        serverEventID: acknowledgementUnknownMutationID,
        message:
          "The prior live generation ended without proving whether this mutation was accepted.",
        recovery:
          "Replace the live session before retrying the same durable client event id."
      )
    }
    var encodingFailures: [InstantLiveMutationEncodingFailure] = []
    let pending = mutations
      .sorted(by: Self.mutationOrder)
      .filter { $0.status == .pending }
    reportDeepOutboxIfNeeded(pendingCount: pending.count)
    var sentCount = 0
    var skippedAlreadyInFlight = 0
    var stoppedForMutationBudget = false
    var stoppedForStepBudget = false
    var nextAcknowledgementOrdinal = inFlightMutationIDs.count + 1
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
      // Preserve outbox order. Admission has already rejected or quarantined
      // any mutation above the hard limit, so this branch only waits for room
      // behind an existing in-flight window.
      if !fitsStepBudget {
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
        InstantMutationAcknowledgementDeadlinePolicy.deadline(
          after: Date(),
          inFlightOrdinal: nextAcknowledgementOrdinal
        )
      offeredMutationIDsInCurrentGeneration.insert(mutation.mutationID)
      let acknowledgementTimeoutMilliseconds =
        InstantMutationAcknowledgementDeadlinePolicy.timeoutMilliseconds(
          inFlightOrdinal: nextAcknowledgementOrdinal
        )
      nextAcknowledgementOrdinal += 1
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
            "ackTimeoutMilliseconds": String(acknowledgementTimeoutMilliseconds),
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
    if let firstEncodingFailure = encodingFailures.first {
      let exampleMutationIDs = encodingFailures.prefix(8).map(\.mutationID).joined(
        separator: ", "
      )
      reportIssue(
        """
        Instant quarantined \(encodingFailures.count) mutation\(encodingFailures.count == 1 ? "" : "s") that cannot be delivered against the current server schema.

        First failure: \(firstEncodingFailure.message)
        Example mutation IDs: \(exampleMutationIDs)
        Deploy the schema (npx instant-cli push schema) so the missing attributes \
        exist on the server, then retry the quarantined mutations.
        """
      )
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

  private func finishDeliveringMutationResponse(
    _ event: InstantLiveServerEvent,
    generation: Int
  ) {
    guard generation == self.generation else { return }
    switch event {
    case let .transactOK(transactOK):
      if let clientEventID = transactOK.clientEventID {
        offeredMutationIDsInCurrentGeneration.remove(clientEventID)
      }
    case let .error(error):
      if let clientEventID = error.clientEventID {
        offeredMutationIDsInCurrentGeneration.remove(clientEventID)
      }
    default:
      break
    }
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
    if let failure = retainedReceiverFailure(for: session) {
      throw InstantReceiverOwnedLiveSessionSendFailure(failure)
    }
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
    let sendGeneration = beginSend(through: session)
    defer { finishSend(sendGeneration) }
    do {
      try await instantLiveWithTimeout(
        operation: "send Instant live session message",
        timeoutMilliseconds: instantLiveOperationTimeoutMilliseconds
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
      let currentSessionOwnsFailure = retainFailureForCurrentSession(error, from: session)
      session.abort()
      guard currentSessionOwnsFailure || invalidateSessionIfCurrent(session, failure: error) else {
        InstantDiagnostics.shared.record(
          .debug,
          subsystem: "instant-swift-data-core",
          category: "transport",
          event: "websocket.message-send-superseded",
          message: "Ignored a send failure from an Instant WebSocket session that was already replaced.",
          metadata: ["op": message.op],
          correlationID: message.clientEventID
        )
        throw InstantSupersededLiveSessionSend()
      }
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "transport",
        event: "websocket.message-send-failed",
        message: "Failed to send an Instant WebSocket message.",
        metadata: ["op": message.op],
        correlationID: message.clientEventID
      )
      if currentSessionOwnsFailure {
        throw InstantReceiverOwnedLiveSessionSendFailure(error)
      }
      throw error
    }
  }

  private func closeGracefully(
    _ session: InstantLiveWebSocketSession,
    operation: String
  ) async {
    do {
      try await session.closeGracefully(operation: operation)
    } catch {
      session.abort()
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "transport",
        event: "websocket.session-close-failed",
        message: "Instant could not gracefully close the live session within 5 seconds.",
        metadata: ["operation": operation]
      )
    }
  }

  private func invalidateSessionIfCurrent(
    _ failedSession: InstantLiveWebSocketSession,
    failure: Error
  ) -> Bool {
    guard session?.identity == failedSession.identity else { return false }
    generation += 1
    receiverFailure = nil
    _ = receiverTaskOwner.requestStop()
    session = nil
    sessionID = nil
    serverAttributes = []
    isOpened = false
    for room in Array(registeredRooms.keys) {
      registeredRooms[room]?.isConnected = false
    }
    for continuation in pendingStreamStarts.values {
      continuation.finish(throwing: failure)
    }
    pendingStreamStarts.removeAll()
    for continuation in pendingStreamFlushes.values {
      continuation.finish(throwing: failure)
    }
    pendingStreamFlushes.removeAll()
    return true
  }

  /// Retains a current send failure before aborting its wire.
  ///
  /// An installed receive loop consumes the failure and remains the one
  /// Runtime reconnect callback. During the low-level-open/receiver-start gap,
  /// `startReceiving` consumes and throws the same failure before Runtime can
  /// publish a false opened state.
  private func retainFailureForCurrentSession(
    _ error: Error,
    from failedSession: InstantLiveWebSocketSession
  ) -> Bool {
    guard
      session?.identity == failedSession.identity,
      isOpened
    else { return false }
    if receiverFailure == nil {
      receiverFailure = ReceiverFailure(
        error: error,
        generation: generation,
        sessionIdentity: failedSession.identity
      )
    }
    return true
  }

  /// A retained failure remains receiver-owned until that exact receive loop
  /// consumes it. Retry callers must not reach the failed generation's wire.
  private func retainedReceiverFailure(
    for session: InstantLiveWebSocketSession
  ) -> Error? {
    guard let receiverFailure,
      isOpened,
      self.session?.identity == session.identity,
      receiverFailure.generation == generation,
      receiverFailure.sessionIdentity == session.identity
    else { return nil }
    return receiverFailure.error
  }

  private func takeReceiverFailure(
    generation: Int,
    session: InstantLiveWebSocketSession
  ) -> Error? {
    guard let receiverFailure,
      receiverFailure.generation == generation,
      receiverFailure.sessionIdentity == session.identity
    else { return nil }
    self.receiverFailure = nil
    return receiverFailure.error
  }

  private func beginSend(
    through session: InstantLiveWebSocketSession
  ) -> SendGeneration {
    let sendGeneration = SendGeneration(
      generation: generation,
      sessionIdentity: session.identity
    )
    inFlightSendCounts[sendGeneration, default: 0] += 1
    return sendGeneration
  }

  private func finishSend(_ sendGeneration: SendGeneration) {
    guard let count = inFlightSendCounts[sendGeneration] else { return }
    guard count == 1 else {
      inFlightSendCounts[sendGeneration] = count - 1
      return
    }
    inFlightSendCounts[sendGeneration] = nil
    let waiters = sendCompletionWaiters.removeValue(forKey: sendGeneration) ?? []
    for waiter in waiters {
      waiter.resume()
    }
  }

  private static func receiverStartFailure() -> InstantError {
    InstantError(
      code: .networkFailed,
      operation: "start receiving Instant live session",
      message: "The Instant live session ended before its receive loop could start.",
      recovery: "Reconnect before reporting the session as opened."
    )
  }

  private func canDeliverReceiverEvent(
    generation: Int,
    session: InstantLiveWebSocketSession
  ) -> Bool {
    generation == self.generation
      && self.session?.identity == session.identity
      && isOpened
  }

  private func receiverEnded(
    generation: Int,
    session: InstantLiveWebSocketSession,
    failure: Error?,
    onFailure: @escaping @Sendable (Error) async -> Void
  ) async {
    guard generation == self.generation else { return }
    let terminalFailure = takeReceiverFailure(generation: generation, session: session)
      ?? failure
      // Upstream's WebSocket `onclose` always schedules reconnect. A custom
      // Swift transport can express the same unexpected current close as
      // `CancellationError`, so preserve that outcome instead of treating it
      // like an explicit generation-changing close.
      ?? InstantError(
        code: .networkFailed,
        operation: "receive Instant live session message",
        message:
          "The current Instant live receive loop ended unexpectedly without an explicit close or replacement.",
        recovery: "Reconnect and reinstall the current live subscriptions."
      )
    self.session = nil
    sessionID = nil
    isOpened = false
    for room in Array(registeredRooms.keys) {
      registeredRooms[room]?.isConnected = false
    }
    await closeGracefully(session, operation: "close ended Instant live session")
    // Explicit close or replacement can interleave while graceful close is
    // suspended. In that case the newer generation owns continuations and the
    // reconnect decision; this old task must only finish its exact handle.
    guard generation == self.generation, !Task.isCancelled else { return }
    for continuation in pendingStreamStarts.values {
      continuation.finish(throwing: terminalFailure)
    }
    pendingStreamStarts.removeAll()
    for continuation in pendingStreamFlushes.values {
      continuation.finish(throwing: terminalFailure)
    }
    pendingStreamFlushes.removeAll()
    await onFailure(terminalFailure)
  }

  func beginClose() async -> InstantRuntimeExactTaskOwner.Handle {
    generation += 1
    receiverFailure = nil
    let session = session
    let receiverTask = receiverTaskOwner.requestStop()
    self.session = nil
    sessionID = nil
    serverAttributes = []
    inFlightMutationIDs.removeAll()
    inFlightMutationStepCounts.removeAll()
    inFlightMutationDeadlines.removeAll()
    offeredMutationIDsInCurrentGeneration.removeAll()
    acknowledgementUnknownMutationIDs.removeAll()
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
    if let session {
      await closeGracefully(session, operation: "close Instant live session")
    }
    return receiverTask
  }

  func close() async {
    let receiverTask = await beginClose()
    await receiverTask.wait()
  }

  func receiverTaskIsIdleForTesting() -> Bool {
    receiverTaskOwner.isIdle
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
