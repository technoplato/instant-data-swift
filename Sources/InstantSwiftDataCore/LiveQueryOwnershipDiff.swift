import Foundation

// History:
// - 2026-10-25: a stored result's ownership changes are worked out here, from the rows SQLite holds and the result that
//   replaces them, so the work is testable on one thread (#1147).
// - 2026-10-25: rows are compared by 128-bit fingerprints of their bytes: a row that stays costs a hash, not three
//   strings, and a fact that stays a hash of its value's text written into one reused buffer, not a string. On a
//   64-line page with one line changed that was about 5,000 allocations a refresh (#1147).

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

  /// The diff against `next`, the facts the result holds now.
  init(next triples: [InstantTriple], encoder: JSONEncoder) throws {
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
