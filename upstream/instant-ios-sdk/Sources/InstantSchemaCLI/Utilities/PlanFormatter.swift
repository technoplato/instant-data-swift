import Foundation
import InstantDB

/// Formats schema plan output for CLI display
enum PlanFormatter {
  static func printPlan(_ plan: SchemaPlanResponse) {
    print("")
    for step in plan.steps {
      let badge = stepBadge(for: step.type)
      let description = formatDescription(step)
      print("\(badge) \(description)")
      
      if let secondary = formatSecondaryDetails(step) {
        print("  \(Terminal.italic(Terminal.gray(secondary)))")
      }
    }
  }
  
  static func stepBadge(for type: String) -> String {
    switch type {
    case "add-attr":
      return Terminal.greenBadge("+ CREATE ATTR")
    case "delete-attr":
      return Terminal.redBadge("- DELETE ATTR")
    case "update-attr":
      return Terminal.yellowBadge("* UPDATE ATTR")
    case "add-namespace":
      return Terminal.greenBadge("+ CREATE NAMESPACE")
    case "delete-namespace":
      return Terminal.redBadge("- DELETE NAMESPACE")
    case "add-link":
      return Terminal.greenBadge("+ CREATE LINK")
    case "delete-link":
      return Terminal.redBadge("- DELETE LINK")
    case "index":
      return Terminal.blueBadge("+ CREATE INDEX")
    case "remove-index":
      return Terminal.blueBadge("- DELETE INDEX")
    case "unique":
      return Terminal.blueBadge("* MAKE UNIQUE")
    case "remove-unique":
      return Terminal.blueBadge("- REMOVE UNIQUE")
    case "required":
      return Terminal.blueBadge("+ MAKE REQUIRED")
    case "remove-required":
      return Terminal.blueBadge("- MAKE OPTIONAL")
    case "check-data-type":
      return Terminal.blueBadge("+ SET DATA TYPE")
    default:
      return Terminal.gray("[\(type)]")
    }
  }
  
  static func formatDescription(_ step: SchemaPlanStep) -> String {
    if let forwardIdentity = step.details["forward-identity"] as? [Any],
       forwardIdentity.count >= 3 {
      let entity = forwardIdentity[1] as? String ?? "?"
      let attr = forwardIdentity[2] as? String ?? "?"
      return Terminal.bold("\(entity)") + ".\(attr)"
    }
    
    if let attrId = step.details["attr-id"] as? String {
      return attrId
    }
    
    return ""
  }
  
  static func formatSecondaryDetails(_ step: SchemaPlanStep) -> String? {
    var details: [String] = []
    
    if let valueType = step.details["value-type"] as? String {
      details.append("type: \(valueType)")
    }
    
    if let indexed = step.details["indexed"] as? Bool, indexed {
      details.append("indexed")
    }
    
    if let unique = step.details["unique"] as? Bool, unique {
      details.append("unique")
    }
    
    return details.isEmpty ? nil : details.joined(separator: ", ")
  }
}
