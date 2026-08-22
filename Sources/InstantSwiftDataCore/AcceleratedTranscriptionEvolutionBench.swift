import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// A product-shaped transcript evolution profile.
///
/// The two-hour profile repeatedly replaces one bounded open segment instead
/// of retaining or diffing a growing transcript document. Each finalized
/// segment becomes immutable before the next segment identity is allocated.
public struct AcceleratedTranscriptionEvolutionProfile: Codable, Equatable, Sendable {
  public var name: String
  public var logicalDurationSeconds: Int
  public var minimumAcceleration: Double
  public var humanWordsPerMinute: Int
  public var segmentDurationSeconds: Int
  public var wordsPerSegment: Int
  public var revisionsPerSegment: Int
  public var sampleEveryRevisionCount: Int

  public init(
    name: String,
    logicalDurationSeconds: Int,
    minimumAcceleration: Double,
    humanWordsPerMinute: Int = 150,
    segmentDurationSeconds: Int = 8,
    wordsPerSegment: Int = 20,
    revisionsPerSegment: Int = 10,
    sampleEveryRevisionCount: Int = 250
  ) {
    self.name = name
    self.logicalDurationSeconds = logicalDurationSeconds
    self.minimumAcceleration = minimumAcceleration
    self.humanWordsPerMinute = humanWordsPerMinute
    self.segmentDurationSeconds = segmentDurationSeconds
    self.wordsPerSegment = wordsPerSegment
    self.revisionsPerSegment = revisionsPerSegment
    self.sampleEveryRevisionCount = sampleEveryRevisionCount
  }

  public static let twoHoursAt100x = Self(
    name: "two-hours-100x",
    logicalDurationSeconds: 7_200,
    minimumAcceleration: 100
  )

  public static let smoke = Self(
    name: "smoke",
    logicalDurationSeconds: 32,
    minimumAcceleration: 0,
    sampleEveryRevisionCount: 5
  )

  public var segmentCount: Int {
    logicalDurationSeconds / segmentDurationSeconds
  }

  public var finalWordCount: Int {
    segmentCount * wordsPerSegment
  }

  public var revisionCount: Int {
    segmentCount * revisionsPerSegment
  }

  public var wallBudgetSeconds: Double {
    guard minimumAcceleration > 0 else { return .infinity }
    return Double(logicalDurationSeconds) / minimumAcceleration
  }

  public var targetRevisionThroughput: Double {
    guard wallBudgetSeconds.isFinite else { return 0 }
    return Double(revisionCount) / wallBudgetSeconds
  }

  public func validate() throws {
    guard logicalDurationSeconds > 0,
      segmentDurationSeconds > 0,
      logicalDurationSeconds.isMultiple(of: segmentDurationSeconds),
      wordsPerSegment > 0,
      revisionsPerSegment > 0,
      wordsPerSegment.isMultiple(of: revisionsPerSegment),
      sampleEveryRevisionCount > 0
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "validate accelerated transcription profile",
        message: "The accelerated transcription profile is not internally consistent.",
        recovery: "Use a positive logical duration divisible by the segment duration and a word count divisible by the revision count."
      )
    }
  }
}

public struct AcceleratedTranscriptWord: Codable, Equatable, Sendable {
  public var index: Int
  public var text: String
  public var startMilliseconds: Int
  public var endMilliseconds: Int
  public var speaker: Int

  public init(
    index: Int,
    text: String,
    startMilliseconds: Int,
    endMilliseconds: Int,
    speaker: Int
  ) {
    self.index = index
    self.text = text
    self.startMilliseconds = startMilliseconds
    self.endMilliseconds = endMilliseconds
    self.speaker = speaker
  }
}

public struct AcceleratedTranscriptPayload: Codable, Equatable, Sendable {
  public var segmentIndex: Int
  public var revision: Int
  public var isFinal: Bool
  public var logicalStartMilliseconds: Int
  public var logicalEndMilliseconds: Int
  public var words: [AcceleratedTranscriptWord]

