import Foundation

// History:
// - 2026-10-23: the store's text for a value and a fact goes through one seam, so the text it keeps can be written
//   without `JSONEncoder` and checked against it (#1007).

/// The JSON text the local store keeps for a value and for a fact (#1007).
///
/// A stored fact keeps its value's text in `value_json`, part of the facts' key and of the lookups that find them, and
/// its own text in `json`. Both are `JSONEncoder`'s text with `.sortedKeys`, and both must stay exactly that: a lookup
/// compares the text byte for byte with the text an earlier version stored.
enum InstantStoredJSON {
  /// The text the store keeps for `value`. Throws what `JSONEncoder` throws for it.
  static func stored(_ value: InstantValue, using encoder: JSONEncoder) throws -> String {
    String(decoding: try encoder.encode(value), as: UTF8.self)
  }

  /// The text the store keeps for `triple`. Throws what `JSONEncoder` throws for it.
  static func stored(_ triple: InstantTriple, using encoder: JSONEncoder) throws -> String {
    String(decoding: try encoder.encode(triple), as: UTF8.self)
  }

  /// The texts the store keeps for a fact's value and for the fact. Throws what `JSONEncoder` throws for them.
  static func storedTexts(
    _ triple: InstantTriple,
    using encoder: JSONEncoder
  ) throws -> (value: String, triple: String) {
    (try stored(triple.value, using: encoder), try stored(triple, using: encoder))
  }
}
