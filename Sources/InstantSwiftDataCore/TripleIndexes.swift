import Foundation

struct AttributeStore: Hashable, Codable, Sendable {
  private var attributesByID: [String: InstantAttribute] = [:]

  init(attributes: [InstantAttribute] = []) {
    self.replaceAll(attributes)
  }

  var attributes: [InstantAttribute] {
    attributesByID.values.sorted { $0.id < $1.id }
  }

  var namespaces: Set<String> {
    Set(attributesByID.values.map(\.namespace))
  }

  mutating func replaceAll(_ attributes: [InstantAttribute]) {
    attributesByID = Dictionary(
      uniqueKeysWithValues: Self.withPrimaryKeys(attributes).map { ($0.id, $0) }
    )
  }

  mutating func merge(_ attributes: [InstantAttribute]) {
    for attribute in Self.withPrimaryKeys(attributes) {
      attributesByID[attribute.id] = attribute
    }
  }

  subscript(id: String) -> InstantAttribute? {
    attributesByID[id] ?? Self.primaryKeyAttribute(id: id)
  }

  func attribute(namespace: String, name: String) -> InstantAttribute? {
    if name == "id" {
      return self[InstantAttribute.primaryKeyID(namespace: namespace)]
    }
    return attributesByID.values.first { $0.namespace == namespace && $0.name == name }
  }

  func primaryKeyAttribute(namespace: String) -> InstantAttribute {
    self[InstantAttribute.primaryKeyID(namespace: namespace)] ?? .primaryKey(namespace: namespace)
  }

  private static func withPrimaryKeys(_ attributes: [InstantAttribute]) -> [InstantAttribute] {
    let namespaces = Set(attributes.map(\.namespace))
    let primaryKeys = namespaces.map(InstantAttribute.primaryKey(namespace:))
    return primaryKeys + attributes.filter { !$0.primaryKey && $0.name != "id" }
  }

  private static func primaryKeyAttribute(id: String) -> InstantAttribute? {
    guard id.hasSuffix("/id") else { return nil }
    let namespace = String(id.dropLast("/id".count))
    guard !namespace.isEmpty else { return nil }
    return .primaryKey(namespace: namespace)
  }
}

struct InstantQueryValidationIssue: Error, Hashable, Sendable {
  var namespace: String
  var path: String?
  var message: String
  var recovery: String
}

struct TripleIndexes: Hashable, Codable, Sendable {
  private var eav: [String: [String: [InstantValue: InstantTriple]]] = [:]
  private var aev: [String: [String: [InstantValue: InstantTriple]]] = [:]
  private var vae: [InstantValue: [String: [String: InstantTriple]]] = [:]

  private struct QuerySnapshot: Hashable, Sendable {
    var snapshot: InstantEntitySnapshot
    var serverCreatedAt: InstantValue?
  }

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

  func containsEntity(
    _ entityID: String,
    namespace: String?,
    attributes: AttributeStore
  ) -> Bool {
    let entityTriples = triples(entityID: entityID)
    if let namespace {
      let idAttribute = attributes.primaryKeyAttribute(namespace: namespace)
      if entityTriples.contains(where: {
        $0.attributeID == idAttribute.id && $0.value == .string(entityID)
      }) {
        return true
      }
    }

    return entityTriples.contains { triple in
      guard let namespace else { return true }
      return attributes[triple.attributeID]?.namespace == namespace
    }
  }

  func containsTriple(
    entityID: String,
    attributeID: String,
    value: InstantValue,
    attribute: InstantAttribute?
  ) -> Bool {
    eav[entityID]?[attributeID]?[Self.normalizedValue(value, attribute: attribute)] != nil
  }

