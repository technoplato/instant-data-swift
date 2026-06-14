import Foundation
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
    let explicitNamespace = explicitNamespace(from: node)
    let namespace: String
    switch explicitNamespace {
    case .none:
      namespace = defaultNamespace
    case let .namespace(value):
      namespace = value
    case .unsupported:
      context.diagnose(
        InstantEntityDiagnostic.unsupportedNamespaceArgument.diagnose(at: Syntax(node))
      )
      return []
    }

    if namespace == defaultNamespace, case .namespace = explicitNamespace {
      context.diagnose(
        InstantEntityDiagnostic.redundantNamespace(defaultNamespace)
          .diagnose(at: Syntax(node))
      )
    }

    var members: [DeclSyntax] = [
      """
      public static var instantNamespace: String {
        "\(raw: namespace)"
      }
      """
    ]
    let explicitStaticMembers = staticMemberNames(in: declaration)
    let properties = storedProperties(in: declaration, context: context)
    let reservedProperties = properties.filter { property in
      isGeneratedSchemaHelper(property)
        && reservedGeneratedMemberNames.contains(property.name)
    }
    for property in reservedProperties {
      context.diagnose(
        InstantEntityDiagnostic.reservedGeneratedMemberName(property.name)
          .diagnose(at: Syntax(declaration))
      )
    }
    let reservedPropertyNames = Set(reservedProperties.map(\.name))
    members.append(
      contentsOf: attributePathDeclarations(
        properties: properties,
        typeName: typeName,
        explicitStaticMembers: explicitStaticMembers,
        reservedPropertyNames: reservedPropertyNames
      )
    )
    if !explicitStaticMembers.contains("instantAttributes") {
      members.append(
        instantAttributesDeclaration(
          properties: properties,
          typeName: typeName,
          reservedPropertyNames: reservedPropertyNames
        )
      )
    }
    if let draft = draftDeclaration(
      properties: properties,
      typeName: typeName,
      reservedPropertyNames: reservedPropertyNames
    ) {
      members.append(draft)
    }
    return members
  }

  private static func attributePathDeclarations(
    properties: [StoredProperty],
    typeName: String,
    explicitStaticMembers: Set<String>,
    reservedPropertyNames: Set<String>
  ) -> [DeclSyntax] {
    properties
      .filter { property in
        isGeneratedSchemaHelper(property)
          && !explicitStaticMembers.contains(property.name)
          && !reservedPropertyNames.contains(property.name)
      }
      .map { property in
        DeclSyntax(
          stringLiteral: """
          public static let \(property.name) = InstantAttributePath<\(typeName), \(property.type)>("\(property.name)")
          """
        )
      }
  }

  private static func instantAttributesDeclaration(
    properties: [StoredProperty],
    typeName: String,
    reservedPropertyNames: Set<String>
  ) -> DeclSyntax {
    let attributes = properties
      .filter { property in
        isGeneratedSchemaHelper(property)
          && !reservedPropertyNames.contains(property.name)
      }
      .map { property in
        property.instantAttributeLiteral(typeName: typeName)
      }
      .joined(separator: ",\n")

    return DeclSyntax(
      stringLiteral: """
      public static var instantAttributes: [InstantAttribute] {
        [
      \(attributes)
        ]
      }
      """
    )
  }

  private static func isGeneratedSchemaHelper(_ property: StoredProperty) -> Bool {
    property.name != "id"
      && property.isWritable
      && property.schemaValue != nil
  }

  private static func draftDeclaration(
    properties: [StoredProperty],
    typeName: String,
    reservedPropertyNames: Set<String>
  ) -> DeclSyntax? {
    guard properties.contains(where: { $0.name == "id" }) else {
      return nil
    }

    let draftProperties = properties.filter { property in
      isGeneratedSchemaHelper(property)
        && !reservedPropertyNames.contains(property.name)
    }
    let declarations = draftProperties.map { property in
      "  public var \(property.name): \(property.type)"
    }.joined(separator: "\n")
    let memberwiseParameters = (
      ["id: \(typeName).ID? = nil"]
        + draftProperties.map { property in
          let defaultValue: String
          if let propertyDefaultValue = property.defaultValue {
            defaultValue = " = \(propertyDefaultValue)"
          } else if property.isOptional {
            defaultValue = " = nil"
          } else {
            defaultValue = ""
          }
          return "\(property.name): \(property.type)\(defaultValue)"
        }
    ).joined(separator: ",\n    ")
    let memberwiseAssignments = (
      ["    self.id = id"]
        + draftProperties.map { "    self.\($0.name) = \($0.name)" }
    ).joined(separator: "\n")
    let entityAssignments = (
      ["    self.id = entity.id"]
        + draftProperties.map { "    self.\($0.name) = entity.\($0.name)" }
    ).joined(separator: "\n")
    let instantAssignments = draftProperties.map { property in
      """
          InstantAttributeAssignment<\(typeName)>(
            name: "\(property.name)",
            attributeID: \(typeName).instantAttributes
              .first(where: { $0.name == "\(property.name)" })?.id
              ?? \(typeName).instantNamespace + "/\(property.name)",
            value: self.\(property.name).instantValue
          )
      """
    }.joined(separator: ",\n")

    return DeclSyntax(
      stringLiteral: """
      public struct Draft: InstantEntityDraft {
        public typealias Entity = \(typeName)
        public var id: \(typeName).ID? = nil
      \(declarations.isEmpty ? "" : "\n\(declarations)")

        public init(
          \(memberwiseParameters)
        ) {
      \(memberwiseAssignments)
        }

        public init(_ entity: \(typeName)) {
      \(entityAssignments)
        }

        public var instantAssignments: [InstantAttributeAssignment<\(typeName)>] {
          [
      \(instantAssignments)
          ]
        }
      }
      """
    )
  }

  private static func storedProperties(
    in declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
  ) -> [StoredProperty] {
    declaration.memberBlock.members.compactMap { member in
      guard let variable = member.decl.as(VariableDeclSyntax.self),
        !variable.modifiers.contains(where: { modifier in
          modifier.name.tokenKind == .keyword(.static)
            || modifier.name.tokenKind == .keyword(.class)
        })
      else { return nil }

      let isWritable = variable.bindingSpecifier.tokenKind == .keyword(.var)

      guard variable.bindings.count == 1, let binding = variable.bindings.first else {
        if !isWritable {
          return nil
        }
        context.diagnose(
          InstantEntityDiagnostic.requiresSingleDraftPropertyBinding
            .diagnose(at: Syntax(variable))
        )
        return nil
      }

      guard binding.accessorBlock == nil,
        let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
      else { return nil }

      guard isWritable || pattern.identifier.text == "id" else {
        return nil
      }

      let type = binding.typeAnnotation?.type.description.trimmed
        ?? inferredType(from: binding.initializer?.value)
      guard let type else {
        context.diagnose(
          InstantEntityDiagnostic.requiresDraftTypeAnnotation(pattern.identifier.text)
            .diagnose(at: Syntax(binding.pattern))
        )
        return nil
      }

      return StoredProperty(
        name: pattern.identifier.text,
        type: type,
        isWritable: isWritable,
        isOptional: binding.typeAnnotation?.type.isInstantOptionalType ?? false,
        defaultValue: binding.initializer?.value.description.trimmed,
        schemaValue: InstantSchemaValue(type: type)
      )
    }
  }

  private static func staticMemberNames(in declaration: some DeclGroupSyntax) -> Set<String> {
    Set(
      declaration.memberBlock.members.flatMap { member -> [String] in
        guard let variable = member.decl.as(VariableDeclSyntax.self),
          variable.modifiers.contains(where: { modifier in
            modifier.name.tokenKind == .keyword(.static)
              || modifier.name.tokenKind == .keyword(.class)
          })
        else { return [] }

        return variable.bindings.compactMap { binding in
          binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        }
      }
    )
  }

  private static func inferredType(from expression: ExprSyntax?) -> String? {
    guard let expression else { return nil }
    if expression.is(BooleanLiteralExprSyntax.self) {
      return "Bool"
    }
    if expression.is(StringLiteralExprSyntax.self) {
      return "String"
    }
    if expression.is(IntegerLiteralExprSyntax.self) {
      return "Int"
    }
    if expression.is(FloatLiteralExprSyntax.self) {
      return "Double"
    }
    return nil
  }

  private static func explicitNamespace(from node: AttributeSyntax) -> ExplicitNamespace {
    guard case let .argumentList(arguments) = node.arguments,
      let argument = arguments.first
    else { return .none }

    guard arguments.count == 1,
      let expression = argument.expression.as(StringLiteralExprSyntax.self),
      let value = expression.representedLiteralValue
    else { return .unsupported }

    return .namespace(value)
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

  private static let reservedGeneratedMemberNames: Set<String> = [
    "Draft",
    "create",
    "decode",
    "delete",
    "instantAttributes",
    "instantNamespace",
    "merge",
    "query",
    "ruleParams",
    "update",
    "updateExisting",
  ]
}

