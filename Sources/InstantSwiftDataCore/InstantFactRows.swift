import Foundation
import SQLite3

// History:
// - 2026-10-25: the read connection's fact reads move here unchanged, so their cost can be counted on one thread
//   (#1150).

/// Reads facts from the fact table's rows (#1150).
///
/// A statement selects ``columns`` first, and ``read(_:into:counting:)`` steps it to its end.
struct InstantFactRowReader {
  /// What a statement selects for the reader, in order.
  static let columns = "json"

  private let decoder: JSONDecoder
  private let path: String?
  private var texts: [String] = []

  /// - Parameter path: The store's file, which a failure to decode names.
  init(decoder: JSONDecoder, path: String?) {
    self.decoder = decoder
    self.path = path
  }

  /// Steps `statement` to its end, appends each row's fact to `triples`, and hands each fact with the byte count of
  /// the text it was read from to `counting`.
  mutating func read(
    _ statement: OpaquePointer,
    into triples: inout [InstantTriple],
    counting: (InstantTriple, Int) -> Void = { _, _ in }
  ) throws {
    texts.removeAll(keepingCapacity: true)
    while true {
      let result = sqlite3_step(statement)
      if result == SQLITE_DONE { break }
      guard result == SQLITE_ROW else {
        throw SQLiteReadConnection.failure(
          operation: "step a local read",
          message: SQLiteReadConnection.errorMessage(sqlite3_db_handle(statement)),
          path: nil
        )
      }
      if let text = sqlite3_column_text(statement, 0) {
        texts.append(String(cString: text))
      }
    }
    guard !texts.isEmpty else { return }
    let array = "[" + texts.joined(separator: ",") + "]"
    let decoded: [InstantTriple]
    do {
      decoded = try decoder.decode([InstantTriple].self, from: Data(array.utf8))
    } catch {
      throw SQLiteReadConnection.failure(
        operation: "decode rows on the local read connection",
        message: "\(texts.count) stored rows could not be decoded: \(error)",
        path: path
      )
    }
    for (text, triple) in zip(texts, decoded) {
      counting(triple, text.utf8.count)
    }
    triples.append(contentsOf: decoded)
  }
}
