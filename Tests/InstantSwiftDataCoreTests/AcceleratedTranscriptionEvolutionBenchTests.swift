import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct AcceleratedTranscriptionEvolutionBenchTests {
  @Test func twoHourProfileHasTheExactProductShape() throws {
    let profile = AcceleratedTranscriptionEvolutionProfile.twoHoursAt100x
    try profile.validate()

    #expect(profile.logicalDurationSeconds == 7_200)
    #expect(profile.wallBudgetSeconds == 72)
    #expect(profile.segmentCount == 900)
    #expect(profile.finalWordCount == 18_000)
    #expect(profile.revisionCount == 9_000)
    #expect(profile.targetRevisionThroughput == 125)
  }

  @Test func eachOpenSegmentRewriteIsBoundedAndFinalizationIsMonotonic() throws {
    let profile = AcceleratedTranscriptionEvolutionProfile.twoHoursAt100x
    var previousWordCount = 0

    for revision in 1...profile.revisionsPerSegment {
      let payload = AcceleratedTranscriptionEvolutionBench.payload(
        profile: profile,
        segmentIndex: 42,
        revision: revision
      )
      #expect(payload.segmentIndex == 42)
      #expect(payload.revision == revision)
      #expect(payload.words.count > previousWordCount)
      #expect(payload.words.count <= profile.wordsPerSegment)
      #expect(payload.isFinal == (revision == profile.revisionsPerSegment))
      previousWordCount = payload.words.count

      let encoded = try AcceleratedTranscriptionEvolutionBench.encodedPayload(
        profile: profile,
        segmentIndex: 42,
        revision: revision
      )
      #expect(encoded.utf8.count < 16 * 1_024)
    }
  }

  @Test func canonicalHashIsStableAndSensitiveToOrder() {
    let profile = AcceleratedTranscriptionEvolutionProfile.twoHoursAt100x
    let first = AcceleratedTranscriptionEvolutionBench.expectedFinalHash(profile: profile)
    let second = AcceleratedTranscriptionEvolutionBench.expectedFinalHash(profile: profile)
    #expect(first == second)
    #expect(first.count == 16)

    let lines = (0..<2).map { index in
      AcceleratedTranscriptionEvolutionBench.canonicalFinalLine(
        payload: AcceleratedTranscriptionEvolutionBench.payload(
          profile: profile,
          segmentIndex: index,
          revision: profile.revisionsPerSegment
        )
      )
    }
    #expect(
      AcceleratedTranscriptionEvolutionBench.canonicalHash(lines)
        != AcceleratedTranscriptionEvolutionBench.canonicalHash(lines.reversed())
    )
  }

  @Test func localFirstSmokePreservesFinalStateAndDrainsTheOutbox() async throws {
    let result = try await AcceleratedTranscriptionEvolutionBench.runLocalFirst(
      profile: .smoke
    )

    #expect(result.failures.isEmpty)
    #expect(result.finalSegmentCount == 4)
    #expect(result.finalWordCount == 80)
    #expect(result.expectedFinalHash == result.actualFinalHash)
    #expect(result.finalPendingMutationCount == 0)
    #expect(result.maximumOpenPayloadBytes < 16 * 1_024)
  }

  @Test func fullTwoHourProfile() async throws {
    guard ProcessInfo.processInfo.environment["INSTANT_ACCELERATED_TRANSCRIPTION_FULL"] == "1"
    else { return }

    let result = try await AcceleratedTranscriptionEvolutionBench.runLocalFirst(
      profile: .twoHoursAt100x
    )
    try writeEvidence(result)

    #expect(result.failures.isEmpty)
    #expect(result.totalWallSeconds <= 72)
    #expect(result.effectiveAcceleration >= 100)
    #expect(result.revisionThroughputPerSecond >= 125)
    #expect(result.finalSegmentCount == 900)
    #expect(result.finalWordCount == 18_000)
    #expect(result.expectedFinalHash == result.actualFinalHash)
    #expect(result.finalPendingMutationCount == 0)
    #expect(result.peakPendingMutationCount <= 1_800)
    #expect(result.cpu.averagePercentOfOneCore <= 200)

    let incrementalPeak = try #require(
      result.memory.incrementalPeakPhysicalFootprintBytes
    )
    let settledGrowth = try #require(
      result.memory.settledPhysicalFootprintGrowthBytes
    )
    #expect(incrementalPeak <= 64 * 1_024 * 1_024)
    #expect(settledGrowth <= 16 * 1_024 * 1_024)
  }

  private func writeEvidence(
    _ result: AcceleratedTranscriptionEvolutionResult
  ) throws {
    let environment = ProcessInfo.processInfo.environment
    let directory = URL(
      fileURLWithPath:
        environment["INSTANT_ACCELERATED_TRANSCRIPTION_RESULTS_DIR"]
        ?? FileManager.default.temporaryDirectory
          .appendingPathComponent("instant-accelerated-transcription-results")
          .path,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    var data = try encoder.encode(result)
    data.append(0x0a)
    try data.write(
      to: directory.appendingPathComponent("swift.json"),
      options: .atomic
    )
  }
}
