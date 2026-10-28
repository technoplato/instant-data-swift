import Foundation

// History:
// - #1315: the live session over HTTP, for watchOS. watchOS treats `URLSessionWebSocketTask` as low-level networking
//   and blocks it unless an audio app is streaming audio or a call is running (TN3135), so a Watch's socket never
//   opened and its live queries never answered. Upstream has the same session over Server-Sent Events
//   (`client/packages/core/src/Connection.ts` `SSEConnection`): a GET whose response streams the server's messages,
//   and a POST per batch of client messages, both plain HTTP, which watchOS allows every app.

extension InstantLiveSessionRequest {
  /// The event stream's URL: the session's host over HTTP at `/runtime/sse`, as upstream `Reactor.js`
  /// `createTransport` builds `${apiURI}/runtime/sse?app_id=`. Messages are posted to the same URL.
  public func eventStreamURL() throws -> URL {
    guard var components = URLComponents(url: try sessionURL(), resolvingAgainstBaseURL: false) else {
      throw InstantError(
        code: .validationFailed,
        operation: "build Instant live event-stream URL",
        path: "websocketURI",
        message: "The WebSocket URI could not be read as URL components.",
        recovery: "Pass an Instant runtime WebSocket URI such as wss://api.instantdb.com/runtime/session."
      )
    }
    components.scheme = components.scheme == "ws" ? "http" : "https"
    components.path = "/runtime/sse"
    guard let url = components.url else {
      throw InstantError(
        code: .validationFailed,
        operation: "build Instant live event-stream URL",
        path: "websocketURI",
        message: "The event-stream URL could not be encoded.",
        recovery: "Check the app id and WebSocket URI before opening the live session."
      )
    }
    return url
  }

  /// The stream's opening request, with this attempt's network access (#1237).
  func eventStreamRequest() throws -> URLRequest {
    var request = URLRequest(url: try eventStreamURL())
    request.httpMethod = "GET"
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
    request.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
    return request
  }
}

/// Reads the Server-Sent Events wire one line at a time: `data:` lines gather until a blank line ends the event; `:`
/// lines are comments (the server's idle keepalive) and other fields are ignored.
struct InstantLiveEventStreamParser {
  private var data: [Substring] = []

  /// The event a line completes, as its joined `data`, or nil.
  mutating func consume(line: String) -> String? {
    if line.isEmpty {
      defer { data = [] }
      return data.isEmpty ? nil : data.joined(separator: "\n")
    }
    guard line.hasPrefix("data:") else { return nil }
    var value = line.dropFirst(5)
    if value.first == " " { value = value.dropFirst() }
    data.append(value)
    return nil
  }
}

enum InstantLiveEventStreamPayload {
  /// The messages one event carries: one object, or an array of them as upstream `SSEConnection.onmessage` accepts.
  static func messages(fromData data: String) throws -> [InstantLiveMessage] {
    guard data.first(where: { !$0.isWhitespace }) == "[" else {
      return [try InstantLiveMessage.decoded(fromFrame: data)]
    }
    return try JSONDecoder().decode([InstantLiveMessage].self, from: Data(data.utf8))
  }
}

/// The server's `sse-init`: the ids and token every POST of this stream carries.
struct InstantLiveEventStreamStart: Hashable, Sendable {
  let machineID: String
  let sessionID: String
  let token: String

  init?(_ message: InstantLiveMessage) {
    guard message.op == "sse-init",
      case .string(let machineID)? = message.fields["machine-id"],
      case .string(let sessionID)? = message.fields["session-id"],
      case .string(let token)? = message.fields["sse-token"]
    else { return nil }
    self.machineID = machineID
    self.sessionID = sessionID
    self.token = token
  }

  func postBody(messages: [InstantLiveMessage]) throws -> Data {
    struct Body: Encodable {
      let machine_id: String
      let session_id: String
      let sse_token: String
      let messages: [InstantLiveMessage]
    }
    return try JSONEncoder().encode(
      Body(machine_id: machineID, session_id: sessionID, sse_token: token, messages: messages)
    )
  }
}

extension InstantLiveTransportClient {
  public enum LiveKind: Hashable, Sendable {
    case webSocket
    case eventStream
  }

  /// What ``live`` opens on this platform: the event stream on watchOS (TN3135), the WebSocket elsewhere.
  public static var liveKind: LiveKind {
    #if os(watchOS)
      .eventStream
    #else
      .webSocket
    #endif
  }

  /// The live session over HTTP (#1315), as upstream `SSEConnection`. ``live`` uses it on watchOS.
  public static let liveEventStream: Self = {
    var live = Self.connectionAttempts { request in
      let urlRequest = try request.eventStreamRequest()
      let stream = InstantURLSessionLiveEventStream(
        streamRequest: urlRequest,
        allowsExpensiveNetworkAccess: request.allowsExpensiveNetworkAccess
      )
      return InstantLiveConnectionAttempt(
        connect: {
          try await stream.waitForStart()
          return InstantLiveWebSocketSession(
            send: { try await stream.send($0) },
            receive: { try await stream.receive() },
            close: { await stream.close() },
            abort: { stream.abort() }
          )
        },
        abort: { stream.abort() }
      )
    }
    live.networkPath = .system
    return live
  }()
}

