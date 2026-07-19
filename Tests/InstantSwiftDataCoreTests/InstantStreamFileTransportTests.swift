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
