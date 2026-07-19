import Foundation

public struct InstantStreamFileFetchResponse: Sendable {
  public var statusCode: Int
  public var body: AsyncThrowingStream<Data, Error>

  public init(
    statusCode: Int,
    body: AsyncThrowingStream<Data, Error>
  ) {
    self.statusCode = statusCode
    self.body = body
  }

  public init(statusCode: Int, data: Data) {
    self.init(
      statusCode: statusCode,
      body: AsyncThrowingStream { continuation in
        if !data.isEmpty {
          continuation.yield(data)
        }
        continuation.finish()
      }
    )
  }
}

public final class InstantStreamFileTransportClient: Sendable {
  public let fetch: @Sendable (URL) async throws -> InstantStreamFileFetchResponse

  public init(
    fetch: @escaping @Sendable (URL) async throws -> InstantStreamFileFetchResponse
  ) {
    self.fetch = fetch
  }
}

extension InstantStreamFileTransportClient {
  public static let live = InstantStreamFileTransportClient { url in
    let (bytes, response) = try await URLSession.shared.bytes(from: url)
    guard let response = response as? HTTPURLResponse else {
      throw InstantError(
        code: .networkFailed,
        operation: "fetch Instant stream file",
        message: "Instant stream storage returned a non-HTTP response.",
        recovery: "Reconnect the stream reader and retry the signed file URL."
      )
    }

    let body = AsyncThrowingStream<Data, Error> { continuation in
      let task = Task {
        do {
          var chunk = Data()
          chunk.reserveCapacity(64 * 1_024)
          for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if chunk.count == 64 * 1_024 {
              continuation.yield(chunk)
              chunk.removeAll(keepingCapacity: true)
            }
          }
          if !chunk.isEmpty {
            continuation.yield(chunk)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
    return InstantStreamFileFetchResponse(
      statusCode: response.statusCode,
      body: body
    )
  }
}

struct InstantStreamFileMaterialization: Sendable {
  var data: Data
  var nextSeenOffset: Int64
}

enum InstantStreamFileAppendMaterializer {
  static func materialize(
    _ append: InstantLiveStreamAppend,
    seenOffset: Int64,
    transport: InstantStreamFileTransportClient
  ) async throws -> InstantStreamFileMaterialization {
    guard append.offset <= seenOffset else {
      throw InstantError(
        code: .decodeFailed,
        operation: "materialize Instant stream append",
        path: "offset",
        serverEventID: append.clientEventID,
        message:
          "Instant stream append starts at byte offset \(append.offset), after the reader's "
          + "seen offset \(seenOffset).",
        recovery: "Reconnect the stream reader from its last seen byte offset."
      )
    }

    var discardByteCount = seenOffset - append.offset
    var materialized = Data()

    func appendUnseenBytes(_ bytes: Data) {
      let dropped = min(discardByteCount, Int64(bytes.count))
      discardByteCount -= dropped
      materialized.append(bytes.dropFirst(Int(dropped)))
    }

    var nextFetch: Task<InstantStreamFileFetchResponse, Error>?
    if let first = append.files.first {
      let url = try fileURL(first, append: append)
      nextFetch = Task { try await transport.fetch(url) }
    }
    defer { nextFetch?.cancel() }

    for index in append.files.indices {
      guard let currentFetch = nextFetch else { break }
      let response = try await currentFetch.value

      if append.files.indices.contains(index + 1) {
        let url = try fileURL(append.files[index + 1], append: append)
        nextFetch = Task { try await transport.fetch(url) }
      } else {
        nextFetch = nil
      }

      guard (200..<300).contains(response.statusCode) else {
        nextFetch?.cancel()
        throw InstantError(
          code: .networkFailed,
          operation: "fetch Instant stream file",
          serverEventID: append.clientEventID,
          message: "Instant stream storage returned HTTP \(response.statusCode).",
          recovery: "Reconnect the stream reader and retry from its last seen byte offset."
        )
      }

      for try await chunk in response.body {
        try Task.checkCancellation()
        appendUnseenBytes(chunk)
      }
    }

    if let content = append.content, !content.isEmpty {
      appendUnseenBytes(Data(content.utf8))
    }

    return InstantStreamFileMaterialization(
      data: materialized,
      nextSeenOffset: seenOffset + Int64(materialized.count)
    )
  }

  private static func fileURL(
    _ file: InstantLiveStreamFile,
    append: InstantLiveStreamAppend
  ) throws -> URL {
    guard let url = URL(string: file.url), url.scheme != nil else {
      throw InstantError(
        code: .decodeFailed,
        operation: "fetch Instant stream file",
        path: "files.url",
        serverEventID: append.clientEventID,
        message: "Instant stream append included an invalid file URL.",
        recovery: "Reconnect the stream reader and inspect the canonical stream-append payload."
      )
    }
    return url
  }
}
