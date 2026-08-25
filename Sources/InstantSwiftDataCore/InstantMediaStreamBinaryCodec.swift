import Foundation

/// Compact fixed-header framing for high-rate audio and video synchronization.
///
/// Unlike the compatibility JSON envelope, this codec writes payload bytes
/// directly: no Base64 expansion, no transient UTF-8 `String`, and no full-stream
/// buffering. The format fingerprint is negotiated by the generated descriptor
/// and repeated as eight bytes so a resumed reader fails closed on mismatch.
public struct InstantMediaStreamBinaryCodec<Frame: InstantMediaStreamFrame>: Sendable {
  public static var envelopeVersion: UInt8 { 1 }
  public static var headerByteCount: Int { 48 }

  public var formatIdentifier: String
  public var maximumFrameBytes: Int
  public var requiresContiguousSequence: Bool

  private let formatFingerprint: UInt64

  public init(
    formatIdentifier: String,
    maximumFrameBytes: Int = 256 * 1_024,
    requiresContiguousSequence: Bool = true
  ) {
    self.formatIdentifier = formatIdentifier
    self.maximumFrameBytes = maximumFrameBytes
    self.requiresContiguousSequence = requiresContiguousSequence
    self.formatFingerprint = Self.fingerprint(formatIdentifier.utf8)
  }

  public func encode(_ frame: Frame) throws -> Data {
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
    guard frame.payload.count <= Int(UInt32.max) else {
      throw InstantMediaStreamFrameError.frameExceedsMaximum(
        actualBytes: frame.payload.count,
        maximumBytes: Int(UInt32.max)
      )
    }

    var encoded = Data()
    encoded.reserveCapacity(Self.headerByteCount + frame.payload.count)
    encoded.append(contentsOf: [0x49, 0x53, 0x44, 0x46]) // ISDF
    encoded.append(Self.envelopeVersion)
    encoded.append(Self.kindByte(Frame.mediaKind))
    encoded.append(frame.flags.rawValue)
    encoded.append(0)
    appendLittleEndian(formatFingerprint, to: &encoded)
    appendLittleEndian(UInt64(bitPattern: frame.sequence), to: &encoded)
    appendLittleEndian(
      UInt64(bitPattern: frame.presentationTimeMicroseconds),
      to: &encoded
    )
    appendLittleEndian(UInt64(bitPattern: frame.durationMicroseconds), to: &encoded)
    appendLittleEndian(UInt32(frame.payload.count), to: &encoded)
    appendLittleEndian(Self.checksum(frame.payload), to: &encoded)
    encoded.append(frame.payload)
    return encoded
  }

  public func makeDecoder(
    expectedSequence: Int64? = nil,
    maximumBufferedBytes: Int? = nil
  ) -> InstantMediaStreamBinaryDecoder<Frame> {
    InstantMediaStreamBinaryDecoder(
      formatIdentifier: formatIdentifier,
      formatFingerprint: formatFingerprint,
      maximumFrameBytes: maximumFrameBytes,
      maximumBufferedBytes:
        maximumBufferedBytes ?? maximumFrameBytes * 2 + Self.headerByteCount * 2,
      requiresContiguousSequence: requiresContiguousSequence,
      expectedSequence: expectedSequence
    )
  }

  fileprivate static func fingerprint<S: Sequence>(_ bytes: S) -> UInt64
  where S.Element == UInt8 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01b3
    }
    return hash
  }

  fileprivate static func checksum(_ data: Data) -> UInt32 {
    var hash: UInt32 = 0x811c_9dc5
    data.withUnsafeBytes { bytes in
      for byte in bytes {
        hash ^= UInt32(byte)
        hash &*= 0x0100_0193
      }
    }
    return hash
  }

  fileprivate static func kindByte(_ kind: InstantMediaStreamKind) -> UInt8 {
    switch kind {
    case .audio: 1
    case .video: 2
    }
  }

  fileprivate static func kind(_ byte: UInt8) throws -> InstantMediaStreamKind {
    switch byte {
    case 1: .audio
    case 2: .video
    default:
      throw InstantMediaStreamFrameError.malformedEnvelope(
        "Unknown binary media kind byte \(byte)."
      )
    }
  }
}

public struct InstantMediaStreamBinaryDecoder<Frame: InstantMediaStreamFrame>: Sendable {
  private let formatIdentifier: String
  private let formatFingerprint: UInt64
  private let maximumFrameBytes: Int
  private let maximumBufferedBytes: Int
  private let requiresContiguousSequence: Bool
  private var expectedSequence: Int64?
  private var buffered = Data()
  private var readOffset = 0

  fileprivate init(
    formatIdentifier: String,
    formatFingerprint: UInt64,
    maximumFrameBytes: Int,
    maximumBufferedBytes: Int,
    requiresContiguousSequence: Bool,
    expectedSequence: Int64?
  ) {
    self.formatIdentifier = formatIdentifier
    self.formatFingerprint = formatFingerprint
    self.maximumFrameBytes = maximumFrameBytes
    self.maximumBufferedBytes = maximumBufferedBytes
    self.requiresContiguousSequence = requiresContiguousSequence
    self.expectedSequence = expectedSequence
  }

  public var bufferedByteCount: Int { buffered.count - readOffset }
  public var nextExpectedSequence: Int64? { expectedSequence }

