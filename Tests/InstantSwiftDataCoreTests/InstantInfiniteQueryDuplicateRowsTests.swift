import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Scribe #388: a windowed live infinite query must never list one entity twice in a snapshot.
///
/// The coordinator publishes a snapshot after every chunk update (`pushSnapshot`), and each chunk's
/// emission reaches it through that chunk's own task. When a row moves from one chunk into another
/// in a single server refresh, the coordinator can publish the destination chunk's update while the
/// source chunk still holds the row. A chunk whose subscription is being replaced (frozen by
/// `loadNextPage`) keeps its old rows until the replacement answers, so a row that leaves it then is
/// listed twice for longer.
///
/// Scribe's recording list trapped on such snapshots on 2026-10-01: the Mac's build 77 and the
/// iPhone's build 76 (`IdentifiedArray(uniqueElements:)` on the page). In the Mac's log the newest
/// recording, recording live on the iPhone, moved above the kickstart cursor: one refresh answered
/// the first forward chunk without it and the leading watcher with it, and the watcher's emission
/// was published first.
///
/// Upstream `normalizeChunks` (infiniteQuery.ts, e7101761) concatenates chunks the same way. On the
/// web a repeated row costs a React key warning; in Swift a consumer keyed by id traps.
///
/// The same logs showed a second defect: at every kickstart the window showed no rows for about 0.6 s,
/// because the starter's rows leave with the pre-bootstrap chunk and the leading watcher answered
/// before the first forward chunk.
@Suite(.serialized)
struct InstantInfiniteQueryDuplicateRowsTests {
  /// Deterministic: `loadNextPage` freezes the first chunk, and while its old subscription retires,
  /// the window's first row moves above the window into the leading watcher.
  @Test
  func aRowThatLeavesAChunkBeingReplacedIsNeverListedTwice() async throws {
    let window = try await DuplicateRowsWindow(
      values: (1...12).map { $0 * 10 },
      order: .descending,
      pageSize: 3,
      maximumPageCount: 4
    )
    let opened = try await window.settled("open the list")
    expectNoDifference(opened.values.map(window.value(of:)), [120, 110, 100])

    await window.retirement.hold()
    window.subscription.loadNextPage()
    try await window.retirement.waitUntilHolding("the first chunk's old subscription retiring")

    let movedID = try #require(await window.server.rowID(withValue: 120))
    let movedValue = try #require(await window.server.moveToTop(rowID: movedID))
    try await window.waitForSnapshot("the leading watcher showing the moved row") { snapshot in
      snapshot.values.contains { window.value(of: $0) == movedValue }
    }
    await window.retirement.release()
    _ = try await window.settled("finish the page load")

    let repeats = await window.recorder.repeats
    expectNoDifference(repeats, [], "snapshots that listed a row twice")
    await window.finish()
  }

  /// The race: the first forward chunk's first row moves above the window's cursor in a refresh that
  /// answers both the first forward chunk and the leading watcher. Every snapshot, not only the
  /// settled ones, must list each row once.
  @Test
  func aRowThatMovesBetweenChunksInOneRefreshIsNeverListedTwice() async throws {
    let window = try await DuplicateRowsWindow(
      values: (1...30).map { $0 * 10 },
      order: .descending,
      pageSize: 3,
      maximumPageCount: 6
    )
    _ = try await window.settled("open the list")
    // The kickstart cursor sits at 300: the first forward chunk holds rows at or below it, and the
    // leading watcher rows above it.
    for move in 1...12 {
      let below = await window.server.orderedValues().filter { $0 <= 300 }
      let value = try #require(below.first)
      let id = try #require(await window.server.rowID(withValue: value))
      await window.server.moveToTop(rowID: id)
      _ = try await window.settled("move \(move): \(value) above the cursor")
    }

    let repeats = await window.recorder.repeats
    expectNoDifference(repeats, [], "snapshots that listed a row twice")
    await window.finish()
  }

