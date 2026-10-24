// The progressive media writer: segments spooled on this device, then stored and listed in order (#1012, ADR 0021).

import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import InstantSwiftData
import Testing

@Suite(
  .dependencies {
    $0.continuousClock = ImmediateClock()
    $0.date.now = Date(timeIntervalSince1970: 1_000)
  }
)
struct InstantProgressiveMediaWriterTests {
  let stream = InstantProgressiveMediaStream(key: "recording-1/audio", pathPrefix: "media/recording-1/audio")
  let spool: InstantProgressiveMediaSpool

  init() throws {
    spool = InstantProgressiveMediaSpool(
      directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("progressive-media-tests-\(UUID().uuidString)", isDirectory: true)
    )
  }

  /// `append` is a write to this device, like `transact`: it returns with nothing stored on the server and no network.
  @Test func appendSpoolsOnThisDeviceAndNeverWaitsForTheNetwork() async throws {
    let storage = StorageDouble(network: .closed)
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    try await writer.start(initialization: Data(count: 612))
    let first = try await writer.append(Data(count: 25_700), durationSeconds: 6)
    let second = try await writer.append(Data(count: 25_600), durationSeconds: 5.99)

    expectNoDifference(
      [first, second],
      [
        InstantProgressiveMediaSegment(
          index: 0, startSeconds: 0, durationSeconds: 6, byteCount: 25_700,
          path: "media/recording-1/audio/000000.m4s"
        ),
        InstantProgressiveMediaSegment(
          index: 1, startSeconds: 6, durationSeconds: 5.99, byteCount: 25_600,
          path: "media/recording-1/audio/000001.m4s"
        ),
      ]
    )
    expectNoDifference(try spool.pendingSegments(of: stream).map(\.index), [0, 1])
    expectNoDifference(storage.events, [])
  }

  /// Each file is stored before its row is written, oldest first, so a row on the server means its bytes are there;
  /// the last segment's row marks the stream finished.
  @Test func deliverStoresEachFileThenWritesItsRowInOrder() async throws {
    let storage = StorageDouble(network: .open)
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    try await writer.start(initialization: Data(count: 612))
    try await writer.append(Data(count: 25_700), durationSeconds: 6)
    try await writer.append(Data(count: 25_600), durationSeconds: 6)
    try await writer.append(Data(count: 19_000), durationSeconds: 4.5)
    try await writer.finish()

    try await writer.deliver()

    expectNoDifference(
      storage.events,
      [
        .upload(path: "media/recording-1/audio/init.mp4", byteCount: 612, contentType: "audio/mp4"),
        .write([.stream(streamRow(.recording, segmentCount: 0, durationSeconds: 0))]),
        .upload(path: "media/recording-1/audio/000000.m4s", byteCount: 25_700, contentType: "audio/mp4"),
        .write([
          .stream(streamRow(.recording, segmentCount: 1, durationSeconds: 6)),
          .segment(segmentRow(0, startSeconds: 0, durationSeconds: 6, byteCount: 25_700)),
        ]),
        .upload(path: "media/recording-1/audio/000001.m4s", byteCount: 25_600, contentType: "audio/mp4"),
        .write([
          .stream(streamRow(.recording, segmentCount: 2, durationSeconds: 12)),
          .segment(segmentRow(1, startSeconds: 6, durationSeconds: 6, byteCount: 25_600)),
        ]),
        .upload(path: "media/recording-1/audio/000002.m4s", byteCount: 19_000, contentType: "audio/mp4"),
        .write([
          .stream(streamRow(.finished, segmentCount: 3, durationSeconds: 16.5)),
          .segment(segmentRow(2, startSeconds: 12, durationSeconds: 4.5, byteCount: 19_000)),
        ]),
      ]
    )
    expectNoDifference(try spool.streams(), [])
  }

