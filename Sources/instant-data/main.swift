import Foundation

let command = CommandLine.arguments.dropFirst().first ?? "help"

switch command {
case "help":
  print("instant-data scaffold. Commands will be added with schema generation and validation.")
default:
  fputs("Unknown command: \(command)\n", stderr)
  exit(2)
}

