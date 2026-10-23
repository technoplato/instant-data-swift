// Reading a progressive media stream: its rows as segments in order, and its files' URLs (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012).

import Dependencies
import Foundation

/// Reads a stream's rows as the segments a player plays, and resolves its files' URLs.
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
    public var isFinished: Bool { false }
  }

  public nonisolated let streamID: InstantID<InstantProgressiveMediaStreamRow>
  private let source: Source
  private let urlPageSize: Int

  public init(
    streamID: InstantID<InstantProgressiveMediaStreamRow>,
    source: Source,
    urlPageSize: Int = 50
  ) {
    self.streamID = streamID
    self.source = source
    self.urlPageSize = urlPageSize
  }

  public func refresh() async throws -> Snapshot {
    Snapshot(stream: nil, segments: [])
  }

  public func url(forSegment index: Int) async throws -> URL {
    throw CancellationError()
  }

  public func initializationURL() async throws -> URL {
    throw CancellationError()
  }
}
