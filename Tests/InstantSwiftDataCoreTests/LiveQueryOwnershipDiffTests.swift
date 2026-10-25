import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #1147 (2026-10-25): every refresh of an open page saves its result, and the save worked out which ownership rows leave
// and join by reading every row the result owned into strings and encoding every value it holds now: on a 64-line page
// with one line changed, about 3,000 allocations to read the rows and 2,000 to encode the values, of the refresh's
// 16,000. The rows that stay the same should cost nothing.
//
// Equality is checked with `#expect`: in a release build `expectNoDifference` reports through IssueReporting, which
// records nothing outside debug builds.
//
// History:
// - 2026-10-25: #1147: the diff's equivalence and cost; the rows an earlier save left, as its facts.

@Suite
struct LiveQueryOwnershipDiffTests {
  /// The rows that leave and join are the set differences of the stored rows and the new facts, in the store's order,
  /// for any mix of kept, changed, removed, added and repeated facts and every kind of value.
  @Test(arguments: [UInt64(91_147), 91_148, 91_149])
  func theDiffIsTheSetDifferenceOfTheRowsAndTheFacts(seed: UInt64) throws {
    var random = InfiniteWindowRandom(seed: seed)
    let encoder = Self.encoder
    for round in 0..<100 {
      var previousFacts: [InstantTriple] = []
      var nextFacts: [InstantTriple] = []
      for entity in 0..<random.int(0...12) {
        for attribute in 0..<random.int(1...5) {
          let value = Self.randomValue(&random)
          let triple = Self.triple("entity-\(entity)", "ns/field-\(attribute)", value)
          switch random.int(0...9) {
          case 0...5:
            previousFacts.append(triple)
            nextFacts.append(triple)
          case 6:
            previousFacts.append(triple)
            nextFacts.append(Self.triple(triple.entityID, triple.attributeID, Self.randomValue(&random)))
          case 7:
            previousFacts.append(triple)
          case 8:
            nextFacts.append(triple)
          default:
            nextFacts.append(triple)
            nextFacts.append(triple)
          }
        }
      }
      let previousRows = Set(try previousFacts.map { try Self.identity($0, encoder: encoder) })
      let nextRows = Set(try nextFacts.map { try Self.identity($0, encoder: encoder) })
      let expectedRemoved = previousRows.subtracting(nextRows).sorted(by: LiveQueryOwnershipDiff.storeOrder)
      let expectedInserted = nextRows.subtracting(previousRows).sorted(by: LiveQueryOwnershipDiff.storeOrder)

      // The rows from SQLite's bytes, and the rows a save earlier in the frame left.
      var fromBytes = try LiveQueryOwnershipDiff(next: nextFacts, encoder: encoder)
      for row in previousRows { Self.feed(row, to: &fromBytes) }
      try fromBytes.finish()
      var fromSet = try LiveQueryOwnershipDiff(next: nextFacts, encoder: encoder)
      fromSet.previousRows(previousRows)
      try fromSet.finish()
      var fromFacts = try LiveQueryOwnershipDiff(next: nextFacts, encoder: encoder)
      try fromFacts.previousFacts(previousFacts)
      try fromFacts.finish()

      for diff in [fromBytes, fromSet, fromFacts] {
        #expect(diff.removed == expectedRemoved, "round \(round) removed: \(String(describing: CustomDump.diff(diff.removed, expectedRemoved)))")
        #expect(diff.inserted == expectedInserted, "round \(round) inserted: \(String(describing: CustomDump.diff(diff.inserted, expectedInserted)))")
        #expect(diff.isUnchanged == (expectedRemoved.isEmpty && expectedInserted.isEmpty), "round \(round)")
        #expect(try diff.nextRows() == nextRows, "round \(round) next rows")
      }
    }
  }

