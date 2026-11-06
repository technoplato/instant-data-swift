// Reading a progressive media stream: its rows as segments in order, and its files' URLs (#1012, ADR 0021).

import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import InstantSwiftData
import Testing

@Suite(
  .dependencies {
    $0.date.now = Date(timeIntervalSince1970: 1_000)
  }
)
struct InstantProgressiveMediaReaderTests {
  let stream = InstantProgressiveMediaStream(key: "recording-1/audio", pathPrefix: "media/recording-1/audio")

  @Test func aRefreshListsTheStoredSegmentsInOrder() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .recording, durations: [6, 6, 4])
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)

    let snapshot = try await reader.refresh()

    expectNoDifference(snapshot.stream?.state, .recording)
    expectNoDifference(
      snapshot.segments,
      [
        InstantProgressiveMediaSegment(
          index: 0, startSeconds: 0, durationSeconds: 6, byteCount: 100, path: stream.segmentPath(0)),
        InstantProgressiveMediaSegment(
          index: 1, startSeconds: 6, durationSeconds: 6, byteCount: 100, path: stream.segmentPath(1)),
        InstantProgressiveMediaSegment(
          index: 2, startSeconds: 12, durationSeconds: 4, byteCount: 100, path: stream.segmentPath(2)),
      ]
    )
    expectNoDifference(snapshot.isFinished, false)
  }

  /// A growing stream costs only its new rows: a refresh asks for the segments after the ones it already has.
  @Test func aRefreshReadsOnlyTheSegmentsItHasNotRead() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .recording, durations: [6, 6, 6])
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)
    _ = try await reader.refresh()
    source.store(state: .finished, durations: [6, 6, 6, 6, 2])

    let snapshot = try await reader.refresh()

    expectNoDifference(snapshot.segments.map(\.index), [0, 1, 2, 3, 4])
    expectNoDifference(snapshot.isFinished, true)
    expectNoDifference(source.segmentRequests, [0, 3])
  }

  /// A segment whose row has not arrived yet ends the listing there: a playlist never skips audio.
  @Test func aMissingRowEndsTheListingUntilItArrives() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .recording, durations: [6, 6, 6], missing: [1])
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)
    let first = try await reader.refresh()
    expectNoDifference(first.segments.map(\.index), [0])

    source.store(state: .recording, durations: [6, 6, 6])
    let second = try await reader.refresh()
    expectNoDifference(second.segments.map(\.index), [0, 1, 2])
  }

  @Test func aStreamWithNoRowYetHasNoSegments() async throws {
    let source = SourceDouble(stream: stream)
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)
    let snapshot = try await reader.refresh()
    expectNoDifference(snapshot.stream, nil)
    expectNoDifference(snapshot.segments, [])
  }

  // MARK: - A long stream lists in a few reads (#1916)

  /// A long stream whose segments sit on its grid lists from one read of its last rows, however long it is. Reading
  /// every row first, 500 a page and one page after another, kept a player of a 81-minute stream (811 segments) from its
  /// first sound until a busy app gave up on the playlist, and cost 16 reads for a 12 h 49 min one (7,695).
  @Test(arguments: [811, 1_768, 7_695])
  func aLongStreamOnItsGridListsFromItsLastRows(count: Int) async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .finished, durations: Self.take(count: count, last: 2.5))
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)

    let snapshot = try await reader.refresh()

    expectNoDifference(source.segmentRequests, [count - 64])
    expectNoDifference(source.rowsRead, 64)
    #expect(snapshot.isFinished)
    try expectListing(snapshot, matches: source.storedSegments, within: Self.frame)
  }

  /// A take that ends early, and an encoder that takes over from where it stopped, leave a short segment that moves every
  /// later start off the grid. Every such stream measured broke in its last two segments, which the last rows hold.
  @Test func aBreakInTheLastRowsListsFromThoseRows() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .finished, durations: Self.take(count: 1_003, last: 4.523) + [4.52])
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)

    let snapshot = try await reader.refresh()

    expectNoDifference(source.segmentRequests, [1_004 - 64])
    try expectListing(snapshot, matches: source.storedSegments, within: Self.frame)
    expectNoDifference(snapshot.segments[1_002], source.storedSegments[1_002].segment)
  }

  /// A stream continued after it stopped breaks where its first take ended, anywhere in it. The listing finds the short
  /// segment by splitting the stretch around it, so its reads grow with its breaks, not its length, and each segment
  /// starts where its row says, exactly at and after a break and within a frame elsewhere.
  @Test func aBreakFurtherBackIsFoundBySplittingTheStretchAroundIt() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .finished, durations: Self.take(count: 3_000, last: 2.1) + Self.take(count: 4_695, last: 4))
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)

    let snapshot = try await reader.refresh()

    // The last rows, then at most four rounds of seven split points, then one short page: never every row.
    #expect(source.rowsRead <= 64 + 4 * 7 + 64)
    #expect(source.segmentRequests.count <= 1 + 4 * 7 + 1)
    try expectListing(snapshot, matches: source.storedSegments, within: Self.frame)
    expectNoDifference(snapshot.segments[2_999], source.storedSegments[2_999].segment)
    expectNoDifference(snapshot.segments[3_000].startSeconds, source.storedSegments[3_000].startSeconds)
  }

  /// Several breaks, near the start, in the middle and before the last rows: each costs its own few reads.
  @Test func severalBreaksEachCostAFewReads() async throws {
    let source = SourceDouble(stream: stream)
    source.store(
      state: .finished,
      durations: Self.take(count: 100, last: 3) + Self.take(count: 2_000, last: 5) + Self.take(count: 3_000, last: 1)
        + Self.take(count: 2_595, last: 2)
    )
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)

    let snapshot = try await reader.refresh()

    #expect(source.rowsRead <= 64 + 3 * (4 * 7 + 64))
    try expectListing(snapshot, matches: source.storedSegments, within: Self.frame)
    for brokenAt in [99, 2_099, 5_099] {
      expectNoDifference(snapshot.segments[brokenAt], source.storedSegments[brokenAt].segment)
    }
  }

  /// A growing stream listed from its last rows still reads only its new rows on the next refresh.
  @Test func aLongGrowingStreamThenReadsOnlyItsNewRows() async throws {
    let source = SourceDouble(stream: stream)
    let durations = Self.take(count: 1_003, last: 6.016)
    source.store(state: .recording, durations: Array(durations.prefix(1_000)))
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)
    _ = try await reader.refresh()
    source.store(state: .recording, durations: durations)

    let snapshot = try await reader.refresh()

    expectNoDifference(source.segmentRequests, [1_000 - 64, 1_000])
    #expect(!snapshot.isFinished)
    try expectListing(snapshot, matches: source.storedSegments, within: Self.frame)
  }

  /// The last rows decide what the listing trusts: a gap among them, or a row whose path is not the stream's own, sends
  /// the reader back to reading every row in order, which ends the listing at a missing row.
  @Test func aGapInTheLastRowsFallsBackToReadingEveryRow() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .finished, durations: Self.take(count: 811, last: 2.5), missing: [800])
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)

    let snapshot = try await reader.refresh()

    expectNoDifference(source.segmentRequests, [811 - 64, 0, 500])
    expectNoDifference(snapshot.segments.map(\.index), Array(0..<800))
    #expect(!snapshot.isFinished)
  }

  /// A short stream is one page, read exactly as before.
  @Test func aShortStreamIsReadAsOnePage() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .finished, durations: Self.take(count: 64, last: 2.5))
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)

    let snapshot = try await reader.refresh()

    expectNoDifference(source.segmentRequests, [0])
    expectNoDifference(snapshot.segments, source.storedSegments.map(\.segment))
  }

  /// One AAC frame at the stream's 24 kHz: AVAssetWriter cuts a take at the first frame at or after each 6 s.
  static let frame = 1_024.0 / 24_000

  /// A take of `count` segments as AVAssetWriter cuts it: 141 and 140 frames (6.016 and 5.973 s, as stored streams
  /// measured, #1916), then a last segment of `last` seconds.
  static func take(count: Int, last: Double) -> [Double] {
    // The frame at or after k * 6 s: k * 144,000 samples over 1,024 a frame, rounded up, in integers.
    func cut(_ k: Int) -> Int { (k * 144_000 + 1_023) / 1_024 }
    return (0..<count).map { k in k == count - 1 ? last : Double(cut(k + 1) - cut(k)) * frame }
  }

  /// The listing is every stored segment in order, at its own path, back to back from 0 to the stream's end, each start
  /// within `tolerance` of the stored one.
  func expectListing(
    _ snapshot: InstantProgressiveMediaReader.Snapshot,
    matches stored: [InstantProgressiveMediaSegmentRow],
    within tolerance: Double,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) throws {
    let sourceLocation = SourceLocation(
      fileID: "\(fileID)", filePath: "\(filePath)", line: Int(line), column: Int(column)
    )
    let listed = snapshot.segments
    expectNoDifference(
      listed.map(\.index), stored.map(\.index), fileID: fileID, filePath: filePath, line: line, column: column
    )
    expectNoDifference(
      listed.map(\.path), stored.map(\.path), fileID: fileID, filePath: filePath, line: line, column: column
    )
    let end = try #require(stored.last?.segment.endSeconds, sourceLocation: sourceLocation)
    #expect(abs((listed.last?.endSeconds ?? 0) - end) < 1e-6, sourceLocation: sourceLocation)
    #expect(listed.first?.startSeconds == 0, sourceLocation: sourceLocation)
    for (segment, next) in zip(listed, listed.dropFirst()) {
      #expect(abs(segment.endSeconds - next.startSeconds) < 1e-6, sourceLocation: sourceLocation)
    }
    let worst = zip(listed, stored).map { abs($0.startSeconds - $1.startSeconds) }.max() ?? 0
    #expect(worst <= tolerance, "a listed start is \(worst) s from its row's", sourceLocation: sourceLocation)
  }

  /// URLs are read in pages, from the asked segment on, and kept: the next segments a player asks for are already known.
  @Test func urlsAreReadInPagesAndKept() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .recording, durations: Array(repeating: 6, count: 5))
    let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source, urlPageSize: 3)
    _ = try await reader.refresh()

    let urls = [
      try await reader.url(forSegment: 1),
      try await reader.url(forSegment: 2),
      try await reader.url(forSegment: 3),
      try await reader.initializationURL(),
    ]

    expectNoDifference(
      urls,
      [
        source.url(stream.segmentPath(1)),
        source.url(stream.segmentPath(2)),
        source.url(stream.segmentPath(3)),
        source.url(stream.initializationPath),
      ]
    )

    expectNoDifference(
      source.urlRequests,
      [
        [stream.segmentPath(1), stream.segmentPath(2), stream.segmentPath(3)],
        [stream.initializationPath],
      ]
    )
  }

  /// A file's URL is signed for 7 days from the start of its UTC day; a kept URL is read again after a day.
  @Test func aKeptURLIsReadAgainAfterADay() async throws {
    let source = SourceDouble(stream: stream)
    source.store(state: .recording, durations: [6])
    let now = LockIsolated(Date(timeIntervalSince1970: 1_000))
    // The clock is the reader's whole life's, not only its creation's: the suite's fixed date would win otherwise.
    try await withDependencies {
      $0.date = DateGenerator { now.value }
    } operation: {
      let reader = InstantProgressiveMediaReader(streamID: stream.id, source: source.source)
      _ = try await reader.refresh()
      _ = try await reader.url(forSegment: 0)
      now.setValue(Date(timeIntervalSince1970: 1_000 + 86_400 - 1))
      _ = try await reader.url(forSegment: 0)
      now.setValue(Date(timeIntervalSince1970: 1_000 + 86_400 + 1))
      _ = try await reader.url(forSegment: 0)
    }

    expectNoDifference(source.urlRequests.count, 2)
  }
}

