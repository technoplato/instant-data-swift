// Progressive media's identities and rows: what a stream's segments hold, where its files live, and the rows that list
// them (#1012, ADR 0021).
//
// History:
// - 2026-10-23: first version (#1012). A stream's files are `$files` objects named by path, and its rows are written
//   only after their bytes are stored, so a row on the server means its file is there.

import Foundation

#if canImport(CryptoKit)
  import CryptoKit
#else
  import Crypto
#endif

/// What a progressive media stream's segments hold, and how long each one aims to be.
///
/// ```swift
/// let format = InstantProgressiveMediaFormat.speech
/// ```
public struct InstantProgressiveMediaFormat: Codable, Hashable, Sendable {
  /// The codec as RFC 6381 names it in a `codecs` parameter: `mp4a.40.2` is AAC-LC.
  public var codecs: String
  public var sampleRate: Int
  public var channelCount: Int
  /// The encoder's target, in bits per second.
  public var bitRate: Int
  /// The length the segmenter cuts at; the last segment of a stream may be shorter.
  public var segmentSeconds: Double

  public init(codecs: String, sampleRate: Int, channelCount: Int, bitRate: Int, segmentSeconds: Double) {
    self.codecs = codecs
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.bitRate = bitRate
    self.segmentSeconds = segmentSeconds
  }

  /// AAC-LC, mono, 24 kHz, 32 kbps, in 6 s segments: ADR 0021's measured choice for speech. 242.8 KB a minute,
  /// 23.7 times smaller than 48 kHz 16-bit PCM, wideband PESQ 4.32, and every player measured plays it.
  public static let speech = Self(
    codecs: "mp4a.40.2",
    sampleRate: 24_000,
    channelCount: 1,
    bitRate: 32_000,
    segmentSeconds: 6
  )
}

/// Whether a stream can still grow.
public enum InstantProgressiveMediaState: String, Codable, Hashable, Sendable, CaseIterable {
  /// Segments may still be appended: a player follows it as a live (EVENT) playlist.
  case recording
  /// Every segment is listed: a player plays it as a finished (VOD) playlist.
  case finished
}

/// A progressive media stream: its row's id, the storage prefix its files live under, and its format.
///
/// The id comes from a key the app chooses, so every device and every relaunch names the same stream the same way:
///
/// ```swift
/// let stream = InstantProgressiveMediaStream(
///   key: "recording/\(recording.id)/audio",
///   pathPrefix: "recordings/\(recording.id)/audio"
/// )
/// ```
public struct InstantProgressiveMediaStream: Codable, Hashable, Sendable {
  public var id: InstantID<InstantProgressiveMediaStreamRow>
  /// Where the stream's files are stored: `<pathPrefix>/init.mp4`, then `<pathPrefix>/000000.m4s` and on.
  public var pathPrefix: String
  public var format: InstantProgressiveMediaFormat

  public init(key: String, pathPrefix: String, format: InstantProgressiveMediaFormat = .speech) {
    self.init(
      id: InstantID(rawValue: Self.derivedID("instant-progressive-media-stream:\(key)")),
      pathPrefix: pathPrefix,
      format: format
    )
  }

  public init(
    id: InstantID<InstantProgressiveMediaStreamRow>,
    pathPrefix: String,
    format: InstantProgressiveMediaFormat = .speech
  ) {
    self.id = id
    self.pathPrefix = pathPrefix
    self.format = format
  }

  /// The initialization segment's storage path.
  public var initializationPath: String { "\(pathPrefix)/init.mp4" }

  /// A media segment's storage path: its index, zero-padded to six digits so a listing sorts in order.
  public func segmentPath(_ index: Int) -> String {
    let digits = String(index)
    return "\(pathPrefix)/\(String(repeating: "0", count: max(0, 6 - digits.count)))\(digits).m4s"
  }

  /// A segment row's id: the same stream and index always name the same row, so a replayed write lands on it.
  public func segmentID(_ index: Int) -> InstantID<InstantProgressiveMediaSegmentRow> {
    InstantID(rawValue: Self.derivedID("instant-progressive-media-segment:\(id.rawValue):\(index)"))
  }