  /// Decode into a caller-owned sink so the hot path need not allocate a frame array.
  public mutating func append(
    _ bytes: Data,
    yield: (Frame) throws -> Void
  ) throws {
    prepareForAppend(bytes.count)
    buffered.append(bytes)
    guard bufferedByteCount <= maximumBufferedBytes else {
      throw InstantMediaStreamFrameError.frameExceedsMaximum(
        actualBytes: bufferedByteCount,
        maximumBytes: maximumBufferedBytes
      )
    }

    while bufferedByteCount >= InstantMediaStreamBinaryCodec<Frame>.headerByteCount {
      let base = readOffset
      guard buffered[base] == 0x49,
        buffered[base + 1] == 0x53,
        buffered[base + 2] == 0x44,
        buffered[base + 3] == 0x46
      else {
        throw InstantMediaStreamFrameError.malformedEnvelope(
          "Binary media frame magic did not match ISDF."
        )
      }

      let version = buffered[base + 4]
      guard version == InstantMediaStreamBinaryCodec<Frame>.envelopeVersion else {
        throw InstantMediaStreamFrameError.invalidEnvelopeVersion(Int(version))
      }
      let actualKind = try InstantMediaStreamBinaryCodec<Frame>.kind(buffered[base + 5])
      guard actualKind == Frame.mediaKind else {
        throw InstantMediaStreamFrameError.mediaKindMismatch(
          expected: Frame.mediaKind,
          actual: actualKind
        )
      }

      let actualFingerprint = readUInt64(at: base + 8)
      guard actualFingerprint == formatFingerprint else {
        throw InstantMediaStreamFrameError.formatMismatch(
          expected: formatIdentifier,
          actual: String(format: "fingerprint:%016llx", actualFingerprint)
        )
      }

      let sequence = Int64(bitPattern: readUInt64(at: base + 16))
      let presentation = Int64(bitPattern: readUInt64(at: base + 24))
      let duration = Int64(bitPattern: readUInt64(at: base + 32))
      let payloadCount = Int(readUInt32(at: base + 40))
      let expectedChecksum = readUInt32(at: base + 44)
      guard sequence >= 0, presentation >= 0, duration >= 0 else {
        throw InstantMediaStreamFrameError.invalidTiming
      }
      guard payloadCount <= maximumFrameBytes else {
        throw InstantMediaStreamFrameError.frameExceedsMaximum(
          actualBytes: payloadCount,
          maximumBytes: maximumFrameBytes
        )
      }

      let totalByteCount = InstantMediaStreamBinaryCodec<Frame>.headerByteCount + payloadCount
      guard bufferedByteCount >= totalByteCount else { break }
      if requiresContiguousSequence, let expectedSequence, sequence != expectedSequence {
        throw InstantMediaStreamFrameError.sequenceMismatch(
          expected: expectedSequence,
          actual: sequence
        )
      }

      let payloadStart = base + InstantMediaStreamBinaryCodec<Frame>.headerByteCount
      let payloadEnd = payloadStart + payloadCount
      let payload = buffered.subdata(in: payloadStart..<payloadEnd)
      guard InstantMediaStreamBinaryCodec<Frame>.checksum(payload) == expectedChecksum else {
        throw InstantMediaStreamFrameError.malformedEnvelope(
          "Binary media frame payload checksum failed for sequence \(sequence)."
        )
      }

      try yield(
        Frame(
          sequence: sequence,
          presentationTimeMicroseconds: presentation,
          durationMicroseconds: duration,
          flags: InstantMediaStreamFrameFlags(rawValue: buffered[base + 6]),
          payload: payload
        )
      )
      expectedSequence = sequence + 1
      readOffset += totalByteCount
    }
    compactIfNeeded()
  }

  public mutating func append(_ bytes: Data) throws -> [Frame] {
    var frames: [Frame] = []
    try append(bytes) { frames.append($0) }
    return frames
  }

  public mutating func finish() throws {
    guard bufferedByteCount == 0 else {
      throw InstantMediaStreamFrameError.malformedEnvelope(
        "The binary stream ended with \(bufferedByteCount) incomplete byte(s)."
      )
    }
    buffered.removeAll(keepingCapacity: false)
    readOffset = 0
  }

  private mutating func prepareForAppend(_ incomingByteCount: Int) {
    guard readOffset > 0,
      bufferedByteCount + incomingByteCount > maximumBufferedBytes
    else { return }
    buffered.removeSubrange(0..<readOffset)
    readOffset = 0
  }

  private mutating func compactIfNeeded() {
    if readOffset == buffered.count {
      buffered.removeAll(keepingCapacity: true)
      readOffset = 0
    } else if readOffset >= 64 * 1_024, readOffset * 2 >= buffered.count {
      buffered.removeSubrange(0..<readOffset)
      readOffset = 0
    }
  }

  private func readUInt32(at offset: Int) -> UInt32 {
    UInt32(buffered[offset])
      | UInt32(buffered[offset + 1]) << 8
      | UInt32(buffered[offset + 2]) << 16
      | UInt32(buffered[offset + 3]) << 24
  }

  private func readUInt64(at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for byteOffset in 0..<8 {
      value |= UInt64(buffered[offset + byteOffset]) << UInt64(byteOffset * 8)
    }
    return value
  }
}

private func appendLittleEndian<Value: FixedWidthInteger>(
  _ value: Value,
  to data: inout Data
) {
  var littleEndian = value.littleEndian
  withUnsafeBytes(of: &littleEndian) { bytes in
    data.append(contentsOf: bytes)
  }
}