// SAFETY: `lock` guards the reader and poster tasks and the closed flag; cancelling them happens after it is released.
private final class InstantLiveEventStreamTasks: @unchecked Sendable {
  private let lock = NSLock()
  private var tasks: [Task<Void, Never>] = []
  private var isAborted = false

  var aborted: Bool { lock.withLock { isAborted } }

  /// Keeps `task` so an abort cancels it; cancels it now when the stream is already aborted.
  func hold(_ task: Task<Void, Never>) {
    let cancelNow = lock.withLock {
      if isAborted { return true }
      tasks.removeAll { $0.isCancelled }
      tasks.append(task)
      return false
    }
    if cancelNow { task.cancel() }
  }

  /// Marks the stream aborted once and cancels every task; true the first time.
  @discardableResult
  func abort() -> Bool {
    let taken: [Task<Void, Never>]? = lock.withLock {
      guard !isAborted else { return nil }
      isAborted = true
      defer { tasks = [] }
      return tasks
    }
    taken?.forEach { $0.cancel() }
    return taken != nil
  }
}

// SAFETY: `lock` guards the buffer, the end and the one waiting receive; a continuation resumes after it is released.
/// The stream's received messages, in order, for one receiver at a time.
private final class InstantLiveEventStreamMailbox: @unchecked Sendable {
  private let lock = NSLock()
  private var buffer: [InstantLiveMessage] = []
  private var end: (any Error)?
  private var waiter: CheckedContinuation<InstantLiveMessage, any Error>?

  func yield(_ message: InstantLiveMessage) {
    let waiter: CheckedContinuation<InstantLiveMessage, any Error>? = lock.withLock {
      guard end == nil else { return nil }
      guard let waiter = self.waiter else {
        buffer.append(message)
        return nil
      }
      self.waiter = nil
      return waiter
    }
    waiter?.resume(returning: message)
  }

  /// Ends the stream once: the messages already received are still read, then `error` is thrown.
  func finish(throwing error: any Error) {
    let waiter: CheckedContinuation<InstantLiveMessage, any Error>? = lock.withLock {
      guard end == nil else { return nil }
      end = error
      defer { self.waiter = nil }
      return self.waiter
    }
    waiter?.resume(throwing: error)
  }

  func next() async throws -> InstantLiveMessage {
    try await withCheckedThrowingContinuation { continuation in
      enum Outcome { case message(InstantLiveMessage), failure(any Error), wait }
      let outcome: Outcome = lock.withLock {
        if !buffer.isEmpty { return .message(buffer.removeFirst()) }
        if let end { return .failure(end) }
        if waiter != nil {
          return .failure(
            InstantError(
              code: .validationFailed,
              operation: "receive Instant live event-stream message",
              message: "Another receive is already waiting on this event stream.",
              recovery: "Receive from one task at a time, as the runtime's receive loop does."
            )
          )
        }
        waiter = continuation
        return .wait
      }
      switch outcome {
      case .message(let message): continuation.resume(returning: message)
      case .failure(let error): continuation.resume(throwing: error)
      case .wait: break
      }
    }
  }
}

