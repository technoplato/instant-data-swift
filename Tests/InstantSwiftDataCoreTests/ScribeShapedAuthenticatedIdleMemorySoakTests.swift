import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Publish gate: Scribe-shaped graph + **guest auth** + dual-write thrash resistance
/// with **absolute idle footprint** budgets (product fail &gt;400 MB).
///
/// Field 2026-08-05: iPad idle multi‑GB was InstantDiagnostics dual-written into
/// Instant `debugLogs` as 400–700-op batches. This suite:
/// 1. Signs in as guest (Scribe's auth path shape; `.local` always; live when env set).
/// 2. Seeds recordings→transcriptions→words.
/// 3. Installs an info-level dual-write thrash driver (Scribe bridge minimumLevel).
/// 4. Settles idle and fails multi‑GB / unbounded climb on **physical footprint**.
///
/// Issues: #150 (soak), dual-write thrash plan 2026-08-05.
@Suite(.serialized)
struct ScribeShapedAuthenticatedIdleMemorySoakTests {
  /// High-frequency events that dual-write hosts must not re-ingest at info+.
  static let dualWriteSensitiveEvents: Set<String> = [
    "outbox.flush.started",
    "outbox.flush.finished",
    "outbox.mutation.send",
    "query-once.started",
    "query-once.completed",
    "transaction.started",
    "transaction.optimistic-commit",
    "websocket.message-sent",
  ]

  @Test("guest-auth Scribe-shaped idle stays under absolute footprint budget")
  func guestAuthScribeShapedIdleUnderAbsoluteBudget() async throws {
    let profile = LinkedInfiniteScribeShapedSoakProfile.publishGateAbsoluteIdle
    let cacheURL = try temporaryScribeAuthIdleCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "scribe-auth-idle-soak",
        persistenceURL: cacheURL,
        initialAttributes: LinkedInfiniteExample.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )

    let session = try await runtime.signInAsGuest()
    #expect(session.userID.isEmpty == false, "Guest auth must produce a user id")
    #expect(session.isGuest == true, "Local guest path must report isGuest")

