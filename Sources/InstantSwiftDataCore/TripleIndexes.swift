import Foundation

struct AttributeStore: Hashable, Codable, Sendable {
  private var attributesByID: [String: InstantAttribute] = [:]

  init(attributes: [InstantAttribute] = []) {
    self.replaceAll(attributes)
  }

  var attributes: [InstantAttribute] {
    attributesByID.values.sorted { $0.id < $1.id }
  }

  mutating func replaceAll(_ attributes: [InstantAttribute]) {
    attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
  }

  mutating func merge(_ attributes: [InstantAttribute]) {
    for attribute in attributes {
      attributesByID[attribute.id] = attribute
    }
  }

  subscript(id: String) -> InstantAttribute? {
    attributesByID[id]
  }

  func attribute(namespace: String, name: String) -> InstantAttribute? {
    attributesByID.values.first { $0.namespace == namespace && $0.name == name }
  }
}

struct TripleIndexes: Hashable, Codable, Sendable {
  private var eav: [String: [String: [InstantValue: InstantTriple]]] = [:]
  private var aev: [String: [String: [InstantValue: InstantTriple]]] = [:]
  private var vae: [InstantValue: [String: [String: InstantTriple]]] = [:]

  init(triples: [InstantTriple] = [], attributes: AttributeStore = AttributeStore()) {
    for triple in triples {
      self.insert(triple, attribute: attributes[triple.attributeID])
    }
  }

  var triples: [InstantTriple] {
    eav.values
      .flatMap(\.values)
      .flatMap(\.values)
      .sorted {
        Self.lexicographicallyPrecedes(Self.tripleSortKey($0), Self.tripleSortKey($1))
      }
  }

  func triples(entityID: String) -> [InstantTriple] {
    eav[entityID]?.values.flatMap(\.values) ?? []
  }

  func reverseRefTriples(targetEntityID: String) -> [InstantTriple] {
    vae[.ref(targetEntityID)]?.values.flatMap(\.values) ?? []
  }

  @discardableResult
  mutating func apply(
    _ operation: InstantTripleOperation,
    attributes: AttributeStore
  ) -> Set<String> {
    switch operation {
    case let .insert(triple):
      var changed: Set<String> = [triple.entityID]
      let attribute = attributes[triple.attributeID]
      if attribute?.valueType == .ref, let targetID = triple.value.refValue {
        changed.insert(targetID)
      }
      insert(triple, attribute: attribute)
      return changed

    case let .retract(triple):
      var changed: Set<String> = [triple.entityID]
      let attribute = attributes[triple.attributeID]
      if attribute?.valueType == .ref, let targetID = triple.value.refValue {
        changed.insert(targetID)
      }
      remove(triple, attribute: attribute)
      return changed

    case let .deleteEntity(entityID):
      var changed: Set<String> = [entityID]
      for triple in triples(entityID: entityID) {
        let attribute = attributes[triple.attributeID]
        if attribute?.valueType == .ref, let targetID = triple.value.refValue {
          changed.insert(targetID)
        }
        remove(triple, attribute: attribute)
      }
      for triple in reverseRefTriples(targetEntityID: entityID) {
        changed.insert(triple.entityID)
        remove(triple, attribute: attributes[triple.attributeID])
      }
      return changed
    }
  }

