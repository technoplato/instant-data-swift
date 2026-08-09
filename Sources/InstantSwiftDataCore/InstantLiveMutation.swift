import Foundation

enum InstantLiveMutationEncoder {
  static func resolveAttributeIDs(
    in steps: [InstantTransportStep],
    attrs: [InstantLiveJSONValue]
  ) throws -> [InstantTransportStep] {
    guard !attrs.isEmpty else { return steps }
    let resolver = AttributeIDResolver(attrs: attrs)
    return try steps.map { step in
      switch step {
      case let .addTriple(entity, attributeID, value, options):
        let attribute = try resolver.resolveAttribute(attributeID)
        let resolvedEntity = try resolver.resolve(entity)
        let resolvedValue = try resolver.resolve(value)
        if attribute.reversesEndpoints {
          return .addTriple(
            entity: try resolver.entityRef(from: resolvedValue, attributeID: attributeID),
            attributeID: attribute.id,
            value: resolver.value(from: resolvedEntity),
            options: nil
          )
        }
        return .addTriple(
          entity: resolvedEntity,
          attributeID: attribute.id,
          value: resolvedValue,
          options: options
        )
      case let .deepMergeTriple(entity, attributeID, value, options):
        return .deepMergeTriple(
          entity: try resolver.resolve(entity),
          attributeID: try resolver.resolve(attributeID),
          value: try resolver.resolve(value),
          options: options
        )
      case let .retractTriple(entity, attributeID, value):
        let attribute = try resolver.resolveAttribute(attributeID)
        let resolvedEntity = try resolver.resolve(entity)
        let resolvedValue = try resolver.resolve(value)
        if attribute.reversesEndpoints {
          return .retractTriple(
            entity: try resolver.entityRef(from: resolvedValue, attributeID: attributeID),
            attributeID: attribute.id,
            value: resolver.value(from: resolvedEntity)
          )
        }
        return .retractTriple(
          entity: resolvedEntity,
          attributeID: attribute.id,
          value: resolvedValue
        )
      case let .deleteEntity(entity, namespace):
        return .deleteEntity(entity: try resolver.resolve(entity), namespace: namespace)
      case let .ruleParams(entity, namespace, params):
        return .ruleParams(
          entity: try resolver.resolve(entity),
          namespace: namespace,
          params: try resolver.resolve(params)
        )
      }
    }
  }

  private struct AttributeIDResolver {
    struct ResolvedAttributeID {
      var id: String
      var reversesEndpoints: Bool
    }

    private var ids: Set<String> = []
    private var idsByForwardIdentity: [String: String] = [:]
    private var idsByReverseIdentity: [String: String] = [:]

    init(attrs: [InstantLiveJSONValue]) {
      for attr in attrs {
        guard let object = attr.objectValue,
          let id = object["id"]?.stringValue
        else {
          continue
        }
        ids.insert(id)
        if let identity = object["forward-identity"]?.arrayValue,
          identity.count >= 3,
          let namespace = identity[1].stringValue,
          let name = identity[2].stringValue
        {
          idsByForwardIdentity["\(namespace)/\(name)"] = id
        }
        if let identity = object["reverse-identity"]?.arrayValue,
          identity.count >= 3,
          let namespace = identity[1].stringValue,
          let name = identity[2].stringValue
        {
          idsByReverseIdentity["\(namespace)/\(name)"] = id
        }
      }
    }

    func resolve(_ attributeID: String) throws -> String {
      try resolveAttribute(attributeID).id
    }

    func resolveAttribute(_ attributeID: String) throws -> ResolvedAttributeID {
      if ids.contains(attributeID) {
        return ResolvedAttributeID(id: attributeID, reversesEndpoints: false)
      }
      if let id = idsByForwardIdentity[attributeID] {
        return ResolvedAttributeID(id: id, reversesEndpoints: false)
      }
      if let id = idsByReverseIdentity[attributeID] {
        return ResolvedAttributeID(id: id, reversesEndpoints: true)
      }
      throw InstantError(
        code: .validationFailed,
        operation: "resolve Instant live transaction attribute ids",
        path: attributeID,
        message: "Could not resolve '\(attributeID)' from the attrs returned by init-ok.",
        recovery: "Deploy a schema containing this attribute before sending the transaction."
      )
    }

