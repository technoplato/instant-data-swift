import Foundation

// History:
// - 2026-10-23: the store's secondary indexes hold their entries in shards, so preparing a write copies the shards it
//   changes instead of whole maps (#1007).
// - 2026-10-24: a sharded dictionary keeps one plain dictionary until it holds more than 32 entries, so it can hold a
//   many-cardinality attribute's values: a recording links every line it holds, and each new line copied them all
//   (#1152).

/// How many shards a sharded collection splits its entries into.
///
/// A write is prepared on a copy of the store's indexes that shares their storage with the store, and its first change
/// to a collection copies what it changes. A collection in shards copies the array of shards (64 references) and the
/// shard that holds the changed entry: about a sixty-fourth of the entries instead of all of them (#1007).
private let shardCount = 64

/// Which shard holds `key`. The hash keeps equal keys together: strings compare by canonical equivalence, so their bytes
/// cannot choose the shard.
@inline(__always)
private func shardIndex(_ key: some Hashable) -> Int {
  key.hashValue & (shardCount - 1)
}

/// A set whose elements live in shards, so a change to a copy copies one shard (#1007).
struct ShardedSet<Element: Hashable>: Sequence, ExpressibleByArrayLiteral {
  /// Empty until the first insert, so an empty set costs nothing.
  private var shards: [Set<Element>] = []

  init() {}

  init(arrayLiteral elements: Element...) {
    for element in elements { insert(element) }
  }

  init(_ elements: some Sequence<Element>) {
    for element in elements { insert(element) }
  }

  var count: Int { shards.reduce(0) { $0 + $1.count } }
  var isEmpty: Bool { shards.allSatisfy(\.isEmpty) }

  func contains(_ element: Element) -> Bool {
    shards.isEmpty ? false : shards[shardIndex(element)].contains(element)
  }

  @discardableResult
  mutating func insert(_ element: Element) -> Bool {
    if shards.isEmpty { shards = Array(repeating: [], count: shardCount) }
    return shards[shardIndex(element)].insert(element).inserted
  }

  @discardableResult
  mutating func remove(_ element: Element) -> Element? {
    guard !shards.isEmpty else { return nil }
    return shards[shardIndex(element)].remove(element)
  }

  /// The elements both sets hold, shard by shard: equal elements share a shard in every sharded set.
  func intersection(_ other: ShardedSet<Element>) -> ShardedSet<Element> {
    guard !shards.isEmpty, !other.shards.isEmpty else { return ShardedSet() }
    var result = ShardedSet()
    result.shards = zip(shards, other.shards).map { $0.intersection($1) }
    return result
  }

  func makeIterator() -> FlattenSequence<[Set<Element>]>.Iterator {
    shards.joined().makeIterator()
  }

  /// The set's shard at `index`, or an empty one before the first insert.
  fileprivate func shard(at index: Int) -> Set<Element> {
    shards.isEmpty ? [] : shards[index]
  }
}

extension ShardedSet: Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    (0..<shardCount).allSatisfy { lhs.shard(at: $0) == rhs.shard(at: $0) }
  }
}

extension ShardedSet: Hashable {
  func hash(into hasher: inout Hasher) {
    for index in 0..<shardCount {
      hasher.combine(shard(at: index))
    }
  }
}

extension ShardedSet: Sendable where Element: Sendable {}

/// How many entries a sharded dictionary keeps in one plain dictionary before it moves them into shards.
///
/// A few entries cost less in one dictionary than in 64 shards, to keep and to copy whole: a many-cardinality attribute
/// with two values would otherwise hold an array of 64 (#1152). Past it, a change to a copy copies the array of shards
/// and the one shard it changes; at it, copying the one dictionary copies at most 32 entries.
private let dictionaryShardingThreshold = 32

/// A dictionary whose entries live in shards once it holds more than 32, so a change to a copy copies one shard (#1007,
/// #1152).
struct ShardedDictionary<Key: Hashable, Value>: Sequence, ExpressibleByDictionaryLiteral {
  /// Empty until the first insert; then one dictionary, until it holds more than `dictionaryShardingThreshold` entries;
  /// then `shardCount` shards for good, however many entries leave again. One array either way, so the dictionary is
  /// one reference wide wherever it is stored: the store keeps one per indexed attribute in maps that a prepared write
  /// copies.
  private var shards: [[Key: Value]] = []

