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

  func entityIDs(matching lookup: InstantLookupRef) -> [String] {
    let value = lookup.value.instantValue
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
    guard filtersReferenceDeclaredFields(plan.filters, namespace: plan.namespace, attributes: attributes)
    else { return InstantQueryPage(values: [], pageInfo: pageInfo(for: [], plan: plan)) }
    guard selectedFieldsReferenceDeclaredFields(
      plan.selectedFields,
      namespace: plan.namespace,
      attributes: attributes
    )
    else { return InstantQueryPage(values: [], pageInfo: pageInfo(for: [], plan: plan)) }
    guard includesReferenceDeclaredLinks(plan.includes, namespace: plan.namespace, attributes: attributes)
    else { return InstantQueryPage(values: [], pageInfo: pageInfo(for: [], plan: plan)) }

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

    snapshots.sort {
      Self.compare($0, $1, order: plan.order) == .orderedAscending
    }

    let paged = paginate(snapshots, plan: plan)
    let linked = includeLinks(paged.values, plan: plan, attributes: attributes)
    return InstantQueryPage(
      values: project(linked, selectedFields: plan.selectedFields),
      pageInfo: paged.pageInfo
    )
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

  private func paginate(
    _ snapshots: [InstantEntitySnapshot],
    plan: InstantQueryPlan
  ) -> (values: [InstantEntitySnapshot], pageInfo: InstantQueryPageInfo?) {
    guard isValidPagination(plan) else {
      return ([], pageInfo(for: [], plan: plan))
    }

    var page = snapshots
    var removedBefore = 0
    var removedAfter = 0

    if let after = plan.after {
      let startIndex: Int
      if after.sortValue == nil {
        guard let index = page.firstIndex(where: { $0.id == after.entityID }) else {
          return ([], pageInfo(for: [], plan: plan))
        }
        startIndex = after.inclusive ? index : index + 1
      } else {
        startIndex = page.firstIndex {
          let comparison = Self.compare($0, to: after, order: plan.order)
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
        guard let index = page.firstIndex(where: { $0.id == before.entityID }) else {
          return ([], pageInfo(for: [], plan: plan))
        }
        endIndex = before.inclusive ? index + 1 : index
      } else {
        endIndex = page.firstIndex {
          let comparison = Self.compare($0, to: before, order: plan.order)
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
    for snapshots: [InstantEntitySnapshot],
    plan: InstantQueryPlan,
    hasPreviousPage: Bool = false,
    hasNextPage: Bool = false
  ) -> InstantQueryPageInfo? {
    guard requestsPageInfo(plan) else { return nil }
    return InstantQueryPageInfo(
      startCursor: snapshots.first.map { cursor(for: $0, order: plan.order) },
      endCursor: snapshots.last.map { cursor(for: $0, order: plan.order) },
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
    for snapshot: InstantEntitySnapshot,
    order: InstantQueryOrder?
  ) -> InstantQueryCursor {
    InstantQueryCursor(
      entityID: snapshot.id,
      sortValue: order.flatMap { snapshot.values[$0.field]?.first }
    )
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

  private func selectedFieldsReferenceDeclaredFields(
    _ fields: [String]?,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    fields?.allSatisfy { isDeclaredField($0, namespace: namespace, attributes: attributes) } ?? true
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
      let targetNamespace = nestedFieldTargetNamespace(
        nested,
        namespace: namespace,
        attributes: attributes
      )
    else { return false }
    return isDeclaredField(nested.field, namespace: targetNamespace, attributes: attributes)
  }

  private struct NestedField: Hashable, Sendable {
    var relation: String
    var field: String
  }

  private struct NestedFieldSnapshots: Hashable, Sendable {
    var namespace: String
    var snapshots: [InstantEntitySnapshot]
  }

  private func nestedField(_ field: String) -> NestedField? {
    let parts = field.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
    return NestedField(relation: String(parts[0]), field: String(parts[1]))
  }

  private func nestedFieldTargetNamespace(
    _ nested: NestedField,
    namespace: String,
    attributes: AttributeStore
  ) -> String? {
    if
      let attribute = attributes.attribute(namespace: namespace, name: nested.relation),
      attribute.valueType == .ref,
      let linkNamespace = attribute.linkNamespace
    {
      return linkNamespace
    }

    return reverseAttribute(
      namespace: namespace,
      name: nested.relation,
      attributes: attributes
    )?.namespace
  }

  private func linkedSnapshots(
    for snapshot: InstantEntitySnapshot,
    nested: NestedField,
    namespace: String,
    attributes: AttributeStore
  ) -> NestedFieldSnapshots? {
    if
      let attribute = attributes.attribute(namespace: namespace, name: nested.relation),
      attribute.valueType == .ref,
      let linkNamespace = attribute.linkNamespace
    {
      let ids = Set(snapshot.values[nested.relation]?.values.compactMap(\.refValue) ?? [])
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
        name: nested.relation,
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
    guard
      let linked = linkedSnapshots(
        for: snapshot,
        nested: nested,
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
      matches($0, filter: filter, namespace: linked.namespace, attributes: attributes)
    }
  }

  private func materializedValue(
    _ snapshot: InstantEntitySnapshot,
    field: String
  ) -> InstantMaterializedValue? {
    snapshot.values[field] ?? (field == "id" ? .one(.string(snapshot.id)) : nil)
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
    _ lhs: InstantEntitySnapshot,
    _ rhs: InstantEntitySnapshot,
    order: InstantQueryOrder?
  ) -> ComparisonResult {
    guard let order else {
      return lhs.id.compare(rhs.id)
    }

    let lhsValue = lhs.values[order.field]?.first
    let rhsValue = rhs.values[order.field]?.first
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
      return lhs.id.compare(rhs.id)
    case .descending:
      return rhs.id.compare(lhs.id)
    }
  }

  private static func compare(
    _ snapshot: InstantEntitySnapshot,
    to cursor: InstantQueryCursor,
    order: InstantQueryOrder?
  ) -> ComparisonResult {
    guard let order, let sortValue = cursor.sortValue else {
      return snapshot.id.compare(cursor.entityID)
    }

    let value = snapshot.values[order.field]?.first
    let valueComparison = compare(value, sortValue)
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
      return snapshot.id.compare(cursor.entityID)
    case .descending:
      return cursor.entityID.compare(snapshot.id)
    }
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
