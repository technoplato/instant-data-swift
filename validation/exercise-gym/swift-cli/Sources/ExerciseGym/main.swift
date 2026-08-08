import Foundation
import InstantSwiftDataCore

#if canImport(Darwin)
  import Darwin
#endif

/// Exercise Gym — Swift simple + complex network write lanes.
///
/// Usage:
///   ExerciseGym --suite simple|complex --app-id … --refresh-token … --user-id …
///     --run-id … --duration 15 --out result.json
///
/// Prefer orchestrator-supplied `--refresh-token` + `--user-id`.
@main
struct ExerciseGym {
  static func main() async {
    do {
      try await run()
    } catch {
      let payload: [String: Any] = [
        "ok": false,
        "side": "swift",
        "suite": "unknown",
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
    let suite = options.suite

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
      .appendingPathComponent("exercise-gym-\(UUID().uuidString).sqlite")

    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL,
      initialAttributes: ExerciseGymSchema.attributes,
      refreshTokenVerifier: .live,
      authTokenInvalidator: .live,
      liveTransport: .live
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let session = try await runtime.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-exercise-gym-user"
    )
    guard session.userID == userID else {
      throw CLIError("Verified user \(session.userID) != expected \(userID)")
    }
    _ = try await runtime.connect()
    try await waitAuthenticated(runtime)

    let clientID = try await runtime.clientID()
    let descriptor =
      options.descriptor
      ?? "swift-cli-\(suite.rawValue)-\(ProcessInfo.processInfo.processIdentifier)"

    let memBaseline = InstantProcessMemory.sample()
    let baselineResident = memBaseline?.residentBytes ?? 0
    let baselineFootprint = memBaseline?.physicalFootprintBytes ?? 0

    FileHandle.standardError.write(
      Data("EXERCISE_GYM_READY suite=\(suite.rawValue) clientId=\(clientID)\n".utf8)
    )

    let result: [String: Any]
    switch suite {
    case .simple:
      result = try await runSimple(
        runtime: runtime,
        appID: appID,
        runID: runID,
        clientID: clientID,
        descriptor: descriptor,
        duration: duration,
        maxAppRssMiB: options.maxAppRssMiB,
        baselineResident: baselineResident,
        baselineFootprint: baselineFootprint
      )
    case .complex:
      result = try await runComplex(
        runtime: runtime,
        appID: appID,
        runID: runID,
        clientID: clientID,
        descriptor: descriptor,
        duration: duration,
        maxAppRssMiB: options.maxAppRssMiB,
        baselineResident: baselineResident,
        baselineFootprint: baselineFootprint,
        chaptersPerDoc: options.chaptersPerDoc,
        blocksPerChapter: options.blocksPerChapter,
        annotationsPerBlock: options.annotationsPerBlock
      )
    }

    if let out = options.outPath {
      let url = URL(fileURLWithPath: out)
      try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        .write(to: url)
    }
    writeJSON(result, to: FileHandle.standardOutput)
    if (result["ok"] as? Bool) != true {
      exit(2)
    }
  }
}

// MARK: - Suites

func runSimple(
  runtime: InstantRuntime,
  appID: String,
  runID: String,
  clientID: String,
  descriptor: String,
  duration: Double,
  maxAppRssMiB: Double,
  baselineResident: UInt64,
  baselineFootprint: UInt64
) async throws -> [String: Any] {
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
      source: "exercise-gym.simple"
    )
    do {
      try await waitForServerAcceptance(
        runtime: runtime,
        transactionID: mutation.transactionID,
        timeoutSeconds: 5
      )
      writesAccepted += 1
      rtts.append(Date().timeIntervalSince1970 * 1_000 - sentAt)
    } catch {
      FileHandle.standardError.write(Data("write-accept-failed seq=\(seq) \(error)\n".utf8))
    }
    if let sample = InstantProcessMemory.sample() {
      peakResident = max(peakResident, sample.residentBytes)
      peakFootprint = max(peakFootprint, sample.physicalFootprintBytes)
    }
    let appResident = peakResident > baselineResident ? peakResident - baselineResident : 0
    if Double(appResident) / (1024 * 1024) >= maxAppRssMiB { break }
  }

  return makeResult(
    suite: "simple",
    appID: appID,
    runID: runID,
    clientID: clientID,
    descriptor: descriptor,
    writesAttempted: writesAttempted,
    writesAccepted: writesAccepted,
    rtts: rtts,
    peakResident: peakResident,
    peakFootprint: peakFootprint,
    baselineResident: baselineResident,
    baselineFootprint: baselineFootprint,
    wall: seconds(ContinuousClock.now - started),
    details: [
      "counterId": counterID,
      "lastSeq": seq,
      "maxAppRssMiB": maxAppRssMiB,
      "durationSeconds": duration,
    ]
  )
}

