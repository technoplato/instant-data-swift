import Foundation
import InstantSwiftDataCore

public struct InstantEntitySchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { namespace }
  public var typeName: String
  public var namespace: String
  public var attributes: [InstantAttribute]

  public init(
    typeName: String,
    namespace: String? = nil,
    attributes: [InstantAttribute]
  ) {
    self.typeName = typeName
    self.namespace = namespace ?? InstantNamespace.defaultName(for: typeName)
    self.attributes = attributes
  }
}

public struct InstantSchemaDocument: Hashable, Codable, Sendable {
  public var entities: [InstantEntitySchema]
  public var links: [InstantLinkSchema]
  public var rooms: [InstantRoomSchema]

  public init(
    entities: [InstantEntitySchema],
    links: [InstantLinkSchema] = [],
    rooms: [InstantRoomSchema] = []
  ) {
    self.entities = entities
    self.links = links
    self.rooms = rooms
  }

  public var attributes: [InstantAttribute] {
    entities.flatMap(\.attributes) + links.flatMap(\.attributes)
  }
}

public struct InstantRoomSchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var presence: InstantRoomPayloadSchema
  public var topics: [InstantRoomTopicSchema]

  public init(
    name: String,
    presence: InstantRoomPayloadSchema,
    topics: [InstantRoomTopicSchema] = []
  ) {
    self.name = name
    self.presence = presence
    self.topics = topics
  }
}

public struct InstantRoomTopicSchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var payload: InstantRoomPayloadSchema

  public init(
    name: String,
    payload: InstantRoomPayloadSchema
  ) {
    self.name = name
    self.payload = payload
  }
}

public struct InstantRoomPayloadSchema: Hashable, Codable, Sendable {
  public var attributes: [InstantAttribute]

  public init(attributes: [InstantAttribute] = []) {
    self.attributes = attributes
  }
}

public struct InstantLinkSchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var forward: InstantLinkEndpoint
  public var reverse: InstantLinkEndpoint
  public var isRequired: Bool?

  public init(
    name: String,
    forward: InstantLinkEndpoint,
    reverse: InstantLinkEndpoint,
    isRequired: Bool? = nil
  ) {
    self.name = name
    self.forward = forward
    self.reverse = reverse
    self.isRequired = isRequired
  }

  public var attributes: [InstantAttribute] {
    [
      InstantAttribute(
        id: "\(forward.namespace)/\(forward.label)",
        namespace: forward.namespace,
        name: forward.label,
        valueType: .ref,
        isRequired: isRequired == true,
        cardinality: forward.cardinality,
        isIndexed: true,
        isUnique: reverse.cardinality == .one,
        forwardIdentity: "\(forward.namespace)/\(forward.label)",
        reverseIdentity: "\(reverse.namespace)/\(reverse.label)",
        linkNamespace: reverse.namespace,
        onDelete: forward.onDelete,
        onDeleteReverse: reverse.onDelete
      )
    ]
  }
}

public struct InstantLinkEndpoint: Hashable, Codable, Sendable {
  public var namespace: String
  public var cardinality: InstantCardinality
  public var label: String
  public var onDelete: InstantDeleteRule

  public init(
    namespace: String,
    cardinality: InstantCardinality,
    label: String,
    onDelete: InstantDeleteRule = .none
  ) {
    self.namespace = namespace
    self.cardinality = cardinality
    self.label = label
    self.onDelete = onDelete
  }
}

public enum InstantSchemaValidationError: Error, Equatable, Sendable, CustomStringConvertible {
  case invalidLinkCascadeEndpoint(
    link: String,
    endpoint: String,
    cardinality: InstantCardinality
  )
  case unsupportedRefAttribute(namespace: String, name: String)

  public var description: String {
    switch self {
    case .invalidLinkCascadeEndpoint(let link, let endpoint, let cardinality):
      "Link '\(link)' \(endpoint) endpoint has invalid cascade delete for cardinality '\(cardinality.rawValue)'. Cascade delete is only supported on has: \"one\" links."
    case .unsupportedRefAttribute(let namespace, let name):
      "Attribute '\(namespace)/\(name)' is a ref attribute. Encode relationships with the schema links section instead."
    }
  }
}

