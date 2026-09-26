import Foundation

/// The stored facts of one entity that a prepared mutation may have changed.
///
/// Upstream never needs this. `Reactor` keeps each query's server result in its own store and
/// layers pending mutations on top when it reads (`Reactor.dataForQuery` →
/// `_applyOptimisticUpdates`), so a rejected mutation is removed and the view is simply
/// recomputed (`_handleMutationError`). Swift keeps one materialized store and persists it, so
/// every prepared mutation must name what to persist and what its inverse is.
///
/// Naming the touched facts rather than whole entities keeps a write's cost proportional to
/// what it wrote. Scribe stores one `recordings/segments` link per transcript segment on the
/// recording, so whole-entity bookkeeping copied, sorted, and re-persisted every link each time
/// a segment or recording summary was written.
package enum InstantEntityFactScope: Sendable, Equatable {
  /// Every fact of the entity: deletes, schema reconciliation, or a change the store did not
  /// attribute to specific facts.
  case wholeEntity

  /// Every value of `attributeIDs` (single-value attributes and merges) plus the listed values
  /// of multi-value attributes. Both empty when only a reverse reference to the entity changed.
  case facts(attributeIDs: Set<String>, values: [String: Set<InstantValue>])

  package static let noStoredFacts = InstantEntityFactScope.facts(attributeIDs: [], values: [:])

  package func contains(_ triple: InstantTriple) -> Bool {
    switch self {
    case .wholeEntity:
      return true
    case let .facts(attributeIDs, values):
      return attributeIDs.contains(triple.attributeID)
        || values[triple.attributeID]?.contains(triple.value) == true
    }
  }

  // The mutators below reset `self` before changing the extracted collections so they are
  // uniquely referenced and grow in place. Rebuilding the payload instead copied every
  // collection once per recorded fact, which is quadratic for many values of one attribute.

  package mutating func formUnion(_ other: InstantEntityFactScope) {
    guard case .facts(var attributeIDs, var values) = self else { return }
    guard case let .facts(otherAttributeIDs, otherValues) = other else {
      self = .wholeEntity
      return
    }
    self = .wholeEntity
    attributeIDs.formUnion(otherAttributeIDs)
    for (attributeID, attributeValues) in otherValues {
      values[attributeID, default: []].formUnion(attributeValues)
    }
    self = .facts(attributeIDs: attributeIDs, values: values)
  }

  package mutating func insert(attributeID: String) {
    guard case .facts(var attributeIDs, let values) = self else { return }
    self = .wholeEntity
    attributeIDs.insert(attributeID)
    self = .facts(attributeIDs: attributeIDs, values: values)
  }

  package mutating func insert(_ value: InstantValue, of attributeID: String) {
    guard case .facts(let attributeIDs, var values) = self else { return }
    self = .wholeEntity
    values[attributeID, default: []].insert(value)
    self = .facts(attributeIDs: attributeIDs, values: values)
  }
}

/// Per-entity fact scopes for one prepared mutation, or the union of several composed steps.
///
/// An entity without an entry is a whole-entity change, which is how every prepared mutation
/// behaved before scopes existed. Only explicitly scoped entities take the narrow paths.
package struct InstantFactScope: Sendable, Equatable {
  package private(set) var scopes: [String: InstantEntityFactScope]

  package init(scopes: [String: InstantEntityFactScope] = [:]) {
    self.scopes = scopes
  }

  package mutating func reserveCapacity(_ entityCount: Int) {
    scopes.reserveCapacity(entityCount)
  }

  package subscript(entityID: String) -> InstantEntityFactScope {
    scopes[entityID] ?? .wholeEntity
  }

  package mutating func record(_ scope: InstantEntityFactScope, for entityID: String) {
    scopes[entityID, default: .noStoredFacts].formUnion(scope)
  }

  package mutating func record(attributeID: String, for entityID: String) {
    scopes[entityID, default: .noStoredFacts].insert(attributeID: attributeID)
  }

  package mutating func record(_ value: InstantValue, of attributeID: String, for entityID: String) {
    scopes[entityID, default: .noStoredFacts].insert(value, of: attributeID)
  }

  package mutating func recordWholeEntity(_ entityID: String) {
    scopes[entityID] = .wholeEntity
  }

  /// This scope with every entity in `changedEntityIDs` given an explicit entry, so an unscoped
  /// (whole) change cannot be narrowed by a later union.
  package func completed(over changedEntityIDs: Set<String>) -> InstantFactScope {
    var completed = self
    for entityID in changedEntityIDs where completed.scopes[entityID] == nil {
      completed.scopes[entityID] = .wholeEntity
    }
    return completed
  }

  /// Adds another composed step's scope. Both sides must be `completed(over:)` their own changed
  /// entities.
  package mutating func formUnion(_ other: InstantFactScope) {
    for (entityID, scope) in other.scopes {
      scopes[entityID, default: .noStoredFacts].formUnion(scope)
    }
  }
}
