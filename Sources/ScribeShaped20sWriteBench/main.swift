import Foundation
import InstantSwiftDataCore

/// Pure CLI for #156 open-segment network write/observe lanes (Swift side).
///
/// Usage:
///   scribe-shaped-20s-write-bench --role writer|observer --scenario net-a|net-b
///
/// Env (required for live):
///   INSTANT_APP_ID
///   INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN
///   INSTANT_SWIFT_DATA_BENCH_USER_ID
///   INSTANT_SWIFT_DATA_BENCH_RECORDING_ID
///   INSTANT_SWIFT_DATA_BENCH_SEGMENT_ID
/// Optional:
///   INSTANT_API_URI
///   INSTANT_WEBSOCKET_URI
///   INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS (default 20)
///   INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT (default 12)
@main
struct ScribeShaped20sWriteBench {
  static func main() async {
    do {
      try await run()
    } catch {
      let payload: [String: Any] = [
        "ok": false,
        "suite": "scribe-open-segment-20s-network",
        "side": "swift",
        "error": String(describing: error),
      ]
      if let data = try? JSONSerialization.data(
        withJSONObject: payload,
        options: [.prettyPrinted, .sortedKeys]
      ) {
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
      } else {
        FileHandle.standardError.write(Data("scribe-shaped-20s-write-bench failed\n".utf8))
      }
      exit(1)
    }
  }

  private static func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    let options = try Options.parse(args)
    let environment = ProcessInfo.processInfo.environment

    let appID = try required("INSTANT_APP_ID", environment)
    let refreshToken = try required("INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN", environment)
    let userID = try required("INSTANT_SWIFT_DATA_BENCH_USER_ID", environment)
    let recordingID = try required("INSTANT_SWIFT_DATA_BENCH_RECORDING_ID", environment)
    let segmentID = try required("INSTANT_SWIFT_DATA_BENCH_SEGMENT_ID", environment)

    let apiURI =
      URL(string: environment["INSTANT_API_URI"] ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString)
      ?? InstantRuntimeConfiguration.defaultAPIURI
    let websocketURI =
      URL(
        string: environment["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      ) ?? InstantRuntimeConfiguration.defaultWebSocketURI

    let duration =
      Double(environment["INSTANT_SWIFT_DATA_BENCH_DURATION_SECONDS"] ?? "")
      ?? options.durationSeconds
    let wordsPerUpsert =
      Int(environment["INSTANT_SWIFT_DATA_BENCH_WORDS_PER_UPSERT"] ?? "")
      ?? options.wordsPerUpsert

    let result: ScribeOpenSegmentBenchResult
    switch options.role {
    case .writer:
      result = try await ScribeOpenSegmentNetworkBench.runWriter(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: userID,
        recordingID: recordingID,
        segmentID: segmentID,
        durationSeconds: duration,
        wordsPerUpsert: wordsPerUpsert,
        scenario: options.scenario
      )
    case .observer:
      result = try await ScribeOpenSegmentNetworkBench.runObserver(
        appID: appID,
        apiURI: apiURI,
        websocketURI: websocketURI,
        refreshToken: refreshToken,
        expectedUserID: userID,
        recordingID: recordingID,
        segmentID: segmentID,
        durationSeconds: duration,
        wordsPerUpsert: wordsPerUpsert,
        scenario: options.scenario
      )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(result)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    if !result.ok {
      exit(2)
    }
  }
}

private struct Options {
  enum Role: String {
    case writer
    case observer
  }

  var role: Role
  var scenario: String
  var durationSeconds: Double
  var wordsPerUpsert: Int

  static func parse(_ arguments: [String]) throws -> Options {
    var role: Role?
    var scenario = "net-unknown"
    var durationSeconds = ScribeOpenSegmentNetworkBench.defaultDurationSeconds
    var wordsPerUpsert = ScribeOpenSegmentNetworkBench.defaultWordsPerUpsert

    var index = 0
    while index < arguments.count {
      let arg = arguments[index]
      switch arg {
      case "--role":
        index += 1
        guard index < arguments.count, let parsed = Role(rawValue: arguments[index]) else {
          throw BenchCLIError("Expected writer|observer after --role")
        }
        role = parsed
      case "--scenario":
        index += 1
        guard index < arguments.count else {
          throw BenchCLIError("Expected value after --scenario")
        }
        scenario = arguments[index]
      case "--duration":
        index += 1
        guard index < arguments.count, let value = Double(arguments[index]), value > 0 else {
          throw BenchCLIError("Expected positive seconds after --duration")
        }
        durationSeconds = value
      case "--words-per-upsert":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
          throw BenchCLIError("Expected positive int after --words-per-upsert")
        }
        wordsPerUpsert = value
      case "--help", "-h":
        print(
          """
          Usage: scribe-shaped-20s-write-bench --role writer|observer --scenario net-a|net-b
            [--duration 20] [--words-per-upsert 12]
          """
        )
        exit(0)
      default:
        throw BenchCLIError("Unknown argument: \(arg)")
      }
      index += 1
    }

    guard let role else {
      throw BenchCLIError("Missing --role writer|observer")
    }
    return Options(
      role: role,
      scenario: scenario,
      durationSeconds: durationSeconds,
      wordsPerUpsert: wordsPerUpsert
    )
  }
}

private struct BenchCLIError: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}

private func required(_ key: String, _ environment: [String: String]) throws -> String {
  guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
    !value.isEmpty
  else {
    throw BenchCLIError("Missing required environment variable \(key)")
  }
  return value
}
