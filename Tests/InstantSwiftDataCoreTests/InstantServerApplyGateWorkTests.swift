import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #932: the work a server apply does while it holds the operation gate, which every transact, observe, query,
/// connection-status call and acknowledgement waits on. On the iPhone (build 114) the gate was held 4.3-7.4 s every
/// ~30 s with ~2,560 pending writes; the resident-outbox patch alone was 0.8-1.3 s of it.
@Suite(.serialized)
struct InstantServerApplyGateWorkTests {
  /// A hold of 250 ms or more stalls every read and write behind it, so its event goes out one by one with its fields.
  /// At `info`, a host's diagnostics bridge counted those holds per minute and dropped their fields: the phone's holds
  /// of 250-999 ms on build 116 arrived as counts, and its commit times could not be read untethered.
  @Test
  func aHoldOfAQuarterSecondOrMoreIsLoggedAtNoticeOrAbove() {
    expectNoDifference(
      [0, 249, 250, 999, 1_000, 4_000].map { InstantRuntime.serverApplyGateHeldLevel(heldMilliseconds: $0) },
      [.debug, .debug, .notice, .notice, .warning, .warning]
    )
  }

  /// The gate-held event names the apply's path, its attempt, the writes it peeled and replayed, and where its commit
  /// spent its time inside the persistence actor. The phone's events said only "commit 3,914 ms" (0 changed entities)
  /// and the reduction's decline was logged at debug, so a slow apply could not say why it was slow.
  @Test
  func theGateHeldEventNamesThePathAndWhereTheCommitSpentItsTime() async throws {
    let events = ServerApplyGateEvents()
    events.start()
    defer { events.stop() }
    let full = try await GateWorkFixture.make(suffix: "event-full", chainLength: 3)
    _ = try await full.runtime.applyServerTransaction(full.serverWrite(value: "event-full"))
    let reduced = try await GateWorkFixture.make(suffix: "event-reduced", chainLength: 3) { configuration in
      configuration.reducesServerApplyToAffectedOverlays = true
    }
    _ = try await reduced.runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "gate-work-server-event-reduced",
        operations: [
          .insert(
            gateWorkTriple(
              entityID: "gate-work-free-entity",
              value: "server",
              transactionID: "gate-work-server-event-reduced",
              milliseconds: 100
            )
          )
        ]
      )
    )

    let fullEvent = try #require(events.events(processedTransactionID: "gate-work-server-event-full").last)
    expectNoDifference(
      [fullEvent["path"], fullEvent["attempt"], fullEvent["heldFromSeed"], fullEvent["plannedComponentBodyCount"]],
      ["full rebase: reduction off", "1", "false", "3"]
    )
    let reducedEvent = try #require(events.events(processedTransactionID: "gate-work-server-event-reduced").last)
    expectNoDifference(
      [reducedEvent["path"], reducedEvent["attempt"], reducedEvent["plannedComponentBodyCount"]],
      ["reduced", "1", "0"]
    )
    for event in [fullEvent, reducedEvent] {
      let parts = [
        "commitValidateMilliseconds", "commitFactsMilliseconds", "commitOutboxMilliseconds",
        "commitResultsMilliseconds", "commitBookkeepingMilliseconds", "commitSQLiteCommitMilliseconds",
      ].map { event[$0].flatMap(Int.init) }
      #expect(!parts.contains(nil), "\(event)")
      let inside = try #require(event["commitInsideMilliseconds"].flatMap(Int.init))
      let commit = try #require(event["commitMilliseconds"].flatMap(Int.init))
      // Each part is rounded down, so their sum is at most the whole, which is at most the commit phase.
      #expect(parts.compactMap { $0 }.reduce(0, +) <= inside)
      #expect(inside <= commit)
    }
  }

  /// The patch refreshes the in-memory outbox, which holds only the claimed delivery window (a cold start holds none).
  /// It decoded the staged lifecycle of every row the apply rewrote and hopped to the outbox once per row, ~0.4 ms a
  /// row on the phone, though `replaceIfPresent` and `remove(id:)` ignore a row the outbox does not hold.
  @Test
  func theResidentPatchReadsOnlyTheRowsTheResidentOutboxHolds() async throws {
    let fixture = try await GateWorkFixture.make(suffix: "resident-patch", chainLength: 120)
    let resident = [fixture.mutations[3], fixture.mutations[77]]
    for mutation in resident {
      await fixture.runtime.outbox.replace(mutation)
    }
    await fixture.runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await fixture.runtime.applyServerTransaction(fixture.serverWrite(value: "server"))

    let metrics = await fixture.runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedComponentBodyCount, 120)
    expectNoDifference(metrics.residentPatchRowCount, resident.count)
    // The rows the outbox holds carry the lifecycle the apply committed: each one's receipt was re-recorded over the
    // server's value.
    let shells = await fixture.runtime.outbox.all()
    expectNoDifference(shells.map(\.id), resident.map(\.id))
    let durable = try await fixture.runtime.persistence.loadOutboxMutations(
      statuses: [.pending],
      ids: resident.map(\.id),
      expectedOutboxRevision: try await fixture.runtime.persistence.currentOutboxRevision()
    )
    expectNoDifference(
      shells.map(\.optimisticEffectReceiptVersion),
      (durable ?? []).sorted(by: PendingMutation.creationOrder).map(\.optimisticEffectReceiptVersion)
    )
    expectNoDifference(
      shells.map(\.rollbackTransaction),
      (durable ?? []).sorted(by: PendingMutation.creationOrder).map(\.compactedForMemory.rollbackTransaction)
    )
  }

  /// Each body page checked every row of the plan against the outbox before reading its own 50 rows: about
  /// 2R^2/50 row checks a full apply, each reading the outbox columns stored after a row's body (~262,000 at the
  /// phone's 2,560 pending). The page checks its own rows; extending the plan and its commit still check every row in
  /// the transactions that write.
  @Test
  func bodyPagesCheckOnlyTheirOwnRowsAgainstTheOutbox() async throws {
    let fixture = try await GateWorkFixture.make(suffix: "page-validation", chainLength: 300)
    await fixture.runtime.persistence.resetServerApplyMetricsForTesting()

    _ = try await fixture.runtime.applyServerTransaction(fixture.serverWrite(value: "server"))

    let metrics = await fixture.runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.plannedComponentBodyCount, 300)
    #expect(metrics.reverseBodyPageCount >= 6)
    #expect(metrics.forwardBodyPageCount >= 6)
    // One check when the catch-up extends the plan under the gate, one in the commit.
    #expect(metrics.wholePlanValidationCount <= 2, "\(metrics.wholePlanValidationCount) whole-plan checks")
    let store = try await fixture.runtime.persistence.loadState()
    expectNoDifference(
      store.snapshot.store.triples.filter { $0.entityID == fixture.entityID }.map(\.value),
      [.string("local-299")]
    )
  }

  /// Scribe writes a line in progress as a `liveLines` row and its final deletes that row (ADR 0069). With a backlog,
  /// the server's live-lines result still shows rows whose deletion is pending on the device. On the phone (build 114)
  /// a server apply every ~30 s peeled and replayed ~2,560 pending writes (~888 changed entities). A frame that only
  /// restates a row a pending write deletes cannot change what the device shows.
  @Test
  func liveLineFramesDuringABacklogDoNotRebaseThePendingWrites() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "live-lines-backlog",
      serverSegmentCount: 20,
      pendingSegmentCount: 20,
      scribeLinks: true,
      defersSegmentText: true,
      liveLines: true
    )
    let (measurement, declines) = try await FastDrainDeclineCounter.counting {
      try await fixture.drain(maximumFrames: 40)
    }
    // The decline counter hears every runtime in the process, so the fixture's own measurement decides.
    print("live-line frames during a backlog: \(measurement); declined reductions: \(declines)")
    expectNoDifference(measurement.rebases, 0)
    expectNoDifference(measurement.plannedBodies, 0)
  }

  /// Every refresh restates whole query results, and the commit read each restated result's ownership rows and encoded
  /// every value to diff them, under the gate: 87-140 ms a frame for 7,287 facts on a Mac mini, and the phone's 1-4 s
  /// commits with nothing pending. The apply works that out before it takes the gate; the commit applies the result.
  @Test
  func restatedResultsAreWorkedOutBeforeTheCommit() async throws {
    let fixture = try await GateWorkFixture.make(suffix: "restated-results", chainLength: 1)
    let key = #"{"items":{}}"#
    let listed = (0..<300).map { index in
      gateWorkTriple(entityID: "listed-\(index)", value: "v\(index)", transactionID: "listed", milliseconds: 50)
    }
    func restate(_ triples: [InstantTriple], frame: Int) async throws {
      _ = try await fixture.runtime.applyServerTransactionMergingAttributesForTesting(
        InstantStoreTransaction(id: "restated-\(frame)", operations: triples.map(InstantTripleOperation.insert)),
        attributesToMerge: [],
        liveQueryResultReplacements: [InstantLiveQueryResultReplacement(key: key, triples: triples, pageInfo: nil)],
        receivedAt: InstantTimestamp(milliseconds: 1_000 + Int64(frame) * 10_000)
      )
    }
    try await restate(listed, frame: 0)
    await fixture.runtime.persistence.resetServerApplyMetricsForTesting()

    // Restated unchanged, then with one fact gone and one changed.
    try await restate(listed, frame: 1)
    var changed = Array(listed.dropLast())
    changed[0] = gateWorkTriple(entityID: "listed-0", value: "changed", transactionID: "listed", milliseconds: 60)
    try await restate(changed, frame: 2)

    let metrics = await fixture.runtime.persistence.serverApplyMetricsForTesting()
    expectNoDifference(metrics.commitResultOwnershipRowReadCount, 0)
    expectNoDifference(metrics.commitResultValueEncodeCount, 0)
    let ownership = try await fixture.runtime.persistence.liveQueryOwnershipForTesting(queryKey: key)
    expectNoDifference(ownership.count, 299)
    #expect(ownership.contains(["listed-0", "items/value", #"{"string":{"_0":"changed"}}"#]))
    #expect(!ownership.contains { $0.first == "listed-299" })
  }

  /// While a recording writes, every optimistic attempt went stale (a local write landed between the seed and the
  /// plan), and after five the apply ran again holding the operation gate from seed to commit: every read and write
  /// waited for the whole apply (25 `server-apply.exclusive-fallback` events on the phone, 2026-10-22..23). A retry
  /// holds the gate only from its seed to its plan; writes that land after the plan are the appended tail the
  /// catch-up replays.
  @Test
  func localWritesBetweenSeedAndPlanDoNotForceAnExclusiveApply() async throws {
    let writes = GateWorkWrites()
    let fixture = try await GateWorkFixture.make(suffix: "seed-plan", chainLength: 20) { configuration in
      configuration.onServerApplySeedLoadedForTesting = { operationGateHeld in
        await writes.writeAfterSeed(operationGateHeld: operationGateHeld)
      }
    }
    await writes.attach(fixture.runtime)
    let fallbacks = ServerApplyGateEvents()
    fallbacks.start()
    defer { fallbacks.stop() }

    let applied = try await fixture.runtime.applyServerTransaction(fixture.serverWrite(value: "server"))
    await writes.finish()

    expectNoDifference(applied.syncState.processedTransactionID, "gate-work-server-server")
    expectNoDifference(fallbacks.fallbackCount, 0)
    let written = await writes.writtenIDs()
    #expect(!written.isEmpty)
    let state = try await fixture.runtime.persistence.loadState()
    let shown = Set(state.snapshot.store.triples.map(\.entityID))
    expectNoDifference(written.filter { !shown.contains("side-\($0)") }, [])
    expectNoDifference(
      state.snapshot.store.triples.first { $0.entityID == fixture.entityID }?.value,
      .string("local-19")
    )
  }
}

