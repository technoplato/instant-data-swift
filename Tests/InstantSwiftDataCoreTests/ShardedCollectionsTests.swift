import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: the store's secondary indexes keep their entries in shards so a prepared write copies only what it changes.
/// A sharded set and a sharded dictionary answer every question exactly as a `Set` and a `Dictionary` holding the same
/// entries do, and a copy changes independently of the value it was copied from.
///
/// #1152: a sharded dictionary keeps one plain dictionary until it holds more than 32 entries, so a many-cardinality
/// slot can use one. Whichever form it holds, it answers, compares, hashes and codes as the plain dictionary does.
@Suite
struct ShardedCollectionsTests {
  @Test(arguments: [UInt64(71_007), 71_008, 71_009])
  func aShardedSetAnswersAsASet(seed: UInt64) {
    var random = InfiniteWindowRandom(seed: seed)
    var sharded = ShardedSet<String>()
    var plain = Set<String>()
    var copies: [(ShardedSet<String>, Set<String>)] = []
    for step in 0..<3_000 {
      // Canonically equivalent spellings must count as one element, as `Set` counts them.
      let element = ["id-\(random.int(0...400))", "e\u{301}-\(random.int(0...3))", "\u{E9}-\(random.int(0...3))",
        "K", "\u{212A}"][random.int(0...4)]
      switch random.int(0...9) {
      case 0...5:
        expectNoDifference(sharded.insert(element), plain.insert(element).inserted, "step \(step)")
      case 6...8:
        expectNoDifference(sharded.remove(element), plain.remove(element), "step \(step)")
      default:
        copies.append((sharded, plain))
      }
      #expect(sharded.contains(element) == plain.contains(element))
    }
    expectNoDifference(sharded.count, plain.count)
    expectNoDifference(sharded.isEmpty, plain.isEmpty)
    expectNoDifference(Set(sharded), plain)
    expectNoDifference(sharded.sorted(), plain.sorted())
    // Every copy kept what it held when it was taken.
    for (shardedCopy, plainCopy) in copies {
      expectNoDifference(Set(shardedCopy), plainCopy)
      expectNoDifference(shardedCopy == ShardedSet(plainCopy), true)
      expectNoDifference(shardedCopy.hashValue == ShardedSet(plainCopy).hashValue, true)
    }
    if let (first, firstPlain) = copies.first, let (last, lastPlain) = copies.last {
      expectNoDifference(Set(first.intersection(last)), firstPlain.intersection(lastPlain))
      expectNoDifference(first == last, firstPlain == lastPlain)
    }
    expectNoDifference(ShardedSet<String>() == [], true)
    expectNoDifference(ShardedSet<String>().hashValue == ShardedSet<String>(["x"]).intersection([]).hashValue, true)
  }

  @Test(arguments: [UInt64(72_007), 72_008, 72_009])
  func aShardedDictionaryAnswersAsADictionary(seed: UInt64) {
    var random = InfiniteWindowRandom(seed: seed)
    var sharded = ShardedDictionary<InstantValue, Int>()
    var plain: [InstantValue: Int] = [:]
    var copies: [(ShardedDictionary<InstantValue, Int>, [InstantValue: Int])] = []
    for step in 0..<3_000 {
      let key: InstantValue = switch random.int(0...4) {
      case 0: .number(Double(random.int(0...300)))
      case 1: .number(random.chance(50) ? 0.0 : -0.0)
      case 2: .string("s-\(random.int(0...300))")
      case 3: .ref(["K", "\u{212A}", "e\u{301}", "\u{E9}"][random.int(0...3)])
      default: .bool(random.chance(50))
      }
      switch random.int(0...9) {
      case 0...4:
        let value = random.int(0...1_000)
        sharded[key] = value
        plain[key] = value
      case 5...6:
        sharded[key, default: 0] += 1
        plain[key, default: 0] += 1
      case 7...8:
        sharded[key] = nil
        plain[key] = nil
      default:
        copies.append((sharded, plain))
      }
      expectNoDifference(sharded[key], plain[key], "step \(step)")
    }
    expectNoDifference(sharded.count, plain.count)
    expectNoDifference(sharded.isEmpty, plain.isEmpty)
    expectNoDifference(Dictionary(uniqueKeysWithValues: sharded.map { ($0.key, $0.value) }), plain)
    for (shardedCopy, plainCopy) in copies {
      expectNoDifference(Dictionary(uniqueKeysWithValues: shardedCopy.map { ($0.key, $0.value) }), plainCopy)
    }
    if let (first, firstPlain) = copies.first, let (last, lastPlain) = copies.last {
      expectNoDifference(first == last, firstPlain == lastPlain)
    }
    let empty: ShardedDictionary<InstantValue, Int> = [:]
    expectNoDifference(empty == ShardedDictionary(), true)
    expectNoDifference(empty.hashValue == ShardedDictionary<InstantValue, Int>().hashValue, true)
  }