  /// A stream finished after its last segment was already stored gets one more write: its finished row.
  @Test func finishingAfterTheLastSegmentWasStoredWritesTheFinishedRow() async throws {
    let storage = StorageDouble(network: .open)
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    try await writer.start(initialization: Data(count: 612))
    try await writer.append(Data(count: 100), durationSeconds: 6)
    let delivery = Task { try await writer.deliver() }
    try await storage.waitForEvents(count: 4)
    try await writer.finish()
    try await delivery.value

    expectNoDifference(
      storage.events.last,
      .write([.stream(streamRow(.finished, segmentCount: 1, durationSeconds: 6))])
    )
    expectNoDifference(storage.events.count, 5)
  }

  /// No attempt is made while the device has no network; the spool waits, and delivery starts when it returns.
  @Test func noUploadIsAttemptedWhileTheNetworkIsDown() async throws {
    let storage = StorageDouble(network: .closed)
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    try await writer.start(initialization: Data(count: 612))
    try await writer.append(Data(count: 100), durationSeconds: 6)
    try await writer.finish()
    let delivery = Task { try await writer.deliver() }
    await Task.megaYield()
    expectNoDifference(storage.events, [])

    storage.openNetwork()
    try await delivery.value
    expectNoDifference(storage.events.count, 4)
  }

  /// A failed upload is tried again, and nothing after it moves first: the row waits for its file.
  @Test func aFailedUploadIsRetriedBeforeAnythingAfterIt() async throws {
    let storage = StorageDouble(network: .open, failures: ["media/recording-1/audio/000000.m4s": 2])
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    try await writer.start(initialization: Data(count: 612))
    try await writer.append(Data(count: 100), durationSeconds: 6)
    try await writer.append(Data(count: 200), durationSeconds: 6)
    try await writer.finish()

    try await writer.deliver()

    expectNoDifference(
      storage.events.map(\.label),
      [
        "upload init.mp4", "write stream",
        "upload 000000.m4s failed", "upload 000000.m4s failed", "upload 000000.m4s", "write stream+0",
        "upload 000001.m4s", "write stream+1",
      ]
    )
  }

  /// The wait between attempts doubles to a ceiling, and goes back to the start only after an upload succeeds
  /// (upstream's reconnect delay likewise resets only on `init-ok`, `Reactor.js` `_scheduleReconnect`).
  @Test func theRetryDelayDoublesToItsCeilingAndResetsOnSuccess() {
    var backoff = InstantProgressiveMediaWriter.Backoff()
    expectNoDifference(
      (0..<9).map { _ in backoff.next() },
      ([1, 2, 4, 8, 16, 32, 60, 60, 60] as [Int]).map { Duration.seconds($0) }
    )
    backoff.reset()
    expectNoDifference(backoff.next(), .seconds(1))
  }

