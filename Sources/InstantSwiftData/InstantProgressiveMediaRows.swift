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

// MARK: - Schema

extension InstantProgressiveMediaStreamRow: InstantEntityModel {
  public static let instantNamespace = "progressiveMediaStreams"

  public static let ownerUserIDAttribute = InstantAttributePath<Self, String>("ownerUserID")
  public static let codecsAttribute = InstantAttributePath<Self, String>("codecs")
  public static let sampleRateAttribute = InstantAttributePath<Self, Int>("sampleRate")
  public static let channelCountAttribute = InstantAttributePath<Self, Int>("channelCount")
  public static let bitRateAttribute = InstantAttributePath<Self, Int>("bitRate")
  public static let segmentSecondsAttribute = InstantAttributePath<Self, Double>("segmentSeconds")
  public static let initializationPathAttribute = InstantAttributePath<Self, String>("initializationPath")
  public static let stateAttribute = InstantAttributePath<Self, String>("state")
  public static let segmentCountAttribute = InstantAttributePath<Self, Int>("segmentCount")
  public static let durationSecondsAttribute = InstantAttributePath<Self, Double>("durationSeconds")
  public static let createdAtMsAttribute = InstantAttributePath<Self, Double>("createdAtMs")
  public static let updatedAtMsAttribute = InstantAttributePath<Self, Double>("updatedAtMs")

  /// The attributes an app's schema declares for `progressiveMediaStreams` (ADR 0021 shows the TypeScript).
  public static let instantAttributes: [InstantAttribute] = [
    .primaryKey(namespace: instantNamespace),
    progressiveMediaAttribute(instantNamespace, "ownerUserID", .string, isIndexed: true),
    progressiveMediaAttribute(instantNamespace, "codecs", .string),
    progressiveMediaAttribute(instantNamespace, "sampleRate", .number),
    progressiveMediaAttribute(instantNamespace, "channelCount", .number),
    progressiveMediaAttribute(instantNamespace, "bitRate", .number),
    progressiveMediaAttribute(instantNamespace, "segmentSeconds", .number),
    progressiveMediaAttribute(instantNamespace, "initializationPath", .string),
    progressiveMediaAttribute(instantNamespace, "state", .string, isIndexed: true),
    progressiveMediaAttribute(instantNamespace, "segmentCount", .number),
    progressiveMediaAttribute(instantNamespace, "durationSeconds", .number),
    progressiveMediaAttribute(instantNamespace, "createdAtMs", .number, isIndexed: true),
    progressiveMediaAttribute(instantNamespace, "updatedAtMs", .number, isIndexed: true),
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id.lowercased())
    ownerUserID = try snapshot.progressiveMediaValue("ownerUserID")
    codecs = try snapshot.progressiveMediaValue("codecs")
    sampleRate = try snapshot.progressiveMediaValue("sampleRate")
    channelCount = try snapshot.progressiveMediaValue("channelCount")
    bitRate = try snapshot.progressiveMediaValue("bitRate")
    segmentSeconds = try snapshot.progressiveMediaValue("segmentSeconds")
    initializationPath = try snapshot.progressiveMediaValue("initializationPath")
    let rawState: String = try snapshot.progressiveMediaValue("state")
    guard let state = InstantProgressiveMediaState(rawValue: rawState) else {
      throw InstantError(
        code: .decodeFailed,
        operation: "decode progressive media stream",
        namespace: snapshot.namespace,
        path: "state",
        localID: snapshot.id,
        message: "Unknown progressive media state \"\(rawState)\".",
        recovery: "Write one of \(InstantProgressiveMediaState.allCases.map(\.rawValue))."
      )
    }
    self.state = state
    segmentCount = try snapshot.progressiveMediaValue("segmentCount")
    durationSeconds = try snapshot.progressiveMediaValue("durationSeconds")
    createdAtMs = try snapshot.progressiveMediaValue("createdAtMs")
    updatedAtMs = try snapshot.progressiveMediaValue("updatedAtMs")
  }

  /// The whole row: the first write creates it and every later one restates it, so a replayed write is harmless.
  public var upsertMutation: InstantMutation {
    Self.update(
      id: id,
      [
        Self.ownerUserIDAttribute.set(ownerUserID),
        Self.codecsAttribute.set(codecs),
        Self.sampleRateAttribute.set(sampleRate),
        Self.channelCountAttribute.set(channelCount),
        Self.bitRateAttribute.set(bitRate),
        Self.segmentSecondsAttribute.set(segmentSeconds),
        Self.initializationPathAttribute.set(initializationPath),
        Self.stateAttribute.set(state.rawValue),
        Self.segmentCountAttribute.set(segmentCount),
        Self.durationSecondsAttribute.set(durationSeconds),
        Self.createdAtMsAttribute.set(createdAtMs),
        Self.updatedAtMsAttribute.set(updatedAtMs),
      ]
    )
  }

  /// The format the row describes.
  public var format: InstantProgressiveMediaFormat {
    InstantProgressiveMediaFormat(
      codecs: codecs,
      sampleRate: sampleRate,
      channelCount: channelCount,
      bitRate: bitRate,
      segmentSeconds: segmentSeconds
    )
  }
}

