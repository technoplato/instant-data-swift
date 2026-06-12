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

public struct TypeScriptSchemaPrinter: Sendable {
  public init() {}

  public func printSchema(_ entities: [InstantEntitySchema]) -> String {
    var lines: [String] = [
      "import { i } from '@instantdb/core';",
      "",
      "export default i.schema({",
      "  entities: {",
    ]

    for entity in entities.sorted(by: { $0.namespace < $1.namespace }) {
      lines.append("    \(propertyKey(entity.namespace)): i.entity({")
      for attribute in entity.attributes.sorted(by: { $0.name < $1.name }) {
        lines.append("      \(propertyKey(attribute.name)): \(typeExpression(for: attribute)),")
      }
      lines.append("    }),")
    }

    lines.append(contentsOf: [
      "  },",
      "});",
      "",
    ])

    return lines.joined(separator: "\n")
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
      case .ref:
        "i.any()"
      }

    var expression = scalar
    if attribute.isIndexed {
      expression += ".indexed()"
    }
    if attribute.isUnique {
      expression += ".unique()"
    }
    return expression
  }

  private func propertyKey(_ key: String) -> String {
    guard isIdentifier(key), !reservedWords.contains(key) else {
      return String(reflecting: key)
    }
    return key
  }

  private func isIdentifier(_ key: String) -> Bool {
    guard let first = key.unicodeScalars.first,
      CharacterSet(charactersIn: "_$").contains(first)
        || CharacterSet.letters.contains(first)
    else { return false }

    return key.unicodeScalars.dropFirst().allSatisfy {
      CharacterSet(charactersIn: "_$").contains($0)
        || CharacterSet.alphanumerics.contains($0)
    }
  }

  private var reservedWords: Set<String> {
    [
      "break", "case", "catch", "class", "const", "continue", "debugger", "default",
      "delete", "do", "else", "export", "extends", "finally", "for", "function", "if",
      "import", "in", "instanceof", "new", "return", "super", "switch", "this", "throw",
      "try", "typeof", "var", "void", "while", "with", "yield",
    ]
  }
}