/// A local write after each server-apply seed: awaited when the gate is free (the attempt then goes stale), started
/// without waiting when the apply holds the gate (it lands once the gate is released).
private actor GateWorkWrites {
  private var runtime: InstantRuntime?
  private var written: [String] = []
  private var started: [Task<Void, Never>] = []

  func attach(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }

  func writeAfterSeed(operationGateHeld: Bool) async {
    guard let runtime, written.count + started.count < 12 else { return }
    let id = "w\(written.count + started.count)"
    let write = InstantStoreTransaction(
      id: "side-write-\(id)",
      operations: [.insert(gateWorkTriple(entityID: "side-\(id)", value: id, transactionID: "side-write-\(id)", milliseconds: 1_000))]
    )
    if operationGateHeld {
      started.append(Task { [weak self] in
        _ = try? await runtime.transact(write, createdAt: InstantTimestamp(milliseconds: 1_000))
        await self?.recordWritten(id)
      })
    } else {
      _ = try? await runtime.transact(write, createdAt: InstantTimestamp(milliseconds: 1_000))
      written.append(id)
    }
  }

  private func recordWritten(_ id: String) {
    written.append(id)
  }

  func finish() async {
    for task in started { await task.value }
    started = []
  }

  func writtenIDs() -> [String] { written }
}

