import Foundation
import InstantSwiftDataCore

#if canImport(Darwin)
  import Darwin
#endif

/// Exercise Gem — Swift simple-write lane (mirrors TS counters path).
///
/// Prefer orchestrator-supplied `--refresh-token` + `--user-id`.
/// Admin-token minting is best-effort only.
@main
struct ExerciseGem {
  static func main() async {
    do {
      try await run()
    } catch {
      let payload: [String: Any] = [
        "ok": false,
        "side": "swift",
        "suite": "simple",
        "error": String(describing: error),
      ]
      writeJSON(payload, to: FileHandle.standardError)
      exit(1)
    }
  }

  private static func run() async throws {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    let env = ProcessInfo.processInfo.environment

    let appID = options.appID ?? env["INSTANT_APP_ID"] ?? ""
    guard !appID.isEmpty else { throw CLIError("Missing --app-id / INSTANT_APP_ID") }

    let apiURI =
      URL(
        string: options.apiURI
          ?? env["INSTANT_API_URI"]
          ?? InstantRuntimeConfiguration.defaultAPIURI.absoluteString
      )
      ?? InstantRuntimeConfiguration.defaultAPIURI
    let websocketURI =
      URL(
        string: options.websocketURI
          ?? env["INSTANT_WEBSOCKET_URI"]
          ?? InstantRuntimeConfiguration.defaultWebSocketURI.absoluteString
      )
      ?? InstantRuntimeConfiguration.defaultWebSocketURI

    let runID = options.runID ?? UUID().uuidString
    let duration = options.durationSeconds

    guard let refreshToken = options.refreshToken ?? env["INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN"],
      let userID = options.userID ?? env["INSTANT_SWIFT_DATA_BENCH_USER_ID"],
      !refreshToken.isEmpty,
      !userID.isEmpty
    else {
      throw CLIError(
        "Missing --refresh-token and --user-id (orchestrator should mint via admin.createToken)"
      )
    }

    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("exercise-gem-\(UUID().uuidString).sqlite")

    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL,
      initialAttributes: ExerciseGemSchema.attributes,
      refreshTokenVerifier: .live,
      authTokenInvalidator: .live,
      liveTransport: .live
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let session = try await runtime.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-exercise-gem-user"
    )
    guard session.userID == userID else {
      throw CLIError("Verified user \(session.userID) != expected \(userID)")
    }
    _ = try await runtime.connect()
    try await waitAuthenticated(runtime)

    let clientID = try await runtime.clientID()
    let descriptor =
      options.descriptor
      ?? "swift-cli-simple-\(ProcessInfo.processInfo.processIdentifier)"

    let memBaseline = InstantProcessMemory.sample()
    let baselineResident = memBaseline?.residentBytes ?? 0
    let baselineFootprint = memBaseline?.physicalFootprintBytes ?? 0

    FileHandle.standardError.write(Data("EXERCISE_GEM_READY clientId=\(clientID)\n".utf8))

    let counterID = UUID().uuidString
    var seq = 0
    var writesAttempted = 0
    var writesAccepted = 0
    var rtts: [Double] = []
    var peakResident = baselineResident
    var peakFootprint = baselineFootprint
    let started = ContinuousClock.now
    let deadline = started + .seconds(duration)

    while ContinuousClock.now < deadline {
      seq += 1
      let sentAt = Date().timeIntervalSince1970 * 1_000
      let ops = counterUpsertOps(
        counterID: counterID,
        runID: runID,
        seq: seq,
        clientID: clientID,
        descriptor: descriptor,
        updatedAtMs: sentAt
      )
      writesAttempted += 1
      let mutation = try await runtime.transact(
        operations: ops,
        source: "exercise-gem.simple"
      )
      do {
        try await waitForServerAcceptance(
          runtime: runtime,
          transactionID: mutation.transactionID,
          timeoutSeconds: 5
        )
        writesAccepted += 1
        let rtt = Date().timeIntervalSince1970 * 1_000 - sentAt
        rtts.append(rtt)
      } catch {
        // Count attempt but do not treat as observed throughput.
        FileHandle.standardError.write(
          Data("write-accept-failed seq=\(seq) \(error)\n".utf8)
        )
      }
      if let sample = InstantProcessMemory.sample() {
        peakResident = max(peakResident, sample.residentBytes)
        peakFootprint = max(peakFootprint, sample.physicalFootprintBytes)
      }

      let appResident = max(0, peakResident - baselineResident)
      if Double(appResident) / (1024 * 1024) >= options.maxAppRssMiB {
        break
      }
    }

