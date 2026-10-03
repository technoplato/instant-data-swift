import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #431, from Scribe #408 (Recording 039; Scribe 0.1 (80) on instant-data-swift 1.9.1). live-stamp found it and wrote
/// the first repro.
///
/// On 2026-10-02 the iPad stamped Recording 039 as its playback: one write of `recordings/activityKind`,
/// `recordings/activityClientID` and `recordings/updatedAtMs`. The iPhone was capturing the recording and wrote
/// `durationSeconds` and `updatedAtMs` every 5 s. Once the server accepted the iPad's write, the iPad showed the
/// iPhone's newer `durationSeconds`, but never its newer `updatedAtMs`: the iPad's store held its own write, stamped
/// with its clock, while every server fact of the recording's single-value slots carried the recording's creation time.
///
/// Instant updates a single-value (`ea`) triple in place and keeps its `created_at`, which a refresh delivers as the
/// fact's stamp. The store resolved single-value facts last-write-wins by stamp, so when another device wrote a slot
/// between this device's write and the refresh that would restate it, the server's later value lost on stamps, and
/// every later one too. A slot another device cleared the same way kept this device's value. Upstream builds each query
/// result's store from the server's triples alone and overlays only the pending mutations (`Reactor.js` refresh-ok:
/// `createStore`, then `_applyOptimisticUpdates` for the mutations `processed-tx-id` does not cover; `store.js`
/// `addTriple` sets an `ea` slot whatever its `created_at`).
///
/// Every case runs on both server-apply paths, the reduced one and the whole-component rebase.
@Suite
struct InstantLocalStampShadowsServerTests {
  /// The iPhone's heartbeat lands between the iPad's write and the refresh: the refresh carries the iPhone's value.
  @Test
  func anotherDevicesLaterValueWinsOverThisDevicesAcceptedWrite() async throws {
    var observations: [FastDrainObservation] = []
    for reduces in [true, false] {
      var fixture = try await Self.recordingTheOtherDeviceStampedActive(suffix: "overwritten", reduces: reduces)
      let recording = FastDrainSchema.recordingID
      try await Self.acceptThisDevicesPlaybackStamp(&fixture) { server in
        _ = server.acceptForeignWrite(entityID: recording, attributeID: "recordings/durationSeconds", value: .number(11_320.5))
        return server.acceptForeignWrite(entityID: recording, attributeID: "recordings/updatedAtMs", value: Self.heartbeat)
      }
      observations.append(try await FastDrainObservation.observe(fixture.runtime))
    }
    for observation in observations {
      for facts in [observation.hotFacts, observation.persistedFacts] {
        // Control: the slot this device never wrote follows the server.
        expectNoDifference(Self.shown("recordings/durationSeconds", in: facts), "\(InstantValue.number(11_320.5))")
        expectNoDifference(Self.shown("recordings/updatedAtMs", in: facts), "\(Self.heartbeat)")
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), "\(InstantValue.string("playback"))")
      }
    }
    expectNoDifference(observations[0].hotFacts, observations[1].hotFacts)
    expectNoDifference(observations[0].persistedFacts, observations[1].persistedFacts)
  }

  /// The iPhone's Stop clears the activity between the iPad's write and the refresh: the slot goes.
  @Test
  func anotherDevicesClearWinsOverThisDevicesAcceptedWrite() async throws {
    var observations: [FastDrainObservation] = []
    for reduces in [true, false] {
      var fixture = try await Self.recordingTheOtherDeviceStampedActive(suffix: "cleared", reduces: reduces)
      let recording = FastDrainSchema.recordingID
      try await Self.acceptThisDevicesPlaybackStamp(&fixture) { server in
        server.acceptForeignRetraction(entityID: recording, attributeID: "recordings/activityKind")
      }
      observations.append(try await FastDrainObservation.observe(fixture.runtime))
    }
    for observation in observations {
      for facts in [observation.hotFacts, observation.persistedFacts] {
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), nil)
        expectNoDifference(
          Self.shown("recordings/updatedAtMs", in: facts),
          "\(InstantValue.number(1_790_988_543_909))"
        )
      }
      expectNoDifference(observation.outbox, [])
    }
    expectNoDifference(observations[0].hotFacts, observations[1].hotFacts)
  }

  /// The clear arrives while this device has another write of the recording pending: the clear still lands, and the
  /// pending write keeps overlaying its own slot until the server accepts it.
  @Test
  func aClearLandsWhileThisDeviceHasAnotherWriteOfTheEntityPending() async throws {
    var observations: [FastDrainObservation] = []
    for reduces in [true, false] {
      var fixture = try await Self.recordingTheOtherDeviceStampedActive(suffix: "cleared-pending", reduces: reduces)
      let recording = FastDrainSchema.recordingID
      try await Self.acceptThisDevicesPlaybackStamp(&fixture) { server in String(server.lastTransactionNumber) }
      let heartbeatAt = InstantTimestamp(milliseconds: fixture.script.deviceMilliseconds + 5_000)
      let ownHeartbeat = InstantStoreTransaction(
        id: "ipad-heartbeat",
        operations: [
          .insert(
            InstantTriple(
              entityID: recording, attributeID: "recordings/updatedAtMs", value: .number(1_790_988_553_909),
              txID: "ipad-heartbeat", txTime: heartbeatAt
            )
          ),
        ]
      )
      _ = try await fixture.runtime.transact(ownHeartbeat, createdAt: heartbeatAt)
      let stop = fixture.server.acceptForeignRetraction(entityID: recording, attributeID: "recordings/activityKind")
      _ = try await fixture.refresh(queries: fixture.server.queries(touching: [recording]), processedTransactionID: stop)

      let whilePending = try await FastDrainObservation.observe(fixture.runtime)
      expectNoDifference(Self.shown("recordings/activityKind", in: whilePending.hotFacts), nil)
      expectNoDifference(
        Self.shown("recordings/updatedAtMs", in: whilePending.hotFacts),
        "\(InstantValue.number(1_790_988_553_909))"
      )

      let window = try await fixture.claimWindow(maximumMutationCount: 1)
      let head = try #require(window.mutations.first)
      #expect(head.id == ownHeartbeat.id)
      _ = try await fixture.acceptAndRefresh(head, claimToken: window.token)
      observations.append(try await FastDrainObservation.observe(fixture.runtime))
    }
    for observation in observations {
      for facts in [observation.hotFacts, observation.persistedFacts] {
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), nil)
        expectNoDifference(
          Self.shown("recordings/updatedAtMs", in: facts),
          "\(InstantValue.number(1_790_988_553_909))"
        )
      }
      expectNoDifference(observation.outbox, [])
    }
    expectNoDifference(observations[0].hotFacts, observations[1].hotFacts)
  }

  /// A store 1.9.1 left shadowed heals on the first refresh after the upgrade, without a reinstall. The shadow is made
  /// the way 1.9.1 made it, by a path this fix leaves alone: the accepted write is pruned at the watermark by a refresh
  /// that does not restate the recording, so the store keeps this device's values, stamped by its clock, owned by no
  /// result, while the results still hold the values from before the write. Then the app relaunches on the store, and
  /// another device has meanwhile written one slot and cleared the other.
  @Test
  func aStoreLeftShadowedHealsOnTheFirstRefreshAfterRelaunch() async throws {
    var observations: [FastDrainObservation] = []
    for reduces in [true, false] {
      var fixture = try await Self.recordingTheOtherDeviceStampedActive(suffix: "heals", reduces: reduces)
      let recording = FastDrainSchema.recordingID
      try await Self.shadowWithAWritePrunedBeforeItsRefresh(&fixture)
      try await fixture.relaunch()
      _ = fixture.server.acceptForeignWrite(entityID: recording, attributeID: "recordings/updatedAtMs", value: Self.heartbeat)
      let stop = fixture.server.acceptForeignRetraction(entityID: recording, attributeID: "recordings/activityKind")
      _ = try await fixture.refresh(queries: fixture.server.queries(touching: [recording]), processedTransactionID: stop)
      observations.append(try await FastDrainObservation.observe(fixture.runtime))
    }
    for observation in observations {
      for facts in [observation.hotFacts, observation.persistedFacts] {
        expectNoDifference(Self.shown("recordings/updatedAtMs", in: facts), "\(Self.heartbeat)")
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), nil)
      }
    }
    expectNoDifference(observations[0].hotFacts, observations[1].hotFacts)
  }

  /// The same shadowed store, where the first refresh after the relaunch comes from one of the two results that hold
  /// the recording: the timeline, not refreshed yet, still holds the `active` value from before this device's write.
  /// The clear still removes this device's value, which no result holds.
  @Test
  func aShadowHealsWhileAnotherResultStillHoldsTheValueFromBeforeTheWrite() async throws {
    var observations: [FastDrainObservation] = []
    for reduces in [true, false] {
      var fixture = try await Self.recordingTheOtherDeviceStampedActive(suffix: "heals-one-result", reduces: reduces)
      let recording = FastDrainSchema.recordingID
      try #require(fixture.server.queries(touching: [recording]) == [.timeline, .list])
      try await Self.shadowWithAWritePrunedBeforeItsRefresh(&fixture)
      try await fixture.relaunch()
      _ = fixture.server.acceptForeignWrite(entityID: recording, attributeID: "recordings/updatedAtMs", value: Self.heartbeat)
      let stop = fixture.server.acceptForeignRetraction(entityID: recording, attributeID: "recordings/activityKind")
      _ = try await fixture.refresh(queries: [.list], processedTransactionID: stop)
      observations.append(try await FastDrainObservation.observe(fixture.runtime))
    }
    for observation in observations {
      for facts in [observation.hotFacts, observation.persistedFacts] {
        expectNoDifference(Self.shown("recordings/updatedAtMs", in: facts), "\(Self.heartbeat)")
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), nil)
      }
    }
    expectNoDifference(observations[0].hotFacts, observations[1].hotFacts)
  }

  /// A slot no result ever held: the server had no `activityKind` for the recording before this device's playback
  /// stamp, the acceptance was pruned before any refresh restated it, and the other device's Stop cleared it. Then a
  /// query that selects the slot refreshes without it: this device's value goes (main, 2026-10-03: "on a full refresh,
  /// a local fact that isn't pending and that the server doesn't return goes away"). This is also the shape 1.9.1 left
  /// behind once it had stored a cleared result: no result holds the slot, and the store still shows the value.
  @Test
  func aValueNoResultEverHeldGoesWhenAQueryThatSelectsItsSlotRefreshesWithoutIt() async throws {
    var observations: [FastDrainObservation] = []
    for reduces in [true, false] {
      var fixture = try await FastDrainFixture.make(
        suffix: "local-stamp-never-held-\(reduces)",
        serverSegmentCount: 2,
        pendingSegmentCount: 0,
        reducesServerApply: reduces
      )
      try await Self.shadowWithAWritePrunedBeforeItsRefresh(&fixture)
      _ = fixture.server.acceptForeignWrite(
        entityID: FastDrainSchema.recordingID, attributeID: "recordings/updatedAtMs", value: Self.heartbeat
      )
      let stop = fixture.server.acceptForeignRetraction(
        entityID: FastDrainSchema.recordingID, attributeID: "recordings/activityKind"
      )
      try await Self.refreshTheRecording(
        &fixture,
        selecting: ["activityKind", "title", "updatedAtMs"],
        processedTransactionID: stop
      )
      observations.append(try await FastDrainObservation.observe(fixture.runtime))
    }
    for observation in observations {
      for facts in [observation.hotFacts, observation.persistedFacts] {
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), nil)
        expectNoDifference(Self.shown("recordings/updatedAtMs", in: facts), "\(Self.heartbeat)")
      }
    }
    expectNoDifference(observations[0].hotFacts, observations[1].hotFacts)
  }

  /// A query that does not select a slot says nothing about it: the same refresh, without `activityKind` in its
  /// `fields`, leaves the value where it is.
  @Test
  func aQueryThatDoesNotSelectASlotLeavesItsValue() async throws {
    for reduces in [true, false] {
      var fixture = try await FastDrainFixture.make(
        suffix: "local-stamp-not-selected-\(reduces)",
        serverSegmentCount: 2,
        pendingSegmentCount: 0,
        reducesServerApply: reduces
      )
      try await Self.shadowWithAWritePrunedBeforeItsRefresh(&fixture)
      let stop = fixture.server.acceptForeignRetraction(
        entityID: FastDrainSchema.recordingID, attributeID: "recordings/activityKind"
      )
      try await Self.refreshTheRecording(&fixture, selecting: ["title", "updatedAtMs"], processedTransactionID: stop)
      let observation = try await FastDrainObservation.observe(fixture.runtime)
      for facts in [observation.hotFacts, observation.persistedFacts] {
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), "\(InstantValue.string("playback"))")
      }
    }
  }

  /// The newest result's word on a slot wins over a result stored earlier: with no write of this device involved,
  /// the iPhone's Stop clears `active`, and only the list refreshes. The timeline, not refreshed (its query no longer
  /// subscribed, say), still lists `active`, which 1.9.1 kept in the store for it.
  @Test
  func aClearWinsOverAResultStoredBeforeIt() async throws {
    var observations: [FastDrainObservation] = []
    for reduces in [true, false] {
      var fixture = try await Self.recordingTheOtherDeviceStampedActive(suffix: "cleared-stale", reduces: reduces)
      let stop = fixture.server.acceptForeignRetraction(
        entityID: FastDrainSchema.recordingID, attributeID: "recordings/activityKind"
      )
      _ = try await fixture.refresh(queries: [.list], processedTransactionID: stop)
      observations.append(try await FastDrainObservation.observe(fixture.runtime))
    }
    for observation in observations {
      for facts in [observation.hotFacts, observation.persistedFacts] {
        expectNoDifference(Self.shown("recordings/activityKind", in: facts), nil)
      }
    }
    expectNoDifference(observations[0].hotFacts, observations[1].hotFacts)
  }

  /// A write that is still pending keeps overlaying the server's value, as upstream's `_applyOptimisticUpdates` does,
  /// and once the server accepts it after the other device's write, its value is the server's.
  @Test
  func aPendingWriteStillOverlaysTheServersValue() async throws {
    for reduces in [true, false] {
      var fixture = try await FastDrainFixture.make(
        suffix: "local-stamp-pending-\(reduces)",
        serverSegmentCount: 2,
        pendingSegmentCount: 0,
        reducesServerApply: reduces
      )
      let recording = FastDrainSchema.recordingID
      let deviceStamp = InstantTimestamp(milliseconds: fixture.script.deviceMilliseconds)
      let rename = InstantStoreTransaction(
        id: "local-pending-title",
        operations: [
          .insert(
            InstantTriple(
              entityID: recording, attributeID: "recordings/title", value: .string("this device's title"),
              txID: "local-pending-title", txTime: deviceStamp
            )
          ),
        ]
      )
      _ = try await fixture.runtime.transact(rename, createdAt: deviceStamp)
      let foreign = fixture.server.acceptForeignWrite(
        entityID: recording, attributeID: "recordings/title", value: .string("another device's title")
      )
      _ = try await fixture.refresh(queries: fixture.server.queries(touching: [recording]), processedTransactionID: foreign)
      let whilePending = try await FastDrainObservation.observe(fixture.runtime)
      expectNoDifference(Self.shown("recordings/title", in: whilePending.hotFacts), "\(InstantValue.string("this device's title"))")

      let window = try await fixture.claimWindow(maximumMutationCount: 1)
      let head = try #require(window.mutations.first)
      #expect(head.id == rename.id)
      _ = try await fixture.acceptAndRefresh(head, claimToken: window.token)
      let accepted = try await FastDrainObservation.observe(fixture.runtime)
      for facts in [accepted.hotFacts, accepted.persistedFacts] {
        expectNoDifference(Self.shown("recordings/title", in: facts), "\(InstantValue.string("this device's title"))")
      }
      expectNoDifference(accepted.outbox, [])
    }
  }

  private static let heartbeat = InstantValue.number(1_790_988_548_909)

  /// A server base where another device (the iPhone) has stamped the recording `active`, stored in this device's results.
  private static func recordingTheOtherDeviceStampedActive(
    suffix: String,
    reduces: Bool
  ) async throws -> FastDrainFixture {
    var fixture = try await FastDrainFixture.make(
      suffix: "local-stamp-\(suffix)-\(reduces)",
      serverSegmentCount: 2,
      pendingSegmentCount: 0,
      reducesServerApply: reduces
    )
    let recording = FastDrainSchema.recordingID
    let active = fixture.server.acceptForeignWrite(
      entityID: recording, attributeID: "recordings/activityKind", value: .string("active")
    )
    _ = try await fixture.refresh(queries: fixture.server.queries(touching: [recording]), processedTransactionID: active)
    let observation = try await FastDrainObservation.observe(fixture.runtime)
    try #require(shown("recordings/activityKind", in: observation.hotFacts) == "\(InstantValue.string("active"))")
    return fixture
  }

  private static func playbackStamp(at deviceStamp: InstantTimestamp) -> InstantStoreTransaction {
    let recording = FastDrainSchema.recordingID
    return InstantStoreTransaction(
      id: "ipad-playback-stamp",
      operations: [
        .insert(
          InstantTriple(
            entityID: recording, attributeID: "recordings/activityKind", value: .string("playback"),
            txID: "ipad-playback-stamp", txTime: deviceStamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: recording, attributeID: "recordings/updatedAtMs", value: .number(1_790_988_543_909),
            txID: "ipad-playback-stamp", txTime: deviceStamp
          )
        ),
      ]
    )
  }

  /// This device stamps the recording as its playback, and the server's acceptance is pruned at the watermark by a
  /// refresh of the transcription, which does not hold the recording: the store keeps this device's values, which no
  /// result holds.
  private static func shadowWithAWritePrunedBeforeItsRefresh(_ fixture: inout FastDrainFixture) async throws {
    let deviceStamp = InstantTimestamp(milliseconds: fixture.script.deviceMilliseconds)
    _ = try await fixture.runtime.transact(playbackStamp(at: deviceStamp), createdAt: deviceStamp)
    let window = try await fixture.claimWindow(maximumMutationCount: 1)
    let head = try #require(window.mutations.first)
    let accepted = fixture.server.accept(head.transaction.operations)
    _ = try await fixture.runtime.acceptMutationIfPresent(id: head.id, serverTransactionID: accepted, claimToken: window.token)
    _ = try await fixture.refresh(queries: [.transcription], processedTransactionID: accepted)
    let shadowed = try await FastDrainObservation.observe(fixture.runtime)
    expectNoDifference(shadowed.outbox, [], "the accepted write is pruned at the watermark")
    expectNoDifference(shown("recordings/activityKind", in: shadowed.persistedFacts), "\(InstantValue.string("playback"))")
  }

  /// This device (the iPad) stamps the recording as its playback and the server accepts the write; then `meanwhile`
  /// changes the server (another device's write or clear) before the refresh, which carries what the server holds then.
  private static func acceptThisDevicesPlaybackStamp(
    _ fixture: inout FastDrainFixture,
    meanwhile: (inout FastDrainServer) -> String
  ) async throws {
    let recording = FastDrainSchema.recordingID
    let deviceStamp = InstantTimestamp(milliseconds: fixture.script.deviceMilliseconds)
    let playback = playbackStamp(at: deviceStamp)
    _ = try await fixture.runtime.transact(playback, createdAt: deviceStamp)
    let window = try await fixture.claimWindow(maximumMutationCount: 1)
    let head = try #require(window.mutations.first)
    #expect(head.id == playback.id)
    let accepted = fixture.server.accept(head.transaction.operations)
    _ = try await fixture.runtime.acceptMutationIfPresent(id: head.id, serverTransactionID: accepted, claimToken: window.token)
    let processed = meanwhile(&fixture.server)
    _ = try await fixture.refresh(queries: fixture.server.queries(touching: [recording]), processedTransactionID: processed)
    let observation = try await FastDrainObservation.observe(fixture.runtime)
    #expect(observation.outbox.isEmpty, "the accepted write is pruned at the watermark")
  }

  /// A refresh of a query with an InstaQL key that selects `fields` of the recording, holding what the server has of
  /// them, as `refresh-ok` carries it.
  private static func refreshTheRecording(
    _ fixture: inout FastDrainFixture,
    selecting fields: [String],
    processedTransactionID: String
  ) async throws {
    let key = #"{"recordings":{"$":{"fields":["# + fields.map { "\"\($0)\"" }.joined(separator: ",") + "]}}}"
    let selected = Set(["recordings/id"] + fields.map { "recordings/\($0)" })
    let triples = fixture.server.triples(in: .list, transactionID: processedTransactionID).filter {
      $0.entityID == FastDrainSchema.recordingID && selected.contains($0.attributeID)
    }
    _ = try await fixture.runtime.applyServerTransactionMergingAttributesForTesting(
      InstantStoreTransaction(id: processedTransactionID, operations: triples.map(InstantTripleOperation.insert)),
      attributesToMerge: [],
      liveQueryResultReplacements: [InstantLiveQueryResultReplacement(key: key, triples: triples, pageInfo: nil)]
    )
  }

  private static func shown(_ attributeID: String, in facts: [FastDrainObservation.Fact]) -> String? {
    facts.first { $0.entityID == FastDrainSchema.recordingID && $0.attributeID == attributeID }?.value
  }
}
