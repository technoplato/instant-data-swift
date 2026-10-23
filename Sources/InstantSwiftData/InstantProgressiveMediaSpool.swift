// The on-device spool of progressive media not yet stored: the only state a writer keeps, so a relaunch resumes from
// it (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). Plain files, one directory per stream, so the spool needs no SQLite table and
//   never touches the library's store; every file is written whole (atomically) before the next step depends on it.

import Foundation

/// A directory of streams whose files wait to be stored.
///
/// Each stream has a directory named by its id:
///
/// ```
/// <directory>/<stream id>/stream.json      what the stream is and how far it has been appended
/// <directory>/<stream id>/init.mp4         the initialization segment, until it is stored
/// <directory>/<stream id>/000007.m4s       a media segment's bytes, until it is stored
/// <directory>/<stream id>/000007.json      its place on the timeline; written after the bytes, removed first
/// ```
///
/// A segment waits while both of its files exist. A crash between two steps leaves either a segment that is stored
/// again (its upload replaces the same path) or a stray file that the next read ignores and removes.
public struct InstantProgressiveMediaSpool: Sendable {
  public var directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  /// What the spool knows about one stream.
  struct Record: Codable, Hashable, Sendable {
    var stream: InstantProgressiveMediaStream
    var ownerUserID: String
    var createdAtMs: Double
    /// The index the next appended segment takes.
    var nextIndex: Int
    /// The end of the last appended segment, where the next one starts.
    var appendedSeconds: Double
    var initializationStored: Bool
    var finished: Bool
  }

  /// A waiting segment's place on the timeline, beside its bytes.
  private struct PendingSegment: Codable, Hashable, Sendable {
    var index: Int
    var startSeconds: Double
    var durationSeconds: Double
    var byteCount: Int
    var createdAtMs: Double
  }

  /// The streams with something left to store, oldest first.
  public func streams() throws -> [InstantProgressiveMediaStream] {
    try records().map(\.stream)
  }

  /// A stream's segments that wait to be stored, in index order.
  public func pendingSegments(of stream: InstantProgressiveMediaStream) throws -> [InstantProgressiveMediaSegment] {
    try pending(of: stream).map(\.segment)
  }

  // MARK: - What the writer uses

  func records() throws -> [Record] {
    guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
    let children = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    return try children.compactMap { child in
      let url = child.appendingPathComponent("stream.json")
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      return try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
    }
    .sorted { ($0.createdAtMs, $0.stream.id.rawValue) < ($1.createdAtMs, $1.stream.id.rawValue) }
  }

  /// The stream's record, reconciled with its waiting segments: a crash after a segment's files were written but
  /// before the record was, leaves the record one segment behind.
  func record(of stream: InstantProgressiveMediaStream) throws -> Record? {
    let url = recordURL(stream)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    var record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
    if let last = try pending(of: stream).last {
      record.nextIndex = max(record.nextIndex, last.segment.index + 1)
      record.appendedSeconds = max(record.appendedSeconds, last.segment.endSeconds)
    }
    return record
  }

  func begin(_ record: Record, initialization: Data) throws {
    try FileManager.default.createDirectory(at: streamDirectory(record.stream), withIntermediateDirectories: true)
    try initialization.write(to: initializationURL(record.stream), options: .atomic)
    try save(record)
  }

  func save(_ record: Record) throws {
    try JSONEncoder().encode(record).write(to: recordURL(record.stream), options: .atomic)
  }

  func append(
    _ segment: InstantProgressiveMediaSegment,
    data: Data,
    createdAtMs: Double,
    to record: Record
  ) throws {
    let stream = record.stream
    try data.write(to: segmentURL(stream, segment.index), options: .atomic)
    let pending = PendingSegment(
      index: segment.index,
      startSeconds: segment.startSeconds,
      durationSeconds: segment.durationSeconds,
      byteCount: segment.byteCount,
      createdAtMs: createdAtMs
    )
    try JSONEncoder().encode(pending).write(to: pendingURL(stream, segment.index), options: .atomic)
    try save(record)
  }

  /// Waiting segments with the time each was appended.
  func pending(
    of stream: InstantProgressiveMediaStream
  ) throws -> [(segment: InstantProgressiveMediaSegment, createdAtMs: Double)] {
    let folder = streamDirectory(stream)
    guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    var segments: [(segment: InstantProgressiveMediaSegment, createdAtMs: Double)] = []
    for name in names where name.hasSuffix(".json") && name != "stream.json" {
      let url = folder.appendingPathComponent(name)
      guard let pending = try? JSONDecoder().decode(PendingSegment.self, from: Data(contentsOf: url)) else {
        try? FileManager.default.removeItem(at: url)
        continue
      }
      guard FileManager.default.fileExists(atPath: segmentURL(stream, pending.index).path) else {
        // Its bytes are gone: it was stored, and the crash came between removing its two files.
        try? FileManager.default.removeItem(at: url)
        continue
      }
      segments.append(
        (
          InstantProgressiveMediaSegment(
            index: pending.index,
            startSeconds: pending.startSeconds,
            durationSeconds: pending.durationSeconds,
            byteCount: pending.byteCount,
            path: stream.segmentPath(pending.index)
          ),
          pending.createdAtMs
        )
      )
    }
    return segments.sorted { $0.segment.index < $1.segment.index }
  }

  /// Forgets a stored segment: its timeline file first, so a crash between the two leaves bytes nothing lists.
  func removeSegment(_ index: Int, of stream: InstantProgressiveMediaStream) throws {
    try removeIfPresent(pendingURL(stream, index))
    try removeIfPresent(segmentURL(stream, index))
  }

  func removeInitialization(of stream: InstantProgressiveMediaStream) throws {
    try removeIfPresent(initializationURL(stream))
  }

  /// Removes a stream that is stored to its end.
  func remove(_ stream: InstantProgressiveMediaStream) throws {
    try removeIfPresent(streamDirectory(stream))
  }

  func initializationURL(_ stream: InstantProgressiveMediaStream) -> URL {
    streamDirectory(stream).appendingPathComponent("init.mp4")
  }

  func segmentURL(_ stream: InstantProgressiveMediaStream, _ index: Int) -> URL {
    streamDirectory(stream).appendingPathComponent(Self.paddedName(index, "m4s"))
  }

  private func pendingURL(_ stream: InstantProgressiveMediaStream, _ index: Int) -> URL {
    streamDirectory(stream).appendingPathComponent(Self.paddedName(index, "json"))
  }

  private func recordURL(_ stream: InstantProgressiveMediaStream) -> URL {
    streamDirectory(stream).appendingPathComponent("stream.json")
  }

  private func streamDirectory(_ stream: InstantProgressiveMediaStream) -> URL {
    directory.appendingPathComponent(stream.id.rawValue, isDirectory: true)
  }

  private func removeIfPresent(_ url: URL) throws {
    do {
      try FileManager.default.removeItem(at: url)
    } catch CocoaError.fileNoSuchFile {
    }
  }

  private static func paddedName(_ index: Int, _ fileExtension: String) -> String {
    let digits = String(index)
    return "\(String(repeating: "0", count: max(0, 6 - digits.count)))\(digits).\(fileExtension)"
  }
}
