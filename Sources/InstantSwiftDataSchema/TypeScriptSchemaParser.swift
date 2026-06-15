import Foundation
import InstantSwiftDataCore

public struct ParsedInstantEntitySchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { namespace }
  public var namespace: String
  public var attributes: [InstantAttribute]

  public init(namespace: String, attributes: [InstantAttribute]) {
    self.namespace = namespace
    self.attributes = ([.primaryKey(namespace: namespace)] + attributes.filter { !$0.primaryKey })
      .sorted { $0.name < $1.name }
  }

  public init(_ schema: InstantEntitySchema) {
    self.init(namespace: schema.namespace, attributes: schema.attributes)
  }
}

public struct ParsedInstantSchemaDocument: Hashable, Codable, Sendable {
  public var entities: [ParsedInstantEntitySchema]
  public var links: [InstantLinkSchema]
  public var rooms: [InstantRoomSchema]

  public init(
    entities: [ParsedInstantEntitySchema],
    links: [InstantLinkSchema] = [],
    rooms: [InstantRoomSchema] = []
  ) {
    self.entities = entities.sorted { $0.namespace < $1.namespace }
    self.links = links.sorted { $0.name < $1.name }
    self.rooms = rooms
      .map { $0.normalized }
      .sorted { $0.name < $1.name }
  }

  public init(_ document: InstantSchemaDocument) {
    self.init(
      entities: document.entities.map(ParsedInstantEntitySchema.init),
      links: document.links,
      rooms: document.rooms
    )
  }
}

public enum TypeScriptSchemaParseError: Error, Equatable, Sendable, CustomStringConvertible {
  case missingEntitiesObject
  case malformedObject(String)
  case unsupportedTopLevelKey(String)
  case unsupportedEntityExpression(namespace: String, expression: String)
  case unsupportedAttributeExpression(namespace: String, attribute: String, expression: String)
  case missingLinkEndpoint(link: String, endpoint: String)
  case unsupportedLinkExpression(name: String, expression: String)
  case unsupportedLinkEndpointKey(name: String, endpoint: String, key: String)
  case unsupportedLinkEndpointValue(name: String, endpoint: String, key: String, value: String)
  case invalidLinkCascadeEndpoint(link: String, endpoint: String, cardinality: InstantCardinality)
  case missingRoomPresence(room: String)
  case unsupportedRoomKey(room: String, key: String)

  public var description: String {
    switch self {
    case .missingEntitiesObject:
      "Could not find an entities object in the TypeScript schema."
    case .malformedObject(let message):
      "Malformed TypeScript schema object: \(message)"
    case .unsupportedTopLevelKey(let key):
      "Unsupported top-level schema key: \(key)"
    case .unsupportedEntityExpression(let namespace, let expression):
      "Unsupported entity expression for '\(namespace)': \(expression)"
    case .unsupportedAttributeExpression(let namespace, let attribute, let expression):
      "Unsupported attribute expression for '\(namespace).\(attribute)': \(expression)"
    case .missingLinkEndpoint(let link, let endpoint):
      "Link '\(link)' is missing its \(endpoint) endpoint."
    case .unsupportedLinkExpression(let name, let expression):
      "Unsupported link expression for '\(name)': \(expression)"
    case .unsupportedLinkEndpointKey(let name, let endpoint, let key):
      "Unsupported \(endpoint) endpoint key for link '\(name)': \(key)"
    case .unsupportedLinkEndpointValue(let name, let endpoint, let key, let value):
      "Unsupported \(endpoint) endpoint value for link '\(name)' key '\(key)': \(value)"
    case .invalidLinkCascadeEndpoint(let link, let endpoint, let cardinality):
      "Link '\(link)' \(endpoint) endpoint has invalid cascade delete for cardinality '\(cardinality.rawValue)'. Cascade delete is only supported on has: \"one\" links."
    case .missingRoomPresence(let room):
      "Room '\(room)' is missing its presence schema."
    case .unsupportedRoomKey(let room, let key):
      "Unsupported room schema key for '\(room)': \(key)"
    }
  }
}

public struct TypeScriptSchemaParser: Sendable {
  public init() {}

  public func parse(_ source: String) throws -> [ParsedInstantEntitySchema] {
    try parseDocument(source).entities
  }

  public func parseDocument(_ source: String) throws -> ParsedInstantSchemaDocument {
    guard let schemaCall = try ObjectEntryParser.firstOccurrence(of: "i.schema(", in: source)
    else {
      throw TypeScriptSchemaParseError.missingEntitiesObject
    }
    let schemaBody = try ObjectEntryParser.extractFirstObjectBody(
      from: String(source[schemaCall.upperBound...]),
      context: "schema"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: schemaBody)
    for entry in entries where entry.key != "entities" && entry.key != "links" && entry.key != "rooms" {
      throw TypeScriptSchemaParseError.unsupportedTopLevelKey(entry.key)
    }
    guard let entitiesExpression = entries.lastValue(for: "entities")
    else {
      throw TypeScriptSchemaParseError.missingEntitiesObject
    }

    let entitiesBody = try ObjectEntryParser.extractFirstObjectBody(
      from: entitiesExpression,
      context: "entities"
    )

    let entities = try ObjectEntryParser.parseObjectEntries(in: entitiesBody)
      .map { entity in
        try parseEntity(namespace: entity.key, expression: entity.value)
      }
      .sorted { $0.namespace < $1.namespace }

    let links: [InstantLinkSchema]
    if let linksExpression = entries.lastValue(for: "links") {
      links = try parseLinks(expression: linksExpression)
    } else {
      links = []
    }

    let rooms: [InstantRoomSchema]
    if let roomsExpression = entries.lastValue(for: "rooms") {
      rooms = try parseRooms(expression: roomsExpression)
    } else {
      rooms = []
    }

    return ParsedInstantSchemaDocument(entities: entities, links: links, rooms: rooms)
  }

