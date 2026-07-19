import Foundation
import InstantSwiftDataCLIParsing
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
    } catch let error as CLIBenchmarkArgumentError {
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
    let result = switch options.suite {
    case InstantSwiftDataLocalBenchmarks.localTodosSuite:
      try await InstantSwiftDataLocalBenchmarks.runLocalTodos(
        appID: options.appID,
        iterations: options.iterations
      )
    case InstantSwiftDataCrossSDKBenchmarks.suite:
      try await InstantSwiftDataCrossSDKBenchmarks.run(
        appID: options.appID,
        iterations: options.iterations
      )
    case InstantSwiftDataCrossSDKRuntimeBenchmarks.suite:
      try await InstantSwiftDataCrossSDKRuntimeBenchmarks.run(
        appID: options.appID,
        iterations: options.iterations
      )
    default:
      preconditionFailure("Benchmark options reject unsupported suites.")
    }

    switch options.output {
    case .human, .json:
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
  var output: CLIOutputMode

  static func parse(arguments: [String]) throws -> Self {
    let invocation = try CLIBenchmarkArguments.parse(
      arguments,
      defaultAppID: "local-benchmark",
      usageCommand: "instant-swift-data-benchmarks"
    )

    guard [
      InstantSwiftDataLocalBenchmarks.localTodosSuite,
      InstantSwiftDataCrossSDKBenchmarks.suite,
      InstantSwiftDataCrossSDKRuntimeBenchmarks.suite,
    ].contains(invocation.suite) else {
      throw BenchmarkCLIError("Unsupported benchmark suite: \(invocation.suite).\n\(usage)", exitCode: 64)
    }

    return Self(
      suite: invocation.suite,
      iterations: invocation.iterations,
      appID: invocation.appID,
      output: invocation.output
    )
  }

  private static var usage: String {
    """
    Usage: instant-swift-data-benchmarks [--suite <local-todos|cross-sdk-core|cross-sdk-runtime>] [--iterations n] [--app-id id] [--json|--jsonl]
    """
  }
}

private struct BenchmarkCLIError: Error, CustomStringConvertible {
  var description: String
  var exitCode: Int32

  init(_ description: String, exitCode: Int32) {
    self.description = description
    self.exitCode = exitCode
  }
}