public struct InstantPermissionsDocument: Hashable, Codable, Sendable {
  public var attrs: InstantAttributePermissions?
  public var defaults: InstantDefaultPermissions?
  public var rateLimits: [InstantRateLimit]
  public var namespaces: [InstantNamespacePermissions]

  public init(
    attrs: InstantAttributePermissions? = nil,
    defaults: InstantDefaultPermissions? = nil,
    rateLimits: [InstantRateLimit] = [],
    namespaces: [InstantNamespacePermissions]
  ) {
    self.attrs = attrs
    self.defaults = defaults
    self.rateLimits = rateLimits
    self.namespaces = namespaces
  }
}

public struct InstantNamespacePermissions: Hashable, Codable, Sendable, Identifiable {
  public var id: String { namespace }
  public var namespace: String
  public var allow: [InstantPermissionAction: String]
  public var link: [String: String]
  public var unlink: [String: String]
  public var bind: [InstantPermissionBinding]
  public var fields: [String: String]

  public init(
    namespace: String,
    allow: [InstantPermissionAction: String] = [:],
    link: [String: String] = [:],
    unlink: [String: String] = [:],
    bind: [InstantPermissionBinding] = [],
    fields: [String: String] = [:]
  ) {
    self.namespace = namespace
    self.allow = allow
    self.link = link
    self.unlink = unlink
    self.bind = bind
    self.fields = fields
  }

  public static func allowAll(namespace: String) -> Self {
    Self(
      namespace: namespace,
      allow: Dictionary(
        uniqueKeysWithValues: InstantPermissionAction.entityActions.map { ($0, "true") }
      )
    )
  }
}

public enum InstantPermissionAction: String, CaseIterable, Codable, Sendable {
  case `default` = "$default"
  case view
  case create
  case update
  case delete

  public static let entityActions: [Self] = [.view, .create, .update, .delete]
}

public struct InstantPermissionBinding: Hashable, Codable, Sendable {
  public var name: String
  public var expression: String

  public init(_ name: String, _ expression: String) {
    self.name = name
    self.expression = expression
  }
}

public struct InstantDefaultPermissions: Hashable, Codable, Sendable {
  public var allow: [InstantPermissionAction: String]
  public var link: [String: String]
  public var unlink: [String: String]
  public var bind: [InstantPermissionBinding]

  public init(
    allow: [InstantPermissionAction: String] = [:],
    link: [String: String] = [:],
    unlink: [String: String] = [:],
    bind: [InstantPermissionBinding] = []
  ) {
    self.allow = allow
    self.link = link
    self.unlink = unlink
    self.bind = bind
  }
}

public struct InstantAttributePermissions: Hashable, Codable, Sendable {
  public var allow: [InstantPermissionAction: String]
  public var bind: [InstantPermissionBinding]

  public init(
    allow: [InstantPermissionAction: String] = [:],
    bind: [InstantPermissionBinding] = []
  ) {
    self.allow = allow
    self.bind = bind
  }
}

public struct InstantRateLimit: Hashable, Codable, Sendable, Identifiable {
  public var id: String { name }
  public var name: String
  public var limits: [InstantRateLimitLimit]

  public init(name: String, limits: [InstantRateLimitLimit]) {
    self.name = name
    self.limits = limits
  }
}

public struct InstantRateLimitLimit: Hashable, Codable, Sendable {
  public var capacity: Int
  public var refill: InstantRateLimitRefill?

  public init(capacity: Int, refill: InstantRateLimitRefill? = nil) {
    self.capacity = capacity
    self.refill = refill
  }
}

public struct InstantRateLimitRefill: Hashable, Codable, Sendable {
  public var amount: Int?
  public var period: String?
  public var type: InstantRateLimitRefillType?

  public init(
    amount: Int? = nil,
    period: String? = nil,
    type: InstantRateLimitRefillType? = nil
  ) {
    self.amount = amount
    self.period = period
    self.type = type
  }
}

public enum InstantRateLimitRefillType: String, Codable, Sendable {
  case interval
  case greedy
}

public enum InstantPermissionsValidationError: Error, Equatable, Sendable, CustomStringConvertible {
  case reservedFieldRule(namespace: String, field: String)
  case emptyRateLimit(name: String)
  case invalidRateLimitCapacity(name: String, capacity: Int)
  case invalidRateLimitRefillAmount(name: String, amount: Int)
  case invalidRateLimitRefillPeriod(name: String, period: String)