  private func parseEntity(
    namespace: String,
    expression: String
  ) throws -> ParsedInstantEntitySchema {
    guard expression.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("i.entity(")
    else {
      throw TypeScriptSchemaParseError.unsupportedEntityExpression(
        namespace: namespace,
        expression: expression
      )
    }

    let attributesBody = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: namespace
    )

    let attributes = try ObjectEntryParser.parseObjectEntries(in: attributesBody)
      .map { attribute in
        try parseAttribute(
          namespace: namespace,
          name: attribute.key,
          expression: attribute.value
        )
      }
      .sorted { $0.name < $1.name }

    return ParsedInstantEntitySchema(namespace: namespace, attributes: attributes)
  }

  private func parseLinks(expression: String) throws -> [InstantLinkSchema] {
    let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard expression.hasPrefix("{") else {
      throw TypeScriptSchemaParseError.unsupportedLinkExpression(
        name: "links",
        expression: expression
      )
    }
    let linksBody = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "links"
    )

    return try ObjectEntryParser.parseObjectEntries(in: linksBody)
      .map { link in
        try parseLink(name: link.key, expression: link.value)
      }
      .sorted { $0.name < $1.name }
  }

  private func parseLink(
    name: String,
    expression: String
  ) throws -> InstantLinkSchema {
    let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard expression.hasPrefix("{") else {
      throw TypeScriptSchemaParseError.unsupportedLinkExpression(
        name: name,
        expression: expression
      )
    }

    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "link \(name)"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)
    for entry in entries where entry.key != "forward" && entry.key != "reverse" {
      throw TypeScriptSchemaParseError.unsupportedLinkEndpointKey(
        name: name,
        endpoint: "link",
        key: entry.key
      )
    }

    guard let forwardExpression = entries.lastValue(for: "forward")
    else {
      throw TypeScriptSchemaParseError.missingLinkEndpoint(link: name, endpoint: "forward")
    }
    guard let reverseExpression = entries.lastValue(for: "reverse")
    else {
      throw TypeScriptSchemaParseError.missingLinkEndpoint(link: name, endpoint: "reverse")
    }

    let forward = try parseLinkEndpoint(
      link: name,
      endpoint: "forward",
      expression: forwardExpression,
      allowsRequired: true
    )
    let reverse = try parseLinkEndpoint(
      link: name,
      endpoint: "reverse",
      expression: reverseExpression,
      allowsRequired: false
    )

    return InstantLinkSchema(
      name: name,
      forward: forward.endpoint,
      reverse: reverse.endpoint,
      isRequired: forward.isRequired
    )
  }

  private func parseLinkEndpoint(
    link: String,
    endpoint: String,
    expression: String,
    allowsRequired: Bool
  ) throws -> ParsedLinkEndpoint {
    let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard expression.hasPrefix("{") else {
      throw TypeScriptSchemaParseError.unsupportedLinkExpression(
        name: link,
        expression: expression
      )
    }

    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "\(link).\(endpoint)"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)

    var namespace: String?
    var cardinality: InstantCardinality?
    var label: String?
    var isRequired: Bool?
    var onDelete = InstantDeleteRule.none

    for entry in entries {
      switch entry.key {
      case "on":
        namespace = try ObjectEntryParser.parseStringExpression(entry.value)

      case "has":
        let value = try ObjectEntryParser.parseStringExpression(entry.value)
        guard let parsed = InstantCardinality(rawValue: value) else {
          throw TypeScriptSchemaParseError.unsupportedLinkEndpointValue(
            name: link,
            endpoint: endpoint,
            key: entry.key,
            value: value
          )
        }
        cardinality = parsed

      case "label":
        label = try ObjectEntryParser.parseStringExpression(entry.value)

      case "required":
        guard allowsRequired else {
          throw TypeScriptSchemaParseError.unsupportedLinkEndpointKey(
            name: link,
            endpoint: endpoint,
            key: entry.key
          )
        }
        isRequired = try ObjectEntryParser.parseBoolExpression(entry.value)

      case "onDelete":
        let value = try ObjectEntryParser.parseStringExpression(entry.value)
        guard value == "cascade" else {
          throw TypeScriptSchemaParseError.unsupportedLinkEndpointValue(
            name: link,
            endpoint: endpoint,
            key: entry.key,
            value: value
          )
        }
        onDelete = .cascade

      default:
        throw TypeScriptSchemaParseError.unsupportedLinkEndpointKey(
          name: link,
          endpoint: endpoint,
          key: entry.key
        )
      }
    }

    guard let namespace else {
      throw TypeScriptSchemaParseError.malformedObject(
        "Link '\(link)' \(endpoint) endpoint is missing 'on'."
      )
    }
    guard let cardinality else {
      throw TypeScriptSchemaParseError.malformedObject(
        "Link '\(link)' \(endpoint) endpoint is missing 'has'."
      )
    }
    guard let label else {
      throw TypeScriptSchemaParseError.malformedObject(
        "Link '\(link)' \(endpoint) endpoint is missing 'label'."
      )
    }
    if onDelete == .cascade, cardinality != .one {
      throw TypeScriptSchemaParseError.invalidLinkCascadeEndpoint(
        link: link,
        endpoint: endpoint,
        cardinality: cardinality
      )
    }

    return ParsedLinkEndpoint(
      endpoint: InstantLinkEndpoint(
        namespace: namespace,
        cardinality: cardinality,
        label: label,
        onDelete: onDelete
      ),
      isRequired: isRequired
    )
  }

  private func parseAttribute(
    namespace: String,
    name: String,
    expression: String
  ) throws -> InstantAttribute {
    let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parsedExpression = ParsedAttributeExpression(expression) else {
      throw TypeScriptSchemaParseError.unsupportedAttributeExpression(
        namespace: namespace,
        attribute: name,
        expression: expression
      )
    }

    return InstantAttribute(
      id: "\(namespace)/\(name)",
      namespace: namespace,
      name: name,
      valueType: parsedExpression.valueType,
      isRequired: parsedExpression.isRequired,
      isIndexed: parsedExpression.isIndexed,
      isUnique: parsedExpression.isUnique
    )
  }

  private func parseRooms(expression: String) throws -> [InstantRoomSchema] {
    let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard try ObjectEntryParser.isExactObjectExpression(expression) else {
      throw TypeScriptSchemaParseError.malformedObject("Expected rooms object.")
    }
    let roomsBody = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "rooms"
    )

    return try ObjectEntryParser.parseObjectEntries(in: roomsBody)
      .map { room in
        try parseRoom(name: room.key, expression: room.value)
      }
      .sorted { $0.name < $1.name }
  }

  private func parseRoom(
    name: String,
    expression: String
  ) throws -> InstantRoomSchema {
    let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard try ObjectEntryParser.isExactObjectExpression(expression) else {
      throw TypeScriptSchemaParseError.unsupportedRoomKey(room: name, key: "initializer")
    }
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "room \(name)"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)
    for entry in entries where entry.key != "presence" && entry.key != "topics" {
      throw TypeScriptSchemaParseError.unsupportedRoomKey(room: name, key: entry.key)
    }

    guard let presenceExpression = entries.lastValue(for: "presence") else {
      throw TypeScriptSchemaParseError.missingRoomPresence(room: name)
    }

    let presence = try parseRoomPayload(
      namespace: "rooms/\(name)/presence",
      expression: presenceExpression
    )

    let topics: [InstantRoomTopicSchema]
    if let topicsExpression = entries.lastValue(for: "topics") {
      topics = try parseRoomTopics(room: name, expression: topicsExpression)
    } else {
      topics = []
    }

    return InstantRoomSchema(name: name, presence: presence, topics: topics)
  }

  private func parseRoomTopics(
    room: String,
    expression: String
  ) throws -> [InstantRoomTopicSchema] {
    let expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    guard try ObjectEntryParser.isExactObjectExpression(expression) else {
      throw TypeScriptSchemaParseError.unsupportedRoomKey(room: room, key: "topics")
    }
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "room \(room) topics"
    )
    return try ObjectEntryParser.parseObjectEntries(in: body)
      .map { topic in
        InstantRoomTopicSchema(
          name: topic.key,
          payload: try parseRoomPayload(
            namespace: "rooms/\(room)/topics/\(topic.key)",
            expression: topic.value
          )
        )
      }
      .sorted { $0.name < $1.name }
  }

  private func parseRoomPayload(
    namespace: String,
    expression: String
  ) throws -> InstantRoomPayloadSchema {
    guard try ObjectEntryParser.isExactEntityExpression(expression) else {
      throw TypeScriptSchemaParseError.unsupportedEntityExpression(
        namespace: namespace,
        expression: expression.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }
    return InstantRoomPayloadSchema(
      attributes: try parseEntity(namespace: namespace, expression: expression)
        .attributes
        .filter { !$0.primaryKey }
    )
  }
}

