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
    guard filtersReferenceDeclaredFields(plan.filters, namespace: plan.namespace, attributes: attributes)
    else { return [] }

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
      guard matches(snapshot, filters: plan.filters, namespace: plan.namespace, attributes: attributes)
      else { continue }
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

    if let offset = plan.offset {
      guard offset >= 0 else { return [] }
      if offset >= snapshots.count {
        return []
      }
      snapshots = Array(snapshots.dropFirst(offset))
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
    filters: [InstantQueryFilter],
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    for filter in filters {
      switch filter {
      case let .equals(field, value):
        guard snapshot.values[field]?.contains(value) == true else { return false }
      case let .notEquals(field, value):
        guard isDeclaredField(field, namespace: namespace, attributes: attributes) else { return false }
        guard matchesNotEquals(snapshot, field: field, value: value) else { return false }
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
      case let .like(field, pattern):
        guard matchesStringPattern(snapshot, field: field, pattern: pattern, caseInsensitive: false)
        else { return false }
      case let .iLike(field, pattern):
        guard matchesStringPattern(snapshot, field: field, pattern: pattern, caseInsensitive: true)
        else { return false }
      case let .isNull(field):
        guard isDeclaredField(field, namespace: namespace, attributes: attributes) else { return false }
        guard isFieldNull(snapshot, field: field) else { return false }
      case let .isNotNull(field):
        guard isDeclaredField(field, namespace: namespace, attributes: attributes) else { return false }
        guard !isFieldNull(snapshot, field: field) else { return false }
      case let .and(filters):
        guard matches(snapshot, filters: filters, namespace: namespace, attributes: attributes)
        else { return false }
      case let .or(filters):
        guard
          !filters.isEmpty
            && filters.contains(where: {
              matches(snapshot, filter: $0, namespace: namespace, attributes: attributes)
            })
        else { return false }
      }
    }
    return true
  }

  private func filtersReferenceDeclaredFields(
    _ filters: [InstantQueryFilter],
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    filters.allSatisfy { filterReferencesDeclaredFields($0, namespace: namespace, attributes: attributes) }
  }

  private func filterReferencesDeclaredFields(
    _ filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    switch filter {
    case let .equals(field, _),
      let .notEquals(field, _),
      let .greaterThan(field, _),
      let .greaterThanOrEqual(field, _),
      let .lessThan(field, _),
      let .lessThanOrEqual(field, _),
      let .in(field, _),
      let .like(field, _),
      let .iLike(field, _),
      let .isNull(field),
      let .isNotNull(field):
      return isDeclaredField(field, namespace: namespace, attributes: attributes)

    case let .and(filters), let .or(filters):
      return filtersReferenceDeclaredFields(filters, namespace: namespace, attributes: attributes)
    }
  }

  private func matches(
    _ snapshot: InstantEntitySnapshot,
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    matches(
      snapshot,
      filters: [filter],
      namespace: namespace,
      attributes: attributes
    )
  }

  private func isDeclaredField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    attributes.attribute(namespace: namespace, name: field) != nil
  }

  private func matchesNotEquals(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    value: InstantValue
  ) -> Bool {
    guard let materialized = snapshot.values[field] else { return true }
    return materialized.values.contains { $0 != value } || materialized.values.contains(.null)
  }

  private func isFieldNull(_ snapshot: InstantEntitySnapshot, field: String) -> Bool {
    guard let materialized = snapshot.values[field] else { return true }
    return materialized.values.contains(.null)
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

  private func matchesStringPattern(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    pattern: String,
    caseInsensitive: Bool
  ) -> Bool {
    guard let materialized = snapshot.values[field] else { return false }
    return materialized.values.contains {
      guard case let .string(value) = $0 else { return false }
      return Self.matchesLikePattern(value, pattern: pattern, caseInsensitive: caseInsensitive)
    }
  }

  private enum LikeToken: Hashable {
    case literal(Character)
    case anyOne
    case anyMany
  }

  private static func matchesLikePattern(
    _ value: String,
    pattern: String,
    caseInsensitive: Bool
  ) -> Bool {
    let input = Array(caseInsensitive ? value.lowercased() : value)
    let tokens = tokenizeLikePattern(caseInsensitive ? pattern.lowercased() : pattern)

    var table = Array(
      repeating: Array(repeating: false, count: tokens.count + 1),
      count: input.count + 1
    )
    table[0][0] = true

    for inputIndex in 0...input.count {
      for tokenIndex in 0..<tokens.count where table[inputIndex][tokenIndex] {
        switch tokens[tokenIndex] {
        case let .literal(character):
          if inputIndex < input.count, input[inputIndex] == character {
            table[inputIndex + 1][tokenIndex + 1] = true
          }

        case .anyOne:
          if inputIndex < input.count {
            table[inputIndex + 1][tokenIndex + 1] = true
          }

        case .anyMany:
          table[inputIndex][tokenIndex + 1] = true
          if inputIndex < input.count {
            table[inputIndex + 1][tokenIndex] = true
          }
        }
      }
    }

    return table[input.count][tokens.count]
  }

  private static func tokenizeLikePattern(_ pattern: String) -> [LikeToken] {
    pattern.map { character in
      switch character {
      case "%":
        .anyMany
      case "_":
        .anyOne
      default:
        .literal(character)
      }
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
