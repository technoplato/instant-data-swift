import Foundation
import InstantSwiftDataCore

@main
struct InstantSwiftDataBenchmarks {
  static func main() async {
    do {
      try await run()
    } catch let error as BenchmarkCLIError {
      if error.exitCode == 0 {
        print(error.description)
      } else {
        writeError(error.description)
      }
      exit(error.exitCode)
    } catch let error as InstantError {
      writeError(error.description)
      exit(exitCode(for: error))
    } catch {
      writeError("instant-swift-data-benchmarks: \(error)")
      exit(70)
    }
  }

  private static func run() async throws {
    let options = try BenchmarkOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    let result = try await InstantSwiftDataLocalBenchmarks.runLocalTodos(
      appID: options.appID,
      iterations: options.iterations
    )

    switch options.output {
    case .json:
      try writeJSON(result)

    case .jsonl:
      for row in result.evidenceRows {
        try writeJSONLine(row)
      }
    }
  }

  private static func writeJSON<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func writeJSONLine<Value: Encodable>(_ value: Value) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func writeError(_ string: String) {
    FileHandle.standardError.write(Data((string + "\n").utf8))
  }

  private static func exitCode(for error: InstantError) -> Int32 {
    switch error.code {
    case .authFailed:
      65
    case .validationFailed, .decodeFailed:
      66
    case .networkFailed:
      69
    case .permissionRejected:
      77
    case .persistenceFailed:
      74
    case .implementationFailed:
      70
    }
  }
}

private struct BenchmarkOptions: Sendable {
  var suite: String
  var iterations: Int
  var appID: String
  var output: BenchmarkOutputMode

  static func parse(arguments: [String]) throws -> Self {
    var arguments = arguments
    var suite = InstantSwiftDataLocalBenchmarks.localTodosSuite
    var iterations = 3
    var appID = "local-benchmark"
    var output = BenchmarkOutputMode.json

    while let argument = arguments.popFirstArgument() {
      switch argument {
      case "--suite":
        guard let value = arguments.popFirstArgument(), !value.isEmpty else {
          throw BenchmarkCLIError(usage, exitCode: 64)
        }
        suite = value

      case "--iterations":
        guard let value = arguments.popFirstArgument(), let count = Int(value), count > 0 else {
          throw BenchmarkCLIError(usage, exitCode: 64)
        }
        iterations = count

      case "--app-id":
        guard let value = arguments.popFirstArgument(),
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw BenchmarkCLIError(usage, exitCode: 64)
        }
        appID = value

      case "--json":
        output = .json

      case "--jsonl":
        output = .jsonl

      case "help", "--help", "-h":
        throw BenchmarkCLIError(usage, exitCode: 0)

      default:
        throw BenchmarkCLIError("Unknown benchmark option: \(argument).\n\(usage)", exitCode: 64)
      }
    }

    guard suite == InstantSwiftDataLocalBenchmarks.localTodosSuite else {
      throw BenchmarkCLIError("Unsupported benchmark suite: \(suite).\n\(usage)", exitCode: 64)
    }

    return Self(suite: suite, iterations: iterations, appID: appID, output: output)
  }

  private static var usage: String {
    """
    Usage: instant-swift-data-benchmarks [--suite local-todos] [--iterations n] [--app-id id] [--json|--jsonl]
    """
  }
}

private enum BenchmarkOutputMode: Sendable {
  case json
  case jsonl
}

private struct BenchmarkCLIError: Error, CustomStringConvertible {
  var description: String
  var exitCode: Int32

  init(_ description: String, exitCode: Int32) {
    self.description = description
    self.exitCode = exitCode
  }
}

private extension Array {
  mutating func popFirstArgument() -> Element? {
    guard !isEmpty else { return nil }
    return removeFirst()
  }
}