  public init(
    segmentIndex: Int,
    revision: Int,
    isFinal: Bool,
    logicalStartMilliseconds: Int,
    logicalEndMilliseconds: Int,
    words: [AcceleratedTranscriptWord]
  ) {
    self.segmentIndex = segmentIndex
    self.revision = revision
    self.isFinal = isFinal
    self.logicalStartMilliseconds = logicalStartMilliseconds
    self.logicalEndMilliseconds = logicalEndMilliseconds
    self.words = words
  }
}

public struct AcceleratedProcessSample: Codable, Equatable, Sendable {
  public var elapsedSeconds: Double
  public var logicalSecondsCompleted: Double
  public var physicalFootprintBytes: UInt64?
  public var residentBytes: UInt64?
  public var pendingMutationCount: Int

  public init(
    elapsedSeconds: Double,
    logicalSecondsCompleted: Double,
    physicalFootprintBytes: UInt64?,
    residentBytes: UInt64?,
    pendingMutationCount: Int
  ) {
    self.elapsedSeconds = elapsedSeconds
    self.logicalSecondsCompleted = logicalSecondsCompleted
    self.physicalFootprintBytes = physicalFootprintBytes
    self.residentBytes = residentBytes
    self.pendingMutationCount = pendingMutationCount
  }
}

public struct AcceleratedCPUUsage: Codable, Equatable, Sendable {
  public var userSeconds: Double
  public var systemSeconds: Double
  public var averagePercentOfOneCore: Double

  public init(userSeconds: Double, systemSeconds: Double, averagePercentOfOneCore: Double) {
    self.userSeconds = userSeconds
    self.systemSeconds = systemSeconds
    self.averagePercentOfOneCore = averagePercentOfOneCore
  }
}

public struct AcceleratedMemoryUsage: Codable, Equatable, Sendable {
  public var baselinePhysicalFootprintBytes: UInt64?
  public var peakPhysicalFootprintBytes: UInt64?
  public var endPhysicalFootprintBytes: UInt64?
  public var incrementalPeakPhysicalFootprintBytes: Int64?
  public var settledPhysicalFootprintGrowthBytes: Int64?
  public var peakResidentBytes: UInt64?

  public init(
    baselinePhysicalFootprintBytes: UInt64?,
    peakPhysicalFootprintBytes: UInt64?,
    endPhysicalFootprintBytes: UInt64?,
    incrementalPeakPhysicalFootprintBytes: Int64?,
    settledPhysicalFootprintGrowthBytes: Int64?,
    peakResidentBytes: UInt64?
  ) {
    self.baselinePhysicalFootprintBytes = baselinePhysicalFootprintBytes
    self.peakPhysicalFootprintBytes = peakPhysicalFootprintBytes
    self.endPhysicalFootprintBytes = endPhysicalFootprintBytes
    self.incrementalPeakPhysicalFootprintBytes = incrementalPeakPhysicalFootprintBytes
    self.settledPhysicalFootprintGrowthBytes = settledPhysicalFootprintGrowthBytes
    self.peakResidentBytes = peakResidentBytes
  }
}

public struct AcceleratedTranscriptionEvolutionResult: Codable, Equatable, Sendable {
  public var protocolVersion: Int
  public var sdk: String
  public var profile: AcceleratedTranscriptionEvolutionProfile
  public var burstWallSeconds: Double
  public var settleWallSeconds: Double
  public var totalWallSeconds: Double
  public var effectiveAcceleration: Double
  public var revisionThroughputPerSecond: Double
  public var finalSegmentCount: Int
  public var finalWordCount: Int
  public var expectedFinalHash: String
  public var actualFinalHash: String
  public var maximumOpenPayloadBytes: Int
  public var peakPendingMutationCount: Int
  public var finalPendingMutationCount: Int
  public var memory: AcceleratedMemoryUsage
  public var cpu: AcceleratedCPUUsage
  public var samples: [AcceleratedProcessSample]
  public var failures: [String]

  public var ok: Bool { failures.isEmpty }
}

public enum AcceleratedTranscriptionEvolutionBench {
  public static let protocolVersion = 1

  public static func segmentID(_ segmentIndex: Int) -> String {
    String(format: "segment-%04d", segmentIndex)
  }

