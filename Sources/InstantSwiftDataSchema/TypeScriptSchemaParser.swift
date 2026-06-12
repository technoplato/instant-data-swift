import Foundation
import InstantSwiftDataCore

public struct ParsedInstantEntitySchema: Hashable, Codable, Sendable, Identifiable {
  public var id: String { namespace }
  public var namespace: String
  public var attributes: [InstantAttribute]

  public init(namespace: String, attributes: [InstantAttribute]) {
    self.namespace = namespace
    self.attributes = attributes.sorted { $0.name < $1.name }
  }

  public init(_ schema: InstantEntitySchema) {
    self.init(namespace: schema.namespace, attributes: schema.attributes)
  }
}

public enum TypeScriptSchemaParseError: Error, Equatable, Sendable, CustomStringConvertible {
  case missingEntitiesObject
  case malformedObject(String)
  case unsupportedTopLevelKey(String)
  case unsupportedEntityExpression(namespace: String, expression: String)
  case unsupportedAttributeExpression(namespace: String, attribute: String, expression: String)

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
    }
  }
}

public struct TypeScriptSchemaParser: Sendable {
  public init() {}

  public func parse(_ source: String) throws -> [ParsedInstantEntitySchema] {
    guard let schemaCall = try ObjectEntryParser.firstOccurrence(of: "i.schema(", in: source)
    else {
      throw TypeScriptSchemaParseError.missingEntitiesObject
    }
    let schemaBody = try ObjectEntryParser.extractFirstObjectBody(
      from: String(source[schemaCall.upperBound...]),
      context: "schema"
    )
    let entries = try ObjectEntryParser.parseObjectEntries(in: schemaBody)
    for entry in entries where entry.key != "entities" {
      throw TypeScriptSchemaParseError.unsupportedTopLevelKey(entry.key)
    }
    guard let entitiesExpression = entries.first(where: { $0.key == "entities" })?.value
    else {
      throw TypeScriptSchemaParseError.missingEntitiesObject
    }

    let entitiesBody = try ObjectEntryParser.extractFirstObjectBody(
      from: entitiesExpression,
      context: "entities"
    )

    return try ObjectEntryParser.parseObjectEntries(in: entitiesBody)
      .map { entity in
        try parseEntity(namespace: entity.key, expression: entity.value)
      }
      .sorted { $0.namespace < $1.namespace }
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
      isIndexed: parsedExpression.isIndexed,
      isUnique: parsedExpression.isUnique
    )
  }
}

private struct ParsedAttributeExpression {
  var valueType: InstantValueType
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
      ("i.any()", .ref),
    ]

    guard let scalar = scalarPrefixes.first(where: { scalarString.hasPrefix($0.0) })
    else { return nil }

    self.valueType = scalar.1
    self.isIndexed = false
    self.isUnique = false

    var remainder = String(scalarString.dropFirst(scalar.0.count))
    while !remainder.isEmpty {
      if remainder.hasPrefix(".indexed()") {
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

  private static func matchingBrace(
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

  private static func skipTrivia(in source: String, index: inout String.Index) {
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
