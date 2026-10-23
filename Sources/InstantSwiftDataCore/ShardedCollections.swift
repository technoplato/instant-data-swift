import Foundation

// History:
// - 2026-10-23: the store's secondary indexes hold their entries in shards, so preparing a write copies the shards it
//   changes instead of whole maps (#1007).

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

/// A dictionary whose entries live in shards, so a change to a copy copies one shard (#1007).
struct ShardedDictionary<Key: Hashable, Value>: Sequence, ExpressibleByDictionaryLiteral {
  /// Empty until the first insert, so an empty dictionary costs nothing.
  private var shards: [[Key: Value]] = []

  init() {}

  init(dictionaryLiteral elements: (Key, Value)...) {
    for (key, value) in elements { self[key] = value }
  }

  var count: Int { shards.reduce(0) { $0 + $1.count } }
  var isEmpty: Bool { shards.allSatisfy(\.isEmpty) }

  subscript(key: Key) -> Value? {
    get { shards.isEmpty ? nil : shards[shardIndex(key)][key] }
    _modify {
      if shards.isEmpty { shards = Array(repeating: [:], count: shardCount) }
      yield &shards[shardIndex(key)][key]
    }
  }

  subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
    get { self[key] ?? defaultValue() }
    _modify {
      if shards.isEmpty { shards = Array(repeating: [:], count: shardCount) }
      yield &shards[shardIndex(key)][key, default: defaultValue()]
    }
  }

  init(_ dictionary: [Key: Value]) {
    for (key, value) in dictionary { self[key] = value }
  }

  /// The same entries in one `Dictionary`, for coding.
  var dictionary: [Key: Value] {
    var dictionary: [Key: Value] = [:]
    dictionary.reserveCapacity(count)
    for (key, value) in self { dictionary[key] = value }
    return dictionary
  }

  var keys: LazyMapSequence<FlattenSequence<[[Key: Value]]>, Key> { shards.joined().lazy.map(\.key) }
  var values: LazyMapSequence<FlattenSequence<[[Key: Value]]>, Value> { shards.joined().lazy.map(\.value) }

  /// Shards grow one at a time; reserving room for all of them would allocate every shard.
  func reserveCapacity(_ minimumCapacity: Int) {}

  @discardableResult
  mutating func removeValue(forKey key: Key) -> Value? {
    guard !shards.isEmpty else { return nil }
    return shards[shardIndex(key)].removeValue(forKey: key)
  }

  func makeIterator() -> FlattenSequence<[[Key: Value]]>.Iterator {
    shards.joined().makeIterator()
  }

  /// The dictionary's shard at `index`, or an empty one before the first insert.
  fileprivate func shard(at index: Int) -> [Key: Value] {
    shards.isEmpty ? [:] : shards[index]
  }
}

extension ShardedDictionary: Equatable where Value: Equatable {
  static func == (lhs: Self, rhs: Self) -> Bool {
    (0..<shardCount).allSatisfy { lhs.shard(at: $0) == rhs.shard(at: $0) }
  }
}

extension ShardedDictionary: Hashable where Value: Hashable {
  func hash(into hasher: inout Hasher) {
    for index in 0..<shardCount {
      hasher.combine(shard(at: index))
    }
  }
}

extension ShardedDictionary: Sendable where Key: Sendable, Value: Sendable {}
