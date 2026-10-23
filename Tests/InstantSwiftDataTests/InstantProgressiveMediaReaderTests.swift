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
      urlRequests: [[String]]()
    )
  )

  init(stream: InstantProgressiveMediaStream) {
    self.stream = stream
  }

  var segmentRequests: [Int] { state.value.segmentRequests }
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
          return Array(
            state.segments.filter { $0.streamID == streamID && $0.index >= fromIndex }.prefix(limit)
          )
        }
      },
      fileURLs: { paths in
        self.state.withValue { $0.urlRequests.append(paths) }
        return Dictionary(uniqueKeysWithValues: paths.map { ($0, self.url($0)) })
      }
    )
  }
}
