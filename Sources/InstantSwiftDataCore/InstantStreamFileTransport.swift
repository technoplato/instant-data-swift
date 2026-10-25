import Foundation

// History:
// - 2026-10-25: a file can be fetched from a byte offset (an HTTP Range request), and a response carries its
//   Content-Range, so a stream reader's resume can ask only for the bytes it has not seen (#1125).

public struct InstantStreamFileFetchResponse: Sendable {
  public var statusCode: Int
  public var body: AsyncThrowingStream<Data, Error>
  /// The response's `Content-Range` header, for a ranged fetch: `bytes 5-9/10` for a 206, `bytes */10` for a 416.
  public var contentRange: String?

  public init(
    statusCode: Int,
    body: AsyncThrowingStream<Data, Error>,
    contentRange: String? = nil
  ) {
    self.statusCode = statusCode
    self.body = body
    self.contentRange = contentRange
  }

  public init(statusCode: Int, data: Data, contentRange: String? = nil) {
    self.init(
      statusCode: statusCode,
      body: AsyncThrowingStream { continuation in
        if !data.isEmpty {
          continuation.yield(data)
        }
        continuation.finish()
      },
      contentRange: contentRange
    )
  }
}

public final class InstantStreamFileTransportClient: Sendable {
  /// Fetches a file whole.
  public let fetch: @Sendable (URL) async throws -> InstantStreamFileFetchResponse
  /// Fetches a file from a byte offset, with an HTTP `Range: bytes=<offset>-` request (#1125), or `nil` for a transport
  /// that cannot; a reader then fetches whole and drops what it has seen. A server that ignores the range answers 200
  /// with the whole file.
  public let fetchFrom: (@Sendable (_ url: URL, _ offset: Int64) async throws -> InstantStreamFileFetchResponse)?

  public init(
    fetch: @escaping @Sendable (URL) async throws -> InstantStreamFileFetchResponse
  ) {
    self.fetch = fetch
    self.fetchFrom = nil
  }

  public init(
    fetch: @escaping @Sendable (URL) async throws -> InstantStreamFileFetchResponse,
    fetchFrom: @escaping @Sendable (_ url: URL, _ offset: Int64) async throws -> InstantStreamFileFetchResponse
  ) {
    self.fetch = fetch
    self.fetchFrom = fetchFrom
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
      try Task.checkCancellation()
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
