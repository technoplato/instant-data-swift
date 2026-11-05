import Foundation

// History:
// - 2026-10-25: a stored result's ownership changes are worked out here, from the rows SQLite holds and the result that
//   replaces them, so the work is testable on one thread (#1147).
// - 2026-10-25: rows are compared by 128-bit fingerprints of their bytes: a row that stays costs a hash, not three
//   strings, and a fact that stays a hash of its value's text written into one reused buffer, not a string. On a
//   64-line page with one line changed that was about 5,000 allocations a refresh (#1147).
// - 2026-11-04: a diff reports its distinct facts, so a server apply's save takes the retractions' diff of the same facts
//   instead of making its own (#1480).
// - 2026-11-05: `LiveQueryEntityFingerprints`, each entity's facts folded into one fingerprint, so a refresh compares only
//   the entities it changed with the rows SQLite holds; a diff of those entities reports the whole result's distinct
//   facts (#1116).

/// One fact a stored live-query result owns, as its ownership row names it: the value as the store keeps its text.
struct LiveQueryOwnershipIdentity: Hashable, Sendable {
  var entityID: String
  var attributeID: String
  var valueJSON: String
}

/// The ownership rows a stored result loses and gains when the facts it holds are replaced (#1147).
///
/// The rows SQLite holds stay the truth: they are handed in one at a time, as their columns' bytes, or as the facts a
/// save earlier in the same frame stored. A row and a fact match when the fingerprints of their entity id, attribute id
/// and value text match (two independently seeded 64-bit hashes of the bytes, so a false match needs both to collide).
/// Only the rows that leave and the facts that join are made into strings.
struct LiveQueryOwnershipDiff {
  /// The rows the result no longer owns, in the store's order, once `finish()` ran.
  private(set) var removed: [LiveQueryOwnershipIdentity] = []
  /// The rows the result owns now and did not, in the store's order, once `finish()` ran.
  private(set) var inserted: [LiveQueryOwnershipIdentity] = []
  var isUnchanged: Bool { removed.isEmpty && inserted.isEmpty }
  /// How many distinct facts the result holds now (#1480): a save checks it compares the facts it saves. A diff of the
  /// changed entities' facts only reports the whole result's count it was given (#1116).
  var distinctFactCount: Int { wholeResultDistinctFactCount ?? factIndexByFingerprint.count }
  /// The entity fingerprints of the facts the result holds now, when the store worked them out (#1116): a save that
  /// takes this diff stores the same facts, and its commit keeps these for the next refresh.
  var entityFingerprints: LiveQueryEntityFingerprints?

  private struct Fingerprint: Hashable {
    var first: Int
    var second: Int
  }

  private let facts: [InstantTriple]
  private let encoder: JSONEncoder
  /// Each distinct new fact's fingerprint and the index of its first occurrence in `facts`.
  private var factIndexByFingerprint: [Fingerprint: Int] = [:]
  /// Whether a stored row holds `facts[index]`, for the first occurrence of each distinct fact.
  private var held: [Bool]
  private var removedRows: [LiveQueryOwnershipIdentity] = []
  /// The rows as identities, when an earlier save in the frame decided them; the diff is then by identity.
  private var previousIdentities: Set<LiveQueryOwnershipIdentity>?
  /// The whole result's distinct facts, when `facts` are only those of the entities that changed (#1116).
  private let wholeResultDistinctFactCount: Int?