/// One live session over Server-Sent Events: the GET's response streams the server's messages in order, and sends are
/// batched into POSTs one at a time, in order, as upstream `SSEConnection.flushQueue` does.
actor InstantURLSessionLiveEventStream {
  /// The stream's idle bound. The server writes a `:` comment every 15 s on a quiet stream (measured 2026-10-28 on
  /// api.instantdb.com), so 20 s is one missed comment plus the 5 s every other wait gets; a shorter bound would close
  /// every quiet stream.
  static let idleSeconds: TimeInterval = 20
  private static let sharedURLSession: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.waitsForConnectivity = true
    configuration.timeoutIntervalForRequest = idleSeconds
    // The stream is a long-lived response; only its idle gaps are bounded.
    configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
    return URLSession(configuration: configuration)
  }()

  private let postURL: URL?
  private let allowsExpensiveNetworkAccess: Bool
  private nonisolated let tasks = InstantLiveEventStreamTasks()
  private nonisolated let mailbox = InstantLiveEventStreamMailbox()
  private let wireMeter: InstantWireMeterStorage
  private var start: InstantLiveEventStreamStart?
  private var queued: [(message: InstantLiveMessage, sent: CheckedContinuation<Void, any Error>)] = []
  private var isPosting = false

  init(
    streamRequest: URLRequest,
    allowsExpensiveNetworkAccess: Bool,
    wireMeter: InstantWireMeterStorage = InstantWireMeter.shared
  ) {
    self.postURL = streamRequest.url
    self.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
    self.wireMeter = wireMeter
    let mailbox = self.mailbox
    let reader = Task {
      do {
        let (bytes, response) = try await Self.sharedURLSession.bytes(for: streamRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
          throw Self.httpError(status: http.statusCode, operation: "open Instant live event stream")
        }
        var parser = InstantLiveEventStreamParser()
        // `AsyncBytes.lines` drops empty lines, and an empty line is what ends an event, so lines are cut here.
        var line: [UInt8] = []
        for try await byte in bytes {
          guard byte == UInt8(ascii: "\n") else {
            line.append(byte)
            continue
          }
          if line.last == UInt8(ascii: "\r") { line.removeLast() }
          let text = String(decoding: line, as: UTF8.self)
          line.removeAll(keepingCapacity: true)
          guard let data = parser.consume(line: text) else { continue }
          let received = try InstantLiveEventStreamPayload.messages(fromData: data)
          InstantURLSessionLiveWebSocket.logWireSummary(
            wireMeter.record(.received, op: received.first?.op ?? "unknown", bytes: data.utf8.count)
          )
          received.forEach { mailbox.yield($0) }
        }
        mailbox.finish(throwing: Self.closedError())
      } catch {
        if !(error is CancellationError) {
          InstantDiagnostics.shared.record(
            error: error,
            subsystem: "instant-swift-data-core",
            category: "network",
            event: "urlsession-event-stream.receive-failed",
            message: "The Instant live event stream failed or ended."
          )
        }
        mailbox.finish(throwing: error)
      }
    }
    tasks.hold(reader)
    InstantDiagnostics.shared.record(
      .debug,
      subsystem: "instant-swift-data-core",
      category: "network",
      event: "urlsession-event-stream.resumed",
      message: "URLSession event stream requested.",
      metadata: [
        "host": streamRequest.url?.host ?? "unknown",
        "allowsExpensiveNetworkAccess": String(allowsExpensiveNetworkAccess),
      ]
    )
  }

  /// Waits for the server's `sse-init`, which upstream treats as the stream's open; the caller bounds the wait.
  func waitForStart() async throws {
    let first = try await next()
    guard let start = InstantLiveEventStreamStart(first) else {
      throw InstantError(
        code: .networkFailed,
        operation: "open Instant live event stream",
        message: "The event stream's first message was \(first.op), not sse-init.",
        recovery: "Check that the server serves /runtime/sse for this app."
      )
    }
    self.start = start
  }

  func receive() async throws -> InstantLiveMessage {
    try await next()
  }

  private func next() async throws -> InstantLiveMessage {
    try await mailbox.next()
  }

  /// Returns once the POST carrying `message` succeeded; a failed POST closes the stream, as upstream's `handleError`.
  func send(_ message: InstantLiveMessage) async throws {
    guard !tasks.aborted, start != nil else { throw Self.closedError() }
    try await withCheckedThrowingContinuation { sent in
      queued.append((message, sent))
      guard !isPosting else { return }
      isPosting = true
      tasks.hold(Task { await self.postQueued() })
    }
  }

  private func postQueued() async {
    while !queued.isEmpty {
      let batch = queued
      queued = []
      do {
        guard let start, let postURL, !tasks.aborted else { throw Self.closedError() }
        let body = try start.postBody(messages: batch.map(\.message))
        var request = URLRequest(url: postURL, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
        request.httpBody = body
        let (_, response) = try await Self.sharedURLSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
          throw Self.httpError(status: http.statusCode, operation: "send Instant live event-stream messages")
        }
        InstantURLSessionLiveWebSocket.logWireSummary(
          wireMeter.record(.sent, op: batch.first?.message.op ?? "unknown", bytes: body.count)
        )
        batch.forEach { $0.sent.resume() }
      } catch {
        InstantDiagnostics.shared.record(
          error: error,
          subsystem: "instant-swift-data-core",
          category: "network",
          event: "urlsession-event-stream.send-failed",
          message: "URLSession failed to post Instant live messages; the event stream closes.",
          metadata: ["op": batch.first?.message.op ?? "unknown", "count": String(batch.count)]
        )
        batch.forEach { $0.sent.resume(throwing: error) }
        let rest = queued
        queued = []
        rest.forEach { $0.sent.resume(throwing: error) }
        abort()
      }
    }
    isPosting = false
  }

  func close() {
    abort()
  }

  /// Ends the stream at once: cancels the GET and any POST, and ends every pending receive.
  nonisolated func abort() {
    guard tasks.abort() else { return }
    mailbox.finish(throwing: Self.closedError())
  }

  private static func closedError() -> InstantError {
    InstantError(
      code: .networkFailed,
      operation: "use Instant live event stream",
      message: "The Instant live event stream is closed.",
      recovery: "The runtime reconnects with a new stream."
    )
  }

  private static func httpError(status: Int, operation: String) -> InstantError {
    InstantError(
      code: .networkFailed,
      operation: operation,
      message: "The server answered HTTP \(status).",
      recovery: "Check the app id and the server's /runtime/sse route."
    )
  }
}
