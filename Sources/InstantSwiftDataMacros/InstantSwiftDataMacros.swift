import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct InstantSwiftDataMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    InstantEntityMacro.self
  ]
}

public struct InstantEntityMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let typeName = declaration.instantTypeName else {
      context.diagnose(
        InstantEntityDiagnostic.requiresNominalType.diagnose(at: Syntax(declaration))
      )
      return []
    }

    let defaultNamespace = InstantEntityMacro.defaultNamespace(for: typeName)
    let namespace = explicitNamespace(from: node) ?? defaultNamespace

    if explicitNamespace(from: node) == defaultNamespace {
      context.diagnose(
        InstantEntityDiagnostic.redundantNamespace(defaultNamespace)
          .diagnose(at: Syntax(node))
      )
    }

    return [
      """
      public static var instantNamespace: String {
        "\(raw: namespace)"
      }
      """
    ]
  }

  private static func explicitNamespace(from node: AttributeSyntax) -> String? {
    guard case let .argumentList(arguments) = node.arguments,
      let expression = arguments.first?.expression.as(StringLiteralExprSyntax.self)
    else { return nil }

    return expression.representedLiteralValue
  }

  private static func defaultNamespace(for typeName: String) -> String {
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
}

private extension DeclGroupSyntax {
  var instantTypeName: String? {
    if let declaration = self.as(StructDeclSyntax.self) {
      return declaration.name.text
    }
    if let declaration = self.as(ClassDeclSyntax.self) {
      return declaration.name.text
    }
    if let declaration = self.as(ActorDeclSyntax.self) {
      return declaration.name.text
    }
    return nil
  }
}

private enum InstantEntityDiagnostic {
  case redundantNamespace(String)
  case requiresNominalType

  func diagnose(at node: Syntax) -> Diagnostic {
    Diagnostic(node: node, message: self)
  }
}

extension InstantEntityDiagnostic: DiagnosticMessage {
  var message: String {
    switch self {
    case let .redundantNamespace(namespace):
      return #"@InstantEntity("\#(namespace)") is redundant; omit the argument to use the default namespace."#
    case .requiresNominalType:
      return "@InstantEntity can only be attached to a struct, class, or actor."
    }
  }

  var diagnosticID: MessageID {
    switch self {
    case .redundantNamespace:
      return MessageID(domain: "InstantSwiftDataMacros", id: "redundantNamespace")
    case .requiresNominalType:
      return MessageID(domain: "InstantSwiftDataMacros", id: "requiresNominalType")
    }
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .redundantNamespace:
      return .warning
    case .requiresNominalType:
      return .error
    }
  }
}