private struct ParsedAttributeExpression {
  var valueType: InstantValueType
  var isRequired: Bool
  var isIndexed: Bool
  var isUnique: Bool

  init?(_ expression: String) {
    let scalars = expression.unicodeScalars
    let scalarString = String(scalars)
    let scalarPrefixes: [(String, InstantValueType)] = [
      ("i.string()", .string),
      ("i.number()", .number),
      ("i.boolean()", .boolean),
      ("i.date()", .date),
      ("i.json()", .json),
      ("i.any()", .any),
    ]

    guard let scalar = scalarPrefixes.first(where: { scalarString.hasPrefix($0.0) })
    else { return nil }

    self.valueType = scalar.1
    self.isRequired = true
    self.isIndexed = false
    self.isUnique = false

    var remainder = String(scalarString.dropFirst(scalar.0.count))
    while !remainder.isEmpty {
      if remainder.hasPrefix(".optional()") {
        self.isRequired = false
        remainder.removeFirst(".optional()".count)
      } else if remainder.hasPrefix(".indexed()") {
        self.isIndexed = true
        remainder.removeFirst(".indexed()".count)
      } else if remainder.hasPrefix(".unique()") {
        self.isUnique = true
        remainder.removeFirst(".unique()".count)
      } else {
        return nil
      }
    }
  }
}

