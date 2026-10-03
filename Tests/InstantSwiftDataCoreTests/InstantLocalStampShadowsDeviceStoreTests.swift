import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

/// #431 against a store a device actually holds: Michael's iPad, pulled 2026-10-03 at 00:52 (instant-data-swift 1.9.1).
/// Set `INSTANT_431_DEVICE_STORE` to the `.sqlite` (with its `-wal` and `-shm`); skipped without it. Each check runs on
/// the phone replay gate's scratch copy, with every credential row deleted, so the file it names is never written, and
/// on a runtime shaped like Scribe's (the store's attributes, Scribe's deferred attributes, no transport).
///
/// Recording 039's `activityKind`, `activityClientID`, and `updatedAtMs` are the iPad's own accepted write: local
/// transaction `e46216ef-…`, stamped with the iPad's clock (1790999718356), while every server fact of the recording's
/// single-value slots carries the recording's creation time (1790977121916). Four stored results hold the iPad's values
/// (their last refresh, at 23:55:58, restated them), and one older result still holds the iPhone's `active` stamp.
/// Each check delivers the refresh the iPad would get after the iPhone's Stop, with `updatedAtMs` at the iPhone's later
/// value (stamped with the creation time, as Instant keeps it) and the two activity slots cleared: once for every
/// stored result that holds the recording, and once for the four alone, the older result left as it is.
@Suite
struct InstantLocalStampShadowsDeviceStoreTests {
  static let recordingID = "a96823cb-66a7-4a55-8098-78554ee670b4"
  static let createdAt = InstantTimestamp(milliseconds: 1_790_977_121_916)