/// Rows and URLs a reader reads, with a record of what it asked for.
private final class SourceDouble: Sendable {
  let stream: InstantProgressiveMediaStream
  private let state = LockIsolated(
    (
      row: InstantProgressiveMediaStreamRow?.none,
      segments: [InstantProgressiveMediaSegmentRow](),
      segmentRequests: [Int](),
      rowsRead: 0,
      urlRequests: [[String]]()
    )
  )

  init(stream: InstantProgressiveMediaStream) {
    self.stream = stream
  }

  /// Where each read of segment rows started, in the order the reads were asked for.
  var segmentRequests: [Int] { state.value.segmentRequests }
  /// How many segment rows the reads returned, all together.
  var rowsRead: Int { state.value.rowsRead }
  var storedSegments: [InstantProgressiveMediaSegmentRow] { state.value.segments }
  var urlRequests: [[String]] { state.value.urlRequests }

  func url(_ path: String) -> URL {
    URL(string: "https://storage.example/\(path)?signature=1")!
  }

  func store(state streamState: InstantProgressiveMediaState, durations: [Double], missing: Set<Int> = []) {
    var start = 0.0
    var segments: [InstantProgressiveMediaSegmentRow] = []
    for (index, duration) in durations.enumerated() {
      defer { start += duration }
      guard !missing.contains(index) else { continue }
      segments.append(
        InstantProgressiveMediaSegmentRow(
          id: stream.segmentID(index), ownerUserID: "owner", streamID: stream.id.rawValue, index: index,
          startSeconds: start, durationSeconds: duration, byteCount: 100, path: stream.segmentPath(index),
          createdAtMs: 1_000_000
        )
      )
    }
    let row = InstantProgressiveMediaStreamRow(
      id: stream.id, ownerUserID: "owner", codecs: "mp4a.40.2", sampleRate: 24_000, channelCount: 1,
      bitRate: 32_000, segmentSeconds: 6, initializationPath: stream.initializationPath, state: streamState,
      segmentCount: durations.count, durationSeconds: durations.reduce(0, +), createdAtMs: 1_000_000,
      updatedAtMs: 1_000_000
    )
    state.withValue { [segments] in
      $0.row = row
      $0.segments = segments
    }
  }

  var source: InstantProgressiveMediaReader.Source {
    InstantProgressiveMediaReader.Source(
      streamRow: { id in
        self.state.withValue { $0.row?.id == id ? $0.row : nil }
      },
      segments: { streamID, fromIndex, limit in
        self.state.withValue { state in
          state.segmentRequests.append(fromIndex)
          let page = Array(
            state.segments.filter { $0.streamID == streamID && $0.index >= fromIndex }.prefix(limit)
          )
          state.rowsRead += page.count
          return page
        }
      },
      fileURLs: { paths in
        self.state.withValue { $0.urlRequests.append(paths) }
        return Dictionary(uniqueKeysWithValues: paths.map { ($0, self.url($0)) })
      }
    )
  }
}