private struct ParsedLinkEndpoint {
  var endpoint: InstantLinkEndpoint
  var isRequired: Bool?
}

public enum TypeScriptPermissionsParseError: Error, Equatable, Sendable, CustomStringConvertible {
  case missingRulesObject
  case unsupportedRuleKey(context: String, key: String)
  case unsupportedRuleValue(context: String, key: String, value: String)

  public var description: String {
    switch self {
    case .missingRulesObject:
      "Could not find a rules object in the TypeScript permissions."
    case .unsupportedRuleKey(let context, let key):
      "Unsupported permissions key in \(context): \(key)"
    case .unsupportedRuleValue(let context, let key, let value):
      "Unsupported permissions value in \(context) for key '\(key)': \(value)"
    }
  }
}

public struct TypeScriptPermissionsParser: Sendable {
  public init() {}

  public func parse(_ source: String) throws -> InstantPermissionsDocument {
    guard let rules = try ObjectEntryParser.firstOccurrence(of: "const rules =", in: source)
    else {
      throw TypeScriptPermissionsParseError.missingRulesObject
    }
    let body = try parseRulesObjectBody(afterRulesEquals: String(source[rules.upperBound...]))
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)

    var attrs: InstantAttributePermissions?
    var defaults: InstantDefaultPermissions?
    var rateLimits: [InstantRateLimit] = []
    var namespaces: [String: InstantNamespacePermissions] = [:]

    for entry in entries {
      switch entry.key {
      case "attrs":
        let block = try parseRuleBlock(
          context: "attrs",
          expression: entry.value,
          allowsRelationshipRules: false,
          allowsFields: false
        )
        attrs = InstantAttributePermissions(
          allow: block.allow,
          bind: block.bind
        )

      case "$default":
        let block = try parseRuleBlock(
          context: "$default",
          expression: entry.value,
          allowsRelationshipRules: true,
          allowsFields: false
        )
        defaults = InstantDefaultPermissions(
          allow: block.allow,
          link: block.link,
          unlink: block.unlink,
          bind: block.bind
        )

      case "$rateLimits":
        rateLimits = try parseRateLimits(expression: entry.value)

      default:
        let block = try parseRuleBlock(
          context: entry.key,
          expression: entry.value,
          allowsRelationshipRules: true,
          allowsFields: true
        )
        namespaces[entry.key] = InstantNamespacePermissions(
          namespace: entry.key,
          allow: block.allow,
          link: block.link,
          unlink: block.unlink,
          bind: block.bind,
          fields: block.fields
        )
      }
    }