  /// A relaunch shows the stored rows at once. When the server's starter answer kickstarts the live chunks and the
  /// leading watcher answers before the first forward chunk, the window keeps those rows until the forward chunk
  /// answers instead of showing none (the Mac's #299 placement logs: 12 rows, then 0 for 0.6 s, then 12).
  @Test
  func theWindowKeepsItsRowsWhileTheKickstartWaitsForItsFirstForwardChunk() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantInfiniteQueryDuplicateRowsTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let persistenceURL = directory.appendingPathComponent("state.sqlite")
    let values = (1...12).map { $0 * 10 }
    // The device holds the rows from another screen's query, but no chunk result of the list: the relaunch's starter
    // shows the stored rows, and the kickstart's chunks have nothing stored to answer from.
    try await DuplicateRowsWindow.storeRows(values: values, persistenceURL: persistenceURL)

    let relaunched = try await DuplicateRowsWindow(
      values: values,
      order: .descending,
      pageSize: 3,
      maximumPageCount: 4,
      persistenceURL: persistenceURL,
      holdsForwardAnswers: true
    )
    // The rows' first run closed its connection, which the store remembers, so the relaunch connects explicitly.
    _ = try await relaunched.runtime.connect()
    try await relaunched.waitUntil("the leading watcher answered while the first forward chunk waits") {
      let residency = await relaunched.subscription.residencySnapshotForTesting()
      return await relaunched.server.heldForwardAnswerCount == 1 && residency.awaitingResultSubscriptionCount == 1
    }
    await relaunched.server.releaseForwardAnswers()
    let settled = try await relaunched.settled("the first forward chunk answered")
    expectNoDifference(settled.values.map(relaunched.value(of:)), [120, 110, 100])

    let emptied = await relaunched.recorder.emptiedAfterRows
    expectNoDifference(emptied, [], "snapshots that showed no rows after showing some")
    let repeats = await relaunched.recorder.repeats
    expectNoDifference(repeats, [], "snapshots that listed a row twice")
    await relaunched.finish()
  }
}

/// One runtime and one windowed infinite query against the #300 model server, recording every
/// snapshot.
private final class DuplicateRowsWindow: Sendable {
  let server: InfiniteListModelServer
  let runtime: InstantRuntime
  let subscription: InstantInfiniteQuerySubscription
  let recorder = DuplicateRowsRecorder()
  let retirement = RetirementHold()
  private let recording: Task<Void, Never>

  init(
    values: [Int],
    order: InfiniteListOrder,
    pageSize: Int,
    maximumPageCount: Int,
    persistenceURL: URL? = nil,
    holdsForwardAnswers: Bool = false
  ) async throws {
    let server = InfiniteListModelServer(values: values, order: order)
    if holdsForwardAnswers {
      await server.holdForwardAnswers()
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantInfiniteQueryDuplicateRowsTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-duplicate-rows",
      persistenceURL: persistenceURL ?? directory.appendingPathComponent("state.sqlite"),
      initialAttributes: duplicateRowsAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: server.transport
    )
    configuration.autoConnectLiveTransport = true
    let retirement = retirement
    configuration.onLiveInfiniteQueryRetirementCleanupStartedForTesting = { _ in
      await retirement.passThrough()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      InstantQueryPlan(
        id: "items.infinite.duplicate-rows",
        namespace: "items",
        order: InstantQueryOrder("value", order == .ascending ? .ascending : .descending),
        limit: pageSize
      ),
      retentionPolicy: .window(maximumPageCount: maximumPageCount)
    )
    let recorder = recorder
    self.server = server
    self.runtime = runtime
    self.subscription = subscription
    self.recording = Task {
      for await snapshot in subscription.snapshots {
        await recorder.record(snapshot)
      }
    }
  }

  /// Stores the rows through a plain live query of the whole list, then closes that runtime.
  static func storeRows(values: [Int], persistenceURL: URL) async throws {
    let server = InfiniteListModelServer(values: values, order: .descending)
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-duplicate-rows",
      persistenceURL: persistenceURL,
      initialAttributes: duplicateRowsAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: server.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observeQueryLease(
      InstantQueryPlan(
        id: "items.all",
        namespace: "items",
        order: InstantQueryOrder("value", .descending)
      )
    )
    let stored = try await instantLiveWithTimeout(
      operation: "store the list's rows through a plain live query",
      timeoutMilliseconds: 5_000
    ) {
      for await emission in observation.stream where emission.values.count == values.count {
        return true
      }
      return false
    }
    #expect(stored, "The plain query stored every row.")
    await observation.cancel()
    _ = try? await runtime.closeConnection()
  }