    let wall = seconds(ContinuousClock.now - started)
    let peakAppResident = max(0, peakResident - baselineResident)
    let peakAppFootprint = max(0, peakFootprint - baselineFootprint)
    let latency = percentile(rtts)

    let result: [String: Any] = [
      "ok": writesAccepted > 0,
      "side": "swift",
      "suite": "simple",
      "runId": runID,
      "appID": appID,
      "identity": [
        "clientId": clientID,
        "descriptor": descriptor,
      ],
      "counterId": counterID,
      "metrics": [
        "throughput": [
          "writesAttempted": writesAttempted,
          "writesLocalAcked": writesAccepted,
          "writesObserved": writesAccepted,
          "wallSeconds": wall,
          "observedPerSecond": wall > 0 ? Double(writesAccepted) / wall : 0,
          "localAckPerSecond": wall > 0 ? Double(writesAccepted) / wall : 0,
          "bytesWritten": 0,
          "bytesPerSecond": 0,
        ],
        "latency": latency,
        "peakRssBytes": peakResident,
        "peakRssMiB": Double(peakResident) / (1024 * 1024),
        "peakAppAttributedRssBytes": peakAppResident,
        "peakAppAttributedRssMiB": Double(peakAppResident) / (1024 * 1024),
        "peakPhysicalFootprintBytes": peakFootprint,
        "peakAppAttributedFootprintMiB": Double(peakAppFootprint) / (1024 * 1024),
        "bootBaselineResidentBytes": baselineResident,
      ],
      "details": [
        "lastSeq": seq,
        "maxAppRssMiB": options.maxAppRssMiB,
        "durationSeconds": duration,
      ],
    ]

    if let out = options.outPath {
      let url = URL(fileURLWithPath: out)
      try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        .write(to: url)
    }
    writeJSON(result, to: FileHandle.standardOutput)
  }
}

// MARK: - Schema

enum ExerciseGemSchema {
  static let ns = "counters"

  static var attributes: [InstantAttribute] {
    [
      .primaryKey(namespace: ns),
      attr("runId", .string, indexed: true),
      attr("name", .string, indexed: true),
      attr("value", .number, indexed: true),
      attr("seq", .number, indexed: true),
      attr("clientId", .string, indexed: true),
      attr("descriptor", .string, indexed: true),
      attr("payloadBytes", .number, indexed: false),
      attr("updatedAtMs", .number, indexed: true),
    ]
  }

  private static func attr(
    _ name: String,
    _ type: InstantValueType,
    indexed: Bool
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(ns)/\(name)",
      namespace: ns,
      name: name,
      valueType: type,
      isIndexed: indexed
    )
  }
}

func counterUpsertOps(
  counterID: String,
  runID: String,
  seq: Int,
  clientID: String,
  descriptor: String,
  updatedAtMs: Double
) -> [InstantTripleOperation] {
  let ns = ExerciseGemSchema.ns
  let now = InstantTimestamp(milliseconds: Int64(updatedAtMs))
  let txID = UUID().uuidString
  let fields: [(String, InstantValue)] = [
    ("runId", .string(runID)),
    ("name", .string("simple-counter")),
    ("value", .number(Double(seq))),
    ("seq", .number(Double(seq))),
    ("clientId", .string(clientID)),
    ("descriptor", .string(descriptor)),
    ("payloadBytes", .number(64)),
    ("updatedAtMs", .number(updatedAtMs)),
  ]
  var ops: [InstantTripleOperation] = [
    .insert(
      InstantTriple(
        entityID: counterID,
        attributeID: InstantAttribute.primaryKeyID(namespace: ns),
        value: .string(counterID),
        txID: txID,
        txTime: now
      )
    ),
  ]
  for (name, value) in fields {
    ops.append(
      .insert(
        InstantTriple(
          entityID: counterID,
          attributeID: "\(ns)/\(name)",
          value: value,
          txID: txID,
          txTime: now
        )
      )
    )
  }
  return ops
}

