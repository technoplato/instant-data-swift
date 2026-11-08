// History:
// - 2026-10-31: created (#1498): a one-shot read compares its answer with the query cache's row by this digest instead
//   of encoding the answer as JSON to write it again. The encode was 431 of queryOnce's 795 ms of CPU a minute in the
//   #1482 audit's sample of the recording exercise (60 reads of one unchanged page, Mac mini, release).
// - 2026-11-08: a row's counts are part of what its answer shows (ADR 0015 L3, #2005), so a changed count rewrites the
//   cached row; a row without counts writes the bytes it wrote before.

import Crypto
import Foundation

/// What a query's answer shows, as a SHA-256 digest (#1498): its query, its rows with their values and included rows,
/// its page info and its error.
///
/// Two answers with the same digest decode from the query cache's row as the same answer, so the cache keeps the row
/// it has and updates only the read's time, revisions and sequence. The sequence is not part of it: it is a column of
/// its own. Everything is written with a tag and, for strings and collections, a length, and a dictionary's keys in
/// order, so different answers never write the same bytes; equal answers can still differ here only where `==`
/// ignores bits (`0.0` and `-0.0`), which costs a whole write and changes nothing a reader sees.
struct InstantQueryAnswerDigest: Hashable, Sendable {
  /// The digest as lowercase hexadecimal, as the query cache stores it.
  let hexValue: String

  init(hexValue: String) {
    self.hexValue = hexValue
  }

  init(_ emission: InstantQueryEmission) {
    var writer = Writer()
    writer.string(emission.queryID)
    writer.count(emission.values.count)
    for snapshot in emission.values {
      writer.entity(
        id: snapshot.id,
        namespace: snapshot.namespace,
        values: snapshot.values,
        links: snapshot.links,
        counts: snapshot.counts
      )
    }
    writer.codable(emission.pageInfo)
    writer.codable(emission.error)
    hexValue = writer.finish()
  }

  /// Feeds an answer's bytes to SHA-256 through a buffer, so a long answer costs a few hash calls, not one per value.
  private struct Writer {
    private var hasher = SHA256()
    private var buffer: [UInt8] = []

    init() {
      buffer.reserveCapacity(Self.flushThreshold + 1_024)
    }

    private static let flushThreshold = 16 * 1_024

    mutating func finish() -> String {
      flush()
      let digits = Array("0123456789abcdef".utf8)
      var hex: [UInt8] = []
      hex.reserveCapacity(64)
      for byte in hasher.finalize() {
        hex.append(digits[Int(byte >> 4)])
        hex.append(digits[Int(byte & 0x0f)])
      }
      return String(decoding: hex, as: UTF8.self)
    }

    private mutating func flush() {
      guard !buffer.isEmpty else { return }
      buffer.withUnsafeBytes { hasher.update(bufferPointer: $0) }
      buffer.removeAll(keepingCapacity: true)
    }

    private mutating func byte(_ value: UInt8) {
      buffer.append(value)
    }

    private mutating func word(_ value: UInt64) {
      withUnsafeBytes(of: value.littleEndian) { buffer.append(contentsOf: $0) }
      if buffer.count >= Self.flushThreshold { flush() }
    }

    mutating func count(_ value: Int) {
      word(UInt64(truncatingIfNeeded: value))
    }

    mutating func string(_ value: String) {
      var value = value
      value.withUTF8 { bytes in
        count(bytes.count)
        buffer.append(contentsOf: bytes)
      }
      if buffer.count >= Self.flushThreshold { flush() }
    }

    mutating func entity(
      id: String,
      namespace: String,
      values: [String: InstantMaterializedValue],
      links: [String: [InstantLinkedEntitySnapshot]]?,
      counts: [String: Int]?
    ) {
      string(id)
      string(namespace)
      count(values.count)
      for key in values.keys.sorted() {
        string(key)
        switch values[key]! {
        case let .one(value):
          byte(1)
          self.value(value)
        case let .many(many):
          byte(2)
          count(many.count)
          for value in many { self.value(value) }
        }
      }
      if let links {
        byte(1)
        count(links.count)
        for name in links.keys.sorted() {
          string(name)
          let children = links[name]!
          count(children.count)
          for child in children {
            entity(
              id: child.id,
              namespace: child.namespace,
              values: child.values,
              links: child.links,
              counts: child.counts
            )
          }
        }
      } else {
        byte(0)
      }
      // ADR 0015 L3: written only when present. One query's rows either all carry counts or none do (its plan decides),
      // and a digest is compared only with its own query's, so this adds no ambiguity and keeps older rows' digests.
      if let counts {
        byte(3)
        count(counts.count)
        for key in counts.keys.sorted() {
          string(key)
          count(counts[key]!)
        }
      }
    }

    private mutating func value(_ value: InstantValue) {
      switch value {
      case .null:
        byte(0)
      case let .string(string):
        byte(1)
        self.string(string)
      case let .number(number):
        byte(2)
        word(number.bitPattern)
      case let .bool(bool):
        byte(bool ? 4 : 3)
      case let .date(date):
        byte(5)
        word(date.timeIntervalSinceReferenceDate.bitPattern)
      case let .json(json):
        byte(6)
        self.json(json)
      case let .ref(ref):
        byte(7)
        string(ref)
      case let .lookupRef(lookup):
        byte(8)
        codable(lookup)
      }
    }

    private mutating func json(_ value: JSONValue) {
      switch value {
      case .null:
        byte(0)
      case let .bool(bool):
        byte(bool ? 2 : 1)
      case let .number(number):
        byte(3)
        word(number.bitPattern)
      case let .string(string):
        byte(4)
        self.string(string)
      case let .array(array):
        byte(5)
        count(array.count)
        for element in array { json(element) }
      case let .object(object):
        byte(6)
        count(object.count)
        for key in object.keys.sorted() {
          string(key)
          json(object[key]!)
        }
      }
    }

    /// A rare value (page info, an error, a lookup reference) as the query cache's JSON holds it.
    mutating func codable<Value: Encodable>(_ value: Value?) {
      guard let value else {
        byte(0)
        return
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      guard let data = try? encoder.encode(value) else {
        // Only a non-finite number fails, and the row's own encode fails on it too; never match a stored digest.
        byte(2)
        string(UUID().uuidString)
        return
      }
      byte(1)
      count(data.count)
      buffer.append(contentsOf: data)
      if buffer.count >= Self.flushThreshold { flush() }
    }
  }
}
