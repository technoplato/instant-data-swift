import Foundation

/// Apply InstaQL nested include limits to persisted live-query triples.
///
/// TypeScript `Reactor.js` stores `querySub.result.store` from
/// `createStore(attrs, result.triples)` after instaql has already applied
/// per-parent nested `limit`. SQLite Data SQL-limits the visible page.
///
/// Swift still has one global InstantStore. Session observe can persist every
/// matching child (Mac recordings list: 481 segments, one parent 328) even
/// when the query JSON says `segments.$limit: 2`. Bootstrap then loads that
/// union (trial 3). This filter runs at save and load in
/// `SQLitePersistenceStore` so InstantStore residency matches the query page.
/// InstantRuntime is unedited. Live `transact` is unchanged.
enum InstantLiveQueryNestedLimit {
  static func limitedTriples(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> [InstantTriple] {
    let retained = retainedEntityIDs(
      queryKey: queryKey,
      triples: triples,
      attributes: attributes
    )
    let attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    return triples.filter { triple in
      guard retained.contains(triple.entityID) else { return false }
      guard let attribute = attributesByID[triple.attributeID],
        attribute.valueType == .ref,
        attribute.cardinality == .many,
        let childID = triple.value.refValue
      else {
        return true
      }
      return retained.contains(childID)
    }
  }

  static func retainedEntityIDs(
    queryKey: String,
    triples: [InstantTriple],
    attributes: [InstantAttribute]
  ) -> Set<String> {
    let allIDs = Set(triples.map(\.entityID))
    guard let object = parseJSONObject(queryKey), !attributes.isEmpty else {
      return allIDs
    }
    let context = Context(triples: triples, attributes: attributes)
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

  static func namespace(in attributeID: String) -> String? {
    guard let slash = attributeID.firstIndex(of: "/") else { return nil }
    let namespace = String(attributeID[..<slash])
    return namespace.isEmpty ? nil : namespace
  }
}

private struct Context {
  var triplesByEntity: [String: [InstantTriple]]
  var attributesByID: [String: InstantAttribute]
  var entityIDsByNamespace: [String: Set<String>]

  init(triples: [InstantTriple], attributes: [InstantAttribute]) {
    attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    var triplesByEntity: [String: [InstantTriple]] = [:]
    var entityIDsByNamespace: [String: Set<String>] = [:]
    for triple in triples {
      triplesByEntity[triple.entityID, default: []].append(triple)
      let namespace = attributesByID[triple.attributeID]?.namespace
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
      var childRetained: Set<String> = []
      for parentID in retained {
        let kids = children(
          of: parentID,
          parentNamespace: namespace,
          includeName: includeName,
          reverseLink: resolved.reverseLink,
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
    let reverseLink = attributesByID.values.first { $0.reverseIdentity == identity }
    let parentLink = attributesByID.values.first {
      $0.namespace == parentNamespace && $0.name == includeName && $0.valueType == .ref
    }
    let childNamespace = reverseLink?.namespace ?? parentLink?.linkNamespace
    guard let childNamespace else { return nil }
    return (childNamespace, reverseLink, parentLink)
  }

  func children(
    of parentID: String,
    parentNamespace: String,
    includeName: String,
    reverseLink: InstantAttribute?,
    parentLink: InstantAttribute?
  ) -> Set<String> {
    var ids: Set<String> = []
    if let reverseLink {
      let stringAttributeID = "\(reverseLink.namespace)/\(reverseLink.name)ID"
      for (entityID, triples) in triplesByEntity {
        for triple in triples {
          let matchesLink = triple.attributeID == reverseLink.id
            || triple.attributeID == stringAttributeID
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
    return entityIDs.sorted { lhs, rhs in
      for clause in order {
        let attributeID = "\(namespace)/\(clause.field)"
        let comparison = value(entityID: lhs, attributeID: attributeID)
          .compare(to: value(entityID: rhs, attributeID: attributeID))
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
