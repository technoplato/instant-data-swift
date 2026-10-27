// The progressive media writer: segments spooled on this device, then stored and listed in order (#1012, ADR 0021).

import CustomDump
import Dependencies
import DependenciesTestSupport
import Foundation
import InstantSwiftData
import InstantSwiftDataCore
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
          .streamProgress(streamRow(.recording, segmentCount: 1, durationSeconds: 6)),
          .segment(segmentRow(0, startSeconds: 0, durationSeconds: 6, byteCount: 25_700)),
        ]),
        .upload(path: "media/recording-1/audio/000001.m4s", byteCount: 25_600, contentType: "audio/mp4"),
        .write([
          .streamProgress(streamRow(.recording, segmentCount: 2, durationSeconds: 12)),
          .segment(segmentRow(1, startSeconds: 6, durationSeconds: 6, byteCount: 25_600)),
        ]),
        .upload(path: "media/recording-1/audio/000002.m4s", byteCount: 19_000, contentType: "audio/mp4"),
        .write([
          .streamProgress(streamRow(.finished, segmentCount: 3, durationSeconds: 16.5)),
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
      .write([.streamProgress(streamRow(.finished, segmentCount: 1, durationSeconds: 6))])
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

  /// A row write that fails is tried again after the same backoff as an upload, and nothing after it moves first: a
  /// store that does not know the namespaces yet (before its first `init-ok` taught them) refuses the rows until it
  /// does, and delivery used to end there for good.
  @Test func aFailedRowWriteIsRetriedBeforeAnythingAfterIt() async throws {
    let storage = StorageDouble(network: .open, writeFailures: 2)
    let writer = try InstantProgressiveMediaWriter(
      stream: stream, ownerUserID: "owner", spool: spool, storage: storage.storage
    )
    try await writer.start(initialization: Data(count: 612))
    try await writer.append(Data(count: 100), durationSeconds: 6)
    try await writer.finish()

    try await writer.deliver()

    expectNoDifference(
      storage.events.map(\.label),
      [
        "upload init.mp4", "write stream failed", "write stream failed", "write stream",
        "upload 000000.m4s", "write stream+0",
      ]
    )
    expectNoDifference(storage.writtenStreamStates, [.recording, .finished])
    let failure = await writer.lastFailure
    #expect(failure == nil)
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
      return rows.compactMap(\.writtenStreamRow)
    }
    expectNoDifference(rows.count, 4)
    expectNoDifference(rows.map(\.updatedAtMs), rows.map(\.updatedAtMs).sorted())
    #expect(rows.allSatisfy { $0.updatedAtMs >= $0.createdAtMs })
  }

  /// #1253: a stream's row restated its 13 fields every segment where four change; on one device that was 59% of the
  /// fact records its store's log held while it recorded. The stream's first write creates the whole row; each later
  /// one carries its state, segment count, duration and update time, and the stored row is the same.
  @Test func aStreamsLaterWriteCarriesOnlyWhatChanges() async throws {
    let created = streamRow(.recording, segmentCount: 0, durationSeconds: 0)
    var progressed = streamRow(.recording, segmentCount: 7, durationSeconds: 42)
    progressed.updatedAtMs = 1_042_000
    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "progressive-media-progress-\(UUID().uuidString)",
        context: .test,
        initialAttributes: InstantProgressiveMediaStreamRow.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      try await db.transact([InstantProgressiveMediaRow.stream(created).mutation], id: "tx-stream-created")
      try await db.transact([InstantProgressiveMediaRow.streamProgress(progressed).mutation], id: "tx-stream-progress")

      let pending = await db.pendingMutations()
      let creation = try #require(pending.first { $0.id == "tx-stream-created" })
      let progress = try #require(pending.first { $0.id == "tx-stream-progress" })
      // The entity's identity and its 12 fields, then the identity and the four that change.
      expectNoDifference(creation.transaction.operations.count, 13)
      expectNoDifference(progress.transaction.operations.count, 5)
      expectNoDifference(
        Set(progress.transaction.operations.compactMap(\.insertedAttributeName)),
        ["id", "state", "segmentCount", "durationSeconds", "updatedAtMs"]
      )
      let stored = try await db.query(InstantProgressiveMediaStreamRow.query)
      expectNoDifference(stored, [progressed])
    }
  }

  /// #1253, measured: on the same store, a progress write's outbox body is smaller than the whole row restated, each
  /// written after another row so neither replaces the stream's unsent write. The pages each save wrote are printed,
  /// not asserted: the write meter counts the whole process, and other tests save in parallel.
  @Test func aProgressWriteSavesFewerPagesThanTheWholeRowRestated() async throws {
    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "progressive-media-pages-\(UUID().uuidString)",
        context: .test,
        initialAttributes: InstantProgressiveMediaStreamRow.instantAttributes
          + InstantProgressiveMediaSegmentRow.instantAttributes
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var db
      func pages(_ row: InstantProgressiveMediaRow, segment: Int, id: String) async throws -> Int {
        try await db.transact(
          [InstantProgressiveMediaRow.segment(segmentRow(segment, startSeconds: 0, durationSeconds: 6, byteCount: 100)).mutation],
          id: "\(id)-segment"
        )
        let before = InstantStorageWriteMeter.snapshot()
        try await db.transact([row.mutation], id: id)
        return InstantStorageWriteMeter.snapshot().subtracting(before).operations
          .filter { $0.key.hasPrefix("saveLocalMutation") }.values.reduce(0) { $0 + $1.pagesWritten }
      }
      try await db.transact(
        [InstantProgressiveMediaRow.stream(streamRow(.recording, segmentCount: 0, durationSeconds: 0)).mutation],
        id: "tx-created"
      )
      let restated = try await pages(
        .stream(streamRow(.recording, segmentCount: 1, durationSeconds: 6)), segment: 0, id: "tx-restated"
      )
      let progressed = try await pages(
        .streamProgress(streamRow(.recording, segmentCount: 2, durationSeconds: 12)), segment: 1, id: "tx-progressed"
      )
      let pending = await db.pendingMutations()
      let bodyBytes = { (id: String) in
        try JSONEncoder().encode(#require(pending.first { $0.id == id })).count
      }
      let restatedBody = try bodyBytes("tx-restated")
      let progressedBody = try bodyBytes("tx-progressed")
      print(
        "PROGRESSIVE-MEDIA #1253 saveLocalMutation pages restated=\(restated) progressed=\(progressed);"
          + " outbox body bytes restated=\(restatedBody) progressed=\(progressedBody)"
      )
      #expect(progressedBody * 2 < restatedBody)
    }
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
    case failedWrite([InstantProgressiveMediaRow])

    var label: String {
      switch self {
      case let .upload(path, _, _):
        "upload \(path.split(separator: "/").last!)"
      case let .failedUpload(path):
        "upload \(path.split(separator: "/").last!) failed"
      case let .write(rows):
        "write " + Self.names(rows)
      case let .failedWrite(rows):
        "write " + Self.names(rows) + " failed"
      }
    }

    static func names(_ rows: [InstantProgressiveMediaRow]) -> String {
      rows.map {
        switch $0 {
        case .stream, .streamProgress: "stream"
        case let .segment(row): "+\(row.index)"
        }
      }.joined()
    }

    var description: String { label }
  }

  private let state: LockIsolated<
    (events: [Event], failures: [String: Int], writeFailures: Int, uploaded: [String: Int])
  >
  private let refusedPrefixes: [String]
  private let gate: AsyncStream<Void>
  private let opener: AsyncStream<Void>.Continuation
  private let isOpen: LockIsolated<Bool>

  init(network: Network, failures: [String: Int] = [:], writeFailures: Int = 0, refusedPrefixes: [String] = []) {
    state = LockIsolated((events: [], failures: failures, writeFailures: writeFailures, uploaded: [:]))
    self.refusedPrefixes = refusedPrefixes
    (gate, opener) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    isOpen = LockIsolated(network == .open)
  }

  var events: [Event] { state.value.events }
  var writtenStreamStates: [InstantProgressiveMediaState] {
    events.flatMap { event -> [InstantProgressiveMediaState] in
      guard case let .write(rows) = event else { return [] }
      return rows.compactMap { $0.writtenStreamRow?.state }
    }
  }
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
        let failed = self.state.withValue { state -> Bool in
          if state.writeFailures > 0 {
            state.writeFailures -= 1
            state.events.append(.failedWrite(rows))
            return true
          }
          state.events.append(.write(rows))
          return false
        }
        if failed {
          throw InstantError(
            code: .validationFailed,
            operation: "transact",
            message: "Entity namespace 'progressiveMediaStreams' does not exist in the local schema.",
            recovery: "Declare the namespace."
          )
        }
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

extension InstantProgressiveMediaRow {
  /// The stream row a write carries, whole or as its progress.
  fileprivate var writtenStreamRow: InstantProgressiveMediaStreamRow? {
    switch self {
    case let .stream(row), let .streamProgress(row): row
    case .segment: nil
    }
  }
}

extension InstantTripleOperation {
  /// The name of the attribute an insert sets (`state` for `progressiveMediaStreams/state`), else nil.
  fileprivate var insertedAttributeName: String? {
    guard case let .insert(triple) = self else { return nil }
    return triple.attributeID.split(separator: "/").last.map(String.init)
  }
}