    return InstantPermissionsDocument(
      attrs: attrs,
      defaults: defaults,
      rateLimits: rateLimits.sorted { $0.name < $1.name },
      namespaces: namespaces.values.sorted { $0.namespace < $1.namespace }
    )
  }

  private func parseRulesObjectBody(afterRulesEquals source: String) throws -> String {
    var index = source.startIndex
    ObjectEntryParser.skipTrivia(in: source, index: &index)
    guard index < source.endIndex, source[index] == "{" else {
      throw TypeScriptPermissionsParseError.unsupportedRuleValue(
        context: "rules",
        key: "initializer",
        value: source.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    let close = try ObjectEntryParser.matchingBrace(in: source, open: index)
    let body = String(source[source.index(after: index)..<close])
    index = source.index(after: close)
    ObjectEntryParser.skipTrivia(in: source, index: &index)
    if consumeKeyword("satisfies", in: source, index: &index) {
      ObjectEntryParser.skipTrivia(in: source, index: &index)
      guard consumeKeyword("InstantRules", in: source, index: &index) else {
        throw unsupportedRulesInitializer(source)
      }
      ObjectEntryParser.skipTrivia(in: source, index: &index)
    }
    guard index < source.endIndex, source[index] == ";" else {
      throw unsupportedRulesInitializer(source)
    }
    source.formIndex(after: &index)
    ObjectEntryParser.skipTrivia(in: source, index: &index)
    guard consumeKeyword("export", in: source, index: &index) else {
      throw unsupportedRulesInitializer(source)
    }
    ObjectEntryParser.skipTrivia(in: source, index: &index)
    guard consumeKeyword("default", in: source, index: &index) else {
      throw unsupportedRulesInitializer(source)
    }
    ObjectEntryParser.skipTrivia(in: source, index: &index)
    guard consumeKeyword("rules", in: source, index: &index) else {
      throw unsupportedRulesInitializer(source)
    }
    ObjectEntryParser.skipTrivia(in: source, index: &index)
    guard index < source.endIndex, source[index] == ";" else {
      throw unsupportedRulesInitializer(source)
    }
    source.formIndex(after: &index)
    ObjectEntryParser.skipTrivia(in: source, index: &index)
    guard index == source.endIndex else {
      throw unsupportedRulesInitializer(source)
    }
    return body
  }

  private func consumeKeyword(
    _ keyword: String,
    in source: String,
    index: inout String.Index
  ) -> Bool {
    guard source[index...].hasPrefix(keyword) else { return false }
    let end = source.index(index, offsetBy: keyword.count)
    if end < source.endIndex, isIdentifierCharacter(source[end]) {
      return false
    }
    index = end
    return true
  }

  private func isIdentifierCharacter(_ character: Character) -> Bool {
    character == "_" || character == "$" || character.isLetter || character.isNumber
  }

  private func unsupportedRulesInitializer(_ source: String) -> TypeScriptPermissionsParseError {
    .unsupportedRuleValue(
      context: "rules",
      key: "initializer",
      value: source.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  private func parseRuleBlock(
    context: String,
    expression: String,
    allowsRelationshipRules: Bool,
    allowsFields: Bool
  ) throws -> ParsedRuleBlock {
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: context
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)

    var allow: [InstantPermissionAction: String] = [:]
    var link: [String: String] = [:]
    var unlink: [String: String] = [:]
    var bind: [InstantPermissionBinding] = []
    var fields: [String: String] = [:]

    for entry in entries {
      switch entry.key {
      case "allow":
        let parsed = try parseAllowBlock(
          context: "\(context).allow",
          expression: entry.value,
          allowsRelationshipRules: allowsRelationshipRules
        )
        allow = parsed.allow
        link = parsed.link
        unlink = parsed.unlink

      case "bind":
        bind = try parseBindings(context: "\(context).bind", expression: entry.value)

      case "fields":
        guard allowsFields else {
          throw TypeScriptPermissionsParseError.unsupportedRuleKey(
            context: context,
            key: entry.key
          )
        }
        fields = try parseStringMap(context: "\(context).fields", expression: entry.value)

      default:
        throw TypeScriptPermissionsParseError.unsupportedRuleKey(
          context: context,
          key: entry.key
        )
      }
    }

    return ParsedRuleBlock(
      allow: allow,
      link: link,
      unlink: unlink,
      bind: bind,
      fields: fields
    )
  }

  private func parseAllowBlock(
    context: String,
    expression: String,
    allowsRelationshipRules: Bool
  ) throws -> ParsedAllowBlock {
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: context
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)

    var allow: [InstantPermissionAction: String] = [:]
    var link: [String: String] = [:]
    var unlink: [String: String] = [:]

    for entry in entries {
      switch entry.key {
      case "link":
        guard allowsRelationshipRules else {
          throw TypeScriptPermissionsParseError.unsupportedRuleKey(
            context: context,
            key: entry.key
          )
        }
        link = try parseStringMap(context: "\(context).link", expression: entry.value)

      case "unlink":
        guard allowsRelationshipRules else {
          throw TypeScriptPermissionsParseError.unsupportedRuleKey(
            context: context,
            key: entry.key
          )
        }
        unlink = try parseStringMap(context: "\(context).unlink", expression: entry.value)

      default:
        guard let action = InstantPermissionAction(rawValue: entry.key) else {
          throw TypeScriptPermissionsParseError.unsupportedRuleKey(
            context: context,
            key: entry.key
          )
        }
        allow[action] = try ObjectEntryParser.parseStringExpression(entry.value)
      }
    }

    return ParsedAllowBlock(allow: allow, link: link, unlink: unlink)
  }

  private func parseBindings(
    context: String,
    expression: String
  ) throws -> [InstantPermissionBinding] {
    let values = try ObjectEntryParser.parseArrayValues(expression, context: context)
    guard values.count.isMultiple(of: 2) else {
      throw TypeScriptPermissionsParseError.unsupportedRuleValue(
        context: context,
        key: "bind",
        value: expression.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    var bindings: [InstantPermissionBinding] = []
    var index = 0
    while index < values.count {
      bindings.append(
        InstantPermissionBinding(
          try ObjectEntryParser.parseStringExpression(values[index]),
          try ObjectEntryParser.parseStringExpression(values[index + 1])
        )
      )
      index += 2
    }
    return bindings
  }

  private func parseStringMap(
    context: String,
    expression: String
  ) throws -> [String: String] {
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: context
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)

    var result: [String: String] = [:]
    for entry in entries {
      result[entry.key] = try ObjectEntryParser.parseStringExpression(entry.value)
    }
    return result
  }

  private func parseRateLimits(expression: String) throws -> [InstantRateLimit] {
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "$rateLimits"
    )
    return try ObjectEntryParser.parseObjectEntries(in: body)
      .map { entry in
        InstantRateLimit(
          name: entry.key,
          limits: try parseRateLimitList(name: entry.key, expression: entry.value)
        )
      }
      .sorted { $0.name < $1.name }
  }

  private func parseRateLimitList(
    name: String,
    expression: String
  ) throws -> [InstantRateLimitLimit] {
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "$rateLimits.\(name)"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)
    for entry in entries where entry.key != "limits" {
      throw TypeScriptPermissionsParseError.unsupportedRuleKey(
        context: "$rateLimits.\(name)",
        key: entry.key
      )
    }

    guard let limitsExpression = entries.lastValue(for: "limits") else {
      throw TypeScriptPermissionsParseError.unsupportedRuleKey(
        context: "$rateLimits.\(name)",
        key: "limits"
      )
    }

    return try ObjectEntryParser.parseArrayValues(
      limitsExpression,
      context: "$rateLimits.\(name).limits"
    )
    .map { try parseRateLimitLimit(name: name, expression: $0) }
  }

  private func parseRateLimitLimit(
    name: String,
    expression: String
  ) throws -> InstantRateLimitLimit {
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "$rateLimits.\(name).limit"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)

    var capacity: Int?
    var refill: InstantRateLimitRefill?
    for entry in entries {
      switch entry.key {
      case "capacity":
        capacity = try ObjectEntryParser.parseIntExpression(entry.value)

      case "refill":
        refill = try parseRateLimitRefill(name: name, expression: entry.value)

      default:
        throw TypeScriptPermissionsParseError.unsupportedRuleKey(
          context: "$rateLimits.\(name).limit",
          key: entry.key
        )
      }
    }

    guard let capacity else {
      throw TypeScriptPermissionsParseError.unsupportedRuleKey(
        context: "$rateLimits.\(name).limit",
        key: "capacity"
      )
    }
    return InstantRateLimitLimit(capacity: capacity, refill: refill)
  }

  private func parseRateLimitRefill(
    name: String,
    expression: String
  ) throws -> InstantRateLimitRefill {
    let body = try ObjectEntryParser.extractFirstObjectBody(
      from: expression,
      context: "$rateLimits.\(name).limit.refill"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: body)

    var amount: Int?
    var period: String?
    var type: InstantRateLimitRefillType?

    for entry in entries {
      switch entry.key {
      case "amount":
        amount = try ObjectEntryParser.parseIntExpression(entry.value)

      case "period":
        period = try ObjectEntryParser.parseStringExpression(entry.value)

      case "type":
        let value = try ObjectEntryParser.parseStringExpression(entry.value)
        guard let parsed = InstantRateLimitRefillType(rawValue: value) else {
          throw TypeScriptPermissionsParseError.unsupportedRuleValue(
            context: "$rateLimits.\(name).limit.refill",
            key: entry.key,
            value: value
          )
        }
        type = parsed

      default:
        throw TypeScriptPermissionsParseError.unsupportedRuleKey(
          context: "$rateLimits.\(name).limit.refill",
          key: entry.key
        )
      }
    }

    return InstantRateLimitRefill(amount: amount, period: period, type: type)
  }
}

