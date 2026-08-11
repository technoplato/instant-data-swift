import Foundation

/// Keeps explicitly named large scalar attributes in SQLite until a query selects them.
///
/// This policy changes only local cache residency. Instant schema and wire semantics stay
/// unchanged, and top-level query projections hydrate configured fields only for the materialized
/// page. Configured attributes must be payload-only fields: cardinality-one, non-reference,
/// non-indexed, and never an input to filtering, relationship traversal, or ordering.
public struct InstantDeferredValueResidencyPolicy: Hashable, Sendable {
  public static let none = Self(attributeIDs: [])

  public var attributeIDs: Set<String>

  public init(attributeIDs: [String]) {
    self.attributeIDs = Set(attributeIDs)
  }

  public init(attributeIDs: Set<String>) {
    self.attributeIDs = attributeIDs
  }

  package var isEnabled: Bool {
    !attributeIDs.isEmpty
  }

  package func validate(attributes: [InstantAttribute]) throws {
    guard isEnabled else { return }
    let attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    for attributeID in attributeIDs.sorted() {
      guard let attribute = attributesByID[attributeID] else {
        throw InstantError(
          code: .validationFailed,
          operation: "validate deferred value residency",
          path: attributeID,
          message: "Deferred attribute '\(attributeID)' is not declared in the Instant schema.",
          recovery: "Declare the attribute before enabling deferred local residency."
        )
      }
      guard attribute.cardinality == .one else {
        throw invalidAttribute(
          attribute,
          requirement: "cardinality-one",
          recovery: "Store a bounded scalar value per entity, or leave this attribute resident."
        )
      }
      guard attribute.valueType != .ref else {
        throw invalidAttribute(
          attribute,
          requirement: "non-reference",
          recovery: "Relationship attributes must remain resident for traversal and deletion."
        )
      }
      guard !attribute.isIndexed else {
        throw invalidAttribute(
          attribute,
          requirement: "non-indexed",
          recovery: "Indexed attributes must remain resident for filtering and ordering."
        )
      }
    }
  }

  package func requestedAttributes(
    for plan: InstantQueryPlan,
    attributes: [InstantAttribute]
  ) -> [InstantAttribute] {
    guard isEnabled else { return [] }
    let selectedFields = plan.selectedFields.map(Set.init)
    return attributes.filter { attribute in
      attribute.namespace == plan.namespace
        && attributeIDs.contains(attribute.id)
        && (selectedFields?.contains(attribute.name) ?? true)
    }
  }

  package func directEntityIDs(in transaction: InstantStoreTransaction) -> Set<String> {
    transaction.operations.reduce(into: Set<String>()) { result, operation in
      switch operation {
      case let .requireEntityMissing(entityID, _),
        let .requireEntityExists(entityID, _),
        let .requireTripleExists(entityID, _, _),
        let .deleteEntity(entityID),
        let .deleteEntityInNamespace(entityID, _),
        let .ruleParams(entityID, _, _):
        result.insert(entityID)

      case let .merge(triple), let .insert(triple), let .retract(triple):
        result.insert(triple.entityID)

      case .requireEntityMissingByLookup, .requireEntityExistsByLookup,
        .mergeByLookup, .insertByLookup, .retractByLookup,
        .deleteEntityByLookup, .ruleParamsByLookup:
        break
      }
    }
  }

  package func requiresEntityDiscovery(in transaction: InstantStoreTransaction) -> Bool {
    transaction.operations.contains { operation in
      switch operation {
      case .requireEntityMissingByLookup, .requireEntityExistsByLookup,
        .mergeByLookup, .insertByLookup, .retractByLookup,
        .deleteEntity, .deleteEntityInNamespace, .deleteEntityByLookup,
        .ruleParamsByLookup:
        true

      case .requireEntityMissing, .requireEntityExists, .requireTripleExists,
        .merge, .insert, .retract, .ruleParams:
        false
      }
    }
  }

  package func hydrating(
    _ emission: InstantQueryEmission,
    with triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> InstantQueryEmission {
    guard !triples.isEmpty else { return emission }
    let attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    var valuesByEntityID: [String: [String: InstantMaterializedValue]] = [:]
    for triple in triples {
      guard let attribute = attributesByID[triple.attributeID] else { continue }
      valuesByEntityID[triple.entityID, default: [:]][attribute.name] = .one(triple.value)
    }
    var hydrated = emission
    hydrated.values = emission.values.map { snapshot in
      guard let values = valuesByEntityID[snapshot.id] else { return snapshot }
      var snapshot = snapshot
      snapshot.values.merge(values) { _, deferred in deferred }
      return snapshot
    }
    return hydrated
  }

  package func hydrating(
    _ snapshot: InstantStoreSnapshot,
    with triples: [InstantTriple]
  ) -> InstantStoreSnapshot {
    guard !triples.isEmpty else { return snapshot }
    let hydratedKeys = Set(
      triples.map { DeferredValueKey(entityID: $0.entityID, attributeID: $0.attributeID) }
    )
    var hydrated = snapshot
    hydrated.triples.removeAll { triple in
      hydratedKeys.contains(
        DeferredValueKey(entityID: triple.entityID, attributeID: triple.attributeID)
      )
    }
    hydrated.triples.append(contentsOf: triples)
    return hydrated
  }

  private func invalidAttribute(
    _ attribute: InstantAttribute,
    requirement: String,
    recovery: String
  ) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "validate deferred value residency",
      namespace: attribute.namespace,
      path: attribute.name,
      localID: attribute.id,
      message:
        "Deferred attribute '\(attribute.id)' must be \(requirement), but its schema is not.",
      recovery: recovery
    )
  }
}

private struct DeferredValueKey: Hashable {
  var entityID: String
  var attributeID: String
}

package struct InstantDeferredValueDecodeMetrics: Hashable, Sendable {
  package var valueCount: Int
  package var encodedByteCount: Int

  package init(valueCount: Int = 0, encodedByteCount: Int = 0) {
    self.valueCount = valueCount
    self.encodedByteCount = encodedByteCount
  }
}
