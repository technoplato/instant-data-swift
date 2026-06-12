import ArgumentParser
import Foundation
import InstantDB

struct PushCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "push",
    abstract: "Push schema to InstantDB"
  )
  
  @Option(name: .long, help: "InstantDB App ID (or set INSTANT_APP_ID env var)")
  var appId: String?
  
  @Option(name: .long, help: "Admin token (or set INSTANT_ADMIN_TOKEN env var)")
  var token: String?
  
  @Option(name: .long, help: "Path to schema JSON file (default: instant.schema.json)")
  var schema: String?
  
  @Flag(name: .long, help: "Skip confirmation prompt")
  var force: Bool = false
  
  @Flag(name: .long, help: "Only show what would change, don't apply")
  var dryRun: Bool = false
  
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
    
    if dryRun {
      print("\n\(Terminal.gray("Dry run complete. No changes applied."))")
      return
    }
    
    if !force {
      print("\n\(Terminal.bold("Push these changes?")) [y/N] ", terminator: "")
      guard readLine()?.lowercased() == "y" else {
        print("\(Terminal.cross) Aborted.")
        return
      }
    }
    
    print("\n\(Terminal.gray("Pushing schema..."))")
    _ = try await api.pushSchema(appId: resolvedAppId, schema: schemaInstance)
    print("\(Terminal.checkmark) \(Terminal.green("Schema updated!"))")
  }
  
  private func loadSchema() throws -> InstantSchema {
    if let schemaPath = schema {
      return try SchemaLoader.load(from: schemaPath)
    }
    
    if let foundPath = SchemaFinder.findSchemaFile() {
      return try SchemaLoader.load(from: foundPath)
    }
    
    throw CLIError.schemaNotFound
  }
}