func runComplex(
  runtime: InstantRuntime,
  appID: String,
  runID: String,
  clientID: String,
  descriptor: String,
  duration: Double,
  maxAppRssMiB: Double,
  baselineResident: UInt64,
  baselineFootprint: UInt64,
  chaptersPerDoc: Int,
  blocksPerChapter: Int,
  annotationsPerBlock: Int
) async throws -> [String: Any] {
  var docSeq = 0
  var writesAttempted = 0
  var writesAccepted = 0
  var entityCount = 0
  var rtts: [Double] = []
  var peakResident = baselineResident
  var peakFootprint = baselineFootprint
  let started = ContinuousClock.now
  let deadline = started + .seconds(duration)
  var lastDocumentID = ""

  while ContinuousClock.now < deadline {
    docSeq += 1
    let documentID = UUID().uuidString
    lastDocumentID = documentID
    let sentAt = Date().timeIntervalSince1970 * 1_000
    let built = complexGraphOps(
      documentID: documentID,
      runID: runID,
      docSeq: docSeq,
      clientID: clientID,
      descriptor: descriptor,
      updatedAtMs: sentAt,
      chaptersPerDoc: chaptersPerDoc,
      blocksPerChapter: blocksPerChapter,
      annotationsPerBlock: annotationsPerBlock
    )
    entityCount += built.entityCount
    writesAttempted += 1
    let mutation = try await runtime.transact(
      operations: built.ops,
      source: "exercise-gym.complex"
    )
    do {
      try await waitForServerAcceptance(
        runtime: runtime,
        transactionID: mutation.transactionID,
        timeoutSeconds: 5
      )
      writesAccepted += 1
      rtts.append(Date().timeIntervalSince1970 * 1_000 - sentAt)
    } catch {
      FileHandle.standardError.write(
        Data("complex-accept-failed seq=\(docSeq) \(error)\n".utf8)
      )
    }
    if let sample = InstantProcessMemory.sample() {
      peakResident = max(peakResident, sample.residentBytes)
      peakFootprint = max(peakFootprint, sample.physicalFootprintBytes)
    }
    let appResident = peakResident > baselineResident ? peakResident - baselineResident : 0
    if Double(appResident) / (1024 * 1024) >= maxAppRssMiB { break }
  }

  return makeResult(
    suite: "complex",
    appID: appID,
    runID: runID,
    clientID: clientID,
    descriptor: descriptor,
    writesAttempted: writesAttempted,
    writesAccepted: writesAccepted,
    rtts: rtts,
    peakResident: peakResident,
    peakFootprint: peakFootprint,
    baselineResident: baselineResident,
    baselineFootprint: baselineFootprint,
    wall: seconds(ContinuousClock.now - started),
    details: [
      "lastDocSeq": docSeq,
      "lastDocumentId": lastDocumentID,
      "entityCount": entityCount,
      "chaptersPerDoc": chaptersPerDoc,
      "blocksPerChapter": blocksPerChapter,
      "annotationsPerBlock": annotationsPerBlock,
      "maxAppRssMiB": maxAppRssMiB,
      "durationSeconds": duration,
    ]
  )
}

