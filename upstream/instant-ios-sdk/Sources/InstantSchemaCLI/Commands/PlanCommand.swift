import ArgumentParser
import Foundation
import InstantDB

struct PlanCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "plan",
    abstract: "Preview schema changes without applying"
  )
  
  @Option(name: .long, help: "InstantDB App ID (or set INSTANT_APP_ID env var)")
  var appId: String?
  
  @Option(name: .long, help: "Admin token (or set INSTANT_ADMIN_TOKEN env var)")
  var token: String?
  
  @Option(name: .long, help: "Path to schema JSON file (auto-detected if not specified)")
  var schema: String?
  
  func run() async throws {
    let resolvedAppId = try Config.resolveAppId(appId)
    let resolvedToken = try Config.resolveToken(token)
    let schemaInstance = try loadSchema()
    
    print(Terminal.gray("Planning..."))
    
    let api = PlatformAPI(token: resolvedToken)
    let plan = try await api.planSchemaPush(appId: resolvedAppId, schema: schemaInstance)
    
    if plan.steps.isEmpty {
      print("\n\(Terminal.checkmark) \(Terminal.green("Schema is already up to date!"))")
      return
    }
    
    PlanFormatter.printPlan(plan)
  }
  
  private func loadSchema() throws -> InstantSchema {
    if let schemaPath = schema {
      return try SchemaLoader.load(from: schemaPath)
    }
    
    guard let foundPath = SchemaFinder.findSchemaFile() else {
      throw CLIError.schemaNotFound
    }
    
    return try SchemaLoader.load(from: foundPath)
  }
}