  /// A refused upload (permission) stops this stream's delivery and keeps its spool; another stream is not affected.
  @Test func aRefusedUploadStopsOnlyItsOwnStream() async throws {
    let refused = InstantProgressiveMediaStream(key: "recording-2/audio", pathPrefix: "media/recording-2/audio")
    let storage = StorageDouble(network: .open, refusedPrefixes: ["media/recording-2/"])
    let refusedWriter = try InstantProgressiveMediaWriter(
      stream: refused, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    for writer in [refusedWriter, writer] {
      try await writer.start(initialization: Data(count: 612))
      try await writer.append(Data(count: 100), durationSeconds: 6)
      try await writer.finish()
    }

    await #expect(throws: InstantError.self) { try await refusedWriter.deliver() }
    try await writer.deliver()

    expectNoDifference(try spool.streams().map(\.id), [refused.id])
    expectNoDifference(try spool.pendingSegments(of: refused).map(\.index), [0])
  }

  /// After a relaunch the spool is the whole state: a new writer continues the numbering and delivers what the old one
  /// left, in order.
  @Test func aNewWriterResumesTheSpoolAfterARelaunch() async throws {
    let closed = StorageDouble(network: .closed)
    do {
      let writer = try InstantProgressiveMediaWriter(
        stream: stream, ownerUserID: "owner", spool: spool, storage: closed.storage
      )
      try await writer.start(initialization: Data(count: 612))
      try await writer.append(Data(count: 100), durationSeconds: 6)
      try await writer.append(Data(count: 200), durationSeconds: 6)
    }
    expectNoDifference(try spool.streams(), [stream])

    let storage = StorageDouble(network: .open)
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    let (nextIndex, appendedSeconds) = (await writer.nextIndex, await writer.appendedSeconds)
    expectNoDifference(nextIndex, 2)
    expectNoDifference(appendedSeconds, 12)
    try await writer.start(initialization: Data(count: 999))
    let third = try await writer.append(Data(count: 300), durationSeconds: 3)
    try await writer.finish()
    try await writer.deliver()

    expectNoDifference(third.startSeconds, 12)
    expectNoDifference(
      storage.events.map(\.label),
      [
        "upload init.mp4", "write stream", "upload 000000.m4s", "write stream+0", "upload 000001.m4s",
        "write stream+1", "upload 000002.m4s", "write stream+2",
      ]
    )
    // The first initialization segment is the stream's; a second `start` keeps it.
    expectNoDifference(storage.uploadedByteCounts["media/recording-1/audio/init.mp4"], 612)
  }

  /// At launch an app finds every stream the spool still holds and delivers it, with the owner it was started for.
  @Test func writersResumeEveryStreamTheSpoolHolds() async throws {
    let other = InstantProgressiveMediaStream(key: "recording-2/audio", pathPrefix: "media/recording-2/audio")
    let closed = StorageDouble(network: .closed)
    for (stream, owner) in [(stream, "owner"), (other, "other-owner")] {
      let writer = try InstantProgressiveMediaWriter(
        stream: stream, ownerUserID: owner, spool: spool, storage: closed.storage
      )
      try await writer.start(initialization: Data(count: 612))
      try await writer.append(Data(count: 100), durationSeconds: 6)
      try await writer.finish()
    }

    let storage = StorageDouble(network: .open)
    let writers = try InstantProgressiveMediaWriter.resumable(in: spool, storage: storage.storage)
    for writer in writers { try await writer.deliver() }

    expectNoDifference(writers.map { $0.stream }.sorted { $0.pathPrefix < $1.pathPrefix }, [stream, other])
    expectNoDifference(writers.map { $0.ownerUserID }.sorted(), ["other-owner", "owner"])
    expectNoDifference(try spool.streams(), [])
    // Each stream: its initialization segment, its row, its one segment, and that segment's rows.
    expectNoDifference(storage.events.count, 8)
  }

  /// A device clock that steps back never makes the writer stamp a stream row earlier than its last one, or than the
  /// stream's start: an app's rules may refuse an update whose updatedAtMs moves back (the consuming app's generated
  /// rules do), and with it the segment row written in the same transaction, so the segment would never be listed.
  @Test func aClockThatStepsBackNeverStampsARowEarlier() async throws {
    let storage = StorageDouble(network: .open)
    let clock = LockIsolated(Date(timeIntervalSince1970: 1_000))
    try await withDependencies {
      // Each read of the clock is a second earlier than the one before.
      $0.date = DateGenerator {
        clock.withValue { now in
          defer { now = now.addingTimeInterval(-1) }
          return now
        }
      }
    } operation: {
      let writer = try InstantProgressiveMediaWriter(
        stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
      )
      try await writer.start(initialization: Data(count: 612))
      for _ in 0..<3 { try await writer.append(Data(count: 100), durationSeconds: 6) }
      try await writer.finish()
      try await writer.deliver()
    }

    let rows = storage.events.flatMap { event -> [InstantProgressiveMediaStreamRow] in
      guard case let .write(rows) = event else { return [] }
      return rows.compactMap { if case let .stream(row) = $0 { row } else { nil } }
    }
    expectNoDifference(rows.count, 4)
    expectNoDifference(rows.map(\.updatedAtMs), rows.map(\.updatedAtMs).sorted())
    #expect(rows.allSatisfy { $0.updatedAtMs >= $0.createdAtMs })
  }

  func streamRow(
    _ state: InstantProgressiveMediaState,
    segmentCount: Int,
    durationSeconds: Double
  ) -> InstantProgressiveMediaStreamRow {
    InstantProgressiveMediaStreamRow(
      id: stream.id,
      ownerUserID: "owner",
      codecs: "mp4a.40.2",
      sampleRate: 24_000,
      channelCount: 1,
      bitRate: 32_000,
      segmentSeconds: 6,
      initializationPath: "media/recording-1/audio/init.mp4",
      state: state,
      segmentCount: segmentCount,
      durationSeconds: durationSeconds,
      createdAtMs: 1_000_000,
      updatedAtMs: 1_000_000
    )
  }

  func segmentRow(
    _ index: Int,
    startSeconds: Double,
    durationSeconds: Double,
    byteCount: Int
  ) -> InstantProgressiveMediaSegmentRow {
    InstantProgressiveMediaSegmentRow(
      id: stream.segmentID(index),
      ownerUserID: "owner",
      streamID: stream.id.rawValue,
      index: index,
      startSeconds: startSeconds,
      durationSeconds: durationSeconds,
      byteCount: byteCount,
      path: stream.segmentPath(index),
      createdAtMs: 1_000_000
    )
  }
}

/// Storage that records what the writer asked of it, with a network that can be closed and uploads that can fail.
private final class StorageDouble: Sendable {
  enum Network { case open, closed }

