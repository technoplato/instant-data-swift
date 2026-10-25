import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantStreamFileTransportTests {
  @Test("File appends discard byte overlap across files and inline content")
  func discardsByteOverlapAcrossFilesAndInlineContent() async throws {
    let responses = StreamFileResponseRecorder(responses: [
      "https://files.test/a": .init(statusCode: 200, data: Data("hello ".utf8)),
      "https://files.test/b": .init(statusCode: 200, data: Data("🚀".utf8)),
    ])
    let append = InstantLiveStreamAppend(
      clientEventID: "subscription-1",
      streamID: "stream-1",
      clientID: "client-1",
      files: [
        .init(url: "https://files.test/a", size: 6),
        .init(url: "https://files.test/b", size: 4),
      ],
      done: false,
      abortReason: nil,
      offset: 0,
      error: nil,
      retry: false,
      content: "!"
    )

    let result = try await InstantStreamFileAppendMaterializer.materialize(
      append,
      seenOffset: 6,
      transport: responses.client
    )

    expectNoDifference(String(data: result.data, encoding: .utf8), "🚀!")
    expectNoDifference(result.nextSeenOffset, 11)
    let requestedURLs = await responses.requestedURLs()
    expectNoDifference(requestedURLs, ["https://files.test/a", "https://files.test/b"])
  }

  @Test("A split UTF-8 scalar is held across response chunks")
  func holdsSplitUTF8ScalarAcrossResponseChunks() async throws {
    let encoded = Data("🚀".utf8)
    let response = InstantStreamFileFetchResponse(
      statusCode: 200,
      body: AsyncThrowingStream { continuation in
        continuation.yield(encoded.prefix(2))
        continuation.yield(encoded.dropFirst(2))
        continuation.finish()
      }
    )
    let append = InstantLiveStreamAppend(
      clientEventID: "subscription-1",
      streamID: "stream-1",
      clientID: "client-1",
      files: [.init(url: "https://files.test/emoji", size: 4)],
      done: false,
      abortReason: nil,
      offset: 0,
      error: nil,
      retry: false,
      content: nil
    )

    let result = try await InstantStreamFileAppendMaterializer.materialize(
      append,
      seenOffset: 0,
      transport: InstantStreamFileTransportClient { _ in response }
    )

    expectNoDifference(String(data: result.data, encoding: .utf8), "🚀")
    expectNoDifference(result.nextSeenOffset, 4)
  }

  @Test("The next file request starts before the current response body is consumed")
  func pipelinesNextFileRequest() async throws {
    let recorder = GatedStreamFileRecorder()
    let append = InstantLiveStreamAppend(
      clientEventID: "subscription-1",
      streamID: "stream-1",
      clientID: "client-1",
      files: [
        .init(url: "https://files.test/a", size: 1),
        .init(url: "https://files.test/b", size: 1),
      ],
      done: false,
      abortReason: nil,
      offset: 0,
      error: nil,
      retry: false,
      content: nil
    )

    let task = Task {
      try await InstantStreamFileAppendMaterializer.materialize(
        append,
        seenOffset: 0,
        transport: recorder.client
      )
    }
    defer { task.cancel() }

    try await recorder.waitForRequests(2)
    let requestedURLs = await recorder.requestedURLs()
    expectNoDifference(requestedURLs, ["https://files.test/a", "https://files.test/b"])
    await recorder.releaseBodies()
    let result = try await task.value
    expectNoDifference(String(data: result.data, encoding: .utf8), "AB")
  }

  @Test("A failed file response does not advance the reader offset")
  func failedResponseThrowsBeforeAdvancing() async throws {
    let append = InstantLiveStreamAppend(
      clientEventID: "subscription-1",
      streamID: "stream-1",
      clientID: "client-1",
      files: [.init(url: "https://files.test/failure", size: 10)],
      done: false,
      abortReason: nil,
      offset: 5,
      error: nil,
      retry: false,
      content: nil
    )

    await #expect(throws: InstantError.self){
      _ = try await InstantStreamFileAppendMaterializer.materialize(
        append,
        seenOffset: 5,
        transport: InstantStreamFileTransportClient { _ in
          InstantStreamFileFetchResponse(statusCode: 503, data: Data())
        }
      )
    }
  }

  /// #1125: a reader that reconnects has seen part of the stream; it asks for the rest with Range requests, a file it
  /// has seen whole past its end (the server's 416 names the file's size) and the one its seen offset falls in from
  /// that point (a 206 starting there), so the bytes it already has are not sent again. Upstream's `Stream.ts` fetches
  /// every file from its start and drops them.
  @Test("A resumed append asks only for the bytes after the seen offset")
  func aResumeFetchesOnlyTheUnseenBytes() async throws {
    // The stream so far: "hello " in one file and "WXYZ" in the next; the reader has seen "hello WX".
    let server = RangedStreamFileServer(
      files: ["https://files.test/a": Data("hello ".utf8), "https://files.test/b": Data("WXYZ".utf8)],
      honorsRanges: true
    )
    let append = InstantLiveStreamAppend(
      clientEventID: "subscription-1",
      streamID: "stream-1",
      files: [.init(url: "https://files.test/a", size: 6), .init(url: "https://files.test/b", size: 4)],
      offset: 0,
      content: "!"
    )

    let result = try await InstantStreamFileAppendMaterializer.materialize(
      append,
      seenOffset: 8,
      transport: server.client
    )

    let requests = await server.requests()
    let bytesSent = await server.bytesSent()
    expectNoDifference(String(data: result.data, encoding: .utf8), "YZ!")
    expectNoDifference(result.nextSeenOffset, 11)
    expectNoDifference(requests, ["a from 8", "b from 2"])
    expectNoDifference(bytesSent, 2)
  }

  /// A server that ignores the range answers 200 with the whole file: the reader drops the bytes it has seen, as it
  /// always did, and fetches the rest whole.
  @Test("A server that ignores the range still yields only the unseen bytes")
  func aServerThatIgnoresRangesStillYieldsTheUnseenBytes() async throws {
    let server = RangedStreamFileServer(
      files: ["https://files.test/a": Data("hello ".utf8), "https://files.test/b": Data("WXYZ".utf8)],
      honorsRanges: false
    )
    let append = InstantLiveStreamAppend(
      clientEventID: "subscription-1",
      streamID: "stream-1",
      files: [.init(url: "https://files.test/a", size: 6), .init(url: "https://files.test/b", size: 4)],
      offset: 0,
      content: "!"
    )

    let result = try await InstantStreamFileAppendMaterializer.materialize(
      append,
      seenOffset: 8,
      transport: server.client
    )

    let requests = await server.requests()
    expectNoDifference(String(data: result.data, encoding: .utf8), "YZ!")
    expectNoDifference(result.nextSeenOffset, 11)
    expectNoDifference(requests, ["a from 8", "b"])
  }

  @Test("Cancelling materialization terminates the active response body")
  func cancellationTerminatesActiveResponseBody() async throws {
    let recorder = CancellableStreamFileRecorder()
    let append = InstantLiveStreamAppend(
      clientEventID: "subscription-1",
      streamID: "stream-1",
      clientID: "client-1",
      files: [.init(url: "https://files.test/blocking", size: 10)],
      offset: 0
    )
    let task = Task {
      try await InstantStreamFileAppendMaterializer.materialize(
        append,
        seenOffset: 0,
        transport: recorder.client
      )
    }

    await recorder.waitUntilStarted()
    task.cancel()
    await #expect(throws: CancellationError.self){
      _ = try await task.value
    }
    await recorder.waitUntilTerminated()
  }
}

