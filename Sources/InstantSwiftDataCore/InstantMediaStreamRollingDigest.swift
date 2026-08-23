import Foundation

/// Allocation-free rolling digest for cross-SDK stream correctness evidence.
///
/// Integer fields are fed directly from their little-endian stack bytes and
/// payloads are traversed through `Data.withUnsafeBytes`; no temporary `Data`
/// values are created per field or frame.
public struct InstantMediaStreamRollingDigest: Codable, Equatable, Hashable, Sendable {
  private var state: UInt64 = 0xcbf2_9ce4_8422_2325

  public init() {}

  public mutating func update<Frame: InstantMediaStreamFrame>(_ frame: Frame) {
    update(Frame.mediaKind.rawValue.utf8)
    update(frame.sequence)
    update(frame.presentationTimeMicroseconds)
    update(frame.durationMicroseconds)
    update(Int64(frame.flags.rawValue))
    frame.payload.withUnsafeBytes { update($0) }
  }

  public var hexadecimal: String {
    String(format: "%016llx", state)
  }

  private mutating func update(_ value: Int64) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { update($0) }
  }

  private mutating func update<S: Sequence>(_ bytes: S)
  where S.Element == UInt8 {
    for byte in bytes {
      state ^= UInt64(byte)
      state &*= 0x0000_0100_0000_01b3
    }
  }

  private mutating func update(_ bytes: UnsafeRawBufferPointer) {
    for byte in bytes {
      state ^= UInt64(byte)
      state &*= 0x0000_0100_0000_01b3
    }
  }
}
