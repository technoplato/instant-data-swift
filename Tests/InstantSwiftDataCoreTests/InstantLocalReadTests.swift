import CustomDump
import Foundation
import Testing
import os

@testable import InstantSwiftDataCore

/// A read through the local reader answers from this device's whole store, at once (#1006).
///
/// Opening a long recording waited on its transcript while the recording's other rows showed: the transcript's lines
/// were on disk but out of memory after a relaunch, and the local reads that could have shown them waited for the
/// operation gate, behind server applies that held it 4 to 7 seconds at a time, and for the persistence actor, behind
/// those applies' SQLite commits.
///
/// Upstream reads never wait: `Reactor.js` answers a subscription from its stored result and the in-memory store
/// synchronously. SQLiteData reads through a `DatabasePool`, whose readers run beside the writer in WAL mode, so a
/// `@Fetch` never waits on a write.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantLocalReadTests {
  /// After a relaunch, a one-shot local read filtered by a lookup attribute finds the lines this device keeps on disk
  /// but not in memory, with their deferred text, and leaves them out of memory.
  @Test
  func aRelaunchedStoreReadsTheLinesItKeepsOnDisk() async throws {
    let url = try Self.temporaryCacheURL()
    // As a relaunch finds the store: 300 lines of one recording that no stored result owns (lines this device wrote,
    // which the server acknowledged), the newest two owned by a stored result (a list's preview), and a line of another
    // recording.
    let lines = (0..<300).map { Self.line($0, recordingID: "recording-1") }
    let other = Self.line(0, recordingID: "recording-2", id: "other-0")
    try await Self.seed(
      url,
      lines: lines + [other],
      ownedBy: ["preview": lines.suffix(2)]
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: Self.configuration(url, lookup: true))

    let memory = try await Self.firstEmission(of: runtime, Self.recordingLines("recording-1"))
    expectNoDifference(memory.values.map(\.id), ["line-298", "line-299"], "memory holds the preview's lines only")

    let read = try await runtime.queryLocally(Self.recordingLines("recording-1"))
    expectNoDifference(read.values.map(\.id), (0..<300).map { "line-\($0)" }, "#1006: every line this device keeps")
    expectNoDifference(Self.texts(read).prefix(3), ["Line 0", "Line 1", "Line 2"], "deferred text from disk")
    expectNoDifference(Self.texts(read).suffix(2), ["Line 298", "Line 299"])

    let after = try await Self.firstEmission(of: runtime, Self.recordingLines("recording-1"))
    expectNoDifference(after.values.map(\.id), ["line-298", "line-299"], "the read left them on disk")
  }

  /// Order and limit apply across memory and disk together.
  @Test
  func aLocalReadOrdersAndLimitsAcrossMemoryAndDisk() async throws {
    let url = try Self.temporaryCacheURL()
    let lines = (0..<20).map { Self.line($0, recordingID: "recording-1") }
    try await Self.seed(url, lines: lines, ownedBy: ["preview": lines.suffix(2)])
    let runtime = try await InstantRuntime.bootstrap(configuration: Self.configuration(url, lookup: true))

    var newest = Self.recordingLines("recording-1")
    newest.order = InstantQueryOrder("index", .descending)
    newest.limit = 3
    let read = try await runtime.queryLocally(newest)
    expectNoDifference(read.values.map(\.id), ["line-19", "line-18", "line-17"])

    var oldest = Self.recordingLines("recording-1")
    oldest.limit = 2
    let first = try await runtime.queryLocally(oldest)
    expectNoDifference(first.values.map(\.id), ["line-0", "line-1"])
  }

  /// A one-shot local read answers while another caller holds the operation gate: it reads the in-memory store, which
  /// needs no gate.
  @Test
  func aLocalReadAnswersWhileAnotherCallerHoldsTheOperationGate() async throws {
    let url = try Self.temporaryCacheURL()
    try await Self.seed(url, lines: (0..<5).map { Self.line($0, recordingID: "recording-1") })
    let holder = GateHolder()
    var configuration = Self.configuration(url, lookup: false, defersText: false)
    configuration.onAuthSessionObservationHoldsOperationGateForTesting = { await holder.hold() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let holding = Task { _ = try await runtime.observeAuthSession() }
    await holder.waitUntilHeld()
    let read = Answer { try await runtime.queryLocally(Self.recordingLines("recording-1")) }
    let answered = await read.value(within: .seconds(1))
    await holder.release()
    _ = try await holding.value
    await read.finish()
    expectNoDifference(answered?.values.count, 5, "#1006: the local read answered while the gate was held")
  }

  /// While a server apply holds the operation gate before its commit, a local read and a local observation hydrate
  /// their deferred values at once: the apply has written nothing yet.
  @Test
  func deferredValuesHydrateWhileAServerApplyHoldsTheGateBeforeItsCommit() async throws {
    let url = try Self.temporaryCacheURL()
    try await Self.seed(url, lines: (0..<5).map { Self.line($0, recordingID: "recording-1") })
    let holder = GateHolder()
    let localWrite = LocalWriteDuringApply()
    var configuration = Self.configuration(url, lookup: false)
    // The whole-component rebase replays a local write landed during the apply's preparation under the gate.
    configuration.reducesServerApplyToAffectedOverlays = false
    configuration.onServerApplyPreparedBeforeCommitForTesting = { _ in await localWrite.land() }
    configuration.onServerApplyCatchUpReplayedForTesting = { _, _ in await holder.hold() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await localWrite.attach(runtime)

    let apply = Task {
      try await runtime.applyServerTransaction(
        InstantStoreTransaction(
          id: "server-other-recording",
          operations: Self.line(0, recordingID: "recording-2", id: "server-line").map(InstantTripleOperation.insert)
        )
      )
    }
    await holder.waitUntilHeld()

    // Both read inside the same hold.
    let read = Answer { try await runtime.queryLocally(Self.recordingLines("recording-1")) }
    let observed = Answer { try await Self.firstEmission(of: runtime, Self.recordingLines("recording-1")) }
    let readAnswer = await read.value(within: .seconds(1))
    let observedAnswer = await observed.value(within: .seconds(1))
    await holder.release()
    _ = try await apply.value
    await read.finish()
    await observed.finish()
    expectNoDifference(readAnswer.map(Self.texts), (0..<5).map { "Line \($0)" }, "#1006: the one-shot read")
    expectNoDifference(observedAnswer.map(Self.texts), (0..<5).map { "Line \($0)" }, "#1006: the observation")
  }

  /// A local read's deferred values do not queue behind a long call on the persistence actor, such as a server apply's
  /// SQLite commit: they are read on their own connection.
  @Test
  func deferredValuesDoNotWaitForTheBusyPersistenceActor() async throws {
    let url = try Self.temporaryCacheURL()
    try await Self.seed(url, lines: (0..<5).map { Self.line($0, recordingID: "recording-1") })
    let runtime = try await InstantRuntime.bootstrap(configuration: Self.configuration(url, lookup: false))
    _ = try await runtime.queryLocally(Self.recordingLines("recording-1"))

    let started = GateHolder()
    let busy = Task {
      await runtime.persistence.occupyForTesting(.seconds(3)) { Task { await started.hold() } }
    }
    await started.waitUntilHeld()
    let start = ContinuousClock.now
    let read = Answer { try await runtime.queryLocally(Self.recordingLines("recording-1")) }
    let answered = await read.value(within: .seconds(1))
    print("#1006 local read beside a busy persistence actor: \(start.duration(to: .now)), answered: \(answered != nil)")
    await busy.value
    await started.release()
    await read.finish()
    expectNoDifference(answered.map(Self.texts), (0..<5).map { "Line \($0)" }, "#1006: read beside the busy actor")
  }
}

// MARK: - Fixtures

extension InstantLocalReadTests {
  static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: "lines"),
    InstantAttribute(id: "lines/recordingID", namespace: "lines", name: "recordingID", valueType: .string, isIndexed: true),
    InstantAttribute(id: "lines/index", namespace: "lines", name: "index", valueType: .number, isIndexed: true),
    // A line's text is a deferred value, as a transcript line's text and words are: no query filters or orders by it.
    InstantAttribute(id: "lines/text", namespace: "lines", name: "text", valueType: .string, isRequired: false),
  ]

  static func recordingLines(_ recordingID: String) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "lines.\(recordingID)",
      namespace: "lines",
      filters: [.equals(field: "recordingID", value: .string(recordingID))],
      order: InstantQueryOrder("index", .ascending)
    )
  }

  static func configuration(_ url: URL, lookup: Bool, defersText: Bool = true) -> InstantRuntimeConfiguration {
    var configuration = InstantRuntimeConfiguration(
      appID: "local-read-\(url.deletingLastPathComponent().lastPathComponent)",
      persistenceURL: url,
      initialAttributes: attributes,
      deferredValueResidency: defersText ? InstantDeferredValueResidencyPolicy(attributeIDs: ["lines/text"]) : .none
    )
    if lookup {
      configuration.localLookup = InstantLocalLookupPolicy(attributeIDs: ["lines/recordingID"])
    }
    return configuration
  }

  static func line(_ index: Int, recordingID: String, id: String? = nil) -> [InstantTriple] {
    let entityID = id ?? "line-\(index)"
    let txTime = InstantTimestamp(milliseconds: Int64(1_000 + index))
    return [
      InstantTriple(entityID: entityID, attributeID: "lines/id", value: .string(entityID), txID: "seed", txTime: txTime),
      InstantTriple(
        entityID: entityID, attributeID: "lines/recordingID", value: .string(recordingID), txID: "seed", txTime: txTime
      ),
      InstantTriple(
        entityID: entityID, attributeID: "lines/index", value: .number(Double(index)), txID: "seed", txTime: txTime
      ),
      InstantTriple(
        entityID: entityID, attributeID: "lines/text", value: .string("Line \(index)"), txID: "seed", txTime: txTime
      ),
    ]
  }

  /// Writes `lines` to a store as a relaunch finds it: each result in `ownedBy` owns its lines; no result owns the rest.
  /// With no stored result at all, a launch loads every row, as a store from before live-query ownership does.
  static func seed(
    _ url: URL,
    lines: [[InstantTriple]],
    ownedBy results: [String: ArraySlice<[InstantTriple]>] = [:]
  ) async throws {
    let persistence = try SQLitePersistenceStore(
      fileURL: url,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(attributeIDs: ["lines/text"]),
      declaredAttributes: attributes
    )
    try await persistence.bootstrap()
    let state = try await persistence.loadCompactState()
    // A result as old as 1970 would be past the pruning policy's age limit, and a launch would collect it.
    let now = InstantTimestamp(milliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
    let stored = results.sorted { $0.key < $1.key }.map { key, owned in
      InstantPersistedLiveQueryResult(
        replacement: InstantLiveQueryResultReplacement(key: key, triples: owned.flatMap { $0 }, pageInfo: nil),
        updatedAt: now
      )
    }
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(store: InstantStoreSnapshot(attributes: attributes, triples: lines.flatMap { $0 })),
      queryResults: stored,
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.local-read",
      metadataValue: "seeded",
      metadataUpdatedAt: now,
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision,
      expectedAttributeRevision: state.attributeRevision
    )
    expectNoDifference(didSave, true)
  }

  static func texts(_ emission: InstantQueryEmission) -> [String] {
    emission.values.map { snapshot in
      guard case let .string(text)? = snapshot.values["text"]?.first else { return "<no text>" }
      return text
    }
  }

  /// The first emission of a local observation of `plan`.
  static func firstEmission(of runtime: InstantRuntime, _ plan: InstantQueryPlan) async throws -> InstantQueryEmission {
    let lease = await runtime.observeLocallyLease(plan)
    defer { Task { await lease.cancel() } }
    for await emission in lease.stream {
      return emission
    }
    throw CancellationError()
  }

  static func temporaryCacheURL() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-local-read-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("instant.sqlite")
  }
}

