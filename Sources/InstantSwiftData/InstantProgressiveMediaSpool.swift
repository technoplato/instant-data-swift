// The on-device spool of progressive media not yet stored: the only state a writer keeps, so a relaunch resumes from
// it (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012).

import Foundation

/// A directory of streams whose segments wait to be stored.
public struct InstantProgressiveMediaSpool: Sendable {
  public var directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  /// The streams with something left to store, oldest first.
  public func streams() throws -> [InstantProgressiveMediaStream] {
    []
  }

  /// A stream's segments that wait to be stored, in index order.
  public func pendingSegments(of stream: InstantProgressiveMediaStream) throws -> [InstantProgressiveMediaSegment] {
    []
  }
}