func makeResult(
  suite: String,
  appID: String,
  runID: String,
  clientID: String,
  descriptor: String,
  writesAttempted: Int,
  writesAccepted: Int,
  rtts: [Double],
  peakResident: UInt64,
  peakFootprint: UInt64,
  baselineResident: UInt64,
  baselineFootprint: UInt64,
  wall: Double,
  details: [String: Any]
) -> [String: Any] {
  let peakAppResident = peakResident > baselineResident ? peakResident - baselineResident : 0
  let peakAppFootprint = peakFootprint > baselineFootprint ? peakFootprint - baselineFootprint : 0
  return [
    "ok": writesAccepted > 0,
    "side": "swift",
    "suite": suite,
    "runId": runID,
    "appID": appID,
    "identity": [
      "clientId": clientID,
      "descriptor": descriptor,
    ],
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
      "latency": percentile(rtts),
      "peakRssBytes": peakResident,
      "peakRssMiB": Double(peakResident) / (1024 * 1024),
      "peakAppAttributedRssBytes": peakAppResident,
      "peakAppAttributedRssMiB": Double(peakAppResident) / (1024 * 1024),
      "peakPhysicalFootprintBytes": peakFootprint,
      "peakAppAttributedFootprintMiB": Double(peakAppFootprint) / (1024 * 1024),
      "bootBaselineResidentBytes": baselineResident,
    ],
    "details": details,
  ]
}

// MARK: - Schema (mirrors validation/exercise-gym schema)

enum ExerciseGymSchema {
  static var attributes: [InstantAttribute] {
    counterAttributes
      + documentAttributes
      + chapterAttributes
      + blockAttributes
      + annotationAttributes
  }

  private static func attr(
    ns: String,
    _ name: String,
    _ type: InstantValueType,
    indexed: Bool = false
  ) -> InstantAttribute {
    InstantAttribute(
      id: "\(ns)/\(name)",
      namespace: ns,
      name: name,
      valueType: type,
      isIndexed: indexed
    )
  }

  static var counterAttributes: [InstantAttribute] {
    let ns = "counters"
    return [
      .primaryKey(namespace: ns),
      attr(ns: ns, "runId", .string, indexed: true),
      attr(ns: ns, "name", .string, indexed: true),
      attr(ns: ns, "value", .number, indexed: true),
      attr(ns: ns, "seq", .number, indexed: true),
      attr(ns: ns, "clientId", .string, indexed: true),
      attr(ns: ns, "descriptor", .string, indexed: true),
      attr(ns: ns, "payloadBytes", .number),
      attr(ns: ns, "updatedAtMs", .number, indexed: true),
    ]
  }

  static var documentAttributes: [InstantAttribute] {
    let ns = "documents"
    return [
      .primaryKey(namespace: ns),
      attr(ns: ns, "runId", .string, indexed: true),
      attr(ns: ns, "title", .string, indexed: true),
      attr(ns: ns, "seq", .number, indexed: true),
      attr(ns: ns, "clientId", .string, indexed: true),
      attr(ns: ns, "descriptor", .string, indexed: true),
      attr(ns: ns, "summaryJSON", .string),
      attr(ns: ns, "updatedAtMs", .number, indexed: true),
    ]
  }

  static var chapterAttributes: [InstantAttribute] {
    let ns = "chapters"
    return [
      .primaryKey(namespace: ns),
      attr(ns: ns, "runId", .string, indexed: true),
      attr(ns: ns, "documentId", .string, indexed: true),
      attr(ns: ns, "title", .string),
      attr(ns: ns, "order", .number, indexed: true),
      attr(ns: ns, "seq", .number, indexed: true),
      attr(ns: ns, "clientId", .string, indexed: true),
      attr(ns: ns, "descriptor", .string, indexed: true),
      attr(ns: ns, "bodyJSON", .string),
      attr(ns: ns, "updatedAtMs", .number, indexed: true),
      InstantAttribute(
        id: "\(ns)/document",
        namespace: ns,
        name: "document",
        valueType: .ref,
        isRequired: false,
        isIndexed: true,
        forwardIdentity: "\(ns)/document",
        reverseIdentity: "documents/chapters",
        linkNamespace: "documents",
        onDelete: .cascade
      ),
    ]
  }

