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

public struct InstantPermissionsDocument: Hashable, Codable, Sendable {
  public var namespaces: [InstantNamespacePermissions]

  public init(namespaces: [InstantNamespacePermissions]) {
    self.namespaces = namespaces
  }
}

public struct InstantNamespacePermissions: Hashable, Codable, Sendable, Identifiable {
  public var id: String { namespace }
  public var namespace: String
  public var allow: [InstantPermissionAction: String]
  public var bind: [InstantPermissionBinding]

  public init(
    namespace: String,
    allow: [InstantPermissionAction: String] = [:],
    bind: [InstantPermissionBinding] = []
  ) {
    self.namespace = namespace
    self.allow = allow
    self.bind = bind
  }

  public static func allowAll(namespace: String) -> Self {
    Self(
      namespace: namespace,
      allow: Dictionary(
        uniqueKeysWithValues: InstantPermissionAction.allCases.map { ($0, "true") }
      )
    )
  }
}

public enum InstantPermissionAction: String, CaseIterable, Codable, Sendable {
  case view
  case create
  case update
  case delete
}

public struct InstantPermissionBinding: Hashable, Codable, Sendable {
  public var name: String
  public var expression: String

  public init(_ name: String, _ expression: String) {
    self.name = name
    self.expression = expression
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

  public static let todoPermissions = InstantPermissionsDocument(
    namespaces: [
      .allowAll(namespace: TodoExample.namespace)
    ]
  )
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
      lines.append("    \(TypeScriptPrinterSupport.propertyKey(entity.namespace)): i.entity({")
      for attribute in entity.attributes.sorted(by: { $0.name < $1.name }) {
        lines.append(
          "      \(TypeScriptPrinterSupport.propertyKey(attribute.name)): \(typeExpression(for: attribute)),"
        )
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

  public func printPermissions(_ document: InstantPermissionsDocument) -> String {
    var lines: [String] = [
      "// Docs: https://www.instantdb.com/docs/permissions",
      "",
      "import type { InstantRules } from \(TypeScriptPrinterSupport.stringLiteral(package.rawValue));",
      "",
      "const rules = {",
    ]

    for namespace in document.namespaces.sorted(by: { $0.namespace < $1.namespace }) {
      lines.append("  \(TypeScriptPrinterSupport.propertyKey(namespace.namespace)): {")
      if namespace.allow.isEmpty {
        lines.append("    allow: {},")
      } else {
        lines.append("    allow: {")
        for action in InstantPermissionAction.allCases {
          guard let expression = namespace.allow[action] else { continue }
          lines.append(
            "      \(TypeScriptPrinterSupport.propertyKey(action.rawValue)): \(TypeScriptPrinterSupport.stringLiteral(expression)),"
          )
        }
        lines.append("    },")
      }
      if !namespace.bind.isEmpty {
        lines.append("    bind: [")
        for binding in namespace.bind {
          lines.append(
            "      \(TypeScriptPrinterSupport.stringLiteral(binding.name)), \(TypeScriptPrinterSupport.stringLiteral(binding.expression)),"
          )
        }
        lines.append("    ],")
      }
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
