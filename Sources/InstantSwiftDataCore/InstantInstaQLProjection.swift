import Foundation

public struct InstantInstaQLObject: Hashable, Codable, Sendable, Identifiable {
  public var id: String
  public var namespace: String
  public var fields: [String: InstantInstaQLValue]

  public init(
    id: String,
    namespace: String,
    fields: [String: InstantInstaQLValue]
  ) {
    self.id = id
    self.namespace = namespace
    self.fields = fields
  }

  public subscript(field: String) -> InstantInstaQLValue? {
    fields[field]
  }
}

public indirect enum InstantInstaQLValue: Hashable, Codable, Sendable {
  case null
  case scalar(InstantValue)
  case scalars([InstantValue])
  case object(InstantInstaQLObject)
  case objects([InstantInstaQLObject])

  public var object: InstantInstaQLObject? {
    guard case let .object(value) = self else { return nil }
    return value
  }

  public var objects: [InstantInstaQLObject]? {
    guard case let .objects(value) = self else { return nil }
    return value
  }

  public var scalar: InstantValue? {
    guard case let .scalar(value) = self else { return nil }
    return value
  }

  public var scalars: [InstantValue]? {
    guard case let .scalars(value) = self else { return nil }
    return value
  }
}

public enum InstantInstaQLProjection {
  public static func project(
    _ snapshots: [InstantEntitySnapshot],
    plan: InstantQueryPlan,
    attributes: [InstantAttribute],
    cardinalityInference: Bool
  ) -> [InstantInstaQLObject] {
    project(
      snapshots,
      plan: plan,
      attributes: AttributeStore(attributes: attributes),
      cardinalityInference: cardinalityInference
    )
  }

  static func project(
    _ snapshots: [InstantEntitySnapshot],
    plan: InstantQueryPlan,
    attributes: AttributeStore,
    cardinalityInference: Bool
  ) -> [InstantInstaQLObject] {
    snapshots.map {
      object(
        from: $0,
        plan: plan,
        attributes: attributes,
        cardinalityInference: cardinalityInference
      )
    }
  }

  private static func object(
    from snapshot: InstantEntitySnapshot,
    plan: InstantQueryPlan,
    attributes: AttributeStore,
    cardinalityInference: Bool
  ) -> InstantInstaQLObject {
    var fields: [String: InstantInstaQLValue] = [
      "id": .scalar(.string(snapshot.id))
    ]

    for key in snapshot.values.keys.sorted() {
      guard let value = snapshot.values[key] else { continue }
      guard !isRelationshipValue(key, namespace: snapshot.namespace, attributes: attributes)
      else { continue }

      switch value {
      case let .one(value):
        fields[key] = .scalar(value)
      case let .many(values):
        fields[key] = .scalars(values)
      }
    }

    for include in plan.includes ?? [] {
      let linked = snapshot.links?[include.name] ?? []
      let childPlan = include.query?.queryPlan
      let childObjects = linked.map { child in
        object(
          from: InstantEntitySnapshot(
            id: child.id,
            namespace: child.namespace,
            values: child.values,
            links: child.links
          ),
          plan: childPlan ?? InstantQueryPlan(
            id: "\(child.namespace).included.\(include.name)",
            namespace: child.namespace
          ),
          attributes: attributes,
          cardinalityInference: cardinalityInference
        )
      }

      if cardinalityInference && isSingular(include, namespace: plan.namespace, attributes: attributes) {
        fields[include.name] = childObjects.first.map(InstantInstaQLValue.object) ?? .null
      } else {
        fields[include.name] = .objects(childObjects)
      }
    }

    return InstantInstaQLObject(id: snapshot.id, namespace: snapshot.namespace, fields: fields)
  }

  private static func isRelationshipValue(
    _ name: String,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    guard let attribute = attributes.attribute(namespace: namespace, name: name)
    else { return false }
    return attribute.valueType == .ref && attribute.linkNamespace != nil
  }

  private static func isSingular(
    _ include: InstantQueryInclude,
    namespace: String,
    attributes: AttributeStore
  ) -> Bool {
    switch include.direction {
    case .forward:
      return attributes.attribute(namespace: namespace, name: include.name)?.cardinality == .one

    case .reverse:
      return reverseAttribute(namespace: namespace, name: include.name, attributes: attributes)?
        .isUnique
        == true
    }
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
}
