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

  /// The longest segment rounded to the nearest second, and at least 1 (RFC 8216 4.3.3.1). Rounding up instead would
  /// add three seconds to a live player's hold-back, which is three target durations (measured 2026-10-23, #1012).
  public var targetDurationSeconds: Int {
    let longest = segments.lazy.map(\.durationSeconds).max() ?? 0
    return max(1, Int(longest.rounded(.toNearestOrAwayFromZero)))
  }

  /// The playlist's text. A window that starts past the stream's first segment carries no playlist type: an `EVENT`
  /// playlist may only grow at its end.
  public var text: String {
    var lines = [
      "#EXTM3U",
      "#EXT-X-VERSION:7",
      "#EXT-X-TARGETDURATION:\(targetDurationSeconds)",
      "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)",
    ]
    if isFinished {
      lines.append("#EXT-X-PLAYLIST-TYPE:VOD")
    } else if mediaSequence == 0 {
      lines.append("#EXT-X-PLAYLIST-TYPE:EVENT")
    }
    lines.append("#EXT-X-INDEPENDENT-SEGMENTS")
    lines.append("#EXT-X-MAP:URI=\"\(initializationURI)\"")
    for segment in segments {
      lines.append("#EXTINF:\(String(format: "%.5f", segment.durationSeconds)),")
      lines.append(segment.uri)
    }
    if isFinished {
      lines.append("#EXT-X-ENDLIST")
    }
    return lines.joined(separator: "\n") + "\n"
  }
}
