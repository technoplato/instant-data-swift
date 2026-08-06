import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Publish-gate soak: **production** Scribe namespaces
/// (recordings → transcriptions → transcriptionWords → segments → attachments),
/// paged like the production library list. Fails when physical footprint balloons.
///
/// Issue: https://issues.knophy.com/issues/150
@Suite(.serialized)
struct LinkedInfiniteScribeShapedMemorySoakTests {
  @Test
  func scribeShapedInfiniteListStayWithinFootprintBudget() async throws {
    let profile = LinkedInfiniteScribeShapedSoakProfile.publishGate
    let baseline = InstantProcessMemory.sample()
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LinkedInfiniteScribeSoak-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "linked-infinite-scribe-soak",
        persistenceURL: cacheURL,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() }
      )
    )

    var recordingIDs: [String] = []
    var transcriptionIDs: [String] = []
    var wordIDsByRecording: [[String]] = []
    var segmentIDsByRecording: [[String]] = []
    var attachmentIDsByRecording: [[String]] = []
    let segmentsPerRecording = max(1, profile.wordsPerRecording / 12)
    for index in 0..<profile.recordingCount {
      recordingIDs.append(
        try await runtime.localID(named: "scribe.prod.recording.\(index)")
      )
      transcriptionIDs.append(
        try await runtime.localID(named: "scribe.prod.transcription.\(index)")
      )
      var wordIDs: [String] = []
      for wordIndex in 0..<profile.wordsPerRecording {
        wordIDs.append(
          try await runtime.localID(named: "scribe.prod.word.\(index).\(wordIndex)")
        )
      }
      wordIDsByRecording.append(wordIDs)
      var segmentIDs: [String] = []
      for segmentIndex in 0..<segmentsPerRecording {
        segmentIDs.append(
          try await runtime.localID(named: "scribe.prod.segment.\(index).\(segmentIndex)")
        )
      }
      segmentIDsByRecording.append(segmentIDs)
      attachmentIDsByRecording.append([
        try await runtime.localID(named: "scribe.prod.attachment.\(index).0")
      ])
    }

    let transactionID = runtime.configuration.makeID()
    let now = InstantTimestamp(milliseconds: 1_700_100_000_000)
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

    let afterSeed = InstantProcessMemory.sample()
    let plan = ScribeProductionShapedSchema.scribeShapedListQuery(pageSize: profile.listPageSize)
    let subscription = await runtime.subscribeInfiniteQuery(plan)
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()

    var latest = try #require(await iterator.next())
    #expect(latest.error == nil)
    #expect(latest.values.count == min(profile.listPageSize, profile.recordingCount))

    // Page through like the library "load older" path until closed or a few expands.
    var expansions = 0
    while latest.canLoadNextPage, expansions < 4, latest.values.count < profile.recordingCount {
      subscription.loadNextPage()
      expansions += 1
      latest = try #require(await iterator.next())
      #expect(latest.error == nil)
    }

    let afterPages = InstantProcessMemory.sample()
    #expect(latest.values.count >= min(profile.listPageSize, profile.recordingCount))

    // Correctness: production word namespace entities persisted (not only a wordCount scalar).
    let wordSnapshots = try await runtime.query(
      InstantQueryPlan(
        id: "soak.words",
        namespace: ScribeProductionShapedSchema.wordNamespace,
        limit: 5
      )
    )
    #expect(wordSnapshots.count == 5)
    let segmentSnapshots = try await runtime.query(
      InstantQueryPlan(
        id: "soak.segments",
        namespace: ScribeProductionShapedSchema.segmentNamespace,
        limit: 5
      )
    )
    #expect(segmentSnapshots.count >= 1)
    let attachmentSnapshots = try await runtime.query(
      InstantQueryPlan(
        id: "soak.attachments",
        namespace: ScribeProductionShapedSchema.attachmentNamespace,
        limit: 5
      )
    )
    #expect(attachmentSnapshots.count >= 1)

    if let baseline, let afterSeed, let afterPages {
      let growthFromBaseline =
        afterPages.physicalFootprintBytes > baseline.physicalFootprintBytes
        ? afterPages.physicalFootprintBytes - baseline.physicalFootprintBytes
        : 0
      let growthFromSeed =
        afterPages.physicalFootprintBytes > afterSeed.physicalFootprintBytes
        ? afterPages.physicalFootprintBytes - afterSeed.physicalFootprintBytes
        : 0
      // Infinite page expands must not thrash; seed is expected to dominate cost.
      let pageExpandBudgetBytes: UInt64 = 64 * 1_024 * 1_024
      #expect(
        afterPages.physicalFootprintBytes <= profile.footprintCeilingBytes,
        """
        Scribe-shaped soak absolute footprint \
        \(afterPages.physicalFootprintBytes) exceeded ceiling \
        \(profile.footprintCeilingBytes). \
        baseline=\(baseline.physicalFootprintBytes) \
        afterSeed=\(afterSeed.physicalFootprintBytes) \
        afterPages=\(afterPages.physicalFootprintBytes) \
        virtual=\(afterPages.virtualBytes) (VSZ is not RAM). \
        recordings=\(profile.recordingCount) words=\(profile.estimatedWordEntities) \
        #150
        """
      )
      #expect(
        growthFromBaseline <= profile.footprintGrowthBudgetBytes,
        """
        Scribe-shaped soak footprint growth \(growthFromBaseline) exceeded budget \
        \(profile.footprintGrowthBudgetBytes). \
        growthFromSeed=\(growthFromSeed) \
        baseline=\(baseline.physicalFootprintBytes) \
        afterSeed=\(afterSeed.physicalFootprintBytes) \
        afterPages=\(afterPages.physicalFootprintBytes) \
        virtual=\(afterPages.virtualBytes) (do not gate on VSZ). \
        #150
        """
      )
      #expect(
        growthFromSeed <= pageExpandBudgetBytes,
        """
        Infinite page expands grew footprint by \(growthFromSeed) \
        (budget \(pageExpandBudgetBytes)). This is the thrash class that Jetsam'd Scribe. \
        afterSeed=\(afterSeed.physicalFootprintBytes) \
        afterPages=\(afterPages.physicalFootprintBytes) \
        #150
        """
      )

      // Idle settle: dual-write thrash climbs multi‑GB while "doing nothing".
      try await Task.sleep(for: .milliseconds(150))
      for _ in 0..<4 {
        _ = try await runtime.query(
          InstantQueryPlan(
            id: "soak.idle.\(UUID().uuidString.prefix(6))",
            namespace: ScribeProductionShapedSchema.recordingNamespace,
            limit: 5
          )
        )
      }
      let afterIdle = InstantProcessMemory.sample()
      if let afterIdle {
        let idleGrowth =
          afterIdle.physicalFootprintBytes > afterPages.physicalFootprintBytes
          ? afterIdle.physicalFootprintBytes - afterPages.physicalFootprintBytes
          : 0
        #expect(
          idleGrowth <= profile.idleSettleGrowthBudgetBytes,
          """
          Idle settle grew \(idleGrowth) (budget \(profile.idleSettleGrowthBudgetBytes)). \
          Dual-write thrash class. afterPages=\(afterPages.physicalFootprintBytes) \
          afterIdle=\(afterIdle.physicalFootprintBytes) virtual=\(afterIdle.virtualBytes)
          """
        )
        #expect(
          afterIdle.physicalFootprintBytes <= profile.idleSettleAbsoluteCeilingBytes,
          """
          Idle absolute footprint \(afterIdle.physicalFootprintBytes) exceeded \
          \(profile.idleSettleAbsoluteCeilingBytes). Multi‑GB idle fails this gate.
          """
        )
      }
    } else {
      Issue.record("Could not sample InstantProcessMemory on this platform.")
    }
  }
}