private actor StreamFileResponseRecorder {
  private let responses: [String: InstantStreamFileFetchResponse]
  private var requests: [String] = []

  init(responses: [String: InstantStreamFileFetchResponse]) {
    self.responses = responses
  }

  nonisolated var client: InstantStreamFileTransportClient {
    InstantStreamFileTransportClient { url in
      try await self.fetch(url)
    }
  }

  func fetch(_ url: URL) throws -> InstantStreamFileFetchResponse {
    requests.append(url.absoluteString)
    guard let response = responses[url.absoluteString] else {
      throw InstantError(
        code: .networkFailed,
        operation: "fetch test stream file",
        message: "missing response",
        recovery: "register the response"
      )
    }
    return response
  }

  func requestedURLs() -> [String] {
    requests
  }
}

private actor GatedStreamFileRecorder {
  private var requests: [String] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var bodyContinuations: [AsyncThrowingStream<Data, Error>.Continuation] = []

  nonisolated var client: InstantStreamFileTransportClient {
    InstantStreamFileTransportClient { url in
      await self.fetch(url)
    }
  }

  func fetch(_ url: URL) -> InstantStreamFileFetchResponse {
    requests.append(url.absoluteString)
    if requests.count >= 2 {
      let current = waiters
      waiters.removeAll()
      current.forEach { $0.resume() }
    }
    let body = AsyncThrowingStream<Data, Error> { continuation in
      bodyContinuations.append(continuation)
    }
    return InstantStreamFileFetchResponse(statusCode: 200, body: body)
  }

  func waitForRequests(_ count: Int) async throws {
    if requests.count >= count { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func requestedURLs() -> [String] {
    requests
  }

  func releaseBodies() {
    for (index, continuation) in bodyContinuations.enumerated() {
      continuation.yield(Data((index == 0 ? "A" : "B").utf8))
      continuation.finish()
    }
    bodyContinuations.removeAll()
  }
}

private actor CancellableStreamFileRecorder {
  private var started = false
  private var terminated = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private var terminationWaiters: [CheckedContinuation<Void, Never>] = []

  nonisolated var client: InstantStreamFileTransportClient {
    InstantStreamFileTransportClient { _ in
      await self.fetch()
    }
  }

  func fetch() -> InstantStreamFileFetchResponse {
    started = true
    let waiters = startWaiters
    startWaiters.removeAll()
    waiters.forEach { $0.resume() }
    let pair = AsyncThrowingStream<Data, Error>.makeStream()
    pair.continuation.onTermination = { @Sendable _ in
      Task { await self.recordTermination() }
    }
    return InstantStreamFileFetchResponse(statusCode: 200, body: pair.stream)
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { continuation in
      startWaiters.append(continuation)
    }
  }

  func waitUntilTerminated() async {
    if terminated { return }
    await withCheckedContinuation { continuation in
      terminationWaiters.append(continuation)
    }
  }

  private func recordTermination() {
    terminated = true
    let waiters = terminationWaiters
    terminationWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }
}

/// A file server that answers whole fetches, and ranged ones as S3 does when `honorsRanges`: 206 with the tail from
/// the offset, or 416 past the end, each with its `Content-Range`; otherwise 200 with the whole file.
private actor RangedStreamFileServer {
  private let files: [String: Data]
  private let honorsRanges: Bool
  private var log: [String] = []
  private var sent = 0

  init(files: [String: Data], honorsRanges: Bool) {
    self.files = files
    self.honorsRanges = honorsRanges
  }

  nonisolated var client: InstantStreamFileTransportClient {
    InstantStreamFileTransportClient(
      fetch: { url in try await self.answer(url, from: nil) },
      fetchFrom: { url, offset in try await self.answer(url, from: offset) }
    )
  }

  func answer(_ url: URL, from offset: Int64?) throws -> InstantStreamFileFetchResponse {
    let name = url.lastPathComponent
    log.append(offset.map { "\(name) from \($0)" } ?? name)
    guard let data = files[url.absoluteString] else {
      return InstantStreamFileFetchResponse(statusCode: 404, data: Data())
    }
    guard let offset, honorsRanges else {
      sent += data.count
      return InstantStreamFileFetchResponse(statusCode: 200, data: data)
    }
    guard offset < Int64(data.count) else {
      return InstantStreamFileFetchResponse(statusCode: 416, data: Data(), contentRange: "bytes */\(data.count)")
    }
    let tail = data.suffix(from: data.startIndex + Int(offset))
    sent += tail.count
    return InstantStreamFileFetchResponse(
      statusCode: 206,
      data: Data(tail),
      contentRange: "bytes \(offset)-\(data.count - 1)/\(data.count)"
    )
  }

  func requests() -> [String] { log }
  func bytesSent() -> Int { sent }
}
