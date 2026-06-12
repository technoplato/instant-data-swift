/// InstantDB Schema Generator
///
/// Parses Swift schema files and generates JSON schema for InstantDB.
///
/// Usage: InstantSchemaGenerator <input-file> <output-file>

import Foundation
import SwiftSyntax
import SwiftParser

enum InstantSchemaGenerator {
  static func main() throws {
    let args = CommandLine.arguments
    
    guard args.count >= 3 else {
      print("Usage: InstantSchemaGenerator <schema.swift> <output.json>")
      exit(1)
    }
    
    let inputFile = args[1]
    let outputFile = args[2]
    
    let source = try String(contentsOfFile: inputFile, encoding: .utf8)
    let syntaxTree = Parser.parse(source: source)
    
    let visitor = SchemaBlockVisitor(viewMode: .all)
    visitor.walk(syntaxTree)
    
    let schema = SchemaOutput(entities: visitor.entities, links: visitor.links)
    
    let json = try JSONEncoder().encode(schema)
    let pretty = try JSONSerialization.data(
      withJSONObject: try JSONSerialization.jsonObject(with: json),
      options: [.prettyPrinted, .sortedKeys]
    )
    try pretty.write(to: URL(fileURLWithPath: outputFile))
  }
}

try InstantSchemaGenerator.main()