  /// The diff against `next`, the facts the result holds now.
  ///
  /// - Parameter wholeResultDistinctFactCount: When `next` holds only the facts of the entities that changed, and the
  ///   rows handed in are only those entities' rows, how many distinct facts the whole result holds (#1116).
  init(next triples: [InstantTriple], encoder: JSONEncoder, wholeResultDistinctFactCount: Int? = nil) throws {
    self.wholeResultDistinctFactCount = wholeResultDistinctFactCount
    facts = triples
    self.encoder = encoder
    held = Array(repeating: false, count: triples.count)
    factIndexByFingerprint.reserveCapacity(triples.count)
    var valueText: [UInt8] = []
    valueText.reserveCapacity(256)
    for (index, triple) in triples.enumerated() {
      valueText.removeAll(keepingCapacity: true)
      try InstantStoredJSON.appendStored(triple.value, to: &valueText, using: encoder)
      let fingerprint = valueText.withUnsafeBufferPointer { value in
        Self.withUTF8(triple.entityID) { entity in
          Self.withUTF8(triple.attributeID) { attribute in
            Self.fingerprint(entity, attribute, value)
          }
        }
      }
      if factIndexByFingerprint[fingerprint] == nil {
        factIndexByFingerprint[fingerprint] = index
      }
    }
  }

  /// One row the result owned: its entity id, attribute id and value text, as the store keeps them (UTF-8).
  mutating func previousRow(
    entityID: UnsafeBufferPointer<UInt8>,
    attributeID: UnsafeBufferPointer<UInt8>,
    valueJSON: UnsafeBufferPointer<UInt8>
  ) {
    if let index = factIndexByFingerprint[Self.fingerprint(entityID, attributeID, valueJSON)] {
      held[index] = true
    } else {
      removedRows.append(
        LiveQueryOwnershipIdentity(
          entityID: String(decoding: entityID, as: UTF8.self),
          attributeID: String(decoding: attributeID, as: UTF8.self),
          valueJSON: String(decoding: valueJSON, as: UTF8.self)
        )
      )
    }
  }

  /// Every row the result owned, as identities.
  mutating func previousRows(_ identities: Set<LiveQueryOwnershipIdentity>) {
    previousIdentities = (previousIdentities ?? []).union(identities)
  }

  /// Every row the result owned, as the facts a save earlier in the same frame stored.
  mutating func previousFacts(_ triples: [InstantTriple]) throws {
    previousRows(Set(try triples.map(identity(of:))))
  }

  /// Works out `removed` and `inserted` from the rows handed in.
  mutating func finish() throws {
    if let previousIdentities {
      let next = try nextRows()
      removed = previousIdentities.subtracting(next).sorted(by: Self.storeOrder)
      inserted = next.subtracting(previousIdentities).sorted(by: Self.storeOrder)
      return
    }
    removed = removedRows.sorted(by: Self.storeOrder)
    var joined: [LiveQueryOwnershipIdentity] = []
    for index in factIndexByFingerprint.values where !held[index] {
      joined.append(try identity(of: facts[index]))
    }
    inserted = joined.sorted(by: Self.storeOrder)
  }

  /// The rows the result owns once this diff is applied, made into strings.
  func nextRows() throws -> Set<LiveQueryOwnershipIdentity> {
    Set(try facts.map(identity(of:)))
  }

  static func storeOrder(_ lhs: LiveQueryOwnershipIdentity, _ rhs: LiveQueryOwnershipIdentity) -> Bool {
    (lhs.entityID, lhs.attributeID, lhs.valueJSON) < (rhs.entityID, rhs.attributeID, rhs.valueJSON)
  }

  private func identity(of triple: InstantTriple) throws -> LiveQueryOwnershipIdentity {
    LiveQueryOwnershipIdentity(
      entityID: triple.entityID,
      attributeID: triple.attributeID,
      valueJSON: try InstantStoredJSON.stored(triple.value, using: encoder)
    )
  }

  private static func fingerprint(
    _ entity: UnsafeBufferPointer<UInt8>,
    _ attribute: UnsafeBufferPointer<UInt8>,
    _ value: UnsafeBufferPointer<UInt8>
  ) -> Fingerprint {
    var first = Hasher()
    var second = Hasher()
    // A different start, so the two hashes are independent.
    second.combine(0x9E37_79B9_7F4A_7C15 as UInt64)
    combine(entity, into: &first, &second)
    combine(attribute, into: &first, &second)
    combine(value, into: &first, &second)
    return Fingerprint(first: first.finalize(), second: second.finalize())
  }

