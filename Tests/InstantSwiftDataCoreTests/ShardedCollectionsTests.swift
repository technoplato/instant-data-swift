import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: the store's secondary indexes keep their entries in shards so a prepared write copies only what it changes.
/// A sharded set and a sharded dictionary answer every question exactly as a `Set` and a `Dictionary` holding the same
/// entries do, and a copy changes independently of the value it was copied from.
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
}