    let dualWriteInfoFires = DualWriteCounter()
    let thrashDriverOps = DualWriteCounter()
    let token = InstantDiagnostics.shared.addHandler { entry in
      // Scribe InstantDBLogger bridge uses minimumLevel `.info`.
      guard entry.level.priorityValue >= InstantDiagnosticLevel.info.priorityValue else { return }
      if Self.dualWriteSensitiveEvents.contains(entry.event) {
        dualWriteInfoFires.increment()
      }
      // Simulate dual-write cost only if demotion regressed: each info fire would
      // enqueue a multi-attr batch. Count ops instead of writing to keep CI fast;
      // absolute footprint still gates unbounded store growth from real work.
      thrashDriverOps.add(22 * 8)
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let afterAuth = InstantProcessMemory.sample()
    try await seedScribeShapedGraph(runtime: runtime, profile: profile)

    let plan = LinkedInfiniteExample.scribeShapedListQuery(pageSize: profile.listPageSize)
    let subscription = await runtime.subscribeInfiniteQuery(plan)
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()
    var latest = try #require(await iterator.next())
    #expect(latest.error == nil)
    #expect(latest.values.isEmpty == false)

    // Local query-once volume (was a dual-write thrash amplifier at info).
    for index in 0..<12 {
      _ = try await runtime.queryOnce(
        InstantQueryPlan(
          id: "auth-idle.query-once.\(index)",
          namespace: LinkedInfiniteExample.recordingNamespace,
          limit: 5
        )
      )
    }

    let afterWork = InstantProcessMemory.sample()

    // Idle settle: no user actions; dual-write must not climb multi‑GB.
    try await Task.sleep(for: .milliseconds(200))
    for _ in 0..<6 {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "idle.recordings.\(UUID().uuidString.prefix(8))",
          namespace: LinkedInfiniteExample.recordingNamespace,
          limit: 10
        )
      )
      try await Task.sleep(for: .milliseconds(50))
    }
    let afterIdle = InstantProcessMemory.sample()

    #expect(
      dualWriteInfoFires.value == 0,
      """
      Dual-write thrash driver saw \(dualWriteInfoFires.value) info+ high-frequency \
      events. Demotion/regate failed — field multi‑GB idle returns.
      """
    )

    if let afterWork, let afterIdle {
      let idleGrowth =
        afterIdle.physicalFootprintBytes > afterWork.physicalFootprintBytes
        ? afterIdle.physicalFootprintBytes - afterWork.physicalFootprintBytes
        : 0
      #expect(
        afterIdle.physicalFootprintBytes <= profile.idleSettleAbsoluteCeilingBytes,
        """
        Absolute idle settle footprint \(afterIdle.physicalFootprintBytes) exceeded \
        ceiling \(profile.idleSettleAbsoluteCeilingBytes) (product fail is 400 MiB). \
        afterAuth=\(afterAuth?.physicalFootprintBytes ?? 0) \
        afterWork=\(afterWork.physicalFootprintBytes) \
        afterIdle=\(afterIdle.physicalFootprintBytes) \
        virtual=\(afterIdle.virtualBytes) (not RAM). \
        guestUser=\(String(describing: session.userID)) words=\(profile.estimatedWordEntities)
        """
      )
      #expect(
        idleGrowth <= profile.idleSettleGrowthBudgetBytes,
        """
        Idle settle grew footprint by \(idleGrowth) (budget \
        \(profile.idleSettleGrowthBudgetBytes)). Dual-write thrash class. \
        afterWork=\(afterWork.physicalFootprintBytes) \
        afterIdle=\(afterIdle.physicalFootprintBytes)
        """
      )
      // Multi‑GB hard fail regardless of profile ceiling typos.
      let multiGB: UInt64 = 1_500 * 1_024 * 1_024
      #expect(
        afterIdle.physicalFootprintBytes < multiGB,
        "Idle footprint \(afterIdle.physicalFootprintBytes) is multi‑GB thrash class"
      )
    } else {
      Issue.record("Could not sample InstantProcessMemory on this platform.")
    }
  }

  @Test("live guest auth Scribe soak when Instant credentials are configured")
  func liveGuestAuthScribeSoakWhenCredentialsConfigured() async throws {
    let appID = ProcessInfo.processInfo.environment["SCRIBE_MAIN_INSTANT_APP_ID"]
      ?? ProcessInfo.processInfo.environment["INSTANT_APP_ID"]
    let useLive = ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK"] == "1"
    guard useLive, let appID, appID.isEmpty == false else {
      // Auth path is still proven by guestAuthScribeShapedIdleUnderAbsoluteBudget
      // with InstantGuestAuthenticator.local. Live path is optional when CI has
      // network + app id; fail loud when explicitly requested but misconfigured.
      if useLive {
        Issue.record(
          """
          INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK=1 requires SCRIBE_MAIN_INSTANT_APP_ID \
          or INSTANT_APP_ID. Live authenticated dual-write gate cannot run.
          """
        )
      }
      return
    }

    let profile = LinkedInfiniteScribeShapedSoakProfile.publishGateAbsoluteIdle
    let cacheURL = try temporaryScribeAuthIdleCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: LinkedInfiniteExample.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .live
      )
    )

    let session: InstantAuthSession
    do {
      session = try await runtime.signInAsGuest()
    } catch {
      Issue.record(
        """
        Live guest auth failed for appID \(appID): \(error). \
        Authenticated Scribe dual-write thrash gate cannot pass without working guest auth.
        """
      )
      throw error
    }
    #expect(session.userID.isEmpty == false)
    #expect((session.refreshToken?.isEmpty == false) || session.isGuest)

    try await seedScribeShapedGraph(runtime: runtime, profile: profile)
    let afterSeed = InstantProcessMemory.sample()
    try await Task.sleep(for: .milliseconds(300))
    let afterIdle = InstantProcessMemory.sample()
    if let afterSeed, let afterIdle {
      let growth =
        afterIdle.physicalFootprintBytes > afterSeed.physicalFootprintBytes
        ? afterIdle.physicalFootprintBytes - afterSeed.physicalFootprintBytes
        : 0
      #expect(afterIdle.physicalFootprintBytes <= profile.idleSettleAbsoluteCeilingBytes)
      #expect(growth <= profile.idleSettleGrowthBudgetBytes)
    }
  }

  @Test("forced info dual-write of oversized debug-log batches is finite and budgeted")
  func forcedInfoDualWriteBatchesStayFiniteAndBudgeted() async throws {
    // Reproduces the thrash *driver* (oversized debug-log-style mutations) without
    // requiring the infinite feedback loop. A regression that re-enables infinite
    // feedback is caught by dualWriteSensitiveEvents demotion + absolute ceilings.
    let cacheURL = try temporaryScribeAuthIdleCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "scribe-forced-dual-write-batch",
        persistenceURL: cacheURL,
        initialAttributes: LinkedInfiniteExample.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    _ = try await runtime.signInAsGuest()

    let baseline = InstantProcessMemory.sample()
    // 12 batches × 8 word-like entities ≈ finite cost; multi‑GB feedback was
    // hundreds of unbounded batches. Gate absolute growth hard.
    for batch in 0..<12 {
      let transactionID = "forced-debug-log-batch-\(batch)"
      let now = InstantTimestamp(milliseconds: 1_700_200_000_000 + Int64(batch))
      var operations: [InstantTripleOperation] = []
      let recordingID = try await runtime.localID(named: "forced.recording.\(batch)")
      let transcriptionID = try await runtime.localID(named: "forced.transcription.\(batch)")
      operations.append(
        contentsOf: LinkedInfiniteExample.createRecordingOperations(
          id: recordingID,
          title: "forced \(batch)",
          updatedAt: now,
          transactionID: transactionID
        )
      )
      operations.append(
        contentsOf: LinkedInfiniteExample.createTranscriptionOperations(
          id: transcriptionID,
          recordingID: recordingID,
          wordCount: 8,
          updatedAt: now,
          transactionID: transactionID,
          transcriptText: String(repeating: "w", count: 64),
          segmentCount: 1
        )
      )
      for entity in 0..<8 {
        let wordID = try await runtime.localID(named: "forced.word.\(batch).\(entity)")
        operations.append(
          contentsOf: LinkedInfiniteExample.createWordOperations(
            id: wordID,
            recordingID: recordingID,
            transcriptionID: transcriptionID,
            text: "w\(entity)",
            wordIndex: entity,
            startTimeSeconds: Double(entity) * 0.1,
            endTimeSeconds: Double(entity) * 0.1 + 0.05,
            updatedAt: now,
            transactionID: transactionID
          )
        )
      }
      try await runtime.transact(
        InstantStoreTransaction(id: transactionID, operations: operations),
        createdAt: now
      )
    }
    let after = InstantProcessMemory.sample()
    if let baseline, let after {
      let growth =
        after.physicalFootprintBytes > baseline.physicalFootprintBytes
        ? after.physicalFootprintBytes - baseline.physicalFootprintBytes
        : 0
      let multiGB: UInt64 = 1_500 * 1_024 * 1_024
      #expect(
        after.physicalFootprintBytes < multiGB,
        "Forced dual-write batches reached multi‑GB \(after.physicalFootprintBytes)"
      )
      #expect(
        growth < 768 * 1_024 * 1_024,
        "Forced dual-write batch growth \(growth) too large for finite 12×8 batches"
      )
    }
  }
}

