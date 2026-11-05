import Foundation

// History:
// - 2026-10-24: a query with no nested include whose rows fit its limits passes through without the general pass's
//   maps, and every attribute lookup reads the triples' own attributes or searches the schema once per include, never a
//   map of the whole schema: run twice per refresh (the translator, then the persisted result), the pass built maps of
//   every attribute (2,283 on the phone) and every row, about 6.5 MB of a 64-line refresh with nothing to drop (#1147).
// - 2026-11-04: the translator and the store pass a schema indexed once per attribute revision: the per-call lookup still
//   walked every attribute, hashing its id and copying it, 258 of the pass's 374 ms in a 90 s trace of the phone
//   transcribing speech (build 251, 1.1% of the app's CPU). The query key is parsed once a call, not twice (#1109).

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
  ///
  /// For one call: the triples' own attributes are found in one pass over `attributes`. Code that bounds every refresh
  /// passes a ``Schema`` indexed once instead (#1109).
  static func limitedTriples(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> [InstantTriple] {
    limitedTriples(queryKey: queryKey, triples: triples, source: AttributeSource(attributes, for: triples))
  }

  /// ``limitedTriples(queryKey:triples:attributes:)`` with the attributes of `schema`, looked up in its indexes.
  static func limitedTriples(queryKey: String, triples: [InstantTriple], schema: Schema) -> [InstantTriple] {
    limitedTriples(queryKey: queryKey, triples: triples, source: AttributeSource(schema))
  }

  static func retainedEntityIDs(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> Set<String> {
    retainedEntityIDs(queryKey: queryKey, triples: triples, source: AttributeSource(attributes, for: triples))
  }

  /// ``retainedEntityIDs(queryKey:triples:attributes:)`` with the attributes of `schema`, looked up in its indexes.
  static func retainedEntityIDs(queryKey: String, triples: [InstantTriple], schema: Schema) -> Set<String> {
    retainedEntityIDs(queryKey: queryKey, triples: triples, source: AttributeSource(schema))
  }

  /// The general pass alone, without the shortcut for queries with no nested include: what the shortcut must equal.
  static func generalLimitedTriplesForTesting(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> [InstantTriple] {
    let source = AttributeSource(attributes, for: triples)
    let retained = generalRetainedEntityIDsForTesting(queryKey: queryKey, triples: triples, attributes: attributes)
    return kept(triples, retained: retained, lookup: source)
  }

  /// The general pass's retained rows, without the shortcut.
  static func generalRetainedEntityIDsForTesting(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> Set<String> {
    let source = AttributeSource(attributes, for: triples)
    guard let object = parseJSONObject(queryKey), !source.isEmpty else { return entityIDs(of: triples) }
    return generalRetainedEntityIDs(object: object, triples: triples, source: source)
  }

  static func namespace(in attributeID: String) -> String? {
    guard let slash = attributeID.firstIndex(of: "/") else { return nil }
    let namespace = String(attributeID[..<slash])
    return namespace.isEmpty ? nil : namespace
  }

  private static func limitedTriples(
    queryKey: String,
    triples: [InstantTriple],
    source: AttributeSource
  ) -> [InstantTriple] {
    kept(triples, retained: retainedEntityIDs(queryKey: queryKey, triples: triples, source: source), lookup: source)
  }

  /// Every row when the key is not a query or there is no schema; otherwise the shortcut's rows, or the general pass's.
  private static func retainedEntityIDs(
    queryKey: String,
    triples: [InstantTriple],
    source: AttributeSource
  ) -> Set<String> {
    guard let object = parseJSONObject(queryKey), !source.isEmpty else { return entityIDs(of: triples) }
    return retainedWithoutNestedIncludes(object: object, triples: triples, source: source)
      ?? generalRetainedEntityIDs(object: object, triples: triples, source: source)
  }

  /// The retained rows of a query whose nodes include nothing, when no node holds more rows than its limit: every row
  /// of the query's namespaces, as the general pass retains them, without its per-row maps or its sort. `nil` when the
  /// query includes something or a node's rows outgrow its limit (the server limits top-level rows, so rarely).
  private static func retainedWithoutNestedIncludes(
    object: [String: Any],
    triples: [InstantTriple],
    source: AttributeSource
  ) -> Set<String>? {
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
        let namespace = source[triple.attributeID]?.namespace ?? namespace(in: triple.attributeID),
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
    object: [String: Any],
    triples: [InstantTriple],
    source: AttributeSource
  ) -> Set<String> {
    let context = Context(triples: triples, source: source)
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
    return retained.isEmpty ? entityIDs(of: triples) : retained
  }

  /// The triples of retained rows, without many-cardinality links to rows not retained.
  private static func kept(_ triples: [InstantTriple], retained: Set<String>, lookup: AttributeSource) -> [InstantTriple] {
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

extension InstantLiveQueryNestedLimit {
  /// A schema indexed for the pass, built once and kept while the schema is unchanged (#1109): the translator's attribute
  /// context holds one, and the store one for its stored attributes.
  ///
  /// Each index holds the first attribute of its key, as the searches it replaces found the first.
  struct Schema: Sendable {
    let attributes: [InstantAttribute]
    private let indexByID: [String: Int]
    private let indexByReverseIdentity: [String: Int]
    private let indexByName: [Name: Int]
    private let refIndexByName: [Name: Int]

    private struct Name: Hashable {
      var namespace: String
      var name: String
    }

    init(_ attributes: [InstantAttribute]) {
      self.attributes = attributes
      var indexByID: [String: Int] = [:]
      var indexByReverseIdentity: [String: Int] = [:]
      var indexByName: [Name: Int] = [:]
      var refIndexByName: [Name: Int] = [:]
      indexByID.reserveCapacity(attributes.count)
      indexByName.reserveCapacity(attributes.count)
      // Last to first, so each key ends at its first attribute.
      for index in attributes.indices.reversed() {
        let attribute = attributes[index]
        indexByID[attribute.id] = index
        let name = Name(namespace: attribute.namespace, name: attribute.name)
        indexByName[name] = index
        if attribute.valueType == .ref {
          refIndexByName[name] = index
        }
        if let reverseIdentity = attribute.reverseIdentity {
          indexByReverseIdentity[reverseIdentity] = index
        }
      }
      self.indexByID = indexByID
      self.indexByReverseIdentity = indexByReverseIdentity
      self.indexByName = indexByName
      self.refIndexByName = refIndexByName
    }

    func attribute(id: String) -> InstantAttribute? {
      indexByID[id].map { attributes[$0] }
    }

    func attribute(reverseIdentity: String) -> InstantAttribute? {
      indexByReverseIdentity[reverseIdentity].map { attributes[$0] }
    }

    func attribute(namespace: String, name: String) -> InstantAttribute? {
      indexByName[Name(namespace: namespace, name: name)].map { attributes[$0] }
    }

    func refAttribute(namespace: String, name: String) -> InstantAttribute? {
      refIndexByName[Name(namespace: namespace, name: name)].map { attributes[$0] }
    }
  }
}

/// Where one pass finds attributes: a ``InstantLiveQueryNestedLimit/Schema`` indexed once (#1109), or for a single call
/// the triples' own attributes found in one pass over the schema and the schema searched for each include, so a page of
/// sixteen attributes costs sixteen entries whatever the schema's size (#1147).
private struct AttributeSource {
  private enum Storage {
    case indexed(InstantLiveQueryNestedLimit.Schema)
    case searched(attributes: [InstantAttribute], byID: [String: InstantAttribute])
  }

  private let storage: Storage

  init(_ schema: InstantLiveQueryNestedLimit.Schema) {
    storage = .indexed(schema)
  }

  init(_ attributes: [InstantAttribute], for triples: [InstantTriple]) {
    var wanted: Set<String> = []
    for triple in triples { wanted.insert(triple.attributeID) }
    var byID: [String: InstantAttribute] = [:]
    byID.reserveCapacity(wanted.count)
    for attribute in attributes where wanted.contains(attribute.id) && byID[attribute.id] == nil {
      byID[attribute.id] = attribute
    }
    storage = .searched(attributes: attributes, byID: byID)
  }

  var isEmpty: Bool {
    switch storage {
    case let .indexed(schema): schema.attributes.isEmpty
    case let .searched(attributes, _): attributes.isEmpty
    }
  }

  /// The first attribute with `id`, for an id of the triples the source was made for.
  subscript(id: String) -> InstantAttribute? {
    switch storage {
    case let .indexed(schema): schema.attribute(id: id)
    case let .searched(_, byID): byID[id]
    }
  }

  func attribute(reverseIdentity: String) -> InstantAttribute? {
    switch storage {
    case let .indexed(schema): schema.attribute(reverseIdentity: reverseIdentity)
    case let .searched(attributes, _): attributes.first { $0.reverseIdentity == reverseIdentity }
    }
  }

  func attribute(namespace: String, name: String) -> InstantAttribute? {
    switch storage {
    case let .indexed(schema): schema.attribute(namespace: namespace, name: name)
    case let .searched(attributes, _): attributes.first { $0.namespace == namespace && $0.name == name }
    }
  }

  func refAttribute(namespace: String, name: String) -> InstantAttribute? {
    switch storage {
    case let .indexed(schema): schema.refAttribute(namespace: namespace, name: name)
    case let .searched(attributes, _):
      attributes.first { $0.namespace == namespace && $0.name == name && $0.valueType == .ref }
    }
  }
}

private struct Context {
  var triplesByEntity: [String: [InstantTriple]]
  var entityIDsByNamespace: [String: Set<String>]
  /// The schema, read for the triples' attributes and for a query's includes and order fields (#1147, #1109).
  private let source: AttributeSource

  init(triples: [InstantTriple], source: AttributeSource) {
    self.source = source
    var triplesByEntity: [String: [InstantTriple]] = [:]
    var entityIDsByNamespace: [String: Set<String>] = [:]
    for triple in triples {
      triplesByEntity[triple.entityID, default: []].append(triple)
      let namespace = source[triple.attributeID]?.namespace
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
    let reverseLink = source.attribute(reverseIdentity: "\(parentNamespace)/\(includeName)")
    let parentLink = source.refAttribute(namespace: parentNamespace, name: includeName)
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
    source.attribute(namespace: namespace, name: name)
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
