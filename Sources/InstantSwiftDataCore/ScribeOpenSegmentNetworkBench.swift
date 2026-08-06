import Foundation

#if canImport(Darwin)
  import Darwin
#endif

// MARK: - #156 Scribe open-segment network write/observe bench
//
// Product write shape: one recording, one open segment, words as JSON on the
// segment (not word entities). Validity: another process must observe `seq`
// advances over the live network. Compare only network-vs-network (or later
// local-vs-local) — never mix.

/// Namespaces and attributes for the open-segment 20s network bench.
public enum ScribeOpenSegmentNetworkBenchSchema: Sendable {
  public static let recordingNamespace = "recordings"
  public static let segmentNamespace = "transcriptionSegments"

  public static var attributes: [InstantAttribute] {
    recordingAttributes + segmentAttributes
  }

  private static var recordingAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: recordingNamespace),
      InstantAttribute(
        id: "\(recordingNamespace)/title",
        namespace: recordingNamespace,
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(recordingNamespace)/updatedAtMs",
        namespace: recordingNamespace,
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }

  private static var segmentAttributes: [InstantAttribute] {
    [
      .primaryKey(namespace: segmentNamespace),
      InstantAttribute(
        id: "\(segmentNamespace)/recordingID",
        namespace: segmentNamespace,
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/text",
        namespace: segmentNamespace,
        name: "text",
        valueType: .string
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/wordsJSON",
        namespace: segmentNamespace,
        name: "wordsJSON",
        valueType: .string
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/wordCount",
        namespace: segmentNamespace,
        name: "wordCount",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/seq",
        namespace: segmentNamespace,
        name: "seq",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/updatedAtMs",
        namespace: segmentNamespace,
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "\(segmentNamespace)/recording",
        namespace: segmentNamespace,
        name: "recording",
        valueType: .ref,
        isRequired: true,
        isIndexed: true,
        forwardIdentity: "\(segmentNamespace)/recording",
        reverseIdentity: "\(recordingNamespace)/segments",
        linkNamespace: recordingNamespace,
        onDelete: .cascade
      ),
    ]
  }

  public static func segmentQuery(segmentID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "bench.open-segment.segment",
      namespace: segmentNamespace,
      filters: [.equals(field: "id", value: .string(segmentID))],
      limit: 1
    )
  }
}

/// One synthetic speech word for the open-segment wordsJSON blob.
public struct ScribeOpenSegmentBenchWord: Codable, Equatable, Sendable {
  public var start: Double
  public var end: Double
  public var text: String

  public init(start: Double, end: Double, text: String) {
    self.start = start
    self.end = end
    self.text = text
  }
}

public struct ScribeOpenSegmentBenchProcessMetrics: Codable, Equatable, Sendable {
  public var footprintStartBytes: UInt64?
  public var footprintPeakBytes: UInt64?
  public var footprintEndBytes: UInt64?
  public var residentPeakBytes: UInt64?
  public var cpuUserSeconds: Double?
  public var cpuSystemSeconds: Double?

  public init(
    footprintStartBytes: UInt64? = nil,
    footprintPeakBytes: UInt64? = nil,
    footprintEndBytes: UInt64? = nil,
    residentPeakBytes: UInt64? = nil,
    cpuUserSeconds: Double? = nil,
    cpuSystemSeconds: Double? = nil
  ) {
    self.footprintStartBytes = footprintStartBytes
    self.footprintPeakBytes = footprintPeakBytes
    self.footprintEndBytes = footprintEndBytes
    self.residentPeakBytes = residentPeakBytes
    self.cpuUserSeconds = cpuUserSeconds
    self.cpuSystemSeconds = cpuSystemSeconds
  }
}

