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

/// The frames one live generation's reader has received and its applier has not taken yet (#296).
///
/// URLSession answers the server's pings only while a `receive()` is outstanding, and the server closes a client
/// that sends nothing, not even a pong, for its idle timeout (about 20-30 s, measured on Instant's hosted server
/// through the throwaway app bd40c50a; see `InstantURLSessionKeepaliveLiveTests`). So one task reads and another
/// applies: the reader keeps a `receive()` outstanding while the applier is inside a long frame. Frames leave in
/// arrival order. The reader's terminal error leaves only after every frame received before it, the order upstream's
/// `onmessage` and `onclose` events have.
///
/// When `capacity` frames are waiting, the reader waits for the applier, as the single receive loop always did. That
/// bounds memory when an applier is stuck, and only then can the socket stop answering pings.
// SAFETY: `lock` protects every mutable field. Continuations are taken under the lock and resumed after it.
final class InstantLiveReceivedFrames: @unchecked Sendable {
  private typealias Applier = CheckedContinuation<InstantLiveMessage, any Error>
  private typealias Reader = CheckedContinuation<Bool, Never>

  private enum Offer {
    case refused
    case buffered
    case handed(Applier)
    case full
  }

  private let lock = NSLock()
  private let capacity: Int
  private var frames: [InstantLiveMessage] = []
  private var terminalError: (any Error)?
  private var isClosed = false
  private var waitingApplier: Applier?
  private var applierCancelledBeforeWaiting = false
  private var waitingReader: (continuation: Reader, frame: InstantLiveMessage)?
  private var readerCancelledBeforeWaiting = false

  init(capacity: Int) {
    precondition(capacity > 0, "A live receive buffer needs room for at least one frame.")
    self.capacity = capacity
  }

  var bufferedCountForTesting: Int {
    lock.withLock { frames.count }
  }

  var readerIsWaitingForTesting: Bool {
    lock.withLock { waitingReader != nil }
  }

  var applierIsWaitingForTesting: Bool {
    lock.withLock { waitingApplier != nil }
  }

  /// Hands one received frame to the applier. Returns `false` once the applier has stopped, and then the reader
  /// stops too. Waits while `capacity` frames are already waiting.
  func append(_ frame: InstantLiveMessage) async -> Bool {
    switch lock.withLock({ offerLocked(frame) }) {
    case .refused:
      return false
    case .buffered:
      return true
    case let .handed(applier):
      applier.resume(returning: frame)
      return true
    case .full:
      break
    }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: Reader) in
        let offer = lock.withLock { () -> Offer in
          guard !readerCancelledBeforeWaiting else { return .refused }
          let offer = offerLocked(frame)
          if case .full = offer {
            waitingReader = (continuation, frame)
          }
          return offer
        }
        switch offer {
        case .refused:
          continuation.resume(returning: false)
        case .buffered:
          continuation.resume(returning: true)
        case let .handed(applier):
          applier.resume(returning: frame)
          continuation.resume(returning: true)
        case .full:
          break
        }
      }
    } onCancel: {
      let reader = lock.withLock { () -> Reader? in
        guard let waiting = waitingReader else {
          readerCancelledBeforeWaiting = true
          return nil
        }
        waitingReader = nil
        return waiting.continuation
      }
      reader?.resume(returning: false)
    }
  }

  /// Records the reader's terminal error. The applier receives it after every frame received before it.
  func finish(throwing error: any Error) {
    let applier = lock.withLock { () -> Applier? in
      guard !isClosed, terminalError == nil else { return nil }
      terminalError = error
      // An applier waits only when no frame is waiting, so nothing is skipped.
      defer { waitingApplier = nil }
      return waitingApplier
    }
    applier?.resume(throwing: error)
  }

  /// The next frame in arrival order. After the last frame it throws the reader's terminal error. After `close()`
  /// or cancellation it throws `CancellationError`.
  func next() async throws -> InstantLiveMessage {
    try Task.checkCancellation()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: Applier) in
        let taken = lock.withLock { () -> (Result<InstantLiveMessage, any Error>, Reader?)? in
          if let taken = takeFrameLocked() {
            return (.success(taken.frame), taken.reader)
          }
          if let terminalError {
            return (.failure(terminalError), nil)
          }
          if isClosed || applierCancelledBeforeWaiting {
            return (.failure(CancellationError()), nil)
          }
          waitingApplier = continuation
          return nil
        }
        if let taken {
          taken.1?.resume(returning: true)
          continuation.resume(with: taken.0)
        }
      }
    } onCancel: {
      let applier = lock.withLock { () -> Applier? in
        guard let waiting = waitingApplier else {
          applierCancelledBeforeWaiting = true
          return nil
        }
        waitingApplier = nil
        return waiting
      }
      applier?.resume(throwing: CancellationError())
    }
  }

  /// Drops every waiting frame and stops the reader. The applier calls this when it stops.
  func close() {
    let waiting = lock.withLock { () -> (Applier?, Reader?) in
      isClosed = true
      frames.removeAll()
      defer {
        waitingApplier = nil
        waitingReader = nil
      }
      return (waitingApplier, waitingReader?.continuation)
    }
    waiting.0?.resume(throwing: CancellationError())
    waiting.1?.resume(returning: false)
  }

  private func offerLocked(_ frame: InstantLiveMessage) -> Offer {
    if isClosed || terminalError != nil {
      return .refused
    }
    if let applier = waitingApplier {
      waitingApplier = nil
      return .handed(applier)
    }
    guard frames.count < capacity else { return .full }
    frames.append(frame)
    return .buffered
  }

  /// Takes the oldest frame. A reader waiting on a full buffer moves its frame in behind the others.
  private func takeFrameLocked() -> (frame: InstantLiveMessage, reader: Reader?)? {
    guard !frames.isEmpty else { return nil }
    let frame = frames.removeFirst()
    guard let reader = waitingReader else { return (frame, nil) }
    waitingReader = nil
    frames.append(reader.frame)
    return (frame, reader.continuation)
  }
}

