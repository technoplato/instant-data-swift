// The progressive media writer: appends segments to the spool on this device, then stores them and writes their rows
// in order (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012).

import Dependencies
import Foundation

/// Appends a stream's segments on this device and delivers them: each file stored at its path, then its row written.
public actor InstantProgressiveMediaWriter {
  /// The writer's effects: where files and rows go, and when the network is there.
  public struct Storage: Sendable {
    /// Stores the file at `path` (an upload; it waits for the server).
    public var upload: @Sendable (_ file: URL, _ path: String, _ contentType: String) async throws -> Void
    /// Writes rows (a `transact`; it never waits for the server).
    public var write: @Sendable (_ rows: [InstantProgressiveMediaRow]) async throws -> Void
    /// Returns once the device has a route to the network.
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
  }

  /// The wait between attempts to store a file.
  public struct Backoff: Hashable, Sendable {
    public init() {}

    public mutating func next() -> Duration { .zero }

    public mutating func reset() {}
  }

  public nonisolated let stream: InstantProgressiveMediaStream
  public nonisolated let ownerUserID: String
  private let spool: InstantProgressiveMediaSpool
  private let storage: Storage

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
  }

  /// A writer for every stream the spool holds, to deliver what a previous launch left.
  public static func resumable(
    in spool: InstantProgressiveMediaSpool,
    storage: Storage
  ) throws -> [InstantProgressiveMediaWriter] {
    []
  }

  public var nextIndex: Int { 0 }

  public var appendedSeconds: Double { 0 }

  public func start(initialization: Data) throws {
    throw Self.unimplemented
  }

  @discardableResult
  public func append(_ segment: Data, durationSeconds: Double) throws -> InstantProgressiveMediaSegment {
    throw Self.unimplemented
  }

  public func finish() throws {
    throw Self.unimplemented
  }

  public func deliver() async throws {
    throw Self.unimplemented
  }

  private static let unimplemented = InstantError(
    code: .implementationFailed,
    operation: "progressive media",
    message: "Not implemented yet (#1012).",
    recovery: "None."
  )
}
