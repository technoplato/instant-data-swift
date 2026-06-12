import ArgumentParser
import Foundation
import InstantDB

struct GetCommand: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "get",
    abstract: "Get current schema from InstantDB"
  )
  
  @Option(name: .long, help: "InstantDB App ID (or set INSTANT_APP_ID env var)")
  var appId: String?
  
  @Option(name: .long, help: "Admin token (or set INSTANT_ADMIN_TOKEN env var)")
  var token: String?
  
  @Flag(name: .long, help: "Output as JSON")
  var json: Bool = false
  
  func run() async throws {
    let resolvedAppId = try Config.resolveAppId(appId)
    let resolvedToken = try Config.resolveToken(token)
    
    print(Terminal.gray("Fetching schema..."))
    
    let api = PlatformAPI(token: resolvedToken)
    let schema = try await api.getSchema(appId: resolvedAppId)
    
    if json {
      let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
      print(String(data: data, encoding: .utf8) ?? "")
    } else {
      SchemaPrinter.print(schema)
    }
  }
}
