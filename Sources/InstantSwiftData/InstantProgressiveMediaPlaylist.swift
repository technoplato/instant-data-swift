// A progressive media stream as an HLS media playlist (RFC 8216), the form AVPlayer and browsers follow (#1012,
// ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012).

import Foundation

/// An HLS media playlist of a stream's fragmented MP4 segments.
///
/// While the stream records, the playlist is an `EVENT` playlist with no end, which a player reloads to follow the live
/// edge; once it is finished it is a `VOD` playlist that ends.
///
/// ```swift
/// let text = InstantProgressiveMediaPlaylist(
///   initializationURI: "init.mp4",
///   segments: [.init(uri: "000000.m4s", durationSeconds: 6)],
///   isFinished: false
/// ).text
/// ```
public struct InstantProgressiveMediaPlaylist: Hashable, Sendable {
  public struct Segment: Hashable, Sendable {
    public var uri: String
    public var durationSeconds: Double

    public init(uri: String, durationSeconds: Double) {
      self.uri = uri
      self.durationSeconds = durationSeconds
    }
  }

  public var initializationURI: String
  public var segments: [Segment]
  /// The sequence number of the first listed segment: its index in the stream.
  public var mediaSequence: Int
  public var isFinished: Bool

  public init(
    initializationURI: String,
    segments: [Segment],
    mediaSequence: Int = 0,
    isFinished: Bool
  ) {
    self.initializationURI = initializationURI
    self.segments = segments
    self.mediaSequence = mediaSequence
    self.isFinished = isFinished
  }

  public var targetDurationSeconds: Int { 0 }

  public var text: String { "" }
}