  enum Event: Equatable, CustomStringConvertible {
    case upload(path: String, byteCount: Int, contentType: String)
    case failedUpload(path: String)
    case write([InstantProgressiveMediaRow])

    var label: String {
      switch self {
      case let .upload(path, _, _):
        "upload \(path.split(separator: "/").last!)"
      case let .failedUpload(path):
        "upload \(path.split(separator: "/").last!) failed"
      case let .write(rows):
        "write "
          + rows.map {
            switch $0 {
            case .stream: "stream"
            case let .segment(row): "+\(row.index)"
            }
          }.joined()
      }
    }

    var description: String { label }
  }

  private let state: LockIsolated<(events: [Event], failures: [String: Int], uploaded: [String: Int])>
  private let refusedPrefixes: [String]
  private let gate: AsyncStream<Void>
  private let opener: AsyncStream<Void>.Continuation
  private let isOpen: LockIsolated<Bool>

  init(network: Network, failures: [String: Int] = [:], refusedPrefixes: [String] = []) {
    state = LockIsolated((events: [], failures: failures, uploaded: [:]))
    self.refusedPrefixes = refusedPrefixes
    (gate, opener) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    isOpen = LockIsolated(network == .open)
  }

  var events: [Event] { state.value.events }
  var uploadedByteCounts: [String: Int] { state.value.uploaded }

  func openNetwork() {
    isOpen.setValue(true)
    opener.yield()
  }

  func waitForEvents(count: Int) async throws {
    while events.count < count {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
  }

  var storage: InstantProgressiveMediaWriter.Storage {
    InstantProgressiveMediaWriter.Storage(
      upload: { file, path, contentType in
        if self.refusedPrefixes.contains(where: path.hasPrefix) {
          throw InstantError(
            code: .permissionRejected, operation: "upload file", message: "refused", recovery: "none")
        }
        let byteCount = try Data(contentsOf: file).count
        let failed = self.state.withValue { state -> Bool in
          if let remaining = state.failures[path], remaining > 0 {
            state.failures[path] = remaining - 1
            state.events.append(.failedUpload(path: path))
            return true
          }
          state.events.append(.upload(path: path, byteCount: byteCount, contentType: contentType))
          state.uploaded[path] = state.uploaded[path] ?? byteCount
          return false
        }
        if failed {
          throw InstantError(
            code: .networkFailed, operation: "upload file", message: "offline", recovery: "retry")
        }
      },
      write: { rows in
        self.state.withValue { $0.events.append(.write(rows)) }
      },
      waitForNetwork: {
        guard !self.isOpen.value else { return }
        for await _ in self.gate {
          if self.isOpen.value { return }
        }
      }
    )
  }
}
