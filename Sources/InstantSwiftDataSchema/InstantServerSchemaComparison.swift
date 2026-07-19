import Foundation
import InstantSwiftDataCore

public enum InstantServerSchemaWarningCode: String, Codable, Hashable, Sendable {
  case systemEntity = "system-entity"
  case systemAttribute = "system-attribute"
  case systemLink = "system-link"
  case canonicalLinkName = "canonical-link-name"
  case serverJSONAsAny = "server-json-as-any"
}

public struct InstantServerSchemaWarning: Codable, Equatable, Hashable, Sendable {
  public var code: InstantServerSchemaWarningCode
  public var path: String

  public init(code: InstantServerSchemaWarningCode, path: String) {
    self.code = code
    self.path = path
  }
}

public struct InstantServerSchemaComparison: Equatable, Sendable {
  public var normalizedDocument: ParsedInstantSchemaDocument
  public var warnings: [InstantServerSchemaWarning]

  public init(
    normalizedDocument: ParsedInstantSchemaDocument,
    warnings: [InstantServerSchemaWarning]
  ) {
    self.normalizedDocument = normalizedDocument
    self.warnings = warnings
  }
}

public enum InstantServerSchemaComparisonError: Error, Equatable, Sendable,
  CustomStringConvertible
{
  case missingEntity(String)
  case unexpectedEntity(String)
  case missingAttribute(String)
  case unexpectedAttribute(String)
  case mismatchedAttribute(String)
  case missingLink(String)
  case unexpectedLink(String)
  case mismatchedLink(String)
  case mismatchedRooms

  public var description: String {
    switch self {
    case .missingEntity(let namespace):
      "Server schema is missing expected entity '\(namespace)'."
    case .unexpectedEntity(let namespace):
      "Server schema contains unexpected application entity '\(namespace)'."
    case .missingAttribute(let path):
      "Server schema is missing expected attribute '\(path)'."
    case .unexpectedAttribute(let path):
      "Server schema contains unexpected application attribute '\(path)'."
    case .mismatchedAttribute(let path):
      "Server attribute '\(path)' does not match the Swift contract."
    case .missingLink(let name):
      "Server schema is missing expected link '\(name)'."
    case .unexpectedLink(let name):
      "Server schema contains unexpected application link '\(name)'."
    case .mismatchedLink(let name):
      "Server link '\(name)' does not match the Swift contract."
    case .mismatchedRooms:
      "Server rooms do not match the Swift contract."
    }
  }
}

extension ParsedInstantSchemaDocument {
  public func comparingServerNormalized(
    to expected: ParsedInstantSchemaDocument
  ) throws -> InstantServerSchemaComparison {
    var warnings: [InstantServerSchemaWarning] = []
    let actualEntities = Dictionary(uniqueKeysWithValues: entities.map { ($0.namespace, $0) })
    let expectedEntities = Dictionary(
      uniqueKeysWithValues: expected.entities.map { ($0.namespace, $0) }
    )

    for actual in entities where expectedEntities[actual.namespace] == nil {
      guard actual.namespace.hasPrefix("$") else {
        throw InstantServerSchemaComparisonError.unexpectedEntity(actual.namespace)
      }
      warnings.append(.init(code: .systemEntity, path: actual.namespace))
    }

    for expectedEntity in expected.entities {
      guard let actualEntity = actualEntities[expectedEntity.namespace] else {
        throw InstantServerSchemaComparisonError.missingEntity(expectedEntity.namespace)
      }

      let actualAttributes = Dictionary(
        uniqueKeysWithValues: actualEntity.attributes.map { ($0.name, $0) }
      )
      let expectedAttributes = Dictionary(
        uniqueKeysWithValues: expectedEntity.attributes.map { ($0.name, $0) }
      )

      for expectedAttribute in expectedEntity.attributes {
        let path = "\(expectedEntity.namespace).\(expectedAttribute.name)"
        guard let actualAttribute = actualAttributes[expectedAttribute.name] else {
          throw InstantServerSchemaComparisonError.missingAttribute(path)
        }
        if actualAttribute != expectedAttribute {
          var normalizedActual = actualAttribute
          normalizedActual.valueType = expectedAttribute.valueType
          guard
            actualAttribute.valueType == .any,
            expectedAttribute.valueType == .json,
            normalizedActual == expectedAttribute
          else {
            throw InstantServerSchemaComparisonError.mismatchedAttribute(path)
          }
          warnings.append(.init(code: .serverJSONAsAny, path: path))
        }
      }

      for actualAttribute in actualEntity.attributes
      where expectedAttributes[actualAttribute.name] == nil
      {
        let path = "\(actualEntity.namespace).\(actualAttribute.name)"
        guard actualEntity.namespace.hasPrefix("$") else {
          throw InstantServerSchemaComparisonError.unexpectedAttribute(path)
        }
        warnings.append(.init(code: .systemAttribute, path: path))
      }
    }

    var matchedActualLinkNames: Set<String> = []
    for expectedLink in expected.links {
      if let sameNameLink = links.first(where: { $0.name == expectedLink.name }) {
        guard sameNameLink.hasSameSemantics(as: expectedLink) else {
          throw InstantServerSchemaComparisonError.mismatchedLink(expectedLink.name)
        }
        matchedActualLinkNames.insert(sameNameLink.name)
        continue
      }

      guard let actualLink = links.first(where: { $0.hasSameSemantics(as: expectedLink) }) else {
        throw InstantServerSchemaComparisonError.missingLink(expectedLink.name)
      }
      matchedActualLinkNames.insert(actualLink.name)
      warnings.append(
        .init(
          code: .canonicalLinkName,
          path: "\(expectedLink.name)->\(actualLink.name)"
        )
      )
    }

    for actualLink in links where !matchedActualLinkNames.contains(actualLink.name) {
      guard
        actualLink.forward.namespace.hasPrefix("$"),
        actualLink.reverse.namespace.hasPrefix("$")
      else {
        throw InstantServerSchemaComparisonError.unexpectedLink(actualLink.name)
      }
      warnings.append(.init(code: .systemLink, path: actualLink.name))
    }

    // Instant room declarations are client-side type metadata. The canonical
    // CLI accepts them in a local schema but does not persist them in the
    // server schema, so a fresh pull reports `rooms: {}`. If a server artifact
    // does contain rooms, continue requiring their exact contract shape.
    guard rooms.isEmpty || rooms == expected.rooms else {
      throw InstantServerSchemaComparisonError.mismatchedRooms
    }

    return InstantServerSchemaComparison(
      normalizedDocument: expected,
      warnings: warnings
    )
  }
}

private extension InstantLinkSchema {
  func hasSameSemantics(as other: InstantLinkSchema) -> Bool {
    forward == other.forward
      && reverse == other.reverse
      && isRequired == other.isRequired
  }
}
