/// Schema Block Visitor for InstantDB Schema Generator
///
/// Parses the `InstantSchema { }` block to extract:
/// - Entity definitions with Entity("name").field(...)
/// - Link definitions with Link("from", "label").to(...)

import SwiftSyntax

/// Visits the InstantSchema DSL block to extract entities and links.
class SchemaBlockVisitor: SyntaxVisitor {
  /// Entities found in the schema block
  var entities: [String: EntitySchema] = [:]
  
  /// Links found in the schema block
  var links: [String: LinkSchema] = [:]
  
  /// Track processed nodes to avoid duplicates
  private var processedNodes: Set<Int> = []
  
  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    if let entity = parseEntityChain(node) {
      entities[entity.name] = entity
    }
    
    if let link = parseLinkChain(node) {
      links[link.name] = link
    }
    
    return .visitChildren
  }
}

// MARK: - Entity Parsing

extension SchemaBlockVisitor {
  private func parseEntityChain(_ node: FunctionCallExprSyntax) -> EntitySchema? {
    var currentNode: FunctionCallExprSyntax? = node
    var fields: [(name: String, type: String, isRequired: Bool, isIndexed: Bool, isUnique: Bool)] = []
    var entityName: String?
    
    while let funcCall = currentNode {
      let nodeId = funcCall.position.utf8Offset
      if processedNodes.contains(nodeId) {
        return nil
      }
      
      if let memberAccess = funcCall.calledExpression.as(MemberAccessExprSyntax.self) {
        let methodName = memberAccess.declName.baseName.text
        
        if methodName == "field" || methodName == "optionalField" {
          if let fieldInfo = parseFieldCall(funcCall, isOptional: methodName == "optionalField") {
            fields.insert(fieldInfo, at: 0)
          }
        }
        
        /// Move up the chain
        if let base = memberAccess.base?.as(FunctionCallExprSyntax.self) {
          currentNode = base
        } else {
          currentNode = nil
        }
      } else if let declRef = funcCall.calledExpression.as(DeclReferenceExprSyntax.self),
                declRef.baseName.text == "Entity" {
        /// Found the root Entity("name") call
        entityName = parseStringArgument(funcCall)
        processedNodes.insert(funcCall.position.utf8Offset)
        break
      } else {
        currentNode = nil
      }
    }
    
    guard let name = entityName, !fields.isEmpty else {
      return nil
    }
    
    /// Mark all nodes as processed
    processedNodes.insert(node.position.utf8Offset)
    
    /// Build entity schema
    var attrs: [String: AttributeSchema] = [:]
    for field in fields {
      attrs[field.name] = AttributeSchema(
        valueType: field.type,
        config: AttributeConfig(
          indexed: field.isIndexed,
          unique: field.isUnique
        ),
        required: field.isRequired ? true : nil
      )
    }
    
    return EntitySchema(name: name, typeName: name, attrs: attrs)
  }
  
  /// Parses .field("name", .type, .constraint, ...) calls
  private func parseFieldCall(_ node: FunctionCallExprSyntax, isOptional: Bool) -> (name: String, type: String, isRequired: Bool, isIndexed: Bool, isUnique: Bool)? {
    var fieldName: String?
    var fieldType: String = "any"
    var isIndexed = false
    var isUnique = false
    
    for (index, arg) in node.arguments.enumerated() {
      if index == 0 {
        /// First arg: field name
        fieldName = parseStringLiteral(arg.expression)
      } else if index == 1 {
        /// Second arg: data type (.string, .number, etc.)
        if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
          fieldType = memberAccess.declName.baseName.text
        }
      } else {
        /// Remaining args: constraints (.indexed, .unique, .required)
        if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
          let constraint = memberAccess.declName.baseName.text
          if constraint == "indexed" {
            isIndexed = true
          } else if constraint == "unique" {
            isUnique = true
            isIndexed = true // unique implies indexed
          }
        }
      }
    }
    
    guard let name = fieldName else { return nil }
    
    return (
      name: name,
      type: fieldType,
      isRequired: !isOptional,
      isIndexed: isIndexed,
      isUnique: isUnique
    )
  }
}

// MARK: - Link Parsing

extension SchemaBlockVisitor {
  /// Parses Link("from", "label").hasMany().to("entity", "label") chains
  private func parseLinkChain(_ node: FunctionCallExprSyntax) -> LinkSchema? {
    // Only process .to() calls (the end of the chain)
    guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
          memberAccess.declName.baseName.text == "to" else {
      return nil
    }
    
    let nodeId = node.position.utf8Offset
    guard !processedNodes.contains(nodeId) else { return nil }
    processedNodes.insert(nodeId)
    
    // Extract .to() arguments
    var toEntity: String?
    var reverseLabel: String?
    var reverseCardinality = "one"
    
    for (index, arg) in node.arguments.enumerated() {
      if index == 0 {
        toEntity = parseStringLiteral(arg.expression)
      } else if index == 1 {
        reverseLabel = parseStringLiteral(arg.expression)
      }
    }
    
    // Walk up the chain to find Link() call and modifiers
    var fromEntity: String?
    var forwardLabel: String?
    var forwardCardinality = "many"
    
    var currentExpr: ExprSyntax? = memberAccess.base
    while let expr = currentExpr {
      if let funcCall = expr.as(FunctionCallExprSyntax.self) {
        if let innerMember = funcCall.calledExpression.as(MemberAccessExprSyntax.self) {
          let methodName = innerMember.declName.baseName.text
          if methodName == "hasMany" {
            forwardCardinality = "many"
          } else if methodName == "hasOne" {
            forwardCardinality = "one"
          } else if methodName == "reverseHasMany" {
            reverseCardinality = "many"
          } else if methodName == "reverseHasOne" {
            reverseCardinality = "one"
          }
          currentExpr = innerMember.base
        } else if let declRef = funcCall.calledExpression.as(DeclReferenceExprSyntax.self),
                  declRef.baseName.text == "Link" {
          // Found the root Link("from", "label") call
          for (index, arg) in funcCall.arguments.enumerated() {
            if index == 0 {
              fromEntity = parseStringLiteral(arg.expression)
            } else if index == 1 {
              forwardLabel = parseStringLiteral(arg.expression)
            }
          }
          break
        } else {
          break
        }
      } else {
        break
      }
    }
    
    guard let from = fromEntity,
          let fwdLabel = forwardLabel,
          let to = toEntity,
          let revLabel = reverseLabel else {
      return nil
    }
    
    let linkName = "\(from)\(fwdLabel.capitalized)"
    
    return LinkSchema(
      name: linkName,
      forward: LinkEndpointSchema(
        on: from,
        has: forwardCardinality,
        label: fwdLabel
      ),
      reverse: LinkEndpointSchema(
        on: to,
        has: reverseCardinality,
        label: revLabel
      )
    )
  }
}

// MARK: - Helpers

extension SchemaBlockVisitor {
  private func parseStringArgument(_ node: FunctionCallExprSyntax) -> String? {
    guard let firstArg = node.arguments.first else { return nil }
    return parseStringLiteral(firstArg.expression)
  }
  
  private func parseStringLiteral(_ expr: ExprSyntax) -> String? {
    guard let stringLiteral = expr.as(StringLiteralExprSyntax.self),
          let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) else {
      return nil
    }
    return segment.content.text
  }
}
