import Foundation

// History:
// - 2026-10-24: a query with no nested include whose rows fit its limits passes through without the general pass's
//   maps, and every attribute lookup reads the triples' own attributes or searches the schema once per include, never a
//   map of the whole schema: run twice per refresh (the translator, then the persisted result), the pass built maps of
//   every attribute (2,283 on the phone) and every row, about 6.5 MB of a 64-line refresh with nothing to drop (#1147).

/// Apply InstaQL nested include limits before authoritative and persisted apply.
///
/// TypeScript Reactor constructs a raw per-query store before InstaQL applies
/// nested limits client-side. Swift instead has one shared authoritative hot
/// store, so retaining the raw response would make one bounded observation grow
/// every other observation's resident base. SQLite Data SQL-limits the page.
///
/// The live-refresh translator uses this as Swift-specific containment before
/// it assembles the authoritative transaction, and persistence repeats the
/// defense at save/load. True server-side nested-limit pushdown remains the
/// structural fix. Live `transact` is unchanged.
enum InstantLiveQueryNestedLimit {
  /// `triples` without the rows the query's nested limits leave out, and without links to rows it left out. Returns
  /// `triples` itself when it keeps every one, as most refreshes do.
  static func limitedTriples(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> [InstantTriple] {
    let lookup = AttributeLookup(attributes, for: triples)
    let retained = retainedWithoutNestedIncludes(queryKey: queryKey, triples: triples, attributes: attributes, lookup: lookup)
      ?? generalRetainedEntityIDs(queryKey: queryKey, triples: triples, attributes: attributes, lookup: lookup)
    return kept(triples, retained: retained, lookup: lookup)
  }

  static func retainedEntityIDs(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> Set<String> {
    let lookup = AttributeLookup(attributes, for: triples)
    return retainedWithoutNestedIncludes(queryKey: queryKey, triples: triples, attributes: attributes, lookup: lookup)
      ?? generalRetainedEntityIDs(queryKey: queryKey, triples: triples, attributes: attributes, lookup: lookup)
  }

  /// The general pass alone, without the shortcut for queries with no nested include: what the shortcut must equal.
  static func generalLimitedTriplesForTesting(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> [InstantTriple] {
    let lookup = AttributeLookup(attributes, for: triples)
    let retained = generalRetainedEntityIDs(queryKey: queryKey, triples: triples, attributes: attributes, lookup: lookup)
    return kept(triples, retained: retained, lookup: lookup)
  }

  /// The general pass's retained rows, without the shortcut.
  static func generalRetainedEntityIDsForTesting(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> Set<String> {
    generalRetainedEntityIDs(
      queryKey: queryKey, triples: triples, attributes: attributes, lookup: AttributeLookup(attributes, for: triples)
    )
  }

  static func namespace(in attributeID: String) -> String? {
    guard let slash = attributeID.firstIndex(of: "/") else { return nil }
    let namespace = String(attributeID[..<slash])
    return namespace.isEmpty ? nil : namespace
  }

  /// The retained rows of a query whose nodes include nothing, when no node holds more rows than its limit: every row
  /// of the query's namespaces, as the general pass retains them, without its per-row maps or its sort. `nil` when the
  /// query includes something or a node's rows outgrow its limit (the server limits top-level rows, so rarely).
  private static func retainedWithoutNestedIncludes(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute],
    lookup: AttributeLookup
  ) -> Set<String>? {
    guard let object = parseJSONObject(queryKey), !attributes.isEmpty else { return entityIDs(of: triples) }
    var limits: [String: Int?] = [:]
    for (namespace, value) in object {
      guard let node = value as? [String: Any] else { continue }
      guard node.keys.allSatisfy({ $0 == "$" }) else { return nil }
      let options = node["$"] as? [String: Any] ?? [:]
      limits[namespace] = .some(jsonInt(options["limit"]) ?? jsonInt(options["first"]) ?? jsonInt(options["last"]))
    }
    var all: Set<String> = []
    var byNamespace: [String: Set<String>] = [:]
    for triple in triples {
      all.insert(triple.entityID)
      guard
        let namespace = lookup[triple.attributeID]?.namespace ?? namespace(in: triple.attributeID),
        limits.index(forKey: namespace) != nil
      else { continue }
      byNamespace[namespace, default: []].insert(triple.entityID)
    }
    var retained: Set<String> = []
    for (namespace, limit) in limits {
      let ids = byNamespace[namespace] ?? []
      if let limit, ids.count > limit { return nil }
      retained.formUnion(ids)
    }
    return retained.isEmpty ? all : retained
  }

  private static func generalRetainedEntityIDs(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute],
    lookup: AttributeLookup
  ) -> Set<String> {
    let allIDs = entityIDs(of: triples)
    guard let object = parseJSONObject(queryKey), !attributes.isEmpty else {
      return allIDs
    }
    let context = Context(triples: triples, attributes: attributes, lookup: lookup)
    var retained: Set<String> = []
    for (namespace, value) in object {
      guard let node = value as? [String: Any] else { continue }
      let candidates = context.entityIDsByNamespace[namespace] ?? []
      retained.formUnion(
        context.retainedEntities(
          namespace: namespace,
          node: node,
          candidateIDs: candidates
        )
      )
    }
    return retained.isEmpty ? allIDs : retained
  }

  /// The triples of retained rows, without many-cardinality links to rows not retained.
  private static func kept(_ triples: [InstantTriple], retained: Set<String>, lookup: AttributeLookup) -> [InstantTriple] {
    func keeps(_ triple: InstantTriple) -> Bool {
      guard retained.contains(triple.entityID) else { return false }
      guard let attribute = lookup[triple.attributeID],
        attribute.valueType == .ref,
        attribute.cardinality == .many,
        let childID = triple.value.refValue
      else {
        return true
      }
      return retained.contains(childID)
    }
    guard let firstDropped = triples.firstIndex(where: { !keeps($0) }) else { return triples }
    var kept = Array(triples[..<firstDropped])
    kept.reserveCapacity(triples.count)
    for triple in triples[(firstDropped + 1)...] where keeps(triple) {
      kept.append(triple)
    }
    return kept
  }

  private static func entityIDs(of triples: [InstantTriple]) -> Set<String> {
    var ids: Set<String> = []
    for triple in triples { ids.insert(triple.entityID) }
    return ids
  }
}

/// The attributes of one set of triples, by id: built from the triples' own attribute ids in one pass over the schema,
/// so a page of sixteen attributes costs sixteen entries whatever the schema's size (#1147).
private struct AttributeLookup {
  private var attributesByID: [String: InstantAttribute] = [:]

  init(_ attributes: [InstantAttribute], for triples: [InstantTriple]) {
    var wanted: Set<String> = []
    for triple in triples { wanted.insert(triple.attributeID) }
    attributesByID.reserveCapacity(wanted.count)
    for attribute in attributes where wanted.contains(attribute.id) && attributesByID[attribute.id] == nil {
      attributesByID[attribute.id] = attribute
    }
  }

  subscript(id: String) -> InstantAttribute? { attributesByID[id] }
}

private struct Context {
  var triplesByEntity: [String: [InstantTriple]]
  var entityIDsByNamespace: [String: Set<String>]
  /// The schema as given, searched only for a query's includes and order fields: a few searches a pass instead of a map
  /// of every attribute (#1147).
  private let attributes: [InstantAttribute]
  private let lookup: AttributeLookup

  init(triples: [InstantTriple], attributes: [InstantAttribute], lookup: AttributeLookup) {
    self.attributes = attributes
    self.lookup = lookup
    var triplesByEntity: [String: [InstantTriple]] = [:]
    var entityIDsByNamespace: [String: Set<String>] = [:]
    for triple in triples {
      triplesByEntity[triple.entityID, default: []].append(triple)
      let namespace = lookup[triple.attributeID]?.namespace
        ?? InstantLiveQueryNestedLimit.namespace(in: triple.attributeID)
      if let namespace {
        entityIDsByNamespace[namespace, default: []].insert(triple.entityID)
      }
    }
    self.triplesByEntity = triplesByEntity
    self.entityIDsByNamespace = entityIDsByNamespace
  }

  func retainedEntities(
    namespace: String,
    node: [String: Any],
    candidateIDs: Set<String>
  ) -> Set<String> {
    let options = node["$"] as? [String: Any] ?? [:]
    let limit = jsonInt(options["limit"]) ?? jsonInt(options["first"]) ?? jsonInt(options["last"])
    let order = parseOrder(options["order"])
    let ordered = sorted(Array(candidateIDs), namespace: namespace, order: order)
    let limited = limit.map { Array(ordered.prefix($0)) } ?? ordered
    var retained = Set(limited)
    for (includeName, nested) in node where includeName != "$" {
      guard let nestedNode = nested as? [String: Any] else { continue }
      guard let resolved = resolveInclude(parentNamespace: namespace, includeName: includeName)
      else {
        continue
      }
      // Once per include rather than once per parent.
      let stringLinkAttributeID = resolved.reverseLink.map { reverseLink in
        attribute(namespace: reverseLink.namespace, name: "\(reverseLink.name)ID")?.id
          ?? "\(reverseLink.namespace)/\(reverseLink.name)ID"
      }
      var childRetained: Set<String> = []
      for parentID in retained {
        let kids = children(
          of: parentID,
          reverseLink: resolved.reverseLink,
          stringLinkAttributeID: stringLinkAttributeID,
          parentLink: resolved.parentLink
        )
        childRetained.formUnion(
          retainedEntities(
            namespace: resolved.childNamespace,
            node: nestedNode,
            candidateIDs: kids
          )
        )
      }
      retained.formUnion(childRetained)
    }
    return retained
  }

  func resolveInclude(
    parentNamespace: String,
    includeName: String
  ) -> (childNamespace: String, reverseLink: InstantAttribute?, parentLink: InstantAttribute?)? {
    let identity = "\(parentNamespace)/\(includeName)"
    let reverseLink = attributes.first { $0.reverseIdentity == identity }
    let parentLink = attributes.first {
      $0.namespace == parentNamespace && $0.name == includeName && $0.valueType == .ref
    }
    let childNamespace = reverseLink?.namespace ?? parentLink?.linkNamespace
    guard let childNamespace else { return nil }
    return (childNamespace, reverseLink, parentLink)
  }

  func children(
    of parentID: String,
    reverseLink: InstantAttribute?,
    stringLinkAttributeID: String?,
    parentLink: InstantAttribute?
  ) -> Set<String> {
    var ids: Set<String> = []
    if let reverseLink {
      for (entityID, triples) in triplesByEntity {
        for triple in triples {
          let matchesLink = triple.attributeID == reverseLink.id
            || triple.attributeID == stringLinkAttributeID
          guard matchesLink, let linked = linkedEntityID(from: triple.value), linked == parentID else {
            continue
          }
          ids.insert(entityID)
        }
      }
    }
    if let parentLink, let parentTriples = triplesByEntity[parentID] {
      for triple in parentTriples where triple.attributeID == parentLink.id {
        if let childID = linkedEntityID(from: triple.value) {
          ids.insert(childID)
        }
      }
    }
    return ids
  }

  func linkedEntityID(from value: InstantValue) -> String? {
    switch value {
    case let .ref(id):
      return id
    case let .string(id):
      return id
    default:
      return nil
    }
  }

  func sorted(
    _ entityIDs: [String],
    namespace: String,
    order: [(field: String, descending: Bool)]
  ) -> [String] {
    guard !order.isEmpty else {
      return entityIDs.sorted()
    }
    // Each clause's attribute once, not once per comparison.
    let clauses = order.map { clause in
      (
        attributeID: attribute(namespace: namespace, name: clause.field)?.id ?? "\(namespace)/\(clause.field)",
        descending: clause.descending
      )
    }
    return entityIDs.sorted { lhs, rhs in
      for clause in clauses {
        let comparison = value(entityID: lhs, attributeID: clause.attributeID)
          .compare(to: value(entityID: rhs, attributeID: clause.attributeID))
        if comparison == .orderedSame {
          continue
        }
        if clause.descending {
          return comparison == .orderedDescending
        }
        return comparison == .orderedAscending
      }
      return lhs < rhs
    }
  }

  func value(entityID: String, attributeID: String) -> InstantValue {
    triplesByEntity[entityID]?.first { $0.attributeID == attributeID }?.value ?? .null
  }

  /// The first attribute the schema declares with `namespace` and `name`, as the general pass's map kept the first.
  func attribute(namespace: String, name: String) -> InstantAttribute? {
    attributes.first { $0.namespace == namespace && $0.name == name }
  }
}

private func parseJSONObject(_ queryKey: String) -> [String: Any]? {
  guard let data = queryKey.data(using: .utf8),
    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
    !object.isEmpty
  else {
    return nil
  }
  return object
}

private func parseOrder(_ value: Any?) -> [(field: String, descending: Bool)] {
  guard let object = value as? [String: Any] else { return [] }
  return object.keys.sorted().compactMap { field in
    let raw = object[field]
    let descending: Bool
    if let text = raw as? String {
      descending = text.lowercased() == "desc" || text.lowercased() == "descending"
    } else {
      descending = false
    }
    return (field: field, descending: descending)
  }
}

private func jsonInt(_ value: Any?) -> Int? {
  if let number = value as? Int {
    return number
  }
  if let number = value as? NSNumber {
    return number.intValue
  }
  if let number = value as? Double {
    return Int(number)
  }
  return nil
}
