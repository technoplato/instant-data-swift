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
        return .addTriple(
          entity: try resolver.resolve(entity),
          attributeID: try resolver.resolve(attributeID),
          value: try resolver.resolve(value),
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
        return .retractTriple(
          entity: try resolver.resolve(entity),
          attributeID: try resolver.resolve(attributeID),
          value: try resolver.resolve(value)
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
    private var ids: Set<String> = []
    private var idsByIdentity: [String: String] = [:]

    init(attrs: [InstantLiveJSONValue]) {
      for attr in attrs {
        guard let object = attr.objectValue,
          let id = object["id"]?.stringValue
        else {
          continue
        }
        ids.insert(id)
        for key in ["forward-identity", "reverse-identity"] {
          guard let identity = object[key]?.arrayValue,
            identity.count >= 3,
            let namespace = identity[1].stringValue,
            let name = identity[2].stringValue
          else {
            continue
          }
          idsByIdentity["\(namespace)/\(name)"] = id
        }
      }
    }

    func resolve(_ attributeID: String) throws -> String {
      if ids.contains(attributeID) {
        return attributeID
      }
      if let id = idsByIdentity[attributeID] {
        return id
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
  }
}