public struct ScribeOpenSegmentBenchResult: Codable, Equatable, Sendable {
  public var suite: String
  public var side: String
  public var role: String
  public var scenario: String
  public var appID: String
  public var recordingID: String
  public var segmentID: String
  public var durationSeconds: Double
  public var wallSeconds: Double
  public var writesAttempted: Int
  public var validWritesObserved: Int
  public var maxSeqSeen: Int
  public var finalWordCount: Int
  public var wordsPerUpsert: Int
  public var ok: Bool
  public var process: ScribeOpenSegmentBenchProcessMetrics
  public var notes: [String]
  public var timestampMs: Int64

  public init(
    suite: String = "scribe-open-segment-20s-network",
    side: String,
    role: String,
    scenario: String,
    appID: String,
    recordingID: String,
    segmentID: String,
    durationSeconds: Double,
    wallSeconds: Double,
    writesAttempted: Int,
    validWritesObserved: Int,
    maxSeqSeen: Int,
    finalWordCount: Int,
    wordsPerUpsert: Int,
    ok: Bool,
    process: ScribeOpenSegmentBenchProcessMetrics,
    notes: [String] = [],
    timestampMs: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
  ) {
    self.suite = suite
    self.side = side
    self.role = role
    self.scenario = scenario
    self.appID = appID
    self.recordingID = recordingID
    self.segmentID = segmentID
    self.durationSeconds = durationSeconds
    self.wallSeconds = wallSeconds
    self.writesAttempted = writesAttempted
    self.validWritesObserved = validWritesObserved
    self.maxSeqSeen = maxSeqSeen
    self.finalWordCount = finalWordCount
    self.wordsPerUpsert = wordsPerUpsert
    self.ok = ok
    self.process = process
    self.notes = notes
    self.timestampMs = timestampMs
  }
}

/// Live open-segment writer/observer for Instant Swift Data (#156).
public enum ScribeOpenSegmentNetworkBench {
  public static let defaultDurationSeconds: Double = 20
  public static let defaultWordsPerUpsert = 12