/// A stream this device writes, restarted on the current connection (#329).
struct InstantStreamWriterRestart: Sendable {
  var serverStreamID: String
  /// The bytes the server already holds; the writer resends from here.
  var serverOffset: Int64
  var generation: Int
}

/// How a writer's catch-up ended.
enum InstantStreamWriterCatchUpEnd: Sendable {
  /// The runtime appended past what the catch-up sent; send the rest from SQLite, then end again.
  case appendedMore
  /// The writer is live; appends go straight to the socket.
  case live
  /// The writer is live and its terminal append went out; the server confirms it with a `stream-flushed`.
  case closing(AsyncThrowingStream<InstantLiveStreamFlushed, Error>)
}

extension InstantLiveMessage {
  /// The server frames that belong to a room: join and leave answers, presence, and broadcasts. The receiver applies
  /// them beside the query applier rather than behind it (#461).
  static let roomFrameOps: Set<String> = [
    "join-room-ok", "leave-room-ok", "join-room-error", "refresh-presence", "patch-presence", "server-broadcast",
    "set-presence-ok", "client-broadcast-ok",
  ]

  var isRoomFrame: Bool { Self.roomFrameOps.contains(op) }
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
    /// The runtime's sequence number of `presence`, so a publication that reaches this actor after a newer one never
    /// replaces it here or on the wire (#461).
    var presenceSequence: UInt64 = 0
    var queuedBroadcasts: [QueuedBroadcast] = []
    var isConnected = false
  }

  private struct RegisteredStreamReader: Sendable {
    var reader: InstantLiveStreamReaderState
    /// The observations sharing this reader. It unsubscribes when the last one ends; naming them, not counting them,
    /// keeps an observation that ended after its reader was retired from ending a newer reader of the same key.
    var observationIDs: Set<UUID>
  }

  /// A stream this device writes, as the server knows it on this connection (#329).
  ///
  /// The content and the close are durable in SQLite before they reach here, so the writer holds no buffer: a
  /// restart resends from SQLite what the server has not flushed (upstream `Stream.ts` keeps that buffer in memory).
  private struct RegisteredStreamWriter: Sendable {
    /// The id `createStream` returned on this device; the runtime names the stream by it.
    var localStreamID: String
    /// The id from `start-stream-ok`; `append-stream` names the stream by it.
    var serverStreamID: String
    /// The connection generation on which the server has every byte the runtime appended, so appends and the close
    /// go straight to the socket. Until then they wait for the writer's catch-up, as upstream's write stream holds
    /// writes while `disconnected`.
    var liveGeneration: Int?
    /// The end of what the runtime appended while the writer was not live; the catch-up sends at least this far.
    var appendedEnd: Int64 = 0
    /// A close the runtime made while the writer was not live; the catch-up sends it after the content.
    var pendingClose: PendingStreamClose?
    /// The generation on which the terminal append went out, so it goes out once per connection.
    var closeSentGeneration: Int?
  }

  private struct PendingStreamClose: Sendable {
    var abortReason: String?
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
  /// Consecutive transient server errors of each live query, and its pending re-send on this socket (#360).
  private var queryResendAttempts: [String: Int] = [:]
  private var queryResends: [String: (id: UUID, task: Task<Void, Never>)] = [:]
  /// The socket generation on which the server last answered each registered query (add-query-ok or
  /// add-query-exists), cleared by a server error for it (library-78, item 7). While a query is answered on the open
  /// socket, the store holds the server's result for it and every refresh since.
  private var answeredQueryGenerations: [String: Int] = [:]
  private var serverAttributes: [InstantLiveJSONValue] = []
  private var inFlightMutationIDs: Set<String> = []
  private var inFlightMutationStepCounts: [String: Int] = [:]
  /// When each in-flight mutation send began, so an
  /// unacknowledged mutation is retried instead of blocking its queue forever.
  private var inFlightMutationDeadlines: [String: Date] = [:]
  /// Mutation IDs offered on this socket generation, retained after a response
  /// is decoded until Runtime finishes its durable acknowledgement transition.
  private var offeredMutationIDsInCurrentGeneration: Set<String> = []
  /// Exact SQLite claim token whose payload was offered for each mutation on
  /// this socket generation. A response captures it before any Runtime
  /// suspension so a late frame cannot authorize a newer same-id claim.
  private var offeredMutationClaimTokensInCurrentGeneration: [String: String] = [:]
  private var acknowledgementUnknownMutationIDs: Set<String> = []
  /// The server frame this generation's applier is applying, from the moment it took the frame from the reader until
  /// the runtime has handled it (#296). While it is set, this socket has proved the server is answering, and an
  /// acknowledgement queued behind it is not late. See `frameBeingApplied()`.
  private var frameBeingAppliedState: (generation: Int, sequence: UInt64, op: String)?
  private var nextFrameSequence: UInt64 = 0
  /// How many received frames may wait for the applier (#296). The server answers each in-flight mutation (at most
  /// `maximumMutationsPerFlush`, 50) with one frame and each registered query with one `add-query-ok`. While it
  /// recomputes, it combines queued refreshes into one (`combine [:refresh :refresh]`, upstream
  /// `server/src/instant/reactive/session.clj`). One long apply therefore has about 70 frames behind it in a
  /// Scribe-sized session. 128 leaves room for that. A full buffer makes the reader wait: the old behaviour, so only a
  /// stuck applier can cost the socket.
  static let maximumBufferedReceivedFrames = 128
  /// The current generation's receive buffer. Only tests read it, to wait until the applier has applied every frame
  /// the reader took (`applierIsWaitingForAFrameForTesting()`).
  private var receivedFrames: InstantLiveReceivedFrames?
  /// Mutation IDs an earlier connection offered and never answered (#296). A server refusal of one of these is a
  /// replay: the earlier offer may have been applied, so the refusal alone does not prove the write was lost. Only
  /// used to classify refusals in diagnostics; bounded because it outlives generations.
  private var offeredWithoutAnswerOnEarlierConnections: Set<String> = []
  /// Mutation IDs whose offer the server answered with a transient error (#376). Like an unanswered offer, the
  /// server may have applied it; only used to classify a later refusal as a replay.
  private var offersAnsweredInconclusively: Set<String> = []
  private static let maximumRememberedUnansweredOffers = 4_096
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
  /// Presence the runtime published in a room it has not joined yet, for the join to carry (#461).
  private var presenceBeforeJoin: [InstantRoomHandle: (values: [String: JSONValue]?, sequence: UInt64)] = [:]
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
        // A stream created online: the server's id is its local id, and there is nothing to catch up.
        registeredStreamWriters[started.streamID] = RegisteredStreamWriter(
          localStreamID: started.streamID,
          serverStreamID: started.streamID,
          liveGeneration: generation
        )
      }
      return started
    } catch {
      pendingStreamStarts[clientEventID]?.finish(throwing: error)
      pendingStreamStarts[clientEventID] = nil
      throw error
    }
  }

  /// Sends a live writer's append. A writer that is not live on this connection only notes how far the runtime
  /// appended; the content is durable, and the writer's catch-up sends it (#329).
  func appendStream(
    streamID localStreamID: String,
    chunks: [String],
    offset: Int64,
    clientEventID: String
  ) async throws {
    guard var writer = registeredStreamWriters[localStreamID] else { return }
    guard let session, isOpened, writer.liveGeneration == generation else {
      let end = offset + chunks.reduce(Int64(0)) { $0 + Int64($1.utf8.count) }
      writer.appendedEnd = max(writer.appendedEnd, end)
      registeredStreamWriters[localStreamID] = writer
      return
    }
    try await send(
      .appendStream(
        streamID: writer.serverStreamID,
        chunks: chunks,
        offset: offset,
        done: false,
        clientEventID: clientEventID
      ),
      through: session
    )
  }

  /// Sends a live writer's close and waits for the server's terminal flush; `true` once the server confirmed it.
  ///
  /// Returns `false` without waiting when the writer is not live on this connection, or its catch-up already sent
  /// the close: the close is durable, and the catch-up sends it once the server has every byte, as upstream's
  /// `close()` appends `done` only once the stream id is known (#329).
  func finishStream(
    streamID localStreamID: String,
    offset: Int64,
    abortReason: String?,
    clientEventID: String
  ) async throws -> Bool {
    guard var writer = registeredStreamWriters[localStreamID] else { return false }
    guard let session, isOpened, writer.liveGeneration == generation else {
      writer.pendingClose = PendingStreamClose(abortReason: abortReason)
      registeredStreamWriters[localStreamID] = writer
      return false
    }
    guard writer.closeSentGeneration != generation else { return false }
    writer.closeSentGeneration = generation
    registeredStreamWriters[localStreamID] = writer
    let serverStreamID = writer.serverStreamID
    let response = AsyncThrowingStream<InstantLiveStreamFlushed, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    pendingStreamFlushes[serverStreamID] = response.continuation
    do {
      try await send(
        .appendStream(
          streamID: serverStreamID,
          chunks: [],
          offset: offset,
          done: true,
          abortReason: abortReason,
          clientEventID: clientEventID
        ),
        through: session
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
      pendingStreamFlushes[serverStreamID] = nil
      return true
    } catch {
      pendingStreamFlushes[serverStreamID]?.finish(throwing: error)
      pendingStreamFlushes[serverStreamID] = nil
      throw error
    }
  }

  /// Restarts a stream this device writes on this connection, as upstream's write stream `start` and
  /// `onConnectionReconnect` send `start-stream` with the writer's client id and reconnect token (#329).
  ///
  /// Returns the server's id and the byte offset it already holds; the writer then catches up on this generation.
  /// `nil` when the writer is already live on this connection.
  func restartStreamWriter(
    localStreamID: String,
    clientID: String,
    reconnectToken: String,
    clientEventID: String
  ) async throws -> InstantStreamWriterRestart? {
    let generation = generation
    guard registeredStreamWriters[localStreamID]?.liveGeneration != generation else { return nil }
    let started = try await startStream(
      clientID: clientID,
      reconnectToken: reconnectToken,
      clientEventID: clientEventID,
      registersWriter: false
    )
    guard generation == self.generation, isOpened else { throw InstantSupersededLiveSessionSend() }
    var writer = registeredStreamWriters[localStreamID]
      ?? RegisteredStreamWriter(localStreamID: localStreamID, serverStreamID: started.streamID)
    writer.serverStreamID = started.streamID
    writer.liveGeneration = nil
    registeredStreamWriters[localStreamID] = writer
    return InstantStreamWriterRestart(
      serverStreamID: started.streamID,
      serverOffset: started.offset,
      generation: generation
    )
  }

  /// Sends one stored chunk of a writer that is catching up on `generation`.
  func sendStreamWriterCatchUp(
    localStreamID: String,
    content: String,
    offset: Int64,
    generation: Int,
    clientEventID: String
  ) async throws {
    guard generation == self.generation, let session, isOpened,
      let writer = registeredStreamWriters[localStreamID], writer.liveGeneration == nil
    else {
      throw InstantSupersededLiveSessionSend()
    }
    try await send(
      .appendStream(
        streamID: writer.serverStreamID,
        chunks: [content],
        offset: offset,
        done: false,
        clientEventID: clientEventID
      ),
      through: session
    )
  }

  /// Takes the writers of `serverStreamID` off the live path after the server refused or could not flush one of
  /// their appends, as upstream `Stream.ts` `onAppendFailed` calls `onDisconnect` before it restarts the write stream
  /// on the same socket. Their appends then wait in SQLite for the writer's catch-up, a close already sent goes out
  /// again after the content, and a close waiting for the server's flush fails now instead of at its timeout.
  ///
  /// Returns whether a writer this device holds owns `serverStreamID`.
  func markStreamWriterBehind(serverStreamID: String, reason: String) -> Bool {
    var owned = false
    for (localStreamID, var writer) in registeredStreamWriters where writer.serverStreamID == serverStreamID {
      writer.liveGeneration = nil
      writer.closeSentGeneration = nil
      registeredStreamWriters[localStreamID] = writer
      owned = true
    }
    guard owned else { return false }
    if let flushes = pendingStreamFlushes.removeValue(forKey: serverStreamID) {
      flushes.finish(
        throwing: InstantError(
          code: .networkFailed,
          operation: "finish Instant live stream",
          message: "Instant could not take the appends of stream '\(serverStreamID)': \(reason)",
          recovery: "The close is stored on this device; the stream's writer restarts on this connection and sends it again."
        )
      )
    }
    return true
  }

  /// Ends a writer's catch-up once it sent everything through `offset`, unless the runtime appended past it
  /// meanwhile. The writer is then live; if the stream is closed, its terminal append goes out, and the caller waits
  /// on the returned flushes for the server's confirmation.
  func endStreamWriterCatchUp(
    localStreamID: String,
    through offset: Int64,
    closedLocally: Bool,
    abortReason: String?,
    generation: Int,
    clientEventID: String
  ) async throws -> InstantStreamWriterCatchUpEnd {
    guard generation == self.generation, let session, isOpened,
      var writer = registeredStreamWriters[localStreamID], writer.liveGeneration == nil
    else {
      throw InstantSupersededLiveSessionSend()
    }
    guard writer.appendedEnd <= offset else { return .appendedMore }
    let close = writer.pendingClose ?? (closedLocally ? PendingStreamClose(abortReason: abortReason) : nil)
    writer.liveGeneration = generation
    writer.pendingClose = nil
    guard let close, writer.closeSentGeneration != generation else {
      registeredStreamWriters[localStreamID] = writer
      return .live
    }
    writer.closeSentGeneration = generation
    registeredStreamWriters[localStreamID] = writer
    let response = AsyncThrowingStream<InstantLiveStreamFlushed, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    pendingStreamFlushes[writer.serverStreamID] = response.continuation
    try await send(
      .appendStream(
        streamID: writer.serverStreamID,
        chunks: [],
        offset: offset,
        done: true,
        abortReason: close.abortReason,
        clientEventID: clientEventID
      ),
      through: session
    )
    return .closing(response.stream)
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
    // The new session's init sends every registered query, so a re-send waiting on the old socket is moot (#360).
    cancelQueryResends()
    let replacedReceiver = receiverTaskOwner.requestStop()
    let replacedSession = session
    session = nil
    sessionID = nil
    serverAttributes = []
    inFlightMutationIDs.removeAll()
    inFlightMutationStepCounts.removeAll()
    inFlightMutationDeadlines.removeAll()
    rememberUnansweredOffersOfEndingGeneration()
    offeredMutationIDsInCurrentGeneration.removeAll()
    offeredMutationClaimTokensInCurrentGeneration.removeAll()
    acknowledgementUnknownMutationIDs.removeAll()
    frameBeingAppliedState = nil
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
      [InstantLiveJSONValue],
      String?
    ) async throws -> Void,
    onEventAcquired: (@Sendable () async -> Void)? = nil,
    onRoomEvent: @escaping @Sendable (
      InstantLiveServerEvent,
      InstantRoomHandle,
      String?
    ) async -> Void = { _, _, _ in },
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
    // Upstream `Reactor.js` applies each frame synchronously in `_handleReceive`, and a browser answers the server's
    // pings below JavaScript, so a long frame never silences its socket. URLSession answers pings only while a
    // `receive()` is outstanding, and the server closes a client that sends nothing for about 20-30 s. So this
    // receiver has a reader, which keeps a `receive()` outstanding, and one applier, which applies the frames one at
    // a time in arrival order with the checks the single receive loop had (#296). Both belong to this generation's
    // task: replacement and close cancel and wait for both, and the buffer dies with them.
    //
    // Room frames (presence, broadcasts, join and leave answers) skip the applier's queue: the reader hands them to a
    // third task that applies them in arrival order, so a presence patch never waits behind a query apply, as
    // `Reactor.js` handles every frame in `_handleReceive` as it arrives (#461). The reader still awaits nothing but
    // `receive()`.
    let frames = InstantLiveReceivedFrames(capacity: Self.maximumBufferedReceivedFrames)
    receivedFrames = frames
    let (roomFrames, roomFrameInbox) = AsyncStream.makeStream(
      of: InstantLiveMessage.self,
      bufferingPolicy: .unbounded
    )
    _ = receiverTaskOwner.start { [weak self] in
      await withTaskGroup(of: Void.self) { group in
        group.addTask { [weak self] in
          for await message in roomFrames {
            guard !Task.isCancelled else { return }
            await self?.applyRoomFrame(
              message,
              generation: generation,
              session: session,
              onRoomEvent: onRoomEvent
            )
          }
        }
        group.addTask {
          do {
            while !Task.isCancelled {
              let message = try await session.receive()
              if message.isRoomFrame {
                roomFrameInbox.yield(message)
                continue
              }
              guard await frames.append(message) else { return }
            }
          } catch {
            frames.finish(throwing: error)
          }
        }
        do {
          while !Task.isCancelled {
            let message = try await frames.next()
            try Task.checkCancellation()
            let event = InstantLiveServerEvent(message: message)
            guard
              try await self?.applierMayApplyNextFrame(
                generation: generation,
                session: session
              ) == true
            else {
              break
            }
            guard
              let recorded = try await self?.record(
                event,
                generation: generation,
                onEventAcquired: onEventAcquired
              )
            else {
              break
            }
            try Task.checkCancellation()
            guard await self?.canDeliverReceiverEvent(
              generation: generation,
              session: session
            ) == true else {
              break
            }
            try await onEvent(
              event,
              recorded.attributes,
              recorded.mutationClaimToken
            )
            await self?.finishDeliveringMutationResponse(
              event,
              generation: generation,
              claimToken: recorded.mutationClaimToken
            )
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
        // The reader stops with the applier. Every path that stops the applier has already closed or aborted this
        // socket, or is about to; aborting it here as well guarantees the reader's outstanding `receive()` returns.
        frames.close()
        roomFrameInbox.finish()
        session.abort()
        group.cancelAll()
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
    forgetQueryResend(key: key)
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
    forgetQueryResend(key: key)
    return registeredQueries.removeValue(forKey: key) != nil
  }

  /// Sends the live query `key` again on this socket after a transient server error, once `delayMilliseconds` of its
  /// consecutive failures has passed (#360).
  ///
  /// Upstream `Reactor.js` leaves a failed query for `_flushPendingMessages` on the next `init-ok`, which needs a
  /// reconnect; a healthy socket never makes one, so the query went silent. The re-send is dropped if the socket is
  /// replaced first (the next `init` sends every registered query) or the query is unregistered.
  ///
  /// - Returns: The attempt number and the delay, or `nil` when the query is not registered on an open socket.
  func scheduleQueryResend(
    key: String,
    delayMilliseconds: @Sendable (Int) -> UInt64,
    sleep: @escaping @Sendable (UInt64) async throws -> Void
  ) -> (attempt: Int, delayMilliseconds: UInt64)? {
    guard registeredQueries[key] != nil, isOpened, session != nil else { return nil }
    let attempt = queryResendAttempts[key, default: 0] + 1
    queryResendAttempts[key] = attempt
    let delay = delayMilliseconds(attempt)
    let generation = generation
    let id = UUID()
    queryResends[key]?.task.cancel()
    let task = Task { [weak self] in
      do {
        try await sleep(delay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await self?.resendQuery(key: key, id: id, generation: generation)
    }
    queryResends[key] = (id, task)
    return (attempt, delay)
  }

  /// The server answered the live query `key`, so its backoff starts over.
  func recordQueryAnswered(key: String) {
    queryResendAttempts[key] = nil
    queryResends.removeValue(forKey: key)?.task.cancel()
    if registeredQueries[key] != nil, isOpened {
      answeredQueryGenerations[key] = generation
    }
  }

  /// The server failed the live query `key`: until it answers again, its result on the device may be behind.
  func recordQueryFailed(key: String) {
    answeredQueryGenerations[key] = nil
  }

  /// Whether a registered query was answered by the server on the socket that is open now and has not failed since
  /// (library-78, item 7). Upstream `Reactor.js` `queryOnce` asks the server even then and resolves on
  /// add-query-exists with the same local result, a round trip that Scribe's backlog of server frames made take 5 s and
  /// more.
  func isAnsweredOnCurrentSocket(key: String) -> Bool {
    isOpened && registeredQueries[key] != nil && answeredQueryGenerations[key] == generation
  }

  func pendingQueryResendCountForTesting() -> Int {
    queryResends.count
  }

  private func resendQuery(key: String, id: UUID, generation: Int) async {
    guard queryResends[key]?.id == id else { return }
    queryResends[key] = nil
    guard generation == self.generation, isOpened, let registration = registeredQueries[key] else { return }
    InstantDiagnostics.shared.record(
      .info,
      subsystem: "instant-swift-data-core",
      category: "query",
      event: "query.live-resent",
      message: "Sent a live query again on the open socket after a transient server error.",
      metadata: [
        "registrationKey": key,
        "attempt": String(queryResendAttempts[key, default: 0]),
      ]
    )
    do {
      try await reconcileQueryMembership(
        key: key,
        fallbackQuery: registration.query,
        initialClientEventID: makeID?() ?? UUID().uuidString.lowercased()
      )
    } catch {
      // A send fails only on a dead socket; its receiver reports that failure, and the reconnect's init sends the
      // query again.
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "query",
        event: "query.live-resend-failed",
        message: "Could not send a live query again; the next connection sends it.",
        metadata: ["registrationKey": key]
      )
    }
  }

  private func forgetQueryResend(key: String) {
    queryResendAttempts[key] = nil
    queryResends.removeValue(forKey: key)?.task.cancel()
    answeredQueryGenerations[key] = nil
  }

  private func cancelQueryResends() {
    for resend in queryResends.values {
      resend.task.cancel()
    }
    queryResends.removeAll()
  }

  func activeQueryKeys() -> Set<String> {
    Set(registeredQueries.keys)
  }

  /// The server frame the current generation's applier is still applying, if any (#296).
  ///
  /// A frame counts from the moment the applier took it until the runtime finished handling it. Upstream
  /// `Reactor.js` handles each frame synchronously (`_handleReceive`), so a mutation timer cannot fire while a frame
  /// is being handled; the runtime defers durable acknowledgement deadlines while this returns a frame to keep that
  /// outcome. `sequence` identifies one frame, so the runtime can bound how long it defers for any single frame.
  func frameBeingApplied() -> (sequence: UInt64, op: String)? {
    // An applier that stops early for a replaced or closed session leaves its frame behind; only an open
    // session's current frame counts.
    guard let frame = frameBeingAppliedState, frame.generation == generation, isOpened else { return nil }
    return (frame.sequence, frame.op)
  }

  /// Whether an earlier connection offered this mutation and never delivered an answer for it (#296).
  func wasOfferedWithoutAnswerOnAnEarlierConnection(_ mutationID: String) -> Bool {
    offeredWithoutAnswerOnEarlierConnections.contains(mutationID)
  }

  /// Records that the server answered an offer of this mutation with a transient error, such as a stalled server's
  /// 500 `operation-timed-out` (#376). The server may still have applied that offer, so a later refusal of the same
  /// mutation is a replay, as for an offer a dead connection never answered.
  func recordInconclusiveAnswer(to mutationID: String) {
    offersAnsweredInconclusively.insert(mutationID)
    if offersAnsweredInconclusively.count > Self.maximumRememberedUnansweredOffers {
      offersAnsweredInconclusively = Set(
        offersAnsweredInconclusively.sorted().prefix(Self.maximumRememberedUnansweredOffers)
      )
    }
  }

  /// Whether an earlier offer of this mutation may have been applied without this runtime learning so: a connection
  /// ended before answering it, or the server answered it with a transient error (#296, #376).
  func mayHaveAppliedAnEarlierOffer(of mutationID: String) -> Bool {
    offeredWithoutAnswerOnEarlierConnections.contains(mutationID)
      || offersAnsweredInconclusively.contains(mutationID)
  }

  /// Forgets a mutation's earlier offers once the server has given it a final answer.
  func forgetEarlierOffers(of mutationID: String) {
    offeredWithoutAnswerOnEarlierConnections.remove(mutationID)
    offersAnsweredInconclusively.remove(mutationID)
  }

  private func rememberUnansweredOffersOfEndingGeneration() {
    offeredWithoutAnswerOnEarlierConnections.formUnion(offeredMutationIDsInCurrentGeneration)
    if offeredWithoutAnswerOnEarlierConnections.count > Self.maximumRememberedUnansweredOffers {
      offeredWithoutAnswerOnEarlierConnections = Set(
        offeredWithoutAnswerOnEarlierConnections.sorted()
          .prefix(Self.maximumRememberedUnansweredOffers)
      )
    }
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
      offeredMutationClaimTokensInCurrentGeneration[mutationID] = nil
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
    observationID: UUID,
    clientID: String? = nil,
    streamID: String? = nil,
    initialByteOffset: Int64,
    ruleParams: InstantLiveJSONValue? = nil,
    clientEventID: String
  ) async throws {
    if var registration = registeredStreamReaders[key] {
      registration.observationIDs.insert(observationID)
      registeredStreamReaders[key] = registration
      return
    }
    let reader = try InstantLiveStreamReaderState(
      clientID: clientID,
      streamID: streamID,
      initialByteOffset: initialByteOffset,
      ruleParams: ruleParams
    )
    registeredStreamReaders[key] = RegisteredStreamReader(reader: reader, observationIDs: [observationID])
    guard let session, isOpened else { return }
    let message = try await reader.subscribeMessage(clientEventID: clientEventID)
    // Record the event id before sending, as upstream `Stream.ts` `startReadStream` registers the iterator before
    // `trySend`: a refusal can arrive while this actor waits for the send, and must find its reader.
    await reader.recordSubscriptionEventID(clientEventID)
    try await send(message, through: session)
  }

  func unregisterStreamReader(key: String, observationID: UUID, clientEventID: String) async throws {
    guard var registration = registeredStreamReaders[key],
      registration.observationIDs.remove(observationID) != nil
    else {
      return
    }
    guard registration.observationIDs.isEmpty else {
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

  /// Deletes the reader whose subscription delivered the stream's end, and returns its key; `nil` when no reader owns
  /// `clientEventID`.
  ///
  /// Upstream `Stream.ts` `onStreamAppend` deletes the reader at done, so no reconnect subscribes it again, and it
  /// sends no `unsubscribe-stream` for it: for a stream already done when subscribed, the server registered no reader
  /// and refuses one (`session.clj` `handle-subscribe-stream!` and `handle-unsubscribe-stream!`).
  func retireFinishedStreamReader(clientEventID: String?) async -> String? {
    guard let clientEventID else { return nil }
    for key in registeredStreamReaders.keys.sorted() {
      guard let registration = registeredStreamReaders[key],
        await registration.reader.subscriptionEventID == clientEventID
      else {
        continue
      }
      registeredStreamReaders[key] = nil
      return key
    }
    return nil
  }

  /// Retires the reader whose subscription the server refused, and returns its registration key so the runtime can end
  /// the observations behind it; `nil` when no reader owns `clientEventID`.
  func retireRejectedStreamReader(
    clientEventID: String?,
    message: String
  ) async -> String? {
    guard let clientEventID else { return nil }
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
      return key
    }
    return nil
  }

  @discardableResult
  func sendMutations(
    _ mutations: [InstantTransportMutation],
    claimToken: String?
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
      if let claimToken {
        offeredMutationClaimTokensInCurrentGeneration[mutation.mutationID] = claimToken
      }
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
        offeredMutationClaimTokensInCurrentGeneration[mutation.mutationID] = nil
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

  /// Registers one holder of `room`; the first sends `join-room`, carrying the presence the runtime published before
  /// the join, as `Reactor.js` sends `initialPresence` with `join-room` and again on `join-room-ok` (#461).
  func joinRoom(
    _ room: InstantRoomHandle,
    clientEventID: String
  ) async throws {
    if var registration = registeredRooms[room] {
      registration.observerCount += 1
      registeredRooms[room] = registration
      return
    }
    let early = presenceBeforeJoin.removeValue(forKey: room)
    registeredRooms[room] = RegisteredRoom(
      room: room,
      observerCount: 1,
      presence: early?.values,
      presenceSequence: early?.sequence ?? 0
    )
    guard let session, isOpened else { return }
    try await send(.joinRoom(room, presence: early?.values, clientEventID: clientEventID), through: session)
  }

  /// Whether the server confirmed the join of `room` on the current connection: `join-room-ok`, or a presence frame or
  /// broadcast for it, since the socket opened. `Reactor.js` reports the same flag as `isLoading: !room.isConnected`.
  func isRoomJoined(_ room: InstantRoomHandle) -> Bool {
    isOpened && registeredRooms[room]?.isConnected == true
  }

  /// Releases one holder of `room`. Returns whether that was the last holder, so the room was left: only then does the
  /// runtime forget the room's presence, as `Reactor.js` deletes `_presence[roomId]` only in `_cleanupRoom` (#461).
  @discardableResult
  func leaveRoom(
    _ room: InstantRoomHandle,
    clientEventID: String
  ) async throws -> Bool {
    guard var registration = registeredRooms[room] else { return false }
    if registration.observerCount > 1 {
      registration.observerCount -= 1
      registeredRooms[room] = registration
      return false
    }
    registeredRooms[room] = nil
    guard let session, isOpened else { return true }
    try await send(.leaveRoom(room, clientEventID: clientEventID), through: session)
    return true
  }

  /// Records the presence the runtime's session carries in `room` as publication `sequence`, `nil` once it published
  /// none, and sends it once the room is joined: `nil` goes out as `{}`, so peers stop seeing what was withdrawn, and a
  /// rejoin carries nothing. Before the room is joined it waits for `joinRoom`. A publication older than the one
  /// already recorded is dropped: two publishes that race to this actor must leave the newer on the wire (#461).
  func setPresence(
    room: InstantRoomHandle,
    values: [String: JSONValue]?,
    sequence: UInt64,
    clientEventID: String
  ) async throws {
    guard var registration = registeredRooms[room] else {
      if sequence > presenceBeforeJoin[room]?.sequence ?? 0 {
        presenceBeforeJoin[room] = (values, sequence)
      }
      return
    }
    guard sequence > registration.presenceSequence else { return }
    registration.presence = values
    registration.presenceSequence = sequence
    registeredRooms[room] = registration
    guard registration.isConnected, let session, isOpened else { return }
    try await send(
      .setPresence(room: room, values: values ?? [:], clientEventID: clientEventID),
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

  private func record(
    _ event: InstantLiveServerEvent,
    generation: Int,
    onEventAcquired: (@Sendable () async -> Void)?
  ) async throws -> (
    attributes: [InstantLiveJSONValue],
    mutationClaimToken: String?
  )? {
    guard generation == self.generation else { return nil }
    nextFrameSequence &+= 1
    frameBeingAppliedState = (generation, nextFrameSequence, event.op)
    // Capture response authority before clearing the in-flight reservation.
    // Once the id leaves `inFlightMutationIDs`, another pump can offer the same
    // durable id under a newer token while this actor is reentrant. The decoded
    // frame must keep the token of the payload that preceded it on this socket.
    let mutationClaimToken = offeredMutationClaimToken(
      for: event,
      generation: generation
    )
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
        // Upstream deletes the write stream once its end is flushed (`Stream.ts` `onStreamFlushed`).
        for (localStreamID, writer) in registeredStreamWriters where writer.serverStreamID == flushed.streamID {
          registeredStreamWriters[localStreamID] = nil
        }
      }
    case .appendFailed:
      // The runtime restarts the writer on this socket (`markStreamWriterBehind`); the socket stays open, as
      // upstream `Stream.ts` `onAppendFailed` restarts only the write stream (library-78).
      break
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
    let attributes = serverAttributes
    await onEventAcquired?()
    return (attributes, mutationClaimToken)
  }

  private func offeredMutationClaimToken(
    for event: InstantLiveServerEvent,
    generation: Int
  ) -> String? {
    guard generation == self.generation else { return nil }
    let mutationID: String?
    switch event {
    case let .transactOK(transactOK):
      mutationID = transactOK.clientEventID
    case let .error(error):
      mutationID = error.clientEventID
    default:
      mutationID = nil
    }
    guard let mutationID else { return nil }
    return offeredMutationClaimTokensInCurrentGeneration[mutationID]
  }

  private func finishDeliveringMutationResponse(
    _ event: InstantLiveServerEvent,
    generation: Int,
    claimToken: String?
  ) {
    guard generation == self.generation else { return }
    if frameBeingAppliedState?.generation == generation {
      frameBeingAppliedState = nil
    }
    let mutationID: String?
    switch event {
    case let .transactOK(transactOK):
      mutationID = transactOK.clientEventID
    case let .error(error):
      mutationID = error.clientEventID
    default:
      mutationID = nil
    }
    guard let mutationID else { return }
    // Answered on this connection: it no longer counts as an unanswered earlier offer.
    offeredWithoutAnswerOnEarlierConnections.remove(mutationID)
    // The Runtime handler suspends while it commits the durable disposition. A
    // deadline/reclaim path may offer the same mutation id under a newer token
    // during that suspension. Finish only the exact response reservation we
    // captured before suspending; never erase the newer offer's authority.
    guard offeredMutationClaimTokensInCurrentGeneration[mutationID] == claimToken else {
      return
    }
    offeredMutationIDsInCurrentGeneration.remove(mutationID)
    offeredMutationClaimTokensInCurrentGeneration[mutationID] = nil
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
      // A write that began finishes, or fails the socket within its timeout, whatever happens to its caller. The
      // timeout used to end on the caller's cancellation too, and a failed write ends the socket below, so cancelling
      // an observation while its add-query was being written closed a healthy socket and re-added every query
      // (library-78). Upstream `Reactor.js` writes with a synchronous `ws.send`, which no caller can interrupt. The
      // unstructured task does not inherit the caller's cancellation, and awaiting its value does not propagate it.
      try await Task {
        try await instantLiveWithTimeout(
          operation: "send Instant live session message",
          timeoutMilliseconds: instantLiveOperationTimeoutMilliseconds
        ) {
          try await session.send(message)
        }
      }.value
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

  /// Whether the applier may apply the next frame it took from the reader (#296).
  ///
  /// `false` stops the applier without a reconnect, because a close or a replacement owns this generation now. A send
  /// failure retained for this socket is thrown, so `receiverEnded` handles it. That send aborted the wire, and the
  /// single receive loop's next `receive()` failed at this point, so frames the reader took before the failure are
  /// dropped the same way.
  private func applierMayApplyNextFrame(
    generation: Int,
    session: InstantLiveWebSocketSession
  ) throws -> Bool {
    guard canDeliverReceiverEvent(generation: generation, session: session) else { return false }
    if let failure = retainedReceiverFailure(for: session) {
      throw failure
    }
    return true
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
    frameBeingAppliedState = nil
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
    cancelQueryResends()
    let session = session
    let receiverTask = receiverTaskOwner.requestStop()
    self.session = nil
    sessionID = nil
    serverAttributes = []
    inFlightMutationIDs.removeAll()
    inFlightMutationStepCounts.removeAll()
    inFlightMutationDeadlines.removeAll()
    rememberUnansweredOffersOfEndingGeneration()
    offeredMutationIDsInCurrentGeneration.removeAll()
    offeredMutationClaimTokensInCurrentGeneration.removeAll()
    acknowledgementUnknownMutationIDs.removeAll()
    frameBeingAppliedState = nil
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

  /// The current applier has applied every frame its reader took and is waiting for the next one. The reader asks
  /// for the next frame as soon as it buffers one, so a new `receive()` no longer proves a frame was applied (#296).
  func applierIsWaitingForAFrameForTesting() -> Bool {
    receivedFrames?.applierIsWaitingForTesting == true
  }

  /// Applies one room frame the reader handed over, in arrival order and beside the query applier (#461): the room's
  /// connection state and the presence and broadcasts it flushes on `join-room-ok`, then the runtime's presence or
  /// broadcast state. A send that fails here aborts the socket, and the applier ends the generation as for any other
  /// failed send.
  private func applyRoomFrame(
    _ message: InstantLiveMessage,
    generation: Int,
    session: InstantLiveWebSocketSession,
    onRoomEvent: @Sendable (InstantLiveServerEvent, InstantRoomHandle, String?) async -> Void
  ) async {
    guard canDeliverReceiverEvent(generation: generation, session: session) else { return }
    let event = InstantLiveServerEvent(message: message)
    let roomID: String
    switch event {
    case let .joinRoomOK(room), let .leaveRoomOK(room):
      roomID = room.roomID
    case let .refreshPresence(refresh):
      roomID = refresh.roomID
    case let .patchPresence(patch):
      roomID = patch.roomID
    case let .serverBroadcast(broadcast):
      roomID = broadcast.roomID
    default:
      // set-presence-ok, client-broadcast-ok, and the legacy join-room-error carry nothing to apply.
      return
    }
    do {
      try await recordRoomEvent(op: event.op, roomID: roomID)
    } catch {
      InstantDiagnostics.shared.record(
        error: error,
        subsystem: "instant-swift-data-core",
        category: "presence",
        event: "live-room.flush-failed",
        message: "A room frame's flush of presence or broadcasts failed; the connection reconnects.",
        metadata: ["op": event.op]
      )
      return
    }
    guard canDeliverReceiverEvent(generation: generation, session: session),
      let room = registeredRooms.keys.first(where: { $0.id == roomID })
    else {
      return
    }
    await onRoomEvent(event, room, sessionID)
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