  init() {}

  init(dictionaryLiteral elements: (Key, Value)...) {
    for (key, value) in elements { self[key] = value }
  }

  init(_ dictionary: [Key: Value]) {
    if dictionary.isEmpty { return }
    shards = dictionary.count <= dictionaryShardingThreshold ? [dictionary] : Self.shards(of: dictionary)
  }

  var count: Int { shards.reduce(0) { $0 + $1.count } }
  var isEmpty: Bool { shards.allSatisfy(\.isEmpty) }

  /// Whether the entries are in `shardCount` shards rather than one dictionary.
  private var isSharded: Bool { shards.count == shardCount }

  subscript(key: Key) -> Value? {
    get { shards.isEmpty ? nil : shards[isSharded ? shardIndex(key) : 0][key] }
    _modify {
      if isSharded {
        yield &shards[shardIndex(key)][key]
      } else {
        if shards.isEmpty { shards = [[:]] }
        defer { moveToShardsWhenFull() }
        yield &shards[0][key]
      }
    }
  }

  subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
    get { self[key] ?? defaultValue() }
    _modify {
      if isSharded {
        yield &shards[shardIndex(key)][key, default: defaultValue()]
      } else {
        if shards.isEmpty { shards = [[:]] }
        defer { moveToShardsWhenFull() }
        yield &shards[0][key, default: defaultValue()]
      }
    }
  }

  /// The same entries in one `Dictionary`, for coding.
  var dictionary: [Key: Value] {
    guard isSharded else { return shards.first ?? [:] }
    var dictionary: [Key: Value] = [:]
    dictionary.reserveCapacity(count)
    for (key, value) in self { dictionary[key] = value }
    return dictionary
  }

  var keys: LazyMapSequence<FlattenSequence<[[Key: Value]]>, Key> { shards.joined().lazy.map(\.key) }
  var values: LazyMapSequence<FlattenSequence<[[Key: Value]]>, Value> { shards.joined().lazy.map(\.value) }

  /// Any one entry, as `Dictionary.first` gives.
  var first: (key: Key, value: Value)? {
    var iterator = makeIterator()
    return iterator.next()
  }

  /// Does nothing: shards grow one at a time, and reserving room in a dictionary that a prepared copy shares with the
  /// store would copy it.
  func reserveCapacity(_ minimumCapacity: Int) {}

  @discardableResult
  mutating func removeValue(forKey key: Key) -> Value? {
    guard !shards.isEmpty else { return nil }
    return shards[isSharded ? shardIndex(key) : 0].removeValue(forKey: key)
  }

  func makeIterator() -> FlattenSequence<[[Key: Value]]>.Iterator {
    shards.joined().makeIterator()
  }

  private mutating func moveToShardsWhenFull() {
    guard shards.count == 1, shards[0].count > dictionaryShardingThreshold else { return }
    shards = Self.shards(of: shards[0])
  }

  private static func shards(of dictionary: [Key: Value]) -> [[Key: Value]] {
    var shards = Array(repeating: [Key: Value](), count: shardCount)
    for (key, value) in dictionary { shards[shardIndex(key)][key] = value }
    return shards
  }
}

extension ShardedDictionary: Equatable where Value: Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    // Equal keys share a shard in every sharded dictionary.
    if lhs.isSharded, rhs.isSharded { return lhs.shards == rhs.shards }
    return lhs.count == rhs.count && lhs.allSatisfy { rhs[$0.key] == $0.value }
  }
}

extension ShardedDictionary: Hashable where Value: Hashable {
  /// Independent of the entries' order and of whether they are in shards, so equal dictionaries hash alike.
  func hash(into hasher: inout Hasher) {
    var entries = 0
    for (key, value) in self {
      var entry = Hasher()
      entry.combine(key)
      entry.combine(value)
      entries ^= entry.finalize()
    }
    hasher.combine(count)
    hasher.combine(entries)
  }
}

extension ShardedDictionary: Sendable where Key: Sendable, Value: Sendable {}

/// Coded as the `Dictionary` holding the same entries, whether or not they are in shards.
extension ShardedDictionary: Codable where Key: Codable, Value: Codable {
  init(from decoder: any Decoder) throws {
    self.init(try [Key: Value](from: decoder))
  }

  func encode(to encoder: any Encoder) throws {
    try dictionary.encode(to: encoder)
  }
}
