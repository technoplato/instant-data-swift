import Foundation
import Testing
@testable import InstantSwiftDataCore

@Suite(.serialized)
struct DualResidencyFootprintMeasureTests {
  @Test
  func publishGatePendingAndColdReopenMetrics() async throws {
    let profile = LinkedInfiniteScribeShapedSoakProfile.publishGate
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("DualResidencyMeasure-pg-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    // PENDING seed floor (comparable to historical main baseline)
    let pendingBaseline = InstantProcessMemory.sample()
    let seedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "dual-residency-publish-gate",
        persistenceURL: cacheURL,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() }
      )
    )
    try await seed(runtime: seedRuntime, profile: profile)
    _ = try await seedRuntime.query(
      InstantQueryPlan(
        id: "pg.list.pending",
        namespace: ScribeProductionShapedSchema.recordingNamespace,
        limit: profile.listPageSize
      )
    )
    let pendingAfter = InstantProcessMemory.sample()
    let pendingGrowth: UInt64 =
      if let pendingBaseline, let pendingAfter,
        pendingAfter.physicalFootprintBytes > pendingBaseline.physicalFootprintBytes
      {
        pendingAfter.physicalFootprintBytes - pendingBaseline.physicalFootprintBytes
      } else { 0 }
    print(
      "AUTORESEARCH_METRIC profile=publishGate mode=pending peak_physical_growth_bytes=\(pendingGrowth) mb_growth=\(String(format: "%.1f", Double(pendingGrowth)/1024/1024))"
    )

    for mutation in await seedRuntime.pendingMutations() where mutation.status == .pending {
      _ = try? await seedRuntime.confirmMutation(id: mutation.id)
    }
    // Drop seed runtime
    _ = seedRuntime

    for _ in 0..<5 { autoreleasepool { _ = [UInt8](repeating: 0, count: 1) } }
    try await Task.sleep(for: .milliseconds(50))

    // COLD reopen settled floor (allocator freelist may still be warm in-process)
    let coldBaseline = InstantProcessMemory.sample()
    let coldRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "dual-residency-publish-gate",
        persistenceURL: cacheURL,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() }
      )
    )
    _ = try await coldRuntime.query(
      InstantQueryPlan(
        id: "pg.list.cold",
        namespace: ScribeProductionShapedSchema.recordingNamespace,
        limit: profile.listPageSize
      )
    )
    let coldAfter = InstantProcessMemory.sample()
    let coldGrowth: UInt64 =
      if let coldBaseline, let coldAfter,
        coldAfter.physicalFootprintBytes > coldBaseline.physicalFootprintBytes
      {
        coldAfter.physicalFootprintBytes - coldBaseline.physicalFootprintBytes
      } else { 0 }
    print(
      "AUTORESEARCH_METRIC profile=publishGate mode=cold-reopen peak_physical_growth_bytes=\(coldGrowth) mb_growth=\(String(format: "%.1f", Double(coldGrowth)/1024/1024))"
    )

    #expect(pendingGrowth > 0)
    #expect(coldGrowth > 0)
  }

  private func seed(
    runtime: InstantRuntime,
    profile: LinkedInfiniteScribeShapedSoakProfile
  ) async throws {
    var recordingIDs: [String] = []
    var transcriptionIDs: [String] = []
    var wordIDsByRecording: [[String]] = []
    var segmentIDsByRecording: [[String]] = []
    var attachmentIDsByRecording: [[String]] = []
    let segmentsPerRecording = max(1, profile.wordsPerRecording / 12)
    for index in 0..<profile.recordingCount {
      recordingIDs.append(try await runtime.localID(named: "pg.rec.\(index)"))
      transcriptionIDs.append(try await runtime.localID(named: "pg.tr.\(index)"))
      var wordIDs: [String] = []
      for wordIndex in 0..<profile.wordsPerRecording {
        wordIDs.append(try await runtime.localID(named: "pg.w.\(index).\(wordIndex)"))
      }
      wordIDsByRecording.append(wordIDs)
      var segmentIDs: [String] = []
      for segmentIndex in 0..<segmentsPerRecording {
        segmentIDs.append(try await runtime.localID(named: "pg.s.\(index).\(segmentIndex)"))
      }
      segmentIDsByRecording.append(segmentIDs)
      attachmentIDsByRecording.append([
        try await runtime.localID(named: "pg.a.\(index).0")
      ])
    }
    let transactionID = runtime.configuration.makeID()
    let now = InstantTimestamp(milliseconds: 1_700_200_000_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: ScribeProductionShapedSchema.soakOperations(
          profile: profile,
          recordingIDs: recordingIDs,
          transcriptionIDs: transcriptionIDs,
          wordIDsByRecording: wordIDsByRecording,
          segmentIDsByRecording: segmentIDsByRecording,
          attachmentIDsByRecording: attachmentIDsByRecording,
          baseTime: now,
          transactionID: transactionID
        )
      ),
      createdAt: now
    )
  }
}
