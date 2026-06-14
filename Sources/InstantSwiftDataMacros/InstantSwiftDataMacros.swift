import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct InstantSwiftDataMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    InstantEntityMacro.self,
    InstantRelationMacro.self,
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
    let typeAliases = typeAliases(in: declaration)
    let properties = storedProperties(in: declaration, context: context)
    let invalidRelationProperties = properties.filter { property in
      property.relation != nil && property.schemaValue?.refTargetType == nil
    }
    for property in invalidRelationProperties {
      context.diagnose(
        InstantEntityDiagnostic.instantRelationRequiresRef(property.name)
          .diagnose(at: Syntax(declaration))
      )
    }
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
    let generatedAttributeNames = Set(
      properties
        .filter { property in
          isGeneratedSchemaHelper(property)
            && !explicitStaticMembers.contains(property.name)
            && !reservedPropertyNames.contains(property.name)
        }
        .map(\.name)
    )
    let relationProperties = properties.filter { property in
      property.relation != nil && property.schemaValue?.refTargetType != nil
    }
    let duplicateReverseNames = Set(
      Dictionary(grouping: relationProperties, by: { $0.relation?.reverseName ?? "" })
        .filter { !$0.key.isEmpty && $0.value.count > 1 }
        .keys
    )
    for name in duplicateReverseNames.sorted() {
      context.diagnose(
        InstantEntityDiagnostic.duplicateReverseRelationName(name)
          .diagnose(at: Syntax(declaration))
      )
    }
    for property in relationProperties {
      guard let relation = property.relation else { continue }
      if !relation.reverseName.isSwiftIdentifier {
        context.diagnose(
          InstantEntityDiagnostic.invalidReverseRelationName(relation.reverseName)
            .diagnose(at: Syntax(declaration))
        )
      }
      if reservedGeneratedMemberNames.contains(relation.reverseName) {
        context.diagnose(
          InstantEntityDiagnostic.reservedReverseRelationName(relation.reverseName)
            .diagnose(at: Syntax(declaration))
        )
      }
      if generatedAttributeNames.contains(relation.reverseName) {
        context.diagnose(
          InstantEntityDiagnostic.reverseRelationNameCollidesWithGeneratedMember(
            relation.reverseName
          )
          .diagnose(at: Syntax(declaration))
        )
      }
    }
    members.append(
      contentsOf: attributePathDeclarations(
        properties: properties,
        typeName: typeName,
        explicitStaticMembers: explicitStaticMembers,
        reservedPropertyNames: reservedPropertyNames
      )
    )
    members.append(
      contentsOf: reverseRelationDeclarations(
        properties: properties,
        typeName: typeName,
        explicitStaticMembers: explicitStaticMembers,
        generatedAttributeNames: generatedAttributeNames,
        duplicateReverseNames: duplicateReverseNames
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
      typeAliases: typeAliases,
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

  private static func reverseRelationDeclarations(
    properties: [StoredProperty],
    typeName: String,
    explicitStaticMembers: Set<String>,
    generatedAttributeNames: Set<String>,
    duplicateReverseNames: Set<String>
  ) -> [DeclSyntax] {
    properties.compactMap { property in
      guard
        let relation = property.relation,
        let targetType = property.schemaValue?.refTargetType,
        relation.reverseName.isSwiftIdentifier,
        !explicitStaticMembers.contains(relation.reverseName),
        !reservedGeneratedMemberNames.contains(relation.reverseName),
        !generatedAttributeNames.contains(relation.reverseName),
        !duplicateReverseNames.contains(relation.reverseName)
      else {
        return nil
      }

      return DeclSyntax(
        stringLiteral: """
        public static let `\(relation.reverseName)` = InstantReverseRelation<\(targetType), \(typeName)>(attribute: \(typeName).\(property.name))
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
    typeAliases: [String: String],
    reservedPropertyNames: Set<String>
  ) -> DeclSyntax? {
    guard
      properties.contains(
        where: { isPrimaryKeyProperty($0, typeName: typeName, typeAliases: typeAliases) }
      )
    else {
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

  private static func isPrimaryKeyProperty(
    _ property: StoredProperty,
    typeName: String,
    typeAliases: [String: String]
  ) -> Bool {
    guard property.name == "id" else { return false }

    let instantIDTypes = Set(["InstantID<\(typeName)>", "InstantID<Self>"])
    switch property.type.removingWhitespace {
    case let type where instantIDTypes.contains(type):
      return true
    case "\(typeName).ID", "Self.ID", "ID":
      guard let idAlias = typeAliases["ID"]?.removingWhitespace else { return false }
      return instantIDTypes.contains(idAlias)
    default:
      return false
    }
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
        schemaValue: InstantSchemaValue(type: type),
        relation: relationMetadata(from: variable.attributes, context: context)
      )
    }
  }

  private static func relationMetadata(
    from attributes: AttributeListSyntax,
    context: some MacroExpansionContext
  ) -> InstantRelationMetadata? {
    for element in attributes {
      guard
        case let .attribute(attribute) = element,
        attribute.attributeName.description.trimmed == "InstantRelation"
      else { continue }

      guard
        case let .argumentList(arguments) = attribute.arguments,
        arguments.count == 1,
        let argument = arguments.first,
        argument.label?.text == "reverse",
        let expression = argument.expression.as(StringLiteralExprSyntax.self),
        let reverseName = expression.representedLiteralValue,
        !reverseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        context.diagnose(
          InstantEntityDiagnostic.unsupportedInstantRelationArgument
            .diagnose(at: Syntax(attribute))
        )
        return nil
      }

      return InstantRelationMetadata(reverseName: reverseName)
    }

    return nil
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

  private static func typeAliases(in declaration: some DeclGroupSyntax) -> [String: String] {
    Dictionary(
      uniqueKeysWithValues: declaration.memberBlock.members.compactMap { member in
        guard let declaration = member.decl.as(TypeAliasDeclSyntax.self) else { return nil }

        return (
          declaration.name.text,
          declaration.initializer.value.description.trimmed
        )
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

public struct InstantRelationMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    []
  }
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
  var relation: InstantRelationMetadata?

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
      let forwardIdentity: String
      let reverseIdentity: String
      if let relation {
        forwardIdentity = "\(typeName).\(name).attributeID"
        reverseIdentity =
          "\(targetType).instantNamespace + \(String(reflecting: "/\(relation.reverseName)"))"
      } else {
        forwardIdentity = "nil"
        reverseIdentity = "nil"
      }
      arguments += [
        "        isUnique: false,",
        "        forwardIdentity: \(forwardIdentity),",
        "        reverseIdentity: \(reverseIdentity),",
        "        primaryKey: false,",
        "        linkNamespace: \(targetType).instantNamespace",
      ]
    }
    arguments.append("      )")
    return arguments.joined(separator: "\n")
  }
}

private struct InstantRelationMetadata {
  var reverseName: String
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

  var isSwiftIdentifier: Bool {
    guard let first = unicodeScalars.first else { return false }
    guard first == "_" || CharacterSet.asciiLetters.contains(first) else { return false }
    return unicodeScalars.dropFirst().allSatisfy {
      $0 == "_" || CharacterSet.asciiLetters.contains($0) || CharacterSet.decimalDigits.contains($0)
    }
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

private extension CharacterSet {
  static let asciiLetters =
    CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
}

private enum InstantEntityDiagnostic {
  case duplicateReverseRelationName(String)
  case invalidReverseRelationName(String)
  case instantRelationRequiresRef(String)
  case reservedGeneratedMemberName(String)
  case reservedReverseRelationName(String)
  case redundantNamespace(String)
  case requiresDraftTypeAnnotation(String)
  case requiresNominalType
  case requiresSingleDraftPropertyBinding
  case reverseRelationNameCollidesWithGeneratedMember(String)
  case unsupportedInstantRelationArgument
  case unsupportedNamespaceArgument

  func diagnose(at node: Syntax) -> Diagnostic {
    Diagnostic(node: node, message: self)
  }
}

extension InstantEntityDiagnostic: DiagnosticMessage {
  var message: String {
    switch self {
    case let .duplicateReverseRelationName(name):
      return "Reverse relation name '\(name)' is used by more than one @InstantRelation on this entity."
    case let .invalidReverseRelationName(name):
      return "Reverse relation name '\(name)' is not a valid Swift member name for @InstantRelation."
    case let .instantRelationRequiresRef(name):
      return "Stored property '\(name)' uses @InstantRelation, but it is not an Instant ref attribute."
    case let .reservedGeneratedMemberName(name):
      return "Stored property '\(name)' uses a name reserved by @InstantEntity generated helpers."
    case let .reservedReverseRelationName(name):
      return "Reverse relation name '\(name)' is reserved by @InstantEntity generated helpers."
    case let .redundantNamespace(namespace):
      return #"@InstantEntity("\#(namespace)") is redundant; omit the argument to use the default namespace."#
    case let .requiresDraftTypeAnnotation(name):
      return "Stored property '\(name)' needs an explicit type annotation for @InstantEntity draft generation."
    case .requiresNominalType:
      return "@InstantEntity can only be attached to a struct, class, or actor."
    case .requiresSingleDraftPropertyBinding:
      return "@InstantEntity draft generation requires one stored property per var declaration."
    case let .reverseRelationNameCollidesWithGeneratedMember(name):
      return "Reverse relation name '\(name)' collides with a generated @InstantEntity member."
    case .unsupportedInstantRelationArgument:
      return #"@InstantRelation requires a non-empty string literal reverse name, for example @InstantRelation(reverse: "posts")."#
    case .unsupportedNamespaceArgument:
      return "@InstantEntity namespace overrides must be string literals."
    }
  }

  var diagnosticID: MessageID {
    switch self {
    case .duplicateReverseRelationName:
      return MessageID(domain: "InstantSwiftDataMacros", id: "duplicateReverseRelationName")
    case .invalidReverseRelationName:
      return MessageID(domain: "InstantSwiftDataMacros", id: "invalidReverseRelationName")
    case .instantRelationRequiresRef:
      return MessageID(domain: "InstantSwiftDataMacros", id: "instantRelationRequiresRef")
    case .reservedGeneratedMemberName:
      return MessageID(domain: "InstantSwiftDataMacros", id: "reservedGeneratedMemberName")
    case .reservedReverseRelationName:
      return MessageID(domain: "InstantSwiftDataMacros", id: "reservedReverseRelationName")
    case .redundantNamespace:
      return MessageID(domain: "InstantSwiftDataMacros", id: "redundantNamespace")
    case .requiresDraftTypeAnnotation:
      return MessageID(domain: "InstantSwiftDataMacros", id: "requiresDraftTypeAnnotation")
    case .requiresNominalType:
      return MessageID(domain: "InstantSwiftDataMacros", id: "requiresNominalType")
    case .requiresSingleDraftPropertyBinding:
      return MessageID(domain: "InstantSwiftDataMacros", id: "requiresSingleDraftPropertyBinding")
    case .reverseRelationNameCollidesWithGeneratedMember:
      return MessageID(
        domain: "InstantSwiftDataMacros",
        id: "reverseRelationNameCollidesWithGeneratedMember"
      )
    case .unsupportedInstantRelationArgument:
      return MessageID(domain: "InstantSwiftDataMacros", id: "unsupportedInstantRelationArgument")
    case .unsupportedNamespaceArgument:
      return MessageID(domain: "InstantSwiftDataMacros", id: "unsupportedNamespaceArgument")
    }
  }

  var severity: DiagnosticSeverity {
    switch self {
    case .duplicateReverseRelationName,
      .invalidReverseRelationName,
      .instantRelationRequiresRef,
      .reservedGeneratedMemberName,
      .reservedReverseRelationName,
      .requiresDraftTypeAnnotation,
      .requiresNominalType,
      .requiresSingleDraftPropertyBinding,
      .reverseRelationNameCollidesWithGeneratedMember,
      .unsupportedInstantRelationArgument,
      .unsupportedNamespaceArgument:
      return .error
    case .redundantNamespace:
      return .warning
    }
  }
}
