import Foundation
import SQLite3

// History:
// - 2026-10-25: the read connection's fact reads move here unchanged, so their cost can be counted on one thread
//   (#1150).
// - 2026-10-25: a fact is read from its columns instead of the `json` the table computes for it (#1150): a history page's
//   512 deferred values went from 23 allocations a fact to 2.
// - 2026-10-25: the store's deferred loads read through it too (#1147); a failure is the caller's to report.

/// Reads facts from the fact table's rows (#1150).
///
/// The table computes each row's `json` when it is read (#1121), and decoding that text cost SQLite building it, a Swift
/// string of it, one joined string a batch, a `Data` copy and `JSONDecoder`'s work: about 23 allocations a fact. Here a
/// fact costs its value's string and, when it changes from the row before, its entity's and transaction's ids: rows
/// come in key order, so an entity's facts reuse one id. A read names few attributes, so their ids are kept and reused.
/// The value's stored text is read by ``InstantStoredJSON/value(stored:)``; `JSONDecoder` reads the rest.
///
/// A statement selects ``columns`` first, and ``read(_:into:counting:)`` steps it to its end.
struct InstantFactRowReader {
  /// What a statement selects for the reader, in order.
  static let columns = "entity_id, attribute_id, value_json, tx_id, tx_time_ms"

  /// A row the reader could not step to or decode, for its caller to report as its own failure.
  struct ReadFailure: Error {
    var operation: String
    var message: String
  }

  private let decoder: JSONDecoder
  private var entityID = ""
  private var txID = ""
  private var attributeIDs: [String] = []
  /// Where a value's string with escapes is unescaped, kept from row to row.
  private var scratch: [UInt8] = []
  /// Attribute ids kept for reuse; a read with more makes the rest anew.
  private static let maximumAttributeIDs = 64

  init(decoder: JSONDecoder) {
    self.decoder = decoder
  }

  /// Steps `statement` to its end, appends each row's fact to `triples`, and hands each fact with the byte count of
  /// its value's stored text to `counting`.
  mutating func read(
    _ statement: OpaquePointer,
    into triples: inout [InstantTriple],
    counting: (InstantTriple, Int) -> Void = { _, _ in }
  ) throws {
    while true {
      let result = sqlite3_step(statement)
      if result == SQLITE_DONE { return }
      guard result == SQLITE_ROW else {
        throw ReadFailure(
          operation: "step a fact read",
          message: SQLiteReadConnection.errorMessage(sqlite3_db_handle(statement))
        )
      }
      let valueText = Self.text(of: statement, column: 2)
      let triple = InstantTriple(
        entityID: Self.reusing(&entityID, Self.text(of: statement, column: 0)),
        attributeID: attributeID(Self.text(of: statement, column: 1)),
        value: try value(valueText),
        txID: Self.reusing(&txID, Self.text(of: statement, column: 3)),
        txTime: InstantTimestamp(milliseconds: sqlite3_column_int64(statement, 4))
      )
      counting(triple, valueText.count)
      triples.append(triple)
    }
  }

  /// A text column's bytes, valid until the statement steps again.
  private static func text(of statement: OpaquePointer, column: Int32) -> UnsafeBufferPointer<UInt8> {
    // The text first, then its length, as SQLite asks.
    guard let text = sqlite3_column_text(statement, column) else { return UnsafeBufferPointer(start: nil, count: 0) }
    return UnsafeBufferPointer(start: text, count: Int(sqlite3_column_bytes(statement, column)))
  }

  /// `last` when `bytes` spell it; otherwise a new string, kept as `last`.
  private static func reusing(_ last: inout String, _ bytes: UnsafeBufferPointer<UInt8>) -> String {
    if !spells(last, bytes) {
      last = String(decoding: bytes, as: UTF8.self)
    }
    return last
  }

  private mutating func attributeID(_ bytes: UnsafeBufferPointer<UInt8>) -> String {
    for id in attributeIDs where Self.spells(id, bytes) {
      return id
    }
    let id = String(decoding: bytes, as: UTF8.self)
    if attributeIDs.count < Self.maximumAttributeIDs {
      attributeIDs.append(id)
    }
    return id
  }

  private mutating func value(_ text: UnsafeBufferPointer<UInt8>) throws -> InstantValue {
    if let value = InstantStoredJSON.value(stored: text, scratch: &scratch) {
      return value
    }
    do {
      return try decoder.decode(InstantValue.self, from: Data(text))
    } catch {
      throw ReadFailure(operation: "decode a stored value", message: "A stored value could not be decoded: \(error)")
    }
  }

  /// Whether `string`'s UTF-8 is `bytes`.
  private static func spells(_ string: String, _ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
    let utf8 = string.utf8
    guard utf8.count == bytes.count else { return false }
    return utf8.withContiguousStorageIfAvailable { stored in
      stored.isEmpty || memcmp(stored.baseAddress!, bytes.baseAddress!, stored.count) == 0
    } ?? utf8.elementsEqual(bytes)
  }
}
