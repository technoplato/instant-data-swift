// History
// 2026-10-25  #1133  Created. A hydration that read deferred values without the operation gate re-checks under it
//                    unless the holder named what it writes, and only transact, the server apply's commit and a closed
//                    result's reload did: on build 118 the re-check waited 5,282 ms behind holders that write no store
//                    facts (plans, prunes, claims, the cache's VACUUM).

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// A hydration's re-check waits only for a holder that may be writing what it read (#1006), so a holder that writes no
/// store facts, or only others, says so as it takes the gate (#1133). Each test pauses one such holder with the gate
/// held, right after a hydration read its values without the gate, and expects the hydrated emission while the holder
/// still holds the gate.
@Suite(.serialized, .timeLimit(.minutes(2)))
struct InstantHydrationRecheckHolderTests {
  /// The local cache's VACUUM rewrites pages, never facts.
  @Test
  func aHydrationDoesNotWaitForTheCachesVacuum() async throws {
    let held = InstantPausePoint()
    let hydrated = try await Self.hydratesWhileHeld(
      "vacuum",
      configure: { configuration in
        configuration.storageMaintenanceConditions = { _ in
          InstantStorageMaintenanceConditions(availableDiskBytes: 1 << 40)
        }
        configuration.onLocalCacheVacuumStartingForTesting = { await held.pauseOnce() }
      },
      held: held
    ) { runtime in
      _ = try? await runtime.compactLocalCache(
        policy: InstantLocalCacheCompactionPolicy(minimumFreeFraction: 0, minimumFreeBytes: 0)
      ) { nil }
    }
    #expect(hydrated, "#1133: the hydration's re-check waited for the VACUUM, which writes no store facts")
  }

  /// A prune batch writes only the facts of the entities it releases, which no open query holds.
  @Test
  func aHydrationDoesNotWaitForAPruneBatch() async throws {
    let held = InstantPausePoint()
    let hydrated = try await Self.hydratesWhileHeld(
      "prune",
      configure: { configuration in
        configuration.onLiveQueryResultPruneBatchHoldsOperationGateForTesting = { await held.pauseOnce() }
      },
      held: held
    ) { runtime in
      _ = try? await runtime.pruneLiveQueryResults(
        policy: InstantLiveQueryResultPruningPolicy(),
        now: InstantTimestamp(milliseconds: 1_700_000_000_000)
      )
    }
    #expect(hydrated, "#1133: the hydration's re-check waited for a prune batch, which writes no fact it read")
  }

