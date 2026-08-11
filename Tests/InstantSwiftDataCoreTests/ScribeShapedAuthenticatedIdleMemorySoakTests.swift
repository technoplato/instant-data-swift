import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// Publish gate: **production Scribe namespaces** + guest auth + real second Instant
/// `debugLogs` store thrash resistance with **absolute idle footprint** budgets.
///
/// Field 2026-08-05: iPad idle multi‑GB was InstantDiagnostics dual-written into a
/// second Instant `debugLogs` client as multi-attr batches (`debug-log-batch-*`,
/// HOL at 256 step budget, pendingMutationCount ~80+). Not the recording path —
/// home screen idle with dual Instant stores.
///
/// This suite:
/// 1. Uses production namespaces: recordings, transcriptions, transcriptionWords,
///    transcriptionSegments, recordingAttachments (issue #150 admin sample shape).
/// 2. Signs in as guest (`.local` always; live when credentials/env present).
/// 3. Boots a **second InstantRuntime** with `debugLogs` attrs and dual-writes
///    multi-attr rows the way InstantDBLogger does.
/// 4. Fails multi‑GB / unbounded climb on **physical footprint** only.
///
/// Issues: #150 (soak), dual-write thrash 2026-08-05.
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

  @Test(
    "guest-auth Scribe-shaped idle stays under absolute footprint budget",
    .enabled(
      if: ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_ISOLATED_MEMORY_GATE"] == "1",
      "Absolute process memory is valid only in the isolated validation process."
    )
  )
  func guestAuthScribeShapedIdleUnderAbsoluteBudget() async throws {
    let profile = LinkedInfiniteScribeShapedSoakProfile.publishGateAbsoluteIdle
    let cacheURL = try temporaryScribeAuthIdleCacheURL(prefix: "main")
    let debugLogsCacheURL = try temporaryScribeAuthIdleCacheURL(prefix: "debugLogs")
    defer {
      try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: debugLogsCacheURL.deletingLastPathComponent())
    }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "scribe-auth-idle-soak-main",
        persistenceURL: cacheURL,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    // Second Instant store — the Scribe Instant debugLogs dual-write client.
    let debugLogsRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "scribe-auth-idle-soak-debugLogs",
        persistenceURL: debugLogsCacheURL,
        initialAttributes: ScribeProductionShapedSchema.debugLogsAttributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    _ = try await debugLogsRuntime.signInAsGuest()

    let session = try await runtime.signInAsGuest()
    #expect(session.userID.isEmpty == false, "Guest auth must produce a user id")
    #expect(session.isGuest == true, "Local guest path must report isGuest")

    let dualWriteInfoFires = DualWriteCounter()
    let dualWriteBatches = DualWriteCounter()
    // Demoted path: only dual-write when info+ high-frequency events leak.
    // With correct demotion this should never enqueue into debugLogsRuntime.
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.level.priorityValue >= InstantDiagnosticLevel.info.priorityValue else { return }
      guard Self.dualWriteSensitiveEvents.contains(entry.event) else { return }
      dualWriteInfoFires.increment()
      // If demotion regressed, actually write multi-attr debugLogs batches into
      // the second Instant store — the field thrash driver, not a counter toy.
      Task {
        dualWriteBatches.increment()
        let batch = dualWriteBatches.value
        let now = InstantTimestamp(milliseconds: 1_700_300_000_000 + Int64(batch))
        var operations: [InstantTripleOperation] = []
        for entity in 0..<8 {
          let id = "leak-debug-log-\(batch)-\(entity)"
          operations.append(
            contentsOf: ScribeProductionShapedSchema.createDebugLogOperations(
              id: id,
              batchIndex: batch,
              entityIndex: entity,
              updatedAt: now,
              transactionID: "debug-log-batch-leak-\(batch)"
            )
          )
        }
        let entityGroups = BoundedBenchmarkSeed.entityCreationGroups(from: operations)
        for transaction in BoundedBenchmarkSeed.transactions(
          baseID: "debug-log-batch-leak-\(batch)",
          atomicOperationGroups: entityGroups
        ) {
          try? await debugLogsRuntime.transact(transaction, createdAt: now)
        }
      }
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }

    let afterAuth = InstantProcessMemory.sample()
    try await seedProductionScribeShapedGraph(runtime: runtime, profile: profile)

    let plan = ScribeProductionShapedSchema.scribeShapedListQuery(pageSize: profile.listPageSize)
    let subscription = await runtime.subscribeInfiniteQuery(plan)
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()
    var latest = try #require(await iterator.next())
    #expect(latest.error == nil)
    #expect(latest.values.isEmpty == false)

    for index in 0..<12 {
      _ = try await runtime.queryOnce(
        InstantQueryPlan(
          id: "auth-idle.query-once.\(index)",
          namespace: ScribeProductionShapedSchema.recordingNamespace,
          limit: 5
        )
      )
    }

    let afterWork = InstantProcessMemory.sample()

    try await Task.sleep(for: .milliseconds(200))
    for _ in 0..<6 {
      _ = try await runtime.query(
        InstantQueryPlan(
          id: "idle.recordings.\(UUID().uuidString.prefix(8))",
          namespace: ScribeProductionShapedSchema.recordingNamespace,
          limit: 10
        )
      )
      try await Task.sleep(for: .milliseconds(50))
    }
    // Allow any leak Tasks to land before sampling.
    try await Task.sleep(for: .milliseconds(100))
    let afterIdle = InstantProcessMemory.sample()

    #expect(
      dualWriteInfoFires.value == 0,
      """
      Dual-write thrash driver saw \(dualWriteInfoFires.value) info+ high-frequency \
      events and wrote \(dualWriteBatches.value) real debugLogs batches into the \
      second Instant store. Demotion/regate failed — field multi‑GB idle returns.
      """
    )

    if let afterWork, let afterIdle {
      let idleGrowth =
        afterIdle.physicalFootprintBytes > afterWork.physicalFootprintBytes
        ? afterIdle.physicalFootprintBytes - afterWork.physicalFootprintBytes
        : 0
      print(
        "INSTANT_MEMORY_METRIC scenario=scribe-authenticated-idle "
          + "afterAuthBytes=\(afterAuth?.physicalFootprintBytes ?? 0) "
          + "afterWorkBytes=\(afterWork.physicalFootprintBytes) "
          + "afterIdleBytes=\(afterIdle.physicalFootprintBytes) "
          + "idleGrowthBytes=\(idleGrowth)"
      )
      #expect(
        afterIdle.physicalFootprintBytes <= profile.idleSettleAbsoluteCeilingBytes,
        """
        Absolute idle settle footprint \(afterIdle.physicalFootprintBytes) exceeded \
        ceiling \(profile.idleSettleAbsoluteCeilingBytes) (product fail is 400 MiB). \
        afterAuth=\(afterAuth?.physicalFootprintBytes ?? 0) \
        afterWork=\(afterWork.physicalFootprintBytes) \
        afterIdle=\(afterIdle.physicalFootprintBytes) \
        virtual=\(afterIdle.virtualBytes) (not RAM). \
        guestUser=\(String(describing: session.userID)) words=\(profile.estimatedWordEntities) \
        namespaces=recordings/transcriptions/transcriptionWords/transcriptionSegments/recordingAttachments+debugLogs
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
      || ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK"] == "auto"
    let credentialsPresent = appID.map { !$0.isEmpty } ?? false
    // When credentials are present and soak is not explicitly disabled, require live.
    let requireLive =
      useLive
      || (credentialsPresent
        && ProcessInfo.processInfo.environment["INSTANT_SWIFT_DATA_LIVE_AUTH_SOAK"] != "0")

    guard requireLive, let appID, appID.isEmpty == false else {
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
    let cacheURL = try temporaryScribeAuthIdleCacheURL(prefix: "live-main")
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: ScribeProductionShapedSchema.attributes,
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

    // Live path: do not seed production-scale into the real app — prove guest
    // auth works and absolute idle ceiling holds. First live connect/hydrate
    // can cost ~100 MiB structurally (attrs + websocket); that is not thrash.
    // Baseline *after* a short settle, then assert idle growth stays flat.
    try await Task.sleep(for: .milliseconds(250))
    let afterConnectSettle = InstantProcessMemory.sample()
    try await Task.sleep(for: .milliseconds(250))
    let afterIdle = InstantProcessMemory.sample()
    if let afterConnectSettle, let afterIdle {
      let growth =
        afterIdle.physicalFootprintBytes > afterConnectSettle.physicalFootprintBytes
        ? afterIdle.physicalFootprintBytes - afterConnectSettle.physicalFootprintBytes
        : 0
      #expect(
        afterIdle.physicalFootprintBytes <= profile.idleSettleAbsoluteCeilingBytes,
        """
        Live guest idle footprint \(afterIdle.physicalFootprintBytes) exceeded \
        absolute ceiling \(profile.idleSettleAbsoluteCeilingBytes). \
        afterConnectSettle=\(afterConnectSettle.physicalFootprintBytes)
        """
      )
      #expect(
        growth <= profile.idleSettleGrowthBudgetBytes,
        """
        Live guest idle grew \(growth) after connect settle (budget \
        \(profile.idleSettleGrowthBudgetBytes)). Climbing after hydrate is thrash. \
        afterConnectSettle=\(afterConnectSettle.physicalFootprintBytes) \
        afterIdle=\(afterIdle.physicalFootprintBytes)
        """
      )
      let multiGB: UInt64 = 1_500 * 1_024 * 1_024
      #expect(afterIdle.physicalFootprintBytes < multiGB)
    }
  }

  @Test("forced dual Instant debugLogs thrash stays finite and budgeted")
  func forcedDualInstantDebugLogsThrashStaysFiniteAndBudgeted() async throws {
    // Reproduces the thrash *driver*: second Instant store + multi-attr
    // debugLogs batches (InstantDBLogger batch size 8 × ~22 attrs). Without
    // demotion this was unbounded feedback; with demotion a finite forced
    // series must stay under multi‑GB and a hard growth budget.
    let mainCache = try temporaryScribeAuthIdleCacheURL(prefix: "forced-main")
    let debugCache = try temporaryScribeAuthIdleCacheURL(prefix: "forced-debug")
    defer {
      try? FileManager.default.removeItem(at: mainCache.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: debugCache.deletingLastPathComponent())
    }

    let mainRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "scribe-forced-dual-write-main",
        persistenceURL: mainCache,
        initialAttributes: ScribeProductionShapedSchema.attributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    let debugRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "scribe-forced-dual-write-debugLogs",
        persistenceURL: debugCache,
        initialAttributes: ScribeProductionShapedSchema.debugLogsAttributes,
        makeID: { UUID().uuidString.lowercased() },
        guestAuthenticator: .local
      )
    )
    _ = try await mainRuntime.signInAsGuest()
    _ = try await debugRuntime.signInAsGuest()

    // Seed a small production-shaped main graph so dual residency is real.
    try await seedProductionScribeShapedGraph(
      runtime: mainRuntime,
      profile: LinkedInfiniteScribeShapedSoakProfile(
        recordingCount: 8,
        wordsPerRecording: 12,
        transcriptTextCharacters: 256,
        listPageSize: 50,
        footprintGrowthBudgetBytes: 256 * 1_024 * 1_024,
        footprintCeilingBytes: 400 * 1_024 * 1_024,
        idleSettleGrowthBudgetBytes: 64 * 1_024 * 1_024,
        idleSettleAbsoluteCeilingBytes: 400 * 1_024 * 1_024
      )
    )

    let baseline = InstantProcessMemory.sample()
    // 16 batches × 8 multi-attr debugLogs entities ≈ field thrash unit.
    // Multi‑GB feedback was hundreds of unbounded batches. Pack each batch into
    // ≤256-step durable transactions so the thrash fixture survives the
    // automatic-delivery step ceiling without raising production limits.
    for batch in 0..<16 {
      let transactionID = "debug-log-batch-\(batch)"
      let now = InstantTimestamp(milliseconds: 1_700_200_000_000 + Int64(batch))
      var operations: [InstantTripleOperation] = []
      for entity in 0..<8 {
        let id = try await debugRuntime.localID(named: "forced.debugLog.\(batch).\(entity)")
        operations.append(
          contentsOf: ScribeProductionShapedSchema.createDebugLogOperations(
            id: id,
            batchIndex: batch,
            entityIndex: entity,
            updatedAt: now,
            transactionID: transactionID
          )
        )
      }
      let entityGroups = BoundedBenchmarkSeed.entityCreationGroups(from: operations)
      for transaction in BoundedBenchmarkSeed.transactions(
        baseID: transactionID,
        atomicOperationGroups: entityGroups
      ) {
        try await debugRuntime.transact(transaction, createdAt: now)
      }
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
        "Forced dual Instant debugLogs thrash reached multi‑GB \(after.physicalFootprintBytes)"
      )
      #expect(
        growth < 768 * 1_024 * 1_024,
        "Forced dual Instant debugLogs growth \(growth) too large for finite 16×8 batches"
      )
      #expect(
        after.physicalFootprintBytes <= 400 * 1_024 * 1_024
          || growth < 256 * 1_024 * 1_024,
        """
        Finite dual-store thrash still too heavy for product budget: \
        footprint=\(after.physicalFootprintBytes) growth=\(growth). \
        Production fail is absolute idle >400 MiB.
        """
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

private func temporaryScribeAuthIdleCacheURL(prefix: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ScribeAuthIdleSoak-\(prefix)-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func seedProductionScribeShapedGraph(
  runtime: InstantRuntime,
  profile: LinkedInfiniteScribeShapedSoakProfile
) async throws {
  var recordingIDs: [String] = []
  var transcriptionIDs: [String] = []
  var wordIDsByRecording: [[String]] = []
  var segmentIDsByRecording: [[String]] = []
  var attachmentIDsByRecording: [[String]] = []
  // Segments/attachments at production-order density relative to recordings:
  // ~1 segment per recording + a few words-group segments; ~1 attachment / 4 recordings.
  let segmentsPerRecording = max(1, profile.wordsPerRecording / 12)
  let attachmentsPerRecording = 1
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
    var attachmentIDs: [String] = []
    for attachmentIndex in 0..<attachmentsPerRecording {
      attachmentIDs.append(
        try await runtime.localID(named: "scribe.prod.attachment.\(index).\(attachmentIndex)")
      )
    }
    attachmentIDsByRecording.append(attachmentIDs)
  }
  let transactionID =
    "scribe-production-shape-\(profile.recordingCount)-\(profile.wordsPerRecording)-seed"
  let now = InstantTimestamp(milliseconds: 1_700_100_500_000)
  let operations = ScribeProductionShapedSchema.soakOperations(
    profile: profile,
    recordingIDs: recordingIDs,
    transcriptionIDs: transcriptionIDs,
    wordIDsByRecording: wordIDsByRecording,
    segmentIDsByRecording: segmentIDsByRecording,
    attachmentIDsByRecording: attachmentIDsByRecording,
    baseTime: now,
    transactionID: transactionID
  )
  let entityGroups = BoundedBenchmarkSeed.entityCreationGroups(from: operations)
  for transaction in BoundedBenchmarkSeed.transactions(
    baseID: transactionID,
    atomicOperationGroups: entityGroups
  ) {
    try await runtime.transact(transaction, createdAt: now)
  }
}
