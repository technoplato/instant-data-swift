// History:
// - 2026-10-28: a prune of a copy of a device's store, hold by hold (#1319): a phone's prune held the operation gate
//   1.0-3.5 s a batch, and one batch across 37 minutes of suspension.

import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import SQLite3
import Testing

/// The live-query prune on a copy of a device's store, measured hold by hold (#1319).
///
/// It runs only when `INSTANT_PHONE_PRUNE_STORE` is set, so ordinary suite runs skip it.
///
/// - `INSTANT_PHONE_PRUNE_STORE`: the store, a `<appID>.sqlite` file or the directory holding one, with its `-wal` and
///   `-shm`. Read only: the test prunes a scratch copy with every credential row deleted.
/// - `INSTANT_PHONE_PRUNE_OPEN`: which stored results stay open while it prunes: `none` (the default, every stored
///   result closed, the most a launch can unload) or `newest:N`.
/// - `INSTANT_PHONE_PRUNE_SCRATCH`: the directory for the scratch copy, the temporary directory by default.
///
/// It prints `PRUNE` lines: the store's results, each hold of the operation gate a prune step made with the WAL frames,
/// pages and full syncs inside it, and the total. It fails when a hold reaches 250 ms, the longest a caller may wait
/// behind one step of the prune.
@Suite(.serialized)
struct PhonePruneHoldTests {
  /// The longest a caller may wait behind one prune step (#1319).
  static let holdBoundMilliseconds = 250.0

  @Test(.enabled(if: ProcessInfo.processInfo.environment["INSTANT_PHONE_PRUNE_STORE"] != nil))
  func aPruneOfTheDevicesStoreLetsOtherCallersThroughBetweenSteps() async throws {
    let environment = ProcessInfo.processInfo.environment
    let store = try PhoneReplayGateTests.storeFile(at: try #require(environment["INSTANT_PHONE_PRUNE_STORE"]))
    let scratchDirectory = environment["INSTANT_PHONE_PRUNE_SCRATCH"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.temporaryDirectory
    StorageIOCounters.install(asDefault: false)
    let url = try PhoneReplayGateTests.scratchCopy(of: store, in: scratchDirectory)
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    StorageIOCounters.watch(directory: url.deletingLastPathComponent())
    defer { StorageIOCounters.watch(directory: nil) }

    let composition = try Self.composition(url)
    print("PRUNE store: \(composition)")
    let holds = PruneHoldRecorder()
    let deferred = InstantDeferredValueResidencyPolicy(attributeIDs: PhoneReplayGateTests.scribeDeferredAttributeIDs)
    let (runtime, policy) = try await SQLitePersistenceStore.$connectionVFSForTesting.withValue(
      StorageIOCounters.vfsName
    ) {
      try await Self.runtime(
        url,
        appID: store.deletingPathExtension().lastPathComponent,
        deferred: deferred,
        holds: holds
      )
    }
    let stored = try Self.storedKeysNewestFirst(url)
    let open = try Self.openKeys(stored, spec: environment["INSTANT_PHONE_PRUNE_OPEN"] ?? "none")
    // A key no stored result has, so the prune unloads every stored result not in `open` (none open means all close).
    let leases = await runtime.beginLiveQueryRegistrationsForTesting(open.union(["phone-prune-open-marker"]))
    defer { for lease in leases { runtime.endLiveQueryRegistrationForTesting(lease) } }
    print("PRUNE open: \(open.count) of \(stored.count) stored results stay open")

    holds.start()
    let started = ContinuousClock.now
    let pruned = try await runtime.pruneLiveQueryResults(
      policy: policy,
      now: InstantTimestamp(milliseconds: Int64((Date().timeIntervalSince1970 * 1_000).rounded()))
    )
    let wall = started.duration(to: .now)
    let steps = holds.finish()
    for (index, step) in steps.enumerated() {
      print(
        "PRUNE hold \(index + 1): \(step.operation) \(String(format: "%.1f", step.milliseconds)) ms, "
          + "WAL frames \(step.io.walFrames), pages read \(step.io.databasePagesRead), "
          + "pages written \(step.io.databasePagesWritten), full syncs \(step.io.fullSyncs)"
      )
    }
    let longest = steps.map(\.milliseconds).max() ?? 0
    print(
      "PRUNE total: \(steps.count) holds in \(wall), longest \(String(format: "%.1f", longest)) ms; "
        + "removed \(pruned.removedQueryKeys.count) results (\(pruned.unloadedQueryKeys.count) unloaded), "
        + "\(pruned.removedOrphanedTripleCount) facts; after: \(try Self.composition(url))"
    )
    #expect(!steps.isEmpty, "the prune took the operation gate")
    for (index, step) in steps.enumerated() {
      // A hold whose commit ran SQLite's WAL checkpoint (database pages written, full syncs) pays for every writer
      // since the last one; which writer crosses 4,000 frames is chance (#1118). That is #1320, not the prune's work.
      let ranACheckpoint = step.io.databasePagesWritten > 0 && step.io.fullSyncs > 0
      if ranACheckpoint, step.milliseconds >= Self.holdBoundMilliseconds {
        withKnownIssue("#1320: SQLite's WAL checkpoint ran inside this batch's commit") {
          Issue.record("hold \(index + 1) held the operation gate \(step.milliseconds) ms, with a checkpoint")
        }
        continue
      }
      #expect(
        step.milliseconds < Self.holdBoundMilliseconds,
        "hold \(index + 1) (\(step.operation)) held the operation gate \(step.milliseconds) ms"
      )
    }
  }

  static func runtime(
    _ url: URL,
    appID: String,
    deferred: InstantDeferredValueResidencyPolicy,
    holds: PruneHoldRecorder
  ) async throws -> (InstantRuntime, InstantLiveQueryResultPruningPolicy) {
    let loader = try SQLitePersistenceStore(fileURL: url, deferredValueResidency: deferred)
    try await loader.bootstrap()
    let attributes = try await loader.loadCompactState().snapshot.store.attributes
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: url,
      initialAttributes: attributes,
      deferredValueResidency: deferred
    )
    configuration.autoConnectLiveTransport = false
    configuration.operationGateTimeline = holds.record
    configuration.onLiveQueryResultPruneBatchFinishedForTesting = { _ in holds.markStep() }
    return (try await InstantRuntime.bootstrap(configuration: configuration), configuration.liveQueryResultPruningPolicy)
  }

