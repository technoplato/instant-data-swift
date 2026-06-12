import Foundation

let command = CommandLine.arguments.dropFirst().first ?? "help"

switch command {
case "help":
  print(
    """
    instant-swift-data scaffold.

    Planned command groups:
      auth, schema, app, query, validate, benchmark, examples, cache, outbox
    """
  )
default:
  fputs("Unknown command: \(command)\n", stderr)
  exit(2)
}

