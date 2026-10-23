import CustomDump
import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: a forward link stores every linked id as one value of a many-cardinality attribute on the linking entity, so a
/// long recording holds thousands of values in each link (its lines, attachments, events, audio chunks). Materializing
/// such an entity sorted each link's values by building both values' sort keys inside every comparison: two string
/// allocations per step, about 2 n log n for n values. Every read of the entity paid it again, cached or not, so a
/// refresh of an observer showing a long recording spent most of its time in that sort. Built once per value, the keys
/// cost about one string each, and the order is the same.
@Suite(.serialized)
struct InstantManyCardinalitySortCostTests {
  /// Materializing an entity lists a link's values in `comparableKey` order, whatever their kinds.
  @Test(arguments: [UInt64(1_007), 1_008, 1_009])
  func aLinkSetMaterializesInComparableKeyOrder(seed: UInt64) throws {
    var random = InfiniteWindowRandom(seed: seed)
    var values: [InstantValue] = []
    for index in 0..<300 {
      switch random.int(0...6) {
      case 0: values.append(.ref(UUID(uuidString: Self.uuidString(seed: seed, index: index))!.uuidString.lowercased()))
      case 1: values.append(.string(["b", "a", "B", "é", "e\u{301}", "10", "9", ""][random.int(0...7)] + "\(index)"))
      case 2: values.append(.number(Double(random.int(-50...50)) / 4))
      case 3: values.append(.bool(random.chance(50)))
      case 4: values.append(.date(Date(timeIntervalSince1970: Double(random.int(0...1_000_000)))))
      case 5: values.append(.json(.object(["index": .number(Double(index)), "kind": .string("j")])))
      default: values.append(.null)
      }
    }
    let (indexes, attributes) = Self.store(holding: values, in: Self.mixedAttribute)
    let snapshot = try #require(
      indexes.entitySnapshot("recording", plan: Self.plan, attributes: attributes)
    )
    let unique = Array(Set(values))
    expectNoDifference(
      snapshot.values[Self.mixedAttribute.name],
      .many(unique.sorted { $0.comparableKey < $1.comparableKey })
    )
  }

  /// A link's ids sort as their keys do, whatever Unicode they hold: leading combining marks, decomposed and precomposed
  /// forms, Hangul jamo, ligatures, emoji sequences.
  @Test(arguments: [UInt64(2_007), 2_008, 2_009])
  func linkIDsMaterializeInComparableKeyOrderWhateverUnicodeTheyHold(seed: UInt64) throws {
    var random = InfiniteWindowRandom(seed: seed)
    let pieces = [
      "a", "B", "z", "\u{301}", "\u{301}\u{323}", "\u{323}\u{301}", "e\u{301}", "\u{E9}", "A\u{30A}", "\u{C5}",
      "\u{1100}", "\u{1161}", "\u{AC00}", "\u{FB01}", "fi", "\u{1F469}\u{200D}\u{1F4BB}", "0", "9", ":", "-", "",
    ]
    var ids: [String] = []
    for index in 0..<400 {
      var id = ""
      for _ in 0..<random.int(1...4) { id += pieces[random.int(0...(pieces.count - 1))] }
      ids.append(id + (random.chance(30) ? "" : "\(index)"))
    }
    let values = ids.map(InstantValue.ref)
    let (indexes, attributes) = Self.store(holding: values, in: Self.linkAttribute)
    let snapshot = try #require(
      indexes.entitySnapshot("recording", plan: Self.plan, attributes: attributes)
    )
    let unique = Array(Set(values))
    expectNoDifference(
      snapshot.values[Self.linkAttribute.name],
      .many(unique.sorted { $0.comparableKey < $1.comparableKey })
    )
  }

  /// Materializing a recording with 4,000 linked lines costs about as much CPU as building one sort key per line, not
  /// the dozens per line a comparator that builds both keys spends.
  @Test
  func materializingALinkSetBuildsAboutOneSortKeyPerValue() throws {
    let values = (0..<4_000).map { InstantValue.ref(Self.uuidString(seed: 1_007, index: $0)) }
    let (indexes, attributes) = Self.store(holding: values, in: Self.linkAttribute)
    let rounds = 5
    // Warm both paths, so neither pays a first-use cost inside its measurement.
    _ = try #require(indexes.entitySnapshot("recording", plan: Self.plan, attributes: attributes))
    var keyLength = 0
    for value in values { keyLength &+= value.comparableKey.utf8.count }

    let materializing = Self.threadCPUNanoseconds {
      for _ in 0..<rounds {
        _ = indexes.entitySnapshot("recording", plan: Self.plan, attributes: attributes)
      }
    }
    let buildingEachKeyOnce = Self.threadCPUNanoseconds {
      for _ in 0..<rounds {
        for value in values { keyLength &+= value.comparableKey.utf8.count }
      }
    }
    #expect(keyLength > 0)
    // About 28 when the comparator builds both keys (v1.9.12); under 10 when no key is built per comparison.
    let ratio = Double(materializing) / Double(max(buildingEachKeyOnce, 1))
    // The comparator that built both keys measured 27.9; the fix about 3-10, nearer 10 while a whole bundle runs beside it
    // (#1021), so the bound leaves room for that load and still fails on the old comparator.
    #expect(ratio < 20, "materializing cost \(ratio) times building each sort key once")
  }

  // MARK: - Helpers

  static let namespace = "sortCostRecordings"

  static let linkAttribute = InstantAttribute(
    id: "\(namespace)/segments",
    namespace: namespace,
    name: "segments",
    valueType: .ref,
    cardinality: .many,
    isIndexed: true,
    forwardIdentity: "\(namespace)/segments",
    reverseIdentity: "sortCostSegments/recording",
    linkNamespace: "sortCostSegments"
  )

  static let mixedAttribute = InstantAttribute(
    id: "\(namespace)/labels",
    namespace: namespace,
    name: "labels",
    valueType: .any,
    cardinality: .many
  )

  static let plan = InstantQueryPlan(id: "sortCost.recording", namespace: namespace)

  static func store(
    holding values: [InstantValue],
    in attribute: InstantAttribute
  ) -> (TripleIndexes, AttributeStore) {
    let attributes = AttributeStore(attributes: [.primaryKey(namespace: namespace), attribute])
    var indexes = TripleIndexes(attributes: attributes)
    var time: Int64 = 1
    func insert(_ attributeID: String, _ value: InstantValue) {
      indexes.apply(
        .insert(
          InstantTriple(
            entityID: "recording",
            attributeID: attributeID,
            value: value,
            txID: "tx-\(time)",
            txTime: InstantTimestamp(milliseconds: time)
          )
        ),
        attributes: attributes
      )
      time += 1
    }
    insert(InstantAttribute.primaryKeyID(namespace: namespace), .string("recording"))
    for value in values {
      insert(attribute.id, value)
    }
    return (indexes, attributes)
  }

  /// A UUID-shaped id, as Scribe's rows have: long enough that its sort key is a heap string.
  static func uuidString(seed: UInt64, index: Int) -> String {
    let high = String(format: "%08x", UInt32(truncatingIfNeeded: seed &* 2_654_435_761 &+ UInt64(index)))
    let low = String(format: "%012x", UInt64(index) &* 40_503 &+ 7)
    return "\(high)-0000-4000-8000-\(low)"
  }

  static func threadCPUNanoseconds(_ work: () -> Void) -> UInt64 {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    work()
    return clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start
  }
}