  func value(of snapshot: InstantEntitySnapshot) -> Int {
    guard case let .one(.number(value)) = snapshot.values["value"] else { return Int.min }
    return Int(value)
  }

  /// Waits at most 5 seconds for a snapshot that satisfies `condition`.
  func waitForSnapshot(
    _ label: String,
    _ condition: @escaping @Sendable (InstantInfiniteQuerySnapshot) -> Bool
  ) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      if let latest = await recorder.latest, condition(latest) { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out after 5 seconds waiting for \(label).")
  }

  /// Waits at most 5 seconds for `condition`.
  func waitUntil(_ label: String, _ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      if await condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out after 5 seconds waiting until \(label).")
  }

  /// Waits at most 5 seconds until nothing is in flight: no navigation, no subscription awaiting or
  /// retiring, no unread server reply, and every frame applied (the #300 harness's quiet point).
  func settled(_ operation: String) async throws -> InstantInfiniteQuerySnapshot {
    let deadline = ContinuousClock.now + .seconds(5)
    var previousMarker: [Int]?
    var quietPolls = 0
    while ContinuousClock.now < deadline {
      let commands = subscription.commandResidencySnapshotForTesting()
      let residency = await subscription.residencySnapshotForTesting()
      let isDrained = await server.isDrained()
      let applierIsWaiting = await runtime.liveReceiverIsWaitingForAFrameForTesting()
      let marker = [await server.receivedMessageCount, await recorder.count]
      let isQuiet = commands.runnerTaskCount == 0
        && commands.pendingNavigationCount == 0
        && residency.awaitingResultSubscriptionCount == 0
        && residency.retiringSubscriptionCount == 0
        && residency.pendingSubscriptionCount == 0
        && isDrained
        && applierIsWaiting
        && marker == previousMarker
      quietPolls = isQuiet ? quietPolls + 1 : 0
      if quietPolls >= 2, let latest = await recorder.latest {
        return latest
      }
      previousMarker = marker
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Waiting to \(operation): the query did not settle within 5 s.")
    throw DuplicateRowsWindowDidNotSettle()
  }

  func finish() async {
    await retirement.release()
    await subscription.unsubscribeAndWait()
    recording.cancel()
    _ = try? await runtime.closeConnection()
  }
}

private struct DuplicateRowsWindowDidNotSettle: Error {}

/// Every snapshot the query published, and each one that listed a row twice.
private actor DuplicateRowsRecorder {
  private(set) var latest: InstantInfiniteQuerySnapshot?
  private(set) var count = 0
  private(set) var repeats: [String] = []
  private(set) var emptiedAfterRows: [String] = []
  private var hasShownRows = false

  func record(_ snapshot: InstantInfiniteQuerySnapshot) {
    latest = snapshot
    count += 1
    if snapshot.values.isEmpty, hasShownRows {
      emptiedAfterRows.append("snapshot \(count) (sequence \(snapshot.sequence)) shows no rows")
    }
    hasShownRows = hasShownRows || !snapshot.values.isEmpty
    let ids = snapshot.values.map(\.id)
    var seen = Set<String>()
    let repeated = ids.filter { !seen.insert($0).inserted }
    guard !repeated.isEmpty else { return }
    repeats.append("snapshot \(count) (sequence \(snapshot.sequence)) lists \(repeated) twice: \(ids)")
  }
}

/// Holds a retiring chunk subscription's cleanup while armed, so the chunk keeps its old rows.
private actor RetirementHold {
  private var isArmed = false
  private var held: [CheckedContinuation<Void, Never>] = []

  func hold() { isArmed = true }

  func release() {
    isArmed = false
    let continuations = held
    held = []
    continuations.forEach { $0.resume() }
  }

  func passThrough() async {
    guard isArmed else { return }
    await withCheckedContinuation { held.append($0) }
  }

  /// Waits at most 5 seconds for a held cleanup.
  func waitUntilHolding(_ label: String) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while ContinuousClock.now < deadline {
      if !held.isEmpty { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out after 5 seconds waiting for \(label).")
  }
}

private let duplicateRowsAttributes: [InstantAttribute] = [
  .primaryKey(namespace: "items"),
  InstantAttribute(
    id: "items/value",
    namespace: "items",
    name: "value",
    valueType: .number,
    isIndexed: true
  ),
]