  /// The stored results' keys, newest first, as the device left them.
  static func storedKeysNewestFirst(_ url: URL) throws -> [String] {
    try strings(
      url,
      """
      SELECT query_key FROM instant_live_query_results
      WHERE \(SQLitePersistenceStore.notReleasedLiveQueryResultSQL) ORDER BY updated_at_ms DESC, query_key
      """
    )
  }

  static func openKeys(_ stored: [String], spec: String) throws -> Set<String> {
    if spec == "none" { return [] }
    if spec.hasPrefix("newest:"), let count = Int(spec.dropFirst("newest:".count)) {
      return Set(stored.prefix(count))
    }
    throw PhoneReplayInputError(description: "INSTANT_PHONE_PRUNE_OPEN is none or newest:N, not \(spec)")
  }

  /// How many results the store holds, stored and unloaded, with their facts and bytes: a stored result's are its
  /// ownership rows' values since #1426, an unloaded one's its JSON.
  static func composition(_ url: URL) throws -> String {
    let stored = try strings(
      url,
      "SELECT count(*) || ' stored (' || ifnull(sum(triple_count), 0) || ' facts, ' || (SELECT ifnull(sum(length(CAST(value_json AS BLOB))), 0) FROM instant_live_query_triples) || ' bytes)' FROM instant_live_query_results"
    )
    let unloaded = try strings(
      url,
      "SELECT count(*) || ' unloaded (' || ifnull(sum(triple_count), 0) || ' facts, ' || ifnull(sum(length(CAST(json AS BLOB))), 0) || ' bytes)' FROM instant_unloaded_live_query_results"
    )
    let facts = try strings(url, "SELECT count(*) || ' facts in the store' FROM instant_triples")
    return (stored + unloaded + facts).joined(separator: ", ")
  }

  static func strings(_ url: URL, _ sql: String) throws -> [String] {
    var database: OpaquePointer?
    guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
      throw PhoneReplayInputError(description: "Cannot open \(url.lastPathComponent) to read it")
    }
    defer { sqlite3_close(database) }
    sqlite3_busy_timeout(database, 10_000)
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw PhoneReplayInputError(description: String(cString: sqlite3_errmsg(database)))
    }
    defer { sqlite3_finalize(statement) }
    var values: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      values.append(sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "")
    }
    return values
  }
}

/// The operation gate's holds by the prune's own steps, each with the storage work inside it (#1319).
final class PruneHoldRecorder: @unchecked Sendable {
  struct Step {
    var operation: String
    var milliseconds: Double
    var io: StorageIOSnapshot
  }

  /// The prune's operations on the operation gate.
  static let pruneOperations: Set<String> = [
    "pruneLiveQueryResults(policy:now:)",
    "collectUnloadedLiveQueryResults(policy:now:)",
  ]

  // SAFETY: `lock` guards every stored property below it.
  private let lock = NSLock()
  private var recording = false
  private var acquired: [UInt64: (operation: String, at: UInt64, io: StorageIOSnapshot)] = [:]
  private var steps: [Step] = []

  var record: @Sendable (AsyncSerialGate.TimelineEvent) -> Void {
    { [weak self] event in
      guard let self, Self.pruneOperations.contains(event.operation) else { return }
      switch event.kind {
      case .acquired:
        let io = StorageIOCounters.snapshot()
        self.lock.withLock {
          guard self.recording else { return }
          self.acquired[event.ticket] = (event.operation, event.uptimeNanoseconds, io)
        }
      case .released:
        let io = StorageIOCounters.snapshot()
        self.lock.withLock {
          guard let start = self.acquired.removeValue(forKey: event.ticket) else { return }
          self.steps.append(
            Step(
              operation: start.operation,
              milliseconds: Double(event.uptimeNanoseconds - start.at) / 1_000_000,
              io: io.subtracting(start.io)
            )
          )
        }
      case .requested, .cancelled:
        break
      }
    }
  }

  func start() { lock.withLock { recording = true } }

  /// A prune batch finished; its hold's release follows.
  func markStep() {}

  func finish() -> [Step] {
    lock.withLock {
      recording = false
      return steps
    }
  }
}
