import Foundation

// History:
// - 2026-10-25: a stored result's ownership changes are worked out here, from the rows SQLite holds and the result that
//   replaces them, so the work is testable on one thread (#1147).

/// One fact a stored live-query result owns, as its ownership row names it: the value as the store keeps its text.
struct LiveQueryOwnershipIdentity: Hashable, Sendable {
  var entityID: String
  var attributeID: String
  var valueJSON: String
}

/// The ownership rows a stored result loses and gains when the facts it holds are replaced (#1147).
///
/// The rows SQLite holds stay the truth: they are handed in one at a time, as their columns' bytes, or all at once when
/// a save earlier in the same frame decided them.
struct LiveQueryOwnershipDiff {
  /// The rows the result no longer owns, in the store's order, once `finish()` ran.
  private(set) var removed: [LiveQueryOwnershipIdentity] = []
  /// The rows the result owns now and did not, in the store's order, once `finish()` ran.
  private(set) var inserted: [LiveQueryOwnershipIdentity] = []
  var isUnchanged: Bool { removed.isEmpty && inserted.isEmpty }

  private let next: Set<LiveQueryOwnershipIdentity>
  private var previous: Set<LiveQueryOwnershipIdentity> = []

  /// The diff against `next`, the facts the result holds now.
  init(next triples: [InstantTriple], encoder: JSONEncoder) throws {
    next = try Set(
      triples.map { triple in
        LiveQueryOwnershipIdentity(
          entityID: triple.entityID,
          attributeID: triple.attributeID,
          valueJSON: try InstantStoredJSON.stored(triple.value, using: encoder)
        )
      }
    )
  }

  /// One row the result owned: its entity id, attribute id and value text, as the store keeps them (UTF-8).
  mutating func previousRow(
    entityID: UnsafeBufferPointer<UInt8>,
    attributeID: UnsafeBufferPointer<UInt8>,
    valueJSON: UnsafeBufferPointer<UInt8>
  ) {
    previous.insert(
      LiveQueryOwnershipIdentity(
        entityID: String(decoding: entityID, as: UTF8.self),
        attributeID: String(decoding: attributeID, as: UTF8.self),
        valueJSON: String(decoding: valueJSON, as: UTF8.self)
      )
    )
  }

  /// Every row the result owned, as an earlier save in the same frame left them.
  mutating func previousRows(_ identities: Set<LiveQueryOwnershipIdentity>) {
    previous.formUnion(identities)
  }

  /// Works out `removed` and `inserted` from the rows handed in.
  mutating func finish() {
    removed = previous.subtracting(next).sorted(by: Self.storeOrder)
    inserted = next.subtracting(previous).sorted(by: Self.storeOrder)
  }

  /// The rows the result owns once this diff is applied, for a later save of the same result in the same frame.
  var nextRows: Set<LiveQueryOwnershipIdentity> { next }

  static func storeOrder(_ lhs: LiveQueryOwnershipIdentity, _ rhs: LiveQueryOwnershipIdentity) -> Bool {
    (lhs.entityID, lhs.attributeID, lhs.valueJSON) < (rhs.entityID, rhs.attributeID, rhs.valueJSON)
  }
}