private struct ParsedRuleBlock {
  var allow: [InstantPermissionAction: String]
  var link: [String: String]
  var unlink: [String: String]
  var bind: [InstantPermissionBinding]
  var fields: [String: String]
}

private struct ParsedAllowBlock {
  var allow: [InstantPermissionAction: String]
  var link: [String: String]
  var unlink: [String: String]
}

extension InstantRoomSchema {
  fileprivate var normalized: Self {
    InstantRoomSchema(
      name: name,
      presence: presence.normalized,
      topics: topics
        .map { $0.normalized }
        .sorted { $0.name < $1.name }
    )
  }
}

extension InstantRoomTopicSchema {
  fileprivate var normalized: Self {
    InstantRoomTopicSchema(
      name: name,
      payload: payload.normalized
    )
  }
}

extension InstantRoomPayloadSchema {
  fileprivate var normalized: Self {
    InstantRoomPayloadSchema(
      attributes: attributes.sorted { $0.name < $1.name }
    )
  }
}

extension [ObjectEntryParser.Entry] {
  fileprivate func lastValue(for key: String) -> String? {
    self.reversed().first { $0.key == key }?.value
  }
}

private enum ObjectEntryParser {
  fileprivate struct Entry: Sendable {
    var key: String
    var value: String
  }

  fileprivate static func parseObjectEntries(in source: String) throws -> [Entry] {
    var entries: [Entry] = []
    var index = source.startIndex

    while true {
      skipTrivia(in: source, index: &index)
      guard index < source.endIndex else { break }

      if source[index] == "," {
        source.formIndex(after: &index)
        continue
      }
      if source[index] == "}" {
        break
      }

      let key = try parsePropertyKey(in: source, index: &index)
      skipTrivia(in: source, index: &index)
      guard index < source.endIndex, source[index] == ":" else {
        throw TypeScriptSchemaParseError.malformedObject("Expected ':' after key '\(key)'.")
      }
      source.formIndex(after: &index)
      skipTrivia(in: source, index: &index)

      let valueStart = index
      try advancePastValue(in: source, index: &index)
      let value = try stripComments(in: String(source[valueStart..<index]))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      entries.append(Entry(key: key, value: value))

      skipTrivia(in: source, index: &index)
      if index < source.endIndex, source[index] == "," {
        source.formIndex(after: &index)
      }
    }

    return entries
  }

