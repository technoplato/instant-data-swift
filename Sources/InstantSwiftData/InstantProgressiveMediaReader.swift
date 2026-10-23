// Reading a progressive media stream: its rows as segments in order, and its files' URLs (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). The stream's row says how many segments are stored; a refresh reads only the
//   segment rows it has not read, so following a six-hour stream costs a few rows a segment, never the whole list again.
//   URLs are read a page at a time (upstream mints one per `$files.url` read, `instaql.clj` `add-url-to-join-rows`,
//   valid 7 days from the start of the UTC day it was signed) and kept for a day.

import Dependencies
import Foundation

/// Reads a stream's rows as the segments a player plays, and resolves its files' URLs.
///
/// ```swift
/// let reader = InstantProgressiveMediaReader(streamID: stream.id, source: .live(client))
/// let snapshot = try await reader.refresh()
/// let playlist = snapshot.playlist(initializationURI: "init.mp4") { "\($0.index).m4s" }
/// ```
///
/// Every read goes to the server: a reader on another device sees what the writer has stored, never this device's
/// optimistic state.
public actor InstantProgressiveMediaReader {
  /// Where the reader's rows and URLs come from.
  public struct Source: Sendable {
    /// The stream's row, or nil before the writer stored it.
    public var streamRow: @Sendable (_ id: InstantID<InstantProgressiveMediaStreamRow>) async throws
      -> InstantProgressiveMediaStreamRow?
    /// Up to `limit` of the stream's segment rows from `fromIndex` on, in index order.
    public var segments: @Sendable (_ streamID: String, _ fromIndex: Int, _ limit: Int) async throws
      -> [InstantProgressiveMediaSegmentRow]
    /// The URLs storage serves the files at `paths` from, by path.
    public var fileURLs: @Sendable (_ paths: [String]) async throws -> [String: URL]

    public init(
      streamRow: @escaping @Sendable (_ id: InstantID<InstantProgressiveMediaStreamRow>) async throws
        -> InstantProgressiveMediaStreamRow?,
      segments: @escaping @Sendable (_ streamID: String, _ fromIndex: Int, _ limit: Int) async throws
        -> [InstantProgressiveMediaSegmentRow],
      fileURLs: @escaping @Sendable (_ paths: [String]) async throws -> [String: URL]
    ) {
      self.streamRow = streamRow
      self.segments = segments
      self.fileURLs = fileURLs
    }
  }

  /// The stream as the reader last read it.
  public struct Snapshot: Hashable, Sendable {
    public var stream: InstantProgressiveMediaStreamRow?
    /// The listed segments: contiguous from index 0, in order.
    public var segments: [InstantProgressiveMediaSegment]

    public init(stream: InstantProgressiveMediaStreamRow?, segments: [InstantProgressiveMediaSegment]) {
      self.stream = stream
      self.segments = segments
    }

    /// Whether every segment is listed.
    public var isFinished: Bool {
      guard let stream, stream.state == .finished else { return false }
      return segments.count >= stream.segmentCount
    }

    /// The listed segments as an HLS media playlist: `EVENT` while the stream records, `VOD` once every segment is
    /// listed.
    public func playlist(
      initializationURI: String,
      segmentURI: (InstantProgressiveMediaSegment) -> String
    ) -> InstantProgressiveMediaPlaylist {
      InstantProgressiveMediaPlaylist(
        initializationURI: initializationURI,
        segments: segments.map {
          InstantProgressiveMediaPlaylist.Segment(uri: segmentURI($0), durationSeconds: $0.durationSeconds)
        },
        isFinished: isFinished
      )
    }
  }

  public nonisolated let streamID: InstantID<InstantProgressiveMediaStreamRow>
  private let source: Source
  private let urlPageSize: Int
  private let segmentPageSize = 500
  private var stream: InstantProgressiveMediaStreamRow?
  private var segments: [InstantProgressiveMediaSegment] = []
  private var urls: [String: (url: URL, readAt: Date)] = [:]

  @Dependency(\.date) private var date

  /// A kept URL is read again after a day: storage signs it for 7 days from the start of the UTC day it was read.
  public static let urlLifetime: TimeInterval = 86_400

  public init(
    streamID: InstantID<InstantProgressiveMediaStreamRow>,
    source: Source,
    urlPageSize: Int = 50
  ) {
    self.streamID = streamID
    self.source = source
    self.urlPageSize = max(1, urlPageSize)
  }

  /// Reads the stream's row, then the segment rows it lists that this reader has not read, and returns the stream.
  ///
  /// Segments are listed contiguously from index 0: a segment whose row has not arrived ends the listing until it
  /// does, so a player never skips audio.
  public func refresh() async throws -> Snapshot {
    stream = try await source.streamRow(streamID)
    if let stream {
      while segments.count < stream.segmentCount {
        let page = try await source.segments(
          streamID.rawValue,
          segments.count,
          min(segmentPageSize, stream.segmentCount - segments.count)
        )
        let before = segments.count
        for row in page.sorted(by: { $0.index < $1.index }) where row.index == segments.count {
          segments.append(row.segment)
        }
        if segments.count == before || page.count < min(segmentPageSize, stream.segmentCount - before) {
          break
        }
      }
    }
    return Snapshot(stream: stream, segments: segments)
  }

  /// The URL of a listed segment's file. A page of the following segments' URLs is read with it, so a player that
  /// plays on finds them kept.
  public func url(forSegment index: Int) async throws -> URL {
    guard segments.indices.contains(index) else {
      throw InstantError(
        code: .validationFailed,
        operation: "read progressive media URL",
        localID: streamID.rawValue,
        message: "Segment \(index) is not listed; \(segments.count) are.",
        recovery: "Call refresh() and ask for a listed segment."
      )
    }
    let path = segments[index].path
    if let url = keptURL(path) { return url }
    let page = segments[index..<min(segments.count, index + urlPageSize)].map(\.path).filter { keptURL($0) == nil }
    return try await read(page, for: path)
  }

  /// The URL of the stream's initialization segment.
  public func initializationURL() async throws -> URL {
    if stream == nil { _ = try await refresh() }
    guard let path = stream?.initializationPath else {
      throw InstantError(
        code: .validationFailed,
        operation: "read progressive media URL",
        localID: streamID.rawValue,
        message: "The stream has no row yet.",
        recovery: "Wait for the writer to store its initialization segment."
      )
    }
    if let url = keptURL(path) { return url }
    return try await read([path], for: path)
  }

  private func keptURL(_ path: String) -> URL? {
    guard let kept = urls[path], date.now.timeIntervalSince(kept.readAt) < Self.urlLifetime else { return nil }
    return kept.url
  }

  private func read(_ paths: [String], for path: String) async throws -> URL {
    let read = try await source.fileURLs(paths)
    let now = date.now
    for (readPath, url) in read {
      urls[readPath] = (url, now)
    }
    guard let url = read[path] else {
      throw InstantError(
        code: .networkFailed,
        operation: "read progressive media URL",
        path: path,
        localID: streamID.rawValue,
        message: "Storage has no file at \(path).",
        recovery: "The file is listed but not readable: check the app's storage rules for this path."
      )
    }
    return url
  }
}