  func materialize(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> [InstantEntitySnapshot] {
    var snapshots: [InstantEntitySnapshot] = []

    for (entityID, attributesByID) in eav {
      var values: [String: InstantMaterializedValue] = [:]

      for (attributeID, valuesByValue) in attributesByID {
        guard let attribute = attributes[attributeID], attribute.namespace == plan.namespace
        else { continue }

        let sortedValues = valuesByValue.values
          .sorted { $0.value.comparableKey < $1.value.comparableKey }
          .map(\.value)

        switch attribute.cardinality {
        case .one:
          if let value = sortedValues.last {
            values[attribute.name] = .one(value)
          }
        case .many:
          values[attribute.name] = .many(sortedValues)
        }
      }

      guard !values.isEmpty else { continue }
      let snapshot = InstantEntitySnapshot(id: entityID, namespace: plan.namespace, values: values)
      guard matches(snapshot, filters: plan.filters) else { continue }
      snapshots.append(snapshot)
    }

    if let order = plan.order {
      snapshots.sort(by: { (lhs: InstantEntitySnapshot, rhs: InstantEntitySnapshot) in
        let lhsValue = lhs.values[order.field]?.first?.comparableKey ?? ""
        let rhsValue = rhs.values[order.field]?.first?.comparableKey ?? ""
        let lhsInstantValue = lhs.values[order.field]?.first
        let rhsInstantValue = rhs.values[order.field]?.first
        switch order.direction {
        case .ascending:
          return Self.valuePrecedes(
            lhsInstantValue,
            rhsInstantValue,
            lhsTieBreaker: [lhsValue, lhs.id],
            rhsTieBreaker: [rhsValue, rhs.id]
          )
        case .descending:
          return Self.valuePrecedes(
            rhsInstantValue,
            lhsInstantValue,
            lhsTieBreaker: [rhsValue, rhs.id],
            rhsTieBreaker: [lhsValue, lhs.id]
          )
        }
      })
    } else {
      snapshots.sort { $0.id < $1.id }
    }

    if let limit = plan.limit {
      guard limit > 0 else { return [] }
      return Array(snapshots.prefix(limit))
    }
    return snapshots
  }

  private mutating func insert(_ triple: InstantTriple, attribute: InstantAttribute?) {
    if attribute?.cardinality == .one {
      if let existingValues = eav[triple.entityID]?[triple.attributeID]?.values {
        for existing in Array(existingValues) {
          remove(existing, attribute: attribute)
        }
      }
    }

    eav[triple.entityID, default: [:]][triple.attributeID, default: [:]][triple.value] = triple
    aev[triple.attributeID, default: [:]][triple.entityID, default: [:]][triple.value] = triple

    if attribute?.valueType == .ref {
      vae[triple.value, default: [:]][triple.attributeID, default: [:]][triple.entityID] = triple
    }
  }

  private mutating func remove(_ triple: InstantTriple, attribute: InstantAttribute?) {
    eav[triple.entityID]?[triple.attributeID]?[triple.value] = nil
    if eav[triple.entityID]?[triple.attributeID]?.isEmpty == true {
      eav[triple.entityID]?[triple.attributeID] = nil
    }
    if eav[triple.entityID]?.isEmpty == true {
      eav[triple.entityID] = nil
    }

    aev[triple.attributeID]?[triple.entityID]?[triple.value] = nil
    if aev[triple.attributeID]?[triple.entityID]?.isEmpty == true {
      aev[triple.attributeID]?[triple.entityID] = nil
    }
    if aev[triple.attributeID]?.isEmpty == true {
      aev[triple.attributeID] = nil
    }

    if attribute?.valueType == .ref {
      vae[triple.value]?[triple.attributeID]?[triple.entityID] = nil
      if vae[triple.value]?[triple.attributeID]?.isEmpty == true {
        vae[triple.value]?[triple.attributeID] = nil
      }
      if vae[triple.value]?.isEmpty == true {
        vae[triple.value] = nil
      }
    }
  }

  private func matches(
    _ snapshot: InstantEntitySnapshot,
    filters: [InstantQueryFilter]
  ) -> Bool {
    for filter in filters {
      switch filter {
      case let .equals(field, value):
        guard snapshot.values[field]?.contains(value) == true else { return false }
      case let .notEquals(field, value):
        guard let values = snapshot.values[field] else { return false }
        guard !values.contains(value) else { return false }
      case let .greaterThan(field, value):
        guard matchesComparison(snapshot, field: field, value: value, allowed: [.orderedDescending])
        else { return false }
      case let .greaterThanOrEqual(field, value):
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          allowed: [.orderedSame, .orderedDescending]
        )
        else { return false }
      case let .lessThan(field, value):
        guard matchesComparison(snapshot, field: field, value: value, allowed: [.orderedAscending])
        else { return false }
      case let .lessThanOrEqual(field, value):
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          allowed: [.orderedAscending, .orderedSame]
        )
        else { return false }
      case let .in(field, values):
        guard let materialized = snapshot.values[field], !values.isEmpty else { return false }
        guard materialized.values.contains(where: values.contains) else { return false }
      case let .isNull(field):
        if let materialized = snapshot.values[field],
          !materialized.values.allSatisfy({ $0 == .null })
        {
          return false
        }
      }
    }
    return true
  }

  private func matchesComparison(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    value: InstantValue,
    allowed: Set<ComparisonResult>
  ) -> Bool {
    guard let materialized = snapshot.values[field] else { return false }
    return materialized.values.contains {
      guard Self.canRangeCompare($0, value) else { return false }
      return allowed.contains($0.compare(to: value))
    }
  }

  private static func canRangeCompare(_ lhs: InstantValue, _ rhs: InstantValue) -> Bool {
    switch (lhs, rhs) {
    case (.string, .string), (.number, .number), (.date, .date):
      return true
    default:
      return false
    }
  }

  private static func tripleSortKey(_ triple: InstantTriple) -> [String] {
    [triple.entityID, triple.attributeID, triple.value.comparableKey]
  }

  private static func lexicographicallyPrecedes(_ lhs: [String], _ rhs: [String]) -> Bool {
    for (left, right) in zip(lhs, rhs) {
      if left != right {
        return left < right
      }
    }
    return lhs.count < rhs.count
  }

  private static func valuePrecedes(
    _ lhs: InstantValue?,
    _ rhs: InstantValue?,
    lhsTieBreaker: [String],
    rhsTieBreaker: [String]
  ) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      return lexicographicallyPrecedes(lhsTieBreaker, rhsTieBreaker)
    case (nil, .some):
      return true
    case (.some, nil):
      return false
    case let (.some(lhs), .some(rhs)):
      switch lhs.compare(to: rhs) {
      case .orderedAscending:
        return true
      case .orderedDescending:
        return false
      case .orderedSame:
        return lexicographicallyPrecedes(lhsTieBreaker, rhsTieBreaker)
      }
    }
  }
}
