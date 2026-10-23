// Plays a progressive media stream in AVPlayer: the playlist is built from the stream's rows on this device, and the
// player is sent to each file's storage URL as it asks for it (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012).

import Foundation
import InstantSwiftData

/// The resources of a stream's `instant-progressive-media:` URLs.
public enum InstantProgressiveMediaResource: Hashable, Sendable {
  case playlist
  case initialization
  case segment(Int)

  public static let scheme = "instant-progressive-media"

  public func url(streamID: InstantID<InstantProgressiveMediaStreamRow>) -> URL {
    URL(string: "\(Self.scheme)://unimplemented")!
  }

  public init?(url: URL, streamID: InstantID<InstantProgressiveMediaStreamRow>) {
    return nil
  }
}