  public var description: String {
    switch self {
    case .reservedFieldRule(let namespace, let field):
      "Field rule '\(namespace).\(field)' is invalid; Instant permissions do not allow rules for id."
    case .emptyRateLimit(let name):
      "Rate limit '\(name)' must contain at least one limit."
    case .invalidRateLimitCapacity(let name, let capacity):
      "Rate limit '\(name)' has invalid capacity \(capacity); capacity must be positive."
    case .invalidRateLimitRefillAmount(let name, let amount):
      "Rate limit '\(name)' has invalid refill amount \(amount); amount must be positive."
    case .invalidRateLimitRefillPeriod(let name, let period):
      "Rate limit '\(name)' has invalid refill period '\(period)'; period must be between 1 second and 24 hours."
    }
  }
}

public enum InstantNamespace {
  public static func defaultName(for typeName: String) -> String {
    let leadingLowercased = typeName.prefix(1).lowercased() + String(typeName.dropFirst())

    if leadingLowercased.hasSuffix("y"),
      let previous = leadingLowercased.dropLast().last,
      !"aeiou".contains(previous)
    {
      return String(leadingLowercased.dropLast()) + "ies"
    }

    if leadingLowercased.hasSuffix("s")
      || leadingLowercased.hasSuffix("x")
      || leadingLowercased.hasSuffix("z")
      || leadingLowercased.hasSuffix("ch")
      || leadingLowercased.hasSuffix("sh")
    {
      return leadingLowercased + "es"
    }

    return leadingLowercased + "s"
  }

  public static func isRedundantOverride(_ override: String, for typeName: String) -> Bool {
    override == defaultName(for: typeName)
  }
}

public enum InstantSchemaExamples {
  public static let todos = InstantEntitySchema(
    typeName: "Todo",
    attributes: TodoExample.attributes
  )

  public static let todosDocument = InstantSchemaDocument(
    entities: [todos]
  )

  public static let todoPermissions = InstantPermissionsDocument(
    namespaces: [
      .allowAll(namespace: TodoExample.namespace)
    ]
  )
}

public struct TypeScriptSchemaPrinter: Sendable {
  public init() {}

  public func printSchema(_ entities: [InstantEntitySchema]) throws -> String {
    try printSchema(InstantSchemaDocument(entities: entities))
  }

  public func printSchema(_ document: InstantSchemaDocument) throws -> String {
    try validate(document)

    var lines: [String] = [
      "import { i } from '@instantdb/core';",
      "",
      "export default i.schema({",
      "  entities: {",
    ]

    for entity in document.entities.sorted(by: { $0.namespace < $1.namespace }) {
      lines.append("    \(TypeScriptPrinterSupport.propertyKey(entity.namespace)): i.entity({")
      for attribute in printableAttributes(entity.attributes).sorted(by: { $0.name < $1.name }) {
        lines.append(
          "      \(TypeScriptPrinterSupport.propertyKey(attribute.name)): \(typeExpression(for: attribute)),"
        )
      }
      lines.append("    }),")
    }

    lines.append("  },")

    if !document.links.isEmpty {
      lines.append("  links: {")
      for link in document.links.sorted(by: { $0.name < $1.name }) {
        lines.append("    \(TypeScriptPrinterSupport.propertyKey(link.name)): {")
        lines.append("      forward: {")
        lines.append(contentsOf: endpointLines(for: link.forward, isRequired: link.isRequired))
        lines.append("      },")
        lines.append("      reverse: {")
        lines.append(contentsOf: endpointLines(for: link.reverse))
        lines.append("      },")
        lines.append("    },")
      }
      lines.append("  },")
    }

    if !document.rooms.isEmpty {
      lines.append("  rooms: {")
      for room in document.rooms.sorted(by: { $0.name < $1.name }) {
        lines.append("    \(TypeScriptPrinterSupport.propertyKey(room.name)): {")
        appendEntityExpression(
          to: &lines,
          name: "presence",
          attributes: room.presence.attributes,
          indentation: "      "
        )
        if !room.topics.isEmpty {
          lines.append("      topics: {")
          for topic in room.topics.sorted(by: { $0.name < $1.name }) {
            appendEntityExpression(
              to: &lines,
              name: topic.name,
              attributes: topic.payload.attributes,
              indentation: "        "
            )
          }
          lines.append("      },")
        }
        lines.append("    },")
      }
      lines.append("  },")
    }

    lines.append(contentsOf: [
      "});",
      "",
    ])

    return lines.joined(separator: "\n")
  }