  func entityIDs(matching lookup: InstantLookupRef, attribute: InstantAttribute?) -> [String] {
    let value = Self.normalizedValue(lookup.value.instantValue, attribute: attribute)
    return aev[lookup.attributeID]?
      .compactMap { entityID, valuesByValue in
        valuesByValue[value] == nil ? nil : entityID
      }
      .sorted()
      ?? []
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
    case .requireEntityMissing, .requireEntityMissingByLookup,
      .requireEntityExists, .requireEntityExistsByLookup,
      .requireTripleExists,
      .mergeByLookup, .insertByLookup, .retractByLookup,
      .deleteEntityByLookup, .ruleParams, .ruleParamsByLookup:
      return []

    case let .merge(triple):
      merge(triple, attribute: attributes[triple.attributeID])
      return [triple.entityID]

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
      var visited: Set<String> = []
      return deleteEntity(entityID, attributes: attributes, visited: &visited)
    }
  }

  func materialize(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> [InstantEntitySnapshot] {
    materializePage(plan, attributes: attributes).values
  }

  func materializePage(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> InstantQueryPage {
    guard Self.validate(plan, attributes: attributes) == nil else {
      return InstantQueryPage(values: [], pageInfo: pageInfo(for: [], plan: plan))
    }

    var snapshots: [QuerySnapshot] = []

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
      snapshots.append(
        QuerySnapshot(
          snapshot: snapshot,
          serverCreatedAt: serverCreatedAtValue(
            entityID: entityID,
            namespace: plan.namespace,
            attributes: attributes
          )
        )
      )
    }

    let effectiveOrder = Self.effectiveOrder(plan.order)
    snapshots.sort {
      Self.compare($0, $1, order: effectiveOrder) == .orderedAscending
    }

    let paged = paginate(
      snapshots,
      plan: plan,
      effectiveOrder: effectiveOrder,
      attributes: attributes
    )
    let linked = includeLinks(paged.values.map(\.snapshot), plan: plan, attributes: attributes)
    return InstantQueryPage(
      values: project(linked, selectedFields: plan.selectedFields),
      pageInfo: paged.pageInfo
    )
  }

  static func validate(
    _ plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    let namespaces = attributes.namespaces
    if !namespaces.isEmpty, !namespaces.contains(plan.namespace) {
      return InstantQueryValidationIssue(
        namespace: plan.namespace,
        path: nil,
        message: "Query namespace '\(plan.namespace)' is not declared in the schema attributes.",
        recovery: "Declare the namespace before querying it, or bootstrap without schema attributes for schemaless queries."
      )
    }

    if plan.first != nil, plan.last != nil {
      return InstantQueryValidationIssue(
        namespace: plan.namespace,
        path: "pagination",
        message: "A query cannot request both 'first' and 'last' pagination.",
        recovery: "Use either 'first' for a forward page or 'last' for a reverse page."
      )
    }

    if let issue = validate(filters: plan.filters, namespace: plan.namespace, attributes: attributes) {
      return issue
    }
    if let issue = validateSelectedFields(
      plan.selectedFields,
      namespace: plan.namespace,
      attributes: attributes
    ) {
      return issue
    }
    if let issue = validateOrder(plan.order, namespace: plan.namespace, attributes: attributes) {
      return issue
    }
    if let issue = validateIncludes(plan.includes, namespace: plan.namespace, attributes: attributes) {
      return issue
    }
    return nil
  }

  private func includeLinks(
    _ snapshots: [InstantEntitySnapshot],
    plan: InstantQueryPlan,
    attributes: AttributeStore
  ) -> [InstantEntitySnapshot] {
    guard let includes = plan.includes, !includes.isEmpty else { return snapshots }

    return snapshots.map { snapshot in
      var links = snapshot.links ?? [:]
      for include in includes {
        switch include.direction {
        case .forward:
          guard
            let attribute = attributes.attribute(namespace: plan.namespace, name: include.name),
            let linkNamespace = attribute.linkNamespace
          else { continue }
          let entityIDs = snapshot.values[include.name]?.values.compactMap(\.refValue) ?? []
          guard !entityIDs.isEmpty else {
            links[include.name] = []
            continue
          }
          links[include.name] = materializeIncludedSnapshots(
            ids: Set(entityIDs),
            namespace: linkNamespace,
            include: include,
            attributes: attributes
          )

        case .reverse:
          guard
            let attribute = reverseAttribute(
              namespace: plan.namespace,
              name: include.name,
              attributes: attributes
            )
          else { continue }
          let entityIDs =
            vae[.ref(snapshot.id)]?[attribute.id]?.keys.sorted()
            ?? []
          guard !entityIDs.isEmpty else {
            links[include.name] = []
            continue
          }
          links[include.name] = materializeIncludedSnapshots(
            ids: Set(entityIDs),
            namespace: attribute.namespace,
            include: include,
            attributes: attributes
          )
        }
      }

      return InstantEntitySnapshot(
        id: snapshot.id,
        namespace: snapshot.namespace,
        values: snapshot.values,
        links: links.isEmpty ? nil : links
      )
    }
  }

  private func materializeIncludedSnapshots(
    ids: Set<String>,
    namespace: String,
    include: InstantQueryInclude,
    attributes: AttributeStore
  ) -> [InstantLinkedEntitySnapshot] {
    let query =
      include.query?.queryPlan
      ?? InstantQueryPlan(
        id: "\(namespace).included.\(include.name)",
        namespace: namespace
      )
    return materializePage(query, attributes: attributes)
      .values
      .filter { ids.contains($0.id) }
      .map(InstantLinkedEntitySnapshot.init)
  }

  private func snapshot(
    entityID: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantEntitySnapshot? {
    guard let attributesByID = eav[entityID] else { return nil }

    var values: [String: InstantMaterializedValue] = [:]
    for (attributeID, valuesByValue) in attributesByID {
      guard let attribute = attributes[attributeID], attribute.namespace == namespace
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

    guard !values.isEmpty else { return nil }
    return InstantEntitySnapshot(id: entityID, namespace: namespace, values: values)
  }

  private func serverCreatedAtValue(
    entityID: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantValue? {
    let idAttribute = attributes.primaryKeyAttribute(namespace: namespace)
    if let triple = eav[entityID]?[idAttribute.id]?[.string(entityID)] {
      return .number(Double(triple.txTime.milliseconds))
    }

    let earliestNamespaceTime = eav[entityID]?
      .flatMap { attributeID, valuesByValue -> [InstantTimestamp] in
        guard attributes[attributeID]?.namespace == namespace else { return [] }
        return valuesByValue.values.map(\.txTime)
      }
      .min()
    return earliestNamespaceTime.map { .number(Double($0.milliseconds)) }
  }

  private func paginate(
    _ snapshots: [QuerySnapshot],
    plan: InstantQueryPlan,
    effectiveOrder: InstantQueryOrder,
    attributes: AttributeStore
  ) -> (values: [QuerySnapshot], pageInfo: InstantQueryPageInfo?) {
    guard isValidPagination(plan) else {
      return ([], pageInfo(for: [], plan: plan, effectiveOrder: effectiveOrder))
    }

    var page = snapshots
    var removedBefore = 0
    var removedAfter = 0

    if let after = plan.after {
      let startIndex: Int
      if after.sortValue == nil {
        guard let index = page.firstIndex(where: { $0.snapshot.id == after.entityID }) else {
          return ([], pageInfo(for: [], plan: plan))
        }
        startIndex = after.inclusive ? index : index + 1
      } else {
        startIndex = page.firstIndex {
          let comparison = Self.compare(
            $0,
            to: after,
            order: effectiveOrder,
            namespace: plan.namespace,
            attributes: attributes
          )
          return after.inclusive
            ? comparison != .orderedAscending
            : comparison == .orderedDescending
        } ?? page.count
      }
      removedBefore += min(startIndex, page.count)
      page = Array(page.dropFirst(startIndex))
    }

    if let before = plan.before {
      let endIndex: Int
      if before.sortValue == nil {
        guard let index = page.firstIndex(where: { $0.snapshot.id == before.entityID }) else {
          return ([], pageInfo(for: [], plan: plan))
        }
        endIndex = before.inclusive ? index + 1 : index
      } else {
        endIndex = page.firstIndex {
          let comparison = Self.compare(
            $0,
            to: before,
            order: effectiveOrder,
            namespace: plan.namespace,
            attributes: attributes
          )
          return before.inclusive
            ? comparison == .orderedDescending
            : comparison != .orderedAscending
        } ?? page.count
      }
      let boundedEndIndex = max(0, min(endIndex, page.count))
      removedAfter += page.count - boundedEndIndex
      page = Array(page.prefix(boundedEndIndex))
    }

    if let offset = plan.offset {
      let count = min(offset, page.count)
      removedBefore += count
      page = Array(page.dropFirst(offset))
    }

    if let first = plan.first {
      let count = min(first, page.count)
      removedAfter += page.count - count
      page = Array(page.prefix(first))
    }

    if let last = plan.last {
      let count = min(last, page.count)
      removedBefore += page.count - count
      page = Array(page.suffix(last))
    }

    if let limit = plan.limit {
      let count = min(limit, page.count)
      removedAfter += page.count - count
      page = Array(page.prefix(limit))
    }

    return (
      page,
      pageInfo(
        for: page,
        plan: plan,
        effectiveOrder: effectiveOrder,
        hasPreviousPage: removedBefore > 0,
        hasNextPage: removedAfter > 0
      )
    )
  }

  private func isValidPagination(_ plan: InstantQueryPlan) -> Bool {
    guard plan.offset.map({ $0 >= 0 }) ?? true else { return false }
    guard plan.limit.map({ $0 >= 0 }) ?? true else { return false }
    guard plan.first.map({ $0 >= 0 }) ?? true else { return false }
    guard plan.last.map({ $0 >= 0 }) ?? true else { return false }
    guard plan.first == nil || plan.last == nil else { return false }
    return true
  }

  private func pageInfo(
    for snapshots: [QuerySnapshot],
    plan: InstantQueryPlan,
    effectiveOrder: InstantQueryOrder? = nil,
    hasPreviousPage: Bool = false,
    hasNextPage: Bool = false
  ) -> InstantQueryPageInfo? {
    guard requestsPageInfo(plan) else { return nil }
    let order = effectiveOrder ?? Self.effectiveOrder(plan.order)
    return InstantQueryPageInfo(
      startCursor: snapshots.first.map { cursor(for: $0, order: order) },
      endCursor: snapshots.last.map { cursor(for: $0, order: order) },
      hasPreviousPage: hasPreviousPage,
      hasNextPage: hasNextPage
    )
  }

  private func requestsPageInfo(_ plan: InstantQueryPlan) -> Bool {
    plan.offset != nil
      || plan.limit != nil
      || plan.first != nil
      || plan.after != nil
      || plan.last != nil
      || plan.before != nil
  }

  private func cursor(
    for querySnapshot: QuerySnapshot,
    order: InstantQueryOrder?
  ) -> InstantQueryCursor {
    InstantQueryCursor(
      entityID: querySnapshot.snapshot.id,
      sortValue: order.flatMap { Self.orderValue(querySnapshot, field: $0.field) }
    )
  }

  private mutating func insert(_ triple: InstantTriple, attribute: InstantAttribute?) {
    var triple = Self.normalizedTriple(triple, attribute: attribute)
    if let existing = eav[triple.entityID]?[triple.attributeID]?[triple.value] {
      triple.txTime = existing.txTime
    }

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

  private mutating func merge(_ triple: InstantTriple, attribute: InstantAttribute?) {
    guard
      attribute?.cardinality != .many,
      let existing = eav[triple.entityID]?[triple.attributeID]?.values.first
    else {
      insert(triple, attribute: attribute)
      return
    }

    var merged = triple
    merged.value = Self.deepMerge(existing.value, with: triple.value)
    insert(merged, attribute: attribute)
  }

  private static func deepMerge(_ current: InstantValue, with update: InstantValue) -> InstantValue {
    guard
      case let .json(currentJSON) = current,
      case let .json(updateJSON) = update
    else { return update }
    return .json(deepMerge(currentJSON, with: updateJSON))
  }

  private static func deepMerge(_ current: JSONValue, with update: JSONValue) -> JSONValue {
    guard
      case let .object(currentFields) = current,
      case let .object(updateFields) = update
    else { return update }

    var merged = currentFields
    for (key, value) in updateFields {
      if let currentValue = merged[key] {
        merged[key] = deepMerge(currentValue, with: value)
      } else {
        merged[key] = value
      }
    }
    return .object(merged)
  }

  private mutating func remove(_ triple: InstantTriple, attribute: InstantAttribute?) {
    let triple = Self.normalizedTriple(triple, attribute: attribute)
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

  private static func normalizedTriple(
    _ triple: InstantTriple,
    attribute: InstantAttribute?
  ) -> InstantTriple {
    var triple = triple
    triple.value = normalizedValue(triple.value, attribute: attribute)
    return triple
  }

  private static func normalizedValue(
    _ value: InstantValue,
    attribute: InstantAttribute?
  ) -> InstantValue {
    guard attribute?.valueType == .date, let date = InstantDateCoercion.coerce(value) else {
      return value
    }
    return .date(date)
  }

  private mutating func deleteEntity(
    _ entityID: String,
    attributes: AttributeStore,
    visited: inout Set<String>
  ) -> Set<String> {
    guard visited.insert(entityID).inserted else { return [] }

    var changed: Set<String> = [entityID]
    let outgoingTriples = triples(entityID: entityID)
    let incomingTriples = reverseRefTriples(targetEntityID: entityID)

    for triple in outgoingTriples {
      guard
        let attribute = attributes[triple.attributeID],
        attribute.valueType == .ref,
        let targetID = triple.value.refValue
      else { continue }

      changed.insert(targetID)
      if attribute.onDeleteReverse == .cascade {
        changed.formUnion(deleteEntity(targetID, attributes: attributes, visited: &visited))
      }
    }

    for triple in incomingTriples {
      let attribute = attributes[triple.attributeID]
      changed.insert(triple.entityID)
      if attribute?.onDelete == .cascade {
        changed.formUnion(deleteEntity(triple.entityID, attributes: attributes, visited: &visited))
      }
    }

    for triple in outgoingTriples {
      remove(triple, attribute: attributes[triple.attributeID])
    }
    for triple in incomingTriples {
      remove(triple, attribute: attributes[triple.attributeID])
    }

    return changed
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
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .equals(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard materializedValue(snapshot, field: field)?.contains(value) == true else { return false }
      case let .notEquals(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .notEquals(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard isDeclaredField(field, namespace: namespace, attributes: attributes) else { return false }
        guard matchesNotEquals(snapshot, field: field, value: value) else { return false }
      case let .greaterThan(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .greaterThan(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(snapshot, field: field, value: value, allowed: [.orderedDescending])
        else { return false }
      case let .greaterThanOrEqual(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .greaterThanOrEqual(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          allowed: [.orderedSame, .orderedDescending]
        )
        else { return false }
      case let .lessThan(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .lessThan(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(snapshot, field: field, value: value, allowed: [.orderedAscending])
        else { return false }
      case let .lessThanOrEqual(field, value):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .lessThanOrEqual(field: nested.field, value: value),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        let value = normalizedValue(value, field: field, namespace: namespace, attributes: attributes)
        guard matchesComparison(
          snapshot,
          field: field,
          value: value,
          allowed: [.orderedAscending, .orderedSame]
        )
        else { return false }
      case let .in(field, values):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .in(field: nested.field, values: values),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard let materialized = materializedValue(snapshot, field: field), !values.isEmpty
        else { return false }
        let values = normalizedValues(values, field: field, namespace: namespace, attributes: attributes)
        guard materialized.values.contains(where: values.contains) else { return false }
      case let .like(field, pattern):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .like(field: nested.field, pattern: pattern),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard matchesStringPattern(snapshot, field: field, pattern: pattern, caseInsensitive: false)
        else { return false }
      case let .iLike(field, pattern):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .iLike(field: nested.field, pattern: pattern),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard matchesStringPattern(snapshot, field: field, pattern: pattern, caseInsensitive: true)
        else { return false }
      case let .isNull(field):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .isNull(field: nested.field),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
        guard isDeclaredField(field, namespace: namespace, attributes: attributes) else { return false }
        guard isFieldNull(snapshot, field: field) else { return false }
      case let .isNotNull(field):
        if let nested = nestedField(field) {
          guard matchesNestedField(
            snapshot,
            nested: nested,
            filter: .isNotNull(field: nested.field),
            namespace: namespace,
            attributes: attributes
          )
          else { return false }
          continue
        }
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

  private static func validate(
    filters: [InstantQueryFilter],
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    for filter in filters {
      if let issue = validate(filter: filter, namespace: namespace, attributes: attributes) {
        return issue
      }
    }
    return nil
  }

  private static func validate(
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    switch filter {
    case let .equals(field, value), let .notEquals(field, value):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        return validateFilterValue(value, field: field, attribute: attribute)

      case let .failure(issue):
        return issue
      }

    case let .greaterThan(field, value),
      let .greaterThanOrEqual(field, value),
      let .lessThan(field, value),
      let .lessThanOrEqual(field, value):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        if let issue = validateFilterValue(value, field: field, attribute: attribute) {
          return issue
        }
        guard attribute.valueType.isRangeComparableInQueries else {
          return unsupportedRangeFilterIssue(field: field, attribute: attribute)
        }
        return nil

      case let .failure(issue):
        return issue
      }

    case let .in(field, values):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        for value in values {
          if let issue = validateFilterValue(value, field: field, attribute: attribute) {
            return issue
          }
        }
        return nil

      case let .failure(issue):
        return issue
      }

    case let .like(field, _), let .iLike(field, _):
      switch validateFilterField(
        field,
        namespace: namespace,
        attributes: attributes
      ) {
      case let .success(attribute):
        guard attribute.valueType == .string else {
          return incompatibleFilterValueIssue(
            field: field,
            attribute: attribute,
            received: "pattern"
          )
        }
        return nil

      case let .failure(issue):
        return issue
      }

    case let .isNull(field), let .isNotNull(field):
      return validateFieldReference(
        field,
        namespace: namespace,
        attributes: attributes,
        context: "query filter",
        allowNested: true
      )

    case let .and(filters), let .or(filters):
      return validate(filters: filters, namespace: namespace, attributes: attributes)
    }
  }

  private static func validateSelectedFields(
    _ fields: [String]?,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    guard let fields else { return nil }
    for field in fields {
      if let issue = validateFieldReference(
        field,
        namespace: namespace,
        attributes: attributes,
        context: "selected field",
        allowNested: false
      ) {
        return issue
      }
    }
    return nil
  }

  private static func validateOrder(
    _ order: InstantQueryOrder?,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    guard let order, !order.isServerCreatedAt else { return nil }
    return validateFieldReference(
      order.field,
      namespace: namespace,
      attributes: attributes,
      context: "query order",
      allowNested: false
    )
  }

  private static func validateIncludes(
    _ includes: [InstantQueryInclude]?,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantQueryValidationIssue? {
    guard let includes else { return nil }
    for include in includes {
      let childNamespace: String?
      switch include.direction {
      case .forward:
        childNamespace = attributes.attribute(namespace: namespace, name: include.name).flatMap {
          attribute in
          guard attribute.valueType == .ref else { return nil }
          return attribute.linkNamespace
        }

      case .reverse:
        childNamespace = reverseAttribute(
          namespace: namespace,
          name: include.name,
          attributes: attributes
        )?.namespace
      }

      guard let childNamespace else {
        return InstantQueryValidationIssue(
          namespace: namespace,
          path: include.name,
          message: "'\(include.name)' is not a declared \(include.direction.rawValue) relation.",
          recovery: "Include a declared ref relation, or update the schema attributes before querying."
        )
      }

      guard let query = include.query else { continue }
      guard query.namespace == childNamespace else {
        return InstantQueryValidationIssue(
          namespace: namespace,
          path: include.name,
          message: "Include '\(include.name)' targets '\(childNamespace)' but its query targets '\(query.namespace)'.",
          recovery: "Use an include query for the relation's target namespace."
        )
      }
      if let issue = validate(filters: query.filters, namespace: query.namespace, attributes: attributes) {
        return issue
      }
      if let issue = validateSelectedFields(
        query.selectedFields,
        namespace: query.namespace,
        attributes: attributes
      ) {
        return issue
      }
      if let issue = validateOrder(query.order, namespace: query.namespace, attributes: attributes) {
        return issue
      }
    }
    return nil
  }

  private static func validateFieldReference(
    _ field: String,
    namespace: String,
    attributes: AttributeStore,
    context: String,
    allowNested: Bool
  ) -> InstantQueryValidationIssue? {
    switch resolvedFieldAttribute(
      field,
      namespace: namespace,
      attributes: attributes,
      context: context,
      allowNested: allowNested
    ) {
    case .success:
      return nil

    case let .failure(issue):
      return issue
    }
  }

  private static func validateFilterField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Result<InstantAttribute, InstantQueryValidationIssue> {
    resolvedFieldAttribute(
      field,
      namespace: namespace,
      attributes: attributes,
      context: "query filter",
      allowNested: true
    )
  }

  private static func resolvedFieldAttribute(
    _ field: String,
    namespace: String,
    attributes: AttributeStore,
    context: String,
    allowNested: Bool
  ) -> Result<InstantAttribute, InstantQueryValidationIssue> {
    if !field.contains(".") {
      guard let attribute = attributes.attribute(namespace: namespace, name: field) else {
        return .failure(undeclaredFieldIssue(field, namespace: namespace, context: context))
      }
      return .success(attribute)
    }

    guard allowNested else {
      return .failure(
        InstantQueryValidationIssue(
          namespace: namespace,
          path: field,
          message: "\(context) '\(field)' cannot use a nested relation path.",
          recovery: "Use a direct field for this query clause."
        )
      )
    }
    guard let nested = nestedField(field) else {
      return .failure(
        InstantQueryValidationIssue(
          namespace: namespace,
          path: field,
          message: "Nested field path '\(field)' is not supported.",
          recovery: "Use one or more relations followed by a field, such as 'project.owner.name'."
        )
      )
    }
    switch nestedFieldTargetNamespace(nested, namespace: namespace, attributes: attributes) {
    case let .success(targetNamespace):
      guard let attribute = attributes.attribute(namespace: targetNamespace, name: nested.field)
      else {
        return .failure(
          undeclaredFieldIssue(
            nested.field,
            namespace: targetNamespace,
            context: context,
            path: field
          )
        )
      }
      return .success(attribute)

    case let .failure(invalidRelation):
      return .failure(
        InstantQueryValidationIssue(
          namespace: invalidRelation.namespace,
          path: field,
          message: "'\(invalidRelation.name)' is not a declared relation.",
          recovery: "Filter through a declared forward or reverse relation."
        )
      )
    }
  }

  private static func validateFilterValue(
    _ value: InstantValue,
    field: String,
    attribute: InstantAttribute
  ) -> InstantQueryValidationIssue? {
    if isCompatibleFilterValue(value, with: attribute) {
      return nil
    }
    return incompatibleFilterValueIssue(
      field: field,
      attribute: attribute,
      received: value.queryValidationTypeDescription
    )
  }

  private static func isCompatibleFilterValue(
    _ value: InstantValue,
    with attribute: InstantAttribute
  ) -> Bool {
    if case .null = value {
      return !attribute.isRequired
    }

    switch (value, attribute.valueType) {
    case (.string, .string),
      (.number, .number),
      (.bool, .boolean),
      (.json, .json),
      (.ref, .ref):
      return true

    case (.date, .date):
      return true

    case (.string, .date), (.number, .date):
      return InstantDateCoercion.coerce(value) != nil

    case (.null, _),
      (.string, _),
      (.number, _),
      (.bool, _),
      (.date, _),
      (.json, _),
      (.ref, _),
      (.lookupRef, _):
      return false
    }
  }

  private static func incompatibleFilterValueIssue(
    field: String,
    attribute: InstantAttribute,
    received: String
  ) -> InstantQueryValidationIssue {
    InstantQueryValidationIssue(
      namespace: attribute.namespace,
      path: field,
      message:
        "query filter '\(field)' expects \(attribute.valueType.queryValidationDescription) values, but received \(received).",
      recovery: "Use a filter value that matches the schema attribute type."
    )
  }

  private static func unsupportedRangeFilterIssue(
    field: String,
    attribute: InstantAttribute
  ) -> InstantQueryValidationIssue {
    InstantQueryValidationIssue(
      namespace: attribute.namespace,
      path: field,
      message:
        "query filter '\(field)' cannot use range operators with \(attribute.valueType.queryValidationDescription) values.",
      recovery: "Use range operators with string, number, boolean, or date fields."
    )
  }

  private static func isDeclaredField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    attributes.attribute(namespace: namespace, name: field) != nil
  }

  private static func undeclaredFieldIssue(
    _ field: String,
    namespace: String,
    context: String,
    path: String? = nil
  ) -> InstantQueryValidationIssue {
    InstantQueryValidationIssue(
      namespace: namespace,
      path: path ?? field,
      message: "\(context) '\(path ?? field)' references an undeclared field.",
      recovery: "Declare the field in the schema attributes, or remove it from the query."
    )
  }

  private static func nestedField(_ field: String) -> NestedField? {
    let parts = field.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
    return NestedField(
      relations: parts.dropLast().map(String.init),
      field: String(parts[parts.count - 1])
    )
  }

  private static func nestedFieldTargetNamespace(
    _ nested: NestedField,
    namespace: String,
    attributes: AttributeStore
  ) -> Result<String, InvalidNestedRelation> {
    var namespace = namespace
    for relation in nested.relations {
      guard let targetNamespace = relationTargetNamespace(
        relation,
        namespace: namespace,
        attributes: attributes
      ) else {
        return .failure(InvalidNestedRelation(name: relation, namespace: namespace))
      }
      namespace = targetNamespace
    }
    return .success(namespace)
  }

  private static func relationTargetNamespace(
    _ relation: String,
    namespace: String,
    attributes: AttributeStore
  ) -> String? {
    if
      let attribute = attributes.attribute(namespace: namespace, name: relation),
      attribute.valueType == .ref,
      let linkNamespace = attribute.linkNamespace
    {
      return linkNamespace
    }

    return reverseAttribute(
      namespace: namespace,
      name: relation,
      attributes: attributes
    )?.namespace
  }

  private static func reverseAttribute(
    namespace: String,
    name: String,
    attributes: AttributeStore
  ) -> InstantAttribute? {
    attributes.attributes.first {
      $0.valueType == .ref
        && $0.linkNamespace == namespace
        && $0.reverseIdentity == "\(namespace)/\(name)"
    }
  }

  private func selectedFieldsReferenceDeclaredFields(
    _ fields: [String]?,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    fields?.allSatisfy { isDeclaredField($0, namespace: namespace, attributes: attributes) } ?? true
  }

  private func orderReferencesDeclaredField(
    _ order: InstantQueryOrder?,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard let order else { return true }
    guard !order.isServerCreatedAt else { return true }
    return isDeclaredField(order.field, namespace: namespace, attributes: attributes)
  }

  private func includesReferenceDeclaredLinks(
    _ includes: [InstantQueryInclude]?,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard let includes else { return true }
    return includes.allSatisfy { include in
      let childNamespace: String?
      switch include.direction {
      case .forward:
        childNamespace = attributes.attribute(namespace: namespace, name: include.name).flatMap {
          attribute in
          guard attribute.valueType == .ref else { return nil }
          return attribute.linkNamespace
        }

      case .reverse:
        childNamespace = reverseAttribute(
          namespace: namespace,
          name: include.name,
          attributes: attributes
        )?.namespace
      }

      guard let childNamespace else { return false }
      guard let query = include.query else { return true }
      guard query.namespace == childNamespace else { return false }
      guard filtersReferenceDeclaredFields(
        query.filters,
        namespace: query.namespace,
        attributes: attributes
      )
      else { return false }
      guard selectedFieldsReferenceDeclaredFields(
        query.selectedFields,
        namespace: query.namespace,
        attributes: attributes
      )
      else { return false }
      guard orderReferencesDeclaredField(query.order, namespace: query.namespace, attributes: attributes)
      else { return false }
      return true
    }
  }

  private func reverseAttribute(
    namespace: String,
    name: String,
    attributes: AttributeStore
  ) -> InstantAttribute? {
    attributes.attributes.first {
      $0.valueType == .ref
        && $0.linkNamespace == namespace
        && $0.reverseIdentity == "\(namespace)/\(name)"
    }
  }

  private func project(
    _ snapshots: [InstantEntitySnapshot],
    selectedFields: [String]?
  ) -> [InstantEntitySnapshot] {
    guard let selectedFields else { return snapshots }
    let selectedFieldSet = Set(selectedFields)
    return snapshots.map { snapshot in
      InstantEntitySnapshot(
        id: snapshot.id,
        namespace: snapshot.namespace,
        values: snapshot.values.filter { selectedFieldSet.contains($0.key) },
        links: snapshot.links
      )
    }
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
      return fieldReferencesDeclaredField(field, namespace: namespace, attributes: attributes)

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

  private func fieldReferencesDeclaredField(
    _ field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard field.contains(".") else {
      return isDeclaredField(field, namespace: namespace, attributes: attributes)
    }
    guard
      let nested = nestedField(field),
      case let .success(targetNamespace) = Self.nestedFieldTargetNamespace(
        nested,
        namespace: namespace,
        attributes: attributes
      )
    else { return false }
    return isDeclaredField(nested.field, namespace: targetNamespace, attributes: attributes)
  }

  private struct NestedField: Hashable, Sendable {
    var relations: [String]
    var field: String
  }

  private struct InvalidNestedRelation: Error, Hashable, Sendable {
    var name: String
    var namespace: String
  }

  private struct NestedFieldSnapshots: Hashable, Sendable {
    var namespace: String
    var snapshots: [InstantEntitySnapshot]
  }

  private func nestedField(_ field: String) -> NestedField? {
    let parts = field.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
    return NestedField(
      relations: parts.dropLast().map(String.init),
      field: String(parts[parts.count - 1])
    )
  }

  private func nestedFieldTargetNamespace(
    _ nested: NestedField,
    namespace: String,
    attributes: AttributeStore
  ) -> Result<String, InvalidNestedRelation> {
    Self.nestedFieldTargetNamespace(nested, namespace: namespace, attributes: attributes)
  }

  private func relationTargetNamespace(
    _ relation: String,
    namespace: String,
    attributes: AttributeStore
  ) -> String? {
    Self.relationTargetNamespace(relation, namespace: namespace, attributes: attributes)
  }

  private func linkedSnapshots(
    for snapshot: InstantEntitySnapshot,
    relation: String,
    namespace: String,
    attributes: AttributeStore
  ) -> NestedFieldSnapshots? {
    if
      let attribute = attributes.attribute(namespace: namespace, name: relation),
      attribute.valueType == .ref,
      let linkNamespace = attribute.linkNamespace
    {
      let ids = Set(snapshot.values[relation]?.values.compactMap(\.refValue) ?? [])
      return NestedFieldSnapshots(
        namespace: linkNamespace,
        snapshots: ids.sorted().compactMap {
          self.snapshot(entityID: $0, namespace: linkNamespace, attributes: attributes)
        }
      )
    }

    if
      let attribute = reverseAttribute(
        namespace: namespace,
        name: relation,
        attributes: attributes
      )
    {
      let ids =
        vae[.ref(snapshot.id)]?[attribute.id]?.keys.sorted()
        ?? []
      return NestedFieldSnapshots(
        namespace: attribute.namespace,
        snapshots: ids.compactMap {
          self.snapshot(entityID: $0, namespace: attribute.namespace, attributes: attributes)
        }
      )
    }

    return nil
  }

  private func matchesNestedField(
    _ snapshot: InstantEntitySnapshot,
    nested: NestedField,
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    matchesNestedField(
      snapshot,
      relations: nested.relations[...],
      filter: filter,
      namespace: namespace,
      attributes: attributes
    )
  }

  private func matchesNestedField(
    _ snapshot: InstantEntitySnapshot,
    relations: ArraySlice<String>,
    filter: InstantQueryFilter,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard let relation = relations.first else {
      return matches(snapshot, filter: filter, namespace: namespace, attributes: attributes)
    }
    guard
      let linked = linkedSnapshots(
        for: snapshot,
        relation: relation,
        namespace: namespace,
        attributes: attributes
      )
    else { return false }
    guard !linked.snapshots.isEmpty else {
      switch filter {
      case .notEquals, .isNull:
        return true
      default:
        return false
      }
    }
    return linked.snapshots.contains {
      matchesNestedField(
        $0,
        relations: relations.dropFirst(),
        filter: filter,
        namespace: linked.namespace,
        attributes: attributes
      )
    }
  }

  private func materializedValue(
    _ snapshot: InstantEntitySnapshot,
    field: String
  ) -> InstantMaterializedValue? {
    snapshot.values[field] ?? (field == "id" ? .one(.string(snapshot.id)) : nil)
  }

  private func normalizedValue(
    _ value: InstantValue,
    field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> InstantValue {
    Self.normalizedValue(
      value,
      attribute: attributes.attribute(namespace: namespace, name: field)
    )
  }

  private func normalizedValues(
    _ values: [InstantValue],
    field: String,
    namespace: String,
    attributes: AttributeStore
  ) -> [InstantValue] {
    let attribute = attributes.attribute(namespace: namespace, name: field)
    return values.map { Self.normalizedValue($0, attribute: attribute) }
  }

  private func matchesNotEquals(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    value: InstantValue
  ) -> Bool {
    guard let materialized = materializedValue(snapshot, field: field) else { return true }
    return materialized.values.contains { $0 != value } || materialized.values.contains(.null)
  }

  private func isFieldNull(_ snapshot: InstantEntitySnapshot, field: String) -> Bool {
    guard let materialized = materializedValue(snapshot, field: field) else { return true }
    return materialized.values.contains(.null)
  }

  private func matchesComparison(
    _ snapshot: InstantEntitySnapshot,
    field: String,
    value: InstantValue,
    allowed: Set<ComparisonResult>
  ) -> Bool {
    guard let materialized = materializedValue(snapshot, field: field) else { return false }
    return materialized.values.contains {
      guard Self.canRangeCompare($0, value) else { return false }
      return allowed.contains($0.compare(to: value))
    }
  }

  private static func canRangeCompare(_ lhs: InstantValue, _ rhs: InstantValue) -> Bool {
    switch (lhs, rhs) {
    case (.string, .string), (.number, .number), (.date, .date), (.bool, .bool):
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
    guard let materialized = materializedValue(snapshot, field: field) else { return false }
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

  private static func compare(
    _ lhs: QuerySnapshot,
    _ rhs: QuerySnapshot,
    order: InstantQueryOrder?
  ) -> ComparisonResult {
    guard let order else {
      return lhs.snapshot.id.compare(rhs.snapshot.id)
    }

    let lhsValue = orderValue(lhs, field: order.field)
    let rhsValue = orderValue(rhs, field: order.field)
    let valueComparison = compare(lhsValue, rhsValue)
    let directedComparison: ComparisonResult
    switch order.direction {
    case .ascending:
      directedComparison = valueComparison
    case .descending:
      directedComparison = valueComparison.reversed
    }
    guard directedComparison == .orderedSame else {
      return directedComparison
    }

    switch order.direction {
    case .ascending:
      return lhs.snapshot.id.compare(rhs.snapshot.id)
    case .descending:
      return rhs.snapshot.id.compare(lhs.snapshot.id)
    }
  }

  private static func effectiveOrder(_ order: InstantQueryOrder?) -> InstantQueryOrder {
    order ?? .serverCreatedAt
  }

  private static func compare(
    _ querySnapshot: QuerySnapshot,
    to cursor: InstantQueryCursor,
    order: InstantQueryOrder?,
    namespace: String,
    attributes: AttributeStore
  ) -> ComparisonResult {
    guard let order, let sortValue = cursor.sortValue else {
      return querySnapshot.snapshot.id.compare(cursor.entityID)
    }

    let value = orderValue(querySnapshot, field: order.field)
    let normalizedSortValue = normalizedValue(
      sortValue,
      attribute: attributes.attribute(namespace: namespace, name: order.field)
    )
    let valueComparison = compare(value, normalizedSortValue)
    let directedComparison: ComparisonResult
    switch order.direction {
    case .ascending:
      directedComparison = valueComparison
    case .descending:
      directedComparison = valueComparison.reversed
    }
    guard directedComparison == .orderedSame else {
      return directedComparison
    }

    switch order.direction {
    case .ascending:
      return querySnapshot.snapshot.id.compare(cursor.entityID)
    case .descending:
      return cursor.entityID.compare(querySnapshot.snapshot.id)
    }
  }

  private static func orderValue(_ querySnapshot: QuerySnapshot, field: String) -> InstantValue? {
    field == InstantQueryOrder.serverCreatedAtField
      ? querySnapshot.serverCreatedAt
      : querySnapshot.snapshot.values[field]?.first
  }

  private static func compare(_ lhs: InstantValue?, _ rhs: InstantValue?) -> ComparisonResult {
    switch (lhs, rhs) {
    case (nil, nil):
      return .orderedSame
    case (nil, .some):
      return .orderedAscending
    case (.some, nil):
      return .orderedDescending
    case let (.some(lhs), .some(rhs)):
      return lhs.compare(to: rhs)
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

private extension InstantValue {
  var queryValidationTypeDescription: String {
    switch self {
    case .null:
      return "null"
    case .string:
      return "string"
    case .number:
      return "number"
    case .bool:
      return "boolean"
    case .date:
      return "date"
    case .json:
      return "json"
    case .ref:
      return "ref"
    case .lookupRef:
      return "lookup ref"
    }
  }
}

private extension InstantValueType {
  var queryValidationDescription: String {
    switch self {
    case .string:
      return "string"
    case .number:
      return "number"
    case .boolean:
      return "boolean"
    case .date:
      return "date"
    case .json:
      return "json"
    case .ref:
      return "ref"
    }
  }

  var isRangeComparableInQueries: Bool {
    switch self {
    case .string, .number, .boolean, .date:
      return true
    case .json, .ref:
      return false
    }
  }
}

private extension ComparisonResult {
  var reversed: Self {
    switch self {
    case .orderedAscending:
      return .orderedDescending
    case .orderedDescending:
      return .orderedAscending
    case .orderedSame:
      return .orderedSame
    }
  }
}