private enum ExplicitNamespace {
  case none
  case namespace(String)
  case unsupported
}

private struct StoredProperty {
  var name: String
  var type: String
  var isWritable: Bool
  var isOptional: Bool
  var defaultValue: String?
  var schemaValue: InstantSchemaValue?

  func instantAttributeLiteral(typeName: String) -> String {
    guard let schemaValue else {
      preconditionFailure("Cannot generate an InstantAttribute for an unsupported schema value.")
    }

    var arguments = [
      "      InstantAttribute(",
      "        id: \(typeName).\(name).attributeID,",
      "        namespace: \(typeName).instantNamespace,",
      "        name: \(typeName).\(name).name,",
      "        valueType: \(schemaValue.valueTypeLiteral),",
      "        isRequired: \(schemaValue.isOptional ? "false" : "true"),",
      "        isIndexed: true",
    ]
    if let targetType = schemaValue.refTargetType {
      arguments[arguments.count - 1] += ","
      arguments += [
        "        isUnique: false,",
        "        forwardIdentity: nil,",
        "        reverseIdentity: nil,",
        "        primaryKey: false,",
        "        linkNamespace: \(targetType).instantNamespace",
      ]
    }
    arguments.append("      )")
    return arguments.joined(separator: "\n")
  }
}

private struct InstantSchemaValue {
  var valueTypeLiteral: String
  var refTargetType: String?
  var isOptional: Bool

