// History:
// - 2026-11-19: added (#2555, #2551): a size comparison reads only the shards it needs.

import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #2555 (#2551): `TripleIndexes.hasLink` and `linkedEntityIDs` probe a link from its smaller side, comparing a
/// many-valued slot's size with the page's entity count, and `ShardedDictionary.count` summed all 64 shards to do it, for
/// each observer on each write (66 innermost samples of a 3.6-hour trace's local-write path). A recording's slot holds
/// thousands of refs and a page tens of entities, so the comparison is settled within the first shard. These tests pin
/// that, and that the answer is `count > limit` whatever the dictionary holds.
@Suite
struct ShardedDictionaryCountReachingTests {
  /// A recording-sized slot (3,000 refs) against a page of 30 entities: one shard tells.
  @Test
  func aLargeSlotIsKnownToHoldMoreThanAPageAfterItsFirstShard() {
    var map = ShardedDictionary<InstantValue, Int>()
    for index in 0..<3_000 {
      map[.ref("line-\(index)")] = index
    }

    let reached = map.countReaching(30)

    #expect(reached.holdsMore)
    #expect(reached.shardsRead <= 2, "read \(reached.shardsRead) of 64 shards")
  }

  /// Every size from empty through the sharding threshold and past it, against limits around it: the same answer as
  /// `count > limit`.
  @Test
  func theAnswerIsCountAboveTheLimit() {
    var map = ShardedDictionary<String, Int>()
    for size in 0...200 {
      if size > 0 { map["key-\(size)"] = size }
      for limit in [0, 1, size - 1, size, size + 1, 31, 32, 33, 100, 1_000] where limit >= 0 {
        expectNoDifference(map.holdsMore(than: limit), map.count > limit, "size \(size), limit \(limit)")
      }
    }
    for size in stride(from: 200, through: 0, by: -1) {
      map.removeValue(forKey: "key-\(size)")
      for limit in [0, 1, 32, 100] {
        expectNoDifference(map.holdsMore(than: limit), map.count > limit, "after removals, size \(map.count), limit \(limit)")
      }
    }
  }
}