  /// A dictionary that outgrew 32 entries and shrank again keeps its shards; one built with the same entries does not.
  /// The two answer, compare, hash and code alike, and as the plain dictionary does, at every size around the threshold.
  @Test(arguments: [0, 1, 31, 32, 33, 34, 130, 2_318])
  func eitherFormAnswersAsTheSameDictionary(entries: Int) throws {
    let plain = Dictionary(uniqueKeysWithValues: (0..<entries).map { (InstantValue.ref("line-\($0)"), $0) })
    var shrunk = ShardedDictionary<InstantValue, Int>()
    for index in 0..<max(entries, 200) { shrunk[.ref("line-\(index)")] = index }
    for index in entries..<max(entries, 200) { shrunk[.ref("line-\(index)")] = nil }
    let built = ShardedDictionary(plain)
    var literal: ShardedDictionary<InstantValue, Int> = [:]
    for (key, value) in plain { literal[key, default: -1] = value }

    for form in [shrunk, built, literal] {
      expectNoDifference(form.count, plain.count)
      expectNoDifference(form.isEmpty, plain.isEmpty)
      expectNoDifference(form.dictionary, plain)
      expectNoDifference(Dictionary(uniqueKeysWithValues: form.map { ($0.key, $0.value) }), plain)
      expectNoDifference(Set(form.keys), Set(plain.keys))
      expectNoDifference(form.values.sorted(), plain.values.sorted())
      expectNoDifference(form.first.map { plain[$0.key] == $0.value } ?? plain.isEmpty, true)
      expectNoDifference(form == shrunk, true)
      expectNoDifference(form.hashValue, shrunk.hashValue)
      let coded = try JSONDecoder().decode([InstantValue: Int].self, from: JSONEncoder().encode(form))
      expectNoDifference(coded, plain)
      let decoded = try JSONDecoder().decode(ShardedDictionary<InstantValue, Int>.self, from: JSONEncoder().encode(plain))
      expectNoDifference(decoded == form, true)
    }
    if entries > 0 {
      var changed = built
      changed[.ref("line-0")] = -1
      expectNoDifference(changed == shrunk, false)
      expectNoDifference(built[.ref("line-0")], 0)
    }
  }

  /// One reference wide, as before it gained its small mode: the store keeps one per indexed attribute in maps that a
  /// prepared write copies whole, so a wider dictionary would make every write copy more.
  @Test func aShardedDictionaryIsOneReferenceWide() {
    expectNoDifference(MemoryLayout<ShardedDictionary<InstantValue, ShardedSet<String>>>.size, MemoryLayout<Int>.size)
    expectNoDifference(MemoryLayout<ShardedDictionary<String, InstantValue>>.size, MemoryLayout<Int>.size)
  }

  /// A many-cardinality slot codes as it did when its values were a plain dictionary, both ways.
  @Test(arguments: [2, 33, 2_318])
  func aManySlotCodesAsItsPlainDictionaryDid(values: Int) throws {
    let stamps = Dictionary(
      uniqueKeysWithValues: (0..<values).map {
        (InstantValue.ref("line-\($0)"), InstantTripleStamp(txIDIndex: UInt32($0 % 7), txTimeMilliseconds: Int64($0)))
      }
    )
    let slot = AttrSlot.many(ShardedDictionary(stamps))
    let legacy = try JSONDecoder().decode(LegacyAttrSlot.self, from: JSONEncoder().encode(slot))
    expectNoDifference(legacy, .many(stamps))
    let decoded = try JSONDecoder().decode(AttrSlot.self, from: JSONEncoder().encode(LegacyAttrSlot.many(stamps)))
    expectNoDifference(decoded == slot, true)
    expectNoDifference(decoded.count, values)
  }

  /// `AttrSlot` as it was coded before #1152 moved its many values into a sharded dictionary.
  private enum LegacyAttrSlot: Codable, Equatable {
    case one(value: InstantValue, stamp: InstantTripleStamp)
    case many([InstantValue: InstantTripleStamp])
  }
}