  private func appendEntityExpression(
    to lines: inout [String],
    name: String,
    attributes: [InstantAttribute],
    indentation: String
  ) {
    if attributes.isEmpty {
      lines.append("\(indentation)\(TypeScriptPrinterSupport.propertyKey(name)): i.entity({}),")
      return
    }

    lines.append("\(indentation)\(TypeScriptPrinterSupport.propertyKey(name)): i.entity({")
    for attribute in printableAttributes(attributes).sorted(by: { $0.name < $1.name }) {
      lines.append(
        "\(indentation)  \(TypeScriptPrinterSupport.propertyKey(attribute.name)): \(typeExpression(for: attribute)),"
      )
    }
    lines.append("\(indentation)}),")
  }

  private func printableAttributes(_ attributes: [InstantAttribute]) -> [InstantAttribute] {
    attributes.filter { !$0.primaryKey }
  }

  private func validate(_ document: InstantSchemaDocument) throws {
    for entity in document.entities {
      try validatePrintableAttributes(entity.attributes)
    }
    for room in document.rooms {
      try validatePrintableAttributes(room.presence.attributes)
      for topic in room.topics {
        try validatePrintableAttributes(topic.payload.attributes)
      }
    }
    for link in document.links {
      try validateCascadeEndpoint(
        link: link.name,
        endpoint: "forward",
        value: link.forward
      )
      try validateCascadeEndpoint(
        link: link.name,
        endpoint: "reverse",
        value: link.reverse
      )
    }
  }

  private func validatePrintableAttributes(_ attributes: [InstantAttribute]) throws {
    for attribute in printableAttributes(attributes) where attribute.valueType == .ref {
      throw InstantSchemaValidationError.unsupportedRefAttribute(
        namespace: attribute.namespace,
        name: attribute.name
      )
    }
  }

  private func validateCascadeEndpoint(
    link: String,
    endpoint: String,
    value: InstantLinkEndpoint
  ) throws {
    guard value.onDelete == .cascade, value.cardinality != .one else { return }
    throw InstantSchemaValidationError.invalidLinkCascadeEndpoint(
      link: link,
      endpoint: endpoint,
      cardinality: value.cardinality
    )
  }

  private func endpointLines(
    for endpoint: InstantLinkEndpoint,
    isRequired: Bool? = nil
  ) -> [String] {
    var lines = [
      "        on: \(TypeScriptPrinterSupport.stringLiteral(endpoint.namespace)),",
      "        has: \(TypeScriptPrinterSupport.stringLiteral(endpoint.cardinality.rawValue)),",
      "        label: \(TypeScriptPrinterSupport.stringLiteral(endpoint.label)),",
    ]
    if let isRequired {
      lines.append("        required: \(isRequired),")
    }
    if endpoint.onDelete == .cascade {
      lines.append("        onDelete: \(TypeScriptPrinterSupport.stringLiteral("cascade")),")
    }
    return lines
  }

  private func typeExpression(for attribute: InstantAttribute) -> String {
    let scalar =
      switch attribute.valueType {
      case .string:
        "i.string()"
      case .number:
        "i.number()"
      case .boolean:
        "i.boolean()"
      case .date:
        "i.date()"
      case .json:
        "i.json()"
      case .any:
        "i.any()"
      case .ref:
        preconditionFailure("Ref attributes must be printed from schema links.")
      }

    var expression = scalar
    if !attribute.isRequired {
      expression += ".optional()"
    }
    if attribute.isIndexed {
      expression += ".indexed()"
    }
    if attribute.isUnique {
      expression += ".unique()"
    }
    return expression
  }
}

public enum TypeScriptInstantRulesPackage: String, Sendable {
  case core = "@instantdb/core"
  case react = "@instantdb/react"
}

public struct TypeScriptPermissionsPrinter: Sendable {
  public var package: TypeScriptInstantRulesPackage