extension InstantProgressiveMediaReader.Source {
  /// Rows and URLs read from the server with `queryOnce`.
  public static func live(_ client: InstantSwiftDataClient) -> Self {
    Self(
      streamRow: { id in
        let plan = InstantQueryPlan(
          id: "progressive-media-stream:\(id.rawValue)",
          namespace: InstantProgressiveMediaStreamRow.instantNamespace,
          filters: [.equals(field: "id", value: .string(id.rawValue))],
          limit: 1
        )
        return try await client.queryOnce(plan).values.first.map(InstantProgressiveMediaStreamRow.init(snapshot:))
      },
      segments: { streamID, fromIndex, limit in
        let plan = InstantQueryPlan(
          id: "progressive-media-segments:\(streamID):\(fromIndex):\(limit)",
          namespace: InstantProgressiveMediaSegmentRow.instantNamespace,
          filters: [
            .equals(field: "streamID", value: .string(streamID)),
            .greaterThanOrEqual(field: "index", value: .number(Double(fromIndex))),
          ],
          order: InstantQueryOrder("index", .ascending),
          limit: limit
        )
        return try await client.queryOnce(plan).values.map(InstantProgressiveMediaSegmentRow.init(snapshot:))
      },
      fileURLs: { paths in
        guard !paths.isEmpty else { return [:] }
        let plan = InstantQueryPlan(
          id: "progressive-media-files:\(paths[0]):\(paths.count)",
          namespace: "$files",
          filters: [.in(field: "path", values: paths.map(InstantValue.string))],
          selectedFields: ["path", "url"]
        )
        var urls: [String: URL] = [:]
        for file in try await client.queryOnce(plan).values {
          guard
            case let .string(path)? = file.values["path"]?.first,
            case let .string(text)? = file.values["url"]?.first,
            let url = URL(string: text)
          else { continue }
          urls[path] = url
        }
        return urls
      }
    )
  }
}
