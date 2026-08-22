import Foundation

/// Media category carried by a typed Instant stream frame.
public enum InstantMediaStreamKind: String, Codable, Hashable, Sendable {
  case audio
  case video
}

/// Stable flags carried with each media frame.
public struct InstantMediaStreamFrameFlags: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let keyFrame = Self(rawValue: 1 << 0)
  public static let discontinuity = Self(rawValue: 1 << 1)
  public static let endOfSegment = Self(rawValue: 1 << 2)
}

/// Typed frame contract shared by audio and video streams.
public protocol InstantMediaStreamFrame: Codable, Hashable, Sendable {
  static var mediaKind: InstantMediaStreamKind { get }

  var sequence: Int64 { get }
  var presentationTimeMicroseconds: Int64 { get }
  var durationMicroseconds: Int64 { get }
  var flags: InstantMediaStreamFrameFlags { get }
  var payload: Data { get }

  init(
    sequence: Int64,
    presentationTimeMicroseconds: Int64,
    durationMicroseconds: Int64,
    flags: InstantMediaStreamFrameFlags,
    payload: Data
  )
}

public struct InstantAudioFrame: InstantMediaStreamFrame {
  public static let mediaKind: InstantMediaStreamKind = .audio

  public var sequence: Int64
  public var presentationTimeMicroseconds: Int64
  public var durationMicroseconds: Int64
  public var flags: InstantMediaStreamFrameFlags
  public var payload: Data

  public init(
    sequence: Int64,
    presentationTimeMicroseconds: Int64,
    durationMicroseconds: Int64,
    flags: InstantMediaStreamFrameFlags = [],
    payload: Data
  ) {
    self.sequence = sequence
    self.presentationTimeMicroseconds = presentationTimeMicroseconds
    self.durationMicroseconds = durationMicroseconds
    self.flags = flags
    self.payload = payload
  }
}

public struct InstantVideoFrame: InstantMediaStreamFrame {
  public static let mediaKind: InstantMediaStreamKind = .video

  public var sequence: Int64
  public var presentationTimeMicroseconds: Int64
  public var durationMicroseconds: Int64
  public var flags: InstantMediaStreamFrameFlags
  public var payload: Data

  public init(
    sequence: Int64,
    presentationTimeMicroseconds: Int64,
    durationMicroseconds: Int64,
    flags: InstantMediaStreamFrameFlags = [],
    payload: Data
  ) {
    self.sequence = sequence
    self.presentationTimeMicroseconds = presentationTimeMicroseconds
    self.durationMicroseconds = durationMicroseconds
    self.flags = flags
    self.payload = payload
  }
}

public enum InstantAudioSampleFormat: String, Codable, Hashable, Sendable {
  case int16
  case int24
  case int32
  case float32
}

/// Inspectable audio format attached to an audio stream descriptor.
public struct InstantAudioStreamFormat: Codable, Hashable, Sendable {
  public var codec: String
  public var sampleRate: Int
  public var channels: Int
  public var sampleFormat: InstantAudioSampleFormat?

  public init(
    codec: String,
    sampleRate: Int,
    channels: Int,
    sampleFormat: InstantAudioSampleFormat? = nil
  ) {
    self.codec = codec
    self.sampleRate = sampleRate
    self.channels = channels
    self.sampleFormat = sampleFormat
  }

  public static func pcm(
    sampleRate: Int,
    channels: Int,
    sampleFormat: InstantAudioSampleFormat = .int16
  ) -> Self {
    Self(
      codec: "pcm",
      sampleRate: sampleRate,
      channels: channels,
      sampleFormat: sampleFormat
    )
  }

  public static func voice(
    sampleRate: Int = 48_000,
    channels: Int = 1
  ) -> Self {
    .pcm(sampleRate: sampleRate, channels: channels, sampleFormat: .int16)
  }

  public var identifier: String {
    [
      "audio",
      codec.lowercased(),
      String(sampleRate),
      String(channels),
      sampleFormat?.rawValue ?? "encoded",
    ].joined(separator: "/")
  }
}

/// Inspectable encoded-video format attached to a video stream descriptor.
public struct InstantVideoStreamFormat: Codable, Hashable, Sendable {
  public var codec: String
  public var width: Int
  public var height: Int
  public var frameRate: Double
  public var keyFrameInterval: Int