  public static func runWriter(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    refreshToken: String,
    expectedUserID: String,
    recordingID: String,
    segmentID: String,
    durationSeconds: Double = defaultDurationSeconds,
    wordsPerUpsert: Int = defaultWordsPerUpsert,
    scenario: String,
    persistenceURL: URL? = nil
  ) async throws -> ScribeOpenSegmentBenchResult {
    let runtime = try await bootstrap(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(runtime, refreshToken: refreshToken, expectedUserID: expectedUserID)

    // Seed parent + open segment if missing (idempotent enough for bench).
    try await seedIfNeeded(
      runtime: runtime,
      recordingID: recordingID,
      segmentID: segmentID
    )
    // Orchestrator waits for this line before starting the peer / scoring clock.
    FileHandle.standardError.write(Data("BENCH_READY role=writer\n".utf8))

    let cpuStart = cpuUsage()
    let memStart = InstantProcessMemory.sample()
    var peakFootprint = memStart?.physicalFootprintBytes ?? 0
    var peakResident = memStart?.residentBytes ?? 0

    var words: [ScribeOpenSegmentBenchWord] = []
    var seq = 0
    var writesAttempted = 0
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let started = ContinuousClock.now
    let deadline = started + .seconds(durationSeconds)

    while ContinuousClock.now < deadline {
      seq += 1
      let base = Double(words.count) * 0.08
      for index in 0..<wordsPerUpsert {
        let start = base + Double(index) * 0.08
        words.append(
          ScribeOpenSegmentBenchWord(
            start: start,
            end: start + 0.07,
            text: "w\(words.count + 1)"
          )
        )
      }
      let wordsJSON = try String(decoding: encoder.encode(words), as: UTF8.self)
      let text = words.suffix(24).map(\.text).joined(separator: " ")
      let nowMs = Date().timeIntervalSince1970 * 1_000
      let ops = segmentUpsertOperations(
        segmentID: segmentID,
        recordingID: recordingID,
        text: text,
        wordsJSON: wordsJSON,
        wordCount: words.count,
        seq: seq,
        updatedAtMs: nowMs
      )
      let mutation = try await runtime.transact(
        operations: ops,
        source: "bench.open-segment.writer"
      )
      // Network validity: only count writes that leave the local outbox for the server.
      try await waitForServerAcceptance(
        runtime: runtime,
        transactionID: mutation.transactionID,
        timeoutSeconds: 5
      )
      writesAttempted += 1
      if let sample = InstantProcessMemory.sample() {
        peakFootprint = max(peakFootprint, sample.physicalFootprintBytes)
        peakResident = max(peakResident, sample.residentBytes)
      }
    }

    let wall = ContinuousClock.now - started
    let wallSeconds = seconds(wall)
    let memEnd = InstantProcessMemory.sample()
    let cpuEnd = cpuUsage()

    return ScribeOpenSegmentBenchResult(
      side: "swift",
      role: "writer",
      scenario: scenario,
      appID: appID,
      recordingID: recordingID,
      segmentID: segmentID,
      durationSeconds: durationSeconds,
      wallSeconds: wallSeconds,
      writesAttempted: writesAttempted,
      validWritesObserved: 0,
      maxSeqSeen: seq,
      finalWordCount: words.count,
      wordsPerUpsert: wordsPerUpsert,
      ok: writesAttempted > 0,
      process: ScribeOpenSegmentBenchProcessMetrics(
        footprintStartBytes: memStart?.physicalFootprintBytes,
        footprintPeakBytes: peakFootprint == 0 ? memEnd?.physicalFootprintBytes : peakFootprint,
        footprintEndBytes: memEnd?.physicalFootprintBytes,
        residentPeakBytes: peakResident == 0 ? memEnd?.residentBytes : peakResident,
        cpuUserSeconds: cpuEnd.user - cpuStart.user,
        cpuSystemSeconds: cpuEnd.system - cpuStart.system
      ),
      notes: [
        "Writer free-runs for duration; valid count comes from the observer process.",
        "Words stored as JSON string on the open segment (no word entities).",
      ]
    )
  }

  public static func runObserver(
    appID: String,
    apiURI: URL = InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: URL = InstantRuntimeConfiguration.defaultWebSocketURI,
    refreshToken: String,
    expectedUserID: String,
    recordingID: String,
    segmentID: String,
    durationSeconds: Double = defaultDurationSeconds,
    wordsPerUpsert: Int = defaultWordsPerUpsert,
    scenario: String,
    persistenceURL: URL? = nil
  ) async throws -> ScribeOpenSegmentBenchResult {
    let runtime = try await bootstrap(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
    )
    try await authenticate(runtime, refreshToken: refreshToken, expectedUserID: expectedUserID)

    let plan = ScribeOpenSegmentNetworkBenchSchema.segmentQuery(segmentID: segmentID)
    // Register observation so live refreshes materialize into the local store.
    let stream = await runtime.observe(plan)
    let consumeTask = Task {
      for await _ in stream {
        if Task.isCancelled { break }
      }
    }
    defer { consumeTask.cancel() }

    // Warm the query once so the first remote refresh path is established.
    _ = try? await runtime.queryOnce(plan)
    FileHandle.standardError.write(Data("BENCH_READY role=observer\n".utf8))

    let cpuStart = cpuUsage()
    let memStart = InstantProcessMemory.sample()
    var peakFootprint = memStart?.physicalFootprintBytes ?? 0
    var peakResident = memStart?.residentBytes ?? 0

    var maxSeqSeen = 0
    var finalWordCount = 0
    // Seed always starts at seq 0; first sight must not become the baseline or
    // a late first poll undercounts every intermediate write.
    let baselineSeq = 0
    let started = ContinuousClock.now
    let deadline = started + .seconds(durationSeconds)

    while ContinuousClock.now < deadline {
      if let emission = try? await runtime.queryOnce(plan) {
        if let seq = seq(from: emission) {
          maxSeqSeen = max(maxSeqSeen, seq)
        }
        if let count = wordCount(from: emission) {
          finalWordCount = max(finalWordCount, count)
        }
      }
      if let sample = InstantProcessMemory.sample() {
        peakFootprint = max(peakFootprint, sample.physicalFootprintBytes)
        peakResident = max(peakResident, sample.residentBytes)
      }
      try await Task.sleep(for: .milliseconds(25))
    }

    let wall = ContinuousClock.now - started
    let wallSeconds = seconds(wall)
    let memEnd = InstantProcessMemory.sample()
    let cpuEnd = cpuUsage()
    let valid = max(0, maxSeqSeen - baselineSeq)

    return ScribeOpenSegmentBenchResult(
      side: "swift",
      role: "observer",
      scenario: scenario,
      appID: appID,
      recordingID: recordingID,
      segmentID: segmentID,
      durationSeconds: durationSeconds,
      wallSeconds: wallSeconds,
      writesAttempted: 0,
      validWritesObserved: valid,
      maxSeqSeen: maxSeqSeen,
      finalWordCount: finalWordCount,
      wordsPerUpsert: wordsPerUpsert,
      ok: true,
      process: ScribeOpenSegmentBenchProcessMetrics(
        footprintStartBytes: memStart?.physicalFootprintBytes,
        footprintPeakBytes: peakFootprint == 0 ? memEnd?.physicalFootprintBytes : peakFootprint,
        footprintEndBytes: memEnd?.physicalFootprintBytes,
        residentPeakBytes: peakResident == 0 ? memEnd?.residentBytes : peakResident,
        cpuUserSeconds: cpuEnd.user - cpuStart.user,
        cpuSystemSeconds: cpuEnd.system - cpuStart.system
      ),
      notes: [
        "validWritesObserved = maxSeqSeen - seed baseline 0 (monotonic advances observed live).",
        "Physical footprint only (never VSZ as a gate).",
      ]
    )
  }

  // MARK: - Internals

  private static func waitForServerAcceptance(
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
            throw InstantError(
              code: .networkFailed,
              operation: "open-segment bench write acceptance",
              message: "Mutation \(transactionID) failed before server acceptance: \(mutation.status).",
              recovery: "Inspect outbox and server permission/schema errors."
            )
          case .waiting:
            continue
          }
        }
        throw InstantError(
          code: .networkFailed,
          operation: "open-segment bench write acceptance",
          message: "Mutation lifecycle stream ended without server acceptance.",
          recovery: "Ensure the live transport remains connected."
        )
      }
      group.addTask {
        try await Task.sleep(for: .seconds(timeoutSeconds))
        throw InstantError(
          code: .networkFailed,
          operation: "open-segment bench write acceptance",
          message: "Timed out after \(timeoutSeconds)s waiting for server acceptance of \(transactionID).",
          recovery: "Check Instant connectivity and outbox delivery."
        )
      }
      _ = try await group.next()
      group.cancelAll()
    }
  }


  private static func bootstrap(
    appID: String,
    apiURI: URL,
    websocketURI: URL,
    persistenceURL: URL?
  ) async throws -> InstantRuntime {
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      apiURI: apiURI,
      websocketURI: websocketURI,
      persistenceURL: persistenceURL
        ?? FileManager.default.temporaryDirectory
        .appendingPathComponent("scribe-open-segment-bench-\(UUID().uuidString).sqlite"),
      initialAttributes: ScribeOpenSegmentNetworkBenchSchema.attributes,
      refreshTokenVerifier: .live,
      authTokenInvalidator: .live,
      liveTransport: .live
    )
    configuration.autoConnectLiveTransport = true
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  private static func authenticate(
    _ runtime: InstantRuntime,
    refreshToken: String,
    expectedUserID: String
  ) async throws {
    let session = try await runtime.signInWithRefreshToken(
      refreshToken,
      userID: "untrusted-open-segment-bench-user"
    )
    guard session.userID == expectedUserID else {
      throw InstantError(
        code: .authFailed,
        operation: "authenticate open-segment bench",
        message: "Server-verified user did not match expected user.",
        recovery: "Recreate the refresh token from admin and retry."
      )
    }
    _ = try await runtime.connect()
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      if try await runtime.connectionStatus().state == .authenticated {
        return
      }
      try await Task.sleep(for: .milliseconds(25))
    }
    throw InstantError(
      code: .networkFailed,
      operation: "wait for open-segment bench authentication",
      message: "Live client did not reach authenticated within 5 seconds.",
      recovery: "Check credentials, network, and Instant app schema."
    )
  }

  private static func seedIfNeeded(
    runtime: InstantRuntime,
    recordingID: String,
    segmentID: String
  ) async throws {
    let nowMs = Date().timeIntervalSince1970 * 1_000
    let now = InstantTimestamp(milliseconds: Int64(nowMs))
    let txID = UUID().uuidString
    let recordingOps: [InstantTripleOperation] = [
      .insert(
        InstantTriple(
          entityID: recordingID,
          attributeID: InstantAttribute.primaryKeyID(
            namespace: ScribeOpenSegmentNetworkBenchSchema.recordingNamespace
          ),
          value: .string(recordingID),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: recordingID,
          attributeID: "\(ScribeOpenSegmentNetworkBenchSchema.recordingNamespace)/title",
          value: .string("open-segment-bench-fast-speech"),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: recordingID,
          attributeID: "\(ScribeOpenSegmentNetworkBenchSchema.recordingNamespace)/updatedAtMs",
          value: .number(nowMs),
          txID: txID,
          txTime: now
        )
      ),
    ]
    let segmentOps = segmentUpsertOperations(
      segmentID: segmentID,
      recordingID: recordingID,
      text: "",
      wordsJSON: "[]",
      wordCount: 0,
      seq: 0,
      updatedAtMs: nowMs
    )
    _ = try await runtime.transact(
      operations: recordingOps + segmentOps,
      source: "bench.open-segment.seed"
    )
  }

  public static func segmentUpsertOperations(
    segmentID: String,
    recordingID: String,
    text: String,
    wordsJSON: String,
    wordCount: Int,
    seq: Int,
    updatedAtMs: Double
  ) -> [InstantTripleOperation] {
    let ns = ScribeOpenSegmentNetworkBenchSchema.segmentNamespace
    let now = InstantTimestamp(milliseconds: Int64(updatedAtMs))
    let txID = UUID().uuidString
    return [
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: InstantAttribute.primaryKeyID(namespace: ns),
          value: .string(segmentID),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(ns)/recordingID",
          value: .string(recordingID),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(ns)/text",
          value: .string(text),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(ns)/wordsJSON",
          value: .string(wordsJSON),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(ns)/wordCount",
          value: .number(Double(wordCount)),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(ns)/seq",
          value: .number(Double(seq)),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(ns)/updatedAtMs",
          value: .number(updatedAtMs),
          txID: txID,
          txTime: now
        )
      ),
      .insert(
        InstantTriple(
          entityID: segmentID,
          attributeID: "\(ns)/recording",
          value: .ref(recordingID),
          txID: txID,
          txTime: now
        )
      ),
    ]
  }

  private static func seq(from emission: InstantQueryEmission) -> Int? {
    guard let entity = emission.values.first else { return nil }
    if case let .number(value) = entity.values["seq"]?.first {
      return Int(value)
    }
    return nil
  }

  private static func wordCount(from emission: InstantQueryEmission) -> Int? {
    guard let entity = emission.values.first else { return nil }
    if case let .number(value) = entity.values["wordCount"]?.first {
      return Int(value)
    }
    return nil
  }

  private static func seconds(_ duration: ContinuousClock.Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1e18
  }

  private static func cpuUsage() -> (user: Double, system: Double) {
    #if canImport(Darwin)
      var usage = rusage()
      getrusage(RUSAGE_SELF, &usage)
      let user =
        Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
      let system =
        Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
      return (user, system)
    #else
      return (0, 0)
    #endif
  }
}
