import Foundation

enum CLIError: Error, LocalizedError {
  case fileNotFound(String)
  case invalidJSON
  case invalidSchemaFormat(String)
  case schemaNotFound
  case schemaCompilationFailed
  case missingAppId
  case missingToken
  case message(String)
  
  var errorDescription: String? {
    switch self {
    case .fileNotFound(let path):
      return "File not found: \(path)"
    case .invalidJSON:
      return "Invalid JSON in schema file"
    case .invalidSchemaFormat(let msg):
      return "Invalid schema format: \(msg)"
    case .schemaNotFound:
      return """
                Could not find instant.schema.json in current directory.
                
                Create a schema file or specify path with --schema option.
                """
    case .schemaCompilationFailed:
      return "Failed to compile schema file"
    case .missingAppId:
      return """
                Missing App ID. Provide it via:
                  --app-id <id>
                  or set INSTANT_APP_ID environment variable
                """
    case .missingToken:
      return """
                Missing Admin Token. Provide it via:
                  --token <token>
                  or set INSTANT_ADMIN_TOKEN environment variable
                
                Get your admin token from the InstantDB dashboard:
                https://instantdb.com/dash
                """
    case .message(let msg):
      return msg
    }
  }
}