  /// Each part's length, then its bytes: "ab" + "c" and "a" + "bc" differ.
  private static func combine(_ part: UnsafeBufferPointer<UInt8>, into first: inout Hasher, _ second: inout Hasher) {
    first.combine(part.count)
    first.combine(bytes: UnsafeRawBufferPointer(part))
    second.combine(part.count)
    second.combine(bytes: UnsafeRawBufferPointer(part))
  }

  private static func withUTF8<Result>(_ string: String, _ body: (UnsafeBufferPointer<UInt8>) -> Result) -> Result {
    if let result = string.utf8.withContiguousStorageIfAvailable(body) { return result }
    return Array(string.utf8).withUnsafeBufferPointer(body)
  }
}

/// Each entity's facts in a live-query result, folded into one fingerprint (#1116).
///
/// A stored result keeps the fingerprints its last save left in memory, so the next refresh of it compares only the
/// entities whose fold changed with the rows SQLite holds, and encodes only their values: one comparison a refresh read
/// every stored row and encoded every restated value, 6.39 ms of serverApplyRetractions per refresh-ok on the phone
/// (build 253, 1,596 frames). The rows stay the truth: an entity whose fold matches holds the same facts, and any other
/// is compared row by row, as before.
///
/// A fact's fingerprint is two independently seeded 64-bit hashes of its entity id, attribute id and value, as the diff
/// fingerprints a row; an entity's fold is the wrapping sum of its distinct facts' fingerprints and their count, so it
/// does not depend on their order. Values are hashed as `InstantValue`s, not as the text the store keeps: two values
/// that keep the same text but differ as values read as a change, which the row comparison then settles.
struct LiveQueryEntityFingerprints: Sendable {
  /// One entity's distinct facts, summed.
  struct Fold: Equatable, Sendable {
    var first: UInt64 = 0
    var second: UInt64 = 0
    var count = 0

    fileprivate mutating func add(_ fact: Fact) {
      first &+= UInt64(UInt(bitPattern: fact.first))
      second &+= UInt64(UInt(bitPattern: fact.second))
      count += 1
    }

    fileprivate mutating func add(_ other: Fold) {
      first &+= other.first
      second &+= other.second
      count += other.count
    }
  }

  fileprivate struct Fact: Hashable {
    var first: Int
    var second: Int
  }

  /// Each entity the result holds a fact of, and its fold.
  private(set) var byEntity: [String: Fold] = [:]
  /// How many distinct facts the result holds.
  private(set) var distinctFactCount = 0

  init(_ triples: [InstantTriple]) {
    var seen = Set<Fact>(minimumCapacity: triples.count)
    // A result lists each entity's facts together, so the fold of the entity being read is kept here and added to the
    // map when the entity changes: one map update an entity rather than one a fact.
    var currentEntityID: String?
    var current = Fold()
    for triple in triples {
      var first = Hasher()
      var second = Hasher()
      // A different start, so the two hashes are independent.
      second.combine(0x9E37_79B9_7F4A_7C15 as UInt64)
      first.combine(triple.entityID)
      second.combine(triple.entityID)
      first.combine(triple.attributeID)
      second.combine(triple.attributeID)
      first.combine(triple.value)
      second.combine(triple.value)
      let fact = Fact(first: first.finalize(), second: second.finalize())
      guard seen.insert(fact).inserted else { continue }
      if triple.entityID != currentEntityID {
        if let currentEntityID { byEntity[currentEntityID, default: Fold()].add(current) }
        currentEntityID = triple.entityID
        current = Fold()
      }
      current.add(fact)
    }
    if let currentEntityID { byEntity[currentEntityID, default: Fold()].add(current) }
    distinctFactCount = seen.count
  }

  /// The entities whose facts differ between this result and `next`: those that joined, left or changed.
  func entitiesChanged(in next: LiveQueryEntityFingerprints) -> Set<String> {
    var changed: Set<String> = []
    for (entityID, fold) in next.byEntity where byEntity[entityID] != fold {
      changed.insert(entityID)
    }
    for entityID in byEntity.keys where next.byEntity[entityID] == nil {
      changed.insert(entityID)
    }
    return changed
  }
}
