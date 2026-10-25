import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

// #1150 (2026-10-25): a local read of a 256-line history page loads the page's deferred text and words through the read
// connection, and each fact cost SQLite computing the row's `json` (#1121), a Swift string of it, one joined string a
// batch, a `Data` copy and `JSONDecoder`: about 17,300 of a page's 23,979 allocations on the Mac mini, 23 a fact in the
// test below. A fact read should cost its value's string and, when they change from the row before, its ids.
//
// Equality is checked with `#expect`: in a release build `expectNoDifference` reports through IssueReporting, which
// records nothing outside debug builds.
//
// History:
// - 2026-10-25: #1150: the reader's equivalence and cost.
// - 2026-10-25: #1150: the stored value reader against `JSONDecoder`, and texts the writer does not write.

@Suite
struct InstantFactRowsTests {
  /// Every kind of value, and ids and texts that need escaping, read back as they were stored.
  @Test(arguments: [UInt64(11_150), 11_151, 11_152])
  func theReaderReturnsTheFactsTheTableHolds(seed: UInt64) throws {
    var random = InfiniteWindowRandom(seed: seed)
    var facts: [InstantTriple] = []
    for entity in 0..<40 {
      let entityID = random.chance(10) ? "entity \"\(entity)\" / \\" : "3f2a\(String(format: "%04d", entity))-7c1e-4b8a-9d21-5e6f7a8b9c0d"
      for attribute in 0..<random.int(1...6) {
        facts.append(
          InstantTriple(
            entityID: entityID,
            attributeID: "ns/field-\(attribute)",
            value: Self.randomValue(&random),
            txID: random.chance(50) ? "tx-\(entity)" : "tx-\(entity)-\(attribute)",
            txTime: InstantTimestamp(milliseconds: 1_792_893_464_257 + Int64(random.int(0...1_000)))
          )
        )
      }
    }
    let table = try FactTable(facts)
    let read = try table.read()
    let expected = try facts.sorted(by: table.keyOrder)
    #expect(read.count == expected.count)
    for (index, (actual, wanted)) in zip(read, expected).enumerated() {
      #expect(actual == wanted, "row \(index): \(actual) != \(wanted)")
    }
  }

