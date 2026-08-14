import Foundation

package struct InstantDeferredValueHydrationRequest: Hashable, Sendable {
  package var namespace: String
  package var attributeIDs: Set<String>
  package var entityIDs: Set<String>
}

/// Keeps explicitly named large scalar attributes in SQLite until a query selects them.
///
/// This policy changes only local cache residency. Instant schema and wire semantics stay
/// unchanged, and query projections hydrate configured fields only for materialized root and
/// nested pages. Configured attributes must be payload-only fields: cardinality-one,
/// non-reference, non-indexed, and never an input to filtering, relationship traversal, or
/// ordering.
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
    let declaredIDs = attributesByID.keys.sorted()
    for attributeID in attributeIDs.sorted() {
      guard let attribute = attributesByID[attributeID] else {
        let namespaceHint = attributeID.split(separator: "/", maxSplits: 1).first.map(String.init)
        let related = declaredIDs.filter { id in
          guard let namespaceHint else { return false }
          return id.hasPrefix(namespaceHint + "/")
        }
        let relatedNote: String
        if related.isEmpty {
          relatedNote =
            declaredIDs.isEmpty
            ? " The bootstrap schema list is empty — no attributes were passed to InstantRuntime."
            : " Declared attribute IDs in this schema: \(declaredIDs.prefix(12).joined(separator: ", "))\(declaredIDs.count > 12 ? ", …" : "")."
        } else {
          relatedNote =
            " Declared attributes in namespace '\(namespaceHint ?? "")': \(related.joined(separator: ", "))."
        }
        throw InstantError(
          code: .validationFailed,
          operation: "validate deferred value residency",
          path: attributeID,
          message:
            "Deferred local residency names attribute '\(attributeID)', but that ID is not in the Instant schema passed at bootstrap.\(relatedNote)",
          recovery:
            "Add '\(attributeID)' to the app's Instant attributes (or InstantEntity model), "
            + "or remove it from InstantDeferredValueResidencyPolicy before bootstrap. "
            + "Scribe cold-start fails here when deferred IDs drift from the schema."
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

  /// Maps every selected deferred field in a query tree to only the entity IDs retained in the
  /// materialized snapshot tree. Nested limits have already run before this mapping is built.
  package func hydrationRequests(
    for plan: InstantQueryPlan,
    values: [InstantEntitySnapshot],
    rootEntityIDs: Set<String>? = nil,
    attributes: [InstantAttribute]
  ) -> [InstantDeferredValueHydrationRequest] {
    guard isEnabled else { return [] }
    let attributesByNamespace = Dictionary(grouping: attributes, by: \.namespace)
    var entityIDsByAttributeID: [String: Set<String>] = [:]
    let roots = if let rootEntityIDs {
      values.filter { rootEntityIDs.contains($0.id) }
    } else {
      values
    }
    collectHydrationEntityIDs(
      from: roots,
      namespace: plan.namespace,
      selectedFields: plan.selectedFields,
      includes: plan.includes,
      attributesByNamespace: attributesByNamespace,
      into: &entityIDsByAttributeID
    )

    let attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    var attributeIDsByBatch: [DeferredValueHydrationBatchKey: Set<String>] = [:]
    for (attributeID, entityIDs) in entityIDsByAttributeID where !entityIDs.isEmpty {
      guard let attribute = attributesByID[attributeID] else { continue }
      let key = DeferredValueHydrationBatchKey(
        namespace: attribute.namespace,
        entityIDs: entityIDs.sorted()
      )
      attributeIDsByBatch[key, default: []].insert(attributeID)
    }
    return attributeIDsByBatch.map { key, attributeIDs in
      InstantDeferredValueHydrationRequest(
        namespace: key.namespace,
        attributeIDs: attributeIDs,
        entityIDs: Set(key.entityIDs)
      )
    }
    .sorted(by: InstantDeferredValueHydrationRequest.stableOrder)
  }

  package func hasRequestedAttributes(
    for plan: InstantQueryPlan,
    attributes: [InstantAttribute]
  ) -> Bool {
    guard isEnabled else { return false }
    return hasRequestedAttributes(
      namespace: plan.namespace,
      selectedFields: plan.selectedFields,
      includes: plan.includes,
      attributesByNamespace: Dictionary(grouping: attributes, by: \.namespace)
    )
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
    for plan: InstantQueryPlan,
    with triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> InstantQueryEmission {
    guard !triples.isEmpty else { return emission }
    let attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    var valuesByEntity: [DeferredValueEntityKey: [String: InstantMaterializedValue]] = [:]
    for triple in triples {
      guard let attribute = attributesByID[triple.attributeID] else { continue }
      let key = DeferredValueEntityKey(
        namespace: attribute.namespace,
        entityID: triple.entityID
      )
      valuesByEntity[key, default: [:]][attribute.name] = .one(triple.value)
    }
    let attributesByNamespace = Dictionary(grouping: attributes, by: \.namespace)
    var hydrated = emission
    hydrated.values = emission.values.map { snapshot in
      hydrate(
        snapshot,
        namespace: plan.namespace,
        selectedFields: plan.selectedFields,
        includes: plan.includes,
        attributesByNamespace: attributesByNamespace,
        valuesByEntity: valuesByEntity
      )
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

  private func collectHydrationEntityIDs<Snapshot: DeferredValueHydratableSnapshot>(
    from snapshots: [Snapshot],
    namespace: String,
    selectedFields: [String]?,
    includes: [InstantQueryInclude]?,
    attributesByNamespace: [String: [InstantAttribute]],
    into entityIDsByAttributeID: inout [String: Set<String>]
  ) {
    let matchingSnapshots = snapshots.filter { $0.namespace == namespace }
    guard !matchingSnapshots.isEmpty else { return }
    let requestedAttributes = requestedAttributes(
      namespace: namespace,
      selectedFields: selectedFields,
      attributesByNamespace: attributesByNamespace
    )
    let entityIDs = Set(matchingSnapshots.map(\.id))
    for attribute in requestedAttributes {
      entityIDsByAttributeID[attribute.id, default: []].formUnion(entityIDs)
    }

    for include in includes ?? [] {
      let children = matchingSnapshots.flatMap { snapshot in
        snapshot.links?[include.name] ?? []
      }
      guard !children.isEmpty else { continue }
      if let query = include.query {
        collectHydrationEntityIDs(
          from: children,
          namespace: query.namespace,
          selectedFields: query.selectedFields,
          includes: query.includes,
          attributesByNamespace: attributesByNamespace,
          into: &entityIDsByAttributeID
        )
      } else {
        for namespace in Set(children.map(\.namespace)) {
          collectHydrationEntityIDs(
            from: children,
            namespace: namespace,
            selectedFields: nil,
            includes: nil,
            attributesByNamespace: attributesByNamespace,
            into: &entityIDsByAttributeID
          )
        }
      }
    }
  }

  private func hydrate<Snapshot: DeferredValueHydratableSnapshot>(
    _ original: Snapshot,
    namespace: String,
    selectedFields: [String]?,
    includes: [InstantQueryInclude]?,
    attributesByNamespace: [String: [InstantAttribute]],
    valuesByEntity: [DeferredValueEntityKey: [String: InstantMaterializedValue]]
  ) -> Snapshot {
    var snapshot = original
    guard snapshot.namespace == namespace else { return snapshot }
    let key = DeferredValueEntityKey(namespace: snapshot.namespace, entityID: snapshot.id)
    if let values = valuesByEntity[key] {
      let requestedFieldNames = Set(
        requestedAttributes(
          namespace: namespace,
          selectedFields: selectedFields,
          attributesByNamespace: attributesByNamespace
        )
        .map(\.name)
      )
      for fieldName in requestedFieldNames {
        if let value = values[fieldName] {
          snapshot.values[fieldName] = value
        }
      }
    }
    guard var links = snapshot.links else { return snapshot }
    for include in includes ?? [] {
      guard let children = links[include.name] else { continue }
      links[include.name] = children.map { child in
        if let query = include.query {
          hydrate(
            child,
            namespace: query.namespace,
            selectedFields: query.selectedFields,
            includes: query.includes,
            attributesByNamespace: attributesByNamespace,
            valuesByEntity: valuesByEntity
          )
        } else {
          hydrate(
            child,
            namespace: child.namespace,
            selectedFields: nil,
            includes: nil,
            attributesByNamespace: attributesByNamespace,
            valuesByEntity: valuesByEntity
          )
        }
      }
    }
    snapshot.links = links
    return snapshot
  }

  private func hasRequestedAttributes(
    namespace: String,
    selectedFields: [String]?,
    includes: [InstantQueryInclude]?,
    attributesByNamespace: [String: [InstantAttribute]]
  ) -> Bool {
    if !requestedAttributes(
      namespace: namespace,
      selectedFields: selectedFields,
      attributesByNamespace: attributesByNamespace
    ).isEmpty {
      return true
    }
    for include in includes ?? [] {
      guard let query = include.query else {
        // Without a nested plan the target namespace is materialization-dependent.
        return true
      }
      if hasRequestedAttributes(
        namespace: query.namespace,
        selectedFields: query.selectedFields,
        includes: query.includes,
        attributesByNamespace: attributesByNamespace
      ) {
        return true
      }
    }
    return false
  }

  private func requestedAttributes(
    namespace: String,
    selectedFields: [String]?,
    attributesByNamespace: [String: [InstantAttribute]]
  ) -> [InstantAttribute] {
    let selectedFields = selectedFields.map(Set.init)
    return (attributesByNamespace[namespace] ?? []).filter { attribute in
      attributeIDs.contains(attribute.id)
        && (selectedFields?.contains(attribute.name) ?? true)
    }
  }
}

private struct DeferredValueHydrationBatchKey: Hashable {
  var namespace: String
  var entityIDs: [String]
}

private struct DeferredValueEntityKey: Hashable {
  var namespace: String
  var entityID: String
}

private protocol DeferredValueHydratableSnapshot {
  var id: String { get }
  var namespace: String { get }
  var values: [String: InstantMaterializedValue] { get set }
  var links: [String: [InstantLinkedEntitySnapshot]]? { get set }
}

extension InstantEntitySnapshot: DeferredValueHydratableSnapshot {}
extension InstantLinkedEntitySnapshot: DeferredValueHydratableSnapshot {}

private extension InstantDeferredValueHydrationRequest {
  static func stableOrder(
    _ lhs: InstantDeferredValueHydrationRequest,
    _ rhs: InstantDeferredValueHydrationRequest
  ) -> Bool {
    if lhs.namespace != rhs.namespace { return lhs.namespace < rhs.namespace }
    let lhsAttributes = lhs.attributeIDs.sorted()
    let rhsAttributes = rhs.attributeIDs.sorted()
    if lhsAttributes != rhsAttributes {
      return lhsAttributes.lexicographicallyPrecedes(rhsAttributes)
    }
    return lhs.entityIDs.sorted().lexicographicallyPrecedes(rhs.entityIDs.sorted())
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