  /// A caller's named writes hold from the moment the gate is handed to it, before its own code runs: the timeline
  /// reports each acquisition in the same turn as the handoff. A caller that marked its writes after entering read as
  /// writing everything until then (#1133).
  @Test
  func aCallersNamedWritesHoldFromTheMomentItTakesTheGate() async throws {
    let gate = GateBox()
    let seen = GateBox.Seen()
    let serialGate = AsyncSerialGate(
      label: "test",
      timeline: { event in
        guard event.kind == .acquired, let gate = gate.gate else { return }
        seen.record(event.operation, mayWrite: gate.holderMayWrite(any: ["entity"]))
      }
    )
    gate.set(serialGate)
    await serialGate.enter(operation: "writer")
    let reader = Task.detached {
      await serialGate.enter(operation: "queued reader", writes: [])
      await serialGate.leave()
    }
    let deadline = ContinuousClock.now + .seconds(10)
    while await serialGate.waiterCount == 0, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(2))
    }
    await serialGate.leave()
    await reader.value
    await serialGate.enter(operation: "reader", writes: [])
    await serialGate.leave()
    await serialGate.enter(operation: "named writer", writes: ["entity"])
    await serialGate.leave()

    #expect(
      seen.value == ["writer": true, "queued reader": false, "reader": false, "named writer": true],
      "#1133: whether each holder may write `entity` as it took the gate"
    )
  }

  // MARK: - Helpers

  static let idAttribute = InstantAttribute.primaryKey(namespace: "notes")
  static let titleAttribute = InstantAttribute(
    id: "notes/title",
    namespace: "notes",
    name: "title",
    valueType: .string,
    isIndexed: true
  )
  /// Kept on disk until a page hydrates it, as Scribe keeps a transcript line's text and words.
  static let bodyAttribute = InstantAttribute(
    id: "notes/body",
    namespace: "notes",
    name: "body",
    valueType: .json
  )
  static let attributes = [idAttribute, titleAttribute, bodyAttribute]

  /// Observes a page whose body is read without the gate. When that read is done, starts `holder` and waits until it
  /// pauses at `held`, holding the gate; then whether the hydrated emission arrives within 5 s, before `held` is
  /// released.
  static func hydratesWhileHeld(
    _ name: String,
    configure: (inout InstantRuntimeConfiguration) -> Void,
    held: InstantPausePoint,
    holder: @escaping @Sendable (InstantRuntime) async -> Void
  ) async throws -> Bool {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantHydrationRecheckHolderTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cacheURL = directory.appendingPathComponent("state.sqlite")
    try await seed(cacheURL)

    let holding = HolderStart()
    var configuration = InstantRuntimeConfiguration(
      appID: "hydration-recheck-\(name)",
      persistenceURL: cacheURL,
      initialAttributes: attributes,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(attributeIDs: [bodyAttribute.id])
    )
    configure(&configuration)
    configuration.onDeferredValuesReadWithoutOperationGateForTesting = { _ in
      // The first hydration has read its values: the holder takes the gate before the re-check does.
      guard let task = holding.startOnce(holder) else { return }
      _ = task
      try? await held.waitUntilEntered(within: .seconds(10))
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    holding.setRuntime(runtime)

    let stream = await runtime.observe(
      InstantQueryPlan(
        id: "hydration-recheck-\(name)",
        namespace: "notes",
        order: InstantQueryOrder(titleAttribute.name),
        limit: 1,
        selectedFields: [titleAttribute.name, bodyAttribute.name]
      )
    )
    let hydrated = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await emission in stream where emission.values.first?.values[bodyAttribute.name] != nil {
          return true
        }
        return false
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(5))
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
    held.release()
    await holding.task?.value
    return hydrated
  }

  static func seed(_ cacheURL: URL) async throws {
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let timestamp = InstantTimestamp(milliseconds: 1)
    let body = JSONValue.string(String(repeating: "a deferred body ", count: 256))
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: attributes,
        triples: [
          InstantTriple(entityID: "note-a", attributeID: idAttribute.id, value: .string("note-a"), txID: "seed", txTime: timestamp),
          InstantTriple(entityID: "note-a", attributeID: titleAttribute.id, value: .string("A"), txID: "seed", txTime: timestamp),
          InstantTriple(entityID: "note-a", attributeID: bodyAttribute.id, value: .json(body), txID: "seed", txTime: timestamp),
        ]
      )
    )
  }
}

/// Starts the paused holder once, from the first hydration's read.
private final class HolderStart: @unchecked Sendable {
  // SAFETY: `lock` guards `runtime` and `started`.
  private let lock = NSLock()
  private var runtime: InstantRuntime?
  private var started: Task<Void, Never>?

  func setRuntime(_ runtime: InstantRuntime) {
    lock.withLock { self.runtime = runtime }
  }

  var task: Task<Void, Never>? { lock.withLock { started } }

  func startOnce(_ holder: @escaping @Sendable (InstantRuntime) async -> Void) -> Task<Void, Never>? {
    lock.withLock {
      guard started == nil, let runtime else { return nil }
      let task = Task { await holder(runtime) }
      started = task
      return task
    }
  }
}

/// The gate a timeline callback reads, set once it exists, and what the callback saw.
private final class GateBox: @unchecked Sendable {
  // SAFETY: `lock` guards `stored`.
  private let lock = NSLock()
  private var stored: AsyncSerialGate?

  var gate: AsyncSerialGate? { lock.withLock { stored } }

  func set(_ gate: AsyncSerialGate) {
    lock.withLock { stored = gate }
  }

  final class Seen: @unchecked Sendable {
    // SAFETY: `lock` guards `mayWrite`.
    private let lock = NSLock()
    private var mayWrite: [String: Bool] = [:]

    var value: [String: Bool] { lock.withLock { mayWrite } }

    func record(_ operation: String, mayWrite: Bool) {
      lock.withLock { self.mayWrite[operation] = mayWrite }
    }
  }
}