  public static func payload(
    profile: AcceleratedTranscriptionEvolutionProfile,
    segmentIndex: Int,
    revision: Int
  ) -> AcceleratedTranscriptPayload {
    let wordsPerRevision = profile.wordsPerSegment / profile.revisionsPerSegment
    let visibleWordCount = min(profile.wordsPerSegment, revision * wordsPerRevision)
    let segmentStart = segmentIndex * profile.segmentDurationSeconds * 1_000
    let words = (0..<visibleWordCount).map { wordIndex in
      let start = segmentStart + wordIndex * 400
      return AcceleratedTranscriptWord(
        index: wordIndex,
        text: wordText(segmentIndex: segmentIndex, wordIndex: wordIndex),
        startMilliseconds: start,
        endMilliseconds: start + 320,
        speaker: segmentIndex % 3
      )
    }
    return AcceleratedTranscriptPayload(
      segmentIndex: segmentIndex,
      revision: revision,
      isFinal: revision == profile.revisionsPerSegment,
      logicalStartMilliseconds: segmentStart,
      logicalEndMilliseconds: segmentStart + profile.segmentDurationSeconds * 1_000,
      words: words
    )
  }

  public static func encodedPayload(
    profile: AcceleratedTranscriptionEvolutionProfile,
    segmentIndex: Int,
    revision: Int
  ) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(
      decoding: try encoder.encode(
        payload(profile: profile, segmentIndex: segmentIndex, revision: revision)
      ),
      as: UTF8.self
    )
  }

  public static func expectedFinalHash(
    profile: AcceleratedTranscriptionEvolutionProfile
  ) -> String {
    canonicalHash(
      (0..<profile.segmentCount).map { segmentIndex in
        canonicalFinalLine(
          payload: payload(
            profile: profile,
            segmentIndex: segmentIndex,
            revision: profile.revisionsPerSegment
          )
        )
      }
    )
  }

  public static func canonicalFinalLine(payload: AcceleratedTranscriptPayload) -> String {
    let text = payload.words.map(\.text).joined(separator: " ")
    return [
      segmentID(payload.segmentIndex),
      String(payload.logicalStartMilliseconds),
      String(payload.logicalEndMilliseconds),
      String(payload.words.count),
      text,
    ].joined(separator: "|")
  }

  public static func canonicalHash(_ lines: [String]) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    let prime: UInt64 = 0x0000_0100_0000_01b3
    for line in lines {
      for byte in line.utf8 {
        hash ^= UInt64(byte)
        hash &*= prime
      }
      hash ^= 0x0a
      hash &*= prime
    }
    return String(format: "%016llx", hash)
  }

  public static func runLocalFirst(
    profile: AcceleratedTranscriptionEvolutionProfile = .twoHoursAt100x,
    appID: String = "accelerated-transcription-evolution",
    cacheDirectory: URL? = nil
  ) async throws -> AcceleratedTranscriptionEvolutionResult {
    try profile.validate()
    let root = cacheDirectory
      ?? FileManager.default.temporaryDirectory.appendingPathComponent(
        "AcceleratedTranscriptionEvolution-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let cacheURL = root.appendingPathComponent("runtime.sqlite")
    let configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let baselineMemory = processMemory()
    let baselineCPU = processCPUSeconds()
    let clock = ContinuousClock()
    let started = clock.now
    var samples: [AcceleratedProcessSample] = []
    var peakFootprint = baselineMemory.physical
    var peakResident = baselineMemory.resident
    var maximumPayloadBytes = 0
    var peakPendingMutationCount = 0
    var completedRevisionCount = 0

    for segmentIndex in 0..<profile.segmentCount {
      for revision in 1...profile.revisionsPerSegment {
        let transactionID = "accelerated-\(segmentIndex)-\(revision)"
        let text = try encodedPayload(
          profile: profile,
          segmentIndex: segmentIndex,
          revision: revision
        )
        maximumPayloadBytes = max(maximumPayloadBytes, text.utf8.count)
        let operations = TodoExample.createOperations(
          id: segmentID(segmentIndex),
          text: text,
          createdAt: InstantTimestamp(
            milliseconds: Int64(segmentIndex * profile.segmentDurationSeconds * 1_000)
          ),
          transactionID: transactionID
        )
        _ = try await runtime.transact(
          InstantStoreTransaction(id: transactionID, operations: operations),
          createdAt: InstantTimestamp(
            milliseconds: Int64(segmentIndex * profile.segmentDurationSeconds * 1_000 + revision)
          ),
          source: "benchmark.transcription-evolution.\(profile.name)"
        )
        completedRevisionCount += 1

        if completedRevisionCount.isMultiple(of: profile.sampleEveryRevisionCount)
          || completedRevisionCount == profile.revisionCount
        {
          let elapsed = durationSeconds(started.duration(to: clock.now))
          let pendingMutations = await runtime.pendingMutations()
          let pending = pendingMutations.count
          peakPendingMutationCount = max(peakPendingMutationCount, pending)
          let memory = processMemory()
          peakFootprint = maxOptional(peakFootprint, memory.physical)
          peakResident = maxOptional(peakResident, memory.resident)
          samples.append(
            AcceleratedProcessSample(
              elapsedSeconds: elapsed,
              logicalSecondsCompleted:
                Double(completedRevisionCount) / Double(profile.revisionCount)
                * Double(profile.logicalDurationSeconds),
              physicalFootprintBytes: memory.physical,
              residentBytes: memory.resident,
              pendingMutationCount: pending
            )
          )
        }
      }
    }

    let burstWallSeconds = durationSeconds(started.duration(to: clock.now))
    let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
    let decoder = JSONDecoder()
    let actualPayloads = try todos.sorted { $0.id < $1.id }.map { todo in
      try decoder.decode(AcceleratedTranscriptPayload.self, from: Data(todo.text.utf8))
    }
    let actualHash = canonicalHash(
      actualPayloads.map { canonicalFinalLine(payload: $0) }
    )
    let finalWordCount = actualPayloads.reduce(0) { $0 + $1.words.count }

    let settleStarted = clock.now
    _ = try? await runtime.closeConnection()
    _ = try await runtime.connect()
    _ = try await runtime.flushPendingMutations()
    let settleWallSeconds = durationSeconds(settleStarted.duration(to: clock.now))
    let finalPendingMutations = await runtime.pendingMutations()
    let finalPendingMutationCount = finalPendingMutations.count

    try? await Task.sleep(for: .milliseconds(100))
    let endMemory = processMemory()
    peakFootprint = maxOptional(peakFootprint, endMemory.physical)
    peakResident = maxOptional(peakResident, endMemory.resident)
    let endCPU = processCPUSeconds()
    let totalWallSeconds = durationSeconds(started.duration(to: clock.now))
    let userSeconds = max(0, endCPU.user - baselineCPU.user)
    let systemSeconds = max(0, endCPU.system - baselineCPU.system)
    let averageCPU = totalWallSeconds > 0
      ? (userSeconds + systemSeconds) / totalWallSeconds * 100
      : 0
    let expectedHash = expectedFinalHash(profile: profile)

    var failures: [String] = []
    if actualPayloads.count != profile.segmentCount {
      failures.append("final segment count \(actualPayloads.count) != \(profile.segmentCount)")
    }
    if actualPayloads.contains(where: { !$0.isFinal || $0.revision != profile.revisionsPerSegment }) {
      failures.append("one or more stored segments is not the final complete assignment")
    }
    if finalWordCount != profile.finalWordCount {
      failures.append("final word count \(finalWordCount) != \(profile.finalWordCount)")
    }
    if actualHash != expectedHash {
      failures.append("final canonical hash \(actualHash) != \(expectedHash)")
    }
    if finalPendingMutationCount != 0 {
      failures.append("final pending mutation count \(finalPendingMutationCount) != 0")
    }
    let effectiveAcceleration = totalWallSeconds > 0
      ? Double(profile.logicalDurationSeconds) / totalWallSeconds
      : .infinity
    let throughput = totalWallSeconds > 0
      ? Double(profile.revisionCount) / totalWallSeconds
      : .infinity
    if profile.minimumAcceleration > 0 && effectiveAcceleration < profile.minimumAcceleration {
      failures.append(
        String(
          format: "effective acceleration %.2fx < %.2fx",
          effectiveAcceleration,
          profile.minimumAcceleration
        )
      )
    }
    if profile.targetRevisionThroughput > 0 && throughput < profile.targetRevisionThroughput {
      failures.append(
        String(
          format: "revision throughput %.2f/s < %.2f/s",
          throughput,
          profile.targetRevisionThroughput
        )
      )
    }
    if maximumPayloadBytes > 16 * 1_024 {
      failures.append("maximum open payload \(maximumPayloadBytes) bytes exceeded 16 KiB")
    }

    return AcceleratedTranscriptionEvolutionResult(
      protocolVersion: protocolVersion,
      sdk: "swift",
      profile: profile,
      burstWallSeconds: burstWallSeconds,
      settleWallSeconds: settleWallSeconds,
      totalWallSeconds: totalWallSeconds,
      effectiveAcceleration: effectiveAcceleration,
      revisionThroughputPerSecond: throughput,
      finalSegmentCount: actualPayloads.count,
      finalWordCount: finalWordCount,
      expectedFinalHash: expectedHash,
      actualFinalHash: actualHash,
      maximumOpenPayloadBytes: maximumPayloadBytes,
      peakPendingMutationCount: peakPendingMutationCount,
      finalPendingMutationCount: finalPendingMutationCount,
      memory: AcceleratedMemoryUsage(
        baselinePhysicalFootprintBytes: baselineMemory.physical,
        peakPhysicalFootprintBytes: peakFootprint,
        endPhysicalFootprintBytes: endMemory.physical,
        incrementalPeakPhysicalFootprintBytes:
          signedDifference(peakFootprint, baselineMemory.physical),
        settledPhysicalFootprintGrowthBytes:
          signedDifference(endMemory.physical, baselineMemory.physical),
        peakResidentBytes: peakResident
      ),
      cpu: AcceleratedCPUUsage(
        userSeconds: userSeconds,
        systemSeconds: systemSeconds,
        averagePercentOfOneCore: averageCPU
      ),
      samples: samples,
      failures: failures
    )
  }

  private static func wordText(segmentIndex: Int, wordIndex: Int) -> String {
    let vocabulary = [
      "local", "first", "transcript", "revision", "stays",
      "bounded", "while", "offline", "sync", "converges",
      "without", "losing", "final", "segment", "order",
      "audio", "progress", "remains", "independent", "today",
    ]
    let base = vocabulary[(segmentIndex + wordIndex) % vocabulary.count]
    return "\(base)-\(segmentIndex)-\(wordIndex)"
  }

  private static func maxOptional(_ lhs: UInt64?, _ rhs: UInt64?) -> UInt64? {
    switch (lhs, rhs) {
    case let (.some(lhs), .some(rhs)):
      return max(lhs, rhs)
    case let (.some(lhs), .none):
      return lhs
    case let (.none, .some(rhs)):
      return rhs
    case (.none, .none):
      return nil
    }
  }

  private static func signedDifference(_ lhs: UInt64?, _ rhs: UInt64?) -> Int64? {
    guard let lhs, let rhs else { return nil }
    if lhs >= rhs { return Int64(clamping: lhs - rhs) }
    return -Int64(clamping: rhs - lhs)
  }

  private static func durationSeconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds)
      + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }

  private static func processCPUSeconds() -> (user: Double, system: Double) {
    #if canImport(Darwin)
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return (0, 0) }
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    return (user, system)
    #else
    return (0, 0)
    #endif
  }

  private static func processMemory() -> (physical: UInt64?, resident: UInt64?) {
    #if canImport(Darwin)
    var vmInfo = task_vm_info_data_t()
    var vmCount = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let vmResult = withUnsafeMutablePointer(to: &vmInfo) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { rebound in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &vmCount)
      }
    }

    var basicInfo = mach_task_basic_info_data_t()
    var basicCount = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
    )
    let basicResult = withUnsafeMutablePointer(to: &basicInfo) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) { rebound in
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &basicCount)
      }
    }
    return (
      vmResult == KERN_SUCCESS ? UInt64(vmInfo.phys_footprint) : nil,
      basicResult == KERN_SUCCESS ? UInt64(basicInfo.resident_size) : nil
    )
    #else
    return (nil, nil)
    #endif
  }
}
