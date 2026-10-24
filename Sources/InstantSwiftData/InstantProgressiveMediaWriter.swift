// The progressive media writer: appends segments to the spool on this device, then stores them and writes their rows
// in order (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). Appends never wait for the server (ADR 0010's contract for writes); delivery
//   stores each file before its row, retries with a doubling delay that resets only after a success, and makes no
//   attempt while the device has no network, as the socket's reconnect does (`Reactor.js` `_scheduleReconnect`).
// - 2026-10-23: a stream row's updatedAtMs never moves back, whatever the device clock does (#1012): an app's rules may
//   refuse such an update, and with it the segment row in the same transaction.

import Dependencies
import Foundation

/// Appends a stream's segments on this device, and delivers them: each file stored at its path, then its row written.
///
/// Appending is a write to this device, like `transact`: it returns once the segment is in the spool, online or not.
/// ``deliver()`` does the network part, oldest first, and survives a relaunch because the spool is its only state:
///
/// ```swift
/// let writer = try InstantProgressiveMediaWriter(
///   stream: stream, ownerUserID: user.id, spool: spool, storage: .live(client)
/// )
/// try await writer.start(initialization: initializationSegment)
/// let delivery = Task { try await writer.deliver() }
/// try await writer.append(segment, durationSeconds: 6)
/// // ...
/// try await writer.finish()
/// try await delivery.value  // returns once every segment is stored and listed
/// ```
public actor InstantProgressiveMediaWriter {
  /// The writer's effects: where files and rows go, and when the network is there.
  public struct Storage: Sendable {
    /// Stores the file at `path`, replacing what the path held. Success waits for the server.
    public var upload: @Sendable (_ file: URL, _ path: String, _ contentType: String) async throws -> Void
    /// Writes rows in one transaction. Like `transact`, success means this device's store and outbox hold them.
    public var write: @Sendable (_ rows: [InstantProgressiveMediaRow]) async throws -> Void
    /// Returns once the device has a route to the network; at once when it has one.
    public var waitForNetwork: @Sendable () async throws -> Void

    public init(
      upload: @escaping @Sendable (_ file: URL, _ path: String, _ contentType: String) async throws -> Void,
      write: @escaping @Sendable (_ rows: [InstantProgressiveMediaRow]) async throws -> Void,
      waitForNetwork: @escaping @Sendable () async throws -> Void
    ) {
      self.upload = upload
      self.write = write
      self.waitForNetwork = waitForNetwork
    }

    /// Files through `uploadFile`, rows through `transact`, and no attempt while `networkPath` has no route.
    public static func live(
      _ client: InstantSwiftDataClient,
      networkPath: InstantNetworkPath = .system
    ) -> Self {
      Self(
        upload: { file, path, contentType in
          try await client.uploadFile(from: file, name: path, contentType: contentType)
        },
        write: { rows in
          try await client.transact(rows.map(\.mutation))
        },
        waitForNetwork: {
          try await networkPath.waitUntilSatisfied()
        }
      )
    }
  }

  /// The wait between attempts to store a file: 1 s, doubling to 60 s, and back to 1 s only after a success.
  public struct Backoff: Hashable, Sendable {
    public var initial: Duration
    public var maximum: Duration
    private var current: Duration?

    public init(initial: Duration = .seconds(1), maximum: Duration = .seconds(60)) {
      self.initial = initial
      self.maximum = maximum
    }

    public mutating func next() -> Duration {
      let delay = current.map { min($0 * 2, maximum) } ?? initial
      current = delay
      return delay
    }

    public mutating func reset() {
      current = nil
    }
  }

  /// Fragmented MP4, the initialization segment and every media segment alike.
  public static let contentType = "audio/mp4"

  public nonisolated let stream: InstantProgressiveMediaStream
  public nonisolated let ownerUserID: String
  private let spool: InstantProgressiveMediaSpool
  private let storage: Storage
  private var record: InstantProgressiveMediaSpool.Record?
  private var backoff = Backoff()
  private var isDelivering = false
  /// Why the newest attempt to store a file failed, while delivery retries it; nil after a success.
  public private(set) var lastFailure: String?
  /// ``deliver()`` waiting for an append or ``finish()``; the next one resumes it.
  private var waiter: CheckedContinuation<Void, Never>?
  /// An append or ``finish()`` that came while ``deliver()`` was busy: its next wait returns at once.
  private var hasNews = false

  @Dependency(\.continuousClock) private var clock
  @Dependency(\.date.now) private var now

  /// A writer for `stream`, resuming what the spool already holds for it.
  public init(
    stream: InstantProgressiveMediaStream,
    ownerUserID: String,
    spool: InstantProgressiveMediaSpool,
    storage: Storage
  ) throws {
    self.stream = stream
    self.ownerUserID = ownerUserID
    self.spool = spool
    self.storage = storage
    self.record = try spool.record(of: stream)
  }

  /// A writer for every stream the spool holds, each with the owner it was started for, to deliver what a previous
  /// launch left:
  ///
  /// ```swift
  /// for writer in try InstantProgressiveMediaWriter.resumable(in: spool, storage: .live(client)) {
  ///   Task { try await writer.deliver() }
  /// }
  /// ```
  ///
  /// A stream that was still recording stays open: its writer delivers what was appended and waits for more, or for
  /// ``finish()``.
  public static func resumable(
    in spool: InstantProgressiveMediaSpool,
    storage: Storage
  ) throws -> [InstantProgressiveMediaWriter] {
    try spool.records().map { record in
      try InstantProgressiveMediaWriter(
        stream: record.stream,
        ownerUserID: record.ownerUserID,
        spool: spool,
        storage: storage
      )
    }
  }

  /// The index the next appended segment takes.
  public var nextIndex: Int { record?.nextIndex ?? 0 }

  /// Where the next appended segment starts on the stream's timeline.
  public var appendedSeconds: Double { record?.appendedSeconds ?? 0 }

  /// Whether ``finish()`` was called.
  public var isFinished: Bool { record?.finished ?? false }

  /// Begins the stream with its initialization segment. A stream that already began keeps its first one: segments
  /// appended after a relaunch continue the same timeline.
  public func start(initialization: Data) throws {
    guard record == nil else { return }
    let record = InstantProgressiveMediaSpool.Record(
      stream: stream,
      ownerUserID: ownerUserID,
      createdAtMs: milliseconds(now),
      nextIndex: 0,
      appendedSeconds: 0,
      initializationStored: false,
      finished: false
    )
    try spool.begin(record, initialization: initialization)
    self.record = record
    announce()
  }

  /// Appends the next media segment to the spool and returns where it sits. It never waits for the network.
  @discardableResult
  public func append(_ segment: Data, durationSeconds: Double) throws -> InstantProgressiveMediaSegment {
    guard var record else { throw Self.notStarted }
    guard !record.finished else {
      throw InstantError(
        code: .validationFailed,
        operation: "append progressive media",
        localID: stream.id.rawValue,
        message: "The stream is finished.",
        recovery: "Append before calling finish()."
      )
    }
    let appended = InstantProgressiveMediaSegment(
      index: record.nextIndex,
      startSeconds: record.appendedSeconds,
      durationSeconds: durationSeconds,
      byteCount: segment.count,
      path: stream.segmentPath(record.nextIndex)
    )
    record.nextIndex += 1
    record.appendedSeconds += durationSeconds
    try spool.append(appended, data: segment, createdAtMs: milliseconds(now), to: record)
    self.record = record
    announce()
    return appended
  }

  /// Marks the stream finished: ``deliver()`` returns once its last segment is stored and listed.
  public func finish() throws {
    guard var record else { throw Self.notStarted }
    guard !record.finished else { return }
    record.finished = true
    try spool.save(record)
    self.record = record
    announce()
  }

  /// Stores the spooled files and writes their rows, oldest first, until the stream is finished and delivered.
  ///
  /// Success waits for the server, unlike ``append(_:durationSeconds:)``. A file that fails to store is tried again
  /// after ``Backoff``'s delay, and nothing after it moves first. While the device has no network no attempt is made.
  /// A refused file (`permissionRejected`) ends delivery with that error and leaves the spool as it is; other streams'
  /// writers are not affected. Cancelling the task stops delivery between steps; the spool keeps what is left.
  public func deliver() async throws {
    guard !isDelivering else {
      throw InstantError(
        code: .validationFailed,
        operation: "deliver progressive media",
        localID: stream.id.rawValue,
        message: "This writer is already delivering.",
        recovery: "Call deliver() from one task at a time."
      )
    }
    isDelivering = true
    defer { isDelivering = false }

    while true {
      try Task.checkCancellation()
      guard let record else {
        await waitForNews()
        continue
      }
      if !record.initializationStored {
        try await store(spool.initializationURL(stream), at: stream.initializationPath)
        try await storage.write([
          .stream(streamRow(.recording, segmentCount: 0, durationSeconds: 0, updatedAtMs: try nextStamp()))
        ])
        try markInitializationStored()
        continue
      }
      if let next = try spool.pending(of: stream).first {
        let segment = next.segment
        try await store(spool.segmentURL(stream, segment.index), at: segment.path)
        // Read after the upload: appends and `finish()` may have happened while it ran.
        let isLast = self.record?.finished == true && segment.index == (self.record?.nextIndex ?? 0) - 1
        try await storage.write([
          .stream(
            streamRow(
              isLast ? .finished : .recording,
              segmentCount: segment.index + 1,
              durationSeconds: segment.endSeconds,
              updatedAtMs: try nextStamp()
            )
          ),
          .segment(segmentRow(segment, createdAtMs: next.createdAtMs)),
        ])
        if isLast {
          try spool.remove(stream)
          return
        }
        try spool.removeSegment(segment.index, of: stream)
        continue
      }
      if record.finished {
        try await storage.write([
          .stream(
            streamRow(
              .finished,
              segmentCount: record.nextIndex,
              durationSeconds: record.appendedSeconds,
              updatedAtMs: try nextStamp()
            )
          )
        ])
        try spool.remove(stream)
        return
      }
      await waitForNews()
    }
  }

  private func announce() {
    if let waiter {
      self.waiter = nil
      waiter.resume()
    } else {
      hasNews = true
    }
  }

  /// Returns after the next append or ``finish()``, at once when one came since the last wait, or when cancelled.
  private func waitForNews() async {
    if hasNews {
      hasNews = false
      return
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        waiter = continuation
      }
    } onCancel: {
      Task { await self.stopWaiting() }
    }
  }

  private func stopWaiting() {
    guard let waiter else { return }
    self.waiter = nil
    waiter.resume()
  }

  private func store(_ file: URL, at path: String) async throws {
    while true {
      try Task.checkCancellation()
      try await storage.waitForNetwork()
      do {
        try await storage.upload(file, path, Self.contentType)
        backoff.reset()
        lastFailure = nil
        return
      } catch let error as InstantError where error.code == .permissionRejected {
        throw error
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        lastFailure = String(describing: error)
        try await clock.sleep(for: backoff.next())
      }
    }
  }

  private func markInitializationStored() throws {
    guard var record else { return }
    record.initializationStored = true
    try spool.save(record)
    try spool.removeInitialization(of: stream)
    self.record = record
  }

  /// The next stamp for the stream's row: never earlier than the last one written, nor than the stream's start.
  private func nextStamp() throws -> Double {
    guard var record else { return milliseconds(now) }
    let stamp = max(milliseconds(now), record.updatedAtMs ?? record.createdAtMs)
    record.updatedAtMs = stamp
    try spool.save(record)
    self.record = record
    return stamp
  }

  private func streamRow(
    _ state: InstantProgressiveMediaState,
    segmentCount: Int,
    durationSeconds: Double,
    updatedAtMs: Double
  ) -> InstantProgressiveMediaStreamRow {
    InstantProgressiveMediaStreamRow(
      id: stream.id,
      ownerUserID: ownerUserID,
      codecs: stream.format.codecs,
      sampleRate: stream.format.sampleRate,
      channelCount: stream.format.channelCount,
      bitRate: stream.format.bitRate,
      segmentSeconds: stream.format.segmentSeconds,
      initializationPath: stream.initializationPath,
      state: state,
      segmentCount: segmentCount,
      durationSeconds: durationSeconds,
      createdAtMs: record?.createdAtMs ?? updatedAtMs,
      updatedAtMs: updatedAtMs
    )
  }

  private func segmentRow(
    _ segment: InstantProgressiveMediaSegment,
    createdAtMs: Double
  ) -> InstantProgressiveMediaSegmentRow {
    InstantProgressiveMediaSegmentRow(
      id: stream.segmentID(segment.index),
      ownerUserID: ownerUserID,
      streamID: stream.id.rawValue,
      index: segment.index,
      startSeconds: segment.startSeconds,
      durationSeconds: segment.durationSeconds,
      byteCount: segment.byteCount,
      path: segment.path,
      createdAtMs: createdAtMs
    )
  }

  private func milliseconds(_ date: Date) -> Double {
    (date.timeIntervalSince1970 * 1_000).rounded()
  }

  private static let notStarted = InstantError(
    code: .validationFailed,
    operation: "append progressive media",
    message: "The stream has not started.",
    recovery: "Call start(initialization:) first."
  )
}