// MARK: - Lifecycle helpers

func waitAuthenticated(_ runtime: InstantRuntime) async throws {
  let deadline = ContinuousClock.now + .seconds(5)
  while ContinuousClock.now < deadline {
    if try await runtime.connectionStatus().state == .authenticated {
      return
    }
    try await Task.sleep(for: .milliseconds(25))
  }
  throw CLIError("Did not reach authenticated within 5s")
}

func waitForServerAcceptance(
  runtime: InstantRuntime,
  transactionID: String,
  timeoutSeconds: Double
) async throws {
  let stream = try await runtime.observeMutationLifecycle(id: transactionID)
  try await withThrowingTaskGroup(of: Void.self) { group in
    group.addTask {
      for await event in stream {
        switch event {
        case .serverAccepted:
          return
        case .failed(let mutation):
          throw CLIError(
            "Mutation \(transactionID) failed before server acceptance: \(mutation.status)"
          )
        case .waiting:
          continue
        }
      }
      throw CLIError("Mutation lifecycle stream ended without server acceptance")
    }
    group.addTask {
      try await Task.sleep(for: .seconds(timeoutSeconds))
      throw CLIError(
        "Timed out after \(timeoutSeconds)s waiting for server acceptance of \(transactionID)"
      )
    }
    _ = try await group.next()
    group.cancelAll()
  }
}

func percentile(_ values: [Double]) -> [String: Any] {
  guard !values.isEmpty else {
    return [
      "count": 0, "minMs": 0, "maxMs": 0, "p50Ms": 0, "p95Ms": 0, "p99Ms": 0, "meanMs": 0,
    ]
  }
  let sorted = values.sorted()
  func pick(_ p: Double) -> Double {
    let idx = min(sorted.count - 1, max(0, Int(ceil(p * Double(sorted.count))) - 1))
    return sorted[idx]
  }
  let mean = values.reduce(0, +) / Double(values.count)
  return [
    "count": values.count,
    "minMs": sorted.first ?? 0,
    "maxMs": sorted.last ?? 0,
    "p50Ms": pick(0.5),
    "p95Ms": pick(0.95),
    "p99Ms": pick(0.99),
    "meanMs": mean,
  ]
}

func seconds(_ duration: Duration) -> Double {
  let comps = duration.components
  return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
}

func writeJSON(_ object: [String: Any], to handle: FileHandle) {
  guard
    let data = try? JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys]
    )
  else { return }
  handle.write(data)
  handle.write(Data("\n".utf8))
}

struct CLIError: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}

struct Options {
  var appID: String?
  var refreshToken: String?
  var userID: String?
  var runID: String?
  var durationSeconds: Double = 15
  var maxAppRssMiB: Double = 150
  var outPath: String?
  var descriptor: String?
  var apiURI: String?
  var websocketURI: String?

  static func parse(_ args: [String]) throws -> Options {
    var o = Options()
    var i = 0
    while i < args.count {
      let a = args[i]
      func next() throws -> String {
        i += 1
        guard i < args.count else { throw CLIError("Expected value after \(a)") }
        return args[i]
      }
      switch a {
      case "--app-id": o.appID = try next()
      case "--admin-token": _ = try next()  // ignored; use refresh token
      case "--refresh-token": o.refreshToken = try next()
      case "--user-id": o.userID = try next()
      case "--run-id": o.runID = try next()
      case "--duration": o.durationSeconds = Double(try next()) ?? 15
      case "--max-app-rss-mib": o.maxAppRssMiB = Double(try next()) ?? 150
      case "--out": o.outPath = try next()
      case "--descriptor": o.descriptor = try next()
      case "--api-uri": o.apiURI = try next()
      case "--websocket-uri": o.websocketURI = try next()
      case "--help", "-h":
        print(
          "ExerciseGem --app-id ID --refresh-token T --user-id U --run-id ID --duration 15 --out path"
        )
        exit(0)
      default:
        throw CLIError("Unknown argument \(a)")
      }
      i += 1
    }
    return o
  }
}