  fileprivate static func firstOccurrence(
    of needle: String,
    in source: String
  ) throws -> Range<String.Index>? {
    var index = source.startIndex
    while index < source.endIndex {
      if source[index] == "\"" || source[index] == "'" {
        _ = try parseStringLiteral(in: source, index: &index)
        continue
      }

      if try skipComment(in: source, index: &index) {
        continue
      }

      if source[index...].hasPrefix(needle) {
        let end = source.index(index, offsetBy: needle.count)
        return index..<end
      }

      source.formIndex(after: &index)
    }

    return nil
  }

  fileprivate static func extractFirstObjectBody(
    from source: String,
    context: String
  ) throws -> String {
    guard let open = source.firstIndex(of: "{") else {
      throw TypeScriptSchemaParseError.malformedObject("Expected object body for '\(context)'.")
    }
    let close = try matchingBrace(in: source, open: open)
    return String(source[source.index(after: open)..<close])
  }

  fileprivate static func isExactObjectExpression(_ source: String) throws -> Bool {
    var index = source.startIndex
    skipTrivia(in: source, index: &index)
    guard index < source.endIndex, source[index] == "{" else { return false }
    let close = try matchingBrace(in: source, open: index)
    index = source.index(after: close)
    skipTrivia(in: source, index: &index)
    return index == source.endIndex
  }

  fileprivate static func isExactEntityExpression(_ source: String) throws -> Bool {
    var index = source.startIndex
    skipTrivia(in: source, index: &index)
    guard index < source.endIndex else { return false }
    guard source[index...].hasPrefix("i.entity(") else { return false }
    index = source.index(index, offsetBy: "i.entity(".count)
    skipTrivia(in: source, index: &index)
    guard index < source.endIndex, source[index] == "{" else { return false }
    let close = try matchingBrace(in: source, open: index)
    index = source.index(after: close)
    skipTrivia(in: source, index: &index)
    guard index < source.endIndex, source[index] == ")" else { return false }
    source.formIndex(after: &index)
    skipTrivia(in: source, index: &index)
    return index == source.endIndex
  }

  fileprivate static func parseArrayValues(
    _ source: String,
    context: String
  ) throws -> [String] {
    let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let open = source.firstIndex(of: "[") else {
      throw TypeScriptSchemaParseError.malformedObject("Expected array body for '\(context)'.")
    }
    let close = try matchingBracket(in: source, open: open)
    let body = String(source[source.index(after: open)..<close])

    var values: [String] = []
    var index = body.startIndex
    while true {
      skipTrivia(in: body, index: &index)
      guard index < body.endIndex else { break }

      if body[index] == "," {
        body.formIndex(after: &index)
        continue
      }

      let valueStart = index
      try advancePastValue(in: body, index: &index)
      let value = try stripComments(in: String(body[valueStart..<index]))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !value.isEmpty {
        values.append(value)
      }

      skipTrivia(in: body, index: &index)
      if index < body.endIndex, body[index] == "," {
        body.formIndex(after: &index)
      }
    }

    return values
  }

  fileprivate static func parseStringExpression(_ source: String) throws -> String {
    var index = source.startIndex
    skipTrivia(in: source, index: &index)
    guard index < source.endIndex, source[index] == "\"" || source[index] == "'"
    else {
      throw TypeScriptSchemaParseError.malformedObject("Expected string literal.")
    }

    let value = try parseStringLiteral(in: source, index: &index)
    skipTrivia(in: source, index: &index)
    guard index == source.endIndex else {
      throw TypeScriptSchemaParseError.malformedObject("Expected end of string literal.")
    }
    return value
  }

  fileprivate static func parseIntExpression(_ source: String) throws -> Int {
    let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let int = Int(value) else {
      throw TypeScriptSchemaParseError.malformedObject("Expected integer literal.")
    }
    return int
  }

  fileprivate static func parseBoolExpression(_ source: String) throws -> Bool {
    var index = source.startIndex
    skipTrivia(in: source, index: &index)
    guard index < source.endIndex else {
      throw TypeScriptSchemaParseError.malformedObject("Expected boolean literal.")
    }
    if source[index...].hasPrefix("true") {
      let end = source.index(index, offsetBy: "true".count)
      index = end
      skipTrivia(in: source, index: &index)
      guard index == source.endIndex else {
        throw TypeScriptSchemaParseError.malformedObject("Expected end of boolean literal.")
      }
      return true
    }
    if source[index...].hasPrefix("false") {
      let end = source.index(index, offsetBy: "false".count)
      index = end
      skipTrivia(in: source, index: &index)
      guard index == source.endIndex else {
        throw TypeScriptSchemaParseError.malformedObject("Expected end of boolean literal.")
      }
      return false
    }
    throw TypeScriptSchemaParseError.malformedObject("Expected boolean literal.")
  }

  private static func parsePropertyKey(
    in source: String,
    index: inout String.Index
  ) throws -> String {
    guard index < source.endIndex else {
      throw TypeScriptSchemaParseError.malformedObject("Unexpected end of object.")
    }

    if source[index] == "\"" || source[index] == "'" {
      return try parseStringLiteral(in: source, index: &index)
    }

    let start = index
    while index < source.endIndex {
      let character = source[index]
      if character == ":" || character.isWhitespace {
        break
      }
      if character == "," || character == "{" || character == "}" {
        throw TypeScriptSchemaParseError.malformedObject("Expected property key.")
      }
      source.formIndex(after: &index)
    }

    guard start < index else {
      throw TypeScriptSchemaParseError.malformedObject("Expected property key.")
    }
    return String(source[start..<index])
  }