  /// A 64-line page restated with one line's text and words changed: the 1,022 facts that stay cost nothing; the work is
  /// the two that changed.
  @Test("Diffing a 64-line page's ownership with one line changed allocates for the line, not the page")
  func diffingARefreshedPageCostsTheChangedLine() throws {
    let encoder = Self.encoder
    let previousFacts = Self.page(lines: 64, changedLine: nil)
    let nextFacts = Self.page(lines: 64, changedLine: 17)
    // The stored rows' bytes, made before the count, as SQLite would hand them.
    let rows = try previousFacts.map { triple -> (entity: [UInt8], attribute: [UInt8], value: [UInt8]) in
      let identity = try Self.identity(triple, encoder: encoder)
      return (Array(identity.entityID.utf8), Array(identity.attributeID.utf8), Array(identity.valueJSON.utf8))
    }
    func diff() throws -> LiveQueryOwnershipDiff {
      var diff = try LiveQueryOwnershipDiff(next: nextFacts, encoder: encoder)
      for row in rows {
        row.entity.withUnsafeBufferPointer { entity in
          row.attribute.withUnsafeBufferPointer { attribute in
            row.value.withUnsafeBufferPointer { value in
              diff.previousRow(entityID: entity, attributeID: attribute, valueJSON: value)
            }
          }
        }
      }
      try diff.finish()
      return diff
    }
    let result = try diff()
    #expect(result.removed.count == 2 && result.inserted.count == 2, "removed \(result.removed.count), inserted \(result.inserted.count)")
    // The bound holds in optimized builds; an unoptimized one allocates each nested closure's context.
    guard RealSizeBudget.isOptimized else { return }
    var allocations = 0
    _ = try diff()
    RealSizeAllocations.start(onCurrentThreadOnly: true)
    _ = try diff()
    allocations = RealSizeAllocations.stop().allocations
    #expect(allocations < 300, "Diffing the 64-line page allocated \(allocations) times (\(allocations / 64) a line).")
  }

  // MARK: - Helpers

  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()

  static func identity(_ triple: InstantTriple, encoder: JSONEncoder) throws -> LiveQueryOwnershipIdentity {
    LiveQueryOwnershipIdentity(
      entityID: triple.entityID, attributeID: triple.attributeID,
      valueJSON: try InstantStoredJSON.stored(triple.value, using: encoder)
    )
  }

  static func feed(_ row: LiveQueryOwnershipIdentity, to diff: inout LiveQueryOwnershipDiff) {
    let entity = Array(row.entityID.utf8)
    let attribute = Array(row.attributeID.utf8)
    let value = Array(row.valueJSON.utf8)
    entity.withUnsafeBufferPointer { entity in
      attribute.withUnsafeBufferPointer { attribute in
        value.withUnsafeBufferPointer { value in
          diff.previousRow(entityID: entity, attributeID: attribute, valueJSON: value)
        }
      }
    }
  }

  /// `lines` transcript lines of sixteen facts each; `changedLine`'s text and words differ.
  static func page(lines: Int, changedLine: Int?) -> [InstantTriple] {
    var facts: [InstantTriple] = []
    for line in 0..<lines {
      let id = "3f2a\(String(format: "%04d", line))-7c1e-4b8a-9d21-5e6f7a8b9c0d"
      let revision = line == changedLine ? "revised " : ""
      facts.append(triple(id, "transcriptionSegments/id", .string(id)))
      facts.append(triple(id, "transcriptionSegments/recordingID", .string("8b1d4c2e-0f3a-4d5b-8c6e-7f8091a2b3c4")))
      facts.append(triple(id, "transcriptionSegments/segmentIndex", .number(Double(line))))
      facts.append(triple(id, "transcriptionSegments/text", .string("\(revision)the words line \(line) says")))
      facts.append(triple(id, "transcriptionSegments/wordsJSON", .string(#"[{"w":"\#(revision)line","s":\#(line).25}]"#)))
      for field in 0..<11 {
        facts.append(triple(id, "transcriptionSegments/field-\(field)", .number(Double(line * 100 + field) + 0.5)))
      }
    }
    return facts
  }

  static func randomValue(_ random: inout InfiniteWindowRandom) -> InstantValue {
    switch random.int(0...6) {
    case 0: .string("text \(random.int(0...3))")
    case 1: .string("needs \"escaping\" / and \\ \(random.int(0...3))")
    case 2: .number(Double(random.int(0...5)) + (random.chance(50) ? 0.25 : 0))
    case 3: .bool(random.chance(50))
    case 4: .ref("ref-\(random.int(0...3))")
    case 5: .null
    default: .json(.object(["k": .number(Double(random.int(0...2)))]))
    }
  }

  static func triple(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> InstantTriple {
    InstantTriple(entityID: entityID, attributeID: attributeID, value: value, txID: "tx", txTime: InstantTimestamp(milliseconds: 1))
  }
}