  public init(package: TypeScriptInstantRulesPackage = .core) {
    self.package = package
  }

  public func printPermissions(_ document: InstantPermissionsDocument) throws -> String {
    try validate(document)

    var lines: [String] = [
      "// Docs: https://www.instantdb.com/docs/permissions",
      "",
      "import type { InstantRules } from \(TypeScriptPrinterSupport.stringLiteral(package.rawValue));",
      "",
      "const rules = {",
    ]

    if let attrs = document.attrs {
      lines.append("  attrs: {")
      lines.append(
        contentsOf: printRuleBlock(
          allow: attrs.allow,
          link: [:],
          unlink: [:],
          bind: attrs.bind,
          fields: nil,
          indentation: "    "
        )
      )
      lines.append("  },")
    }

    if let defaults = document.defaults {
      lines.append("  \(TypeScriptPrinterSupport.propertyKey("$default")): {")
      lines.append(
        contentsOf: printRuleBlock(
          allow: defaults.allow,
          link: defaults.link,
          unlink: defaults.unlink,
          bind: defaults.bind,
          fields: nil,
          indentation: "    "
        )
      )
      lines.append("  },")
    }

    if !document.rateLimits.isEmpty {
      lines.append("  \(TypeScriptPrinterSupport.propertyKey("$rateLimits")): {")
      for rateLimit in document.rateLimits.sorted(by: { $0.name < $1.name }) {
        lines.append("    \(TypeScriptPrinterSupport.propertyKey(rateLimit.name)): {")
        lines.append("      limits: [")
        for limit in rateLimit.limits {
          lines.append(contentsOf: printRateLimit(limit, indentation: "        "))
        }
        lines.append("      ],")
        lines.append("    },")
      }
      lines.append("  },")
    }

    for namespace in document.namespaces.sorted(by: { $0.namespace < $1.namespace }) {
      lines.append("  \(TypeScriptPrinterSupport.propertyKey(namespace.namespace)): {")
      lines.append(
        contentsOf: printRuleBlock(
          allow: namespace.allow,
          link: namespace.link,
          unlink: namespace.unlink,
          bind: namespace.bind,
          fields: namespace.fields,
          indentation: "    "
        )
      )
      lines.append("  },")
    }

    lines.append(contentsOf: [
      "} satisfies InstantRules;",
      "",
      "export default rules;",
      "",
    ])

    return lines.joined(separator: "\n")
  }

  private func validate(_ document: InstantPermissionsDocument) throws {
    for namespace in document.namespaces {
      if namespace.fields.keys.contains("id") {
        throw InstantPermissionsValidationError.reservedFieldRule(
          namespace: namespace.namespace,
          field: "id"
        )
      }
    }

    for rateLimit in document.rateLimits {
      guard !rateLimit.limits.isEmpty else {
        throw InstantPermissionsValidationError.emptyRateLimit(name: rateLimit.name)
      }

      for limit in rateLimit.limits {
        guard limit.capacity > 0 else {
          throw InstantPermissionsValidationError.invalidRateLimitCapacity(
            name: rateLimit.name,
            capacity: limit.capacity
          )
        }
        if let amount = limit.refill?.amount, amount <= 0 {
          throw InstantPermissionsValidationError.invalidRateLimitRefillAmount(
            name: rateLimit.name,
            amount: amount
          )
        }
        if let period = limit.refill?.period,
          !Self.isValidRateLimitRefillPeriod(period)
        {
          throw InstantPermissionsValidationError.invalidRateLimitRefillPeriod(
            name: rateLimit.name,
            period: period
          )
        }
      }
    }
  }

  private static func isValidRateLimitRefillPeriod(_ period: String) -> Bool {
    let parts =
      period
      .split(whereSeparator: \.isWhitespace)
      .map { String($0).lowercased() }
    guard parts.count == 2,
      let value = Double(parts[0]),
      value > 0
    else {
      return false
    }

    let seconds =
      switch parts[1] {
      case "second", "seconds":
        value
      case "minute", "minutes":
        value * 60
      case "hour", "hours":
        value * 60 * 60
      case "day", "days":
        value * 24 * 60 * 60
      default:
        -1.0
      }

    return seconds >= 1 && seconds <= 24 * 60 * 60
  }

