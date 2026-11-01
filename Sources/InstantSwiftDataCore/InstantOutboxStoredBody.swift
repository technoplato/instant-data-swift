// History:
// - 2026-10-31: added (#1510, #1463): an outbox write's body is stored compressed, so a live write's cell fits its
//   leaf and its save and echo allocate and free no overflow page.

import Compression
import Foundation

/// A write's body as `instant_outbox_bodies.json` stores it (#1463): its JSON compressed.
///
/// A `WITHOUT ROWID` cell keeps at most 1,002 bytes on its leaf (4 KB pages). A phone's live bodies were 3.4-12 KB of
/// JSON, so each took two to four overflow pages, allocated from the free list at the save (page 1 and a trunk page
/// rewritten) and freed at the echo (both again). Raw deflate takes the median body from 8,389 to 944 bytes, and with
/// the lifecycle derived instead of stored beside it, 6 of the 8 live cells on that store fit their leaf.
///
/// The stored value is a BLOB: one format byte, the JSON's length in four big-endian bytes, then the JSON compressed
/// with raw deflate (`COMPRESSION_ZLIB`, RFC 1951), which any zlib inflates (`zlib.inflateRawSync`, Python's
/// `zlib.decompress(data[5:], -15)`). A TEXT value is a body an older version stored; it is read as it is.
enum InstantOutboxStoredBody {
  /// The format byte of a compressed body.
  static let compressedFormat: UInt8 = 1
  private static let headerByteCount = 5

  /// `json` as stored: compressed, or nil when compressing it would not make it shorter (it is then stored as text).
  static func compressed(_ json: String) -> Data? {
    var source = Array(json.utf8)
    guard !source.isEmpty, source.count <= Int(UInt32.max) else { return nil }
    let capacity = source.count
    var stored = [UInt8](repeating: 0, count: headerByteCount + capacity)
    let written = stored.withUnsafeMutableBufferPointer { destination in
      source.withUnsafeMutableBufferPointer { input in
        compression_encode_buffer(
          destination.baseAddress! + headerByteCount,
          capacity,
          input.baseAddress!,
          input.count,
          nil,
          COMPRESSION_ZLIB
        )
      }
    }
    // Zero means the output did not fit in the input's own length: such a body is not worth compressing.
    guard written > 0 else { return nil }
    let length = UInt32(source.count)
    stored[0] = compressedFormat
    stored[1] = UInt8(truncatingIfNeeded: length >> 24)
    stored[2] = UInt8(truncatingIfNeeded: length >> 16)
    stored[3] = UInt8(truncatingIfNeeded: length >> 8)
    stored[4] = UInt8(truncatingIfNeeded: length)
    source.removeAll()
    return Data(stored[0..<(headerByteCount + written)])
  }

  /// The JSON a compressed body holds, or nil when `stored` is not one this version wrote or it does not inflate to
  /// exactly the length its header says.
  static func json(fromCompressed stored: UnsafeRawBufferPointer) -> String? {
    guard stored.count > headerByteCount, stored[0] == compressedFormat else { return nil }
    let length = Int(stored[1]) << 24 | Int(stored[2]) << 16 | Int(stored[3]) << 8 | Int(stored[4])
    guard length > 0 else { return nil }
    // One byte more than the header says, so a stream that inflates longer is caught rather than cut.
    var json = [UInt8](repeating: 0, count: length + 1)
    let written = json.withUnsafeMutableBufferPointer { destination in
      compression_decode_buffer(
        destination.baseAddress!,
        destination.count,
        stored.baseAddress!.assumingMemoryBound(to: UInt8.self) + headerByteCount,
        stored.count - headerByteCount,
        nil,
        COMPRESSION_ZLIB
      )
    }
    guard written == length else { return nil }
    return String(decoding: json[0..<length], as: UTF8.self)
  }
}