    func resolve(_ entity: InstantTransportEntityRef) throws -> InstantTransportEntityRef {
      switch entity {
      case .id:
        return entity
      case let .lookup(lookup):
        return .lookup(
          InstantLookupRef(
            attributeID: try resolve(lookup.attributeID),
            value: lookup.value
          )
        )
      }
    }

    func resolve(_ value: InstantTransportValue) throws -> InstantTransportValue {
      switch value {
      case .null, .bool, .number, .string:
        return value
      case let .array(values):
        return .array(try values.map(resolve))
      case let .object(values):
        return .object(try values.mapValues(resolve))
      case let .lookupRef(attributeID, value):
        return .lookupRef(
          attributeID: try resolve(attributeID),
          value: try resolve(value)
        )
      }
    }

    func entityRef(
      from value: InstantTransportValue,
      attributeID: String
    ) throws -> InstantTransportEntityRef {
      switch value {
      case let .string(id):
        return .id(id)
      case let .lookupRef(lookupAttributeID, transportLookupValue):
        return .lookup(
          InstantLookupRef(
            attributeID: lookupAttributeID,
            value: try lookupValue(from: transportLookupValue, attributeID: attributeID)
          )
        )
      case .null, .bool, .number, .array, .object:
        throw InstantError(
          code: .validationFailed,
          operation: "orient Instant live reverse relation",
          path: attributeID,
          message: "Reverse relation '\(attributeID)' does not point to an entity id or lookup ref.",
          recovery: "Link the reverse relation to an Instant entity id or unique lookup ref."
        )
      }
    }

    func value(from entity: InstantTransportEntityRef) -> InstantTransportValue {
      switch entity {
      case let .id(id):
        return .string(id)
      case let .lookup(lookup):
        return .lookupRef(
          attributeID: lookup.attributeID,
          value: InstantTransportValue(lookup.value)
        )
      }
    }

    private func lookupValue(
      from value: InstantTransportValue,
      attributeID: String
    ) throws -> InstantLookupValue {
      switch value {
      case .null:
        return .null
      case let .bool(value):
        return .bool(value)
      case let .number(value):
        return .number(value)
      case let .string(value):
        return .string(value)
      case let .array(values):
        return .json(.array(try values.map { try jsonValue(from: $0, attributeID: attributeID) }))
      case let .object(values):
        return .json(.object(try values.mapValues { try jsonValue(from: $0, attributeID: attributeID) }))
      case .lookupRef:
        throw InstantError(
          code: .validationFailed,
          operation: "orient Instant live reverse relation",
          path: attributeID,
          message: "Reverse relation '\(attributeID)' contains a nested lookup ref.",
          recovery: "Use a scalar or JSON value for the relation's unique lookup attribute."
        )
      }
    }

    private func jsonValue(
      from value: InstantTransportValue,
      attributeID: String
    ) throws -> JSONValue {
      switch value {
      case .null:
        return .null
      case let .bool(value):
        return .bool(value)
      case let .number(value):
        return .number(value)
      case let .string(value):
        return .string(value)
      case let .array(values):
        return .array(try values.map { try jsonValue(from: $0, attributeID: attributeID) })
      case let .object(values):
        return .object(try values.mapValues { try jsonValue(from: $0, attributeID: attributeID) })
      case .lookupRef:
        throw InstantError(
          code: .validationFailed,
          operation: "orient Instant live reverse relation",
          path: attributeID,
          message: "Reverse relation '\(attributeID)' contains a nested lookup ref.",
          recovery: "Use a scalar or JSON value for the relation's unique lookup attribute."
        )
      }
    }
  }
}