extension InstantProgressiveMediaSegmentRow: InstantEntityModel {
  public static let instantNamespace = "progressiveMediaSegments"

  public static let ownerUserIDAttribute = InstantAttributePath<Self, String>("ownerUserID")
  public static let streamIDAttribute = InstantAttributePath<Self, String>("streamID")
  public static let indexAttribute = InstantAttributePath<Self, Int>("index")
  public static let startSecondsAttribute = InstantAttributePath<Self, Double>("startSeconds")
  public static let durationSecondsAttribute = InstantAttributePath<Self, Double>("durationSeconds")
  public static let byteCountAttribute = InstantAttributePath<Self, Int>("byteCount")
  public static let pathAttribute = InstantAttributePath<Self, String>("path")
  public static let createdAtMsAttribute = InstantAttributePath<Self, Double>("createdAtMs")

  /// The attributes an app's schema declares for `progressiveMediaSegments`: `streamID` and `index` are indexed, so a
  /// reader asks for one stream's segments in order.
  public static let instantAttributes: [InstantAttribute] = [
    .primaryKey(namespace: instantNamespace),
    progressiveMediaAttribute(instantNamespace, "ownerUserID", .string, isIndexed: true),
    progressiveMediaAttribute(instantNamespace, "streamID", .string, isIndexed: true),
    progressiveMediaAttribute(instantNamespace, "index", .number, isIndexed: true),
    progressiveMediaAttribute(instantNamespace, "startSeconds", .number),
    progressiveMediaAttribute(instantNamespace, "durationSeconds", .number),
    progressiveMediaAttribute(instantNamespace, "byteCount", .number),
    progressiveMediaAttribute(instantNamespace, "path", .string),
    progressiveMediaAttribute(instantNamespace, "createdAtMs", .number, isIndexed: true),
  ]

  public init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id.lowercased())
    ownerUserID = try snapshot.progressiveMediaValue("ownerUserID")
    streamID = try snapshot.progressiveMediaValue("streamID")
    index = try snapshot.progressiveMediaValue("index")
    startSeconds = try snapshot.progressiveMediaValue("startSeconds")
    durationSeconds = try snapshot.progressiveMediaValue("durationSeconds")
    byteCount = try snapshot.progressiveMediaValue("byteCount")
    path = try snapshot.progressiveMediaValue("path")
    createdAtMs = try snapshot.progressiveMediaValue("createdAtMs")
  }

  /// The whole row; a replayed write restates the same values.
  public var upsertMutation: InstantMutation {
    Self.update(
      id: id,
      [
        Self.ownerUserIDAttribute.set(ownerUserID),
        Self.streamIDAttribute.set(streamID),
        Self.indexAttribute.set(index),
        Self.startSecondsAttribute.set(startSeconds),
        Self.durationSecondsAttribute.set(durationSeconds),
        Self.byteCountAttribute.set(byteCount),
        Self.pathAttribute.set(path),
        Self.createdAtMsAttribute.set(createdAtMs),
      ]
    )
  }

  /// The segment the row lists.
  public var segment: InstantProgressiveMediaSegment {
    InstantProgressiveMediaSegment(
      index: index,
      startSeconds: startSeconds,
      durationSeconds: durationSeconds,
      byteCount: byteCount,
      path: path
    )
  }
}

extension InstantProgressiveMediaRow {
  /// The row's write.
  public var mutation: InstantMutation {
    switch self {
    case let .stream(row): row.upsertMutation
    case let .segment(row): row.upsertMutation
    }
  }
}

private func progressiveMediaAttribute(
  _ namespace: String,
  _ name: String,
  _ valueType: InstantValueType,
  isIndexed: Bool = false
) -> InstantAttribute {
  InstantAttribute(
    id: "\(namespace)/\(name)",
    namespace: namespace,
    name: name,
    valueType: valueType,
    isRequired: true,
    isIndexed: isIndexed
  )
}

extension InstantEntitySnapshot {
  fileprivate func progressiveMediaValue<Value: InstantValueDecodable>(_ path: String) throws -> Value {
    try Value.decodeInstantValue(
      values[path]?.first,
      namespace: namespace,
      path: path,
      localID: id,
      operation: "decode progressive media row"
    )
  }
}