// MARK: - Fixture

private let gateWorkAttributes = [
  InstantAttribute(id: "items/value", namespace: "items", name: "value", valueType: .string, isRequired: false)
]

/// One entity written by a chain of pending writes, as a recording is by its lines: a server write to it puts every
/// pending write in the apply's component. The whole-component rebase is selected, as the phone's frames took it.
private struct GateWorkFixture {
  var runtime: InstantRuntime
  var entityID: String
  var mutations: [PendingMutation]

  static func make(
    suffix: String,
    chainLength: Int,
    configure: (inout InstantRuntimeConfiguration) -> Void = { _ in }
  ) async throws -> Self {
    let entityID = "gate-work-entity"
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-gate-work-\(suffix)-\(UUID().uuidString).sqlite"
    )
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL, declaredAttributes: gateWorkAttributes)
    try await persistence.bootstrap()
    let mutations = (0..<chainLength).map { index in
      gateWorkMutation(
        id: "gate-work-\(String(format: "%04d", index))",
        position: Int64(index),
        entityID: entityID,
        before: index == 0 ? "base" : "local-\(index - 1)",
        after: "local-\(index)"
      )
    }
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: gateWorkAttributes,
        triples: [gateWorkTriple(entityID: entityID, value: "local-\(chainLength - 1)", transactionID: "seed", milliseconds: Int64(chainLength))]
      )
    )
    let seeded = try await persistence.loadCompactState()
    let saved = try await persistence.saveOutbox(
      mutations,
      replacing: [],
      metadataEntries: [],
      expectedStoreRevision: seeded.storeRevision,
      expectedOutboxRevision: seeded.outboxRevision
    )
    #expect(saved)
    var configuration = InstantRuntimeConfiguration(
      appID: "gate-work-\(suffix)",
      persistenceURL: cacheURL,
      initialAttributes: gateWorkAttributes
    )
    configuration.reducesServerApplyToAffectedOverlays = false
    configure(&configuration)
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    return Self(runtime: runtime, entityID: entityID, mutations: mutations)
  }

  func serverWrite(value: String) -> InstantStoreTransaction {
    let id = "gate-work-server-\(value)"
    return InstantStoreTransaction(
      id: id,
      operations: [.insert(gateWorkTriple(entityID: entityID, value: value, transactionID: id, milliseconds: 100))]
    )
  }
}

private func gateWorkMutation(
  id: String,
  position: Int64,
  entityID: String,
  before: String,
  after: String
) -> PendingMutation {
  var mutation = PendingMutation(
    id: id,
    createdAt: InstantTimestamp(milliseconds: position),
    transaction: InstantStoreTransaction(
      id: id,
      operations: [.insert(gateWorkTriple(entityID: entityID, value: after, transactionID: id, milliseconds: position + 1))]
    ),
    status: .pending
  )
  mutation.rollbackTransaction = InstantStoreTransaction(
    id: "rollback-\(id)",
    operations: [
      .insert(gateWorkTriple(entityID: entityID, value: before, transactionID: "rollback-\(id)", milliseconds: position + 1))
    ]
  )
  mutation.optimisticOverlayState = .applied
  mutation.optimisticEffectReceiptVersion = PendingMutation.currentOptimisticEffectReceiptVersion
  return mutation
}

private func gateWorkTriple(
  entityID: String,
  value: String,
  transactionID: String,
  milliseconds: Int64
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: "items/value",
    value: .string(value),
    txID: transactionID,
    txTime: InstantTimestamp(milliseconds: milliseconds)
  )
}