  private func printRuleBlock(
    allow: [InstantPermissionAction: String],
    link: [String: String],
    unlink: [String: String],
    bind: [InstantPermissionBinding],
    fields: [String: String]?,
    indentation: String
  ) -> [String] {
    var lines: [String] = []
    if allow.isEmpty, link.isEmpty, unlink.isEmpty {
      lines.append("\(indentation)allow: {},")
    } else {
      lines.append("\(indentation)allow: {")
      for action in InstantPermissionAction.allCases {
        guard let expression = allow[action] else { continue }
        lines.append(
          "\(indentation)  \(TypeScriptPrinterSupport.propertyKey(action.rawValue)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
        )
      }
      if !link.isEmpty {
        lines.append("\(indentation)  link: {")
        for (name, expression) in link.sorted(by: { $0.key < $1.key }) {
          lines.append(
            "\(indentation)    \(TypeScriptPrinterSupport.propertyKey(name)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
          )
        }
        lines.append("\(indentation)  },")
      }
      if !unlink.isEmpty {
        lines.append("\(indentation)  unlink: {")
        for (name, expression) in unlink.sorted(by: { $0.key < $1.key }) {
          lines.append(
            "\(indentation)    \(TypeScriptPrinterSupport.propertyKey(name)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
          )
        }
        lines.append("\(indentation)  },")
      }
      lines.append("\(indentation)},")
    }

    if !bind.isEmpty {
      lines.append("\(indentation)bind: [")
      for binding in bind {
        lines.append(
          "\(indentation)  \(TypeScriptPrinterSupport.stringLiteral(binding.name)), \(TypeScriptPrinterSupport.stringLiteral(binding.expression)),"
        )
      }
      lines.append("\(indentation)],")
    }

    if let fields, !fields.isEmpty {
      lines.append("\(indentation)fields: {")
      for (name, expression) in fields.sorted(by: { $0.key < $1.key }) {
        lines.append(
          "\(indentation)  \(TypeScriptPrinterSupport.propertyKey(name)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
        )
      }
      lines.append("\(indentation)},")
    }

    return lines
  }

  private func printRateLimit(
    _ limit: InstantRateLimitLimit,
    indentation: String
  ) -> [String] {
    guard let refill = limit.refill else {
      return ["\(indentation){ capacity: \(limit.capacity) },"]
    }

    var refillParts: [String] = []
    if let amount = refill.amount {
      refillParts.append("amount: \(amount)")
    }
    if let period = refill.period {
      refillParts.append("period: \(TypeScriptPrinterSupport.stringLiteral(period))")
    }
    if let type = refill.type {
      refillParts.append("type: \(TypeScriptPrinterSupport.stringLiteral(type.rawValue))")
    }

    if refillParts.isEmpty {
      return ["\(indentation){ capacity: \(limit.capacity), refill: {} },"]
    }

    return [
      "\(indentation){ capacity: \(limit.capacity), refill: { \(refillParts.joined(separator: ", ")) } },"
    ]
  }
}

private enum TypeScriptPrinterSupport {
  static func propertyKey(_ key: String) -> String {
    guard !key.hasPrefix("$"),
      isIdentifier(key)
    else {
      return stringLiteral(key)
    }
    return key
  }

  static func stringLiteral(_ string: String) -> String {
    var result = "\""
    for scalar in string.unicodeScalars {
      switch scalar {
      case "\"":
        result += "\\\""
      case "\\":
        result += "\\\\"
      case "\n":
        result += "\\n"
      case "\r":
        result += "\\r"
      case "\t":
        result += "\\t"
      case "\u{08}":
        result += "\\b"
      case "\u{0C}":
        result += "\\f"
      case let scalar where scalar.value < 0x20:
        let hex = String(scalar.value, radix: 16)
        result += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
      default:
        result.unicodeScalars.append(scalar)
      }
    }
    result += "\""
    return result
  }

  private static func isIdentifier(_ key: String) -> Bool {
    guard let first = key.unicodeScalars.first,
      CharacterSet(charactersIn: "_$").contains(first)
        || CharacterSet.letters.contains(first)
    else { return false }

    return key.unicodeScalars.dropFirst().allSatisfy {
      CharacterSet(charactersIn: "_$").contains($0)
        || CharacterSet.alphanumerics.contains($0)
    }
  }
}