  /// A version 4 shaped UUID from the SHA-256 of `name`: Instant ids are UUIDs, and these must not depend on a clock
  /// or a random source.
  static func derivedID(_ name: String) -> String {
    var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
    bytes[6] = (bytes[6] & 0x0F) | 0x40
    bytes[8] = (bytes[8] & 0x3F) | 0x80
    let uuid = UUID(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
      )
    )
    return uuid.uuidString.lowercased()
  }
}

/// One segment of a stream: where it sits on the stream's timeline and where its file is stored.
public struct InstantProgressiveMediaSegment: Codable, Hashable, Sendable {
  public var index: Int
  public var startSeconds: Double
  public var durationSeconds: Double
  public var byteCount: Int
  public var path: String

  public init(index: Int, startSeconds: Double, durationSeconds: Double, byteCount: Int, path: String) {
    self.index = index
    self.startSeconds = startSeconds
    self.durationSeconds = durationSeconds
    self.byteCount = byteCount
    self.path = path
  }

  public var endSeconds: Double { startSeconds + durationSeconds }
}

/// A row the writer stores: the stream's own row, or one segment's.
public enum InstantProgressiveMediaRow: Hashable, Sendable {
  case stream(InstantProgressiveMediaStreamRow)
  case segment(InstantProgressiveMediaSegmentRow)
}

/// A stream's row in `progressiveMediaStreams`: its format, its initialization segment, and how far it has been stored.
///
/// The app declares the namespace in its schema (ADR 0001: applications own their schema) with the attributes in
/// ``instantAttributes``, and its rules decide who reads it; ``ownerUserID`` is there for those rules.
public struct InstantProgressiveMediaStreamRow: Hashable, Sendable {
  public var id: InstantID<Self>
  public var ownerUserID: String
  public var codecs: String
  public var sampleRate: Int
  public var channelCount: Int
  public var bitRate: Int
  public var segmentSeconds: Double
  public var initializationPath: String
  public var state: InstantProgressiveMediaState
  /// How many segments are stored and listed: indexes `0..<segmentCount`.
  public var segmentCount: Int
  /// The end of the last listed segment.
  public var durationSeconds: Double
  public var createdAtMs: Double
  public var updatedAtMs: Double

  public init(
    id: InstantID<Self>,
    ownerUserID: String,
    codecs: String,
    sampleRate: Int,
    channelCount: Int,
    bitRate: Int,
    segmentSeconds: Double,
    initializationPath: String,
    state: InstantProgressiveMediaState,
    segmentCount: Int,
    durationSeconds: Double,
    createdAtMs: Double,
    updatedAtMs: Double
  ) {
    self.id = id
    self.ownerUserID = ownerUserID
    self.codecs = codecs
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.bitRate = bitRate
    self.segmentSeconds = segmentSeconds
    self.initializationPath = initializationPath
    self.state = state
    self.segmentCount = segmentCount
    self.durationSeconds = durationSeconds
    self.createdAtMs = createdAtMs
    self.updatedAtMs = updatedAtMs
  }
}

/// One segment's row in `progressiveMediaSegments`, written once its file is stored.
public struct InstantProgressiveMediaSegmentRow: Hashable, Sendable {
  public var id: InstantID<Self>
  public var ownerUserID: String
  /// The stream row's id.
  public var streamID: String
  public var index: Int
  public var startSeconds: Double
  public var durationSeconds: Double
  public var byteCount: Int
  public var path: String
  public var createdAtMs: Double

  public init(
    id: InstantID<Self>,
    ownerUserID: String,
    streamID: String,
    index: Int,
    startSeconds: Double,
    durationSeconds: Double,
    byteCount: Int,
    path: String,
    createdAtMs: Double
  ) {
    self.id = id
    self.ownerUserID = ownerUserID
    self.streamID = streamID
    self.index = index
    self.startSeconds = startSeconds
    self.durationSeconds = durationSeconds
    self.byteCount = byteCount
    self.path = path
    self.createdAtMs = createdAtMs
  }
}