  private static func parseStringLiteral(
    in source: String,
    index: inout String.Index
  ) throws -> String {
    let delimiter = source[index]
    source.formIndex(after: &index)

    var result = ""
    while index < source.endIndex {
      let character = source[index]
      source.formIndex(after: &index)

      if character == delimiter {
        return result
      }

      if character == "\\" {
        guard index < source.endIndex else {
          throw TypeScriptSchemaParseError.malformedObject("Unterminated string escape.")
        }
        let escaped = source[index]
        source.formIndex(after: &index)
        switch escaped {
        case "n":
          result.append("\n")
        case "r":
          result.append("\r")
        case "t":
          result.append("\t")
        default:
          result.append(escaped)
        }
      } else {
        result.append(character)
      }
    }

    throw TypeScriptSchemaParseError.malformedObject("Unterminated string literal.")
  }

  private static func advancePastValue(
    in source: String,
    index: inout String.Index
  ) throws {
    var parenDepth = 0
    var braceDepth = 0
    var bracketDepth = 0

    while index < source.endIndex {
      let character = source[index]

      if character == "\"" || character == "'" {
        _ = try parseStringLiteral(in: source, index: &index)
        continue
      }

      if character == "/" {
        if try skipComment(in: source, index: &index) {
          continue
        }
      }

      switch character {
      case "(":
        parenDepth += 1
      case ")":
        if parenDepth > 0 {
          parenDepth -= 1
        }
      case "{":
        braceDepth += 1
      case "}":
        if braceDepth == 0, parenDepth == 0, bracketDepth == 0 {
          return
        }
        braceDepth -= 1
      case "[":
        bracketDepth += 1
      case "]":
        if bracketDepth > 0 {
          bracketDepth -= 1
        }
      case ",":
        if parenDepth == 0, braceDepth == 0, bracketDepth == 0 {
          return
        }
      default:
        break
      }

      source.formIndex(after: &index)
    }
  }

  private static func stripComments(in source: String) throws -> String {
    var result = ""
    var index = source.startIndex

    while index < source.endIndex {
      let character = source[index]

      if character == "\"" || character == "'" {
        let start = index
        _ = try parseStringLiteral(in: source, index: &index)
        result += source[start..<index]
        continue
      }

      if character == "/" {
        if try skipComment(in: source, index: &index) {
          continue
        }
      }

      result.append(character)
      source.formIndex(after: &index)
    }

    return result
  }

  fileprivate static func matchingBrace(
    in source: String,
    open: String.Index
  ) throws -> String.Index {
    var index = source.index(after: open)
    var depth = 1

    while index < source.endIndex {
      let character = source[index]

      if character == "\"" || character == "'" {
        _ = try parseStringLiteral(in: source, index: &index)
        continue
      }

      if character == "{" {
        depth += 1
      } else if character == "}" {
        depth -= 1
        if depth == 0 {
          return index
        }
      }

      source.formIndex(after: &index)
    }

    throw TypeScriptSchemaParseError.malformedObject("Unbalanced braces.")
  }

  private static func matchingBracket(
    in source: String,
    open: String.Index
  ) throws -> String.Index {
    var index = source.index(after: open)
    var depth = 1

    while index < source.endIndex {
      let character = source[index]

      if character == "\"" || character == "'" {
        _ = try parseStringLiteral(in: source, index: &index)
        continue
      }

      if try skipComment(in: source, index: &index) {
        continue
      }

      if character == "[" {
        depth += 1
      } else if character == "]" {
        depth -= 1
        if depth == 0 {
          return index
        }
      }

      source.formIndex(after: &index)
    }

    throw TypeScriptSchemaParseError.malformedObject("Unbalanced brackets.")
  }

  fileprivate static func skipTrivia(in source: String, index: inout String.Index) {
    while index < source.endIndex {
      if source[index].isWhitespace {
        source.formIndex(after: &index)
        continue
      }

      if source[index] == "/" {
        if (try? skipComment(in: source, index: &index)) == true {
          continue
        }
      }

      break
    }
  }

  private static func skipComment(
    in source: String,
    index: inout String.Index
  ) throws -> Bool {
    guard index < source.endIndex, source[index] == "/" else { return false }

    let next = source.index(after: index)
    guard next < source.endIndex else { return false }

    if source[next] == "/" {
      index = source.index(after: next)
      while index < source.endIndex, source[index] != "\n" {
        source.formIndex(after: &index)
      }
      return true
    }

    if source[next] == "*" {
      index = source.index(after: next)
      while index < source.endIndex {
        if source[index] == "*" {
          let slash = source.index(after: index)
          if slash < source.endIndex, source[slash] == "/" {
            index = source.index(after: slash)
            return true
          }
        }
        source.formIndex(after: &index)
      }
      throw TypeScriptSchemaParseError.malformedObject("Unterminated block comment.")
    }

    return false
  }
}