  public init(
    codec: String,
    width: Int,
    height: Int,
    frameRate: Double,
    keyFrameInterval: Int
  ) {
    self.codec = codec
    self.width = width
    self.height = height
    self.frameRate = frameRate
    self.keyFrameInterval = keyFrameInterval
  }

  public static func h264(
    width: Int,
    height: Int,
    frameRate: Double,
    keyFrameInterval: Int = 60
  ) -> Self {
    Self(
      codec: "h264",
      width: width,
      height: height,
      frameRate: frameRate,
      keyFrameInterval: keyFrameInterval
    )
  }

  public var identifier: String {
    [
      "video",
      codec.lowercased(),
      "\(width)x\(height)",
      String(format: "%.3f", frameRate),
      String(keyFrameInterval),
    ].joined(separator: "/")
  }
}

public enum InstantMediaStreamFrameError: Error, Equatable, Sendable {
  case invalidEnvelopeVersion(Int)
  case mediaKindMismatch(expected: InstantMediaStreamKind, actual: InstantMediaStreamKind)
  case formatMismatch(expected: String, actual: String)
  case sequenceMismatch(expected: Int64, actual: Int64)
  case invalidTiming
  case frameExceedsMaximum(actualBytes: Int, maximumBytes: Int)
  case malformedEnvelope(String)
}

/// Newline-delimited, one-frame-at-a-time wire envelope.
///
/// The payload is encoded by `Data`'s standard Base64 `Codable` representation.
/// A decoder retains only an incomplete trailing line, never a complete stream.
public struct InstantMediaStreamFrameCodec<Frame: InstantMediaStreamFrame>: Sendable {
  public static var envelopeVersion: Int { 1 }

  public var formatIdentifier: String
  public var maximumFrameBytes: Int
  public var requiresContiguousSequence: Bool

  public init(
    formatIdentifier: String,
    maximumFrameBytes: Int = 256 * 1_024,
    requiresContiguousSequence: Bool = true
  ) {
    self.formatIdentifier = formatIdentifier
    self.maximumFrameBytes = maximumFrameBytes
    self.requiresContiguousSequence = requiresContiguousSequence
  }

  public func encode(_ frame: Frame) throws -> String {
    guard frame.sequence >= 0,
      frame.presentationTimeMicroseconds >= 0,
      frame.durationMicroseconds >= 0
    else {
      throw InstantMediaStreamFrameError.invalidTiming
    }
    guard frame.payload.count <= maximumFrameBytes else {
      throw InstantMediaStreamFrameError.frameExceedsMaximum(
        actualBytes: frame.payload.count,
        maximumBytes: maximumFrameBytes
      )
    }

    let envelope = Envelope(
      version: Self.envelopeVersion,
      kind: Frame.mediaKind,
      format: formatIdentifier,
      sequence: frame.sequence,
      presentationTimeMicroseconds: frame.presentationTimeMicroseconds,
      durationMicroseconds: frame.durationMicroseconds,
      flags: frame.flags,
      payload: frame.payload
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(envelope)
    return String(decoding: data, as: UTF8.self) + "\n"
  }

  public func makeDecoder(
    expectedSequence: Int64? = nil,
    maximumBufferedBytes: Int? = nil
  ) -> InstantMediaStreamFrameDecoder<Frame> {
    InstantMediaStreamFrameDecoder(
      formatIdentifier: formatIdentifier,
      maximumFrameBytes: maximumFrameBytes,
      maximumBufferedBytes: maximumBufferedBytes ?? maximumFrameBytes * 2 + 4_096,
      requiresContiguousSequence: requiresContiguousSequence,
      expectedSequence: expectedSequence
    )
  }

  fileprivate struct Envelope: Codable, Sendable {
    var version: Int
    var kind: InstantMediaStreamKind
    var format: String
    var sequence: Int64
    var presentationTimeMicroseconds: Int64
    var durationMicroseconds: Int64
    var flags: InstantMediaStreamFrameFlags
    var payload: Data
  }
}

public struct InstantMediaStreamFrameDecoder<Frame: InstantMediaStreamFrame>: Sendable {
  private let formatIdentifier: String
  private let maximumFrameBytes: Int
  private let maximumBufferedBytes: Int
  private let requiresContiguousSequence: Bool
  private var expectedSequence: Int64?
  private var buffered = Data()