  init?(type rawType: String) {
    let normalizedType = rawType.removingWhitespace
    let (type, isOptional) = normalizedType.unwrappedOptionalType()
    self.isOptional = isOptional
    self.refTargetType = nil

    switch type {
    case "String":
      self.valueTypeLiteral = ".string"
    case "Bool":
      self.valueTypeLiteral = ".boolean"
    case "Date", "InstantTimestamp":
      self.valueTypeLiteral = ".date"
    case "Double", "Float", "Int", "Int64":
      self.valueTypeLiteral = ".number"
    case "JSONValue":
      self.valueTypeLiteral = ".json"
    case "AnyInstantID":
      self.valueTypeLiteral = ".ref"
    default:
      guard let target = type.instantIDTargetType else { return nil }
      self.valueTypeLiteral = ".ref"
      self.refTargetType = target
    }
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

private extension TypeSyntax {
  var isInstantOptionalType: Bool {
    if self.is(OptionalTypeSyntax.self) || self.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
      return true
    }

    if let identifier = self.as(IdentifierTypeSyntax.self) {
      return identifier.name.text == "Optional"
        && identifier.genericArgumentClause?.arguments.count == 1
    }

    if let member = self.as(MemberTypeSyntax.self) {
      return member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift"
        && member.name.text == "Optional"
        && member.genericArgumentClause?.arguments.count == 1
    }

    return false
  }
}

private extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var removingWhitespace: String {
    filter { !$0.isWhitespace }
  }

  var instantIDTargetType: String? {
    guard hasPrefix("InstantID<"), hasSuffix(">") else { return nil }
    let target = dropFirst("InstantID<".count).dropLast()
    guard !target.isEmpty else { return nil }
    return String(target)
  }

  func unwrappedOptionalType() -> (type: String, isOptional: Bool) {
    if hasSuffix("?") {
      return (String(dropLast()), true)
    }

    if hasPrefix("Optional<"), hasSuffix(">") {
      return (String(dropFirst("Optional<".count).dropLast()), true)
    }

    if hasPrefix("Swift.Optional<"), hasSuffix(">") {
      return (String(dropFirst("Swift.Optional<".count).dropLast()), true)
    }

    return (self, false)
  }
}

private enum InstantEntityDiagnostic {
  case reservedGeneratedMemberName(String)
  case redundantNamespace(String)
  case requiresDraftTypeAnnotation(String)
  case requiresNominalType
  case requiresSingleDraftPropertyBinding
  case unsupportedNamespaceArgument

  func diagnose(at node: Syntax) -> Diagnostic {
    Diagnostic(node: node, message: self)
  }
}

extension InstantEntityDiagnostic: DiagnosticMessage {
  var message: String {
    switch self {
    case let .reservedGeneratedMemberName(name):
      return "Stored property '\(name)' uses a name reserved by @InstantEntity generated helpers."
    case let .redundantNamespace(namespace):
      return #"@InstantEntity("\#(namespace)") is redundant; omit the argument to use the default namespace."#
    case let .requiresDraftTypeAnnotation(name):
      return "Stored property '\(name)' needs an explicit type annotation for @InstantEntity draft generation."
    case .requiresNominalType:
      return "@InstantEntity can only be attached to a struct, class, or actor."
    case .requiresSingleDraftPropertyBinding:
      return "@InstantEntity draft generation requires one stored property per var declaration."
    case .unsupportedNamespaceArgument:
      return "@InstantEntity namespace overrides must be string literals."
    }
  }

  var diagnosticID: MessageID {
    switch self {
    case .reservedGeneratedMemberName:
      return MessageID(domain: "InstantSwiftDataMacros", id: "reservedGeneratedMemberName")
    case .redundantNamespace:
      return MessageID(domain: "InstantSwiftDataMacros", id: "redundantNamespace")
    case .requiresDraftTypeAnnotation:
      return MessageID(domain: "InstantSwiftDataMacros", id: "requiresDraftTypeAnnotation")
    case .requiresNominalType:
      return MessageID(domain: "InstantSwiftDataMacros", id: "requiresNominalType")
    case .requiresSingleDraftPropertyBinding:
      return MessageID(domain: "InstantSwiftDataMacros", id: "requiresSingleDraftPropertyBinding")
    case .unsupportedNamespaceArgument:
      return MessageID(domain: "InstantSwiftDataMacros", id: "unsupportedNamespaceArgument")
    }
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .reservedGeneratedMemberName,
      .requiresDraftTypeAnnotation,
      .requiresNominalType,
      .requiresSingleDraftPropertyBinding,
      .unsupportedNamespaceArgument:
      return .error
    case .redundantNamespace:
      return .warning
    }
  }
}