/// A read started at once whose answer a test checks within a limit, without cancelling it.
final class Answer<Value: Sendable>: Sendable {
  private let answer = OSAllocatedUnfairLock<Value?>(uncheckedState: nil)
  private let task: Task<Void, Error>

  init(_ body: @escaping @Sendable () async throws -> Value) {
    let answer = self.answer
    task = Task {
      let value = try await body()
      answer.withLockUnchecked { $0 = value }
    }
  }

  /// The answer if it arrived within `limit`, else nil.
  func value(within limit: Duration) async -> Value? {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
      if let value = answer.withLockUnchecked({ $0 }) { return value }
      try? await Task.sleep(for: .milliseconds(5))
    }
    return answer.withLockUnchecked { $0 }
  }

  /// Waits for the read to end, once whatever held it is released.
  func finish() async {
    _ = try? await task.value
  }
}

/// Holds a test's place inside a critical section until released.
actor GateHolder {
  private var isHeld = false
  private var isReleased = false
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func hold() async {
    isHeld = true
    for waiter in heldWaiters { waiter.resume() }
    heldWaiters.removeAll()
    guard !isReleased else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func waitUntilHeld() async {
    guard !isHeld else { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  func release() {
    isReleased = true
    for waiter in releaseWaiters { waiter.resume() }
    releaseWaiters.removeAll()
  }
}

/// Lands one local write while a server apply prepares, so the apply catches it up under the operation gate.
actor LocalWriteDuringApply {
  private weak var runtime: InstantRuntime?
  private var didLand = false

  func attach(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }

  func land() async {
    guard !didLand, let runtime else { return }
    didLand = true
    _ = try? await runtime.transact(
      InstantStoreTransaction(
        id: "local-during-apply",
        operations: InstantLocalReadTests.line(7, recordingID: "recording-3", id: "local-line")
          .map(InstantTripleOperation.insert)
      ),
      createdAt: InstantTimestamp(milliseconds: 9_000)
    )
  }
}