  fileprivate init(
    formatIdentifier: String,
    maximumFrameBytes: Int,
    maximumBufferedBytes: Int,
    requiresContiguousSequence: Bool,
    expectedSequence: Int64?
  ) {
    self.formatIdentifier = formatIdentifier
    self.maximumFrameBytes = maximumFrameBytes
    self.maximumBufferedBytes = maximumBufferedBytes
    self.requiresContiguousSequence = requiresContiguousSequence
    self.expectedSequence = expectedSequence
  }

  public var bufferedByteCount: Int { buffered.count }
  public var nextExpectedSequence: Int64? { expectedSequence }

  public mutating func append(_ content: String) throws -> [Frame] {
    try append(Data(content.utf8))
  }

  public mutating func append(_ bytes: Data) throws -> [Frame] {
    buffered.append(bytes)
    guard buffered.count <= maximumBufferedBytes else {
      throw InstantMediaStreamFrameError.frameExceedsMaximum(
        actualBytes: buffered.count,
        maximumBytes: maximumBufferedBytes
      )
    }

    var frames: [Frame] = []
    while let newline = buffered.firstIndex(of: 0x0A) {
      let line = Data(buffered[..<newline])
      buffered.removeSubrange(...newline)
      guard !line.isEmpty else { continue }

      let envelope: InstantMediaStreamFrameCodec<Frame>.Envelope
      do {
        envelope = try JSONDecoder().decode(
          InstantMediaStreamFrameCodec<Frame>.Envelope.self,
          from: line
        )
      } catch {
        throw InstantMediaStreamFrameError.malformedEnvelope(String(describing: error))
      }

      guard envelope.version == InstantMediaStreamFrameCodec<Frame>.envelopeVersion else {
        throw InstantMediaStreamFrameError.invalidEnvelopeVersion(envelope.version)
      }
      guard envelope.kind == Frame.mediaKind else {
        throw InstantMediaStreamFrameError.mediaKindMismatch(
          expected: Frame.mediaKind,
          actual: envelope.kind
        )
      }
      guard envelope.format == formatIdentifier else {
        throw InstantMediaStreamFrameError.formatMismatch(
          expected: formatIdentifier,
          actual: envelope.format
        )
      }
      guard envelope.payload.count <= maximumFrameBytes else {
        throw InstantMediaStreamFrameError.frameExceedsMaximum(
          actualBytes: envelope.payload.count,
          maximumBytes: maximumFrameBytes
        )
      }
      guard envelope.sequence >= 0,
        envelope.presentationTimeMicroseconds >= 0,
        envelope.durationMicroseconds >= 0
      else {
        throw InstantMediaStreamFrameError.invalidTiming
      }
      if requiresContiguousSequence, let expectedSequence,
        envelope.sequence != expectedSequence
      {
        throw InstantMediaStreamFrameError.sequenceMismatch(
          expected: expectedSequence,
          actual: envelope.sequence
        )
      }

      frames.append(
        Frame(
          sequence: envelope.sequence,
          presentationTimeMicroseconds: envelope.presentationTimeMicroseconds,
          durationMicroseconds: envelope.durationMicroseconds,
          flags: envelope.flags,
          payload: envelope.payload
        )
      )
      expectedSequence = envelope.sequence + 1
    }
    return frames
  }

  public mutating func finish() throws {
    guard buffered.isEmpty else {
      throw InstantMediaStreamFrameError.malformedEnvelope(
        "The stream ended with \(buffered.count) byte(s) of an incomplete frame."
      )
    }
  }
}

/// Stable, allocation-light FNV-1a digest for cross-SDK benchmark evidence.
public struct InstantMediaStreamDigest: Codable, Equatable, Hashable, Sendable {
  private var state: UInt64 = 0xcbf29ce484222325

  public init() {}

  public mutating func update<Frame: InstantMediaStreamFrame>(_ frame: Frame) {
    update(rawValue: Frame.mediaKind.rawValue)
    update(frame.sequence)
    update(frame.presentationTimeMicroseconds)
    update(frame.durationMicroseconds)
    update(Int64(frame.flags.rawValue))
    update(frame.payload)
  }

  public var hexadecimal: String {
    String(format: "%016llx", state)
  }

  private mutating func update(_ value: Int64) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { update(Data($0)) }
  }

  private mutating func update(rawValue: String) {
    update(Data(rawValue.utf8))
  }

  private mutating func update(_ data: Data) {
    for byte in data {
      state ^= UInt64(byte)
      state &*= 0x100000001b3
    }
  }
}