  static var blockAttributes: [InstantAttribute] {
    let ns = "blocks"
    return [
      .primaryKey(namespace: ns),
      attr(ns: ns, "runId", .string, indexed: true),
      attr(ns: ns, "chapterId", .string, indexed: true),
      attr(ns: ns, "kind", .string, indexed: true),
      attr(ns: ns, "text", .string),
      attr(ns: ns, "order", .number, indexed: true),
      attr(ns: ns, "seq", .number, indexed: true),
      attr(ns: ns, "clientId", .string, indexed: true),
      attr(ns: ns, "descriptor", .string, indexed: true),
      attr(ns: ns, "metaJSON", .string),
      attr(ns: ns, "updatedAtMs", .number, indexed: true),
      InstantAttribute(
        id: "\(ns)/chapter",
        namespace: ns,
        name: "chapter",
        valueType: .ref,
        isRequired: false,
        isIndexed: true,
        forwardIdentity: "\(ns)/chapter",
        reverseIdentity: "chapters/blocks",
        linkNamespace: "chapters",
        onDelete: .cascade
      ),
    ]
  }

  static var annotationAttributes: [InstantAttribute] {
    let ns = "annotations"
    return [
      .primaryKey(namespace: ns),
      attr(ns: ns, "runId", .string, indexed: true),
      attr(ns: ns, "blockId", .string, indexed: true),
      attr(ns: ns, "note", .string),
      attr(ns: ns, "score", .number, indexed: true),
      attr(ns: ns, "seq", .number, indexed: true),
      attr(ns: ns, "clientId", .string, indexed: true),
      attr(ns: ns, "descriptor", .string, indexed: true),
      attr(ns: ns, "updatedAtMs", .number, indexed: true),
      InstantAttribute(
        id: "\(ns)/block",
        namespace: ns,
        name: "block",
        valueType: .ref,
        isRequired: false,
        isIndexed: true,
        forwardIdentity: "\(ns)/block",
        reverseIdentity: "blocks/annotations",
        linkNamespace: "blocks",
        onDelete: .cascade
      ),
    ]
  }
}

// MARK: - Ops builders