  /// A history page's deferred values: 256 lines, a text and a words value each, both written in the line's
  /// transaction.
  @Test("Reading a page's deferred values allocates for the values, not the rows' texts")
  func readingDeferredValuesCostsTheValues() throws {
    var facts: [InstantTriple] = []
    for line in 0..<256 {
      let id = "3f2a\(String(format: "%04d", line))-7c1e-4b8a-9d21-5e6f7a8b9c0d"
      let txID = "8b1d4c2e-0f3a-4d5b-8c6e-\(String(format: "%012d", line))"
      let words = (0..<24).map { #"{"w":"word\#($0)","s":\#(Double(line) + Double($0) / 4)}"# }.joined(separator: ",")
      facts.append(
        InstantTriple(
          entityID: id, attributeID: "transcriptionSegments/text",
          value: .string("Line \(line) of the recording says what was heard, about a hundred and twenty characters long."),
          txID: txID, txTime: InstantTimestamp(milliseconds: 1_792_893_464_257 + Int64(line))
        )
      )
      facts.append(
        InstantTriple(
          entityID: id, attributeID: "transcriptionSegments/wordsJSON", value: .string("[\(words)]"),
          txID: txID, txTime: InstantTimestamp(milliseconds: 1_792_893_464_257 + Int64(line))
        )
      )
    }
    let table = try FactTable(facts)
    #expect(try table.read().count == 512)
    // The bound holds in optimized builds; an unoptimized one allocates each nested closure's context.
    guard RealSizeBudget.isOptimized else { return }
    let allocations = try table.allocationsOfOneRead()
    #expect(allocations < 3 * 512, "Reading 512 deferred facts allocated \(allocations) times (\(allocations / 512) a fact).")
  }

  /// The stored text of every kind of value reads back as `JSONDecoder` reads it; the reader declines only what it does
  /// not take apart byte for byte, which the row reader then hands to `JSONDecoder`.
  @Test(arguments: [UInt64(21_150), 21_151, 21_152])
  func aStoredValueReadsAsTheDecoderReadsIt(seed: UInt64) throws {
    guard #available(iOS 18, macOS 15, macCatalyst 18, tvOS 18, watchOS 11, *) else { return }
    var random = InfiniteWindowRandom(seed: seed)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    for round in 0..<500 {
      let value = Self.randomValue(&random)
      let text = Array(try InstantStoredJSON.stored(value, using: encoder).utf8)
      let decoded = try JSONDecoder().decode(InstantValue.self, from: Data(text))
      let read = text.withUnsafeBufferPointer { InstantStoredJSON.value(stored: $0) }
      switch value {
      case .json, .lookupRef:
        #expect(read == nil, "round \(round): \(value) is JSONDecoder's to read")
      default:
        #expect(read == decoded, "round \(round): \(String(describing: read)) != \(decoded)")
      }
    }
  }

  /// Texts the writer does not write today, as an older store or another writer may have kept them.
  @Test func storedTextsTheWriterDoesNotWrite() throws {
    guard #available(iOS 18, macOS 15, macCatalyst 18, tvOS 18, watchOS 11, *) else { return }
    func read(_ text: String) -> InstantValue? {
      Array(text.utf8).withUnsafeBufferPointer { InstantStoredJSON.value(stored: $0) }
    }
    func decoded(_ text: String) throws -> InstantValue {
      try JSONDecoder().decode(InstantValue.self, from: Data(text.utf8))
    }
    // Escapes JSONEncoder does not write, but JSON allows: they read as the decoder reads them.
    for text in [
      #"{"string":{"_0":"café 🎙 \/ A"}}"#,
      #"{"string":{"_0":"\b\f\n\r\t\"\\"}}"#,
      #"{"number":{"_0":-0.5e+2}}"#,
      #"{"number":{"_0":1E3}}"#,
      #"{"ref":{"_0":""}}"#,
    ] {
      #expect(read(text) == (try decoded(text)), "\(text)")
    }
    // Texts it declines, for `JSONDecoder` to read or refuse.
    for text in [
      #"{"string":{"_0":"\ud800"}}"#,
      #"{"string":{"_0":"\x"}}"#,
      #"{"string":{"_0":"unterminated}}"#,
      "{\"string\":{\"_0\":\"raw \u{1} control\"}}",
      #"{"number":{"_0":01}}"#,
      #"{"number":{"_0":1.}}"#,
      #"{"number":{"_0":+1}}"#,
      #"{"number":{"_0":1e400}}"#,
      #"{"bool":{"_0":true}} "#,
      #"{"null":{}}x"#,
      #"{"json":{"_0":{"k":1}}}"#,
      #"{"string": {"_0":"spaced"}}"#,
    ] {
      #expect(read(text) == nil, "\(text)")
    }
  }

  // MARK: - Helpers

  /// An in-memory fact table in the store's layout (#1121), filled with `facts`.
  final class FactTable {
    private var connection: OpaquePointer?

    init(_ facts: [InstantTriple]) throws {
      guard sqlite3_open(":memory:", &connection) == SQLITE_OK else { throw Failure("open") }
      try execute(SQLitePersistenceStore.factTableSQL(named: "instant_triples"))
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try execute("BEGIN")
      for fact in facts {
        try execute(
          "INSERT OR REPLACE INTO instant_triples (entity_id, attribute_id, value_json, tx_id, tx_time_ms) VALUES (?, ?, ?, ?, ?)",
          [
            .text(fact.entityID), .text(fact.attributeID), .text(try InstantStoredJSON.stored(fact.value, using: encoder)),
            .text(fact.txID), .integer(fact.txTime.milliseconds),
          ]
        )
      }
      try execute("COMMIT")
    }

    deinit { sqlite3_close(connection) }

    /// The table's order: entity id, attribute id, then the value's stored text.
    func keyOrder(_ lhs: InstantTriple, _ rhs: InstantTriple) throws -> Bool {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let left = (lhs.entityID, lhs.attributeID, try InstantStoredJSON.stored(lhs.value, using: encoder))
      let right = (rhs.entityID, rhs.attributeID, try InstantStoredJSON.stored(rhs.value, using: encoder))
      return Array(left.0.utf8).lexicographicallyPrecedes(right.0.utf8)
        || (left.0 == right.0
          && (Array(left.1.utf8).lexicographicallyPrecedes(right.1.utf8)
            || (left.1 == right.1 && Array(left.2.utf8).lexicographicallyPrecedes(right.2.utf8))))
    }

    func read() throws -> [InstantTriple] {
      var reader = InstantFactRowReader(decoder: JSONDecoder())
      return try withStatement { statement in
        var triples: [InstantTriple] = []
        try reader.read(statement, into: &triples)
        return triples
      }
    }

    /// The allocations of the second of two reads, on this thread.
    func allocationsOfOneRead() throws -> Int {
      var reader = InstantFactRowReader(decoder: JSONDecoder())
      var triples: [InstantTriple] = []
      triples.reserveCapacity(1_024)
      try withStatement { try reader.read($0, into: &triples) }
      triples.removeAll(keepingCapacity: true)
      return try withStatement { statement in
        RealSizeAllocations.start(onCurrentThreadOnly: true)
        try reader.read(statement, into: &triples)
        return RealSizeAllocations.stop().allocations
      }
    }

    private func withStatement<Result>(_ body: (OpaquePointer) throws -> Result) throws -> Result {
      var statement: OpaquePointer?
      let sql = "SELECT \(InstantFactRowReader.columns) FROM instant_triples ORDER BY entity_id, attribute_id, value_json"
      guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw Failure("prepare: \(String(cString: sqlite3_errmsg(connection)))")
      }
      defer { sqlite3_finalize(statement) }
      return try body(statement)
    }

    private enum Binding {
      case text(String)
      case integer(Int64)
    }

    private func execute(_ sql: String, _ bindings: [Binding] = []) throws {
      var statement: OpaquePointer?
      guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw Failure("prepare: \(String(cString: sqlite3_errmsg(connection)))")
      }
      defer { sqlite3_finalize(statement) }
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      for (index, binding) in bindings.enumerated() {
        switch binding {
        case let .text(text): sqlite3_bind_text(statement, Int32(index + 1), text, -1, transient)
        case let .integer(integer): sqlite3_bind_int64(statement, Int32(index + 1), integer)
        }
      }
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw Failure("step: \(String(cString: sqlite3_errmsg(connection)))")
      }
    }

    struct Failure: Error, CustomStringConvertible {
      var description: String
      init(_ description: String) { self.description = description }
    }
  }

  static func randomValue(_ random: inout InfiniteWindowRandom) -> InstantValue {
    switch random.int(0...11) {
    case 0: .null
    case 1: .string("plain text \(random.int(0...9))")
    case 2: .string("needs \"escaping\" / and \\ and\ttabs\nand lines \u{1}\u{1F}")
    case 3: .string("non-ASCII: café, 日本語, emoji 🎙️ and a combining e\u{301}")
    case 4: .string(String(repeating: "long ", count: random.int(4...40)))
    case 5: .number([0, -0.0, 1, -3, 12.5, 0.1, 1e-7, 1.5e300, -2.25e-10, 123_456_789_012][random.int(0...9)])
    case 6: .bool(random.chance(50))
    case 7: .ref("3f2a\(random.int(1000...9999))-7c1e-4b8a-9d21-5e6f7a8b9c0d")
    case 8: .date(Date(timeIntervalSinceReferenceDate: Double(random.int(0...1_000_000_000)) + 0.25))
    case 9: .json(.object(["k": .number(Double(random.int(0...2))), "list": .array([.string("a/b"), .bool(true), .null])]))
    case 10: .lookupRef(InstantLookupRef(attributeID: "recordings/id", value: .string("rec-\(random.int(0...9))")))
    default: .string("")
    }
  }
}