// MARK: - Helpers

private final class DualWriteCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var _value = 0
  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return _value
  }
  func increment() {
    lock.lock()
    _value += 1
    lock.unlock()
  }
  func add(_ n: Int) {
    lock.lock()
    _value += n
    lock.unlock()
  }
}

extension InstantDiagnosticLevel {
  fileprivate var priorityValue: Int {
    switch self {
    case .trace: 0
    case .debug: 1
    case .info: 2
    case .notice: 3
    case .warning: 4
    case .error: 5
    case .critical: 6
    }
  }
}

private func temporaryScribeAuthIdleCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ScribeAuthIdleSoak-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func seedScribeShapedGraph(
  runtime: InstantRuntime,
  profile: LinkedInfiniteScribeShapedSoakProfile
) async throws {
  var recordingIDs: [String] = []
  var transcriptionIDs: [String] = []
  var wordIDsByRecording: [[String]] = []
  for index in 0..<profile.recordingCount {
    recordingIDs.append(
      try await runtime.localID(named: LinkedInfiniteExample.seedLocalIDName(index: index))
    )
    transcriptionIDs.append(
      try await runtime.localID(
        named: LinkedInfiniteExample.transcriptionLocalIDName(index: index)
      )
    )
    var wordIDs: [String] = []
    for wordIndex in 0..<profile.wordsPerRecording {
      wordIDs.append(
        try await runtime.localID(
          named: LinkedInfiniteExample.wordLocalIDName(
            recordingIndex: index,
            wordIndex: wordIndex
          )
        )
      )
    }
    wordIDsByRecording.append(wordIDs)
  }
  let transactionID = runtime.configuration.makeID()
  let now = InstantTimestamp(milliseconds: 1_700_100_500_000)
  try await runtime.transact(
    InstantStoreTransaction(
      id: transactionID,
      operations: LinkedInfiniteExample.scribeShapedSoakOperations(
        profile: profile,
        recordingIDs: recordingIDs,
        transcriptionIDs: transcriptionIDs,
        wordIDsByRecording: wordIDsByRecording,
        baseTime: now,
        transactionID: transactionID
      )
    ),
    createdAt: now
  )
}
