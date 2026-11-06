// Reading a progressive media stream: its rows as segments in order, and its files' URLs (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). The stream's row says how many segments are stored; a refresh reads only the
//   segment rows it has not read, so following a six-hour stream costs a few rows a segment, never the whole list again.
//   URLs are read a page at a time (upstream mints one per `$files.url` read, `instaql.clj` `add-url-to-join-rows`,
//   valid 7 days from the start of the UTC day it was signed) and kept for a day.
// - 2026-11-06: a long stream's first listing reads its last rows and the few rows its breaks need, never every row
//   (#1916). Reading every row first, 500 a page and one page after another, kept a player from its first sound for as
//   long as the stream was long: 2 reads for 811 segments, 16 for 7,695, and on a busy client the playlist request
//   failed after 20 s on every retry. See `InstantProgressiveMediaListing` for why the rows' arithmetic is enough.

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
    /// The stream's stored segment rows at `indexes`, in any order; a row not stored is left out. A long stream's
    /// first listing reads its rows this way (#1916).
    public var segmentsAt: @Sendable (_ streamID: String, _ indexes: [Int]) async throws
      -> [InstantProgressiveMediaSegmentRow]
    /// The URLs storage serves the files at `paths` from, by path.
    public var fileURLs: @Sendable (_ paths: [String]) async throws -> [String: URL]

    /// A source whose `segmentsAt` reads each run of consecutive indexes with `segments`.
    public init(
      streamRow: @escaping @Sendable (_ id: InstantID<InstantProgressiveMediaStreamRow>) async throws
        -> InstantProgressiveMediaStreamRow?,
      segments: @escaping @Sendable (_ streamID: String, _ fromIndex: Int, _ limit: Int) async throws
        -> [InstantProgressiveMediaSegmentRow],
      fileURLs: @escaping @Sendable (_ paths: [String]) async throws -> [String: URL]
    ) {
      self.init(
        streamRow: streamRow,
        segments: segments,
        segmentsAt: { streamID, indexes in
          var rows: [InstantProgressiveMediaSegmentRow] = []
          for run in InstantProgressiveMediaListing.runs(of: indexes) {
            rows += try await segments(streamID, run.lowerBound, run.count).filter { run.contains($0.index) }
          }
          return rows
        },
        fileURLs: fileURLs
      )
    }

    public init(
      streamRow: @escaping @Sendable (_ id: InstantID<InstantProgressiveMediaStreamRow>) async throws
        -> InstantProgressiveMediaStreamRow?,
      segments: @escaping @Sendable (_ streamID: String, _ fromIndex: Int, _ limit: Int) async throws
        -> [InstantProgressiveMediaSegmentRow],
      segmentsAt: @escaping @Sendable (_ streamID: String, _ indexes: [Int]) async throws
        -> [InstantProgressiveMediaSegmentRow],
      fileURLs: @escaping @Sendable (_ paths: [String]) async throws -> [String: URL]
    ) {
      self.streamRow = streamRow
      self.segments = segments
      self.segmentsAt = segmentsAt
      self.fileURLs = fileURLs
    }
  }

  /// The stream as the reader last read it.
  public struct Snapshot: Hashable, Sendable {
    public var stream: InstantProgressiveMediaStreamRow?
    /// The listed segments: contiguous from index 0, in order, each ending where the next starts. A segment a long
    /// stream's listing placed from the stream's grid, without reading its row, has a `byteCount` of 0 (#1916).
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
  /// does, so a player never skips audio. The first listing of a stream longer than one listing page reads its last rows
  /// and only the rows its breaks need (`InstantProgressiveMediaListing`, #1916): its other segments are placed by the
  /// stream's grid, so the reads grow with the stream's breaks, never with its length.
  public func refresh() async throws -> Snapshot {
    stream = try await source.streamRow(streamID)
    if let stream {
      if segments.isEmpty, stream.segmentCount > InstantProgressiveMediaListing.pageSize,
        let listed = try await list(stream)
      {
        segments = listed
      }
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

  /// Lists a long stream from its last rows and the rows its breaks need (#1916), or nil when those rows are not the
  /// stream's as the writer writes them; `refresh()` then reads every row in order. Each round is one read.
  private func list(_ stream: InstantProgressiveMediaStreamRow) async throws -> [InstantProgressiveMediaSegment]? {
    let lastIndexes = Array(InstantProgressiveMediaListing.lastIndexes(of: stream))
    let lastRows = try await source.segmentsAt(streamID.rawValue, lastIndexes)
    guard var listing = InstantProgressiveMediaListing(stream: stream, lastRows: lastRows) else { return nil }
    var indexes = listing.nextReads()
    while !indexes.isEmpty {
      let rows = try await source.segmentsAt(streamID.rawValue, indexes)
      guard listing.record(rows, asked: indexes) else { return nil }
      indexes = listing.nextReads()
    }
    return listing.segments
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
      // By the rows' own ids, which come from the stream's id and the index (`segmentID`): the server finds each row
      // without reading the stream's others. Measured 2026-11-06 (#1916) on streams not read for a while: 64 rows by id
      // in 171-315 ms where the stream's last 64 by `streamID` and `index` took 0.9-6.6 s, growing with its length.
      segmentsAt: { streamID, indexes in
        guard let first = indexes.first else { return [] }
        let plan = InstantQueryPlan(
          id: "progressive-media-segments-at:\(streamID):\(first):\(indexes.count)",
          namespace: InstantProgressiveMediaSegmentRow.instantNamespace,
          filters: [
            .in(
              field: "id",
              values: indexes.map {
                .string(InstantProgressiveMediaStream.segmentID(streamID: streamID, index: $0).rawValue)
              }
            )
          ]
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

/// A long stream's first listing, made from its last rows and the few rows its breaks need (#1916). Pure: the reader
/// performs the reads it asks for and hands back their rows.
///
/// The writer starts each segment where the one before it ends (its `startSeconds` is the sum of the durations before
/// it), names each file after its index (`segmentPath`), and writes the stream row's `segmentCount` in the transaction
/// that writes each segment row, after its file. AVAssetWriter cuts a take at the first frame at or after each
/// `segmentSeconds` from where the take starts. So inside a take every start sits within a frame of the grid, `index *
/// segmentSeconds` from the take's first segment, and only a segment that ends a take early (a stop followed by more
/// audio, or an encoder that takes over) moves every later start, all by the same amount. A stretch whose two ends are
/// `n` segments and `n * segmentSeconds` apart holds no such break: its segments are placed by the grid. A stretch that
/// is off is split at a few rows read together, and a short one is read whole, so the reads grow with the breaks and
/// with the logarithm of the length, never with the length.
///
/// Measured 2026-11-06 on a live app's 221 streams: 212 had every start within 0.25 s of the grid (durations of 6.016 and
/// 5.973 s, 141 and 140 AAC frames; the largest drift across one 12.8-hour take was 0.17 s), the other 8 broke only in
/// their last two segments, which the last rows hold.
struct InstantProgressiveMediaListing: Sendable {
  /// A stream this long or shorter is read whole as one page, as before; a longer one reads this many last rows first,
  /// and a broken stretch this short is read whole.
  static let pageSize = 64
  /// A stretch off the grid is split into this many, at rows read together.
  static let fanOut = 16
  /// How far a stretch's far end may sit from where the grid puts it and still be placed by the grid: above the drift of
  /// a whole 12.8-hour take (0.17 s) and the jitter of one frame (0.043 s), and the largest error a placed start can have.
  static let tolerance: TimeInterval = 0.25

  /// Two read rows, or the stream's start and a read row, and the segments between them.
  private struct Stretch: Hashable, Sendable {
    var lower: Int
    var upper: Int
  }

  private let count: Int
  private let segmentSeconds: Double
  private let media: InstantProgressiveMediaStream
  private var known: [Int: InstantProgressiveMediaSegment] = [:]
  private var pending: [Stretch]

  /// The indexes read first: the stream's last `pageSize`.
  static func lastIndexes(of stream: InstantProgressiveMediaStreamRow) -> Range<Int> {
    max(0, stream.segmentCount - pageSize)..<stream.segmentCount
  }

  /// `indexes` as runs of consecutive indexes, in order.
  static func runs(of indexes: [Int]) -> [Range<Int>] {
    var runs: [Range<Int>] = []
    for index in Set(indexes).sorted() {
      if let last = runs.last, last.upperBound == index {
        runs[runs.count - 1] = last.lowerBound..<(index + 1)
      } else {
        runs.append(index..<(index + 1))
      }
    }
    return runs
  }

  /// A listing from the stream's last rows, or nil when they are not all there at the stream's own paths.
  init?(stream: InstantProgressiveMediaStreamRow, lastRows rows: [InstantProgressiveMediaSegmentRow]) {
    let suffix = "/init.mp4"
    guard stream.segmentCount > 0, stream.segmentSeconds > 0, stream.initializationPath.hasSuffix(suffix) else {
      return nil
    }
    self.count = stream.segmentCount
    self.segmentSeconds = stream.segmentSeconds
    self.media = InstantProgressiveMediaStream(
      id: stream.id,
      pathPrefix: String(stream.initializationPath.dropLast(suffix.count)),
      format: stream.format
    )
    let lastIndexes = Self.lastIndexes(of: stream)
    self.pending = lastIndexes.lowerBound > 0 ? [Stretch(lower: 0, upper: lastIndexes.lowerBound)] : []
    guard record(rows, asked: Array(lastIndexes)) else { return nil }
  }

  /// Keeps the rows a read returned; false unless it returned the stream's row at every index asked for, at its own
  /// path (a missing row, or a writer that names its files another way).
  mutating func record(_ rows: [InstantProgressiveMediaSegmentRow], asked indexes: [Int]) -> Bool {
    var found: [Int: InstantProgressiveMediaSegmentRow] = [:]
    for row in rows where row.streamID == media.id.rawValue {
      found[row.index] = row
    }
    for index in indexes {
      guard let row = found[index], row.path == media.segmentPath(index) else { return false }
      known[index] = row.segment
    }
    return true
  }

  /// The indexes the stretches still need, to read together; empty once every segment can be placed. A stretch on the
  /// grid needs none, a short one is read whole, and a long one is split at `fanOut - 1` rows into stretches looked at
  /// next.
  mutating func nextReads() -> [Int] {
    var reads: [Int] = []
    var next: [Stretch] = []
    for stretch in pending {
      let span = stretch.upper - stretch.lower
      let drift = start(of: stretch.upper) - start(of: stretch.lower) - Double(span) * segmentSeconds
      guard abs(drift) > Self.tolerance, span > 1 else { continue }
      if span <= Self.pageSize {
        reads += (stretch.lower + 1)..<stretch.upper
        continue
      }
      let points = (1..<Self.fanOut).map { stretch.lower + span * $0 / Self.fanOut }
      reads += points
      next += zip([stretch.lower] + points, points + [stretch.upper]).map { Stretch(lower: $0, upper: $1) }
    }
    pending = next
    return reads
  }

  /// Every segment, once `nextReads()` is empty: the rows read as they are, the others placed by the grid from the row
  /// before them (or the stream's start), each ending where the next starts.
  var segments: [InstantProgressiveMediaSegment] {
    var listed: [InstantProgressiveMediaSegment] = []
    listed.reserveCapacity(count)
    var anchor = (index: 0, start: 0.0)
    for index in 0..<count {
      if let row = known[index] {
        anchor = (index, row.startSeconds)
        listed.append(row)
      } else {
        listed.append(
          InstantProgressiveMediaSegment(
            index: index,
            startSeconds: anchor.start + Double(index - anchor.index) * segmentSeconds,
            durationSeconds: segmentSeconds,
            byteCount: 0,
            path: media.segmentPath(index)
          )
        )
      }
    }
    // A player's timeline is the sum of the listed durations: back to back, it meets the stream's at every row read.
    for index in listed.indices.dropLast() where known[index] == nil || known[index + 1] == nil {
      listed[index].durationSeconds = listed[index + 1].startSeconds - listed[index].startSeconds
    }
    return listed
  }

  /// A read row's start; the stream starts at 0 (the writer's first segment).
  private func start(of index: Int) -> Double {
    known[index]?.startSeconds ?? 0
  }
}

extension InstantProgressiveMediaStream {
  /// The id `segmentID(_:)` gives the segment at `index` of the stream whose id is `streamID`.
  static func segmentID(streamID: String, index: Int) -> InstantID<InstantProgressiveMediaSegmentRow> {
    InstantProgressiveMediaStream(id: InstantID(rawValue: streamID), pathPrefix: "").segmentID(index)
  }
}