func counterUpsertOps(
  counterID: String,
  runID: String,
  seq: Int,
  clientID: String,
  descriptor: String,
  updatedAtMs: Double
) -> [InstantTripleOperation] {
  let ns = "counters"
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

struct BuiltGraph {
  var ops: [InstantTripleOperation]
  var entityCount: Int
}

func complexGraphOps(
  documentID: String,
  runID: String,
  docSeq: Int,
  clientID: String,
  descriptor: String,
  updatedAtMs: Double,
  chaptersPerDoc: Int,
  blocksPerChapter: Int,
  annotationsPerBlock: Int
) -> BuiltGraph {
  let now = InstantTimestamp(milliseconds: Int64(updatedAtMs))
  let txID = UUID().uuidString
  var ops: [InstantTripleOperation] = []
  var entityCount = 0

  func insertEntity(ns: String, id: String, fields: [(String, InstantValue)], link: (attr: String, target: String)? = nil) {
    ops.append(
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: InstantAttribute.primaryKeyID(namespace: ns),
          value: .string(id),
          txID: txID,
          txTime: now
        )
      )
    )
    for (name, value) in fields {
      ops.append(
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "\(ns)/\(name)",
            value: value,
            txID: txID,
            txTime: now
          )
        )
      )
    }
    if let link {
      ops.append(
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "\(ns)/\(link.attr)",
            value: .ref(link.target),
            txID: txID,
            txTime: now
          )
        )
      )
    }
    entityCount += 1
  }

  let body = "complex-body-\(docSeq)"
  insertEntity(
    ns: "documents",
    id: documentID,
    fields: [
      ("runId", .string(runID)),
      ("title", .string("doc-\(docSeq)")),
      ("seq", .number(Double(docSeq))),
      ("clientId", .string(clientID)),
      ("descriptor", .string(descriptor)),
      ("summaryJSON", .string("{\"body\":\"\(body)\",\"docSeq\":\(docSeq)}")),
      ("updatedAtMs", .number(updatedAtMs)),
    ]
  )

  for c in 0..<chaptersPerDoc {
    let chapterID = UUID().uuidString
    insertEntity(
      ns: "chapters",
      id: chapterID,
      fields: [
        ("runId", .string(runID)),
        ("documentId", .string(documentID)),
        ("title", .string("ch-\(docSeq)-\(c)")),
        ("order", .number(Double(c))),
        ("seq", .number(Double(docSeq))),
        ("clientId", .string(clientID)),
        ("descriptor", .string(descriptor)),
        ("bodyJSON", .string("{\"c\":\(c),\"body\":\"\(body)\"}")),
        ("updatedAtMs", .number(updatedAtMs)),
      ],
      link: ("document", documentID)
    )
    for b in 0..<blocksPerChapter {
      let blockID = UUID().uuidString
      insertEntity(
        ns: "blocks",
        id: blockID,
        fields: [
          ("runId", .string(runID)),
          ("chapterId", .string(chapterID)),
          ("kind", .string(b % 2 == 0 ? "paragraph" : "code")),
          ("text", .string(String(body.prefix(80)))),
          ("order", .number(Double(b))),
          ("seq", .number(Double(docSeq))),
          ("clientId", .string(clientID)),
          ("descriptor", .string(descriptor)),
          ("metaJSON", .string("{\"b\":\(b),\"c\":\(c),\"docSeq\":\(docSeq)}")),
          ("updatedAtMs", .number(updatedAtMs)),
        ],
        link: ("chapter", chapterID)
      )
      for a in 0..<annotationsPerBlock {
        let annotationID = UUID().uuidString
        insertEntity(
          ns: "annotations",
          id: annotationID,
          fields: [
            ("runId", .string(runID)),
            ("blockId", .string(blockID)),
            ("note", .string("note-\(docSeq)-\(c)-\(b)-\(a)")),
            ("score", .number(Double(a))),
            ("seq", .number(Double(docSeq))),
            ("clientId", .string(clientID)),
            ("descriptor", .string(descriptor)),
            ("updatedAtMs", .number(updatedAtMs)),
          ],
          link: ("block", blockID)
        )
      }
    }
  }

  return BuiltGraph(ops: ops, entityCount: entityCount)
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

enum Suite: String {
  case simple
  case complex
}

struct Options {
  var suite: Suite = .simple
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
  var chaptersPerDoc: Int = 2
  var blocksPerChapter: Int = 3
  var annotationsPerBlock: Int = 2

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
      case "--suite":
        let raw = try next()
        guard let s = Suite(rawValue: raw) else {
          throw CLIError("Unknown suite \(raw); use simple|complex")
        }
        o.suite = s
      case "--app-id": o.appID = try next()
      case "--admin-token": _ = try next()
      case "--refresh-token": o.refreshToken = try next()
      case "--user-id": o.userID = try next()
      case "--run-id": o.runID = try next()
      case "--duration": o.durationSeconds = Double(try next()) ?? 15
      case "--max-app-rss-mib": o.maxAppRssMiB = Double(try next()) ?? 150
      case "--out": o.outPath = try next()
      case "--descriptor": o.descriptor = try next()
      case "--api-uri": o.apiURI = try next()
      case "--websocket-uri": o.websocketURI = try next()
      case "--chapters-per-doc": o.chaptersPerDoc = Int(try next()) ?? 2
      case "--blocks-per-chapter": o.blocksPerChapter = Int(try next()) ?? 3
      case "--annotations-per-block": o.annotationsPerBlock = Int(try next()) ?? 2
      case "--help", "-h":
        print(
          """
          ExerciseGym --suite simple|complex --app-id ID --refresh-token T --user-id U \\
            --run-id ID --duration 15 --out path
          """
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