  /// The store as pulled: the Stop's refresh replaces values the results restated.
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["INSTANT_431_DEVICE_STORE"] != nil),
    arguments: [true, false]
  )
  func theDevicesStoreTakesTheServersValueAndItsClear(refreshingTheOlderResultToo: Bool) async throws {
    let (runtime, store) = try await Self.scratchRuntime()
    defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
    let before = try await Self.recordingFacts(runtime)
    expectNoDifference(before.persisted["recordings/activityKind"], "\(InstantValue.string("playback"))")

    let laterUpdatedAt = InstantValue.number(1_791_000_000_000)
    try await Self.deliverTheStop(
      runtime,
      to: try Self.resultKeys(store, refreshingTheOlderResultToo: refreshingTheOlderResultToo),
      updatedAt: laterUpdatedAt,
      processedTransactionID: "2855999999"
    )

    let after = try await Self.recordingFacts(runtime)
    for facts in [after.hot, after.persisted] {
      expectNoDifference(facts["recordings/updatedAtMs"], "\(laterUpdatedAt)")
      expectNoDifference(facts["recordings/activityKind"], nil)
      expectNoDifference(facts["recordings/activityClientID"], nil)
      expectNoDifference(facts["recordings/title"], before.persisted["recordings/title"])
    }
  }

  /// The shape #431 leaves stuck, on this store: the iPad stamps the recording again after a relaunch (a new client
  /// id and a later `updatedAtMs`, stamped by its clock), the server accepts it, and the iPhone's Stop lands before the
  /// refresh, so no result ever restates the iPad's new values.
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["INSTANT_431_DEVICE_STORE"] != nil),
    arguments: [true, false]
  )
  func theDevicesNextStampFollowsTheStopThatLandsBeforeItsRefresh(refreshingTheOlderResultToo: Bool) async throws {
    let (runtime, store) = try await Self.scratchRuntime()
    defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
    let deviceStamp = InstantTimestamp(milliseconds: 1_791_000_100_000)
    let restamp = InstantStoreTransaction(
      id: "ipad-next-playback-stamp",
      operations: [
        .insert(
          InstantTriple(
            entityID: Self.recordingID, attributeID: "recordings/activityClientID",
            value: .string("0f3c2b4e-5a6d-4e7f-8091-a2b3c4d5e6f7"), txID: "ipad-next-playback-stamp", txTime: deviceStamp
          )
        ),
        .insert(
          InstantTriple(
            entityID: Self.recordingID, attributeID: "recordings/updatedAtMs", value: .number(1_791_000_100_000),
            txID: "ipad-next-playback-stamp", txTime: deviceStamp
          )
        ),
      ]
    )
    _ = try await runtime.transact(restamp, createdAt: deviceStamp)
    let claimToken = "device-store-claim"
    let window = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: await runtime.automaticDeliveryClaimantIDForTesting(),
        claimToken: claimToken,
        now: deviceStamp,
        maximumMutationCount: 1
      )
    )
    let head = try #require(window.mutations.first)
    #expect(head.id == restamp.id)
    _ = try await runtime.acceptMutationIfPresent(id: head.id, serverTransactionID: "2856000000", claimToken: claimToken)

    let laterUpdatedAt = InstantValue.number(1_791_000_200_000)
    try await Self.deliverTheStop(
      runtime,
      to: try Self.resultKeys(store, refreshingTheOlderResultToo: refreshingTheOlderResultToo),
      updatedAt: laterUpdatedAt,
      processedTransactionID: "2856000001"
    )

    let outbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(outbox.map(\.id), [])
    let after = try await Self.recordingFacts(runtime)
    for facts in [after.hot, after.persisted] {
      expectNoDifference(facts["recordings/updatedAtMs"], "\(laterUpdatedAt)")
      expectNoDifference(facts["recordings/activityKind"], nil)
      expectNoDifference(facts["recordings/activityClientID"], nil)
    }
    // `INSTANT_431_KEEP_STORE_DIRECTORY`: keep the store as the code under test left it, for the check below.
    if !refreshingTheOlderResultToo,
      let directory = ProcessInfo.processInfo.environment["INSTANT_431_KEEP_STORE_DIRECTORY"]
    {
      try Self.copyStore(store, to: URL(fileURLWithPath: directory))
    }
  }

  /// A store 1.9.1 left stuck heals without a reinstall. `INSTANT_431_STUCK_STORE` names the store the check above
  /// kept when it ran on 1.9.1: its Stop's refresh stored the four results without the activity slots and the store
  /// kept the iPad's new stamp, so no result holds the iPad's values any more. The iPhone's next heartbeat refreshes
  /// the same four results, the activity slots still clear, and the store takes the server's values.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_431_STUCK_STORE"] != nil))
  func aStoreTheOldVersionLeftStuckHealsOnTheNextRefresh() async throws {
    let source = try PhoneReplayGateTests.storeFile(
      at: try #require(ProcessInfo.processInfo.environment["INSTANT_431_STUCK_STORE"])
    )
    let store = try PhoneReplayGateTests.scratchCopy(of: source, in: FileManager.default.temporaryDirectory)
    defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
    let runtime = try await PhoneReplayGateTests.runtime(
      store,
      appID: source.deletingPathExtension().lastPathComponent,
      deferred: InstantDeferredValueResidencyPolicy(attributeIDs: PhoneReplayGateTests.scribeDeferredAttributeIDs)
    )
    let before = try await Self.recordingFacts(runtime)
    expectNoDifference(before.persisted["recordings/updatedAtMs"], "\(InstantValue.number(1_791_000_100_000))")
    expectNoDifference(
      before.persisted["recordings/activityClientID"],
      "\(InstantValue.string("0f3c2b4e-5a6d-4e7f-8091-a2b3c4d5e6f7"))"
    )

    // The four results the Stop's refresh stored, holding the iPhone's `updatedAtMs` from it.
    let keys = try Self.selectStrings(
      store,
      "SELECT DISTINCT query_key FROM instant_live_query_triples WHERE entity_id = '\(Self.recordingID)'"
        + #" AND attribute_id = 'recordings/updatedAtMs' AND value_json = '{"number":{"_0":1791000200000}}'"#
        + " ORDER BY query_key"
    )
    try #require(!keys.isEmpty)
    let heartbeat = InstantValue.number(1_791_000_300_000)
    try await Self.deliverTheStop(runtime, to: keys, updatedAt: heartbeat, processedTransactionID: "2856000002")

    let after = try await Self.recordingFacts(runtime)
    for facts in [after.hot, after.persisted] {
      expectNoDifference(facts["recordings/updatedAtMs"], "\(heartbeat)")
      expectNoDifference(facts["recordings/activityKind"], nil)
      expectNoDifference(facts["recordings/activityClientID"], nil)
    }
  }

  /// Copies the store's file, `-wal`, and `-shm` into `directory`, replacing what is there.
  private static func copyStore(_ store: URL, to directory: URL) throws {
    try? FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: store.path + suffix) {
      try FileManager.default.copyItem(
        at: URL(fileURLWithPath: store.path + suffix),
        to: directory.appendingPathComponent(store.lastPathComponent + suffix)
      )
    }
  }

  private static func scratchRuntime() async throws -> (runtime: InstantRuntime, store: URL) {
    let source = try PhoneReplayGateTests.storeFile(
      at: try #require(ProcessInfo.processInfo.environment["INSTANT_431_DEVICE_STORE"])
    )
    let store = try PhoneReplayGateTests.scratchCopy(of: source, in: FileManager.default.temporaryDirectory)
    let runtime = try await PhoneReplayGateTests.runtime(
      store,
      appID: source.deletingPathExtension().lastPathComponent,
      deferred: InstantDeferredValueResidencyPolicy(attributeIDs: PhoneReplayGateTests.scribeDeferredAttributeIDs)
    )
    return (runtime, store)
  }

  /// The stored results that hold the recording, or only those that hold the iPad's `playback` stamp.
  private static func resultKeys(_ store: URL, refreshingTheOlderResultToo: Bool) throws -> [String] {
    let holders = refreshingTheOlderResultToo
      ? ""
      : #" AND attribute_id = 'recordings/activityKind' AND value_json = '{"string":{"_0":"playback"}}'"#
    let keys = try selectStrings(
      store,
      "SELECT DISTINCT query_key FROM instant_live_query_triples WHERE entity_id = '\(recordingID)'\(holders)"
        + " ORDER BY query_key"
    )
    try #require(!keys.isEmpty)
    return keys
  }

  /// The refresh after the iPhone's Stop for each of `keys`: its stored result, with the recording as the most recently
  /// refreshed of those results holds it (the server's one state of it), `updatedAtMs` at `updatedAt`, and no
  /// `activityKind` or `activityClientID`.
  private static func deliverTheStop(
    _ runtime: InstantRuntime,
    to keys: [String],
    updatedAt: InstantValue,
    processedTransactionID: String
  ) async throws {
    var stored: [InstantPersistedLiveQueryResult] = []
    for key in keys {
      stored.append(try #require(try await runtime.persistence.liveQueryResult(key: key)))
    }
    let newest = try #require(stored.max { $0.updatedAt.milliseconds < $1.updatedAt.milliseconds })
    let recording = newest.triples.filter {
      $0.entityID == recordingID
        && !["recordings/activityKind", "recordings/activityClientID", "recordings/updatedAtMs"].contains($0.attributeID)
    } + [
      InstantTriple(
        entityID: recordingID, attributeID: "recordings/updatedAtMs", value: updatedAt,
        txID: processedTransactionID, txTime: createdAt
      )
    ]
    var replacements: [InstantLiveQueryResultReplacement] = []
    for result in stored {
      let triples = result.triples.filter { $0.entityID != recordingID } + recording
      replacements.append(InstantLiveQueryResultReplacement(key: result.key, triples: triples, pageInfo: result.pageInfo))
    }
    let inserts = recording.map(InstantTripleOperation.insert)
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      InstantStoreTransaction(id: processedTransactionID, operations: inserts),
      attributesToMerge: [],
      liveQueryResultReplacements: replacements
    )
  }

  private static func recordingFacts(
    _ runtime: InstantRuntime
  ) async throws -> (hot: [String: String], persisted: [String: String]) {
    func singleValues(_ triples: [InstantTriple]) -> [String: String] {
      Dictionary(
        triples.filter { $0.entityID == recordingID && $0.attributeID != "recordings/attachments" }
          .map { ($0.attributeID, "\($0.value)") },
        uniquingKeysWith: { first, _ in first }
      )
    }
    let hot = await runtime.store.snapshot().triples
    let persisted = try await runtime.persistence.loadState().snapshot.store.triples
    return (singleValues(hot), singleValues(persisted))
  }

  /// The first column of every row, read straight from the SQLite file (the runtime holds its own connection).
  private static func selectStrings(_ store: URL, _ sql: String) throws -> [String] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(store.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      sqlite3_close(database)
      throw CocoaError(.fileReadUnknown)
    }
    defer { sqlite3_close(database) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw CocoaError(.fileReadCorruptFile)
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      if let text = sqlite3_column_text(statement, 0) { values.append(String(cString: text)) }
    }
    return values
  }
}
